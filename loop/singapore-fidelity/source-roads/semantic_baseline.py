#!/usr/bin/env python3
"""Fresh source-semantic baseline from immutable original OSM/DEM facts.

Generated grade IDs may change. Raw tags, original IDs/order/XZ, source
segment direction/access and original-node-only connections are audited.
"""
import argparse
from collections import Counter,OrderedDict
import itertools
import json
import math
from pathlib import Path
import sqlite3
import time

from shapely.geometry import LineString,Polygon

import compile_roads_semantic_v2 as K
import cpu_job
import expand_national as original
import road_semantics_v2 as semantics


def ingest_original_facts(source,db):
    if source.execute('select count(*) from (select node from vertices group by node having max(base)-min(base)>1e-7)').fetchone()[0]:
        raise ValueError('Original preferred DEM reference differs across grades of the same source node')
    db.executemany('insert into owners values(?,?)',source.execute('select owner,descriptor from owners order by owner'))
    db.executemany('insert into source_nodes values(?,?,?)',source.execute('select id,x,z from source_nodes order by id'))
    unknown_nodes={row[0] for row in source.execute("select v.node from vertices v join diagnostics d on cast(d.detail as integer)=v.v where d.kind='unresolved_DEM_GAME_zero_fallback'")}
    cache=OrderedDict();counts=Counter()
    def node_facts(node):
        if node in cache:
            value=cache.pop(node);cache[node]=value;return value
        row=source.execute('select s.x,s.z,v.base from source_nodes s join vertices v on v.node=s.id where s.id=? limit 1',(node,)).fetchone()
        if row is None:raise ValueError('Original ordered source node has no canonical/DEM fact')
        cache[node]=row
        if len(cache)>100000:cache.popitem(last=False)
        return row
    for identifier,owner,name,raw_text,old_policy,old_vertices in source.execute('select id,owner,name,raw,policy,vertices from ways order by owner,id'):
        raw=json.loads(raw_text);tags=raw['tags'];policy=K.way_policy(tags);old_policy=json.loads(old_policy)
        if {k:v for k,v in policy.items() if k!='grade'}!={k:v for k,v in old_policy.items() if k!='grade'}:
            raise ValueError('Non-grade source direction/access/width policy changed')
        ids=[];grade=policy['grade']
        for index,node in enumerate(raw['node_ids']):
            x,z,base=node_facts(node)
            found=db.execute('select v from vertices where node=? and grade=?',(node,grade['key'])).fetchone()
            if found:v=found[0]
            else:
                bounds=semantics.metric_assumption(grade,base)
                v=db.execute('insert into vertices(node,grade,x,z,base,lower_y,upper_y,y) values(?,?,?,?,?,?,?,?)',
                             (node,grade['key'],x,z,base,bounds['lower_y'],bounds['upper_y'],base)).lastrowid
                if node in unknown_nodes:db.execute('insert into diagnostics values(?,?)',('unresolved_DEM_GAME_zero_fallback',str(v)))
            ids.append(v);db.execute('insert into occurrences values(?,?,?,?)',(node,v,identifier,int(index in (0,len(raw['node_ids'])-1))))
        db.execute('insert into ways values(?,?,?,?,?,?)',(identifier,owner,name,raw_text,K.canonical(policy).decode(),K.canonical(ids).decode()))
        for i,(a,b) in enumerate(zip(ids,ids[1:])):
            ax,az=db.execute('select x,z from vertices where v=?',(a,)).fetchone();bx,bz=db.execute('select x,z from vertices where v=?',(b,)).fetchone()
            length=math.hypot(bx-ax,bz-az)
            if length<.000001:
                db.execute('insert into diagnostics values(?,?)',('source_zero_length_segment',identifier+'@'+str(i)));continue
            grade_limit=.12 if policy['modes']['car']['bits'] else .7 if tags.get('highway')=='steps' else .25
            db.execute('insert into edges values(?,?,?,?,?,?,?,?,?,?,?)',(identifier+'@'+str(i),a,b,length,grade_limit*length,identifier,i,*[policy['modes'][mode]['bits'] for mode in K.MODES],0))
        counts['source_ways']+=1;counts['structure_'+grade['structure']]+=1
        if counts['source_ways']%10000==0:
            db.commit();K.budget();print(json.dumps({'stage':'semantic_source_ingest','counts':dict(counts)}),flush=True)
    db.commit();return dict(counts)


