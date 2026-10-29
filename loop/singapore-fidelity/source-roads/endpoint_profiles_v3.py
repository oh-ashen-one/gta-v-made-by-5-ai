"""Versioned metric inference with source-connected structure portals.

No OSM facts or navigation arcs are changed. Metric offsets are game choices,
not heights derived from layer ordinals or a surveyed elevation model.
"""
from collections import Counter
import heapq
import json
import math
import numpy as np

import compile_roads_semantic_v2 as K

POLICY = 'source_road_endpoint_metric_profile_v3'
NOMINAL = {'bridge': 6.0, 'tunnel': 5.0}
TAPER_GRADE_BUDGET_FRACTION = 0.5
MAX_STRUCTURE_RELATIONS = 100000
MAX_RELATIVE_CLOSURE_ROUNDS = 64


def distances(adjacency, seeds, cost_index, with_origins=False):
    result = {v: 0.0 for v in seeds}
    origins = {v: v for v in seeds}
    heap = [(0.0, v) for v in seeds]
    heapq.heapify(heap)
    while heap:
        distance, node = heapq.heappop(heap)
        if distance != result.get(node):
            continue
        for edge in adjacency.get(node, ()):
            other, cost = edge[0], edge[cost_index]
            candidate = distance + cost
            if candidate < result.get(other, math.inf) or (candidate == result.get(other) and origins[node] < origins.get(other, origins[node] + 1)):
                result[other] = candidate
                origins[other] = origins[node]
                heapq.heappush(heap, (candidate, other))
    return (result, origins) if with_origins else result


