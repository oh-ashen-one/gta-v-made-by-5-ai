extends Node
## Performance piece (wave S): static census of everything that can draw.
## `--scene-stats` (headless is fine): after the world, traffic and crowd are
## built, walks the tree and reports, per family (the first two path levels
## under the main scene), how many geometry instances, surfaces (≈ draw calls
## before culling), triangles, shadow casters and visibility-ranged nodes exist.
## Writes <capture-dir>/scene_stats.json and prints the top families.

var main: Node
var out_dir := "user://scene_stats"

func setup(m: Node, dir: String) -> void:
	main = m
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

static func mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var tris := 0
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for s in am.get_surface_count():
			var n := am.surface_get_array_index_len(s)
			if n <= 0:
				n = am.surface_get_array_len(s)
			tris += n / 3
	elif mesh is PrimitiveMesh:
		var arr := (mesh as PrimitiveMesh).get_mesh_arrays()
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			tris = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return tris

static func family_of(node: Node, base: Node) -> String:
	var parts: Array[String] = []
	var n := node.get_parent()
	while n != null and n != base:
		var nm := String(n.name)
		var stripped := nm.rstrip("0123456789_@-")
		parts.push_front(stripped if stripped != "" else nm)
		n = n.get_parent()
	var nm2 := String(node.name)
	if node.get_parent() != null and String(node.get_parent().name) == "District":
		# District leaves: fold the numbered batch / building names.
		parts.append(nm2.rstrip("0123456789_@-").left(28))
	return "/".join(parts.slice(0, 3))

static func census(base: Node) -> Dictionary:
	var fams := {}
	var stack: Array[Node] = [base]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		if not node is GeometryInstance3D:
			continue
		var gi := node as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var surfaces := 0
		var tris := 0
		var instances := 1
		if gi is MeshInstance3D:
			var mesh := (gi as MeshInstance3D).mesh
			if mesh == null:
				continue
			surfaces = mesh.get_surface_count()
			tris = mesh_tris(mesh)
		elif gi is MultiMeshInstance3D:
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			surfaces = mm.mesh.get_surface_count()
			instances = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			tris = mesh_tris(mm.mesh) * instances
		else:
			surfaces = 1
		var fam := family_of(gi, base)
		if not fams.has(fam):
			fams[fam] = {"nodes": 0, "surfaces": 0, "tris": 0, "instances": 0, "shadow_surfaces": 0, "shadow_tris": 0, "ranged": 0, "multimesh": 0}
		var f: Dictionary = fams[fam]
		f["nodes"] += 1
		f["surfaces"] += surfaces
		f["tris"] += tris
		f["instances"] += instances
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			f["shadow_surfaces"] += surfaces
			f["shadow_tris"] += tris
		if gi.visibility_range_end > 0.0:
			f["ranged"] += 1
		if gi is MultiMeshInstance3D:
			f["multimesh"] += 1
	return fams

func _run() -> void:
	for i in 30:
		await get_tree().physics_frame
	var fams := census(main)
	var keys := fams.keys()
	keys.sort_custom(func(a, b): return int(fams[a]["surfaces"]) > int(fams[b]["surfaces"]))
	var total := {"nodes": 0, "surfaces": 0, "tris": 0, "shadow_surfaces": 0, "shadow_tris": 0, "ranged": 0}
	for k in keys:
		for t in total:
			total[t] += int(fams[k][t])
	print("[scene-stats] TOTAL ", JSON.stringify(total))
	for k in keys.slice(0, 60):
		print("[scene-stats] ", k, " ", JSON.stringify(fams[k]))
	# Heaviest single nodes (triangles), to find the families worth an LOD.
	var heavy: Array = []
	for gi in main.find_children("*", "GeometryInstance3D", true, false):
		if not (gi as GeometryInstance3D).is_visible_in_tree():
			continue
		var mesh: Mesh = null
		var count := 1
		if gi is MeshInstance3D:
			mesh = gi.mesh
		elif gi is MultiMeshInstance3D and gi.multimesh != null:
			mesh = gi.multimesh.mesh
			count = gi.multimesh.instance_count
		if mesh == null:
			continue
		heavy.append([mesh_tris(mesh) * count, gi, mesh, count])
	heavy.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	for h in heavy.slice(0, 40):
		var g: GeometryInstance3D = h[1]
		var m: Mesh = h[2]
		print("[scene-heavy] tris=", h[0], " n=", h[3], " per=", mesh_tris(m), " shadow=", g.cast_shadow, " vr=", g.visibility_range_end, " mesh=", m.resource_path if m.resource_path != "" else m.resource_name, " path=", main.get_path_to(g))
	var occluders := main.find_children("*", "OccluderInstance3D", true, false).size()
	print("[scene-stats] occluders=", occluders, " use_occlusion_culling=", ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false))
	var f := FileAccess.open(out_dir + "/scene_stats.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"total": total, "families": fams, "occluders": occluders}, "\t"))
	f.close()
	Sfx.shutdown_audio()
	get_tree().quit(0)
