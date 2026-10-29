"""Data-driven eligibility from every retained unexplained country seam failure.

No source IDs are hardcoded. Healthy source ways/joins receive no speculative
overlap proposal. The eventual global solve and full country audits still
check propagated changes and previously unhandled joins.
"""
from collections import defaultdict
import json
import math

import numpy as np

import audit_national as audit
import protected_road_branches as branches


def select(args,source_db):
    raw=(args.failure_audit/'seam-audit.json').read_bytes();failure=json.loads(raw)
    if failure['country_identity_sha256']!=args.failure_identity:
        raise ValueError('Failed full-country audit identity mismatch')
    rows=failure['outlier_examples']
    if len(rows)!=failure['counts']['outlier_comparisons_over5mm']:
        raise ValueError('Truncated full audit is not a complete repair eligibility inventory')
    if failure['counts'].get('missing_source_surface_samples',0):
        raise ValueError('Missing source surfaces require explicit repair inventory, not selective omission')
    if audit.digest(args.failure_country/'identity.json')!=args.failure_identity:
        raise ValueError('Failed country identity changed')
    identity=json.loads((args.failure_country/'identity.json').read_bytes())
    manifest=audit.read(args.failure_country,identity['manifest'])
    if manifest['parent_road_identity_sha256']!=args.identity:
        raise ValueError('Failed country is not derived from the exact base profile')
    needed={r[k] for r in rows for k in ('from','other')};cells=set()
    for row in rows:
        tx,tz=math.floor(row['xz'][0]/1000),math.floor(row['xz'][1]/1000)
        cells.update(f'{tx+dx}_{tz+dz}' for dx in (-1,0,1) for dz in (-1,0,1))
    pieces=defaultdict(list)
    for descriptor in manifest['physical_tiles']:
        if descriptor['spatial_tile_key'] not in cells:continue
        for feature in audit.read(args.failure_country,descriptor)['features']:
            if feature['id'] in needed:pieces[feature['id']].append(audit.triangle_table(feature))
    tables={key:tuple(np.concatenate([part[i] for part in parts]) for i in range(4)) for key,parts in pieces.items()}
    records=branches.discover(source_db,needed);rules=branches.build_rules(source_db,records)
    find,_=branches.transition_groups(source_db)
    by_way={key:branches.way_data(source_db,key) for key in needed}
    failed_groups=set();classified=[];protected_count=0
    for row in rows:
        group=row['group'];x,z=row['xz'];kept=[];proof=[];raw_values=[]
        for key in (row['from'],row['other']):
            if key not in tables:raise ValueError('Missing actual mesh for failed source way')
            values=audit.heights(tables[key],x,z)
            if not values:raise ValueError('Missing actual support surface at recorded failed join')
            raw_values.append(values)
            ids=by_way[key][2]
            candidates=[i for i,v in enumerate(ids) if find(v)==find(group)]
            if len(candidates)!=1:
                # An ambiguous repeated node cannot receive an inferred level waiver.
                kept.append(values);continue
            remaining,explained=branches.partition(values,key,candidates[0],x,z,rules)
            kept.append(remaining);proof.extend(explained)
        raw_delta=max(abs(a-b) for a in raw_values[0] for b in raw_values[1])
        if raw_delta<=.005 or abs(raw_delta-row['height_delta_m'])>.00025:
            raise ValueError('Recorded failure does not reproduce in the unchanged actual country mesh')
        delta=max(abs(a-b) for a in kept[0] for b in kept[1])
        if delta<=.005 and proof:
            decision='PROTECTED_OTHER_SOURCE_LEVEL_EXPLAINED';protected_count+=1
        else:
            decision='FAILED_SOURCE_JOIN_REQUIRES_REPAIR';failed_groups.add(group)
        classified.append({**row,'actual_raw_delta_m':raw_delta,'local_branch_delta_m':delta,
                           'decision':decision,'source_branch_proof':proof})
    failed_roots={find(v) for v in failed_groups}
    target_hubs={v for v, in source_db.execute('select v from render_hubs') if find(v) in failed_roots}
    selected_ways=set()
    for v in target_hubs:selected_ways.update(row[0] for row in source_db.execute('select distinct way from occurrences where v=?',(v,)))
    if failed_groups and (not target_hubs or not selected_ways):raise ValueError('Failed joins have no exact original-node repair targets')
    result={'status':'COMPLETE_MEASURED_SOURCE_JOIN_ELIGIBILITY','failed_country_identity_sha256':args.failure_identity,
            'full_failure_receipt_sha256':audit.frozen.sha(raw),'all_outlier_rows':len(rows),'protected_rows':protected_count,
            'unexplained_rows':len(rows)-protected_count,'failed_join_groups':sorted(failed_groups),
            'target_original_vertices':sorted(target_hubs),'selected_incident_source_ways':sorted(selected_ways),
            'classified_rows':classified,'protected_source_portal_records':records,
            'not_a_hardcoded_source_id_allowlist':True,'healthy_joins_not_speculatively_modified':True}
    return result
