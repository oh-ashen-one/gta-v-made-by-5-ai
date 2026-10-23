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
const DtBridges := preload("res://src/world/downtown/bridges.gd")
const Rules := preload("res://src/systems/traffic_rules.gd")
const LANE_OFFSETS: Array[float] = [4.6, 2.3]   # kerb lane (slow), median lane
const ENTRY := 11.0      # lane starts this far past a junction centre
const STOP := 12.0       # stop line this far before the next junction centre
const SPAWN_RADIUS := 175.0
const DESPAWN_RADIUS := 245.0
const MIN_GAP := 8.0
const ACCEL := 2.6
const DECEL := 6.5
const CELL := 16.0
## Integration fixes (pre-integrator, wave B):
## - the opening five-foot-way spawn stretch stays clear of ambient vehicles
##   so the player is never wedged between a parked car and a stopped bus;
## - a vehicle stalled for GRIDLOCK_RESET s is re-seeded out of sight, which
##   dissolves junction gridlock without a visible pop;
## - a vehicle stalled next to the player on foot is moved away after
##   WEDGE_RESET s even if visible (safety over continuity).
const OPENING_CLEAR := 34.0
const GRIDLOCK_RESET := 18.0
const WEDGE_RESET := 4.0
const WEDGE_RADIUS := 7.0
const DEADLOCK_RESET := 6.0
const GIVE_UP := 10.0
const FAR_SIM := 130.0
const FAR_TICKS := 3
var _tick := 0

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
var stats := {"relocated": 0, "cuts": 0, "promoted": 0, "unstuck": 0}

func setup(t: TrafficManager) -> void:
	name = "AmbientTraffic"
	traffic = t
	# A copy: the downtown graph appends nodes here, never to the legacy
	# 5 x 5 traffic_nodes that tests and the route driver index.
	nodes = t.nodes.duplicate()
	_rng.seed = Game.seed_value + 77
	_build_edges()
	_legacy_count = nodes.size()
	if t.world != null:
		adopt_downtown(t.world.downtown_graph)
	annotate_rules()
	# Street-life D: no procedural box buses (critic: "box-primitive buses read
	# as blockouts"); the stream is the provider sedan/coupe/van art.
	var kinds := ["sedan", "taxi", "sedan", "coupe", "van", "sedan", "taxi", "coupe", "sedan", "van", "taxi", "sedan"]
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
			_add_edge(i, j, LANE_OFFSETS, true, ENTRY, STOP, 0.0, 0.0)

## One directed lane edge. offs: lane-centre offsets left of the centreline,
## kerb lane first; entry/stop: lane start past the from-node and stop line
## before the to-node; y0/y1: road surface height at each end (bridge decks).
func _add_edge(i: int, j: int, offs: Array, signal_held: bool, entry: float, stop: float, y0: float, y1: float) -> void:
	var d := nodes[j] - nodes[i]
	d.y = 0.0
	var dir := d.normalized()
	edges.append({"a": Vector3(nodes[i].x, 0.0, nodes[i].z), "b": Vector3(nodes[j].x, 0.0, nodes[j].z), "dir": dir, "left": Vector3.UP.cross(dir).normalized(),
		"len": d.length(), "from": i, "to": j, "offs": offs, "signal": signal_held, "entry": entry, "stop": stop, "y0": y0, "y1": y1})
	_out_edges[i].append(edges.size() - 1)

# ------------------------------------------------------- downtown (wave M)
## Adopt the downtown-map road graph (loop/DOWNTOWN_PLAN.md section 5):
## {"nodes": Array[Vector3], "edges": Array[Vector2i] (undirected),
## "lanes": Array[int] (per direction), "links": Array[Vector2i] (downtown
## node -> legacy traffic_nodes index)}. Every downtown edge becomes two
## directed lane edges; linked or coincident nodes merge with the legacy
## grid, so lane traffic flows between the district and the new roads.
## Signals hold only at real junctions (3+ roads); bends are driven through.
## Returns the number of directed edges added (0 for an empty graph).
const DT_LANE_W := 3.5
func adopt_downtown(g: Dictionary) -> int:
	if g.is_empty() or not g.has("nodes") or not g.has("edges"):
		return 0
	var dn: Array = g["nodes"]
	var link := {}
	for l in g.get("links", []):
		link[int((l as Vector2i).x)] = int((l as Vector2i).y)
	var legacy := nodes.size()
	var index: Array[int] = []
	for i in dn.size():
		var p: Vector3 = dn[i]
		var found := -1
		if link.has(i) and int(link[i]) >= 0 and int(link[i]) < legacy:
			found = int(link[i])
		else:
			for k in nodes.size():
				if Vector2(nodes[k].x - p.x, nodes[k].z - p.z).length() < 1.5:
					found = k
					break
		if found < 0:
			nodes.append(p)
			found = nodes.size() - 1
			_out_edges[found] = []
		index.append(found)
	var degree := {}
	for e in g["edges"]:
		var ev := e as Vector2i
		for k in [index[ev.x], index[ev.y]]:
			degree[k] = int(degree.get(k, 0)) + 1
	var lanes: Array = g.get("lanes", [])
	var before := edges.size()
	for n in g["edges"].size():
		var ev: Vector2i = g["edges"][n]
		var a := index[ev.x]
		var b := index[ev.y]
		if a == b:
			continue
		var per_dir := clampi(int(lanes[n]) if n < lanes.size() else 1, 1, 4)
		var median := _plan_median(dn[ev.x], dn[ev.y])
		var offs: Array[float] = [(per_dir - 0.5) * DT_LANE_W + median * 0.5]
		if per_dir >= 2:
			offs.append((per_dir - 1.5) * DT_LANE_W + median * 0.5)
		var flat := Vector2(nodes[b].x - nodes[a].x, nodes[b].z - nodes[a].z).length()
		for pair in [[a, b, (dn[ev.x] as Vector3).y, (dn[ev.y] as Vector3).y], [b, a, (dn[ev.y] as Vector3).y, (dn[ev.x] as Vector3).y]]:
			var junction_from := int(degree.get(pair[0], 0)) >= 3 or int(pair[0]) < legacy
			var junction_to := int(degree.get(pair[1], 0)) >= 3 or int(pair[1]) < legacy
			var entry := ENTRY if junction_from else 3.0
			var stop := STOP if junction_to else 3.0
			# Short links keep a drivable stretch between the two ends.
			var room := flat - entry - stop
			if room < 8.0:
				var k := maxf(0.2, (flat - 8.0) / maxf(1.0, entry + stop))
				entry *= k
				stop *= k
			_add_edge(int(pair[0]), int(pair[1]), offs, junction_to, entry, stop, float(pair[2]), float(pair[3]))
			edges[edges.size() - 1]["dt"] = true
	stats["downtown_edges"] = edges.size() - before
	return edges.size() - before

## Median width of the DowntownPlan road this segment lies on (0 if none).
func _plan_median(p: Vector3, q: Vector3) -> float:
	var mid := (p + q) * 0.5
	for road_name in DowntownPlan.ROADS:
		var road: Dictionary = DowntownPlan.ROADS[road_name]
		var pts: Array = road["pts"]
		for k in pts.size() - 1:
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[k + 1]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var t := clampf(Vector2(mid.x - a.x, mid.z - a.z).dot(ab) / maxf(0.01, ab.length_squared()), 0.0, 1.0)
			if Vector2(mid.x - a.x, mid.z - a.z).distance_to(ab * t) < 2.0:
				return float(road.get("median", 0.0))
	return 0.0

func _entry(e: int) -> float:
	return float(edges[e]["entry"])

func _s_end(e: int) -> float:
	return float(edges[e]["len"]) - float(edges[e]["stop"])

func _off(e: int, lane: int) -> float:
	var offs: Array = edges[e]["offs"]
	return float(offs[mini(lane, offs.size() - 1)])

## Lane index valid on edge e (a two-lane approach feeding a one-lane road).
func _lane_for(e: int, lane: int) -> int:
	return mini(lane, (edges[e]["offs"] as Array).size() - 1)

func _signal_ok(e: int) -> bool:
	if int(edges[e].get("control", Rules.CONTROL_SIGNAL if edges[e]["signal"] else Rules.CONTROL_NONE)) != Rules.CONTROL_SIGNAL:
		return true
	return traffic.signal_allows(edges[e]["dir"])

# ------------------------------------------------- road rules (traffic-flow T)
## See traffic_rules.gd. Per directed edge: "clear" keep-clear intervals
## (zebras) in s, "hold" (front-bumper hold line just behind the painted stop
## line), "exit_clear" (the rear of a car that stops after entering this edge
## must be past it: past the exit-side zebra), "control" (none / signal /
## major / give way). Per node: "box" half size of the junction box.
var _legacy_count := 25
var _node_box: Dictionary = {}       # node index -> junction box half size (m)
var _in_edges: Dictionary = {}       # node index -> Array[int] of incoming edges
var _yield_t: Dictionary = {}        # AmbientVehicle -> seconds waiting at a give-way line
var _last_leader: AmbientVehicle = null
## QA A/B switch: `--traffic-rules=off` restores the wave-S behaviour (the
## zebras are still mapped, so the census audit can count stops on them).
var rules_on := not ("--traffic-rules=off" in OS.get_cmdline_user_args())

