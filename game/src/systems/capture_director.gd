extends Node
## Uninterrupted scripted gameplay evidence. Only public input actions and the
## same mouse-look yaw/pitch values used by human input drive this route. No
## actor teleport, health reset, wanted reset, mission-stage write, or invulnerability.

const ROUTE_TIMEOUT := 720.0
const ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "aim", "fire", "interact", "reload"]
var main: Node
var player: Player
var world: WorldBuilder
var mission: Mission
var traffic: TrafficManager
var out_dir := "captures"
var log_lines: Array[String] = []
var _shots := 0
var _started_us := 0
var _last_frame_us := 0
var _last_sample_second := -1
var _initial_deaths := 0
var _finished := false
var _capture_in_progress := false
var _failure := ""
var _frames_ms: Array[float] = []
var _frame_stalls: Array[Dictionary] = []
var _frame_stall_overflow := 0
var _frame_stall_log: FileAccess
var _frame_stall_log_opened := false
const FRAME_STALL_THRESHOLD_MS := 100.0
const FRAME_STALL_MAX_EVENTS := 1000
var _samples: Array[Dictionary] = []
var _gates: Array[Dictionary] = []
var _combat_kills := 0
var _boarding_target: Node3D
var _soak_enabled := false
var _soak_seconds := 1800.0
var _phase := "mission"
var _run_index := 0
var _run_started := 0.0
var _run_kills_start := 0
var _run_gate_start := 0
var _completed_runs: Array[Dictionary] = []
var _fixture_checks: Array[Dictionary] = []
var _free_distance := {"foot": 0.0, "car": 0.0, "helicopter": 0.0}
var _free_last_actor: Node3D
var _free_last_position := Vector3.ZERO
var _continuity_actor: Node3D
var _continuity_position := Vector3.ZERO
var _continuity_us := 0
var _continuity_breaks: Array[Dictionary] = []
const SOAK_REQUIRED_RUNS := 3
const SOAK_ACCEPTANCE_SECONDS := 1800.0
const SOAK_FINAL_RESERVE_SECONDS := 180.0
var _final_recovery_requested := false
var _final_observation_started := -1.0
var _reboard_cycle_verified := false
var _aircraft_cycle_verified := false
var _free_roam_events: Array[Dictionary] = []
var _foot_motion_bucket := 0.0
var _recent_foot_motion: Array[Dictionary] = []
var _last_foot_motion_seconds := -1000.0
var _engine_log_path := ""
var _next_error_scan := 30.0
var _runtime_log_scan := {"checked": false, "fatal_errors": [], "classified_nonfatal": []}
var _next_soak_still := 300.0
var _monitor_ids: Dictionary = {}
var _monitor_unavailable: Array[String] = []
var _headless := false
var _inclusive_frames_ms: Array[float] = []
var _readback_since_frame := false
var _record_dir := ""
var _record_log: FileAccess
var _record_index := 0
var _record_bytes := 0
var _record_requested_samples := 0
var _record_dropped_samples := 0
var _record_next_us := 0
var _record_pending := false
var _record_capped := false
var _record_cap_reason := ""
var _record_cost_ms: Array[float] = []
var _completion_recording_hold: Dictionary = {"requested": false, "elapsed_seconds": 0.0, "frames_written": 0}
const RECORD_INTERVAL_US := 100000 # Requested 10Hz; timestamps are authoritative.
const RECORD_MAX_FRAMES := 7200
const RECORD_MAX_BYTES := 1024 * 1024 * 1024
const RECORD_MAX_SECONDS := 720.0

func setup(m: Node, p: Player, w: WorldBuilder, mi: Mission, t: TrafficManager) -> void:
	main = m
	player = p
	world = w
	mission = mi
	traffic = t
	for arg in OS.get_cmdline_user_args():
		if arg == "--soak":
			_soak_enabled = true
		elif arg.begins_with("--soak-seconds="):
			_soak_seconds = clampf(float(arg.trim_prefix("--soak-seconds=")), 30.0, 1800.0)
		elif arg.begins_with("--capture-dir="):
			out_dir = arg.trim_prefix("--capture-dir=")
		elif arg.begins_with("--record-frames="):
			_record_dir = arg.trim_prefix("--record-frames=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_frame_stall_log = FileAccess.open(out_dir.path_join("frame_stalls.jsonl"), FileAccess.WRITE)
	_frame_stall_log_opened = _frame_stall_log != null
	_engine_log_path = _resolve_engine_log_path()
	_initialize_monitors()
	_initial_deaths = Game.death_count
	_started_us = Time.get_ticks_usec()
	_last_frame_us = _started_us
	_headless = DisplayServer.get_name() == "headless"
	if not _record_dir.is_empty() and not _headless:
		DirAccess.make_dir_recursive_absolute(_record_dir)
		_record_log = FileAccess.open(_record_dir.path_join("frames.jsonl"), FileAccess.WRITE)
		_record_next_us = _started_us
		if _record_log == null:
			_record_capped = true
			_record_cap_reason = "Could not open frames.jsonl"
	Events.actor_died.connect(func(actor: Node, by_player: bool):
		if by_player and actor is NPC and actor.is_hostile:
			_combat_kills += 1
			_maybe_combat_shot(actor as NPC))
	_run()

func _process(_delta: float) -> void:
	if _finished or player == null:
		return
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _started_us) / 1000000.0
	if _last_frame_us > 0:
		var frame_ms := float(now - _last_frame_us) / 1000.0
		var capture_overhead := _capture_in_progress or _readback_since_frame or _record_pending
		_inclusive_frames_ms.append(frame_ms)
		if not capture_overhead:
			_frames_ms.append(frame_ms)
		if frame_ms > FRAME_STALL_THRESHOLD_MS:
			if _frame_stalls.size() < FRAME_STALL_MAX_EVENTS:
				var stall := {"started_seconds": float(_last_frame_us - _started_us) / 1000000.0,
					"ended_seconds": elapsed, "interval_ms": frame_ms, "phase": _phase, "run": _run_index,
					"capture_overhead": capture_overhead, "screenshot_pending": _capture_in_progress,
					"readback_since_frame": _readback_since_frame, "recording_pending": _record_pending}
				_frame_stalls.append(stall)
				if _frame_stall_log:
					_frame_stall_log.store_line(JSON.stringify(stall))
					_frame_stall_log.flush()
			else:
				_frame_stall_overflow += 1
	_last_frame_us = now
	_readback_since_frame = false
	if _record_log and not _record_capped and elapsed >= RECORD_MAX_SECONDS:
		_record_capped = true
		_record_cap_reason = "Recording duration safety cap reached"
	if _record_log and not _record_capped and now >= _record_next_us:
		var due := 1 + int((now - _record_next_us) / RECORD_INTERVAL_US)
		_record_requested_samples += due
		_record_dropped_samples += due - 1
		_record_next_us += due * RECORD_INTERVAL_US
		if _record_pending:
			_record_dropped_samples += 1
		else:
			_record_frame()
	if int(elapsed) != _last_sample_second:
		_last_sample_second = int(elapsed)
		_samples.append(_snapshot(elapsed))
		if _soak_enabled:
			_recent_foot_motion.append({"seconds": elapsed, "distance_m": _foot_motion_bucket})
			_foot_motion_bucket = 0.0
			while not _recent_foot_motion.is_empty() and _recent_foot_motion[0]["seconds"] < elapsed - 60.0:
				_recent_foot_motion.pop_front()
		_write_checkpoint()
	if _soak_enabled and elapsed >= _soak_seconds - SOAK_FINAL_RESERVE_SECONDS:
		_final_recovery_requested = true
	if _soak_enabled and elapsed >= _next_error_scan:
		_next_error_scan += 30.0
		_scan_runtime_log()
		if not _runtime_log_scan["checked"] or not _runtime_log_scan["fatal_errors"].is_empty():
			_abort("Soak runtime error-log gate is unavailable or contains unhandled errors.")
			return
	if _soak_enabled and not _headless and elapsed >= _next_soak_still and not _capture_in_progress and not _record_pending:
		_next_soak_still += 300.0
		_shot("soak_%s_%04d" % [_phase, int(elapsed)])
	if _phase == "mission":
		var controlled := player.controlled_actor()
		if controlled == _continuity_actor and _continuity_us > 0:
			var travelled := controlled.global_position.distance_to(_continuity_position)
			var allowance := 2.0 + 80.0 * float(now - _continuity_us) / 1000000.0
			if travelled > allowance:
				_continuity_breaks.append({"run": _run_index, "seconds": elapsed, "distance_m": travelled, "allowance_m": allowance})
				_abort("Unexpected controlled-actor position discontinuity during mission attempt.")
				return
		_continuity_actor = controlled
		_continuity_position = controlled.global_position
		_continuity_us = now
	else:
		_continuity_actor = null
	if _phase in ["free_roam", "final_recovery", "final_observation"]:
		var actor := player.controlled_actor()
		if actor == _free_last_actor:
			var travelled := actor.global_position.distance_to(_free_last_position)
			if travelled < 12.0:
				var key := "foot" if Game.mode == Game.MODE_FOOT else ("car" if Game.mode == Game.MODE_CAR else "helicopter")
				if Game.mode == Game.MODE_FOOT:
					var ground_travelled := _ground_distance(actor.global_position, _free_last_position)
					_free_distance[key] += ground_travelled
					_foot_motion_bucket += ground_travelled
					if ground_travelled > 0.02: _last_foot_motion_seconds = elapsed
				else:
					_free_distance[key] += travelled
		_free_last_actor = actor
		_free_last_position = actor.global_position
	if _phase == "mission" and Game.death_count != _initial_deaths:
		_abort("Player died/respawned; this attempt cannot certify an uninterrupted mission.")
	elif _phase != "fixture_assisted" and player.current_vehicle != null and player.current_vehicle.get("disabled"):
		_abort("Controlled vehicle disabled; transport leg failed.")
	elif _soak_enabled and elapsed >= _soak_seconds:
		var complete := _soak_complete()
		if not complete: _failure = "Soak deadline reached before required mission/fixture/mixed-activity gates."
		_finish(complete)
	elif _phase == "mission" and elapsed - _run_started >= ROUTE_TIMEOUT:
		_abort("Mission attempt exceeded %.0f-second wall-clock limit." % ROUTE_TIMEOUT)

