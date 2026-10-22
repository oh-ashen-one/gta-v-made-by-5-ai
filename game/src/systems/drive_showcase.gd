extends Node
## `--drive-showcase` (opus55 driving piece): scripted chase-cam footage of the
## player car through real player input. Phases: launch and accelerate down a
## boulevard, take a junction hard (slip, smoke, marks), accelerate, brake hard
## to a stop, then ram a stationary car. Every rendered frame is written as a
## JPEG with its timestamp into --capture-dir; key moments are also saved as
## PNG stills. Never touches the save slot.

var main: Node
var player: Player
var world: WorldBuilder
var traffic: TrafficManager
var out_dir := "user://drive_showcase"
var car: Car
var _t0 := 0
var _frame := 0
var _recording := false
var _log_lines: PackedStringArray = []
var _phase := "setup"

func setup(main_node: Node, p: Player, w: WorldBuilder, t: TrafficManager, dir: String) -> void:
	main = main_node
	player = p
	world = w
	traffic = t
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	_run.call_deferred()

func _log(msg: String) -> void:
	var line := "[drive-showcase %.2f] %s" % [_elapsed(), msg]
	print(line)
	_log_lines.append(line)

func _elapsed() -> float:
	return float(Time.get_ticks_usec() - _t0) / 1000000.0

var _last_us := 0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0 and now - _last_us > 250000:
		_log("frame stall %.0f ms phase=%s" % [(now - _last_us) / 1000.0, _phase])
	_last_us = now
	if _recording:
		_grab()

func _grab() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null: return
	_frame += 1
	img.save_jpg("%s/frames/f%05d.jpg" % [out_dir, _frame], 0.9)

func _still(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, label])
		var fx = car.fx
		_log("still %s speed=%.1f km/h roll=%.3f pitch=%.3f fov=%.1f skids=%d sparks=%d" % [label, car.speed_kmh(), fx.last_roll, fx.last_pitch, car._camera.fov, fx.skid_marks_laid, fx.sparks_fired])

func _release() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
		Input.action_release(a)

func _steer_to(target: Vector3, gain: float = 2.2) -> float:
	var fwd := -car.global_transform.basis.z
	var off := target - car.global_position
	off.y = 0.0
	var dir := off.normalized()
	var angle := atan2(fwd.z * dir.x - fwd.x * dir.z, fwd.dot(dir))
	Input.action_release("move_left")
	Input.action_release("move_right")
	if absf(angle) > 0.02:
		Input.action_press("move_left" if angle > 0.0 else "move_right", clampf(absf(angle) * gain, 0.12, 1.0))
	return off.length()

func _lane_point(a: Vector3, b: Vector3, along: float) -> Vector3:
	var f := (b - a)
	f.y = 0.0
	f = f.normalized()
	var left := Vector3.UP.cross(f).normalized()
	return a + f * along + left * 3.4

