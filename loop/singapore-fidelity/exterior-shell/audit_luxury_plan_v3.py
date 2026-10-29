"""Independent all-ID/source-volume/circulation/annex audit for luxury v3."""
from pathlib import Path
import json,hashlib,collections,math
import audit_core_layout as g
import plan_source_floors as source
import annex_luxury_type_areas_v3 as rooms
from audit_source_floor_allocation import connected
HERE=Path(__file__).resolve().parent

def audit(doc):
 checks=0;failures=[]
 def check(label,ok):
  nonlocal checks;checks+=1
  if not ok:failures.append(label)
 original={u['id']:u for f in source.INV['hotel_floors'] for u in f['units']};seen={};typeareas=collections.Counter();types=collections.Counter();suites=0;relocations=0;cross=0;patchcount=0
 for f in doc['floors'].values():
  record=next(q for q in source.INV['hotel_floors'] if q['id']==f['floor_id']);base=source.profile(f['tower'],record['elevation_m']);top=source.profile(f['tower'],record['elevation_m']+record['geometry']['clear_height_m']);ground=source.ground_ring(f['tower']);gb=g.axis_bounds(ground);s0=(g.axis_bounds(base)[3]-g.axis_bounds(base)[1])/(gb[3]-gb[1]);s1=(g.axis_bounds(top)[3]-g.axis_bounds(top)[1])/(gb[3]-gb[1]);bank=source.BANKS[f['tower']];hall=g.shifted(g.rectangle(-13.75,-3.5,13.75,-.9),bank)
  corridors=[c['polygon'] for c in f['corridors']]+([f['bank_connector']] if f['bank_connector'] else [])+[hall];reached={len(corridors)-1}
  for _ in corridors:
   old=len(reached);reached|={j for i in reached for j in range(len(corridors)) if connected(corridors[i],corridors[j])}
   if old==len(reached):break
  check(f['floor_id']+' connected public circulation',len(reached)==len(corridors))
  check(f['floor_id']+' occupied original floor',bool(f['rooms']))
  for i,p in enumerate(corridors):check(f['floor_id']+' corridor source contained '+str(i),g.contains(base,p) and g.contains(top,p))
  forbidden=[f['core_bank_polygon']]+corridors[:-1]+([f['lower_public_atrium_void']] if f['lower_public_atrium_void'] else [])
  used=[]
  for r in f['rooms']:
   uid=r['id'];check(uid+' original identity/type/bedroom retained exactly once',uid in original and uid not in seen and original.get(uid)==r['unit']);seen[uid]=1;suites+=r['unit']['is_suite'];relocations+=r['original_floor_id']!=r['physical_floor_id'];cross+=r['original_floor_id'].split('-')[0]!=f['tower'];types[r['unit']['kind']]+=1;typeareas[r['unit']['kind']]+=rooms.area(r)
   check(uid+' physical floor coherent',r['physical_floor_id']==f['floor_id'])
   patches=rooms.patches(r);own=[];patchcount+=len(patches)
   for j,p in enumerate(patches):
    check(uid+' patch '+str(j)+' source base/ceiling containment',g.contains(base,p) and g.contains(top,p))
    b=g.axis_bounds(p);zs=[gb[3]+(z-gb[3])/s for z in [b[1],b[3]] for s in [s0,s1]]
    check(uid+' patch '+str(j)+' continuous full-height containment',g.contains(ground,g.rectangle(b[0],min(zs),b[2],max(zs))))
    check(uid+' patch '+str(j)+' core/void/corridor/other room exclusion',not any(g.convex_intersection_area(p,o)>1e-7 for o in forbidden+used+own));own.append(p)
   # Connectivity is an actual >=1.3m wall/opening plan, never a disconnected
   # patch counted toward area. A tiny actual party-wall connector may join it.
   attached={0}
   for _ in patches:
    old=len(attached);attached|={j for i in attached for j in range(len(patches)) if connected(patches[i],patches[j])}
    if old==len(attached):break
   check(uid+' all reserved patches attached',len(attached)==len(patches));used.extend(patches)
   p=r['approach_own_xz'];square=g.rectangle(p[0]-.38,p[1]-.38,p[0]+.38,p[1]+.38)
   check(uid+' full capsule approach on connected public floor',any(g.contains(corridors[j],square) for j in reached))
   u=r['frontage_own_axis'];v=r['into_room_own_axis'];check(uid+' proper unscaled room frame',sum(x*x for x in u)==1 and sum(x*x for x in v)==1 and u[0]*v[0]+u[1]*v[1]==0 and u[0]*v[1]-u[1]*v[0]==1)
 check('all1850 original identities',set(seen)==set(original));check('all775 suites',suites==775)
 expected=[r for r in source.INV['hotel_floors']+source.INV['resort_program_floors'] if r['factory']!='guest_floor_v1'];check('all57 additional programme records retained',doc['program_records_retained_for_separate_source_polygon_planning']==expected)
 target=json.loads((HERE/'LUXURY_TYPE_REFERENCES.json').read_text())['types'];deficits={kind:max(0,target[kind]['target_area_m2']*types[kind]-typeareas[kind]) for kind in types}
 return {'schema':'mbs_luxury_v3_full_geometry_audit','geometry_checks':checks,'geometry_failed':len(failures),'failures':failures,'all_room_ids':len(seen),'suites':suites,'occupied_guest_floors':len(doc['floors']),'exact_room_floor_patches':patchcount,'documented_physical_floor_relocations':relocations,'cross_tower_relocations':cross,'type_area_averages_m2':{k:typeareas[k]/types[k] for k in types},'type_area_deficits_m2':deficits,'area_reference_targets_met':all(v<=.05 for v in deficits.values()),'all_rooms_furnished_or_traversable':False,'native_or_rendered_verified':False,'all57_additional_programme_geometry_complete':False,'scope':'All source envelopes, full-height room patch containment, no core/void/public-corridor/room overlap, attached private annexes, original unit metadata and full-capsule public approaches. This is not furniture/door implementation or native room traversal.'}

if __name__=='__main__':
 p=HERE/'SOURCE_FLOOR_LUXURY_REALLOCATED_V3.json';doc=json.loads(p.read_text());r=audit(doc);r['candidate_sha256']=hashlib.sha256(p.read_bytes()).hexdigest();(HERE/'LUXURY_V3_GEOMETRY_AUDIT.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='failures'},indent=2));print(r['failures'][:30]);raise SystemExit(bool(r['geometry_failed']))
