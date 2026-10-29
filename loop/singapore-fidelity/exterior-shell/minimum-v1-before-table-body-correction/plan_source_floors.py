"""Bounded authoring compiler for source-conforming hotel allocation.

Retains every inventory room identity/type/bedroom count; reports each explicit
reconstruction resize and physical-floor reassignment. Never writes inventory.
"""
from __future__ import annotations
import json,math,hashlib,importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('core_audit',Path(__file__).with_name('audit_core_layout.py')); geom=importlib.util.module_from_spec(spec);spec.loader.exec_module(geom)
REF=geom.const(ROOT/'game/src/world/mbs_interior/site_reference.gd','DATA')
AXES=geom.const(ROOT/'game/src/world/mbs_interior/exterior_shell.gd','AXES')
BANKS=geom.const(ROOT/'game/src/world/mbs_interior/source_core_layout.gd','BANK_CENTRES')
VOIDS=geom.const(ROOT/'game/src/world/mbs_interior/source_core_layout.gd','OWN_ATRIUM_INTERVALS')
VOID_TOP={'T1':76.0,'T2':47.0,'T3':27.0}
INV=json.loads((ROOT/'game/data/mbs-interior/inventory.json').read_text())


def ground_ring(tower):
 s=next(t for t in REF['towers'] if t['tower']==tower); c=s['centroid_world_xz'];u=REF['axis_south_xz'];v=REF['axis_bayward_xz'];a=AXES[tower];ring=[]
 for q in s['footprint_rings_world_xz'][0]:
  dx=q[0]-c[0];dz=q[1]-c[1];x=dx*u[0]+dz*u[1];z=dx*v[0]+dz*v[1];ring.append([x*a['south'][0]+z*a['south'][1],x*a['bayward'][0]+z*a['bayward'][1]])
 if ring[0]==ring[-1]:ring.pop()
 return ring

def profile(tower,y):
 ring=ground_ring(tower);b=geom.axis_bounds(ring);t=max(0,min(1,y/77.45));scale=1+(30/(b[3]-b[1])-1)*t*(2-t)
 return [[x,b[3]+(z-b[3])*scale] for x,z in ring]

def cross_section(poly,z):
 xs=[]
 for a,b in zip(poly,poly[1:]+poly[:1]):
  if (a[1]<=z<b[1]) or (b[1]<=z<a[1]):xs.append(a[0]+(b[0]-a[0])*(z-a[1])/(b[1]-a[1]))
 xs.sort()
 return [xs[i:i+2] for i in range(0,len(xs)-1,2)]

def strip_span(polys,z0,z1):
 feasible=[[-1e9,1e9]]
 for poly in polys:
  values=[z0+1e-8,z1-1e-8]
  for p in poly:
   if z0<p[1]<z1:values.extend([max(z0+1e-9,p[1]-1e-8),min(z1-1e-9,p[1]+1e-8)])
  for z in values:
   spans=cross_section(poly,z);next_spans=[]
   for a,b in feasible:
    for c,d in spans:
     lo=max(a,c);hi=min(b,d)
     if hi-lo>.000001:next_spans.append([lo,hi])
   feasible=next_spans
   if not feasible:return None
 if not feasible:return None
 lo,hi=max(feasible,key=lambda q:q[1]-q[0])
 return [lo+.30,hi-.30] if hi-lo>.60 else None

def cut(spans,a,b):
 result=[]
 for lo,hi in spans:
  if hi<=a or lo>=b:result.append([lo,hi]);continue
  if lo<a:result.append([lo,a])
  if hi>b:result.append([b,hi])
 return result

def room_profile(unit):
 # Explicit new construction dimensions; retain full king/twin mattresses,
 # bathroom, desk, wardrobes, suite social/bedroom program and clear passages.
 if unit['is_suite']:
  if unit['entertainment']=='billiards':return {'frontage_m':{1:10.0,2:13.8,3:17.6}[unit['bedrooms']],'depth_m':9.2,'living_width_m':6.0,'furnishing_profile':'full_billiards_suite_v3','billiards_table_xz_m':[2.54,1.27],'cue_clearance_each_side_m':1.45,'full_cue_rectangle_xz_m':[5.44,4.17]}
  return {'frontage_m':{1:7.4,2:12.2,3:17.0}[unit['bedrooms']],'depth_m':8.0,'furnishing_profile':'retained_full_suite_program_v2','media_program_required':unit['entertainment']=='media'}
 return {'frontage_m':7.2 if unit['bed_variant']=='twin_queen' else 6.0,'depth_m':7.0,'furnishing_profile':'retained_full_premier_program_v2'}