func annotate_rules() -> void:
	var zs: Array = Rules.zebras()
	var lit: Array[Vector3] = Rules.signalled_points()
	_in_edges.clear()
	for e in edges.size():
		var to := int(edges[e]["to"])
		if not _in_edges.has(to):
			_in_edges[to] = []
		(_in_edges[to] as Array).append(e)
	var rank: Array[float] = []
	for e in edges.size():
		var ed: Dictionary = edges[e]
		rank.append(Rules.road_rank(ed["a"], ed["b"]) if ed.get("dt", false) else 116.0)
	var counts := {"signal": 0, "major": 0, "yield": 0, "none": 0, "zebra_edges": 0}
	for e in edges.size():
		var ed: Dictionary = edges[e]
		var length := float(ed["len"])
		var clear: Array[Vector2] = Rules.clear_intervals(ed["a"], ed["dir"], ed["left"], length, zs)
		# Keep only zebras on the drivable stretch (not inside the junction boxes).
		var kept: Array[Vector2] = []
		for iv in clear:
			if iv.y > 0.5 and iv.x < length - 0.5:
				kept.append(iv)
		ed["clear"] = kept
		if not kept.is_empty():
			counts["zebra_edges"] += 1
		var s_end := _s_end(e)
		var hold := s_end + 1.75
		var exit_clear := _entry(e)
		for iv in kept:
			# (only zebras in the far half: on a short link the exit-side zebra of
			# the previous junction also lies within 34 m of the end)
			if iv.y > length - 34.0 and iv.x > length * 0.5 and iv.x - 0.6 < hold:
				hold = maxf(_entry(e) + 4.0, iv.x - 0.6)
			if iv.x < _entry(e) + 14.0 and iv.y < length * 0.5:
				exit_clear = maxf(exit_clear, iv.y + 0.4)
		if not rules_on:
			hold = s_end + 1.75
			exit_clear = _entry(e)
		ed["hold"] = hold
		ed["exit_clear"] = exit_clear
		var control := Rules.CONTROL_NONE
		if bool(ed["signal"]):
			var to := int(ed["to"])
			control = Rules.CONTROL_YIELD
			if to < _legacy_count:
				control = Rules.CONTROL_SIGNAL
			else:
				for p in lit:
					if Vector2(p.x - nodes[to].x, p.z - nodes[to].z).length() < 8.0:
						control = Rules.CONTROL_SIGNAL
						break
			if control == Rules.CONTROL_YIELD:
				var best_other := -1.0
				for o in _in_edges.get(to, []):
					if int(o) != e and int(edges[o]["from"]) != int(ed["from"]):
						best_other = maxf(best_other, rank[o])
				if rank[e] >= best_other:
					control = Rules.CONTROL_MAJOR
		if not rules_on and control != Rules.CONTROL_NONE:
			control = Rules.CONTROL_SIGNAL
		ed["control"] = control
		counts[["none", "signal", "major", "yield"][control]] += 1
	# Short links into a junction (a bridge end or bend 10-20 m before the
	# junction, e.g. the Esplanade Bridge -> Connaught Drive): there is no
	# room to queue on the link itself, so the straight bend edge feeding it
	# holds instead (its own stop line or zebra), and the link is driven
	# through like part of the junction.
	if rules_on:
		for e in edges.size():
			var ed: Dictionary = edges[e]
			if int(ed["control"]) == Rules.CONTROL_NONE or float(ed["len"]) > 24.0:
				continue
			var link_control := int(ed["control"])
			for i in _in_edges.get(int(ed["from"]), []):
				var ei: Dictionary = edges[i]
				if int(ei["control"]) != Rules.CONTROL_NONE or int(ei["from"]) == int(ed["to"]):
					continue
				if (ei["dir"] as Vector3).dot(ed["dir"]) < 0.9:
					continue
				ei["control"] = link_control
				ei["proxy_to"] = int(ed["to"])
				var h := _s_end(i) + 1.75
				for iv: Vector2 in ei["clear"]:
					if iv.y > float(ei["len"]) - 20.0:
						h = minf(h, iv.x - 0.6)
				ei["hold"] = h
				ed["control"] = Rules.CONTROL_NONE
				counts["proxied"] = int(counts.get("proxied", 0)) + 1
	# Junction box half size: the widest road meeting at the node.
	for n in _in_edges:
		var w := 8.0
		for e in _in_edges[n]:
			var offs: Array = edges[e]["offs"]
			w = maxf(w, float(offs[0]) + DT_LANE_W * 0.5 + 1.0)
		_node_box[n] = w + 1.5
	stats["rules"] = counts

## A real junction (3+ roads, or the legacy grid), not a bend.
func is_junction_node(n: int) -> bool:
	if n < _legacy_count:
		return true
	for e in _in_edges.get(n, []):
		if bool(edges[e]["signal"]):
			return true
	return false

## Front-bumper hold line of edge e (just behind its stop line and zebra).
func _hold(e: int) -> float:
	return float(edges[e].get("hold", _s_end(e) + 1.75))

## Give way: may a car at the line of a minor road enter the junction?
## Not while another car is in the box or a priority-road car is about to
## arrive. After GIVE_WAY_PATIENCE s only the box itself has to be clear.
const GIVE_WAY_PATIENCE := 7.0
func _give_way_blocked(v: AmbientVehicle, delta: float) -> bool:
	var to := int(edges[v.edge].get("proxy_to", edges[v.edge]["to"]))
	var node: Vector3 = nodes[to]
	var box := float(_node_box.get(to, 10.0)) + 2.0
	var waited: float = float(_yield_t.get(v, 0.0)) + delta
	_yield_t[v] = waited
	for u in vehicles:
		if not u.active or u == v:
			continue
		var d := Vector2(u.global_position.x - node.x, u.global_position.z - node.z)
		if absf(d.x) < box and absf(d.y) < box and u.edge != v.edge:
			return true
		if waited > GIVE_WAY_PATIENCE or u.speed < 1.5 or u.j_len > 0.0 and u.s < _entry(u.edge):
			continue
		if int(edges[u.edge]["to"]) == to and int(edges[u.edge].get("control", 0)) == Rules.CONTROL_MAJOR and u.edge != v.edge:
			var to_line := _s_end(u.edge) - u.s
			if to_line > -2.0 and to_line < 10.0 + u.speed * 2.6:
				return true
	_yield_t.erase(v)
	return false

func lane_point(e: int, lane: int, s: float) -> Vector3:
	var ed: Dictionary = edges[e]
	var p: Vector3 = ed["a"] + ed["dir"] * s + ed["left"] * _off(e, lane)
	p.y = 0.07 + lerpf(float(ed["y0"]), float(ed["y1"]), clampf(s / maxf(0.01, float(ed["len"])), 0.0, 1.0))
	# Integrator (wave S): downtown lanes follow the real bridge deck profile
	# (cosine ramps). The straight chord between two graph nodes ran under the
	# deck: cars half-buried on the Esplanade Bridge ramp, a box truck sliding
	# through the Bayfront Bridge deck, an unseen under-deck car blocking the
	# player (critic downtown-polish-S1).
	if ed.get("dt", false):
		var h := DtBridges.height_at(p.x, p.z)
		if h > 0.001:
			p.y = 0.07 + h
	return p

# ----------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	var pt0 := Time.get_ticks_usec()
	_physics_step(delta)
	if _prof:
		_prof_us += Time.get_ticks_usec() - pt0
		_prof_frames += 1
		if _prof_frames % 300 == 0:
			print("[street-prof] ambient physics avg %.2f ms/frame over 300 frames" % [_prof_us / 300000.0])
			_prof_us = 0

var _prof_us := 0
var _prof_frames := 0
func _physics_step(delta: float) -> void:
	_update_focus()
	if Game.simulation_paused:
		return
	_grid_timer -= delta
	if _grid_timer <= 0.0:
		_grid_timer = 0.1
		_rebuild_grid()
	_rebuild_keys()
	_update_player_car()
	_tick += 1
	var i := 0
	for v in vehicles:
		i += 1
		if v.active:
			# M1 perf: lane cars far from the camera and the player step every
			# FAR_TICKS physics frames with the summed delta (nobody sees them;
			# queues and signals still evolve).
			var dt := delta
			var far := Vector2(v.global_position.x - _cam_pos.x, v.global_position.z - _cam_pos.z).length_squared() > FAR_SIM * FAR_SIM \
					and not _player_near(v.global_position, FAR_SIM)
			if far:
				if (i + _tick) % FAR_TICKS != 0:
					continue
				dt = delta * FAR_TICKS
			_yield_lane(v, dt)
			_drive(v, dt)
			if v.active:
				_unstick(v, dt)
	_recycle(false)
	_tidy_promoted()
	_census_t -= delta
	if _census_t <= 0.0:
		_census_t = 1.0
		_census()
	if _debug:
		_debug_timer -= delta
		if _debug_timer <= 0.0:
			_debug_timer = 0.5
			_debug_dump()

