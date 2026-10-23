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
	if _headless():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	_frame += 1
	img.save_jpg("%s/frames/f%05d.jpg" % [out_dir, _frame], 0.85)
	if _jsonl:
		var a := player.controlled_actor()
		_jsonl.store_line(JSON.stringify({"file": "f%05d.jpg" % _frame, "seconds": snappedf(_elapsed(), 0.01), "phase": _phase, "pos": str(a.global_position.snapped(Vector3.ONE * 0.1)) if a else ""}))

## Headless runs (no frames are drawn) skip stills, frame grabs, the fixed
## views and the perf sweep, so the drive / walk / fly legs can be validated
## without a GPU (integration, wave M).
static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _still(label: String) -> void:
	if _headless():
		_log("still %s at %s (headless: no image)" % [label, player.controlled_actor().global_position])
		return
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

## Sign of the sharpest upcoming heading change (+ left, - right).
func _turn_sign(path: Array[Vector3], i: int, dist: float) -> float:
	var a := _ahead(path, i, 6.0) - path[i]
	var b := _ahead(path, i, dist) - _ahead(path, i, maxf(dist - 12.0, 6.0))
	a.y = 0.0
	b.y = 0.0
	if a.length() < 0.1 or b.length() < 0.1:
		return 0.0
	return signf(a.normalized().signed_angle_to(b.normalized(), Vector3.UP))

const LANE_SHIFT := 3.5

## Right of the path's travel direction at index i (ground plane).
static func _path_right(path: Array[Vector3], i: int) -> Vector3:
	var j := clampi(i, 0, path.size() - 2)
	var f := path[j + 1] - path[j]
	f.y = 0.0
	if f.length() < 0.01:
		return Vector3.ZERO
	f = f.normalized()
	return Vector3(-f.z, 0.0, f.x)

## Distance along the route to the nearest vehicle or pedestrian inside a
## corridor of half width `half_w` that FOLLOWS THE PATH (shifted `shift`
## metres to the right of travel) for `look` metres from the car, INF when
## clear. Street-life ambient vehicles, legacy AI cars and walkers count;
## vehicles in either direction count, so the overtake check also sees
## oncoming traffic in the lane it moves into. Following the path matters at
## corners: a straight-ahead probe saw the promenade crowd past a left turn
## and waited there for ever.
var _gap_node: Node3D = null