def plan(db):
    roles = {}
    for v, grade, base in db.execute('select v,grade,base from vertices'):
        key = json.loads(grade)
        if isinstance(key, list) and key[0] in NOMINAL:
            # Compatible structure/level runs cross arbitrary source way splits.
            # Explicit transitions between layer ordinals still preserve their
            # shared original-node identity; layer is not a metre height.
            roles[v] = {'structure': key[0], 'level': key[2], 'base': base,
                        'group': (key[0], key[2])}
    flat_parent = {}

    def find(v):
        while flat_parent.get(v, v) != v:
            flat_parent[v] = flat_parent.get(flat_parent[v], flat_parent[v])
            v = flat_parent[v]
        return v

    def union(a, b):
        a, b = find(a), find(b)
        if a != b:
            flat_parent[max(a, b)] = min(a, b)

    has_geometry = db.execute("select count(*) from sqlite_master where name='height_constraints'").fetchone()[0]
    for a, b in db.execute('select a,b from edges where allowance=0'):
        union(a, b)
    if has_geometry:
        for a, b in db.execute('select a,b from height_constraints where allowance=0'):
            union(a, b)

    portals = set()
    connections = []
    adjacency, physical_adjacency = {}, {}

    def compatible(a, b):
        return a in roles and b in roles and roles[a]['group'] == roles[b]['group']

    def add(graph, a, b, allowance, length):
        graph.setdefault(a, []).append((b, allowance, length))
        graph.setdefault(b, []).append((a, allowance, length))

    for identifier, a, b, length, allowance, transition in db.execute('select id,a,b,length,allowance,transition from edges'):
        if compatible(a, b):
            add(adjacency, a, b, allowance, length)
            add(physical_adjacency, a, b, allowance, length)
        elif transition and (a in roles or b in roles):
            # The immutable ingester only emits these transitions through the
            # same ORIGINAL source node, never an XY intersection.
            na, nb = [db.execute('select node from vertices where v=?', (v,)).fetchone()[0] for v in (a, b)]
            if na != nb or length != 0.0 or allowance != 0.0:
                raise ValueError('Portal is not an exact continuous original-node transition')
            portals.update(v for v in (a, b) if v in roles)
            connections.append({'transition': identifier, 'original_node': na, 'vertices': [a, b],
                                'structures': [roles.get(v, {}).get('structure', 'other_source_grade') for v in (a, b)]})
    if has_geometry:
        for a, b, allowance in db.execute('select a,b,allowance from height_constraints'):
            if compatible(a, b):
                # Geometry allowances constrain height only; they never become
                # navigation edges or claimed source-traversal distances.
                add(adjacency, a, b, allowance, 0.0)
    portal_groups = {find(v) for v in portals}
    seeds = {v for v in roles if find(v) in portal_groups}
    vertical_budget, anchors = distances(adjacency, seeds, 1, True)
    source_metres = distances(physical_adjacency, seeds, 2)
    records = []
    counts = Counter()
    for v, role in sorted(roles.items()):
        budget = vertical_budget.get(v)
        nominal = NOMINAL[role['structure']]
        offset = nominal if budget is None else min(nominal, budget * TAPER_GRADE_BUDGET_FRACTION)
        if offset == 0.0:
            lower = upper = None
            status = 'CONTINUOUS_PORTAL_OR_OWNED_FLAT_COMPONENT_NO_OPPOSED_ABSOLUTE_CAP'
        elif budget is not None and offset < nominal:
            lower = upper = None
            status = 'TRANSITION_RELATIVE_TO_SOLVED_PORTAL_HEIGHT_NOT_TERRAIN_COVER'
        elif role['structure'] == 'bridge':
            lower, upper = role['base'] + offset, None
            status = 'NO_CONNECTED_PORTAL_NOMINAL_GAME_ESTIMATE' if budget is None else 'NOMINAL_INTERIOR_GAME_OFFSET' if offset == nominal else 'TRANSITION_INTERIOR_GAME_OFFSET_BELOW_NOMINAL'
        else:
            lower, upper = None, role['base'] - offset
            status = 'NO_CONNECTED_PORTAL_NOMINAL_GAME_ESTIMATE' if budget is None else 'NOMINAL_INTERIOR_GAME_OFFSET' if offset == nominal else 'TRANSITION_INTERIOR_GAME_OFFSET_BELOW_NOMINAL'
        counts[status] += 1
        relative = None
        if budget is not None and offset > 0.0:
            anchor = anchors[v]
            relative = {'lower_vertex': anchor if role['structure'] == 'bridge' else v,
                        'upper_vertex': v if role['structure'] == 'bridge' else anchor,
                        'minimum_game_difference_m': offset, 'portal_flat_anchor_vertex': anchor}
        records.append({'vertex': v, 'structure': role['structure'], 'level': role['level'],
                        'original_preferred_dem_m': role['base'], 'allowed_height_distance_from_portal_flat_m': budget,
                        'original_network_distance_from_portal_flat_m': source_metres.get(v),
                        'nominal_game_offset_m': nominal, 'applied_game_offset_m': offset,
                        'lower_y': lower, 'upper_y': upper, 'relative_to_solved_portal': relative, 'status': status})
    return {'policy': POLICY, 'records': records, 'true_portal_source_transitions': connections,
            'portal_vertices': sorted(portals), 'portal_flat_component_structured_vertices': sorted(seeds),
            'classification_counts': dict(counts), 'nominal_game_offsets_m': NOMINAL,
            'taper_fraction_of_unchanged_native_grade_budget': TAPER_GRADE_BUDGET_FRACTION,
            'nominal_car_transition_after_flat_m': {'bridge': 100.0, 'tunnel': 5.0 / (.12 * .5)},
            'nominal_targets_unattained_at_short_transition_vertices_are_explicit': True,
            'source_xy_tags_ids_modes_and_navigation_unchanged': True,
            'source_layer_ordinal_is_not_metric_elevation': True,
            'surveyed_elevations_or_native_clearance_verified': False}


def apply(db):
    result = plan(db)
    total_relations = sum(record['relative_to_solved_portal'] is not None for record in result['records'])
    if total_relations > MAX_STRUCTURE_RELATIONS:
        raise ValueError('Explicit structure relation work budget exceeded; no truncated profile')
    db.execute('create table endpoint_metric_inference(v integer primary key,record text)')
    db.execute('create table structure_metric_orders(id text primary key,lower_v integer,upper_v integer,clearance real)')
    count = 0
    for record in result['records']:
        db.execute('update vertices set lower_y=?,upper_y=?,y=base where v=?',
                   (record['lower_y'], record['upper_y'], record['vertex']))
        db.execute('insert into endpoint_metric_inference values(?,?)',
                   (record['vertex'], json.dumps(record, sort_keys=True, separators=(',', ':'))))
        relation = record['relative_to_solved_portal']
        if relation is not None:
            count += 1
            db.execute('insert into structure_metric_orders values(?,?,?,?)',
                       (f"structure/{record['vertex']}", relation['lower_vertex'], relation['upper_vertex'], relation['minimum_game_difference_m']))
    db.commit()
    result['structure_relative_constraints'] = count
    return result