func _snapshot(elapsed: float) -> Dictionary:
	var actor := player.controlled_actor()
	var pos := actor.global_position
	return {"seconds": snappedf(elapsed, 0.01), "phase": _phase, "run": _run_index, "position": [pos.x, pos.y, pos.z],
		"mode": Game.mode, "stage": mission.stage, "health": Game.health,
		"wanted": Game.wanted_level, "deaths": Game.death_count - _initial_deaths,
		"car_distance_m": mission.car_driven_distance, "flight_distance_m": mission.flight_distance,
		"vehicle_health": actor.get("health") if actor != player else null, "heading": actor.rotation.y,
		"police": _police_sample(pos),
		"engine_monitors": _performance_snapshot(),
		"render_texture_pixels": [get_viewport().get_texture().get_width(), get_viewport().get_texture().get_height()],
		"msaa_3d": ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d"),
		"taa": ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa")}

## Pursuit telemetry (wave 5): responder count, nearest responder distance and
## how many responders moved under 0.5 m since the previous sample (stuck).
var _police_last: Dictionary = {}
var _police_last_time := -1.0
func _police_sample(pos: Vector3) -> Dictionary:
	# Only refresh the movement reference once per second of route time, so
	# 10 Hz frame records cannot make a slow responder look stationary.
	var now := _elapsed()
	var refresh := _police_last_time < 0.0 or now - _police_last_time >= 0.95
	var nearest := INF
	var count := 0
	var still := 0
	var seen := {}
	for pc in traffic.police_cars:
		if not is_instance_valid(pc) or pc.disabled: continue
		count += 1
		nearest = minf(nearest, pc.global_position.distance_to(pos))
		var id := pc.get_instance_id()
		seen[id] = pc.global_position
		if refresh and _police_last.has(id) and (pc.global_position as Vector3).distance_to(_police_last[id]) < 0.5: still += 1
	if refresh:
		_police_last = seen
		_police_last_time = now
	return {"cars": count, "nearest_m": snappedf(nearest, 0.1) if count > 0 else null, "stationary": still}

func _log(message: String) -> void:
	if _finished: return
	log_lines.append("%.2fs %s" % [_elapsed(), message])
	print("[capture] ", log_lines[-1])

func _elapsed() -> float:
	return float(Time.get_ticks_usec() - _started_us) / 1000000.0

func _gate(label: String, condition: bool) -> bool:
	if _finished: return false
	_gates.append({"name": label, "passed": condition, "state": _snapshot(_elapsed())})
	_log("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_abort(label)
	return condition

func _shot(label: String) -> void:
	if _finished or _headless:
		return
	_capture_in_progress = true
	await RenderingServer.frame_post_draw
	if _finished:
		_capture_in_progress = false
		return
	var img := get_viewport().get_texture().get_image()
	if img != null:
		_shots += 1
		var path := "%s/%02d_%s.png" % [out_dir, _shots, label]
		img.save_png(path)
		_log("screenshot " + path)
	_readback_since_frame = true
	_capture_in_progress = false

## Continuous viewport evidence. Every file carries its actual wall-clock
## timestamp; an encoder must preserve those durations instead of assuming a
## perfect 10fps source. Recording is bounded independently of the route.
func _record_frame() -> void:
	_record_pending = true
	await RenderingServer.frame_post_draw
	if _finished or _record_log == null:
		_record_pending = false
		return
	var timestamp_us := Time.get_ticks_usec()
	if float(timestamp_us - _started_us) / 1000000.0 >= RECORD_MAX_SECONDS:
		_record_capped = true
		_record_cap_reason = "Recording duration safety cap reached"
		_record_pending = false
		return
	var capture_started := timestamp_us
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_record_dropped_samples += 1
		_record_pending = false
		return
	var filename := "frame_%06d.jpg" % _record_index
	var path := _record_dir.path_join(filename)
	var encoded := img.save_jpg_to_buffer(0.8)
	if _record_bytes + encoded.size() > RECORD_MAX_BYTES:
		_record_capped = true
		_record_cap_reason = "Recording byte safety cap reached"
		_record_pending = false
		_readback_since_frame = true
		return
	var output := FileAccess.open(path, FileAccess.WRITE)
	var error := ERR_CANT_OPEN
	if output:
		output.store_buffer(encoded)
		error = output.get_error()
		output.close()
	var capture_cost := float(Time.get_ticks_usec() - capture_started) / 1000.0
	_record_cost_ms.append(capture_cost)
	_readback_since_frame = true
	if error != OK:
		_record_capped = true
		_record_cap_reason = "JPEG write failed (%d)" % error
	else:
		_record_bytes += encoded.size()
		_record_log.store_line(JSON.stringify({"sequence": _record_index, "file": filename,
			"timestamp_us": timestamp_us, "seconds": float(timestamp_us - _started_us) / 1000000.0,
			"width": img.get_width(), "height": img.get_height(), "readback_encode_ms": capture_cost,
			"state": _snapshot(float(timestamp_us - _started_us) / 1000000.0), "life": _life_counts()}))
		_record_index += 1
		if _record_index % 10 == 0: _record_log.flush()
		if _record_index >= RECORD_MAX_FRAMES or _record_bytes >= RECORD_MAX_BYTES:
			_record_capped = true
			_record_cap_reason = "Recording frame/byte safety cap reached"
	_record_pending = false

func _run() -> void:
	if _finished: return
	_phase = "mission"
	_continuity_actor = null
	_run_index += 1
	_run_started = _elapsed()
	_run_kills_start = _combat_kills
	_run_gate_start = _gates.size()
	await get_tree().create_timer(0.75).timeout
	_log("Route start; seed=%d; headless=%s; scripted-input-automation=true" % [Game.seed_value, _headless])
	await _shot("opening_street")
	await _nav_to(world.locations["package"], 4.0, 130.0)
	if not _gate("market reached on foot", _ground_distance(player.global_position, world.locations["package"]) < 8.0): return
	await _shot("hawker_market")

	# Actual damage-producing weapon input, with camera aim corrected each frame.
	for guard in mission._hostiles:
		if is_instance_valid(guard) and guard.state != NPC.State.DEAD:
			await _shoot_at(guard)
		if _finished: return
	if not _gate("combat damaged and killed a mission combatant", _combat_kills > _run_kills_start): return
	if not _combat_shot_taken:
		await _shot("combat")
	_combat_shot_taken = false
	await _walk_to(world.locations["package"], 2.5, 25.0)
	await _tap("interact")
	if not _gate("package collected through interaction", mission.stage == Mission.Stage.TO_CAR and mission.package_taken): return
	await _shot("package_taken")

	var car := _nearest_parked_car()
	if not _gate("usable parked car found", car != null): return
	_boarding_target = car
	await _nav_to(car.global_position, 2.6, 80.0)
	await _interact_until(Game.MODE_CAR)
	if not _gate("car entered", Game.mode == Game.MODE_CAR and player.current_vehicle is Car): return
	await _shot("car_entered")
	# Street-life r1: the drive now obeys red lights and queues behind lane
	# traffic (held time is logged as "drive life ... held_s"), so the leg
	# budget is longer than the empty-street 160 s. M1: 300 s (five headless
	# routes took 93-202 s, held 28-111 s at signals and behind queues).
	await _drive_route(world.locations["helipad_primary"], 300.0)
	if not _gate("uninterrupted driving leg reached aviation compound", Game.mode == Game.MODE_CAR and mission.stage == Mission.Stage.TO_HELI and mission.car_driven_distance >= 80.0): return
	await _shot("driving")
	_release_all()
	await get_tree().create_timer(1.0).timeout
	await _interact_until(Game.MODE_FOOT)
	if not _gate("car exit restored walking", Game.mode == Game.MODE_FOOT): return
	await _shot("exited_car")

	var heli := main.get_node_or_null("Helicopter") as Helicopter
	if not _gate("helicopter remains usable", heli != null and not heli.disabled): return
	_boarding_target = heli
	await _walk_to(heli.global_position + Vector3(3.0, 0.0, 0.0), 1.4, 40.0)
	await _interact_until(Game.MODE_HELI)
	if not _gate("helicopter boarded", Game.mode == Game.MODE_HELI and mission.stage == Mission.Stage.FLY): return
	await _shot("helicopter_boarding")
	await _fly_to(world.locations["helipad_secondary"], 120.0)
	if not _gate("flight reached waterfront pad airspace", Game.mode == Game.MODE_HELI and _ground_distance(heli.global_position, world.locations["helipad_secondary"]) < 15.0): return
	await _shot("aerial_view")
	await _land(world.locations["helipad_secondary"], 50.0)
	# The aircraft reports touchdown in its own physics step, which runs after
	# the mission's step in tree order; give the mission its next tick(s) to
	# observe the landing before gating (wave-5 run route1 failed on this race).
	await _await_stage(Mission.Stage.LAND, 1.0)
	if not _gate("helicopter landed intact on destination pad", heli.is_landed() and not heli.disabled and mission.stage == Mission.Stage.LAND): return
	await _interact_until(Game.MODE_FOOT)
	await _await_stage(Mission.Stage.DELIVER, 1.0)
	if not _gate("landing exit restored walking", Game.mode == Game.MODE_FOOT and mission.stage == Mission.Stage.DELIVER): return
	await _shot("landed")
	await _walk_to(world.locations["delivery"], 3.0, 45.0)
	await _tap("interact")
	if not _gate("mission completed through delivery interaction", mission.stage == Mission.Stage.DONE and Game.death_count == _initial_deaths): return
	await _shot("delivery")
	await _route_succeeded()

func _route_succeeded() -> void:
	if _finished: return
	_completed_runs.append({"run": _run_index, "started_seconds": _run_started, "finished_seconds": _elapsed(),
		"duration_seconds": _elapsed() - _run_started, "uninterrupted": Game.death_count == _initial_deaths,
		"combat_kills": _combat_kills - _run_kills_start, "car_distance_m": mission.car_driven_distance,
		"flight_distance_m": mission.flight_distance, "gates": _gates.slice(_run_gate_start)})
	_log("Verified mission completions: %d" % _completed_runs.size())
	if not _soak_enabled:
		if _record_log and not _record_capped:
			_release_all()
			var hold_started := _elapsed()
			var first_hold_frame := _record_index
			_completion_recording_hold = {"requested": true, "started_seconds": hold_started,
				"elapsed_seconds": 0.0, "frames_written": 0}
			_log("Holding completed mission visible for 0.5 seconds of continuous recording.")
			await get_tree().create_timer(0.5, true, false, true).timeout
			if _finished: return
			_completion_recording_hold = {"requested": true, "started_seconds": hold_started,
				"ended_seconds": _elapsed(), "elapsed_seconds": _elapsed() - hold_started,
				"frames_written": _record_index - first_hold_frame}
			if mission.stage != Mission.Stage.DONE or Game.death_count != _initial_deaths:
				_abort("Completed mission did not remain valid during the terminal recording hold.")
				return
		_finish(true)
		return
	if _completed_runs.size() < SOAK_REQUIRED_RUNS:
		_phase = "mission_restart"
		_release_all()
		_log("Restarting through the real Mission.restart for next independent mission attempt.")
		mission.restart()
		await get_tree().physics_frame
		await get_tree().physics_frame
		await _run()
		return
	await _soak_fixture_phase()
	if _finished: return
	await _soak_free_roam()

func _fixture_check(label: String, passed: bool) -> void:
	if _finished: return
	_fixture_checks.append({"name": label, "passed": passed, "phase": "fixture_assisted", "seconds": _elapsed()})
	_log("FIXTURE %s %s (excluded from mission completion count)" % ["PASS" if passed else "FAIL", label])

func _soak_fixture_phase() -> void:
	_phase = "fixture_assisted"
	_release_all()
	_log("Beginning explicit fixture-assisted negative cases. Three completion records are already sealed.")
	Events.notify.emit("QA fixture checks — excluded from mission completion count.", "info")
	var saved_position := player.global_position
	var saved_yaw := player.yaw
	var saved_checkpoint := Game.checkpoint_index
	var saved_safe_position := Game.last_safe_position
	var saved_safe_rotation := Game.last_safe_rotation
	Game.simulation_paused = true
	var paused_position := player.global_position
	var paused_car_position := traffic.cars[0].global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(0.4, true, false, true).timeout
	if _finished: return
	Input.action_release("move_forward")
	_fixture_check("pause freezes player and live traffic", player.global_position.distance_to(paused_position) < 0.001 and traffic.cars[0].global_position.distance_to(paused_car_position) < 0.001)
	Game.simulation_paused = false
	# Keep the fixture beside the task-owned save when one was supplied.
	var save_dir := String(Game.get("_save_path")).get_base_dir()
	var fixture_path := ("%s/orchard_soak_%d.json" % [save_dir, OS.get_process_id()]) if save_dir.begins_with("/") else "/tmp/orchard_soak_%d.json" % OS.get_process_id()
	var saved := Game.save_game(fixture_path)
	_fixture_check("completed-run checkpoint writes through atomic save path", saved)
	if saved:
		var invalid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		invalid["player_position"] = [1.0]
		var file := FileAccess.open(fixture_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(invalid))
		file.close()
		var previous_health := Game.health
		var previous_stage := mission.stage
		var loaded := Game.load_game(fixture_path)
		_fixture_check("malformed checkpoint is rejected without state mutation", not loaded and Game.health == previous_health and mission.stage == previous_stage and player.global_position == saved_position)
		DirAccess.remove_absolute(fixture_path)
	# Explicit test-only relocation. It cannot increment _completed_runs:
	# only the actual route's final interaction calls _route_succeeded.
	mission._set_stage(Mission.Stage.TO_AIRFIELD, false)
	player.respawn_at(world.locations["helipad_primary"] + Vector3(3.6, 0.6, 0.0), 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	if _finished: return
	_fixture_check("walking to airfield cannot satisfy drive stage", mission.stage == Mission.Stage.TO_AIRFIELD)
	mission.restore_stage(Mission.Stage.DONE)
	Game.checkpoint_index = saved_checkpoint
	Game.mark_safe_position(saved_safe_position, saved_safe_rotation)
	player.respawn_at(saved_position, saved_yaw)
	await get_tree().physics_frame
	await _shot("fixture_phase_finished")
	for result in _fixture_checks:
		if not result["passed"]:
			_abort("A separately labelled soak fixture failed.")
			return
	_log("Fixture phase complete; starting genuine mixed free roam from the restored completion location.")
	Events.notify.emit("QA free roam — three mission runs verified.", "info")

func _soak_free_roam() -> void:
	_phase = "free_roam"
	_free_last_actor = null
	var activity := 0
	while not _finished and not _final_recovery_requested:
		if player.current_vehicle is Helicopter and not player.current_vehicle.is_landed():
			var current_heli := player.current_vehicle as Helicopter
			var nearest_pad: Vector3 = _nearest_pad(current_heli.global_position)
			await _fly_to(nearest_pad, 90.0)
			if _final_recovery_requested: break
			await _land(nearest_pad, 60.0)
			if _final_recovery_requested: break
			if not current_heli.is_landed():
				_abort("Free-roam aircraft recovery failed to land.")
				return
		if Game.mode != Game.MODE_FOOT: await _interact_until(Game.MODE_FOOT)
		if _finished: return
		if _final_recovery_requested: break
		if Game.mode != Game.MODE_FOOT:
			_abort("Free-roam vehicle recovery could not restore on-foot control.")
			return
		match activity % 3:
			0:
				var start_node := _nearest_node(player.global_position)
				var neighbours := traffic._neighbours(start_node)
				var destination: Vector3 = world.traffic_nodes[neighbours[activity % neighbours.size()]]
				_log("Free-roam foot leg to " + str(destination.round()))
				await _nav_to(destination, 7.0, 100.0)
			1:
				var car := _nearest_parked_car()
				if car != null:
					_boarding_target = car
					await _nav_to(car.global_position, 2.5, 130.0)
					if _final_recovery_requested: break
					await _interact_until(Game.MODE_CAR)
					if Game.mode == Game.MODE_CAR:
						var current := _nearest_node(car.global_position)
						var destination: Vector3 = world.traffic_nodes[(current + 7) % world.traffic_nodes.size()]
						_log("Free-roam driving leg to " + str(destination.round()))
						await _drive_route(destination, 130.0)
						if _final_recovery_requested: break
						if _ground_distance(car.global_position, destination) > 18.0:
							_abort("Free-roam car failed its destination gate.")
							return
						_free_roam_events.append({"event": "car_destination_reached", "seconds": _elapsed(), "passed": true})
						await _verify_reboard_cycle(car)
			2:
				var heli := main.get_node_or_null("Helicopter") as Helicopter
				if heli != null and not heli.disabled:
					_boarding_target = heli
					await _nav_to(heli.global_position + heli.global_transform.basis.x * 3.0, 1.2, 180.0)
					if _final_recovery_requested: break
					await _interact_until(Game.MODE_HELI)
					if Game.mode == Game.MODE_HELI:
						var destination: Vector3 = world.locations["helipad_primary"] if _ground_distance(heli.global_position, world.locations["helipad_primary"]) > 100.0 else world.locations["helipad_secondary"]
						_log("Free-roam aircraft leg to " + str(destination.round()))
						await _fly_to(destination, 100.0)
						if _final_recovery_requested: break
						if _ground_distance(heli.global_position, destination) >= 15.0:
							_abort("Free-roam aircraft failed to reach its destination.")
							return
						await _land(destination, 60.0)
						if _final_recovery_requested: break
						if not heli.is_landed() or heli.disabled:
							_abort("Free-roam aircraft failed its landing gate.")
							return
						await _interact_until(Game.MODE_FOOT)
						if Game.mode != Game.MODE_FOOT:
							_abort("Free-roam aircraft exit failed.")
							return
						_aircraft_cycle_verified = true
						_free_roam_events.append({"event": "aircraft_flight_landing_exit", "seconds": _elapsed(), "passed": true})
		activity += 1
		await get_tree().create_timer(0.3).timeout
	if not _finished: await _soak_final_recovery()

func _verify_reboard_cycle(car: Car) -> void:
	if _finished or car == null or car.disabled: return
	_release_all()
	await get_tree().create_timer(0.7).timeout
	await _interact_until(Game.MODE_FOOT)
	if _finished: return
	var exited := Game.mode == Game.MODE_FOOT and player.current_vehicle == null
	if not exited:
		_abort("Free-roam car exit failed.")
		return
	_boarding_target = car
	# Interaction takes the nearest vehicle, so at a busy junction a passing car
	# can be nearer than our own (wave 5 soak6: the automation carjacked passing
	# traffic). Like a player, wait until our car is the interaction target.
	# Try each door side and end of our car in turn (a car stopped at a signal
	# beside one door stays nearer for a whole cycle; soak7 at 1590 s).
	var approaches: Array[Vector3] = [car.global_transform.basis.x * 1.9, car.global_transform.basis.x * -1.9,
		car.global_transform.basis.z * -3.0, car.global_transform.basis.z * 3.0]
	for approach in approaches:
		if _finished or player._interaction_target() == car: break
		await _walk_to(car.global_position + approach, 0.6, 5.0)
		var settle_until := _elapsed() + 1.5
		while not _finished and _elapsed() < settle_until and player._interaction_target() != car:
			await get_tree().physics_frame
	await _interact_until(Game.MODE_CAR)
	var same_car := player.current_vehicle == car
	await _interact_until(Game.MODE_FOOT)
	var returned := same_car and Game.mode == Game.MODE_FOOT and player.current_vehicle == null and player.camera.current and not player.busy
	_reboard_cycle_verified = _reboard_cycle_verified or returned
	_free_roam_events.append({"event": "car_exit_same_car_reboard_exit", "seconds": _elapsed(), "passed": returned})
	_log("Free-roam same-car return/exit/reboard/exit cycle=%s" % returned)
	if not returned: _abort("Free-roam same-car reboard ownership cycle failed.")

func _nearest_pad(position: Vector3) -> Vector3:
	return world.locations["helipad_primary"] if _ground_distance(position, world.locations["helipad_primary"]) < _ground_distance(position, world.locations["helipad_secondary"]) else world.locations["helipad_secondary"]

func _interrupt_free_action() -> bool:
	return _phase == "free_roam" and _final_recovery_requested

func _soak_final_recovery() -> void:
	_phase = "final_recovery"
	_release_all()
	_log("Reserved final recovery: return to healthy on-foot control, then demonstrate movement until the deadline.")
	if player.current_vehicle is Helicopter:
		var heli := player.current_vehicle as Helicopter
		if not heli.is_landed():
			var pad := _nearest_pad(heli.global_position)
			if _ground_distance(heli.global_position, pad) > 8.0: await _fly_to(pad, 75.0)
			await _land(pad, 60.0)
		if not heli.is_landed() or heli.disabled:
			_abort("Final aircraft recovery failed.")
			return
	if Game.mode != Game.MODE_FOOT: await _interact_until(Game.MODE_FOOT)
	if _finished: return
	if Game.mode != Game.MODE_FOOT or player.current_vehicle != null:
		_abort("Final control recovery failed to return to foot.")
		return
	if not _reboard_cycle_verified:
		var car := _nearest_parked_car()
		if car != null and _ground_distance(player.global_position, car.global_position) < 45.0:
			_boarding_target = car
			await _walk_to(car.global_position, 2.4, 20.0)
			await _interact_until(Game.MODE_CAR)
			if player.current_vehicle == car: await _verify_reboard_cycle(car)
	if _finished: return
	_phase = "final_observation"
	_final_observation_started = _elapsed()
	var anchor := player.global_position
	var direction := 1.0
	while not _finished:
		var target := anchor + Vector3(direction * 16.0, 0.0, direction * 4.0)
		target.x = clampf(target.x, -310.0, 310.0)
		target.z = clampf(target.z, -334.0, 310.0)
		await _walk_to(target, 1.8, 10.0)
		direction *= -1.0
		await get_tree().create_timer(0.2).timeout

func _terminal_liveness() -> Dictionary:
	var distance := 0.0
	for sample in _recent_foot_motion:
		if sample["seconds"] >= _elapsed() - 60.0: distance += sample["distance_m"]
	return {"foot_distance_last_60_seconds_m": distance, "seconds_since_foot_motion": _elapsed() - _last_foot_motion_seconds,
		"final_observation_seconds": _elapsed() - _final_observation_started if _final_observation_started >= 0.0 else 0.0,
		"healthy_on_foot": Game.health > 0.0 and player.alive and not player.busy and not Game.simulation_paused and Game.mode == Game.MODE_FOOT and player.current_vehicle == null and player.camera.current,
		"reboard_cycle_verified": _reboard_cycle_verified, "aircraft_cycle_verified": _aircraft_cycle_verified,
		"current_horizontal_speed_mps": Vector2(player.velocity.x, player.velocity.z).length()}

func _soak_complete() -> bool:
	if not _soak_enabled or _soak_seconds < SOAK_ACCEPTANCE_SECONDS or _elapsed() < SOAK_ACCEPTANCE_SECONDS: return false
	if _completed_runs.size() != SOAK_REQUIRED_RUNS or _phase != "final_observation": return false
	if _fixture_checks.size() < 4: return false
	for result in _fixture_checks:
		if not result["passed"]: return false
	if not (_free_distance["foot"] >= 100.0 and _free_distance["car"] >= 200.0 and _free_distance["helicopter"] >= 200.0): return false
	var terminal := _terminal_liveness()
	if not terminal["healthy_on_foot"] or not terminal["reboard_cycle_verified"] or not terminal["aircraft_cycle_verified"]: return false
	if terminal["final_observation_seconds"] < 30.0 or terminal["foot_distance_last_60_seconds_m"] < 15.0 or terminal["seconds_since_foot_motion"] > 1.0: return false
	_scan_runtime_log()
	return _runtime_log_scan["checked"] and _runtime_log_scan["fatal_errors"].is_empty()

func _resolve_engine_log_path() -> String:
	# Godot consumes recognized --log-file arguments before exposing its
	# command-line array. Carry an explicit QA copy after the -- separator.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-engine-log="):
			var supplied := arg.trim_prefix("--qa-engine-log=")
			if not supplied.is_empty(): return supplied
	var engine_args := OS.get_cmdline_args()
	for index in engine_args.size():
		if engine_args[index] == "--log-file" and index + 1 < engine_args.size(): return engine_args[index + 1]
		if engine_args[index].begins_with("--log-file="): return engine_args[index].trim_prefix("--log-file=")
	return ""

func _scan_runtime_log() -> void:
	if _engine_log_path.is_empty() or not FileAccess.file_exists(_engine_log_path):
		_runtime_log_scan = {"checked": false, "fatal_errors": [], "classified_nonfatal": [], "reason": "Explicit --qa-engine-log=ABS user argument is required for soak error verification."}
		return
	var content := FileAccess.get_file_as_string(_engine_log_path)
	if content.is_empty():
		_runtime_log_scan = {"checked": false, "fatal_errors": [], "classified_nonfatal": [], "reason": "QA engine log is empty or unreadable.", "path": _engine_log_path}
		return
	var fatal: Array[String] = []
	var known: Array[String] = []
	for line in content.split("\n"):
		if "ERROR:" not in line and "Parse Error:" not in line and "Failed to load script" not in line: continue
		if 'Condition "ret != noErr"' in line and "get_system_ca_certificates" in content:
			known.append(line)
		else:
			fatal.append(line)
	_runtime_log_scan = {"checked": true, "fatal_errors": fatal, "classified_nonfatal": known, "path": _engine_log_path, "seconds": _elapsed()}

func _initialize_monitors() -> void:
	var available := ClassDB.class_get_integer_constant_list("Performance")
	var wanted := {"object_count": "OBJECT_COUNT", "node_count": "OBJECT_NODE_COUNT", "orphan_node_count": "OBJECT_ORPHAN_NODE_COUNT",
		"resource_count": "OBJECT_RESOURCE_COUNT", "static_memory_bytes": "MEMORY_STATIC", "static_memory_peak_bytes": "MEMORY_STATIC_MAX",
		"render_video_memory_bytes": "RENDER_VIDEO_MEM_USED", "render_texture_memory_bytes": "RENDER_TEXTURE_MEM_USED",
		"render_buffer_memory_bytes": "RENDER_BUFFER_MEM_USED", "draw_calls": "RENDER_TOTAL_DRAW_CALLS_IN_FRAME", "fps": "TIME_FPS"}
	for key in wanted:
		if wanted[key] in available: _monitor_ids[key] = ClassDB.class_get_integer_constant("Performance", wanted[key])
		else: _monitor_unavailable.append(key)

func _performance_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for key in _monitor_ids:
		result[key] = null if _headless and (String(key).begins_with("render_") or key == "draw_calls") else Performance.get_monitor(_monitor_ids[key])
	return result

func _monitor_summary() -> Dictionary:
	var summary: Dictionary = {}
	for key in _monitor_ids:
		var values: Array[float] = []
		for sample in _samples:
			var value: Variant = sample.get("engine_monitors", {}).get(key)
			if value != null: values.append(float(value))
		if not values.is_empty():
			summary[key] = {"first": values[0], "last": values[-1], "min": values.min(), "max": values.max(), "samples": values.size()}
	return summary

func _tap(action: String) -> void:
	if _finished: return
	Input.action_press(action)
	await get_tree().create_timer(0.16).timeout
	Input.action_release(action)
	await get_tree().create_timer(0.16).timeout

func _interact_until(target_mode: int) -> void:
	for attempt in 3:
		if _finished or Game.mode == target_mode: return
		# Never press interact far from the requested vehicle (soak #8): the
		# nearest other car would be taken instead. Walk back beside it first.
		if Game.mode == Game.MODE_FOOT and target_mode != Game.MODE_FOOT and is_instance_valid(_boarding_target):
			var away := _ground_distance(player.global_position, _boarding_target.global_position)
			if away > 6.0:
				_log("interaction deferred: %s is %.1f m away" % [_boarding_target.name, away])
				var side := 1.0 if attempt % 2 == 0 else -1.0
				var reach := 3.0 if _boarding_target is Helicopter else 1.9
				await _walk_to(_boarding_target.global_position + _boarding_target.global_transform.basis.x * side * reach, 0.7, 30.0)
		await _tap("interact")
		if Game.mode == target_mode: return
		_log("interaction attempt %d: %s" % [attempt, _interaction_diagnostic()])
		if Game.mode == Game.MODE_FOOT and target_mode != Game.MODE_FOOT and is_instance_valid(_boarding_target):
			# Walk to an actual door side if another object occluded the first
			# approach. LOS stays enforced by normal interaction code.
			var side := 1.0 if attempt % 2 == 0 else -1.0
			var reach := 3.0 if _boarding_target is Helicopter else 1.9
			await _walk_to(_boarding_target.global_position + _boarding_target.global_transform.basis.x * side * reach, 0.7, 10.0)

func _interaction_diagnostic() -> String:
	var chosen: Node = player._interaction_target() if player.has_method("_interaction_target") else null
	var description := "mode=%d chosen=%s" % [Game.mode, chosen.name if chosen else "none"]
	if not is_instance_valid(_boarding_target): return description
	description += " requested=%s at=%s distance=%.2f" % [_boarding_target.name, _boarding_target.global_position, player.global_position.distance_to(_boarding_target.global_position)]
	var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.25, _boarding_target.global_position + Vector3.UP * 0.65)
	ray.collision_mask = 1 | 8
	var excluded: Array[RID] = [player.get_rid()]
	if _boarding_target is CollisionObject3D: excluded.append(_boarding_target.get_rid())
	ray.exclude = excluded
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var body: CollisionObject3D = hit["collider"]
		var shape_owner: Node3D = body.shape_owner_get_owner(body.shape_find_owner(hit["shape"]))
		description += " occluded_by=%s hit=%s shape_position=%s" % [body.name, hit["position"], shape_owner.global_position]
	else:
		description += " LOS=clear"
	return description

func _nearby_vehicles_diagnostic() -> String:
	var parts: PackedStringArray = []
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		var body := vehicle as Node3D
		if body == null: continue
		var gap := _ground_distance(player.global_position, body.global_position)
		if gap > 7.0: continue
		var state := ""
		if body is Car:
			var car := body as Car
			state = " ai=%s npc=%s player=%s speed=%.1f" % [car.has_ai, car.occupied_by_npc, car.driver_is_player, car.velocity.length()]
		parts.append("%s@%s %.1fm%s" % [body.name, body.global_position.snapped(Vector3.ONE * 0.1), gap, state])
	return "; ".join(parts) if not parts.is_empty() else "no vehicle within 7 m"

func _release_all() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func _ground_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _face_towards(target: Vector3) -> void:
	var direction := target - player.global_position
	player.yaw = atan2(-direction.x, -direction.z)

func _walk_to(target: Vector3, stop_distance: float, timeout: float) -> void:
	if _finished: return
	var deadline := _elapsed() + timeout
	var last_pos := player.global_position
	var stuck_for := 0.0
	var sidestep_for := 0.0
	var sidestep_sign := 1.0
	# Progress watchdog (soak #8): sliding along a car body never trips the
	# per-frame stuck test, so 12 s without gaining 0.5 m backs out, then
	# walks across the old line on alternating sides before resuming. Soak #9
	# showed a 2.5 s trigger interrupts sidesteps that clear walls on their own.
	var best_distance := _ground_distance(player.global_position, target)
	var best_at := _elapsed()
	var backout_for := 0.0
	var backouts := 0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	while _elapsed() < deadline and not _finished and not _interrupt_free_action() and Game.mode == Game.MODE_FOOT:
		await get_tree().physics_frame
		var distance := _ground_distance(player.global_position, target)
		if distance <= stop_distance: break
		var delta := get_physics_process_delta_time()
		_face_towards(target)
		if backout_for > 0.0:
			backout_for -= delta
			player.yaw += PI if backout_for > 1.2 + 0.3 * backouts else (1.0 if backouts % 2 == 1 else -1.0) * PI * 0.5
			if backout_for <= 0.0:
				best_distance = distance
				best_at = _elapsed()
			last_pos = player.global_position
			continue
		if distance < best_distance - 0.5:
			best_distance = distance
			best_at = _elapsed()
		elif _elapsed() - best_at > 12.0:
			backouts += 1
			backout_for = 0.8 + 1.2 + 0.3 * backouts
			Input.action_release("jump")
			_log("walk stalled %.1f m from target at %s; backing out (%d): %s" % [distance, player.global_position.snapped(Vector3.ONE * 0.1), backouts, _nearby_vehicles_diagnostic()])
			continue
		if sidestep_for > 0.0:
			sidestep_for -= delta
			player.yaw += sidestep_sign * 1.2
		if player.global_position.distance_to(last_pos) < 0.015:
			stuck_for += delta
		else:
			stuck_for = 0.0
		if stuck_for > 0.8:
			sidestep_for = 0.8
			sidestep_sign *= -1.0
			stuck_for = 0.0
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		last_pos = player.global_position
	_release_all()
	_log("walk end at %s; target=%s distance=%.1f" % [player.global_position.round(), target.round(), _ground_distance(player.global_position, target)])

func _nearest_node(position: Vector3) -> int:
	var best := 0
	var distance := INF
	for index in world.traffic_nodes.size():
		var current := _ground_distance(position, world.traffic_nodes[index])
		if current < distance:
			distance = current
			best = index
	return best

func _grid_path(from_index: int, to_index: int) -> Array[int]:
	var row := from_index / 5
	var column := from_index % 5
	var target_row := to_index / 5
	var target_column := to_index % 5
	var route: Array[int] = [from_index]
	while column != target_column:
		column += signi(target_column - column)
		route.append(row * 5 + column)
	while row != target_row:
		row += signi(target_row - row)
		route.append(row * 5 + column)
	return route

func _nav_to(target: Vector3, distance: float, timeout: float) -> void:
	if _ground_distance(player.global_position, target) < 100.0:
		await _walk_to(target, distance, timeout)
		return
	var deadline := _elapsed() + timeout
	for index in _grid_path(_nearest_node(player.global_position), _nearest_node(target)):
		if _finished or _interrupt_free_action() or _elapsed() >= deadline: return
		await _walk_to(world.traffic_nodes[index], 7.0, minf(40.0, deadline - _elapsed()))
	await _walk_to(target, distance, maxf(1.0, deadline - _elapsed()))

func _nearest_parked_car() -> Car:
	var best: Car = null
	var distance := INF
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if not vehicle is Car or vehicle.disabled or vehicle.has_ai or vehicle.driver_is_player: continue
		if vehicle.get_meta("courtyard_only", false): continue
		var candidate := _ground_distance(player.global_position, vehicle.global_position)
		if candidate < distance:
			distance = candidate
			best = vehicle
	return best

## Combat piece: the gate's combat frame is taken on the frame of the final
## kill shot (muzzle flash, tracer, impact, falling guard) rather than after
## the gun is lowered. Same player camera; only the moment changes.
var _combat_shot_taken := false
func _maybe_combat_shot(victim: NPC) -> void:
	if _phase != "mission" or _combat_shot_taken or mission == null:
		return
	# The first kill whose victim is in clear view of the player camera (a
	# guard hidden behind a stall reads as nothing); otherwise the last kill.
	var alive := 0
	for guard in mission._hostiles:
		if is_instance_valid(guard) and guard.state != NPC.State.DEAD:
			alive += 1
	var cam: Camera3D = player.camera
	var visible_victim := true
	for h in [1.2, 1.6]:
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, victim.global_position + Vector3.UP * h)
		q.collision_mask = 1 | 8
		if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			visible_victim = false
	if not visible_victim and alive > 0:
		return
	_combat_shot_taken = true
	await _shot("combat")

func _shoot_at(hostile: NPC) -> void:
	Input.action_press("aim")
	for shot in 8:
		if _finished or not is_instance_valid(hostile) or hostile.state == NPC.State.DEAD: break
		if Game.current_mag() == 0:
			await _tap("reload")
			await get_tree().create_timer(1.7).timeout
		var aiming_until := _elapsed() + 0.22
		while _elapsed() < aiming_until and not _finished:
			await get_tree().physics_frame
			var direction := (hostile.global_position + Vector3(0.0, 1.15, 0.0)) - player.camera.global_position
			player.yaw = atan2(-direction.x, -direction.z)
			player.pitch = clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), -1.25, 0.85)
		await _tap("fire")
	Input.action_release("aim")
	player.pitch = -0.12
	_log("combat target health=%.1f state=%d" % [hostile.health, hostile.state])

