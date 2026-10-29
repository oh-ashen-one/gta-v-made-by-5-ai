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
var _collision_mode := "per_feature"
var _faces_per_body := 32768
var _faces_per_frame := 4096
var _maximum_collision_faces := 1000000
var _body_tiles: Dictionary = {}

func configure(frame: RefCounted, material_for_surface: Callable, may_retire: Callable, maximum_tiles: int = 9, features_per_frame: int = 16, identity: Dictionary = {}, options: Dictionary = {}) -> bool:
	if _configured or not is_inside_tree() or not frame is SourceFrame or not frame.metadata().configured: return false
	if not material_for_surface.is_valid() or not may_retire.is_valid() or maximum_tiles < 1 or maximum_tiles > 25 or features_per_frame < 1 or features_per_frame > 64: return false
	if identity.size() != 2 or identity.get("snapshot_manifest_sha256") != frame.metadata().snapshot_manifest_sha256: return false
	var hash_pattern := RegEx.new(); hash_pattern.compile("^[0-9a-f]{64}$")
	if not identity.get("geometry_identity_sha256") is String or hash_pattern.search(identity.geometry_identity_sha256) == null: return false
	for key in options:
		if not key in ["collision_mode","faces_per_body","faces_per_frame","maximum_collision_faces_per_tile"]: return false
	var mode: Variant = options.get("collision_mode","per_feature")
	if not mode is String or not mode in ["per_feature","static_batches"]: return false
	var limits: Array = [options.get("faces_per_body",32768),options.get("faces_per_frame",4096),options.get("maximum_collision_faces_per_tile",1000000)]
	if not limits[0] is int or limits[0]<8 or limits[0]>65536 or not limits[1] is int or limits[1]<128 or limits[1]>16384 or not limits[2] is int or limits[2]<128 or limits[2]>2000000: return false
	_collision_mode = mode; _faces_per_body = limits[0]; _faces_per_frame = limits[1]; _maximum_collision_faces = limits[2]
	_identity = identity.duplicate(true)
	_frame = frame; _materials = material_for_surface; _retire_guard = may_retire
	if _materials.get_object() is RefCounted: _material_owner = _materials.get_object()
	if _retire_guard.get_object() is RefCounted: _guard_owner = _retire_guard.get_object()
	_maximum_tiles = maximum_tiles; _feature_batch = features_per_frame; _configured = true
	return true

func _new_batch(holder: Node3D,key: String,identity: String,faces: PackedVector3Array,ranges: Array[Dictionary],index: int) -> Dictionary:
	var body := StaticBody3D.new(); body.collision_layer = 0; body.collision_mask = 0
	body.name = "SourceCollisionBatch_"+str(index); holder.add_child(body)
	var collision := CollisionShape3D.new(); collision.name = "ExactSourceTriangles"
	var shape := ConcavePolygonShape3D.new(); shape.backface_collision = false; shape.set_faces(faces)
	collision.shape = shape; body.add_child(collision)
	var feature_set: Dictionary = {}; var fragment_set: Dictionary = {}
	for source: Dictionary in ranges:
		feature_set[source.feature_key] = true; fragment_set[source.fragment_key] = true
	var features: Array[String] = []; features.assign(feature_set.keys())
	var fragments: Array[String] = []; fragments.assign(fragment_set.keys())
	body.set_meta("source_geometry_identity",identity)
	body.set_meta("source_city_batch",{"tile_key":key,"batch_index":index,"feature_ids":features,"fragment_ids":fragments})
	return {"body":body,"shape":collision,"source":{"ranges":ranges.duplicate(true),"face_count":faces.size()/3,"shape_instance_id":shape.get_instance_id(),"feature_ids":features,"fragment_ids":fragments}}

func _source_range(feature: Dictionary,first: int,count: int,feature_first: int) -> Dictionary:
	return {"feature_key":feature.feature_key,"fragment_key":feature.fragment_key,"catalog_owner":feature.get("catalog_owner",""),"logical_feature_source_sha256":feature.get("logical_feature_source_sha256",""),"first_face":first,"face_count":count,"feature_first_face":feature_first}