def legacy_dimensions(unit):
 record=next(f for f in INV['hotel_floors'] if f['id']==unit['floor_id']);g=record['geometry'];same=[u for u in record['units'] if u['wing']==unit['wing']];side=-1 if unit['wing']=='east' else 1
 inner=g['void_min_z_m'] if side<0 else g['void_max_z_m'];front=(g['length_m']-2*g['core_bay_m'])*unit['frontage_weight']/sum(u['frontage_weight'] for u in same);depth=abs(side*g['cross_m']/2-inner)-g['corridor_width_m']
 return {'frontage_m':front,'depth_m':depth,'area_m2':front*depth,'status':'OLD_GENERIC_RECONSTRUCTION_NOT_ASBUILT_OR_SOURCE_CONFORMING'}

def fitout_contract(unit,profile):
 w=profile['frontage_m'];d=profile['depth_m'];suite=unit['is_suite'];living=profile.get('living_width_m',max(3.2,min(5.4,w*.36))) if suite else 0
 result={'schema':'mbs_full_room_fitout_contract_v3','minimum_door_width_m':1.30,'bathroom_door_width_m':1.12,'bedroom_door_width_m':1.15,'bathroom_width_depth_m':[3.2,2.8],'full_king_mattress_width_m':1.95,'retained_twin_mattress_width_m':1.40,'room_v_coordinates_m':[0,d],'furnishing_scale':1.0,'bedrooms':[],'objects':[],'route_spine_u_m':.85,'front_gallery_v_m':3.40,'native_furnishing_or_walk_validation':False}
 if suite:
  bw=(w-living)/unit['bedrooms']
  for i in range(unit['bedrooms']):
   left=living+i*bw;right=left+bw;bed=right-.15-1.255;aisle=(left+.075+bed-1.255)/2
   result['bedrooms'].append({'id':unit['id']+'-bedroom-'+str(i+1),'left_u':left,'right_u':right,'front_v':4.05,'door_u':max(left+.725,aisle),'bed_center_uv':[bed,d-1.25],'whole_bed_furniture_envelope_m':[2.51,2.375],'clear_window_aisle_m':bed-1.255-left-.075,'window_route_u':aisle,'mattress_width_m':1.95})
  result['living_width_m']=living
  if unit['entertainment']=='billiards':
   result['objects']=[{'kind':'billiards_table','center_uv':[3.0,d-.15-4.17/2],'size_xz_m':[2.54,1.27],'cue_clear_rectangle_uv':[.28,d-.15-4.17,5.72,d-.15],'cue_clearance_each_side_m':1.45},{'kind':'sofa','center_uv':[1.30,4.30],'size_xz_m':[1.65,.82]},{'kind':'media_screen','mount':'living_divider','size_m':[1.5,.90,.05]}]
  else:result['objects']=[{'kind':'sofa','center_uv':[living-.95,d*.68],'size_xz_m':[1.65,.82]},{'kind':'coffee_table','center_uv':[living-1.0,max(d*.68-1.2,4.25)],'size_xz_m':[1.0,.62]},{'kind':'media_screen','mount':'living_divider','size_m':[1.5,.90,.05]}]
  result['retained_social_programs']=['bathroom','separate_bedrooms','living_lounge','social_bar']+(['dining_with_six_chairs'] if w>11 else [])
 else:
  centres=[3.0,5.2] if unit['bed_variant']=='twin_queen' else [3.1]
  for i,x in enumerate(centres):result['bedrooms'].append({'id':unit['id']+'-bed-'+str(i+1),'bed_center_uv':[x,d-1.25],'whole_bed_furniture_envelope_m':[1.96 if len(centres)==2 else 2.51,2.375],'mattress_width_m':1.40 if len(centres)==2 else 1.95})
  result['objects']=[{'kind':'desk','center_uv':[4.80,3.40] if len(centres)==2 else [w-.75,d-.70],'size_xz_m':[1.20,.60]},{'kind':'armoire','center_uv':[w-.36,4.1],'size_xz_m':[.64,1.40]}]
  if d>=9:result['objects'].append({'kind':'sofa','center_uv':[3.25,5.5],'size_xz_m':[1.65,.82]})
  result['retained_social_programs']=['bathroom','desk','wardrobe','sleeping']
 result['entertainment_program']=unit['entertainment'];result['required_program_identity']=unit['id']+'-'+unit['entertainment']
 return result