def returning_portal_evidence(points,width):
    """Adjacent caps on a short connector are not separate stacked branches.

    A candidate must actually leave the two endpoint footprint neighborhoods
    and return, using its original ordered source polyline. This is evidence
    for a reconstructed nonlocal portal rule, not surveyed deck separation.
    """
    def disk(point):return Polygon([(point[0]+width*.5*math.cos(i*math.tau/16),point[2]+width*.5*math.sin(i*math.tau/16)) for i in range(16)])
    first,last=disk(points[0]),disk(points[-1])
    area=first.intersection(last).area
    outside=LineString([(p[0],p[2]) for p in points]).difference(first.union(last)).length
    return {'endpoint_footprint_overlap_m2':area,'original_source_path_outside_endpoint_footprints_m':outside,
            'has_nonlocal_returning_path':area>1e-8 and outside>1e-8,
            'surveyed_vertical_separation_proved':False}


def install_ramp_orders(db):
    db.execute('create table vertical_orders(id text primary key,lower_v integer,upper_v integer,clearance real,source_way text,evidence text)')
    records=[];diagnostics=Counter()
    for identifier,raw_text,policy_text,vertices_text in db.execute('select id,raw,policy,vertices from ways order by id'):
        raw,policy,ids=json.loads(raw_text),json.loads(policy_text),json.loads(vertices_text);tags=raw['tags']
        if not policy['modes']['car']['bits'] or policy['grade']['level'] or tags.get('service') not in ('driveway','parking_aisle'):continue
        if raw['node_ids'][0]==raw['node_ids'][-1]:continue
        points=[list(db.execute('select x,y,z from vertices where v=?',(v,)).fetchone()) for v in ids]
        width=policy['width']['metres']
        if math.hypot(points[0][0]-points[-1][0],points[0][2]-points[-1][2])>=width:continue
        geometry_evidence=returning_portal_evidence(points,width)
        if geometry_evidence['endpoint_footprint_overlap_m2']<=1e-8:continue
        if not geometry_evidence['has_nonlocal_returning_path']:
            diagnostics['LOCAL_ADJACENT_CAPS_NOT_NONLOCAL_STACKED_PORTALS']+=1
            continue
        neighbor_records=[];orders=[]
        for node in (raw['node_ids'][0],raw['node_ids'][-1]):
            candidates=[]
            for other,raw_other,policy_other in db.execute('select distinct w.id,w.raw,w.policy from occurrences o join ways w on w.id=o.way where o.node=? and w.id!=?',(node,identifier)):
                pol=json.loads(policy_other)
                if not pol['modes']['car']['bits'] or pol['grade']['level'] or pol['grade']['layer'] is None:continue
                candidates.append({'source_way':other,'shared_original_node_id':node,'raw_source_tags':json.loads(raw_other)['tags'],
                                   'effective_order':pol['grade']['layer'],'order_status':pol['grade']['status']})
            layers={c['effective_order'] for c in candidates};orders.append(next(iter(layers)) if len(layers)==1 else None);neighbor_records.append(candidates)
        path=sum(math.hypot(b[0]-a[0],b[2]-a[2]) for a,b in zip(points,points[1:]))
        proposal=semantics.ramp_order_assumption(orders[0],orders[1],source_way_connected=True,ports_overlap=True,
                    original_endpoint_nodes=[raw['node_ids'][0],raw['node_ids'][-1]],available_source_path_m=path)
        diagnostics[proposal['status']]+=1
        if proposal['status']=='INFEASIBLE_LOCAL_GAME_CLEARANCE_REQUIRES_REVIEW':
            raise ValueError('Source-proven ramp cannot meet declared game clearance: '+identifier)
        if proposal['constraint'] is None:continue
        c=proposal['constraint'];endpoints=[ids[0],ids[-1]];record=dict(proposal,source_way=identifier,
                original_source_nodes=[raw['node_ids'][0],raw['node_ids'][-1]],generated_endpoint_vertices=endpoints,
                neighbor_source_evidence=neighbor_records,source_way_tags=tags,
                returning_source_geometry_evidence=geometry_evidence)
        db.execute('insert into vertical_orders values(?,?,?,?,?,?)',('ramp-order/'+identifier,endpoints[c['lower_endpoint']],endpoints[c['upper_endpoint']],c['minimum_game_separation_m'],identifier,K.canonical(record).decode()))
        records.append(record)
    db.commit();return {'records':records,'classification_counts':dict(diagnostics),'relative_constraints':len(records),
                        'source_order_is_not_metric_storey':True,'game_site_gap_m':5.,'navigation_arcs_added':False}


