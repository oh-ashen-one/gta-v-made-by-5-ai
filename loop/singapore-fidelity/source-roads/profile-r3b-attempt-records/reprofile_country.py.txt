#!/usr/bin/env python3
"""Isolated copied-DB inferred road-profile recipe; never edits R5 or topology."""
import argparse
from collections import Counter
import hashlib
import itertools
import json
from pathlib import Path
import sqlite3
import time

import cpu_job
import expand_national as batch
import profile_overlap as overlap
import protected_road_branches as branches
import select_measured_repairs

KERNEL_SHA = batch.EXPECTED_KERNEL
PROTOTYPE_SHA = '2bcb14310e572a35fa180955b26a548b28d1098fc67789db76a24a9854402f30'
F = batch.frozen


def point_rows(db, ids):
    return [list(db.execute('select x,y,z from vertices where v=?', (v,)).fetchone()) for v in ids]


def continuations(db):
    parents, grades = {}, {}
    def find(v):
        while parents.get(v, v) != v:
            parents[v] = parents.get(parents[v], parents[v])
            v = parents[v]
        return v
    for a, b, ga, gb in db.execute('select e.a,e.b,a.grade,b.grade from edges e join vertices a on a.v=e.a join vertices b on b.v=e.b where e.transition=1'):
        parents[find(a)] = find(b)
        grades.setdefault(a, set()).add(gb)
        grades.setdefault(b, set()).add(ga)
    return find, grades


