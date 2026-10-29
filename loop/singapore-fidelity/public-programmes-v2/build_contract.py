"""Versioned source-bound public-programme contract. CPU only; no runtime adoption.

The metric world polygons come verbatim from the frozen OSM tile. The operator
brochure provides programme/topological facts, not a world registration or a
surveyed slab. No rectangle profile or legacy elevation is promoted to fact.
"""
from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
TILE=ROOT/'game/data/geography/osm-2026-10-27/0_-1.json'
REGISTRY=ROOT/'loop/singapore-fidelity/exterior-shell/PUBLIC_MIXED_USE_FLOOR_REGISTRY_PROPOSAL_V14.json'
CITY=ROOT/'loop/singapore-fidelity/recovery/private/city-geometry/candidate-r2/catalogs/0_-1.json'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def stable(v):return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def write(name,value):(OUT/name).write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
def source_bindings():
    tile=json.loads(TILE.read_text()); features={f['id']:f for f in tile['features']}
    city={f['id']:f for f in json.loads(CITY.read_text())['features']}
    rows=[]
    relation_rows=json.loads((OUT/'RELATION_MEMBER_EVIDENCE.json').read_text())['relations']
    for rel in relation_rows:
        key=rel['building_key'];relationid=rel['relation_id'];members=rel['members']
        parts=[]
        for m in members:
            sid=m['source_id']; f=features.get(sid); c=city.get(sid)
            if f is None:raise ValueError('Required frozen source member missing: '+sid)
            pts=[q for poly in f['geometry']['coordinates'] for ring in poly for q in ring]
            parts.append({**m,'feature_key':'building|'+sid,'source_tags':f['tags'],'geometry_world_xz':f['geometry'],'source_geometry_sha256':stable(f['geometry']),'source_record_sha256':stable(f),'source_tile':str(TILE.relative_to(ROOT)),'source_tile_sha256':digest(TILE),'world_bounds_xz':[min(q[0] for q in pts),min(q[1] for q in pts),max(q[0] for q in pts),max(q[1] for q in pts)],'geometry_role':'outline_or_building_part_NOT_floor_slab','frozen_city_status':c.get('status') if c else 'NOT_PRESENT_IN_THIS_CITY_CATALOGUE','frozen_city_source_feature_sha256':c.get('source_feature_sha256') if c else None,'frozen_city_mesh_tiles':c.get('mesh_tiles',[]) if c else []})
        rows.append({'building_key':key,'relation_source_id':'relation/'+relationid,'relation_version':rel['version'],'relation_timestamp_utc':rel['timestamp_utc'],'relation_source_url':'https://api.openstreetmap.org/api/0.6/relation/'+relationid,'relation_response_sha256':rel['raw_response_sha256'],'relation_name':rel['name'],'relation_observation_utc':'2026-10-29T19:43:58Z','metadata_scope':'New identity/member metadata only; retained2026-10-27 geometry is not replaced with current network geometry. Relation metadata is not asserted to have been independently present in original PBF.','parts':parts,'generic_city_replacement_feature_keys':[p['feature_key'] for p in parts],'already_excluded_source_keys':[p['feature_key'] for p in parts if p['frozen_city_status']=='excluded_root_special_complex'],'replacement_policy':{'replace_only_exact_source_ids':True,'no_spatial_blanket_deletion':True,'install_real_collision_before_removing_generic':True,'preserve_unreplaced_roof_parts_and_adjacent_buildings':True,'wait_for_readiness_and_physics_frame_before_entry':True,'source_face_and_saved_identity_mapping_required':True},'planar_outline_is_not_every_floor_slab':True,'terrain_basement_cutouts_verified':False})
    return {'schema':'mbs_public_building_bindings_v2','coordinate_frame':json.loads((ROOT/'game/data/geography/osm-2026-10-27/manifest.json').read_text())['georeference'],'frozen_country_manifest_sha256':digest(ROOT/'game/data/geography/osm-2026-10-27/manifest.json'),'frozen_source_tile_sha256':digest(TILE),'buildings':rows,'source_attribution':'© OpenStreetMap contributors, ODbL-1.0','license_url':'https://www.openstreetmap.org/copyright','production_pin_changed':False}

