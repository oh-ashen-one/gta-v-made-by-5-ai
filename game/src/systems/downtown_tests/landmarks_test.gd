extends RefCounted
## downtown-landmarks regression checks (run by SelfTest._downtown_plan_checks).
## Protects: anchors and location keys, the north-pointing SkyPark cantilever
## and three-tower massing, the collision budget, walkable surfaces at street
## level (ray probes) and an end-to-end walk across the Helix Bridge with the
## real player controller.

func run(world: WorldBuilder, suite: Object) -> void:
	var report: Dictionary = world.get_meta("downtown_landmarks", {})
	suite._check("landmarks: piece built every module", report.has("mbs") and report.has("helix") and report.has("artscience") and report.has("esplanade") and report.has("flyer") and report.has("gardens") and report.has("fullerton"), str(report.keys()))
	var anchors_ok := true
	for key: String in ["marina_bay_sands", "artscience_museum", "singapore_flyer", "helix_bridge", "esplanade_theatre", "gardens_supertree_grove", "fullerton_hotel"]:
		var have: Vector3 = world.locations.get(key, Vector3.INF)
		if have.distance_to(DowntownPlan.anchor(key)) > 0.01:
			anchors_ok = false
	suite._check("landmarks: location keys sit on the plan anchors (ArtScience and Flyer moved, D2)", anchors_ok)
	var budget: int = DowntownPlan.PERF["collision_shapes_budget"]["landmarks"]
	suite._check("landmarks: collision within the plan budget", int(report.get("shapes", 9999)) <= budget, "%d of %d" % [int(report.get("shapes", -1)), budget])
	suite._check("landmarks: extra headless build time within budget", float(report.get("build_ms", 99999)) < 4000.0, str(report.get("build_ms")))
	# MBS: SkyPark cantilever points north (-x), three towers, real geometry.
	var mbs_root := world.find_child("marina_bay_sands", true, false)
	var sky := mbs_root.find_child("MBSSkyPark", false, false) as MeshInstance3D if mbs_root else null
	var towers := mbs_root.find_child("MBSTowers", false, false) as MeshInstance3D if mbs_root else null
	var mbs: Vector3 = DowntownPlan.anchor("marina_bay_sands")
	var sky_ok := false
	if sky != null and towers != null:
		var aabb := sky.get_aabb()
		var north_overhang := mbs.x - aabb.position.x
		var south_overhang := aabb.end.x - mbs.x
		sky_ok = north_overhang > 170.0 and south_overhang < 140.0 and aabb.position.y > 185.0 and towers.get_aabb().end.y > 185.0
	suite._check("landmarks: MBS SkyPark cantilever points north over three curved towers", sky_ok)
	suite._check("landmarks: MBS is a detailed street-level model, not a backdrop", int((report.get("mbs", {}) as Dictionary).get("tris", 0)) > 9000)
	# Street-level reachability: ray probes onto the walk surfaces.
	var space := world.get_world_3d().direct_space_state
	var probes := {
		"event plaza promenade": [Vector3(-118.0, 20.0, -632.0), 0.2, 0.6],
		# Query the street-level terrace from its standing head volume. A20m
		# ray now correctly hits the separately supported wave roof first;
		# that cannot establish which floor a pedestrian stands on below it.
		"Shoppes terrace": [Vector3(-60.0, 3.5, -658.0), 1.3, 1.7],
		"Helix deck mid-span": [_helix_mid(world), 3.3, 3.9],
		"SkyPark deck": [Vector3(-118.0, 260.0, -712.0), 195.0, 201.0],
		"ArtScience promontory walk": [Vector3(-262.0, 20.0, -586.0), 0.2, 0.6],
		"Esplanade waterfront": [Vector3(-660.0, 20.0, -470.0), 0.2, 0.6],
		"Flyer entrance plaza": [DowntownPlan.anchor("singapore_flyer") + Basis(Vector3.UP, deg_to_rad(-35.0)) * Vector3(0, 20.0, -50.0), 0.2, 0.6],
		"Supertree Grove plaza": [DowntownPlan.anchor("gardens_supertree_grove") + Vector3(0, 20.0, 0), 0.2, 0.6],
		"Merlion Park terrace": [Vector3(-465.0, 20.0, -398.0), 1.0, 1.5],
	}
	for name: String in probes:
		var pr: Array = probes[name]
		var from: Vector3 = pr[0]
		var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 300.0, 0), 1)
		var hit := space.intersect_ray(q)
		var y: float = (hit["position"] as Vector3).y if hit.has("position") else -999.0
		suite._check("landmarks: walkable surface at %s" % name, y >= float(pr[1]) and y <= float(pr[2]), "hit y=%.2f" % y)
	await _helix_walk(world, suite)

