#!/usr/bin/env python3
"""Read-only one-cell diagnosis of a completed national seam-audit index.

Never repairs, adopts, or changes an artifact. The complete audit remains the
acceptance source; this bounded helper retains exact source-way diagnostics.
"""
import argparse
import json
import math
from pathlib import Path
import resource
import sqlite3
import time

import numpy as np
import audit_national as audit


def diagnose(args):
    started = time.monotonic()
    manifest, _, source, index = audit.inputs(args)
    db = sqlite3.connect('file:' + str(args.seam_index) + '?mode=ro', uri=True)
    tx, tz = map(int, args.cell.split('_'))
    groups, needed = [], set()
    for group, in db.execute('select g from groups where tx=? and tz=?', (tx, tz)):
        rows = db.execute('select way,i,width from incidence where g=?', (group,)).fetchall()
        groups.append((group, rows))
        needed.update(row[0] for row in rows)
    ways = {key: json.loads(index.execute('select data from ways where id=?', (key,)).fetchone()[0]) for key in needed}
    pieces = {key: [] for key in needed}
    for descriptor in manifest['physical_tiles']:
        sx, sz = map(int, descriptor['spatial_tile_key'].split('_'))
        if abs(sx - tx) > 1 or abs(sz - tz) > 1:
            continue
        for feature in audit.read(args.country, descriptor)['features']:
            if feature['id'] in needed:
                pieces[feature['id']].append(audit.triangle_table(feature))
        audit.frozen.budget()
    tables = {key: tuple(np.concatenate([part[i] for part in parts]) for i in range(4)) for key, parts in pieces.items() if parts}
    examples, maximum, comparisons = [], 0., 0
    for group, rows in groups:
        incident = {row[0] for row in rows}
        half = max(row[2] * .5 for row in rows)
        for key, node_index, width in rows:
            points = ways[key]['source_points_xyz']
            for step in [-1, 1]:
                j, distance = node_index, 0.
                while 0 <= j + step < len(points) and distance < half:
                    p, q = points[j], points[j + step]
                    length = math.hypot(q[0] - p[0], q[2] - p[2])
                    if length < 1e-9:
                        j += step
                        continue
                    extent = min(length, half - distance)
                    steps = max(1, math.ceil(extent / .5))
                    for sample in range(steps + 1):
                        t = extent * sample / steps / length
                        x, z = p[0] + (q[0] - p[0]) * t, p[2] + (q[2] - p[2]) * t
                        own = audit.heights(tables[key], x, z) if key in tables else []
                        for other in incident:
                            if key == other or other not in tables or not own:
                                continue
                            values = audit.heights(tables[other], x, z)
                            if not values:
                                continue
                            comparisons += 1
                            delta = max(abs(h - v) for h in own for v in values)
                            maximum = max(maximum, delta)
                            if delta > .005 and len(examples) < 100:
                                examples.append({'group': group, 'from': key, 'from_name': ways[key]['name'], 'from_width': width,
                                                 'from_node_index': node_index, 'other': other, 'other_name': ways[other]['name'],
                                                 'xz': [x, z], 'height_delta_m': delta, 'own_heights': own,
                                                 'other_heights': values, 'association_rows': rows,
                                                 'canonical_source_node': points[node_index]})
                    distance += length
                    j += step
        audit.frozen.budget()
    result = {'status': 'DIAGNOSTIC_ONLY_NO_NATIONAL_ADOPTION', 'country_identity_sha256': args.country_identity,
              'cell': args.cell, 'junction_groups': len(groups), 'overlap_comparisons': comparisons,
              'maximum_mismatch_m': maximum, 'first100_outliers': examples,
              'peak_rss_bytes': audit.frozen.budget(), 'wall_seconds': time.monotonic() - started}
    audit.put(args.output, result)
    db.close()
    source.close()
    index.close()
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--country', type=Path, required=True)
    parser.add_argument('--country-identity', required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--source-identity', required=True)
    parser.add_argument('--seam-index', type=Path, required=True)
    parser.add_argument('--cell', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    resource.setrlimit(resource.RLIMIT_CPU, (120, 125))
    result = diagnose(args)
    print(json.dumps({key: value for key, value in result.items() if key != 'first100_outliers'}), flush=True)
