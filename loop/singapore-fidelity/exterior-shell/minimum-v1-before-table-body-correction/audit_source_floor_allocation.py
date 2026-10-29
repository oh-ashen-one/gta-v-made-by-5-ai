"""Independent whole guest-allocation audit; CPU geometry, not gameplay proof."""
from __future__ import annotations
import json,math,hashlib
from pathlib import Path
import audit_core_layout as g
import plan_source_floors as compiler
PATH=Path(__file__).with_name('SOURCE_FLOOR_ALLOCATION_CANDIDATE.json')

def connected(a,b):
 a=g.axis_bounds(a);b=g.axis_bounds(b);dx=min(a[2],b[2])-max(a[0],b[0]);dz=min(a[3],b[3])-max(a[1],b[1]);return (dx>=.76 and dz>=-1e-6) or (dz>=.76 and dx>=-1e-6)

def audit(doc):
 failures=[];checks=0
 def check(label,ok):
  nonlocal checks;checks+=1
  if not ok:failures.append(label)
 original={u['id']:u for f in compiler.INV['hotel_floors'] for u in f['units']};seen={};types={};moves=0
 for f in doc['floors'].values():
  record=next(v for v in compiler.INV['hotel_floors'] if v['id']==f['floor_id']);tower=f['tower'];base=compiler.profile(tower,record['elevation_m']);top=compiler.profile(tower,record['elevation_m']+record['geometry']['clear_height_m'])
  check(f['floor_id']+' remains occupied',bool(f['rooms']))
  bank=compiler.BANKS[tower];hall=g.shifted(g.rectangle(-13.75,-3.5,13.75,-.9),bank)
  corridors=[c['polygon'] for c in f['corridors']]+([f['bank_connector']] if f['bank_connector'] else [])+[hall]
  for i,c in enumerate(corridors):check(f['floor_id']+' corridor source containment '+str(i),g.contains(base,c) and g.contains(top,c))
  reached={len(corridors)-1}
  for _ in corridors:
   new={j for i in reached for j in range(len(corridors)) if connected(corridors[i],corridors[j])};old=len(reached);reached|=new
   if len(reached)==old:break
  check(f['floor_id']+' all corridors connect to physical core hall',len(reached)==len(corridors))
  obstacles=[f['core_bank_polygon']]+([f['lower_public_atrium_void']] if f['lower_public_atrium_void'] else [])+corridors[:-1]
  ground=compiler.ground_ring(tower);gb=g.axis_bounds(ground)
  for i,r in enumerate(f['rooms']):
   uid=r['id'];check(uid+' exact unit identity once',uid in original and uid not in seen and r['unit']==original.get(uid));seen[uid]=True
   check(uid+' physical allocation identity',r['physical_floor_id']==f['floor_id'] and r['original_floor_id']==original[uid]['floor_id'])
   check(uid+' source polygon containment',g.contains(base,r['footprint_own_xz']) and g.contains(top,r['footprint_own_xz']))
   # Exact inverse-affine sweep of each axis-aligned room rectangle across
   # the whole storey profile; protects walls/ceilings, not only floor points.
   b=g.axis_bounds(r['footprint_own_xz']);s0=(g.axis_bounds(base)[3]-g.axis_bounds(base)[1])/(gb[3]-gb[1]);s1=(g.axis_bounds(top)[3]-g.axis_bounds(top)[1])/(gb[3]-gb[1]);zs=[gb[3]+(z-gb[3])/s for z in [b[1],b[3]] for s in [s0,s1]]
   check(uid+' continuous full storey volume containment',g.contains(ground,g.rectangle(b[0],min(zs),b[2],max(zs))))
   check(uid+' clears every core void corridor and other room',not any(g.convex_intersection_area(r['footprint_own_xz'],o)>1e-7 for o in obstacles+[q['footprint_own_xz'] for q in f['rooms'][i+1:]]))
   p=r['approach_own_xz']; capsule_square=g.rectangle(p[0]-.38,p[1]-.38,p[0]+.38,p[1]+.38)
   check(uid+' full capsule approach supported by connected circulation',any(g.contains(corridors[j],capsule_square) for j in reached))
   u=r['frontage_own_axis'];v=r['into_room_own_axis'];check(uid+' rigid uncompressed room transform',sum(x*x for x in u)==1 and sum(x*x for x in v)==1 and u[0]*v[0]+u[1]*v[1]==0 and u[0]*v[1]-u[1]*v[0]==1)
   profile=r['profile'];required=compiler.room_profile(r['unit']);check(uid+' full-size prescribed room program',profile['frontage_m']>=required['frontage_m']-1e-8 and profile['depth_m']>=required['depth_m']-1e-8 and r['fitout_contract']['furnishing_scale']==1)
   contract=r['fitout_contract']; w=profile['frontage_m'];d=profile['depth_m'];room=g.rectangle(0,0,w,d);objects=[]
   for b in contract['bedrooms']:
    p=b['bed_center_uv'];sz=b['whole_bed_furniture_envelope_m'];poly=g.rectangle(p[0]-sz[0]/2,p[1]-sz[1]/2,p[0]+sz[0]/2,p[1]+sz[1]/2);objects.append(('bed',poly));check(uid+' retained full bed contained',g.contains(room,poly))
    if r['unit']['is_suite']:check(uid+' full capsule bedroom window aisle',b['clear_window_aisle_m']>=.80)
   for obj in contract['objects']:
    if 'center_uv' not in obj:continue
    p=obj['center_uv'];sz=obj['size_xz_m'];poly=g.rectangle(p[0]-sz[0]/2,p[1]-sz[1]/2,p[0]+sz[0]/2,p[1]+sz[1]/2);objects.append((obj['kind'],poly));check(uid+' full '+obj['kind']+' contained',g.contains(room,poly))
   check(uid+' explicit loose furnishings do not interpenetrate',not any(g.convex_intersection_area(a[1],b[1])>1e-7 for i,a in enumerate(objects) for b in objects[i+1:]))
   ent=r['unit']['entertainment'];types[ent]=types.get(ent,0)+1
   check(uid+' entertainment program retained',contract['entertainment_program']==ent)
   if ent=='billiards':
    table=next((o for o in contract['objects'] if o['kind']=='billiards_table'),None);check(uid+' full table and cue circulation retained',table is not None and table['size_xz_m']==[2.54,1.27] and table['cue_clearance_each_side_m']>=1.45)
    if table:
     q=g.rectangle(*table['cue_clear_rectangle_uv']);check(uid+' full cue area contained and unblocked',g.contains(room,q) and all(k=='billiards_table' or g.convex_intersection_area(q,poly)<1e-7 for k,poly in objects))
   if ent=='media':check(uid+' physical media fitout retained',any(o['kind']=='media_screen' for o in contract['objects']))
   moves+=r['original_floor_id']!=r['physical_floor_id']
 check('exact all1850 original unit set',set(seen)==set(original))
 expected=[f for f in compiler.INV['hotel_floors']+compiler.INV['resort_program_floors'] if f['factory']!='guest_floor_v1']
 check('all57 named program floor records retained byte-semantically',doc['program_records_retained_for_separate_source_polygon_planning']==expected)
 return {'schema':'mbs_source_guest_allocation_audit_v1','checks':checks,'failed':len(failures),'failures':failures,'room_ids':len(seen),'entertainment_programs':types,'explicit_relocations':moves,'allocation_sha256':hashlib.sha256(PATH.read_bytes()).hexdigest(),'program_geometry_planned':False,'native_or_rendered_verified':False,'scope':'All guest room identity and source/core/void/room/corridor geometry plus full furniture envelope and named entertainment program validation. Does not certify native furniture, door swings, public/resort/roof program construction or whole-building fidelity.'}

if __name__=='__main__':
 doc=json.loads(PATH.read_text());result=audit(doc);p=PATH.with_name('SOURCE_FLOOR_ALLOCATION_AUDIT.json');p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='failures'},indent=2));print(result['failures'][:30]);raise SystemExit(bool(result['failed']))
