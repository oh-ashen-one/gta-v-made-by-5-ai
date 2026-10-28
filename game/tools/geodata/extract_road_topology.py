#!/usr/bin/env python3
"""Regional original-node road/path topology, not a vehicle routing policy.

Reads original way node references without a node-location cache. Does not
connect spatial line crossings, infer elevations/permissions or alter geometry.
"""
import argparse
from collections import Counter,defaultdict
from copy import deepcopy
import json
import math
from pathlib import Path
import time

import osmium
import georeference
from enrich_source_tags import (EnrichmentError,canonical_bytes,catalog_targets,
    input_binding,read_json,sha,sha_file,source_id,string_tags)

SCHEMA='singapore_original_way_topology_v1'
VERIFIED_SCHEMA='singapore_original_way_topology_v2'
ROUNDING_TOLERANCE_METRES=0.0001
MAX_TARGET_WAYS=10000
SEMANTIC_TAGS=('highway','construction','proposed','oneway','oneway:bicycle',
    'junction','bridge','tunnel','layer','level','access','access:conditional',
    'vehicle','vehicle:conditional','motor_vehicle','motor_vehicle:conditional',
    'motorcar','motorcar:conditional','bicycle','bicycle:conditional','foot',
    'foot:conditional','service','width','width:carriageway','maxspeed','ele','ele:datum')

class TopologyError(ValueError):
    pass

def select_targets(catalog,kinds=('road',)):
    catalog_targets(catalog) # Validates all identities/checksums/string tags.
    targets=defaultdict(list)
    for item in catalog:
        if item['kind'] not in kinds:continue
        kind,osm_id=source_id(item['id'])
        if kind!='way':raise TopologyError('Selected topology feature is not an original OSM way')
        geometry=item.get('source_geometry_world_xz')
        if not isinstance(geometry,dict) or geometry.get('type')!='LineString':
            raise TopologyError('Selected way does not have an exact canonical LineString')
        coordinates=geometry.get('coordinates')
        if not isinstance(coordinates,(list,tuple)) or len(coordinates)<2:
            raise TopologyError('Canonical centreline must retain at least two ordered positions')
        for p in coordinates:
            if not isinstance(p,(list,tuple)) or len(p)!=2 or not all(isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v) for v in p):
                raise TopologyError('Canonical centreline contains invalid projected positions')
        targets[item['id']].append({'feature_key':item['feature_key'],'source_feature_sha256':item['source_feature_sha256'],
            'canonical_tags':deepcopy(item['tags']),'canonical_coordinates_world_xz':deepcopy(coordinates)})
    if not targets or len(targets)>MAX_TARGET_WAYS:raise TopologyError('Regional topology must contain1..10000 selected ways')
    return {key:sorted(records,key=lambda r:r['feature_key']) for key,records in sorted(targets.items())}

class WayNodeCollector(osmium.SimpleHandler):
    def __init__(self,targets):
        super().__init__();self.targets=targets;self.found={};self.duplicate_source_ids=[]
    def observe(self,osm_id,node_refs,tags,metadata):
        if not isinstance(osm_id,int) or isinstance(osm_id,bool) or osm_id<=0:raise TopologyError('Invalid original way ID')
        key=f'way/{osm_id}'
        if key not in self.targets:return
        if not isinstance(node_refs,list) or not all(isinstance(n,int) and not isinstance(n,bool) and n>0 for n in node_refs):
            raise TopologyError('Original way references must retain positive ordered node IDs')
        if key in self.found:
            self.duplicate_source_ids.append(key);return
        self.found[key]={'ordered_node_ids':node_refs.copy(),'source_tags':string_tags(tags),'osm_metadata':deepcopy(metadata)}
    def way(self,way):
        if f'way/{way.id}' not in self.targets:return
        stamp=str(way.timestamp)
        if stamp.startswith('1970-01-01'):stamp=None
        self.observe(int(way.id),[int(node.ref) for node in way.nodes],dict(way.tags),{
            'version':int(way.version) if way.version>0 else None,'timestamp_utc':stamp,
            'changeset':int(way.changeset) if way.changeset>0 else None,'visible':bool(way.visible)})

