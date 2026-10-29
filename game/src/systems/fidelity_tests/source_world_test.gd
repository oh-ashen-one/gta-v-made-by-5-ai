extends Node3D
## Root-run neighborhood assembly proof using real source triangle geometry
## and production input/physics. NOT a whole bridge/MBS/national travel test.
const World = preload("res://src/world/geography/source_world.gd")
var world: Node3D
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var output := ""
var finished := false
const WALL_BOUND_S := 600.0
const WALK_SIM_BOUND_S := 15.0
const ARRIVAL_RADIUS_M := .65
var _started_us := 0
var _simulation_s := 0.0
var _phase := "setup"
var _phase_started_us := 0
var _last_progress_us := 0
var _last_progress_tick := 0
var _progress: Array[Dictionary] = []
var _active_walk: Dictionary = {}
var _qa_base := ""
var _restore_events: Array[Dictionary] = []

func check(label: String, value: bool, detail: Variant = "") -> bool:
	checks += 1
	print("[source-world] %s %s %s" % ["PASS" if value else "FAIL",label,str(detail)])
	if not value: failures.append(label)
	return value

func _safe(path: String) -> bool:
	if not path.begins_with("/private/tmp/singapore-fidelity/") or path != path.simplify_path(): return false
	var current := "/private/tmp"
	for segment in path.trim_prefix("/private/tmp/").split("/",false):
		var folder := DirAccess.open(current)
		if folder != null and folder.is_link(segment): return false
		current = current.path_join(segment)
	return true

func _ready() -> void:
	_started_us = Time.get_ticks_usec()
	_phase_started_us = _started_us
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at < 0 or at+1 >= args.size(): get_tree().quit(2); return
	var base: String = args[at+1]
	if base.begins_with("/tmp/"): base = "/private/tmp/"+base.trim_prefix("/tmp/")
	_qa_base = base.trim_suffix("/")
	output = base.path_join("source-world")
	if not _safe(output) or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK: get_tree().quit(2); return
	get_tree().create_timer(WALL_BOUND_S,true,false,true).timeout.connect(func():
		if not finished:
			if not _active_walk.is_empty(): _active_walk["termination_reason"] = "whole_test_wall_bound"
			_sample_progress(true)
			check("bounded source world QA",false,"600-second diagnostic wall bound; not FPS acceptance")
			_finish())
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _wait_quiet(actor: CharacterBody3D,maximum_frames: int,maximum_speed: float) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var start_sim: float = _simulation_s
	var quiet := 0
	var count := 0
	for index in maximum_frames:
		if finished: break
		count += 1
		quiet = quiet+1 if actor.is_on_floor() and actor.velocity.length()<=maximum_speed else 0
		if quiet>=3: break
		await get_tree().physics_frame
	return {"ok":quiet>=3,"quiet_physics_samples":quiet,"frames":count,"maximum_frames":maximum_frames,"maximum_speed_mps":maximum_speed,"native_velocity":_v(actor.velocity),"native_on_floor":actor.is_on_floor(),"simulation_s":_simulation_s-start_sim,"wall_s":float(Time.get_ticks_usec()-started)/1000000.0}

func _physics_process(delta: float) -> void:
	_simulation_s += delta

func _process(_delta: float) -> void:
	if not finished: _sample_progress()

func _set_phase(value: String) -> void:
	_phase = value
	_phase_started_us = Time.get_ticks_usec()
	_sample_progress(true)

func _v(value: Vector3) -> Array:
	return [float(value.x),float(value.y),float(value.z)]

func _collider(value: Object) -> Dictionary:
	if not is_instance_valid(value): return {"valid":false}
	var result := {"valid":true,"instance_id":value.get_instance_id(),"class":value.get_class()}
	if value is Node: result["name"] = String(value.name)
	for key in ["source_feature_id","source_fragment_id","source_way","source_geometry_identity"]:
		if value.has_meta(key): result[key] = value.get_meta(key)
	return result

