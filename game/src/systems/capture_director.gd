extends Node
## Automated playtest used to capture evidence of the golden path.
## It drives the REAL systems through the real input actions (no teleporting,
## no scripted camera): walk, shoot, steal a car, drive, board the helicopter,
## fly, land, exit and deliver. Screenshots and a JSON state log are written
## to the capture directory for independent review.

var main: Node
var player: Player
var world: WorldBuilder
var mission: Mission
var traffic: TrafficManager
var out_dir := "captures"
var log_lines: Array[String] = []
var _shots := 0

func setup(m: Node, p: Player, w: WorldBuilder, mi: Mission, t: TrafficManager) -> void:
	main = m
	player = p
	world = w
	mission = mi
	traffic = t
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			out_dir = arg.split("=")[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func _log(text: String) -> void:
	log_lines.append(text)
	print("[capture] ", text)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	_shots += 1
	var path := "%s/%02d_%s.png" % [out_dir, _shots, name]
	img.save_png(path)
	_log("screenshot %s" % path)

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	_log("start: player at %s" % str(player.global_position))
	await _shot("safe_room")

	# --- 1. walk out of the safe room, then through the streets -------------
	if world.locations.has("safe_room_exit"):
		await _walk_to(world.locations["safe_room_exit"], 2.5, 40.0)
	await _nav_to(world.locations["package"], 1.8, 240.0)
	await _shot("hawker_market")

	# --- 2. take the package (real interactable) ----------------------------
	await _interact()
	await _shot("package_taken")
	_log("mission stage after package: %d" % mission.stage)

	# --- 3. shoot a hostile -------------------------------------------------
	var hostile := _nearest_hostile()
	if hostile:
		await _shoot_at(hostile)
		await _shot("combat")

	# --- 4. steal a car and drive to the aviation compound -------------------
	var car := _nearest_car()
	if car:
		await _nav_to(car.global_position, 2.2, 180.0)
		await _interact()
		_log("mode after entering car: %d (car mode=%d)" % [Game.mode, Game.MODE_CAR])
		await _shot("car_entered")
		await _drive_route(world.locations["helipad_primary"], 200.0)
		await _shot("driving")
		# park and get out
		_release("move_forward")
		await get_tree().create_timer(1.5).timeout
		await _interact()
		_log("mode after exiting car: %d" % Game.mode)
		await _shot("exited_car")

	# --- 5. board the helicopter -------------------------------------------
	var heli := main.get_node_or_null("Helicopter")
	if heli:
		await _nav_to(heli.global_position, 2.6, 180.0)
		await _interact()
		await get_tree().create_timer(0.4).timeout
		_log("mode after boarding helicopter: %d (heli mode=%d)" % [Game.mode, Game.MODE_HELI])
		await _shot("helicopter_boarding")
		await _fly_to(world.locations["helipad_secondary"], 170.0)
		await _shot("aerial_view")
		await _land()
		await _shot("landed")
		await _interact()
		_log("mode after exiting helicopter: %d" % Game.mode)

	# --- 6. walk to the delivery point --------------------------------------
	await _nav_to(world.locations["delivery"], 2.2, 240.0)
	await _interact()
	await _shot("delivery")
	_log("final mission stage: %d (done=%d)" % [mission.stage, Mission.Stage.DONE])
	_write_log()

func _write_log() -> void:
	var f := FileAccess.open("%s/capture_log.json" % out_dir, FileAccess.WRITE)
	if f:
		var data := {
			"health": Game.health,
			"wanted_level": Game.wanted_level,
			"mission_stage": mission.stage,
			"mode": Game.mode,
			"peds": traffic.count_peds(),
			"traffic_cars": traffic.count_traffic(),
			"log": log_lines,
		}
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	_log("log written")
	get_tree().quit(0)

# ------------------------------------------------------------------ helpers
## Press the interact action with retries: a scripted press has to be seen by
## the polled input path, so it is repeated over a short window.
func _interact() -> void:
	for attempt in 4:
		_press("interact")
		await get_tree().create_timer(0.18).timeout
		_release("interact")
		await get_tree().create_timer(0.18).timeout

func _press(action: String) -> void:
	Input.action_press(action)

func _release(action: String) -> void:
	Input.action_release(action)

func _face_towards(target: Vector3) -> void:
	var d := target - player.global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	d = d.normalized()
	player.yaw = atan2(-d.x, -d.z)

## Grid navigation over the district junction graph: walk to the nearest
## junction, along the street grid, then the last few metres to the target.
func _nav_to(target: Vector3, stop_distance: float, timeout: float) -> void:
	var nodes: Array = world.traffic_nodes
	if nodes.is_empty():
		await _walk_to(target, stop_distance, timeout)
		return
	var start_i := _nearest_node(nodes, player.global_position)
	var goal_i := _nearest_node(nodes, target)
	var elapsed := 0.0
	for idx in _grid_path(start_i, goal_i):
		if elapsed > timeout:
			break
		await _walk_to(nodes[idx], 7.0, 45.0)
		elapsed += 45.0
		if player.global_position.distance_to(nodes[idx]) > 20.0:
			_log("navigation: missed junction %s" % str(nodes[idx]))
	await _walk_to(target, stop_distance, 60.0)

func _nearest_node(nodes: Array, p: Vector3) -> int:
	var best := 0
	var best_d := 1e12
	for i in nodes.size():
		var n: Vector3 = nodes[i]
		var d: float = Vector2(n.x - p.x, n.z - p.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best

## Manhattan route over the 5x5 junction lattice.
func _grid_path(start_i: int, goal_i: int) -> Array[int]:
	var cols := 5
	var sr := start_i / cols
	var sc := start_i % cols
	var gr := goal_i / cols
	var gc := goal_i % cols
	var path: Array[int] = []
	while sc != gc:
		sc += signi(gc - sc)
		path.append(sr * cols + sc)
	while sr != gr:
		sr += signi(gr - sr)
		path.append(sr * cols + sc)
	return path

func _walk_to(target: Vector3, stop_distance: float, timeout: float) -> void:
	_press("move_forward")
	_press("sprint")
	var elapsed := 0.0
	var last_pos := player.global_position
	var stuck_time := 0.0
	var sidestep := 0.0
	var sidestep_dir := 1.0
	while elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if sidestep > 0.0:
			# blocked: slide along the obstacle for a moment, then resume
			sidestep -= get_process_delta_time()
			player.yaw += sidestep_dir * 1.8 * get_process_delta_time()
		else:
			_face_towards(target)
		if player.global_position.distance_to(last_pos) < 0.02:
			stuck_time += get_process_delta_time()
			if stuck_time > 1.2:
				stuck_time = 0.0
				sidestep = 1.4
				sidestep_dir = 1.0 if randf() > 0.5 else -1.0
				# hop: kerbs and low ledges should not stop the walk
				_press("jump")
				await get_tree().process_frame
				_release("jump")
		else:
			stuck_time = 0.0
		last_pos = player.global_position
		if int(elapsed * 2.0) % 4 == 0 and absf(elapsed - float(int(elapsed * 2.0) / 2.0)) < 0.02:
			_log("walk pos=%s target=%s dist=%.1f" % [str(player.global_position.round()), str(target.round()), player.global_position.distance_to(target)])
		if player.global_position.distance_to(target) < stop_distance:
			break
	_release("sprint")
	_release("move_forward")

func _shoot_at(hostile: Node) -> void:
	for shot in 3:
		_face_towards(hostile.global_position + Vector3(0.0, 1.2, 0.0))
		_press("aim")
		await get_tree().create_timer(0.25).timeout
		_press("fire")
		await get_tree().create_timer(0.2).timeout
		_release("fire")
		await get_tree().create_timer(0.35).timeout
	_release("aim")

func _nearest_hostile() -> Node:
	var best: Node = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.is_hostile and n.state != NPC.State.DEAD:
			var d: float = n.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = n
	return best

func _nearest_car() -> Node:
	var best: Node = null
	var best_d := 1e9
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.has_method("interact") and not v.is_in_group("helicopters"):
			var d: float = v.global_position.distance_to(player.global_position)
			if d < best_d and d < 120.0:
				best_d = d
				best = v
	return best

## Drive the stolen car along the junction lattice, then onto the target.
func _drive_route(target: Vector3, timeout: float) -> void:
	var nodes: Array = world.traffic_nodes
	var start_i := _nearest_node(nodes, player.current_vehicle.global_position)
	var goal_i := _nearest_node(nodes, target)
	for idx in _grid_path(start_i, goal_i):
		await _drive_to(nodes[idx], 60.0)
	await _drive_to(target, 40.0)

## Steer the player-driven car toward a target using only the driving inputs.
func _drive_to(target: Vector3, timeout: float) -> void:
	var elapsed := 0.0
	_press("move_forward")
	while elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var car := player.current_vehicle
		if car == null:
			break
		var to_target: Vector3 = target - car.global_position
		to_target.y = 0.0
		if to_target.length() < 18.0:
			break
		to_target = to_target.normalized()
		var fwd: Vector3 = -car.global_transform.basis.z
		var cross_y: float = fwd.z * to_target.x - fwd.x * to_target.z
		_release("move_left")
		_release("move_right")
		if cross_y > 0.06:
			_press("move_left")
		elif cross_y < -0.06:
			_press("move_right")
	_release("move_left")
	_release("move_right")
	_release("move_forward")

## Fly the helicopter toward a target with arcade inputs, then descend.
func _fly_to(target: Vector3, timeout: float) -> void:
	var elapsed := 0.0
	_press("jump")  # climb
	while elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var heli := player.current_vehicle
		if heli == null:
			break
		var to_target: Vector3 = target - heli.global_position
		to_target.y = 0.0
		var dist: float = to_target.length()
		if dist < 25.0:
			break
		to_target = to_target.normalized()
		var fwd: Vector3 = -heli.global_transform.basis.z
		var cross_y: float = fwd.z * to_target.x - fwd.x * to_target.z
		_release("move_left")
		_release("move_right")
		if cross_y > 0.05:
			_press("move_left")
		elif cross_y < -0.05:
			_press("move_right")
		if heli.global_position.y < 40.0:
			_press("jump")
		else:
			_release("jump")
		_press("move_forward")
	_release("jump")

func _land() -> void:
	var heli := player.current_vehicle
	if heli == null:
		return
	_release("move_forward")
	_release("move_left")
	_release("move_right")
	var elapsed := 0.0
	while elapsed < 90.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		heli = player.current_vehicle
		if heli == null:
			return
		if heli.is_landed():
			break
		_press("sprint")  # descend
		await get_tree().process_frame
	_release("sprint")
