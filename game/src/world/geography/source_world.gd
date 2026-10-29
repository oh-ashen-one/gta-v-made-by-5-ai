extends Node3D
## Development entry for the actual source world. One common frame/context,
## actual native terrain/building/road collision and production gameplay actors.
## Root must supply packaged dataset locations before replacing normal main.
## No fictional city, flat sea/land fallback, local-coordinate save migration,
## or implicit origin rebase occurs here.
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_world_guard.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const DEM = preload("res://src/world/geography/source_terrain.gd")
const Tiles = preload("res://src/world/geography/runtimecity_tiles.gd")
const City = preload("res://src/world/geography/city_scene.gd")
const Terrain = preload("res://src/world/geography/terrain_scene.gd")
const Roads = preload("res://src/world/geography/source_roads.gd")
const Materials = preload("res://src/world/geography/source_world_materials.gd")
const SourceHUD = preload("res://src/world/geography/source_world_hud.gd")
const SessionController = preload("res://src/world/geography/source_session_controller.gd")
const Site = preload("res://src/world/mbs_interior/site.gd")
const Stack = preload("res://src/world/mbs_interior/floor_stack.gd")
const Hotel = preload("res://src/world/mbs_interior/hotel.gd")
const Public = preload("res://src/world/mbs_interior/public_l1.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const SiteReference = preload("res://src/world/mbs_interior/site_reference.gd")
const Cabins = preload("res://src/world/mbs_interior/cabins.gd")
const SNAPSHOT := "d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983"
const DOMAIN_SHA := "82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834"
const DEM_SHA := "5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841"
const CITY_SHA := "8b84896f8c9134b5933b2f6c3b036d025a1120d526ab12668e32181d4f148963"
const TERRAIN_SHA := "f8488742dd93726276b33ca12cda7c6d0a38b967123a0be0d574b9145b7f469c"
const MASKS_SHA := "9d91185dab9c936316b1397a7faad778556b28fb29e44f01f03b4fe04d498625"
const ROADS_SHA := "4e80cfc7f2d7ea898dc9479a7e91fb7670757522e6b09e03919187574bcf0802"
const SOURCE_ORIGIN := [0.0,0.0,-500.0]
const START := [436.9498,6.1851874,577.2218]
## Next original-node position on the pinned actual primary route. This is
## arrival placement only; the route has not thereby been physically driven.
const CAR_ARRIVAL := [432.0735,6.1297323816219835,585.591]
const CAR_FORWARD_NEXT := [417.533,7.5187707960595604,610.5649]
const HOTEL_ANCHOR := [461.805267208433,0.0,-1030.482512158889]
const Y_POLICY := {"mode":"EGM96_DEM_game_world_reference_not_current_survey","offset_m":0.0}
const PROFILE := {"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":.6156614753256583,"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}

signal source_world_ready(receipt: Dictionary)
signal source_world_failed(reason: String)
signal source_rebase_requested(source_xyz: Array, origin_revision: int)
signal source_region_requested(cell: String, source_xyz: Array)
signal source_save_requested(pose: Dictionary)
signal source_consumers_ready(services: Dictionary)

@export var auto_boot := true
@export var build_mbs := true
@export var city_data_directory := ProjectSettings.globalize_path("res://").path_join("../loop/singapore-fidelity/recovery/private/city-geometry/candidate-r2").simplify_path()
@export var terrain_data_directory := ProjectSettings.globalize_path("res://").path_join("../loop/singapore-fidelity/recovery/private/terrain-scene/mbs-neighborhood-r1").simplify_path()
@export var road_data_directory := ProjectSettings.globalize_path("res://").path_join("../loop/singapore-fidelity/source-roads/generated/candidate-r5-recovery-r1").simplify_path()
## Root must explicitly approve a corrected, natively checked physical road
## identity. A property toggle can NEVER make the known-rejectedR2 acceptable.
@export var road_physical_candidate_approved := false
var source_frame: RefCounted
var source_context: RefCounted
var source_runtime: Node3D
var domain: RefCounted
var dem: RefCounted
var city_provider: RefCounted
var roads: RefCounted
var city_scene: Node3D
var terrain_scene: Node3D
var site: Node3D
var floor_stack: Node3D
var hotel: Node3D
var player: Player
var car: Car
var helicopter: Helicopter
var hud: CanvasLayer
var session_controller: Node
var minimap_lines: Array[Dictionary] = []
var ready_for_play := false
var boot_failed := false
var last_error := ""
var _materials: RefCounted
var _regions: Array[String] = []
var _tile_rows: Dictionary = {}
var _receipts: Dictionary = {}
var _loading: CanvasLayer
var _loading_label: Label
var _start_source: Array = []
var _spawn_receipts: Dictionary = {}
var _rebase_notice_revision := -1
var _region_notice := ""
var _paused := false
var _settings_return_to_pause := false
var _booting := false
var _datum: Dictionary = {}
var _architecture_inventory: Dictionary = {}
var _architecture_inventory_sha := ""
var _pending_architecture: Dictionary = {}
var _architecture_loading := false
var _architecture_failures: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("source_singapore_world")
	_show_loading("Preparing Singapore…")
	if auto_boot: boot.call_deferred()

func _show_loading(text: String) -> void:
	if _loading == null:
		_loading = CanvasLayer.new()
		_loading.layer = 20
		add_child(_loading)
		var background := ColorRect.new()
		background.color = Color(.025,.05,.06)
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading.add_child(background)
		_loading_label = Label.new()
		_loading_label.position = Vector2(65,75)
		_loading_label.add_theme_font_size_override("font_size",25)
		_loading.add_child(_loading_label)
	_loading_label.text = text

func _fail(reason: String) -> Dictionary:
	last_error = reason
	boot_failed = true
	_booting = false
	ready_for_play = false
	Game.simulation_paused = true
	for actor in [player,car,helicopter]:
		if is_instance_valid(actor): actor.process_mode = Node.PROCESS_MODE_DISABLED
	_show_loading("Singapore could not finish loading.\nPlease return to the project to check this build.")
	push_error("SourceWorld: " + reason)
	source_world_failed.emit(reason)
	return {"ok":false,"reason":reason}

func _digest(data: Dictionary) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(JSON.stringify(data,"",true,true).to_utf8_buffer())
	return hash.finish().hex_encode()

func boot() -> Dictionary:
	if _booting or ready_for_play or boot_failed: return {"ok":false,"reason":"Source world can boot only once"}
	if ROADS_SHA == "a70fedf48a0a3ab158dfc9e617ec828dfedbfa18d60d2e5b6f4871f6901dc190": return _fail("Known-rejected R2 physical road mesh remains pinned; wait for corrected explicit artifact identity")
	if not road_physical_candidate_approved: return _fail("Corrected physical road candidate has not received Root native approval")
	_booting = true
	Game.simulation_paused = true
	Game.mode = Game.MODE_FOOT
	Game.in_mission = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Lighting.build_environment(self)
	_materials = Materials.new()
	source_frame = Frame.new()
	if not source_frame.configure(Frame.EXPECTED_FRAME,SOURCE_ORIGIN,SNAPSHOT,{"status":"source_tag","reference":Tiles.YMODE,"source_reference":"Mapzen Skadi EGM96 coarse source DEM; game world offset 0m; not current surveyed ground"}): return _fail("Source frame rejected")
	domain = Domain.new()
	if not domain.configure("res://data/geography/domain/osm-2026-10-27",DOMAIN_SHA,SNAPSHOT): return _fail("Country/coast identity rejected")
	dem = DEM.new()
	if not dem.configure("res://data/geography/terrain/mapzen-skadi-2026-10-28",DEM_SHA,SNAPSHOT,4): return _fail("DEM identity rejected")
	var base: Dictionary = dem.sample(HOTEL_ANCHOR)
	if not base.get("ok",false) or base.get("state") != "sampled_dem": return _fail("No declared DEM reference at actual hotel source anchor")
	_datum = {"base_elevation_m":float(base.height_m_egm96),"base_elevation_provenance":"COARSE EGM96 DEM sampled at actual source hotel anchor; reconstructed level datum, NOT current surveyed L1","source_anchor_xyz":HOTEL_ANCHOR.duplicate(),"dem_identity_sha256":DEM_SHA,"dem_sample":base.duplicate(true)}
	if not _prepare_architecture_inventory(): return _fail("MBS source/reconstruction inventory could not bind transition guard")
	var geometry := {"schema":"singapore_source_world_assembly_v1","snapshot_sha256":SNAPSHOT,"city_sha256":CITY_SHA,"terrain_sha256":TERRAIN_SHA,"roads_sha256":ROADS_SHA,"root_masks_sha256":MASKS_SHA,"mbs_inventory_sha256":_architecture_inventory_sha,"mbs_reconstruction_base":_datum.base_elevation_m,"world_y_policy":Y_POLICY,"registry_policy":"non_dry_exterior_tile_support_ids_actual_native_triangles","city_collision_representation":"exact_static_batches_32768_v1","road_collision_representation":"exact_arraymesh_static_batches_32768_v1"}
	var vertical := {"dem_identity_sha256":DEM_SHA,"world_y_policy":Y_POLICY,"mbs_reference":_datum}
	source_context = Context.new()
	if not source_context.configure(source_frame,_digest(geometry),_digest(vertical),PROFILE,get_world_3d()): return _fail(source_context.last_error)
	for provider: Dictionary in domain.provider_descriptors():
		if not source_context.register_provider(provider.kind,provider.provider_id,provider.source_reference): return _fail("Domain provider registry rejected")
	if not source_context.register_provider("physics","source-world-native-physics-v1","Actual same-World3D triangle/capsule observations after committed collision neighborhoods"): return _fail("Native physics provider rejected")
	source_runtime = Runtime.new()
	source_runtime.name = "SourceWorldRuntime"
	add_child(source_runtime)
	if not source_runtime.configure(source_frame,source_context,domain.observe): return _fail("Source runtime frame/context mismatch")
	if not source_runtime.configure_architecture("res://data/geography/mbs-root-holes.json",MASKS_SHA,_architecture_assessment): return _fail("Source architecture guard rejected exact Root mask identity")
	source_runtime.architecture_required.connect(_on_architecture_required)
	city_provider = Tiles.new()
	if not city_provider.configure(city_data_directory,CITY_SHA,SNAPSHOT,DEM_SHA,Y_POLICY,2): return _fail(city_provider.last_error)
	city_scene = City.new()
	city_scene.name = "ActualSourceBuildings"
	add_child(city_scene)
	if not city_scene.configure(source_frame,_materials.material_for,_retain_tile,9,16,{"geometry_identity_sha256":CITY_SHA,"snapshot_manifest_sha256":SNAPSHOT},{"collision_mode":"static_batches"}): return _fail("City scene authority rejected")
	terrain_scene = Terrain.new()
	terrain_scene.name = "ActualSourceTerrain"
	add_child(terrain_scene)
	if not terrain_scene.configure(source_frame,_materials.material_for,_retain_tile,9,16): return _fail("Terrain scene authority rejected")
	if not terrain_scene.open_prepared(terrain_data_directory,TERRAIN_SHA,SNAPSHOT,DEM_SHA,MASKS_SHA,Y_POLICY,2): return _fail(terrain_scene.last_error)
	roads = Roads.new()
	if not roads.configure(road_data_directory,ROADS_SHA,source_frame): return _fail("Source road artifact rejected")
	var road_inventory: Array = roads.metadata().physical_tiles
	for tx in range(-1,2):
		for tz in range(-2,1):
			var key := "%d_%d" % [tx,tz]
			_show_loading("Preparing Singapore…\nNeighborhood %d of 9" % (_tile_rows.size()+1))
			var row := {"key":key,"tx":tx,"tz":tz,"bodies":[],"groups":[],"road_node":null}
			var terrain_data: Dictionary = terrain_scene.prepare_tile(tx,tz)
			if not terrain_data.get("ok",false): return _fail("Required terrain tile unavailable: "+key)
			var terrain_result: Dictionary = await terrain_scene.install_tile(terrain_data)
			if not terrain_result.get("ok",false): return _fail("Terrain native commit failed: "+key)
			var terrain_bodies: Array = terrain_scene.collision_bodies(key)
			row.bodies.append_array(terrain_bodies)
			row.groups.append({"kind":"terrain","identity":TERRAIN_SHA,"bodies":terrain_bodies})
			var cell: Array = city_provider.mesh_keys_for_cell(tx,tz)
			if not cell.is_empty():
				var city_data: Dictionary = city_provider.tile(tx,tz)
				if not city_data.get("ok",false): return _fail("Required city geometry failed integrity: "+key)
				var city_result: Dictionary = await city_scene.install_tile(city_data)
				if not city_result.get("ok",false): return _fail("City native commit failed: "+key)
				var city_bodies: Array = city_scene.collision_bodies(key)
				row.bodies.append_array(city_bodies)
				row.groups.append({"kind":"building_shell","identity":CITY_SHA,"bodies":city_bodies})
			if road_inventory.has(key):
				var prepared: Dictionary = roads.prepare_physical(key)
				if not prepared.get("ok",false): return _fail("Road tile integrity failed: "+key)
				var built: Dictionary = roads.build_physical(prepared.plan,self,_materials.material_for("roads","road"),{"collision_mode":"static_batches"})
				if not built.get("ok",false): return _fail("Road native preparation rejected: "+key+" "+str(built.get("error","")))
				row.road_node = built.node
				var road_bodies: Array = []
				_collect_bodies(built.node,road_bodies)
				row.bodies.append_array(road_bodies)
				row.groups.append({"kind":"road","identity":ROADS_SHA,"bodies":road_bodies})
				for feature: Dictionary in prepared.plan.data.features:
					var points: Array = feature.source_points_xyz
					if points.size() > 1:
						var bounds: Array = [INF,INF,-INF,-INF]
						for point: Array in points:
							bounds[0] = minf(bounds[0],float(point[0])); bounds[1] = minf(bounds[1],float(point[2]))
							bounds[2] = maxf(bounds[2],float(point[0])); bounds[3] = maxf(bounds[3],float(point[2]))
						minimap_lines.append({"source_id":feature.id,"points":points.duplicate(true),"bounds_xz":bounds})
			_tile_rows[key] = row
			await get_tree().process_frame
	for tick in 3: await get_tree().physics_frame
	if not _commit_regions(): return _fail(last_error)
	if build_mbs:
		_show_loading("Preparing Marina Bay Sands…")
		var mbs: Dictionary = await _build_mbs()
		if not mbs.get("ok",false): return _fail("MBS assembly held: "+str(mbs.get("reason","")))
	_show_loading("Preparing your arrival…")
	var actors: Dictionary = await _spawn_actors()
	if not actors.get("ok",false): return _fail(actors.get("reason","No safe actual source arrival"))
	session_controller = SessionController.new()
	session_controller.name = "SourceSessionController"
	add_child(session_controller)
	if not session_controller.configure(self): return _fail("Source save/recovery service could not bind this world")
	await get_tree().physics_frame
	if not session_controller.capture_initial_anchor(): return _fail("No natively restorable source checkpoint at initial arrival")
	hud = SourceHUD.new()
	hud.name = "SingaporeHUD"
	add_child(hud)
	hud.setup_source(self,player)
	ready_for_play = true
	_booting = false
	Game.simulation_paused = false
	if is_instance_valid(_loading): _loading.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	source_consumers_ready.emit(services())
	var result := report()
	source_world_ready.emit(result)
	return {"ok":true,"receipt":result}

func _collect_bodies(node: Node, bodies: Array) -> void:
	if node is StaticBody3D and node.collision_layer & 1 != 0: bodies.append(node)
	for child: Node in node.get_children(): _collect_bodies(child,bodies)

func _source_body_id(body: StaticBody3D, index: int) -> String:
	if body.has_meta("source_road_batch"):
		var road_batch:Dictionary=body.get_meta("source_road_batch")
		return "road-batch/"+String(road_batch.tile_key)+"/"+str(road_batch.batch_index)
	if body.has_meta("source_city_batch"):
		var batch: Dictionary = body.get_meta("source_city_batch")
		return "city-batch/"+String(batch.tile_key)+"/"+str(batch.batch_index)
	return String(body.get_meta("source_fragment_id",body.get_meta("source_way",body.get_meta("source_feature_id","body-"+str(index)))))

## Envelopes identify a registry, never dry terrain or physical support. Only
## stamped current native triangles can support a queried actor. Original
## feature IDs in collision batches resolve through the native face lookup. Split rather
## than discard source IDs when the context's4096support budget is reached.
func _register_group(key: String, group: Dictionary) -> Dictionary:
	var bodies: Array = group.bodies
	var supports: Array = []
	var cell: PackedStringArray = key.split("_")
	var tx: int = int(cell[0])
	var tz: int = int(cell[1])
	for first in range(0,bodies.size(),4096):
		var partition: int = first/4096
		var feature := "source-"+String(group.kind)+"-registry|"+key+"|"+str(partition)
		var ids: Array[String] = []
		for index in range(first,mini(first+4096,bodies.size())):
			var body: StaticBody3D = bodies[index]
			var id := _source_body_id(body,index)+"@"+key+"/"+str(index)
			ids.append(id)
			supports.append({"body":body,"feature_id":feature,"floor_id":"native_exterior_geometry","support_id":id})
		var floor := {"feature_id":feature,"floor_id":"native_exterior_geometry","geometry_sha256":group.identity,"support_ids":ids,"volumes":[{"volume_id":"identity-envelope-not-land","min_xyz":[tx*1000.0-48.0,-512.0,tz*1000.0-48.0],"max_xyz":[(tx+1)*1000.0+48.0,2000.0,(tz+1)*1000.0+48.0],"dry":false}],"provenance":"Native source triangles; original identities via body metadata or native shape/face lookup. Nondry envelope is not ground, hydrology or survey proof."}
		if not source_context.register_floor(floor): return {"ok":false,"reason":source_context.last_error}
	return {"ok":true,"supports":supports}

func _commit_regions() -> bool:
	var all_bodies: Array = []
	var supports_by_tile: Dictionary = {}
	for key: String in _tile_rows:
		var row: Dictionary = _tile_rows[key]
		all_bodies.append_array(row.bodies)
		var supports: Array = []
		for group: Dictionary in row.groups:
			var registered: Dictionary = _register_group(key,group)
			if not registered.get("ok",false): last_error = registered.get("reason","Registry rejected"); return false
			supports.append_array(registered.supports)
		supports_by_tile[key] = supports
	# Neighbor features may overhang a tile edge. Each region references ALL
	# active neighborhood geometry; no collider is freed independently here.
	for key: String in _tile_rows:
		var row: Dictionary = _tile_rows[key]
		var id := "source-world/"+key
		if not source_runtime.commit_region(id,[row.tx*1000.0,-512.0,row.tz*1000.0],[(row.tx+1)*1000.0,2000.0,(row.tz+1)*1000.0],all_bodies,supports_by_tile[key]):
			last_error = "Native complete source collision region rejected: "+key
			return false
		_regions.append(id)
	return true

func _build_mbs() -> Dictionary:
	var base: float = _datum.base_elevation_m
	var provenance: String = _datum.base_elevation_provenance
	var connections: Array = Public.default_core_connection_requests(base)
	var arrival: Dictionary = Public.default_arrival_request(base)
	site = Site.new()
	site.name = "ActualSourceMBSHotel"
	add_child(site)
	var built: Dictionary = site.build(source_frame,source_context,source_runtime,{"base_elevation_m":base,"base_elevation_provenance":provenance,"core_connections":connections,"arrival_corridor":arrival})
	if not built.get("built",false): return {"ok":false,"reason":built.get("error","Public site rejected")}
	for i in 3: await get_tree().physics_frame
	var committed: Dictionary = site.commit_native_floor()
	if not committed.get("ok",false): return {"ok":false,"reason":committed.get("error","Public site native commit rejected")}
	floor_stack = Stack.new()
	floor_stack.name = "SourceMBSFloorStack"
	add_child(floor_stack)
	# All three pinned L1s protect their B1/L2neighbors: nine actual floors.
	# Reserve nine more slots for current, open-door/shaft protected and
	# destination neighborhoods during walking and source-save restoration.
	# No occupied floor is evicted to force a transition through the budget.
	if not floor_stack.configure(source_frame,source_context,source_runtime,base,provenance,{"max_active_floors":18,"max_pending_requests":3,"auto_stream":true,"public_core_connections":connections,"public_arrival_corridor":arrival}): return {"ok":false,"reason":"MBS floor stack rejected shared datum/context"}
	for tower in ["T1","T2","T3"]:
		var floor_result: Dictionary = await floor_stack.ensure_floor(tower+"-L1")
		if not floor_result.get("ready",false): return {"ok":false,"reason":str(floor_result)}
		floor_stack.pin_floor(tower+"-L1","source-world-public-entry")
	hotel = Hotel.new()
	hotel.name = "SourceMBSPhysicalTransport"
	add_child(hotel)
	var hotel_result: Dictionary = await hotel.build(source_frame,source_context,source_runtime,floor_stack,base)
	if not hotel_result.get("built",false): return {"ok":false,"reason":hotel_result.get("error","Hotel transport rejected")}
	_receipts["mbs"] = {"site":site.report(),"stack":floor_stack.report(),"hotel":hotel.report(),"datum":_datum.duplicate(true)}
	return {"ok":true}

## Copy immutable source/reconstruction descriptors once, not all native floor
## recipes each frame. These descriptors select expected lifecycle ONLY; they
## never claim native support or surveyed/private as-built measurements.
func _prepare_architecture_inventory() -> bool:
	var inventory: Dictionary = Inventory.load_inventory()
	if inventory.has("error") or not inventory.get("hotel_floors") is Array: return false
	_architecture_inventory_sha = FileAccess.get_sha256(Inventory.PATH)
	if _architecture_inventory_sha.length()!=64: return false
	var towers: Dictionary = {}
	for source: Dictionary in SiteReference.DATA.towers:
		var records: Array[Dictionary] = []
		for input: Dictionary in inventory.hotel_floors:
			if input.get("tower")!=source.tower: continue
			if not input.get("id") is String or not input.get("geometry") is Dictionary or not typeof(input.get("elevation_m")) in [TYPE_FLOAT,TYPE_INT]: return false
			var row: Dictionary = input.duplicate(true)
			if row.get("level")=="L1":
				# Same explicit L1 adaptation as Root FloorStack: preserve public
				# atrium width instead of silently creating a cross-atrium slab.
				var width: float = SiteReference.ATRIUM_ENGINEERING.approx_width_m[source.tower]
				row.geometry.atrium_void_active = true
				row.geometry.void_min_z_m = -width*.5
				row.geometry.void_max_z_m = width*.5
			records.append(row)
		records.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.elevation_m)<float(b.elevation_m))
		if records.is_empty(): return false
		towers[String(source.id)] = {"tower":source.tower,"source_id":source.id,"anchor_xz":source.centroid_world_xz.duplicate(),"records":records}
	_architecture_inventory = {"towers":towers,"inventory_sha256":_architecture_inventory_sha,"source_site_reference_sha256":FileAccess.get_sha256("res://src/world/mbs_interior/site_reference.gd"),"root_masks_sha256":MASKS_SHA,"reconstructed_not_as_built":true}
	return true

