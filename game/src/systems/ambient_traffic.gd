class_name AmbientTraffic
extends Node3D
## Dense, camera-centred civilian traffic (street-life, Opus wave A).
##
## Critic 5: "In 06_driving the boulevard has zero traffic ... it reads as a
## test map." Twenty-six physics cars spread over a 640 m grid leave any one
## street empty. This system keeps a pool of lightweight AmbientVehicles on the
## left-hand lane graph *around the active camera* (the way open-world games
## stream traffic): two lanes each way, car following, red-light queues, left
## and straight turns through junctions, braking for people and other cars.
## Vehicles that fall far behind the camera are re-seeded ahead of it, out of
## view, so the street the player is looking at is always busy.

const POOL := 112
const LANE_OFFSETS: Array[float] = [4.6, 2.3]   # kerb lane (slow), median lane
const ENTRY := 11.0      # lane starts this far past a junction centre
const STOP := 12.0       # stop line this far before the next junction centre
const SPAWN_RADIUS := 175.0
const DESPAWN_RADIUS := 245.0
const MIN_GAP := 8.0
const ACCEL := 2.6
const DECEL := 6.5
const CELL := 16.0

var traffic: TrafficManager
var nodes: Array[Vector3] = []
var edges: Array[Dictionary] = []          # directed: a, b, dir, left, len, from, to
var _out_edges: Dictionary = {}            # node index -> Array[int]
var vehicles: Array[AmbientVehicle] = []
var _keys: Dictionary = {}                  # edge*2+lane -> Array[AmbientVehicle] sorted by s
var _rng := RandomNumberGenerator.new()
var _focus := Vector3.INF
var _pp_vel := Vector3.ZERO
var _last_pp := Vector3.ZERO
var _last_pp_ms := 0
var _cam_pos := Vector3.ZERO
var _cam_fwd := Vector3.FORWARD
var _grid: Dictionary = {}
var _grid_timer := 0.0
var _promoted: Array[Car] = []
var stats := {"relocated": 0, "cuts": 0, "promoted": 0}

func setup(t: TrafficManager) -> void:
	name = "AmbientTraffic"
	traffic = t
	nodes = t.nodes
	_rng.seed = Game.seed_value + 77
	_build_edges()
	var kinds := ["sedan", "sedan", "sedan", "taxi", "coupe", "van", "sedan", "coupe", "taxi", "van", "sedan", "bus"]
	# Car paint: original texture plus restrained multiplies (silver, white,
	# charcoal, navy, deep red); Singapore taxis in blue and yellow.
	var paints := [Color.WHITE, Color(0.78, 0.8, 0.84), Color(0.35, 0.36, 0.4), Color(0.46, 0.55, 0.78), Color(0.9, 0.9, 0.88), Color(0.62, 0.3, 0.28), Color(0.55, 0.6, 0.55)]
	for i in POOL:
		var v := AmbientVehicle.new()
		var kind: String = kinds[i % kinds.size()]
		var color: Color = paints[(i * 5 + i / 7) % paints.size()]
		if kind == "taxi":
			color = Color(0.35, 0.55, 1.0) if i % 2 == 0 else Color(1.0, 0.85, 0.3)
		elif kind == "bus":
			color = Color.WHITE if i % 24 < 12 else Color(0.62, 0.42, 0.62)
		v.manager = self
		v.setup_vehicle(kind, color)
		v.vmax = _rng.randf_range(9.0, 13.5) if kind != "bus" else 8.5
		add_child(v)
		v.global_position = Vector3(0, -60.0 - i * 0.1, 0)
		v.active = false
		v.visible = false
		vehicles.append(v)

func _build_edges() -> void:
	for i in nodes.size():
		_out_edges[i] = []
	for i in nodes.size():
		for j in nodes.size():
			if i == j:
				continue
			var d := nodes[j] - nodes[i]
			d.y = 0.0
			if not ((absf(d.x) < 0.5 and absf(absf(d.z) - 160.0) < 0.5) or (absf(d.z) < 0.5 and absf(absf(d.x) - 160.0) < 0.5)):
				continue
			var dir := d.normalized()
			edges.append({"a": nodes[i], "b": nodes[j], "dir": dir, "left": Vector3.UP.cross(dir).normalized(), "len": d.length(), "from": i, "to": j})
			_out_edges[i].append(edges.size() - 1)