def build():
    bindings=source_bindings();write('SOURCE_BUILDING_BINDINGS.json',bindings)
    registry=json.loads(REGISTRY.read_text()); seeds=json.loads((OUT/'PROGRAMME_SEEDS.json').read_text()); plans=json.loads((OUT/'OPERATOR_PLAN_OBSERVATIONS.json').read_text())
    levels=[]
    for fid in ['EXPO-L3','MUSEUM-B2','MUSEUM-L4','MUSEUM-B1']:
        record=registry['floor_records'][fid]; zones=seeds['levels'][fid]
        levels.append({'floor_id':fid,'building_key':record['building'],'label':record['level'],'registry_record':record,'zones':zones,'source_building_binding':record['building'],'physical_floor_must_remain_built':True,'legacy_elevation_m':record.get('metric_elevation_m'),'elevation_status':record['metric_elevation_status'],'world_slab_polygon':None,'world_slab_status':'MISSING_SURVEY_OR_EXPLICIT_SOURCE_CONFORMING_RECONSTRUCTION_APPROVAL','world_zone_polygons':None,'whole_floor_occupancy_claimed':False,'native_build_ready':False,'do_not_spawn_old_rectangle_fallback':True,'completion_requirements':['A real level envelope tied to source body/outline, with holes and neighboring levels.','Explicit metric Y with provenance; legacy label or roof height is insufficient.','All zone programmes, service/public circulation, two independent exits and lift/stair landing ownership.','All programme polygons inside actual slab, non-overlapping usable areas, supported doors and unchanged full Player capsule.','Exact source-ID generic collision replacement and terrain holes installed atomically only after actual geometry readiness.','Native continuous entry/traversal and actual rendered review.']})
    contract={'schema':'mbs_public_programme_contract_v2','version':2,'state':'SOURCE_BOUND_PROGRAMME_CONTRACT_NOT_YET_NATIVE_FLOOR_GEOMETRY','target_epoch':'2026 current three-tower resort','registry_input':{'path':str(REGISTRY.relative_to(ROOT)),'sha256':digest(REGISTRY),'retained_legacy_floor_count':registry['legacy_floor_ids_retained'],'new_documented_level_ids':registry['new_documented_level_ids']},'source_binding_artifact':{'path':'SOURCE_BUILDING_BINDINGS.json','sha256':digest(OUT/'SOURCE_BUILDING_BINDINGS.json')},'programme_seed_sha256':digest(OUT/'PROGRAMME_SEEDS.json'),'plan_observations_sha256':digest(OUT/'OPERATOR_PLAN_OBSERVATIONS.json'),'levels':levels,'operator_plan_observations':plans,'required_programme_groups':{'EXPO-L3':{'main_ballroom':5,'junior_ballroom':5,'meeting_room_requirement':5,'fitness_centre':1},'MUSEUM-B2':{'public_gallery_programme':2,'box_office':1,'learning_laboratory':1},'MUSEUM-L4':{'cinema':1,'lift_lobby':1,'vr_gallery':1}},'hotel_coordination':{'separate_registry_not_competing_schedule':True,'guest_key_catalogue_target':1844,'guest_suite_catalogue_target':775,'existing_guest_inventory_mutated':False,'tower_cores_or_axes_changed':False,'T2_L5_T1_L55_T2_L55':'Keep mixed-use uncertainty; no whole-floor guest exclusions inferred from venue labels. Outside this contract concrete reservations.'},'global_rules':{'no_permanent_generic_rectangle':True,'no_claim_outline_equals_slab':True,'no_fabricated_private_asbuilt':True,'museum_B1_not_relabelled_2026_education':True,'no_existing_game_factories_modified':True,'all_programmes_preserved_pending_metric_fit':True,'plan_scale_or_georegistration_verified':False,'engine_or_gameplay_acceptance':False,'current_source_shell_not_replaced':True}}
    write('PUBLIC_PROGRAMME_CONTRACT_V2.json',contract)
    return contract
if __name__=='__main__':
    c=build();print('contract',len(c['levels']),'floors',sum(len(f['zones']) for f in c['levels']),'zones')
