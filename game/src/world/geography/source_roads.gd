extends RefCounted
## Bound source-road data and explicit main-thread physical ribbon commit.
## No actor, traffic-budget, save, scene-bootstrap or implicit rebase mutation.
const Frame = preload("res://src/world/geography/source_frame.gd")
const SCHEMA := "singapore_source_roads_v1"
const IDENTITY := "singapore_source_roads_identity_v1"
const GRAPH_SCHEMA := "singapore_source_road_graph_chunk_v1"
const MAX_BYTES := 33554432
const MAX_LOADED_OWNERS := 16
const MAX_VERTICES := 200000
const MAX_EDGES := 400000
var last_error := ""
var _configured := false
var _root := ""
var _identity_sha := ""
var _snapshot := ""
var _manifest: Dictionary = {}
var _frame: Variant = null
var _graphs: Dictionary = {}
var _physical: Dictionary = {}
var _loaded: Dictionary = {}
var _vertices: Dictionary = {}
var _adjacency: Dictionary = {}
var _key_to_vertex: Dictionary = {}
var _ways: Dictionary = {}
var _vertex_id_to_key: Dictionary = {}

func _fail(message: String) -> Dictionary: return {"ok": false, "error": message}

func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

func _integer(value: Variant, maximum: int) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) <= maximum and float(value) == floorf(float(value))

