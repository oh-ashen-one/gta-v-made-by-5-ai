#!/usr/bin/env python3
"""Offline arithmetic of the proposed public furniture plan; NOT engine QA."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parents[3]
module = root / 'game/src/world/mbs_interior/public_l1.gd'
reference = root / 'game/src/world/mbs_interior/site_reference.gd'
source = reference.read_text()
data = json.JSONDecoder().raw_decode(source.split('const DATA := ', 1)[1])[0]
widths = {'T3': 10.0, 'T2': 20.0, 'T1': 40.0}
heights = {'T3': 27.0, 'T2': 47.0, 'T1': 76.0}
zones = [dict(tower=t['tower'], x=t['centroid_local_xz'][0], z=t['centroid_local_xz'][1], length=t['source_long_extent_m']*.78, w=widths[t['tower']], h=heights[t['tower']]) for t in data['towers']]
profile = [dict(zones[0], x=zones[0]['x']-zones[0]['length']/2)] + zones + [dict(zones[-1], x=zones[-1]['x']+zones[-1]['length']/2)]

def sample(x):
    for a, b in zip(profile, profile[1:]):
        if x <= b['x']+.0001:
            u = max(0, min(1, (x-a['x'])/(b['x']-a['x'])))
            return {k: a[k]+(b[k]-a[k])*u for k in ['x', 'z', 'w', 'h']}
    return profile[-1]

def plan(x, side, size, tower, kind, identifier):
    sx, sy, sz = size
    points = [x-sx/2, x, x+sx/2] + [s['x'] for s in profile if x-sx/2 < s['x'] < x+sx/2]
    samples = [sample(p) for p in points]
    min_z, max_z = min(s['z'] for s in samples), max(s['z'] for s in samples)
    east = max(s['z']-s['w']/2+s['w']*.14*sy/s['h'] for s in samples)
    west = min(s['z']+s['w']/2 for s in samples)
    s = sample(x)
    preferred = s['z']+side*s['w']*.31
    z = max(preferred, max_z+2.5+sz/2) if side > 0 else min(preferred, min_z-2.5-sz/2)
    aisle = z-sz/2-max_z if side > 0 else min_z-z-sz/2
    wall = west-z-sz/2 if side > 0 else z-sz/2-east
    assert aisle >= 2.5-.0001 and wall >= .25-.0001, (identifier, aisle, wall)
    return dict(id=identifier, tower=tower, kind=kind, position=[x, 0, z], size=size, centerline_clearance_m=aisle, wall_clearance_m=wall)

items = []
for zone in zones:
    for side in [-1, 1]:
        for i, longitudinal in enumerate([-.25, .25]):
            x = zone['x']+zone['length']*longitudinal
            identifier = zone['tower']+('_east_' if side < 0 else '_west_')+str(i)
            items.append(plan(x, side, [2,.5,.5], zone['tower'], 'bench', identifier+'_bench'))
            items.append(plan(x+2.8, side, [1.8,3,1.8], zone['tower'], 'planter', identifier+'_planter'))
    if zone['tower'] == 'T1':
        items.append(plan(zone['x']+zone['length']*.05, -1, [5.2,1.24,1.3], 'T1', 'reception', 'T1_reception'))

trees = []
for item in [i for i in items if i['kind']=='planter']:
    x, _, z = item['position']
    w, h = {'T3': (2.1,4.5), 'T2': (3.8,5.6), 'T1': (4.8,6.2)}[item['tower']]
    top = 3-.04+h
    points = [x-w/2,x,x+w/2]+[s['x'] for s in profile if x-w/2 < s['x'] < x+w/2]
    samples = [sample(p) for p in points]
    east = max(s['z']-s['w']/2+s['w']*.14*top/s['h'] for s in samples)
    west = min(s['z']+s['w']/2 for s in samples)
    cap_clear = min(x-profile[0]['x'],profile[-1]['x']-x)-.25
    crown = min(w, 2*min(min(z-east, west-z)-.18, cap_clear))
    clearance = min(z-crown/2-east, west-z-crown/2)
    assert crown > .5 and clearance >= .18-.0001, (item['id'], crown, clearance)
    trees.append(dict(id=item['id'], crown_width_m=crown, top_m=top, wall_clearance_m=clearance))

result = dict(created_utc=datetime.now(timezone.utc).isoformat(), method='OFFLINE_PYTHON_ARITHMETIC_ONLY_NOT_GODOT_QA', source_sha256=hashlib.sha256(module.read_bytes()).hexdigest(), reference_sha256=hashlib.sha256(reference.read_bytes()).hexdigest(), furniture_count=len(items), minimum_furniture_centerline_clearance_m=min(i['centerline_clearance_m'] for i in items), minimum_furniture_wall_clearance_m=min(i['wall_clearance_m'] for i in items), tree_count=len(trees), minimum_overhead_tree_wall_clearance_m=min(t['wall_clearance_m'] for t in trees), furniture=items, trees=trees, engine_tests_run=False, rendered_fidelity_accepted=False)
assert len(items)==25 and len(trees)==12
out = Path(__file__).with_name('r5-static-clearance.json')
out.write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['furniture','trees']}))
