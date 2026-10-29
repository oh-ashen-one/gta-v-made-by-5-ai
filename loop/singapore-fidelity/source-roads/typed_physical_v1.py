"""Typed source walking/driving surfaces; frozen profile and topology untouched."""
import math
import re

import numpy as np
import compile_roads_semantic_v2 as K

SCHEMA = 'source_surface_types_v1'
EMITTED_LIMIT = {'car_ribbon': .121, 'foot_ribbon': .251, 'foot_steps': .701}
NATIVE_LIMIT = {'car_ribbon': .122, 'foot_ribbon': .252, 'foot_steps': .702}
MIN_RISER, MAX_RISER, MIN_TREAD = .08, .24, .18


def classification(raw, policy):
    tags = raw['tags']
    if policy['grade']['level']:
        return None, 'INDOOR_LEVEL_REQUIRES_FLOOR_REGISTRY'
    if policy['grade']['structure'] == 'conflicting_structure':
        return None, 'CONFLICTING_STRUCTURE_REQUIRES_SOURCE_REVIEW'
    if tags.get('area') == 'yes':
        return None, 'SOURCE_AREA_REQUIRES_POLYGON_AND_HOLE_MEMBERSHIP'
    if policy['modes']['car']['bits']:
        return 'car_ribbon', None
    if policy['modes']['foot']['bits']:
        return ('foot_steps' if tags.get('highway') == 'steps' else 'foot_ribbon'), None
    return None, 'SOURCE_ACCESS_OR_DIRECTION_DOES_NOT_ALLOW_CAR_OR_FOOT'


def step_layout(points, width, hubs, tags):
    cells = []
    for span in K.structured_sections(points, width, hubs):
        i = span['index']; a_y, b_y = points[i][1], points[i + 1][1]
        for a, oa, ta, b, ob, tb in span['cells']:
            ya, yb = a_y + (b_y - a_y) * ta, a_y + (b_y - a_y) * tb
            cells.append({'a': a, 'oa': oa, 'b': b, 'ob': ob, 'ya': ya, 'yb': yb,
                          'rise': abs(yb - ya), 'run': math.dist(a, b)})
    moving = [cell for cell in cells if cell['rise'] > 1e-6]
    total = sum(cell['rise'] for cell in moving)
    report = {'source_step_count_raw': tags.get('step_count'), 'source_incline_raw': tags.get('incline'),
              'total_absolute_profile_rise_m': total, 'net_original_order_profile_rise_m': points[-1][1] - points[0][1],
              'actual_native_step_playback_verified': False, 'plausibility_is_game_policy_not_building_code': True}
    if not moving or total < MIN_RISER:
        return None, dict(report, status='UNRESOLVED_SOURCE_STEPS_WITH_NEAR_ZERO_PROFILE_RISE')
    incline = tags.get('incline')
    if incline not in (None, 'up', 'down'):
        return None, dict(report, status='UNRESOLVED_SOURCE_INCLINE_SYNTAX_NOT_YET_ENFORCED')
    if incline == 'up' and any(c['yb'] < c['ya'] - 1e-6 for c in moving) or incline == 'down' and any(c['yb'] > c['ya'] + 1e-6 for c in moving):
        return None, dict(report, status='UNRESOLVED_PROFILE_CONTRADICTS_ORIGINAL_SOURCE_INCLINE')
    raw_count = tags.get('step_count')
    if raw_count is not None and not re.fullmatch(r'[1-9]\d{0,3}', raw_count):
        return None, dict(report, status='UNRESOLVED_SOURCE_STEP_COUNT_SYNTAX')
    count = int(raw_count) if raw_count is not None else max(1, round(total / .17))
    if count > 2048 or count < len(moving):
        return None, dict(report, status='UNRESOLVED_STEP_COUNT_OR_FLIGHT_WORK_BUDGET')
    ideal = [count * c['rise'] / total for c in moving]
    allocation = [max(1, int(x)) for x in ideal]
    while sum(allocation) > count:
        candidates = [i for i, value in enumerate(allocation) if value > 1]
        if not candidates: return None, dict(report, status='UNRESOLVED_STEP_ALLOCATION')
        index = max(candidates, key=lambda i: allocation[i] - ideal[i]); allocation[index] -= 1
    for _ in range(count - sum(allocation)):
        index = max(range(len(moving)), key=lambda i: ideal[i] - allocation[i]); allocation[index] += 1
    for cell, steps in zip(moving, allocation):
        cell['steps'] = steps
        rise, tread = cell['rise'] / steps, cell['run'] / steps
        if not MIN_RISER <= rise <= MAX_RISER or tread < MIN_TREAD:
            return None, dict(report, status='UNRESOLVED_SOURCE_COUNT_PROFILE_RISER_OR_TREAD_FIT',
                              limiting_riser_m=rise, limiting_tread_m=tread, source_count_preserved=count)
    report.update(status='EXPLICIT_SOURCE_COUNT' if raw_count is not None else 'RECONSTRUCTED_COUNT_FROM_GAME_PROFILE_RISE',
                  steps=count, original_source_count_changed=False,
                  maximum_riser_m=max(c['rise']/c['steps'] for c in moving),
                  minimum_tread_m=min(c['run']/c['steps'] for c in moving),
                  continuous_walk_collision_with_separate_visible_steps=True)
    return cells, report


