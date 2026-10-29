"""CPU prototype: corrected catalogue, true perimeter cells, variable room depth.
Uses a clearly marked legacy geometry fixture until the public-floor review is
complete. It never installs that fixture schedule as an operator floor fact.
"""
from pathlib import Path
import json,math,copy,hashlib,time
import plan_source_floors as base
import perimeter_floor_plan_v7 as perimeter
import audit_core_layout as g
HERE=Path(__file__).resolve().parent


def floor_fixture(record,special_630=False):
 f=perimeter.floor(record)
 if special_630 and not f['active_lower_atrium']:
  for row in f['room_rows']:
   if row['axis']=='z':
    side=row['side'];front=side*17.4;outer=row['z0'] if side<0 else row['z1'];row.update({'front_z':front,'depth_m':abs(front-outer),'z0':min(front,outer),'z1':max(front,outer)})
   else:row['span_x']=[-14.725,14.725];row['cursor']=-14.725;row['available_m']=29.45
  bank=base.BANKS[f['tower']];z0=min(p[1] for p in f['source_floor_polygon'])+.2;z1=max(p[1] for p in f['source_floor_polygon'])-.2
  f['corridors']=[{'id':'special-end-gallery-left','polygon':g.rectangle(-17.4,z0,-14.8,z1),'clear_width_m':2.6},{'id':'special-end-gallery-right','polygon':g.rectangle(14.8,z0,17.4,z1),'clear_width_m':2.6},{'id':'reused-core-hall-join','polygon':g.rectangle(-16.1,bank[1]-3.5,16.1,bank[1]-.9),'clear_width_m':2.6}];f['special_gallery_reconstruction_for_630m2_residence']=True
 f['source_public_programme_schedule_verified']=False;f['floor_schedule_status']='LEGACY_GEOMETRY_FIXTURE_ONLY_PENDING_CURRENT_PUBLIC_MIXED_USE_REVIEW';return f


def profile(unit,cat,maxdepth):
 area=float(unit['published_average_area_target_m2']);beds=unit['advertised_bedrooms'] or 1
 if not unit['is_suite']:
  minimum=5.5 if cat['id']=='sands_studio' else 5.0 if cat['id']=='paiza_club' else 4.5
  if unit.get('legacy_record',{}).get('bed_variant')=='twin_queen' and 'two_queen' in cat.get('bed_options',[]):minimum=max(minimum,5.2)
 else:
  bedwidth=cat.get('published_mattress_width_m',2.0)
  if cat.get('published_bed_widths_m'):bedwidth=cat['published_bed_widths_m'].get('super_king',2.0)
  if cat.get('published_bed_width_options_m'):bedwidth=max(cat['published_bed_width_options_m']['super_king'])
  private_bed_facade=max(3.75,bedwidth+.56+.90+.15)
  living=6.4 if cat['id'].startswith('chairman') else 3.2
  minimum=beds*private_bed_facade+living+(2.4 if cat['separate_kids_room'] else 0)
 width=max(minimum,area/maxdepth);depth=area/width
 if depth<3.75:return None
 if unit['is_suite'] and depth<6.2:return None
 return {'frontage_m':width,'depth_m':depth,'target_area_m2':area,'area_is_published_category_average_not_individual_survey':True,'minimum_source_facing_zones_m':minimum,'full_size_fitout_pending_native_validation':True,'furniture_scale':1.0,'published_category_id':cat['id']}


