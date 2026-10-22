class_name TrafficManager
extends Node3D
## Population and traffic simulation: lane graph, left-hand traffic, civilian
## pedestrians, parked cars, and police response (TRAFFIC-01/02, LAW-02/03).

const LANE_OFFSET := 4.0        # lane centre is 4 m to the LEFT of the road centre
const PED_COUNT := 140
const FOCUSED_PED_COUNT := 58
const DINER_COUNT := 45
const TRAFFIC_COUNT := 26
const POLICE_SPAWN_DISTANCE := 55.0

var world: WorldBuilder
var nodes: Array[Vector3] = []
var cars: Array[Car] = []
var peds: Array[NPC] = []
var police_cars: Array[Car] = []
var _ped_lanes: Array = []
var _player: Node = null
var _police_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _signal_clock := 0.0
var _signal_visual_phase := -1
var _signal_materials: Array[Material] = []
var _signal_unlit: Material
## Pre-built police officers held off-stage. Wave 2 constructed a fresh skinned
## NPC inside the 4.5 s responder timer, which the packaged workload measured as
## repeated ~735-762 ms combat stalls (package-soak-r2/frame_stalls.jsonl).
## Pooling moves that cost to load time and keeps activation O(1).
var _officer_pool: Array[NPC] = []
const OFFICER_POOL_SIZE := 5
var _officer_pool_ready := false
var _officer_activation_us: Array[int] = []
var _police_car_pool: Array[Car] = []
const POLICE_CAR_POOL_SIZE := 2

func setup(w: WorldBuilder, player: Node) -> void:
	add_to_group("traffic_manager")
	world = w
	_player = player
	nodes = w.traffic_nodes
	_ped_lanes = w.ped_lanes
	_rng.seed = Game.seed_value
	_spawn_parked()
	_spawn_traffic()
	_spawn_peds()
	_warm_officer_pool()
	_update_signal_lamps(true)

## Build the officer responders during world load, then keep them inert and
## out of `peds` until a responder is actually requested.
func _warm_officer_pool() -> void:
	var started := Time.get_ticks_usec()
	for i in OFFICER_POOL_SIZE:
		var officer := NPC.new()
		officer.is_police = true
		officer.state = NPC.State.IDLE
		officer.visible = false
		officer.collision_layer = 0
		officer.collision_mask = 0
		officer.set_physics_process(false)
		officer.set_process(false)
		add_child(officer)
		officer.global_position = Vector3(0.0, -80.0 - i * 3.0, 0.0)
		_officer_pool.append(officer)
	for i in POLICE_CAR_POOL_SIZE:
		var pc := Car.new()
		pc.kind = "police"
		pc.visible = false
		pc.has_ai = false
		pc.collision_layer = 0
		pc.collision_mask = 0
		pc.set_physics_process(false)
		pc.set_process(false)
		add_child(pc)
		pc.global_position = Vector3(12.0, -90.0 - i * 5.0, 0.0)
		_police_car_pool.append(pc)
	_officer_pool_ready = true
	print("[profile] officer_pool_build_us=", Time.get_ticks_usec() - started, " size=", _officer_pool.size(), " police_cars=", _police_car_pool.size())

## Activate one pooled officer at `pos`. Returns null when the pool is empty, so
## the caller falls back to construction rather than silently spawning nothing.
func _take_officer(pos: Vector3) -> NPC:
	var officer: NPC = null
	while not _officer_pool.is_empty():
		var candidate: NPC = _officer_pool.pop_back()
		if is_instance_valid(candidate):
			officer = candidate
			break
	if officer == null:
		return null
	officer.global_position = pos
	officer.health = 100.0
	officer.state = NPC.State.PURSUE
	officer.idle_time = 0.0
	officer.panic_time = 0.0
	officer.collision_layer = 4
	officer.collision_mask = 1 | 4
	officer.visible = true
	officer.set_physics_process(true)
	officer.set_process(true)
	if officer.character_visual != null:
		officer.character_visual.reset_alive()
	return officer

## Return a responder to the pool instead of freeing and rebuilding it.
func _recycle_officer(officer: NPC) -> void:
	if not is_instance_valid(officer):
		return
	officer.state = NPC.State.IDLE
	officer.visible = false
	officer.collision_layer = 0
	officer.collision_mask = 0
	officer.set_physics_process(false)
	officer.set_process(false)
	officer.global_position = Vector3(0.0, -80.0 - _officer_pool.size() * 3.0, 0.0)
	_officer_pool.append(officer)

