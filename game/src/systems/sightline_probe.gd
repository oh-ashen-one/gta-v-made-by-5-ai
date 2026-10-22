extends Node
## Headless sightline probe (wave 5). Casts a grid of camera rays against
## temporary trimesh copies of every visible mesh and writes a coarse semantic
## map of what a camera sees: which landmark, building family, tree, vehicle or
## sky occupies each cell, and how much of each landmark is occluded.
##
## This is geometric visibility evidence that runs without a GPU. It is NOT a
## render: no lighting, materials, transparency, fog or leaf alpha (leaf cards
## count as solid, so tree occlusion is overstated). Use it to check framing and
## occlusion; judge the look only from real rendered captures.

const PROBE_LAYER := 1 << 19
const LANDMARK_LAYER := 1 << 20
const W := 256
const H := 144
const CATEGORIES := {
	"sky": Color(0.62, 0.80, 0.96), "marina_bay_sands": Color(0.90, 0.10, 0.10),
	"supertree_grove": Color(0.85, 0.15, 0.85), "artscience_museum": Color(1.0, 0.75, 0.80),
	"singapore_flyer": Color(0.05, 0.85, 0.90), "merlion_landmark": Color(1.0, 0.92, 0.10),
	"shophouse": Color(0.98, 0.55, 0.12), "hdb": Color(0.55, 0.62, 1.0),
	"hawker": Color(0.60, 0.25, 0.10), "tree": Color(0.15, 0.55, 0.15),
	"vehicle": Color(0.10, 0.12, 0.45), "person": Color(1.0, 0.45, 0.70),
	"background_city": Color(0.55, 0.55, 0.58), "water": Color(0.10, 0.45, 0.50),
	"other": Color(0.86, 0.82, 0.70),
}
const LANDMARKS := ["marina_bay_sands", "supertree_grove", "artscience_museum", "singapore_flyer", "merlion_landmark"]

var main: Node
var out_dir := "user://sightlines"
var _shape_cache := {}
var _bodies := 0

func setup(m: Node, dir: String) -> void:
	main = m
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func _run() -> void:
	# Let the player settle and the spring arm resolve before measuring.
	for i in 30:
		await get_tree().physics_frame
	var started := Time.get_ticks_msec()
	var root := Node3D.new()
	root.name = "SightlineProbeShapes"
	add_child(root)
	_collect(get_tree().root, root)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[sightline] probe bodies=", _bodies, " build_ms=", Time.get_ticks_msec() - started)
	var world: WorldBuilder = main.world
	var cam: Camera3D = main.player.camera
	var views: Array[Dictionary] = [
		{"name": "opening_player_camera", "camera": cam},
		{"name": "promenade_merlion", "pos": Vector3(30.0, 1.9, -330.0), "look": Vector3(-60.0, 40.0, -700.0), "fov": 58.0},
		{"name": "aerial_district_fixed", "pos": Vector3(250.0, 95.0, 250.0), "look": Vector3(-40.0, 0.0, -60.0), "fov": 62.0},
		{"name": "heli_approach", "pos": Vector3(120.0, 110.0, -120.0), "look": Vector3(-60.0, 40.0, -650.0), "fov": 62.0},
		{"name": "hawker_road_north", "pos": Vector3(-150.0, 1.9, -60.0), "look": Vector3(-160.0, 30.0, -700.0), "fov": 58.0},
	]
	var report := {"note": "Headless geometric ray probe, not a render. Leaf cards and glass count as opaque.", "grid": [W, H], "views": []}
	var probe_cam := Camera3D.new()
	add_child(probe_cam)
	for view in views:
		var c: Camera3D = view.get("camera", null)
		if c == null:
			probe_cam.global_position = view["pos"]
			probe_cam.fov = float(view["fov"])
			probe_cam.look_at(view["look"], Vector3.UP)
			c = probe_cam
		report["views"].append(_probe_view(String(view["name"]), c))
	var f := FileAccess.open(out_dir + "/sightlines.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("[sightline] done ms=", Time.get_ticks_msec() - started)
	Sfx.shutdown_audio()
	get_tree().quit(0)

func _category(node: Node) -> String:
	var n := node
	var depth := 0
	while n != null and depth < 12:
		if n is Car: return "vehicle"
		if n is Helicopter: return "vehicle"
		if n is NPC or n is Player: return "person"
		var file := String(n.scene_file_path).get_file().get_basename()
		var name_text := String(n.name)
		for key in LANDMARKS:
			if file == key or name_text.begins_with(key): return key
		if file.begins_with("shophouse") or name_text.begins_with("shophouse"): return "shophouse"
		if file.begins_with("hdb") or name_text.begins_with("hdb"): return "hdb"
		if file.begins_with("hawker_pavilion"): return "hawker"
		if file in ["rain_tree", "palm", "fern"]: return "tree"
		if file.begins_with("skyline"): return "background_city"
		n = n.get_parent()
		depth += 1
	return "other"

func _shape_for(mesh: Mesh) -> Shape3D:
	var key := mesh.get_rid()
	if not _shape_cache.has(key):
		_shape_cache[key] = mesh.create_trimesh_shape()
	return _shape_cache[key]

func _add_body(parent: Node3D, shape: Shape3D, xform: Transform3D, category: String) -> void:
	if shape == null: return
	var body := StaticBody3D.new()
	body.collision_layer = PROBE_LAYER | (LANDMARK_LAYER if category in LANDMARKS else 0)
	body.collision_mask = 0
	body.set_meta("cat", category)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	body.global_transform = xform
	_bodies += 1

func _collect(node: Node, parent: Node3D) -> void:
	if node == parent: return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			var category := _category(mi)
			if mi.mesh is PlaneMesh and (mi.mesh as PlaneMesh).size.x > 1000.0: category = "water"
			_add_body(parent, _shape_for(mi.mesh), mi.global_transform, category)
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.mesh != null and mmi.is_visible_in_tree():
			# Physics bodies drop non-uniform scale, so bake each instance's full
			# transform into its own triangle soup and place the body at identity.
			var faces: PackedVector3Array = mmi.multimesh.mesh.get_faces()
			var category := "background_city"
			var batch_name := String(mmi.name)
			if batch_name.begins_with("StaticBatch"):
				category = "other"
				for key in ["rain_tree", "palm", "fern"]:
					if batch_name.contains(key): category = "tree"
				if batch_name.contains("skyline"): category = "background_city"
				if batch_name.contains("shophouse"): category = "shophouse"
				if batch_name.contains("hdb"): category = "hdb"
			var copies: Array = mmi.get_meta("probe_xforms", [])
			for i in mmi.multimesh.instance_count:
				var local: Transform3D = copies[i] if i < copies.size() else mmi.multimesh.get_instance_transform(i)
				var xf := mmi.global_transform * local
				var baked := PackedVector3Array()
				baked.resize(faces.size())
				for f in faces.size():
					baked[f] = xf * faces[f]
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(baked)
				_add_body(parent, shape, Transform3D.IDENTITY, category)
	for child in node.get_children():
		_collect(child, parent)

func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 4000.0, mask)
	q.hit_back_faces = true
	return space.intersect_ray(q)