func _native_player_diagnostics() -> Dictionary:
	if not is_instance_valid(world) or not world.ready_for_play or not is_instance_valid(world.player): return {}
	var actor: Player = world.player
	var state: Dictionary = world.source_runtime.inspect_player(actor)
	var contacts: Array[Dictionary] = []
	for index in mini(actor.get_slide_collision_count(),6):
		var hit: KinematicCollision3D = actor.get_slide_collision(index)
		contacts.append({"collider":_collider(hit.get_collider()),"normal_local_world":_v(hit.get_normal()),"position_local_world":_v(hit.get_position()),"travel":_v(hit.get_travel()),"remainder":_v(hit.get_remainder())})
	return {"position":_v(actor.global_position),"velocity":_v(actor.velocity),"yaw":actor.yaw,"on_floor":actor.is_on_floor(),"alive":actor.alive,"busy":actor.busy,"visible":actor.visible,"current_vehicle":String(actor.current_vehicle.name) if is_instance_valid(actor.current_vehicle) else "none","paused":Game.simulation_paused,"source_controls_held":Game.source_controls_held(),"forward_input":Input.get_action_strength("move_forward"),"native_state":state,"last_move_slide_contacts":contacts,"architecture_guard":world.source_runtime.architecture_guard_metadata()}

func _sample_progress(force: bool = false) -> void:
	var now: int = Time.get_ticks_usec()
	if not force and now-_last_progress_us<10000000: return
	var sample := {"phase":_phase,"wall_s":float(now-_started_us)/1000000.0,"phase_wall_s":float(now-_phase_started_us)/1000000.0,"simulation_s":_simulation_s,"physics_tick":Engine.get_physics_frames(),"walk":_active_walk.duplicate(true)}
	if _last_progress_us>0 and now-_last_progress_us>500000: sample["observed_physics_hz_not_performance_acceptance"] = float(Engine.get_physics_frames()-_last_progress_tick)/(float(now-_last_progress_us)/1000000.0)
	_last_progress_us = now
	_last_progress_tick = Engine.get_physics_frames()
	if is_instance_valid(world):
		sample["completed_tiles"] = world.get("_tile_rows").size()
		sample["ready_for_play"] = world.ready_for_play
		if is_instance_valid(world.source_runtime): sample["source_runtime"] = world.source_runtime.residency_profile()
		if world.ready_for_play:
			var diagnostic_started: int = Time.get_ticks_usec()
			sample["player"] = _native_player_diagnostics()
			sample["diagnostic_cost_us"] = Time.get_ticks_usec()-diagnostic_started
	_progress.append(sample)
	print("[source-world] PROGRESS ",JSON.stringify(sample,"",true,true))

func _capsule_probe(point: Vector3) -> Dictionary:
	var actor: Player = world.player
	var shape_node: CollisionShape3D
	for child: Node in actor.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D and not child.disabled: shape_node = child
	if shape_node==null: return {"clear":false,"reason":"actual_player_capsule_missing"}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = Transform3D(actor.global_basis,point)*shape_node.transform
	query.collision_mask = Player.COLLIDE_MASK
	query.exclude = [actor.get_rid()]
	var hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(query,16)
	var details: Array[Dictionary] = []
	for hit: Dictionary in hits: details.append(_collider(hit.collider))
	return {"clear":hits.is_empty(),"hits":details,"point":_v(point),"actual_capsule_height":(shape_node.shape as CapsuleShape3D).height,"actual_capsule_radius":(shape_node.shape as CapsuleShape3D).radius}