def scan_way_references(path,targets,expected_sha256):
    if path.is_symlink():raise TopologyError('Private PBF symlink refused')
    before=path.stat()
    if sha_file(path)!=expected_sha256:raise TopologyError('Private PBF differs from exact pinned SHA256')
    collector=WayNodeCollector(targets)
    reader=osmium.io.Reader(str(path),osmium.osm.osm_entity_bits.WAY)
    try:
        header=reader.header()
        metadata={k:header.get(k) or None for k in ('osmosis_replication_timestamp','osmosis_replication_sequence_number','generator')}
        osmium.apply(reader,collector) # No node handlers, location cache or intersections.
    finally:reader.close()
    after=path.stat()
    if (before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_ino,after.st_size,after.st_mtime_ns):
        raise TopologyError('Private PBF changed during verification/way-reference scan')
    return collector,metadata

def build_topology(targets,found,binding,provenance,*,header_metadata=None,duplicate_source_ids=()):
    ways={};nodes={};segments={};issues=[];missing=[];duplicates=sorted(set(duplicate_source_ids));matched=0
    for identifier,features in sorted(targets.items()):
        observed=found.get(identifier)
        feature_keys=[f['feature_key'] for f in features]
        base={'feature_keys':feature_keys,'canonical_feature_sha256':{f['feature_key']:f['source_feature_sha256'] for f in features}}
        if observed is None:
            missing.append(identifier);ways[identifier]={**base,'status':'unresolved_missing_source_way','ordered_node_ids':None};continue
        refs=observed['ordered_node_ids'];tags=string_tags(observed['source_tags']);local=[]
        for f in features:
            if len(refs)!=len(f['canonical_coordinates_world_xz']):
                local.append({'source_way':identifier,'feature_key':f['feature_key'],'type':'node_coordinate_count_mismatch',
                    'source_node_count':len(refs),'canonical_coordinate_count':len(f['canonical_coordinates_world_xz'])})
            for tag,value in f['canonical_tags'].items():
                if tag not in tags or tags[tag]!=value:
                    local.append({'source_way':identifier,'feature_key':f['feature_key'],'type':'canonical_tag_conflict',
                        'tag':tag,'canonical_value':value,'pbf_value':tags.get(tag),'pbf_tag_present':tag in tags})
        if identifier in duplicates:local.append({'source_way':identifier,'type':'duplicate_source_way'})
        if len(refs)<2:local.append({'source_way':identifier,'type':'fewer_than_two_original_nodes'})
        issues.extend(local)
        ways[identifier]={**base,'status':'unresolved_source_contract' if local else 'original_node_order_associated',
            'ordered_node_ids':refs.copy(),'source_tags':tags,'source_tags_sha256':sha(canonical_bytes(tags)),
            'semantic_tags':{k:tags[k] for k in SEMANTIC_TAGS if k in tags},
            'multilingual_names':{k:v for k,v in tags.items() if k=='name' or k.startswith('name:')},
            'osm_metadata':deepcopy(observed.get('osm_metadata')),
            'closed_by_node_identity':len(refs)>1 and refs[0]==refs[-1],
            'node_association_contract':'Original PBF way reference at index i pairs with unchanged canonical LineString position i. Count and shared-node consistency checked; independent source-node-location projection not checked.',
            'vehicle_routing_policy':'unassessed; original order, oneway/roundabout/access tags are not inferred legal travel arcs',
            'vertical_policy':'unassessed; bridge/tunnel/layer tags are not metric elevations'}
        if local:continue # No truncated/repaired path or partial graph accepted.
        matched+=1
        for f in features:
            coordinates=f['canonical_coordinates_world_xz']
            for index,(node_id,point) in enumerate(zip(refs,coordinates)):
                key=str(node_id)
                association={'source_way':identifier,'feature_key':f['feature_key'],'node_index':index,
                    'canonical_position_world_xz':list(point),'is_start':index==0,'is_end':index==len(refs)-1}
                if key not in nodes:
                    nodes[key]={'canonical_reference_position_world_xz':list(point),
                        'minimum_canonical_position_world_xz':list(point),'maximum_canonical_position_world_xz':list(point),'associations':[],
                        'incident_source_segments':[],'incident_source_ways':[],'endpoint_associations':[],
                        'max_axis_coordinate_delta_m':0.0,'coordinate_status':'consistent_with_canonical_rounding_allowance'}
                node=nodes[key];reference=node['canonical_reference_position_world_xz']
                low=node['minimum_canonical_position_world_xz'];high=node['maximum_canonical_position_world_xz']
                for axis in (0,1):low[axis]=min(low[axis],point[axis]);high[axis]=max(high[axis],point[axis])
                delta=max(float(high[0])-float(low[0]),float(high[1])-float(low[1]))
                node['max_axis_coordinate_delta_m']=delta
                if delta>ROUNDING_TOLERANCE_METRES+1e-12:
                    node['coordinate_status']='unresolved_shared_node_coordinate_conflict'
                    issues.append({'type':'shared_node_coordinate_conflict','node_id':node_id,
                        'source_way':identifier,'feature_key':f['feature_key'],'node_index':index,
                        'first_canonical_position_world_xz':reference.copy(),'conflicting_canonical_position_world_xz':list(point),
                        'all_association_minimum_world_xz':low.copy(),'all_association_maximum_world_xz':high.copy(),
                        'max_axis_delta_m':delta,'tolerance_m':ROUNDING_TOLERANCE_METRES})
                node['associations'].append(association)
                if index==0 or index==len(refs)-1:node['endpoint_associations'].append(association.copy())
        # Structural source segments are unique per way/index, not per role.
        # Retraces/closed-way indices survive and no coordinate-based merging occurs.
        for index,(a,b) in enumerate(zip(refs,refs[1:])):
            segment_key=f'{identifier}@{index}'
            segments[segment_key]={'source_way':identifier,'feature_keys':feature_keys,
                'from_node_id':a,'to_node_id':b,'from_node_index':index,'to_node_index':index+1,
                'legal_vehicle_direction':'unassessed; source order only'}
            for node_id in set((a,b)):nodes[str(node_id)]['incident_source_segments'].append(segment_key)
        for node_id in set(refs):nodes[str(node_id)]['incident_source_ways'].append(identifier)
    for node in nodes.values():
        node['associations'].sort(key=lambda a:(a['source_way'],a['feature_key'],a['node_index']))
        node['endpoint_associations'].sort(key=lambda a:(a['source_way'],a['feature_key'],a['node_index']))
        node['incident_source_segments'].sort();node['incident_source_ways'].sort()
    # Structural neighbours preserve explicit node identity only. This is an
    # undirected incidence view, not an access/oneway-aware route graph.
    for key,node in nodes.items():
        node_id=int(key);neighbors=[]
        for segment_key in node['incident_source_segments']:
            segment=segments[segment_key]
            other=segment['to_node_id'] if segment['from_node_id']==node_id else segment['from_node_id']
            neighbors.append(other)
        node['source_neighbor_node_ids']=sorted(set(neighbors))
    coordinate_conflicts={i['node_id'] for i in issues if i['type']=='shared_node_coordinate_conflict'}
    affected_ways={a['source_way'] for key in coordinate_conflicts for a in nodes[str(key)]['associations']}
    for identifier in affected_ways:ways[identifier]['status']='unresolved_shared_node_coordinate_conflict'
    header_metadata=deepcopy(header_metadata or {})
    header_time=header_metadata.get('osmosis_replication_timestamp')
    header_conflict=header_time is not None and header_time!=binding.get('source_snapshot_utc')
    ready=not issues and not missing and not duplicates and not header_conflict
    return {'schema':SCHEMA,'binding':deepcopy(binding),'source_attribution':deepcopy(provenance),
        'pbf_header_metadata':header_metadata,'ways':ways,'nodes':dict(sorted(nodes.items(),key=lambda pair:int(pair[0]))),
        'source_segments':dict(sorted(segments.items())),
        'audit':{'ready_for_source_identity_topology':ready,'requested_source_ways':len(targets),
            'found_source_ways':len(ways)-len(missing),'matched_count_tag_contract_ways':matched,
            'missing_source_ways':missing,'duplicate_source_ways':duplicates,'issues':issues,
            'header_snapshot_time_conflict':header_conflict,
            'unique_source_nodes':len(nodes),'ordered_node_associations':sum(len(n['associations']) for n in nodes.values()),
            'source_segments':len(segments),'shared_between_source_ways_nodes':sum(len(n['incident_source_ways'])>1 for n in nodes.values()),
            'closed_source_ways':sum(w.get('closed_by_node_identity',False) for w in ways.values()),
            'source_node_locations_independently_projected':False,'canonical_rounding_allowance_per_axis_m':ROUNDING_TOLERANCE_METRES,
            'full_source_tag_keys':dict(sorted(Counter(k for w in ways.values() for k in w.get('source_tags',{})).items()))},
        'contract':{'canonical_v1_changed':False,'geometry_changed':False,'connect_by_xy_intersection':False,
            'connect_by_equal_coordinates':False,'original_order_preserved':True,
            'logical_roles_do_not_duplicate_source_segments':True,'routable_vehicle_classification':'unassessed',
            'road_width_speed_permission_inference':False,'terrain_or_vertical_profile_inferred':False,
            'consumer_rule':'Verify every bound hash and require ready_for_source_identity_topology before consuming incidence. Preserve kind/feature keys and source node indices. Incidence is not legal vehicle routing.'},
        'limitations':['Regional source-node incidence only; not whole-Singapore migration or visual/gameplay acceptance.',
            'No source-node coordinates were read; independent original-coordinate projection/order validation remains unverified for isolated ways. Count and shared-node checks cannot prove every coordinate association by themselves.',
            'Identical XY or geometric crossings with different source node IDs are intentionally not connected.',
            'Shared source node IDs establish source incidence, not independently surveyed grade, permission or vehicle manoeuvre validity.',
            'No road widths, speeds, access permissions, metric bridge/tunnel levels, terrain heights or lane geometry are inferred.']}