func _public_architecture_ready() -> bool:
	if not is_instance_valid(site) or not site.report().get("native_collision_committed",false): return false
	var floor: Dictionary = source_context.floor_record(Site.FEATURE,Site.FLOOR)
	return floor.get("ok",false) and source_runtime.region_status("mbs-public-site").get("live",false)

func _registered_floor_contains(feature: String,id: String,point: Array) -> bool:
	var record: Dictionary = source_context.floor_record(feature,id)
	# Consume Root's exact registered source volumes, including rotated stair
	# and door adapters. Do not substitute an absolute float AABB here.
	return record.get("ok",false) and source_context._floor_contains(record.floor,point)

func _floor_requirement(id: String,point: Array,mask_id: String) -> Dictionary:
	var lifecycle := {"ready":false,"floor_id":id,"status":"source_stack_not_installed"}
	if is_instance_valid(floor_stack): lifecycle = floor_stack.floor_state(id)
	return {"state":"required","floor_ids":[id],"ready":bool(lifecycle.get("ready",false)),"provenance":"Pinned source hotel footprint plus versioned reconstructed inventory; actual same-context FloorStack.floor_state native/neighbor lifecycle","inventory_sha256":_architecture_inventory_sha,"root_masks_sha256":MASKS_SHA,"mask_id":mask_id,"source_xyz":point.duplicate(),"native_lifecycle":lifecycle}

