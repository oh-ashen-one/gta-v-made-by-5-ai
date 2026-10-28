extends Node3D
## Coupled source-domain/native-public-site entry. No arbitrary whole-module
## fixture translation: the active origin is the actual source hotel anchor.
## Emits stdout evidence only; the owned supervisor retains it and hashes.
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const Site = preload("res://src/world/mbs_interior/site.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
var checks := 0
var failures: Array[String] = []
var finished := false
var player: Player
var site: Node3D
var runtime: Node3D
var frame: RefCounted
var context: RefCounted
var metrics: Dictionary = {}
var tracking := false
var travel := 0.0
var max_step := 0.0
var previous := Vector3.ZERO

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	get_tree().create_timer(230.0, true, false, true).timeout.connect(func():
		if not finished:
			check("bounded actual-source public entry", false)
			finish())
	run.call_deferred()

func _physics_process(_delta: float) -> void:
	if not tracking: return
	var point := player.global_position
	travel += point.distance_to(previous)
	max_step = maxf(max_step, point.distance_to(previous))
	previous = point

func check(label: String, good: bool, detail: Variant = "") -> bool:
	checks += 1
	print("[mbs-source-entry] %s %s %s" % ["PASS" if good else "FAIL", label, str(detail)])
	if not good: failures.append(label)
	return good

func frames(count: int) -> void:
	for index in count: await get_tree().physics_frame

func sha(text: String) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(text.to_utf8_buffer())
	return hash.finish().hex_encode()

func run() -> void:
	var raw := FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json")
	var manifest: Dictionary = JSON.parse_string(raw)
	frame = Frame.new()
	var origin: Array = [Reference.DATA.origin_world_xz[0], 0.0, Reference.DATA.origin_world_xz[1]]
	if not check("real source CRS/snapshot and hotel-origin configure", frame.configure(manifest.georeference, origin, sha(raw), {"status": "staging", "reference": "MBS reconstructed L1=0; surveyed datum unresolved", "source_reference": "Historical architectural form plus explicit metric assumptions"})):
		finish(); return
	var domain := Domain.new()
	if not check("actual pinned national domain loads", domain.configure("res://data/geography/domain/osm-2026-10-27", "82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834", sha(raw))):
		finish(); return
	context = Context.new()
	var profile := {"profile_id": "production-player-upright", "radius_m": .36, "height_m": 1.75, "center_offset_xyz": [0.0, .9, 0.0],
		"min_support_normal_y": cos(deg_to_rad(52.0)), "max_support_drop_m": .35, "max_support_rise_m": .1, "max_support_lateral_m": .4}
	if not check("one context binds actual site and world", context.configure(frame, sha(FileAccess.get_file_as_string("res://src/world/mbs_interior/public_l1.gd")), sha("EXPLICIT MBS metric-staging L1=0; datum not surveyed"), profile, get_world_3d())):
		finish(); return
	for descriptor: Dictionary in domain.provider_descriptors(): check("register actual domain " + descriptor.kind, context.register_provider(descriptor.kind, descriptor.provider_id, descriptor.source_reference))
	check("register native streamer provider", context.register_provider("physics", "source-native-neighborhood/v1", "Owned main-thread source-site geometry commit"))
	runtime = Runtime.new()
	add_child(runtime)
	check("source runtime uses exact shared domain/frame/context", runtime.configure(frame, context, domain.observe))
	site = Site.new()
	add_child(site)
	var report: Dictionary = site.build(frame, context, runtime)
	if not check("actual source public site builds with origin subtraction", report.get("built", false) and report.public.coordinate_context.origin_subtracted_before_vector, report.get("error", "")):
		finish(); return
	await frames(3)
	if not check("actual source structure commits native collision", site.commit_native_floor().ok): finish(); return
	var route: Array = site.public_l1.walking_route_world(true)
	check("complete source doorway/atrium/return route exists", route.size() >= 7)
	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.position = route[0] + Vector3.UP * .1
	add_child(player)
	if not check("production Player binds to real source site", runtime.bind_player(player)): finish(); return
	Game.health = Game.MAX_HEALTH
	Game.simulation_paused = false
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await frames(45)
	var started: Dictionary = frame.to_source_current_live(player.global_position)
	var actual_domain: Dictionary = domain.observe(started.source_xyz)
	check("actual opening belongs to Singapore national polygon", actual_domain.territory.state == "inside", started.source_xyz)
	metrics["source_spawn_xyz"] = started.source_xyz
	previous = player.global_position
	tracking = true
	for index in range(1, route.size()):
		if not await walk(route[index]): finish(); return
		var state: Dictionary = runtime.inspect_player(player)
		check("native source support/dry envelope at route gate " + str(index), state.get("ok", false) and state.support.state == "supported" and state.water.state == "dry_indoor" and Game.health == Game.MAX_HEALTH, state.get("water", {}))
	tracking = false
	check("actual source traversal has no discontinuous relocation", travel > 450.0 and max_step < .3 and Game.health == Game.MAX_HEALTH, {"distance": travel, "max_step": max_step})
	metrics["distance_m"] = travel
	metrics["max_step_m"] = max_step
	metrics["actual_source_origin_xyz"] = origin
	metrics["actual_source_tower_ids"] = report.public.tower_source_ids
	metrics["no_postbuild_module_translation"] = true
	metrics["source_pose"] = runtime.capture_player_pose(player)
	finish()

func walk(target: Vector3) -> bool:
	var deadline := Time.get_ticks_msec() + int((player.global_position.distance_to(target) / 4.5 + 12.0) * 1000.0)
	while player.global_position.distance_to(target) > .36 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		var direction := target - player.global_position
		player.yaw = lerp_angle(player.yaw, atan2(-direction.x, -direction.z), .25)
		Input.action_press("move_forward")
		Input.action_press("sprint")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await frames(3)
	return check("continuous native doorway/atrium walk", player.global_position.distance_to(target) < .55, {"at": player.global_position, "target": target})

func finish() -> void:
	if finished: return
	finished = true
	for action in ["move_forward", "sprint", "jump"]: Input.action_release(action)
	print("[mbs-source-entry] RESULT ", JSON.stringify({"checks": checks, "failures": failures, "metrics": metrics,
		"scope": "Actual national domain + common frame/context + source-positioned public loft and production Player; not full MBS/city/default bootstrap, exterior bridge, source terrain, rendered or performance acceptance."}))
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures.is_empty() else 1)