class SourceNodeCollector(osmium.SimpleHandler):
    def __init__(self,target_node_ids):
        super().__init__();self.targets=set(target_node_ids);self.found={};self.duplicate_source_ids=[]
    def observe(self,node_id,lon,lat,tags,metadata):
        if not isinstance(node_id,int) or isinstance(node_id,bool) or node_id<=0:raise TopologyError('Invalid original node ID')
        if node_id not in self.targets:return
        if node_id in self.found:
            self.duplicate_source_ids.append(node_id);return
        valid=all(isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v) for v in (lon,lat))
        valid=valid and -180<=lon<=180 and -90<=lat<=90
        self.found[node_id]={'source_wgs84_lon_lat':[lon,lat] if valid else None,
            'source_coordinate_status':'valid_source_location' if valid else 'unresolved_invalid_source_location',
            'source_tags':string_tags(tags),'osm_metadata':deepcopy(metadata)}
    def node(self,node):
        if node.id not in self.targets:return
        valid=node.location.valid()
        stamp=str(node.timestamp)
        if stamp.startswith('1970-01-01'):stamp=None
        self.observe(int(node.id),node.location.lon if valid else None,node.location.lat if valid else None,
            dict(node.tags),{'version':int(node.version) if node.version>0 else None,'timestamp_utc':stamp,
                'changeset':int(node.changeset) if node.changeset>0 else None,'visible':bool(node.visible)})

