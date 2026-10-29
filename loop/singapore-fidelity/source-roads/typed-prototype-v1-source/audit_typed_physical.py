#!/usr/bin/env python3
"""Independent typed Float32/source-profile audit; no native gameplay claim."""
import argparse
from collections import Counter,defaultdict
import hashlib
import json
import math
from pathlib import Path
import sqlite3
import time

import numpy as np
import cpu_job

CAPS={'car_ribbon':(.121,.122),'foot_ribbon':(.251,.252),'foot_steps':(.701,.702)}


def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda:stream.read(1024*1024),b''):h.update(data)
    return h.hexdigest()


def read(root,d):
    rel=Path(d['file']);path=root/rel
    if rel.is_absolute() or '..' in rel.parts or path.is_symlink() or d['bytes']>32*1024**2:raise ValueError('Unsafe/oversized typed descriptor')
    if path.stat().st_size!=d['bytes'] or digest(path)!=d['sha256']:raise ValueError('Typed descriptor hash/size mismatch')
    return json.loads(path.read_bytes())


def save(path,value):
    with path.open('x') as stream:json.dump(value,stream,indent=2,sort_keys=True);stream.write('\n')


def mesh_arrays(mesh):
    points=np.asarray(mesh['vertices_local_xyz'],dtype=np.float64);normals=np.asarray(mesh['normals'],dtype=np.float64)
    indices=mesh['indices']
    if points.ndim!=2 or points.shape[1]!=3 or normals.shape!=points.shape or len(indices)%3 or not indices:raise ValueError('Malformed mesh arrays')
    if not all(type(i)is int and 0<=i<len(points) for i in indices):raise ValueError('Noninteger/out-of-range mesh index')
    if not np.isfinite(points).all() or not np.isfinite(normals).all():raise ValueError('Nonfinite mesh')
    if not np.array_equal(points.astype('<f4').astype(float),points):raise ValueError('Mesh is not declared Float32 codec payload')
    if np.max(np.abs(np.sum(normals*normals,axis=1)-1.))>.001:raise ValueError('Mesh normal not unit length')
    return points,normals,np.asarray(indices,dtype=np.int64).reshape(-1,3)


def walk_audit(feature,origin):
    points,normals,indices=mesh_arrays(feature['mesh']);canonical=points+np.asarray(feature['anchor_source_xyz'],dtype=float)
    local=(canonical-np.asarray(origin,dtype=float)).astype('<f4')
    if np.max(np.abs(local))>2048.:return None
    tri=local[indices];cross=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0])
    length2=np.sum(cross*cross,axis=1)
    valid=(cross[:,1]<0)&(length2>=1e-12)
    if not np.all(valid):return {'error':'NATIVE_FLOAT_DEGENERATE_OR_REVERSED','faces':np.flatnonzero(~valid)[:20].tolist(),'count':int(np.sum(~valid))}
    slopes=np.hypot(cross[:,0],cross[:,2])/-cross[:,1]
    maximum=float(np.max(slopes));kind=feature['physical_contract']['surface_class']
    if maximum>CAPS[kind][1]:return {'error':'NATIVE_FLOAT_TYPED_GRADE_CAP','maximum':maximum,'cap':CAPS[kind][1]}
    if np.any(normals[:,1]<=0):raise ValueError('Walking surface normals not upward')
    raw_tri=points[indices];raw_cross=np.cross(raw_tri[:,1]-raw_tri[:,0],raw_tri[:,2]-raw_tri[:,0]);raw_slopes=np.hypot(raw_cross[:,0],raw_cross[:,2])/-raw_cross[:,1]
    if np.any(raw_cross[:,1]>=0) or float(np.max(raw_slopes))>CAPS[kind][0]:raise ValueError('Actual emitted typed surface exceeds contract')
    return {'native_maximum':maximum,'emitted_maximum':float(np.max(raw_slopes)),'faces':len(indices)}