## Per-frame life counter for the driving acceptance check (driving C2):
## moving AI cars (>= 10 km/h) within 80 m of the player, and live pedestrians
## within 40 m of the camera.
func _life_counts() -> Dictionary:
	var origin := Game.player_position
	var moving := 0
	var ahead := 0
	var fwd := Vector3.ZERO
	if player.current_vehicle is Car:
		fwd = -(player.current_vehicle as Node3D).global_transform.basis.z
	for v in get_tree().get_nodes_in_group("vehicles"):
		if not v is Car or v.driver_is_player: continue
		var c := v as Car
		if absf(c.speed_kmh()) < 10.0 or c.global_position.distance_to(origin) > 80.0: continue
		moving += 1
		var rel := c.global_position - origin
		if fwd != Vector3.ZERO and rel.dot(fwd) > 0.0 and (-c.global_transform.basis.z).dot(fwd) > 0.7: ahead += 1
	# Street-life D: the lane traffic stream (AmbientVehicle) is traffic too.
	for v in get_tree().get_nodes_in_group("ambient_vehicles"):
		var av := v as AmbientVehicle
		if av == null or not av.active or av.speed < 2.78 or av.global_position.distance_to(origin) > 80.0: continue
		moving += 1
		var rel2 := av.global_position - origin
		if fwd != Vector3.ZERO and rel2.dot(fwd) > 0.0 and (-av.global_transform.basis.z).dot(fwd) > 0.7: ahead += 1
	var peds := 0
	var cam := get_viewport().get_camera_3d()
	for n in get_tree().get_nodes_in_group("npcs"):
		if n is Node3D and cam != null and (n as Node3D).global_position.distance_to(cam.global_position) < 40.0 and not cam.is_position_behind((n as Node3D).global_position):
			peds += 1
	return {"traffic_moving_within_80m": moving, "traffic_ahead_same_dir": ahead, "peds_visible": peds}