def floor_plan(record):
 tower=record['tower'];y=record['elevation_m'];polys=[profile(tower,y),profile(tower,y+record['geometry']['clear_height_m'])];bounds=[geom.axis_bounds(p) for p in polys];zmin=max(b[1] for b in bounds)+.30;zmax=min(b[3] for b in bounds)-.30
 bank=BANKS[tower];bankpoly=geom.shifted(geom.rectangle(-14,-3.6,14,3.6),bank);bankb=geom.axis_bounds(bankpoly)
 rows=[];corridors=[];spine=[];void=[]
 active=0<y<VOID_TOP[tower]
 def add(name,z0,z1,front,side,spine_cut=False):
  span=strip_span(polys,z0,z1)
  if not span:return
  segments=[span]
  if max(z0,bankb[1]-.15)<min(z1,bankb[3]+.15):segments=cut(segments,bankb[0]-.15,bankb[2]+.15)
  if spine_cut:segments=cut(segments,-1.40,1.40)
  for i,(a,b) in enumerate(segments):
   if b-a<6.0:continue
   poly=geom.rectangle(a,z0,b,z1)
   if not all(geom.contains(p,poly) for p in polys):raise ValueError((record['id'],'strip not contained',poly))
   rows.append({'id':name+'-'+str(i),'span_x':[a,b],'available_m':b-a,'cursor':a,'z0':z0,'z1':z1,'front_z':front,'depth_m':z1-z0,'side':side,'axis':'x','rooms':[]})
 if not active:
  a=zmin;b=a+9.2; c=b+2.6; d=c+8;e=d+2.6;f=e+7
  add('north',a,b,b,-1)
  add('middle',c,d,c,1,True)
  if f<=zmax+1e-7:add('south-ends',e,f,e,1)
  for name,lo,hi in [('primary',b,c),('secondary',d,e)]:
   span=strip_span(polys,lo,hi)
   if span:corridors.append({'id':name,'polygon':geom.rectangle(span[0],lo,span[1],hi),'clear_width_m':2.6})
  spine=[[-1.30,b],[1.30,b],[1.30,bank[1]-2.20],[-1.30,bank[1]-2.20]]
 else:
  v0,v1=VOIDS[tower]
  # Preserve open lower atrium. Connected end galleries replace the old
  # disconnected opposite-wing assumptions; not claimed to be as-built.
  fullspan=strip_span(polys,zmin,zmax)
  if fullspan:
   ex0,ex1=fullspan
   # Reconstructed occupied end banks above the ground public atrium, not
   # a whole-length rectangular void that makes all T1 lower floors empty.
   min_x=max(b[0] for b in bounds)+.30;max_x=min(b[2] for b in bounds)-.30
   end_depth=8.0 if tower=='T3' else 9.2
   left_front=max(min_x+end_depth,ex0);right_front=min(max_x-end_depth,ex1)
   void=geom.rectangle(left_front+2.8,v0,right_front-2.8,v1)
   for label,front,side in [('end-north',left_front,-1),('end-south',right_front,1)]:
    x0=min(front,front+side*end_depth);x1=max(front,front+side*end_depth)
    swapped=[[[z,x] for x,z in p] for p in polys];span=strip_span(swapped,x0,x1)
    if span:
     segments=[span]
     if max(x0,bankb[0]-.15)<min(x1,bankb[2]+.15):segments=cut(segments,bankb[1]-.15,bankb[3]+.15)
     for i,(a,b) in enumerate(segments):
      if b-a>=6:rows.append({'id':label+'-'+str(i),'span_x':[a,b],'available_m':b-a,'cursor':a,'z0':x0,'z1':x1,'front_z':front,'depth_m':end_depth,'side':side,'axis':'z','rooms':[]})
  for side in [-1,1]:
   depth=8.0
   if side<0:
    end=v0-2.75
    if end-zmin<depth:depth=7.0
    start=end-depth
    if start>=zmin-1e-7:
     add('atrium-east',start,end,end,-1);span=strip_span(polys,end,v0-.15)
     if span:corridors.append({'id':'atrium-east','polygon':geom.rectangle(span[0],end,span[1],v0-.15),'clear_width_m':2.6})
   else:
    start=v1+2.75
    if zmax-start<depth:depth=7.0
    end=start+depth
    if end<=zmax+1e-7:
     add('atrium-west',start,end,start,1);span=strip_span(polys,v1+.15,start)
     if span:corridors.append({'id':'atrium-west','polygon':geom.rectangle(span[0],v1+.15,span[1],start),'clear_width_m':2.6})
  if fullspan:
   for corridor in corridors:
    cb=geom.axis_bounds(corridor['polygon']);corridor['polygon']=geom.rectangle(max(cb[0],left_front),cb[1],min(cb[2],right_front),cb[3])
   for label,front,side in [('north-end',left_front,-1),('south-end',right_front,1)]:
    x0=min(front,front-side*2.6);x1=max(front,front-side*2.6)
    corridor=geom.rectangle(x0,zmin,x1,zmax)
    if all(geom.contains(p,corridor) for p in polys):corridors.append({'id':label,'polygon':corridor,'clear_width_m':2.6})
   # Horizontal rooms stop at occupied end-bank/gallery boundaries.
   for row in rows:
    if row['axis']!='x':continue
    row['span_x'][0]=max(row['span_x'][0],left_front+2.8);row['span_x'][1]=min(row['span_x'][1],right_front-2.8);row['cursor']=row['span_x'][0];row['available_m']=max(0,row['span_x'][1]-row['span_x'][0])
   # These meet the core helper's existing shared hall; do not add a slab
   # over its shafts/stairs. Parent clips shared-edge duplicate support.
   by=bank[1]-2.2
   for label,a,b in [('bank-north-link',left_front+1.3,-13.75),('bank-south-link',13.75,right_front-1.3)]:
    if a<b:
     poly=geom.rectangle(a,by-1.3,b,by+1.3)
     if all(geom.contains(p,poly) for p in polys):corridors.append({'id':label,'polygon':poly,'clear_width_m':2.6})
 return {'floor_id':record['id'],'tower':tower,'elevation_m':y,'source_floor_polygon':polys[0],'source_ceiling_polygon':polys[1],'lower_public_atrium_void':void,'room_rows':rows,'corridors':corridors,'bank_connector':spine,'core_bank_polygon':bankpoly,'rooms':[],'active_lower_atrium':active,'geometry_status':'RECONSTRUCTED_PRIVATE_LAYOUT_WITH_EXACT_SOURCE_ENVELOPE_CONTAINMENT','native_verified':False}

