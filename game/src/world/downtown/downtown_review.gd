extends Node
## `--downtown-review` (downtown-map, wave M): scripted footage through real
## player input, no teleports inside a leg.
##   drive: from the player start up the heritage avenue, left onto Collyer
##          Quay, Fullerton Road, over the Esplanade Bridge, Esplanade Drive,
##          Raffles Avenue, Bayfront Avenue North, over the Bayfront Bridge,
##          Bayfront Avenue, Marina Boulevard and back onto Collyer Quay
##          (the Marina Bay loop, left-hand lanes);
##   walk:  along the west shore promenade onto the Fullerton peninsula and
##          over the Jubilee footbridge to the Esplanade waterfront;
##   fly:   from the aviation pad over the city to NS Square, land, get out
##          and walk.
## Frames (every 2nd rendered frame) go to --capture-dir/frames as JPEG with a
## jsonl index; stills at key points; review.json has frame-time stats and the
## pass/fail of each leg. Never touches the save slot (run with --qa-session).

var main: Node
var player: Player
var world: WorldBuilder
var traffic: TrafficManager
var out_dir := "user://downtown_review"
var car: Car
var heli: Helicopter
var _t0 := 0
var _frame := 0
var _tick := 0
var _recording := false
var _phase := "setup"
var _jsonl: FileAccess
var _log_lines: PackedStringArray = []
var _frame_ms: Array[float] = []
var _last_us := 0
var _results := {}
var _max_h := {}

func setup(main_node: Node, p: Player, w: WorldBuilder, t: TrafficManager, dir: String) -> void:
	main = main_node
	player = p
	world = w
	traffic = t
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	_run.call_deferred()

func _log(msg: String) -> void:
	var line := "[downtown-review %.2f] %s" % [_elapsed(), msg]
	print(line)
	_log_lines.append(line)

func _elapsed() -> float:
	return float(Time.get_ticks_usec() - _t0) / 1000000.0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var grabbed_last := _recording and _tick % 2 == 1
	if _last_us > 0 and _recording and not grabbed_last:
		_frame_ms.append((now - _last_us) / 1000.0)
	_last_us = now
	_tick += 1
	if _recording and _tick % 2 == 0:
		_grab()
	var actor := player.controlled_actor()
	if actor != null:
		_max_h[_phase] = maxf(float(_max_h.get(_phase, -99.0)), actor.global_position.y)

func _grab() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	_frame += 1
	img.save_jpg("%s/frames/f%05d.jpg" % [out_dir, _frame], 0.85)
	if _jsonl:
		var a := player.controlled_actor()
		_jsonl.store_line(JSON.stringify({"file": "f%05d.jpg" % _frame, "seconds": snappedf(_elapsed(), 0.01), "phase": _phase, "pos": str(a.global_position.snapped(Vector3.ONE * 0.1)) if a else ""}))

