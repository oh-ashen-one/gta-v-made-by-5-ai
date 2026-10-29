#!/usr/bin/env python3
"""Fresh country mesh export from an explicitly pinned new profile/graph DB."""
import argparse
from collections import Counter
import json
from pathlib import Path
import shutil
import sqlite3
import time

import cpu_job
import expand_national as batch

F = batch.frozen
BATCH_SHA = '7f4ef07893ca1595f566f6953f6d27cc4761177ca1acaaa5c40e652f61f8ccfc'


def source(args):
    if batch.digest(Path(F.__file__)) != batch.EXPECTED_KERNEL or batch.digest(Path(batch.__file__)) != BATCH_SHA:
        raise ValueError('Frozen geometry/producer helper source changed')
    if batch.digest(args.source/'identity.json') != args.identity:
        raise ValueError('Pinned profile identity mismatch')
    lifecycle=json.loads((args.source/'supervisor.json').read_text())
    result=json.loads((args.source/'result.json').read_text())
    if lifecycle['status']!='COMPLETE' or lifecycle['worker_exit']!=0 or result['status']!='PROFILE_GRAPH_CANDIDATE_COMPLETE_NOT_COUNTRY_OR_NATIVE_ACCEPTANCE':
        raise ValueError('New profile is not a terminal successful bounded job')
    if result['identity_sha256']!=args.identity or result['database_sha256']!=args.database_sha:
        raise ValueError('Completed profile result binding mismatch')
    identity=json.loads((args.source/'identity.json').read_bytes())
    manifest=F.read_bound(args.source,identity['manifest'])
    if manifest['profile_recipe']['database_sha256']!=args.database_sha or batch.digest(args.source/'work.sqlite')!=args.database_sha:
        raise ValueError('New profile database changed')
    if manifest['profile_invariants']['status']!='PASS_SOURCE_TOPOLOGY_AND_BOUND_PRESERVATION':
        raise ValueError('Missing complete source/topology/height-bound audit')
    db=sqlite3.connect('file:'+str(args.source/'work.sqlite')+'?mode=ro',uri=True)
    db.executescript('pragma cache_size=-65536;pragma temp_store=FILE;pragma mmap_size=0;')
    return manifest,db


def worker(args):
    cpu_job.worker_guard(args)
    started=time.monotonic();manifest,db=source(args)
    batch.put(args.output/'state.json',{'profile_source_identity':args.identity,'profile_database_sha256':args.database_sha,
                                      'producer_sha256':batch.digest(__file__),'frozen_batch_helper_sha256':BATCH_SHA,
                                      'frozen_kernel_sha256':batch.EXPECTED_KERNEL})
    args.reuse_country=None;args.expected_reuse_index_sha=None
    index=batch.build_index(args,db);radii=dict(db.execute('select v,radius from render_hubs'))
    tiles=index.execute('select tile,tx,tz from tiles order by tx,tz').fetchall()
    for complete,(tile,tx,tz) in enumerate(tiles,1):
        receipt=batch.emit_tile(args,index,tile,tx,tz,radii)
        for way,count in receipt['per_way_fragments'].items():
            index.execute('insert into covered values(?,?) on conflict(way) do update set fragments=fragments+excluded.fragments',(way,count))
        index.execute('update tiles set done=1,receipt=? where tile=?',(F.canonical(receipt).decode(),tile));index.commit()
        print(json.dumps({'stage':'country_r3_physical','complete':complete,'total':len(tiles),'tile':tile,
                          'parts':len(receipt['parts']),'triangles':receipt['counts'].get('triangles',0),'peak_rss':F.budget()}),flush=True)
    missing=index.execute('select count(*) from ways w left join covered c on c.way=w.id where c.way is null').fetchone()[0]
    if missing:raise ValueError('Eligible source roads missing physical geometry: '+str(missing))
    for descriptor in manifest['graph_chunks']:
        raw=(args.source/descriptor['file']).read_bytes()
        if len(raw)!=descriptor['bytes'] or F.sha(raw)!=descriptor['sha256']:
            raise ValueError('New matched graph catalog changed')
        batch.immutable(args.output/descriptor['file'],raw)
    physical=[];groups={};totals=Counter();maximum=0.
    for tile,raw in index.execute('select tile,receipt from tiles order by tile'):
        receipt=json.loads(raw);physical.extend(receipt['parts']);groups[tile]=[p['tile'] for p in receipt['parts']]
        totals.update(receipt['counts']);maximum=max(maximum,receipt['maximum_surface_slope'])
    counts=dict(index.execute('select kind,value from counts'))
    result=dict(manifest)
    result.update(version=3,parent_road_identity_sha256=args.identity,profile_source_identity_sha256=args.identity,
                  r5_source_identity_sha256=manifest['parent_road_identity_sha256'],physical_tiles=physical,physical_tile_groups=groups,
                  physical_scope={'scope':'ALL_SAME_ELIGIBILITY_COUNTRY_SOURCE_ROAD_FOOTPRINTS_NEW_MATCHED_INFERRED_PROFILE',
                                  'source_ways':257845,'eligible_ways':counts['eligible_ways'],'spatial_candidate_tiles':len(tiles),
                                  'physical_parts':len(physical),'source_conservation_missing':missing,'counts':dict(totals),
                                  'maximum_actual_surface_slope':maximum,
                                  'graph_only_exclusions':{k:v for k,v in counts.items() if k.startswith('excluded_')},
                                  'whole_way_cross_border_extensions_not_a_territory_or_land_claim':True},
                  national_builder={'wrapper_sha256':batch.digest(__file__),'frozen_batch_helper_sha256':BATCH_SHA,
                                    'frozen_kernel_sha256':batch.EXPECTED_KERNEL,'source_database_sha256':args.database_sha,
                                    'profile_recomputed_before_this_export':True,'graph_matches_new_profile_source':True},
                  national_validation={'generation_winding_slope_conservation':'PASS','independent_profile_source_mesh_audit':'PENDING',
                                       'branch_aware_seam_audit':'PENDING','native_or_world_adoption':'PENDING'},
                  national_resources={'wall_seconds':time.monotonic()-started,'peak_rss_bytes':F.budget(),'one_spatial_tile_in_memory':True})
    descriptor=batch.put(args.output/'manifest.json',result)
    batch.put(args.output/'identity.json',{'schema':F.IDENTITY,'version':3,'manifest':descriptor,
                                        'snapshot_manifest_sha256':manifest['snapshot_manifest_sha256'],'parent_road_identity_sha256':args.identity})
    db.close();index.close()
    receipt={'status':'COUNTRY_R3_COMPILE_COMPLETE_INDEPENDENT_AUDITS_AND_NATIVE_PENDING',
             'identity_sha256':batch.digest(args.output/'identity.json'),'profile_source_identity_sha256':args.identity,
             'scope':result['physical_scope'],'resources':result['national_resources']}
    batch.put(args.output/'result.json',receipt)
    return receipt


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--identity',required=True)
    parser.add_argument('--database-sha',required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--worker',action='store_true');parser.add_argument('--job-token');args=parser.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'matched-profile-country-r3',protected=[args.source])
        print(json.dumps(result),flush=True)
        if result.get('status')=='INCOMPLETE':raise SystemExit(1)
    except Exception as error:
        print(json.dumps({'status':'COUNTRY_R3_INCOMPLETE_NO_ACCEPTANCE','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
