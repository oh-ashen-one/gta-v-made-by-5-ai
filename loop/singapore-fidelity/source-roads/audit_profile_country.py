#!/usr/bin/env python3
"""Bounded independent source/profile/graph/mesh and branch-aware seam audits."""
import argparse
from collections import Counter
import hashlib
import itertools
import json
import math
from pathlib import Path
import sqlite3
import time

import numpy as np

import audit_national as audit
import cpu_job
import protected_road_branches as branches


class JsonlParts:
    def __init__(self,root,name):
        self.root,self.name=root,name;self.parts=[];self.stream=None;self.size=0;self.count=0;self.hash=None

    def write(self,row):
        raw=audit.frozen.canonical(row)+b'\n'
        if self.stream is None or self.size+len(raw)>16*1024*1024:
            self.close_part();path=self.root/f'{self.name}-{len(self.parts):04d}.jsonl'
            self.stream=path.open('xb');self.size=0;self.hash=hashlib.sha256()
        self.stream.write(raw);self.hash.update(raw);self.size+=len(raw);self.count+=1

    def close_part(self):
        if self.stream is not None:
            name=Path(self.stream.name).name;self.stream.close()
            self.parts.append({'file':name,'bytes':self.size,'sha256':self.hash.hexdigest()});self.stream=None

    def finish(self):
        self.close_part();return {'rows':self.count,'parts':self.parts,'format':'canonical_json_lines_all_rows_no_truncation'}


def inputs(args):
    manifest,profile,db,index=audit.inputs(args)
    original_identity=json.loads((args.original/'identity.json').read_bytes())
    if audit.digest(args.original/'identity.json')!=args.original_identity:
        raise ValueError('Original R5 identity changed')
    original_manifest=audit.read(args.original,original_identity['manifest'])
    if profile['parent_road_identity_sha256']!=args.original_identity or manifest['r5_source_identity_sha256']!=args.original_identity:
        raise ValueError('New profile/country does not bind original R5 source facts')
    if audit.digest(args.source/'work.sqlite')!=profile['profile_recipe']['database_sha256']:
        raise ValueError('New profile DB hash differs from bound manifest')
    if audit.digest(args.original/'work.sqlite')!=profile['profile_recipe']['parent_database_sha256']:
        raise ValueError('Original R5 DB hash differs from bound lineage')
    if manifest['georeference']!=original_manifest['georeference'] or manifest['snapshot_manifest_sha256']!=original_manifest['snapshot_manifest_sha256']:
        raise ValueError('Frame or source snapshot changed')
    original=sqlite3.connect('file:'+str(args.original/'work.sqlite')+'?mode=ro',uri=True)
    original.executescript('pragma cache_size=-32768;pragma temp_store=FILE;pragma mmap_size=0;')
    return manifest,profile,db,index,original


