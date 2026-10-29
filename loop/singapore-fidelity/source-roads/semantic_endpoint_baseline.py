#!/usr/bin/env python3
"""Bounded fresh endpoint-metric v3 profile from verified source-only ingestion.

The predecessor profile was rejected; its Y is never adopted. Original source
facts are re-audited against recovered R5, and frozen metric-v2 remains intact.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import time

import cpu_job
import endpoint_profiles_v3 as metric
import semantic_baseline as base
import expand_national as original

K = base.K


def source_signature(db):
    digest = hashlib.sha256()
    queries = {
        'owners': 'select * from owners order by owner',
        'source_nodes': 'select * from source_nodes order by id',
        'source_vertices': 'select v,node,grade,x,z,base from vertices order by v',
        'ways': 'select * from ways order by id',
        'occurrences': 'select * from occurrences order by node,v,way,endpoint',
        'edges': 'select * from edges order by id',
        'height_constraints': 'select * from height_constraints order by a,b,allowance',
        'render_hubs': 'select * from render_hubs order by v',
        'vertical_orders': 'select * from vertical_orders order by id',
    }
    counts = {}
    for name, query in queries.items():
        digest.update(name.encode() + b'\0')
        count = 0
        for row in db.execute(query):
            digest.update(K.canonical(row) + b'\n')
            count += 1
        counts[name] = count
    return {'sha256': digest.hexdigest(), 'row_counts': counts,
            'mutable_metric_bounds_and_profile_y_excluded_explicitly': True}


def open_source_only_clone(args):
    if original.digest(args.ingested / 'work.sqlite') != args.ingested_database_sha:
        raise ValueError('Source-only predecessor database hash differs')
    status = json.loads((args.ingested / 'supervisor.json').read_bytes())
    if status.get('status') != 'INCOMPLETE' or status.get('worker_exit') != 1:
        raise ValueError('Expected terminal rejected v2 profile source-only input')
    proof = json.loads((args.ingested / 'original-source-audit.json').read_bytes())
    if proof.get('status') != 'PASS_ORIGINAL_OSM_IDS_ORDER_XY_MODES_AND_EXPLICIT_NODE_ONLY_CONNECTIONS':
        raise ValueError('Original source-conservation proof missing')
    target = args.output / 'work.sqlite'
    if shutil.disk_usage(args.output).free < args.minimum_free_bytes:
        raise ValueError('Direct filesystem free space below explicit reserve')
    # APFS clone preserves the immutable predecessor and avoids copying1.3GiB
    # of unchanged source pages. If clone is unavailable, fail for review; no
    # hidden unbounded fallback or source mutation.
    subprocess.run(['/bin/cp', '-c', str(args.ingested / 'work.sqlite'), str(target)], check=True)
    db = sqlite3.connect(target)
    db.execute('pragma cache_size=-65536'); db.execute('pragma mmap_size=0'); db.execute('pragma temp_store=FILE')
    if db.execute('select count(*) from vertices where y!=base').fetchone()[0]:
        raise ValueError('Rejected predecessor unexpectedly contains mutated profile heights')
    if db.execute("select count(*) from sqlite_master where name in ('endpoint_metric_inference','structure_metric_orders')").fetchone()[0]:
        raise ValueError('Source-only predecessor is not the frozen v2 schema')
    return db, proof


def worker(args):
    cpu_job.worker_guard(args); started = time.monotonic()
    source_manifest, source = original.source(args)
    db, predecessor_source_proof = open_source_only_clone(args)
    source_facts = base.audit_original_source(source, db)
    if source_facts != predecessor_source_proof:
        raise ValueError('Recomputed full source audit differs from predecessor proof')
    original.put(args.output / 'original-source-audit.json', source_facts)
    signature_before = source_signature(db)
    original.put(args.output / 'immutable-source-signature-before.json', signature_before)
    old_diagnostics = dict(db.execute("select kind,count(*) from diagnostics where kind='incompatible_game_clearance_constraints_v2' group by kind"))
    db.execute("delete from diagnostics where kind='incompatible_game_clearance_constraints_v2'")
    db.commit()
    print(json.dumps({'stage': 'endpoint_metric_inference', 'predecessor_solver_diagnostics_preserved_in_prior_output': old_diagnostics}), flush=True)
    inference = metric.apply(db)
    inference_desc = original.put(args.output / 'metric-inference.json', inference)
    print(json.dumps({'stage': 'endpoint_metric_profile_solve', 'structured_vertices': len(inference['records']),
                      'structure_relations': inference['structure_relative_constraints'],
                      'portal_source_transitions': len(inference['true_portal_source_transitions'])}), flush=True)
    profile = metric.solve(db)
    signature_after = source_signature(db)
    if signature_after != signature_before:
        raise ValueError('Endpoint profile modified original source/graph/geometry/order facts')
    original.put(args.output / 'immutable-source-signature-after.json', signature_after)
    graph = K.export_catalogs(db, args.output)
    counts = dict(db.execute('select kind,count(*) from diagnostics group by kind'))
    db.commit(); db.close(); source.close()
    database_sha = original.digest(args.output / 'work.sqlite')
    ingest = json.loads((args.ingested / 'ingest-counts.json').read_bytes())
    manifest = dict(source_manifest)
    manifest.update(version=5, graph_chunks=graph, physical_tiles=[], profile=profile,
        compiler_sha256=original.digest(K.__file__), parent_road_identity_sha256=args.identity,
        counts={'owners': 906, 'ways': 257845, 'endpoint_grade_transitions': ingest['derived_grade_transitions']},
        diagnostics=counts, surface_height_constraints=ingest['geometry'], source_semantic_counts=ingest['counts'],
        owned_ingest_reuse={'source_only_rejected_metric_v2_input': str(args.ingested),
                            'database_sha256': args.ingested_database_sha, 'failed_metric_y_adopted': False,
                            'new_full_source_audit': source_facts, 'APFS_clone': True},
        source_metric_recipe={'policy': metric.POLICY, 'metric_module_sha256': original.digest(metric.__file__),
                              'wrapper_sha256': original.digest(__file__), 'versioned_kernel_sha256': original.digest(K.__file__),
                              'semantic_policy_sha256': original.digest(base.semantics.__file__),
                              'database_sha256': database_sha, 'inference': inference_desc,
                              'immutable_source_signature': signature_after,
                              'predecessor_failed_profile_diagnostics_preserved_separately': old_diagnostics},
        physical_scope={'status': 'GRAPH_AND_RECONSTRUCTED_PROFILE_ONLY_NOT_PHYSICAL_OR_NATIVE_ACCEPTANCE',
                        'next': 'Actual type-aware pedestrian-only decks/paths in addition to unchanged car-grade ribbons'},
        resources={'wall_seconds': time.monotonic() - started, 'peak_rss_bytes': K.budget(),
                   'logical_output_budget_bytes': args.output_budget_bytes, 'minimum_direct_free_bytes': args.minimum_free_bytes})
    descriptor = original.put(args.output / 'manifest.json', manifest)
    original.put(args.output / 'identity.json', {'schema': K.IDENTITY, 'version': 5, 'manifest': descriptor,
        'snapshot_manifest_sha256': manifest['snapshot_manifest_sha256'], 'parent_road_identity_sha256': args.identity})
    result = {'status': 'ENDPOINT_METRIC_V3_GRAPH_BASELINE_COMPLETE_NOT_COUNTRY_OR_NATIVE_ACCEPTANCE',
              'identity_sha256': original.digest(args.output / 'identity.json'), 'database_sha256': database_sha,
              'profile': profile, 'source_facts': source_facts, 'immutable_source_signature': signature_after,
              'resources': manifest['resources']}
    original.put(args.output / 'result.json', result)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True); parser.add_argument('--identity', required=True)
    parser.add_argument('--database-sha', required=True); parser.add_argument('--ingested', type=Path, required=True)
    parser.add_argument('--ingested-database-sha', required=True); parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--output-budget-bytes', type=int, default=8 * 1024**3)
    parser.add_argument('--minimum-free-bytes', type=int, default=12 * 1024**3)
    parser.add_argument('--worker', action='store_true'); parser.add_argument('--job-token')
    args = parser.parse_args()
    try:
        result = worker(args) if args.worker else cpu_job.supervise(args, __file__, 'source-endpoint-metric-v3', protected=[args.source, args.ingested])
        print(json.dumps(result), flush=True)
        if result.get('status') == 'INCOMPLETE': raise SystemExit(1)
    except Exception as error:
        print(json.dumps({'status': 'ENDPOINT_METRIC_V3_REJECTED_NO_ADOPTION', 'error': str(error)}), flush=True)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
