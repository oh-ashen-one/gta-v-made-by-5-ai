#!/usr/bin/env python3
"""One bounded20-cell typed physical batch from immutable endpoint-v3 Y."""
import argparse
from collections import Counter,defaultdict
import hashlib
import json
import math
from pathlib import Path
import shutil
import sqlite3
import subprocess
import time

import cpu_job
import typed_physical_v1 as T
import compile_roads_semantic_v2 as K

MAX_PART_BYTES=24*1024**2
MAX_PART_VERTICES=180000
BOUNDS=(-2000.,-2500.,2000.,2000.)


def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda:stream.read(1024**2),b''):h.update(data)
    return h.hexdigest()


def put(path,data):
    return K.write_new(path,K.canonical(data))


def load(args):
    if digest(args.source/'identity.json')!=args.identity:raise ValueError('Wrong exact profile input identity')
    identity=json.loads((args.source/'identity.json').read_bytes());manifest=K.read_bound(args.source,identity['manifest'])
    status=json.loads((args.source/'supervisor.json').read_bytes())
    if status.get('status')!='COMPLETE' or status.get('worker_exit')!=0:raise ValueError('Profile producer not terminal/successful')
    if manifest.get('physical_tiles'):raise ValueError('Expected immutable graph/profile-only v3 input')
    recipe=manifest['source_metric_recipe']
    if digest(args.source/'work.sqlite')!=recipe['database_sha256']:raise ValueError('Profile database changed')
    db=sqlite3.connect('file:'+str(args.source/'work.sqlite')+'?mode=ro',uri=True)
    db.execute('pragma cache_size=-65536');db.execute('pragma temp_store=FILE');db.execute('pragma mmap_size=0')
    return manifest,db


def cells():
    return [(tx,tz) for tx in range(-2,2) for tz in range(-3,2)]


def cell_clip(tx,tz):
    return [max(BOUNDS[0],tx*1000.),max(BOUNDS[1],tz*1000.),min(BOUNDS[2],(tx+1)*1000.),min(BOUNDS[3],(tz+1)*1000.)]


def select(db):
    selected={};links=defaultdict(list);ledger=[];counts=Counter()
    for identifier,raw_text,policy_text,vertices_text in db.execute('select id,raw,policy,vertices from ways order by id'):
        raw=json.loads(raw_text);policy=json.loads(policy_text);b=raw['source_bounds_xz'];pad=policy['width']['metres']
        if b[2]+pad<BOUNDS[0] or b[0]-pad>BOUNDS[2] or b[3]+pad<BOUNDS[1] or b[1]-pad>BOUNDS[3]:continue
        counts['source_bbox_candidates']+=1
        kind,reason=T.classification(raw,policy)
        if reason:
            ledger.append({'source_way':identifier,'source_name':raw.get('name'),'status':reason,'source_tags':raw['tags']})
            counts[reason]+=1;continue
        ids=json.loads(vertices_text)
        points=[list(db.execute('select x,y,z from vertices where v=?',(v,)).fetchone()) for v in ids]
        base=[db.execute('select base from vertices where v=?',(v,)).fetchone()[0] for v in ids]
        item={'raw':raw,'policy':policy,'ids':ids,'points':points,'class':kind,'profile_minus_preferred_dem':[p[1]-h for p,h in zip(points,base)]}
        selected[identifier]=item;counts['selected_'+kind]+=1
        if len(selected)>20000:raise ValueError('Explicit first-batch source-way work budget exceeded; no truncation')
        for tx,tz in cells():
            c=cell_clip(tx,tz)
            if b[2]+pad>=c[0] and b[0]-pad<=c[2] and b[3]+pad>=c[1] and b[1]-pad<=c[3]:links[(tx,tz)].append(identifier)
    return selected,links,ledger,counts


