extends Node3D
## Real-district controls-based flight and free-look verification.
## Only the initial ground-side player boarding position is a fixture. The
## airborne route, ordinary-roof landing, E exit and subsequent walking never
## assign an actor position or force a landed/mission state. A separately
## labeled native save/load phase restores the on-foot roof checkpoint.
## Source-world geography is still the legacy compressed layout; this scene
## does not certify Singapore mapping, MBS architecture or human acceptance.
const MBS = preload("res://src/world/downtown/landmarks/mbs.gd")
const CLIMB_Y := 245.0
const REVIEW_LIMIT_SECONDS := 250.0
var main: Node
var world: WorldBuilder
var player: Player
var heli: Helicopter
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var captures: Array[Dictionary] = []
var notes: Array[String] = []
var output := ""
var qa_session := ""
var _started := 0
var _finished := false
var _flight_tracking := false
var _last_heli := Vector3.ZERO
var _flight_distance := 0.0
var _max_heli_step := 0.0
var _initial_deaths := 0
var _initial_mission := 0

func _ready() -> void:
	if not _configure_paths():
		get_tree().quit(2)
		return
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.ignore_time_scale = true
	add_child(watchdog)
	watchdog.timeout.connect(func():
		if not _finished:
			check("review completes inside its bounded contract", false, str(_state()))
			_finish())
	watchdog.start(REVIEW_LIMIT_SECONDS)
	_run.call_deferred()

func _canonical(path: String) -> String:
	if path.begins_with("/tmp/"): return "/private/tmp/" + path.trim_prefix("/tmp/")
	return path

func _owned_temp(path: String) -> bool:
	if path != path.simplify_path() or not path.begins_with("/private/tmp/singapore-fidelity/"): return false
	var parent := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/", false):
		var folder := DirAccess.open(parent)
		if folder != null and folder.is_link(part): return false
		parent = parent.path_join(part)
	return true

func _configure_paths() -> bool:
	var args := OS.get_cmdline_user_args()
	var qa_index := args.find("--qa-session")
	if qa_index < 0 or qa_index + 1 >= args.size():
		push_error("World helicopter review requires --qa-session <owned private temp directory>")
		return false
	qa_session = _canonical(args[qa_index + 1])
	var capture_args := 0
	for arg in args:
		if arg.begins_with("--capture-dir="):
			capture_args += 1
			output = _canonical(arg.trim_prefix("--capture-dir="))
	if capture_args != 1 or output == qa_session or not _owned_temp(output) or not _owned_temp(qa_session):
		push_error("Use separate owned /private/tmp/singapore-fidelity/... capture and QA paths; symlinks/unnormalized paths refused")
		return false
	if FileAccess.file_exists(output.path_join("review.json")):
		push_error("World review refuses to overwrite an existing report")
		return false
	return DirAccess.make_dir_recursive_absolute(output) == OK

func _physics_process(_delta: float) -> void:
	if not _flight_tracking or not is_instance_valid(heli) or _finished: return
	var step := heli.global_position.distance_to(_last_heli)
	_flight_distance += step
	_max_heli_step = maxf(_max_heli_step, step)
	_last_heli = heli.global_position

func check(label: String, passed: bool, detail: String = "") -> bool:
	if _finished: return false
	checks += 1
	print("[heli-world] %s %s %s" % ["PASS" if passed else "FAIL", label, detail])
	if not passed: failures.append(label)
	return passed

func _note(text: String) -> void:
	var line := "%.2fs %s" % [_elapsed(), text]
	notes.append(line)
	print("[heli-world] ", line)

func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _started) / 1000.0

func _release() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "interact"]:
		Input.action_release(action)

func _frames(count: int) -> void:
	for i in count:
		if _finished: return
		await get_tree().physics_frame

func _press_e() -> void:
	Input.action_press("interact")
	await get_tree().process_frame
	await _frames(2)
	Input.action_release("interact")
	await get_tree().process_frame
	await _frames(4)

func _state() -> Dictionary:
	if not is_instance_valid(heli): return {"heli_present": false}
	return {"heli_position": str(heli.global_position), "velocity": str(heli.velocity),
		"health": heli.health, "disabled": heli.disabled, "on_floor": heli.is_on_floor(),
		"landed": heli.is_landed(), "mode": Game.mode, "elapsed_s": _elapsed(),
		"flight_distance_m": _flight_distance, "max_physics_step_m": _max_heli_step}

