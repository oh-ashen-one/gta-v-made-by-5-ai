#!/usr/bin/env python3
"""Fresh, bounded V4 geometry-inference database; immutable source audit."""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import time

import cpu_job
import metric_geometry_v4 as geometry
import compile_roads_semantic_v2 as K


def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for b in iter(lambda:stream.read(1024**2),b''):h.update(b)
    return h.hexdigest()


def source_signature(db):
    h=hashlib.sha256();counts={}
    queries={
        'owners':'select * from owners order by owner',
        'source_nodes':'select * from source_nodes order by id',
        'vertices':'select v,node,grade,x,z,base from vertices order by v',
        'ways':'select * from ways order by id',
        'occurrences':'select * from occurrences order by node,v,way,endpoint',
        'source_edges':'select id,a,b,length,way,seg,car,bicycle,foot,transition from edges order by id',
        'source_supported_ramp_orders':'select * from vertical_orders order by id'}
    for table,query in queries.items():
        h.update(table.encode()+b'\0');count=0
        for row in db.execute(query):h.update(K.canonical(row)+b'\n');count+=1
        counts[table]=count
    return {'sha256':h.hexdigest(),'counts':counts,'explicitly_excluded_inferred_fields':['profile_Y','metric_bounds','edge_height_allowances','geometry_equalities'],'source_XZ_tags_modes_adjacency_and_preferred_DEM_included':True}


def put(path,obj):
    return K.write_new(path,K.canonical(obj))


def worker(args):
    cpu_job.worker_guard(args);started=time.monotonic()
    if digest(args.source/'identity.json')!=args.identity:raise ValueError('Wrong immutable v3 source identity')
    identity=json.loads((args.source/'identity.json').read_bytes());m=K.read_bound(args.source,identity['manifest'])
    expected=m['source_metric_recipe']['database_sha256']
    if digest(args.source/'work.sqlite')!=expected:raise ValueError('Immutable v3 database changed')
    status=json.loads((args.source/'supervisor.json').read_bytes())
    if status.get('status')!='COMPLETE' or status.get('worker_exit')!=0:raise ValueError('Source producer not terminal')
    target=args.output/'work.sqlite';subprocess.run(['/bin/cp','-c',str(args.source/'work.sqlite'),str(target)],check=True)
    if digest(target)!=expected:raise ValueError('Fresh APFS clone differs from input')
    db=sqlite3.connect(target);db.execute('pragma cache_size=-65536');db.execute('pragma mmap_size=0');db.execute('pragma temp_store=FILE')
    before=source_signature(db);put(args.output/'source-before.json',before)
    print(json.dumps({'stage':'v4_geometry_rebuild','source_signature':before['sha256']}),flush=True)
    result=geometry.rebuild(db)
    after=source_signature(db)
    if after!=before:raise ValueError('V4 geometry changed original source facts or protected ramp order')
    put(args.output/'source-after.json',after);put(args.output/'geometry-result.json',result)
    db.close()
    receipt={'status':'V4_GEOMETRY_INFERENCE_SOURCE_AUDITED_NOT_SOLVED_OR_PHYSICAL',
             'input_identity_sha256':args.identity,'input_database_sha256':expected,
             'database_sha256':digest(target),'source_signature':after,
             'unresolved_reliable_flat_stairways':len(result['unresolved_reliable_flat_stairways']),
             'geometry_iterations':len(result['geometry_relaxation_history']),
             'geometry_source_sha256':digest(Path(geometry.__file__)),'wrapper_sha256':digest(Path(__file__)),
             'seconds':time.monotonic()-started,'peak_rss_bytes':K.budget(),'global_profile_or_native_adoption':False}
    put(args.output/'result.json',receipt);return receipt


def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--identity',required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--output-budget-bytes',type=int,default=8*1024**3);p.add_argument('--minimum-free-bytes',type=int,default=12*1024**3)
    p.add_argument('--worker',action='store_true');p.add_argument('--job-token');args=p.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'source-metric-v4-geometry',protected=[args.source])
        print(json.dumps(result),flush=True)
        if result.get('status')=='INCOMPLETE':raise SystemExit(1)
    except Exception as error:print(json.dumps({'status':'V4_GEOMETRY_REJECTED_NO_ADOPTION','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
