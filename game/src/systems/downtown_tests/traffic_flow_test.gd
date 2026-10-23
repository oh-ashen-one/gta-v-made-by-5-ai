extends RefCounted
## traffic-flow (wave T) regression checks: lane traffic obeys the painted
## road (hold lines behind zebras, junction control mapped) and, live, no
## standing car is left on a zebra or inside a junction box.

const Rules := preload("res://src/systems/traffic_rules.gd")

static func run(t: Node, amb: AmbientTraffic) -> void:
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
	t._check("no standing lane car on a zebra or in a junction box", near > 20 and zebra == 0 and boxed == 0, "%d on zebras, %d in boxes, %d cars near" % [zebra, boxed, near])
