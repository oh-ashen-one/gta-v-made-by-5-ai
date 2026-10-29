"""Expand from every actual attached room patch, not only its first rectangle.
Unchanged source envelopes, public corridors, core and minimum2x3m usable patches.
"""
from pathlib import Path
import json,copy,time,hashlib
import annex_luxury_type_areas_v3 as annex
import audit_core_layout as g
import expand_luxury_rooms_v2 as growth
import audit_luxury_plan_v3 as audit
HERE=Path(__file__).resolve().parent

def all_options(f,r,allowed):
 result=[];seen=set()
 for patch in annex.patches(r):
  # options only uses this field to propose an adjacent edge. Its clear()
  # still sees the ORIGINAL room's entire patch union in the floor list.
  proxy=dict(r);proxy['footprint_own_xz']=patch
  for candidate in annex.options(f,proxy,allowed):
   key=tuple(round(v,7) for v in g.axis_bounds(candidate[1]))
   if key not in seen:seen.add(key);result.append(candidate)
 return result

def apply(doc):
 start=time.monotonic();changes=[]
 for kind in ['signature_suite','paiza_suite']:
  rr=[(f,r) for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind];deficit=140*len(rr)-sum(annex.area(r) for f,r in rr)
  for round in range(3):
   made=0
   for f,r in sorted(rr,key=lambda x:(annex.area(x[1]),x[1]['id'])):
    if deficit<=.05:break
    if time.monotonic()-start>240:raise RuntimeError('Bounded240s CPU planning budget exceeded')
    if len(r.get('private_annex_patches',[]))>=8:continue
    allowed=min(deficit,210-annex.area(r))
    if allowed<6:continue
    options=all_options(f,r,allowed)
    if not options:continue
    gain,poly,wall,length,depth=max(options,key=lambda q:q[0]);r.setdefault('private_annex_patches',[]).append({'polygon':poly,'area_m2':gain,'shared_wall_segment':wall,'planned_opening_width_m':1.3,'program':'walkin_wardrobe' if min(length,depth)<3 else 'additional_living_dining','minimum_patch_dimensions_m':[length,depth],'requires_real_internal_opening_furnishing_and_native_route':True,'native_or_asbuilt_verified':False});deficit-=gain;r['reserved_area_m2']=annex.area(r);changes.append({'room_id':r['id'],'area_m2':gain,'kind':kind});made+=1
   if not made:break
 stats={}
 for kind,ref in growth.TARGETS.items():
  rooms=[r for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind];aa=[annex.area(r) for r in rooms];total=sum(aa);stats[kind]={'count':len(rooms),'published_average_target_m2':ref['target_area_m2'],'reserved_average_m2':total/len(rooms),'reserved_total_m2':total,'target_total_m2':len(rooms)*ref['target_area_m2'],'remaining_aggregate_deficit_m2':max(0,len(rooms)*ref['target_area_m2']-total),'minimum_reserved_m2':min(aa),'maximum_reserved_m2':max(aa),'url':ref['url']}
 doc['schema']='mbs_source_luxury_attached_patch_candidate_v5';doc['v5_attached_patch_expansions']=changes;doc['area_progress']={'new_reserved_total_m2':sum(x['reserved_total_m2'] for x in stats.values()),'type_statistics':stats,'all_category_targets_met':all(x['remaining_aggregate_deficit_m2']<=.05 for x in stats.values()),'actual_internal_annex_openings_or_furniture_verified':False,'requires_exact_patch_union_not_room_bounding_rectangle':True,'elapsed_cpu_seconds':time.monotonic()-start};return doc

if __name__=='__main__':
 source=HERE/'SOURCE_FLOOR_LUXURY_CANDIDATE_V4.json';d=json.loads(source.read_text());d['before_v5_sha256']=hashlib.sha256(source.read_bytes()).hexdigest();d=apply(d);p=HERE/'SOURCE_FLOOR_LUXURY_CANDIDATE_V5.json';p.write_text(json.dumps(d,indent=2)+'\n');r=audit.audit(d);r['candidate_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();(HERE/'LUXURY_V5_GEOMETRY_AUDIT.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='failures'},indent=2));print(r['failures'][:10])
