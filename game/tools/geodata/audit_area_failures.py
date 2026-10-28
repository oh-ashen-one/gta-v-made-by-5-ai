#!/usr/bin/env python3
"""Audit emitted OSM area-factory failures before exact-country filtering.

No canonical mutations, geometry repair or assertion that the native area
assembler emits every invalid source object. Private PBF paths are not emitted.
"""
import argparse
import hashlib
from collections import Counter,deque
import json
import math
import os
from pathlib import Path
import resource
import shutil
import subprocess
import sys
import time

import osmium
from shapely.geometry import LineString,Point,box,shape
from enrich_source_tags import canonical_bytes,read_json,sha,sha_file,string_tags

SCHEMA='singapore_emitted_area_failure_audit_v1'
MAX_FAILURES=32
MAX_RING_RECORDS=32
RING_SAMPLE_HEAD=8
RING_SAMPLE_TAIL=8
MAX_REPORT_BYTES=8*1024*1024
RELEVANT_TAGS=('name','name:en','name:zh','ISO3166-1','admin_level','type','building',
    'building:part','natural','water','waterway','landuse','area','place','boundary')

class AreaAuditError(ValueError):pass

class BudgetStop(AreaAuditError):pass

def selected_area(tags):
    # Exact predicate/order from pinned extract_singapore.py, before spatial filtering.
    country=tags.get('ISO3166-1')=='SG' or (tags.get('admin_level')=='2' and tags.get('name:en',tags.get('name'))=='Singapore')
    building='building' in tags or 'building:part' in tags
    water=tags.get('natural')=='water' or 'water' in tags
    return country,building,water

def envelope_geometry(bounds):
    a,b,c,d=bounds
    if a==c and b==d:return Point(a,b)
    if a==c or b==d:return LineString([(a,b),(c,d)])
    return box(a,b,c,d)

def classify_bounds(valid_bounds,*,invalid_nodes=0,inaccessible_rings=0,valid_nodes=0,country):
    """Only prove outside when the complete valid coordinate envelope is disjoint."""
    if invalid_nodes or inaccessible_rings or valid_nodes<=0 or valid_bounds is None:
        return {'classification':'UNKNOWN','reason':'Missing/invalid/inaccessible raw coordinates prevent outside-country proof'}
    if len(valid_bounds)!=4 or not all(math.isfinite(v) for v in valid_bounds):
        return {'classification':'UNKNOWN','reason':'Nonfinite raw coordinate envelope'}
    try:disjoint=envelope_geometry(valid_bounds).disjoint(country)
    except Exception:return {'classification':'UNKNOWN','reason':'Exact-country envelope comparison could not be evaluated'}
    if disjoint:return {'classification':'outside_country','reason':'All raw ring nodes have valid coordinates and their complete envelope is disjoint from the exact country multipolygon'}
    return {'classification':'potentially_missing','reason':'Complete valid-node envelope touches/intersects the exact country; invalid geometry is not repaired or treated as present'}

def _position(node):
    try:
        if not node.location.valid():return None
        lon=float(node.location.lon if hasattr(node.location,'lon') else node.lon)
        lat=float(node.location.lat if hasattr(node.location,'lat') else node.lat)
        if not all(math.isfinite(v) for v in (lon,lat)) or not -180<=lon<=180 or not -90<=lat<=90:return None
        return [lon,lat]
    except Exception:return None

