"""Source-derived physical existence is separate from AI navigation access.

Pure candidate policy only. No source tags, road graph, solver bounds or mesh
are mutated here. The v3 and first typed prototype remain immutable.
"""
import math
import re

POLICY='source_physical_road_and_stair_constraints_v4'
VEHICLE_TYPES={'motorway','motorway_link','trunk','trunk_link','primary','primary_link',
               'secondary','secondary_link','tertiary','tertiary_link','unclassified',
               'residential','living_street','service','track','raceway','road'}
FOOT_TYPES={'footway','pedestrian','path','steps','bridleway','cycleway','corridor','platform'}
MIN_GAME_RISER=.08
MAX_GAME_RISER=.24


def physical_role(tags,mode_policy):
    highway=tags.get('highway','')
    modes={name:int(mode_policy['modes'][name]['bits']) for name in ('car','bicycle','foot')}
    if highway in ('construction','proposed') or tags.get('construction') or tags.get('proposed'):
        kind='construction_or_proposed_site';grade=None;status='REQUIRES_SITE_GEOMETRY_NOT_ORDINARY_FINISHED_ROAD'
    elif highway=='elevator':
        kind='vertical_transport';grade=None;status='REQUIRES_FLOOR_REGISTRY_AND_PHYSICAL_LIFT'
    elif tags.get('area')=='yes':
        kind='source_area';grade=.12 if highway in VEHICLE_TYPES or modes['car'] else .25
        status='REQUIRES_AREA_AND_HOLE_MEMBERSHIP_NOT_A_LINE_RIBBON'
    elif highway=='steps':
        kind='foot_steps';grade=.7;status='SOURCE_STAIR_CONSTRAINT_AND_GEOMETRY_REQUIRED'
    elif highway in VEHICLE_TYPES or modes['car'] and highway not in ('corridor','platform'):
        kind='vehicle_road';grade=.12;status='PHYSICAL_VEHICLE_ROAD_EXISTS_INDEPENDENT_OF_ACCESS_BITS'
    elif highway in FOOT_TYPES:
        kind='foot_surface';grade=.25;status='PHYSICAL_FOOT_SURFACE_EXISTS_INDEPENDENT_OF_ACCESS_BITS'
    else:
        kind='unresolved';grade=None;status='SOURCE_HIGHWAY_GEOMETRY_CLASS_UNRESOLVED'
    return {'policy':POLICY,'physical_kind':kind,'maximum_game_grade':grade,'status':status,
            'original_navigation_direction_bits':modes,'AI_access_bits_changed':False,
            'raw_source_access':{k:v for k,v in tags.items() if k in ('access','vehicle','motor_vehicle','motorcar','foot','bicycle') or k.endswith(':conditional')},
            'source_floor_level':tags.get('level'),'floor_binding_required':bool(tags.get('level')),
            'source_tags_changed':False,'native_or_physical_mesh_acceptance':False}


def stair_constraints(tags,ordered_node_ids,source_run_m):
    if tags.get('highway')!='steps':return None
    if not isinstance(ordered_node_ids,list) or len(ordered_node_ids)<2 or any(type(v)is not int or v<=0 for v in ordered_node_ids):
        raise ValueError('Exact original ordered source nodes required')
    if not math.isfinite(source_run_m) or source_run_m<0:raise ValueError('Finite nonnegative original source run required')
    incline=tags.get('incline');raw_count=tags.get('step_count')
    sign=1 if incline=='up' else -1 if incline=='down' else None
    count=int(raw_count) if isinstance(raw_count,str) and re.fullmatch(r'[1-9]\d{0,3}',raw_count) else None
    result={'policy':POLICY,'source_incline_raw':incline,'source_step_count_raw':raw_count,
            'source_original_endpoint_nodes':[ordered_node_ids[0],ordered_node_ids[-1]],
            'source_way_run_m':source_run_m,'reliable_original_order_sign':sign,'source_step_count':count,
            'source_order_or_count_rewritten':False,'plausible_riser_is_game_inference_not_source_measurement':True,
            'game_riser_interval_m':[MIN_GAME_RISER,MAX_GAME_RISER],
            'requires_stair_specific_portal_geometry_not_legacy_full_flat_aprons':True}
    if raw_count is not None and count is None:
        return dict(result,status='UNRESOLVED_SOURCE_STEP_COUNT_SYNTAX_PRESERVED')
    if incline not in (None,'up','down'):
        return dict(result,status='UNRESOLVED_INCLINE_VALUE_PRESERVED_FOR_EXPLICIT_SEMANTIC_REVIEW')
    if count is not None and count>2048:
        return dict(result,status='STEP_WORK_BUDGET_EXCEEDED_NO_TRUNCATION')
    if sign is None:
        return dict(result,status='COUNT_PRESERVED_DIRECTION_NEEDS_CONNECTED_SOURCE_HEIGHT_INFERENCE')
    if ordered_node_ids[0]==ordered_node_ids[-1]:
        return dict(result,status='CONTRADICTORY_SIGNED_CLOSED_SAME_NODE_STAIR_SOURCE')
    minimum=count*MIN_GAME_RISER if count is not None else MIN_GAME_RISER
    maximum=min(count*MAX_GAME_RISER,.7*source_run_m) if count is not None else .7*source_run_m
    if maximum<minimum-1e-8:
        return dict(result,status='SOURCE_COUNT_RUN_AND_UNCHANGED_STEP_GRADE_INFEASIBLE',minimum_game_rise_m=minimum,maximum_game_rise_m=maximum)
    return dict(result,status='SOURCE_SIGN_WITH_EXPLICIT_GAME_RISE_INTERVAL',minimum_game_rise_m=minimum,maximum_game_rise_m=maximum,
                lower_original_node=ordered_node_ids[0] if sign>0 else ordered_node_ids[-1],
                upper_original_node=ordered_node_ids[-1] if sign>0 else ordered_node_ids[0],
                each_ordered_segment_must_not_reverse_reliable_source_sign=True,
                global_solver_and_geometry_acceptance=False)
