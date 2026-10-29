#!/usr/bin/env python3
"""Attest recovered R5 content against its preserved immutable manifest.

Resource timings and ingest-cache provenance legitimately change on a fresh
run. They are reported, never copied to forge the previous artifact identity.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3


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


def diagnostic_history(before, after, recovered):
    old, new = before.get('diagnostics', {}), after.get('diagnostics', {})
    if old == new:
        return None
    kind = 'incompatible_interior_grade_shared_node'
    if {k: v for k, v in old.items() if k != kind} != {k: v for k, v in new.items() if k != kind}:
        raise ValueError('A non-history diagnostic changed')
    previous, current = old.get(kind), new.get(kind)
    if not all(isinstance(n, int) and not isinstance(n, bool) and n > 0 for n in (previous, current)) or previous < current or previous % current:
        raise ValueError('Diagnostic counts do not describe repeated legacy log rows')
    if not before.get('owned_ingest_reuse') or after.get('owned_ingest_reuse') is not None:
        raise ValueError('Diagnostic difference is not from a fresh ingest versus a reused history')
    db = sqlite3.connect('file:' + str(Path(recovered) / 'work.sqlite') + '?mode=ro', uri=True)
    expected = set()
    for (node,) in db.execute('select node from occurrences group by node having count(distinct v)>1'):
        groups = db.execute('select v,max(endpoint) from occurrences where node=? group by v order by v', (node,)).fetchall()
        for index, (a, end_a) in enumerate(groups):
            for b, end_b in groups[index + 1:]:
                if not end_a or not end_b:
                    expected.add((node, a, b))
    observed = [tuple(json.loads(row[0])) for row in db.execute('select detail from diagnostics where kind=?', (kind,))]
    db.close()
    if len(observed) != current or len(set(observed)) != current or set(observed) != expected:
        raise ValueError('Fresh diagnostic rows differ from independently reconstructed original-node incidence')
    return {
        'kind': kind, 'old_logged_rows': previous, 'fresh_logged_rows': current,
        'fresh_unique_rows': len(expected), 'fresh_rows_exactly_match_original_node_incidence': True,
        'old_total_to_fresh_unique_ratio': previous // current,
        'explanation': 'Frozen add_endpoint_transitions appends these diagnostics during each ingest reuse without deleting prior rows. Old reuse and integer count ratio support duplicate-history inference.',
        'old_sqlite_missing_after_restart': True,
        'historical_per_row_multiplicity_independently_verified': False,
        'source_and_geometry_equality_required_separately': True,
    }


def audit(reference, recovered):
    reference, recovered = Path(reference), Path(recovered)
    before_identity = json.loads((reference / 'identity.json').read_bytes())
    after_identity = json.loads((recovered / 'identity.json').read_bytes())
    before = read(reference, before_identity['manifest'])
    after = read(recovered, after_identity['manifest'])
    diagnostics = diagnostic_history(before, after, recovered)
    allowed_changes = {'resources', 'owned_ingest_reuse'}
    if diagnostics is not None:
        allowed_changes.add('diagnostics')
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
        'diagnostic_history_evidence_and_limit': diagnostics,
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