func _moving_cabin_assessment(point: Array,actor: CharacterBody3D) -> Dictionary:
	if not actor is Player or not is_instance_valid(hotel): return {}
	var state: Dictionary = source_runtime.inspect_player(actor)
	if not state.get("ok",false) or state.support.state!="supported" or state.support.floor_id!="CABIN" or not String(state.support.feature_id).begins_with("mbs-hotel/physical-shaft/"): return {}
	var shaft: String = String(state.support.feature_id).trim_prefix("mbs-hotel/physical-shaft/")
	var module: Node3D = hotel.get_cabin(shaft)
	if not is_instance_valid(module) or not is_instance_valid(module.cabin) or module.cabin.get_instance_id()!=state.support.collider_instance_id or not source_runtime.region_status("mbs-shaft/"+shaft).get("live",false): return {}
	var local: Dictionary = source_frame.to_local(point)
	if not local.get("ok",false): return {}
	var native_pose: Transform3D = PhysicsServer3D.body_get_state(module.cabin.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var foot: Vector3 = native_pose.affine_inverse()*local.position
	# Keep the entire production capsule footprint on the actual moving slab.
	# The enclosing shaft volume alone cannot authorize stepping out of a
	# closed cabin into a missing architectural landing.
	var radius: float = PROFILE.radius_m
	if absf(foot.x)>(Cabins.WIDTH-.12)*.5-radius or absf(foot.z)>(Cabins.DEPTH-.24)*.5-radius or foot.y<-.15 or foot.y>.45: return {}
	return {"state":"required","floor_ids":["CABIN/"+shaft],"ready":true,"provenance":"Current native stamped moving-cabin support, live shaft lease and proposed full capsule footprint inside actual slab dimensions; not merely broad enclosed-shaft volume","collider_instance_id":module.cabin.get_instance_id(),"origin_revision":source_frame.metadata().origin_revision}

func _architecture_assessment(mask_id: String,point: Array,actor: CharacterBody3D) -> Dictionary:
	var base: float = _datum.base_elevation_m
	var moving: Dictionary = _moving_cabin_assessment(point,actor)
	if not moving.is_empty(): return moving
	# The real constructed public floor/adapters take precedence over a tower
	# mask's reconstructed central void. This preserves normal ground entry.
	if _registered_floor_contains(Site.FEATURE,Site.FLOOR,point):
		return {"state":"required","floor_ids":["public-L1"],"ready":_public_architecture_ready(),"provenance":"Exact Root registered public L1/portal/core source volumes and live same-World3D region","root_masks_sha256":MASKS_SHA}
	if mask_id=="constructed-public-atrium-floor":
		if float(point[1])>base+3.2:
			return {"state":"known_physical_void","floor_ids":[],"ready":false,"provenance":"Airspace above reconstructed public L1 support band; no floor, dryland or water inferred"}
		if float(point[1])<base-.35:
			return {"state":"unknown","floor_ids":[],"ready":false,"provenance":"Public source mask below declared L1; basement/retail/terrain connection mapping is not prepared"}
		return {"state":"required","floor_ids":["public-L1"],"ready":_public_architecture_ready(),"provenance":"Root-approved exact reconstructed public floor mask; actual site region must be natively committed","root_masks_sha256":MASKS_SHA}
	var source_id: String = mask_id.trim_prefix("source-foundation/")
	if not _architecture_inventory.towers.has(source_id):
		return {"state":"unknown","floor_ids":[],"ready":false,"provenance":"Exact source retail foundation is planned architecture but no source-placed native retail program mapping is installed","source_feature_id":source_id,"root_masks_sha256":MASKS_SHA}
	var tower: Dictionary = _architecture_inventory.towers[source_id]
	var rows: Array = tower.records
	var below: int = -1
	for index in rows.size():
		if base+float(rows[index].elevation_m)<=float(point[1])+.35: below = index
	if below<0: return {"state":"unknown","floor_ids":[],"ready":false,"provenance":"Below the versioned reconstructed tower inventory; no basement extension or terrain support invented","source_feature_id":source_id}
	var row: Dictionary = rows[below]
	var plane_y: float = base+float(row.elevation_m)
	if below==rows.size()-1 and float(point[1])>plane_y+maxf(float(row.geometry.clear_height_m),float(row.geometry.storey_height_m))+.5:
		return {"state":"not_required","floor_ids":[],"ready":false,"provenance":"Above the reconstructed tower floor program; actual collision and source residency still apply"}
	# Exact registered architectural source volumes include stairs/core joins
	# crossing a nominal storey selection boundary. Test the copied adjacent
	# inventory IDs before any simpler reconstructed void classification.
	for index in range(maxi(0,below-1),mini(rows.size(),below+2)):
		var candidate: Dictionary = rows[index]
		if _registered_floor_contains(Stack.FEATURE,String(candidate.id),point): return _floor_requirement(String(candidate.id),point,mask_id)
	var dx: float = float(point[0])-float(tower.anchor_xz[0])
	var dz: float = float(point[2])-float(tower.anchor_xz[1])
	var along: float = dx*float(SiteReference.DATA.axis_south_xz[0])+dz*float(SiteReference.DATA.axis_south_xz[1])
	var across: float = dx*float(SiteReference.DATA.axis_bayward_xz[0])+dz*float(SiteReference.DATA.axis_bayward_xz[1])
	var geometry: Dictionary = row.geometry
	var end: float = float(geometry.length_m)*.5-float(geometry.core_bay_m)
	if bool(geometry.atrium_void_active) and absf(along)<end and across>float(geometry.void_min_z_m) and across<float(geometry.void_max_z_m) and float(point[1])>plane_y+.35:
		return {"state":"known_physical_void","floor_ids":[],"ready":false,"provenance":"Versioned reconstructed floor factory explicitly preserves this central atrium void; not a missing slab or inferred land","inventory_floor_id":row.id,"inventory_sha256":_architecture_inventory_sha}
	var requirement: Dictionary = _floor_requirement(String(row.id),point,mask_id)
	if requirement.ready:
		# Native floor readiness is insufficient when this exact point is not
		# inside its registered source volumes. Keep the layout mismatch visible
		# instead of claiming the whole OSM footprint a completed floor.
		requirement.state = "unknown"
		requirement.ready = false
		requirement.provenance = "Source footprint point is outside actual registered floor/stair volumes; Root needs source-layout adaptation before crossing"
	return requirement

func _on_architecture_required(requirement: Dictionary) -> void:
	var assessment: Dictionary = requirement.get("assessment",{})
	for value in assessment.get("floor_ids",[]):
		if not value is String or Inventory.floor_record(value).is_empty(): continue
		_pending_architecture[value] = true
	if not _architecture_loading and ready_for_play: _load_required_architecture.call_deferred()

func _load_required_architecture() -> void:
	if _architecture_loading or not is_instance_valid(floor_stack): return
	_architecture_loading = true
	while not _pending_architecture.is_empty() and ready_for_play:
		var id: String = _pending_architecture.keys()[0]
		_pending_architecture.erase(id)
		var prepared: Dictionary = await floor_stack.ensure_floor(id)
		if not prepared.get("ready",false):
			_architecture_failures.append({"floor_id":id,"result":prepared.duplicate(true),"origin_revision":source_frame.metadata().origin_revision})
			while _architecture_failures.size()>16: _architecture_failures.pop_front()
	_architecture_loading = false

func _ray_surface(source_xz: Array, expected_y: float, allowance: float = 6.0) -> Dictionary:
	var projected: Dictionary = source_frame.to_local([float(source_xz[0]),expected_y,float(source_xz[1])])
	if not projected.ok: return {"ok":false}
	var p: Vector3 = projected.position
	var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*allowance,p-Vector3.UP*allowance,1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < .8: return {"ok":false}
	var canonical: Dictionary = source_frame.to_source_current_live(hit.position)
	if not canonical.ok: return {"ok":false}
	var source_id: String = hit.collider.get_meta("source_way",hit.collider.get_meta("source_feature_id",""))
	var source_lookup: Dictionary = city_scene.resolve_source_hit(hit) if is_instance_valid(city_scene) else {}
	if source_lookup.get("ok",false): source_id = source_lookup.feature_id
	elif hit.collider.has_meta("source_city_batch"): return {"ok":false,"reason":"Native city batch face source identity unresolved"}
	if hit.collider.has_meta("source_road_batch"):
		source_lookup=roads.resolve_source_hit(hit)
		if not source_lookup.get("ok",false):return {"ok":false,"reason":"Native road batch face source identity unresolved"}
		source_id=source_lookup.source_way
	return {"ok":true,"position":hit.position,"source_xyz":canonical.source_xyz,"normal":hit.normal,"body":hit.collider,"source_id":source_id,"native_source_lookup":source_lookup}


func _clear_box(foot: Vector3, size: Vector3, center_y: float) -> bool:
	var shape := BoxShape3D.new()
	shape.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,foot+Vector3(0,center_y+.08,0))
	query.collision_mask = 1|2|4|8
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _find_spawn(anchor: Array, size: Vector3, center_y: float, search_radius: float) -> Dictionary:
	# Bounded explicit source-space search; a failed query does not create land.
	for radius in [0.0,4.0,8.0,16.0,24.0,32.0,48.0,64.0]:
		if radius > search_radius: continue
		for direction in range(1 if radius == 0.0 else 12):
			var angle: float = TAU*float(direction)/12.0
			var point: Array = [float(anchor[0])+cos(angle)*radius,float(anchor[2])+sin(angle)*radius]
			var hit: Dictionary = _ray_surface(point,float(anchor[1]),8.0)
			if not hit.get("ok",false) or not _clear_box(hit.position,size,center_y): continue
			# A real support under each skid/corner is required, not center-only
			# roof/terrain bounding-box placement across holes or unsupported water.
			var stable := true
			for sx in [-1.0,1.0]:
				for sz in [-1.0,1.0]:
					var edge: Dictionary = _ray_surface([point[0]+sx*size.x*.5,point[1]+sz*size.z*.5],hit.position.y+float(SOURCE_ORIGIN[1]),2.0)
					if not edge.get("ok",false) or absf(edge.position.y-hit.position.y)>.45: stable = false
			if stable: return hit
	return {"ok":false}

