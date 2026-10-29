"""Add ONLY full-size wardrobe alcoves with an explicit capsule/door contract.
The1.8m depth contains a0.64m cabinet,0.10m rear reserve and1.06m clear apron;
this is a furnished/useable planning patch, not an area-only sliver.
"""
from pathlib import Path
import json,time,hashlib
import audit_core_layout as g
import annex_luxury_type_areas_v3 as annex
import expand_luxury_rooms_v2 as growth
import audit_luxury_plan_v3 as audit
HERE=Path(__file__).resolve().parent

def possible(f,r,allowed):
 static=[f['core_bank_polygon']]+[c['polygon'] for c in f['corridors']]+([f['bank_connector']] if f['bank_connector'] else [])+([f['lower_public_atrium_void']] if f['lower_public_atrium_void'] else []);ob=[(p,g.axis_bounds(p)) for p in static];result=[];seen=set()
 for existing in annex.patches(r):
  b=g.axis_bounds(existing)
  for side in range(4):
   axis=1 if side in [0,2] else 0;lo=b[axis];hi=b[axis+2]
   for length in [3.,4.,5.,6.,8.]:
    if length>hi-lo-.10:continue
    for at in sorted(set([lo+.05,hi-length-.05,(lo+hi-length)*.5])):
     depth=1.80
     if length*depth>allowed+.001:continue
     if side==0:p=g.rectangle(b[0]-depth,at,b[0],at+length);wall=[[b[0],at],[b[0],at+length]];normal=[-1,0]
     elif side==2:p=g.rectangle(b[2],at,b[2]+depth,at+length);wall=[[b[2],at],[b[2],at+length]];normal=[1,0]
     elif side==1:p=g.rectangle(at,b[1]-depth,at+length,b[1]);wall=[[at,b[1]],[at+length,b[1]]];normal=[0,-1]
     else:p=g.rectangle(at,b[3],at+length,b[3]+depth);wall=[[at,b[3]],[at+length,b[3]]];normal=[0,1]
     key=tuple(round(v,7) for v in g.axis_bounds(p))
     if key in seen:continue
     seen.add(key)
     if not annex.clear(p,f,r,ob):continue
     centre=[(wall[0][i]+wall[1][i])*.5 for i in range(2)];cabinet=[centre[i]+normal[i]*(depth-.10-.32) for i in range(2)];approach=[centre[i]+normal[i]*(depth-.10-.64-.55) for i in range(2)];size=[.64,2.0] if normal[0] else [2.0,.64];body=g.rectangle(cabinet[0]-size[0]/2,cabinet[1]-size[1]/2,cabinet[0]+size[0]/2,cabinet[1]+size[1]/2);capsule=g.rectangle(approach[0]-.38,approach[1]-.38,approach[0]+.38,approach[1]+.38)
     if not g.contains(p,body) or not g.contains(p,capsule) or g.convex_intersection_area(body,capsule)>1e-8:continue
     result.append((length*depth,p,wall,{'schema':'mbs_usable_wardrobe_annex_v1','full_size_cabinet_xyz_m':[size[0],2.20,size[1]],'cabinet_center_own_xz':cabinet,'cabinet_footprint':body,'door_opening_width_m':1.30,'door_center_own_xz':centre,'internal_approach_own_xz':approach,'conservative_capsule_footprint':capsule,'capsule_radius_m':.36,'extra_margin_m':.02,'clear_apron_depth_m':depth-.10-.64,'cabinet_scale':1.0,'static_annex_capsule_clear':True,'main_room_furnishing_route_native_or_actuator_verified':False}))
 return result

def apply(doc):
 start=time.monotonic();changes=[]
 for kind in ['signature_suite','paiza_suite']:
  rr=[(f,r) for f in doc['floors'].values() for r in f['rooms'] if r['unit']['kind']==kind];deficit=140*len(rr)-sum(annex.area(r) for f,r in rr)
  for f,r in sorted(rr,key=lambda x:(annex.area(x[1]),x[1]['id'])):
   if deficit<=.05:break
   if time.monotonic()-start>180:raise RuntimeError('Bounded CPU180s budget exceeded')
   if len(r.get('private_annex_patches',[]))>=10:continue
   candidates=possible(f,r,min(deficit,210-annex.area(r)))
   if not candidates:continue
   gain,p,wall,contract=max(candidates,key=lambda c:c[0]);r.setdefault('private_annex_patches',[]).append({'polygon':p,'area_m2':gain,'shared_wall_segment':wall,'planned_opening_width_m':1.30,'program':'full_size_furnished_wardrobe_annex','typed_fitout_contract':contract,'native_or_asbuilt_verified':False});r['reserved_area_m2']=annex.area(r);deficit-=gain;changes.append({'room_id':r['id'],'area_m2':gain,'kind':kind})
 doc['schema']='mbs_source_luxury_usable_wardrobe_candidate_v6';doc['usable_wardrobe_annexes']=changes;doc['all_category_targets_met']=False;return doc

if __name__=='__main__':
 p=HERE/'SOURCE_FLOOR_LUXURY_CANDIDATE_V5.json';d=json.loads(p.read_text());d['before_v6_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();d=apply(d);p=HERE/'SOURCE_FLOOR_LUXURY_CANDIDATE_V6.json';p.write_text(json.dumps(d,indent=2)+'\n');r=audit.audit(d);r['candidate_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();(HERE/'LUXURY_V6_GEOMETRY_AUDIT.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='failures'},indent=2));print('wardrobes',len(d['usable_wardrobe_annexes']),r['failures'][:10])
