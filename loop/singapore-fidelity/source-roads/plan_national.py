#!/usr/bin/env python3
"""Streaming national physical coverage estimate; no mesh/engine work."""
import argparse,hashlib,json,math,sqlite3,time
from collections import Counter
from pathlib import Path

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--identity',required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    raw=(args.source/'identity.json').read_bytes()
    if hashlib.sha256(raw).hexdigest()!=args.identity:raise SystemExit('Source road identity mismatch')
    identity=json.loads(raw);mr=(args.source/identity['manifest']['file']).read_bytes()
    if hashlib.sha256(mr).hexdigest()!=identity['manifest']['sha256']:raise SystemExit('Source manifest mismatch')
    manifest=json.loads(mr);db=sqlite3.connect('file:'+str(args.source/'work.sqlite')+'?mode=ro',uri=True);counts=Counter();tiles=Counter();largest=0;began=time.monotonic()
    for identifier,raw,policy in db.execute('select id,raw,policy from ways'):
        counts['source_ways']+=1;item=json.loads(raw);data=json.loads(policy)
        if not data['modes']['car']['bits']:counts['same_R5_noncar_or_unresolved_access_direction_not_physically_selected']+=1;continue
        if data['grade']['level']:counts['same_R5_level_requires_floor_registry_not_selected']+=1;continue
        if data['grade']['structure']=='conflicting_structure':counts['same_R5_conflicting_structure_not_selected']+=1;continue
        counts['eligible_physical_ways']+=1;counts['structure_'+data['grade']['structure']]+=1
        b=item['source_bounds_xz'];pad=data['width']['metres'] # miter <=2half; conservative estimate only.
        x0=math.floor((b[0]-pad)/1000);x1=math.floor((b[2]+pad)/1000);z0=math.floor((b[1]-pad)/1000);z1=math.floor((b[3]+pad)/1000)
        largest=max(largest,(x1-x0+1)*(z1-z0+1))
        for x in range(x0,x1+1):
            for z in range(z0,z1+1):tiles[f'{x}_{z}']+=1
    core=manifest['physical_scope'];ratio=counts['eligible_physical_ways']/core['ways']
    result={'status':'ESTIMATE_ONLY_NOT_PHYSICAL_COMPLETION','source_identity':args.identity,'counts':dict(counts),'candidate_1km_tiles_bbox_upper_estimate':len(tiles),
            'candidate_way_tile_pairs_bbox_upper_estimate':sum(tiles.values()),'maximum_candidates_per_tile':max(tiles.values()),'maximum_bbox_tiles_for_one_way':largest,
            'largest_tiles':tiles.most_common(15),'source_car_way_scale_over_core':ratio,'estimated_triangles_from_R5_mean':round(327872*ratio),
            'rough_runtime_minutes':{'physical_worker':round(max(5,ratio*1.6)),'streamed_audits':round(max(3,ratio*.7))},
            'proposed_limits':{'rss_bytes':2147483648,'cpu_seconds_per_worker':3600,'wall_seconds_per_worker':7200,'one_physical_tile_in_memory':True,'tile_file_bytes':33554432,'partition_vertices':180000},
            'frozen_R5_compiler_change_required':False,'new_wrapper_needed':'Existing export collects whole batch and scans all ways per tile; wrapper indexes segment envelopes then streams per tile, reusing exact frozen ribbon/profile',
            'scope':'Same R5 car-permitted/no-indoor-level policy country-wide. Noncar/conditional/restricted/indoor paths remain fully in graph, not claimed physical. Whole original ways retained; cross-border extensions do not assert territory/land.',
            'estimate_elapsed_seconds':time.monotonic()-began}
    if args.output.exists():raise SystemExit('Fresh estimate receipt required')
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));db.close()

if __name__=='__main__':main()
