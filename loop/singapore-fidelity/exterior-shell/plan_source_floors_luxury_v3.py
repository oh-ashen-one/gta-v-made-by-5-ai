"""Area-first alternate private layout, independent of frozen minimum topology."""
from __future__ import annotations
import json,math,copy,hashlib
from pathlib import Path
import plan_source_floors as base
import audit_core_layout as g
HERE=Path(__file__).resolve().parent
TARGETS=json.loads((HERE/'LUXURY_TYPE_REFERENCES.json').read_text())['types']
SEED_RATIO=.85
HERO_FLOORS={u['floor_id'] for f in base.INV['hotel_floors'] for u in f['units'] if u['kind'] in ['chairman_residence','presidential_suite']}

def rows_for(record):
 p=base.floor_plan(record)
 if p['active_lower_atrium']:
  t=record['tower'];polys=[p['source_floor_polygon'],p['source_ceiling_polygon']];bounds=[g.axis_bounds(q) for q in polys];zmin=max(b[1] for b in bounds)+.20;zmax=min(b[3] for b in bounds)-.20;bankb=g.axis_bounds(p['core_bank_polygon']);voidb=g.axis_bounds(p['lower_public_atrium_void']);v0,v1=base.VOIDS[t]
  p['room_rows']=[r for r in p['room_rows'] if not r['id'].startswith('atrium-')];p['corridors']=[c for c in p['corridors'] if not c['id'].startswith('atrium-')]
  for name,lo,hi,front,side,clo,chi in [('atrium-east',zmin,v0-2.75,v0-2.75,-1,v0-2.75,v0-.15),('atrium-west',v1+2.75,zmax,v1+2.75,1,v1+.15,v1+2.75)]:
   if hi-lo<6.2:continue
   span=base.strip_span(polys,lo,hi)
   if not span:continue
   segments=[[max(span[0],voidb[0]),min(span[1],voidb[2])]]
   if max(lo,bankb[1]-.15)<min(hi,bankb[3]+.15):segments=base.cut(segments,bankb[0]-.15,bankb[2]+.15)
   for corridor in p['corridors']:
    cb=g.axis_bounds(corridor['polygon'])
    if max(lo,cb[1])<min(hi,cb[3])-1e-7:segments=base.cut(segments,cb[0]-.075,cb[2]+.075)
   for index,(a,b) in enumerate(segments):
    if b-a>=3.75:p['room_rows'].append({'id':name+'-'+str(index),'span_x':[a,b],'available_m':b-a,'cursor':a,'z0':lo,'z1':hi,'front_z':front,'depth_m':hi-lo,'side':side,'axis':'x','rooms':[]})
   span=base.strip_span(polys,clo,chi)
   if span:p['corridors'].append({'id':name,'polygon':g.rectangle(max(span[0],voidb[0]-2.8),clo,min(span[1],voidb[2]+2.8),chi),'clear_width_m':2.6})
  return p
 t=record['tower'];polys=[p['source_floor_polygon'],p['source_ceiling_polygon']];bb=[g.axis_bounds(q) for q in polys];zmin=max(b[1] for b in bb)+.20;zmax=min(b[3] for b in bb)-.20;bank=base.BANKS[t];bankb=g.axis_bounds(p['core_bank_polygon']);p['room_rows']=[];p['corridors']=[]
 deep=record['id'] in HERO_FLOORS
 north_depth=(bankb[1]-.20-zmin-2.6) if deep else 10.0
 main0=zmin+north_depth;main1=main0+2.6;rear0=bankb[1]-.20
 def add(name,z0,z1,front,side,cut_spine=False):
  span=base.strip_span(polys,z0,z1)
  if not span:return
  segments=[span]
  if cut_spine:
   middle=(span[0]+span[1])*.5;p['middle_spine_x']=middle;segments=base.cut(segments,middle-1.40,middle+1.40)
  for i,(a,b) in enumerate(segments):
   if b-a<3.75:continue
   p['room_rows'].append({'id':name+'-'+str(i),'span_x':[a,b],'available_m':b-a,'cursor':a,'z0':z0,'z1':z1,'front_z':front,'depth_m':z1-z0,'side':side,'axis':'x','rooms':[]})
 add('deep-luxury' if deep else 'front-luxury',zmin,main0,main0,-1)
 if not deep and rear0-main1>=7.0:add('middle-luxury',main1,rear0,main1,1,True)
 span=base.strip_span(polys,main0,main1)
 if span:p['corridors'].append({'id':'single-main-gallery','polygon':g.rectangle(span[0],main0,span[1],main1),'clear_width_m':2.6})
 spine_x=p.get('middle_spine_x',0.0)
 p['bank_connector']=[[spine_x-1.30,main0],[spine_x+1.30,main0],[spine_x+1.30,bank[1]-2.20],[spine_x-1.30,bank[1]-2.20]]
 # Rear rooms face inward into short side galleries, rather than wasting a
 # second whole-building cross corridor. Core bank/own stairs stay unchanged.
 rear_span=base.strip_span(polys,rear0,zmax)
 if rear_span:
  for side in [-1,1]:
   front=side*16.8;outside=rear_span[0] if side<0 else rear_span[1];depth=abs(outside-front)
   if depth<7-1e-8:continue
   low=min(front,outside);high=max(front,outside);swapped=[[[z,x] for x,z in q] for q in polys];longspan=base.strip_span(swapped,low,high)
   if not longspan:continue
   a=max(rear0,longspan[0]);b=min(zmax,longspan[1])
   if b-a<3.75:continue
   p['room_rows'].append({'id':'rear-end-'+str(side),'span_x':[a,b],'available_m':b-a,'cursor':a,'z0':low,'z1':high,'front_z':front,'depth_m':depth,'side':side,'axis':'z','rooms':[]})
   corridor=g.rectangle(min(front,front-side*2.6),rear0,max(front,front-side*2.6),zmax)
   if not all(g.contains(q,corridor) for q in polys):raise ValueError('rear side corridor outside source')
   p['corridors'].append({'id':'rear-end-gallery-'+str(side),'polygon':corridor,'clear_width_m':2.6})
   a0=min(front-side*1.3,side*13.75);a1=max(front-side*1.3,side*13.75);link=g.rectangle(a0,bank[1]-3.5,a1,bank[1]-.9)
   p['corridors'].append({'id':'rear-core-join-'+str(side),'polygon':link,'clear_width_m':2.6})
 p['layout_pattern']='deep-residence-band' if deep else 'area-first-single-main-gallery'
 return p