def audit_profile_source(args,manifest,profile,db,original):
    started=time.monotonic();counts={}
    queries={
      'source_ways':'select id,owner,name,raw,policy,vertices from ways order by id',
      'source_vertices':'select v,node,grade,x,z,base,lower_y,upper_y from vertices order by v',
      'source_occurrences':'select node,v,way,endpoint from occurrences order by node,v,way,endpoint',
      'source_owners':'select owner,descriptor from owners order by owner',
      'navigation_edges':'select id,a,b,length,way,seg,car,bicycle,foot,transition from edges order by id'}
    for name,query in queries.items():
        total=0
        for before,after in itertools.zip_longest(original.execute(query),db.execute(query)):
            if before!=after:raise ValueError('Independent original source/navigation mismatch: '+name)
            total+=1
        counts[name]=total;audit.frozen.budget()
    maximum_shift=0.;changed=0
    for before,after in zip(original.execute('select v,y,lower_y,upper_y from vertices order by v'),db.execute('select v,y from vertices order by v')):
        vertex,y,lo,hi=before
        if vertex!=after[0] or not math.isfinite(after[1]):raise ValueError('Invalid new inferred vertex height')
        old_lo=max(0.,lo-y) if lo is not None else 0.;old_hi=max(0.,y-hi) if hi is not None else 0.
        new_lo=max(0.,lo-after[1]) if lo is not None else 0.;new_hi=max(0.,after[1]-hi) if hi is not None else 0.
        if new_lo>old_lo+1e-6 or new_hi>old_hi+1e-6:raise ValueError('Independent audit found worsened explicit source height bound')
        delta=abs(after[1]-y);maximum_shift=max(maximum_shift,delta);changed+=delta>1e-8
    for before,after in zip(original.execute('select id,allowance from edges order by id'),db.execute('select id,allowance from edges order by id')):
        if before[0]!=after[0] or after[1]>before[1]+1e-12:raise ValueError('Independent grade allowance relaxation')
    edge_error=db.execute('select max(abs(a.y-b.y)-e.allowance) from edges e join vertices a on a.v=e.a join vertices b on b.v=e.b').fetchone()[0] or 0.
    equal_error=db.execute('select max(abs(a.y-b.y)-c.allowance) from height_constraints c join vertices a on a.v=c.a join vertices b on b.v=c.b').fetchone()[0] or 0.
    if edge_error>1e-6 or equal_error>1e-6:raise ValueError('Independent profile slope/equality constraint failure')
    old_conflicts={row[0] for row in original.execute("select detail from diagnostics where kind='incompatible_bridge_tunnel_clearance_constraints'")}
    new_conflicts={row[0] for row in db.execute("select detail from diagnostics where kind='incompatible_bridge_tunnel_clearance_constraints'")}
    if not new_conflicts.issubset(old_conflicts):raise ValueError('New inherited-bound contradiction introduced')
    # Recompute portal facts from the original source and compare actual new Y;
    # do not trust only the producer's protection declarations.
    known=branches.discover(original,{p['source_way'] for p in manifest['protected_levels']})
    for record in known:
        _,_,ids,old_points,_=branches.way_data(original,record['source_way'])
        _,_,new_ids,new_points,_=branches.way_data(db,record['source_way'])
        i,j=record['source_indices'];old_gap=old_points[i][1]-old_points[j][1];new_gap=new_points[i][1]-new_points[j][1]
        if ids!=new_ids or (abs(old_gap)>.005 and (new_gap*old_gap<=0 or abs(new_gap)<abs(old_gap)-1e-6)):
            raise ValueError('Independent protected source-level separation failure')
    rules=branches.build_rules(db,known)
    result={'status':'PASS_INDEPENDENT_ORIGINAL_SOURCE_AND_NEW_PROFILE','country_identity_sha256':args.country_identity,
            'profile_identity_sha256':args.source_identity,'original_identity_sha256':args.original_identity,'counts':counts,
            'maximum_inferred_height_shift_m':maximum_shift,'changed_inferred_heights':changed,
            'maximum_edge_grade_allowance_error_m':edge_error,'maximum_height_equality_error_m':equal_error,
            'inherited_unresolved_bound_conflicts':len(old_conflicts),'remaining_unresolved_bound_conflicts':len(new_conflicts),
            'new_or_exacerbated_bounds':0,'protected_source_portal_pairs_verified':len(known),
            'protected_branch_rule_orientations':sum(len(v) for v in rules.values()),'wall_seconds':time.monotonic()-started,
            'inferred_not_surveyed_or_native_accepted':True}
    audit.put(args.output/'profile-source-audit.json',result);return result


def audit_graph_profile(args,manifest,db):
    counts=Counter();ways_seen=set();vertices_seen=set();edges_seen=set();started=time.monotonic()
    for number,descriptor in enumerate(manifest['graph_chunks'],1):
        graph=audit.read(args.country,descriptor)
        if graph['owner']!=descriptor['owner'] or graph['xy_connectivity_added']:
            raise ValueError('Graph owner or XY navigation policy changed')
        for vertex in graph['vertices']:
            v=vertex['vertex_id'];row=db.execute('select node,grade,x,y,z,base from vertices where v=?',(v,)).fetchone()
            if row is None or vertex['original_node_id']!=row[0] or vertex['grade_key']!=row[1] or vertex['key']!=f'node/{row[0]}|grade/{row[1]}' or vertex['source_xyz']!=list(row[2:5]) or vertex['egm96_preferred_m']!=row[5] or vertex['world_y_is_game_profile'] is not True:
                raise ValueError('Graph source vertex does not exactly match new inferred DB profile')
            vertices_seen.add(v);counts['graph_vertex_records']+=1
        for way in graph['ways']:
            row=db.execute('select owner,raw,policy,vertices from ways where id=?',(way['id'],)).fetchone()
            if row is None or row[0]!=descriptor['owner']:raise ValueError('Graph original source ownership mismatch')
            expected=json.loads(row[1]);expected.update(policy=json.loads(row[2]),vertex_ids=json.loads(row[3]))
            if way!=expected or way['id'] in ways_seen:raise ValueError('Graph source tags/order/IDs/policy changed or duplicated')
            ways_seen.add(way['id']);counts['graph_way_records']+=1
        for edge in graph['edges']:
            row=db.execute('select a,b,length,car,bicycle,foot,way,transition from edges where id=?',(edge['id'],)).fetchone()
            expected={'id':edge['id'],'a':row[0],'b':row[1],'length_m':row[2],
                      'directions':dict(zip(('car','bicycle','foot'),row[3:6])),'source_way':row[6],
                      'grade_transition':bool(row[7])} if row else None
            if edge!=expected:raise ValueError('Graph original edge/access/direction/grade changed')
            edges_seen.add(edge['id']);counts['graph_edge_records']+=1
        if number%100==0:print(json.dumps({'stage':'matched_graph_audit','owners':number}),flush=True)
        audit.frozen.budget()
    if len(ways_seen)!=db.execute('select count(*) from ways').fetchone()[0] or len(vertices_seen)!=db.execute('select count(*) from vertices').fetchone()[0] or len(edges_seen)!=db.execute('select count(*) from edges').fetchone()[0]:
        raise ValueError('Full graph/profile conservation incomplete')
    result={'status':'PASS_ALL_GRAPH_SOURCE_IDS_TOPOLOGY_AND_MATCHED_PROFILE_Y','country_identity_sha256':args.country_identity,
            'counts':dict(counts),'unique_source_ways':len(ways_seen),'unique_source_vertices':len(vertices_seen),
            'unique_original_edges':len(edges_seen),'graph_catalogs':len(manifest['graph_chunks']),
            'wall_seconds':time.monotonic()-started,'native_or_navigation_acceptance':False}
    audit.put(args.output/'graph-profile-audit.json',result);return result