func _take_police_car(pos: Vector3, target: Vector3) -> Car:
	var pc: Car = null
	while not _police_car_pool.is_empty():
		var candidate: Car = _police_car_pool.pop_back()
		if is_instance_valid(candidate):
			pc = candidate
			break
	if pc == null:
		pc = Car.new()
		pc.kind = "police"
		add_child(pc)
	pc.disabled = false
	pc.health = 100.0
	pc._forward = 0.0
	pc.velocity = Vector3.ZERO
	pc.global_position = pos
	pc.collision_layer = 8
	pc.collision_mask = 1 | 2 | 4 | 8
	pc.visible = true
	pc.has_ai = true
	pc.max_speed = 23.0
	pc.ai_target = target
	pc.set_physics_process(true)
	pc.set_process(true)
	return pc

func _recycle_police_car(pc: Car) -> void:
	if not is_instance_valid(pc):
		return
	if pc.driver_is_player:
		return
	pc.has_ai = false
	pc._forward = 0.0
	pc.remove_meta("pursuit_wp")
	pc.remove_meta("pursuit_goal")
	pc.velocity = Vector3.ZERO
	pc.visible = false
	pc.collision_layer = 0
	pc.collision_mask = 0
	pc.set_physics_process(false)
	pc.set_process(false)
	pc.global_position = Vector3(12.0, -90.0 - _police_car_pool.size() * 5.0, 0.0)
	if not _police_car_pool.has(pc):
		_police_car_pool.append(pc)

# ------------------------------------------------------------------- spawning
func _spawn_parked() -> void:
	var i := 0
	for spot in world.parked_spots:
		var kind := String(spot.get("kind", "sedan"))
		if kind == "van":
			kind = "van"
		var car := Car.new()
		car.kind = kind
		if bool(spot.get("courtyard_only", false)):
			car.set_meta("courtyard_only", true)
		add_child(car)
		car.global_position = spot["pos"]
		car.rotation.y = float(spot.get("heading", 0.0))
		if i % 5 == 0:
			# occupied parked car: a civilian is sitting in it (CAR-02)
			var npc := NPC.new()
			npc.is_hostile = false
			add_child(npc)
			npc.global_position = car.global_position
			npc.visible = false          # seated in the car, not standing in it
			npc.collision_layer = 0
			npc.collision_mask = 0
			npc.set_physics_process(false)
			npc.set_process(false)
			car.set_ai_driver(npc)
		i += 1

func _spawn_traffic() -> void:
	# The manager's review called the heritage street "an almost-empty endless
	# road". 26 cars spread uniformly over a 640 m grid still leaves the street
	# the player actually walks empty, so two in five are seeded on edges near
	# the heritage/market blocks.
	for i in TRAFFIC_COUNT:
		var car := _spawn_ai_car(["sedan", "coupe", "van"][i % 3], i % 5 < 2)
		if car:
			cars.append(car)

func _spawn_ai_car(kind: String, near_heritage: bool = false) -> Car:
	var edge := _random_edge_near(Vector3(-100.0, 0.0, -100.0), 230.0) if near_heritage else _random_edge()
	if edge.is_empty():
		return null
	var car := Car.new()
	car.kind = kind
	add_child(car)
	car.global_position = edge["from"].lerp(edge["to"], _rng.randf_range(0.15, 0.8))
	car.rotation.y = atan2(-(edge["to"].x - edge["from"].x), -(edge["to"].z - edge["from"].z))
	car.has_ai = true
	car.max_speed = 12.0
	car.set_meta("from_node", edge["from"])
	car.ai_target = _lane_point(edge["from"], edge["to"])
	car.set_meta("next_node", edge["to"])
	return car

func _random_edge() -> Dictionary:
	if nodes.size() < 2:
		return {}
	var idx := _rng.randi_range(0, nodes.size() - 1)
	var neighbours := _neighbours(idx)
	if neighbours.is_empty():
		return {}
	var nxt: int = neighbours[_rng.randi_range(0, neighbours.size() - 1)]
	return {"from": nodes[idx], "to": nodes[nxt]}