func _spawn_actors() -> Dictionary:
	var arrival: Dictionary = _find_spawn(START,Vector3(.72,1.75,.72),.9,24.0)
	if not arrival.get("ok",false): return {"ok":false,"reason":"No ray-confirmed clear source player arrival near original South Bridge Road node"}
	_start_source = arrival.source_xyz.duplicate()
	player = Player.new()
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.position = arrival.position+Vector3.UP*.05
	player.yaw = 0.0
	player.uses_source_world = true
	player.source_world_runtime = source_runtime
	add_child(player)
	if not source_runtime.bind_player(player): return {"ok":false,"reason":"Production player source profile rejected"}
	var car_spawn: Dictionary = _find_spawn(CAR_ARRIVAL,Vector3(4.6,1.45,4.6),.82,24.0)
	if not car_spawn.get("ok",false): return {"ok":false,"reason":"No clear fully supported actual-source car arrival"}
	car = Car.new()
	car.name = "SingaporePlayerCar"
	car.has_ai = false
	car.kind = "sedan"
	car.process_mode = Node.PROCESS_MODE_DISABLED
	car.position = car_spawn.position+Vector3.UP*.08
	car.rotation.y = atan2(-(float(CAR_FORWARD_NEXT[0])-float(CAR_ARRIVAL[0])),-(float(CAR_FORWARD_NEXT[2])-float(CAR_ARRIVAL[2])))
	car.uses_source_world = true
	car.source_world_runtime = source_runtime
	add_child(car)
	if not source_runtime.bind_car(car): return {"ok":false,"reason":"Production car source hull rejected"}
	var helicopter_anchor: Array = [float(_start_source[0])+20.0,float(_start_source[1]),float(_start_source[2])+20.0]
	var helicopter_spawn: Dictionary = _find_spawn(helicopter_anchor,Vector3(3.4,2.7,7.0),1.65,64.0)
	if not helicopter_spawn.get("ok",false): return {"ok":false,"reason":"No clear source helicopter skids/rotor arrival in bounded search"}
	helicopter = Helicopter.new()
	helicopter.name = "SingaporePlayerHelicopter"
	helicopter.process_mode = Node.PROCESS_MODE_DISABLED
	helicopter.position = helicopter_spawn.position+Vector3.UP*.08
	helicopter.uses_source_world = true
	helicopter.source_world_runtime = source_runtime
	add_child(helicopter)
	if not source_runtime.bind_aircraft(helicopter): return {"ok":false,"reason":"Production aircraft source binding rejected"}
	_spawn_receipts = {"player":_surface_receipt(arrival),"car":_surface_receipt(car_spawn),"helicopter":_surface_receipt(helicopter_spawn)}
	for actor in [player,car,helicopter]: actor.process_mode = Node.PROCESS_MODE_INHERIT
	Game.mark_safe_position(player.global_position,player.yaw)
	return {"ok":true}