def propose_geometry(db, output, eligibility=None):
    radii = dict(db.execute('select v,radius from render_hubs'))
    original = dict(radii)
    find, grades = continuations(db)
    db.executescript('create table overlap_proposals(iteration integer,way text,details text);'
                     'create table overlap_equalities(a integer,b integer,primary key(a,b));'
                     'create table protected_levels(way text,a integer,b integer,details text,primary key(way,a,b));'
                     'create table radius_changes(v integer primary key,old_radius real,new_radius real);')
    history = []
    selected_ways = set(eligibility['selected_incident_source_ways']) if eligibility else None
    target_vertices = set(eligibility['target_original_vertices']) if eligibility else None
    if eligibility:
        for record in eligibility['protected_source_portal_records']:
            identifier=record['source_way'];_,policy,ids,points,_=branches.way_data(db,identifier)
            i,j=record['source_indices']
            details=dict(record,source_points_before=[points[i],points[j]],source_grade=policy['grade'],
                         source_arc_length_m=sum(((b[0]-a[0])**2+(b[2]-a[2])**2)**.5 for a,b in zip(points,points[1:])),
                         width=policy['width'],status='PROTECTED_SOURCE_CONTINUATION_LEVELS_NOT_NATIVE_CLEARANCE_ACCEPTANCE')
            db.execute('insert or ignore into protected_levels values(?,?,?,?)',(identifier,ids[i],ids[j],F.canonical(details).decode()))
    for iteration in range(32):
        updates, counts = dict(radii), Counter()
        for identifier, raw, policy, vertices in db.execute('select id,raw,policy,vertices from ways order by id'):
            if selected_ways is not None and identifier not in selected_ways:
                continue
            policy = json.loads(policy)
            if batch.eligible(policy):
                continue
            ids = json.loads(vertices)
            points = point_rows(db, ids)
            report = overlap.propose(points, policy['width']['metres'], [radii.get(v, 0.) for v in ids], ids,
                                     [sorted(grades.get(v, ())) for v in ids], source_ele_tag=policy['grade']['source_ele_tag'])
            counts['eligible_ways'] += 1
            if not report['status'].startswith('HEIGHT_ONLY_'):
                counts[report['status']] += 1
                if eligibility:
                    raise ValueError('Measured failed source way requires unresolved proposal policy: '+identifier)
                continue
            selected_pairs=[pair for pair in report['equalities'] if target_vertices is None or any(v in target_vertices for v in pair)]
            eligible_vertices=set(target_vertices or ())
            eligible_vertices.update(v for pair in selected_pairs for v in pair)
            for pair in selected_pairs:
                db.execute('insert or ignore into overlap_equalities values(?,?)', pair)
            for index, radius in report['radius_overrides'].items():
                v = ids[int(index)]
                if target_vertices is not None and v not in eligible_vertices:
                    continue
                updates[v] = max(updates[v], radius)
            if report['radius_overrides'] or report['equalities'] or report['protected']:
                db.execute('insert into overlap_proposals values(?,?,?)', (iteration, identifier, F.canonical(report).decode()))
            for protected in report['protected']:
                if protected['kind'] == 'PLATEAU_EXTENSION_EXCEEDS_EXISTING_128M_CAP':
                    if target_vertices is not None and ids[protected['hub_index']] not in eligible_vertices:
                        counts['unselected_nonlocal_cap_proposal_not_applied']+=1
                        continue
                    batch.put(output/'rejection.json',{'source_way':identifier,'proposal':protected,'selection':eligibility})
                    raise ValueError('Measured join proposal exceeds existing plateau cap: '+identifier)
                if protected['kind'] != 'DISTINCT_CONTINUATION_GRADES':
                    raise ValueError('Unclassified profile-protection result')
                i, j = protected['source_indices']
                details = dict(protected, source_way=identifier, source_indices=[i, j], vertex_ids=[ids[i], ids[j]],
                               original_node_ids=[db.execute('select node from vertices where v=?', (ids[k],)).fetchone()[0] for k in (i, j)],
                               source_points_before=[points[i], points[j]], source_grade=policy['grade'],
                               source_arc_length_m=sum(((b[0]-a[0])**2+(b[2]-a[2])**2)**.5 for a,b in zip(points,points[1:])),
                               width=policy['width'], status='PROTECTED_SOURCE_CONTINUATION_LEVELS_NOT_NATIVE_CLEARANCE_ACCEPTANCE')
                details['continuation_grades_by_source_index']={str(k):sorted(grades.get(ids[k],())) for k in (i,j)}
                db.execute('insert or ignore into protected_levels values(?,?,?,?)', (identifier, ids[i], ids[j], F.canonical(details).decode()))
            if counts['eligible_ways'] % 5000 == 0:
                db.commit();F.budget()
                print(json.dumps({'stage':'geometry_radius_proposals','iteration':iteration,'counts':dict(counts)}), flush=True)
        maximums = {}
        for v, radius in updates.items():
            maximums[find(v)] = max(maximums.get(find(v), 0.), radius)
        updates = {v: maximums[find(v)] for v in updates}
        changed = sum(updates[v] > radii[v] + 1e-7 for v in radii)
        history.append({'iteration':iteration,'changed_hubs':changed,'counts':dict(counts)})
        db.commit();print(json.dumps({'stage':'geometry_radius_round_complete',**history[-1]}), flush=True)
        if not changed:
            break
        radii = updates
    else:
        raise ValueError('32-round bounded geometry fixed point did not converge')
    for v, radius in radii.items():
        if radius < original[v] or radius > 128.:
            raise ValueError('Profile plateau bounds relaxed')
        if radius > original[v] + 1e-7:
            db.execute('insert into radius_changes values(?,?,?)', (v, original[v], radius))
    db.executemany('update render_hubs set radius=? where v=?', ((r,v) for v,r in radii.items()))
    db.execute('insert or ignore into height_constraints select a,b,0 from overlap_equalities')
    changed_allowances, geometry_equalities = 0, 0
    for identifier, raw, policy, vertices in db.execute('select id,raw,policy,vertices from ways order by id'):
        policy, ids = json.loads(policy), json.loads(vertices)
        points = point_rows(db, ids)
        grade = .12 if policy['modes']['car']['bits'] else .7 if json.loads(raw)['tags'].get('highway') == 'steps' else .25
        layout = F._section_layout(points, policy['width']['metres'], [radii.get(v,0.) for v in ids])
        for i,j in layout['equalities']:
            if ids[i] != ids[j]:
                db.execute('insert or ignore into height_constraints values(?,?,0)', tuple(sorted((ids[i],ids[j]))));geometry_equalities += 1
        for span in layout['spans']:
            key = identifier+'@'+str(span['index'])
            old = db.execute('select allowance from edges where id=?',(key,)).fetchone()
            if old is None:
                continue  # Original zero-horizontal source segments have no routing edge.
            allowance = min(old[0], grade*span['allowance_distance'])
            changed_allowances += allowance < old[0]-1e-10
            db.execute('update edges set allowance=? where id=?',(allowance,key))
    db.commit();F.budget()
    result = {'rounds':history,'changed_hub_radii':db.execute('select count(*) from radius_changes').fetchone()[0],
              'proposed_apron_equalities':db.execute('select count(*) from overlap_equalities').fetchone()[0],
              'new_height_constraint_count':db.execute('select count(*) from height_constraints').fetchone()[0],
              'tightened_edge_allowances':changed_allowances,'protected_pairs':db.execute('select count(*) from protected_levels').fetchone()[0],
              'navigation_or_source_XZ_changed':False,'existing_allowances_only_tightened':True,
              'measured_join_eligibility_required_for_production':True,
              'repair_source_ways':sorted(selected_ways) if selected_ways is not None else 'TARGETED_QA_FIXTURE_ONLY'}
    batch.put(output/'geometry-constraints.json',result)
    return result