def inspect_raw_rings(area):
    summary={'outer_rings':0,'inner_rings':0,'node_references':0,'valid_nodes':0,'invalid_nodes':0,
        'inaccessible_rings':0,'valid_node_bounds_wgs84':None,'ring_records':[],'ring_records_omitted':0,
        'all_ring_coordinates_inspected':True,'samples_are_not_complete_source_geometry':True}
    def ring_record(ring,role,outer_index,inner_index=None):
        summary[role+'_rings']+=1;head=[];tail=deque(maxlen=RING_SAMPLE_TAIL)
        count=0;valid=0;invalid=0;first_ref=None;last_ref=None;first_pos=None;last_pos=None
        node_hash=hashlib.sha256()
        try:
            for node in ring:
                count+=1;ref=int(node.ref);position=_position(node)
                if first_ref is None:first_ref=ref;first_pos=position
                last_ref=ref;last_pos=position
                item={'node_id':ref,'location_valid':position is not None,'wgs84_lon_lat':position}
                if len(head)<RING_SAMPLE_HEAD:head.append(item)
                tail.append(item);node_hash.update(canonical_bytes(item))
                if position is None:invalid+=1;continue
                valid+=1
                bounds=summary['valid_node_bounds_wgs84']
                if bounds is None:summary['valid_node_bounds_wgs84']=[position[0],position[1],position[0],position[1]]
                else:
                    bounds[0]=min(bounds[0],position[0]);bounds[1]=min(bounds[1],position[1])
                    bounds[2]=max(bounds[2],position[0]);bounds[3]=max(bounds[3],position[1])
        except Exception:
            summary['inaccessible_rings']+=1;summary['all_ring_coordinates_inspected']=False
        summary['node_references']+=count;summary['valid_nodes']+=valid;summary['invalid_nodes']+=invalid
        record={'role':role,'outer_index':outer_index,'inner_index':inner_index,'node_count':count,
            'valid_nodes':valid,'invalid_nodes':invalid,'closed_by_node_identity':count>1 and first_ref==last_ref,
            'closed_by_valid_coordinates':count>1 and first_pos is not None and first_pos==last_pos,
            'ordered_node_position_sha256':node_hash.hexdigest(),'head_samples':head,'tail_samples':list(tail),
            'samples_overlap_for_short_rings':count<RING_SAMPLE_HEAD+RING_SAMPLE_TAIL}
        if len(summary['ring_records'])<MAX_RING_RECORDS:summary['ring_records'].append(record)
        else:summary['ring_records_omitted']+=1
    try:
        for oi,outer in enumerate(area.outer_rings()):
            ring_record(outer,'outer',oi)
            try:
                for ii,inner in enumerate(area.inner_rings(outer)):ring_record(inner,'inner',oi,ii)
            except Exception:
                summary['inaccessible_rings']+=1;summary['all_ring_coordinates_inspected']=False
    except Exception:
        summary['inaccessible_rings']+=1;summary['all_ring_coordinates_inspected']=False
    return summary

class AreaFailureAudit(osmium.SimpleHandler):
    def __init__(self,country,*,factory=None):
        super().__init__();self.country=country;self.factory=factory or osmium.geom.GeoJSONFactory()
        self.counts=Counter();self.failures=[];self.country_factory_checks=[]
    def area(self,area):
        self.counts['emitted_area_events']+=1;tags=dict(area.tags)
        is_country,building,water=selected_area(tags)
        if not (is_country or building or water):return
        self.counts['eligible_factory_attempts']+=1
        self.counts['country_attempts' if is_country else 'building_attempts' if building else 'water_attempts']+=1
        try:geometry=json.loads(self.factory.create_multipolygon(area))
        except Exception as e:
            self.counts['area_geometry']+=1
            if len(self.failures)>=MAX_FAILURES:raise BudgetStop('Failure record budget exceeded; audit incomplete')
            raw=inspect_raw_rings(area)
            classification=classify_bounds(raw['valid_node_bounds_wgs84'],invalid_nodes=raw['invalid_nodes'],
                inaccessible_rings=raw['inaccessible_rings'],valid_nodes=raw['valid_nodes'],country=self.country)
            relevant={k:tags[k][:1024] for k in RELEVANT_TAGS if k in tags}
            self.failures.append({'source_id':('way/' if area.from_way() else 'relation/')+str(area.orig_id()),
                'area_event_id':int(area.id),'relevant_source_tags':relevant,
                'relevant_tag_values_truncated':[k for k in relevant if len(tags[k])>1024],
                'factory_error_type':type(e).__name__,'raw_rings':raw,**classification})
            return
        self.counts['factory_successes']+=1
        if is_country:
            try:
                g=shape(geometry)
                self.country_factory_checks.append({'source_id':('way/' if area.from_way() else 'relation/')+str(area.orig_id()),
                    'matches_exact_pinned_country':g.equals(self.country),'factory_geometry_sha256':sha(canonical_bytes(geometry))})
            except Exception:self.country_factory_checks.append({'matches_exact_pinned_country':False,'reason':'Country factory geometry comparison failed'})
        # Successful geometries are immediately discarded, never retained for
        # all Malaysia/Singapore/Brunei objects or written as a national export.

