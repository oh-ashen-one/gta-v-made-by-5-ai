#!/usr/bin/env python3
"""Prototype height-only source-way overlap constraints; no artifact mutation.

The caller retains raw sources, topology and explicit height bounds. This
module proposes pairs of original vertices for the existing profile solver;
it never creates a navigation edge, changes XZ, or edits an existing DB.
"""
import math
from pathlib import Path
import sys

from shapely.geometry import Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'game/tools/geography'))
import compile_roads as kernel


def apron(point, width):
    half = width * .5
    return Polygon([(point[0] + half * math.cos(i * math.tau / 16),
                     point[2] + half * math.sin(i * math.tau / 16)) for i in range(16)])


def _ring_points(shape):
    if shape.is_empty:
        return []
    if shape.geom_type == 'Polygon':
        return list(shape.exterior.coords)
    return [p for part in getattr(shape, 'geoms', ()) for p in _ring_points(part)]


def propose(points, width, hubs, vertex_ids, continuation_grades, *, source_ele_tag=None):
    """Return deterministic height equality proposals for ONE original way.

    ``continuation_grades[i]`` is the exact set of other grade keys reachable
    through an existing original-node endpoint transition at source index i.
    Empty means none, not permission to connect another road. This prototype
    rejects measured-elevation cases for separate review.
    """
    n = len(points)
    if n < 2 or len(hubs) != n or len(vertex_ids) != n or len(continuation_grades) != n:
        raise ValueError('Exact ordered source arrays required')
    if not kernel.number(width) or not 0 < width <= 128:
        raise ValueError('Invalid bounded physical width')
    if len(set(vertex_ids)) != len(vertex_ids):
        # A closed source way may repeat its first original vertex. Its two
        # occurrences need a separate station policy, never an implicit cut.
        return {'status': 'REVIEW_REPEATED_SOURCE_VERTEX', 'equalities': [], 'reasons': [], 'protected': []}
    if any(len(p) != 3 or not all(kernel.number(v) for v in p) for p in points):
        raise ValueError('Finite canonical source triples required')
    if any(not kernel.number(r) or r < 0 or r > 1024 for r in hubs):
        raise ValueError('Invalid plateau radii')
    if any(not isinstance(v, int) or isinstance(v, bool) or v <= 0 for v in vertex_ids):
        raise ValueError('Original source vertex IDs required')
    if any(not isinstance(g, (list, tuple, set)) or any(not isinstance(k, str) for k in g) for g in continuation_grades):
        raise ValueError('Explicit typed continuation-grade sets required')
    if source_ele_tag is not None:
        return {'status': 'REVIEW_SOURCE_ELEVATION_EVIDENCE', 'equalities': [], 'reasons': [], 'protected': []}
    hub_indices = [i for i, radius in enumerate(hubs) if radius > 0]
    polygons = {i: apron(points[i], width) for i in hub_indices}
    parent = {i: i for i in hub_indices}

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    equalities, reasons, protected = set(), [], []

    def constrain(hub, targets, kind, **evidence):
        for target in targets:
            a, b = sorted((vertex_ids[hub], vertex_ids[target]))
            if a != b:
                equalities.add((a, b))
        reasons.append({'kind': kind, 'hub_index': hub, 'source_indices': list(targets), **evidence})

    # Per-way spatial bins make long source ways bounded rather than O(n^2).
    bins = {}
    cell_size = max(width, 1.)
    for i in hub_indices:
        x, z = points[i][0], points[i][2]
        cell = (math.floor(x / cell_size), math.floor(z / cell_size))
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for j in bins.get((cell[0] + dx, cell[1] + dz), ()):
                    intersection = polygons[i].intersection(polygons[j])
                    if intersection.area <= 1e-8:
                        continue
                    signatures = [sorted(set(continuation_grades[k])) for k in (i, j)]
                    if signatures[0] != signatures[1]:
                        protected.append({'kind': 'DISTINCT_CONTINUATION_GRADES', 'source_indices': [j, i],
                                          'continuation_grades': signatures, 'overlap_m2': intersection.area,
                                          'inferred_height_difference_m': abs(points[i][1] - points[j][1])})
                        continue
                    constrain(j, [i], 'SAME_WAY_FLAT_APRON_OVERLAP', overlap_m2=intersection.area)
                    parent[find(i)] = find(j)
        bins.setdefault(cell, []).append(i)

    stations = [0.]
    for p, q in zip(points, points[1:]):
        stations.append(stations[-1] + math.hypot(q[0] - p[0], q[2] - p[2]))
    layout = kernel._section_layout(points, width, hubs)
    coherent_footprints = {i: unary_union([polygons[j] for j in hub_indices if find(j) == find(i)]) for i in hub_indices}
    proposed_radii = list(hubs)

    def local_hub_for_interval(hub, lo, hi):
        """Every overlap station must belong to this exact source-arc hub.

        Height equalities between two aprons do not make their source branches
        interchangeable. Otherwise a far portal on a loop could drag an
        unrelated approach interval into the near portal's profile.
        """
        probes = [lo, hi]
        ordered = sorted(stations[i] for i in hub_indices)
        probes.extend((a + b) * .5 for a, b in zip(ordered, ordered[1:]) if lo <= (a + b) * .5 <= hi)
        for station in probes:
            distances = [(abs(station - stations[i]), i) for i in hub_indices]
            best = min(d for d, _ in distances)
            winners = {i for d, i in distances if abs(d - best) < 1e-7}
            if winners != {hub}:
                return False
        return True

    for span in layout['spans']:
        i = span['index']
        source_a, source_b = points[i], points[i + 1]
        dx, dz = source_b[0] - source_a[0], source_b[2] - source_a[2]
        length2 = dx * dx + dz * dz
        if length2 < 1e-16:
            continue
        for a, oa, ta, b, ob, tb in span['cells']:
            al, ar = (a[0] + oa[0], a[1] + oa[1]), (a[0] - oa[0], a[1] - oa[1])
            bl, br = (b[0] + ob[0], b[1] + ob[1]), (b[0] - ob[0], b[1] - ob[1])
            shape = unary_union([Polygon([al, ar, bl]), Polygon([ar, br, bl])])
            if shape.is_empty:
                continue
            for hub in hub_indices:
                intersection = shape.intersection(coherent_footprints[hub])
                if intersection.area <= 1e-8:
                    continue
                projected = []
                for x, z in _ring_points(intersection):
                    t = max(0., min(1., ((x - source_a[0]) * dx + (z - source_a[2]) * dz) / length2))
                    projected.append(stations[i] + math.sqrt(length2) * t)
                if not projected or not local_hub_for_interval(hub, min(projected), max(projected)):
                    continue
                # Extend the local flat approach only to the actual footprint
                # boundary. Equating an entire long span's source endpoints
                # would unnecessarily flatten its remaining graded transition.
                extent = max(abs(station - stations[hub]) for station in projected)
                if extent <= hubs[hub] + 1e-7:
                    continue
                radius = extent + .001  # Explicit 1mm construction guard.
                if radius > 128.:
                    protected.append({'kind': 'PLATEAU_EXTENSION_EXCEEDS_EXISTING_128M_CAP',
                                      'hub_index': hub, 'required_radius_m': radius})
                    continue
                proposed_radii[hub] = max(proposed_radii[hub], radius)
                reasons.append({'kind': 'FOOTPRINT_DERIVED_LOCAL_FLAT_APPROACH_RADIUS',
                                'hub_index': hub, 'source_span': i, 'radius_m': radius,
                                'overlap_m2': intersection.area,
                                'source_station_interval': [min(projected), max(projected)]})
        kernel.budget()
    return {'status': 'HEIGHT_ONLY_PROPOSALS_NOT_APPLIED', 'equalities': [list(p) for p in sorted(equalities)],
            'radius_overrides': {str(i): radius for i, radius in enumerate(proposed_radii) if radius > hubs[i] + 1e-7},
            'reasons': reasons, 'protected': protected,
            'construction_guard_m': .001, 'max_plateau_arc_radius_m': 128.,
            'source_xz_tags_ids_navigation_mutated': False}