func _approach_ray(point: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(world.player.global_position+Vector3.UP*1.25,point+Vector3.UP*1.25,Player.COLLIDE_MASK)
	ray.exclude = [world.player.get_rid()]
	# Deliberately include the destination vehicle: an opposite-side target
	# whose approach crosses its hull is unsuitable for a straight W-only walk.
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	return {"clear":hit.is_empty(),"hit":_collider(hit.get("collider")),"position":_v(hit.get("position",Vector3.ZERO)),"normal":_v(hit.get("normal",Vector3.ZERO))}

func _native_motion_probe(point: Vector3) -> Dictionary:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = world.player.global_transform
	parameters.motion = point-world.player.global_position
	parameters.margin = world.player.safe_margin
	parameters.max_collisions = 16
	parameters.recovery_as_collision = false
	var result := PhysicsTestMotionResult3D.new()
	var blocked: bool = PhysicsServer3D.body_test_motion(world.player.get_rid(),parameters,result)
	var contacts: Array[Dictionary] = []
	var hard := false
	for index in result.get_collision_count():
		var normal: Vector3 = result.get_collision_normal(index)
		if normal.y<float(World.PROFILE.min_support_normal_y): hard = true
		contacts.append({"collider":_collider(result.get_collider(index)),"normal":_v(normal),"point":_v(result.get_collision_point(index)),"depth_m":result.get_collision_depth(index)})
	return {"blocked":blocked,"hard_obstruction":hard,"contacts":contacts,"motion":_v(parameters.motion),"actual_player_body_RID":true,"actor_or_velocity_assigned":false}

func _hull_relative(vehicle: CharacterBody3D,point: Vector3) -> Dictionary:
	for child: Node in vehicle.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D and not child.disabled:
			var native_pose: Transform3D = PhysicsServer3D.body_get_state(vehicle.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			var local: Vector3 = (native_pose*child.transform).affine_inverse()*point
			var half: Vector3 = (child.shape as BoxShape3D).size*.5
			return {"point_in_actual_box_native_body_frame":_v(local),"box_half_extents":_v(half),"point_inside_box":absf(local.x)<=half.x and absf(local.y)<=half.y and absf(local.z)<=half.z,"native_body_position":_v(native_pose.origin),"node_position":_v(vehicle.global_position),"yaw":vehicle.rotation.y}
	return {}

func _interaction_approach(vehicle: CharacterBody3D,label: String,maximum_distance: float) -> Dictionary:
	var legacy_offset := Vector3(2.4,0,1.0) if vehicle is Car else Vector3(3.2,0,1.0)
	var legacy_point: Vector3 = vehicle.global_position+legacy_offset
	var legacy := {"raw_target":_v(legacy_point),"hull":_hull_relative(vehicle,legacy_point),"capsule":_capsule_probe(legacy_point),"approach_ray":_approach_ray(legacy_point),"native_motion":_native_motion_probe(legacy_point)}
	metrics[label+"_legacy_target"] = legacy
	var right: Vector3 = vehicle.global_basis.x
	var forward: Vector3 = -vehicle.global_basis.z
	var offsets: Array[Vector3] = []
	if vehicle is Car: offsets.assign([right*1.9,-right*1.9,forward*2.9,-forward*2.9,right*2.8+forward*1.2,-right*2.8+forward*1.2])
	else: offsets.assign([right*2.8,-right*2.8,forward*4.0,-forward*4.0])
	offsets.sort_custom(func(a: Vector3,b: Vector3) -> bool: return (vehicle.global_position+a).distance_squared_to(world.player.global_position)<(vehicle.global_position+b).distance_squared_to(world.player.global_position))
	# Keep a physically valid original approach when it really is clear. Its
	# Y is resolved by the production exit probe instead of guessed from hullY.
	offsets.push_front(legacy_offset)
	var attempts: Array[Dictionary] = []
	for offset: Vector3 in offsets:
		var one_offset: Array[Vector3] = [offset]
		var point: Vector3 = Car.find_safe_exit(vehicle,one_offset)
		var attempt := {"offset":_v(offset),"production_exit_candidate":_v(point)}
		if point==Vector3.ZERO: attempt["reason"] = "production_native_exit_probe_refused"; attempts.append(attempt); continue
		var capsule: Dictionary = _capsule_probe(point)
		var ray: Dictionary = _approach_ray(point)
		var motion: Dictionary = _native_motion_probe(point)
		attempt.merge({"capsule":capsule,"approach_ray":ray,"native_motion":motion,"vehicle_distance_m":point.distance_to(vehicle.global_position)})
		attempts.append(attempt)
		if capsule.clear and ray.clear and not motion.hard_obstruction and point.distance_to(vehicle.global_position)<maximum_distance:
			var source: Dictionary = world.source_frame.to_source_current_live(point)
			var begun: Dictionary = world.source_context.begin_query(source.source_xyz)
			var native: Dictionary = world.source_context.evaluate(begun.query,world.source_runtime._native_player_observations(begun.query,world.player)) if begun.get("ok",false) else {}
			var result := {"ok":true,"point":point,"point_xyz":_v(point),"source_xyz":source.source_xyz,"native_support":native.get("support",{}),"native_residency":native.get("residency",{}),"water":native.get("water",{}),"method":"production_native_exit_probe_plus_actual_capsule_eye_route_and_body_motion","original_offset_retained":offset==legacy_offset,"attempts":attempts}
			metrics[label+"_approach"] = result.duplicate(true)
			print("[source-world] INTERACTION_APPROACH ",JSON.stringify({"vehicle":label,"legacy":legacy,"selected":result},"",true,true))
			return result
	var failed := {"ok":false,"reason":"no_native_clear_straight_interaction_approach","attempts":attempts}
	metrics[label+"_approach"] = failed
	return failed

func _press_interact() -> void:
	Input.action_press("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("interact")
	await get_tree().process_frame

func _native_key(code: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code; down.physical_keycode = code; down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = code; up.physical_keycode = code; up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

func _source_world_save_load() -> bool:
	_set_phase("native_initial_F5_save_F6_load")
	var service: Node = world.session_controller.service
	var meta: Dictionary = service.metadata()
	if not check("real-world F5/F6 slot is private QA source sibling",_safe(meta.slot_path) and meta.slot_path.begins_with(_qa_base+"/") and meta.legacy_path.begins_with(_qa_base+"/") and Game.source_session_owns(service)): return false
	var legacy_existed: bool = FileAccess.file_exists(meta.legacy_path)
	var legacy_hash: String = FileAccess.get_sha256(meta.legacy_path) if legacy_existed else ""
	if not check("initial source-world QA sibling is fresh",not FileAccess.file_exists(meta.slot_path)): return false
	service.restored.connect(func(reason: String,token: String):
		_restore_events.append({"reason":reason,"token":token,"source_pose_at_production_apply":world.source_frame.to_source_current_live(world.player.global_position),"heading_at_production_apply":world.player.yaw,"service_result":service.last_result.duplicate(true),"native_state":world.source_runtime.inspect_player(world.player)}))
	await _native_key(KEY_F5)
	if finished: return false
	if not check("native F5 writes real source-world service save",FileAccess.file_exists(meta.slot_path) and service.has_save()): return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(meta.slot_path)
	var saved: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not check("F5 file binds exact current source terrain pose",saved is Dictionary and saved.get("context_pose") is Dictionary and saved.context_pose==service.metadata().last_saved_pose): return false
	var count: int = _restore_events.size()
	var started: int = Time.get_ticks_usec()
	await _native_key(KEY_F6)
	while not finished and _restore_events.size()==count and Time.get_ticks_usec()-started<60000000:
		await get_tree().process_frame
	if finished: return false
	if not check("native F6 applies through real World/Game/controller",_restore_events.size()==count+1,service.last_result): return false
	var event: Dictionary = _restore_events[-1]
	check("production immediate-load applies exact canonical source pose",event.reason=="load" and event.source_pose_at_production_apply.get("ok",false) and event.source_pose_at_production_apply.source_xyz==saved.context_pose.source_pose.source_xyz and event.heading_at_production_apply==saved.context_pose.source_pose.heading_rad,event)
	check("real terrain reload retains unknown water and actual native support",event.native_state.support.state=="supported" and event.native_state.residency.state=="resident" and event.native_state.water.state=="unknown" and event.native_state.land.state=="unknown" and not event.service_result.hydrology_reclassified,event.native_state)
	check("immediate-load preserves both source and legacy slot bytes",FileAccess.get_file_as_bytes(meta.slot_path)==bytes and FileAccess.file_exists(meta.legacy_path)==legacy_existed and (not legacy_existed or FileAccess.get_sha256(meta.legacy_path)==legacy_hash))
	metrics["real_world_F5_F6"] = {"save_source_pose":saved.context_pose,"restore_event":event,"elapsed_wall_s":float(Time.get_ticks_usec()-started)/1000000.0,"production_restore_outside_continuous_walks":true,"arbitrary_stats_geometry_or_actor_mutations":false,"legacy_existed_before":legacy_existed,"legacy_unchanged":FileAccess.file_exists(meta.legacy_path)==legacy_existed and (not legacy_existed or FileAccess.get_sha256(meta.legacy_path)==legacy_hash)}
	return failures.is_empty()

func _walk_to(target: Vector3,label: String) -> Dictionary:
	_active_walk.clear()
	_set_phase(label)
	var start: Vector3 = world.player.global_position
	var previous := start
	var distance := 0.0
	var frame_count := 0
	var reached := false
	var started: int = Time.get_ticks_usec()
	var start_sim: float = _simulation_s
	var best: float = Vector2(target.x-start.x,target.z-start.z).length()
	var progress_distance: float = best
	var progress_sim: float = start_sim
	var progress_wall: int = started
	var reason := "simulation_budget"
	while not finished:
		frame_count += 1
		var delta: Vector3 = target-world.player.global_position
		var remaining: float = Vector2(delta.x,delta.z).length()
		best = minf(best,remaining)
		var now: int = Time.get_ticks_usec()
		_active_walk = {"label":label,"target":_v(target),"distance_m":distance,"remaining_m":remaining,"best_remaining_m":best,"frames":frame_count,"simulation_elapsed_s":_simulation_s-start_sim,"wall_elapsed_s":float(now-started)/1000000.0,"since_progress_sim_s":_simulation_s-progress_sim,"since_progress_wall_s":float(now-progress_wall)/1000000.0,"termination_reason":"running"}
		if remaining<ARRIVAL_RADIUS_M: reached = true; reason = "arrival"; break
		if _simulation_s-start_sim>=WALK_SIM_BOUND_S: break
		if progress_distance-best>=.10:
			progress_distance = best; progress_sim = _simulation_s; progress_wall = now
		if _simulation_s-progress_sim>=2.5: reason = "no_approach_progress_over_2.5_simulation_seconds"; break
		if now-progress_wall>=60000000: reason = "no_progress_wall_guard_low_simulation_throughput"; break
		world.player.yaw = atan2(-delta.x,-delta.z)
		Input.action_press("move_forward")
		await get_tree().physics_frame
		distance += world.player.global_position.distance_to(previous)
		previous = world.player.global_position
		if world.player.global_position.y < start.y-5.0: reason = "unexpected_fall"; break
	Input.action_release("move_forward")
	if finished:
		_active_walk["reached"] = false
		return _active_walk.duplicate(true)
	var commanded_simulation_s: float = _simulation_s-start_sim
	var settled: Dictionary = await _wait_quiet(world.player,30,.12)
	var final: Vector3 = world.player.global_position
	var final_distance: float = Vector2(target.x-final.x,target.z-final.z).length()
	if reached and final_distance>=ARRIVAL_RADIUS_M: reason = "released_input_native_settle_left_arrival_radius"
	if not settled.ok: reason = "released_input_native_settle_not_quiet"
	var result := {"reached":reached and final_distance<ARRIVAL_RADIUS_M and settled.ok,"arrival_radius_m":ARRIVAL_RADIUS_M,"distance_m":distance,"remaining_after_release_m":final_distance,"frames":frame_count,"commanded_simulation_s":commanded_simulation_s,"simulation_s_with_release_settle":_simulation_s-start_sim,"native_release_settle":settled,"wall_s":float(Time.get_ticks_usec()-started)/1000000.0,"termination_reason":reason,"start_xyz":_v(start),"end_xyz":_v(final),"target_xyz":_v(target),"teleports":0,"actor_position_or_velocity_assigned":false,"heading_steering_command_only":true,"native":_native_player_diagnostics()}
	_active_walk = result.duplicate(true)
	_sample_progress(true)
	return result

func _run() -> void:
	world = World.new()
	world.auto_boot = false
	# Explicit Root operator acknowledgement, after the separate corrected-road
	# native gate. This cannot override SourceWorld's hard rejectedR2hash.
	world.road_physical_candidate_approved = OS.get_cmdline_user_args().has("--source-world-test-approved-roads")
	# Separate initial integration fixture: full MBS has its own second entry
	# run once Root's actual public-core joins are ready, never inferred here.
	world.build_mbs = OS.get_cmdline_user_args().has("--source-world-test-with-mbs")
	add_child(world)
	metrics["profile_source_runtime_requested"] = OS.get_cmdline_user_args().has("--profile-source-runtime")
	_set_phase("boot")
	var boot_started: int = Time.get_ticks_usec()
	var boot: Dictionary = await world.boot()
	if finished: return
	metrics["boot_timing"] = {"wall_s":float(Time.get_ticks_usec()-boot_started)/1000000.0,"simulation_s":_simulation_s,"physics_tick":Engine.get_physics_frames(),"profile_source_runtime":world.source_runtime.residency_profile() if is_instance_valid(world.source_runtime) else {}}
	if not check("real source world boots",boot.get("ok",false),boot.get("reason","")): _finish(); return
	check("all9actual terrain/city/road neighborhoods committed",world.report().tile_count==9 and world.report().active_regions.size()==9)
	check("production source actors share one runtime",world.player is Player and world.car is Car and world.helicopter is Helicopter and world.player.source_world_runtime==world.source_runtime and world.car.source_world_runtime==world.source_runtime and world.helicopter.source_world_runtime==world.source_runtime)
	check("legacy fiction is not instantiated",get_tree().get_nodes_in_group("world").is_empty() and not world.report().legacy_mission_traffic_save_consumers_migrated)
	check("actual source-origin metres retained",world.source_frame.metadata().source_origin_xyz == World.SOURCE_ORIGIN)
	check("native source support IDs recorded for all arrivals",world.report().spawn_receipts.player.support_source_id!="" and world.report().spawn_receipts.car.support_source_id!="" and world.report().spawn_receipts.helicopter.support_source_id!="")
	metrics["boot"] = world.report()
	_set_phase("settle_initial_arrival")
	var initial_settle: Dictionary = await _wait_quiet(world.player,90,.12)
	metrics["initial_native_settle"] = initial_settle
	if not check("initial source player settles with three quiet native samples",initial_settle.ok,initial_settle): _finish(); return
	var state: Dictionary = world.source_runtime.inspect_player(world.player)
	check("actual resting player resident/supported",state.get("ok",false) and state.residency.state=="resident" and state.support.state=="supported",state)
	check("outdoor hydrology remains unknown",state.get("ok",false) and state.land.state=="unknown" and state.water.state=="unknown",state)
	var save_load_passed: bool = await _source_world_save_load()
	if not save_load_passed: _finish(); return
	var foot_start: Vector3 = world.player.global_position
	_set_phase("probe_car_interaction_approach")
	var car_approach: Dictionary = _interaction_approach(world.car,"car",4.0)
	if not check("car has a native clear physical interaction approach",car_approach.get("ok",false),car_approach): _finish(); return
	var walk: Dictionary = await _walk_to(car_approach.point,"walk_to_car")
	if finished: return
	metrics["continuous_walk_to_car"] = walk
	if not check("continuous native walking reaches real car",walk.reached and walk.distance_m>1.0 and walk.teleports==0,walk): _finish(); return
	check("player did not fall through source surface",world.player.global_position.y>foot_start.y-4.0)
	if not check("car boarding is at physical interaction distance",world.player.global_position.distance_to(world.car.global_position)<4.0): _finish(); return
	if not check("native player interaction selection reaches intended car",world.player._interaction_target()==world.car): _finish(); return
	_set_phase("native_car_interact_input")
	await _press_interact()
	await _frames(4)
	if not check("actual production car boarding",world.player.current_vehicle==world.car and world.car.driver_is_player and Game.mode==Game.MODE_CAR): _finish(); return
	var car_start: Vector3 = world.car.global_position
	var drive_distance := 0.0
	var last := car_start
	_set_phase("native_drive")
	Input.action_press("move_forward",.35)
	for i in 180:
		await get_tree().physics_frame
		drive_distance += world.car.global_position.distance_to(last)
		last = world.car.global_position
	Input.action_release("move_forward")
	_set_phase("native_brake")
	Input.action_press("jump")
	var brake: Dictionary = await _wait_quiet(world.car,150,.25)
	Input.action_release("jump")
	metrics["native_drive"] = {"distance_m":drive_distance,"start_xyz":[car_start.x,car_start.y,car_start.z],"end_xyz":[last.x,last.y,last.z],"native_braking_settle":brake,"teleports":0,"full_bridge_route":false}
	check("real source car moves under production throttle",drive_distance>3.0,metrics.native_drive)
	if not check("source car brakes to three quiet grounded samples",brake.ok,brake): _finish(); return
	_set_phase("native_car_exit_input")
	await _press_interact()
	var exit_settle: Dictionary = await _wait_quiet(world.player,30,.12)
	metrics["car_exit_native_settle"] = exit_settle
	if not check("native car exit settles production capsule",exit_settle.ok,exit_settle): _finish(); return
	if not check("native source car exit reaches supported foot pose",world.player.current_vehicle==null and Game.mode==Game.MODE_FOOT): _finish(); return
	var after_exit: Dictionary = world.source_runtime.inspect_player(world.player)
	check("exited player has fresh native source support",after_exit.get("ok",false) and after_exit.support.state=="supported",after_exit)
	_set_phase("probe_aircraft_interaction_approach")
	var heli_approach: Dictionary = _interaction_approach(world.helicopter,"helicopter",Player.INTERACT_RANGE)
	if not check("aircraft has a native clear physical interaction approach",heli_approach.get("ok",false),heli_approach): _finish(); return
	var heli_walk: Dictionary = await _walk_to(heli_approach.point,"walk_to_aircraft")
	if finished: return
	metrics["continuous_walk_to_aircraft"] = heli_walk
	if not check("continuous source walk reaches real aircraft",heli_walk.reached and heli_walk.teleports==0,heli_walk): _finish(); return
	if not check("native player interaction selection reaches intended aircraft",world.player._interaction_target()==world.helicopter): _finish(); return
	_set_phase("native_aircraft_interact_input")
	await _press_interact()
	await _frames(4)
	if not check("actual production aircraft boarding",world.player.current_vehicle==world.helicopter and world.helicopter.pilot_is_player): _finish(); return
	var flight_start: Vector3 = world.helicopter.global_position
	_set_phase("native_aircraft_climb")
	Input.action_press("jump")
	await _frames(300)
	Input.action_release("jump")
	_set_phase("native_aircraft_forward_flight")
	Input.action_press("move_forward",.35)
	await _frames(180)
	Input.action_release("move_forward")
	var flight_end: Vector3 = world.helicopter.global_position
	metrics["native_flight"] = {"climb_m":flight_end.y-flight_start.y,"horizontal_m":Vector2(flight_end.x-flight_start.x,flight_end.z-flight_start.z).length(),"teleports":0,"bridge_or_hotel_landing":false}
	check("production helicopter climbs over source city",metrics.native_flight.climb_m>3.0,metrics.native_flight)
	check("production helicopter flies continuously in shared source frame",metrics.native_flight.horizontal_m>3.0 and world.canonical_actor_position().get("ok",false),metrics.native_flight)
	check("source entry does not advertise whole goal completion",not world.report().whole_requested_game_or_visual_acceptance and not world.report().national_residency_and_rebase_implemented)
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	for action in ["move_forward","move_back","move_left","move_right","jump","sprint","interact"]:
		if InputMap.has_action(action): Input.action_release(action)
	Game.simulation_paused = true
	metrics["progress"] = _progress
	metrics["last_active_walk"] = _active_walk.duplicate(true)
	metrics["terminal_phase"] = _phase
	metrics["total_wall_s"] = float(Time.get_ticks_usec()-_started_us)/1000000.0
	metrics["total_simulation_s"] = _simulation_s
	if is_instance_valid(world) and is_instance_valid(world.source_runtime): metrics["terminal_runtime_profile"] = world.source_runtime.residency_profile()
	var report := {"schema":"singapore_source_world_native_entry_test_v2","checks":checks,"failed":failures.size(),"failures":failures,"metrics":metrics,"wall_bound_s":WALL_BOUND_S,"walk_simulation_bound_s":WALK_SIM_BOUND_S,"rendered_visual_acceptance":false,"performance_acceptance":false,"full_bridge_MBS_continuous_route":false,"all_country_playable":false}
	var path := output.path_join("report.json")
	if not _safe(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): get_tree().quit(2); return
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: get_tree().quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("[source-world] FINISHED checks=%d failed=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