def report_for(audit,binding,*,status='complete',reason=None,resource_metrics=None):
    classes=Counter(f['classification'] for f in audit.failures)
    expected=binding.get('recorded_area_geometry_exceptions')
    reproduced=audit.counts['area_geometry']==expected if expected is not None else None
    country_matches=bool(audit.country_factory_checks) and all(c.get('matches_exact_pinned_country') for c in audit.country_factory_checks)
    return {'schema':SCHEMA,'status':status,'reason':reason,'binding':binding,'counts':dict(audit.counts),
        'failure_classifications':dict(classes),'failures':audit.failures,
        'country_factory_checks':audit.country_factory_checks,
        'reproduces_recorded_exception_count':reproduced,'country_factory_matches_exact_pinned_country':country_matches,
        'recorded_failure_scope_conclusion':('all_reproduced_recorded_factory_failures_outside_country'
            if status=='complete' and reproduced and country_matches and classes['outside_country']==expected else 'unresolved_or_potential_country_omissions'),
        'resources':resource_metrics or {},
        'scope':{'exact_original_area_predicate_and_factory_pass':True,'spatial_country_filter_applied_before_factory':False,
            'canonical_data_mutated':False,'invalid_geometry_repaired':False,'rough_bbox_used_as_country':False,
            'native_assembler_suppressed_objects_audited':False,'source_completeness_certified':False},
        'limitations':['Only emitted areas reaching the exact factory predicate are audited. Native assembler omissions/errors that never emit area events remain outside this test.',
            'Outside classification requires all raw ring coordinates accessible/valid and their complete envelope disjoint from the exact pinned country multipolygon.',
            'Potential/UNKNOWN failures stay unresolved; no polygon repair, inferred missing building or source geometry is fabricated.',
            'This audit neither certifies full Singapore source completeness nor the rendered/runtime city.']}

def write_json_new(path,document):
    data=canonical_bytes(document)
    if len(data)>MAX_REPORT_BYTES:raise AreaAuditError('Bounded audit report exceeds8MiB; no large payload emitted')
    with path.open('xb') as f:f.write(data)

def source_inputs(args):
    manifest,manifest_raw=read_json(args.snapshot_manifest)
    boundary,boundary_raw=read_json(args.country)
    if manifest.get('pbf_sha256')!=args.expected_pbf_sha256:raise AreaAuditError('Pinned canonical PBF identity differs from requested source')
    if sha(boundary_raw)!=args.expected_country_sha256:raise AreaAuditError('Country boundary differs from exact pinned SHA256')
    country=shape(boundary)
    if country.geom_type not in ('Polygon','MultiPolygon') or country.is_empty or not country.is_valid:
        raise AreaAuditError('Exact pinned country must be valid Polygon/MultiPolygon; no repair/substitute')
    if args.pbf.is_symlink() or sha_file(args.pbf)!=args.expected_pbf_sha256:raise AreaAuditError('Private PBF differs from exact pinned SHA256')
    reader=osmium.io.Reader(str(args.pbf),osmium.osm.osm_entity_bits.NOTHING)
    try:
        h=reader.header();header={k:h.get(k) or None for k in ('osmosis_replication_timestamp','osmosis_replication_sequence_number','generator')}
    finally:reader.close()
    if header['osmosis_replication_timestamp']!=manifest.get('source_snapshot_utc'):raise AreaAuditError('PBF/canonical snapshot timestamp conflict')
    binding={'pbf_sha256':args.expected_pbf_sha256,'source_snapshot_utc':manifest.get('source_snapshot_utc'),
        'pbf_header':header,'canonical_snapshot_manifest_sha256':sha(manifest_raw),'exact_country_sha256':sha(boundary_raw),
        'recorded_area_geometry_exceptions':manifest.get('parse_errors',{}).get('area_geometry',0),
        'original_extractor_sha256':sha(Path(__file__).with_name('extract_singapore.py').read_bytes()),
        'attribution':'© OpenStreetMap contributors','data_license':'ODbL-1.0','license_url':'https://www.openstreetmap.org/copyright'}
    return country,binding