func lane_point(e: int, lane: int, s: float) -> Vector3:
	var ed: Dictionary = edges[e]
	var p: Vector3 = ed["a"] + ed["dir"] * s + ed["left"] * LANE_OFFSETS[lane]
	p.y = 0.07
	return p

# ----------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	_update_focus()
	if Game.simulation_paused:
		return
	_grid_timer -= delta
	if _grid_timer <= 0.0:
		_grid_timer = 0.1
		_rebuild_grid()
	_rebuild_keys()
	for v in vehicles:
		if v.active:
			_drive(v, delta)
	_recycle(false)
	_tidy_promoted()
	if _debug:
		_debug_timer -= delta
		if _debug_timer <= 0.0:
			_debug_timer = 0.5
			_debug_dump()

var _debug := "--street-debug" in OS.get_cmdline_user_args()
var _debug_timer := 0.0
func _debug_dump() -> void:
	var p := Game.player_position
	var near: Array = []
	for v in vehicles:
		if v.active and v.global_position.distance_to(p) < 14.0:
			near.append("%s e%d l%d s%.1f v%.1f gap%.1f lead%.1f sig%s" % [str(v.global_position.round()), v.edge, v.lane, v.s, v.speed, v.obstacle_gap, _leader_gap(v, float(edges[v.edge]["len"]) - STOP), traffic.signal_allows(edges[v.edge]["dir"])])
	var others: Array = []
	for g in ["vehicles", "npcs"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and (n as Node3D).global_position.distance_to(p) < 9.0 and (n as Node3D).global_position.distance_to(p) > 0.5:
				others.append("%s:%s" % [n.get_class() if not n is Car else "Car", str((n as Node3D).global_position.round())])
	var pc = get_tree().get_first_node_in_group("player")
	var yaw := 0.0
	if pc and pc.current_vehicle:
		yaw = rad_to_deg(pc.current_vehicle.rotation.y)
		var cv: Car = pc.current_vehicle
		var hits: Array = []
		for i in cv.get_slide_collision_count():
			var c := cv.get_slide_collision(i)
			if c.get_normal().y < 0.65:
				hits.append("%s n%s" % [c.get_collider().name if c.get_collider() else "?", str(c.get_normal().snapped(Vector3.ONE * 0.1))])
		others.append("spd%.1f hits=%s" % [cv.forward_speed(), hits])
	print("[street-debug] t=%.1f player=%s yaw=%.0f mode=%d near=%s others=%s" % [Time.get_ticks_msec() / 1000.0, str(p.round()), yaw, Game.mode, near.slice(0, 4), others])

func _process(_delta: float) -> void:
	# Fixed-view captures run with the simulation paused; still seed the view.
	if Game.simulation_paused:
		_update_focus()

func _update_focus() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_cam_pos = cam.global_position
	var fwd := -cam.global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.05:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	_cam_fwd = flat
	var reach := clampf(_cam_pos.y * 1.85, 30.0, 180.0)
	var f := Vector3(_cam_pos.x, 0.0, _cam_pos.z) + flat * reach
	# Lead the focus along the player's motion so a driving player meets
	# traffic and people that were seeded out of sight ahead of time.
	var now_ms := Time.get_ticks_msec()
	if _last_pp_ms > 0 and now_ms > _last_pp_ms:
		var inst := (Game.player_position - _last_pp) / (float(now_ms - _last_pp_ms) / 1000.0)
		inst.y = 0.0
		if inst.length() < 60.0:
			_pp_vel = _pp_vel.lerp(inst, 0.1)
	_last_pp = Game.player_position
	_last_pp_ms = now_ms
	f += _pp_vel.limit_length(25.0) * 2.5
	var cut := _focus == Vector3.INF or f.distance_to(_focus) > 60.0
	_focus = f
	if cut:
		stats["cuts"] += 1
		_rebuild_keys()
		_recycle(true)
		_rebuild_keys()

## Re-seed vehicles that are far from the focus. On a camera cut everything
## outside the spawn radius is re-seeded at once; in continuous play only cars
## far behind are moved, and only to spots the camera cannot see.
func _recycle(cut: bool) -> void:
	var budget := POOL if cut else 3
	for v in vehicles:
		if budget <= 0:
			break
		if v.active:
			var d := Vector2(v.global_position.x - _focus.x, v.global_position.z - _focus.z).length()
			if cut:
				if d < SPAWN_RADIUS:
					continue
			elif d < DESPAWN_RADIUS:
				continue
		if _seed_vehicle(v, not cut):
			budget -= 1
			stats["relocated"] += 1

func _seed_vehicle(v: AmbientVehicle, hidden_only: bool) -> bool:
	for attempt in 24:
		var e := _rng.randi_range(0, edges.size() - 1)
		var ed: Dictionary = edges[e]
		var lo: float = ENTRY + 2.0
		var hi: float = float(ed["len"]) - STOP - 4.0
		var s := _rng.randf_range(lo, hi)
		var lane := 0 if _rng.randf() < 0.55 else 1
		var p := lane_point(e, lane, s)
		var dist := Vector2(p.x - _focus.x, p.z - _focus.z).length()
		# Bias towards the near field and towards what the camera faces.
		if dist > SPAWN_RADIUS or (dist > 90.0 and _rng.randf() < 0.55):
			continue
		var view := p - _cam_pos
		view.y = 0.0
		if not hidden_only and view.length() > 12.0 and view.normalized().dot(_cam_fwd) < 0.45 and _rng.randf() < 0.6:
			continue
		if hidden_only:
			var rel := p - _cam_pos
			rel.y = 0.0
			if rel.length() < 105.0 and rel.normalized().dot(_cam_fwd) > -0.2:
				continue
		if v.kind == "bus" and lane == 1:
			lane = 0
			p = lane_point(e, lane, s)
		if not _gap_free(e, lane, s):
			continue
		if _player_near(p, 9.0):
			continue
		_place(v, e, lane, s)
		return true
	return false

func _gap_free(e: int, lane: int, s: float) -> bool:
	var list: Array = _keys.get(e * 2 + lane, [])
	for other in list:
		if absf((other as AmbientVehicle).s - s) < MIN_GAP + 3.0:
			return false
	return true

func _player_near(p: Vector3, r: float) -> bool:
	return Vector2(p.x - Game.player_position.x, p.z - Game.player_position.z).length() < r

func _place(v: AmbientVehicle, e: int, lane: int, s: float) -> void:
	var old_key := v.edge * 2 + v.lane
	if v.active and _keys.has(old_key):
		_keys[old_key].erase(v)
	v.edge = e
	v.lane = lane
	v.s = s
	v.j_len = 0.0
	v.speed = v.vmax * _rng.randf_range(0.6, 1.0)
	v.next_edge = _choose_next(e)
	v.active = true
	v.visible = true
	v.collision_layer = 8
	v.obstacle_gap = INF
	v.scan_timer = _rng.randf() * 0.15
	var key := e * 2 + lane
	if not _keys.has(key):
		_keys[key] = []
	_keys[key].append(v)
	_apply_transform(v)

func _choose_next(e: int) -> int:
	var ed: Dictionary = edges[e]
	var options: Array = _out_edges.get(int(ed["to"]), [])
	var straight := -1
	var left := -1
	var right := -1
	for o in options:
		var d2: Vector3 = edges[o]["dir"]
		var dot: float = (ed["dir"] as Vector3).dot(d2)
		if dot > 0.9:
			straight = o
		elif dot < -0.9:
			continue
		elif (ed["left"] as Vector3).dot(d2) > 0.9:
			left = o
		else:
			right = o
	# Left-hand traffic: straight and near-side (left) turns never cross the
	# opposing flow; far-side (right) turns are only taken at the map edge.
	if straight >= 0 and left >= 0:
		return straight if _rng.randf() < 0.68 else left
	if straight >= 0:
		return straight
	if left >= 0:
		return left
	return right

func _rebuild_keys() -> void:
	_keys.clear()
	for v in vehicles:
		if not v.active:
			continue
		var key := v.edge * 2 + v.lane
		if not _keys.has(key):
			_keys[key] = []
		_keys[key].append(v)
	for key in _keys:
		(_keys[key] as Array).sort_custom(func(a, b): return a.s < b.s)

func _drive(v: AmbientVehicle, delta: float) -> void:
	var ed: Dictionary = edges[v.edge]
	var s_end: float = float(ed["len"]) - STOP
	var target := v.vmax
	# 1. Car following, including the tail of the lane we are about to enter.
	var gap := _leader_gap(v, s_end)
	target = minf(target, _stop_speed(gap - 3.0))
	# 2. Signals: hold at the stop line unless already committed.
	if v.s <= s_end:
		var to_line := s_end - v.s
		var committed := to_line < 3.5 and v.speed > 5.0
		if not traffic.signal_allows(ed["dir"]) and not committed:
			target = minf(target, _stop_speed(to_line - 0.5))
		# Keep the box clear: do not enter the junction unless the exit lane
		# has room for this car on the far side.
		elif not committed and v.next_edge >= 0 and _exit_room(v) < v.dims.z + 2.5:
			target = minf(target, _stop_speed(to_line - 0.5))
		# Give way to a player-driven vehicle crossing or about to cross.
		elif not committed and to_line < 30.0 and _player_in_junction(ed["b"], v):
			target = minf(target, _stop_speed(to_line - 0.5))
		if v.next_edge >= 0 and to_line < 22.0 and (edges[v.next_edge]["dir"] as Vector3).dot(ed["dir"]) < 0.5:
			target = minf(target, 6.5)
	else:
		target = minf(target, 6.5 if v.j_len > 0.0 and absf((v.j_p2 - v.j_c).normalized().dot((v.j_c - v.j_p0).normalized())) < 0.5 else v.vmax)
	# 3. People, the player and physics cars in the lane corridor ahead.
	v.scan_timer -= delta
	if v.scan_timer <= 0.0:
		v.scan_timer = 0.15
		v.obstacle_gap = _scan_obstacles(v)
	if v.obstacle_gap < INF:
		target = minf(target, _stop_speed(v.obstacle_gap - 1.6))
		if v.obstacle_gap < 0.6:
			v.speed = 0.0
	# Junction deadlock breaker: a car held inside the box for long creeps on.
	if v.speed < 0.2 and v.j_len > 0.0 and v.s < ENTRY:
		v.stuck_time += delta
	else:
		v.stuck_time = 0.0 if v.speed > 1.0 else v.stuck_time
	var rate := ACCEL if target > v.speed else DECEL * (1.6 if target < 0.5 else 1.0)
	v.speed = move_toward(v.speed, target, rate * delta)
	v.set_braking(target < v.speed - 0.4 or (v.speed < 0.3 and target < 0.5))
	v.s += v.speed * delta
	if v.j_len <= 0.0 and v.s >= s_end and v.next_edge >= 0:
		_enter_junction(v)
	elif v.j_len > 0.0 and v.s >= ENTRY:
		v.j_len = 0.0
	_apply_transform(v)

func _stop_speed(distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	return sqrt(2.0 * 3.5 * distance)

func _leader_gap(v: AmbientVehicle, s_end: float) -> float:
	var list: Array = _keys.get(v.edge * 2 + v.lane, [])
	var idx := list.find(v)
	var half := v.dims.z * 0.5
	if idx >= 0 and idx < list.size() - 1:
		var lead: AmbientVehicle = list[idx + 1]
		return lead.s - v.s - half - lead.dims.z * 0.5
	if v.next_edge < 0:
		return INF
	var nxt: Array = _keys.get(v.next_edge * 2 + v.lane, [])
	if nxt.is_empty():
		return INF
	var tail: AmbientVehicle = nxt[0]
	var through := 23.0
	return (s_end - v.s) + through + (tail.s - ENTRY) - half - tail.dims.z * 0.5

func _player_in_junction(node: Vector3, v: AmbientVehicle) -> bool:
	if Game.mode != Game.MODE_CAR:
		return false
	var p := Game.player_position
	if absf(p.x - node.x) > 22.0 or absf(p.z - node.z) > 22.0:
		return false
	# A player queued behind this car is not crossing in front of it.
	var rel := p - v.global_position
	return rel.dot(-v.global_transform.basis.z) > 2.0

func _exit_room(v: AmbientVehicle) -> float:
	var nxt: Array = _keys.get(v.next_edge * 2 + v.lane, [])
	if nxt.is_empty():
		return INF
	var tail: AmbientVehicle = nxt[0]
	return tail.s - ENTRY - tail.dims.z * 0.5

func _enter_junction(v: AmbientVehicle) -> void:
	var overflow := v.s - (float(edges[v.edge]["len"]) - STOP)
	var p0 := lane_point(v.edge, v.lane, float(edges[v.edge]["len"]) - STOP)
	var ne := v.next_edge
	var lane := v.lane
	var p2 := lane_point(ne, lane, ENTRY)
	var d1: Vector3 = edges[v.edge]["dir"]
	var d2: Vector3 = edges[ne]["dir"]
	var c: Vector3
	if absf(d1.dot(d2)) > 0.9:
		c = (p0 + p2) * 0.5
	else:
		# Intersection of the incoming and outgoing lane lines.
		var b: Vector3 = edges[v.edge]["b"]
		c = b + (edges[v.edge]["left"] as Vector3) * LANE_OFFSETS[lane] + (edges[ne]["left"] as Vector3) * LANE_OFFSETS[lane]
		c.y = p0.y
	v.j_p0 = p0
	v.j_c = c
	v.j_p2 = p2
	v.j_len = maxf(4.0, (p0.distance_to(c) + c.distance_to(p2) + p0.distance_to(p2)) * 0.5)
	v.edge = ne
	v.s = ENTRY - v.j_len + overflow
	v.next_edge = _choose_next(ne)

func _apply_transform(v: AmbientVehicle) -> void:
	var pos: Vector3
	var fwd: Vector3
	if v.j_len > 0.0 and v.s < ENTRY:
		var t := clampf(1.0 - (ENTRY - v.s) / v.j_len, 0.0, 1.0)
		var a := v.j_p0.lerp(v.j_c, t)
		var b := v.j_c.lerp(v.j_p2, t)
		pos = a.lerp(b, t)
		fwd = (b - a)
		if fwd.length() < 0.001:
			fwd = v.j_p2 - v.j_p0
	else:
		pos = lane_point(v.edge, v.lane, v.s)
		fwd = edges[v.edge]["dir"]
	fwd.y = 0.0
	fwd = fwd.normalized()
	var basis := Basis.looking_at(fwd, Vector3.UP)
	v.global_transform = Transform3D(basis, pos)

# --------------------------------------------------------------- obstacles
func _rebuild_grid() -> void:
	_grid.clear()
	for group in ["npcs", "vehicles"]:
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node3D
			if node == null or not node.visible:
				continue
			if node is NPC and (node as NPC).state == NPC.State.DEAD:
				continue
			_grid_add(node.global_position, node)
	for v in vehicles:
		if v.active:
			_grid_add(v.global_position, v)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.visible:
		_grid_add(player.global_position, player)

func _grid_add(p: Vector3, node: Node3D) -> void:
	var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append(node)

## Clear distance from this car's front bumper to the nearest person or
## physics vehicle in (or overlapping) its lane corridor, or INF. Physics cars
## are tested by their four footprint corners, so a car parked diagonally
## across the lane, or one already alongside, still stops the traffic. Cars
## far from the camera do not look.
func _scan_obstacles(v: AmbientVehicle) -> float:
	var here := v.global_position
	if Vector2(here.x - _cam_pos.x, here.z - _cam_pos.z).length() > 170.0:
		return INF
	var fwd := -v.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var left := Vector3.UP.cross(fwd)
	var half_len := v.dims.z * 0.5
	var half_w := v.dims.x * 0.5 + (0.08 if v.kind != "bus" else 0.0)
	var probe := here + fwd * 9.0
	var cx := floori(probe.x / CELL)
	var cz := floori(probe.z / CELL)
	var best := INF
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for n in _grid.get(Vector2i(cx + dx, cz + dz), []):
				if not is_instance_valid(n):
					continue
				var node := n as Node3D
				var points: Array[Vector3] = []
				var radius := 0.0
				if node is AmbientVehicle:
					if node == v or (v.stuck_time > 6.0 and v.j_len > 0.0):
						continue
					var ab := node.global_transform.basis
					var abx := Vector3(ab.x.x, 0, ab.x.z).normalized() * ((node as AmbientVehicle).dims.x * 0.5)
					var abz := Vector3(ab.z.x, 0, ab.z.z).normalized() * ((node as AmbientVehicle).dims.z * 0.5)
					var ac := node.global_position
					points = [ac, ac + abx + abz, ac + abx - abz, ac - abx + abz, ac - abx - abz]
				elif node is Car:
					# A player car that is already behind our front axle is left
					# behind rather than waited for.
					if (node as Car).driver_is_player and (node.global_position - here).dot(fwd) < 0.0:
						continue
					var b := node.global_transform.basis
					# The player's car gets extra room: it does not keep to lanes.
					var pad := 0.6 if (node as Car).driver_is_player else 0.0
					var bx := Vector3(b.x.x, 0, b.x.z).normalized() * (0.93 + pad)
					var bz := Vector3(b.z.x, 0, b.z.z).normalized() * (2.4 + pad)
					var c := node.global_position
					points = [c, c + bx + bz, c + bx - bz, c - bx + bz, c - bx - bz]
				elif node is Helicopter:
					continue
				else:
					points = [node.global_position]
					radius = 0.45
				for p in points:
					var d: Vector3 = p - here
					var ahead := d.dot(fwd)
					if ahead < -half_len or ahead > 20.0:
						continue
					if absf(d.dot(left)) > half_w + radius:
						continue
					best = minf(best, maxf(0.0, ahead - half_len - radius))
	return best

# --------------------------------------------------------------- carjacking
## Swap a stopped ambient car for a real, drivable Car and hand it to the
## player. The ambient body is recycled out of sight.
func promote(v: AmbientVehicle, player: Node) -> void:
	if not v.active:
		return
	var kind := v.kind if v.kind in ["sedan", "coupe", "van"] else "sedan"
	var car := Car.new()
	car.kind = kind
	traffic.add_child(car)
	car.global_transform = v.global_transform
	if car._provider_root != null and v.paint != Color.WHITE:
		AssetLibrary.tint(car._provider_root, v.paint)
	_promoted.append(car)
	stats["promoted"] += 1
	v.active = false
	v.visible = false
	v.collision_layer = 0
	v.speed = 0.0
	v.global_position = Vector3(0, -60.0, 0)
	_rebuild_keys()
	car.interact(player)
	Events.notify.emit("Driver bails out. Witnesses are looking.", "warn")

func _tidy_promoted() -> void:
	if _promoted.size() <= 4:
		return
	for i in range(_promoted.size() - 1, -1, -1):
		var c := _promoted[i]
		if not is_instance_valid(c):
			_promoted.remove_at(i)
			continue
		if c.driver_is_player or c.has_ai:
			continue
		if c.global_position.distance_to(Game.player_position) > 200.0:
			_promoted.remove_at(i)
			c.queue_free()
			return

# ----------------------------------------------------------------- QA view
## Vehicles within `radius` of `p` (active only).
func count_near(p: Vector3, radius: float) -> int:
	var n := 0
	for v in vehicles:
		if v.active and v.global_position.distance_to(p) < radius:
			n += 1
	return n

func count_active() -> int:
	var n := 0
	for v in vehicles:
		if v.active:
			n += 1
	return n
