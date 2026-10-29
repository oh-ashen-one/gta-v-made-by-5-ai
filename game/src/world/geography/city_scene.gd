extends Node3D
const SourceFrame = preload("res://src/world/geography/source_frame.gd")
## Main-thread source mesh installation. Decoding/I/O belongs to the producer;
## the world coordinator owns residency, actors, rebases and eviction policy.
signal tile_committed(tile_key: String, receipt: Dictionary)
signal tile_retired(tile_key: String)
var _frame: RefCounted
var _materials: Callable
var _material_owner: RefCounted
var _retire_guard: Callable
var _guard_owner: RefCounted
var _tiles: Dictionary = {}
var _busy := false
var _configured := false
var _maximum_tiles := 9
var _feature_batch := 16
var _identity: Dictionary = {}

func configure(frame: RefCounted, material_for_surface: Callable, may_retire: Callable, maximum_tiles: int = 9, features_per_frame: int = 16, identity: Dictionary = {}) -> bool:
	if _configured or not is_inside_tree() or not frame is SourceFrame or not frame.metadata().configured: return false
	if not material_for_surface.is_valid() or not may_retire.is_valid() or maximum_tiles < 1 or maximum_tiles > 25 or features_per_frame < 1 or features_per_frame > 64: return false
	if identity.size() != 2 or identity.get("snapshot_manifest_sha256") != frame.metadata().snapshot_manifest_sha256: return false
	var hash_pattern := RegEx.new(); hash_pattern.compile("^[0-9a-f]{64}$")
	if not identity.get("geometry_identity_sha256") is String or hash_pattern.search(identity.geometry_identity_sha256) == null: return false
	_identity = identity.duplicate(true)
	_frame = frame; _materials = material_for_surface; _retire_guard = may_retire
	if _materials.get_object() is RefCounted: _material_owner = _materials.get_object()
	if _retire_guard.get_object() is RefCounted: _guard_owner = _retire_guard.get_object()
	_maximum_tiles = maximum_tiles; _feature_batch = features_per_frame; _configured = true
	return true