def place(plan,unit):
 profile=room_profile(unit); options=[]
 for row in plan['room_rows']:
  if row['depth_m']+1e-8<profile['depth_m']:continue
  width=profile['frontage_m'];need=width+.15
  if row['available_m']+1e-8>=need:options.append((row['available_m']-need,row))
 if not options:return False
 _,row=min(options,key=lambda r:r[0]);a=row['cursor'];b=a+profile['frontage_m'];row['cursor']=b+.15;row['available_m']-=profile['frontage_m']+.15
 depth=row['depth_m'];profile=dict(profile);profile['minimum_depth_m']=profile['depth_m'];profile['depth_m']=depth
 front=row['front_z'];far=front+row['side']*depth
 if row['axis']=='x':
  polygon=geom.rectangle(a,min(front,far),b,max(front,far));u_axis=[row['side'],0];v_axis=[0,row['side']];origin=[a if row['side']>0 else b,front]
 else:
  polygon=geom.rectangle(min(front,far),a,max(front,far),b);u_axis=[0,-row['side']];v_axis=[row['side'],0];origin=[front,a if row['side']<0 else b]
 assert all(geom.contains(p,polygon) for p in [plan['source_floor_polygon'],plan['source_ceiling_polygon']])
 entry=[origin[i]+u_axis[i]*.85 for i in range(2)];approach=[entry[i]-v_axis[i]*1.15 for i in range(2)]
 room={'id':unit['id'],'original_floor_id':unit['floor_id'],'physical_floor_id':plan['floor_id'],'original_wing_alias':unit['wing'],'row_id':row['id'],'unit':unit,'profile':profile,'footprint_own_xz':polygon,'room_origin_own_xz':origin,'frontage_own_axis':u_axis,'threshold_own_xz':entry,'approach_own_xz':approach,'into_room_own_axis':v_axis,'private_asbuilt_verified':False,'explicit_relayout_not_legacy_dimensions':True,'old_prototype_dimensions':legacy_dimensions(unit),'fitout_contract':fitout_contract(unit,profile)}
 plan['rooms'].append(room);row['rooms'].append(unit['id']);return True

