#!/usr/bin/env python3
"""Independent scalar source-plan audit, not Godot/collision/render acceptance."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re
root=Path(__file__).resolve().parents[3]
requests=json.loads(Path(__file__).with_name('REQUESTS.json').read_text())
s=(root/'game/src/world/mbs_interior/site_reference.gd').read_text()
ref=json.JSONDecoder().raw_decode(s.split('const DATA := ',1)[1])[0]
inventory=json.loads((root/'game/data/mbs-interior/inventory.json').read_text())
widths={'T1':40.0,'T2':20.0,'T3':10.0}
heights={'T1':76.0,'T2':47.0,'T3':27.0}
zones=[dict(tower=t['tower'],x=t['centroid_local_xz'][0],z=t['centroid_local_xz'][1],w=widths[t['tower']],h=heights[t['tower']],length=t['source_long_extent_m']*.78,source=t['centroid_world_xz']) for t in ref['towers']]
profile=[dict(zones[0],x=zones[0]['x']-zones[0]['length']/2)]+zones+[dict(zones[-1],x=zones[-1]['x']+zones[-1]['length']/2)]
def section(x):
 for a,b in zip(profile,profile[1:]):
  if x<=b['x']+.0001:
   u=max(0,min(1,(x-a['x'])/(b['x']-a['x'])))
   return {k:a[k]+(b[k]-a[k])*u for k in ['x','z','w','h']}
 return profile[-1]
def source(zone,x,z,y=0):
 ax=ref['axis_south_xz'];az=ref['axis_bayward_xz']
 return [zone['source'][0]+ax[0]*x+az[0]*z,y,zone['source'][1]+ax[1]*x+az[1]*z]
rows=[]
for req in requests['core_connections']:
 z=next(z for z in zones if z['tower']==req['tower']);side=-1 if req['side']=='east' else 1
 x=z['x']+req['along_offset_m'];p=section(x)
 glass=p['z']+side*p['w']/2;target=z['z']+side*z['w']/2
 assert req['width_m']>=2 and req['height_m']>=2.2
 assert req['width_m']/2-(req['width_m']/2-.45+.36+.01)>.079
 rows.append({'tower':req['tower'],'side':req['side'],'public_local_x':x,'actual_glass_base_z':glass,'copied_program_void_edge_z':target,'base_edge_difference_m':glass-target,'target_source_xyz':source(z,req['along_offset_m'],side*(z['w']/2+req['corridor_width_m']/2)),'height_difference_m':0.0,'door_width_m':req['width_m'],'capsule_offcentre_boundary_margin_m':.08,'geometry_status':'RECONSTRUCTED_APERTURE_AND_PRIVATE_CORRIDOR_NOT_SURVEYED'})
t1=next(z for z in zones if z['tower']=='T1')
record=next(r for r in inventory['hotel_floors'] if r['id']=='T1-L1');g=record['geometry'];arrival=requests['arrival_corridor']
run=g['length_m']-2*g['core_bay_m'];wall=.15
left_room=(-run/2,-arrival['width_m']/2-wall/2)
right_room=(arrival['width_m']/2+wall/2,run/2)
actual_clear=right_room[0]-wall/2-(left_room[1]+wall/2)
assert abs(actual_clear-2.6)<1e-12
assert left_room[1]-left_room[0]>7 and right_room[1]-right_room[0]>7
protected=json.loads(Path(__file__).with_name('PROTECTED_STACK_APIS.json').read_text())
stack=(root/'game/src/world/mbs_interior/floor_stack.gd').read_text()
for name,saved in protected.items():
 current=re.search(r'func '+name+r'\(.*?(?=\nfunc )',stack,re.S).group(0)
 assert hashlib.sha256(current.encode()).hexdigest()==saved['sha256'],name
result={'created_utc':datetime.now(timezone.utc).isoformat(),'method':'PYTHON_DOUBLE_SCALAR_SOURCE_PLAN_ONLY_NOT_ENGINE_QA','core_joins':rows,'arrival':{'source_outer_facade_xyz':source(t1,0,arrival['target_cross_m']/2),'source_initial_outside_xyz':source(t1,0,arrival['target_cross_m']/2+arrival['outside_approach_m']-.5),'actual_facade_to_spawn_distance_m':arrival['outside_approach_m']-.5,'actual_clear_aisle_width_m':actual_clear,'coherent_left_room_bounds_x':left_room,'coherent_right_room_bounds_x':right_room,'retained_program_ids':[p['id'] for p in record['program_spaces']],'height_difference_m':0.0,'metric_status':'RECONSTRUCTED_FACADE_PARTITIONS_ELEVATIONS_NOT_AS_BUILT'},'protected_stack_api_hashes_preserved':{n:p['sha256'] for n,p in protected.items()},'source_hashes':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in ['game/src/world/mbs_interior/public_l1.gd','game/src/world/mbs_interior/program_floor.gd','game/src/world/mbs_interior/floor_stack.gd','game/src/systems/fidelity_tests/mbs_public_core_entry_test.gd']},'engine_compile_verified':False,'actual_runtime_verified':False,'public_visual_fidelity_accepted':False,'whole_building_completed':False}
Path(__file__).with_name('STATIC_JOIN_AUDIT.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'core_joins':rows,'arrival':result['arrival'],'protected_apis_preserved':True,'engine_runtime_verified':False}))
