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
	return out