func _drive_route(target: Vector3, timeout: float) -> void:
	if not player.current_vehicle is Car: return
	var deadline := _elapsed() + timeout
	var route := _grid_path(_nearest_node(player.current_vehicle.global_position), _nearest_node(target))
	if route.size() >= 2:
		var car_pos: Vector3 = (player.current_vehicle as Node3D).global_position
		var p0 := world.traffic_nodes[route[0]]
		var p1 := world.traffic_nodes[route[1]]
		var to_p0 := Vector2(p0.x - car_pos.x, p0.z - car_pos.z)
		var seg := Vector2(p1.x - p0.x, p1.z - p0.z)
		if to_p0.length() > 4.0 and seg.length() > 4.0 and to_p0.normalized().dot(seg.normalized()) < -0.35:
			route.remove_at(0)
	# driving C2: keep left like real traffic. Each junction is driven as a lane
	# entry point before the mouth and a lane exit point after it, so the car
	# never runs down the planted median (critic C1: drove through the ferns).
	var nodes: Array[Vector3] = []
	for index in route: nodes.append(world.traffic_nodes[index])
	var start := (player.current_vehicle as Node3D).global_position
	var mouth := WorldBuilder.ROAD_HALF + 3.0
	for k in nodes.size():
		var node := nodes[k]
		var from := start if k == 0 else nodes[k - 1]
		var dir_in := Vector3(node.x - from.x, 0.0, node.z - from.z)
		var targets: Array[Vector3] = []
		if dir_in.length() > mouth + 4.0:
			dir_in = dir_in.normalized()
			targets.append(node - dir_in * mouth + Vector3.UP.cross(dir_in).normalized() * DRIVE_LANE)
		if k + 1 < nodes.size():
			var dir_out := Vector3(nodes[k + 1].x - node.x, 0.0, nodes[k + 1].z - node.z).normalized()
			var left_out := Vector3.UP.cross(dir_out).normalized()
			# A turn goes through the point where the two lane lines cross, so
			# the car follows the lane round the corner instead of cutting the
			# kerb (left turn) or the median nose (right turn).
			var exit_point := node + dir_out * mouth + left_out * DRIVE_LANE
			if not targets.is_empty() and absf(dir_in.dot(dir_out)) < 0.5:
				# r1 street-life: follow the turn as a curve (quadratic Bezier
				# with the lane-line crossing as control point). Driving to the
				# crossing point and then turning swung the near-side turn wide
				# into the oncoming lanes, head-on into queued lane traffic.
				var corner := node + (Vector3.UP.cross(dir_in).normalized() + left_out) * DRIVE_LANE
				# M2: the car understeers out of the turn along dir_in; aim the
				# arc's end that much short so it lands in its lane, not on the
				# median nose (headless M2 debug: exited 1.5 m wide and hit it).
				exit_point -= dir_in * 0.7
				corner -= dir_in * 0.35
				var entry: Vector3 = targets[targets.size() - 1]
				_approach_points[entry] = true
				for t in [0.3, 0.55, 0.8]:
					targets.append(entry.lerp(corner, t).lerp(corner.lerp(exit_point, t), t))
					_arc_points[targets[targets.size() - 1]] = true
				_arc_points[exit_point] = true
				targets.append(exit_point)
				# Settle back on the lane line before speeding up.
				exit_point = node + dir_out * (mouth + 9.0) + left_out * DRIVE_LANE
				_arc_points[exit_point] = true
			targets.append(exit_point)
		elif targets.is_empty():
			targets.append(node)
		for t in targets:
			if _finished or _interrupt_free_action() or _elapsed() >= deadline: return
			_turn_cap = 5.0 if _arc_points.has(t) else 0.0
			_approach_slow = _approach_points.has(t)
			await _drive_to(t, 2.5 if _arc_points.has(t) or _approach_points.has(t) else 5.0, minf(35.0, deadline - _elapsed()))
			_turn_cap = 0.0
			if mission.stage == Mission.Stage.TO_HELI:
				_log_drive_life()
				return
	await _drive_to(target, 48.0, maxf(1.0, deadline - _elapsed()))
	_log_drive_life()

