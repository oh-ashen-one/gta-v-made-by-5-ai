"""Final bounded audit of the already-produced partial support-fixed contract.
No optimizer, source-area change or new allocation is performed here.
"""
from pathlib import Path
import json,hashlib
import audit_core_layout as geometry
import source_facade_bays_v10 as facade
import plan_source_floors as source
from audit_source_floor_allocation import connected
HERE=Path(__file__).resolve().parent

def rectangular_union_contains(rectangle,polygons):
    x0,z0,x1,z1=geometry.axis_bounds(rectangle)
    boxes=[geometry.axis_bounds(p) for p in polygons]
    cuts=sorted(set([x0,x1]+[x for b in boxes for x in [b[0],b[2]] if x0<x<x1]))
    for left,right in zip(cuts,cuts[1:]):
        x=(left+right)*.5
        spans=sorted((max(z0,b[1]),min(z1,b[3])) for b in boxes if b[0]-1e-8<=x<=b[2]+1e-8 and min(z1,b[3])>=max(z0,b[1]))
        covered=z0
        for lo,hi in spans:
            if lo>covered+1e-7:break
            covered=max(covered,hi)
        if covered<z1-1e-7:return False
    return True

def audit(candidate):
    catalogue=json.loads((HERE/'OPERATOR_CATALOGUE_INVENTORY_PROPOSAL_V11.json').read_text())
    expected={u['id']:u for u in catalogue['active_units']}
    seen={};failures=[];checks=0;windows=[];floor_status=[]
    def check(label,ok):
        nonlocal checks
        checks+=1
        if not ok:failures.append(label)
    for floor in candidate['floors'].values():
        before=len(failures);bank=source.BANKS[floor['tower']]
        hall=geometry.shifted(geometry.rectangle(-13.75,-3.5,13.75,-.9),bank)
        corridors=[c['polygon'] for c in floor['corridors']]+([floor['bank_connector']] if floor['bank_connector'] else [])+[hall]
        reached={len(corridors)-1}
        for _ in corridors:
            count=len(reached)
            reached|={j for i in reached for j in range(len(corridors)) if connected(corridors[i],corridors[j])}
            if count==len(reached):break
        check(floor['floor_id']+' public paths connect to core',len(reached)==len(corridors))
        for index,poly in enumerate(corridors):
            check(floor['floor_id']+' support source containment '+str(index),geometry.contains(floor['source_floor_polygon'],poly) and geometry.contains(floor['source_ceiling_polygon'],poly))
        used=[]
        for room in floor['rooms']:
            id=room['id'];poly=room['footprint_own_xz']
            check(id+' unique catalogue identity',id in expected and id not in seen and room['unit']==expected.get(id));seen[id]=True
            check(id+' floor and ceiling source containment',geometry.contains(floor['source_floor_polygon'],poly) and geometry.contains(floor['source_ceiling_polygon'],poly))
            check(id+' exact published category area',abs(abs(geometry.signed_area(poly))-expected[id]['published_average_area_target_m2'])<1e-5)
            obstacles=[floor['core_bank_polygon']]+corridors[:-1]+used+([floor['lower_public_atrium_void']] if floor['lower_public_atrium_void'] else [])
            check(id+' no room core public or void overlap',not any(geometry.convex_intersection_area(poly,ob)>1e-7 for ob in obstacles));used.append(poly)
            q=room['approach_own_xz'];capsule=geometry.rectangle(q[0]-.38,q[1]-.38,q[0]+.38,q[1]+.38)
            check(id+' full capsule on connected support union',rectangular_union_contains(capsule,[corridors[j] for j in reached]))
            window=facade.plan_room(floor,room);windows.append(window)
            check(id+' actual source facade candidate',window['minimum_unit_view_frontage_candidate'])
        floor_status.append({'floor_id':floor['floor_id'],'placed_keys':len(floor['rooms']),'bounded_geometry_checks_passed':before==len(failures),'source_schedule_status':floor['floor_schedule_status']})
    missing={u['id'] for u in candidate['unplaced_units']}
    check('exact1844 active partition',set(seen).isdisjoint(missing) and set(seen)|missing==set(expected))
    check('all1850 legacy records retained',len(candidate['legacy_mapping'])==1850)
    # Explicit negative support control: a real gap cannot pass the union test.
    check('support union rejects a real gap',not rectangular_union_contains(geometry.rectangle(0,0,1,1),[geometry.rectangle(0,0,.49,1),geometry.rectangle(.51,0,1,1)]))
    check('support union accepts adjacent actual pieces',rectangular_union_contains(geometry.rectangle(0,0,1,1),[geometry.rectangle(0,0,.5,1),geometry.rectangle(.5,0,1,1)]))
    return {'schema':'mbs_owner_cutoff_partial_contract_audit','checks':checks,'failed':len(failures),'failures':failures,'assigned_keys':len(seen),'unplaced_keys':len(missing),'placed_suites':sum(r['unit']['is_suite'] for f in candidate['floors'].values() for r in f['rooms']),'floor_status':floor_status,'support_method':'Exact axis-aligned polygon-union coverage of unchanged0.76m square; can straddle actual adjacent floor bodies. No gap/clearance relaxation.','complete_allocation':False,'native_furnishing_or_glazing_verified':False,'source_floor_schedule_not_adopted':True},windows

if __name__=='__main__':
    p=HERE/'OWNER_CUTOFF_PARTIAL_ALLOCATION_SUPPORT_FIXED.json';candidate=json.loads(p.read_text());result,windows=audit(candidate);result['candidate_sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
    (HERE/'OWNER_CUTOFF_FINAL_AUDIT.json').write_text(json.dumps(result,indent=2)+'\n')
    (HERE/'OWNER_CUTOFF_WINDOW_CONTRACTS.json').write_text(json.dumps({'schema':'mbs_source_window_contracts_at_owner_cutoff','candidate_sha256':result['candidate_sha256'],'rooms':windows,'native_glazing_verified':False},indent=2)+'\n')
    print({k:v for k,v in result.items() if k not in ['failures','floor_status']});print(result['failures'][:20])