func _shot(label: String) -> void:
	if _finished: return
	var record := {"label": label, "state": _state(), "camera_yaw": heli._cam_yaw,
		"camera_pitch": heli._cam_pitch, "initial_boarding_fixture": true, "failed_assertions": failures.duplicate()}
	if DisplayServer.get_name() == "headless":
		record["saved"] = false
		record["reason"] = "headless: no rendered image"
		captures.append(record)
		return
	var expected := player.camera if player.current_vehicle == null else heli._camera
	if not check("real active player/vehicle camera " + label, get_viewport().get_camera_3d() == expected): return
	await RenderingServer.frame_post_draw
	if _finished: return
	var file := output.path_join(label + ".png")
	if FileAccess.file_exists(file) or DirAccess.open(output).is_link(label + ".png"):
		check("capture preserves existing evidence " + label, false, file)
		return
	var image := get_viewport().get_texture().get_image()
	var ok := image != null and not image.is_empty() and image.save_png(file) == OK
	check("actual rendered frame " + label, ok)
	record["file"] = file
	record["saved"] = ok
	if image != null:
		record["pixels"] = [image.get_width(), image.get_height()]
	captures.append(record)

func _run() -> void:
	_started = Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	world = main.world
	player = main.player
	heli = main.get_node_or_null("Helicopter") as Helicopter
	if not check("production district, player, helicopter and HUD exist", world != null and player != null and heli != null and main.hud != null):
		_finish(); return
	main.started = true
	main.hud.show_title(false)
	Game.simulation_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# QA process only: block desktop typing from steering this scripted run.
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"): InputMap.action_erase_events(action)
	_release()
	await _frames(6) # register real district collision transforms before ray queries
	_initial_deaths = Game.death_count
	_initial_mission = main.mission.stage
	if not check("MBS world location exists", world.locations.has("marina_bay_sands")):
		_finish(); return
	var roof: Vector3 = world.locations["marina_bay_sands"] + Vector3(-130.0, MBS.DECK_Y, 2.0)
	# The originally proposed local(-100,200,0) sits inside a visible pavilion.
	# This point lies on clear unpainted deck, outside pool/lounger/planter rows.
	metrics["roof_target"] = [roof.x, roof.y, roof.z]
	# Navigation hint is recorded only; physical geometry controls permission.
	metrics["marked_landing_hint_at_target"] = DowntownPlan.is_marked_landing_hint(roof)
	if not check("native save is confined to explicit QA session", _canonical(String(Game.get("_save_path"))) == qa_session.path_join("orchard_reach_save.json")):
		_finish(); return
	metrics["roof_selection"] = "local(-130,deck_y,2): clear unpainted deck; local(-100,deck_y,0) rejected because it overlaps the visible pavilion"
	var query := PhysicsRayQueryParameters3D.create(roof + Vector3.UP * 30.0, roof - Vector3.UP * 3.0, 1)
	var support := get_world_3d().direct_space_state.intersect_ray(query)
	var roof_supported := not support.is_empty() and absf((support.position as Vector3).y - roof.y) < 0.2 and (support.normal as Vector3).y > 0.8
	if not check("ordinary MBS roof has actual flat collision at deck height", roof_supported, str(support)):
		_finish(); return
	if world.locations.has("helipad_skypark"):
		var pad: Vector3 = world.locations["helipad_skypark"]
		check("target is well outside the painted roof pad", Vector2(roof.x - pad.x, roof.z - pad.z).length() > 50.0)
	_note("FIXTURE initial player ground-side boarding placement; no subsequent aircraft relocation")
	player.respawn_at(heli.global_position + heli.global_basis.x * 3.6 + Vector3.UP * 0.3, heli.rotation.y)
	await _frames(40)
	if not check("real helicopter is E interaction target", player._interaction_target() == heli):
		_finish(); return
	await _press_e()
	if not check("actual E boards production helicopter exclusively", player.current_vehicle == heli and heli.pilot_is_player and Game.mode == Game.MODE_HELI and player.collision_layer == 0 and heli._camera.current and not player.camera.current):
		_finish(); return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_flight_tracking = true
	_last_heli = heli.global_position
	Input.action_press("jump")
	var climb_end := _elapsed() + 35.0
	while _elapsed() < climb_end and heli.global_position.y < CLIMB_Y and not heli.disabled:
		await get_tree().physics_frame
	_release()
	await _frames(45)
	if not check("real Space takeoff reaches clear flight altitude", heli.global_position.y >= CLIMB_Y - 1.0 and not heli.disabled, str(_state())):
		_finish(); return
	await _shot("01_airborne_aviation")
	await _camera_review()
	if _finished: return
	# Fly over the bay rather than through a downtown tower corridor.
	var bay_waypoint := Vector3(100.0, CLIMB_Y, -450.0)
	if not await _fly_to(bay_waypoint, 60.0, 18.0, false):
		check("controls flight reaches bay waypoint", false, str(_state())); _finish(); return
	check("controls flight reaches bay waypoint", true, str(_state()))
	await _shot("08_bay_approach")
	if not await _fly_to(roof, 75.0, 4.0, true):
		check("controls flight lands on ordinary unpainted MBS roof", false, str(_state())); _finish(); return
	_release()
	await _frames(8)
	if not check("controls flight lands on ordinary unpainted MBS roof", heli.is_on_floor() and heli.is_landed() and _horizontal(heli.global_position, roof) < 8.0, str(_state())):
		_finish(); return
	if not check("landing leaves aircraft usable", not heli.disabled and heli.health >= 95.0, "health=%.2f touchdown=%.2f" % [heli.health, heli.last_touchdown_speed]):
		_finish(); return
	await _shot("09_landed_unpainted_roof")
	await _press_e()
	if not check("actual E permits ordinary roof exit", player.current_vehicle == null and Game.mode == Game.MODE_FOOT and player.visible and player.camera.current and absf(player.global_position.y - roof.y) < 0.5 and _horizontal(player.global_position, roof) < 12.0):
		_finish(); return
	await _frames(10)
	# Use the normal mouse-look helper to face along the roof's long axis,
	# keeping this short walk clear of the existing pool/lounge/pavilion row.
	var foot_sens := Player.MOUSE_SENS * float(Game.settings.get("mouse_sensitivity", 1.0))
	player._apply_mouse_look(Vector2(-wrapf(PI * 0.5 - player.yaw, -PI, PI) / foot_sens, 0))
	metrics["foot_walk_heading_rad"] = player.yaw
	await _frames(2)
	var foot_start := player.global_position
	Input.action_press("move_forward")
	await _frames(60)
	_release()
	await _frames(6)
	check("walking works after ordinary roof exit", _horizontal(player.global_position, foot_start) > 2.0 and player.is_on_floor() and absf(player.global_position.y - roof.y) < 0.5, str(player.global_position))
	await _shot("10_walking_unpainted_roof")
	await _roof_save_reload_checks(roof)
	check("flight has no teleport-sized physics steps", _max_heli_step < 3.0, "max_step=%.3f distance=%.1f" % [_max_heli_step, _flight_distance])
	check("flight and exit cause no player death", Game.death_count == _initial_deaths and Game.health > 0.0)
	check("original story objective remains unchanged", main.mission.stage == _initial_mission)
	_finish()