func _log_drive_life() -> void:
	_log("drive life: samples=%d moving_within_80m=%.0f%% same_dir_ahead=%.0f%% min_car_health=%.0f held_s=%.1f bypass_s=%.1f" % [
		_drive_life["samples"], 100.0 * _drive_life["moving"] / maxf(1.0, _drive_life["samples"]),
		100.0 * _drive_life["ahead"] / maxf(1.0, _drive_life["samples"]), _drive_life["min_health"], _drive_life["held"], _drive_life["bypass"]])
	var parts: Array[String] = []
	for k in _hold_why:
		parts.append("%s=%.1f" % [k, _hold_why[k]])
	_log("drive slow (<6 m/s allowed) by reason: " + ", ".join(parts))

var _arc_points := {}
var _approach_points := {}
var _approach_slow := false
var _turn_cap := 0.0

## Street-life D: once-a-second traffic sample along the scripted drive, so a
## headless route also reports how often moving traffic shares the road.
var _drive_life := {"samples": 0, "moving": 0, "ahead": 0, "min_health": 100.0, "held": 0.0, "bypass": 0.0, "next": 0.0}
func _sample_drive_life(car: Car, bypassing: bool) -> void:
	var dt := get_physics_process_delta_time()
	_drive_life["min_health"] = minf(float(_drive_life["min_health"]), car.health)
	if _held_for > 0.0: _drive_life["held"] = float(_drive_life["held"]) + dt
	if bypassing: _drive_life["bypass"] = float(_drive_life["bypass"]) + dt
	if _elapsed() < float(_drive_life["next"]): return
	_drive_life["next"] = _elapsed() + 1.0
	var life := _life_counts()
	_drive_life["samples"] = int(_drive_life["samples"]) + 1
	if int(life["traffic_moving_within_80m"]) > 0: _drive_life["moving"] = int(_drive_life["moving"]) + 1
	if int(life["traffic_ahead_same_dir"]) > 0: _drive_life["ahead"] = int(_drive_life["ahead"]) + 1

