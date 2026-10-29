"""Full-size Premier layout contracts + conservative 2D capsule circulation.

Every size is actual furniture geometry, not a scaling-to-fit operation. This
adds a new reconstruction layout; no old factory or active game is modified.
Native vertical/door/controller/render checks remain required.
"""
from __future__ import annotations
import math,heapq,json,collections,time
from pathlib import Path
RADIUS=.38 # Production .36 capsule plus .02 planning margin.
WALL=.15

def build(width,depth,variant='king'):
 w=float(width);d=float(depth);objects=[];walls=[];doors=[]
 def box(id,cx,cz,sx,sz,kind='furniture',height=1.0):
  out={'id':id,'kind':kind,'center_uv':[cx,cz],'size_xyz_m':[sx,height,sz],'rect':[cx-sx/2,cz-sz/2,cx+sx/2,cz+sz/2],'scale':1.0};objects.append(out);return out
 def wall(id,a,b):walls.append({'id':id,'rect':[a[0],a[1],b[0],b[1]],'height_m':3.08,'thickness_m':WALL})
 narrow=w<4.8
 offset=1.5 if narrow else 0.0
 bath_width=min(3.2,w-1.0);left=w-bath_width
 # Full original tub/vanity/WC dimensions remain constant even in the narrow
 # vestibule layout. The bathroom's footprint, not its fixtures, is rearranged.
 door_z=offset+1.40
 wall('bath-front',(left,offset-WALL/2),(w,offset+WALL/2)) if offset else None
 wall('bath-back',(left,offset+2.8-WALL/2),(w,offset+2.8+WALL/2))
 wall('bath-side-low',(left-WALL/2,offset),(left+WALL/2,door_z-.56))
 wall('bath-side-high',(left-WALL/2,door_z+.56),(left+WALL/2,offset+2.8))
 doors.append({'id':'bath','kind':'guarded_paired_pocket_door','width_m':1.12,'height_m':2.35,'opening_center_uv':[left,door_z],'normal_uv':[1,0],'leaf_count':2,'each_leaf_width_m':.56,'leaf_thickness_m':.075,'each_leaf_travel_m':.60,'partition_thickness_m':.15,'pocket_skin_thickness_m':.025,'open_leaf_intervals_v':[[door_z-1.16,door_z-.60],[door_z+.60,door_z+1.16]],'pockets_within_original_bath_side_partition':True,'static_partition_requires_two_skins_around_leaf_cavity':True,'existing_motion_base':'res://src/world/mbs_interior/cabins.gd::_gate_center/_publish_transforms (adapt existing paired linear gate)','open_state_used_for_this_static_audit':True,'native_actuator_not_implemented':True})
 box('tub',left+1.0,offset+2.25,1.80,.90,height=.64)
 box('double-vanity',left+1.024,offset+.42,1.664,.65,height=.86)
 box('wc',w-.42,offset+2.30,.55,.72,height=.68)
 box('shower-glass',w-.70,offset+.85,.04,.80,height=2.4)
 bath_target=[left+1.30,door_z]
 if variant=='twin_queen':
  if w<5.2-1e-8 or d<6.2-1e-8:return {'valid':False,'error':'Full twin furniture needs the declared5.2m/6.2m layout domain.'}
  for i,x in enumerate([1.20,w-1.20]):box('queen-bed-'+str(i+1),x,d-1.30,1.96,2.375,height=1.5)
  wardrobe_z=2.2 if d<7.2 else 3.5
  box('wardrobe',.425,wardrobe_z,.64,1.40,height=2.2)
  desk_x=min(2.8,left-.8) if d<7.2 else w-.8;desk_z=.60 if d<7.2 else 3.4
  box('desk',desk_x,desk_z,1.20,.60,height=.81)
  sleep_target=[w/2,d-.80];wardrobe_target=[1.20,wardrobe_z];desk_target=[desk_x,1.40] if d<7.2 else [w-2.0,3.4]
  routes={'sleeping-between-beds':sleep_target,'wardrobe-front':wardrobe_target,'desk-front':desk_target}
 else:
  if w<3.75-1e-8 or d<6.2-1e-8:return {'valid':False,'error':'Outside full-size king layout domain.'}
  if narrow:
   bed_x=w-.15-1.28;box('king-bed',bed_x,d-1.30,2.56,2.375,height=1.5)
   box('wardrobe',w-.425,5.1,.64,1.40,height=2.2)
   desk_z=min(7.0,d-2.95)
   box('desk',w-.80,desk_z,1.20,.60,height=.81)
   box('sofa',max(1.75,w*.43),d-3.8,1.65,.82,height=.88)
   routes={'sleeping-window-aisle':[(.075+bed_x-1.28)/2,d-.80],'wardrobe-front':[w-1.30,5.1],'desk-front':([w-1.82,desk_z] if d<10.0 else [w-.80,desk_z-.8]),'living-sofa':[.50,d-3.8]}
  else:
   bed_x=w*.55;box('king-bed',bed_x,d-1.30,2.56,2.375,height=1.5)
   box('wardrobe',.425,3.5,.64,1.40,height=2.2)
   desk_z=d-.70 if d<7.0 else 3.40
   box('desk',w-.80,desk_z,1.20,.60,height=.81)
   desk_point=[w-.80,d-1.50] if d<7.0 else [w-2.0,3.4]
   routes={'sleeping-left-aisle':[(.075+bed_x-1.28)/2,d-.80],'sleeping-right-aisle':[(bed_x+1.28+w-.075)/2,d-1.80 if d<7 else d-.80],'wardrobe-front':[1.2,3.5],'desk-front':desk_point}
 routes['bath-entry']=bath_target
 return {'valid':True,'schema':'mbs_premier_fullsize_fitout_v3','room_dimensions_m':[w,d],'bed_variant':variant,'furniture':objects,'partitions':walls,'doorways':doors,'entry_inside_uv':[.85,.80],'named_routes':routes,'capsule_radius_with_margin_m':RADIUS,'geometry_not_native_or_visual_acceptance':True,'layout_status':'SOURCE_AREA_TARGETED_PRIVATE_RECONSTRUCTION_NOT_ASBUILT'}

