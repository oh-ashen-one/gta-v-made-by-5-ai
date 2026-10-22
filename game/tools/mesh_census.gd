extends Node
## Count render instances in the built district (wave 5 draw-call proxy).
func _ready() -> void:
	var world := WorldBuilder.new()
	add_child(world)
	world.build(Game.seed_value)
	var stats := {"mesh_instances": 0, "multimesh_instances": 0, "multimesh_items": 0, "primitive": {}, "imported": 0, "labels": 0, "lights": 0, "materials": {}, "convertible": 0}
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is MeshInstance3D:
			stats["mesh_instances"] += 1
			var m: Mesh = n.mesh
			if m is PrimitiveMesh:
				var k := m.get_class()
				stats["primitive"][k] = int(stats["primitive"].get(k, 0)) + 1
				var mat: Material = n.material_override
				if mat is StandardMaterial3D and n.get_child_count() == 0 and n.get_groups().is_empty() and (n.get_script() == null) and (mat as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					stats["convertible"] += 1
			else:
				stats["imported"] += 1
			if n.material_override != null:
				stats["materials"][n.material_override.get_instance_id()] = true
		elif n is MultiMeshInstance3D:
			stats["multimesh_instances"] += 1
			stats["multimesh_items"] += n.multimesh.instance_count
		elif n is Label3D:
			stats["labels"] += 1
		elif n is Light3D:
			stats["lights"] += 1
	stats["unique_override_materials"] = stats["materials"].size()
	var by_mesh := {}
	stack = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is MeshInstance3D and not (n.mesh is PrimitiveMesh):
			var overrides := 0
			for i in n.get_surface_override_material_count():
				if n.get_surface_override_material(i) != null: overrides += 1
			var k := "%s|ovr=%d|mo=%s" % [String(n.mesh.resource_path).get_file() if n.mesh.resource_path != "" else str(n.mesh.get_rid().get_id()), overrides, n.material_override != null]
			by_mesh[k] = int(by_mesh.get(k, 0)) + 1
	var top := by_mesh.keys()
	top.sort_custom(func(a, b): return by_mesh[a] > by_mesh[b])
	var rows := []
	for k in top.slice(0, 25): rows.append("%s x%d" % [k, by_mesh[k]])
	print("IMPORTED_TOP ", JSON.stringify(rows))
	stats.erase("materials")
	print("MESH_CENSUS ", JSON.stringify(stats))
	Sfx.shutdown_audio()
	get_tree().quit(0)