## Street-life D: the scripted car keeps to the ambient traffic's offside
## (median) lane centre, AmbientTraffic.LANE_OFFSETS[1], so lane traffic flows
## past it in the kerb lane instead of meeting a car that straddles both.
const DRIVE_LANE := 2.3

var _reverse_side := -1.0

func _drive_to(target: Vector3, stop_distance: float, timeout: float) -> void:
	var deadline := _elapsed() + timeout
	var stuck_for := 0.0
	var previous := player.controlled_actor().global_position
	# integ-Q (rendered route stalled 140 s at the (-156,156) corner, boxed in
	# by two pursuing police cars that kept nudging it, so the per-frame
	# stillness test never fired): also back out when the distance to the
	# waypoint has not improved by 0.5 m for 3 s.
	var best := INF
	var best_t := _elapsed()
	var force_back := false
	while _elapsed() < deadline and not _finished and not _interrupt_free_action() and player.current_vehicle is Car:
		await get_tree().physics_frame
		var car := player.current_vehicle as Car
		if car.disabled: break
		if mission.stage == Mission.Stage.TO_HELI: break
		var offset := target - car.global_position
		offset.y = 0.0
		if offset.length() < stop_distance: break
		if offset.length() < best - 0.5:
			best = offset.length()
			best_t = _elapsed()
		elif _held_for > 0.0:
			best_t = _elapsed()   # street-life: holding behind traffic or at a red light is not a stall
		elif _elapsed() - best_t > 3.0:
			var near_desc: Array[String] = []
			for g in ["ambient_vehicles", "vehicles", "npcs"]:
				for n in get_tree().get_nodes_in_group(g):
					if n != car and n is Node3D and (n as Node3D).visible and (n as Node3D).global_position.distance_to(car.global_position) < 7.0:
						near_desc.append("%s%s" % [g.left(3), str((n as Node3D).global_position.round())])
			_log("drive no progress for 3 s at %s yaw=%.0f, backing out; near=%s" % [car.global_position.round(), rad_to_deg(car.rotation.y), near_desc])
			force_back = true
			best_t = _elapsed() + 1.2
			best = INF
		var forward := -car.global_transform.basis.z
		var direction := offset.normalized()
		var avoidance := _avoid_car_direction(car, forward)
		# Street-life D: drive with the ambient traffic like a player would,
		# following the car ahead, stopping at red lights and only steering
		# round a vehicle that has been standing still in front for a while.
		var lead := _traffic_lead(car, forward)
		var red_line := _red_light_line(car, forward)
		var safe := 99.0
		if lead["gap"] < INF:
			var lead_speed := maxf(0.0, float(lead["speed"]))
			safe = lead_speed + maxf(0.0, float(lead["gap"]) - 4.0) * 0.8
			if float(lead["gap"]) < 3.0: safe = minf(safe, lead_speed * 0.5)
		if red_line < INF:
			safe = minf(safe, sqrt(2.0 * 3.5 * maxf(0.0, red_line - 1.0)))
		# r1 street-life: give way to a lane car whose path crosses ours in the
		# next 1.6 s (a left turn out of the median lane across a kerb-lane car
		# going straight on spun the car round in a headless run).
		var conflict := _crossing_conflict(car, forward)
		if conflict:
			safe = 0.0
		if safe < 6.0:
			# Where the slow time goes (headless tuning): per-reason seconds.
			var why := "crossing" if conflict else ("red" if red_line < INF and sqrt(2.0 * 3.5 * maxf(0.0, red_line - 1.0)) <= safe + 0.01 else ("person" if lead["node"] is NPC else ("car" if lead["node"] != null else "other")))
			_hold_why[why] = float(_hold_why.get(why, 0.0)) + get_physics_process_delta_time()
		if safe < 1.0:
			_held_for += get_physics_process_delta_time()
			if _held_for > 3.0 and _elapsed() > _held_log_next:
				_held_log_next = _elapsed() + 3.0
				var ln: Node3D = lead["node"]
				_log("drive held %.1fs at %s: lead=%s gap=%.1f lead_speed=%.1f red_line=%.1f" % [_held_for, car.global_position.round(),
					(ln.name + ("(ambient e%d l%d idle%.0f obst=%s)" % [ln.edge, ln.lane, ln.idle_time, ln.obstacle_node.name if ln.obstacle_node else "-"] if ln is AmbientVehicle else "")) if ln else "-",
					float(lead["gap"]), float(lead["speed"]), red_line])
				if ln is AmbientVehicle and traffic.ambient != null: _log("  chain: " + traffic.ambient.chain_desc(ln))
		else:
			_held_for = 0.0
		var bypass: bool = _held_for > 5.0 and red_line == INF and lead["gap"] < INF and absf(float(lead["speed"])) < 0.4
		if _held_for > 25.0:
			bypass = true   # never wait for ever (a signal or a stuck queue)
		if bypass and lead["node"] != null:
			var rel: Vector3 = (lead["node"] as Node3D).global_position - car.global_position
			var lft := Vector3.UP.cross(forward).normalized()
			var side := -1.0 if rel.dot(lft) >= 0.0 else 1.0
			avoidance = (forward * maxf(4.0, float(lead["gap"]) * 0.75 + 3.0) + lft * side * 3.2).normalized()
			safe = 4.0
		elif bypass:
			safe = 4.0
		if avoidance != Vector3.ZERO:
			direction = avoidance
		var angle := atan2(forward.z * direction.x - forward.x * direction.z, forward.dot(direction))
		Input.action_release("move_left")
		Input.action_release("move_right")
		if absf(angle) > 0.025:
			Input.action_press("move_left" if angle > 0.0 else "move_right", clampf(absf(angle) * 1.8, 0.15, 1.0))
		# M2: pass-through waypoints (lane points before and after a straight
		# junction) are driven through at speed; only turns slow the car.
		# Only once lined up: full throttle while still yawed out of a turn
		# spun the car (headless M2 runs).
		var floor_v := 11.0 if not (_turn_cap > 0.0 or _approach_slow) and absf(angle) < 0.25 else 5.0
		var desired_speed := clampf(offset.length() * 0.8, floor_v, 21.0)
		if absf(angle) > 0.3 and car.forward_speed() < 9.0: desired_speed = minf(desired_speed, 7.0)
		if absf(angle) > 0.4: desired_speed = minf(desired_speed, 6.0)
		if _turn_cap > 0.0: desired_speed = minf(desired_speed, _turn_cap)
		if _approach_slow and offset.length() < 20.0: desired_speed = minf(desired_speed, 7.0)
		desired_speed = minf(desired_speed, safe)
		Input.action_release("move_forward")
		Input.action_release("move_back")
		if desired_speed < 0.6:
			# Hold: brake to a stand, never reverse into the queue behind.
			if car.forward_speed() > 0.5:
				Input.action_press("move_back")
		elif car.forward_speed() > desired_speed + 1.0:
			Input.action_press("move_back")
		else:
			Input.action_press("move_forward")
		if desired_speed < 0.6:
			stuck_for = 0.0   # waiting in traffic is not being stuck
		elif car.global_position.distance_to(previous) < 0.015:
			stuck_for += get_physics_process_delta_time()
		else:
			stuck_for = 0.0
		previous = car.global_position
		_sample_drive_life(car, bypass)
		if _drive_debug and car.global_position.x < -140.0 and car.global_position.z > 150.0 and car.global_position.z < 175.0:
			var cols: Array[String] = []
			for ci in car.get_slide_collision_count():
				var col := car.get_slide_collision(ci)
				cols.append("%s@%s n=%s" % [str(col.get_collider().name if col.get_collider() else "?"), str(col.get_position().round()), str(col.get_normal().snapped(Vector3.ONE * 0.1))])
			_log("dbg pos=%s yaw=%.0f v=%.1f ang=%.2f des=%.1f safe=%.1f fwd=%s back=%s cols=%s" % [car.global_position.snapped(Vector3.ONE * 0.1), rad_to_deg(car.rotation.y), car.forward_speed(), angle, desired_speed, safe,
				Input.is_action_pressed("move_forward"), Input.is_action_pressed("move_back"), cols])
		if stuck_for > 0.9 or force_back:
			force_back = false
			# Reverse and steer clear using the same inputs as a player; alternate
			# the steering side so a symmetric trap (a U-turn wedged between kerbs
			# and parked cars) cannot repeat the same failed manoeuvre (wave 5).
			_reverse_side = -_reverse_side
			Input.action_release("move_forward")
			Input.action_press("move_back")
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_right" if _reverse_side > 0.0 else "move_left")
			await get_tree().create_timer(1.2).timeout
			stuck_for = 0.0
	_release_all()
	var wc := player.controlled_actor()
	_log("drive waypoint target=%s distance=%.1f speed=%.1f yaw=%.0f" % [target.round(), _ground_distance(wc.global_position, target), (wc as Car).forward_speed() if wc is Car else 0.0, rad_to_deg(wc.rotation.y)])

