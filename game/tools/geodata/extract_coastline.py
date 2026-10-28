#!/usr/bin/env python3
"""Pinned OSM coastline source rings; administrative territory is not land.

Original node identity/direction drives assembly. No reverse/snap/buffer/repair,
XY union, terrain/tide inference, or arbitrary closure of open coastline chains.
"""
import argparse
from collections import Counter,defaultdict
from copy import deepcopy
import json
import math
from pathlib import Path
import resource
import subprocess
import sys
import time

import osmium
from shapely.geometry import Polygon,MultiPolygon,box,mapping,shape
from shapely.strtree import STRtree
import georeference
from build_spatial_index import projected_country,validate_frame
from enrich_source_tags import canonical_bytes,read_json,sha,sha_file,string_tags

SCHEMA='singapore_source_coastline_v1'
MAX_WAYS=50000
MAX_NODES=1500000
MAX_REFS=2000000
MAX_CATALOG_BYTES=128*1024*1024

class CoastlineError(ValueError):pass

def _metadata(obj):
    stamp=str(obj.timestamp)
    return {'version':int(obj.version) if obj.version>0 else None,
        'timestamp_utc':None if stamp.startswith('1970-01-01') else stamp,
        'changeset':int(obj.changeset) if obj.changeset>0 else None}

class CoastWays(osmium.SimpleHandler):
    def __init__(self):super().__init__();self.ways={};self.duplicate_ids=[];self.refs=0
    def way(self,way):
        if dict(way.tags).get('natural')!='coastline':return
        key='way/'+str(way.id)
        if key in self.ways:self.duplicate_ids.append(key);return
        refs=[int(n.ref) for n in way.nodes];self.refs+=len(refs)
        if len(self.ways)>=MAX_WAYS or self.refs>MAX_REFS:raise CoastlineError('Source coastline way/reference budget exceeded')
        self.ways[key]={'ordered_node_ids':refs,'source_tags':dict(way.tags),'osm_metadata':_metadata(way)}

class CoastNodes(osmium.SimpleHandler):
    def __init__(self,targets):super().__init__();self.targets=targets;self.nodes={};self.duplicate_ids=[]
    def node(self,node):
        if node.id not in self.targets:return
        key=int(node.id)
        if key in self.nodes:self.duplicate_ids.append(key);return
        valid=node.location.valid();position=None
        if valid:
            lon,lat=float(node.location.lon),float(node.location.lat)
            if math.isfinite(lon) and math.isfinite(lat) and -180<=lon<=180 and -90<=lat<=90:position=[lon,lat]
        self.nodes[key]={'source_wgs84_lon_lat':position,'source_tags':dict(node.tags),'osm_metadata':_metadata(node)}

def _reader_apply(pbf,entities,filters,handler):
    reader=osmium.io.Reader(str(pbf),entities)
    try:
        header=reader.header();metadata={k:header.get(k) or None for k in ('osmosis_replication_timestamp','osmosis_replication_sequence_number','generator')}
        osmium.apply(reader,*filters,handler)
    finally:reader.close()
    return metadata

def scan_coastline(pbf,expected_sha):
    if pbf.is_symlink() or sha_file(pbf)!=expected_sha:raise CoastlineError('Private PBF differs from explicitly pinned SHA256')
    before=pbf.stat();ways=CoastWays()
    header=_reader_apply(pbf,osmium.osm.osm_entity_bits.WAY,[osmium.filter.TagFilter(('natural','coastline'))],ways)
    ids={n for w in ways.ways.values() for n in w['ordered_node_ids']}
    if len(ids)>MAX_NODES or any(n<=0 for n in ids):raise CoastlineError('Selected coastline node budget/identity invalid')
    nodes=CoastNodes(ids)
    node_header=_reader_apply(pbf,osmium.osm.osm_entity_bits.NODE,[osmium.filter.IdFilter(sorted(ids))],nodes)
    after=pbf.stat()
    if header!=node_header or (before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_ino,after.st_size,after.st_mtime_ns):
        raise CoastlineError('Source changed between exact-source metadata passes')
    return ways,nodes,header

def _bbox_relation(positions,country,complete):
    if not complete or not positions:return 'UNKNOWN'
    bounds=[min(p[0] for p in positions),min(p[1] for p in positions),max(p[0] for p in positions),max(p[1] for p in positions)]
    # Degenerate known chains are conservatively buffered by no amount; use
    # their envelope only for scope metadata, never to close or fill land.
    from audit_area_failures import envelope_geometry
    return 'known_chain_envelope_disjoint' if envelope_geometry(bounds).disjoint(country) else 'potential_country_intersection'

