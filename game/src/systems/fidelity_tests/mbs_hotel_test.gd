extends "res://src/systems/fidelity_tests/mbs_cabin_test.gd"
## Real-source, real-streamer, real-transport integration. Exactly one initial
## player spawn; no subsequent actor pose/velocity/reparent mutation by QA.
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const Stack = preload("res://src/world/mbs_interior/floor_stack.gd")
const Hotel = preload("res://src/world/mbs_interior/hotel.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
class RegistrationRetryHotel extends Hotel:
	var _seen_registration := 0
	var _inject_one_failure := true
	func _register_native_shaft(key: String) -> bool:
		if _inject_one_failure and _seen_registration == 1:
			_inject_one_failure = false
			return false
		_seen_registration += 1
		return super._register_native_shaft(key)
var frame: RefCounted
var context: RefCounted
var runtime: Node3D
var stack: Node3D
var hotel: Node3D
var _source_support_samples := 0
var _source_support_expected := 0
var _global_offset_peak := 0.0

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args(): get_tree().quit(2); return
	# This test emits stdout only, so cannot write a report into an owner slot.
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func():
		if not finished:
			check("bounded source hotel integration", false)
			finish())
	run.call_deferred()

func check(label: String, value: bool, detail: String = "") -> bool:
	checks += 1
	print("[mbs-hotel] %s %s %s" % ["PASS" if value else "FAIL", label, detail])
	if not value: failures.append(label)
	return value

func _sha(value: String) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	hash.update(value.to_utf8_buffer()); return hash.finish().hex_encode()

func _physics_process(_delta: float) -> void:
	if not tracking or not is_instance_valid(player): return
	var point := player.global_position
	max_step = maxf(max_step, point.distance_to(previous)); previous = point
	if riding:
		ride_samples += 1
		if player.is_on_floor(): ride_on_floor += 1
		ride_peak_platform_speed = maxf(ride_peak_platform_speed, absf(player.get_platform_velocity().y))
		_global_offset_peak = maxf(_global_offset_peak, absf(player.global_position.y - lift.cabin.global_position.y))
		var state: Dictionary = runtime.inspect_player(player)
		if state.get("ok", false):
			_source_support_samples += 1
			if state.support.state == "supported" and state.support.floor_id == "CABIN" and state.water.state == "dry_indoor": _source_support_expected += 1

