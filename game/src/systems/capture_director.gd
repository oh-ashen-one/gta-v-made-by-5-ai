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
var _samples: Array[Dictionary] = []
var _gates: Array[Dictionary] = []
var _combat_kills := 0
var _boarding_target: Node3D
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
const RECORD_INTERVAL_US := 100000 # Requested 10Hz; timestamps are authoritative.
const RECORD_MAX_FRAMES := 7200
const RECORD_MAX_BYTES := 1024 * 1024 * 1024

func setup(m: Node, p: Player, w: WorldBuilder, mi: Mission, t: TrafficManager) -> void:
	main = m
	player = p
	world = w
	mission = mi
	traffic = t
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			out_dir = arg.trim_prefix("--capture-dir=")
		elif arg.begins_with("--record-frames="):
			_record_dir = arg.trim_prefix("--record-frames=")
	DirAccess.make_dir_recursive_absolute(out_dir)
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
			_combat_kills += 1)
	_run()

func _process(_delta: float) -> void:
	if _finished or player == null:
		return
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _started_us) / 1000000.0
	if _last_frame_us > 0:
		var frame_ms := float(now - _last_frame_us) / 1000.0
		_inclusive_frames_ms.append(frame_ms)
		if not _capture_in_progress and not _readback_since_frame and not _record_pending:
			_frames_ms.append(frame_ms)
	_last_frame_us = now
	_readback_since_frame = false
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
		_write_checkpoint()
	if Game.death_count != _initial_deaths:
		_abort("Player died/respawned; this attempt cannot certify an uninterrupted mission.")
	elif player.current_vehicle != null and player.current_vehicle.get("disabled"):
		_abort("Controlled vehicle disabled; transport leg failed.")
	elif elapsed >= ROUTE_TIMEOUT:
		_abort("Route exceeded %.0f-second wall-clock limit." % ROUTE_TIMEOUT)

func _snapshot(elapsed: float) -> Dictionary:
	var actor := player.controlled_actor()
	var pos := actor.global_position
	return {"seconds": snappedf(elapsed, 0.01), "position": [pos.x, pos.y, pos.z],
		"mode": Game.mode, "stage": mission.stage, "health": Game.health,
		"wanted": Game.wanted_level, "deaths": Game.death_count - _initial_deaths,
		"car_distance_m": mission.car_driven_distance, "flight_distance_m": mission.flight_distance,
		"vehicle_health": actor.get("health") if actor != player else null, "heading": actor.rotation.y}

func _log(message: String) -> void:
	log_lines.append("%.2fs %s" % [_elapsed(), message])
	print("[capture] ", log_lines[-1])

func _elapsed() -> float:
	return float(Time.get_ticks_usec() - _started_us) / 1000000.0

func _gate(label: String, condition: bool) -> bool:
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
	var capture_started := timestamp_us
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_record_dropped_samples += 1
		_record_pending = false
		return
	var filename := "frame_%06d.jpg" % _record_index
	var path := _record_dir.path_join(filename)
	var error := img.save_jpg(path, 0.8)
	var capture_cost := float(Time.get_ticks_usec() - capture_started) / 1000.0
	_record_cost_ms.append(capture_cost)
	_readback_since_frame = true
	if error != OK:
		_record_capped = true
		_record_cap_reason = "JPEG write failed (%d)" % error
	else:
		var written := FileAccess.open(path, FileAccess.READ)
		var byte_count := written.get_length() if written else 0
		if written: written.close()
		_record_bytes += byte_count
		_record_log.store_line(JSON.stringify({"sequence": _record_index, "file": filename,
			"timestamp_us": timestamp_us, "seconds": float(timestamp_us - _started_us) / 1000000.0,
			"width": img.get_width(), "height": img.get_height(), "readback_encode_ms": capture_cost,
			"state": _snapshot(float(timestamp_us - _started_us) / 1000000.0)}))
		_record_index += 1
		if _record_index % 10 == 0: _record_log.flush()
		if _record_index >= RECORD_MAX_FRAMES or _record_bytes >= RECORD_MAX_BYTES:
			_record_capped = true
			_record_cap_reason = "Recording frame/byte safety cap reached"
	_record_pending = false