def _clip_polygon(points, bounds):
    result = [list(p) for p in points]
    if bounds is None: return result
    for axis, boundary, positive in [(0, bounds[0], True), (0, bounds[2], False), (2, bounds[1], True), (2, bounds[3], False)]:
        previous, output = result[-1] if result else None, []
        for point in result:
            inside = point[axis] >= boundary if positive else point[axis] <= boundary
            before = previous[axis] >= boundary if positive else previous[axis] <= boundary
            if inside != before:
                t = (boundary - previous[axis]) / (point[axis] - previous[axis])
                output.append([previous[i] + (point[i] - previous[i]) * t for i in range(3)])
            if inside: output.append(point)
            previous = point
        result = output
    return result


def visible_steps(cells, anchor, bounds):
    vertices, normals, indices = [], [], []
    counts = {'tread_triangles': 0, 'riser_triangles': 0}

    def quad(points, role):
        polygon = _clip_polygon(points, bounds)
        for i in range(1, len(polygon) - 1):
            tri = [np.asarray([p[j] - anchor[j] for j in range(3)], dtype='<f4').astype(float) for p in (polygon[0], polygon[i], polygon[i+1])]
            cross = np.cross(tri[1]-tri[0], tri[2]-tri[0]); length = np.linalg.norm(cross)
            if length < 1e-10: continue
            # Input quad is outward-clockwise; normals oppose its cross.
            normal = -cross / length
            if role == 'tread' and normal[1] < 0:
                tri[1], tri[2] = tri[2], tri[1]; normal = -normal
            for point in tri:
                indices.append(len(vertices)); vertices.append(point.tolist()); normals.append(normal.tolist())
            counts[role + '_triangles'] += 1

    for cell in cells:
        a, b, oa, ob = cell['a'], cell['b'], cell['oa'], cell['ob']
        steps = cell.get('steps', 1)
        for index in range(steps):
            t0, t1 = index/steps, (index+1)/steps
            def section(t, y):
                x, z = a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t
                ox, oz = oa[0]+(ob[0]-oa[0])*t, oa[1]+(ob[1]-oa[1])*t
                return [x+ox,y,z+oz], [x-ox,y,z-oz]
            rising = cell['yb'] >= cell['ya']
            low_y = cell['ya']+(cell['yb']-cell['ya'])*t0
            next_y = cell['ya']+(cell['yb']-cell['ya'])*t1
            # Exactly N visible height changes for N source steps. Walking
            # collision remains the explicitly separate continuous incline.
            y = next_y if rising else low_y
            al, ar = section(t0,y); bl, br = section(t1,y)
            quad([al, ar, br, bl], 'tread')
            if cell.get('steps'):
                at = t0 if rising else t1
                old_l, old_r = section(at,low_y)
                new_l, new_r = section(at,next_y)
                quad([old_l,old_r,new_r,new_l], 'riser')
    return {'vertices_local_xyz':vertices,'normals':normals,'indices':indices,
            'usage':'VISIBLE_STEPS_ONLY_NOT_COLLISION','counts':counts,
            'native_step_contact_animation_unverified':True}


