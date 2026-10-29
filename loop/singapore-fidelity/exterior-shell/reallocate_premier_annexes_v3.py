"""Move complete Premier units to real unused corridor slots, adding their old
space as a connected same-floor suite annex. Every original unit remains once.
No runtime/visual fit is claimed; this is bounded reconstruction planning.
"""
from pathlib import Path
import json,copy,time,math,hashlib,collections
import audit_core_layout as g
import plan_source_floors as base
import plan_source_floors_luxury_v3 as plan
import annex_luxury_type_areas_v3 as annex
import expand_luxury_rooms_v2 as growth
import premier_fitout_v3 as premier
from functools import lru_cache
HERE=Path(__file__).resolve().parent

def bridge(a,b):
 a=g.axis_bounds(a);b=g.axis_bounds(b)
 for axis in [0,1]:
  other=1-axis;lo=max(a[other],b[other]);hi=min(a[other+2],b[other+2])
  if hi-lo<1.30:continue
  for l,r in [(a,b),(b,a)]:
   gap=r[axis]-l[axis+2]
   if -.00001<=gap<=.20001:
    if axis==0:p=g.rectangle(l[2],lo,r[0],hi)
    else:p=g.rectangle(lo,l[3],hi,r[1])
    return p,hi-lo,gap
 return None

def area(r):return annex.area(r)
@lru_cache(maxsize=2048)
def fullsize_premier_profile(variant,depth):
 minimum=5.2 if variant=='twin_queen' else 3.75
 width=max(45.0/depth,minimum)
 contract=premier.build(width,depth,variant);proof=premier.audit(contract)
 if not proof['passed']:return None
 return {'frontage_m':width,'depth_m':depth,'furnishing_profile':'fullsize_premier_typed_open_door_v3','published_type_area_target_m2':45,'furnishing_scale':1.0,'typed_fitout_contract':contract,'static_capsule_proof':proof,'native_or_rendered_verified':False}

def free_slots(doc,unit,old_floor):
 own=old_floor['tower'];choices=[]
 for f in doc['floors'].values():
  if f['floor_id']==old_floor['floor_id']:continue
  for row in f['room_rows']:
   prof=fullsize_premier_profile(unit['bed_variant'],round(float(row['depth_m']),9))
   if not prof:continue
   spans=[row['span_x'][:]];axis=0 if row['axis']=='x' else 1;other=1-axis;depthlo=min(row['z0'],row['z1']);depthhi=max(row['z0'],row['z1'])
   static=[f['core_bank_polygon']]+[c['polygon'] for c in f['corridors']]+([f['bank_connector']] if f['bank_connector'] else [])+([f['lower_public_atrium_void']] if f['lower_public_atrium_void'] else [])
   occupied=static+[p for room in f['rooms'] for p in annex.patches(room)]
   for ob in occupied:
    b=g.axis_bounds(ob)
    if max(depthlo,b[other])<min(depthhi,b[other+2])-1e-7:spans=base.cut(spans,b[axis],b[axis+2])
   for lo,hi in spans:
    if hi-lo>=prof['frontage_m']-1e-8:
     choices.append((f['tower']!=own,prof['frontage_m']*prof['depth_m'],abs(f['elevation_m']-old_floor['elevation_m']),f['floor_id'],lo,f,row,prof))
 return sorted(choices,key=lambda v:v[:5])

def relocate(room,f,row,prof,a):
 r=copy.deepcopy(room);b=a+prof['frontage_m'];front=row['front_z'];far=front+row['side']*prof['depth_m']
 if row['axis']=='x':poly=g.rectangle(a,min(front,far),b,max(front,far));u=[row['side'],0];v=[0,row['side']];origin=[a if row['side']>0 else b,front]
 else:poly=g.rectangle(min(front,far),a,max(front,far),b);u=[0,-row['side']];v=[row['side'],0];origin=[front,a if row['side']<0 else b]
 entry=[origin[i]+u[i]*.85 for i in range(2)];approach=[entry[i]-v[i]*1.15 for i in range(2)]
 for key in ['private_annex_patches','contiguous_expansions','category_average_expansion_records']:r.pop(key,None)
 r.update({'physical_floor_id':f['floor_id'],'row_id':row['id'],'profile':prof,'footprint_own_xz':poly,'room_origin_own_xz':origin,'frontage_own_axis':u,'into_room_own_axis':v,'threshold_own_xz':entry,'approach_own_xz':approach,'reserved_area_m2':prof['frontage_m']*prof['depth_m'],'reallocated_from_physical_floor_id':room['physical_floor_id'],'frozen_minimum_footprint_after_row_reorder':copy.deepcopy(poly),'luxury_target_area_m2':45,'final_luxury_acceptance':False,'party_wall_policy':'ONE_SHARED_150MM_WALL_AT_TOUCHING_BOUNDARY_NOT_DUPLICATE_COLLIDERS'})
 return r