func install_tile(decoded: Dictionary) -> Dictionary:
	if not _configured or _busy: return {"ok": false, "reason": "Scene installer unavailable/busy"}
	if not decoded.get("ok", false) or not decoded.get("features") is Array or not decoded.get("tile_key") is String: return {"ok": false, "reason": "Require validated city-provider mesh data"}
	if decoded.get("identity_sha256") != _identity.geometry_identity_sha256: return {"ok": false, "reason": "Decoded tile belongs to a different geometry authority"}
	var key: String = decoded.tile_key
	if _tiles.has(key): return {"ok": false, "reason": "Tile already installed; retire its owned generation first"}
	if _tiles.size() >= _maximum_tiles or decoded.features.size() > 20000: return {"ok": false, "reason": "Bounded active scene budget reached"}
	if _collision_mode=="static_batches":
		var face_total := 0
		for feature: Dictionary in decoded.features:
			for surface: Dictionary in feature.surfaces:
				var indices: Variant = surface.arrays[Mesh.ARRAY_INDEX]
				if not indices is PackedInt32Array or indices.size()%3!=0: return {"ok":false,"reason":"Batching requires validated indexed triangle surfaces"}
				face_total += indices.size()/3
				if face_total>_maximum_collision_faces: return {"ok":false,"reason":"Explicit tile collision-face memory/work bound exceeded"}
	var projection: Dictionary = _frame.to_local(decoded.get("anchor_source_xyz"))
	if not projection.ok: return projection
	var epoch: int = _frame.metadata().origin_revision
	_busy = true
	var holder := Node3D.new(); holder.name = "SourceCity_" + key.validate_node_name()
	holder.visible = false; add_child(holder); holder.global_position = projection.position
	var bodies: Array[StaticBody3D] = []
	var fragments: Dictionary = {}
	var seen_fragments: Dictionary = {}
	var surface_count := 0
	var triangle_count := 0
	var shape_sources: Dictionary = {}
	var pending_faces := PackedVector3Array()
	var pending_ranges: Array[Dictionary] = []
	var frame_face_work := 0
	for index in decoded.features.size():
		if not _materials.is_valid() or _frame.metadata().origin_revision != epoch:
			return await _discard(holder, "Source epoch/material owner changed during construction")
		var feature: Dictionary = decoded.features[index]
		if seen_fragments.has(feature.fragment_key): return await _discard(holder, "Duplicate source fragment")
		seen_fragments[feature.fragment_key] = true
		var mesh := ArrayMesh.new()
		var feature_triangles := 0
		for surface: Dictionary in feature.surfaces:
			var material: Variant = _materials.call(feature.feature_key, surface.role)
			if not material is Material: return await _discard(holder, "World material resolver returned no valid material")
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
			surface_count += 1
			triangle_count += (surface.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			feature_triangles += (surface.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var visual := MeshInstance3D.new(); visual.mesh = mesh
		visual.name = feature.fragment_key.validate_node_name(); holder.add_child(visual)
		visual.set_meta("source_feature_id", feature.feature_key)
		visual.set_meta("source_fragment_id", feature.fragment_key)
		if _collision_mode=="per_feature":
			var body := StaticBody3D.new(); body.collision_layer = 0; body.collision_mask = 0
			body.name = "Collision_" + feature.fragment_key.validate_node_name(); holder.add_child(body)
			var shape := CollisionShape3D.new(); shape.shape = mesh.create_trimesh_shape(); body.add_child(shape)
			body.set_meta("source_feature_id", feature.feature_key)
			body.set_meta("source_fragment_id", feature.fragment_key)
			body.set_meta("source_geometry_identity", decoded.identity_sha256)
			bodies.append(body); fragments[feature.fragment_key] = body.get_instance_id()
			shape_sources[shape.get_instance_id()] = {"ranges":[_source_range(feature,0,feature_triangles,0)],"face_count":feature_triangles,"shape_instance_id":shape.shape.get_instance_id() if shape.shape!=null else 0,"feature_ids":[feature.feature_key],"fragment_ids":[feature.fragment_key]}
		else:
			# Same Mesh.get_faces expansion used by trimesh creation, preserving
			# every original surface/index triangle and winding. Only grouping
			# changes; normals/UVs/materials and visual meshes above are untouched.
			var exact_faces: PackedVector3Array = mesh.get_faces()
			if exact_faces.is_empty() or exact_faces.size()!=feature_triangles*3: return await _discard(holder,"Source mesh face expansion differs from exact indexed surface triangles")
			var cursor := 0
			while cursor<exact_faces.size()/3:
				var pending_count: int = pending_faces.size()/3
				var count: int = mini(_faces_per_body-pending_count,mini(_faces_per_frame-frame_face_work,exact_faces.size()/3-cursor))
				pending_ranges.append(_source_range(feature,pending_count,count,cursor))
				pending_faces.append_array(exact_faces.slice(cursor*3,(cursor+count)*3))
				cursor += count; frame_face_work += count
				if pending_faces.size()/3==_faces_per_body:
					var batch: Dictionary = _new_batch(holder,key,decoded.identity_sha256,pending_faces,pending_ranges,bodies.size())
					bodies.append(batch.body); shape_sources[batch.shape.get_instance_id()] = batch.source
					for source: Dictionary in pending_ranges:
						if not fragments.has(source.fragment_key): fragments[source.fragment_key] = batch.body.get_instance_id()
					pending_faces = PackedVector3Array(); pending_ranges = []
				if frame_face_work>=_faces_per_frame:
					await get_tree().process_frame
					frame_face_work = 0
					if _frame.metadata().origin_revision!=epoch or not _materials.is_valid(): return await _discard(holder,"Source epoch/material changed during bounded collision expansion")
		if (index + 1) % _feature_batch == 0: await get_tree().process_frame
	if _collision_mode=="static_batches" and not pending_faces.is_empty():
		var batch: Dictionary = _new_batch(holder,key,decoded.identity_sha256,pending_faces,pending_ranges,bodies.size())
		bodies.append(batch.body); shape_sources[batch.shape.get_instance_id()] = batch.source
		for source: Dictionary in pending_ranges:
			if not fragments.has(source.fragment_key): fragments[source.fragment_key] = batch.body.get_instance_id()
	if _frame.metadata().origin_revision != epoch: return await _discard(holder, "Source origin changed before collision commit")
	for body: StaticBody3D in bodies: body.collision_layer = 1
	for tick in 3: await get_tree().physics_frame
	if _frame.metadata().origin_revision != epoch: return await _discard(holder, "Source origin changed during native insertion")
	for body: StaticBody3D in bodies:
		if PhysicsServer3D.body_get_space(body.get_rid()) != get_world_3d().space or PhysicsServer3D.body_get_shape_count(body.get_rid()) != 1:
			return await _discard(holder, "Native collision did not commit")
	var receipt := {"tile_key": key, "source_geometry_identity": decoded.identity_sha256,
		"anchor_source_xyz": decoded.anchor_source_xyz.duplicate(), "origin_revision": epoch,
		"feature_count": decoded.features.size(), "surfaces": surface_count, "triangles": triangle_count,
		"collision_mode":_collision_mode,"collision_body_count":bodies.size(),"collision_shape_count":shape_sources.size(),"maximum_faces_per_collision_body":_faces_per_body if _collision_mode=="static_batches" else 0,
		"native_collision_committed": true, "source_runtime_residency_registered": false,
		"whole_city_or_visual_acceptance": false}
	holder.visible = true
	_tiles[key] = {"node": holder, "bodies": bodies, "fragments": fragments, "receipt": receipt,"shape_sources":shape_sources}
	for body: StaticBody3D in bodies: _body_tiles[body.get_instance_id()] = key
	_busy = false
	tile_committed.emit(key, receipt.duplicate(true))
	return {"ok": true, "receipt": receipt.duplicate(true)}

## Invoke immediately on a fresh native ray hit. Concave face ranges identify
## original source features even when many share one body/shape. Unknown face
## data never guesses a source ID. This is not authentication of forged hits.
func resolve_source_hit(hit: Dictionary) -> Dictionary:
	var body: Variant = hit.get("collider")
	if not is_instance_valid(body) or not body is StaticBody3D or not body.is_inside_tree() or body.collision_layer==0 or body.get_world_3d()!=get_world_3d(): return {"ok":false,"reason":"Hit has no active owned source body"}
	var key: String = _body_tiles.get(body.get_instance_id(),"")
	if key.is_empty() or not _tiles.has(key): return {"ok":false,"reason":"Hit belongs to foreign or retired geometry"}
	var entry: Dictionary = _tiles[key]
	if entry.receipt.origin_revision!=_frame.metadata().origin_revision: return {"ok":false,"reason":"Hit belongs to stale source origin"}
	if PhysicsServer3D.body_get_space(body.get_rid())!=get_world_3d().space: return {"ok":false,"reason":"Native body no longer belongs to the installed physics space"}
	if hit.has("rid") and (not hit.rid is RID or hit.rid!=body.get_rid()): return {"ok":false,"reason":"Native hit RID/body mismatch"}
	var shape_index: Variant = hit.get("shape")
	if not shape_index is int or shape_index<0 or shape_index>=PhysicsServer3D.body_get_shape_count(body.get_rid()): return {"ok":false,"reason":"Invalid native shape index"}
	var owner: Object = body.shape_owner_get_owner(body.shape_find_owner(shape_index))
	if not is_instance_valid(owner) or not owner is CollisionShape3D or owner.get_parent()!=body or owner.disabled or not owner.shape is ConcavePolygonShape3D or not entry.shape_sources.has(owner.get_instance_id()): return {"ok":false,"reason":"Native shape owner is not current source geometry"}
	var descriptor: Dictionary = entry.shape_sources[owner.get_instance_id()]
	if owner.shape.get_instance_id()!=descriptor.shape_instance_id: return {"ok":false,"reason":"Owned collision shape resource was replaced"}
	var face: Variant = hit.get("face_index",-1)
	var source: Dictionary = {}
	if not face is int or face < -1 or face>=descriptor.face_count: return {"ok":false,"reason":"Invalid native concave face index"}
	if face>=0:
		var lo := 0; var hi: int = descriptor.ranges.size()-1
		while lo<=hi:
			var middle: int = (lo+hi)/2
			var row: Dictionary = descriptor.ranges[middle]
			if face<row.first_face: hi = middle-1
			elif face>=row.first_face+row.face_count: lo = middle+1
			else: source = row; break
	elif face==-1 and descriptor.feature_ids.size()==1 and descriptor.fragment_ids.size()==1: source = descriptor.ranges[0]
	if source.is_empty(): return {"ok":false,"reason":"Native face index cannot resolve a unique source fragment"}
	return {"ok":true,"feature_id":source.feature_key,"fragment_id":source.fragment_key,"catalog_owner":source.catalog_owner,"logical_feature_source_sha256":source.logical_feature_source_sha256,"tile_key":key,"geometry_identity_sha256":entry.receipt.source_geometry_identity,"origin_revision":entry.receipt.origin_revision,"native_shape_index":shape_index,"native_face_index":face,"fragment_face_index":source.feature_first_face+face-source.first_face if face>=0 else -1}

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
	for body: StaticBody3D in _tiles[tile_key].bodies:
		body.collision_layer = 0
		_body_tiles.erase(body.get_instance_id())
	holder.queue_free()
	for tick in 3: await get_tree().physics_frame
	_tiles.erase(tile_key); _busy = false
	tile_retired.emit(tile_key)
	return {"ok": true, "owned_geometry_reaped": not is_instance_valid(holder)}
