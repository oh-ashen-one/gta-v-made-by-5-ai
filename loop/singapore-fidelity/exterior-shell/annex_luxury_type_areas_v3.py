"""Attach real bounded room patches where a whole-rectangle widening cannot fit.

Every patch has at least2m x3m clear planning extent and a>=1.3m shared wall.
No public passage, core or atrium is consumed; native furnishing/access pending.
"""
from pathlib import Path
import json,copy,hashlib,time
import audit_core_layout as g
import plan_source_floors as source
import expand_luxury_rooms_v2 as growth
HERE=Path(__file__).resolve().parent

def patches(r):return [r['footprint_own_xz']]+[a['polygon'] for a in r.get('private_annex_patches',[])]
def area(r):return sum(abs(g.signed_area(p)) for p in patches(r))
def bbox_overlap(a,b):return min(a[2],b[2])-max(a[0],b[0])>1e-8 and min(a[3],b[3])-max(a[1],b[1])>1e-8

def clear(poly,f,room,obstacles):
 if not g.contains(f['source_floor_polygon'],poly) or not g.contains(f['source_ceiling_polygon'],poly):return False
 pb=g.axis_bounds(poly)
 for ob,bb in obstacles:
  if bbox_overlap(pb,bb) and g.convex_intersection_area(poly,ob)>1e-7:return False
 for other in f['rooms']:
  for ob in patches(other):
   bb=g.axis_bounds(ob)
   if bbox_overlap(pb,bb) and g.convex_intersection_area(poly,ob)>1e-7:return False
 return True

def options(f,r,allowed):
 b=g.axis_bounds(r['footprint_own_xz']);static=[f['core_bank_polygon']]+[c['polygon'] for c in f['corridors']]+([f['bank_connector']] if f['bank_connector'] else [])+([f['lower_public_atrium_void']] if f['lower_public_atrium_void'] else []);obs=[(p,g.axis_bounds(p)) for p in static];result=[]
 for side in range(4):
  axis=1 if side in [0,2] else 0;low=b[axis];high=b[axis+2]
  for length in [3.0,4.0,5.0,6.0,8.0,10.0]:
   if length>high-low-.10:continue
   for at in sorted(set([low+.05,high-length-.05,(low+high-length)*.5])):
    for depth in [2.0,2.5,3.0,4.0,5.0,6.0,8.0]:
     if length*depth>allowed+.001:continue
     if side==0:poly=g.rectangle(b[0]-depth,at,b[0],at+length);wall=[[b[0],at],[b[0],at+length]]
     elif side==2:poly=g.rectangle(b[2],at,b[2]+depth,at+length);wall=[[b[2],at],[b[2],at+length]]
     elif side==1:poly=g.rectangle(at,b[1]-depth,at+length,b[1]);wall=[[at,b[1]],[at+length,b[1]]]
     else:poly=g.rectangle(at,b[3],at+length,b[3]+depth);wall=[[at,b[3]],[at+length,b[3]]]
     if clear(poly,f,r,obs):result.append((length*depth,poly,wall,length,depth))
 return result

def apply(doc):
 started=time.monotonic();added=[]
 for kind in ['signature_suite','paiza_suite']:
  rooms=[(f,r) for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind];target=growth.TARGETS[kind]['target_area_m2'];deficit=target*len(rooms)-sum(area(r) for f,r in rooms)
  for f,r in sorted(rooms,key=lambda fr:(area(fr[1]),fr[1]['id'])):
   if deficit<=.05:break
   if time.monotonic()-started>240:raise RuntimeError('Bounded CPU annex240s budget exceeded; no partial artifact published')
   for _ in range(2):
    allowed=min(deficit,target*1.5-area(r))
    if allowed<6:break
    candidates=options(f,r,allowed)
    if not candidates:break
    gain,poly,wall,length,depth=max(candidates,key=lambda c:c[0]);r.setdefault('private_annex_patches',[]).append({'polygon':poly,'area_m2':gain,'shared_wall_segment':wall,'planned_opening_width_m':1.3,'program':'walkin_wardrobe' if min(length,depth)<3 else 'additional_living_or_dining','minimum_patch_dimensions_m':[length,depth],'requires_real_internal_opening_furnishing_and_native_route':True,'native_or_asbuilt_verified':False});deficit-=gain;added.append({'room_id':r['id'],'kind':kind,'area_m2':gain});r['reserved_area_m2']=area(r)
 stats={}
 for kind,ref in growth.TARGETS.items():
  rr=[r for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind];aa=[area(r) for r in rr];total=sum(aa)
  stats[kind]={'count':len(rr),'published_average_target_m2':ref['target_area_m2'],'reserved_average_m2':total/len(rr),'reserved_total_m2':total,'target_total_m2':len(rr)*ref['target_area_m2'],'minimum_reserved_m2':min(aa),'maximum_reserved_m2':max(aa),'remaining_aggregate_deficit_m2':max(0,len(rr)*ref['target_area_m2']-total),'url':ref['url']}
 doc['schema']='mbs_source_floor_luxury_annex_v3';doc['private_annex_records']=added;doc['area_progress']={'new_reserved_total_m2':sum(v['reserved_total_m2'] for v in stats.values()),'type_statistics':stats,'all_category_targets_met':all(v['remaining_aggregate_deficit_m2']<=.05 for v in stats.values()),'actual_internal_annex_openings_or_furniture_verified':False,'requires_exact_patch_union_not_room_bounding_rectangle':True,'elapsed_cpu_seconds':time.monotonic()-started};return doc

if __name__=='__main__':
 p=HERE/'SOURCE_FLOOR_LUXURY_BALANCED_V3.json';d=json.loads(p.read_text());d['pre_annex_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();d=apply(d);out=HERE/'SOURCE_FLOOR_LUXURY_ANNEX_V3.json';out.write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d['area_progress'],indent=2))
