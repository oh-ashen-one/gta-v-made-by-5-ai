#!/usr/bin/env python3
"""Separate CPU model for the proposed native translated-anchor representation.

The original flattened-world audit failures remain valid for the old loader.
Only Root's actual transformed native-shape/ray tests can prove the new loader.
"""
import argparse
import json
from pathlib import Path
import numpy as np

import audit_typed_physical as common
import cpu_job


def anchored_walk_audit(feature,origin):
    points,normals,indices=common.mesh_arrays(feature['mesh'])
    anchor=np.asarray(feature['anchor_source_xyz'],dtype=float);origin=np.asarray(origin,dtype=float)
    canonical=points+anchor;world=canonical-origin
    if np.max(np.abs(world))>2048.:return None
    anchor_position=anchor-origin
    if np.max(np.abs(anchor_position))>2048.:
        return {'error':'ANCHOR_REQUIRES_PREFETCH_REBASE','anchor_local':anchor_position.tolist()}
    shape=points.astype('<f4');tri=shape[indices]
    cross=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);length2=np.sum(cross*cross,axis=1)
    good=(cross[:,1]<0)&(length2>=1e-12)
    if not np.all(good):return {'error':'ANCHORED_LOCAL_FLOAT_DEGENERATE_OR_REVERSED','faces':np.flatnonzero(~good)[:20].tolist(),'count':int(np.sum(~good))}
    slopes=np.hypot(cross[:,0],cross[:,2])/-cross[:,1];maximum=float(np.max(slopes));kind=feature['physical_contract']['surface_class']
    if maximum>common.CAPS[kind][1]:return {'error':'ANCHORED_LOCAL_FLOAT_TYPED_GRADE_CAP','maximum':maximum,'cap':common.CAPS[kind][1]}
    # Expected world point error is checked independently of the preserved
    # local shape-normal slope. We do not claim world-rounded vertex deltas
    # equal the physics engine's local-space normal calculation.
    reconstructed=(shape+anchor_position.astype('<f4')).astype('<f4').astype(float)+origin
    error=float(np.max(np.abs(reconstructed-canonical)))
    if error>.00025:return {'error':'ANCHORED_WORLD_CODEC_ERROR','maximum_axis_error_m':error,'unchanged_codec_tolerance_m':.00025}
    raw_tri=points[indices];raw_cross=np.cross(raw_tri[:,1]-raw_tri[:,0],raw_tri[:,2]-raw_tri[:,0])
    emitted=float(np.max(np.hypot(raw_cross[:,0],raw_cross[:,2])/-raw_cross[:,1]))
    if emitted>common.CAPS[kind][0] or np.any(normals[:,1]<=0):raise ValueError('Encoded walking surface did not satisfy original typed contract')
    return {'native_maximum':maximum,'emitted_maximum':emitted,'faces':len(indices),'world_axis_error_m':error}


def main():
    p=argparse.ArgumentParser();p.add_argument('--artifact',type=Path,required=True);p.add_argument('--identity',required=True);p.add_argument('--profile',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--worker',action='store_true');p.add_argument('--job-token');args=p.parse_args()
    try:
        result=common.worker(args,anchored_walk_audit,'encoded_local_shapes_plus_translated_float32_anchor_CPU_MODEL_NOT_NATIVE_PROOF') if args.worker else cpu_job.supervise(args,__file__,'anchored-typed-cpu-model-audit',protected=[args.artifact,args.profile])
        print(json.dumps(result),flush=True)
        if result.get('status') in ('INCOMPLETE','REVIEW_REQUIRED_NATIVE_FLOAT_FAILURES'):raise SystemExit(1)
    except Exception as error:print(json.dumps({'status':'ANCHORED_TYPED_MODEL_AUDIT_FAILED','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