def _signed_area(points):
    return .5*sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(points,points[1:]))

def assemble_rings(ways,nodes,country_wgs84,*,duplicate_way_ids=(),duplicate_node_ids=()):
    keys=sorted(ways);parent={k:k for k in keys};first_way={};indegree=Counter();outdegree=Counter();way_issues=defaultdict(list)
    def find(k):
        while parent[k]!=k:parent[k]=parent[parent[k]];k=parent[k]
        return k
    def join(a,b):
        a,b=find(a),find(b)
        if a!=b:parent[max(a,b)]=min(a,b)
    for key in keys:
        refs=ways[key]['ordered_node_ids']
        if len(refs)<2:way_issues[key].append('fewer_than_two_source_nodes')
        for n in refs:
            if n in first_way:join(key,first_way[n])
            else:first_way[n]=key
        for a,b in zip(refs,refs[1:]):
            outdegree[a]+=1;indegree[b]+=1
            if a==b:way_issues[key].append('zero_identity_source_segment')
    groups=defaultdict(list)
    for key in keys:groups[find(key)].append(key)
    rings=[];unresolved=[];dup_ways=set(duplicate_way_ids);dup_nodes=set(duplicate_node_ids)
    for number,(_,component) in enumerate(sorted(groups.items())):
        all_ids={n for key in component for n in ways[key]['ordered_node_ids']};missing=sorted(all_ids-set(nodes));invalid=sorted(n for n in all_ids if n in nodes and nodes[n].get('source_wgs84_lon_lat') is None)
        branches=sorted(n for n in all_ids if indegree[n]>1 or outdegree[n]>1)
        ends=sorted(n for n in all_ids if indegree[n]!=1 or outdegree[n]!=1)
        issues=sorted({i for key in component for i in way_issues[key]})
        if missing:issues.append('missing_original_nodes')
        if invalid:issues.append('invalid_original_coordinates')
        if branches:issues.append('ambiguous_branch_or_retraced_coastline')
        if ends:issues.append('open_or_direction_mismatched_coastline_chain')
        if dup_ways.intersection(component) or dup_nodes.intersection(all_ids):issues.append('duplicate_source_observation')
        positions=[nodes[n]['source_wgs84_lon_lat'] for n in all_ids if n in nodes and nodes[n].get('source_wgs84_lon_lat') is not None]
        entry={'component_id':'coast-component-%06d'%number,'source_way_ids':component,
            'distinct_source_node_count':len(all_ids),'missing_node_ids':missing,'invalid_node_ids':invalid,
            'branch_node_ids':branches,'open_or_direction_mismatch_node_ids':ends,
            'known_chain_country_scope':_bbox_relation(positions,country_wgs84,not missing and not invalid),
            'scope_warning':'Known-chain envelope disjointness is not a proof about land on the unclosed side or unmapped continuation.'}
        if issues:unresolved.append({**entry,'issues':issues});continue
        by_start={ways[k]['ordered_node_ids'][0]:k for k in component};current=component[0];used=[];ordered=[]
        for _ in range(len(component)+1):
            if current in used:break
            used.append(current);refs=ways[current]['ordered_node_ids']
            ordered.extend(refs if not ordered else refs[1:])
            if ordered[-1]==ordered[0]:break
            current=by_start.get(ordered[-1])
            if current is None:break
        if len(used)!=len(component) or not ordered or ordered[0]!=ordered[-1] or len(set(ordered))<3:
            unresolved.append({**entry,'issues':['cannot_form_one_source_directed_closed_ring']});continue
        lonlat=[nodes[n]['source_wgs84_lon_lat'] for n in ordered]
        try:
            projected=[georeference.from_wgs84(*p) for p in lonlat]
            xz=[[p[0],p[2]] for p in projected]
            polygon=Polygon(xz);area=_signed_area(xz)
            if not all(math.isfinite(v) for p in xz for v in p) or not polygon.is_valid or polygon.is_empty or area==0:
                raise ValueError('invalid')
        except Exception:
            unresolved.append({**entry,'issues':['invalid_closed_source_polygon_no_repair']});continue
        rings.append({**entry,'source_way_ids_in_order':used,'ordered_node_ids':ordered,
            'source_wgs84_lon_lat':lonlat,'projected_world_xz':xz,'signed_area_xz_m2':area,
            'land_left_role':'land_interior' if area<0 else 'water_interior',
            'polygon':polygon})
    return rings,unresolved