def worker(args):
    cpu_job.worker_guard(args);started=time.monotonic()
    if digest(args.artifact/'identity.json')!=args.identity:raise ValueError('Wrong typed artifact')
    identity=json.loads((args.artifact/'identity.json').read_bytes());manifest=read(args.artifact,identity['manifest'])
    if digest(args.profile/'identity.json')!=manifest['parent_profile_identity_sha256']:raise ValueError('Typed/profile lineage differs')
    profile_identity=json.loads((args.profile/'identity.json').read_bytes());profile_manifest=read(args.profile,profile_identity['manifest'])
    if manifest['graph_chunks']!=profile_manifest['graph_chunks']:raise ValueError('Typed output changed parent graph descriptors')
    for descriptor in manifest['graph_chunks']:read(args.artifact,descriptor)
    expected_db=profile_manifest['source_metric_recipe']['database_sha256']
    if digest(args.artifact/'work.sqlite')!=expected_db:raise ValueError('Typed data mixed another solved database')
    db=sqlite3.connect('file:'+str(args.artifact/'work.sqlite')+'?mode=ro',uri=True);db.execute('pragma cache_size=-65536');db.execute('pragma mmap_size=0')
    counts=Counter();maxima=defaultdict(float);failures=[];cache={};seen=set();frame_checks=Counter()
    for descriptor in manifest['physical_tiles']:
        tile=read(args.artifact,descriptor);tx,tz=map(int,tile['spatial_tile_key'].split('_'));part_vertices=0
        for feature in tile['features']:
            key=feature['id']
            if key not in cache:
                row=db.execute('select raw,policy,vertices from ways where id=?',(key,)).fetchone()
                if row is None:raise ValueError('Physical feature is not original source way')
                raw,policy,ids=json.loads(row[0]),json.loads(row[1]),json.loads(row[2])
                xyz=[list(db.execute('select x,y,z from vertices where v=?',(v,)).fetchone()) for v in ids]
                cache[key]=(raw,policy,ids,xyz)
            raw,policy,ids,xyz=cache[key]
            if feature['name']!=raw.get('name') or feature['source_tags']!=raw['tags'] or feature['policy']!=policy or feature['source_vertex_ids']!=ids or feature['source_points_xyz']!=xyz:raise ValueError('Original source/profile/modes changed in physical fragment')
            if feature['source_feature_sha256']!=raw['source_feature_sha256'] or feature['source_geometry_sha256']!=raw['source_geometry_sha256']:raise ValueError('Original source lineage hashes changed')
            kind=feature['physical_contract']['surface_class'];bits=policy['modes'];tags=raw['tags']
            if kind not in CAPS or feature['physical_contract']['schema']!='source_surface_types_v1':raise ValueError('Unknown native surface type')
            if kind=='car_ribbon' and not bits['car']['bits'] or kind!='car_ribbon' and (bits['car']['bits'] or not bits['foot']['bits']):raise ValueError('Prototype surface class does not match preserved mode policy')
            if (kind=='foot_steps')!=(tags.get('highway')=='steps'):raise ValueError('Steps type/source evidence mismatch')
            if tags.get('area')=='yes':raise ValueError('Area source was silently converted to line ribbon')
            if feature['physical_contract']['maximum_emitted_slope']!=CAPS[kind][0] or feature['physical_contract']['required_native_slope_cap']!=CAPS[kind][1]:raise ValueError('File attempts to redefine fixed typed cap')
            for label,origin in [('cell-centred',[tx*1000.+500.,0.,tz*1000.+500.]),('current-world',[0.,0.,-500.])]:
                result=walk_audit(feature,origin)
                if result is None:frame_checks[label+'_outside_active_frame_skipped']+=1;continue
                frame_checks[label]+=1
                if 'error' in result:failures.append(dict(result,source_way=key,part=descriptor['tile'],frame=label))
                else:
                    maxima[kind]=max(maxima[kind],result['native_maximum']);counts['native_float_faces_checked']+=result['faces']
            part_vertices+=len(feature['mesh']['vertices_local_xyz']);counts['collision_faces']+=len(feature['mesh']['indices'])//3
            if kind=='foot_steps':
                evidence=feature['step_evidence']
                if tags.get('step_count') is not None and evidence['steps']!=int(tags['step_count']):raise ValueError('Source step count rewritten')
                if evidence['original_source_count_changed'] or feature['mesh']['native_collision_uses_identical_topology']:raise ValueError('Incorrect visible/collision stair claim')
                points,normals,indices=mesh_arrays(feature['visual_mesh']);tri=points[indices];cross=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0])
                if np.any(np.sum(cross*normals[indices[:,0]],axis=1)>=0):raise ValueError('Visible stair winding contradicts its normals')
                if tags.get('incline')=='up' and any(b[1]<a[1]-1e-6 for a,b in zip(xyz,xyz[1:])) or tags.get('incline')=='down' and any(b[1]>a[1]+1e-6 for a,b in zip(xyz,xyz[1:])):raise ValueError('Visible stairs contradict original-node-order incline')
                part_vertices+=len(points);counts['visible_stair_faces']+=len(indices)
            counts['class_'+kind]+=1;counts['physical_fragments']+=1;seen.add(key)
        if part_vertices>180000 or descriptor['bytes']>24*1024**2:raise ValueError('Declared part limits exceeded')
        counts['physical_parts']+=1
        print(json.dumps({'stage':'typed_independent_part_audit','part':descriptor['tile'],'complete':counts['physical_parts'],'failures':len(failures)}),flush=True)
    db.close()
    result={'status':'PASS_BOUNDED_TYPED_SOURCE_AND_CPU_NATIVE_FLOAT_CHECKS' if not failures else 'REVIEW_REQUIRED_NATIVE_FLOAT_FAILURES',
            'identity_sha256':args.identity,'counts':dict(counts),'distinct_original_ways':len(seen),'frame_checks':dict(frame_checks),
            'maximum_native_float_slope_by_class':dict(maxima),'failure_count':len(failures),'failures':failures,
            'seconds':time.monotonic()-started,'native_engine_or_traversal_terrain_cover_full_city_stairs_coverage':False}
    save(args.output/'result.json',result);return result


def main():
    p=argparse.ArgumentParser();p.add_argument('--artifact',type=Path,required=True);p.add_argument('--identity',required=True);p.add_argument('--profile',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--worker',action='store_true');p.add_argument('--job-token');args=p.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'typed-physical-independent-audit',protected=[args.artifact,args.profile])
        print(json.dumps(result),flush=True)
        if result.get('status') in ('INCOMPLETE','REVIEW_REQUIRED_NATIVE_FLOAT_FAILURES'):raise SystemExit(1)
    except Exception as error:print(json.dumps({'status':'TYPED_PHYSICAL_AUDIT_FAILED','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
