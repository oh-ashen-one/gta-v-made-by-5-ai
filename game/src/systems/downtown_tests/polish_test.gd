extends RefCounted
## downtown-polish (wave S) regression checks (run by self_test._downtown_plan_checks).

func _ray(space: PhysicsDirectSpaceState3D, x: float, z: float, top: float = 6.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -6.0, z), 1)
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else -99.0

func run(world: WorldBuilder, suite: Node) -> void:
	await suite.get_tree().physics_frame
	await suite.get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var stats: Dictionary = world.get_meta("downtown_map_stats", {})
	var pl: Dictionary = stats.get("planting", {})
	# 1. layered roadside planting: >= 4 species/sizes (rain tree, palm, >= 2
	#    shrub / ground-cover kinds), a continuous kerbside strip, palms mixed
	#    into the tree pits and medians, forecourt beds on the plots
	var kinds: Array = pl.get("shrub_kinds", [])
	suite._check("downtown-polish: layered roadside planting (>= 4 species, >= 3000 strip clumps, >= 60 palms, >= 40 forecourt beds)",
		int(pl.get("species", 0)) >= 4 and kinds.size() >= 3 and int(pl.get("strip_clumps", 0)) >= 3000 and int(pl.get("palms", 0)) >= 60 and int(pl.get("forecourt_beds", 0)) >= 40, str(pl))
	# 2. tower ground shadows beyond the shadow map
	var blocks_root := world.find_child("DowntownBlocks", true, false)
	var bstats: Dictionary = blocks_root.get_meta("blocks_stats", {}) if blocks_root != null else {}
	suite._check("downtown-polish: tower ground shadows from the sun (>= 150 buildings incl. MBS)", int(bstats.get("ground_shadows", 0)) >= 150, "shadows=%s" % bstats.get("ground_shadows", 0))
	# 3. Marina Centre reads as a tower cluster (>= 10 buildings, 3+ over 100 m)
	var mc := 0
	var mc_tall := 0
	for e: Dictionary in bstats.get("sequence", []):
		if String(e["block"]).begins_with("marina_centre"):
			mc += 1
			if float(e["h"]) > 100.0:
				mc_tall += 1
	suite._check("downtown-polish: Marina Centre is a dense cluster (>= 10 buildings, >= 4 over 100 m)", mc >= 10 and mc_tall >= 4, "buildings=%d tall=%d" % [mc, mc_tall])
	# 4. towers directly behind MBS rise above the old 70 m cap
	suite._check("downtown-polish: >= 5 towers over 100 m stand directly behind MBS", int(stats.get("behind_mbs_tall", 0)) >= 5, "behind_mbs_tall=%s" % stats.get("behind_mbs_tall", 0))
	# 5. corner plaza: nothing of the blocks piece within 15 m of the
	#    Raffles Avenue / Bayfront Avenue North kerb return
	var corner := Vector2(-780.0, -768.0)
	var near := 0
	for bk: String in DowntownPlan.BLOCKS:
		var b: Dictionary = DowntownPlan.BLOCKS[bk]
		if String(b.get("kind", "")) == "marina_centre":
			var r: Rect2 = b["rect"]
			var cp := Vector2(clampf(corner.x, r.position.x, r.end.x), clampf(corner.y, r.position.y, r.end.y))
			if cp.distance_to(corner) < 15.0:
				near += 1
	suite._check("downtown-polish: Raffles Ave / Bayfront Ave North corner keeps a 15 m plaza", near == 0, "plots_near=%d" % near)
	# 6. the Helix landing plazas are walkable from the quay (edge ramps)
	var ramp_ok := true
	var detail := []
	for p: Vector2 in [Vector2(-495.0, -736.4), Vector2(-503.6 - 0.9, -745.0), Vector2(-265.0, -736.4), Vector2(-255.2, -745.0)]:
		var y := _ray(space, p.x, p.y)
		detail.append("%.2f" % y)
		if y < 0.05 or y > 0.34:
			ramp_ok = false
	suite._check("downtown-polish: Helix landing plazas have walkable edge ramps", ramp_ok, ",".join(detail))