var _held_for := 0.0
var _held_log_next := 0.0
var _hold_why := {}
var _drive_debug := "--drive-debug" in OS.get_cmdline_user_args()

func _crossing_conflict(car: Car, forward: Vector3) -> bool:
	if traffic == null or traffic.ambient == null: return false
	var my_speed := maxf(car.forward_speed(), 3.0)
	for v in traffic.ambient.vehicles:
		if not v.active or v.speed < 1.5: continue
		var rel := v.global_position - car.global_position
		rel.y = 0.0
		if rel.length() > 22.0 or rel.dot(forward) < -2.5: continue
		var vf := -v.global_transform.basis.z
		vf.y = 0.0
		vf = vf.normalized()
		# Same direction (our lane: _traffic_lead; the next lane: alongside, not
		# crossing). M2: lane cars running beside the car held it for 17 s.
		if vf.dot(forward) > 0.9: continue
		for t in [0.4, 0.8, 1.2, 1.6]:
			var a: Vector3 = car.global_position + forward * my_speed * t
			var b: Vector3 = v.global_position + vf * v.speed * t
			if Vector2(a.x - b.x, a.z - b.z).length() < 3.2: return true
	return false

## Street-life D driver perception: the nearest vehicle (physics car or
## ambient lane traffic) whose footprint overlaps this car's corridor ahead.
## Returns {gap (m, bumper to footprint), speed (m/s along our heading), node}.
func _traffic_lead(car: Car, forward: Vector3) -> Dictionary:
	var left := Vector3.UP.cross(forward).normalized()
	var best := {"gap": INF, "speed": 0.0, "node": null}
	var candidates: Array = get_tree().get_nodes_in_group("vehicles")
	candidates.append_array(get_tree().get_nodes_in_group("ambient_vehicles"))
	for other in candidates:
		if other == car or other is Helicopter or not other is Node3D: continue
		var node := other as Node3D
		if not node.visible: continue
		var half := Vector2(0.95, 2.35)
		var other_speed := 0.0
		if node is AmbientVehicle:
			var av := node as AmbientVehicle
			if not av.active: continue
			half = Vector2(av.dims.x * 0.5, av.dims.z * 0.5)
			other_speed = av.speed * (-node.global_transform.basis.z).dot(forward)
		elif node is Car:
			other_speed = (node as Car).velocity.dot(forward)
		else:
			continue
		var rel := node.global_position - car.global_position
		rel.y = 0.0
		var ahead := rel.dot(forward)
		if ahead < 0.0 or ahead > 45.0: continue
		var bx := node.global_transform.basis.x
		var bz := node.global_transform.basis.z
		var ext_lat := absf(Vector3(bx.x, 0, bx.z).normalized().dot(left)) * half.x + absf(Vector3(bz.x, 0, bz.z).normalized().dot(left)) * half.y
		var ext_fwd := absf(Vector3(bx.x, 0, bx.z).normalized().dot(forward)) * half.x + absf(Vector3(bz.x, 0, bz.z).normalized().dot(forward)) * half.y
		if absf(rel.dot(left)) > 0.85 + ext_lat: continue
		var gap := ahead - ext_fwd - 2.35
		if gap < -1.0: continue
		# r1: an oncoming car (waiting at its own stop line, or met mid-turn)
		# is not a car to follow; only an imminent one holds us.
		var heading := -node.global_transform.basis.z
		var hdot := Vector3(heading.x, 0, heading.z).normalized().dot(forward)
		if hdot < -0.3 and (gap > 3.0 or absf(other_speed) < 0.5): continue
		# M2: a car standing at its own stop line across our path is swept by
		# our heading mid-turn; it is not in the lane we are driving into.
		if absf(hdot) < 0.6 and absf(other_speed) < 0.5 and gap > 1.5: continue
		if gap < float(best["gap"]):
			best = {"gap": maxf(0.0, gap), "speed": other_speed, "node": node}
	# Street-life M1: give way to people in the car's path (a walker on the
	# side-road crossing during a left turn was struck, spun the car and sent
	# it off the road in two headless routes). A walker that keeps standing
	# in front of the held car steps aside, as lane traffic asks them to.
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NPC
		if npc == null or not npc.visible or npc.state == NPC.State.DEAD or npc.is_hostile:
			continue
		# M2: people on the pavement are not in the road (a turn sweeps the
		# corridor across the corner pavement and held the car there).
		if not _on_carriageway(npc.global_position):
			continue
		var rel := npc.global_position - car.global_position
		rel.y = 0.0
		var ahead := rel.dot(forward)
		if ahead < 0.0 or ahead > 14.0 or absf(rel.dot(left)) > 1.5:
			continue
		var gap := ahead - 2.35 - 0.4
		# Ask them to step clear early (as a slow car edging through a busy
		# crossing does), and only stop for someone right at the bumper, so
		# a turn through a crossing is not abandoned half way round.
		if gap < 9.0:
			npc.dodge_vehicle(car.global_position, forward)
		gap += 2.6
		if gap < float(best["gap"]):
			best = {"gap": maxf(0.0, gap), "speed": 0.0, "node": npc}
	return best

func _on_carriageway(p: Vector3) -> bool:
	for x in WorldBuilder.X_LINES:
		if absf(p.x - x) < WorldBuilder.ROAD_HALF:
			return true
	for z in WorldBuilder.Z_LINES:
		if absf(p.z - z) < WorldBuilder.ROAD_HALF:
			return true
	return absf(p.x) > 330.0 or absf(p.z) > 330.0

## Distance from the front bumper to a red stop line ahead (INF when the
## signal is green, no junction is near, or the car is already committed).
func _red_light_line(car: Car, forward: Vector3) -> float:
	if traffic == null: return INF
	var left := Vector3.UP.cross(forward).normalized()
	for node in world.traffic_nodes:
		var rel: Vector3 = node - car.global_position
		rel.y = 0.0
		var ahead := rel.dot(forward)
		if ahead < 8.0 or ahead > 60.0 or absf(rel.dot(left)) > 9.0: continue
		var line := ahead - 12.0 - 2.35
		if line < 0.5 and car.forward_speed() > 3.0: return INF   # committed
		if line < -1.0: return INF
		if traffic.signal_allows(forward):
			_red_wait = 0.0
			return INF
		# Street-life M2: drive like a player. Lane traffic gives way to a
		# player car approaching a junction (AmbientTraffic._player_in_junction),
		# so a red is only waited at while cross traffic is still moving
		# through the box. (M1 sat through every red behind queues: the drive
		# leg took 166 s against 39 s and police caught the stationary car.)
		if traffic.ambient != null and _cross_traffic_in_box(node, forward):
			return line
		_red_wait = 0.0
		return INF
	_red_wait = 0.0
	return INF

func _cross_traffic_in_box(node: Vector3, forward: Vector3) -> bool:
	for v in traffic.ambient.vehicles:
		if not v.active or v.speed < 1.0:
			continue
		var p := v.global_position
		if absf(p.x - node.x) > 13.0 or absf(p.z - node.z) > 13.0:
			continue
		var vf := -v.global_transform.basis.z
		vf.y = 0.0
		if absf(vf.normalized().dot(forward)) < 0.7:
			return true
	return false

const RED_PATIENCE := 6.0
var _red_wait := 0.0