func _surface_receipt(hit: Dictionary) -> Dictionary:
	return {"source_xyz":hit.source_xyz.duplicate(),"support_source_id":hit.source_id,"normal_xyz":[hit.normal.x,hit.normal.y,hit.normal.z],"native_collision_instance_id":hit.body.get_instance_id(),"native_source_lookup":hit.get("native_source_lookup",{}).duplicate(true),"surveyed_or_hydrology_verified":false}

func _retain_tile(_key: String,_receipt: Dictionary) -> bool:
	# Initial bounded assembly is pinned. Root will replace this with the atomic
	# source actor/mission/camera/pin-aware transaction before national travel.
	return false

func services() -> Dictionary:
	return {"frame":source_frame,"context":source_context,"runtime":source_runtime,"domain":domain,"roads":roads,"city_provider":city_provider,"city_scene":city_scene,"terrain_scene":terrain_scene,"player":player,"car":car,"helicopter":helicopter,"mbs_site":site,"mbs_floor_stack":floor_stack,"mbs_hotel":hotel,"session_controller":session_controller,"source_consumers_require_explicit_migration":true}

func canonical_actor_position() -> Dictionary:
	if not ready_for_play or not is_instance_valid(player): return {"ok":false}
	return source_frame.to_source_current_live(player.controlled_actor().global_position)

