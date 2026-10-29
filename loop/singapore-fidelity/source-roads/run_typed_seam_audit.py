#!/usr/bin/env python3
"""Owned bounded invocation of the existing independent canonical seam audit."""
import argparse
import json
from pathlib import Path
import runpy
import sys

import cpu_job
import audit_typed_physical as verified


def worker(args):
    cpu_job.worker_guard(args)
    if verified.digest(args.artifact/'identity.json')!=args.identity:raise ValueError('Wrong typed seam input identity')
    identity=json.loads((args.artifact/'identity.json').read_bytes());manifest=verified.read(args.artifact,identity['manifest'])
    for descriptor in manifest['physical_tiles']:verified.read(args.artifact,descriptor)
    if verified.digest(args.artifact/'work.sqlite')!=manifest['typed_physical_recipe']['profile_database_sha256']:raise ValueError('Typed seam database differs from its graph/physical profile')
    old=sys.argv
    try:
        sys.argv=['audit_seams.py','--artifact',str(args.artifact),'--output',str(args.output/'canonical-seams.json')]
        runpy.run_path(str(Path(__file__).with_name('audit_seams.py')),run_name='__main__')
    finally:sys.argv=old
    result=json.loads((args.output/'canonical-seams.json').read_bytes())
    result.update(input_identity_sha256=args.identity,representation='CANONICAL_ENCODED_GEOMETRY_NOT_NATIVE_TRANSFORMED_WORLD_RAYS',
                  numeric_seam_tolerance_m=.005,anchored_codec_tolerance_m=.00025,
                  native_world_seam_or_traversal_acceptance=False)
    with (args.output/'result.json').open('x') as stream:json.dump(result,stream,indent=2,sort_keys=True);stream.write('\n')
    return result


def main():
    p=argparse.ArgumentParser();p.add_argument('--artifact',type=Path,required=True);p.add_argument('--identity',required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--worker',action='store_true');p.add_argument('--job-token');args=p.parse_args()
    try:
        result=worker(args) if args.worker else cpu_job.supervise(args,__file__,'typed-canonical-seam-audit',protected=[args.artifact])
        print(json.dumps({k:v for k,v in result.items() if k!='outliers_over5mm'}),flush=True)
        if result.get('status') in ('INCOMPLETE','REVIEW_REQUIRED_SEAM_OUTLIERS'):raise SystemExit(1)
    except Exception as error:print(json.dumps({'status':'TYPED_SEAM_AUDIT_FAILED','error':str(error)}),flush=True);raise SystemExit(1)


if __name__=='__main__':main()