def assemble_land(rings,country_projected):
    polygons=[r['polygon'] for r in rings];tree=STRtree(polygons) if polygons else None
    parents={};conflict=set();issues=[];warnings=[]
    for i,p in enumerate(polygons):
        containers=[]
        for raw_j in tree.query(p,predicate='intersects'):
            j=int(raw_j)
            if j==i:continue
            other=polygons[j]
            if p.equals(other):
                conflict.update((i,j));issues.append({'rings':[i,j],'issue':'coincident_closed_rings_not_merged'})
            elif other.contains(p):
                containers.append(j)
                if p.boundary.intersects(other.boundary):conflict.update((i,j));issues.append({'rings':[i,j],'issue':'nested_boundary_contact_ambiguous'})
            elif p.contains(other):continue
            elif j>i:
                overlap=p.intersection(other)
                if overlap.area>0 or p.boundary.intersection(other.boundary).length>0:
                    conflict.update((i,j));issues.append({'rings':[i,j],'issue':'crossing_or_overlapping_closed_rings_no_repair'})
                else:warnings.append({'rings':[i,j],'warning':'point_contact_kept_as_distinct_source_rings_no_xy_merge'})
        if containers:parents[i]=min(containers,key=lambda j:polygons[j].area)
    for i,j in parents.items():
        if rings[i]['land_left_role']==rings[j]['land_left_role']:
            conflict.update((i,j));issues.append({'rings':[i,j],'issue':'nested_same_land_left_orientation_ambiguous'})
    for i,r in enumerate(rings):
        if r['land_left_role']=='water_interior' and i not in parents:
            conflict.add(i);issues.append({'rings':[i],'issue':'orphan_water_interior_ring_no_land_exterior_invented'})
    # A contradictory nested boundary makes its ancestor/descendant envelope
    # unresolved; do not hide it with a polygon union or arbitrary hole repair.
    changed=True
    while changed:
        changed=False
        for i,j in parents.items():
            if (i in conflict)!=(j in conflict):conflict.update((i,j));changed=True
    output=[]
    for i,r in enumerate(rings):
        if i in conflict or r['land_left_role']!='land_interior':continue
        hole_ids=sorted(j for j,p in parents.items() if p==i and j not in conflict and rings[j]['land_left_role']=='water_interior')
        polygon=Polygon(r['projected_world_xz'],[rings[j]['projected_world_xz'] for j in hole_ids])
        if not polygon.is_valid:
            issues.append({'rings':[i,*hole_ids],'issue':'assembled_source_holes_invalid_no_repair'});continue
        clipped=polygon.intersection(country_projected)
        if clipped.is_empty or clipped.area==0:continue
        def polygon_parts(geometry):
            if geometry.geom_type=='Polygon':return [geometry]
            if hasattr(geometry,'geoms'):return [p for g in geometry.geoms for p in polygon_parts(g)]
            return []
        parts=polygon_parts(clipped)
        if not parts:continue
        clipped=parts[0] if len(parts)==1 else MultiPolygon(parts)
        # Clip each independent supported polygon. Never XY-union source rings.
        output.append({'type':'Feature','properties':{'source_component_id':r['component_id'],
            'source_outer_ring_index':i,'source_hole_ring_indices':hole_ids,
            'land_left_semantics':'source directed coast; land on left, XZ orientation flips WGS84 handedness',
            'terrain_elevation_m':None,'tide_datum':None,
            'surface_scope':'Coastline-enclosed surface, not an independently verified inland-water/dryland or elevation model'},
            'geometry':mapping(clipped)})
    return {'type':'FeatureCollection','coordinate_space':'projected Godot XZ metres, not longitude/latitude','features':output},issues,warnings,sorted(conflict)