func _roof_save_reload_checks(roof: Vector3) -> void:
	# This is the real save API and schema, not a hand-built payload. Any
	# old public-terrace restriction must fail here instead of being bypassed.
	_release()
	await _frames(30) # normal deceleration settles before native snapshot
	var saved_position := player.global_position
	var saved_health := Game.health
	var saved_stage: int = main.mission.stage
	var activity := get_tree().get_first_node_in_group("downtown_activity")
	var saved_courier: Dictionary = activity.serialize_state() if activity != null else {}
	var saved := Game.save_game()
	metrics["roof_save_position"] = [saved_position.x, saved_position.y, saved_position.z]
	if not check("native save accepts unpainted roof state", saved): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(Game.get("_save_path"))))
	var payload_position: Variant = parsed.get("player_position") if parsed is Dictionary else null
	var payload_matches := false
	if payload_position is Array and payload_position.size() == 3:
		var actual := Vector3(float(payload_position[0]), float(payload_position[1]), float(payload_position[2]))
		payload_matches = actual.distance_to(saved_position) < 0.01
		metrics["roof_save_payload_position"] = payload_position
	check("native payload stores actual unpainted roof position", payload_matches)
	Input.action_press("move_right")
	await _frames(60)
	_release()
	await _frames(30)
	check("player really moves before roof reload", _horizontal(player.global_position, saved_position) > 1.0 and player.is_on_floor(), str(player.global_position))
	metrics["roof_position_before_reload"] = [player.global_position.x, player.global_position.y, player.global_position.z]
	player.set_meta("_qa_motion_probe", true) # existing production read-only QA instrumentation
	var reload_diagnostics: Array[Dictionary] = [_motion_snapshot("before_native_load")]
	var loaded := Game.load_game()
	reload_diagnostics.append(_motion_snapshot("immediate_after_native_load"))
	metrics["roof_reload_motion_diagnostics"] = reload_diagnostics
	# Check the exact restored coordinates before ordinary gravity/snap ticks.
	if not check("native load restores exact unpainted roof position", loaded and player.global_position.distance_to(saved_position) < 0.01, "loaded=%s actual=%s expected=%s" % [loaded, player.global_position, saved_position]):
		await _shot("diagnostic_roof_reload_failure")
		return
	await _frames(12)
	reload_diagnostics.append(_motion_snapshot("after_load_physics"))
	if not check("loaded unpainted roof has floor and live foot control", loaded and player.is_on_floor() and absf(player.global_position.y - roof.y) < 0.5 and player.current_vehicle == null and player.alive and player.visible and not player.busy and player.camera.current and Game.mode == Game.MODE_FOOT and player.collision_layer == 2 and player.collision_mask == Player.COLLIDE_MASK):
		await _shot("diagnostic_roof_reload_floor_failure")
		return
	check("roof reload preserves health and story", is_equal_approx(Game.health, saved_health) and main.mission.stage == saved_stage)
	check("roof reload preserves optional courier state", activity == null or activity.serialize_state() == saved_courier)
	# Preserve a one-shot diagnostic of the former driver. Native focus
	# changes can clear synthetic held actions; the continuous-hold phase
	# reasserts the intended key each physics tick, as the flight driver does.
	# Neither phase changes actor positions, enables physics or edits state.
	var one_shot: Dictionary = await _observe_postload_walk("one_shot", false)
	metrics["roof_post_reload_one_shot"] = one_shot
	var held: Dictionary = await _observe_postload_walk("reasserted_hold", true)
	metrics["roof_post_reload_reasserted_hold"] = held
	var movement_ok := float(held.displacement_m) > 2.0 and player.is_on_floor() and absf(player.global_position.y - roof.y) < 0.5
	check("walking remains usable after native roof reload", movement_ok, "held=%.3fm one_shot=%.3fm position=%s" % [float(held.displacement_m), float(one_shot.displacement_m), player.global_position])
	metrics["roof_post_reload_position"] = [player.global_position.x, player.global_position.y, player.global_position.z]
	# Let the real restore notification expire; preserve all assertions/logs.
	await get_tree().create_timer(4.2).timeout
	await _shot("11_unpainted_roof_after_native_reload" if movement_ok else "diagnostic_roof_reload_motion_failure")

