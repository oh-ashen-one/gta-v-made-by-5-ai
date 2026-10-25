extends RefCounted
## traffic-flow (wave T) regression checks: lane traffic obeys the painted
## road (hold lines behind zebras, junction control mapped) and, live, no
## standing car is left on a zebra or inside a junction box.

const Rules := preload("res://src/systems/traffic_rules.gd")

static func run(t: Node, amb: AmbientTraffic) -> void:
	_density_and_spawn_checks(t, amb)
	var rules: Dictionary = amb.stats.get("rules", {})
	t._check("road rules mapped onto the lane graph (signals, priority, give way, zebras)",
		int(rules.get("signal", 0)) > 40 and int(rules.get("major", 0)) + int(rules.get("yield", 0)) > 4 and int(rules.get("zebra_edges", 0)) > 40, str(rules))
	var bad := 0
	var approaches := 0
	for e in amb.edges.size():
		var ed: Dictionary = amb.edges[e]
		if int(ed.get("control", 0)) == Rules.CONTROL_NONE:
			continue
		var length := float(ed["len"])
		for iv: Vector2 in ed.get("clear", []):
			if iv.y > length - 34.0 and iv.x > length * 0.5:
				approaches += 1
				if float(ed["hold"]) > iv.x - 0.4:
					bad += 1
	t._check("junction hold lines sit behind the zebra on every approach", approaches > 40 and bad == 0, "%d/%d approaches" % [bad, approaches])
	var zebra := 0
	var boxed := 0
	var near := 0
	for v in amb.vehicles:
		if not v.active or v.global_position.distance_to(amb._focus) > 170.0:
			continue
		near += 1
		if v.speed > 0.3:
			continue
		if v.j_len > 0.0 and v.s < amb._entry(v.edge) and amb.is_junction_node(int(amb.edges[v.edge]["from"])):
			boxed += 1
		elif amb._on_zebra(v.edge, v.s, v.dims.z * 0.5):
			zebra += 1
	t._check("no standing lane car on a zebra or in a junction box", near >= 8 and near <= 48 and zebra == 0 and boxed == 0, "%d on zebras, %d in boxes, %d cars near" % [zebra, boxed, near])

## Owner density regression: occupancy has an upper bound as well as enough
## traffic to exercise the functional road rules. Do not require the old jam.
static func _density_and_spawn_checks(t: Node, amb: AmbientTraffic) -> void:
	t._check("ambient fleet stays within the free-driving budget",
		amb.vehicles.size() > 0 and amb.vehicles.size() <= 48 and amb.count_active() <= 48,
		"%d allocated, %d active (wave T: 112)" % [amb.vehicles.size(), amb.count_active()])
	t._check("physical civilian traffic stays within the free-driving budget",
		amb.traffic.cars.size() > 0 and amb.traffic.cars.size() <= 7,
		"%d physical traffic cars (wave T: 14)" % amb.traffic.cars.size())
	var parking: Dictionary = amb.traffic.parking_stats
	var available := int(parking.get("road_available", 0))
	var occupied := int(parking.get("road_spawned", 0))
	t._check("road parking leaves at least 40 percent of bays empty",
		available > 0 and occupied >= available / 2 and occupied <= ceili(available * 0.6), str(parking))
	var protected := 0
	var missing := 0
	for spot: Dictionary in amb.traffic.world.parked_spots:
		var pos: Vector3 = spot["pos"]
		var start: Vector3 = amb.traffic.world.locations["player_start"]
		if not bool(spot.get("courtyard_only", false)) and Vector2(pos.x - start.x, pos.z - start.z).length() > TrafficManager.OPENING_PARKING_RADIUS:
			continue
		protected += 1
		var found := false
		for child in amb.traffic.get_children():
			if child is Car and child.get_meta("traffic_parking", false) and child.get_meta("parking_origin", Vector3.INF) == pos:
				var car := child as Car
				found = car.visible and not car.disabled and car.has_method("interact") and car.is_in_group("vehicles")
				break
		if not found:
			missing += 1
	t._check("protected parking produces usable opening and courtyard cars", protected > 0 and missing == 0, "%d protected, %d missing/unusable" % [protected, missing])
	# A populated short lane must reject another seed even when its proposed
	# position has a safe local gap. This catches the old camera-cut bypass.
	var fixture := AmbientTraffic.new()
	fixture.edges.append({"a": Vector3.ZERO, "b": Vector3(80, 0, 0), "dir": Vector3.RIGHT,
		"left": Vector3.FORWARD, "len": 80.0, "entry": 11.0, "stop": 12.0})
	var a := AmbientVehicle.new()
	var b := AmbientVehicle.new()
	a.s = 15.0
	b.s = 30.0
	fixture._keys[0] = [a, b]
	t._check("short-lane budget rejects another seed at a distant gap", not fixture._gap_free(0, 0, 60.0))
	fixture._keys[0] = [a]
	t._check("lane budget still admits separated cars and rejects overlaps", fixture._gap_free(0, 0, 60.0) and not fixture._gap_free(0, 0, 20.0))
	a.free()
	b.free()
	fixture.free()
	_camera_cut_checks(t)

static func _camera_cut_checks(t: Node) -> void:
	# An isolated one-lane street has room for two cars by the occupancy
	# budget, but enough physical gaps for four. Exercise the complete cut
	# path with eight pooled bodies, including failed-seed exhaustion.
	# No live world state or RNG is changed by this fixture.
	var fixture := AmbientTraffic.new()
	t.add_child(fixture)
	fixture.set_process(false)
	fixture.set_physics_process(false)
	fixture._rng.seed = 3007
	fixture.nodes.assign([Vector3(9000, 0, 0), Vector3(9080, 0, 0)])
	fixture._out_edges = {0: [0], 1: []}
	fixture.edges.append({"a": fixture.nodes[0], "b": fixture.nodes[1], "dir": Vector3.RIGHT,
		"left": Vector3.FORWARD, "len": 80.0, "entry": 11.0, "stop": 12.0,
		"from": 0, "to": 1, "offs": [4.6], "signal": false, "hold": 68.0, "clear": [], "y0": 0.0, "y1": 0.0})
	fixture._focus = Vector3(9040, 0, 0)
	fixture._cam_pos = Vector3(9000, 2, 20)
	fixture._cam_fwd = Vector3.RIGHT
	for i in 8:
		var v := AmbientVehicle.new()
		fixture.add_child(v)
		v.active = false
		v.visible = false
		v.collision_layer = 0
		fixture.vehicles.append(v)
	fixture._recycle(true)
	var first := fixture.count_active()
	fixture._recycle(true)
	var second := fixture.count_active()
	var overlaps := 0
	var inactive_colliders := 0
	for i in fixture.vehicles.size():
		var v := fixture.vehicles[i]
		if not v.active:
			if v.collision_layer != 0 or v.visible:
				inactive_colliders += 1
			continue
		for j in range(i + 1, fixture.vehicles.size()):
			var other := fixture.vehicles[j]
			if other.active and absf(v.s - other.s) < AmbientTraffic.MIN_GAP + 3.0:
				overlaps += 1
	t._check("real camera cuts fill only the short-lane budget and exhaust safely",
		first == 2 and second == 2 and overlaps == 0 and inactive_colliders == 0,
		"active %d then %d /8, overlaps %d, inactive colliders %d" % [first, second, overlaps, inactive_colliders])
	fixture.free()
