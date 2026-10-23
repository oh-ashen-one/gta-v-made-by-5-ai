class_name PerfPreload
extends RefCounted
## Wave S performance piece: load-time overlap. Before the world is built,
## main.gd asks the ResourceLoader to load the scenes and textures the start-up
## needs on worker threads (in the order the build first uses them), so their
## file reads, decompression and GPU uploads overlap the single-threaded
## GDScript world build. A later load() of the same path waits for (or reuses)
## the threaded result, so behaviour is unchanged; missing private assets are
## skipped. `--no-preload` turns it off for A/B timing; headless runs skip it.
## The list was generated from a --verbose start-up (wave S, 2026-10-23):
## every non-script resource loaded before world_ui_ready, first-use order.

const PATHS := [
	"res://assets/authored/surfaces/weather_masks.png",
	"res://assets/authored/surfaces/asphalt_albedo.png",
	"res://assets/authored/surfaces/asphalt_normal.png",
	"res://assets/authored/surfaces/asphalt_aggregate_albedo.png",
	"res://assets/authored/surfaces/asphalt_aggregate_normal.png",
	"res://assets/providers/higgsfield/road_asphalt_albedo.png",
	"res://assets/providers/higgsfield/road_asphalt_normal.png",
	"res://assets/authored/surfaces/pavers_albedo.png",
	"res://assets/authored/surfaces/pavers_normal.png",
	"res://assets/authored/surfaces/pavers_roughness.png",
	"res://assets/providers/higgsfield/concrete_weathered_albedo.png",
	"res://assets/providers/higgsfield/concrete_weathered_normal.png",
	"res://assets/authored/surfaces/concrete_albedo.png",
	"res://assets/authored/surfaces/concrete_normal.png",
	"res://assets/authored/surfaces/soil_albedo.png",
	"res://assets/authored/surfaces/soil_normal.png",
	"res://assets/providers/higgsfield/footpath_pavers_albedo.png",
	"res://assets/providers/higgsfield/footpath_pavers_normal.png",
	"res://assets/providers/higgsfield/footpath_pavers_rough.png",
	"res://assets/providers/higgsfield/foliage_median_atlas.png",
	"res://assets/authored/surfaces/metal_albedo.png",
	"res://assets/authored/surfaces/street_signs_albedo.png",
	"res://assets/authored/surfaces/metal_normal.png",
	"res://assets/authored/surfaces/metal_roughness.png",
	"res://assets/authored/surfaces/plaster_albedo.png",
	"res://assets/authored/surfaces/plaster_normal.png",
	"res://assets/providers/planter_clean.glb",
	"res://assets/providers/planter_clean_tropical+plant+3d+model_basecolor.jpg",
	"res://assets/providers/planter_clean_tropical+plant+3d+model_rm.jpg",
	"res://assets/providers/planter_clean_tropical+plant+3d+model_normal.png",
	"res://assets/providers/shophouse_clean.glb",
	"res://assets/providers/shophouse_clean_Color_bd941274-9ef3-419c-befe-da22efed2b85.jpg",
	"res://assets/providers/shophouse_clean_ORM_bd941274-9ef3-419c-befe-da22efed2b85.jpg",
	"res://assets/providers/shophouse_clean_NormalGL_bd941274-9ef3-419c-befe-da22efed2b85.png",
	"res://assets/authored/fern.glb",
	"res://assets/providers/ac_unit_clean.glb",
	"res://assets/providers/ac_unit_clean_air+conditioner+unit+3d+model_basecolor.jpg",
	"res://assets/providers/ac_unit_clean_air+conditioner+unit+3d+model_rm.jpg",
	"res://assets/providers/ac_unit_clean_air+conditioner+unit+3d+model_normal.png",
	"res://assets/authored/surfaces/chalk_menu_albedo.png",
	"res://assets/providers/hdb_slab_clean.glb",
	"res://assets/providers/hdb_slab_clean_texture_pbr_20250901.png",
	"res://assets/providers/hdb_slab_clean_texture_pbr_20250901_metallic-texture_pbr_20250901_roughness.png",
	"res://assets/providers/hdb_slab_clean_texture_pbr_20250901_normal.png",
	"res://assets/authored/rain_tree.glb",
	"res://assets/authored/rain_tree_rain_tree_bark.png",
	"res://assets/authored/rain_tree_rain_tree_bark_normal.png",
	"res://assets/providers/service_clutter_clean.glb",
	"res://assets/providers/service_clutter_clean_trash+bins+3d+model_basecolor.jpg",
	"res://assets/providers/service_clutter_clean_trash+bins+3d+model_rm.jpg",
	"res://assets/providers/service_clutter_clean_trash+bins+3d+model_normal.png",
	"res://assets/authored/supertree_grove.glb",
	"res://assets/authored/hawker_pavilion.glb",
	"res://assets/authored/hawker_pavilion_hawker_pavilion_terracotta.png",
	"res://assets/providers/hawker_counter_refined.glb",
	"res://assets/providers/hawker_counter_refined_hawker+stall+3d+model_basecolor.jpg",
	"res://assets/providers/player_clean.glb",
	"res://assets/providers/player_clean_Color_7c03bee9-b47e-419a-813e-ccc0106d092e.jpg",
	"res://assets/providers/player_clean_ORM_7c03bee9-b47e-419a-813e-ccc0106d092e.jpg",
	"res://assets/providers/player_clean_NormalGL_7c03bee9-b47e-419a-813e-ccc0106d092e.png",
	"res://assets/providers/hawker_table_refined.glb",
	"res://assets/providers/hawker_table_refined_round+table+3d+model_basecolor.jpg",
	"res://assets/authored/hawker_meal.glb",
	"res://assets/providers/officer_clean.glb",
	"res://assets/providers/officer_clean_Color_b351e7bc-2305-42e4-bc74-b35a2256b75f.jpg",
	"res://assets/providers/officer_clean_ORM_b351e7bc-2305-42e4-bc74-b35a2256b75f.jpg",
	"res://assets/providers/officer_clean_NormalGL_b351e7bc-2305-42e4-bc74-b35a2256b75f.png",
	"res://assets/providers/helicopter_clean.glb",
	"res://assets/providers/helicopter_clean_Color_6982c251-8629-479f-b267-fea6cc6d8c2c.jpg",
	"res://assets/providers/helicopter_clean_ORM_6982c251-8629-479f-b267-fea6cc6d8c2c.jpg",
	"res://assets/providers/helicopter_clean_NormalGL_6982c251-8629-479f-b267-fea6cc6d8c2c.png",
	"res://assets/providers/airfield_clutter_clean.glb",
	"res://assets/providers/airfield_clutter_clean_weathered+cargo+crates+3d+model_basecolor.jpg",
	"res://assets/providers/airfield_clutter_clean_weathered+cargo+crates+3d+model_rm.jpg",
	"res://assets/providers/airfield_clutter_clean_weathered+cargo+crates+3d+model_normal.png",
	"res://assets/authored/interior_safe_furnishings.glb",
	"res://assets/authored/interior_convenience_shop.glb",
	"res://assets/authored/interior_convenience_shop_packaging_atlas.png",
	"res://assets/authored/surfaces/concrete_roughness.png",
	"res://assets/authored/surfaces/plaster_roughness.png",
	"res://assets/authored/interior_workshop.glb",
	"res://assets/authored/merlion_landmark.glb",
	"res://assets/providers/street_lamp_clean.glb",
	"res://assets/providers/street_lamp_clean_street+lamp+3d+model_basecolor.jpg",
	"res://assets/providers/street_lamp_clean_street+lamp+3d+model_rm.jpg",
	"res://assets/providers/street_lamp_clean_street+lamp+3d+model_normal.png",
	"res://assets/authored/skyline_2.glb",
	"res://assets/authored/skyline_3.glb",
	"res://assets/authored/skyline_0.glb",
	"res://assets/authored/skyline_1.glb",
	"res://assets/authored/boundary_railing.glb",
	"res://assets/authored/palm.glb",
	"res://assets/authored/singapore_flyer.glb",
	"res://assets/providers/higgsfield/rooftop_flat_albedo.png",
	"res://assets/providers/higgsfield/sign_teck_huat_kopitiam.png",
	"res://assets/providers/higgsfield/sign_sin_leong_hardware.png",
	"res://assets/providers/higgsfield/sign_mei_ling_tailor.png",
	"res://assets/providers/higgsfield/sign_joo_heng_medical_hall.png",
	"res://assets/providers/higgsfield/sign_ah_kow_prawn_noodle.png",
	"res://assets/providers/higgsfield/sign_kim_seng_provision.png",
	"res://assets/providers/higgsfield/sign_golden_lotus_money_changer.png",
	"res://assets/providers/higgsfield/sign_happy_cycles.png",
	"res://assets/providers/pistol_clean.glb",
	"res://assets/providers/pistol_clean_pistol+3d+model_basecolor.jpg",
	"res://assets/providers/pistol_clean_pistol+3d+model_rm.jpg",
	"res://assets/providers/pistol_clean_pistol+3d+model_normal.png",
	"res://assets/providers/player_rigged_loco4.glb",
	"res://assets/providers/player_rigged_loco4_Color_7c03bee9-b47e-419a-813e-ccc0106d092e.jpg",
	"res://assets/providers/player_rigged_loco4_ORM_7c03bee9-b47e-419a-813e-ccc0106d092e.jpg",
	"res://assets/providers/player_rigged_loco4_NormalGL_7c03bee9-b47e-419a-813e-ccc0106d092e.png",
	"res://assets/providers/player_rigged_loco4_OrchardOriginalCharcoalWeave.png",
	"res://assets/providers/pistol_held.glb",
	"res://assets/providers/pistol_held_pistol+3d+model_basecolor.jpg",
	"res://assets/providers/pistol_held_pistol+3d+model_rm.jpg",
	"res://assets/providers/pistol_held_pistol+3d+model_normal.png",
	"res://assets/providers/coupe_clean.glb",
	"res://assets/providers/coupe_clean_texture_pbr_20250901.png",
	"res://assets/providers/coupe_clean_texture_pbr_20250901_metallic-texture_pbr_20250901_roughness.png",
	"res://assets/providers/coupe_clean_texture_pbr_20250901_normal.png",
	"res://assets/providers/civilian_rigged_v2.glb",
	"res://assets/providers/civilian_rigged_v2_Color_7c03bee9-b47e-419a-813e-ccc0106d092e.jpg",
	"res://assets/providers/civilian_rigged_v2_ORM_7c03bee9-b47e-419a-813e-ccc0106d092e.jpg",
	"res://assets/providers/civilian_rigged_v2_NormalGL_7c03bee9-b47e-419a-813e-ccc0106d092e.png",
	"res://assets/providers/civilian_rigged_v2_OrchardOriginalCharcoalWeave.png",
	"res://assets/providers/van_clean.glb",
	"res://assets/providers/van_clean_texture_pbr_20250901.png",
	"res://assets/providers/van_clean_texture_pbr_20250901_metallic-texture_pbr_20250901_roughness.png",
	"res://assets/providers/van_clean_texture_pbr_20250901_normal.png",
	"res://assets/providers/sedan_clean.glb",
	"res://assets/providers/sedan_clean_Color_c00e82b4-f67d-42f8-8980-663ac27d866f.jpg",
	"res://assets/providers/sedan_clean_ORM_c00e82b4-f67d-42f8-8980-663ac27d866f.jpg",
	"res://assets/providers/sedan_clean_NormalGL_c00e82b4-f67d-42f8-8980-663ac27d866f.png",
	"res://assets/providers/officer_rigged_v2.glb",
	"res://assets/providers/officer_rigged_v2_Color_b351e7bc-2305-42e4-bc74-b35a2256b75f.jpg",
	"res://assets/providers/officer_rigged_v2_ORM_b351e7bc-2305-42e4-bc74-b35a2256b75f.jpg",
	"res://assets/providers/officer_rigged_v2_NormalGL_b351e7bc-2305-42e4-bc74-b35a2256b75f.png",
	"res://assets/providers/helicopter_refined.glb",
	"res://assets/providers/helicopter_refined_Color_6982c251-8629-479f-b267-fea6cc6d8c2c.jpg",
	"res://assets/providers/helicopter_refined_ORM_6982c251-8629-479f-b267-fea6cc6d8c2c.jpg",
	"res://assets/providers/helicopter_refined_NormalGL_6982c251-8629-479f-b267-fea6cc6d8c2c.png"
]

static var requested := 0

static func start() -> void:
	if "--no-preload" in OS.get_cmdline_user_args():
		return
	# The headless dummy renderer's texture storage is not thread-safe (a
	# worker-thread texture racing the main thread logged 'Parameter "t" is
	# null'); the real renderer creates textures from loader threads safely.
	if DisplayServer.get_name() == "headless" and not ("--preload-headless" in OS.get_cmdline_user_args()):
		return
	for p: String in PATHS:
		if ResourceLoader.exists(p):
			if ResourceLoader.load_threaded_request(p, "", true) == OK:
				requested += 1
	print("[perf] threaded preload requested: ", requested, " resources")

## Hands the finished threaded loads back (the loader keeps each result
## referenced until it is fetched); still-running ones are retried later.
static func finish(tree: SceneTree) -> void:
	var pending := 0
	for p: String in PATHS:
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(p)
		elif st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			pending += 1
	if pending > 0 and tree != null:
		tree.create_timer(1.0).timeout.connect(finish.bind(tree))