func _motion_snapshot(label: String) -> Dictionary:
	var contacts: Array[Dictionary] = []
	for i in player.get_slide_collision_count():
		var hit := player.get_slide_collision(i)
		var collider: Object = hit.get_collider()
		contacts.append({"collider": str((collider as Node).get_path()) if collider is Node else str(collider),
			"normal": str(hit.get_normal()), "position": str(hit.get_position())})
	var probe: Variant = player.get_meta("_qa_motion_state", {})
	return {"label": label, "ticks_msec": Time.get_ticks_msec(),
		"physics_frame": Engine.get_physics_frames(), "process_frame": Engine.get_process_frames(),
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"velocity": str(player.velocity), "speed_state": player._speed, "heading": player._heading,
		"yaw": player.yaw, "busy": player.busy, "alive": player.alive, "visible": player.visible,
		"vehicle": str(player.current_vehicle) if is_instance_valid(player.current_vehicle) else "none",
		"mode": Game.mode, "game_paused": Game.simulation_paused, "tree_paused": get_tree().paused,
		"physics_processing": player.is_physics_processing(), "processing": player.is_processing(),
		"floor": player.is_on_floor(), "camera_current": player.camera.current,
		"collision_layer": player.collision_layer, "collision_mask": player.collision_mask,
		"forward_strength": Input.get_action_strength("move_forward"),
		"back_strength": Input.get_action_strength("move_back"),
		"left_strength": Input.get_action_strength("move_left"),
		"right_strength": Input.get_action_strength("move_right"),
		"forward_pressed": Input.is_action_pressed("move_forward"),
		"window_focused": get_window().has_focus(), "contacts": contacts,
		"production_motion_probe": probe.duplicate(true) if probe is Dictionary else {},
		"probe_timing": "production probe is from the most recently completed Player physics tick"}