func _probe_view(view_name: String, cam: Camera3D) -> Dictionary:
	var space := cam.get_world_3d().direct_space_state
	var vp := cam.get_viewport().get_visible_rect().size
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var counts := {}
	var unoccluded := {}
	var boxes := {}
	for y in H:
		for x in W:
			var pixel := Vector2((x + 0.5) / W * vp.x, (y + 0.5) / H * vp.y)
			var origin := cam.project_ray_origin(pixel)
			var dir := cam.project_ray_normal(pixel)
			var hit := _cast(space, origin, dir, PROBE_LAYER)
			var category := "sky"
			if not hit.is_empty():
				category = String((hit["collider"] as Node).get_meta("cat", "other"))
			counts[category] = int(counts.get(category, 0)) + 1
			img.set_pixel(x, y, CATEGORIES.get(category, Color.BLACK))
			if category in LANDMARKS:
				var b: Rect2i = boxes.get(category, Rect2i(x, y, 0, 0))
				boxes[category] = b.expand(Vector2i(x, y))
			var lm := _cast(space, origin, dir, LANDMARK_LAYER)
			if not lm.is_empty():
				var lcat := String((lm["collider"] as Node).get_meta("cat", "other"))
				unoccluded[lcat] = int(unoccluded.get(lcat, 0)) + 1
	img.resize(W * 4, H * 4, Image.INTERPOLATE_NEAREST)
	img.save_png("%s/sightline_%s.png" % [out_dir, view_name])
	var total := float(W * H)
	var shares := {}
	for k in counts: shares[k] = snappedf(float(counts[k]) / total * 100.0, 0.01)
	var landmark_rows := {}
	for key in LANDMARKS:
		var seen := int(counts.get(key, 0))
		var possible := int(unoccluded.get(key, 0))
		var b: Rect2i = boxes.get(key, Rect2i())
		landmark_rows[key] = {"frame_percent": snappedf(seen / total * 100.0, 0.01), "unoccluded_frame_percent": snappedf(possible / total * 100.0, 0.01),
			"visible_fraction": snappedf(float(seen) / float(possible), 0.01) if possible > 0 else 0.0,
			"bbox_norm": [snappedf(b.position.x / float(W), 0.01), snappedf(b.position.y / float(H), 0.01), snappedf(b.end.x / float(W), 0.01), snappedf(b.end.y / float(H), 0.01)] if seen > 0 else []}
	print("[sightline] ", view_name, " ", JSON.stringify(landmark_rows))
	return {"name": view_name, "camera_position": str(cam.global_position.snappedf(0.01)), "camera_forward": str((-cam.global_transform.basis.z).snappedf(0.001)), "fov": cam.fov, "shares_percent": shares, "landmarks": landmark_rows}