class RawFailureObjects(osmium.SimpleHandler):
    def __init__(self,way_ids,relation_ids=()):
        super().__init__();self.wanted_ways=set(way_ids);self.wanted_relations=set(relation_ids)
        self.ways={};self.relations={};self.duplicates=[]
    def way(self,way):
        if way.id not in self.wanted_ways:return
        if way.id in self.ways:self.duplicates.append('way/'+str(way.id));return
        refs=[int(n.ref) for n in way.nodes]
        if len(refs)>100000:raise BudgetStop('Raw failure way exceeds bounded node-reference budget')
        self.ways[int(way.id)]={'node_refs':refs,'tags':dict(way.tags)}
    def relation(self,relation):
        if relation.id not in self.wanted_relations:return
        if relation.id in self.relations:self.duplicates.append('relation/'+str(relation.id));return
        members=[{'type':m.type,'ref':int(m.ref),'role':str(m.role)} for m in relation.members]
        if len(members)>512:raise BudgetStop('Raw failure relation exceeds bounded member budget')
        self.relations[int(relation.id)]={'members':members,'tags':dict(relation.tags)}

class RawFailureNodes(osmium.SimpleHandler):
    def __init__(self,wanted):super().__init__();self.wanted=set(wanted);self.nodes={};self.duplicates=[]
    def node(self,node):
        if node.id not in self.wanted:return
        if node.id in self.nodes:self.duplicates.append(int(node.id));return
        self.nodes[int(node.id)]=_position(node)

def _filtered_apply(pbf,entities,ids,handler):
    if not ids:return
    reader=osmium.io.Reader(str(pbf),entities)
    try:osmium.apply(reader,osmium.filter.IdFilter(sorted(ids)),handler)
    finally:reader.close()