func _observe_postload_walk(label: String, reassert: bool) -> Dictionary:
	_release()
	await _frames(30)
	var start := player.global_position
	var started := Time.get_ticks_msec()
	var trace: Array[Dictionary] = [_motion_snapshot(label + "_before_press")]
	var cleared_samples := 0
	Input.action_press("move_forward")
	for i in 60:
		if reassert: Input.action_press("move_forward")
		var strength_before := Input.get_action_strength("move_forward")
		await get_tree().physics_frame
		var sample := _motion_snapshot("%s_tick_%d" % [label, i])
		sample["strength_before_tick"] = strength_before
		if float(sample.forward_strength) < 0.9: cleared_samples += 1
		trace.append(sample)
	_release()
	await _frames(30)
	trace.append(_motion_snapshot(label + "_after_deceleration"))
	var result := {"driver": label, "reassert_each_physics_tick": reassert,
		"physics_ticks_held": 60, "elapsed_s": float(Time.get_ticks_msec() - started) / 1000.0,
		"displacement_m": _horizontal(player.global_position, start),
		"input_cleared_samples": cleared_samples, "trace": trace}
	print("[heli-world] POSTLOAD_MOTION ", JSON.stringify(result))
	return result

func _look_to(pitch: float, yaw_delta: float, ticks: int) -> Dictionary:
	var pitch_direction := signf(pitch - heli._cam_pitch)
	var dy := -(pitch - heli._cam_pitch) / Player.MOUSE_SENS
	var dx := -yaw_delta / Player.MOUSE_SENS
	var previous_y := heli._camera.global_position.y - heli.global_position.y
	var reversals := 0
	var trace: Array[float] = []
	for i in ticks:
		player._apply_mouse_look(Vector2(dx, dy) / float(ticks))
		await get_tree().physics_frame
		var current_y := heli._camera.global_position.y - heli.global_position.y
		trace.append(current_y)
		# Ignore the first two update-order frames. In this clear-air test,
		# a single-direction pitch sweep must not bounce vertically.
		if i >= 2 and pitch_direction != 0.0 and (current_y - previous_y) * pitch_direction > 0.02:
			reversals += 1
		previous_y = current_y
	return {"vertical_reversals": reversals, "relative_camera_y_trace_m": trace}

func _camera_review() -> void:
	var foot_yaw := player.yaw
	var foot_pitch := player.pitch
	# Production sensitivity is normalized only within this explicit QA process.
	var old_sensitivity: float = float(Game.settings.get("mouse_sensitivity", 1.0))
	var old_invert: bool = bool(Game.settings.get("invert_y", false))
	Game.settings["mouse_sensitivity"] = 1.0
	Game.settings["invert_y"] = false
	for i in 4:
		await _look_to(Helicopter.CAMERA_DEFAULT_PITCH, PI * 0.5, 45)
		await _frames(3)
		await _shot("02_orbit_quarter_%d" % (i + 1))
	check("look sequence requests full360 orbit", absf(wrapf(heli._cam_yaw - heli.rotation.y, -PI, PI)) < 0.02)
	var up_trace: Dictionary = await _look_to(deg_to_rad(88.5), 0.0, 15)
	metrics["look_up_motion"] = up_trace
	check("upward look has no vertical bounce in district", up_trace.vertical_reversals == 0, str(up_trace))
	await _frames(3)
	check("actual camera can look nearly straight up", (-heli._camera.global_basis.z).y > 0.995)
	await _shot("03_look_up")
	var down_trace: Dictionary = await _look_to(deg_to_rad(-88.5), 0.0, 15)
	metrics["look_down_motion"] = down_trace
	check("downward look has no vertical bounce in district", down_trace.vertical_reversals == 0, str(down_trace))
	await _frames(3)
	check("actual camera can look nearly straight down", (-heli._camera.global_basis.z).y < -0.995)
	await _shot("04_look_down")
	await _look_to(Helicopter.CAMERA_DEFAULT_PITCH, 0.0, 15)
	await _frames(8)
	var held_forward := -heli._camera.global_basis.z
	var held_yaw := heli._cam_yaw
	var yaw_start := heli.rotation.y
	var y_min := INF
	var y_max := -INF
	var max_view_rotation := 0.0
	Input.action_press("move_left", 0.5)
	for i in 120:
		await get_tree().physics_frame
		var relative_y := heli._camera.global_position.y - heli.global_position.y
		y_min = minf(y_min, relative_y)
		y_max = maxf(y_max, relative_y)
		max_view_rotation = maxf(max_view_rotation, held_forward.angle_to(-heli._camera.global_basis.z))
	_release()
	metrics["relative_camera_y_range_no_mouse_m"] = y_max - y_min
	metrics["camera_rotation_no_mouse_rad"] = max_view_rotation
	metrics["aircraft_yaw_change_during_hold_rad"] = absf(wrapf(heli.rotation.y - yaw_start, -PI, PI))
	check("aircraft turns while free camera is held", metrics.aircraft_yaw_change_during_hold_rad > 0.5)
	check("free look does not recenter on aircraft", absf(wrapf(heli._cam_yaw - held_yaw, -PI, PI)) < 0.001 and max_view_rotation < 0.005)
	check("no vertical orbit jitter in actual district clear air", y_max - y_min < 0.02, "relative_y_range=%.6f" % (y_max - y_min))
	check("aircraft look does not steer hidden foot camera", player.yaw == foot_yaw and player.pitch == foot_pitch)
	Game.settings["mouse_sensitivity"] = old_sensitivity
	Game.settings["invert_y"] = old_invert
	await _shot("05_held_camera_after_turn")

