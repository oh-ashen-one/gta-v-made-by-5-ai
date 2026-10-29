#!/usr/bin/env python3
"""Bounded source-wide v4 constraint/geometry work inventory, no DB mutation."""
import argparse
from collections import Counter,defaultdict
import hashlib
import json
import math
from pathlib import Path
import sqlite3
import time

import cpu_job
import source_physical_policy_v4 as policy


def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for b in iter(lambda:stream.read(1024**2),b''):h.update(b)
    return h.hexdigest()


def worker(args):
    cpu_job.worker_guard(args);started=time.monotonic()
    if digest(args.source/'identity.json')!=args.identity:raise ValueError('Wrong immutable v3 source')
    identity=json.loads((args.source/'identity.json').read_bytes());raw=(args.source/identity['manifest']['file']).read_bytes()
    if len(raw)!=identity['manifest']['bytes'] or hashlib.sha256(raw).hexdigest()!=identity['manifest']['sha256']:raise ValueError('Source manifest changed')
    manifest=json.loads(raw)
    if digest(args.source/'work.sqlite')!=manifest['source_metric_recipe']['database_sha256']:raise ValueError('Source DB changed')
    db=sqlite3.connect('file:'+str(args.source/'work.sqlite')+'?mode=ro',uri=True);db.execute('pragma cache_size=-65536');db.execute('pragma mmap_size=0')
    parents={}
    def find(v):
        while parents.get(v,v)!=v:parents[v]=parents.get(parents[v],parents[v]);v=parents[v]
        return v
    for a,b in db.execute('select a,b from edges where allowance=0 union all select a,b from height_constraints where allowance=0'):
        a,b=find(a),find(b)
        if a!=b:parents[max(a,b)]=min(a,b)
    counts=Counter();stairs=[];changed_roads=[];forced_groups=defaultdict(list)
    for index,(identifier,raw,old,vertices) in enumerate(db.execute('select id,raw,policy,vertices from ways order by id')):
        raw,old,ids=json.loads(raw),json.loads(old),json.loads(vertices)
        role=policy.physical_role(raw['tags'],old);counts['physical_'+role['physical_kind']]+=1
        old_grade=.12 if old['modes']['car']['bits'] else .7 if raw['tags'].get('highway')=='steps' else .25
        grade=role['maximum_game_grade']
        if grade is not None and grade!=old_grade:
            if grade>old_grade:raise ValueError('v4 plan unexpectedly relaxes prior numeric grade')
            changed_roads.append({'source_way':identifier,'source_name':raw.get('name'),'source_highway':raw['tags'].get('highway'),
                                  'previous_game_grade':old_grade,'required_physical_game_grade':grade,
                                  'original_AI_bits_unchanged':role['original_navigation_direction_bits'],
                                  'raw_source_access':role['raw_source_access']})
        if raw['tags'].get('highway')=='steps':
            xyz=[db.execute('select x,y,z from vertices where v=?',(v,)).fetchone() for v in ids]
            run=sum(math.hypot(b[0]-a[0],b[2]-a[2]) for a,b in zip(xyz,xyz[1:]))
            rule=policy.stair_constraints(raw['tags'],raw['node_ids'],run)
            counts['stairs_'+rule['status']]+=1
            group=find(ids[0]);flat=group==find(ids[-1])
            if rule['status']=='SOURCE_SIGN_WITH_EXPLICIT_GAME_RISE_INTERVAL' and flat:
                forced_groups[group].append(identifier);counts['reliable_stairs_forced_flat_by_legacy_geometry']+=1
            stairs.append({'source_way':identifier,'source_tags':raw['tags'],'source_vertex_ids':ids,
                           'existing_game_net_rise_m':xyz[-1][1]-xyz[0][1],
                           'legacy_zero_height_group':group if flat else None,'new_candidate_rule':rule})
        if index and index%50000==0:print(json.dumps({'stage':'v4_source_inventory','ways':index,'steps':len(stairs)}),flush=True)
    geometry_groups={g:{'legacy_group':g,'signed_stairways':ways,'source_vertices':[],'incident_ways':[]} for g,ways in forced_groups.items()}
    for v, in db.execute('select v from vertices'):
        g=find(v)
        if g in geometry_groups:geometry_groups[g]['source_vertices'].append(v)
    for identifier,raw,vertices in db.execute('select id,raw,vertices from ways'):
        matched={find(v) for v in json.loads(vertices)}&geometry_groups.keys()
        for g in matched:geometry_groups[g]['incident_ways'].append({'source_way':identifier,'source_tags':json.loads(raw)['tags']})
    db.close()
    result={'status':'V4_SOURCE_CONSTRAINT_AND_JUNCTION_PLAN_ONLY_NO_PROFILE_OR_GEOMETRY_ADOPTION',
            'source_identity_sha256':args.identity,'source_database_sha256':manifest['source_metric_recipe']['database_sha256'],
            'policy_sha256':digest(Path(policy.__file__)),'counts':dict(counts),
            'vehicle_geometry_grade_tightening':changed_roads,'stair_rules':stairs,'targeted_junction_groups':list(geometry_groups.values()),
            'requires':'Geometry-specific stair portals/landings and scoped junction repair before adding positive rise constraints; no blanket flat-equality deletion',
            'original_source_access_XZ_tags_graph_modified':False,'seconds':time.monotonic()-started}
    with (args.output/'result.json').open('x') as stream:json.dump(result,stream,indent=2,sort_keys=True);stream.write('\n')
    return {k:v for k,v in result.items() if k not in ('vehicle_geometry_grade_tightening','stair_rules','targeted_junction_groups')}


def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--identity',required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--worker',action='store_true');p.add_argument('--job-token');args=p.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'source-metric-v4-plan',protected=[args.source])
        print(json.dumps(result),flush=True)
        if result.get('status')=='INCOMPLETE':raise SystemExit(1)
    except Exception as error:print(json.dumps({'status':'V4_PLAN_FAILED','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
