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
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at < 0 or at+1 >= args.size(): get_tree().quit(2); return
	var base: String = args[at+1]
	if base.begins_with("/tmp/"): base = "/private/tmp/"+base.trim_prefix("/tmp/")
	output = base.path_join("source-world")
	if not _safe(output) or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK: get_tree().quit(2); return
	get_tree().create_timer(240.0,true,false,true).timeout.connect(func():
		if not finished:
			check("bounded source world QA",false,"240-second wall bound")
			_finish())
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _walk_to(target: Vector3, max_frames: int = 900) -> Dictionary:
	var start: Vector3 = world.player.global_position
	var previous := start
	var distance := 0.0
	var frame_count := 0
	var reached := false
	for i in max_frames:
		frame_count += 1
		var delta: Vector3 = target-world.player.global_position
		if Vector2(delta.x,delta.z).length() < .65: reached = true; break
		world.player.yaw = atan2(-delta.x,-delta.z)
		Input.action_press("move_forward")
		await get_tree().physics_frame
		distance += world.player.global_position.distance_to(previous)
		previous = world.player.global_position
		if world.player.global_position.y < start.y-5.0: break
	Input.action_release("move_forward")
	await _frames(10)
	return {"reached":reached,"distance_m":distance,"frames":frame_count,"start_xyz":[start.x,start.y,start.z],"end_xyz":[world.player.global_position.x,world.player.global_position.y,world.player.global_position.z],"teleports":0}

func _run() -> void:
	world = World.new()
	world.auto_boot = false
	# Separate initial integration fixture: full MBS has its own second entry
	# run once Root's actual public-core joins are ready, never inferred here.
	world.build_mbs = OS.get_cmdline_user_args().has("--source-world-test-with-mbs")
	add_child(world)
	var boot: Dictionary = await world.boot()
	if not check("real source world boots",boot.get("ok",false),boot.get("reason","")): _finish(); return
	check("all9actual terrain/city/road neighborhoods committed",world.report().tile_count==9 and world.report().active_regions.size()==9)
	check("production source actors share one runtime",world.player is Player and world.car is Car and world.helicopter is Helicopter and world.player.source_world_runtime==world.source_runtime and world.car.source_world_runtime==world.source_runtime and world.helicopter.source_world_runtime==world.source_runtime)
	check("legacy fiction is not instantiated",get_tree().get_nodes_in_group("world").is_empty() and not world.report().legacy_mission_traffic_save_consumers_migrated)
	check("actual source-origin metres retained",world.source_frame.metadata().source_origin_xyz == World.SOURCE_ORIGIN)
	check("native source support IDs recorded for all arrivals",world.report().spawn_receipts.player.support_source_id!="" and world.report().spawn_receipts.car.support_source_id!="" and world.report().spawn_receipts.helicopter.support_source_id!="")
	metrics["boot"] = world.report()
	await _frames(90)
	var state: Dictionary = world.source_runtime.inspect_player(world.player)
	check("actual resting player resident/supported",state.get("ok",false) and state.residency.state=="resident" and state.support.state=="supported",state)
	check("outdoor hydrology remains unknown",state.get("ok",false) and state.land.state=="unknown" and state.water.state=="unknown",state)
	var foot_start: Vector3 = world.player.global_position
	var to_car: Vector3 = world.car.global_position+Vector3(2.4,0,1.0)
	var walk: Dictionary = await _walk_to(to_car)
	metrics["continuous_walk_to_car"] = walk
	if not check("continuous native walking reaches real car",walk.reached and walk.distance_m>1.0 and walk.teleports==0,walk): _finish(); return
	check("player did not fall through source surface",world.player.global_position.y>foot_start.y-4.0)
	if not check("car boarding is at physical interaction distance",world.player.global_position.distance_to(world.car.global_position)<4.0): _finish(); return
	world.car.interact(world.player)
	await _frames(4)
	if not check("actual production car boarding",world.player.current_vehicle==world.car and world.car.driver_is_player and Game.mode==Game.MODE_CAR): _finish(); return
	var car_start: Vector3 = world.car.global_position
	var drive_distance := 0.0
	var last := car_start
	Input.action_press("move_forward",.35)
	for i in 180:
		await get_tree().physics_frame
		drive_distance += world.car.global_position.distance_to(last)
		last = world.car.global_position
	Input.action_release("move_forward")
	Input.action_press("jump")
	await _frames(150)
	Input.action_release("jump")
	metrics["native_drive"] = {"distance_m":drive_distance,"start_xyz":[car_start.x,car_start.y,car_start.z],"end_xyz":[last.x,last.y,last.z],"teleports":0,"full_bridge_route":false}
	check("real source car moves under production throttle",drive_distance>3.0,metrics.native_drive)
	world.car.exit_vehicle(world.player)
	await _frames(20)
	if not check("native source car exit reaches supported foot pose",world.player.current_vehicle==null and Game.mode==Game.MODE_FOOT): _finish(); return
	var after_exit: Dictionary = world.source_runtime.inspect_player(world.player)
	check("exited player has fresh native source support",after_exit.get("ok",false) and after_exit.support.state=="supported",after_exit)
	var to_heli: Vector3 = world.helicopter.global_position+Vector3(3.2,0,1.0)
	var heli_walk: Dictionary = await _walk_to(to_heli,1800)
	metrics["continuous_walk_to_aircraft"] = heli_walk
	if not check("continuous source walk reaches real aircraft",heli_walk.reached and heli_walk.teleports==0,heli_walk): _finish(); return
	world.helicopter.interact(world.player)
	await _frames(4)
	if not check("actual production aircraft boarding",world.player.current_vehicle==world.helicopter and world.helicopter.pilot_is_player): _finish(); return
	var flight_start: Vector3 = world.helicopter.global_position
	Input.action_press("jump")
	await _frames(300)
	Input.action_release("jump")
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
	for action in ["move_forward","move_back","move_left","move_right","jump","sprint"]:
		if InputMap.has_action(action): Input.action_release(action)
	Game.simulation_paused = true
	var report := {"schema":"singapore_source_world_native_entry_test_v1","checks":checks,"failed":failures.size(),"failures":failures,"metrics":metrics,"rendered_visual_acceptance":false,"full_bridge_MBS_continuous_route":false,"all_country_playable":false}
	var path := output.path_join("report.json")
	if not _safe(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): get_tree().quit(2); return
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: get_tree().quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("[source-world] FINISHED checks=%d failed=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