def audit_seams(args,manifest,index,db):
    started=time.monotonic();incidence=audit.build_incidence(args,index,db);by_spatial={}
    for descriptor in manifest['physical_tiles']:by_spatial.setdefault(descriptor['spatial_tile_key'],[]).append(descriptor)
    # Original source identifiers/grade signatures are rechecked by build_rules.
    records=branches.discover(db,{p['source_way'] for p in manifest['protected_levels']})
    rules=branches.build_rules(db,records)
    counts=Counter();maximum=0.;raw_maximum=0.;examples=[];outlier_groups={}
    failures=JsonlParts(args.output,'unexplained-seams');protected=JsonlParts(args.output,'explained-source-levels')
    total=incidence.execute('select count(*) from groups').fetchone()[0]
    for tx,tz in incidence.execute('select distinct tx,tz from groups order by tx,tz').fetchall():
        groups=[];needed=set()
        for group, in incidence.execute('select g from groups where tx=? and tz=?',(tx,tz)):
            rows=incidence.execute('select way,i,width from incidence where g=?',(group,)).fetchall()
            groups.append((group,rows));needed.update(row[0] for row in rows)
        ways={key:json.loads(index.execute('select data from ways where id=?',(key,)).fetchone()[0]) for key in needed}
        pieces={key:[] for key in needed}
        for dx in (-1,0,1):
            for dz in (-1,0,1):
                for descriptor in by_spatial.get(f'{tx+dx}_{tz+dz}',()):
                    for feature in audit.read(args.country,descriptor)['features']:
                        if feature['id'] in needed:pieces[feature['id']].append(audit.triangle_table(feature))
        tables={key:tuple(np.concatenate([item[i] for item in items]) for i in range(4)) for key,items in pieces.items() if items}
        for group,rows in groups:
            incident={r[0] for r in rows};indices={key:[r[1] for r in rows if r[0]==key] for key in incident}
            half=max(r[2]*.5 for r in rows);counts['junction_groups']+=1
            for identifier,node_index,_ in rows:
                points=ways[identifier]['source_points_xyz']
                for step in (-1,1):
                    j=node_index;distance=0.
                    while 0<=j+step<len(points) and distance<half:
                        a,b=points[j],points[j+step];length=math.hypot(b[0]-a[0],b[2]-a[2])
                        if length<1e-9:j+=step;continue
                        extent=min(length,half-distance);steps=max(1,math.ceil(extent/.5))
                        for sample in range(steps+1):
                            along=extent*sample/steps;x=a[0]+(b[0]-a[0])*along/length;z=a[2]+(b[2]-a[2])*along/length
                            own_raw=audit.heights(tables[identifier],x,z) if identifier in tables else []
                            if not own_raw:counts['missing_source_surface_samples']+=1;continue
                            own,own_proof=branches.partition(own_raw,identifier,node_index,x,z,rules)
                            counts['samples']+=1
                            for other in incident:
                                if other==identifier or other not in tables:continue
                                values_raw=audit.heights(tables[other],x,z)
                                if not values_raw:continue
                                if len(indices[other])==1:
                                    values,other_proof=branches.partition(values_raw,other,indices[other][0],x,z,rules)
                                else:values,other_proof=values_raw,[]
                                counts['overlap_comparisons']+=1
                                raw_delta=max(abs(h-v) for h in own_raw for v in values_raw);raw_maximum=max(raw_maximum,raw_delta)
                                delta=max(abs(h-v) for h in own for v in values);maximum=max(maximum,delta)
                                row={'group':group,'from':identifier,'from_node_index':node_index,'other':other,'xz':[x,z],
                                     'height_delta_m':delta,'raw_height_delta_m':raw_delta}
                                if raw_delta>.005 and delta<=.005 and (own_proof or other_proof):
                                    counts['protected_source_level_comparisons']+=1
                                    protected.write({**row,'proof':own_proof+other_proof})
                                if delta>.005:
                                    counts['outlier_comparisons_over5mm']+=1;failures.write(row)
                                    outlier_groups[group]=max(outlier_groups.get(group,0.),delta)
                                    if len(examples)<100:examples.append(row)
                        distance+=length;j+=step
        audit.frozen.budget()
        print(json.dumps({'stage':'branch_aware_country_seams','cell':f'{tx}_{tz}','groups_complete':counts['junction_groups'],
                          'groups_total':total,'max_unexplained_m':maximum,'max_raw_m':raw_maximum}),flush=True)
    failure_catalog,protected_catalog=failures.finish(),protected.finish();incidence.close()
    passed=not counts['outlier_comparisons_over5mm'] and not counts['missing_source_surface_samples']
    result={'status':'PASS_ALL_COUNTRY_BRANCH_AWARE_SOURCE_JUNCTION_SEAMS' if passed else 'REVIEW_REQUIRED_COUNTRY_BRANCH_SEAMS',
            'country_identity_sha256':args.country_identity,'counts':dict(counts),'maximum_unexplained_height_mismatch_m':maximum,
            'maximum_raw_multilevel_height_mismatch_m':raw_maximum,'outlier_examples':examples,
            'outlier_groups':[{'group':g,'maximum_delta_m':delta} for g,delta in sorted(outlier_groups.items())],
            'all_unexplained_records':failure_catalog,'all_protected_source_level_proofs':protected_catalog,
            'protected_branch_policy':{'minimum_inferred_level_gap_m':branches.MIN_SEPARATE_LEVEL_GAP,
                                       'requires_distinct_original_continuation_grades_and_flat_branch_geometry':True,
                                       'requires_positive_current_local_surface':True,'nearest_height_selection':False},
            'wall_seconds':time.monotonic()-started,'one3x3_neighborhood_in_memory':True,
            'scope':'Sampled actual emitted centreline overlap near original-node joins; not all-area/country scene/native-car/terrain/performance/survey acceptance'}
    audit.put(args.output/'seam-audit.json',result);return result