def verify_invariants(before, after):
    queries = {
        'ways': 'select * from ways order by id',
        'owners': 'select * from owners order by owner',
        'occurrences': 'select * from occurrences order by node,v,way,endpoint',
        'vertex_source_facts': 'select v,node,grade,x,z,base,lower_y,upper_y from vertices order by v',
        'navigation_edges': 'select id,a,b,length,way,seg,car,bicycle,foot,transition from edges order by id'}
    counts = {}
    for kind, query in queries.items():
        count = 0
        for old,new in itertools.zip_longest(before.execute(query),after.execute(query)):
            if old != new:
                raise ValueError('Original source/navigation invariant changed: '+kind)
            count += 1
        counts[kind] = count
    max_shift, changed, worsened = 0., 0, []
    for old,new in zip(before.execute('select v,y,lower_y,upper_y from vertices order by v'),after.execute('select v,y from vertices order by v')):
        v,y,lo,hi = old
        if v != new[0]:raise ValueError('Source vertex sequence changed')
        shift = abs(new[1]-y);max_shift=max(max_shift,shift);changed += shift>1e-8
        old_lower=max(0.,lo-y) if lo is not None else 0.
        old_upper=max(0.,y-hi) if hi is not None else 0.
        new_lower=max(0.,lo-new[1]) if lo is not None else 0.
        new_upper=max(0.,new[1]-hi) if hi is not None else 0.
        if new_lower > old_lower+1e-6 or new_upper > old_upper+1e-6:worsened.append(v)
    old_conflicts={r[0] for r in before.execute("select detail from diagnostics where kind='incompatible_bridge_tunnel_clearance_constraints'")}
    new_conflicts={r[0] for r in after.execute("select detail from diagnostics where kind='incompatible_bridge_tunnel_clearance_constraints'")}
    if worsened or not new_conflicts.issubset(old_conflicts):
        raise ValueError('New or exacerbated original height-bound contradictions; no profile publication: '+str(worsened[:10]))
    for old,new in zip(before.execute('select id,allowance from edges order by id'),after.execute('select id,allowance from edges order by id')):
        if old[0]!=new[0] or new[1]>old[1]+1e-12:raise ValueError('Existing grade allowance relaxed')
    protected=[]
    for raw, in after.execute('select details from protected_levels order by way,a,b'):
        p=json.loads(raw);a,b=p['vertex_ids'];ya=after.execute('select y from vertices where v=?',(a,)).fetchone()[0];yb=after.execute('select y from vertices where v=?',(b,)).fetchone()[0]
        before_delta=p['source_points_before'][0][1]-p['source_points_before'][1][1]
        after_delta=ya-yb
        if abs(before_delta)>.005 and (before_delta*after_delta<=0 or abs(after_delta)<abs(before_delta)-1e-6):
            raise ValueError('Protected source continuation-level separation was reduced')
        p.update(source_heights_after=[ya,yb],inferred_height_gap_m=abs(after_delta));protected.append(p)
    return {'status':'PASS_SOURCE_TOPOLOGY_AND_BOUND_PRESERVATION','counts':counts,'changed_inferred_vertex_heights':changed,
            'maximum_inferred_height_shift_m':max_shift,'inherited_unresolved_conflicts':len(old_conflicts),'remaining_unresolved_conflicts':len(new_conflicts),
            'new_or_worsened_bounds':0,'protected_levels':protected,'original_IDS_XZ_tags_order_directions_access_unchanged':True}