func _run() -> void:
	await get_tree().create_timer(0.75).timeout
	_log("Route start; seed=%d; headless=%s; scripted-input-automation=true" % [Game.seed_value, _headless])
	await _shot("safe_room")
	if world.locations.has("safe_room_exit"):
		await _walk_to(world.locations["safe_room_exit"], 2.0, 25.0)
	await _nav_to(world.locations["package"], 4.0, 130.0)
	if not _gate("market reached on foot", _ground_distance(player.global_position, world.locations["package"]) < 8.0): return
	await _shot("hawker_market")

	# Actual damage-producing weapon input, with camera aim corrected each frame.
	for guard in mission._hostiles:
		if is_instance_valid(guard) and guard.state != NPC.State.DEAD:
			await _shoot_at(guard)
		if _finished: return
	if not _gate("combat damaged and killed a mission combatant", _combat_kills > 0): return
	await _shot("combat")
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
	await _drive_route(world.locations["helipad_primary"], 160.0)
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
	if not _gate("helicopter landed intact on destination pad", heli.is_landed() and not heli.disabled and mission.stage == Mission.Stage.LAND): return
	await _interact_until(Game.MODE_FOOT)
	if not _gate("landing exit restored walking", Game.mode == Game.MODE_FOOT and mission.stage == Mission.Stage.DELIVER): return
	await _shot("landed")
	await _walk_to(world.locations["delivery"], 3.0, 45.0)
	await _tap("interact")
	if not _gate("mission completed through delivery interaction", mission.stage == Mission.Stage.DONE and Game.death_count == _initial_deaths): return
	await _shot("delivery")
	_finish(true)

func _tap(action: String) -> void:
	if _finished: return
	Input.action_press(action)
	await get_tree().create_timer(0.16).timeout
	Input.action_release(action)
	await get_tree().create_timer(0.16).timeout

func _interact_until(target_mode: int) -> void:
	for attempt in 3:
		if _finished or Game.mode == target_mode: return
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
	Input.action_press("move_forward")
	Input.action_press("sprint")
	while _elapsed() < deadline and not _finished and Game.mode == Game.MODE_FOOT:
		await get_tree().physics_frame
		if _ground_distance(player.global_position, target) <= stop_distance: break
		var delta := get_physics_process_delta_time()
		_face_towards(target)
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
		if _finished or _elapsed() >= deadline: return
		await _walk_to(world.traffic_nodes[index], 7.0, minf(40.0, deadline - _elapsed()))
	await _walk_to(target, distance, maxf(1.0, deadline - _elapsed()))

func _nearest_parked_car() -> Car:
	var best: Car = null
	var distance := INF
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if not vehicle is Car or vehicle.disabled or vehicle.has_ai or vehicle.driver_is_player: continue
		var candidate := _ground_distance(player.global_position, vehicle.global_position)
		if candidate < distance:
			distance = candidate
			best = vehicle
	return best

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

func _drive_route(target: Vector3, timeout: float) -> void:
	if not player.current_vehicle is Car: return
	var deadline := _elapsed() + timeout
	for index in _grid_path(_nearest_node(player.current_vehicle.global_position), _nearest_node(target)):
		if _finished or _elapsed() >= deadline: return
		await _drive_to(world.traffic_nodes[index], 7.0, minf(35.0, deadline - _elapsed()))
		if mission.stage == Mission.Stage.TO_HELI: return
	await _drive_to(target, 48.0, maxf(1.0, deadline - _elapsed()))

func _drive_to(target: Vector3, stop_distance: float, timeout: float) -> void:
	var deadline := _elapsed() + timeout
	var stuck_for := 0.0
	var previous := player.controlled_actor().global_position
	while _elapsed() < deadline and not _finished and player.current_vehicle is Car:
		await get_tree().physics_frame
		var car := player.current_vehicle as Car
		if mission.stage == Mission.Stage.TO_HELI: break
		var offset := target - car.global_position
		offset.y = 0.0
		if offset.length() < stop_distance: break
		var forward := -car.global_transform.basis.z
		var direction := offset.normalized()
		var avoidance := _avoid_car_direction(car, forward)
		if avoidance != Vector3.ZERO:
			direction = avoidance
		var angle := atan2(forward.z * direction.x - forward.x * direction.z, forward.dot(direction))
		Input.action_release("move_left")
		Input.action_release("move_right")
		if absf(angle) > 0.025:
			Input.action_press("move_left" if angle > 0.0 else "move_right", clampf(absf(angle) * 1.8, 0.15, 1.0))
		var desired_speed := clampf(offset.length() * 0.8, 5.0, 19.0)
		if absf(angle) > 0.4: desired_speed = minf(desired_speed, 6.0)
		Input.action_release("move_forward")
		Input.action_release("move_back")
		if car.forward_speed() > desired_speed + 1.0:
			Input.action_press("move_back")
		else:
			Input.action_press("move_forward")
		if car.global_position.distance_to(previous) < 0.015:
			stuck_for += get_physics_process_delta_time()
		else:
			stuck_for = 0.0
		previous = car.global_position
		if stuck_for > 0.9:
			# Reverse and steer clear using the same inputs as a player.
			Input.action_release("move_forward")
			Input.action_press("move_back")
			Input.action_release("move_left")
			Input.action_press("move_right")
			await get_tree().create_timer(1.2).timeout
			stuck_for = 0.0
	_release_all()
	_log("drive waypoint target=%s distance=%.1f" % [target.round(), _ground_distance(player.controlled_actor().global_position, target)])