func report() -> Dictionary:
	return {"ok":ready_for_play,"boot_failed":boot_failed,"last_error":last_error,"schema":"singapore_source_world_entry_v1","snapshot_manifest_sha256":SNAPSHOT,"city_identity_sha256":CITY_SHA,"terrain_identity_sha256":TERRAIN_SHA,"roads_identity_sha256":ROADS_SHA,"road_physical_candidate_root_approved":road_physical_candidate_approved,"frame":source_frame.metadata() if source_frame != null else {},"context":source_context.metadata() if source_context != null else {},"architecture_guard":source_runtime.architecture_guard_metadata() if source_runtime!=null else {},"architecture_inventory_sha256":_architecture_inventory_sha,"architecture_load_failures":_architecture_failures.duplicate(true),"active_regions":_regions.duplicate(),"tile_count":_tile_rows.size(),"spawn_receipts":_spawn_receipts.duplicate(true),"mbs":_receipts.get("mbs",{}).duplicate(true),"datum":_datum.duplicate(true),"legacy_mission_traffic_save_consumers_migrated":false,"national_residency_and_rebase_implemented":false,"whole_requested_game_or_visual_acceptance":false}

func _process(_delta: float) -> void:
	if not ready_for_play or _paused: return
	var position: Dictionary = canonical_actor_position()
	if not position.get("ok",false): return
	var local: Vector3 = player.controlled_actor().global_position
	if maxf(absf(local.x),absf(local.z)) > 1536.0 and _rebase_notice_revision != int(source_frame.metadata().origin_revision):
		_rebase_notice_revision = int(source_frame.metadata().origin_revision)
		source_rebase_requested.emit(position.source_xyz.duplicate(),_rebase_notice_revision)
		Events.toast("The next neighborhood is not ready yet. Stay within the loaded streets.","normal")
	var key := "%d_%d" % [int(floor(float(position.source_xyz[0])/1000.0)),int(floor(float(position.source_xyz[2])/1000.0))]
	if key != _region_notice:
		_region_notice = key
		source_region_requested.emit(key,position.source_xyz.duplicate())

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_play or not event is InputEventKey or not event.pressed or event.echo: return
	if hud.settings_visible() and event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5]:
		_apply_setting_key(event.keycode)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE: _toggle_pause(); get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F3: _toggle_settings(); get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F5:
		session_controller.save_game()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F6:
		session_controller.load_game()
		get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	if hud.settings_visible(): _toggle_settings(); return
	_paused = not _paused
	Game.simulation_paused = _paused
	hud.set_paused(_paused)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED

func _toggle_settings() -> void:
	var opening: bool = not hud.settings_visible()
	if opening: _settings_return_to_pause = _paused
	hud.toggle_settings()
	_paused = true if opening else _settings_return_to_pause
	Game.simulation_paused = _paused
	hud.set_paused(not opening and _paused)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED

func _apply_setting_key(key: int) -> void:
	match key:
		KEY_1: Game.settings["mouse_sensitivity"] = clampf(float(Game.settings.get("mouse_sensitivity",1.0))-.1,.2,3.0)
		KEY_2: Game.settings["mouse_sensitivity"] = clampf(float(Game.settings.get("mouse_sensitivity",1.0))+.1,.2,3.0)
		KEY_3: Game.settings["invert_y"] = not bool(Game.settings.get("invert_y",false))
		KEY_4: Game.settings["reduced_shake"] = not bool(Game.settings.get("reduced_shake",false))
		KEY_5: Game.settings["hud_visible"] = not bool(Game.settings.get("hud_visible",true))
	hud.set_gameplay_visible(bool(Game.settings.get("hud_visible",true)))
	hud.refresh_settings()

func _quit_game() -> void:
	# No implicit legacy v1 save on quit. Root save service owns persisted poses.
	Sfx.shutdown_audio()
	get_tree().quit()
