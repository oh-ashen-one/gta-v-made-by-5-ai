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
	if _jsonl:
		_jsonl.store_line(JSON.stringify({"file": "f%05d.jpg" % _frame, "seconds": _elapsed(), "phase": _phase, "kmh": snappedf(car.speed_kmh(), 0.1) if car else 0.0}))

func _still(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_jpg("%s/%s.jpg" % [out_dir, label], 0.95)  # C2: PNG encode hitched 250-300 ms
		var fx = car.fx
		_log("still %s speed=%.1f km/h roll=%.3f pitch=%.3f fov=%.1f skids=%d sparks=%d yaw_rate=%.2f slip=%.2f" % [label, car.speed_kmh(), fx.last_roll, fx.last_pitch, car._camera.fov, fx.skid_marks_laid, fx.sparks_fired, car._yaw_rate, car.drift_amount()])

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

func _lane_point(a: Vector3, b: Vector3, along: float, side: float = 1.0) -> Vector3:
	var f := (b - a)
	f.y = 0.0
	f = f.normalized()
	var left := Vector3.UP.cross(f).normalized()
	return a + f * along + left * 3.4 * side

## Which carriageway the car is on relative to the a->b centre line (+1 left).
func _side_of(a: Vector3, b: Vector3) -> float:
	var f := (b - a)
	f.y = 0.0
	var left := Vector3.UP.cross(f.normalized())
	return 1.0 if (car.global_position - a).dot(left) >= 0.0 else -1.0

var _jsonl: FileAccess

func _node(row: int, col: int) -> Vector3:
	return world.traffic_nodes[row * 5 + col]

## Drive along a lane from `a` toward `b`, holding a speed, until `stop_before`
## metres before `b`'s junction centre.
func _leg(a: Vector3, b: Vector3, kmh: float, stop_before: float, timeout: float) -> void:
	var f := (b - a)
	f.y = 0.0
	f = f.normalized()
	var t_end := _elapsed() + timeout
	var side := _side_of(a, b)
	while _elapsed() < t_end:
		await get_tree().physics_frame
		var along := (car.global_position - a).dot(f)
		_steer_to(_lane_point(a, b, along + 14.0, side))
		Input.action_release("move_forward")
		Input.action_release("move_back")
		if car.speed_kmh() < kmh: Input.action_press("move_forward")
		elif car.speed_kmh() > kmh + 8.0: Input.action_press("move_back")
		if (b - car.global_position).dot(f) < stop_before: break

## Take the junction at `n` from the a->n lane into the n->c lane.
func _corner(a: Vector3, n: Vector3, c: Vector3, entry_kmh: float, handbrake: bool, still_label: String) -> void:
	var f_in := (n - a)
	f_in.y = 0.0
	f_in = f_in.normalized()
	var f_out := (c - n)
	f_out.y = 0.0
	f_out = f_out.normalized()
	var apex := _lane_point(n, c, 2.0) - f_in * 2.0
	var exit := _lane_point(n, c, 34.0)
	var t_end := _elapsed() + 8.0
	var turned := false
	var still_done := false
	var hb_t := 0.0
	while _elapsed() < t_end:
		await get_tree().physics_frame
		var heading := -car.global_transform.basis.z
		heading.y = 0.0
		heading = heading.normalized()
		var d_apex := car.global_position.distance_to(apex)
		if not turned and (d_apex < (17.0 if handbrake else 13.0) or (car.global_position - n).dot(f_in) > -4.0):
			turned = true
		Input.action_release("move_forward")
		Input.action_release("move_back")
		if not turned:
			_steer_to(_lane_point(a, n, (car.global_position - a).dot(f_in) + 12.0))
			if car.speed_kmh() > entry_kmh + 4.0: Input.action_press("move_back")
			else: Input.action_press("move_forward")
			continue
		if handbrake and hb_t < 1.1 and heading.dot(f_out) < 0.93:
			hb_t += get_physics_process_delta_time()
			Input.action_press("jump")
			var side := f_in.cross(f_out).y
			Input.action_release("move_left")
			Input.action_release("move_right")
			Input.action_press("move_left" if side > 0.0 else "move_right", 1.0)
			if hb_t > 0.35: Input.action_press("move_forward", 0.6)
		else:
			Input.action_release("jump")
			_steer_to(exit, 3.2)
			Input.action_press("move_forward")
		if not still_done and heading.dot(f_out) > 0.55 and heading.dot(f_out) < 0.9:
			still_done = true
			await _still(still_label)
		if heading.dot(f_out) > 0.97 and (car.global_position - n).dot(f_out) > 16.0: break
	Input.action_release("jump")

func _run() -> void:
	_t0 = Time.get_ticks_usec()
	await get_tree().create_timer(1.5).timeout
	Game.simulation_paused = false
	# Zig-zag through two junctions near the package: (r,c)->(r,c+1)->(r+1,c+1)->(r+1,c+2).
	var pk := _nearest_node(world.locations["package"])
	var r := clampi(pk / 5, 0, (world.traffic_nodes.size() / 5) - 2)
	var c := clampi(pk % 5, 0, 2)
	var n0 := _node(r, c)
	var n1 := _node(r, c + 1)
	var n2 := _node(r + 1, c + 1)
	var n3 := _node(r + 1, c + 2)
	_log("nodes %s %s %s %s" % [n0, n1, n2, n3])
	car = null
	for cc in traffic.cars:
		if cc is Car and not cc.has_ai and not cc.disabled and cc.kind == "sedan":
			car = cc
			break
	if car == null:
		car = traffic.cars[0]
	car.has_ai = false
	car.occupied_by_npc = false
	car.max_speed = Car.MAX_SPEED
	car.accel = Car.ACCEL
	var f01 := (n1 - n0).normalized()
	car.global_position = _lane_point(n0, n1, 22.0) + Vector3(0.0, 0.3, 0.0)
	car.rotation = Vector3(0.0, atan2(-f01.x, -f01.z), 0.0)
	car.velocity = Vector3.ZERO
	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	await get_tree().create_timer(0.6).timeout
	_jsonl = FileAccess.open(out_dir + "/frames/frames.jsonl", FileAccess.WRITE)
	_recording = true
	_phase = "enter"
	car.interact(player)
	await get_tree().create_timer(1.0).timeout
	_log("recording start")
	# 1. Launch down the first street.
	_phase = "launch"
	Input.action_press("move_forward")
	var t_launch := _elapsed() + 2.2
	var launched := false
	while _elapsed() < t_launch:
		await get_tree().physics_frame
		_steer_to(_lane_point(n0, n1, (car.global_position - n0).dot(f01) + 14.0))
		if not launched and car.speed_kmh() > 35.0:
			launched = true
			await _still("01_launch")
	await _leg(n0, n1, 84.0, 46.0, 10.0)
	await _still("02_at_speed")
	# 2. Junction one: brake late, roll into the corner on grip.
	_phase = "corner1"
	await _corner(n0, n1, n2, 48.0, false, "03_corner_grip")
	# 3. Accelerate, then a handbrake turn at junction two.
	_phase = "straight2"
	await _leg(n1, n2, 66.0, 34.0, 10.0)
	_phase = "handbrake"
	await _corner(n1, n2, n3, 55.0, true, "04_handbrake_turn")
	await _still("05_handbrake_exit")
	# 4. Accelerate and brake hard to a stop.
	_phase = "brake"
	var f23 := (n3 - n2).normalized()
	await _leg(n2, n3, 80.0, -1e9, 4.5)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	var braked := false
	var t_end := _elapsed() + 4.0
	var bside := _side_of(n2, n3)
	while _elapsed() < t_end:
		await get_tree().physics_frame
		_steer_to(_lane_point(n2, n3, (car.global_position - n2).dot(f23) + 14.0, bside))
		if not braked and car.speed_kmh() < 60.0:
			braked = true
			await _still("06_hard_braking")
		if car.forward_speed() < 0.4: break
	Input.action_release("move_back")
	await get_tree().create_timer(0.7).timeout
	await _still("07_stopped_settle")
	# 6. Into a wall: find the building line beside the lane and hit it at an angle.
	_phase = "wall"
	var left := Vector3.UP.cross(f23).normalized() * _side_of(n2, n3)
	var wall_point := Vector3.INF
	var space := car.get_world_3d().direct_space_state
	car.last_impact = {}
	for ahead in [18.0, 24.0, 30.0, 36.0, 42.0, 48.0, 54.0, 60.0, 66.0]:
		for sd in [1.0]:
			if wall_point != Vector3.INF: break
			for hgt in [1.2]:
				var o: Vector3 = car.global_position + f23 * float(ahead) + Vector3.UP * float(hgt)
				var q := PhysicsRayQueryParameters3D.create(o, o + left * float(sd) * 16.0)
				q.collision_mask = 1
				q.exclude = [car.get_rid()]
				var hit := space.intersect_ray(q)
				_log("wall ray ahead=%.0f side=%.0f h=%.1f hit=%s" % [ahead, sd, hgt, (str(hit["position"]) + " n=" + str(hit["normal"]) + " " + str(hit["collider"])) if not hit.is_empty() else "none"])
				if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.5:
					wall_point = hit["position"]
					break
		if wall_point != Vector3.INF: break
	_log("wall point %s" % [wall_point])
	if wall_point != Vector3.INF:
		var impacts_before: int = car.fx.sparks_fired
		Input.action_press("move_forward")
		var wall_hit := -1.0
		t_end = _elapsed() + 7.0
		while _elapsed() < t_end:
			await get_tree().physics_frame
			if wall_hit < 0.0: _steer_to(wall_point, 2.4)
			if wall_hit < 0.0 and not car.last_impact.is_empty() and not car.last_impact.get("car", true):
				wall_hit = _elapsed()
				_log("wall impact %s" % [car.last_impact])
				_release()
				await _still("11_wall_impact")
			if wall_hit > 0.0 and _elapsed() - wall_hit > 1.8: break
		_release()
	# Back out of the wall and rejoin the lane before the next hit.
	_phase = "recover"
	Input.action_press("move_back")
	# Reversing with the wheel turned toward the kerb swings the nose back out.
	Input.action_press("move_left" if _side_of(n2, n3) > 0.0 else "move_right", 0.8)
	await get_tree().create_timer(1.6).timeout
	_release()
	await get_tree().create_timer(0.4).timeout
	await _leg(n2, n3, 32.0, -1e9, 3.0)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	t_end = _elapsed() + 3.0
	while _elapsed() < t_end and car.forward_speed() > 0.4:
		await get_tree().physics_frame
	_release()
	await get_tree().create_timer(0.5).timeout
	# 5. Ram a parked car standing in the lane 34 m ahead.
	_phase = "collision"
	# A traffic car (prefer a coupe) is stopped and parked in the lane ahead.
	var victim: Car = null
	var best := INF
	for cc in traffic.cars:
		if cc == car or not cc is Car or cc.disabled or cc.driver_is_player: continue
		if cc.kind == "van" or cc.kind == "police": continue
		var dd: float = (cc as Car).global_position.distance_to(car.global_position) + (0.0 if cc.kind == "coupe" else 400.0)
		if dd < best:
			best = dd
			victim = cc
	var victim_from := Vector3.ZERO
	if victim != null:
		victim.has_ai = false
		victim.occupied_by_npc = false
		var vp := car.global_position + f23 * 34.0
		vp.y = car.global_position.y
		victim.global_position = vp + Vector3(0.0, 0.3, 0.0)
		victim.rotation = Vector3(0.0, atan2(-f23.x, -f23.z) + 0.3, 0.0)
		victim.velocity = Vector3.ZERO
		victim.visible = true
		victim.set_physics_process(true)
		await get_tree().create_timer(0.4).timeout
		victim_from = victim.global_position
		_log("victim %s at %s kind=%s" % [victim.name, victim.global_position, victim.kind])
		Input.action_press("move_forward")
		var hit_time := -1.0
		t_end = _elapsed() + 7.0
		while _elapsed() < t_end:
			await get_tree().physics_frame
			if hit_time < 0.0: _steer_to(victim.global_position, 2.0)
			if hit_time < 0.0 and not car.last_impact.is_empty() and car.last_impact.get("car", false):
				hit_time = _elapsed()
				_log("ram impact %s" % [car.last_impact])
				_release()
				await _still("08_collision_impact")
			if hit_time > 0.0 and _elapsed() - hit_time > 0.25 and _elapsed() - hit_time < 0.4:
				await _still("09_collision_follow")
			if hit_time > 0.0 and _elapsed() - hit_time > 2.0: break
		_release()
		_log("victim moved %.2f m, speed now %.1f km/h, victim dents=%d debris=%d" % [victim.global_position.distance_to(victim_from), car.speed_kmh(), victim.damage.dent_count() if victim.damage else -1, car.damage.debris_spawned if car.damage else -1])
		await _still("10_after_collision")
	await get_tree().create_timer(0.8).timeout
	_recording = false
	# Added review views (not fixed comparison cameras).
	var look_cam := Camera3D.new()
	add_child(look_cam)
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := Vector3.UP.cross(fwd).normalized()
	look_cam.fov = 55.0
	look_cam.current = true
	look_cam.global_position = _clear_view(car, [fwd * 4.6 + side * 1.6, fwd * 4.6 - side * 1.6, fwd * 5.0, fwd * 3.6 + side * 3.0, fwd * 3.6 - side * 3.0, side * 4.6, -side * 4.6]) - Vector3.UP * 0.3
	look_cam.look_at(car.global_position + fwd * 1.2 + Vector3.UP * 0.55, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _still("12_damage_front_quarter")
	look_cam.global_position = _clear_view(car, [-fwd * 4.4 - side * 2.4, -fwd * 4.4 + side * 2.4, -side * 4.4, side * 4.4, -fwd * 5.0])
	look_cam.look_at(car.global_position + Vector3.UP * 0.6, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await _still("13_damage_rear_quarter")
	if victim != null:
		look_cam.global_position = victim.global_position + (victim_from - victim.global_position).normalized() * 6.0 + side * 3.0 + Vector3.UP * 2.0
		look_cam.look_at(victim.global_position + Vector3.UP * 0.6, Vector3.UP)
		await get_tree().create_timer(0.4).timeout
		await _still("14_struck_car")
	# Tyre marks through the handbrake junction, from a road-level camera.
	var mm: MultiMesh = car.fx._skids.multimesh
	var centre := Vector3.ZERO
	var count := 0
	for i in mm.visible_instance_count:
		var o: Vector3 = mm.get_instance_transform(i).origin
		if o.distance_to(n2) < 26.0:
			centre += o
			count += 1
	centre = centre / count if count > 0 else n2
	var f12 := (n2 - n1).normalized()
	look_cam.global_position = n2 - f12 * 16.0 + f23 * 7.0 + Vector3.UP * 4.2
	look_cam.look_at(n2 + f23 * 4.0, Vector3.UP)
	look_cam.fov = 60.0
	await get_tree().create_timer(0.4).timeout
	await _still("15_junction_tyre_marks")
	await get_tree().create_timer(0.3).timeout
	_log("frames=%d done marks_near_junction=%d" % [_frame, count])
	if _jsonl: _jsonl.close()
	var f := FileAccess.open(out_dir + "/showcase.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log_lines) + "\n")
		f.close()
	get_tree().quit(0)

## A review-camera spot around `target` with a clear line to it (not inside a
## shopfront or awning).
func _clear_view(target: Node3D, offsets: Array) -> Vector3:
	var space := target.get_world_3d().direct_space_state
	var aim: Vector3 = target.global_position + Vector3.UP * 0.8
	for off in offsets:
		var p: Vector3 = target.global_position + (off as Vector3) + Vector3.UP * 1.45
		var q := PhysicsRayQueryParameters3D.create(aim, p + ((p - aim).normalized() * 0.6))
		q.collision_mask = 1
		q.exclude = [(target as CollisionObject3D).get_rid()]
		var up := PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 4.0)
		up.collision_mask = 1
		if space.intersect_ray(q).is_empty() and space.intersect_ray(up).is_empty():
			return p
	return target.global_position + (offsets[0] as Vector3) + Vector3.UP * 1.45

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
