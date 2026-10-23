extends RefCounted
## Wave S performance piece: regression checks (called from SelfTest).
## Each check is [name, passed, detail].

static func run(main: Node) -> Array:
	var out: Array = []
	var world := main.get_node_or_null("World") as WorldBuilder
	var district: Node = world.get_node_or_null("District") if world != null else null
	# Occlusion culling: enabled, and solid building volumes became occluders.
	var occ := district.get_node_or_null("PerfOccluders") if district != null else null
	var occ_n := occ.get_child_count() if occ != null else 0
	out.append(["perf-S: occlusion culling on with >= 150 building occluders (downtown shells, shophouse rows, HDB slabs)",
		bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false)) and occ_n >= 150, "occluders=%d" % occ_n])
	# Every occluder sits above the street band (arcades, lobbies, void decks stay see-through).
	var low := 0
	if occ != null:
		for o in occ.get_children():
			var oi := o as OccluderInstance3D
			var bo := oi.occluder as BoxOccluder3D
			if bo == null or oi.global_position.y - bo.size.y * 0.5 < 3.5:
				low += 1
	out.append(["perf-S: occluders start above the street band (>= 3.5 m)", occ_n > 0 and low == 0, "below=%d" % low])
	# Background tree batches are chunked: no rain-tree MultiMesh holds more than one cell's worth.
	var big := 0
	var tree_mm := 0
	if district != null:
		for c in district.get_children():
			if c is MultiMeshInstance3D and c.multimesh != null and c.multimesh.mesh != null and "rain_tree" in c.multimesh.mesh.resource_path:
				tree_mm += 1
				if c.multimesh.instance_count > 120:
					big += 1
	out.append(["perf-S: rain-tree batches are per-cell (culled, distance LOD), none map-wide", tree_mm > 0 and big == 0, "batches=%d oversized=%d" % [tree_mm, big]])
	var groups: Array = PerfBudget.cell_groups([Transform3D(Basis(), Vector3(10, 0, 10)), Transform3D(Basis(), Vector3(15, 0, 20)), Transform3D(Basis(), Vector3(900, 0, 10))], 200.0)
	out.append(["perf-S: cell grouping splits far instances", groups.size() == 2, "groups=%d" % groups.size()])
	# Crowd animation strides.
	var s_near := PerfBudget.people_anim_stride(10.0 * 10.0, true)
	var s_mid := PerfBudget.people_anim_stride(50.0 * 50.0, true)
	var s_far := PerfBudget.people_anim_stride(120.0 * 120.0, true)
	var s_off := PerfBudget.people_anim_stride(10.0 * 10.0, false)
	out.append(["perf-S: crowd animates every frame near, strided far and off screen", s_near == 1 and s_mid > 1 and s_far >= s_mid and s_off > 1,
		"near=%d mid=%d far=%d off=%d" % [s_near, s_mid, s_far, s_off]])
	# Packaged builds: the look-mesh bake is accepted when the source .glb is not shipped.
	out.append(["perf-S: look bake valid in packaged builds (source .glb absent) and still rejected for a different source",
		CharacterLook._source_matches({"source": "res://assets/providers/__absent__.glb", "source_bytes": 123}, "res://assets/providers/__absent__.glb")
		and not CharacterLook._source_matches({"source": "res://assets/providers/other.glb", "source_bytes": 123}, "res://assets/providers/__absent__.glb"), ""])
	# Director: street-life drawables are kept out of the bay reflection pass.
	var pd := main.get_node_or_null("PerfDirector")
	var tagged := 0
	var untagged := 0
	var traffic := main.get_node_or_null("Traffic")
	if traffic != null:
		for g in traffic.find_children("*", "MeshInstance3D", true, false):
			var gi := g as GeometryInstance3D
			if "Tree" in String(gi.name):
				continue
			if gi.layers & PerfDirector.NO_REFLECT_LAYER:
				tagged += 1
			elif gi.layers & 1:
				untagged += 1
	var rc := world.find_child("BayReflectionCamera", true, false) as Camera3D if world != null else null
	out.append(["perf-S: street-life meshes leave the bay reflection pass (main cameras still see them)",
		pd != null and tagged > 100 and untagged * 20 < tagged and (rc == null or (rc.cull_mask & PerfDirector.NO_REFLECT_LAYER) == 0)
		and (main.get_viewport().get_camera_3d() == null or (main.get_viewport().get_camera_3d().cull_mask & PerfDirector.NO_REFLECT_LAYER) != 0),
		"tagged=%d untagged=%d" % [tagged, untagged]])
	out.append_array(_wave_t(main))
	return out