func _sha(raw: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(raw)
	return context.finish().hex_encode()

func _point(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3: return false
	for component in value:
		if not _number(component) or absf(float(component)) > Frame.MAX_CANONICAL_COMPONENT_M: return false
	return true

func _read(path: String, limit: int, expected_sha: String = "", expected_bytes: int = -1) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > limit: return _fail("Missing or oversized bound road resource")
	var raw := file.get_buffer(file.get_length())
	file.close()
	if (expected_bytes >= 0 and raw.size() != expected_bytes) or (not expected_sha.is_empty() and _sha(raw) != expected_sha): return _fail("Road resource size/hash mismatch")
	var value: Variant = JSON.parse_string(raw.get_string_from_utf8())
	return {"ok": true, "data": value, "sha256": _sha(raw)} if typeof(value) == TYPE_DICTIONARY else _fail("Road resource is not a JSON object")

func _bound(descriptor: Variant) -> Dictionary:
	if typeof(descriptor) != TYPE_DICTIONARY or typeof(descriptor.get("file")) != TYPE_STRING or typeof(descriptor.get("sha256")) != TYPE_STRING or not _integer(descriptor.get("bytes"), MAX_BYTES): return _fail("Invalid road descriptor")
	var relative: String = descriptor.file
	if relative.is_absolute_path() or relative.contains("..") or relative.contains("\\") or relative != relative.simplify_path(): return _fail("Unsafe road resource path")
	return _read(_root.path_join(relative), MAX_BYTES, descriptor.sha256, int(descriptor.bytes))

## Configure before live rendering. Preparation is synchronous bounded I/O:
## caller schedules it on its worker/setup path, never in a render/physics tick.
func configure(root: Variant, expected_identity_sha256: Variant, frame: Variant) -> bool:
	if _configured or typeof(root) != TYPE_STRING or root.is_empty() or typeof(expected_identity_sha256) != TYPE_STRING or expected_identity_sha256.length() != 64 or not frame is Frame or not frame.metadata().configured:
		last_error = "Require fresh loader, pinned road identity and configured source frame"
		return false
	var identity: Dictionary = _read(root.path_join("identity.json"), 65536, expected_identity_sha256)
	if not identity.ok or typeof(identity.data.get("schema")) != TYPE_STRING or identity.data.schema != IDENTITY:
		last_error = identity.get("error", "Wrong road identity schema")
		return false
	_root = root
	var manifest: Dictionary = _bound(identity.data.get("manifest"))
	if not manifest.ok or typeof(manifest.data.get("schema")) != TYPE_STRING or manifest.data.schema != SCHEMA or typeof(manifest.data.get("snapshot_manifest_sha256")) != TYPE_STRING or manifest.data.snapshot_manifest_sha256 != frame.metadata().snapshot_manifest_sha256 or typeof(manifest.data.get("georeference")) != TYPE_DICTIONARY or JSON.stringify(manifest.data.georeference, "", true, true) != JSON.stringify(frame.metadata().georeference, "", true, true):
		_root = ""
		last_error = manifest.get("error", "Road snapshot/frame mismatch")
		return false
	if typeof(manifest.data.get("graph_chunks")) != TYPE_ARRAY or typeof(manifest.data.get("physical_tiles")) != TYPE_ARRAY:
		last_error = "Missing road graph/physical descriptor arrays"
		_root = ""
		return false
	var graph: Dictionary = {}
	var physical: Dictionary = {}
	for row in manifest.data.graph_chunks:
		if typeof(row) != TYPE_DICTIONARY or typeof(row.get("owner")) != TYPE_STRING or graph.has(row.owner):
			_root = ""; last_error = "Invalid/duplicate graph owner"; return false
		graph[row.owner] = row.duplicate(true)
	for row in manifest.data.physical_tiles:
		if typeof(row) != TYPE_DICTIONARY or typeof(row.get("tile")) != TYPE_STRING or physical.has(row.tile):
			_root = ""; last_error = "Invalid/duplicate physical tile"; return false
		physical[row.tile] = row.duplicate(true)
	_manifest = manifest.data.duplicate(true)
	_graphs = graph
	_physical = physical
	_identity_sha = expected_identity_sha256
	_snapshot = frame.metadata().snapshot_manifest_sha256
	_frame = frame
	_configured = true
	last_error = ""
	return true

func _plan(kind: String, key: String, descriptors: Dictionary) -> Dictionary:
	if not _configured or not descriptors.has(key): return _fail("Road chunk is not in this artifact/work batch; request another compiled batch, not outside-world recovery")
	var read: Dictionary = _bound(descriptors[key])
	if not read.ok: return read
	var plan := {"kind": kind, "key": key, "artifact_identity_sha256": _identity_sha, "snapshot_manifest_sha256": _snapshot, "data": read.data}
	plan["content_sha256"] = _sha(JSON.stringify(read.data, "", true, true).to_utf8_buffer())
	return {"ok": true, "plan": plan}

func prepare_graph(owner: String) -> Dictionary: return _plan("graph", owner, _graphs)
func prepare_physical(tile: String) -> Dictionary: return _plan("physical", tile, _physical)

func _validate_plan(plan: Variant, kind: String) -> Dictionary:
	if not _configured or typeof(plan) != TYPE_DICTIONARY: return _fail("Configure source roads first")
	for key in ["kind", "key", "artifact_identity_sha256", "snapshot_manifest_sha256", "content_sha256"]:
		if typeof(plan.get(key)) != TYPE_STRING: return _fail("Malformed road preparation identity")
	if plan.kind != kind or plan.artifact_identity_sha256 != _identity_sha or plan.snapshot_manifest_sha256 != _snapshot or typeof(plan.get("data")) != TYPE_DICTIONARY: return _fail("Road plan belongs to another artifact/snapshot")
	if plan.content_sha256 != _sha(JSON.stringify(plan.data, "", true, true).to_utf8_buffer()): return _fail("Road preparation contents changed")
	return {"ok": true}

func _graph_valid(data: Dictionary) -> bool:
	if typeof(data.get("schema")) != TYPE_STRING or data.schema != GRAPH_SCHEMA or typeof(data.get("vertices")) != TYPE_ARRAY or typeof(data.get("edges")) != TYPE_ARRAY or typeof(data.get("ways")) != TYPE_ARRAY or data.vertices.size() > MAX_VERTICES or data.edges.size() > MAX_EDGES: return false
	for way in data.ways:
		if typeof(way) != TYPE_DICTIONARY or typeof(way.get("id")) != TYPE_STRING or typeof(way.get("tags")) != TYPE_DICTIONARY: return false
		for key in way.tags:
			if typeof(key) != TYPE_STRING or typeof(way.tags[key]) != TYPE_STRING: return false
	var ids: Dictionary = {}
	for row in data.vertices:
		if typeof(row) != TYPE_DICTIONARY or not _integer(row.get("vertex_id"), 3000000) or int(row.vertex_id) == 0 or typeof(row.get("key")) != TYPE_STRING or not _point(row.get("source_xyz")): return false
		var id := str(int(row.vertex_id))
		if ids.has(id) and ids[id] != row.source_xyz: return false
		ids[id] = row.source_xyz
	for edge in data.edges:
		if typeof(edge) != TYPE_DICTIONARY or typeof(edge.get("id")) != TYPE_STRING or not _integer(edge.get("a"), 3000000) or not _integer(edge.get("b"), 3000000) or not ids.has(str(int(edge.a))) or not ids.has(str(int(edge.b))) or not _number(edge.get("length_m")) or float(edge.length_m) < 0.0 or typeof(edge.get("directions")) != TYPE_DICTIONARY: return false
		for mode in ["car", "bicycle", "foot"]:
			if not _integer(edge.directions.get(mode), 3): return false
	return true

## Graph commit is main-owner state work only, not scene mutation. Canonical
## graph points survive origin rebases; no retained bare Vector3 cache exists.
func commit_graph(plan: Variant) -> Dictionary:
	var checked: Dictionary = _validate_plan(plan, "graph")
	if not checked.ok: return checked
	if not _graphs.has(plan.key) or not _graph_valid(plan.data) or typeof(plan.data.get("owner")) != TYPE_STRING or plan.data.owner != plan.key: return _fail("Invalid graph content or owner")
	var staged: Dictionary = _loaded.duplicate(true)
	staged[plan.key] = plan.data.duplicate(true)
	if staged.size() > MAX_LOADED_OWNERS: return _fail("Bounded graph cache full; explicitly release old owners")
	var built: Dictionary = _graph_lookup(staged)
	if not built.ok: return built
	_loaded = staged
	_vertices = built.vertices
	_adjacency = built.adjacency
	_key_to_vertex = built.key_lookup
	_ways = built.way_lookup
	_vertex_id_to_key = built.id_keys
	return {"ok": true, "owners": _loaded.size(), "vertices": _vertices.size()}

func _graph_lookup(chunks: Dictionary) -> Dictionary:
	var vertices: Dictionary = {}
	var keys: Dictionary = {}
	var vertex_keys: Dictionary = {}
	var adjacency: Dictionary = {}
	var edges: Dictionary = {}
	var ways: Dictionary = {}
	for data: Dictionary in chunks.values():
		for way: Dictionary in data.ways:
			if ways.has(way.id) and JSON.stringify(ways[way.id], "", true, true) != JSON.stringify(way, "", true, true): return _fail("Original way metadata differs across loaded owners")
			ways[way.id] = way.duplicate(true)
		for row: Dictionary in data.vertices:
			var id := str(int(row.vertex_id))
			if vertices.has(id) and vertices[id] != row.source_xyz: return _fail("Shared source vertex differs between graph owners")
			if vertex_keys.has(id) and vertex_keys[id] != row.key: return _fail("Original node/grade identity differs across graph owners")
			if keys.has(row.key) and keys[row.key] != id: return _fail("Original node/grade has conflicting vertex identity")
			vertices[id] = row.source_xyz.duplicate()
			vertex_keys[id] = row.key
			keys[row.key] = id
		for edge: Dictionary in data.edges:
			if edges.has(edge.id) and edges[edge.id] != edge: return _fail("Shared original source edge differs")
			edges[edge.id] = edge
	if vertices.size() > MAX_VERTICES or edges.size() > MAX_EDGES: return _fail("Bounded graph cache vertex/edge limit")
	for edge: Dictionary in edges.values():
		var a := str(int(edge.a)); var b := str(int(edge.b))
		for mode in ["car", "bicycle", "foot"]:
			var bits := int(edge.directions[mode])
			if bits & 1:
				var key: String = mode + "|" + a
				if not adjacency.has(key): adjacency[key] = []
				adjacency[key].append({"to_vertex_id": b, "edge_id": edge.id, "length_m": edge.length_m, "source_way": edge.get("source_way"), "grade_transition": edge.get("grade_transition", false)})
			if bits & 2:
				var key: String = mode + "|" + b
				if not adjacency.has(key): adjacency[key] = []
				adjacency[key].append({"to_vertex_id": a, "edge_id": edge.id, "length_m": edge.length_m, "source_way": edge.get("source_way"), "grade_transition": edge.get("grade_transition", false)})
	return {"ok": true, "vertices": vertices, "key_lookup": keys, "id_keys": vertex_keys, "adjacency": adjacency, "way_lookup": ways}

func successors(original_node_grade_key: String, mode: String) -> Dictionary:
	if not mode in ["car", "bicycle", "foot"]: return _fail("Unknown source transport mode")
	if not _key_to_vertex.has(original_node_grade_key): return {"ok": false, "requires_chunk": true, "error": "Original node/grade not loaded; not outside/void"}
	var id: String = _key_to_vertex[original_node_grade_key]
	var edges: Array = _adjacency.get(mode + "|" + id, []).duplicate(true)
	for edge: Dictionary in edges:
		edge["to_source_xyz"] = _vertices[edge.to_vertex_id].duplicate()
		edge["to_original_node_grade_key"] = _vertex_id_to_key[edge.to_vertex_id]
	return {"ok": true, "vertex_id": id, "source_xyz": _vertices[id].duplicate(), "edges": edges,
		"loaded_owner_scope": _loaded.keys(), "full_incidence_not_certified_in_partial_cache": true, "current_legal_turns_verified": false}

func release_graph(owner: String) -> bool:
	if not _loaded.has(owner): return false
	var staged: Dictionary = _loaded.duplicate(true)
	staged.erase(owner)
	var built: Dictionary = _graph_lookup(staged)
	if not built.ok: return false
	_loaded = staged; _vertices = built.vertices; _adjacency = built.adjacency; _key_to_vertex = built.key_lookup; _ways = built.way_lookup; _vertex_id_to_key = built.id_keys
	return true

func way_record(original_way_id: String) -> Dictionary:
	return {"ok": true, "way": _ways[original_way_id].duplicate(true)} if _ways.has(original_way_id) else {"ok": false, "requires_chunk": true, "error": "Original source way metadata is not loaded"}

## Main thread ONLY. Parent must be the identity local-world root; the frame
## already supplies source-origin subtraction. Validate all before scene edits.
func build_physical(plan: Variant, parent: Node3D, material: Material = null) -> Dictionary:
	var checked: Dictionary = _validate_plan(plan, "physical")
	if not checked.ok: return checked
	if not is_instance_valid(parent) or not parent.is_inside_tree() or not parent.global_transform.is_equal_approx(Transform3D.IDENTITY) or not _physical.has(plan.key): return _fail("Require identity local-world parent and bound physical tile")
	var data: Dictionary = plan.data
	if typeof(data.get("schema")) != TYPE_STRING or data.schema != SCHEMA or typeof(data.get("tile")) != TYPE_STRING or data.tile != plan.key or typeof(data.get("features")) != TYPE_ARRAY: return _fail("Invalid physical road tile")
	var prepared: Array[Dictionary] = []
	var total := 0
	var maximum_native_slope := 0.0
	for feature in data.features:
		if typeof(feature) != TYPE_DICTIONARY or typeof(feature.get("id")) != TYPE_STRING or not _point(feature.get("anchor_source_xyz")) or typeof(feature.get("mesh")) != TYPE_DICTIONARY: return _fail("Invalid source road feature")
		var mesh: Dictionary = feature.mesh
		if typeof(mesh.get("vertices_local_xyz")) != TYPE_ARRAY or typeof(mesh.get("normals")) != TYPE_ARRAY or typeof(mesh.get("indices")) != TYPE_ARRAY or mesh.vertices_local_xyz.size() < 3 or mesh.indices.size() < 3 or mesh.vertices_local_xyz.size() != mesh.normals.size() or mesh.indices.size() % 3 != 0: return _fail("Invalid road render/collision topology")
		total += mesh.vertices_local_xyz.size()
		if total > MAX_VERTICES: return _fail("Physical tile vertex commit budget exceeded")
		var positions := PackedVector3Array(); var normals := PackedVector3Array(); var indices := PackedInt32Array(); var uvs := PackedVector2Array()
		for i in mesh.vertices_local_xyz.size():
			var v: Variant = mesh.vertices_local_xyz[i]; var n: Variant = mesh.normals[i]
			if not _point(v) or not _point(n): return _fail("Nonfinite or premature native source road point")
			var projected: Dictionary = _frame.to_local([float(feature.anchor_source_xyz[0]) + float(v[0]), float(feature.anchor_source_xyz[1]) + float(v[1]), float(feature.anchor_source_xyz[2]) + float(v[2])])
			if not projected.ok: return _fail("Road tile exceeds active frame; rebase/prefetch rather than create absolute vectors")
			var normal := Vector3(float(n[0]), float(n[1]), float(n[2]))
			if normal.y <= 0.0 or absf(normal.length_squared() - 1.0) > .001: return _fail("Invalid source road surface normal")
			positions.append(projected.position); normals.append(normal)
			# Tile-local UVs plus canonical anchor phase stay stable across source
			# rebases without creating huge absolute float texture coordinates.
			uvs.append(Vector2(float(v[0]) * .25 + fposmod(float(feature.anchor_source_xyz[0]), 4.0) * .25, float(v[2]) * .25 + fposmod(float(feature.anchor_source_xyz[2]), 4.0) * .25))
		for index in mesh.indices:
			if not _integer(index, positions.size() - 1): return _fail("Road index out of bounds")
			indices.append(int(index))
		for start in range(0, indices.size(), 3):
			var a: Vector3 = positions[indices[start]]; var b: Vector3 = positions[indices[start + 1]]; var c: Vector3 = positions[indices[start + 2]]
			var cross: Vector3 = (b - a).cross(c - a)
			if cross.y >= 0.0 or cross.length_squared() < .000000000001: return _fail("Native float road triangle is degenerate/reversed; no culling bypass")
			var slope := Vector2(cross.x, cross.z).length() / -cross.y
			maximum_native_slope = maxf(maximum_native_slope, slope)
			if slope > .122: return _fail("Actual native road surface exceeds grade cap; shader normals cannot certify driveability")
		prepared.append({"id": feature.id, "name": feature.get("name"), "positions": positions, "normals": normals, "indices": indices, "uvs": uvs})
	var root := Node3D.new()
	root.name = ("SourceRoads_" + plan.key).validate_node_name()
	if material == null:
		var fallback := StandardMaterial3D.new(); fallback.albedo_color = Color(.17, .18, .18); fallback.roughness = .95; material = fallback
	var batch_positions := PackedVector3Array(); var batch_normals := PackedVector3Array(); var batch_uvs := PackedVector2Array(); var batch_indices := PackedInt32Array()
	var source_names: Dictionary = {}
	for row: Dictionary in prepared:
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = row.positions; arrays[Mesh.ARRAY_NORMAL] = row.normals; arrays[Mesh.ARRAY_INDEX] = row.indices; arrays[Mesh.ARRAY_TEX_UV] = row.uvs
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var offset := batch_positions.size()
		batch_positions.append_array(row.positions); batch_normals.append_array(row.normals); batch_uvs.append_array(row.uvs)
		for index in row.indices: batch_indices.append(int(index) + offset)
		source_names[row.id] = row.name
		var body := StaticBody3D.new(); body.name = (String(row.id) + "_SameTopologyCollision").validate_node_name(); body.collision_layer = 1
		var collision := CollisionShape3D.new(); collision.shape = mesh.create_trimesh_shape(); body.add_child(collision); body.set_meta("source_way", row.id); root.add_child(body)
	if not batch_positions.is_empty():
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = batch_positions; arrays[Mesh.ARRAY_NORMAL] = batch_normals; arrays[Mesh.ARRAY_TEX_UV] = batch_uvs; arrays[Mesh.ARRAY_INDEX] = batch_indices
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var visual := MeshInstance3D.new(); visual.name = "SourceAsphaltMaterialBatch"; visual.mesh = mesh; visual.material_override = material
		visual.set_meta("actual_source_way_names", source_names); root.add_child(visual)
	root.set_meta("source_roads_binding", {"artifact_identity_sha256": _identity_sha, "snapshot_manifest_sha256": _snapshot, "origin_revision": _frame.metadata().origin_revision})
	parent.add_child(root)
	return {"ok": true, "node": root, "features": prepared.size(), "vertices": total, "maximum_native_surface_slope": maximum_native_slope, "origin_revision": _frame.metadata().origin_revision, "actual_support_and_drivability_unverified": true}

func metadata() -> Dictionary:
	return {"configured": _configured, "artifact_identity_sha256": _identity_sha, "snapshot_manifest_sha256": _snapshot,
		"graph_owners": _graphs.keys(), "physical_tiles": _physical.keys(), "loaded_graph_owners": _loaded.keys(),
		"physical_scope": _manifest.get("physical_scope", {}).duplicate(true), "traffic_budget_owned_by_caller": "GLOBAL48ambient/7physics", "actor_or_bootstrap_mutated": false}
