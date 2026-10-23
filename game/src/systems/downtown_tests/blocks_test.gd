extends RefCounted
## downtown-blocks regression checks (run by SelfTest._downtown_plan_checks).

const Blocks := preload("res://src/world/downtown/blocks.gd")

func run(world: WorldBuilder, suite) -> void:
	var root: Node = world.find_child("DowntownBlocks", true, false)
	suite._check("downtown blocks: piece built its root", root != null)
	if root == null:
		return
	var stats: Dictionary = root.get_meta("blocks_stats", {})
	var mine := Blocks.my_blocks()
	suite._check("downtown blocks: every owned plot is built (%d plots)" % mine.size(), int(stats.get("blocks", 0)) == mine.size(), "built=%s" % stats.get("blocks", 0))
	suite._check("downtown blocks: collision stays inside the 600-box budget", int(stats.get("boxes", 0)) > 0 and int(stats.get("boxes", 0)) <= int(DowntownPlan.PERF["collision_shapes_budget"]["blocks"]), "boxes=%s" % stats.get("boxes", 0))
	suite._check("downtown blocks: no building footprint leaves its plot", int(stats.get("footprint_violations", -1)) == 0, "violations=%s" % stats.get("footprint_violations", -1))
	suite._check("downtown blocks: dense CBD (>= 40 buildings, >= 20 towers over 100 m)", int(stats.get("buildings", 0)) >= 40 and int(stats.get("towers", 0)) >= 20, "buildings=%s towers=%s" % [stats.get("buildings", 0), stats.get("towers", 0)])
	suite._check("downtown blocks: Boat Quay row has >= 60 shophouse units", int(stats.get("boat_quay_units", 0)) >= 60, "units=%s" % stats.get("boat_quay_units", 0))
	# facade variety: no run of more than 3 identical adjacent buildings, and
	# neighbouring towers never share both silhouette and cladding
	var seq: Array = stats.get("sequence", [])
	var worst := 1
	var run_len := 1
	var same_pair := 0
	for i in range(1, seq.size()):
		var a: Dictionary = seq[i - 1]
		var b: Dictionary = seq[i]
		if a["style"] == b["style"] and a["cid"] == b["cid"]:
			same_pair += 1
			run_len += 1
			worst = maxi(worst, run_len)
		else:
			run_len = 1
	suite._check("downtown blocks: adjacent towers never share silhouette + cladding", same_pair == 0 and worst <= 3, "same_pairs=%d worst_run=%d" % [same_pair, worst])
	var styles := {}
	var clads := {}
	for e in seq:
		styles[e["style"]] = true
		clads[e["cid"]] = true
	suite._check("downtown blocks: >= 7 silhouettes and >= 6 claddings in use", styles.size() >= 7 and clads.size() >= 6, "styles=%d claddings=%d" % [styles.size(), clads.size()])
	suite._check("downtown blocks: street frontage (linkways >= 2 km, >= 30 entrances, >= 4 bus stops, >= 40 shop signs)",
		float(stats.get("linkway_m", 0.0)) >= 2000.0 and int(stats.get("entrances", 0)) >= 30 and int(stats.get("bus_stops", 0)) >= 4 and int(stats.get("signs", 0)) >= 40,
		"linkway=%.0f entrances=%s bus=%s signs=%s" % [float(stats.get("linkway_m", 0.0)), stats.get("entrances", 0), stats.get("bus_stops", 0), stats.get("signs", 0)])
	# no procedural background tower inside a built plot
	var inside := 0
	for node in world.find_children("SkylineCity_*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			var o := mm.get_instance_transform(i).origin
			for n in mine:
				if (DowntownPlan.BLOCKS[n]["rect"] as Rect2).has_point(Vector2(o.x, o.z)):
					inside += 1
					break
	suite._check("downtown blocks: built plots are clear of procedural background towers", inside == 0, "inside=%d" % inside)
	# physical presence: a downward ray onto a CBD tower roof hits it high up
	var space := world.get_world_3d().direct_space_state
	var br: Rect2 = DowntownPlan.BLOCKS["cbd_a2"]["rect"]
	var top := -INF
	for ix in 5:
		for iz in 7:
			var p := br.position + br.size * Vector2((float(ix) + 0.5) / 5.0, (float(iz) + 0.5) / 7.0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 400.0, p.y), Vector3(p.x, -5.0, p.y)))
			if not hit.is_empty():
				top = maxf(top, (hit["position"] as Vector3).y)
	suite._check("downtown blocks: CBD towers are collidable from the air", top > 60.0, "highest hit y=%.1f" % top)