## Driver perception for this automated playtest: steer around an actual
## nearby car using normal controls. The obstacle and vehicle are never moved.
func _avoid_car_direction(car: Car, forward: Vector3) -> Vector3:
	var left := Vector3.UP.cross(forward).normalized()
	var nearest := INF
	var obstacle: Node3D = null
	for other in get_tree().get_nodes_in_group("vehicles"):
		if other == car or other is Helicopter: continue
		# Street-life D: moving or AI-driven traffic is followed (_traffic_lead),
		# not swerved round; only parked or wrecked cars are steered past here.
		if other is Car and ((other as Car).has_ai or (other as Car).velocity.length() > 1.0): continue
		var offset: Vector3 = other.global_position - car.global_position
		var ahead := offset.dot(forward)
		var lateral := offset.dot(left)
		if ahead > 1.0 and ahead < 17.0 and absf(lateral) < 2.4 and ahead < nearest:
			nearest = ahead
			obstacle = other
	if obstacle == null: return Vector3.ZERO
	var relative := obstacle.global_position - car.global_position
	var side := -1.0 if relative.dot(left) >= 0.0 else 1.0
	return (forward * maxf(4.0, nearest * 0.75) + left * side * 5.0).normalized()

func _fly_to(target: Vector3, timeout: float) -> void:
	var deadline := _elapsed() + timeout
	while _elapsed() < deadline and not _finished and not _interrupt_free_action() and player.current_vehicle is Helicopter:
		await get_tree().physics_frame
		var heli := player.current_vehicle as Helicopter
		var offset := target - heli.global_position
		offset.y = 0.0
		if offset.length() < 6.0 and Vector2(heli.velocity.x, heli.velocity.z).length() < 2.0: break
		_steer_aircraft(heli, offset, 98.0)
		Input.action_release("jump")
		Input.action_release("sprint")
		if heli.global_position.y < 108.0:
			Input.action_press("jump", clampf((112.0 - heli.global_position.y) / 10.0, 0.0, 1.0))
		elif heli.global_position.y > 114.0:
			Input.action_press("sprint", 0.3)
	_release_all()

func _steer_aircraft(heli: Helicopter, offset: Vector3, minimum_altitude: float = 0.5) -> void:
	var direction := offset.normalized()
	var forward := -heli.global_transform.basis.z
	var angle := atan2(forward.z * direction.x - forward.x * direction.z, forward.dot(direction))
	Input.action_release("move_left")
	Input.action_release("move_right")
	if absf(angle) > 0.015:
		Input.action_press("move_left" if angle > 0.0 else "move_right", clampf(absf(angle) * 1.1, 0.05, 1.0))
	Input.action_release("move_forward")
	Input.action_release("move_back")
	# Climb clear of the district before translating; align before accelerating.
	if absf(angle) < 0.8 and heli.global_position.y > minimum_altitude and offset.length() > 2.0:
		Input.action_press("move_forward", clampf(offset.length() / 65.0, 0.0, 0.8) * maxf(0.0, cos(angle)))

## Wait (physics ticks only, no state writes) for the mission to reach `stage`.
func _await_stage(stage: int, seconds: float) -> void:
	var deadline := _elapsed() + seconds
	while mission.stage != stage and _elapsed() < deadline and not _finished:
		await get_tree().physics_frame

func _land(target: Vector3, timeout: float) -> void:
	var deadline := _elapsed() + timeout
	while _elapsed() < deadline and not _finished and not _interrupt_free_action() and player.current_vehicle is Helicopter:
		await get_tree().physics_frame
		var heli := player.current_vehicle as Helicopter
		if heli.is_landed(): break
		var offset := target - heli.global_position
		offset.y = 0.0
		_steer_aircraft(heli, offset)
		Input.action_release("jump")
		Input.action_release("sprint")
		if offset.length() < 10.0:
			Input.action_press("sprint", 1.0 if heli.global_position.y > 8.0 else 0.45)
	_release_all()

func _abort(reason: String) -> void:
	if _finished: return
	_failure = reason
	_log("ABORT " + reason)
	_finish(false)

func _write_checkpoint() -> void:
	var output := FileAccess.open("%s/route_progress.json" % out_dir, FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify({"elapsed_seconds": _elapsed(), "finished": _finished,
			"latest": _snapshot(_elapsed()), "gates": _gates, "completed_runs": _completed_runs.size(),
			"frame_stalls_recorded": _frame_stalls.size(), "frame_stall_overflow": _frame_stall_overflow,
			"fixture_checks": _fixture_checks, "free_roam_distance_m": _free_distance, "reboard_cycle_verified": _reboard_cycle_verified,
			"terminal_liveness": _terminal_liveness(), "runtime_log_scan": _runtime_log_scan, "recent_log": log_lines.slice(maxi(0, log_lines.size() - 8))}, "\t"))
		output.close()

func _percentile(sorted: Array[float], percentile: float) -> float:
	if sorted.is_empty(): return 0.0
	return sorted[clampi(int(ceil(percentile * sorted.size())) - 1, 0, sorted.size() - 1)]

func _frame_metrics(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += value
	return {"count": sorted.size(), "mean_ms": total / maxf(1.0, sorted.size()),
		"p50_ms": _percentile(sorted, 0.50), "p95_ms": _percentile(sorted, 0.95),
		"p99_ms": _percentile(sorted, 0.99), "max_ms": sorted[-1] if not sorted.is_empty() else 0.0}

func _finish(success: bool) -> void:
	if _finished: return
	_finished = true
	_release_all()
	if _frame_stall_log:
		_frame_stall_log.flush()
		_frame_stall_log.close()
		_frame_stall_log = null
	if _record_log:
		_record_log.flush()
		_record_log.close()
		_record_log = null
	var recording := {"requested": not _record_dir.is_empty(), "enabled": not _headless and not _record_dir.is_empty(), "directory": _record_dir,
		"requested_hz": 10, "frames_written": _record_index, "bytes_written": _record_bytes,
		"scheduled_samples": _record_requested_samples, "missed_samples": _record_dropped_samples,
		"capped": _record_capped, "cap_reason": _record_cap_reason,
		"max_frames": RECORD_MAX_FRAMES, "max_bytes": RECORD_MAX_BYTES,
		"max_duration_seconds": RECORD_MAX_SECONDS, "timestamps": "frames.jsonl monotonic seconds from route setup",
		"completion_hold": _completion_recording_hold,
		"readback_encode_cost_ms": _frame_metrics(_record_cost_ms)}
	if not _record_dir.is_empty():
		var record_summary := FileAccess.open(_record_dir.path_join("recording.json"), FileAccess.WRITE)
		if record_summary:
			record_summary.store_string(JSON.stringify(recording, "\t"))
			record_summary.close()
	var output := FileAccess.open("%s/capture_log.json" % out_dir, FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify({"schema": 2, "success": success, "failure_reason": _failure,
			"uninterrupted": success and not _soak_enabled and Game.death_count == _initial_deaths, "controls_only": not _soak_enabled,
			"mission_input_driver_controls_only": true,
			"automation_kind": "scripted input actions, direct mouse-look yaw/pitch, fractional action strengths",
			"native_human_run": false, "no_teleports_or_state_bypasses": not _soak_enabled and _continuity_breaks.is_empty(),
			"mission_input_driver_writes_transforms_or_health": false, "mission_continuity_breaks": _continuity_breaks,
			"headless": _headless, "rendered_timing_baseline": not _headless,
			"performance_acceptance_valid": false,
			"performance_caveats": ["Runtime timing baseline; exclusive machine/CPU/GPU conditions are not asserted by this script.", "JPEG/screenshot readback adds work; inclusive and unaffected interval summaries are separate.", "Human gameplay and target-frame-rate acceptance require their own review."],
			"run_mode": "soak" if _soak_enabled else "single_route", "soak_duration_contract_seconds": SOAK_ACCEPTANCE_SECONDS if _soak_enabled else 0,
			"configured_soak_timeout_seconds": _soak_seconds if _soak_enabled else 0,
			"required_mission_completions": SOAK_REQUIRED_RUNS if _soak_enabled else 1,
			"completed_mission_runs": _completed_runs, "fixture_assisted_checks": _fixture_checks,
			"free_roam_distance_m": _free_distance, "fixture_teleports_count_as_completion": false,
			"free_roam_events": _free_roam_events, "terminal_liveness": _terminal_liveness(), "runtime_log_scan": _runtime_log_scan,
			"requires_clean_supervisor_exit": true, "continuous_30_minute_video_claim": false,
			"evidence_coverage": "1Hz state/resource samples, per-gate screenshots and five-minute soak stills; optional JPEG sequence is independently capped at720s.",
			"engine_monitor_summary": _monitor_summary(), "unavailable_engine_monitors": _monitor_unavailable,
			"memory_leak_acceptance_valid": false, "memory_qualification": "Resource trends require review; process exit alone is not a leak verdict.",
			"finished_utc": Time.get_datetime_string_from_system(true), "elapsed_seconds": _elapsed(),
			"engine": Engine.get_version_info()["string"], "seed": Game.seed_value,
			"health": Game.health, "wanted_level": Game.wanted_level, "mission_stage": mission.stage,
			"mode": Game.mode, "deaths": Game.death_count - _initial_deaths, "combat_kills": _combat_kills,
			"peds": traffic.count_peds(), "traffic_cars": traffic.count_traffic(), "screenshots": _shots,
			"frame_times": _frame_metrics(_frames_ms),
			"frame_time_method": "Monotonic process-frame intervals; excludes intervals touched by screenshot/recording readback.",
			"frame_times_including_capture_overhead": _frame_metrics(_inclusive_frames_ms),
			"frame_stalls": {"threshold_ms_exclusive": FRAME_STALL_THRESHOLD_MS,
				"max_events": FRAME_STALL_MAX_EVENTS, "overflow_count": _frame_stall_overflow,
				"total_count": _frame_stalls.size() + _frame_stall_overflow,
				"event_log_path": out_dir.path_join("frame_stalls.jsonl"), "event_log_opened": _frame_stall_log_opened,
				"time_basis": "Monotonic seconds from capture setup; phase/run identify the interval end. Capture-overhead flags indicate readback overlap, not proven causation.",
				"events": _frame_stalls},
			"recording": recording,
			"gates": _gates, "samples": _samples, "log": log_lines}, "\t"))
		output.close()
	_write_checkpoint()
	print("[capture] terminal success=%s deaths=%d seconds=%.1f" % [success, Game.death_count - _initial_deaths, _elapsed()])
	Game.simulation_paused = true
	Sfx.shutdown_audio()
	_quit_after_audio(0 if success else 2)

func _quit_after_audio(exit_code: int) -> void:
	await get_tree().create_timer(0.15, true, false, true).timeout
	get_tree().quit(exit_code)