## Same as _random_edge but restricted to edges whose midpoint lies within
## `radius` of `centre`. Falls back to any edge when none qualify.
func _random_edge_near(centre: Vector3, radius: float) -> Dictionary:
	if nodes.size() < 2:
		return {}
	var candidates: Array[Dictionary] = []
	for idx in nodes.size():
		for nxt in _neighbours(idx):
			var midpoint: Vector3 = (nodes[idx] + nodes[nxt]) * 0.5
			if midpoint.distance_to(centre) <= radius:
				candidates.append({"from": nodes[idx], "to": nodes[nxt]})
	if candidates.is_empty():
		return _random_edge()
	return candidates[_rng.randi_range(0, candidates.size() - 1)]

func _neighbours(idx: int) -> Array[int]:
	var result: Array[int] = []
	var cols := 5
	var r := idx / cols
	var c := idx % cols
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr: int = r + dr
			var nc: int = c + dc
			if nr < 0 or nr > 4 or nc < 0 or nc > 4:
				continue
			if dr != 0 and dc != 0:
				continue  # keep traffic orthogonal: believable junctions, no drifting
			result.append(nr * cols + nc)
	return result

## Left-hand rule: the lane centre sits on the left of the travel direction.
func _lane_point(from: Vector3, to: Vector3) -> Vector3:
	var dir := (to - from)
	dir.y = 0.0
	if dir.length() < 0.01:
		return from
	dir = dir.normalized()
	var left := Vector3.UP.cross(dir).normalized()
	return to + left * LANE_OFFSET - dir * 8.0

func _spawn_peds() -> void:
	if _ped_lanes.is_empty(): return
	# A denser, continuous walking perimeter around the heritage/market block.
	# Spawn along path segments, so people do not all appear on junction nodes.
	var focused_lanes: Array = [
		[Vector3(-150.0, 0.25, -145.0), Vector3(-150.0, 0.25, -15.0)],
		[Vector3(-10.0, 0.25, -145.0), Vector3(-10.0, 0.25, -15.0)],
		[Vector3(-145.0, 0.25, -150.0), Vector3(-15.0, 0.25, -150.0)],
		[Vector3(-145.0, 0.25, -10.0), Vector3(-15.0, 0.25, -10.0)],
		# Wave 5: the opening heritage row's five-foot way, opposite the hall.
		[Vector3(-171.5, 0.25, -148.0), Vector3(-171.5, 0.25, -36.0)],
	]
	for index in PED_COUNT:
		var ped := NPC.new()
		add_child(ped)
		var path: Array
		if index < FOCUSED_PED_COUNT:
			path = focused_lanes[index % focused_lanes.size()]
		else:
			path = _ped_lanes[_rng.randi_range(0, _ped_lanes.size() - 1)]
		_spawn_on_segment(ped, path)
		peds.append(ped)
	# Damageable/reactive diners and queueing customers. Keep the package and
	# combat aisle (local z=-8 and north of it) clear for actual mission play.
	var centre: Vector3 = world.locations["hawker"]
	var seats: Array[Vector3] = [Vector3(.857,.495,-.194),Vector3(.025,.48,-.80),Vector3(-.844,.492,-.18),Vector3(-.557,.475,.714),Vector3(.497,.471,.741)]
	for index in DINER_COUNT:
		var diner:=NPC.new();add_child(diner)
		var table_id: int=index/5
		var column: int=1+(table_id%3)*4
		var row: int=3+(table_id/3)*2
		var seat: Vector3=seats[index%5]
		var position:=centre+Vector3(-27.5+column*5.0+seat.x,.4,-11.0+row*4.5+seat.z)
		diner.global_position=position
		diner.rotation.y=atan2(seat.x,seat.z)
		diner.state=NPC.State.IDLE;diner.idle_time=3600
		diner.set_meta("ambient_role","diner")
		diner.set_meta("activity_home",position)
		if diner.character_visual!=null and diner.character_visual.loaded:
			diner.character_visual.position.y=seat.y-.445
			diner.character_visual.set_seated(true)
		peds.append(diner)