func _horizontal(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _fly_to(target: Vector3, timeout: float, reach: float, landing: bool) -> bool:
	var until := _elapsed() + timeout
	var best := INF
	var last_note := _elapsed()
	while _elapsed() < until and not _finished:
		await get_tree().physics_frame
		if heli.disabled or Game.death_count != _initial_deaths: break
		var delta := target - heli.global_position
		delta.y = 0.0
		var distance := delta.length()
		best = minf(best, distance)
		var speed := Vector2(heli.velocity.x, heli.velocity.z).length()
		_release()
		var desired_yaw := atan2(-delta.x, -delta.z)
		var err := wrapf(desired_yaw - heli.rotation.y, -PI, PI)
		if absf(err) > 0.035:
			Input.action_press("move_left" if err > 0.0 else "move_right", clampf(absf(err) * 1.5, 0.08, 1.0))
		var desired_speed := 30.0 if distance > 120.0 else clampf(distance * 0.22, 0.0, 18.0)
		if distance <= reach: desired_speed = 0.0
		if absf(err) < 0.5 and desired_speed > 0.0:
			Input.action_press("move_forward", desired_speed / Helicopter.MAX_FORWARD)
		var wanted_y := CLIMB_Y
		if landing and distance < 120.0:
			wanted_y = target.y + 20.0
		if landing and distance < reach and speed < 1.5:
			wanted_y = target.y - 1.0
		var altitude_error := wanted_y - heli.global_position.y
		if altitude_error > 1.0:
			Input.action_press("jump", clampf(altitude_error / 10.0, 0.1, 1.0))
		elif altitude_error < -0.3:
			Input.action_press("sprint", clampf(-altitude_error / 12.0, 0.1, 1.0))
		if landing:
			if heli.is_on_floor() and heli.is_landed() and distance < 8.0:
				_note("physical roof touchdown " + str(_state()))
				return true
		elif distance < reach:
			_release()
			return true
		if _elapsed() - last_note > 8.0:
			_note("flight target=%s distance=%.2f best=%.2f altitude=%.2f" % [target, distance, best, heli.global_position.y])
			last_note = _elapsed()
	_release()
	return false

func _finish() -> void:
	if _finished: return
	_release()
	var report := {"checks": checks, "failures": failures, "metrics": metrics, "captures": captures,
		"notes": notes, "terminal": _state(), "elapsed_s": _elapsed(), "rendered": DisplayServer.get_name() != "headless",
		"native_human_input": false, "initial_ground_boarding_fixture": true,
		"in_flight_position_assignments": false, "geographic_accuracy_verified": false,
		"scope": "Real compressed district; actual controls-based flight/free-look/ordinary-roof exit. Not whole-interior/map/performance acceptance."}
	var f := FileAccess.open(output.path_join("review.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t")); f.close()
	else:
		check("review report writes", false, output)
	report["checks"] = checks
	report["failures"] = failures
	print("[heli-world] RESULT ", JSON.stringify(report))
	_finished = true
	_flight_tracking = false
	Game.simulation_paused = true
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures.is_empty() else 1)