def emit_cell(args,tx,tz,ids,selected,radii):
    tile=f'{tx}_{tz}';clip=cell_clip(tx,tz);parts=[];part=[];vertices=0;size=0;counts=Counter();coverage=Counter();unresolved={};limits=defaultdict(float)
    def flush():
        nonlocal part,vertices,size
        if not part:return
        key=f'{tile}.p{len(parts):03d}'
        data={'schema':K.SCHEMA,'tile':key,'spatial_tile_key':tile,'features':part,
              'physical_scope':'BOUNDED_TYPED_WORK_BATCH_WITH_EXPLICIT_UNRESOLVED_SOURCE_CASES','surface_contract':T.SCHEMA}
        raw=K.canonical(data)
        if len(raw)>MAX_PART_BYTES or vertices>MAX_PART_VERTICES:raise ValueError('Typed part exceeds explicit native memory contract')
        descriptor=K.write_new(args.output/'physical'/f'{key}.json',raw)
        descriptor.update(file=f'physical/{key}.json',tile=key,spatial_tile_key=tile,source_bounds_xz=clip,vertices=vertices)
        parts.append(descriptor);part=[];vertices=0;size=0
    for identifier in ids:
        item=selected[identifier]
        feature,error=T.build_feature(identifier,item['raw'],item['policy'],item['ids'],item['points'],radii,clip,tile)
        if error:
            counts[error['status']]+=1
            if error['status']!='NO_ACTUAL_CLIPPED_SURFACE':unresolved[identifier]=dict(error,source_tags=item['raw']['tags'],source_name=item['raw'].get('name'))
            continue
        local_vertices=len(feature['mesh']['vertices_local_xyz'])+len(feature.get('visual_mesh',{}).get('vertices_local_xyz',[]))
        local_size=len(K.canonical(feature))
        if local_vertices>MAX_PART_VERTICES or local_size>MAX_PART_BYTES-65536:raise ValueError('One source fragment requires finer physical partition; no deletion or truncation')
        if part and (vertices+local_vertices>MAX_PART_VERTICES or size+local_size>MAX_PART_BYTES-65536):flush()
        part.append(feature);vertices+=local_vertices;size+=local_size+1
        counts['fragments']+=1;counts['collision_triangles']+=len(feature['mesh']['indices'])//3
        counts['visible_step_triangles']+=len(feature.get('visual_mesh',{}).get('indices',[]))//3
        counts['class_'+item['class']]+=1;coverage[identifier]+=1
        limits[item['class']]=max(limits[item['class']],feature['mesh']['maximum_emitted_surface_slope'])
        K.budget()
    flush()
    receipt={'spatial_tile_key':tile,'source_clip':clip,'parts':parts,'counts':dict(counts),'maximum_emitted_slope_by_class':dict(limits),'coverage':dict(coverage),'unresolved':list(unresolved.values())}
    put(args.output/'tile-receipts'/f'{tile}.json',receipt)
    return receipt