def build_feature(identifier, raw, policy, ids, points, radii, clip, tile):
    kind, reason = classification(raw, policy)
    if reason: return None, {'source_way':identifier,'status':reason}
    hubs = [radii.get(v,0.) for v in ids]
    step_cells = step_report = None
    if kind == 'foot_steps':
        step_cells, step_report = step_layout(points,policy['width']['metres'],hubs,raw['tags'])
        if step_cells is None: return None, dict(step_report,source_way=identifier)
    anchor=[clip[0],0.,clip[1]]
    mesh=K.ribbon(points,policy['width']['metres'],anchor,clip,hubs)
    if not mesh['indices']:return None, {'source_way':identifier,'status':'NO_ACTUAL_CLIPPED_SURFACE'}
    if mesh['maximum_emitted_surface_slope']>EMITTED_LIMIT[kind]:
        vertices=mesh['vertices_local_xyz'];cx=anchor[0]+(min(v[0] for v in vertices)+max(v[0] for v in vertices))*.5;cz=anchor[2]+(min(v[2] for v in vertices)+max(v[2] for v in vertices))*.5
        choices=[]
        for y in (0.,points[0][1]):
            at=[cx,y,cz];candidate=K.ribbon(points,policy['width']['metres'],at,clip,hubs);choices.append((candidate['maximum_emitted_surface_slope'],at,candidate))
        _,at,candidate=min(choices,key=lambda x:x[0])
        if candidate['maximum_emitted_surface_slope']<mesh['maximum_emitted_surface_slope']:
            anchor,mesh=at,candidate
            mesh['codec_anchor_policy']='LOCAL_ENCODING_ONLY_SAME_CANONICAL_XZ_Y_PROFILE'
    if mesh['maximum_emitted_surface_slope']>EMITTED_LIMIT[kind]:
        raise ValueError(f'{identifier} actual {kind} Float32 slope exceeds strict contract: {mesh["maximum_emitted_surface_slope"]}')
    feature={'id':identifier,'name':raw.get('name'),'tile':tile,'anchor_source_xyz':anchor,
             'source_vertex_ids':ids,'source_points_xyz':points,'policy':policy,'source_tags':raw['tags'],
             'source_feature_sha256':raw['source_feature_sha256'],'source_geometry_sha256':raw['source_geometry_sha256'],
             'mesh':mesh,'physical_contract':{'schema':SCHEMA,'surface_class':kind,
                 'maximum_emitted_slope':EMITTED_LIMIT[kind],'required_native_slope_cap':NATIVE_LIMIT[kind],
                 'native_loader_must_derive_limits_from_class_not_trust_numbers':True,
                 'source_car_direction_bits':policy['modes']['car']['bits'],'source_foot_direction_bits':policy['modes']['foot']['bits'],
                 'native_traversal_verified':False,'terrain_cut_fill_portal_cover_deck_underside_edge_protection_built':False}}
    if kind=='foot_steps':
        feature['visual_mesh']=visible_steps(step_cells,anchor,clip)
        feature['step_evidence']=step_report
        feature['mesh']['usage']='CONTINUOUS_STAIR_WALK_COLLISION_ONLY'
        feature['mesh']['native_collision_uses_identical_topology']=False
    return feature, None