def build_document(ways,nodes,country_wgs84,country_projected,binding,*,duplicate_way_ids=(),duplicate_node_ids=()):
    rings,unresolved=assemble_rings(ways,nodes,country_wgs84,duplicate_way_ids=duplicate_way_ids,duplicate_node_ids=duplicate_node_ids)
    land,issues,warnings,excluded=assemble_land(rings,country_projected)
    ring_catalog=[{k:v for k,v in ring.items() if k!='polygon'} for ring in rings]
    report={'schema':SCHEMA,'binding':binding,'projection_frame':georeference.manifest(),
        'counts':{'source_coastline_ways':len(ways),'source_nodes':len(nodes),
            'closed_directed_valid_rings':len(rings),'unresolved_source_components':len(unresolved),
            'land_interior_rings':sum(r['land_left_role']=='land_interior' for r in rings),
            'water_interior_rings':sum(r['land_left_role']=='water_interior' for r in rings),
            'ambiguous_excluded_ring_indices':len(excluded),'country_clipped_source_land_features':len(land['features'])},
        'closed_rings':ring_catalog,'unresolved_components':unresolved,'assembly_issues':issues,'warnings':warnings,
        'excluded_ring_indices':excluded,'land':land,
        'contract':{'country_is_administrative_territory_not_land':True,'clip_only_after_source_assembly':True,
            'original_node_identity_and_direction_only':True,'reversed_source_ways':False,'xy_snapping_or_merging':False,
            'simplification_or_buffer_repair':False,'country_or_rectangle_filled_as_land':False,
            'metres_per_unit':1.0,'terrain_elevation_inferred':False,'tide_datum_known':False,
            'inland_water_is_not_coastline':True,'inland_water_surface_classification':'separate source-supported layer still required'},
        'acceptance':{'source_completeness_certified':False,'whole_country_land_coverage_certified':False,
            'terrain_or_rendered_city_completed':False},
        'limitations':['Only mapped natural=coastline source ways are used; missing or clipped source coverage and source survey accuracy remain unverified.',
            'Open/branched/missing/invalid/ambiguous chains remain unresolved, including unmapped continuation beyond the PBF boundary; no administrative sea territory is filled as land.',
            'Mapped inland water, inland terrain, elevations, tides, seawalls and navigable water require separate verified layers; coastline enclosure alone does not certify dryland everywhere inside.',
            'Source-supported closed rings and their country clipping are data only, not detailed terrain, city runtime, materials, architecture or gameplay acceptance.']}
    return report

def write_output(output,document,ways,nodes):
    if (output/'coastline.json').exists() or (output/'source-catalog.json').exists():raise CoastlineError('Refusing to overwrite coastline evidence')
    catalog={'schema':SCHEMA,'binding':document['binding'],'ways':ways,'nodes':{str(k):v for k,v in sorted(nodes.items())},
        'coordinates':'Original WGS84 and directed node references; no full source location cache or inferred heights'}
    raw=canonical_bytes(catalog)
    if len(raw)>MAX_CATALOG_BYTES:raise CoastlineError('Source coastline catalog exceeds128MiB bound')
    with (output/'source-catalog.json').open('xb') as f:f.write(raw)
    document['source_catalog']={'file':'source-catalog.json','sha256':sha(raw),'bytes':len(raw)}
    data=canonical_bytes(document)
    if len(data)>MAX_CATALOG_BYTES:raise CoastlineError('Compiled coastline report exceeds128MiB bound')
    with (output/'coastline.json').open('xb') as f:f.write(data)
    return {'schema':SCHEMA,'status':'complete','coastline_sha256':sha(data),'coastline_bytes':len(data),
        'catalog_sha256':sha(raw),'catalog_bytes':len(raw),'counts':document['counts']}

def _worker(args):
    started=time.monotonic();resource.setrlimit(resource.RLIMIT_CPU,(args.max_cpu_seconds,args.max_cpu_seconds+15))
    manifest,manifest_raw=read_json(args.snapshot_manifest);boundary,boundary_raw=read_json(args.country)
    validate_frame(manifest.get('georeference'))
    if manifest.get('georeference')!=georeference.manifest():raise CoastlineError('Current metre projection differs from canonical frame')
    if manifest.get('pbf_sha256')!=args.expected_pbf_sha256 or sha(boundary_raw)!=args.expected_country_sha256:
        raise CoastlineError('Canonical PBF/country differs from explicitly pinned source')
    country=shape(boundary)
    if country.geom_type not in ('Polygon','MultiPolygon') or country.is_empty or not country.is_valid:raise CoastlineError('Exact country invalid; no repair/substitute')
    ways,nodes,header=scan_coastline(args.pbf,args.expected_pbf_sha256)
    if header.get('osmosis_replication_timestamp')!=manifest.get('source_snapshot_utc'):raise CoastlineError('PBF/canonical snapshot timestamp mismatch')
    binding={'pbf_sha256':args.expected_pbf_sha256,'canonical_manifest_sha256':sha(manifest_raw),'country_sha256':sha(boundary_raw),
        'source_snapshot_utc':manifest.get('source_snapshot_utc'),'pbf_header':header,
        'attribution':'© OpenStreetMap contributors','data_license':'ODbL-1.0','license_url':'https://www.openstreetmap.org/copyright',
        'projection_implementation_sha256':sha(Path(georeference.__file__).read_bytes())}
    doc=build_document(ways.ways,nodes.nodes,country,projected_country(boundary),binding,
        duplicate_way_ids=ways.duplicate_ids,duplicate_node_ids=nodes.duplicate_ids)
    usage=resource.getrusage(resource.RUSAGE_SELF)
    doc['resources']={'wall_seconds':round(time.monotonic()-started,3),'cpu_seconds':round(usage.ru_utime+usage.ru_stime,3),
        'peak_rss_bytes':int(usage.ru_maxrss if sys.platform=='darwin' else usage.ru_maxrss*1024),'location_cache_created':False}
    receipt=write_output(args.output_dir,doc,ways.ways,nodes.nodes)
    receipt['resources']=doc['resources'];(args.output_dir/'worker-receipt.json').write_bytes(canonical_bytes(receipt))
    return 0

