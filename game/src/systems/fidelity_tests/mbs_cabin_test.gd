extends Node3D
## Two actual GuestFloor landings, native E, production Player/platform physics.
## One declared initial spawn only; no actor relocation/reparent during tests.
const Cabins = preload("res://src/world/mbs_interior/cabins.gd")
const GuestFloor = preload("res://src/world/mbs_interior/guest_floor.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const LOWER := "T3-L5"
const UPPER := "T3-L6"
const REPORT_NAME := "mbs-cabin-report.json"
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var qa_session := ""
var output := ""
var finished := false
var lift: Node3D
var player: Player
var floors: Dictionary = {}
var resident: Dictionary = {}
var requests: Array[String] = []
var motion_samples: Array[Dictionary] = []
var tracking := false
var riding := false
var previous := Vector3.ZERO
var max_step := 0.0
var ride_samples := 0
var ride_on_floor := 0
var ride_peak_platform_speed := 0.0
var ride_peak_offset := 0.0
var path_enabled := true
var initial_actor_spawns := 0

func check(label: String, condition: bool, detail: String = "") -> bool:
	checks += 1
	print("[mbs-cabin] %s %s %s" % ["PASS" if condition else "FAIL", label, detail])
	if not condition: failures.append(label)
	return condition

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at < 0 or at + 1 >= args.size(): get_tree().quit(2); return
	qa_session = args[at + 1]
	if qa_session.begins_with("/tmp/"): qa_session = "/private/tmp/" + qa_session.trim_prefix("/tmp/")
	if not _report_path_error(qa_session, true).is_empty() or DirAccess.make_dir_absolute(qa_session) != OK or not _report_path_error(qa_session, false).is_empty(): get_tree().quit(2); return
	output = qa_session.path_join(REPORT_NAME)
	get_tree().create_timer(150.0, true, true).timeout.connect(func():
		if not finished:
			check("bounded cabin QA completion", false, "150s watchdog")
			finish())
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func until(predicate: Callable, seconds: float, label: String) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await get_tree().physics_frame
	return check(label, false, JSON.stringify(lift.report() if is_instance_valid(lift) else {}))

func _physics_process(_delta: float) -> void:
	if not tracking or not is_instance_valid(player): return
	var p := player.global_position
	max_step = maxf(max_step, p.distance_to(previous))
	previous = p
	if riding:
		ride_samples += 1
		if player.is_on_floor(): ride_on_floor += 1
		ride_peak_platform_speed = maxf(ride_peak_platform_speed, absf(player.get_platform_velocity().y))
		ride_peak_offset = maxf(ride_peak_offset, absf(p.y - float(lift.report().commanded_y_m)))
		motion_samples.append({"tick": Engine.get_physics_frames(), "player_xyz": [p.x, p.y, p.z], "cabin_y": lift.report().commanded_y_m, "platform_y_velocity": player.get_platform_velocity().y, "player_resolved_velocity_y": player.velocity.y, "on_floor": player.is_on_floor()})
		if motion_samples.size() > 500: motion_samples.pop_front()

func _ready_for_floor(id: String) -> Dictionary:
	return {"ready": bool(resident.get(id, false)) and floors.has(id) and is_instance_valid(floors[id]), "floor_id": id,
		"collision_generation": "qa-committed-" + id if resident.get(id, false) else "unloaded", "travel_ready": path_enabled and is_instance_valid(lift) and lift.shaft_collision_ready()}

func load_floor(id: String) -> bool:
	var node := GuestFloor.new()
	var record: Dictionary = Inventory.floor_record(id)
	node.position.y = float(record.elevation_m)
	add_child(node)
	var result: Dictionary = node.build(record)
	if not check("actual GuestFloor collision builds " + id, result.get("built", false), JSON.stringify(result)): return false
	floors[id] = node
	await frames(5)
	resident[id] = true
	if is_instance_valid(lift): return check("native floor transition/interlock binds " + id, lift.bind_floor(id, node, id + "-east-guest_lift"))
	return true

func _door(id: String) -> Node3D:
	return floors[id].doors.get(id + "-east-guest_lift")

func landing(id: String, extra: float = 0.0) -> Vector3:
	for portal: Dictionary in floors[id].portals:
		if portal.id == id + "-east-guest_lift": return floors[id].to_global(portal.landing + Vector3(0, 0, extra))
	return Vector3.ZERO

func native_e(target: Node3D) -> bool:
	Input.action_release("interact")
	await frames(10)
	if not check("native E selects exact " + String(target.name), player._interaction_target() == target and player._interaction_visible(target), str(player._interaction_target())): return false
	Input.action_press("interact")
	await frames(5)
	Input.action_release("interact")
	await frames(5)
	return true

func walk(target: Vector3, label: String) -> bool:
	var end := Time.get_ticks_msec() + 10000
	while player.global_position.distance_to(target) > .24 and Time.get_ticks_msec() < end:
		var delta := target - player.global_position
		player.yaw = atan2(-delta.x, -delta.z)
		Input.action_press("move_forward")
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await frames(6)
	return check("native continuous walk " + label, player.global_position.distance_to(target) < .40 and player.alive, str({"actual": player.global_position, "target": target}))

func _box(center: Vector3, size: Vector3, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.position = center
	return body

func run() -> void:
	var generated: Dictionary = Cabins.inventory_descriptor("T3", "east", "guest_lift", LOWER)
	if not check("inventory fixed-axis shaft descriptor exists", generated.get("valid", false), JSON.stringify(generated)): finish(); return
	var descriptor: Dictionary = generated.descriptor
	var full_stops: Array = descriptor.stops
	check("inventory includes actual relative basement and upper terminal heights", full_stops.any(func(s: Dictionary): return s.floor_id == "T3-B5" and float(s.elevation_m) == -22.5) and full_stops.any(func(s: Dictionary): return s.floor_id == "T3-L57" and float(s.elevation_m) == 194.75))
	descriptor.stops = full_stops.filter(func(s: Dictionary): return s.floor_id in [LOWER, UPPER])
	check("QA uses actual inventory floor-height difference without scaling", descriptor.stops.size() == 2 and absf(float(descriptor.stops[1].elevation_m) - float(descriptor.stops[0].elevation_m) - 3.45) < .000001)
	if not await load_floor(LOWER): finish(); return
	lift = Cabins.new()
	add_child(lift)
	var bad: Dictionary = descriptor.duplicate(true)
	bad.schema = "fake_warp_lift"
	check("invalid descriptor rejects before any cabin children", not lift.build(bad, _ready_for_floor).get("built", true) and lift.get_child_count() == 0)
	var built: Dictionary = lift.build(descriptor, _ready_for_floor)
	if not check("physical cabin and closed shaft build", built.get("built", false), JSON.stringify(built)): finish(); return
	lift.floor_requested.connect(func(_shaft: String, id: String): requests.append(id))
	if not check("lower native GuestFloor interlock binds", lift.bind_floor(LOWER, floors[LOWER], LOWER + "-east-guest_lift")): finish(); return
	check("unbound target is closed and not a fabricated resident floor", not floors.has(UPPER) and lift.report().landing_fractions[UPPER] == 0.0)
	player = Player.new()
	player.set_meta("_qa_motion_probe", true)
	add_child(player)
	# ONLY declared initial spawn. No other actor position/transform/respawn or
	# actor reparent operation is used anywhere in this fixture or component.
	player.respawn_at(landing(LOWER) + Vector3.UP * .12, 0.0)
	initial_actor_spawns += 1
	await frames(20)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tracking = true
	previous = player.global_position
	if not await native_e(_door(LOWER)): finish(); return
	if not await until(func(): return lift.report().state == "OPEN" and lift.report().gate_fraction > .999, 10.0, "lower cabin arrival doors open"): finish(); return
	check("native landing door opens only present aligned resident cabin", _door(LOWER).get("opened") and lift.report().current_floor_id == LOWER and absf(float(lift.report().commanded_y_m) - float(Inventory.floor_record(LOWER).elevation_m)) < .01)
	var center := Vector3(float(descriptor.center_xz[0]), float(Inventory.floor_record(LOWER).elevation_m), float(descriptor.center_xz[1]))
	if not await walk(center, "into actual cabin"): finish(); return
	var threshold := Vector3(center.x, center.y + 1.0, center.z + 1.4)
	var blocker := _box(threshold, Vector3(.5, 1.9, .45), "QaDoorwayObstruction")
	await frames(4)
	if not await native_e(lift.panel): finish(); return
	if not await native_e(lift.panel): finish(); return
	await frames(180)
	check("obstructed threshold prevents departure and preserves open safe landing", absf(float(lift.report().commanded_y_m) - center.y) < .001 and lift.report().state == "OPEN" and _door(LOWER).get("opened"), JSON.stringify(lift.report()))
	blocker.queue_free()
	await frames(4)
	if not await until(func(): return lift.report().state == "WAIT_READY" and lift.report().target_floor_id == UPPER, 10.0, "wait for truly absent upper floor"): finish(); return
	var waiting_y: float = lift.report().commanded_y_m
	await frames(90)
	check("cold destination waits closed without passenger/cabin warp", requests.has(UPPER) and lift.report().state == "WAIT_READY" and absf(float(lift.report().commanded_y_m) - waiting_y) < .001 and absf(player.global_position.y - waiting_y) < .12 and lift.report().gate_fraction < .001 and not bool(_door(LOWER).get("opened")))
	riding = true
	if not await load_floor(UPPER): finish(); return
	if not await until(func(): return lift.report().state == "OPEN" and lift.report().current_floor_id == UPPER and lift.report().gate_fraction > .999, 20.0, "native upward cabin ride"): finish(); return
	await frames(10)
	riding = false
	check("native moving platform carries production Player upward", absf(player.global_position.y - float(Inventory.floor_record(UPPER).elevation_m)) < .12 and ride_peak_platform_speed > .5 and ride_samples > 30, JSON.stringify({"samples": ride_samples, "platform_peak": ride_peak_platform_speed, "offset_peak": ride_peak_offset}))
	if not await walk(landing(UPPER), "out onto upper GuestFloor"): finish(); return
	check("upper exit has real native floor support", player.is_on_floor() and absf(player.global_position.y - float(Inventory.floor_record(UPPER).elevation_m)) < .12)
	if not await walk(Vector3(center.x, float(Inventory.floor_record(UPPER).elevation_m), center.z), "back into upper cabin"): finish(); return
	if not await native_e(lift.panel) or not await native_e(lift.panel): finish(); return
	riding = true
	if not await until(func(): return lift.report().state == "OPEN" and lift.report().current_floor_id == LOWER and lift.report().gate_fraction > .999, 20.0, "native downward cabin ride"): finish(); return
	await frames(10)
	riding = false
	check("native platform returns Player without pose assignment", absf(player.global_position.y - center.y) < .12 and player.is_on_floor() and ride_peak_offset < .16 and float(ride_on_floor) / maxf(1.0, ride_samples) > .95, JSON.stringify({"offset_peak": ride_peak_offset, "supported_fraction": float(ride_on_floor) / maxf(1.0, ride_samples)}))
	if not await walk(landing(LOWER, 1.2), "out and clear of doorway"): finish(); return
	var ceiling := _box(Vector3(center.x, center.y + 2.95, center.z), Vector3(1.7, .20, 2.25), "QaCeilingSweepObstruction")
	await frames(4)
	lift.request_floor(UPPER)
	if not await until(func(): return lift.report().state == "EMERGENCY", 12.0, "native cabin ceiling sweep stops motion"): finish(); return
	check("physical ceiling stops incrementally without passing through or opening shaft", float(lift.report().commanded_y_m) - center.y < .25 and lift.report().gate_fraction < .001 and not bool(_door(LOWER).get("opened")), JSON.stringify(lift.report()))
	ceiling.queue_free()
	await frames(4)
	check("explicit safety recheck can resume after actual obstruction removed", lift.resume_after_safety_check())
	if not await until(func(): return lift.report().state == "MOVING", 10.0, "resumed physical motion"): finish(); return
	path_enabled = false
	await frames(4)
	var lease_stop_y: float = lift.report().commanded_y_m
	await frames(30)
	check("withdrawn travel lease holds closed cabin without unverified travel", lift.report().state == "EMERGENCY" and absf(float(lift.report().commanded_y_m) - lease_stop_y) < .001 and lift.report().gate_fraction < .001, JSON.stringify(lift.report()))
	path_enabled = true
	check("renewed shaft/floor lease resumes only explicit safety check", lift.resume_after_safety_check())
	if not await until(func(): return lift.report().state == "MOVING", 10.0, "motion after renewed lease"): finish(); return
	if not await native_e(_door(LOWER)): finish(); return
	check("native second landing call queues rather than teleporting cabin", lift.report().queue.has(LOWER), JSON.stringify(lift.report()))
	if not await until(func(): return lift.report().state == "OPEN" and lift.report().current_floor_id == LOWER and lift.report().queue.is_empty(), 30.0, "queued physical up-and-return call"): finish(); return
	check("unoccupied queued trips leave Player on his actual floor", player.is_on_floor() and absf(player.global_position.y - center.y) < .12)
	check("incremental production Player path contains no teleport-sized step", max_step < .25, str(max_step))
	metrics["ride"] = {"samples": ride_samples, "on_floor_samples": ride_on_floor, "platform_peak_y_velocity_mps": ride_peak_platform_speed, "maximum_cabin_player_offset_m": ride_peak_offset, "maximum_player_step_m": max_step, "last_motion_samples": motion_samples}
	check("component report keeps actor/source-world scope explicit", lift.report().actor_pose_assignments == 0 and lift.report().actor_reparents == 0 and not lift.report().source_world_or_whole_MBS_completed)
	finish()

func finish() -> void:
	if finished: return
	finished = true
	for action in ["interact", "move_forward", "sprint"]: Input.action_release(action)
	var report := {"checks": checks, "failures": failures, "metrics": metrics, "initial_actor_spawns": initial_actor_spawns,
		"scope": "Isolated two-stop physical cabin and native GuestFloor/production Player fixture. No source city/site streaming, whole-MBS assembly, rebase/save integration, rendered/performance or private as-built acceptance."}
	var written := _write_guarded_report(qa_session, output, JSON.stringify(report, "\t", true, true))
	if not written.ok: push_error(written.error); get_tree().quit(2); return
	print("[mbs-cabin] RESULT ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func _owned(path: String) -> bool:
	if path != path.simplify_path() or not path.begins_with("/private/tmp/singapore-fidelity/"): return false
	var parent := "/private/tmp"
	var parts := path.trim_prefix("/private/tmp/").split("/", false)
	for i in parts.size():
		var part: String = parts[i]
		var folder := DirAccess.open(parent)
		if folder == null or folder.is_link(part): return false
		var next := parent.path_join(part)
		if not folder.dir_exists(part):
			# Only a missing final session component is allowed; its verified
			# parent must already exist. Regular files/dangling links refuse.
			return i == parts.size() - 1 and not _entry_present(next)
		parent = next
	return true

## Directory enumeration notices existing entries without opening/following
## the report leaf. FileAccess.file_exists alone misses dangling symlinks.
func _entry_present(path: String) -> bool:
	var folder := DirAccess.open(path.get_base_dir())
	if folder == null: return true # Failure to prove absence is a refusal.
	var leaf := path.get_file()
	if folder.is_link(leaf): return true
	folder.include_hidden = true
	if folder.list_dir_begin() != OK: return true
	for i in 4096:
		var entry := folder.get_next()
		if entry.is_empty():
			folder.list_dir_end()
			return false
		if entry == leaf:
			folder.list_dir_end()
			return true
	folder.list_dir_end()
	return true # Oversized/unreadable evidence directory fails closed.

func _report_path_error(session: String, require_fresh_session: bool) -> String:
	if not _owned(session): return "QA session has an unsafe path, ancestor or entry"
	if require_fresh_session:
		if _entry_present(session): return "QA session must be fresh; existing entries are refused"
		return ""
	if not DirAccess.dir_exists_absolute(session): return "QA session directory disappeared"
	if _entry_present(session.path_join(REPORT_NAME)): return "Report leaf already exists or is a link"
	return ""

func _write_guarded_report(session: String, destination: String, content: String) -> Dictionary:
	if destination != session.path_join(REPORT_NAME): return {"ok": false, "error": "Output no longer matches its checked report path"}
	var path_error := _report_path_error(session, false)
	if not path_error.is_empty(): return {"ok": false, "error": path_error}
	# Immediate recheck above is an ownership guard, not an O_EXCL primitive.
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "Cannot create mbs-cabin report"}
	file.store_string(content)
	file.flush()
	var complete := file.get_error() == OK and file.get_length() == content.to_utf8_buffer().size()
	file.close()
	return {"ok": true} if complete else {"ok": false, "error": "Incomplete mbs-cabin report write"}