def audit_raw_source_failures(original,country,pbf,*,predecessor_sha256):
    # Native failed area events may contain zero rings. Recover only their
    # original way/relation membership and selected node records, never repair.
    way_ids={int(f['source_id'].split('/')[1]) for f in original['failures'] if f['source_id'].startswith('way/')}
    relation_ids={int(f['source_id'].split('/')[1]) for f in original['failures'] if f['source_id'].startswith('relation/')}
    objects=RawFailureObjects(way_ids,relation_ids)
    _filtered_apply(pbf,osmium.osm.osm_entity_bits.WAY|osmium.osm.osm_entity_bits.RELATION,way_ids|relation_ids,objects)
    member_way_ids={m['ref'] for r in objects.relations.values() for m in r['members'] if m['type']=='w'}
    if len(member_way_ids)>512:raise BudgetStop('Raw failure member-way budget exceeded')
    missing_member_ways=member_way_ids-set(objects.ways)
    if missing_member_ways:
        extra=RawFailureObjects(missing_member_ways)
        _filtered_apply(pbf,osmium.osm.osm_entity_bits.WAY,missing_member_ways,extra)
        objects.ways.update(extra.ways);objects.duplicates.extend(extra.duplicates)
    node_ids={n for w in objects.ways.values() for n in w['node_refs']}
    node_ids.update(m['ref'] for r in objects.relations.values() for m in r['members'] if m['type']=='n')
    if len(node_ids)>100000 or any(n<=0 for n in node_ids):raise BudgetStop('Raw failure selected-node budget/identity invalid')
    nodes=RawFailureNodes(node_ids)
    _filtered_apply(pbf,osmium.osm.osm_entity_bits.NODE,node_ids,nodes)
    result=json.loads(canonical_bytes(original));classes=Counter()
    for failure in result['failures']:
        typ,identifier=failure['source_id'].split('/');identifier=int(identifier)
        selected_ways=[];direct_nodes=[];unresolved=[];record=None
        if typ=='way':
            record=objects.ways.get(identifier)
            if record is None:unresolved.append('missing_original_source_way')
            else:selected_ways=[identifier]
        elif typ=='relation':
            record=objects.relations.get(identifier)
            if record is None:unresolved.append('missing_original_source_relation')
            else:
                for m in record['members']:
                    if m['type']=='w':selected_ways.append(m['ref'])
                    elif m['type']=='n':direct_nodes.append(m['ref'])
                    else:unresolved.append('nested_or_unknown_relation_member_not_resolved')
        else:unresolved.append('unsupported_original_source_type')
        if record is not None:
            for key,value in failure['relevant_source_tags'].items():
                if key in failure.get('relevant_tag_values_truncated',[]):unresolved.append('truncated_tag_not_exactly_comparable')
                elif record['tags'].get(key)!=value:unresolved.append('original_source_tag_conflict')
        refs=list(direct_nodes);raw_ways=[]
        for way_id in selected_ways:
            way=objects.ways.get(way_id)
            if way is None:unresolved.append('missing_relation_member_way');continue
            ordered=way['node_refs'];refs.extend(ordered)
            if not ordered:unresolved.append('empty_original_source_way_has_no_coordinate_evidence')
            raw_ways.append({'source_id':'way/'+str(way_id),'node_reference_count':len(ordered),
                'ordered_node_reference_sha256':sha(canonical_bytes(ordered)),
                'closed_by_node_identity':len(ordered)>1 and ordered[0]==ordered[-1],
                'distinct_source_node_ids':len(set(ordered)),
                'head_node_ids':ordered[:8],'tail_node_ids':ordered[-8:]})
        required=set(refs);missing=sorted(required-set(nodes.nodes));invalid=sorted(n for n in required if n in nodes.nodes and nodes.nodes[n] is None)
        if any(n in nodes.duplicates for n in required):unresolved.append('duplicate_original_source_node')
        if objects.duplicates:unresolved.append('duplicate_original_source_way_or_relation')
        valid=[nodes.nodes[n] for n in required if n in nodes.nodes and nodes.nodes[n] is not None]
        bounds=[min(p[0] for p in valid),min(p[1] for p in valid),max(p[0] for p in valid),max(p[1] for p in valid)] if valid else None
        evidence={'method':'Original source way/member-way node references plus bounded selected original node-coordinate pass; no area repair',
            'source_way_records':raw_ways,'direct_relation_node_ids':direct_nodes,
            'relation_members':record.get('members') if typ=='relation' and record else None,
            'raw_node_references':len(refs),'distinct_required_nodes':len(required),'valid_source_nodes':len(valid),
            'missing_source_node_ids':missing,'invalid_source_node_ids':invalid,'unresolved_source_conditions':unresolved,
            'complete_valid_source_node_bounds_wgs84':bounds,'valid_source_node_positions_sha256':sha(canonical_bytes({str(n):nodes.nodes[n] for n in sorted(required) if n in nodes.nodes})),
            'bounded_node_samples':[{'node_id':n,'wgs84_lon_lat':nodes.nodes.get(n)} for n in sorted(required)[:16]]}
        classified=classify_bounds(bounds,invalid_nodes=len(invalid)+len(missing),inaccessible_rings=len(unresolved),valid_nodes=len(valid),country=country)
        failure['assembled_event_classification']=failure['classification'];failure['assembled_event_reason']=failure['reason']
        failure['raw_source_evidence']=evidence;failure.update(classified);classes[failure['classification']]+=1
    result['failure_classifications']=dict(classes)
    result['binding']['predecessor_emitted_area_audit_sha256']=predecessor_sha256
    result['raw_source_fallback']={'only_failed_source_ids_and_members_retained':True,
        'source_ways_retained':len(objects.ways),'source_relations_retained':len(objects.relations),
        'source_nodes_requested':len(node_ids),'source_nodes_found':len(nodes.nodes),
        'node_location_cache_created':False,'nested_relations_expanded':False,'geometry_repaired':False}
    expected=result['binding']['recorded_area_geometry_exceptions']
    result['recorded_failure_scope_conclusion']=('all_reproduced_recorded_factory_failures_outside_country'
        if original.get('status')=='complete' and original.get('reproduces_recorded_exception_count') and original.get('country_factory_matches_exact_pinned_country') and classes['outside_country']==expected
        else 'unresolved_or_potential_country_omissions')
    result['limitations'].append('Raw-source fallback resolves only recorded failure IDs/member ways/nodes. Missing/invalid/nested-unresolved source stays UNKNOWN, and suppressed native area events remain unaudited.')
    return result

