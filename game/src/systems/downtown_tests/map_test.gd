extends RefCounted
## downtown-map regression checks (run by self_test._downtown_plan_checks).

const Bridges := preload("res://src/world/downtown/bridges.gd")
const Roads := preload("res://src/world/downtown/roads.gd")
const Shoreline := preload("res://src/world/downtown/shoreline.gd")

func _ray(space: PhysicsDirectSpaceState3D, x: float, z: float, top: float = 30.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -6.0, z), 1)
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else -99.0

func run(world: WorldBuilder, suite: Node) -> void:
	await suite.get_tree().physics_frame
	await suite.get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var stats: Dictionary = world.get_meta("downtown_map_stats", {})
	suite._check("downtown-map: piece built (ground, roads, bridges, edges) and took over the legacy ground/rail sections",
		not stats.is_empty() and world._replaced("district_ground") and world._replaced("far_shore_ground") and world._replaced("boundary_rails_x"), str(stats))
	# 1. ground everywhere on playable land, no holes (every 30 m)
	var holes: Array[String] = []
	var r := DowntownPlan.PLAYABLE
	var x := r.position.x + 7.0
	while x < r.end.x:
		var z := r.position.y + 7.0
		while z < r.end.y:
			if DowntownPlan.is_land(Vector3(x, 0, z)) and not Shoreline.is_water_ext(x, z):
				var y := _ray(space, x, z, 3.0 if Bridges.height_at(x, z) < 0.05 else 8.0)
				if y < -0.2:
					holes.append("(%d,%d)" % [x, z])
			z += 30.0
		x += 30.0
	suite._check("downtown-map: every playable land sample has walkable collision (no void)", holes.is_empty(), "holes=%d %s" % [holes.size(), ", ".join(holes.slice(0, 8))])
	# 2. the Marina Bay loop is continuous driveable surface, bridges at deck height
	var loop_pts: Array = [Vector3(-320, 0, -320), Vector3(-470, 0, -320)]
	loop_pts.append_array((DowntownPlan.ROADS["fullerton_road"]["pts"] as Array).slice(1))
	loop_pts.append_array([Vector3(-650, 0, -360), Vector3(-790, 0, -360), Vector3(-790, 0, -780), Vector3(-480, 0, -780), Vector3(-320, 0, -780), Vector3(400, 0, -780), Vector3(400, 0, -320), Vector3(320, 0, -320)])
	var gaps: Array[String] = []
	var max_y := 0.0
	for s: Array in Roads.samples(loop_pts, 5.0):
		var p: Vector3 = s[0]
		var lane := p + Roads.left_of(s[1]) * 3.4
		var expect := Bridges.height_at(lane.x, lane.z)
		var y2 := _ray(space, lane.x, lane.z, expect + 2.5)
		max_y = maxf(max_y, y2)
		if y2 < expect - 0.35 or y2 > expect + 0.6:
			gaps.append("(%d,%d) y=%.2f want %.2f" % [lane.x, lane.z, y2, expect])
	suite._check("downtown-map: Marina Bay loop lane (Collyer Quay - Esplanade Bridge - Raffles Ave - Bayfront Bridge - Marina Blvd) is continuous collision at the road surface",
		gaps.is_empty() and max_y > 3.4, "gaps=%d max_y=%.2f %s" % [gaps.size(), max_y, "; ".join(gaps.slice(0, 6))])
	var spans_ok := true
	var detail := ""
	for name: String in ["esplanade_bridge", "bayfront_bridge", "jubilee_bridge", "cavenagh_bridge", "elgin_bridge", "coleman_bridge"]:
		var b: Dictionary = DowntownPlan.BRIDGES[name]
		var mid: Vector3 = (b["from"] + b["to"]) * 0.5
		var yd := _ray(space, mid.x, mid.z, float(b["deck_y"]) + 3.0)
		var ok := absf(yd - float(b["deck_y"])) < 0.5 and DowntownPlan.is_water(mid)
		spans_ok = spans_ok and ok
		detail += "%s deck %.2f; " % [name, yd]
	suite._check("downtown-map: six bridges stand over water with deck collision at plan height", spans_ok, detail)
	# 3. lane graph published, connected round the loop, linked to the legacy grid
	var g := world.downtown_graph
	var nodes: Array = g.get("nodes", [])
	var edges: Array = g.get("edges", [])
	var adj := {}
	for e: Vector2i in edges:
		adj[e.x] = adj.get(e.x, []) + [e.y]
		adj[e.y] = adj.get(e.y, []) + [e.x]
	var near := func(p: Vector3) -> int:
		var best := -1
		var bd := INF
		for i in nodes.size():
			var d := Vector2(nodes[i].x - p.x, nodes[i].z - p.z).length()
			if d < bd:
				bd = d
				best = i
		return best
	var start: int = near.call(Vector3(-320, 0, -320))
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var n: int = queue.pop_front()
		for k: int in adj.get(n, []):
			if not seen.has(k):
				seen[k] = true
				queue.append(k)
	var reach := true
	for target: Vector3 in [Vector3(-650, 0, -360), Vector3(-790, 0, -780), Vector3(-320, 0, -780), Vector3(400, 0, -780), Vector3(400, 0, 375), Vector3(-900, 0, 0), Vector3(760, 0, -480)]:
		reach = reach and seen.has(near.call(target))
	suite._check("downtown-map: downtown lane graph is connected from the district to the Bayfront, Marina South and civic district, linked to legacy junctions",
		nodes.size() >= 40 and reach and (g.get("links", []) as Array).size() >= 4 and bool(g.get("left_hand", false)) and not world.downtown_ped_lanes.is_empty() and world.traffic_nodes.size() == 25,
		"nodes=%d edges=%d links=%d reach=%s peds=%d" % [nodes.size(), edges.size(), (g.get("links", []) as Array).size(), reach, world.downtown_ped_lanes.size()])
	# 4. helicopter exit rule
	var allowed := DowntownPlan.heli_exit_allowed(Vector3(-580, 0.6, -618)) and DowntownPlan.heli_exit_allowed(Vector3(205, 0.3, -662)) \
		and DowntownPlan.heli_exit_allowed(Vector3(-430, 0.2, 50)) and DowntownPlan.heli_exit_allowed(Vector3(0.4, 0.3, -329.6)) and DowntownPlan.heli_exit_allowed(Vector3(240, 0.3, 240))
	var refused := not DowntownPlan.heli_exit_allowed(Vector3(-150, -0.5, -500)) and not DowntownPlan.heli_exit_allowed(Vector3(-430, 60.0, 50)) and not DowntownPlan.heli_exit_allowed(Vector3(950, 0.2, 0))
	var pads := world.locations.has("helipad_ns_square") and world.locations.has("helipad_the_lawn") and world.locations.has("helipad_esplanade_park") and world.locations.has("helipad_gardens_east")
	suite._check("downtown-map: helicopter may land and exit on downtown streets and the four new pads; water, rooftops and off-map refused", allowed and refused and pads, "allowed=%s refused=%s pads=%s" % [allowed, refused, pads])
	# 5. physical edges: a walker meets a barrier at every PLAYABLE edge
	var edge_ok := true
	var edge_detail := ""
	for probe: Array in [[Vector3(-880, 1.2, -200), Vector3(-920, 1.2, -200)], [Vector3(740, 1.2, -300), Vector3(780, 1.2, -300)], [Vector3(-700, 1.2, 355), Vector3(-700, 1.2, 395)], [Vector3(500, 1.2, 355), Vector3(500, 1.2, 395)], [Vector3(100, 1.2, -1040), Vector3(100, 1.2, -1080)]]:
		var q := PhysicsRayQueryParameters3D.create(probe[0], probe[1], 1)
		var hit := space.intersect_ray(q)
		edge_ok = edge_ok and not hit.is_empty()
		edge_detail += "%s:%s " % [probe[1], not hit.is_empty()]
	suite._check("downtown-map: every playable edge has a physical barrier (hoarding, railing, fence)", edge_ok, edge_detail)
	# 6. the old district side railings no longer wall the district off from downtown
	# along Robinson Road and Market Street, where the old x = +-375 rails stood
	var open_q := PhysicsRayQueryParameters3D.create(Vector3(340, 1.2, -163.4), Vector3(420, 1.2, -163.4), 1)
	var open_q2 := PhysicsRayQueryParameters3D.create(Vector3(-340, 1.2, 3.4), Vector3(-420, 1.2, 3.4), 1)
	suite._check("downtown-map: the district opens onto downtown (no x = +-375 rail wall)", space.intersect_ray(open_q).is_empty() and space.intersect_ray(open_q2).is_empty())
	# 7. budgets
	suite._check("downtown-map: collision and draw budgets (shapes, mesh draws)", int(stats.get("shapes", 99999)) <= 2600 and int(stats.get("draws", 9999)) <= 600 and int(stats.get("build_ms", 9999)) < 4000,
		"shapes=%s draws=%s build_ms=%s" % [stats.get("shapes"), stats.get("draws"), stats.get("build_ms")])
