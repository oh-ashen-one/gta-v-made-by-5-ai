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
		if not amb.traffic._keep_parked_spot(spot, 1):
			missing += 1
	t._check("opening and courtyard parking are protected from thinning", protected > 0 and missing == 0, "%d protected, %d missing" % [protected, missing])
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
	t._check("camera-cut seeding cannot overfill a short lane", not fixture._gap_free(0, 0, 60.0))
	fixture._keys[0] = [a]
	t._check("lane budget still admits separated cars and rejects overlaps", fixture._gap_free(0, 0, 60.0) and not fixture._gap_free(0, 0, 20.0))
	a.free()
	b.free()
	fixture.free()