## Wave T performance piece (CPU side, hitches).
static func _wave_t(main: Node) -> Array:
	var out: Array = []
	# Far walkers: deferred body motion is committed exactly, visual glide reset.
	var npc: NPC = null
	for n in main.get_tree().get_nodes_in_group("npcs"):
		if n is NPC and (n as NPC).body_root != null and (n as NPC).state != NPC.State.DEAD:
			npc = n
			break
	var ok_flush := false
	var detail := "no npc"
	if npc != null:
		var p0 := npc.global_position
		var base := npc.body_root.position
		npc._root_base = base
		npc._far_off = Vector3(0.3, 0.0, -0.2)
		npc.body_root.position = base + Vector3(0.3, 0.0, -0.2)
		npc._flush_far()
		var moved := npc.global_position - p0
		ok_flush = moved.distance_to(Vector3(0.3, 0.0, -0.2)) < 0.001 and npc.body_root.position.distance_to(base) < 0.0001 and npc._far_off == Vector3.ZERO
		detail = "moved=%s root=%s" % [str(moved.snapped(Vector3.ONE * 0.001)), str(npc.body_root.position)]
		npc.global_position = p0
	out.append(["perf-T: far walker deferred motion commits exactly and resets the visual glide", ok_flush, detail])
	var g_near := PerfBudget.far_glide_stride(20.0 * 20.0, true)
	var g_far := PerfBudget.far_glide_stride(100.0 * 100.0, true)
	var g_off := PerfBudget.far_glide_stride(20.0 * 20.0, false)
	out.append(["perf-T: far walkers glide every tick near the lens, strided far / off screen; idlers strided; near walkers full rate",
		g_near == 1 and g_far == 2 and g_off == NPC.SIM_FAR_TICKS and PerfBudget.IDLE_TICKS >= 2 and PerfBudget.IDLE_TICKS <= 6
		and PerfBudget.WALK_FULL_RATE_M >= 6.0, "glide %d/%d/%d idle=%d full=%.0f m" % [g_near, g_far, g_off, PerfBudget.IDLE_TICKS, PerfBudget.WALK_FULL_RATE_M]])
	# Render-sync and first-use hitches.
	var wash := FileAccess.get_file_as_string("res://src/world/boat_wash.gd")
	var fx := FileAccess.get_file_as_string("res://src/actors/car_fx.gd")
	var blur := FileAccess.get_file_as_string("res://src/actors/car_motion_blur.gd")
	out.append(["perf-T: no per-frame render-server readback in boat wash; car probe re-placed on the budget cadence; blur shader shared and prewarmed",
		wash != "" and not wash.contains("get_instance_custom_data") and fx.contains("PerfBudget.CAR_PROBE_STEP") and PerfBudget.CAR_PROBE_STEP >= 0.9
		and blur.contains("static func prewarm") and blur.contains("static var _s_pipeline"), ""])
	# Crowd / lane-car re-seeding: failed seeds are capped per frame / tick (over
	# the bay every far roamer and car retried every frame: 10-20 fps flight).
	var crowd := FileAccess.get_file_as_string("res://src/systems/crowd_director.gd")
	var amb := FileAccess.get_file_as_string("res://src/systems/ambient_traffic.gd")
	out.append(["perf-T: failed crowd and lane-car re-seeds are capped per frame (no retry storm when the focus is over water)",
		PerfBudget.CROWD_SEED_FAILS >= 1 and PerfBudget.TRAFFIC_SEED_FAILS >= 1 and crowd.contains("PerfBudget.CROWD_SEED_FAILS") and amb.contains("PerfBudget.TRAFFIC_SEED_FAILS")
		and crowd.contains("fails -= 1") and amb.contains("fails -= 1"), "crowd=%d traffic=%d" % [PerfBudget.CROWD_SEED_FAILS, PerfBudget.TRAFFIC_SEED_FAILS]])
	return out
