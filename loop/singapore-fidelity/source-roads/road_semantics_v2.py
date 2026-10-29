"""Versioned OSM structure semantics, separate from inferred metric choices.

R5 is immutable. This module does not mutate source tags, IDs, coordinates,
mode/direction policy, a DB, or any runtime instance.
"""
import json
import math
import re

POLICY_VERSION='source_road_vertical_semantics_v2'
BUILDING_PASSAGE='https://wiki.openstreetmap.org/wiki/Tag:tunnel%3Dbuilding_passage'
LAYER='https://wiki.openstreetmap.org/wiki/Key:layer'
TUNNEL='https://wiki.openstreetmap.org/wiki/Key:tunnel'
FALSE_VALUES={None,'no','false','0'}
SUBSURFACE_TUNNELS={'yes','culvert','flooded'}


def grade_policy(tags):
    if not isinstance(tags,dict) or not all(isinstance(k,str) and isinstance(v,str) for k,v in tags.items()):
        raise ValueError('Exact string source tags required')
    bridge=tags.get('bridge') not in FALSE_VALUES
    raw_tunnel=tags.get('tunnel')
    passage=raw_tunnel=='building_passage'
    explicit_underground=tags.get('location') in ('underground','underwater')
    subsurface=raw_tunnel in SUBSURFACE_TUNNELS or (passage and explicit_underground)
    unknown_tunnel=raw_tunnel not in FALSE_VALUES and not passage and not subsurface
    raw_layer=tags.get('layer');explicit_layer=raw_layer is not None and re.fullmatch(r'-?\d+',raw_layer) is not None
    parsed_layer=int(raw_layer) if explicit_layer else None
    if parsed_layer is not None and abs(parsed_layer)>1000:
        raise ValueError('Unbounded layer ordinal requires review; source is not clamped')
    if raw_layer is not None and not explicit_layer:
        layer=None;status='UNRESOLVED_SOURCE_LAYER_ORDINAL_PRESERVED'
    else:
        layer=parsed_layer if explicit_layer else 1 if bridge else -1 if subsurface else 0
        status='EXPLICIT_SOURCE_VERTICAL_ORDER_NOT_METRES' if explicit_layer else 'DEFAULT_STRUCTURE_ORDER_NOT_SOURCE_ELEVATION'
    if bridge and subsurface:structure='conflicting_structure'
    elif bridge:structure='bridge'
    elif subsurface:structure='tunnel'
    elif passage:structure='covered_passage'
    elif unknown_tunnel:structure='unresolved_tunnel_value'
    else:structure='surface'
    # Covered at a compatible source layer/level is the same surface grade at
    # an ORIGINAL shared OSM node; no connection is inferred from equal XZ.
    connection_class='surface' if structure=='covered_passage' else structure
    layer_key=layer if layer is not None else {'unresolved_raw_layer':raw_layer}
    signature=json.dumps([connection_class,layer_key,tags.get('level','')],separators=(',',':'),sort_keys=True)
    return {'key':signature,'structure':structure,'connection_class':connection_class,'layer':layer,
            'level':tags.get('level',''),'raw_layer':raw_layer,'raw_tunnel':raw_tunnel,'raw_bridge':tags.get('bridge'),
            'covered_building_passage':passage,'explicit_underground_location':explicit_underground,
            'source_layer_explicit':explicit_layer,'status':status,'vertical_profile_source':'UNRESOLVED_METRIC_SOURCE_ELEVATION',
            'source_ele_tag':tags.get('ele'),'source_ele_datum':tags.get('ele:datum'),
            'metric_layer_height_is_source_fact':False,'inference_policy':POLICY_VERSION}


def metric_assumption(grade,preferred_egm96):
    if isinstance(preferred_egm96,bool) or not isinstance(preferred_egm96,(int,float)) or not math.isfinite(preferred_egm96):
        raise ValueError('Finite preferred DEM reference required')
    structure=grade['structure'];lower=upper=None
    if structure=='bridge':lower=preferred_egm96+6.
    elif structure=='tunnel':upper=preferred_egm96-5.
    return {'lower_y':lower,'upper_y':upper,'preferred_y':float(preferred_egm96),
            'status':'EXPLICIT_GAME_STRUCTURE_CLEARANCE_NOT_SURVEY_OR_ORDINAL_STOREY',
            'bridge_clearance_game_m':6.,'ordinary_tunnel_cover_game_m':5.,
            'layer_ordinal_multiplied_into_metres':False,
            'covered_passage_implies_depth_cap':False,'profile_source_datum':'coarse EGM96 preferred reference, not road survey'}


def ramp_order_assumption(first_layer,last_layer,*,source_way_connected,ports_overlap,
                          original_endpoint_nodes,available_source_path_m):
    """A local source-proven grade order, never a metric layer multiplication.

    The caller must prove an original connected way joins overlapping portals
    with different continuation orders. A 5m reconstructed separation is one
    explicit game choice for the site; all ordinal differences use one gap.
    The eventual profile solver must enforce the relative constraint and may
    reject infeasible sites. This function does not move either portal.
    """
    if not isinstance(source_way_connected,bool) or not isinstance(ports_overlap,bool):
        raise ValueError('Typed explicit source connectivity/overlap proof required')
    if not isinstance(original_endpoint_nodes,(list,tuple)) or len(original_endpoint_nodes)!=2 or any(isinstance(v,bool) or not isinstance(v,int) or v<=0 for v in original_endpoint_nodes):
        raise ValueError('Two exact original OSM endpoint IDs required')
    if not source_way_connected or not ports_overlap or original_endpoint_nodes[0]==original_endpoint_nodes[1]:
        return {'status':'NO_SOURCE_PROVEN_LOCAL_RAMP_ORDER','constraint':None}
    if any(isinstance(v,bool) or not isinstance(v,int) for v in (first_layer,last_layer)) or first_layer==last_layer:
        return {'status':'NO_DISTINCT_RESOLVED_SOURCE_ORDER','constraint':None}
    if isinstance(available_source_path_m,bool) or not isinstance(available_source_path_m,(int,float)) or not math.isfinite(available_source_path_m) or available_source_path_m<=0:
        raise ValueError('Actual connected source path length required')
    gap=5.
    if available_source_path_m*.12<gap:
        return {'status':'INFEASIBLE_LOCAL_GAME_CLEARANCE_REQUIRES_REVIEW','constraint':None,'requested_game_gap_m':gap}
    high=0 if first_layer>last_layer else 1
    return {'status':'SOURCE_ORDER_WITH_SEPARATE_RECONSTRUCTED_SITE_CLEARANCE',
            'constraint':{'upper_endpoint':high,'lower_endpoint':1-high,'minimum_game_separation_m':gap},
            'source_original_endpoint_nodes':list(original_endpoint_nodes),'source_way_path_m':available_source_path_m,
            'ordinal_difference_used_as_metric_storeys':False,'native_or_as_built_clearance_verified':False}