def compile_all():
 guests=[f for f in INV['hotel_floors'] if f['factory']=='guest_floor_v1'];plans={f['id']:floor_plan(f) for f in guests};units=[u for f in guests for u in f['units']]; units.sort(key=lambda u:(-u['bedrooms'],-room_profile(u)['frontage_m'],u['id']))
 overflow=[]
 for unit in units:
  if not place(plans[unit['floor_id']],unit):overflow.append(unit)
 remaining=[]
 for unit in overflow:
  tower=unit['floor_id'].split('-')[0]
  candidates=sorted(plans.values(),key=lambda p:(p['tower']!=tower,abs(p['elevation_m']-next(f['elevation_m'] for f in guests if f['id']==unit['floor_id'])),p['floor_id']))
  if not any(place(p,unit) for p in candidates):remaining.append(unit)
 for p in plans.values():
  for index,r in enumerate(p['rooms']):r['physical_display_label']=p['floor_id']+' / '+('Suite ' if r['unit']['is_suite'] else 'Room ')+str(index+1).zfill(2);r['display_label_status']='RECONSTRUCTED_WAYFINDING_NOT_ASBUILT_NUMBER';r['original_display_label']=r['unit']['label']
 assigned=[r for p in plans.values() for r in p['rooms']]
 report={'schema':'mbs_source_floor_allocation_v1','source_inventory_sha256':hashlib.sha256((ROOT/'game/data/mbs-interior/inventory.json').read_bytes()).hexdigest(),'source_reference_sha256':hashlib.sha256((ROOT/'game/src/world/mbs_interior/site_reference.gd').read_bytes()).hexdigest(),'core_contract_sha256':hashlib.sha256((ROOT/'game/src/world/mbs_interior/source_core_layout.gd').read_bytes()).hexdigest(),'assigned_room_count':len(assigned),'original_room_count':len(units),'assigned_suite_count':sum(r['unit']['is_suite'] for r in assigned),'relocated_count':sum(r['original_floor_id']!=r['physical_floor_id'] for r in assigned),'cross_tower_relocations':sum(r['original_floor_id'].split('-')[0]!=r['physical_floor_id'].split('-')[0] for r in assigned),'remaining_units':remaining,'floors':plans,'program_records_retained_for_separate_source_polygon_planning':[f for f in INV['hotel_floors']+INV['resort_program_floors'] if f['factory']!='guest_floor_v1'],'furniture_shrink_authorized':False,'explicit_room_relayout':True,'native_validated':False,'all_floors_or_building_completed':False}
 return report

if __name__=='__main__':
 result=compile_all();out=Path(__file__).with_name('SOURCE_FLOOR_ALLOCATION_CANDIDATE.json');out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:result[k] for k in ['assigned_room_count','original_room_count','assigned_suite_count','relocated_count','cross_tower_relocations']}));print('unplaced',len(result['remaining_units']));print('floor_counts',[(k,len(v['rooms'])) for k,v in result['floors'].items() if v['active_lower_atrium']][:24])