func run() -> void:
	Game.simulation_paused = false; Game.health = Game.MAX_HEALTH; Game.death_count = 0
	var raw := FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json")
	var manifest: Dictionary = JSON.parse_string(raw)
	var tower: Dictionary = Reference.DATA.towers[0]
	var origin: Array = [tower.centroid_world_xz[0], Inventory.floor_record(LOWER).elevation_m, tower.centroid_world_xz[1]]
	frame = Frame.new()
	if not check("actual T3 source frame and explicit reconstructed datum", frame.configure(manifest.georeference, origin, _sha(raw), {"status": "staging", "reference": "MBS inventory L1=0, source transport test only", "source_reference": "Actual horizontal anchors; reconstructed relative floor elevations"})): finish(); return
	context = Context.new()
	var profile := {"profile_id": "production-player-upright", "radius_m": .36, "height_m": 1.75, "center_offset_xyz": [0.0, .9, 0.0], "min_support_normal_y": cos(deg_to_rad(52.0)), "max_support_drop_m": .35, "max_support_rise_m": .1, "max_support_lateral_m": .4}
	var geometry := _sha(FileAccess.get_file_as_string("res://src/world/mbs_interior/hotel.gd") + FileAccess.get_file_as_string("res://src/world/mbs_interior/cabins.gd") + FileAccess.get_file_as_string("res://src/world/mbs_interior/floor_stack.gd"))
	if not check("shared native world/source context", context.configure(frame, geometry, _sha("Explicit reconstructed relative hotel stop elevations"), profile, get_world_3d())): finish(); return
	var domain := Domain.new()
	if not check("actual national source domain", domain.configure("res://data/geography/domain/osm-2026-10-27", "82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834", _sha(raw))): finish(); return
	for provider: Dictionary in domain.provider_descriptors(): context.register_provider(provider.kind, provider.provider_id, provider.source_reference)
	context.register_provider("physics", "source-native-neighborhood/v1", "Source floor-stack and hotel shaft native commits")
	runtime = Runtime.new(); add_child(runtime)
	if not check("one runtime retains actual domain", runtime.configure(frame, context, domain.observe)): finish(); return
	stack = Stack.new(); add_child(stack)
	if not check("actual source floor streamer", stack.configure(frame, context, runtime, 0.0, "Explicit relative MBS inventory test; no surveyed datum", {"max_active_floors": 6, "auto_stream": false})): finish(); return
	hotel = RegistrationRetryHotel.new(); add_child(hotel)
	var other := SubViewport.new(); other.own_world_3d = true; add_child(other)
	var wrong := Hotel.new(); other.add_child(wrong)
	var count_before: int = context.metadata().registered_floor_count
	var refused: Dictionary = await wrong.build(frame, context, runtime, stack, 0.0)
	check("foreign World3D construction rejects before children or context mutation", not refused.get("built", true) and wrong.get_child_count() == 0 and context.metadata().registered_floor_count == count_before)
	other.queue_free(); await frames(3)
	var specs := [{"tower": "T3", "wing": "east", "kind": "guest_lift", "initial_floor_id": LOWER}, {"tower": "T3", "wing": "east", "kind": "service_lift", "initial_floor_id": LOWER}]
	var first: Dictionary = await hotel.build(frame, context, runtime, stack, 0.0, specs)
	check("failed shaft registration reaps owned geometry and leaves stack guard unchanged", not first.get("built", true) and first.get("owned_geometry_reaped", false) and hotel.get_child_count() == 0 and not stack.get("_unload_guard_set"))
	var retained_definitions: int = context.metadata().registered_floor_count
	check("failed build retains immutable architecture definition for exact retry", retained_definitions > 0)
	var built: Dictionary = await hotel.build(frame, context, runtime, stack, 0.0, specs)
	if not check("actual source shaft plus moving support registration", built.get("built", false), str(built)): finish(); return
	var duplicate := Hotel.new(); add_child(duplicate)
	var count_after: int = context.metadata().registered_floor_count
	var duplicate_result: Dictionary = await duplicate.build(frame, context, runtime, stack, 0.0, specs)
	check("duplicate hotel authority rejects before geometry, guard or context mutation", not duplicate_result.get("built", true) and duplicate.get_child_count() == 0 and context.metadata().registered_floor_count == count_after and stack.get("_unload_guard") == hotel._before_floor_unload)
	duplicate.queue_free(); await frames(3)
	lift = hotel.get_cabin("T3-east-guest_lift")
	var loaded: Dictionary = await stack.ensure_floor(LOWER)
	if not check("source lower floor/neighbours committed and automatically bound", loaded.ready and lift.report().bound_floor_ids.has(LOWER), str(loaded)): finish(); return
	check("destination neighbour genuinely cold before panel request", not stack.floor_ready(UPPER) and stack.get_floor("T3-L7") == null)
	floors[LOWER] = stack.get_floor(LOWER)
	player = Player.new(); player.process_mode = Node.PROCESS_MODE_DISABLED; add_child(player)
	player.respawn_at(landing(LOWER) + Vector3.UP * .12, floors[LOWER].global_rotation.y)
	initial_actor_spawns += 1
	if not check("real player binds source transport context", runtime.bind_player(player)): finish(); return
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await frames(30); tracking = true; previous = player.global_position
	if not await native_e(_door(LOWER)): finish(); return
	if not await until(func(): return lift.report().state == "OPEN" and lift.report().gate_fraction > .999, 15.0, "source lower landing opens"): finish(); return
	var descriptor: Dictionary = lift.get("_descriptor")
	var cabin_center: Vector3 = lift.to_global(Vector3(descriptor.center_xz[0], Inventory.floor_record(LOWER).elevation_m, descriptor.center_xz[1]))
	if not await walk(cabin_center, "into source-positioned cabin"): finish(); return
	if not await native_e(lift.panel): finish(); return
	if not await native_e(lift.panel): finish(); return
	riding = true
	if not await until(func(): return lift.report().state == "OPEN" and lift.report().current_floor_id == UPPER and lift.report().gate_fraction > .999, 30.0, "source floor request loads neighbours and actual platform ascends"): finish(); return
	riding = false
	check("actual source upper floor loaded through manager callback", stack.floor_ready(UPPER) and stack.get_floor("T3-L7") != null)
	check("native platform carries player at real world transform", ride_samples > 20 and float(ride_on_floor) / ride_samples > .90 and _global_offset_peak < .16 and ride_peak_platform_speed > .2, str({"samples": ride_samples, "supported": ride_on_floor, "offset_peak": _global_offset_peak, "platform_velocity": ride_peak_platform_speed}))
	check("moving source cabin retains correct dry/native support identity", _source_support_samples > 20 and float(_source_support_expected) / _source_support_samples > .90, str({"samples": _source_support_samples, "source_cabin_support": _source_support_expected}))
	floors[UPPER] = stack.get_floor(UPPER)
	if not await walk(landing(UPPER), "out onto actual source upper floor"): finish(); return
	var state: Dictionary = runtime.inspect_player(player)
	check("exit support changes from moving cabin to exact source floor", state.get("ok", false) and state.support.get("floor_id", "") == UPPER and state.water.state == "dry_indoor", str(state.get("support", {})))
	var refusal: Dictionary = await stack.unload_floor(UPPER)
	check("occupied transport destination cannot unload", not refusal.ok and refusal.status == "protected")
	check("single initial spawn and continuous source traversal", initial_actor_spawns == 1 and max_step < .5 and Game.death_count == 0)
	metrics["source_origin_xyz"] = origin
	metrics["source_support_samples"] = _source_support_samples
	metrics["source_support_expected"] = _source_support_expected
	metrics["global_platform_offset_peak_m"] = _global_offset_peak
	metrics["hotel"] = hotel.report()
	var shaft_id := "T3-east-guest_lift"
	runtime.retire_region("mbs-shaft/" + shaft_id)
	check("retired source shaft lease refuses travel while native bodies remain", is_instance_valid(lift.cabin) and lift.shaft_collision_ready() and not hotel._ready_for_cabin(shaft_id, UPPER).travel_ready)
	hotel.queue_free(); await frames(3)
	var old_pins: Dictionary = stack.get("_pins")
	check("hotel teardown releases only its floor pins", old_pins.values().all(func(owners: Dictionary): return not owners.has(shaft_id)))
	finish()

func finish() -> void:
	if finished: return
	finished = true; tracking = false
	for action in ["move_forward", "move_back", "sprint", "walk", "jump", "interact"]: Input.action_release(action)
	print("[mbs-hotel] RESULT ", JSON.stringify({"checks": checks, "failures": failures, "initial_actor_spawns": initial_actor_spawns, "max_step_m": max_step, "metrics": metrics,
		"scope": "Coupled real-source hotel floor streamer, actual cabin, source physics and production Player; not complete MBS/public-entry/entire city, save/rebase, rendered or owner acceptance."}))
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures.is_empty() else 1)