func _gap_path(path: Array[Vector3], i: int, actor: Node3D, shift: float, look: float, half_w: float) -> float:
	var origin := actor.global_position + _path_right(path, i) * shift
	var poly: Array[Vector3] = [Vector3(origin.x, 0.0, origin.z)]
	var cum: Array[float] = [0.0]
	var k := i + 1
	while k < path.size() and cum[cum.size() - 1] < look:
		var q := path[k] + _path_right(path, mini(k, path.size() - 2)) * shift
		q.y = 0.0
		cum.append(cum[cum.size() - 1] + poly[poly.size() - 1].distance_to(q))
		poly.append(q)
		k += 1
	var fwd := -actor.global_transform.basis.z
	fwd.y = 0.0
	var obs: Array = []
	if traffic.ambient != null:
		for v in traffic.ambient.vehicles:
			if is_instance_valid(v) and v.active and v.visible:
				obs.append([v.global_position, v.dims.x * 0.5, v.dims.z * 0.5, false, v])
	for c in traffic.cars:
		if is_instance_valid(c) and c != actor and not c.disabled:
			obs.append([c.global_position, 0.95, 2.3, false, c])
	for pd in traffic.peds:
		if is_instance_valid(pd) and pd.visible:
			obs.append([pd.global_position, 0.35, 0.35, true, pd])
	var best := INF
	_gap_node = null
	for e: Array in obs:
		var o: Vector3 = e[0]
		var rel := o - actor.global_position
		rel.y = 0.0
		if rel.length() > look + 8.0 or rel.dot(fwd) < -1.0:
			continue
		if absf(o.y - actor.global_position.y) > 2.5:
			continue
		var o2 := Vector2(o.x, o.z)
		for sgi in poly.size() - 1:
			var a2 := Vector2(poly[sgi].x, poly[sgi].z)
			var b2 := Vector2(poly[sgi + 1].x, poly[sgi + 1].z)
			var cp := Geometry2D.get_closest_point_to_segment(o2, a2, b2)
			if cp.distance_to(o2) < half_w + float(e[1]):
				var along := cum[sgi] + a2.distance_to(cp) - float(e[2]) - 2.3
				if bool(e[3]) and along > 14.0:
					break   # walkers only matter close in
				if maxf(along, 0.0) < best:
					best = maxf(along, 0.0)
					_gap_node = e[4]
				break
	return best

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
	# `--downtown-legs=drive,walk,fly,views` picks legs (iteration only; the
	# default runs everything).
	var legs := "drive,walk,fly,views"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--downtown-legs="):
			legs = arg.trim_prefix("--downtown-legs=")
	if "drive" in legs:
		await _drive_leg()
	if "walk" in legs:
		await _walk_leg()
	if "fly" in legs:
		await _fly_leg()
	_recording = false
	_release()
	if not _headless() and "views" in legs:
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
	# downtown-polish (wave S): Marina Centre, the skyline behind MBS and the
	# CBD from helicopter height, and the opened Raffles / Bayfront corner
	{"name": "dtx_heli_marina_centre", "pos": Vector3(-380.0, 165.0, -520.0), "look": Vector3(-770.0, 30.0, -780.0), "fov": 62.0},
	{"name": "dtx_heli_behind_mbs", "pos": Vector3(-430.0, 175.0, -330.0), "look": Vector3(-110.0, 60.0, -1000.0), "fov": 62.0},
	{"name": "dtx_heli_cbd", "pos": Vector3(-760.0, 170.0, -580.0), "look": Vector3(-420.0, 70.0, -90.0), "fov": 62.0},
	{"name": "dtx_raffles_bayfront_corner", "pos": Vector3(-786.0, 1.6, -690.0), "look": Vector3(-770.0, 4.0, -800.0), "fov": 66.0},
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
	# downtown-polish (wave S): the loop starts and ends on Collyer Quay (the
	# heritage-avenue approach and its left turn are not part of the owner's
	# route and cost minutes behind the district signals).
	var centre: Array = [Vector3(-60, 0, -320), Vector3(-470, 0, -320)]
	var offs: Array = [3.4]
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
	var t_end := _elapsed() + 900.0
	var stills := {"esplanade_bridge": Vector3(-600, 0, -360), "raffles_avenue": Vector3(-790, 0, -600), "bayfront_bridge": Vector3(-420, 0, -780), "bayfront_avenue": Vector3(0, 0, -780), "marina_boulevard": Vector3(400, 0, -520)}
	var stuck_t := 0.0
	var max_deck := 0.0
	# downtown-polish (wave S): the rendered drive now shares the road with the
	# street-life traffic (queues at signals, platoons, turning cars). The
	# driver behaves like a player: it follows the car ahead at a safe gap,
	# waits behind queues, and after a few seconds blocked overtakes one lane
	# toward the centre (across the centre line on two-lane streets when the
	# corridor ahead is clear), returning to its lane once past. Reversing is
	# kept only for being stuck on geometry with nothing ahead.
	var shift := 0.0
	var shift_target := 0.0
	var blocked_t := 0.0
	var shift_hold := 0
	var overtakes := 0
	var waits := 0.0
	var tows := 0
	var stall_node: Node3D = null
	var stall_for := 0.0
	while _elapsed() < t_end:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		i = _closest(path, car.global_position, i)
		if i >= path.size() - 2:
			break
		var kmh := car.speed_kmh()
		var turn := maxf(_turn_ahead(path, i, 34.0), _turn_ahead(path, i, 52.0))
		# Integration (wave M): right-angle RIGHT turns (the wide crossing turn
		# in left-hand traffic) overshot at 24 km/h into the block / landmark
		# collision now framing those corners; take them at 16 km/h. Left turns
		# keep 24 km/h (slower oversteers into the kerb). Wave S: the corners
		# were opened up (corner plazas, kerb returns), so 20 km/h holds.
		var corner_kmh := 20.0 if _turn_sign(path, i, 52.0) < 0.0 else 22.0
		var target_kmh := 72.0 if turn < 0.25 else (corner_kmh if turn > 0.9 else 40.0)
		shift = move_toward(shift, shift_target, 2.2 * dt)
		var gap := _gap_path(path, i, car, shift, 46.0, 1.6)
		if gap < INF:
			# brake to stop ~6 m behind whatever is ahead (4 m/s^2)
			var allow := sqrt(2.0 * 4.0 * maxf(gap - 6.5, 0.0)) * 3.6
			target_kmh = minf(target_kmh, allow)
		var blocker := _gap_node
		if gap < 14.0 and kmh < 6.0:
			blocked_t += dt
			waits += dt
			if blocker != stall_node:
				stall_node = blocker
				stall_for = 0.0
			stall_for += dt
		else:
			blocked_t = 0.0
			stall_for = 0.0
		# A street-life car that has sat stalled in front of us for 45 s with
		# every lane around it blocked is recycled the way the traffic system
		# recycles its own gridlocked cars (logged as a tow; footage shows it).
		if stall_for > 45.0 and is_instance_valid(stall_node) and stall_node is AmbientVehicle and traffic.ambient != null:
			_log("tow: ambient %s stalled 45 s ahead at %s" % [stall_node.name, stall_node.global_position])
			if not traffic.ambient._seed_vehicle(stall_node, true):
				traffic.ambient._park_offscreen(stall_node)
			traffic.ambient._rebuild_keys()
			tows += 1
			stall_for = 0.0
			stall_node = null
		if blocked_t > 12.0:
			# still boxed in (a stalled queue, or the lane we moved to stopped):
			# take whichever lane offset has the clearest corridor, own lane first
			for cand: float in [0.0, LANE_SHIFT, LANE_SHIFT * 2.0]:
				if is_equal_approx(cand, shift_target):
					continue
				if _gap_path(path, i, car, cand, 34.0, 1.6) > 28.0:
					shift_target = cand
					shift_hold = i + 14
					overtakes += 1
					_log("change lane to offset %.1f at %s" % [cand, car.global_position])
					break
			blocked_t = 0.0
		# overtake on straights after 5 s; anywhere short of a right-angle
		# corner after 10 s (a queue that never moves is a stalled car)
		elif shift_target == 0.0 and ((blocked_t > 5.0 and turn < 0.5) or (blocked_t > 10.0 and turn < 0.9)) and _gap_path(path, i, car, LANE_SHIFT, 40.0, 1.6) > 34.0:
			shift_target = LANE_SHIFT
			shift_hold = i + 14
			overtakes += 1
			blocked_t = 0.0
			_log("overtake at %s (gap %.1f m)" % [car.global_position, gap])
		elif shift_target != 0.0 and i > shift_hold:
			if _gap_path(path, i, car, 0.0, 26.0, 1.6) > 24.0 or turn > 0.5:
				shift_target = 0.0
		var tgt := _ahead(path, i, clampf(kmh * 0.32, 9.0, 22.0)) + _path_right(path, mini(i + 2, path.size() - 2)) * shift
		_steer(car, tgt, 2.6)
		Input.action_release("move_forward")
		Input.action_release("move_back")
		if kmh < target_kmh:
			Input.action_press("move_forward")
		elif kmh > target_kmh + 5.0:
			Input.action_press("move_back")
		max_deck = maxf(max_deck, car.global_position.y)
		for key: String in stills.keys():
			if Vector2(car.global_position.x - stills[key].x, car.global_position.z - stills[key].z).length() < 12.0:
				stills.erase(key)
				await _still("drive_" + key)
				break
		if Input.is_action_pressed("move_forward") and kmh < 3.0 and gap > 14.0:
			stuck_t += dt
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
	_results["drive"] = {"completed": done, "seconds": snappedf(_elapsed(), 0.1), "max_y": snappedf(max_deck, 0.01), "end": str(car.global_position),
		"overtakes": overtakes, "tows": tows, "waiting_s": snappedf(waits, 0.1)}
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
	# Integration (wave M): with the landmarks present the route climbs the
	# Merlion Park terrace steps from the promenade, crosses the terrace, then
	# passes the One Fullerton pavilions to the Jubilee landing plaza.
	var pts: Array[Vector3] = [Vector3(-440, 0, -338), Vector3(-458, 0, -344), Vector3(-460, 0, -372), Vector3(-488, 0, -380), Vector3(-521, 0, -384), Vector3(-521, 0, -400), Vector3(-657.5, 0, -400), Vector3(-657, 0, -409), Vector3(-648, 0, -440), Vector3(-648, 0, -560)]
	# downtown-polish (wave S): the owner's full walk continues down the
	# Esplanade waterfront, along the Marina Promenade, up the Helix Bridge
	# landing ramp, over the channel on the helix deck and down to the foot of
	# Marina Bay Sands (tower 1's east leg).
	pts.append_array([Vector3(-647, 0, -630), Vector3(-647, 0, -659), Vector3(-641, 0, -666), Vector3(-560, 0, -666), Vector3(-500, 0, -666), Vector3(-488, 0, -668), Vector3(-489, 0, -700), Vector3(-492, 0, -733), Vector3(-498, 0, -741), Vector3(-497, 0, -745.2), Vector3(-487, 0, -745.4)])
	var helix_from: int = pts.size()
	for u: float in [0.04, 0.12, 0.22, 0.32, 0.42, 0.5, 0.58, 0.68, 0.78, 0.88, 0.96, 1.0]:
		var hb: Dictionary = DowntownPlan.BRIDGES["helix_bridge"]
		var a: Vector3 = hb["from"]
		var b: Vector3 = hb["to"]
		pts.append(Vector3(lerpf(a.x, b.x, u), 0.0, lerpf(a.z, b.z, u) - 6.0 * sin(PI * u)))
	pts.append_array([Vector3(-258, 0, -745), Vector3(-247, 0, -749), Vector3(-241, 0, -757)])
	var k := 0
	var t_end := _elapsed() + 240.0
	var stills := {2: "walk_peninsula", 6: "walk_jubilee_bridge", 9: "walk_esplanade_waterfront", 13: "walk_marina_promenade", helix_from + 4: "walk_helix_bridge", pts.size() - 1: "walk_mbs"}
	var max_y := 0.0
	var stall_p := player.global_position
	var stall_t := _elapsed()
	while _elapsed() < t_end and k < pts.size():
		await get_tree().physics_frame
		if player.global_position.distance_to(stall_p) > 1.0:
			stall_p = player.global_position
			stall_t = _elapsed()
		elif _elapsed() - stall_t > 3.0:
			# a walker who bumps a trunk or post steps sideways and carries on
			_log("walk stalled before waypoint %d %s at %s: side-step" % [k, pts[k], player.global_position])
			stall_t = _elapsed()
			var step_dir := "move_left" if (k + int(_elapsed())) % 2 == 0 else "move_right"
			Input.action_release("sprint")
			Input.action_press(step_dir)
			await get_tree().create_timer(0.7).timeout
			Input.action_release(step_dir)
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
	if k >= pts.size():
		# arrival: turn to look up at Marina Bay Sands (tower 1)
		var mbs: Vector3 = DowntownPlan.ANCHORS["marina_bay_sands"]["pos"] + Vector3(-98.0, 0.0, -10.0)
		var dm := mbs - player.global_position
		var want_m := atan2(-dm.x, -dm.z)
		var t_turn := _elapsed() + 1.6
		while _elapsed() < t_turn:
			await get_tree().physics_frame
			player.yaw = lerp_angle(player.yaw, want_m, 0.08)
		await _still("walk_mbs_arrival")
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