def _closure(initial, offsets, neighbors, costs, orders, maximum=True):
    values = K.envelope(initial, offsets, neighbors, costs, maximum)
    for iteration in range(MAX_RELATIVE_CLOSURE_ROUNDS):
        seeds = set()
        for lower, upper, gap in orders:
            source, target = (lower, upper) if maximum else (upper, lower)
            candidate = values[source] + gap if maximum else values[source] - gap
            if (maximum and candidate > values[target] + 1e-9) or (not maximum and candidate < values[target] - 1e-9):
                values[target] = candidate
                seeds.add(target)
        if not seeds:
            return values, iteration
        values = K._seed_envelope(values, offsets, neighbors, costs, seeds, maximum)
        K.budget()
    raise ValueError('Endpoint-relative closure unresolved within64round work budget; no claimed infeasibility or mutated heights')


def solve(db):
    total, offsets, neighbors, costs = K._csr(db)
    has_ramps = db.execute("select count(*) from sqlite_master where name='vertical_orders'").fetchone()[0]
    ramps = list(db.execute('select lower_v,upper_v,clearance from vertical_orders order by id')) if has_ramps else []
    structures = list(db.execute('select lower_v,upper_v,clearance from structure_metric_orders order by id'))
    if len(ramps) > 4096 or len(structures) > MAX_STRUCTURE_RELATIONS:
        raise ValueError('Explicit ramp/structure relation budget exceeded; no truncation')
    orders = ramps + structures
    for a, b, gap in orders:
        if not 1 <= a <= total or not 1 <= b <= total or a == b or not math.isfinite(gap) or not 0 < gap <= 20:
            raise ValueError('Invalid source-order or structure relation')
    base = np.full(total + 1, -np.inf)
    lower = np.full(total + 1, -np.inf)
    upper = np.full(total + 1, np.inf)
    for v, y, lo, hi in db.execute('select v,base,lower_y,upper_y from vertices'):
        base[v] = y
        if lo is not None: lower[v] = lo
        if hi is not None: upper[v] = hi
    preferred, preferred_rounds = _closure(base, offsets, neighbors, costs, orders)
    low, lower_rounds = _closure(lower, offsets, neighbors, costs, orders)
    high, upper_rounds = _closure(upper, offsets, neighbors, costs, orders, False)
    conflicts = np.flatnonzero(low[1:] > high[1:] + .000001) + 1
    if len(conflicts):
        db.executemany('insert into diagnostics values(?,?)', [('incompatible_endpoint_metric_constraints_v3', str(int(v))) for v in conflicts])
        db.commit()
        raise ValueError(f'{len(conflicts)} endpoint metric assumptions conflict; no profile mutation')
    heights = np.maximum(low, np.minimum(preferred, high))
    grade_error = geometry_error = relative_error = 0.0
    for a, b, allowance in db.execute('select a,b,allowance from edges'):
        grade_error = max(grade_error, abs(float(heights[a] - heights[b])) - allowance)
    if db.execute("select count(*) from sqlite_master where name='height_constraints'").fetchone()[0]:
        for a, b, allowance in db.execute('select a,b,allowance from height_constraints'):
            geometry_error = max(geometry_error, abs(float(heights[a] - heights[b])) - allowance)
    for a, b, gap in orders:
        relative_error = max(relative_error, gap - float(heights[b] - heights[a]))
    if max(grade_error, geometry_error, relative_error) > 1e-6:
        raise ValueError('Endpoint profile violates unchanged grade/geometry/source-order constraint')
    db.executemany('update vertices set y=? where v=?', [(float(heights[v]), v) for v in range(1, total + 1) if math.isfinite(float(heights[v]))])
    db.commit()
    return {'policy': POLICY, 'vertices': total, 'ramp_relations': len(ramps), 'structure_relations': len(structures),
            'maximum_allowance_error_m': grade_error, 'maximum_height_only_constraint_error_m': geometry_error,
            'maximum_relative_clearance_error_m': relative_error, 'conflicting_game_constraints': 0,
            'closure_rounds': [preferred_rounds, lower_rounds, upper_rounds],
            'physical_scope': 'CAR_ONLY_PRODUCER_STILL_REQUIRES_FOOT_DECK_PATH_SUPPORT_NEXT',
            'car_grade_limit': .12, 'foot_graph_grade_limit': .25, 'step_graph_grade_limit': .7,
            'source_elevation_survey_or_terrain_cover_or_native_acceptance': False}