def run_worker(args):
    started=time.monotonic();audit=None;binding={};status='complete';reason=None
    resource.setrlimit(resource.RLIMIT_CPU,(args.max_cpu_seconds,args.max_cpu_seconds+15))
    try:
        country,binding=source_inputs(args)
        if args.raw_source_audit is not None:
            original,raw=read_json(args.raw_source_audit)
            if sha(raw)!=args.expected_prior_audit_sha256 or original.get('schema')!=SCHEMA:
                raise AreaAuditError('Original emitted-area audit identity/schema mismatch')
            if any(original.get('binding',{}).get(k)!=v for k,v in binding.items()):
                raise AreaAuditError('Original audit differs from exact source/country binding')
            document=audit_raw_source_failures(original,country,args.pbf,predecessor_sha256=sha(raw))
        else:
            audit=AreaFailureAudit(country)
            audit.apply_file(str(args.pbf),locations=True,idx='sparse_file_array,'+str(args.output_dir/'location-index.bin'))
    except Exception as e:
        status='incomplete';reason=type(e).__name__+': bounded source/factory audit interrupted; no private paths emitted'
    usage=resource.getrusage(resource.RUSAGE_SELF)
    metrics={'wall_seconds':round(time.monotonic()-started,3),'cpu_seconds':round(usage.ru_utime+usage.ru_stime,3),
        'peak_rss_bytes':int(usage.ru_maxrss if sys.platform=='darwin' else usage.ru_maxrss*1024),
        'location_index':('none; C++ ID-filtered recorded failure/member-way/node metadata only' if args.raw_source_audit is not None else 'disk-backed sparse_file_array; all source locations needed by native area assembly, no feature payload retained')}
    if args.raw_source_audit is not None and status=='complete':
        document['raw_source_fallback_resources']=metrics
        write_json_new(args.output_dir/'audit.json',document)
        return 0
    document=report_for(audit,binding,status=status,reason=reason,resource_metrics=metrics) if audit else {
        'schema':SCHEMA,'status':'incomplete','reason':reason,'binding':binding,'resources':metrics}
    write_json_new(args.output_dir/'audit.json',document)
    return 0 if status=='complete' else 1

def _rss_bytes(pid):
    try:
        result=subprocess.run(['/bin/ps','-o','rss=','-p',str(pid)],capture_output=True,text=True,check=False)
        text=result.stdout.strip()
        return int(text)*1024 if text else None
    except Exception:return None