## downtown-life QA: once a second, how much lane traffic the lens sees
## (moving cars within 80 m in front of it, any car within 30 m). Printed at
## exit with --traffic-census; also kept in stats for the self-test.
var _census_t := 1.0
func _census() -> void:
	var moving80 := 0
	var near30 := 0
	for v in vehicles:
		if not v.active:
			continue
		var rel := v.global_position - _cam_pos
		rel.y = 0.0
		var d := rel.length()
		if d < 30.0:
			near30 += 1
		if d < 80.0 and v.speed > 1.0 and (d < 8.0 or rel.normalized().dot(_cam_fwd) > 0.25):
			moving80 += 1
	# traffic-flow (T): rule audit over every car the lens can see (120 m):
	# standing on a zebra, standing inside a junction box, and the longest
	# standstill that is not a red-light / give-way wait.
	var zebra := 0
	var boxed := 0
	var stalled := 0.0
	for v in vehicles:
		if not v.active or v.speed > 0.3:
			continue
		var rel := v.global_position - _cam_pos
		rel.y = 0.0
		if rel.length() > 120.0:
			continue
		var in_box := v.j_len > 0.0 and v.s < _entry(v.edge) and is_junction_node(int(edges[v.edge]["from"]))
		if in_box:
			# Giving way to people on the crossing, or to the player, is a
			# legitimate stop in the box; anything else is a blocked box.
			var on := v.obstacle_node
			if on != null and is_instance_valid(on) and (on is NPC or on.is_in_group("player") or on is Car):
				stats["box_yields"] = int(stats.get("box_yields", 0)) + 1
			else:
				boxed += 1
				if _jam_debug:
					print("[traffic-debug] BOX %s" % chain_desc(v))
		elif _on_zebra(v.edge, v.s, v.dims.z * 0.5):
			zebra += 1
			if _jam_debug:
				print("[traffic-debug] ZEBRA %s" % chain_desc(v))
		if v.idle_time > stalled:
			stalled = v.idle_time
	stats["zebra_stops"] = int(stats.get("zebra_stops", 0)) + zebra
	stats["box_stops"] = int(stats.get("box_stops", 0)) + boxed
	stats["max_idle_seen"] = maxf(float(stats.get("max_idle_seen", 0.0)), stalled)
	if _jam_debug and stalled > 20.0:
		for v in vehicles:
			if v.active and v.idle_time > 20.0 and v.global_position.distance_to(_cam_pos) < 160.0 and int(v.idle_time) % 5 == 0:
				print("[traffic-debug] JAM idle=%.0f %s" % [v.idle_time, chain_desc(v)])
	stats["census_samples"] = int(stats.get("census_samples", 0)) + 1
	if moving80 > 0:
		stats["census_moving80"] = int(stats.get("census_moving80", 0)) + 1
	if near30 >= 3:
		stats["census_near30_3"] = int(stats.get("census_near30_3", 0)) + 1
	stats["census_moving80_sum"] = int(stats.get("census_moving80_sum", 0)) + moving80
	if _census_log:
		print("[traffic-census] t=%.0f cam=%s moving80=%d near30=%d active=%d" % [Time.get_ticks_msec() / 1000.0, str(_cam_pos.round()), moving80, near30, count_active()])

var _census_log := "--traffic-census" in OS.get_cmdline_user_args()
var _jam_debug := "--traffic-debug" in OS.get_cmdline_user_args()
func _exit_tree() -> void:
	if _census_log:
		var n := maxi(1, int(stats.get("census_samples", 0)))
		print("[traffic-census] summary samples=%d moving_within_80m=%.0f%% three_within_30m=%.0f%% mean_moving80=%.1f relocated=%d" % [n,
			100.0 * int(stats.get("census_moving80", 0)) / n, 100.0 * int(stats.get("census_near30_3", 0)) / n, float(stats.get("census_moving80_sum", 0)) / n, int(stats["relocated"])])
		print("[traffic-census] rules zebra_stops=%d box_stops=%d box_yields=%d max_idle_seen=%.0f unstuck=%d rules=%s" % [int(stats.get("zebra_stops", 0)), int(stats.get("box_stops", 0)), int(stats.get("box_yields", 0)), float(stats.get("max_idle_seen", 0.0)), int(stats["unstuck"]), str(stats.get("rules", {}))])

var _debug := "--street-debug" in OS.get_cmdline_user_args()
var _prof := "--street-prof" in OS.get_cmdline_user_args()
var _debug_timer := 0.0
func _debug_dump() -> void:
	var p := Game.player_position
	var near: Array = []
	for v in vehicles:
		if v.active and v.global_position.distance_to(p) < 14.0:
			near.append("%s e%d l%d s%.1f v%.1f gap%.1f lead%.1f sig%s" % [str(v.global_position.round()), v.edge, v.lane, v.s, v.speed, v.obstacle_gap, _leader_gap(v, _s_end(v.edge)), _signal_ok(v.edge)])
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
		var t0 := Time.get_ticks_usec()
		stats["cuts"] += 1
		_refresh_near_edges(true)
		_build_view_spans()
		_rebuild_keys()
		_recycle(true)
		_rebuild_keys()
		_preroll(PREROLL_SECONDS)
		stats["cut_ms"] = float(stats.get("cut_ms", 0.0)) + (Time.get_ticks_usec() - t0) / 1000.0
		if _prof:
			print("[street-prof] cut %d took %.1f ms (total %.0f ms)" % [stats["cuts"], (Time.get_ticks_usec() - t0) / 1000.0, stats["cut_ms"]])

## Wave-M integration: still-photo lens hygiene. Lane cars whose body comes
## within `radius` of the lens (or `player_radius` of the on-foot player) are
## re-seeded out of sight: fixed views opened on a bus roof (photo_01) or two
## door panels (dt_bayfront_drive), and a queued sedan stopped against the
## player in the grove vista. Stills only; live play is untouched.
func clear_lens(cam_pos: Vector3, radius: float, player_radius: float = 0.0) -> int:
	var cleared := 0
	for v in vehicles:
		if not v.active:
			continue
		var half := v.dims.z * 0.5
		var near_cam := Vector2(v.global_position.x - cam_pos.x, v.global_position.z - cam_pos.z).length() < radius + half
		var near_player := player_radius > 0.0 and _player_near(v.global_position, player_radius + half)
		if near_cam or near_player:
			if not _seed_vehicle(v, true):
				_park_offscreen(v)
			cleared += 1
	if cleared > 0:
		_rebuild_keys()
		stats["lens_cleared"] = int(stats.get("lens_cleared", 0)) + cleared
	return cleared

## Street-life D: lane stretches (edge, s_lo, s_hi) that lie 10-140 m inside
## the street-level camera's forward cone; the pre-roll then carries the cars
## seeded there into queues and platoons.
var _view_spans: Array[Vector3] = []
func _build_view_spans() -> void:
	_view_spans.clear()
	if _cam_pos.y > 30.0:
		return
	for e in edges.size():
		var ed: Dictionary = edges[e]
		var lo := INF
		var hi := -INF
		var s := _entry(e) + 2.0
		while s < _s_end(e) - 4.0:
			var p := lane_point(e, 0, s)
			var rel := p - _cam_pos
			rel.y = 0.0
			if rel.length() > 10.0 and rel.length() < 140.0 and rel.normalized().dot(_cam_fwd) > 0.6:
				lo = minf(lo, s)
				hi = maxf(hi, s)
			s += 6.0
		if hi > lo:
			_view_spans.append(Vector3(e, lo, hi))

## Street-life D: after a camera cut, run the lane simulation forward a few
## seconds (signals held) so the new view opens on traffic that has already
## formed red-light queues and platoons, not on cars scattered at random.
const PREROLL_SECONDS := 9.0
func _preroll(seconds: float) -> void:
	if traffic == null:
		return
	_rebuild_grid()
	var step := 0.1
	var t := 0.0
	# r1: replay the signal history of the last `seconds` instead of holding
	# the current phase (a held red piled every red approach into one long
	# queue: 97 of 112 cars standing after a cut).
	var clock_now: float = traffic._signal_clock
	while t < seconds:
		traffic._signal_clock = fposmod(clock_now - seconds + t, 28.0)
		_rebuild_keys()
		for v in vehicles:
			if v.active:
				_drive(v, step)
		t += step
	traffic._signal_clock = clock_now
	_rebuild_keys()
	stats["prerolls"] = int(stats.get("prerolls", 0)) + 1

