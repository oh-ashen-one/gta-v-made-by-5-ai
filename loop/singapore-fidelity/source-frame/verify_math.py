#!/usr/bin/env python3
"""Independent float32/double design study, NOT execution of GDScript.

Uses only the Python standard library. The parent must still run the actual
Godot scene; these results cannot establish parsing, physics or world QA.
"""
import hashlib
import json
from pathlib import Path
import struct


def f32(value):
    return struct.unpack('f', struct.pack('f', value))[0]


def error(a, b):
    return max(abs(x-y) for x, y in zip(a, b))


def main():
    root = Path(__file__).resolve().parents[3]
    manifest_path = root / 'game/data/geography/osm-2026-10-27/manifest.json'
    manifest_raw = manifest_path.read_bytes()
    manifest = json.loads(manifest_raw)
    origin = [17384.7, -18.5, -80120.7]
    point = [17384.705412828924, -18.5, -80120.70113909859]
    point_mm = [v+0.001 for v in point]
    raw_delta = [f32(b)-f32(a) for a, b in zip(point, point_mm)]
    local = [f32(p-o) for p, o in zip(point, origin)]
    local_mm = [f32(p-o) for p, o in zip(point_mm, origin)]
    local_delta = [f32(b-a) for a, b in zip(local, local_mm)]
    restored = [o+p for o, p in zip(origin, local)]

    old = [f32(v) for v in [1023.999939, 31.12345, -1023.999937]]
    new_origin = [1023.999931, 31.123441, -1023.999921]
    naive = [f32(p+f32(-o)) for p, o in zip(old, new_origin)]
    reconstructed = [f32(p-o) for p, o in zip(old, new_origin)]
    naive_source = [o+p for o, p in zip(new_origin, naive)]
    rebuilt_source = [o+p for o, p in zip(new_origin, reconstructed)]

    origin = [17384.7, 0.0, -80120.7]
    center = list(origin)
    offsets = [[-12.25, -18.5, 0.123456], [5.875, 245.125, 35.5], [201.123, 1.5, -112.25]]
    maximum = 0.0
    for _ in range(219):
        center[2] += 512.0
        canonical = [[a+b for a, b in zip(center, offset)] for offset in offsets]
        locals_before = [[f32(p-o) for p, o in zip(point, origin)] for point in canonical]
        captured_physical_sources = [[o+p for o, p in zip(origin, local)] for local in locals_before]
        new_locals = [[f32(p-o) for p, o in zip(source, center)] for source in captured_physical_sources]
        origin = list(center)
        for source, local in zip(canonical, new_locals):
            maximum = max(maximum, error(source, [o+p for o, p in zip(origin, local)]))

    report = {
        'scope': 'CPU float32/double design arithmetic only, not a GDScript parser or engine run',
        'actual_manifest_sha256': hashlib.sha256(manifest_raw).hexdigest(),
        'actual_source_snapshot_utc': manifest['source_snapshot_utc'],
        'absolute_float32_mm_delta_xyz': raw_delta,
        'origin_relative_float32_mm_delta_xyz': local_delta,
        'source_roundtrip_max_error_m': error(point, restored),
        'non_grid_naive_delta_addition_error_m': error(old, naive_source),
        'non_grid_canonical_reconstruction_error_m': error(old, rebuilt_source),
        'bounded_rebases': 219,
        'canonical_motion_span_m': 219*512.0,
        'repeated_rebase_max_error_m': maximum,
        'source_hashes': {
            str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in [root/'game/src/world/geography/source_frame.gd',
                         root/'game/src/systems/fidelity_tests/source_frame_test.gd',
                         root/'game/src/systems/fidelity_tests/source_frame_test.tscn']
        },
        'godot_run_by_worker': False,
        'compile_verified': False,
        'physics_or_world_integration_verified': False,
    }
    assert max(abs(v-0.001) for v in local_delta) < 1e-7
    assert report['source_roundtrip_max_error_m'] < 1e-6
    assert report['non_grid_canonical_reconstruction_error_m'] < 1e-8
    assert maximum < 1e-4
    out = Path(__file__).with_name('equation-study.json')
    if out.exists():
        raise SystemExit('Refusing to overwrite existing equation-study evidence')
    out.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, sort_keys=True))


if __name__ == '__main__':
    main()
