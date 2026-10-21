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

	# --- 1. walk through the shophouse streets to the hawker centre ---------
	await _walk_to(world.locations["package"], 3.0, 180.0)
	await _shot("hawker_market")

	# --- 2. take the package (real interactable) ----------------------------
	_press("interact")
	await get_tree().create_timer(0.4).timeout
	_release("interact")
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
		await _walk_to(car.global_position, 3.0, 90.0)
		_press("interact")
		await get_tree().create_timer(0.4).timeout
		_release("interact")
		await get_tree().create_timer(0.4).timeout
		_log("mode after entering car: %d (car mode=%d)" % [Game.mode, Game.MODE_CAR])
		await _shot("car_entered")
		await _drive_to(world.locations["helipad_primary"], 150.0)
		await _shot("driving")
		# park and get out
		_release("move_forward")
		await get_tree().create_timer(1.5).timeout
		_press("interact")
		await get_tree().create_timer(0.4).timeout
		_release("interact")
		await get_tree().create_timer(0.4).timeout
		_log("mode after exiting car: %d" % Game.mode)
		await _shot("exited_car")

	# --- 5. board the helicopter -------------------------------------------
	var heli := main.get_node_or_null("Helicopter")
	if heli:
		await _walk_to(heli.global_position, 4.0, 90.0)
		_press("interact")
		await get_tree().create_timer(0.4).timeout
		_release("interact")
		await get_tree().create_timer(0.6).timeout
		_log("mode after boarding helicopter: %d (heli mode=%d)" % [Game.mode, Game.MODE_HELI])
		await _shot("helicopter_boarding")
		await _fly_to(world.locations["helipad_secondary"], 170.0)
		await _shot("aerial_view")
		await _land()
		await _shot("landed")
		_press("interact")
		await get_tree().create_timer(0.4).timeout
		_release("interact")
		await get_tree().create_timer(0.4).timeout
		_log("mode after exiting helicopter: %d" % Game.mode)

	# --- 6. walk to the delivery point --------------------------------------
	await _walk_to(world.locations["delivery"], 3.0, 120.0)
	_press("interact")
	await get_tree().create_timer(0.5).timeout
	_release("interact")
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

func _walk_to(target: Vector3, stop_distance: float, timeout: float) -> void:
	_press("move_forward")
	_press("sprint")
	var elapsed := 0.0
	while elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		_face_towards(target)
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
		var to_target := target - car.global_position
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
		var to_target := target - heli.global_position
		to_target.y = 0.0
		var dist := to_target.length()
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