func _spawn_on_segment(ped: NPC, path: Array) -> void:
	ped.lane = path
	if path.size() < 2:
		return
	var segment := _rng.randi_range(0, path.size() - 2)
	var from: Vector3 = path[segment]
	var to: Vector3 = path[segment + 1]
	var sideways := Vector3.UP.cross((to - from).normalized())
	ped.global_position = from.lerp(to, _rng.randf_range(0.08, 0.92)) + sideways * _rng.randf_range(-0.65, 0.65)
	ped.lane_dir = 1 if _rng.randf() > 0.5 else -1
	ped.lane_index = segment + (1 if ped.lane_dir > 0 else 0)
	var facing: Vector3 = path[ped.lane_index] - ped.global_position
	ped.rotation.y = atan2(-facing.x, -facing.z)

# --------------------------------------------------------------------- update
func _process(delta: float) -> void:
	if Game.simulation_paused:
		return
	_signal_clock = fmod(_signal_clock + delta, 28.0)
	_update_signal_lamps()
	for car in cars:
		if not is_instance_valid(car) or car.disabled or not car.has_ai:
			continue
		var nxt = car.get_meta("next_node", null)
		if nxt == null:
			continue
		var target: Vector3 = car.ai_target
		var distance_to_stop := car.global_position.distance_to(Vector3(target.x, car.global_position.y, target.z))
		var from_node: Vector3 = car.get_meta("from_node", car.global_position)
		var green := signal_allows(nxt - from_node)
		car.ai_speed_limit = INF
		if not green and distance_to_stop < 34.0:
			car.ai_speed_limit = maxf(0.0, (distance_to_stop - 3.0) * 0.75)
		if distance_to_stop < 7.0 and green:
			var from := Vector3(nxt.x, car.global_position.y, nxt.z)
			var edge: Vector3 = _pick_next_edge(car)
			if edge == Vector3.ZERO:
				continue
			car.set_meta("from_node", from)
			car.ai_target = _lane_point(from, edge)
			car.set_meta("next_node", edge)
	for pc in police_cars:
		if not is_instance_valid(pc) or pc.disabled:
			continue
		if _player:
			# With eyes on the player they converge; otherwise they sweep the
			# last known position (LAW-04 search phase).
			var goal: Vector3 = _player.controlled_actor().global_position if Game.player_seen else Game.last_seen_position
			pc.ai_target = _pursuit_waypoint(pc, goal)
	_update_police(delta)

## Road-graph pursuit (wave 5). Wave 2-4 aimed responders straight at the
## player, so a car on the far side of a block drove into the buildings. Close
## with a clear line, chase directly; otherwise follow the junction grid one
## Manhattan step at a time toward the goal's nearest junction.
func _pursuit_waypoint(pc: Car, goal: Vector3) -> Vector3:
	var here := pc.global_position
	var gap := Vector2(goal.x - here.x, goal.z - here.z).length()
	if gap < 45.0:
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(here + Vector3.UP, goal + Vector3.UP)
		q.collision_mask = 1
		if space == null or space.intersect_ray(q).is_empty():
			pc.set_meta("pursuit_wp", -1)
			return goal
	# Commit to one junction at a time (a fresh nearest-node choice every frame
	# flipped between two junctions; critic, wave 5).
	var b := _nearest_node(goal)
	var wp := int(pc.get_meta("pursuit_wp", -1))
	if wp >= 0 and int(pc.get_meta("pursuit_goal", -1)) == b:
		if Vector2(nodes[wp].x - here.x, nodes[wp].z - here.z).length() > 10.0:
			return nodes[wp]
		wp = _grid_step(wp, b)
	else:
		var a := _nearest_node(here)
		wp = a if (a == b or Vector2(nodes[a].x - here.x, nodes[a].z - here.z).length() > 10.0) else _grid_step(a, b)
	pc.set_meta("pursuit_wp", wp)
	pc.set_meta("pursuit_goal", b)
	if wp == b and Vector2(nodes[b].x - here.x, nodes[b].z - here.z).length() <= 10.0:
		# At the goal's own junction: run down the road through it toward the
		# goal instead of parking at the junction (critic pass 2).
		var j := nodes[b]
		if absf(goal.x - j.x) < absf(goal.z - j.z):
			return Vector3(j.x, j.y, goal.z)
		return Vector3(goal.x, j.y, j.z)
	return nodes[wp]

