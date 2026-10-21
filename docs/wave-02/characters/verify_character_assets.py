"""Inspect exported glTF skins and numeric deformations without an engine.
This is structural verification, never a rendered visual or gameplay pass.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import struct
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / 'game/assets/providers'
REPORT = Path(__file__).with_name('asset-verification.json')
SAMPLES = Path('/tmp/astra_rig_samples')
report = {'time_utc': datetime.now(timezone.utc).isoformat(),
          'scope': 'CPU asset verification; rendered/gameplay acceptance is separate', 'assets': []}
prior = json.loads(REPORT.read_text()) if REPORT.exists() else {}
for name in ['player', 'officer', 'civilian']:
    path = ASSETS / (name + '_rigged.glb')
    data = path.read_bytes(); size = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20 + size]); binary = data[28 + size:]
    def accessor(index):
        a = gltf['accessors'][index]; view = gltf['bufferViews'][a['bufferView']]
        dtype = {5126: 'f4', 5125: 'u4', 5123: 'u2', 5121: 'u1'}[a['componentType']]
        count = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
        return np.frombuffer(binary, dtype=dtype, count=a['count'] * count,
            offset=view.get('byteOffset', 0) + a.get('byteOffset', 0)).reshape(-1, count)
    skin = gltf['skins'][0]; errors = []
    for mesh in gltf['meshes']:
        for primitive in mesh['primitives']:
            attrs = primitive['attributes']; weights = accessor(attrs['WEIGHTS_0'])
            joints = accessor(attrs['JOINTS_0']); positions = accessor(attrs['POSITION'])
            if not np.isfinite(positions).all(): errors.append('nonfinite position')
            if not np.isfinite(weights).all(): errors.append('nonfinite weight')
            if np.max(np.abs(weights.sum(axis=1) - 1)) > .0001: errors.append('unnormalized weights')
            if joints.max() >= len(skin['joints']): errors.append('out of range joint')
    clips = {a['name']: float(accessor(a['samplers'][0]['input']).max()) for a in gltf['animations']}
    report['assets'].append({'asset': path.name, 'sha256': hashlib.sha256(data).hexdigest(),
        'bytes': len(data), 'joints': len(skin['joints']), 'clips_seconds': clips,
        'materials': [m.get('name', '') for m in gltf['materials']], 'errors': errors})
    print(name, 'joints', len(skin['joints']), 'clips', len(clips), 'structural_errors', errors)
    if (SAMPLES / (name + '_idle.npz')).exists():
        rest = np.load(SAMPLES / (name + '_idle.npz')); vertices = rest['positions']; triangles = rest['triangles']
        edges = np.concatenate([triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]])
        before = np.linalg.norm(vertices[edges[:, 0]] - vertices[edges[:, 1]], axis=1); valid = before > .005
        poses = {}
        for pose in ['walk_contact', 'walk_swing', 'run_swing', 'aim', 'hit', 'fall', 'seated', 'drive']:
            sample = SAMPLES / (name + '_' + pose + '.npz')
            if not sample.exists(): continue
            deformed = np.load(sample)['positions']
            after = np.linalg.norm(deformed[edges[:, 0]] - deformed[edges[:, 1]], axis=1)
            poses[pose] = {'p99_edge_stretch': float(np.quantile(after[valid] / before[valid], .99)),
                'edges_extended_over_10cm': int(((after - before) > .1).sum()),
                'lowest_z_m': float(deformed[:, 2].min())}
        report.setdefault('pose_diagnostics', {})[name] = poses
for name in ['player', 'officer']:
    path = ASSETS / (name + '_clean.glb'); digest = hashlib.sha256(path.read_bytes()).hexdigest()
    expected = prior.get('source_sha256', {}).get(path.name)
    if expected and digest != expected: raise RuntimeError('SOURCE ASSET CHANGED: ' + path.name)
    report.setdefault('source_sha256', {})[path.name] = digest
for name in ['pistol_held.glb', 'smg_held.glb']:
    path = ASSETS / name
    report.setdefault('held_weapon_sha256', {})[name] = hashlib.sha256(path.read_bytes()).hexdigest()
REPORT.write_text(json.dumps(report, indent=2) + '\n')
if any(a['errors'] for a in report['assets']): raise SystemExit(1)