def scan_source_nodes(path,target_node_ids,expected_sha256):
    if path.is_symlink():raise TopologyError('Private PBF symlink refused')
    before=path.stat()
    if sha_file(path)!=expected_sha256:raise TopologyError('Private PBF differs from exact pinned SHA256')
    collector=SourceNodeCollector(target_node_ids)
    reader=osmium.io.Reader(str(path),osmium.osm.osm_entity_bits.NODE)
    try:
        header=reader.header()
        metadata={k:header.get(k) or None for k in ('osmosis_replication_timestamp','osmosis_replication_sequence_number','generator')}
        # C++ ID filtering prevents Python callbacks/retention for all other
        # source nodes. No full source location cache is constructed.
        osmium.apply(reader,osmium.filter.IdFilter(sorted(target_node_ids)),collector)
    finally:reader.close()
    after=path.stat()
    if (before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_ino,after.st_size,after.st_mtime_ns):
        raise TopologyError('Private PBF changed during selected-node scan')
    return collector,metadata

def verify_original_node_coordinates(original,found,*,predecessor_sha256,node_header_metadata=None,duplicate_source_ids=()):
    if original.get('schema')!=SCHEMA:raise TopologyError('Node audit requires an original bound v1 topology')
    if not isinstance(predecessor_sha256,str) or len(predecessor_sha256)!=64 or any(c not in '0123456789abcdef' for c in predecessor_sha256):
        raise TopologyError('Node audit requires exact predecessor SHA256')
    result=deepcopy(original);missing=[];invalid=[];mismatches=[];checked=0;max_error=0.0
    duplicates=sorted(set(duplicate_source_ids));failed_nodes=set(duplicates)
    target_ids={n for w in result['ways'].values() for n in (w.get('ordered_node_ids') or [])}
    if target_ids!={int(k) for k in result['nodes']}:raise TopologyError('Original topology node inventory is incomplete')
    for node_id in sorted(target_ids):
        entry=result['nodes'][str(node_id)];observed=found.get(node_id)
        if observed is None:
            missing.append(node_id);failed_nodes.add(node_id)
            entry['source_node']={'status':'unresolved_missing_source_node'};continue
        source=deepcopy(observed);entry['source_node']=source
        source['source_tags_sha256']=sha(canonical_bytes(source['source_tags']))
        if source.get('source_coordinate_status')!='valid_source_location':
            invalid.append(node_id);failed_nodes.add(node_id);source['status']='unresolved_invalid_source_node';continue
        try:
            projected=georeference.from_wgs84(*source['source_wgs84_lon_lat'])
            valid_projection=all(math.isfinite(v) for v in projected)
        except Exception:valid_projection=False
        if not valid_projection:
            invalid.append(node_id);failed_nodes.add(node_id);source['status']='unresolved_invalid_projection';continue
        source['projected_world_xz']=[projected[0],projected[2]]
        local_max=0.0
        for association in entry['associations']:
            point=association['canonical_position_world_xz'];checked+=1
            error=max(abs(projected[0]-point[0]),abs(projected[2]-point[1]));max_error=max(max_error,error);local_max=max(local_max,error)
            if error>ROUNDING_TOLERANCE_METRES+1e-12:
                failed_nodes.add(node_id)
                mismatches.append({'node_id':node_id,'source_way':association['source_way'],'feature_key':association['feature_key'],
                    'node_index':association['node_index'],'canonical_position_world_xz':point,
                    'source_projected_world_xz':[projected[0],projected[2]],'maximum_axis_error_m':error,
                    'tolerance_m':ROUNDING_TOLERANCE_METRES})
        source['maximum_axis_coordinate_error_m']=local_max
        source['status']='unresolved_coordinate_or_duplicate_conflict' if node_id in failed_nodes else 'source_projection_matches_all_ordered_associations'
    header=deepcopy(node_header_metadata or {})
    snapshot=header.get('osmosis_replication_timestamp')
    header_conflict=snapshot is not None and snapshot!=result['binding'].get('source_snapshot_utc')
    # If both scans retain header metadata, they must come from the same source.
    source_header_conflict=bool(header and original.get('pbf_header_metadata') and header!=original['pbf_header_metadata'])
    original_ready=bool(result['audit'].get('ready_for_source_identity_topology'))
    independently_verified=not missing and not invalid and not mismatches and not duplicates and not header_conflict and not source_header_conflict
    ready=original_ready and independently_verified
    for way in result['ways'].values():
        if any(node_id in failed_nodes for node_id in (way.get('ordered_node_ids') or [])):
            way['status']='unresolved_source_node_projection_or_order'
        elif ready:way['status']='original_node_order_and_projected_coordinates_verified'
        way['node_association_contract']='Original node reference index i is compared with canonical LineString index i using independently projected original node longitude/latitude; see global/per-node validation status. No vertical profile is inferred.'
    result['schema']=VERIFIED_SCHEMA
    result['binding']['predecessor_topology_sha256']=predecessor_sha256
    result['node_scan_pbf_header_metadata']=header
    result['node_coordinate_validation']={'requested_source_nodes':len(target_ids),'found_source_nodes':len(target_ids)-len(missing),
        'ordered_associations_checked':checked,'missing_source_node_ids':missing,'invalid_source_node_ids':invalid,
        'duplicate_source_node_ids':duplicates,'coordinate_mismatches':mismatches,'maximum_axis_error_m':max_error,
        'rounding_tolerance_per_axis_m':ROUNDING_TOLERANCE_METRES,'projection_frame':georeference.manifest(),
        'projection_implementation_sha256':sha(Path(georeference.__file__).read_bytes()),
        'source_header_conflict':source_header_conflict,'snapshot_time_conflict':header_conflict,
        'source_node_tags_preserved':True,'elevation_inferred_from_tags':False}
    result['audit']['ready_for_source_identity_topology']=ready
    result['audit']['source_node_locations_independently_projected']=independently_verified
    result['audit']['source_node_coordinate_order_validation_passed']=independently_verified
    result['audit']['node_validation_issue_count']=len(missing)+len(invalid)+len(duplicates)+len(mismatches)+int(header_conflict)+int(source_header_conflict)
    result['contract']['source_order_and_coordinate_projection_verified']=independently_verified
    result['predecessor_limitations']=result['limitations']
    result['limitations']=[
        'Regional original-node incidence/2D projection only; not whole-Singapore migration or visual/gameplay acceptance.',
        'Every selected ordered canonical coordinate is compared to its original source node; source survey accuracy itself is not independently certified.',
        'Whole selected ways extend outside the requested patch; incidence of other unselected outside ways is not country-complete.',
        'Identical XY or geometric crossings with different source node IDs remain intentionally unconnected.',
        'Shared-node incidence does not establish legal vehicle travel, permissions, surveyed grade, lane geometry or bridge/tunnel elevations.',
        'Original node tags including crossings/signals/kerbs/ele remain string facts; no elevation, widths, speeds or driving policy is inferred.']
    return result

