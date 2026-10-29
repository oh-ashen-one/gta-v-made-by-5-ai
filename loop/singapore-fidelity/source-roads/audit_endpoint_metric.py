#!/usr/bin/env python3
"""Independent emitted-graph and inequality audit; no solver/imported kernel."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sqlite3
import time

import cpu_job


def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda:stream.read(1024*1024),b''):value.update(part)
    return value.hexdigest()


def read(root,descriptor):
    relative=Path(descriptor['file'])
    if relative.is_absolute() or '..' in relative.parts:raise ValueError('Unsafe artifact path')
    path=root/relative
    if path.is_symlink() or path.stat().st_size!=descriptor['bytes'] or digest(path)!=descriptor['sha256']:raise ValueError('Artifact hash/length mismatch')
    if descriptor['bytes']>64*1024**2:raise ValueError('Bounded audit JSON size exceeded')
    return json.loads(path.read_bytes())


def put(path,data):
    with path.open('x') as stream:json.dump(data,stream,indent=2,sort_keys=True);stream.write('\n')


def worker(args):
    cpu_job.worker_guard(args);started=time.monotonic()
    if digest(args.artifact/'identity.json')!=args.identity:raise ValueError('Wrong exact endpoint artifact')
    identity=json.loads((args.artifact/'identity.json').read_bytes());manifest=read(args.artifact,identity['manifest'])
    recipe=manifest['source_metric_recipe']
    if digest(args.artifact/'work.sqlite')!=recipe['database_sha256']:raise ValueError('Metric database changed')
    status=json.loads((args.artifact/'supervisor.json').read_bytes())
    if status.get('status')!='COMPLETE' or status.get('worker_exit')!=0:raise ValueError('Producer not terminal/successful')
    if manifest['physical_tiles']:raise ValueError('This profile-only audit must not certify unaudited physical geometry')
    db=sqlite3.connect('file:'+str(args.artifact/'work.sqlite')+'?mode=ro',uri=True)
    db.execute('pragma cache_size=-65536');db.execute('pragma temp_store=FILE');db.execute('pragma mmap_size=0')
    vertices=0;bounds_error=0.
    for v,x,z,y,base,lo,hi in db.execute('select v,x,z,y,base,lower_y,upper_y from vertices'):
        if not all(math.isfinite(n) for n in (x,z,y,base)):raise ValueError('Nonfinite source/profile vertex')
        if lo is not None:bounds_error=max(bounds_error,lo-y)
        if hi is not None:bounds_error=max(bounds_error,y-hi)
        vertices+=1
    maxima={'absolute_metric_bound_error_m':bounds_error};counts={'profile_vertices':vertices}
    for table,metric in [('edges','source_edge_grade_error_m'),('height_constraints','geometry_allowance_error_m')]:
        maximum=0.;count=0
        for ya,yb,allowance in db.execute(f'select a.y,b.y,e.allowance from {table} e join vertices a on a.v=e.a join vertices b on b.v=e.b'):
            maximum=max(maximum,abs(ya-yb)-allowance);count+=1
        maxima[metric]=maximum;counts[table]=count
    for table in ('vertical_orders','structure_metric_orders'):
        maximum=0.;count=0
        for low,high,gap in db.execute(f'select a.y,b.y,e.clearance from {table} e join vertices a on a.v=e.lower_v join vertices b on b.v=e.upper_v'):
            maximum=max(maximum,gap-(high-low));count+=1
        maxima[table+'_error_m']=maximum;counts[table]=count
    if max(maxima.values())>1e-6:raise ValueError('Independent complete inequality audit failed')
    car_edges=0;source_allowance_error=0.
    for length,allowance in db.execute('select length,allowance from edges where transition=0 and car!=0'):
        source_allowance_error=max(source_allowance_error,allowance-.12*length);car_edges+=1
    if source_allowance_error>1e-6:raise ValueError('Car grade limit was widened')
    maxima['car_12percent_allowance_error_m']=source_allowance_error;counts['car_permitted_source_segments']=car_edges
    inference=read(args.artifact,recipe['inference']);portal_error=0.
    for portal in inference['true_portal_source_transitions']:
        a,b=portal['vertices'];na,ya=db.execute('select node,y from vertices where v=?',(a,)).fetchone();nb,yb=db.execute('select node,y from vertices where v=?',(b,)).fetchone()
        if na!=nb or na!=portal['original_node']:raise ValueError('Portal original source-node identity differs')
        portal_error=max(portal_error,abs(ya-yb))
    if portal_error>1e-6:raise ValueError('Source portal is not continuous')
    maxima['continuous_portal_height_error_m']=portal_error;counts['source_portal_transitions']=len(inference['true_portal_source_transitions'])
    emitted=set();occurrences=0
    for index,descriptor in enumerate(manifest['graph_chunks']):
        graph=read(args.artifact,descriptor)
        for vertex in graph['vertices']:
            v=int(vertex['vertex_id']);row=db.execute('select node,grade,x,y,z from vertices where v=?',(v,)).fetchone()
            if row is None or row[0]!=vertex['original_node_id'] or row[1]!=vertex['grade_key'] or list(row[2:])!=vertex['source_xyz']:raise ValueError('Emitted graph vertex disagrees with solved source database')
            emitted.add(v);occurrences+=1
        if index%100==0:print(json.dumps({'stage':'independent_graph_profile_audit','owners':index+1,'unique_vertices':len(emitted)}),flush=True)
    if len(emitted)!=vertices:raise ValueError('Emitted graph does not cover complete solved profile')
    counts.update(emitted_unique_vertices=len(emitted),emitted_vertex_occurrences=occurrences,graph_chunks=len(manifest['graph_chunks']))
    db.close()
    result={'status':'PASS_ALL_PROFILE_INEQUALITIES_AND_EMITTED_GRAPH_ALIGNMENT_ONLY','artifact_identity_sha256':args.identity,
            'database_sha256':recipe['database_sha256'],'counts':counts,'maxima':maxima,'seconds':time.monotonic()-started,
            'source_facts_and_modes_audit':'Separate full original-city catalog audit and before/after source signature remain required',
            'physical_surfaces_native_traversal_terrain_cover_or_surveyed_elevations_proved':False}
    put(args.output/'result.json',result);return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--artifact',type=Path,required=True);parser.add_argument('--identity',required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--worker',action='store_true');parser.add_argument('--job-token');args=parser.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'independent-endpoint-profile-audit',protected=[args.artifact])
        print(json.dumps(result),flush=True)
        if result.get('status')=='INCOMPLETE':raise SystemExit(1)
    except Exception as error:
        print(json.dumps({'status':'INDEPENDENT_PROFILE_AUDIT_FAILED','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