func install_tile(decoded: Dictionary) -> Dictionary:
	if not _configured or _busy: return {"ok": false, "reason": "Scene installer unavailable/busy"}
	if not decoded.get("ok", false) or not decoded.get("features") is Array or not decoded.get("tile_key") is String: return {"ok": false, "reason": "Require validated city-provider mesh data"}
	if decoded.get("identity_sha256") != _identity.geometry_identity_sha256: return {"ok": false, "reason": "Decoded tile belongs to a different geometry authority"}
	var key: String = decoded.tile_key
	if _tiles.has(key): return {"ok": false, "reason": "Tile already installed; retire its owned generation first"}
	if _tiles.size() >= _maximum_tiles or decoded.features.size() > 20000: return {"ok": false, "reason": "Bounded active scene budget reached"}
	var projection: Dictionary = _frame.to_local(decoded.get("anchor_source_xyz"))
	if not projection.ok: return projection
	var epoch: int = _frame.metadata().origin_revision
	_busy = true
	var holder := Node3D.new(); holder.name = "SourceCity_" + key.validate_node_name()
	holder.visible = false; add_child(holder); holder.global_position = projection.position
	var bodies: Array[StaticBody3D] = []
	var fragments: Dictionary = {}
	var surface_count := 0
	var triangle_count := 0
	for index in decoded.features.size():
		if not _materials.is_valid() or _frame.metadata().origin_revision != epoch:
			return await _discard(holder, "Source epoch/material owner changed during construction")
		var feature: Dictionary = decoded.features[index]
		if fragments.has(feature.fragment_key): return await _discard(holder, "Duplicate source fragment")
		var mesh := ArrayMesh.new()
		for surface: Dictionary in feature.surfaces:
			var material: Variant = _materials.call(feature.feature_key, surface.role)
			if not material is Material: return await _discard(holder, "World material resolver returned no valid material")
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
			surface_count += 1
			triangle_count += (surface.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var visual := MeshInstance3D.new(); visual.mesh = mesh
		visual.name = feature.fragment_key.validate_node_name(); holder.add_child(visual)
		visual.set_meta("source_feature_id", feature.feature_key)
		visual.set_meta("source_fragment_id", feature.fragment_key)
		var body := StaticBody3D.new(); body.collision_layer = 0; body.collision_mask = 0
		body.name = "Collision_" + feature.fragment_key.validate_node_name(); holder.add_child(body)
		var shape := CollisionShape3D.new(); shape.shape = mesh.create_trimesh_shape(); body.add_child(shape)
		body.set_meta("source_feature_id", feature.feature_key)
		body.set_meta("source_fragment_id", feature.fragment_key)
		body.set_meta("source_geometry_identity", decoded.identity_sha256)
		bodies.append(body); fragments[feature.fragment_key] = body.get_instance_id()
		if (index + 1) % _feature_batch == 0: await get_tree().process_frame
	if _frame.metadata().origin_revision != epoch: return await _discard(holder, "Source origin changed before collision commit")
	for body: StaticBody3D in bodies: body.collision_layer = 1
	for tick in 3: await get_tree().physics_frame
	if _frame.metadata().origin_revision != epoch: return await _discard(holder, "Source origin changed during native insertion")
	for body: StaticBody3D in bodies:
		if PhysicsServer3D.body_get_space(body.get_rid()) != get_world_3d().space or PhysicsServer3D.body_get_shape_count(body.get_rid()) == 0:
			return await _discard(holder, "Native collision did not commit")
	var receipt := {"tile_key": key, "source_geometry_identity": decoded.identity_sha256,
		"anchor_source_xyz": decoded.anchor_source_xyz.duplicate(), "origin_revision": epoch,
		"feature_count": bodies.size(), "surfaces": surface_count, "triangles": triangle_count,
		"native_collision_committed": true, "source_runtime_residency_registered": false,
		"whole_city_or_visual_acceptance": false}
	holder.visible = true
	_tiles[key] = {"node": holder, "bodies": bodies, "fragments": fragments, "receipt": receipt}
	_busy = false
	tile_committed.emit(key, receipt.duplicate(true))
	return {"ok": true, "receipt": receipt.duplicate(true)}

func _discard(holder: Node3D, reason: String) -> Dictionary:
	for child: Node in holder.get_children():
		if child is CollisionObject3D: child.collision_layer = 0
	holder.queue_free()
	for tick in 3: await get_tree().physics_frame
	_busy = false
	return {"ok": false, "reason": reason, "owned_partial_geometry_reaped": not is_instance_valid(holder)}

func collision_bodies(tile_key: String) -> Array:
	return _tiles[tile_key].bodies.duplicate() if _tiles.has(tile_key) else []

func tile_receipt(tile_key: String) -> Dictionary:
	return _tiles[tile_key].receipt.duplicate(true) if _tiles.has(tile_key) else {}

func retire_tile(tile_key: String) -> Dictionary:
	if not _configured or _busy or not _tiles.has(tile_key): return {"ok": false, "reason": "No idle owned tile"}
	if not _retire_guard.is_valid(): return {"ok": false, "reason": "World retirement authority unavailable"}
	var allowed: Variant = _retire_guard.call(tile_key, _tiles[tile_key].receipt.duplicate(true))
	if typeof(allowed) != TYPE_BOOL or not allowed: return {"ok": false, "reason": "World retains this tile's collision"}
	_busy = true
	# The world guard must retire its source-runtime region/support metadata
	# before granting this destruction. This component never moves actors.
	var holder: Node3D = _tiles[tile_key].node
	for body: StaticBody3D in _tiles[tile_key].bodies: body.collision_layer = 0
	holder.queue_free()
	for tick in 3: await get_tree().physics_frame
	_tiles.erase(tile_key); _busy = false
	tile_retired.emit(tile_key)
	return {"ok": true, "owned_geometry_reaped": not is_instance_valid(holder)}
