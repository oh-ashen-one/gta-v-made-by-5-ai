#!/usr/bin/env python3
"""Attest recovered R5 content against its preserved immutable manifest.

Resource timings and ingest-cache provenance legitimately change on a fresh
run. They are reported, never copied to forge the previous artifact identity.
"""
import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(part)
    return value.hexdigest()


def read(root, descriptor):
    relative = Path(descriptor['file'])
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Unsafe artifact descriptor')
    path = root / relative
    if path.is_symlink() or path.stat().st_size != descriptor['bytes'] or digest(path) != descriptor['sha256']:
        raise ValueError('Artifact descriptor differs: ' + str(relative))
    return json.loads(path.read_bytes())


def audit(reference, recovered):
    reference, recovered = Path(reference), Path(recovered)
    before_identity = json.loads((reference / 'identity.json').read_bytes())
    after_identity = json.loads((recovered / 'identity.json').read_bytes())
    before = read(reference, before_identity['manifest'])
    after = read(recovered, after_identity['manifest'])
    allowed_changes = {'resources', 'owned_ingest_reuse'}
    if {k: v for k, v in before.items() if k not in allowed_changes} != {k: v for k, v in after.items() if k not in allowed_changes}:
        differing = sorted(k for k in before.keys() | after.keys() if k not in allowed_changes and before.get(k) != after.get(k))
        raise ValueError('Recovered source/geometry contract differs: ' + ', '.join(differing))
    if {k: v for k, v in before_identity.items() if k != 'manifest'} != {k: v for k, v in after_identity.items() if k != 'manifest'}:
        raise ValueError('Recovered identity lineage differs')
    for field in ('graph_chunks', 'physical_tiles'):
        for descriptor in after[field]:
            read(recovered, descriptor)
    receipt = json.loads((recovered / 'supervisor.json').read_bytes())
    if receipt.get('worker_exit') != 0 or receipt.get('status') != 'complete_compile_not_runtime_acceptance':
        raise ValueError('Recovered compiler did not terminate successfully')
    return {
        'status': 'PASS_EXACT_R5_GRAPH_AND_PHYSICAL_PAYLOAD_REPRODUCTION',
        'original_identity_sha256': digest(reference / 'identity.json'),
        'recovered_identity_sha256': digest(recovered / 'identity.json'),
        'recovered_database_sha256': digest(recovered / 'work.sqlite'),
        'source_city_identity_sha256': after['city_identity_sha256'],
        'graph_chunks_verified': len(after['graph_chunks']),
        'physical_tiles_verified': len(after['physical_tiles']),
        'legitimate_metadata_changes': {k: {'before': before.get(k), 'after': after.get(k)} for k in sorted(allowed_changes) if before.get(k) != after.get(k)},
        'old_manifest_and_identity_unchanged': True,
        'native_or_semantic_v2_or_world_acceptance': False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--recovered', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.reference, args.recovered)
    with args.output.open('x') as stream:
        json.dump(result, stream, sort_keys=True, indent=2)
        stream.write('\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