def supervise(args):
    if args.output_dir.exists():raise AreaAuditError('Refusing to overwrite previous area-audit evidence')
    args.output_dir.mkdir(parents=True,mode=0o700)
    limits={'max_rss_mib':args.max_rss_mib,'max_index_mib':args.max_index_mib,
        'max_cpu_seconds':args.max_cpu_seconds,'max_wall_seconds':args.max_wall_seconds,
        'rss_poll_interval_seconds':1,'rss_is_supervised_not_kernel_hard_limit':True}
    if shutil.disk_usage(args.output_dir).free<(args.max_index_mib+256)*1024*1024:
        write_json_new(args.output_dir/'supervisor.json',{'status':'pending_not_started','reason':'Insufficient safe disk headroom','limits':limits});return 2
    command=[sys.executable,str(Path(__file__).resolve()),*sys.argv[1:],'--worker']
    started=time.monotonic();peak_rss=0;peak_index=0;stop_reason=None;unknown_rss=0
    process=subprocess.Popen(command,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        while process.poll() is None:
            rss=_rss_bytes(process.pid)
            if rss is None:unknown_rss+=1
            else:peak_rss=max(peak_rss,rss);unknown_rss=0
            index=args.output_dir/'location-index.bin'
            if index.exists():peak_index=max(peak_index,index.stat().st_size)
            if peak_rss>args.max_rss_mib*1024*1024:stop_reason='Worker RSS exceeded supervised budget'
            elif peak_index>args.max_index_mib*1024*1024:stop_reason='Disk-backed location index exceeded supervised budget'
            elif time.monotonic()-started>args.max_wall_seconds:stop_reason='Worker exceeded wall-time budget'
            elif unknown_rss>=5:stop_reason='Could not supervise worker memory reliably'
            if stop_reason:
                process.terminate()
                try:process.wait(timeout=30)
                except subprocess.TimeoutExpired:process.kill();process.wait()
                break
            time.sleep(1)
    finally:
        if process.poll() is None:
            process.terminate()
            try:process.wait(timeout=30)
            except subprocess.TimeoutExpired:process.kill();process.wait()
    receipt={'status':'complete' if process.returncode==0 and stop_reason is None else 'incomplete',
        'reason':stop_reason,'worker_exit_code':process.returncode,'wall_seconds':round(time.monotonic()-started,3),
        'sampled_peak_worker_rss_bytes':peak_rss,'sampled_peak_index_bytes':peak_index,'limits':limits}
    report_path=args.output_dir/'audit.json'
    if report_path.exists():
        raw=report_path.read_bytes();report=json.loads(raw)
        receipt.update({'audit_sha256':sha(raw),'audit_status':report.get('status'),
            'failure_classifications':report.get('failure_classifications'),'reproduces_recorded_exception_count':report.get('reproduces_recorded_exception_count')})
    index=args.output_dir/'location-index.bin'
    if index.exists():
        peak_index=max(peak_index,index.stat().st_size);receipt['sampled_peak_index_bytes']=peak_index
        index.unlink();receipt['owned_location_index_removed_after_worker_exit']=True
    write_json_new(args.output_dir/'supervisor.json',receipt)
    print(json.dumps(receipt,sort_keys=True),flush=True)
    return 0 if receipt['status']=='complete' else 1

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pbf',type=Path,required=True);p.add_argument('--expected-pbf-sha256',required=True)
    p.add_argument('--snapshot-manifest',type=Path,required=True);p.add_argument('--country',type=Path,required=True)
    p.add_argument('--expected-country-sha256',required=True)
    p.add_argument('--raw-source-audit',type=Path);p.add_argument('--expected-prior-audit-sha256')
    p.add_argument('--output-dir',type=Path,required=True);p.add_argument('--worker',action='store_true',help=argparse.SUPPRESS)
    p.add_argument('--max-rss-mib',type=int,default=2048);p.add_argument('--max-index-mib',type=int,default=2048)
    p.add_argument('--max-cpu-seconds',type=int,default=240);p.add_argument('--max-wall-seconds',type=int,default=480)
    args=p.parse_args()
    try:
        if not 64<=args.max_rss_mib<=4096 or not 64<=args.max_index_mib<=4096 or not 5<=args.max_cpu_seconds<=480 or not 5<=args.max_wall_seconds<=900:
            raise AreaAuditError('Invalid bounded resource contract')
        return run_worker(args) if args.worker else supervise(args)
    except Exception:
        print(json.dumps({'status':'incomplete','reason':'Bounded source audit input/output failure; no private paths emitted'}),flush=True);return 2

if __name__=='__main__':raise SystemExit(main())
