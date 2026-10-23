extends RefCounted
## downtown-life (wave S) regression checks, run by self_test._downtown_plan_checks
## (DowntownPlan.PIECE_TESTS lists this path).

func run(world: WorldBuilder, suite: Node) -> void:
	var tree := suite.get_tree()
	var traffic := tree.get_first_node_in_group("traffic_manager") as TrafficManager
	# 1. Carriageway raster: lanes, pavements, junction mouths, plazas.
	var raster_ok := StreetRaster.at(-430.0, 100.0) == 1 and StreetRaster.at(-421.0, 100.0) == 0 \
		and StreetRaster.at(-430.0, 0.0) == 2 and StreetRaster.at(-118.0, -642.0) == 0 \
		and StreetRaster.at(-118.0, -780.0) == 1 and StreetRaster.at(0.0, -100.0) == 1 and StreetRaster.at(-171.0, -22.0) == 0
	suite._check("downtown-life: carriageway raster marks Cecil St / Bayfront Ave lanes, not their pavements or the plazas", raster_ok)
	if traffic == null or traffic.ambient == null or traffic.crowd == null:
		suite._check("downtown-life: street life present", false, "street-life off?")
		return
	# 2. No downtown walk vertex lies in a live lane.
	var bad := 0
	for poly in traffic.crowd._polys:
		for q in poly:
			if StreetRaster.at((q as Vector3).x, (q as Vector3).z) == 1:
				bad += 1
	suite._check("downtown-life: no downtown walk line runs along a live lane", bad == 0 and traffic.crowd._polys.size() > 20, "%d bad vertices, %d lines" % [bad, traffic.crowd._polys.size()])
	# 3. Lane cars are seeded from edges near a downtown focus (Cecil St).
	var amb := traffic.ambient
	var keep := amb._focus
	amb._focus = Vector3(-430.0, 0.0, -100.0)
	amb._refresh_near_edges(true)
	var far := 0
	for e in amb._near_edges:
		var ed: Dictionary = amb.edges[e]
		var a: Vector3 = ed["a"]
		var b: Vector3 = ed["b"]
		if minf(a.distance_to(amb._focus), b.distance_to(amb._focus)) > AmbientTraffic.SPAWN_RADIUS + float(ed["len"]):
			far += 1
	suite._check("downtown-life: lane-car seeding draws from edges near the focus", amb._near_edges.size() >= 8 and far == 0, "%d near edges of %d" % [amb._near_edges.size(), amb.edges.size()])
	amb._focus = keep
	amb._refresh_near_edges(true)
	# 4. Plaza activity stations: benches, ice-cream carts, photo spots, all
	#    on level open ground off the carriageway; units sized to the pool.
	for i in 4:
		await tree.physics_frame
	var plaza := traffic.plaza
	var kinds := {}
	var on_road := 0
	if plaza != null:
		for st in plaza.stations:
			kinds[st["kind"]] = int(kinds.get(st["kind"], 0)) + 1
			var p: Vector3 = st["pos"]
			if StreetRaster.at(p.x, p.z) != 0:
				on_road += 1
	var people := 0
	if plaza != null:
		for u in plaza.units:
			people += (u["people"] as Array).size()
	suite._check("downtown-life: plaza stations (benches, ice-cream carts, photo spots) built off the carriageway",
		plaza != null and plaza.stations.size() >= 18 and int(kinds.get("bench", 0)) >= 8 and int(kinds.get("cart", 0)) >= 4 and int(kinds.get("photo", 0)) >= 3 and on_road == 0 and people == PlazaLife.pool_size(),
		"%s on_road=%d people=%d" % [str(kinds), on_road, people])