def worker(args):
    cpu_job.worker_guard(args);started=time.monotonic();manifest,db=load(args)
    if shutil.disk_usage(args.output).free<args.minimum_free_bytes:raise ValueError('Direct free-space reserve unavailable')
    for relative,expected_sha in [('work.sqlite',manifest['source_metric_recipe']['database_sha256']),
                                  (manifest['source_metric_recipe']['inference']['file'],manifest['source_metric_recipe']['inference']['sha256'])]:
        source=args.source/relative;target=args.output/relative
        if Path(relative).is_absolute() or '..' in Path(relative).parts or digest(source)!=expected_sha:raise ValueError('Unsafe or changed immutable profile resource')
        target.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run(['/bin/cp','-c',str(source),str(target)],check=True)
        if digest(target)!=expected_sha:raise ValueError('Profile clone did not preserve exact parent bytes')
    for descriptor in manifest['graph_chunks']:
        relative=Path(descriptor['file']);source=args.source/relative;target=args.output/relative
        if source.stat().st_size!=descriptor['bytes'] or digest(source)!=descriptor['sha256']:raise ValueError('Graph descriptor mismatch before APFS clone')
        target.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run(['/bin/cp','-c',str(source),str(target)],check=True)
        if digest(target)!=descriptor['sha256']:raise ValueError('Graph clone did not preserve exact v3 payload')
    selected,links,ledger,counts=select(db)
    put(args.output/'selection.json',{'counts':dict(counts),'unemitted':ledger,'explicit_bounds_xz':list(BOUNDS),'no_world_boundary_claim':True})
    radii=dict(db.execute('select v,radius from render_hubs'));descriptors=[];covered=Counter();unresolved={row['source_way']:row for row in ledger};parts_by_cell={};totals=Counter();maxima=defaultdict(float)
    for index,(tx,tz) in enumerate(cells()):
        receipt=emit_cell(args,tx,tz,links[(tx,tz)],selected,radii)
        descriptors.extend(receipt['parts']);parts_by_cell[receipt['spatial_tile_key']]=[p['tile'] for p in receipt['parts']]
        covered.update(receipt['coverage']);totals.update(receipt['counts'])
        unresolved.update({row['source_way']:row for row in receipt['unresolved']})
        for kind,value in receipt['maximum_emitted_slope_by_class'].items():maxima[kind]=max(maxima[kind],value)
        print(json.dumps({'stage':'typed_physical_cell','complete':index+1,'total':20,'cell':receipt['spatial_tile_key'],'parts':len(receipt['parts']),'fragments':receipt['counts'].get('fragments',0),'unresolved_stairways':len(receipt['unresolved'])}),flush=True)
    remaining=[identifier for identifier in selected if identifier not in covered and identifier not in unresolved]
    terrain={'status':'PROFILE_MINUS_COARSE_DEM_DIAGNOSTIC_NOT_ACTUAL_NATIVE_TERRAIN_INTERSECTION',
             'ways':[{'source_way':key,'minimum_m':min(item['profile_minus_preferred_dem']),'maximum_m':max(item['profile_minus_preferred_dem'])} for key,item in selected.items()],
             'cut_fill_tunnel_cover_undersides_rails_and_water_clearance_built':False}
    put(args.output/'terrain-profile-discrepancies.json',terrain)
    coverage={'status':'BOUNDED_TYPED_PARTIAL_PHYSICAL_COVERAGE_EXPLICIT_GAPS_REMAIN','selection_counts':dict(counts),
              'emitted_way_count':len(covered),'per_original_way_fragments':dict(covered),'unresolved_source_cases':list(unresolved.values()),
              'bbox_candidates_with_no_actual_clipped_geometry':remaining,'source_facts_or_counts_rewritten':False}
    coverage_descriptor=put(args.output/'coverage.json',coverage)
    db.close()
    result_manifest=dict(manifest)
    result_manifest.update(version=6,physical_tiles=descriptors,spatial_tile_parts=parts_by_cell,
        parent_profile_identity_sha256=args.identity,surface_contract=T.SCHEMA,
        physical_scope={'bounds_xz':list(BOUNDS),'spatial_cells':20,'parts':len(descriptors),'status':coverage['status'],
                        'coverage':coverage_descriptor,'graph_and_physical_same_profile_identity':args.identity,
                        'terrain_cut_fill_cover_or_native_acceptance':False},
        typed_physical_recipe={'schema':T.SCHEMA,'producer_sha256':digest(Path(__file__)),'geometry_sha256':digest(Path(T.__file__)),
                               'profile_database_sha256':manifest['source_metric_recipe']['database_sha256'],
                               'per_class_emitted_slope_caps':T.EMITTED_LIMIT,'per_class_required_native_slope_caps':T.NATIVE_LIMIT,
                               'source_step_count_and_incline_conflicts_remain_explicit':True},
        resources={'wall_seconds':time.monotonic()-started,'peak_rss_bytes':K.budget(),'logical_output_budget_bytes':args.output_budget_bytes,
                   'minimum_direct_free_bytes':args.minimum_free_bytes})
    descriptor=put(args.output/'manifest.json',result_manifest)
    put(args.output/'identity.json',{'schema':K.IDENTITY,'version':6,'manifest':descriptor,'snapshot_manifest_sha256':manifest['snapshot_manifest_sha256'],'parent_profile_identity_sha256':args.identity})
    result={'status':'TYPED_BATCH_WRITTEN_WITH_EXPLICIT_GAPS_AUDIT_AND_NATIVE_REQUIRED','identity_sha256':digest(args.output/'identity.json'),
            'parent_profile_identity_sha256':args.identity,'counts':dict(totals),'emitted_original_ways':len(covered),
            'unresolved_source_cases':len(unresolved),'maximum_emitted_slope_by_class':dict(maxima),'resources':result_manifest['resources'],
            'whole_city_or_complete_stairs_or_native_acceptance':False}
    put(args.output/'result.json',result);return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--identity',required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--output-budget-bytes',type=int,default=8*1024**3);parser.add_argument('--minimum-free-bytes',type=int,default=12*1024**3)
    parser.add_argument('--worker',action='store_true');parser.add_argument('--job-token');args=parser.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'typed-physical-central20-v1',protected=[args.source])
        print(json.dumps(result),flush=True)
        if result.get('status')=='INCOMPLETE':raise SystemExit(1)
    except Exception as error:
        print(json.dumps({'status':'TYPED_PHYSICAL_BATCH_REJECTED_NO_ADOPTION','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