def audit_original_source(source,db):
    counts=Counter()
    for before,after in itertools.zip_longest(source.execute('select * from owners order by owner'),db.execute('select * from owners order by owner')):
        if before!=after:raise ValueError('Original source-owner descriptor changed')
        counts['source_owners']+=1
    for before,after in itertools.zip_longest(source.execute('select * from source_nodes order by id'),db.execute('select * from source_nodes order by id')):
        if before!=after:raise ValueError('Original node ID/coordinate changed')
        counts['original_nodes']+=1
    checked_vertices=set()
    for old,new in itertools.zip_longest(source.execute('select id,owner,name,raw,policy from ways order by id'),db.execute('select id,owner,name,raw,policy,vertices from ways order by id')):
        if old is None or new is None or old[:4]!=new[:4]:raise ValueError('Original source way ID/tags/order/hash/owner changed')
        raw=json.loads(new[3]);policy=json.loads(new[4]);old_policy=json.loads(old[4]);ids=json.loads(new[5])
        if len(ids)!=len(raw['node_ids']) or {k:v for k,v in policy.items() if k!='grade'}!={k:v for k,v in old_policy.items() if k!='grade'}:
            raise ValueError('Original width/direction/access or ordered association changed')
        for node,v in zip(raw['node_ids'],ids):
            row=db.execute('select node,grade,x,z,base,lower_y,upper_y from vertices where v=?',(v,)).fetchone();xy=source.execute('select x,z from source_nodes where id=?',(node,)).fetchone()
            grade=semantics.grade_policy(raw['tags'])
            if row[0]!=node or row[1]!=grade['key'] or row[2:4]!=xy:
                raise ValueError('Derived grade vertex does not retain exact original node/XY')
            if v not in checked_vertices:
                base=source.execute('select base from vertices where node=? limit 1',(node,)).fetchone()[0]
                bounds=semantics.metric_assumption(grade,base)
                if row[4]!=base or row[5]!=bounds['lower_y'] or row[6]!=bounds['upper_y']:
                    raise ValueError('New metric inference did not use unchanged preferred DEM and versioned semantic role')
                checked_vertices.add(v)
            counts['ordered_original_node_associations']+=1
        counts['source_ways']+=1
    old_query='select id,length,way,seg,car,bicycle,foot from edges where transition=0 order by id'
    for old,new in itertools.zip_longest(source.execute(old_query),db.execute(old_query)):
        if old!=new:raise ValueError('Original ordered segment adjacency/direction/access/length changed')
        counts['original_source_segments']+=1
    for a,b in db.execute('select a,b from edges where transition=1'):
        na=db.execute('select node from vertices where v=?',(a,)).fetchone()[0];nb=db.execute('select node from vertices where v=?',(b,)).fetchone()[0]
        if na!=nb:raise ValueError('A derived grade transition merged different original source nodes')
    return {'status':'PASS_ORIGINAL_OSM_IDS_ORDER_XY_MODES_AND_EXPLICIT_NODE_ONLY_CONNECTIONS','counts':dict(counts),
            'generated_grade_vertex_ids_are_versioned':True,'old_generated_grade_identity_is_not_an_immutable_source_fact':True}