def wanted_profile(unit,depth):
 typ=unit['kind'];target=TARGETS[typ]['target_area_m2'];seed=target*SEED_RATIO if typ in ['signature_suite','paiza_suite'] else target;w=seed/depth
 if not unit['is_suite']:
  if unit['bed_variant']=='twin_queen':minimum=5.2 if depth>=8.6-1e-8 else 7.2
  else:
   minimum=3.75 if depth>=11.84-1e-8 else 4.2 if depth>=10.71-1e-8 else 4.5 if depth>=9.0-1e-8 else 5.2 if depth>=8.0-1e-8 else 6.0
   if depth>=11.84-1e-8:w=max(44.5/depth,minimum)
  if depth<6.2-1e-8:return None
  w=max(w,minimum);mode='long_fullsize_premier_v5' if depth>=9-1e-8 else 'compact_fullsize_premier_v5'
 else:
  if depth<8-1e-8:return None
  living=6.0 if unit['entertainment']=='billiards' or typ in ['presidential_suite','chairman_residence'] else 3.2
  bedroom_width=4.3 if typ=='chairman_residence' else 4.1 if typ=='presidential_suite' else 4.0
  if unit['entertainment']=='billiards' and depth<9.4-1e-8:return None
  w=max(w,living+unit['bedrooms']*bedroom_width);mode='published_type_area_suite_v5'
 return {'frontage_m':w,'depth_m':depth,'furnishing_profile':mode,'published_type_area_target_m2':target,'allocation_seed_area_m2':seed,'category_average_target_must_be_met_after_expansion':True,'type_reference_url':TARGETS[typ]['url'],'all_dimensions_reconstructed':True,'furnishing_scale':1.0}