def write_topology(output,doc):
    if output.exists():raise TopologyError('Refusing to overwrite prior topology evidence')
    output.parent.mkdir(parents=True,exist_ok=True);data=canonical_bytes(doc)
    with output.open('xb') as f:f.write(data)
    receipt={'schema':doc['schema'],'sha256':sha(data),'bytes':len(data),**{k:doc['audit'][k] for k in (
        'ready_for_source_identity_topology','requested_source_ways','found_source_ways','unique_source_nodes',
        'ordered_node_associations','source_segments','shared_between_source_ways_nodes','closed_source_ways')},
        'issues':len(doc['audit']['issues']),'missing_source_ways':len(doc['audit']['missing_source_ways'])}
    if 'node_coordinate_validation' in doc:
        validation=doc['node_coordinate_validation']
        receipt.update({'source_node_locations_independently_projected':doc['audit']['source_node_locations_independently_projected'],
            'source_nodes_checked':validation['found_source_nodes'],'ordered_associations_checked':validation['ordered_associations_checked'],
            'maximum_axis_projection_error_m':validation['maximum_axis_error_m'],
            'node_validation_issues':doc['audit']['node_validation_issue_count']})
    return receipt

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pbf',type=Path,required=True);p.add_argument('--expected-pbf-sha256',required=True)
    p.add_argument('--catalog',type=Path,required=True);p.add_argument('--patch-manifest',type=Path,required=True)
    p.add_argument('--snapshot-manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--verify-topology',type=Path);p.add_argument('--expected-topology-sha256')
    args=p.parse_args();started=time.monotonic()
    try:
        _,binding,provenance=input_binding(args.catalog,args.patch_manifest,args.snapshot_manifest,args.expected_pbf_sha256)
        catalog,_=read_json(args.catalog);targets=select_targets(catalog)
        binding['selected_semantic_kinds']=['road'];binding['selected_source_ways']=len(targets)
        binding['selected_logical_features']=sum(len(v) for v in targets.values())
        if args.verify_topology is not None:
            predecessor,raw=read_json(args.verify_topology)
            if args.expected_topology_sha256 is None or sha(raw)!=args.expected_topology_sha256:
                raise TopologyError('Predecessor topology differs from explicitly pinned SHA256')
            if predecessor.get('schema')!=SCHEMA or any(predecessor.get('binding',{}).get(k)!=v for k,v in binding.items()):
                raise TopologyError('Predecessor topology differs from bound catalog/PBF/snapshot selection')
            if set(predecessor.get('ways',{}))!=set(targets):raise TopologyError('Predecessor source-way inventory mismatch')
            snapshot,_=read_json(args.snapshot_manifest)
            if snapshot.get('georeference')!=georeference.manifest():raise TopologyError('Current projection differs from canonical snapshot frame')
            node_ids={n for way in predecessor['ways'].values() for n in (way.get('ordered_node_ids') or [])}
            collector,header=scan_source_nodes(args.pbf,node_ids,args.expected_pbf_sha256)
            doc=verify_original_node_coordinates(predecessor,collector.found,predecessor_sha256=sha(raw),
                node_header_metadata=header,duplicate_source_ids=collector.duplicate_source_ids)
        else:
            collector,header=scan_way_references(args.pbf,targets,args.expected_pbf_sha256)
            doc=build_topology(targets,collector.found,binding,provenance,header_metadata=header,duplicate_source_ids=collector.duplicate_source_ids)
        report=write_topology(args.output,doc);report['scan_and_verify_seconds']=round(time.monotonic()-started,3)
        print(json.dumps(report,sort_keys=True),flush=True)
        return 0 if report['ready_for_source_identity_topology'] else 1
    except (TopologyError,EnrichmentError) as e:
        print(json.dumps({'status':'failed','reason':str(e)}),flush=True);return 2
    except Exception:
        print(json.dumps({'status':'failed','reason':'Input I/O, JSON or PBF parser failure; no private input path emitted'}),flush=True);return 2

if __name__=='__main__':raise SystemExit(main())