def worker(args):
    cpu_job.worker_guard(args);started=time.monotonic();manifest,source=original.source(args)
    db=K.database(args.output/'work.sqlite')
    counts=ingest_original_facts(source,db);transitions=K.add_endpoint_transitions(db);geometry=K.install_geometry_allowances(db)
    original.put(args.output/'ingest-counts.json',{'counts':counts,'derived_grade_transitions':transitions,'geometry':geometry})
    # Source conservation is independently useful even if the later game-height
    # reconstruction rejects a constraint. Do not lose this evidence on a
    # profile failure, or mistake it for physical/runtime acceptance.
    facts=audit_original_source(source,db)
    original.put(args.output/'original-source-audit.json',facts)
    ramps=install_ramp_orders(db);original.put(args.output/'ramp-orders.json',ramps)
    print(json.dumps({'stage':'semantic_global_profile_solve','relative_orders':ramps['relative_constraints']}),flush=True)
    profile=K.solve_profiles(db,conflict_policy='reject')
    graph=K.export_catalogs(db,args.output);db.commit();db.close();source.close();database_sha=original.digest(args.output/'work.sqlite')
    result=dict(manifest)
    result.update(version=4,parent_road_identity_sha256=args.identity,graph_chunks=graph,physical_tiles=[],profile=profile,
        source_semantics_version=semantics.POLICY_VERSION,source_semantics_recipe={
          'semantic_policy_sha256':original.digest(semantics.__file__),'versioned_kernel_sha256':original.digest(K.__file__),
          'baseline_wrapper_sha256':original.digest(__file__),'original_source_database_sha256':args.database_sha,
          'database_sha256':database_sha,'source_facts_unchanged':True,'generated_grade_identity_changed_explicitly':True},
        profile_invariants=facts,surface_height_constraints=geometry,ramp_relative_orders=ramps,
        physical_scope={'status':'SEMANTIC_PROFILE_GRAPH_BASELINE_ONLY_NOT_PHYSICAL_OR_WORLD_ACCEPTANCE'},
        source_semantic_counts=counts,resources={'wall_seconds':time.monotonic()-started,'peak_rss_bytes':K.budget()})
    descriptor=original.put(args.output/'manifest.json',result)
    original.put(args.output/'identity.json',{'schema':K.IDENTITY,'version':4,'manifest':descriptor,
        'snapshot_manifest_sha256':manifest['snapshot_manifest_sha256'],'parent_road_identity_sha256':args.identity})
    receipt={'status':'SEMANTIC_BASELINE_COMPLETE_SOURCE_PROFILE_GRAPH_NOT_COUNTRY_ACCEPTANCE',
        'identity_sha256':original.digest(args.output/'identity.json'),'database_sha256':database_sha,
        'counts':counts,'profile':profile,'original_source_audit':facts,'resources':result['resources']}
    original.put(args.output/'result.json',receipt);return receipt


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--identity',required=True)
    parser.add_argument('--database-sha',required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--worker',action='store_true');parser.add_argument('--job-token');args=parser.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'source-semantic-baseline-v2',protected=[args.source])
        print(json.dumps(result),flush=True)
        if result.get('status')=='INCOMPLETE':raise SystemExit(1)
    except Exception as error:
        print(json.dumps({'status':'SEMANTIC_BASELINE_FAILED_OR_UNRESOLVED_NO_ADOPTION','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