## One Manhattan step on the 5x5 junction grid from node a toward node b.
func _grid_step(a: int, b: int) -> int:
	if a == b:
		return a
	var ra := a / 5
	var ca := a % 5
	var rb := b / 5
	var cb := b % 5
	if absi(cb - ca) >= absi(rb - ra):
		return ra * 5 + ca + signi(cb - ca)
	return (ra + signi(rb - ra)) * 5 + ca

func _pick_next_edge(car: Car) -> Vector3:
	var nxt = car.get_meta("next_node", null)
	if nxt == null:
		return Vector3.ZERO
	var idx := _nearest_node(nxt)
	var neighbours := _neighbours(idx)
	if neighbours.is_empty():
		return nxt
	var options: Array[Vector3] = []
	for n in neighbours:
		var node: Vector3 = nodes[n]
		if node.distance_to(nxt) < 0.5:
			continue
		options.append(node)
	if options.is_empty():
		options.append(nodes[neighbours[_rng.randi_range(0, neighbours.size() - 1)]])
	return options[_rng.randi_range(0, options.size() - 1)]

func _nearest_node(p: Vector3) -> int:
	var best := 0
	var best_d := 1e12
	for i in nodes.size():
		var d := Vector2(nodes[i].x - p.x, nodes[i].z - p.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best

# --------------------------------------------------------------------- police
func _update_police(delta: float) -> void:
	_police_timer -= delta
	var wanted := Game.wanted_level
	for index in range(police_cars.size() - 1, -1, -1):
		var responder := police_cars[index]
		if not is_instance_valid(responder):
			police_cars.remove_at(index)
		elif responder.disabled or (_player and responder.global_position.distance_to(_player.controlled_actor().global_position) > 200.0):
			police_cars.remove_at(index)
			_recycle_police_car(responder)
	for index in range(peds.size() - 1, -1, -1):
		if not is_instance_valid(peds[index]):
			peds.remove_at(index)
	Game.player_seen = false
	if wanted <= 0:
		Sfx.set_siren(false, 1.0)
		# responders stand down and are cleaned up when the search ends (LAW-05)
		for pc in police_cars:
			if is_instance_valid(pc):
				_recycle_police_car(pc)
		police_cars.clear()
		for index in range(peds.size() - 1, -1, -1):
			var officer := peds[index]
			if is_instance_valid(officer) and officer.is_police:
				peds.remove_at(index)
				_recycle_officer(officer)
	if wanted > 0 and _player != null:
		for pc in police_cars:
			if is_instance_valid(pc) and _has_sight(pc.global_position):
				Game.player_seen = true
				Game.last_seen_position = _player.controlled_actor().global_position
				Game.search_timer = 14.0
				break
		if not Game.player_seen:
			for officer in peds:
				if is_instance_valid(officer) and officer.is_police and officer.state != NPC.State.DEAD:
					if officer.global_position.distance_to(_player.controlled_actor().global_position) < 45.0 and _has_sight(officer.global_position):
						Game.player_seen = true
						Game.last_seen_position = _player.controlled_actor().global_position
						Game.search_timer = 14.0
						break
	if wanted <= 0:
		for pc in police_cars:
			if is_instance_valid(pc) and pc.has_ai:
				pc.has_ai = false
				pc.global_position = pc.global_position
		return
	if _player == null:
		return
	# on-foot response: officers appear at a believable distance, never in plain sight
	var live_officers := 0
	for pedestrian in peds:
		if is_instance_valid(pedestrian) and pedestrian.is_police and pedestrian.state != NPC.State.DEAD:
			live_officers += 1
	if Game.mode == Game.MODE_FOOT and _police_timer <= 0.0 and live_officers < mini(2 + wanted, 5):
		_police_timer = 4.5
		var angle := _rng.randf_range(0.0, TAU)
		var pos: Vector3 = _player.controlled_actor().global_position + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(28.0, 45.0)
		pos.y = 0.4
		var activation_started := Time.get_ticks_usec()
		var officer := _take_officer(pos)
		if officer == null:
			# Pool exhausted (more responders than the cap allows): build once.
			officer = NPC.new()
			officer.is_police = true
			add_child(officer)
			officer.global_position = pos
			officer.state = NPC.State.PURSUE
		var activation_us := Time.get_ticks_usec() - activation_started
		_officer_activation_us.append(activation_us)
		print("[profile] officer_activation_us=", activation_us, " pooled=", activation_us < 20000, " live=", live_officers)
		peds.append(officer)
	Sfx.set_siren(wanted > 0 and not police_cars.is_empty(), 1.0 + 0.1 * float(wanted))
	# vehicle pursuit: one active pursuit car, respawned when it is wrecked
	# or has fallen far behind (B13)
	# Response vehicles are bounded, and no new road car is spawned to chase
	# an airborne helicopter. Escaping line of sight can actually end a search.
	if Game.mode == Game.MODE_CAR and police_cars.size() < mini(wanted, 2) and _police_timer <= 0.0:
		_police_timer = 8.0
		var actor: Node3D = _player.controlled_actor()
		var nearest := _nearest_node(actor.global_position)
		var candidates := _neighbours(nearest)
		var spawn_node := nodes[candidates[_rng.randi_range(0, candidates.size() - 1)]] if not candidates.is_empty() else nodes[nearest]
		var pc := _take_police_car(spawn_node + Vector3(4.0, 0.4, 4.0), actor.global_position)
		police_cars.append(pc)

## Twenty-eight-second cycle: ten seconds green and two amber for each
## axis, with two all-red clearance seconds between the approaches.
func signal_allows(direction: Vector3) -> bool:
	var east_west := absf(direction.x) > absf(direction.z)
	return _signal_clock < 10.0 if east_west else (_signal_clock >= 14.0 and _signal_clock < 24.0)

func _update_signal_lamps(force: bool = false) -> void:
	var phase := 0 if _signal_clock < 10.0 else (1 if _signal_clock < 12.0 else (2 if _signal_clock < 14.0 else (3 if _signal_clock < 24.0 else (4 if _signal_clock < 26.0 else 5))))
	if not force and phase == _signal_visual_phase: return
	_signal_visual_phase = phase
	if _signal_materials.is_empty():
		_signal_materials.append(Palette.emissive(Color(1.0, 0.07, 0.025), 3.0))
		_signal_materials.append(Palette.emissive(Color(1.0, 0.57, 0.025), 3.0))
		_signal_materials.append(Palette.emissive(Color(0.025, 1.0, 0.12), 3.0))
		_signal_unlit = Palette.mat(Color(0.025, 0.035, 0.03), 0.35, 0.15)
	for lamp in get_tree().get_nodes_in_group("traffic_lamps"):
		if not lamp is MeshInstance3D: continue
		var axis := int(lamp.get_meta("signal_axis", 0))
		var lens := int(lamp.get_meta("lamp_index", 0))
		var active_lens := 0
		if axis == 0:
			active_lens = 2 if phase == 0 else (1 if phase == 1 else 0)
		else:
			active_lens = 2 if phase == 3 else (1 if phase == 4 else 0)
		lamp.material_override = _signal_materials[active_lens] if lens == active_lens else _signal_unlit

## Can the police at `from` see the player? Distance plus a world ray test.
func _has_sight(from: Vector3) -> bool:
	if _player == null:
		return false
	var to_player: Vector3 = _player.controlled_actor().global_position + Vector3(0.0, 1.2, 0.0) - (from + Vector3(0.0, 1.2, 0.0))
	if to_player.length() > 80.0:
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return true
	var params := PhysicsRayQueryParameters3D.create(from + Vector3(0.0, 1.2, 0.0), from + Vector3(0.0, 1.2, 0.0) + to_player)
	params.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(params)
	return hit.is_empty()

func wanted_reset() -> void:
	for index in range(peds.size() - 1, -1, -1):
		var pedestrian := peds[index]
		if is_instance_valid(pedestrian) and pedestrian.is_police:
			peds.remove_at(index)
			_recycle_officer(pedestrian)
	Game.player_seen = false
	Game.search_timer = 0.0
	_police_timer = 0.0
	Sfx.set_siren(false, 1.0)
	for pc in police_cars:
		if is_instance_valid(pc):
			_recycle_police_car(pc)
	police_cars.clear()

func count_peds() -> int:
	var n := 0
	for p in peds:
		if is_instance_valid(p) and p.state != NPC.State.DEAD:
			n += 1
	return n

func count_traffic() -> int:
	var n := 0
	for c in cars:
		if is_instance_valid(c) and not c.disabled:
			n += 1
	return n
