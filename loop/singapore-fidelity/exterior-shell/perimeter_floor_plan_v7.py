"""Perimeter-facing hotel-room allocator. No interior-only guest rows.
The spare interior is reserved for genuine private annexes and circulation.
"""
from pathlib import Path
import json,math,copy
import plan_source_floors as base
import plan_source_floors_luxury_v3 as luxury
import audit_core_layout as g
HERE=Path(__file__).resolve().parent

def floor(record):
 p=base.floor_plan(record)
 if p['active_lower_atrium']:
  # Existing end-bank reconstruction is already perimeter-facing. Remove any
  # interior-only horizontal candidate band; direct facade audit is mandatory.
  p['room_rows']=[r for r in p['room_rows'] if r['axis']=='z']
  p['layout_pattern']='source_perimeter_lower_end_banks';return p
 tower=record['tower'];polys=[p['source_floor_polygon'],p['source_ceiling_polygon']];bb=[g.axis_bounds(q) for q in polys];zmin=max(b[1] for b in bb)+.20;zmax=min(b[3] for b in bb)-.20;bank=base.BANKS[tower];bankb=g.axis_bounds(p['core_bank_polygon']);p['room_rows']=[];p['corridors']=[];p['bank_connector']=[]
 # Real longitudinal end-facing rooms; an inner2.6m public gallery separates
 # each end-bank from the central north-facing room block and core reservation.
 left_inner=-16.60;right_inner=16.60
 for side,front in [(-1,left_inner),(1,right_inner)]:
  # Use source X extents at every edge-vertex Z interval. This allows a source
  # notch to change depth rather than silently replacing its polygon by bbox.
  levels=sorted(set([zmin,zmax]+[q[1] for poly in polys for q in poly if zmin+.10<q[1]<zmax-.10]))
  # Search a few bounded whole strips and source-notch split strips. Retain
  # the widest depth that has exact full-height polygon containment.
  ranges=[(zmin,zmax)]
  for z in levels[1:-1]:ranges.extend([(zmin,z-.10),(z+.10,zmax)])
  candidates=[]
  for lo,hi in ranges:
   if hi-lo<3.75:continue
   span=base.strip_span(polys,lo,hi)
   if not span:continue
   outside=span[0] if side<0 else span[1];depth=abs(front-outside)
   if (side<0 and outside>=front) or (side>0 and outside<=front) or depth<3.5:continue
   poly=g.rectangle(min(front,outside),lo,max(front,outside),hi)
   if all(g.contains(q,poly) for q in polys):candidates.append(((hi-lo)*depth,lo,hi,outside,depth))
  chosen=[]
  for _,lo,hi,outside,depth in sorted(candidates,reverse=True):
   if any(min(hi,b)-max(lo,a)>.01 for a,b in chosen):continue
   chosen.append((lo,hi));p['room_rows'].append({'id':'source-end-'+str(side)+'-'+str(len(chosen)),'span_x':[lo,hi],'available_m':hi-lo,'cursor':lo,'z0':min(front,outside),'z1':max(front,outside),'front_z':front,'depth_m':depth,'side':side,'axis':'z','rooms':[],'facade_source_side':'longitudinal_end','exact_source_facade_required':True})
  corridor=g.rectangle(front if side<0 else front-2.6,zmin,front+2.6 if side<0 else front,zmax)
  if all(g.contains(q,corridor) for q in polys):p['corridors'].append({'id':'perimeter-end-gallery-'+str(side),'polygon':corridor,'clear_width_m':2.6})
 # North-facing deep rooms lie between the end galleries and the unchanged
 # core front hall. Unlike former middle rows, their back actually meets the
 # source external northern facade.
 hero=record['id'] in luxury.HERO_FLOORS
 front=bank[1]-3.5-.15;depth=front-zmin
 north_span=base.strip_span(polys,zmin,front)
 if north_span and depth>=7:
  a=max(north_span[0],left_inner+2.6+.075);b=min(north_span[1],right_inner-2.6-.075)
  if b-a>=3.75:p['room_rows'].append({'id':'source-north-middle','span_x':[a,b],'available_m':b-a,'cursor':a,'z0':zmin,'z1':front,'front_z':front,'depth_m':depth,'side':-1,'axis':'x','rooms':[],'facade_source_side':'north','exact_source_facade_required':True})
  gallery=g.rectangle(left_inner+1.3,bank[1]-3.5,right_inner-1.3,bank[1]-.9)
  if all(g.contains(q,gallery) for q in polys):p['corridors'].append({'id':'perimeter-cross-gallery','polygon':gallery,'clear_width_m':2.6})
 # Public core hall remains Root-owned. A short central join connects it.
 p['bank_connector']=[] # The cross gallery is the existing core hall, not a second parallel passage.
 p['core_hall_reused_directly']=True
 p['shared_party_wall_policy']='ONE150MM_WALL_AT_TOUCHING_ROOM_BOUNDARIES'
 p['layout_pattern']='source_perimeter_end_banks_plus_north_middle';return p

