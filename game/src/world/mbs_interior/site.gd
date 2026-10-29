extends Node3D
## Source-coordinate MBS assembly. This first integration commits the public
## floor; guest/program stacks, exterior shells and cabins are still pending.
## Never add it over the old solid/fictional hotel at a second position.
const PublicL1 = preload("res://src/world/mbs_interior/public_l1.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
var public_l1: Node3D
var _frame: RefCounted
var _context: RefCounted
var _runtime: Node3D
var _bodies: Array = []
var _built := false
var _committed := false
var _floor_definition: Dictionary = {}
var _report: Dictionary = {}
const FEATURE := "mbs-hotel/public-atrium-recreation"
const FLOOR := "L1"

func _hash(text: String) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(text.to_utf8_buffer())
	return hash.finish().hex_encode()

func _canonical(local: Vector3) -> Array:
	var origin: Array = Reference.DATA.origin_world_xz
	var south: Array = Reference.DATA.axis_south_xz
	var bay: Array = Reference.DATA.axis_bayward_xz
	return [float(origin[0]) + float(south[0]) * float(local.x) + float(bay[0]) * float(local.z),
		float(local.y), float(origin[1]) + float(south[1]) * float(local.x) + float(bay[1]) * float(local.z)]

func _volume(id: String, at: Vector3, half: Vector3) -> Dictionary:
	var south: Array = Reference.DATA.axis_south_xz
	var bay: Array = Reference.DATA.axis_bayward_xz
	return {"schema": "singapore_upright_obox_v1", "volume_id": id, "center_xyz": _canonical(at),
		"half_extents_xyz": [float(half.x), float(half.y), float(half.z)],
		"axis_x_xyz": [float(south[0]), 0.0, float(south[1])],
		"axis_z_xyz": [float(bay[0]), 0.0, float(bay[1])], "dry": true}

func _collect(node: Node) -> void:
	if node is CollisionObject3D and node.collision_layer & 1 != 0: _bodies.append(node)
	for child: Node in node.get_children(): _collect(child)

func build(frame: RefCounted, context: RefCounted, runtime: Node3D) -> Dictionary:
	if _built or not is_inside_tree() or not frame.metadata().configured or not context.metadata().configured:
		return {"built": false, "error": "Require fresh site and configured common source context."}
	if context.metadata().frame_instance_id != frame.get_instance_id() or runtime.context != context:
		return {"built": false, "error": "Site, actors and domains require one geometry/frame authority."}
	_frame = frame
	_context = context
	_runtime = runtime
	public_l1 = PublicL1.new()
	public_l1.name = "SourceMBSHotelPublicL1"
	add_child(public_l1)
	var result: Dictionary = public_l1.build({"source_frame": frame})
	if not result.get("built", false):
		public_l1.queue_free()
		return result
	var volumes: Array = []
	var sections: Array = public_l1.sections
	# Inscribed rotated boxes follow the bent continuous loft. Never turn its
	# rotated whole-site AABB into a dry building volume outside the walls.
	for index in sections.size() - 1:
		var a: float = sections[index].center.x
		var b: float = sections[index + 1].center.x
		var steps := maxi(1, ceili((b - a) / 2.0))
		for step in steps:
			var x0 := lerpf(a, b, float(step) / steps)
			var x1 := lerpf(a, b, float(step + 1) / steps)
			var middle := (x0 + x1) * 0.5
			var center: Vector3 = public_l1._section_at(middle).center
			var east := maxf(public_l1._edge(public_l1._section_at(x0), -1.0, 3.0).z, public_l1._edge(public_l1._section_at(x1), -1.0, 3.0).z)
			var west := minf(public_l1._edge(public_l1._section_at(x0), 1.0).z, public_l1._edge(public_l1._section_at(x1), 1.0).z)
			var width := minf(center.z - east, west - center.z)
			if width <= 0.0: return {"built": false, "error": "Public source volume planning failed."}
			volumes.append(_volume("loft-%d-%d" % [index, step], Vector3(middle, 1.35, center.z), Vector3((x1 - x0) * 0.5, 1.65, width)))
	var portal: Dictionary = public_l1.portal_local
	var outside: Vector3 = portal.outside
	var inside: Vector3 = portal.inside
	volumes.append(_volume("entrance-approach", (outside + inside) * 0.5 + Vector3.UP * 1.35, Vector3(2.0, 1.65, absf(outside.z - inside.z) * 0.5 + 1.0)))
	_collect(public_l1)
	var ids: Array[String] = []
	for index in _bodies.size(): ids.append("public-structure-" + str(index))
	var geometry := _hash(JSON.stringify({"schema": "mbs_source_public_geometry_v1", "geometry_manifest_sha256": context.metadata().geometry_manifest_sha256, "reference": Reference.DATA, "volumes": volumes}))
	_floor_definition = {"feature_id": FEATURE, "floor_id": FLOOR, "geometry_sha256": geometry,
		"support_ids": ids, "volumes": volumes, "provenance": "Actual OSM source site/axes; staged historical atrium form, reconstructed exact metrics/fitout"}
	if not context.register_floor(_floor_definition): return {"built": false, "error": context.last_error}
	_built = true
	_report = {"built": true, "source_site": true, "legacy_layout_or_duplicate_hotel_used": false,
		"canonical_origin_xyz": [Reference.DATA.origin_world_xz[0], 0.0, Reference.DATA.origin_world_xz[1]],
		"public": result, "native_collision_committed": false, "floor_volume_count": volumes.size(),
		"full_MBS_assembly_completed": false, "default_city_bootstrap_migrated": false,
		"pending": ["source exterior/guest/program floor stacks", "physical cabins and connected stairs", "retail/Bayfront Avenue/bridge/city integration", "integrated visual and normal-input acceptance"]}
	return _report.duplicate(true)

func commit_native_floor() -> Dictionary:
	if not _built or _committed: return {"ok": false, "error": "Fresh built site required"}
	# The caller waits for actual physics commits. This method never yields,
	# teleports actors, or stamps geometry before the caller's controlled step.
	var bounds: AABB
	var initial := true
	var pending: Array[Node] = [public_l1]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			var box: AABB = node.global_transform * node.get_aabb()
			bounds = box if initial else bounds.merge(box)
			initial = false
		pending.append_array(node.get_children())
	if initial: return {"ok": false, "error": "No committed source structure"}
	bounds = bounds.grow(3.0)
	var minimum: Dictionary = _frame.to_source_current_live(bounds.position)
	var maximum: Dictionary = _frame.to_source_current_live(bounds.end)
	if not minimum.ok or not maximum.ok: return {"ok": false, "error": "Site exceeds active local frame; rebase before commit"}
	var supports: Array = []
	for index in _bodies.size():
		supports.append({"body": _bodies[index], "feature_id": FEATURE, "floor_id": FLOOR, "support_id": _floor_definition.support_ids[index]})
	_committed = _runtime.commit_region("mbs-public-site", minimum.source_xyz, maximum.source_xyz, _bodies, supports)
	_report.native_collision_committed = _committed
	return {"ok": _committed, "report": _report.duplicate(true)}

func report() -> Dictionary:
	return _report.duplicate(true)