def worker(args):
    cpu_job.worker_guard(args);manifest,profile,db,index,original=inputs(args);results={}
    if args.phase in ('source','all'):
        results['profile_source']=audit_profile_source(args,manifest,profile,db,original)
        results['graph_profile']=audit_graph_profile(args,manifest,db)
        results['mesh']=audit.audit_source(args,manifest,profile,db,index)
    if args.phase in ('seams','all'):results['seams']=audit_seams(args,manifest,index,db)
    original.close();db.close();index.close()
    audit.put(args.output/'result.json',results)
    if any(not r['status'].startswith('PASS_') for r in results.values()):raise ValueError('Complete audit retained unexplained failures; no adoption')
    return results


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--country',type=Path,required=True);parser.add_argument('--country-identity',required=True)
    parser.add_argument('--source',type=Path,required=True);parser.add_argument('--source-identity',required=True)
    parser.add_argument('--original',type=Path,required=True);parser.add_argument('--original-identity',required=True)
    parser.add_argument('--output',type=Path,required=True);parser.add_argument('--phase',choices=('source','seams','all'),default='all')
    parser.add_argument('--worker',action='store_true');parser.add_argument('--job-token');args=parser.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'independent-country-r3-'+args.phase,
                                                               protected=[args.country,args.source,args.original])
        print(json.dumps(result),flush=True)
        if result.get('status')=='INCOMPLETE':raise SystemExit(1)
    except Exception as error:
        print(json.dumps({'status':'COUNTRY_R3_AUDIT_FAILED_OR_REVIEW_NO_ADOPTION','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