def profile(unit,depth):
 ref=luxury.TARGETS[unit['kind']]['target_area_m2'];seed=ref*.87 if unit['kind'] in ['signature_suite','paiza_suite'] else ref
 if not unit['is_suite']:
  minimum_frontage=3.75 if unit['bed_variant']=='king' else 5.2
  if depth<6.2:return None # Narrow facade strip requires a distinct rotated fitout, not a silent pass.
  return {'frontage_m':max(seed/depth,minimum_frontage),'depth_m':depth,'published_type_area_target_m2':ref,'allocation_seed_area_m2':seed,'furnishing_profile':'source_perimeter_premier_pending_typed_fitout','furnishing_scale':1.0,'native_or_asbuilt_verified':False}
 if depth<8:return None
 minimum_frontage=3.2+unit['bedrooms']*3.75 # Facade-facing sleeping/living; full billiards den may be behind them.
 if unit['kind']=='chairman_residence':minimum_frontage=6+unit['bedrooms']*4.3
 if unit['kind']=='presidential_suite':minimum_frontage=6+unit['bedrooms']*4.1
 return {'frontage_m':max(seed/depth,minimum_frontage),'depth_m':depth,'published_type_area_target_m2':ref,'allocation_seed_area_m2':seed,'furnishing_profile':'source_perimeter_suite_pending_typed_fitout','furnishing_scale':1.0,'native_or_asbuilt_verified':False}

def compile_all():
 records=[r for r in base.INV['hotel_floors'] if r['factory']=='guest_floor_v1'];floors={r['id']:floor(r) for r in records};units=[u for r in records for u in r['units']];remaining=[]
 original=luxury.wanted_profile;luxury.wanted_profile=profile
 try:
  for group in [[u for u in units if u['kind'] in ['chairman_residence','presidential_suite','family_suite']],[u for u in units if u['is_suite'] and u['kind'] not in ['chairman_residence','presidential_suite','family_suite']],[u for u in units if not u['is_suite']]]:
   group.sort(key=lambda u:(-luxury.TARGETS[u['kind']]['target_area_m2'],-u['bedrooms'],u['id']));overflow=[]
   for u in group:
    if not luxury.place(floors[u['floor_id']],u):overflow.append(u)
   for u in overflow:
    own=u['floor_id'].split('-')[0];elev=next(r['elevation_m'] for r in records if r['id']==u['floor_id']);choices=sorted(floors.values(),key=lambda f:(f['tower']!=own,abs(f['elevation_m']-elev),f['floor_id']))
    if not any(luxury.place(f,u) for f in choices):remaining.append(u)
 finally:luxury.wanted_profile=original
 assigned=[r for f in floors.values() for r in f['rooms']]
 return {'schema':'mbs_source_perimeter_allocation_v7','floors':floors,'assigned':len(assigned),'remaining_units':remaining,'suite_count':sum(r['unit']['is_suite'] for r in assigned),'all_original_ids_retained':len(assigned)+len(remaining)==1850,'relocated':sum(r['original_floor_id']!=r['physical_floor_id'] for r in assigned),'cross_tower':sum(r['original_floor_id'].split('-')[0]!=r['physical_floor_id'].split('-')[0] for r in assigned),'actual_furniture_or_traversal_or_full_building_verified':False,'empty_guest_floors':[f['floor_id'] for f in floors.values() if not f['rooms']],'program_records_retained_for_separate_source_polygon_planning':[f for f in base.INV['hotel_floors']+base.INV['resort_program_floors'] if f['factory']!='guest_floor_v1']}

if __name__=='__main__':
 d=compile_all();(HERE/'SOURCE_FLOOR_PERIMETER_CANDIDATE_V7.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps({k:v for k,v in d.items() if k not in ['floors','remaining_units','program_records_retained_for_separate_source_polygon_planning']},indent=2));print('unplaced',len(d['remaining_units']))