func _run() -> void:
	_t0 = Time.get_ticks_usec()
	await get_tree().create_timer(1.5).timeout
	Game.simulation_paused = false
	# Pick the route's own boulevard: package -> aviation compound, which has a
	# long straight and a right-angle junction.
	var from := _nearest_node(world.locations["package"])
	var to := _nearest_node(world.locations["helipad_primary"])
	var path := _grid_path(from, to)
	if path.size() < 3:
		path = [0, 1, 6]
	# The junction where the path turns: n0 -> n1 straight, n1 -> n2 turned.
	var k := 1
	for i in range(1, path.size() - 1):
		var da: Vector3 = (world.traffic_nodes[path[i]] - world.traffic_nodes[path[i - 1]]).normalized()
		var db: Vector3 = (world.traffic_nodes[path[i + 1]] - world.traffic_nodes[path[i]]).normalized()
		if da.dot(db) < 0.5:
			k = i
			break
	var n0: Vector3 = world.traffic_nodes[path[k - 1]]
	var n1: Vector3 = world.traffic_nodes[path[k]]
	var n2: Vector3 = world.traffic_nodes[path[k + 1]]
	_log("path %s nodes %s %s %s" % [path, n0, n1, n2])
	car = null
	for c in traffic.cars:
		if c is Car and not c.has_ai and not c.disabled:
			car = c
			break
	if car == null:
		car = traffic.cars[0]
	car.has_ai = false
	car.occupied_by_npc = false
	car.max_speed = Car.MAX_SPEED
	car.accel = Car.ACCEL
	var start := _lane_point(n0, n1, 18.0)
	car.global_position = start + Vector3(0.0, 0.3, 0.0)
	var f01 := (n1 - n0).normalized()
	car.rotation = Vector3(0.0, atan2(-f01.x, -f01.z), 0.0)
	car.velocity = Vector3.ZERO
	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	await get_tree().create_timer(0.6).timeout
	_phase = "enter"
	car.interact(player)
	await get_tree().create_timer(1.2).timeout
	_recording = true
	_log("recording start")
	# 1. Launch + accelerate down the boulevard.
	_phase = "accelerate"
	var corner := _lane_point(n1, n2, -2.0)
	Input.action_press("move_forward")
	var stills := {}
	var t_end := _elapsed() + 14.0
	while _elapsed() < t_end:
		await get_tree().physics_frame
		_steer_to(_lane_point(n0, n1, (car.global_position - n0).dot(f01) + 14.0))
		var to_corner := car.global_position.distance_to(corner)
		if not stills.has("a") and car.speed_kmh() > 45.0:
			stills["a"] = true
			await _still("01_launch_accelerating")
		if to_corner < 34.0: break
	# 2. Hard cornering into the junction at speed.
	_phase = "corner"
	_log("corner entry speed %.1f km/h" % car.speed_kmh())
	var exit := _lane_point(n1, n2, 40.0)
	t_end = _elapsed() + 6.0
	var turned := false
	while _elapsed() < t_end:
		await get_tree().physics_frame
		var d_corner := car.global_position.distance_to(corner)
		var target := corner if (d_corner > 16.0 and not turned) else exit
		if d_corner < 16.0: turned = true
		_steer_to(target, 3.5)
		# Late, hard brake into the junction, then back on the throttle.
		if not turned and car.speed_kmh() > 62.0:
			Input.action_release("move_forward")
			Input.action_press("move_back")
		else:
			Input.action_release("move_back")
			Input.action_press("move_forward")
		if turned and not stills.has("c"):
			if car.speed_kmh() > 55.0: Input.action_press("jump")
			else: Input.action_release("jump")
		if turned and car.global_position.distance_to(_lane_point(n1, n2, 6.0)) < 9.0 and not stills.has("c"):
			stills["c"] = true
			await _still("02_hard_cornering")
		var f12 := (n2 - n1).normalized()
		if turned and (-car.global_transform.basis.z).dot(f12) > 0.97 and (car.global_position - n1).dot(f12) > 22.0: break
	Input.action_release("jump")
	await _still("03_corner_exit_marks")
	# 3. Accelerate down the cross street.
	_phase = "accelerate2"
	var f12b := (n2 - n1).normalized()
	t_end = _elapsed() + 6.0
	while _elapsed() < t_end:
		await get_tree().physics_frame
		_steer_to(_lane_point(n1, n2, (car.global_position - n1).dot(f12b) + 16.0))
		if car.speed_kmh() > 92.0: break
	await _still("04_top_speed")
	# 4. Hard braking to a stop.
	_phase = "brake"
	Input.action_release("move_forward")
	Input.action_press("move_back")
	var braked := false
	t_end = _elapsed() + 4.0
	while _elapsed() < t_end:
		await get_tree().physics_frame
		_steer_to(_lane_point(n1, n2, (car.global_position - n1).dot(f12b) + 16.0))
		if not braked and car.speed_kmh() < 70.0:
			braked = true
			await _still("05_hard_braking")
		if car.forward_speed() < 0.4: break
	Input.action_release("move_back")
	await get_tree().create_timer(0.8).timeout
	await _still("06_stopped_settle")
	# 5. Collision: a stationary car in our lane 30 m ahead, hit at speed.
	_phase = "collision"
	var victim: Car = null
	for c in traffic.cars:
		if c != car and c is Car and not c.disabled and not c.has_ai:
			victim = c
			break
	if victim == null:
		for c in traffic.cars:
			if c != car and c is Car and not c.disabled:
				victim = c
				break
	if victim != null:
		victim.has_ai = false
		victim.occupied_by_npc = false
		var vp := _lane_point(n1, n2, (car.global_position - n1).dot(f12b) + 32.0)
		victim.global_position = vp + Vector3(0.0, 0.3, 0.0)
		victim.rotation = Vector3(0.0, atan2(-f12b.x, -f12b.z) + 0.35, 0.0)
		victim.velocity = Vector3.ZERO
		victim.visible = true
		victim.set_physics_process(true)
		_log("victim %s at %s kind=%s" % [victim.name, victim.global_position, victim.kind])
		Input.action_press("move_forward")
		var hit_time := -1.0
		t_end = _elapsed() + 7.0
		while _elapsed() < t_end:
			await get_tree().physics_frame
			_steer_to(victim.global_position, 2.0)
			if Engine.get_physics_frames() % 20 == 0:
				_log("ram: speed=%.1f dist=%.1f contacts=%d" % [car.speed_kmh(), car.global_position.distance_to(victim.global_position), car.get_slide_collision_count()])
			if hit_time < 0.0 and car.fx.sparks_fired > 0:
				hit_time = _elapsed()
				_release()
				await get_tree().create_timer(0.12).timeout
				await _still("07_collision_sparks")
			if hit_time > 0.0 and _elapsed() - hit_time > 1.6: break
		_release()
		await get_tree().create_timer(0.5).timeout
		await _still("08_after_collision")
	_recording = false
	# Added review view (not a fixed comparison camera): a kerbside camera at
	# the junction looking back over the cornering line, for the tyre marks.
	var look_cam := Camera3D.new()
	add_child(look_cam)
	var f12c := (n2 - n1).normalized()
	var side := Vector3.UP.cross(f12c).normalized()
	# Aim at the centroid of the marks laid through the corner.
	var mm: MultiMesh = car.fx._skids.multimesh
	var centre := Vector3.ZERO
	var count := 0
	for i in range(60, mini(200, mm.visible_instance_count)):
		centre += mm.get_instance_transform(i).origin
		count += 1
	if count > 0: centre /= count
	else: centre = n1 + f12c * 6.0
	_log("skid centroid %s (car y %.2f) first=%s" % [centre, car.global_position.y, mm.get_instance_transform(70)])
	look_cam.global_position = centre - f12c * 4.0 + side * 6.0 + Vector3(0.0, 7.5, 0.0)
	look_cam.look_at(centre, Vector3.UP)
	look_cam.fov = 60.0
	look_cam.current = true
	await get_tree().create_timer(0.5).timeout
	await _still("09_junction_tyre_marks")
	await get_tree().create_timer(0.3).timeout
	var dur := _elapsed()
	_log("frames=%d done" % _frame)
	var f := FileAccess.open(out_dir + "/showcase.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log_lines) + "\n")
		f.close()
	get_tree().quit(0)

func _nearest_node(position: Vector3) -> int:
	var best := 0
	var distance := INF
	for index in world.traffic_nodes.size():
		var p: Vector3 = world.traffic_nodes[index]
		var current := Vector2(p.x - position.x, p.z - position.z).length()
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