## Re-seed vehicles that are far from the focus. On a camera cut everything
## outside the spawn radius is re-seeded at once; in continuous play only cars
## far behind are moved, and only to spots the camera cannot see.
func _recycle(cut: bool) -> void:
	var budget := POOL if cut else 3
	# Wave T perf: failed seeds count too (over the bay no lane is near the
	# focus and every far car retried every tick, ~4 ms per tick).
	var fails := PerfBudget.TRAFFIC_SEED_FAILS * (20 if cut else 1)
	for v in vehicles:
		if budget <= 0 or fails <= 0:
			break
		if v.active:
			var d := Vector2(v.global_position.x - _focus.x, v.global_position.z - _focus.z).length()
			if cut:
				# downtown-life: with seeding near the focus most of the pool is
				# already inside the radius at a cut, so it stayed spread round
				# the camera and the viewed street got few cars. Most cars the
				# new lens cannot see are re-seeded (half into its view).
				if d < SPAWN_RADIUS and (not _hidden_from_camera(v.global_position) or _rng.randf() < 0.3):
					continue
			elif d < DESPAWN_RADIUS:
				continue
		if _seed_vehicle(v, not cut):
			budget -= 1
			stats["relocated"] += 1
		else:
			fails -= 1

## downtown-life (wave S): seeds are drawn from the lane edges that pass
## within SPAWN_RADIUS of the focus. With the downtown graph adopted (about
## four times the legacy grid, spread over 1.6 x 1.4 km) a uniformly random
## edge was almost always too far away: most of the 24 attempts failed and
## stranded cars stayed active kilometres from the camera, which is why the
## Cecil St and Bayfront views showed 0-1 cars.
var _near_edges: PackedInt32Array = PackedInt32Array()
var _near_focus := Vector3.INF
func _refresh_near_edges(force: bool = false) -> void:
	if not force and _near_focus != Vector3.INF and Vector2(_focus.x - _near_focus.x, _focus.z - _near_focus.z).length() < 20.0:
		return
	_near_focus = _focus
	_near_edges.clear()
	var f2 := Vector2(_focus.x, _focus.z)
	for e in edges.size():
		var ed: Dictionary = edges[e]
		var a: Vector3 = ed["a"]
		var b: Vector3 = ed["b"]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var t := clampf((f2 - Vector2(a.x, a.z)).dot(ab) / maxf(0.01, ab.length_squared()), 0.0, 1.0)
		if f2.distance_to(Vector2(a.x, a.z) + ab * t) < SPAWN_RADIUS:
			_near_edges.append(e)
	stats["near_edges"] = _near_edges.size()

func _pick_edge() -> int:
	if _near_edges.is_empty() or _rng.randf() < 0.08:
		return _rng.randi_range(0, edges.size() - 1)
	return _near_edges[_rng.randi_range(0, _near_edges.size() - 1)]

func _seed_vehicle(v: AmbientVehicle, hidden_only: bool) -> bool:
	_refresh_near_edges()
	_spacing_cap = hidden_only
	for attempt in 24:
		var e := _pick_edge()
		var ed: Dictionary = edges[e]
		var lo: float = _entry(e) + 2.0
		var hi: float = minf(_s_end(e) - 4.0, _hold(e) - 3.5)
		# Street-life D: half of the seeds of a cut go straight into the lane
		# stretches the street-level lens is looking at.
		if not hidden_only and not _view_spans.is_empty() and attempt < 12 and _rng.randf() < 0.5:
			var span: Vector3 = _view_spans[_rng.randi_range(0, _view_spans.size() - 1)]
			e = int(span.x)
			ed = edges[e]
			lo = span.y
			hi = span.z
		if hi <= lo:
			continue
		var s := _rng.randf_range(lo, hi)
		# On a long edge only the stretch near the focus can qualify.
		if float(ed["len"]) > 2.0 * SPAWN_RADIUS and (hidden_only or _view_spans.is_empty() or attempt >= 12):
			var a: Vector3 = ed["a"]
			var along := (_focus - a).dot(ed["dir"])
			var lo2 := maxf(lo, along - SPAWN_RADIUS)
			var hi2 := minf(hi, along + SPAWN_RADIUS)
			if hi2 > lo2:
				s = _rng.randf_range(lo2, hi2)
		var lane := _lane_for(e, 0 if _rng.randf() < 0.55 else 1)
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
		if not _gap_free(e, lane, s) or _on_zebra(e, s, v.dims.z * 0.5):
			continue
		if _player_near(p, 18.0) or _in_opening_clear(p):
			continue
		# Street-life M2: never seed into the player's own lane ahead of a
		# player-driven car (the scripted drive queued behind seeded cars for
		# most of a 166 s leg).
		if _in_player_path(p, lane_point(e, lane, s + 1.0) - p, 140.0):
			if (ed["offs"] as Array).size() < 2:
				continue
			lane = 1 - lane
			p = lane_point(e, lane, s)
			if _in_player_path(p, lane_point(e, lane, s + 1.0) - p, 140.0) or not _gap_free(e, lane, s):
				continue
		_place(v, e, lane, s)
		return true
	return false

## downtown-life: at most one car per LANE_SPACING m of a lane at seeding
## time. Concentrating the pool near the focus (near-edge seeding) otherwise
## packed short downtown links and district approaches solid, and most of
## the street stood in queues instead of flowing.
const LANE_SPACING := 26.0
## Only out-of-sight seeding in continuous play is capped; a camera cut still
## packs the viewed lanes (their red-light queues are the point of the view).
var _spacing_cap := false
func _gap_free(e: int, lane: int, s: float) -> bool:
	var list: Array = _keys.get(e * 2 + lane, [])
	if _spacing_cap and list.size() >= maxi(1, int((_s_end(e) - _entry(e)) / LANE_SPACING)):
		return false
	for other in list:
		if absf((other as AmbientVehicle).s - s) < MIN_GAP + 3.0:
			return false
	return true

## Does a body centred at s (half length `half`) overlap a zebra of edge e?
func _on_zebra(e: int, s: float, half: float) -> bool:
	for iv: Vector2 in edges[e].get("clear", []):
		if s + half > iv.x + 0.25 and s - half < iv.y - 0.25:
			return true
	return false

func _in_opening_clear(p: Vector3) -> bool:
	if traffic == null or traffic.world == null or not traffic.world.locations.has("player_start"):
		return false
	var o: Vector3 = traffic.world.locations["player_start"]
	return Vector2(p.x - o.x, p.z - o.z).length() < OPENING_CLEAR

## Out of the camera's sight (behind it, or far away)?
func _hidden_from_camera(p: Vector3) -> bool:
	var rel := p - _cam_pos
	rel.y = 0.0
	return rel.length() > 140.0 or (rel.length() > 14.0 and rel.normalized().dot(_cam_fwd) < -0.15)

## Stalled vehicles: re-seed gridlocked ones out of sight, and move any that
## have stopped against the on-foot player.
func _unstick(v: AmbientVehicle, delta: float) -> void:
	if v.speed < 0.3:
		v.idle_time += delta
	else:
		v.idle_time = 0.0
		return
	var on_foot := Game.mode != Game.MODE_CAR
	# Street-life D: only a car that is actually waiting on the player (its
	# obstacle scan stopped for the player or the player's car), or one the
	# player on foot is pressed against, is moved. A car queued at a red light
	# beside or ahead of the player stays put (no visible pop).
	var waits_on_player := v.obstacle_node != null and is_instance_valid(v.obstacle_node) \
			and (v.obstacle_node.is_in_group("player") or (v.obstacle_node is Car and (v.obstacle_node as Car).driver_is_player))
	var wedged := on_foot and v.idle_time > WEDGE_RESET and (waits_on_player and v.blocked_time > 0.0 \
			or _player_near(v.global_position, 1.8 + v.dims.z * 0.5)) and _player_near(v.global_position, WEDGE_RADIUS + v.dims.z * 0.5)
	# In a car: an ambient car yields to the player's car while the player's
	# car waits on it, a mutual deadlock that froze the scripted drive at the
	# (-160, 0, 0) junction. Break it after DEADLOCK_RESET s.
	if not on_foot and v.idle_time > DEADLOCK_RESET and waits_on_player and _player_near(v.global_position, 12.0 + v.dims.z * 0.5):
		wedged = true
	var opening := v.idle_time > WEDGE_RESET and _in_opening_clear(v.global_position)
	if v.next_edge < 0 and v.idle_time > 2.0 and (_hidden_from_camera(v.global_position) or v.idle_time > 25.0):
		opening = true
	var gridlock := v.idle_time > GRIDLOCK_RESET and _hidden_from_camera(v.global_position)
	if wedged or opening or gridlock:
		v.idle_time = 0.0
		stats["unstuck"] += 1
		if not _seed_vehicle(v, true):
			_park_offscreen(v)