## Driver perception for this automated playtest: steer around an actual
## nearby car using normal controls. The obstacle and vehicle are never moved.
func _avoid_car_direction(car: Car, forward: Vector3) -> Vector3:
	var left := Vector3.UP.cross(forward).normalized()
	var nearest := INF
	var obstacle: Node3D = null
	for other in get_tree().get_nodes_in_group("vehicles"):
		if other == car or other is Helicopter: continue
		var offset: Vector3 = other.global_position - car.global_position
		var ahead := offset.dot(forward)
		var lateral := offset.dot(left)
		if ahead > 1.0 and ahead < 17.0 and absf(lateral) < 3.2 and ahead < nearest:
			nearest = ahead
			obstacle = other
	if obstacle == null: return Vector3.ZERO
	var relative := obstacle.global_position - car.global_position
	var side := -1.0 if relative.dot(left) >= 0.0 else 1.0
	return (forward * maxf(4.0, nearest * 0.75) + left * side * 5.0).normalized()

func _fly_to(target: Vector3, timeout: float) -> void:
	var deadline := _elapsed() + timeout
	while _elapsed() < deadline and not _finished and player.current_vehicle is Helicopter:
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

func _land(target: Vector3, timeout: float) -> void:
	var deadline := _elapsed() + timeout
	while _elapsed() < deadline and not _finished and player.current_vehicle is Helicopter:
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
			"latest": _snapshot(_elapsed()), "gates": _gates, "recent_log": log_lines.slice(maxi(0, log_lines.size() - 8))}, "\t"))
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
	if _record_log:
		_record_log.flush()
		_record_log.close()
		_record_log = null
	var recording := {"requested": not _record_dir.is_empty(), "enabled": not _headless and not _record_dir.is_empty(), "directory": _record_dir,
		"requested_hz": 10, "frames_written": _record_index, "bytes_written": _record_bytes,
		"scheduled_samples": _record_requested_samples, "missed_samples": _record_dropped_samples,
		"capped": _record_capped, "cap_reason": _record_cap_reason,
		"max_frames": RECORD_MAX_FRAMES, "max_bytes": RECORD_MAX_BYTES,
		"max_duration_seconds": ROUTE_TIMEOUT, "timestamps": "frames.jsonl monotonic seconds from route setup",
		"readback_encode_cost_ms": _frame_metrics(_record_cost_ms)}
	if not _record_dir.is_empty():
		var record_summary := FileAccess.open(_record_dir.path_join("recording.json"), FileAccess.WRITE)
		if record_summary:
			record_summary.store_string(JSON.stringify(recording, "\t"))
			record_summary.close()
	var output := FileAccess.open("%s/capture_log.json" % out_dir, FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify({"schema": 2, "success": success, "failure_reason": _failure,
			"uninterrupted": success and Game.death_count == _initial_deaths, "controls_only": true,
			"automation_kind": "scripted input actions, direct mouse-look yaw/pitch, fractional action strengths",
			"native_human_run": false, "no_teleports_or_state_bypasses": true,
			"headless": _headless, "rendered_performance_valid": not _headless,
			"finished_utc": Time.get_datetime_string_from_system(true), "elapsed_seconds": _elapsed(),
			"engine": Engine.get_version_info()["string"], "seed": Game.seed_value,
			"health": Game.health, "wanted_level": Game.wanted_level, "mission_stage": mission.stage,
			"mode": Game.mode, "deaths": Game.death_count - _initial_deaths, "combat_kills": _combat_kills,
			"peds": traffic.count_peds(), "traffic_cars": traffic.count_traffic(), "screenshots": _shots,
			"frame_times": _frame_metrics(_frames_ms),
			"frame_time_method": "Monotonic process-frame intervals; excludes intervals touched by screenshot/recording readback.",
			"frame_times_including_capture_overhead": _frame_metrics(_inclusive_frames_ms),
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