def _supervise(args):
    if args.output_dir.exists():raise CoastlineError('Refusing to overwrite prior coastline run')
    args.output_dir.mkdir(parents=True,mode=0o700);started=time.monotonic();peak=0;reason=None;unknown=0
    process=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),*sys.argv[1:],'--worker'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        while process.poll() is None:
            result=subprocess.run(['/bin/ps','-o','rss=','-p',str(process.pid)],capture_output=True,text=True)
            if result.stdout.strip():peak=max(peak,int(result.stdout.strip())*1024);unknown=0
            else:unknown+=1
            if peak>args.max_rss_mib*1024*1024:reason='Worker exceeded supervised RSS budget'
            elif time.monotonic()-started>args.max_wall_seconds:reason='Worker exceeded wall-time budget'
            elif unknown>=5:reason='Worker RSS supervision unavailable'
            if reason:break
            time.sleep(1)
    finally:
        if process.poll() is None:
            process.terminate()
            try:process.wait(timeout=30)
            except subprocess.TimeoutExpired:process.kill();process.wait()
    receipt={'status':'complete' if process.returncode==0 and reason is None else 'incomplete',
        'reason':reason,'worker_exit_code':process.returncode,'wall_seconds':round(time.monotonic()-started,3),
        'sampled_peak_rss_bytes':peak,'limits':{'rss_mib':args.max_rss_mib,'wall_seconds':args.max_wall_seconds,
            'cpu_seconds':args.max_cpu_seconds,'rss_sample_seconds':1,'memory_limit_is_supervised_not_kernel_hard':True,
            'max_ways':MAX_WAYS,'max_selected_nodes':MAX_NODES,'max_source_refs':MAX_REFS}}
    if (args.output_dir/'worker-receipt.json').exists():receipt['worker']=json.loads((args.output_dir/'worker-receipt.json').read_bytes())
    if (args.output_dir/'failure.json').exists():receipt['failure']=json.loads((args.output_dir/'failure.json').read_bytes())
    (args.output_dir/'supervisor.json').write_bytes(canonical_bytes(receipt));print(json.dumps(receipt,sort_keys=True),flush=True)
    return 0 if receipt['status']=='complete' else 1

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pbf',type=Path,required=True);p.add_argument('--expected-pbf-sha256',required=True)
    p.add_argument('--snapshot-manifest',type=Path,required=True);p.add_argument('--country',type=Path,required=True);p.add_argument('--expected-country-sha256',required=True)
    p.add_argument('--output-dir',type=Path,required=True);p.add_argument('--worker',action='store_true',help=argparse.SUPPRESS)
    p.add_argument('--max-rss-mib',type=int,default=2048);p.add_argument('--max-cpu-seconds',type=int,default=240);p.add_argument('--max-wall-seconds',type=int,default=600)
    args=p.parse_args()
    try:
        if not 64<=args.max_rss_mib<=4096 or not 5<=args.max_cpu_seconds<=480 or not 5<=args.max_wall_seconds<=900:raise CoastlineError('Invalid resource bounds')
        return _worker(args) if args.worker else _supervise(args)
    except Exception as e:
        receipt={'status':'incomplete','reason':str(e) if isinstance(e,CoastlineError) else 'Source I/O/parser/geometry failure; no private source path emitted'}
        if args.worker and args.output_dir.is_dir():(args.output_dir/'failure.json').write_bytes(canonical_bytes(receipt))
        else:print(json.dumps(receipt),flush=True)
        return 2

if __name__=='__main__':raise SystemExit(main())