def apply(doc):
 started=time.monotonic();moves=[]
 premier_total=sum(area(r) for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']=='premier')
 for kind in ['signature_suite','paiza_suite']:
  rr=[(f,r) for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind];deficit=len(rr)*140-sum(area(r) for f,r in rr)
  for f,suite in sorted(rr,key=lambda x:(area(x[1]),x[1]['id'])):
   if deficit<=.05:break
   if time.monotonic()-started>240:raise RuntimeError('Bounded CPU240s budget exceeded; no partial new candidate published')
   candidates=[]
   for room in f['rooms']:
    if room['unit']['kind']!='premier' or area(suite)+area(room)>210+.001:continue
    join=bridge(suite['footprint_own_xz'],room['footprint_own_xz'])
    if not join:continue
    connector,length,gap=join
    static=[f['core_bank_polygon']]+[c['polygon'] for c in f['corridors']]+([f['bank_connector']] if f['bank_connector'] else [])+([f['lower_public_atrium_void']] if f['lower_public_atrium_void'] else [])
    if gap>.00001 and not annex.clear(connector,f,suite,[(p,g.axis_bounds(p)) for p in static]):continue
    candidates.append((area(room),room,connector,length,gap))
   for gain,room,connector,length,gap in sorted(candidates,key=lambda v:-v[0]):
    if room not in f['rooms'] or area(suite)+gain>210+.001:continue
    slots=free_slots(doc,room['unit'],f)
    chosen=None
    for _,new_area,_,_,lo,dest,row,prof in slots:
     if premier_total-gain+new_area<1075*45-.01:continue
     candidate=relocate(room,dest,row,prof,lo)
     static=[dest['core_bank_polygon']]+[c['polygon'] for c in dest['corridors']]+([dest['bank_connector']] if dest['bank_connector'] else [])+([dest['lower_public_atrium_void']] if dest['lower_public_atrium_void'] else [])
     if annex.clear(candidate['footprint_own_xz'],dest,candidate,[(p,g.axis_bounds(p)) for p in static]):chosen=(dest,row,candidate,new_area);break
    if not chosen:continue
    dest,row,newroom,new_area=chosen;f['rooms'].remove(room);dest['rooms'].append(newroom);row['rooms'].append(newroom['id'])
    for source_row in f['room_rows']:
     if room['id'] in source_row['rooms']:source_row['rooms'].remove(room['id'])
    for poly in annex.patches(room):suite.setdefault('private_annex_patches',[]).append({'polygon':poly,'area_m2':abs(g.signed_area(poly)),'shared_wall_segment':connector,'planned_opening_width_m':1.30,'program':'full_living_dining_or_wardrobe_annex','formerly_separate_room_id':room['id'],'former_room_relocated_intact_to_floor':dest['floor_id'],'requires_real_internal_opening_furnishing_and_native_route':True,'old_public_entry_requires_explicit_closure_or_same_suite_access':True,'native_or_asbuilt_verified':False})
    if gap>.00001:suite['private_annex_patches'].append({'polygon':connector,'area_m2':abs(g.signed_area(connector)),'program':'actual_shared_party_wall_connection_floor','planned_opening_width_m':1.30,'native_or_asbuilt_verified':False})
    actualgain=gain+(abs(g.signed_area(connector)) if gap>.00001 else 0);suite['reserved_area_m2']=area(suite);premier_total+=new_area-gain;deficit-=actualgain;moves.append({'room_id':room['id'],'from_floor':f['floor_id'],'to_floor':dest['floor_id'],'suite_receiving_old_space':suite['id'],'suite_added_area_m2':actualgain,'premier_new_area_m2':new_area});break
 stats={}
 for kind,ref in growth.TARGETS.items():
  rr=[r for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind];aa=[area(r) for r in rr];total=sum(aa)
  stats[kind]={'count':len(rr),'published_average_target_m2':ref['target_area_m2'],'reserved_average_m2':total/len(rr),'reserved_total_m2':total,'target_total_m2':len(rr)*ref['target_area_m2'],'minimum_reserved_m2':min(aa),'maximum_reserved_m2':max(aa),'remaining_aggregate_deficit_m2':max(0,len(rr)*ref['target_area_m2']-total),'url':ref['url']}
 doc['schema']='mbs_source_floor_luxury_reallocated_annex_v3';doc['premier_preserving_annex_reallocations']=moves;doc['area_progress']={'new_reserved_total_m2':sum(v['reserved_total_m2'] for v in stats.values()),'type_statistics':stats,'all_category_targets_met':all(v['remaining_aggregate_deficit_m2']<=.05 for v in stats.values()),'actual_internal_annex_openings_or_furniture_verified':False,'requires_exact_patch_union_not_room_bounding_rectangle':True,'elapsed_cpu_seconds':time.monotonic()-started};return doc

if __name__=='__main__':
 p=HERE/'SOURCE_FLOOR_LUXURY_ANNEX_V3.json';d=json.loads(p.read_text());d['pre_reallocate_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();d=apply(d);out=HERE/'SOURCE_FLOOR_LUXURY_REALLOCATED_V3.json';out.write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d['area_progress'],indent=2));print('relocations',len(d['premier_preserving_annex_reallocations']))