def overlap(a,b):return min(a[2],b[2])-max(a[0],b[0])>1e-8 and min(a[3],b[3])-max(a[1],b[1])>1e-8

def audit(contract):
 if not contract.get('valid'):return {'passed':False,'failures':[contract.get('error','invalid')],'routes':{}}
 w,d=contract['room_dimensions_m'];rects=[o['rect'] for o in contract['furniture']]+[p['rect'] for p in contract['partitions']];fail=[]
 for i,a in enumerate(contract['furniture']):
  b=a['rect']
  if b[0]<.075-1e-8 or b[1]<.075-1e-8 or b[2]>w-.075+1e-8 or b[3]>d-.075+1e-8:fail.append('furniture outside interior: '+a['id'])
  for other in contract['furniture'][i+1:]:
   if overlap(b,other['rect']):fail.append('furniture overlap: '+a['id']+' / '+other['id'])
  for other in contract['partitions']:
   if overlap(b,other['rect']):fail.append('partition overlap: '+a['id']+' / '+other['id'])
 expanded=[[a-RADIUS,b-RADIUS,c+RADIUS,e+RADIUS] for a,b,c,e in rects]
 def clear(x,z):return .075+RADIUS<=x<=w-.075-RADIUS and .075+RADIUS<=z<=d-.075-RADIUS and not any(a<x<c and b<z<e for a,b,c,e in expanded)
 step=.05; start=contract['entry_inside_uv'];s=(round(start[0]/step),round(start[1]/step));queue=collections.deque([s]);visited={s};parent={}
 if not clear(s[0]*step,s[1]*step):fail.append('entry capsule blocked');queue.clear()
 while queue:
  x,z=queue.popleft()
  for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]:
   q=(x+dx,z+dz)
   if q in visited:continue
   if clear(q[0]*step,q[1]*step):visited.add(q);parent[q]=(x,z);queue.append(q)
 results={}
 for label,p in contract['named_routes'].items():
  q=(round(p[0]/step),round(p[1]/step));reachable=q in visited;results[label]={'target_uv':p,'reachable_in_conservative_open_door_fixture':reachable}
  if not reachable:fail.append('full capsule route blocked: '+label)
 return {'passed':not fail,'failures':fail,'routes':results,'reachable_grid_nodes':len(visited),'grid_step_m':step,'continuous_axis_moves_with_expanded_obstacles':True,'native_door_or_furniture_mesh_or_controller_verified':False}

if __name__=='__main__':
 tests=[(3.75,12.0,'king'),(4.2,11.0,'king'),(4.5,10.0,'king'),(5.5,8.2,'king'),(7.25,6.21,'king'),(5.2,8.7,'twin_queen'),(5.625,8.0,'twin_queen'),(6.25,7.2,'twin_queen')];out=[]
 for args in tests:
  c=build(*args);r=audit(c);out.append({'dimensions':args,'contract':c,'audit':r});print(args,r['passed'],r['failures'])
 Path(__file__).with_name('PREMIER_FITOUT_V3_PROTOTYPE.json').write_text(json.dumps({'scope':'Fullsize static rectangle and conservative open-door capsule planning only','cases':out},indent=2)+'\n')