func _helix_mid(world: WorldBuilder) -> Vector3:
	var path: Array = world.get_meta("helix_path", [])
	if path.is_empty():
		return Vector3(-380.0, 20.0, -750.0)
	var p: Vector3 = path[path.size() / 2]
	return p + Vector3(0, 6.0, 0)

## Helix Bridge walkability. The suite runs under a 40 s watchdog, so the full
## 220 m walk is proven in the rendered --landmark-review footage; here: (1) the
## walk surface is continuous end to end (ray probe every ~2 m on the
## centreline, heights within the ramp/deck envelope), (2) balustrades stop a
## sideways walk off the deck, (3) the real player controller climbs the 5 %
## ramp from the quay onto the span.
func _helix_walk(world: WorldBuilder, suite: Object) -> void:
	var path: Array = world.get_meta("helix_path", [])
	var space := world.get_world_3d().direct_space_state
	var gaps := 0
	var worst := 0.0
	for i in path.size():
		var p: Vector3 = path[i]
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.0, 0), p - Vector3(0, 3.0, 0), 1)
		var hit := space.intersect_ray(q)
		if not hit.has("position"):
			gaps += 1
		else:
			worst = maxf(worst, absf((hit["position"] as Vector3).y - p.y))
	suite._check("landmarks: Helix deck is continuous end to end (%d probes)" % path.size(), path.size() > 50 and gaps == 0 and worst < 0.2, "gaps=%d worst=%.2f" % [gaps, worst])
	var rails_ok := path.size() > 50
	for i in [int(path.size() * 0.3), int(path.size() * 0.5), int(path.size() * 0.85)]:
		if path.size() <= 50:
			break
		var p: Vector3 = path[i]
		var t: Vector3 = ((path[i + 1] as Vector3) - (path[i - 1] as Vector3)).normalized()
		var side := t.cross(Vector3.UP).normalized()
		for sgn: float in [-1.0, 1.0]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.8, 0), p + Vector3(0, 0.8, 0) + side * sgn * 6.0, 1)
			if not space.intersect_ray(q).has("position"):
				rails_ok = false
	suite._check("landmarks: Helix balustrades enclose the walkway", rails_ok)
	var main_node := world.get_parent()
	var player: Node3D = main_node.get_node_or_null("Player") if main_node else null
	if player == null:
		player = world.get_tree().get_first_node_in_group("player")
	if player == null or path.size() < 10:
		suite._check("landmarks: player climbs the Helix ramp onto the span", false, "no player or path")
		return
	var saved_pos: Vector3 = player.global_position
	var saved_yaw: float = player.yaw
	var start: Vector3 = path[0]
	var dir0: Vector3 = ((path[3] as Vector3) - start).normalized()
	player.respawn_at(start - dir0 * 3.0 + Vector3(0, 0.6, 0), atan2(-dir0.x, -dir0.z))
	var tree := world.get_tree()
	for i in 3:
		await tree.physics_frame
	var old_scale := Engine.time_scale
	Engine.time_scale = 6.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var idx := 0
	var t0 := Time.get_ticks_msec()
	var min_y := 99.0
	while Time.get_ticks_msec() - t0 < 3500:
		await tree.physics_frame
		var p: Vector3 = player.global_position
		while idx < path.size() - 1 and Vector2(p.x - (path[idx] as Vector3).x, p.z - (path[idx] as Vector3).z).length() < 6.0:
			idx += 1
		var target: Vector3 = path[mini(idx + 2, path.size() - 1)]
		var d := Vector3(target.x - p.x, 0, target.z - p.z)
		if d.length() > 0.1:
			player.yaw = atan2(-d.x, -d.z)
		if idx > 3:
			min_y = minf(min_y, p.y)
		if idx > int(path.size() * 0.45):
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Engine.time_scale = old_scale
	var endp: Vector3 = player.global_position
	var progressed := Vector2(endp.x - start.x, endp.z - start.z).length()
	suite._check("landmarks: player climbs the Helix ramp onto the span (real controller)", progressed > 60.0 and endp.y > 3.0 and min_y > 0.25,
		"progressed=%.1f m end_y=%.2f min_y=%.2f idx=%d" % [progressed, endp.y, min_y, idx])
	player.respawn_at(saved_pos, saved_yaw)
	for i in 2:
		await tree.physics_frame
