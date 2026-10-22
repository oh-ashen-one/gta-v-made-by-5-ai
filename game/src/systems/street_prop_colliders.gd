class_name StreetPropColliders
extends RefCounted
## Locomotion-Q: on-foot collision for the street clutter the player used to
## walk through (run-2 critic: "passes through scooters, bikes and planters").
## The street dressing emits its props as MultiMesh batches with no physics,
## and some planters are bare imported meshes. After the world is built this
## reads every such instance once and adds simple boxes on their own physics
## layer (PROP_LAYER) to ONE static body. Only the on-foot player collides
## with that layer: cars, NPCs and the camera spring arm do not, so traffic,
## crowd lanes and the chase camera are unchanged. No visual change.

const PROP_LAYER := 1 << 12
const SOLID_KINDS := ["bike", "scooter", "box", "cyl", "cone"]
static var built := false
static var shape_count := 0

static func ensure(tree: SceneTree) -> void:
	if built or tree == null or tree.current_scene == null:
		return
	built = true
	var body := StaticBody3D.new()
	body.name = "StreetPropColliders"
	body.collision_layer = PROP_LAYER
	body.collision_mask = 0
	tree.current_scene.add_child(body)
	shape_count = 0
	for node in tree.current_scene.find_children("StreetDressing_*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var kind := String(mmi.name).trim_prefix("StreetDressing_").get_slice("_", 0)
		if not (kind in SOLID_KINDS) or mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		var aabb := mmi.multimesh.mesh.get_aabb()
		# Instance transforms as the dressing authored them (the headless
		# rendering server keeps no MultiMesh data to read back).
		var xforms: Array = mmi.get_meta("instance_xforms", [])
		for xf in xforms:
			_add_box(body, mmi.global_transform * (xf as Transform3D), aabb, kind)
	# Imported planter pots placed as plain scenes (world_builder street fittings).
	for node in tree.current_scene.find_children("*planter*", "Node3D", true, false):
		var n3 := node as Node3D
		if n3 is MeshInstance3D or n3.find_children("*", "CollisionObject3D", true, false).size() > 0:
			continue
		var box := AABB()
		var first := true
		for m in n3.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var wb: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = wb if first else box.merge(wb)
			first = false
		if not first:
			_add_world_box(body, box)
	print("[street-prop-colliders] %d prop boxes on layer %d" % [shape_count, PROP_LAYER])

static func _add_box(body: StaticBody3D, xf: Transform3D, aabb: AABB, kind: String) -> void:
	var scale := xf.basis.get_scale()
	var size := aabb.size * scale
	# Ground-standing clutter only: no flat paint/grates, no overhead boxes,
	# nothing building-sized (those already have world collision).
	if size.y < 0.28 or maxf(size.x, size.z) > 4.0:
		return
	# Generic boxes/cylinders: only knee-to-waist street clutter with a real
	# footprint (planters, bins, crates, bollards), not walls, signs or trim.
	if kind in ["box", "cyl"] and (size.y > 1.3 or minf(size.x, size.z) < 0.12 or maxf(size.x, size.z) > 2.6):
		return
	var center_local := aabb.get_center()
	var origin := xf * center_local
	var bottom := origin.y - size.y * 0.5
	# Street level is ~0-0.6 m in this district; anything floating higher is
	# signage, awnings or roof clutter.
	if bottom > 1.2:
		return
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	# Slightly slimmer than the visual so the capsule brushes past edges.
	bs.size = Vector3(maxf(size.x * 0.9, 0.08), minf(size.y, 1.4), maxf(size.z * 0.9, 0.08))
	shape.shape = bs
	origin.y = bottom + bs.size.y * 0.5
	shape.transform = Transform3D(xf.basis.orthonormalized(), origin)
	body.add_child(shape)
	shape_count += 1

static func _add_world_box(body: StaticBody3D, box: AABB) -> void:
	if box.size.y < 0.28 or maxf(box.size.x, box.size.z) > 4.0:
		return
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(box.size.x * 0.85, minf(box.size.y, 1.2), box.size.z * 0.85)
	shape.shape = bs
	shape.position = box.get_center()
	body.add_child(shape)
	shape_count += 1
