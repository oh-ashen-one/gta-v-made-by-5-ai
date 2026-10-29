#!/usr/bin/env python3
"""Independent source/inventory arithmetic. Does not load Godot or verify RIDs."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,math
root=Path(__file__).resolve().parents[3]
raw=(root/'game/data/mbs-interior/inventory.json').read_bytes()
data=json.loads(raw)
text=(root/'game/src/world/mbs_interior/site_reference.gd').read_text()
reference=json.JSONDecoder().raw_decode(text.split('const DATA := ',1)[1])[0]
axes=(reference['axis_south_xz'],reference['axis_bayward_xz'])
x,z=axes
assert abs(sum(v*v for v in x)-1)<1e-12
assert abs(sum(v*v for v in z)-1)<1e-12
assert abs(x[0]*z[0]+x[1]*z[1])<1e-12
assert abs(x[0]*z[1]-x[1]*z[0]-1)<1e-12
records={r['id']:r for r in data['hotel_floors']}
origin=[reference['towers'][1]['centroid_world_xz'][0],records['T2-L24']['elevation_m'],reference['towers'][1]['centroid_world_xz'][1]]
rows=[];unsupported=[];neighbours={}
for tower in reference['towers']:
 ordered=sorted((r for r in data['hotel_floors'] if r['tower']==tower['tower']),key=lambda r:r['elevation_m'])
 for index,record in enumerate(ordered):
  anchor=[tower['centroid_world_xz'][0],record['elevation_m'],tower['centroid_world_xz'][1]]
  projected=[anchor[i]-origin[i] for i in range(3)]
  assert all(abs(v)<2048 for v in projected)
  assert max(abs(projected[i]+origin[i]-anchor[i]) for i in range(3))<1e-12
  near=[r['id'] for r in ordered[max(0,index-1):min(len(ordered),index+2)] if r['id']!=record['id']]
  neighbours[record['id']]=near
  rise=None
  if index+1<len(ordered):
   rise=ordered[index+1]['elevation_m']-record['elevation_m']
   assert rise>0
   if record['geometry']['clear_height_m']+.20>rise+1e-5:
    unsupported.append({'floor_id':record['id'],'upper_floor_id':ordered[index+1]['id'],'actual_inventory_rise_m':rise,'required_clear_height_plus_slab_m':record['geometry']['clear_height_m']+.20,'resolution':'TRANSIENT_ROOT_PARTIAL_MEZZANINE_VERTICAL_ZONES_NOT_EMPTY_FLOOR'})
  rows.append({'floor_id':record['id'],'source_tower_id':tower['id'],'canonical_anchor_xyz':anchor,'projected_local_xyz':projected,'copied_next_stair_rise_m':rise,'has_upper_floor':rise is not None,'neighbours':near})
assert len(rows)==189
assert len(unsupported)==6
result={'created_utc':datetime.now(timezone.utc).isoformat(),'method':'PYTHON_DOUBLE_SOURCE_AND_INVENTORY_ARITHMETIC_ONLY_NOT_ENGINE_QA','module_sha256':hashlib.sha256((root/'game/src/world/mbs_interior/floor_stack.gd').read_bytes()).hexdigest(),'inventory_sha256':hashlib.sha256(raw).hexdigest(),'actual_tower_source_ids':[t['id'] for t in reference['towers']],'common_source_axes_double':axes,'test_origin_xyz':origin,'hotel_floor_count':len(rows),'resort_records_require_explicit_source_mapping':len(data['resort_program_floors']),'incompatible_mezzanine_recipe_rows':unsupported,'target_neighbour_sets':{k:neighbours[k] for k in ['T2-L24','T2-L25','T3-L24']},'placements':rows,'engine_compile_verified':False,'native_runtime_verified':False,'origin_commits_performed':0,'actor_pose_mutations':0,'full_building_completed':False}
Path(__file__).with_name('STATIC_SOURCE_GEOMETRY.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['placements','common_source_axes_double']}))