func _park_offscreen(v: AmbientVehicle) -> void:
	var key := v.edge * 2 + v.lane
	if _keys.has(key):
		_keys[key].erase(v)
	v.active = false
	v.visible = false
	v.collision_layer = 0
	v.global_position = Vector3(0, -60.0, 0)

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
	var s_end: float = _s_end(v.edge)
	var target := v.vmax
	# M2: traffic in front of a player-driven car moves at the player's pace
	# (the M1 drive crawled behind 9-13 m/s lane cars for most of its leg).
	var boosted := _pc_active and _pc_speed > 4.0 and _in_player_path(v.global_position, -v.global_transform.basis.z, 130.0)
	if boosted:
		target = maxf(target, 20.0)
	# 1. Car following, including the tail of the lane we are about to enter.
	var gap := _leader_gap(v, s_end)
	target = _mt(v, target, _stop_speed(gap - 3.0), "leader")
	# traffic-flow (T): a dead end (only a U-turn out): stop at the end of the
	# road and wait to be recycled out of sight. Lane cars with no next edge
	# used to drive straight on off the graph, through kerbs and buildings,
	# and stall in other roads (one parked across Fullerton Road for 40 s+
	# was a tow in the downtown drive).
	if v.next_edge < 0:
		target = _mt(v, target, _stop_speed(s_end - v.s), "dead_end")
	# 2. Signals: hold at the stop line unless already committed.
	# traffic-flow (T): the hold line is the front bumper just behind the
	# painted stop line and zebra (was the car centre 12.5 m from the junction
	# centre on every road, which put queue heads on the crossing).
	if v.s <= s_end:
		var to_line := s_end - v.s
		var front := v.s + v.dims.z * 0.5
		var to_hold := _hold(v.edge) - front
		var in_box := v.j_len > 0.0 and v.s < _entry(v.edge)
		# Patience: a car held this long by one of the courtesy rules (keep
		# clear, give way, the far crossing, a stopped car in the box) goes
		# anyway, the way real drivers eventually do; signals and the queue
		# in front still hold it. No jam may freeze in view.
		var assertive := rules_on and v.idle_time > ASSERT_AFTER and String(why.get(v, "")) in SOFT_RULES
		if assertive:
			_assert_t[v] = 5.0
		elif _assert_t.has(v):
			_assert_t[v] = float(_assert_t[v]) - delta
			assertive = float(_assert_t[v]) > 0.0
			if not assertive:
				_assert_t.erase(v)
		var committed := (to_hold < 1.2 and v.speed > 4.0) or to_hold < -0.6
		# M2: a queue standing at a red light in front of a player-driven car
		# is released (the light "changes" for the player's approach, as in
		# GTA); cross traffic then holds for the player (_player_in_junction).
		var release := _pc_active and _in_player_path(v.global_position, -v.global_transform.basis.z, 110.0)
		var control := int(ed.get("control", 0))
		if not _signal_ok(v.edge) and not committed and not release:
			target = _mt(v, target, _stop_speed(to_hold - 0.25), "red")
		# Keep the box clear: do not enter the junction unless the exit lane
		# has room for this car past its exit-side zebra.
		elif not committed and not release and v.next_edge >= 0 and (not rules_on or control != Rules.CONTROL_NONE) and _exit_room(v) < v.dims.z + (3.5 if rules_on else 2.5):
			target = _mt(v, target, _stop_speed(to_hold - 0.25), "exit_room")
		# Give way to a player-driven vehicle crossing or about to cross.
		elif not committed and to_line < 30.0 and (not rules_on or control != Rules.CONTROL_NONE) and _player_in_junction(ed["b"], v):
			target = _mt(v, target, _stop_speed(to_hold - 0.25), "player")
		# A car ahead of us standing in the box (turning elsewhere, held by its
		# own exit or a pedestrian): wait at the line, not on the zebra.
		elif rules_on and not assertive and not committed and not in_box and to_hold < 30.0 and _box_ahead_blocked(v, to_hold):
			target = _mt(v, target, _stop_speed(to_hold - 0.25), "box_ahead")
		# People on the crossing on the far side of the junction.
		elif rules_on and not assertive and not committed and not in_box and to_hold < 18.0 and _exit_zebra_busy(v):
			target = _mt(v, target, _stop_speed(to_hold - 0.25), "exit_zebra")
		# Unsignalled junction, minor road: give way at the line.
		elif control == Rules.CONTROL_YIELD and not assertive and not committed and not release and not in_box and to_hold < 14.0 and _give_way_blocked(v, delta):
			target = _mt(v, target, _stop_speed(to_hold - 0.25), "give_way")
		if v.next_edge >= 0 and to_line < 22.0 and (edges[v.next_edge]["dir"] as Vector3).dot(ed["dir"]) < 0.5:
			target = _mt(v, target, 6.5, "turn")
		# Keep zebras clear: never stop with the body on a crossing. A car
		# whose leader is standing (or crawling) does not roll onto a zebra
		# unless there is room for its whole length beyond it.
		if not in_box and not assertive:
			target = _mt(v, target, _keep_clear_target(v, front, gap), "keep_clear")
		elif rules_on and not assertive:
			# Turning out of the box: people on the far crossing get the road;
			# stop short of the zebra rather than on it.
			for iv: Vector2 in ed.get("clear", []):
				if front <= iv.x + 0.05 and iv.x - front < 16.0 and _person_on_zebra(v, v.edge, v.lane, iv):
					target = _mt(v, target, _stop_speed(iv.x - front - 0.35), "box_zebra")
					break
	else:
		target = _mt(v, target, 6.5 if v.j_len > 0.0 and absf((v.j_p2 - v.j_c).normalized().dot((v.j_c - v.j_p0).normalized())) < 0.5 else v.vmax, "box_turn")
	# 3. People, the player and physics cars in the lane corridor ahead.
	v.scan_timer -= delta
	if v.scan_timer <= 0.0:
		v.scan_timer = 0.15
		v.obstacle_gap = _scan_obstacles(v)
	# M2: two lane cars that each see the other as the obstacle (a car
	# turning through the box and one standing at the next stop line, held
	# the scripted drive 56 s) — the one already in the junction goes on.
	var mutual := v.obstacle_gap < INF and is_instance_valid(v.obstacle_node) and v.obstacle_node is AmbientVehicle \
			and (v.obstacle_node as AmbientVehicle).obstacle_node == v and v.j_len > 0.0 and v.s < _entry(v.edge)
	if v.obstacle_gap < INF and not mutual:
		target = _mt(v, target, _stop_speed(v.obstacle_gap - 1.6), "obstacle")
		if v.obstacle_gap < 0.6:
			v.speed = 0.0
	_lane_change(v, delta)
	if _jam_debug and (v.idle_time > 30.0 or (v.idle_time > 12.0 and gap == INF and _signal_ok(v.edge))) and int(v.idle_time * 2.0) != int((v.idle_time - delta) * 2.0) and int(v.idle_time) % 2 == 0:
		print("[traffic-debug] STARVE e%d sig=%s clock=%.1f target=%.2f speed=%.2f why=%s s=%.1f hold=%.1f gap=%.1f exit=%.1f obst=%.1f node=%s ctl=%d %s" % [v.edge, _signal_ok(v.edge), traffic._signal_clock, target, v.speed, why.get(v, "-"), v.s, _hold(v.edge), gap, _exit_room(v) if v.next_edge >= 0 else -1.0, v.obstacle_gap,
			str(v.obstacle_node.get_class()) if v.obstacle_node != null and is_instance_valid(v.obstacle_node) else "-", int(ed.get("control", 0)), str(v.global_position.round())])
	# Junction deadlock breaker: a car held inside the box for long creeps on.
	if v.speed < 0.2 and v.j_len > 0.0 and v.s < _entry(v.edge):
		v.stuck_time += delta
	else:
		v.stuck_time = 0.0 if v.speed > 1.0 else v.stuck_time
	var rate := (ACCEL * (1.6 if boosted else 1.0)) if target > v.speed else DECEL * (1.6 if target < 0.5 else 1.0)
	v.speed = move_toward(v.speed, target, rate * delta)
	v.set_braking(target < v.speed - 0.4 or (v.speed < 0.3 and target < 0.5))
	var s_before := v.s
	v.s += v.speed * delta
	# M1 route safety: lane traffic never drives into the player's car. A
	# kinematic body moved into it shoved it sideways or pressed it through
	# the road (a headless route ended with the car wedged at y = -1). If
	# the step would overlap the player's car footprint, hold instead.
	if _pc_active and v.speed > 0.0 and _pc_blocks(v, delta):
		v.s = s_before
		v.speed = 0.0
		v.obstacle_node = _pc
		v.obstacle_gap = 0.0
		v.set_braking(true)
		stats["pc_holds"] = int(stats.get("pc_holds", 0)) + 1
		return
	if v.j_len <= 0.0 and v.s >= s_end and v.next_edge >= 0:
		_enter_junction(v)
	elif v.j_len > 0.0 and v.s >= _entry(v.edge):
		v.j_len = 0.0
	if v.lat_shift != 0.0:
		v.lat_shift = move_toward(v.lat_shift, 0.0, LANE_CHANGE_RATE * delta)
	_apply_transform(v)