def place(f,unit):
 options=[]
 for row in f['room_rows']:
  prof=wanted_profile(unit,row['depth_m'])
  gap=.15 if row['rooms'] else 0.0
  if prof and row['available_m']>=prof['frontage_m']+gap-1e-8:options.append((row['available_m']-prof['frontage_m']-gap,row,prof))
 if not options:return False
 _,row,prof=min(options,key=lambda v:v[0]);gap=.15 if row['rooms'] else 0.0;a=row['cursor']+gap;b=a+prof['frontage_m'];row['cursor']=b;row['available_m']-=prof['frontage_m']+gap;front=row['front_z'];far=front+row['side']*prof['depth_m']
 if row['axis']=='x':poly=g.rectangle(a,min(front,far),b,max(front,far));u=[row['side'],0];v=[0,row['side']];origin=[a if row['side']>0 else b,front]
 else:poly=g.rectangle(min(front,far),a,max(front,far),b);u=[0,-row['side']];v=[row['side'],0];origin=[front,a if row['side']<0 else b]
 assert all(g.contains(q,poly) for q in [f['source_floor_polygon'],f['source_ceiling_polygon']])
 entry=[origin[i]+u[i]*.85 for i in range(2)];approach=[entry[i]-v[i]*1.15 for i in range(2)]
 r={'id':unit['id'],'unit':unit,'original_floor_id':unit['floor_id'],'physical_floor_id':f['floor_id'],'original_wing_alias':unit['wing'],'row_id':row['id'],'profile':prof,'footprint_own_xz':poly,'room_origin_own_xz':origin,'frontage_own_axis':u,'into_room_own_axis':v,'threshold_own_xz':entry,'approach_own_xz':approach,'old_prototype_dimensions':base.legacy_dimensions(unit),'explicit_relayout_not_legacy_dimensions':True,'private_asbuilt_verified':False,'native_fitout_verified':False}
 f['rooms'].append(r);row['rooms'].append(unit['id']);return True

def compile_all():
 records=[r for r in base.INV['hotel_floors'] if r['factory']=='guest_floor_v1'];floors={r['id']:rows_for(r) for r in records};units=[u for r in records for u in r['units']];remaining=[]
 for group in [[u for u in units if u['kind'] in ['chairman_residence','presidential_suite','family_suite']],[u for u in units if u['is_suite'] and u['kind'] not in ['chairman_residence','presidential_suite','family_suite']],[u for u in units if not u['is_suite']]]:
  group.sort(key=lambda u:(-TARGETS[u['kind']]['target_area_m2'],-u['bedrooms'],u['id']));overflow=[]
  for u in group:
   if not place(floors[u['floor_id']],u):overflow.append(u)
  for u in overflow:
   own=u['floor_id'].split('-')[0];elev=next(r['elevation_m'] for r in records if r['id']==u['floor_id'])
   choices=sorted(floors.values(),key=lambda f:(f['tower']!=own,abs(f['elevation_m']-elev),f['floor_id']))
   if not any(place(f,u) for f in choices):remaining.append(u)
 assigned=[r for f in floors.values() for r in f['rooms']]
 return {'schema':'mbs_area_first_luxury_floor_plan_v3','floors':floors,'assigned':len(assigned),'remaining_units':remaining,'suite_count':sum(r['unit']['is_suite'] for r in assigned),'all_original_ids_retained':len(assigned)+len(remaining)==1850,'relocated':sum(r['original_floor_id']!=r['physical_floor_id'] for r in assigned),'cross_tower':sum(r['original_floor_id'].split('-')[0]!=r['physical_floor_id'].split('-')[0] for r in assigned),'room_reserved_area_m2':sum(g._area(r['footprint_own_xz']) if hasattr(g,'_area') else abs(g.signed_area(r['footprint_own_xz'])) for r in assigned),'type_area_targets':TARGETS,'actual_furniture_or_traversal_or_full_building_verified':False,'empty_guest_floors':[f['floor_id'] for f in floors.values() if not f['rooms']],'program_records_retained_for_separate_source_polygon_planning':[f for f in base.INV['hotel_floors']+base.INV['resort_program_floors'] if f['factory']!='guest_floor_v1']}

if __name__=='__main__':
 d=compile_all();p=HERE/'SOURCE_FLOOR_LUXURY_AREA_FIRST_V3.json';p.write_text(json.dumps(d,indent=2)+'\n');print(json.dumps({k:v for k,v in d.items() if k not in ['floors','remaining_units','type_area_targets','program_records_retained_for_separate_source_polygon_planning']},indent=2));print('remaining',len(d['remaining_units']))