def place(f,unit,cat):
 candidates=[]
 for row in f['room_rows']:
  p=profile(unit,cat,row['depth_m'])
  if not p or p['frontage_m']>row['available_m']+1e-8:continue
  candidates.append((row['available_m']-p['frontage_m'],row,p))
 if not candidates:return False
 _,row,p=min(candidates,key=lambda x:x[0]);a=row['cursor'];b=a+p['frontage_m'];row['cursor']=b;row['available_m']-=p['frontage_m'];gap=row['depth_m']-p['depth_m'];front=row['front_z']+row['side']*gap;far=front+row['side']*p['depth_m']
 if row['axis']=='x':poly=g.rectangle(a,min(front,far),b,max(front,far));u=[row['side'],0];v=[0,row['side']];origin=[a if row['side']>0 else b,front]
 else:poly=g.rectangle(min(front,far),a,max(front,far),b);u=[0,-row['side']];v=[row['side'],0];origin=[front,a if row['side']<0 else b]
 if not all(g.contains(q,poly) for q in [f['source_floor_polygon'],f['source_ceiling_polygon']]):raise RuntimeError('New perimeter room exits actual source profile')
 entry_u=p['frontage_m']*.5;entry=[origin[i]+u[i]*entry_u for i in range(2)];approach=[entry[i]-v[i]*1.15 for i in range(2)]
 if gap>.001:
  outside=[entry[i]-v[i]*gap for i in range(2)];corners=[[entry[i]+u[i]*sign*1.3 for i in range(2)] for sign in [-1,1]]+[[outside[i]+u[i]*sign*1.3 for i in range(2)] for sign in [1,-1]]
  if not all(g.contains(q,corners) for q in [f['source_floor_polygon'],f['source_ceiling_polygon']]):raise RuntimeError('Access spur exits source profile')
  f['corridors'].append({'id':unit['id']+'-actual-access-spur','polygon':corners,'clear_width_m':2.6,'role':'actual_public_access_to_shallower_perimeter_room_not_private_area'})
 r={'id':unit['id'],'unit':copy.deepcopy(unit),'catalogue_category_id':cat['id'],'original_floor_id':unit['legacy_record']['floor_id'],'physical_floor_id':f['floor_id'],'row_id':row['id'],'profile':p,'footprint_own_xz':poly,'room_origin_own_xz':origin,'frontage_own_axis':u,'into_room_own_axis':v,'threshold_own_xz':entry,'approach_own_xz':approach,'entry_u_m':entry_u,'main_entry_width_m':1.3,'shared_party_wall_policy':'ONE150MM_WALL_AT_TOUCHING_ROOM_BOUNDARY','source_facing_window_geometry_required':True,'native_or_furnished_or_asbuilt_verified':False}
 f['rooms'].append(r);row['rooms'].append(unit['id']);return True


def allocate():
 source=HERE/'OPERATOR_CATALOGUE_INVENTORY_PROPOSAL_V11.json';catalogue=json.loads(source.read_text());cats={c['id']:c for c in catalogue['catalogue']};records=[r for r in base.INV['hotel_floors'] if r['factory']=='guest_floor_v1'];floors={r['id']:floor_fixture(r,r['id'] in ['T1-L54','T2-L54']) for r in records};missing=[];units=sorted(catalogue['active_units'],key=lambda u:(-u['published_average_area_target_m2'],-int(u['paiza_royal']),u['id']))
 for unit in units:
  c=cats[unit['catalogue_category_id']];allowed=unit['allowed_towers_from_current_page'];eligible=[f for f in floors.values() if not allowed or f['tower'] in allowed]
  old=unit['legacy_record']['floor_id'];oldlevel=int(old.split('-L')[-1]);old_tower=old.split('-')[0]
  if unit['paiza_royal']:eligible=[f for f in eligible if int(f['floor_id'].split('-L')[-1])>=48]
  if unit['collection']=='Paiza':eligible.sort(key=lambda f:(int(f['floor_id'].split('-L')[-1])<40,f['tower']!=old_tower,-int(f['floor_id'].split('-L')[-1]),f['floor_id']))
  else:eligible.sort(key=lambda f:(f['tower']!=old_tower,abs(int(f['floor_id'].split('-L')[-1])-oldlevel),f['floor_id']))
  if not any(place(f,unit,c) for f in eligible):missing.append(unit)
 placed=[r for f in floors.values() for r in f['rooms']]
 return {'schema':'mbs_catalogue_perimeter_allocation_prototype_v12','proposal_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'adoption_status':'NOT_ADOPTED_PENDING_INDEPENDENT_CATALOGUE_AND_PUBLIC_FLOOR_REVIEW','floor_registry_status':'LEGACY_GEOMETRY_FIXTURE_NOT_OPERATOR_GUEST_FLOOR_SCHEDULE','floors':floors,'active_key_target':1844,'assigned':len(placed),'assigned_suites':sum(r['unit']['is_suite'] for r in placed),'unplaced_units':missing,'legacy_mapping':catalogue['legacy_mapping'],'published_area_preserved':all(abs(abs(g.signed_area(r['footprint_own_xz']))-r['profile']['target_area_m2'])<1e-5 for r in placed),'native_or_actual_furniture_verified':False}

if __name__=='__main__':
 d=allocate();p=HERE/'CATALOGUE_PERIMETER_ALLOCATION_PROTOTYPE_V12.json';p.write_text(json.dumps(d,indent=2)+'\n');print('assigned',d['assigned'],'suites',d['assigned_suites'],'unplaced',len(d['unplaced_units']),'areas',d['published_area_preserved'])
 from collections import Counter
 print(Counter(u['catalogue_category_id'] for u in d['unplaced_units']))