## Street-life D: a car held behind something that is not ordinary queue
## traffic (a person or the player standing in the road, a parked or wrecked
## car, a stalled car) changes lanes round it when the other lane is clear,
## instead of waiting behind it for ever.
const LANE_CHANGE_RATE := 1.6
func _lane_change(v: AmbientVehicle, delta: float) -> void:
	var node := v.obstacle_node
	var odd := node != null and is_instance_valid(node) and v.obstacle_gap < 14.0 \
			and (not node is AmbientVehicle or (node as AmbientVehicle).idle_time > 6.0)
	if not odd or v.speed > 4.0:
		v.blocked_time = 0.0
		return
	v.blocked_time += delta
	# r1: a person standing in the carriageway in front of a waiting car steps
	# clear (rendered route: walkers loitering at the stop line held a whole
	# approach, and the car stuck in the box behind them, for over a minute).
	if node is NPC and v.blocked_time > 2.0 and fmod(v.blocked_time, 1.5) < delta:
		var fwd := -v.global_transform.basis.z
		(node as NPC).dodge_vehicle(v.global_position, Vector3(fwd.x, 0.0, fwd.z).normalized())
	if v.blocked_time < 0.9 or v.lat_shift != 0.0 or (v.j_len > 0.0 and v.s < _entry(v.edge)):
		return
	var ed: Dictionary = edges[v.edge]
	if v.s > _s_end(v.edge) - 6.0 or (ed["offs"] as Array).size() < 2:
		return
	var other := 1 - v.lane
	# The obstacle must not also block the other lane.
	var lat: float = (node.global_position - (ed["a"] as Vector3)).dot(ed["left"])
	if absf(lat - _off(v.edge, other)) < 2.1:
		return
	for o in _keys.get(v.edge * 2 + other, []):
		var ds: float = (o as AmbientVehicle).s - v.s
		if ds > -16.0 and ds < 12.0:
			return
	var old_key := v.edge * 2 + v.lane
	if _keys.has(old_key):
		_keys[old_key].erase(v)
	v.lat_shift = _off(v.edge, v.lane) - _off(v.edge, other)
	v.lane = other
	var key := v.edge * 2 + other
	if not _keys.has(key):
		_keys[key] = []
	_keys[key].append(v)
	(_keys[key] as Array).sort_custom(func(a, b): return a.s < b.s)
	v.blocked_time = 0.0
	v.obstacle_gap = INF
	v.obstacle_node = null
	stats["lane_changes"] = int(stats.get("lane_changes", 0)) + 1

var _pc: Car = null
var _pc_active := false
var _pc_pos := Vector3.ZERO
var _pc_x := Vector3.RIGHT
var _pc_z := Vector3.BACK
const PC_HALF := Vector2(1.15, 2.6)   # player car half extents plus margin
var _pc_speed := 0.0

## Street-life M2: is point p (travelling along dir) in the player car's own
## lane, ahead of it and within `reach` m, going the same way?
func _in_player_path(p: Vector3, dir: Vector3, reach: float) -> bool:
	if not _pc_active:
		return false
	var fwd := -_pc_z
	dir.y = 0.0
	if dir.length() < 0.01 or dir.normalized().dot(fwd) < 0.8:
		return false
	var rel := p - _pc_pos
	rel.y = 0.0
	var ahead := rel.dot(fwd)
	return ahead > -3.0 and ahead < reach and absf(rel.dot(_pc_x)) < 1.9

## Street-life M2: lane traffic ahead of the player's car in his lane moves
## over to the other lane when it is clear (keep-left courtesy), so a player
## is not stuck behind queues; a car that cannot move over stays put.
func _yield_lane(v: AmbientVehicle, _delta: float) -> void:
	if not _pc_active or v.lat_shift != 0.0 or (v.j_len > 0.0 and v.s < _entry(v.edge)):
		return
	if absf(v.global_position.x - _pc_pos.x) > 135.0 or absf(v.global_position.z - _pc_pos.z) > 135.0:
		return
	var fwd := -v.global_transform.basis.z
	if not _in_player_path(v.global_position, fwd, 130.0):
		return
	# A car standing at a light does not slide sideways in view.
	if v.speed < 0.5 and not _hidden_from_camera(v.global_position) and v.global_position.distance_to(_pc_pos) < 28.0:
		return
	var ed: Dictionary = edges[v.edge]
	if (ed["offs"] as Array).size() < 2 or v.s > _s_end(v.edge) - 4.0:
		return
	var other := 1 - v.lane
	var lat_other: float = _off(v.edge, other)
	var here_other := lane_point(v.edge, other, v.s)
	# Moving over must actually leave the player's path.
	if _in_player_path(here_other, fwd, 130.0):
		return
	for o in _keys.get(v.edge * 2 + other, []):
		var ds: float = (o as AmbientVehicle).s - v.s
		if ds > -10.0 and ds < 9.0:
			return
	var old_key := v.edge * 2 + v.lane
	if _keys.has(old_key):
		_keys[old_key].erase(v)
	v.lat_shift = _off(v.edge, v.lane) - lat_other
	v.lane = other
	var key := v.edge * 2 + other
	if not _keys.has(key):
		_keys[key] = []
	_keys[key].append(v)
	(_keys[key] as Array).sort_custom(func(a, b): return a.s < b.s)
	stats["yields"] = int(stats.get("yields", 0)) + 1

func _update_player_car() -> void:
	_pc_active = false
	var pl := get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var cv = pl.get("current_vehicle")
	if cv == null or not cv is Car or not is_instance_valid(cv):
		return
	_pc = cv as Car
	_pc_active = true
	_pc_pos = _pc.global_position
	_pc_speed = Vector2(_pc.velocity.x, _pc.velocity.z).length()
	var b := _pc.global_transform.basis
	_pc_x = Vector3(b.x.x, 0.0, b.x.z).normalized()
	_pc_z = Vector3(b.z.x, 0.0, b.z.z).normalized()

## Would this vehicle's footprint at its new lane position overlap the
## player's car (2D separating-axis test on the two rectangles)?
func _pc_blocks(v: AmbientVehicle, delta: float) -> bool:
	var here := v.global_position
	if absf(here.x - _pc_pos.x) > 16.0 or absf(here.z - _pc_pos.z) > 16.0:
		return false
	var fwd := -v.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var c := here + fwd * (v.speed * delta + 0.35)
	var ax := Vector3.UP.cross(fwd)
	var ah := Vector2(v.dims.x * 0.5, v.dims.z * 0.5)
	var d := c - _pc_pos
	d.y = 0.0
	for axis in [ax, fwd, _pc_x, _pc_z]:
		var ra: float = ah.x * absf(ax.dot(axis)) + ah.y * absf(fwd.dot(axis))
		var rb: float = PC_HALF.x * absf(_pc_x.dot(axis)) + PC_HALF.y * absf(_pc_z.dot(axis))
		if absf(d.dot(axis)) > ra + rb:
			return false
	# Only a step toward the player's car is held; a car already touching it
	# (the player drove into it) may still pull away.
	return fwd.dot(_pc_pos - here) > 0.0