def worker(args):
    cpu_job.worker_guard(args)
    started=time.monotonic()
    if batch.digest(Path(F.__file__))!=KERNEL_SHA or batch.digest(Path(overlap.__file__))!=PROTOTYPE_SHA:
        raise ValueError('Root-reviewed kernel/prototype source changed')
    manifest,before=batch.source(args)
    eligibility=select_measured_repairs.select(args,before)
    batch.put(args.output/'measured-repair-eligibility.json',eligibility)
    after=sqlite3.connect(args.output/'work.sqlite')
    before.backup(after)
    after.executescript('pragma cache_size=-65536;pragma temp_store=FILE;pragma mmap_size=0;')
    print(json.dumps({'stage':'source_database_copied','source_identity':args.identity}),flush=True)
    geometry=propose_geometry(after,args.output,eligibility)
    print(json.dumps({'stage':'global_profile_solve'}),flush=True)
    profile=F.solve_profiles(after,conflict_policy=manifest['profile']['conflict_policy'])
    invariants=verify_invariants(before,after)
    if profile['maximum_allowance_error_m']>1e-6 or profile['maximum_height_only_constraint_error_m']>1e-6:
        raise ValueError('New global profile violates unchanged grade/equality constraints')
    batch.put(args.output/'profile-invariants.json',invariants)
    print(json.dumps({'stage':'graph_catalogs_export'}),flush=True)
    graph=F.export_catalogs(after,args.output)
    after.commit();after.close();before.close()
    database_sha=batch.digest(args.output/'work.sqlite')
    result=dict(manifest)
    result.update(version=3,parent_road_identity_sha256=args.identity,graph_chunks=graph,physical_tiles=[],profile=profile,
                  surface_height_constraints={**manifest['surface_height_constraints'],'overlap_profile_extension':geometry},
                  profile_recipe={'schema':'source_roads_overlap_profile_v3','wrapper_sha256':batch.digest(__file__),
                                  'prototype_sha256':PROTOTYPE_SHA,'frozen_kernel_sha256':KERNEL_SHA,'parent_database_sha256':args.database_sha,
                                  'database_sha256':database_sha,'source_facts_navigation_unchanged':True,'profile_y_is_inferred_not_survey':True,
                                  'measured_failure_identity_sha256':args.failure_identity,
                                  'measured_failure_receipt_sha256':eligibility['full_failure_receipt_sha256'],
                                  'eligibility_selector_sha256':batch.digest(select_measured_repairs.__file__),
                                  'protected_branch_policy_sha256':batch.digest(branches.__file__),
                                  'protected_level_gap_for_audit_m':2.3,'actual_collision_or_clearance_acceptance':False},
                  protected_levels=invariants['protected_levels'],profile_invariants={k:v for k,v in invariants.items() if k!='protected_levels'},
                  physical_scope={'status':'PROFILE_AND_GRAPH_ONLY_NOT_PHYSICAL_OR_WORLD_ACCEPTANCE'},
                  resources={'wall_seconds':time.monotonic()-started,'peak_rss_bytes':F.budget()})
    descriptor=batch.put(args.output/'manifest.json',result)
    batch.put(args.output/'identity.json',{'schema':F.IDENTITY,'version':3,'manifest':descriptor,
                                        'snapshot_manifest_sha256':manifest['snapshot_manifest_sha256'],'parent_road_identity_sha256':args.identity})
    receipt={'status':'PROFILE_GRAPH_CANDIDATE_COMPLETE_NOT_COUNTRY_OR_NATIVE_ACCEPTANCE','identity_sha256':batch.digest(args.output/'identity.json'),
             'database_sha256':database_sha,'geometry':geometry,'profile':profile,'invariants':{k:v for k,v in invariants.items() if k!='protected_levels'},'resources':result['resources']}
    batch.put(args.output/'result.json',receipt)
    return receipt


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--identity',required=True)
    parser.add_argument('--database-sha',required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--failure-country',type=Path,required=True);parser.add_argument('--failure-identity',required=True)
    parser.add_argument('--failure-audit',type=Path,required=True)
    parser.add_argument('--worker',action='store_true');parser.add_argument('--job-token');args=parser.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'global-road-profile-r3',protected=[args.source])
        print(json.dumps(result),flush=True)
        if result.get('status')=='INCOMPLETE':raise SystemExit(1)
    except Exception as error:
        print(json.dumps({'status':'PROFILE_FAILED_NO_ARTIFACT_ACCEPTANCE','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
