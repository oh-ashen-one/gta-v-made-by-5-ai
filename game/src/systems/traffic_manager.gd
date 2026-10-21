class_name TrafficManager
extends Node3D
## Population and traffic simulation: lane graph, left-hand traffic, civilian
## pedestrians, parked cars, and police response (TRAFFIC-01/02, LAW-02/03).

const LANE_OFFSET := 4.0        # lane centre is 4 m to the LEFT of the road centre
const PED_COUNT := 34
const TRAFFIC_COUNT := 14
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

func setup(w: WorldBuilder, player: Node) -> void:
	world = w
	_player = player
	nodes = w.traffic_nodes
	_ped_lanes = w.ped_lanes
	_rng.seed = Game.seed_value
	_spawn_parked()
	_spawn_traffic()
	_spawn_peds()

# ------------------------------------------------------------------- spawning
func _spawn_parked() -> void:
	var i := 0
	for spot in world.parked_spots:
		var kind := String(spot.get("kind", "sedan"))
		if kind == "van":
			kind = "van"
		var car := Car.new()
		car.kind = kind
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
			car.set_ai_driver(npc)
		i += 1

func _spawn_traffic() -> void:
	for i in TRAFFIC_COUNT:
		var car := _spawn_ai_car(["sedan", "coupe", "van"][i % 3])
		if car:
			cars.append(car)

func _spawn_ai_car(kind: String) -> Car:
	var edge := _random_edge()
	if edge.is_empty():
		return null
	var car := Car.new()
	car.kind = kind
	add_child(car)
	car.global_position = edge["from"].lerp(edge["to"], _rng.randf_range(0.15, 0.8))
	car.rotation.y = atan2(-(edge["to"].x - edge["from"].x), -(edge["to"].z - edge["from"].z))
	car.has_ai = true
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
			if nr < 0 or nr > 3 or nc < 0 or nc > 4:
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
	return from + left * LANE_OFFSET + dir * 8.0

func _spawn_peds() -> void:
	for i in PED_COUNT:
		var ped := NPC.new()
		add_child(ped)
		var lane_id := _rng.randi_range(0, maxi(1, _ped_lanes.size() - 1))
		ped.assign_lane(_ped_lanes, lane_id)
		var lane: Array = _ped_lanes[lane_id]
		if not lane.is_empty():
			var p: Vector3 = lane[_rng.randi_range(0, lane.size() - 1)]
			ped.global_position = p + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
		peds.append(ped)

# --------------------------------------------------------------------- update
func _process(delta: float) -> void:
	if Game.simulation_paused:
		return
	for car in cars:
		if not is_instance_valid(car) or car.disabled:
			continue
		var nxt = car.get_meta("next_node", null)
		if nxt == null:
			continue
		var target: Vector3 = car.ai_target
		if car.global_position.distance_to(Vector3(target.x, car.global_position.y, target.z)) < 7.0:
			var from := Vector3(nxt.x, car.global_position.y, nxt.z)
			var edge: Vector3 = _pick_next_edge(car)
			if edge == Vector3.ZERO:
				continue
			car.ai_target = _lane_point(from, edge)
			car.set_meta("next_node", edge)
	for pc in police_cars:
		if not is_instance_valid(pc) or pc.disabled:
			continue
		if _player:
			# With eyes on the player they converge; otherwise they sweep the
			# last known position (LAW-04 search phase).
			if Game.player_seen:
				pc.ai_target = _player.global_position
			else:
				pc.ai_target = Game.last_seen_position
	_update_police(delta)

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
	Game.player_seen = false
	if wanted <= 0:
		# responders stand down and are cleaned up when the search ends (LAW-05)
		for pc in police_cars:
			if is_instance_valid(pc):
				pc.queue_free()
		police_cars.clear()
		for officer in peds:
			if is_instance_valid(officer) and officer.is_police:
				officer.queue_free()
	if wanted > 0 and _player != null:
		for pc in police_cars:
			if is_instance_valid(pc) and _has_sight(pc.global_position):
				Game.player_seen = true
				Game.last_seen_position = _player.global_position
				Game.search_timer = 14.0
				break
		if not Game.player_seen:
			for officer in peds:
				if is_instance_valid(officer) and officer.is_police and officer.state != NPC.State.DEAD:
					if officer.global_position.distance_to(_player.global_position) < 45.0 and _has_sight(officer.global_position):
						Game.player_seen = true
						Game.last_seen_position = _player.global_position
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
	if Game.mode == Game.MODE_FOOT and _police_timer <= 0.0:
		_police_timer = 4.5
		var officer := NPC.new()
		officer.is_police = true
		add_child(officer)
		var angle := _rng.randf_range(0.0, TAU)
		var pos: Vector3 = _player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(28.0, 45.0)
		pos.y = 0.4
		officer.global_position = pos
		officer.state = NPC.State.PURSUE
		peds.append(officer)
	Sfx.set_siren(wanted > 0 and not police_cars.is_empty(), 1.0 + 0.1 * float(wanted))
	# vehicle pursuit: one active pursuit car, respawned when it is wrecked
	# or has fallen far behind (B13)
	var need_pursuit := false
	if Game.mode != Game.MODE_FOOT:
		for pc in police_cars:
			if not is_instance_valid(pc) or pc.disabled:
				need_pursuit = true
			elif _player and pc.global_position.distance_to(_player.global_position) > 180.0:
				need_pursuit = true
		if police_cars.is_empty():
			need_pursuit = true
	if need_pursuit:
		var pc := Car.new()
		pc.kind = "police"
		add_child(pc)
		var angle2 := _rng.randf_range(0.0, TAU)
		var spawn: Vector3 = _player.global_position + Vector3(cos(angle2), 0.0, sin(angle2)) * POLICE_SPAWN_DISTANCE
		spawn.y = 0.4
		pc.global_position = spawn
		pc.has_ai = true
		pc.max_speed = 30.0
		police_cars.append(pc)

## Can the police at `from` see the player? Distance plus a world ray test.
func _has_sight(from: Vector3) -> bool:
	if _player == null:
		return false
	var to_player: Vector3 = _player.global_position + Vector3(0.0, 1.2, 0.0) - (from + Vector3(0.0, 1.2, 0.0))
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
	for pc in police_cars:
		if is_instance_valid(pc):
			pc.queue_free()
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