func _stop_speed(distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	return sqrt(2.0 * 3.5 * distance)

func _leader_gap(v: AmbientVehicle, s_end: float) -> float:
	var list: Array = _keys.get(v.edge * 2 + v.lane, [])
	var idx := list.find(v)
	var half := v.dims.z * 0.5
	_last_leader = null
	if idx >= 0 and idx < list.size() - 1:
		var lead: AmbientVehicle = list[idx + 1]
		_last_leader = lead
		return lead.s - v.s - half - lead.dims.z * 0.5
	if v.next_edge < 0:
		return INF
	var nxt: Array = _keys.get(v.next_edge * 2 + _lane_for(v.next_edge, v.lane), [])
	if nxt.is_empty():
		return INF
	var tail: AmbientVehicle = nxt[0]
	_last_leader = tail
	var through := float(edges[v.edge]["stop"]) + _entry(v.next_edge)
	return (s_end - v.s) + through + (tail.s - _entry(v.next_edge)) - half - tail.dims.z * 0.5

func _player_in_junction(node: Vector3, v: AmbientVehicle) -> bool:
	if Game.mode != Game.MODE_CAR:
		return false
	var p := Game.player_position
	# Street-life M2: a player car driving toward this junction (within ~45 m,
	# heading for the box) has priority, like GTA traffic yielding to the
	# player, so cross traffic holds at its line instead of filling the box.
	if _pc_active and _pc_speed > 2.0 and absf(p.x - node.x) < 48.0 and absf(p.z - node.z) < 48.0:
		var to_node := node - _pc_pos
		to_node.y = 0.0
		if to_node.length() > 4.0 and to_node.normalized().dot(-_pc_z) > 0.85:
			var vf := -v.global_transform.basis.z
			vf.y = 0.0
			# Only traffic crossing or turning across the player's road.
			if absf(vf.normalized().dot(-_pc_z)) < 0.6:
				return true
	if absf(p.x - node.x) > 22.0 or absf(p.z - node.z) > 22.0:
		return false
	# A player queued behind this car is not crossing in front of it.
	var rel := p - v.global_position
	rel.y = 0.0
	var fwd := -v.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if rel.dot(fwd) <= 2.0:
		return false
	# traffic-flow (T): only a player in the box or in this car's own path
	# (a player passing on the far carriageway held whole approaches for a
	# minute: Esplanade Drive / Connaught Drive, Collyer Quay).
	var box := float(_node_box.get(int(edges[v.edge]["to"]), 10.0))
	if absf(p.x - node.x) < box and absf(p.z - node.z) < box:
		return true
	return absf(rel.dot(Vector3.UP.cross(fwd))) < 3.0

func _exit_room(v: AmbientVehicle) -> float:
	var ne := v.next_edge
	var nxt: Array = _keys.get(ne * 2 + _lane_for(ne, v.lane), [])
	var clear_from := maxf(_entry(ne), float(edges[ne].get("exit_clear", 0.0)))
	if nxt.is_empty():
		# A short link (<= 24 m): the room is what the road beyond it has left.
		# The way out of the link (planned now: there is no room to wait on
		# the link itself) must have room.
		if rules_on and float(edges[ne]["len"]) <= 24.0:
			var n2 := _link_plan(v, ne)
			if n2 < 0:
				return INF
			var l2: Array = _keys.get(n2 * 2 + _lane_for(n2, v.lane), [])
			if l2.is_empty():
				return INF
			var t2: AmbientVehicle = l2[0]
			return float(edges[ne]["len"]) + t2.s - t2.dims.z * 0.5 - maxf(clear_from, float(edges[n2].get("exit_clear", 0.0)))
		return INF
	var tail: AmbientVehicle = nxt[0]
	return tail.s - clear_from - tail.dims.z * 0.5

const ASSERT_AFTER := 14.0
var _assert_t: Dictionary = {}
const SOFT_RULES := ["keep_clear", "exit_zebra", "box_ahead", "give_way", "box_zebra"]
## The rule that last capped a car's speed below walking pace (patience
## rule above; printed by --traffic-debug).
var why: Dictionary = {}
func _mt(v: AmbientVehicle, cur: float, cap: float, tag: String) -> float:
	if cap < cur:
		if cap < 0.5:
			why[v] = tag
		return cap
	return cur

func _box_ahead_blocked(v: AmbientVehicle, to_hold: float) -> bool:
	var n := v.obstacle_node
	if v.obstacle_gap == INF or n == null or not is_instance_valid(n) or not n is AmbientVehicle:
		return false
	var a := n as AmbientVehicle
	return a.speed < 3.0 and a.j_len > 0.0 and a.s < _entry(a.edge) and v.obstacle_gap > to_hold - 1.0

## Where the rear of v can end up (edge s) once the queue in front has
## closed up: the first standing or crawling car ahead in this lane, minus
## the cars in between at standstill spacing. `lead_rear` is the current
## leader's rear (front + gap) when nothing ahead stands.
func _queue_end(v: AmbientVehicle, lead_rear: float) -> float:
	var list: Array = _keys.get(v.edge * 2 + v.lane, [])
	var idx := list.find(v)
	if idx < 0:
		return lead_rear
	var between := 0.0
	var soonest := INF
	for j in range(idx + 1, list.size()):
		var u: AmbientVehicle = list[j]
		if u.speed < 2.0:
			return minf(soonest, u.s - u.dims.z * 0.5 - between - 3.0)
		# A moving car ahead could stop within its braking distance (it may be
		# heading for a red or a full exit): plan for that, not for it going on.
		if j == idx + 1:
			soonest = u.s - u.dims.z * 0.5 + u.speed * u.speed / 7.0 - 3.0
		between += u.dims.z + 3.0
	# Nobody in this lane stands: is the tail of the lane we go to next standing?
	if v.next_edge >= 0:
		var nxt: Array = _keys.get(v.next_edge * 2 + _lane_for(v.next_edge, v.lane), [])
		if not nxt.is_empty():
			var t: AmbientVehicle = nxt[0]
			if t.speed < 2.0:
				var through := float(edges[v.edge]["stop"]) + _entry(v.next_edge)
				return minf(soonest, _s_end(v.edge) + through + t.s - _entry(v.next_edge) - t.dims.z * 0.5 - between - 3.0)
	var lead := _last_leader
	if lead != null and lead.speed < 2.0:
		return minf(soonest, lead_rear - 3.0)
	return soonest

var _plan: Dictionary = {}   # AmbientVehicle -> onward edge after a short link
func _link_plan(v: AmbientVehicle, link: int) -> int:
	if not _plan.has(v) or (_plan[v] as Vector2i).x != link:
		_plan[v] = Vector2i(link, _choose_next(link))
	return (_plan[v] as Vector2i).y

## Speed cap that keeps the body of v off the next zebra ahead while the
## traffic in front stands (see _drive).
func _keep_clear_target(v: AmbientVehicle, front: float, gap: float) -> float:
	var clear: Array = edges[v.edge].get("clear", [])
	if not rules_on or clear.is_empty():
		return INF
	for iv: Vector2 in clear:
		if iv.y <= front - v.dims.z:
			continue          # already behind us
		if front > iv.x + 0.05:
			return INF        # already rolling over it: clear it
		if iv.x - front > 45.0:
			return INF
		var qe := _queue_end(v, front + gap) if gap < INF else INF
		var on := v.obstacle_node
		if v.obstacle_gap < INF and on != null and is_instance_valid(on) and on is AmbientVehicle and (on as AmbientVehicle).speed < 2.0:
			qe = minf(qe, front + v.obstacle_gap - 1.6)
		if qe - iv.y < v.dims.z + 1.2:
			return _stop_speed(iv.x - front - 0.35)
		# Somebody on (or stepping onto) the crossing in our half of the road:
		# stop at the zebra, not on it.
		if iv.x - front < 22.0 and _person_on_zebra(v, v.edge, v.lane, iv):
			return _stop_speed(iv.x - front - 0.35)
		return INF
	return INF

## Is a pedestrian on the zebra interval iv of v's edge, within the half of
## the carriageway v drives on (plus a step either side)?
func _person_on_zebra(v: AmbientVehicle, e: int, lane: int, iv: Vector2) -> bool:
	# A person who will not step clear stops counting after GIVE_UP * 1.5 s
	# (as in _scan_obstacles), so a loiterer never freezes an approach.
	if v.idle_time > GIVE_UP * 1.5:
		return false
	var ed: Dictionary = edges[e]
	var mid := lane_point(e, lane, (iv.x + iv.y) * 0.5)
	var cx := floori(mid.x / CELL)
	var cz := floori(mid.z / CELL)
	var a: Vector3 = ed["a"]
	var lat0 := _off(e, lane)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for n in _grid.get(Vector2i(cx + dx, cz + dz), []):
				if not is_instance_valid(n) or not n is NPC:
					continue
				# Someone standing about on the crossing (a crowd that gathered at
				# the bridge foot) is not crossing: no indefinite wait for them.
				if (n as NPC).state == NPC.State.IDLE and v.idle_time > 4.0:
					continue
				var rel: Vector3 = (n as Node3D).global_position - a
				var along: float = rel.dot(ed["dir"])
				if along < iv.x - 0.6 or along > iv.y + 0.6:
					continue
				if absf(rel.dot(ed["left"]) - lat0) < 3.2:
					# Waiting on them: they finish crossing briskly.
					if v.speed < 0.5 and v.idle_time > 2.5 and fmod(v.idle_time, 1.5) < 0.05:
						var fwd: Vector3 = ed["dir"]
						(n as NPC).dodge_vehicle(v.global_position, fwd)
					return true
	return false

## The zebra just past the junction on the way out (the start of the next
## edge): is somebody on it in our lane? Then wait at the line, not on it.
func _exit_zebra_busy(v: AmbientVehicle) -> bool:
	var ne := v.next_edge
	if ne < 0:
		return false
	var lane := _lane_for(ne, v.lane)
	for iv: Vector2 in edges[ne].get("clear", []):
		if iv.x > float(edges[ne].get("exit_clear", 0.0)) + 1.0:
			break
		if _person_on_zebra(v, ne, lane, iv):
			return true
	return false

func _enter_junction(v: AmbientVehicle) -> void:
	var overflow := v.s - _s_end(v.edge)
	var p0 := lane_point(v.edge, v.lane, _s_end(v.edge))
	var ne := v.next_edge
	var lane := _lane_for(ne, v.lane)
	# M2: a car turning into the road ahead of a player-driven car takes the
	# lane the player is not in.
	if _pc_active and (edges[ne]["offs"] as Array).size() >= 2:
		var probe := lane_point(ne, lane, _entry(ne) + 6.0)
		if _in_player_path(probe, edges[ne]["dir"], 140.0):
			lane = 1 - lane
	var p2 := lane_point(ne, lane, _entry(ne))
	var d1: Vector3 = edges[v.edge]["dir"]
	var d2: Vector3 = edges[ne]["dir"]
	var c: Vector3
	if absf(d1.dot(d2)) > 0.9:
		c = (p0 + p2) * 0.5
	else:
		# Intersection of the incoming and outgoing lane lines.
		var b: Vector3 = edges[v.edge]["b"]
		c = b + (edges[v.edge]["left"] as Vector3) * _off(v.edge, v.lane) + (edges[ne]["left"] as Vector3) * _off(ne, lane)
		c.y = (p0.y + p2.y) * 0.5
	v.j_p0 = p0
	v.j_c = c
	v.j_p2 = p2
	v.j_len = maxf(4.0, (p0.distance_to(c) + c.distance_to(p2) + p0.distance_to(p2)) * 0.5)
	v.edge = ne
	v.lane = lane
	v.s = _entry(ne) - v.j_len + overflow
	v.next_edge = _choose_next(ne)
	if _plan.has(v):
		var pl: Vector2i = _plan[v]
		if pl.x == ne and pl.y >= 0:
			v.next_edge = pl.y
		_plan.erase(v)

func _apply_transform(v: AmbientVehicle) -> void:
	var pos: Vector3
	var fwd: Vector3
	if v.j_len > 0.0 and v.s < _entry(v.edge):
		var t := clampf(1.0 - (_entry(v.edge) - v.s) / v.j_len, 0.0, 1.0)
		var a := v.j_p0.lerp(v.j_c, t)
		var b := v.j_c.lerp(v.j_p2, t)
		pos = a.lerp(b, t)
		fwd = (b - a)
		if fwd.length() < 0.001:
			fwd = v.j_p2 - v.j_p0
	else:
		pos = lane_point(v.edge, v.lane, v.s)
		fwd = edges[v.edge]["dir"]
		if v.lat_shift != 0.0:
			var lft: Vector3 = edges[v.edge]["left"]
			pos += lft * v.lat_shift
			# Nose into the new lane while drifting across.
			fwd = fwd - lft * signf(v.lat_shift) * 0.09
	var slope := 0.0
	if v.j_len <= 0.0 or v.s >= _entry(v.edge):
		# Integrator (wave S): pitch with the deck on bridge ramps.
		if edges[v.edge].get("dt", false):
			slope = (lane_point(v.edge, v.lane, v.s + 2.0).y - lane_point(v.edge, v.lane, v.s - 2.0).y) / 4.0
	fwd.y = 0.0
	fwd = fwd.normalized()
	if absf(slope) > 0.002:
		fwd = Vector3(fwd.x, clampf(slope, -0.35, 0.35), fwd.z).normalized()
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
		v.obstacle_node = null
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
	var best_node: Node3D = null
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
					# r1 gridlock fix: two cars inside the same junction box never
					# hold each other (crossing paths formed hold cycles that froze
					# whole approaches); same-lane order inside the box is kept by
					# _leader_gap, which follows the exit lane's queue.
					var na := node as AmbientVehicle
					if v.j_len > 0.0 and v.s < _entry(v.edge) and na.j_len > 0.0 and na.s < _entry(na.edge):
						continue
					# traffic-flow (T): a lane car whose centre is behind ours is
					# never "ahead" (a follower nosed into our rear bumper held us
					# while it waited for us: the Esplanade Bridge hold cycle).
					var rel_c: Vector3 = node.global_position - here
					if rel_c.x * fwd.x + rel_c.z * fwd.z < 0.3:
						continue
					# Oncoming lane traffic never holds us: on the Fullerton Road bends
					# the two directions' corridors touch, and a westbound and an
					# eastbound car each waited on the other (Collyer Quay tows, wave S).
					var ob := -node.global_transform.basis.z
					if ob.x * fwd.x + ob.z * fwd.z < -0.5:
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
					# r1 gridlock dissolver: after GIVE_UP s at a stand, a stopped
					# non-player car (a police car parked across the box, a civilian
					# wedged between lanes) no longer holds lane traffic; the lane
					# car nudges past and physics pushes the stopped car aside.
					if not (node as Car).driver_is_player and v.idle_time > GIVE_UP and (node as Car).velocity.length() < 0.5:
						continue
					var b := node.global_transform.basis
					# The player's car gets extra room when it is off the lane
					# axis; a player car driving straight in the next lane is
					# passed like any other car (street-life D).
					var pad := 0.0
					if (node as Car).driver_is_player:
						var pf := Vector3(b.z.x, 0, b.z.z).normalized()
						pad = 0.15 if absf(pf.dot(fwd)) > 0.97 else 0.6
					var bx := Vector3(b.x.x, 0, b.x.z).normalized() * (0.93 + pad)
					var bz := Vector3(b.z.x, 0, b.z.z).normalized() * (2.4 + pad)
					var c := node.global_position
					points = [c, c + bx + bz, c + bx - bz, c - bx + bz, c - bx - bz]
				elif node is Helicopter:
					continue
				else:
					if node is NPC and v.idle_time > GIVE_UP * 1.5:
						continue   # a person who would not step clear (see _lane_change)
					# traffic-flow (T): a person standing still in the road (not
					# walking across it) holds a car for 6 s, not 15.
					if node is NPC and (node as NPC).state == NPC.State.IDLE and v.idle_time > 6.0:
						continue
					points = [node.global_position]
					radius = 0.45
				for p in points:
					var d: Vector3 = p - here
					var ahead := d.dot(fwd)
					if ahead < -half_len or ahead > 20.0:
						continue
					if absf(d.dot(left)) > half_w + radius:
						continue
					var gap := maxf(0.0, ahead - half_len - radius)
					if gap < best:
						best = gap
						best_node = node
	v.obstacle_node = best_node
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

## QA: who is holding whom (follow obstacle_node through ambient cars).
func chain_desc(v: AmbientVehicle) -> String:
	var out: Array[String] = []
	var cur: Node3D = v
	for i in 6:
		if cur == null or not is_instance_valid(cur):
			break
		if cur is AmbientVehicle:
			var a := cur as AmbientVehicle
			var ed: Dictionary = edges[a.edge]
			out.append("%s[e%d l%d s%.0f/%.0f j%.0f v%.1f idle%.0f stuck%.0f sig%s next%d gap%.1f exit%.0f %s why=%s]" % [a.name.right(5), a.edge, a.lane, a.s, _s_end(a.edge), a.j_len, a.speed, a.idle_time, a.stuck_time,
				_signal_ok(a.edge), a.next_edge, a.obstacle_gap, _exit_room(a) if a.next_edge >= 0 else -1.0, str(a.global_position.round()), why.get(a, "-")])
			cur = a.obstacle_node
		else:
			var what := cur.get_class()
			if cur is Car:
				var c := cur as Car
				what = "Car(%s ai=%s player=%s v=%.1f)" % [c.kind, c.has_ai, c.driver_is_player, c.velocity.length()]
			elif cur is NPC:
				what = "NPC(state=%d police=%s)" % [(cur as NPC).state, (cur as NPC).is_police]
			out.append("%s:%s%s" % [what, cur.name.right(6), str(cur.global_position.round())])
			break
	return " -> ".join(out)

## QA: why active cars are standing (histogram of reasons).
func hold_reasons() -> Dictionary:
	var out := {}
	for v in vehicles:
		if not v.active or v.speed >= 0.6:
			continue
		var ed: Dictionary = edges[v.edge]
		var r := "other"
		var n := v.obstacle_node
		if n != null and is_instance_valid(n) and v.obstacle_gap < 3.0:
			if n is AmbientVehicle:
				r = "amb_box" if (n as AmbientVehicle).j_len > 0.0 and (n as AmbientVehicle).s < _entry((n as AmbientVehicle).edge) else ("amb_idle" if (n as AmbientVehicle).idle_time > 5.0 else "amb")
			elif n is Car:
				r = "car_ai" if (n as Car).has_ai else ("car_player" if (n as Car).driver_is_player else "car_parked")
			elif n is NPC:
				r = "npc"
			else:
				r = "player"
		elif v.j_len > 0.0 and v.s < _entry(v.edge):
			r = "in_box"
		elif not _signal_ok(v.edge):
			r = "red"
		elif _leader_gap(v, _s_end(v.edge)) < 4.0:
			r = "queue"
		elif v.next_edge >= 0 and _exit_room(v) < v.dims.z + 2.5:
			r = "exit_full"
		out[r] = int(out.get(r, 0)) + 1
	return out

## Any lane car moving inside (or about to cross) the junction box at `node`?
func box_busy(node: Vector3) -> bool:
	for v in vehicles:
		if not v.active or v.speed < 1.0:
			continue
		var p := v.global_position
		if absf(p.x - node.x) < 15.0 and absf(p.z - node.z) < 15.0:
			return true
	return false