func _still(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_jpg("%s/%s.jpg" % [out_dir, label], 0.95)
		_log("still %s at %s" % [label, player.controlled_actor().global_position])

func _release() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint"]:
		Input.action_release(a)

# ------------------------------------------------------------ paths
static func _left(f: Vector3) -> Vector3:
	return Vector3(f.z, 0.0, -f.x)

## Lane path along a list of road / bridge centreline points, offset into the
## left-hand lane of travel.
func _lane_path(centre: Array, offsets: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in centre.size() - 1:
		var a: Vector3 = centre[i]
		var b: Vector3 = centre[i + 1]
		var f := (b - a)
		f.y = 0.0
		f = f.normalized()
		var off: float = offsets[i]
		var n := maxi(1, int(a.distance_to(b) / 6.0))
		for k in n:
			var q := a.lerp(b, float(k) / n) + _left(f) * off
			out.append(Vector3(q.x, 0.0, q.z))
	var last: Vector3 = centre[centre.size() - 1]
	out.append(last)
	return out

func _closest(path: Array[Vector3], p: Vector3, from_i: int) -> int:
	var best := from_i
	var bd := INF
	for i in range(from_i, mini(path.size(), from_i + 40)):
		var d := Vector2(path[i].x - p.x, path[i].z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best

func _ahead(path: Array[Vector3], i: int, dist: float) -> Vector3:
	var acc := 0.0
	var k := i
	while k < path.size() - 1 and acc < dist:
		acc += path[k].distance_to(path[k + 1])
		k += 1
	return path[k]

## Sharpest heading change within `dist` metres ahead (radians).
func _turn_ahead(path: Array[Vector3], i: int, dist: float) -> float:
	var a := _ahead(path, i, 6.0) - path[i]
	var b := _ahead(path, i, dist) - _ahead(path, i, maxf(dist - 12.0, 6.0))
	a.y = 0.0
	b.y = 0.0
	if a.length() < 0.1 or b.length() < 0.1:
		return 0.0
	return absf(a.normalized().signed_angle_to(b.normalized(), Vector3.UP))

func _steer(actor: Node3D, target: Vector3, gain: float = 2.2) -> void:
	var fwd := -actor.global_transform.basis.z
	var off := target - actor.global_position
	off.y = 0.0
	var dir := off.normalized()
	var angle := atan2(fwd.z * dir.x - fwd.x * dir.z, fwd.dot(dir))
	Input.action_release("move_left")
	Input.action_release("move_right")
	if absf(angle) > 0.015:
		Input.action_press("move_left" if angle > 0.0 else "move_right", clampf(absf(angle) * gain, 0.1, 1.0))

# ------------------------------------------------------------ run
func _run() -> void:
	_t0 = Time.get_ticks_usec()
	await get_tree().create_timer(1.5).timeout
	Game.simulation_paused = false
	if main.get("hud") != null:
		main.hud.clear_notifications()
	_jsonl = FileAccess.open(out_dir + "/frames/frames.jsonl", FileAccess.WRITE)
	await _drive_leg()
	await _walk_leg()
	await _fly_leg()
	_recording = false
	_release()
	await _views()
	await _perf_sweep()
	_finish()

## Frame-time sweep with no frame readback: 150 rendered frames at each of a
## street, bridge, waterfront and helicopter-height downtown view.
var _perf := {}
func _perf_sweep() -> void:
	_phase = "perf"
	_recording = false
	var cam := get_viewport().get_camera_3d()
	var spots := [
		["street_raffles_avenue", Vector3(-783.0, 1.6, -420.0), Vector3(-790.0, 6.0, -760.0)],
		["bridge_esplanade", Vector3(-560.0, 5.4, -355.0), Vector3(-790.0, 4.0, -360.0)],
		["waterfront_merlion_park", Vector3(-470.0, 1.7, -395.0), Vector3(-118.0, 90.0, -705.0)],
		["street_shenton_way", Vector3(392.0, 1.6, 300.0), Vector3(400.0, 20.0, -200.0)],
		["heli_bayfront", Vector3(-650.0, 140.0, -560.0), Vector3(-250.0, 0.0, -800.0)],
		["heli_river_mouth", Vector3(-380.0, 120.0, -200.0), Vector3(-600.0, 0.0, -420.0)],
	]
	var all: Array[float] = []
	for sp: Array in spots:
		cam.global_position = sp[1]
		cam.look_at(sp[2], Vector3.UP)
		for w in 20:
			await get_tree().process_frame
		var times: Array[float] = []
		var last := Time.get_ticks_usec()
		for k in 150:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
		times.sort()
		all.append_array(times)
		_perf[sp[0]] = {"p50": snappedf(times[75], 0.01), "p95": snappedf(times[142], 0.01), "max": snappedf(times[149], 0.01)}
		_log("perf %s p50 %.2f p95 %.2f max %.2f ms" % [sp[0], times[75], times[142], times[149]])
	all.sort()
	_perf["all"] = {"n": all.size(), "p50": snappedf(all[all.size() / 2], 0.01), "p95": snappedf(all[int(all.size() * 0.95)], 0.01), "p99": snappedf(all[int(all.size() * 0.99)], 0.01)}

## Fixed stills: the plan's downtown views plus street-level and helicopter
## height views of the new roads and bridges (free camera, fixture-assisted).
const EXTRA_VIEWS := [
	{"name": "dtx_esplanade_bridge_street", "pos": Vector3(-470.0, 1.7, -327.0), "look": Vector3(-650.0, 3.0, -362.0), "fov": 64.0},
	{"name": "dtx_raffles_avenue_street", "pos": Vector3(-783.0, 1.6, -420.0), "look": Vector3(-790.0, 6.0, -760.0), "fov": 66.0},
	{"name": "dtx_bayfront_bridge_street", "pos": Vector3(-560.0, 1.6, -793.0), "look": Vector3(-300.0, 8.0, -780.0), "fov": 64.0},
	{"name": "dtx_shenton_way_street", "pos": Vector3(392.0, 1.6, 300.0), "look": Vector3(400.0, 20.0, -200.0), "fov": 64.0},
	{"name": "dtx_heli_river_mouth", "pos": Vector3(-380.0, 120.0, -200.0), "look": Vector3(-600.0, 0.0, -420.0), "fov": 62.0},
	{"name": "dtx_heli_bayfront", "pos": Vector3(-650.0, 140.0, -560.0), "look": Vector3(-250.0, 0.0, -800.0), "fov": 62.0},
	{"name": "dtx_heli_marina_south", "pos": Vector3(150.0, 150.0, -420.0), "look": Vector3(450.0, 0.0, -650.0), "fov": 62.0},
]

func _views() -> void:
	_phase = "views"
	if main.get("hud") != null:
		main.hud.set_gameplay_visible(false)
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	var views: Array = DowntownPlan.VIEWS.duplicate()
	views.append_array(EXTRA_VIEWS)
	for v: Dictionary in views:
		cam.global_position = v["pos"]
		cam.fov = float(v["fov"])
		cam.look_at(v["look"], Vector3.UP)
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("%s/view_%s.png" % [out_dir, String(v["name"])])

func _drive_leg() -> void:
	_phase = "drive"
	car = null
	for cc in traffic.cars:
		if cc is Car and not cc.has_ai and not cc.disabled and cc.kind == "sedan":
			car = cc
			break
	if car == null:
		car = traffic.cars[0]
	car.has_ai = false
	car.occupied_by_npc = false
	# The Marina Bay loop from the player's street (left-hand lanes).
	var r := DowntownPlan.ROADS
	var centre: Array = [Vector3(-160, 0, -40), Vector3(-160, 0, -320), Vector3(-470, 0, -320)]
	var offs: Array = [3.4, 3.4]
	for q: Vector3 in (r["fullerton_road"]["pts"] as Array).slice(1):
		centre.append(q)
		offs.append(3.4)
	for q2: Vector3 in [Vector3(-650, 0, -360), Vector3(-790, 0, -360), Vector3(-790, 0, -780), Vector3(-480, 0, -780), Vector3(-320, 0, -780), Vector3(400, 0, -780), Vector3(400, 0, -320), Vector3(250, 0, -320)]:
		centre.append(q2)
	offs.append_array([5.25, 5.25, 5.25, 6.75, 6.25, 6.75, 5.25, 3.4])
	var path := _lane_path(centre, offs)
	var f0 := (path[1] - path[0]).normalized()
	car.global_position = path[0] + Vector3(0, 0.4, 0)
	car.rotation = Vector3(0.0, atan2(-f0.x, -f0.z), 0.0)
	car.velocity = Vector3.ZERO
	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	await get_tree().create_timer(0.5).timeout
	car.interact(player)
	await get_tree().create_timer(0.6).timeout
	_recording = true
	_log("drive start at %s" % car.global_position)
	var i := 0
	var t_end := _elapsed() + 330.0
	var stills := {"esplanade_bridge": Vector3(-600, 0, -360), "raffles_avenue": Vector3(-790, 0, -600), "bayfront_bridge": Vector3(-420, 0, -780), "bayfront_avenue": Vector3(0, 0, -780), "marina_boulevard": Vector3(400, 0, -520)}
	var stuck_t := 0.0
	var max_deck := 0.0
	while _elapsed() < t_end:
		await get_tree().physics_frame
		i = _closest(path, car.global_position, i)
		if i >= path.size() - 2:
			break
		var kmh := car.speed_kmh()
		var turn := maxf(_turn_ahead(path, i, 34.0), _turn_ahead(path, i, 52.0))
		var target_kmh := 72.0 if turn < 0.25 else (24.0 if turn > 0.9 else 42.0)
		_steer(car, _ahead(path, i, clampf(kmh * 0.32, 9.0, 22.0)), 2.6)
		Input.action_release("move_forward")
		Input.action_release("move_back")
		if kmh < target_kmh:
			Input.action_press("move_forward")
		elif kmh > target_kmh + 6.0:
			Input.action_press("move_back")
		max_deck = maxf(max_deck, car.global_position.y)
		for key: String in stills.keys():
			if Vector2(car.global_position.x - stills[key].x, car.global_position.z - stills[key].z).length() < 12.0:
				stills.erase(key)
				await _still("drive_" + key)
				break
		if Input.is_action_pressed("move_forward") and kmh < 3.0:
			stuck_t += get_physics_process_delta_time()
			if stuck_t > 2.0:
				_log("unstick at %s" % car.global_position)
				Input.action_release("move_forward")
				Input.action_press("move_back")
				await get_tree().create_timer(1.2).timeout
				Input.action_release("move_back")
				stuck_t = 0.0
		else:
			stuck_t = 0.0
	_release()
	var done := i >= path.size() - 3
	_results["drive"] = {"completed": done, "seconds": snappedf(_elapsed(), 0.1), "max_y": snappedf(max_deck, 0.01), "end": str(car.global_position)}
	_log("drive done=%s at %s, max deck y %.2f" % [done, car.global_position, max_deck])
	# stop and get out on Collyer Quay
	Input.action_press("move_back")
	await get_tree().create_timer(1.5).timeout
	_release()
	if player.current_vehicle == car:
		car.interact(player)
		await get_tree().create_timer(0.5).timeout

func _walk_leg() -> void:
	_phase = "walk"
	_recording = false
	player.respawn_at(Vector3(-330.0, 0.6, -337.0), deg_to_rad(90.0))
	await get_tree().create_timer(1.2).timeout
	if main.get("hud") != null:
		main.hud.clear_notifications()
	player.camera.current = true
	_recording = true
	var pts: Array[Vector3] = [Vector3(-440, 0, -338), Vector3(-485, 0, -378), Vector3(-522, 0, -400), Vector3(-662, 0, -400), Vector3(-648, 0, -440), Vector3(-648, 0, -560)]
	var k := 0
	var t_end := _elapsed() + 120.0
	var stills := {1: "walk_peninsula", 3: "walk_jubilee_bridge", 5: "walk_esplanade_waterfront"}
	var max_y := 0.0
	while _elapsed() < t_end and k < pts.size():
		await get_tree().physics_frame
		var d := pts[k] - player.global_position
		d.y = 0.0
		if d.length() < 3.0:
			if stills.has(k):
				await _still(stills[k])
			k += 1
			continue
		var dir := d.normalized()
		var want := atan2(-dir.x, -dir.z)
		player.yaw = lerp_angle(player.yaw, want, 0.12)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		max_y = maxf(max_y, player.global_position.y)
	_release()
	_results["walk"] = {"completed": k >= pts.size(), "reached": k, "end": str(player.global_position), "max_y": snappedf(max_y, 0.01)}
	_log("walk reached %d/%d at %s max y %.2f" % [k, pts.size(), player.global_position, max_y])

func _fly_leg() -> void:
	_phase = "fly"
	_recording = false
	heli = main.get_node_or_null("Helicopter") as Helicopter
	if heli == null:
		_results["fly"] = {"completed": false, "error": "no helicopter"}
		return
	player.respawn_at(heli.global_position + Vector3(3.0, 0.5, 0.0), 0.0)
	await get_tree().create_timer(0.6).timeout
	heli.interact(player)
	await get_tree().create_timer(0.4).timeout
	if main.get("hud") != null:
		main.hud.clear_notifications()
	_recording = true
	var pad: Vector3 = DowntownPlan.HELIPADS["ns_square"]["pos"]
	# climb
	Input.action_press("jump")
	var t_climb := _elapsed() + 9.0
	while _elapsed() < t_climb and heli.global_position.y < 110.0:
		await get_tree().physics_frame
	Input.action_release("jump")
	var t_end := _elapsed() + 90.0
	var stills := [700.0, 300.0]
	var landed := false
	while _elapsed() < t_end:
		await get_tree().physics_frame
		var d := pad - heli.global_position
		d.y = 0.0
		var dist := d.length()
		var want := atan2(-d.x, -d.z)
		var err := wrapf(want - heli.rotation.y, -PI, PI)
		Input.action_release("move_left")
		Input.action_release("move_right")
		if absf(err) > 0.04:
			Input.action_press("move_left" if err > 0.0 else "move_right", clampf(absf(err) * 1.6, 0.15, 1.0))
		var hspeed := Vector2(heli.velocity.x, heli.velocity.z).length()
		Input.action_release("move_forward")
		Input.action_release("move_back")
		Input.action_release("sprint")
		Input.action_release("jump")
		if dist > 140.0:
			if absf(err) < 0.6: Input.action_press("move_forward")
			if heli.global_position.y < 95.0: Input.action_press("jump")
		elif dist > 6.0:
			var want_speed := clampf(dist * 0.18, 2.0, 22.0)
			if hspeed < want_speed and absf(err) < 0.5: Input.action_press("move_forward", 0.6)
			elif hspeed > want_speed + 2.0: Input.action_press("move_back", 0.8)
			if heli.global_position.y > clampf(dist * 0.5, 14.0, 95.0): Input.action_press("sprint", 0.7)
		else:
			if hspeed > 2.0: Input.action_press("move_back", 0.6)
			Input.action_press("sprint")
		if not stills.is_empty() and dist < stills[0]:
			await _still("fly_%dm" % int(stills[0]))
			stills.pop_front()
		if heli.is_landed() and dist < 30.0:
			landed = true
			break
	_release()
	await get_tree().create_timer(1.5).timeout
	await _still("fly_landed_ns_square")
	heli.exit_vehicle(player)
	await get_tree().create_timer(0.5).timeout
	var on_foot := player.current_vehicle == null
	_results["fly"] = {"completed": landed and on_foot, "landed": landed, "on_foot": on_foot, "heli": str(heli.global_position), "allowed": DowntownPlan.heli_exit_allowed(heli.global_position)}
	_log("fly landed=%s on_foot=%s at %s" % [landed, on_foot, heli.global_position])
	if on_foot:
		player.camera.current = true
		var t_walk := _elapsed() + 6.0
		while _elapsed() < t_walk:
			await get_tree().physics_frame
			player.yaw = lerp_angle(player.yaw, deg_to_rad(90.0), 0.05)
			Input.action_press("move_forward")
		_release()
		await _still("fly_walk_ns_square")

func _finish() -> void:
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var pct := func(q: float) -> float:
		return sorted[clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)] if not sorted.is_empty() else 0.0
	var mean := 0.0
	for v: float in sorted:
		mean += v
	mean /= maxf(1.0, sorted.size())
	var report := {"results": _results, "frames_saved": _frame, "frame_ms": {"n": sorted.size(), "mean": snappedf(mean, 0.01), "p50": snappedf(pct.call(0.5), 0.01), "p95": snappedf(pct.call(0.95), 0.01), "p99": snappedf(pct.call(0.99), 0.01), "max": snappedf(pct.call(1.0), 0.01)},
		"perf_sweep_ms": _perf, "note": "frame_ms excludes frames that carried a JPEG readback (encoding still lands on neighbours); perf_sweep_ms has no readback at all", "stats": world.get_meta("downtown_map_stats", {}), "log": _log_lines}
	var f := FileAccess.open(out_dir + "/review.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	if _jsonl:
		_jsonl.close()
	_log("done: %s frame p95 %.2f ms" % [JSON.stringify(_results), float(report["frame_ms"]["p95"])])
	Game.simulation_paused = true
	Sfx.shutdown_audio()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0)
