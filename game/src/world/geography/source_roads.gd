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
const MAX_COLLISION_FACES := 400000
var _collision_batches: Dictionary = {}
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
	if manifest.data.has("surface_contract") and (not manifest.data.surface_contract is String or manifest.data.surface_contract!="source_surface_types_v1"):
		_root="";last_error="Unsupported typed surface manifest contract";return false
	var graph: Dictionary = {}
	var physical: Dictionary = {}
	var cell_parts: Dictionary = {}
	for row in manifest.data.graph_chunks:
		if typeof(row) != TYPE_DICTIONARY or typeof(row.get("owner")) != TYPE_STRING or graph.has(row.owner):
			_root = ""; last_error = "Invalid/duplicate graph owner"; return false
		graph[row.owner] = row.duplicate(true)
	for row in manifest.data.physical_tiles:
		if typeof(row) != TYPE_DICTIONARY or typeof(row.get("tile")) != TYPE_STRING or physical.has(row.tile):
			_root = ""; last_error = "Invalid/duplicate physical tile"; return false
		var cell:Variant=row.get("spatial_tile_key",row.tile)
		if not cell is String or cell.is_empty() or (String(row.tile).contains(".p") and not row.has("spatial_tile_key")):
			_root="";last_error="Explicit physical part/cell identity required";return false
		var ordinal:=-1
		if row.tile!=cell:
			var prefix:String=cell+".p";var suffix:String=String(row.tile).trim_prefix(prefix)
			if not String(row.tile).begins_with(prefix) or suffix.length()!=3 or not suffix.is_valid_int() or int(suffix)<0 or str(int(suffix)).pad_zeros(3)!=suffix:
				_root="";last_error="Malformed physical part ordinal";return false
			ordinal=int(suffix)
		if not cell_parts.has(cell):cell_parts[cell]=[]
		cell_parts[cell].append(ordinal)
		physical[row.tile] = row.duplicate(true)
	for cell:String in cell_parts:
		var parts:Array=cell_parts[cell];parts.sort()
		if parts==[-1]:continue
		for index in parts.size():
			if parts[index]!=index:
				_root="";last_error="Incomplete or mixed physical parts for cell "+cell;return false
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

## Class-specific bounds are code policy, never a file-supplied permission to
## widen the car cap. This v1 prototype still separates access from geometry
## imperfectly; the v4 producer must declare a separately reviewed contract.
func _surface_spec(feature: Dictionary) -> Dictionary:
	var typed: String = _manifest.get("surface_contract","")
	if typed.is_empty():
		if feature.has("physical_contract") or feature.has("visual_mesh"):return _fail("Typed feature needs an explicit manifest contract")
		return {"ok":true,"surface_class":"car_ribbon","cap":.122,"emitted_cap":.121,"separate_visual":false}
	if typed!="source_surface_types_v1":return _fail("Unsupported source surface contract")
	var contract:Variant=feature.get("physical_contract");var policy:Variant=feature.get("policy");var tags:Variant=feature.get("source_tags")
	if not contract is Dictionary or contract.get("schema")!=typed or not policy is Dictionary or not tags is Dictionary:return _fail("Typed road lacks its source policy/tags")
	var modes:Variant=policy.get("modes")
	if not modes is Dictionary or not modes.get("car") is Dictionary or not modes.get("foot") is Dictionary:return _fail("Typed road mode evidence missing")
	var car:Variant=modes.car.get("bits");var foot:Variant=modes.foot.get("bits")
	if not _integer(car,3) or not _integer(foot,3) or contract.get("source_car_direction_bits")!=car or contract.get("source_foot_direction_bits")!=foot:return _fail("Typed mode evidence disagrees")
	var kind:Variant=contract.get("surface_class")
	var caps:Dictionary={"car_ribbon":[.121,.122],"foot_ribbon":[.251,.252],"foot_steps":[.701,.702]}
	if not kind is String or not caps.has(kind):return _fail("Unknown physical surface class")
	if kind=="car_ribbon" and (int(car)==0 or tags.get("highway")=="steps"):return _fail("Car class contradicts its source modes/type")
	if kind!="car_ribbon" and (int(car)!=0 or int(foot)==0):return _fail("Foot-only class cannot widen vehicle geometry")
	if (kind=="foot_steps")!=(tags.get("highway")=="steps"):return _fail("Step geometry must match original source type")
	for pair:Array in [["maximum_emitted_slope",caps[kind][0]],["required_native_slope_cap",caps[kind][1]]]:
		if not _number(contract.get(pair[0])) or absf(float(contract[pair[0]])-float(pair[1]))>.0000001:return _fail("File cap contradicts the fixed class contract")
	if (kind=="foot_steps")!=feature.has("visual_mesh"):return _fail("Steps require separately declared visible treads/risers")
	return {"ok":true,"surface_class":kind,"cap":caps[kind][1],"emitted_cap":caps[kind][0],"separate_visual":kind=="foot_steps"}

func _mesh_arrays(mesh: Variant, anchor: Array, walking: bool, slope_cap: float) -> Dictionary:
	if not mesh is Dictionary or not mesh.get("vertices_local_xyz") is Array or not mesh.get("normals") is Array or not mesh.get("indices") is Array:return _fail("Missing road mesh arrays")
	if mesh.vertices_local_xyz.size()<3 or mesh.vertices_local_xyz.size()>MAX_VERTICES or mesh.vertices_local_xyz.size()!=mesh.normals.size() or mesh.indices.size()<3 or mesh.indices.size()%3!=0 or mesh.indices.size()/3>MAX_COLLISION_FACES:return _fail("Invalid or over-budget road topology")
	var positions:=PackedVector3Array();var normals:=PackedVector3Array();var indices:=PackedInt32Array();var uvs:=PackedVector2Array()
	for index in mesh.vertices_local_xyz.size():
		var vertex:Variant=mesh.vertices_local_xyz[index];var normal:Variant=mesh.normals[index]
		if not _point(vertex) or not _point(normal):return _fail("Nonfinite source mesh component")
		var canonical:Array=[float(anchor[0])+float(vertex[0]),float(anchor[1])+float(vertex[1]),float(anchor[2])+float(vertex[2])]
		if not _frame.to_local(canonical).ok:return _fail("Source road vertex exceeds active frame; prefetch/rebase required")
		var n:=Vector3(normal[0],normal[1],normal[2])
		if absf(n.length_squared()-1.0)>.001 or (walking and n.y<=0.0):return _fail("Invalid source surface normal")
		# Keep the already encoded local coordinates. Flattening anchor+vertex
		# into ArrayMesh world vectors introduces a second Float32 quantization.
		positions.append(Vector3(vertex[0],vertex[1],vertex[2]));normals.append(n)
		uvs.append(Vector2(float(vertex[0])*.25+fposmod(float(anchor[0]),4.0)*.25,float(vertex[2])*.25+fposmod(float(anchor[2]),4.0)*.25))
	for index:Variant in mesh.indices:
		if not _integer(index,positions.size()-1):return _fail("Road index out of bounds")
		indices.append(int(index))
	var maximum_slope:=0.0
	for start in range(0,indices.size(),3):
		var a:Vector3=positions[indices[start]];var b:Vector3=positions[indices[start+1]];var c:Vector3=positions[indices[start+2]]
		var cross:Vector3=(b-a).cross(c-a)
		if cross.length_squared()<.000000000001:return _fail("Degenerate native local triangle")
		if walking:
			if cross.y>=0.0:return _fail("Reversed native walking triangle; no backface bypass")
			var slope:float=Vector2(cross.x,cross.z).length()/-cross.y
			maximum_slope=maxf(maximum_slope,slope)
			if slope>slope_cap:return _fail("Actual native local surface exceeds its fixed class grade cap")
		elif cross.dot(normals[indices[start]]+normals[indices[start+1]]+normals[indices[start+2]])>=-.000000000001:
			return _fail("Visible source tread/riser winding disagrees with its normals")
	return {"ok":true,"positions":positions,"normals":normals,"indices":indices,"uvs":uvs,"maximum_slope":maximum_slope}

func _array_mesh(row: Dictionary) -> ArrayMesh:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=row.positions;arrays[Mesh.ARRAY_NORMAL]=row.normals;arrays[Mesh.ARRAY_INDEX]=row.indices;arrays[Mesh.ARRAY_TEX_UV]=row.uvs
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

## Root must commit EVERY returned part before declaring a complete cell.
## Empty cells and partial compiled coverage remain the world's responsibility.
func physical_parts_for_cell(tx: int,tz: int) -> Array[String]:
	var cell:="%d_%d"%[tx,tz];var result:Array[String]=[]
	for key:String in _physical:
		var descriptor:Dictionary=_physical[key]
		if String(descriptor.get("spatial_tile_key",key))==cell:result.append(key)
	result.sort();return result

## Main-thread commit under the current frame. Native bodies and visual batches
## translate their own exact source anchors; only identical anchors may batch.
func build_physical(plan: Variant,parent: Node3D,material: Material=null,options: Dictionary={}) -> Dictionary:
	for key in options:
		if key not in ["collision_mode","faces_per_body"]:return _fail("Unknown road collision option")
	var mode:Variant=options.get("collision_mode","per_feature");var face_limit:Variant=options.get("faces_per_body",32768)
	if not mode is String or mode not in ["per_feature","static_batches"] or not face_limit is int or face_limit<8 or face_limit>65536:return _fail("Invalid bounded road collision options")
	var checked:Dictionary=_validate_plan(plan,"physical")
	if not checked.ok:return checked
	if not is_instance_valid(parent) or not parent.is_inside_tree() or not parent.global_transform.is_equal_approx(Transform3D.IDENTITY) or not _physical.has(plan.key):return _fail("Require identity native parent and bound physical part")
	var data:Dictionary=plan.data
	if data.get("schema")!=SCHEMA or data.get("tile")!=plan.key or not data.get("features") is Array:return _fail("Invalid physical source part")
	var descriptor:Dictionary=_physical[plan.key]
	if descriptor.has("spatial_tile_key") and data.get("spatial_tile_key")!=descriptor.spatial_tile_key:return _fail("Physical part/cell identity disagrees")
	var prepared:Array[Dictionary]=[];var vertices:=0;var faces:=0;var collision_face_count:=0;var visible_face_count:=0;var maximum_slope:=0.0;var slopes:Dictionary={};var groups:Dictionary={}
	for feature:Variant in data.features:
		if not feature is Dictionary or not feature.get("id") is String or not _point(feature.get("anchor_source_xyz")):return _fail("Invalid source feature identity/anchor")
		var surface:Dictionary=_surface_spec(feature)
		if not surface.ok:return surface
		var anchor:Array=feature.anchor_source_xyz
		var projected:Dictionary=_frame.to_local(anchor)
		if not projected.ok:return _fail("Source feature anchor exceeds active frame")
		var collision:Dictionary=_mesh_arrays(feature.get("mesh"),anchor,true,float(surface.cap))
		if not collision.ok:return collision
		var visible:Dictionary=collision
		if surface.separate_visual:
			visible=_mesh_arrays(feature.get("visual_mesh"),anchor,false,0.0)
			if not visible.ok:return visible
		vertices+=collision.positions.size()+(visible.positions.size() if surface.separate_visual else 0)
		faces+=collision.indices.size()/3+(visible.indices.size()/3 if surface.separate_visual else 0)
		collision_face_count+=collision.indices.size()/3;visible_face_count+=visible.indices.size()/3
		if vertices>MAX_VERTICES or faces>MAX_COLLISION_FACES:return _fail("Combined visible/collision native work budget exceeded")
		maximum_slope=maxf(maximum_slope,collision.maximum_slope)
		slopes[surface.surface_class]=maxf(float(slopes.get(surface.surface_class,0.0)),collision.maximum_slope)
		var anchor_key:String=JSON.stringify(anchor,"",true,true)
		var row:Dictionary={"id":feature.id,"name":feature.get("name"),"surface_class":surface.surface_class,"collision":collision,"visible":visible,"anchor_source_xyz":anchor.duplicate(),"anchor_local":projected.position}
		prepared.append(row)
		if not groups.has(anchor_key):groups[anchor_key]=[]
		groups[anchor_key].append(row)
	var root:=Node3D.new();root.name=("SourceRoads_"+String(plan.key)).validate_node_name()
	if material==null:
		var fallback:=StandardMaterial3D.new();fallback.albedo_color=Color(.17,.18,.18);fallback.roughness=.95;material=fallback
	var new_batches:Array[Dictionary]=[];var native_body_count:=0
	for anchor_key:String in groups:
		var rows:Array=groups[anchor_key];var anchor_local:Vector3=rows[0].anchor_local;var anchor_source:Array=rows[0].anchor_source_xyz
		var pending_faces:=PackedVector3Array();var ranges:Array[Dictionary]=[]
		var visual_arrays:Dictionary={"positions":PackedVector3Array(),"normals":PackedVector3Array(),"indices":PackedInt32Array(),"uvs":PackedVector2Array()};var names:Dictionary={}
		for row:Dictionary in rows:
			var mesh:ArrayMesh=_array_mesh(row.collision)
			if mode=="per_feature":
				var body:=StaticBody3D.new();body.name=(String(row.id)+"_SameTopologyCollision").validate_node_name();body.collision_layer=1;body.position=anchor_local
				var shape:=CollisionShape3D.new();shape.shape=mesh.create_trimesh_shape();body.add_child(shape)
				body.set_meta("source_way",row.id);body.set_meta("source_anchor_xyz",anchor_source.duplicate());body.set_meta("source_surface_class",row.surface_class);root.add_child(body);native_body_count+=1
			else:
				var expanded:PackedVector3Array=mesh.get_faces();var source_face:=0
				while source_face<expanded.size()/3:
					var first_face:int=pending_faces.size()/3;var take:int=mini(face_limit-first_face,expanded.size()/3-source_face)
					ranges.append({"first_face":first_face,"face_count":take,"source_first_face":source_face,"source_way":row.id,"name":row.name,"surface_class":row.surface_class})
					for index in range(source_face*3,(source_face+take)*3):pending_faces.append(expanded[index])
					source_face+=take
					if pending_faces.size()/3==face_limit:
						new_batches.append(_create_collision_batch(root,plan.key,new_batches.size(),pending_faces,ranges,anchor_local,anchor_source))
						pending_faces=PackedVector3Array();ranges=[];native_body_count+=1
			var visual:Dictionary=row.visible;var offset:int=visual_arrays.positions.size()
			visual_arrays.positions.append_array(visual.positions);visual_arrays.normals.append_array(visual.normals);visual_arrays.uvs.append_array(visual.uvs)
			for index in visual.indices:visual_arrays.indices.append(int(index)+offset)
			names[row.id]=row.name
		if not pending_faces.is_empty():
			new_batches.append(_create_collision_batch(root,plan.key,new_batches.size(),pending_faces,ranges,anchor_local,anchor_source));native_body_count+=1
		if not visual_arrays.positions.is_empty():
			var visual:=MeshInstance3D.new();visual.name="SourceMaterialAnchorBatch";visual.position=anchor_local;visual.mesh=_array_mesh(visual_arrays);visual.material_override=material
			visual.set_meta("actual_source_way_names",names);visual.set_meta("source_anchor_xyz",anchor_source.duplicate());root.add_child(visual)
	root.set_meta("source_roads_binding",{"artifact_identity_sha256":_identity_sha,"snapshot_manifest_sha256":_snapshot,"origin_revision":_frame.metadata().origin_revision,"collision_representation":"anchored_local_v2"})
	parent.add_child(root)
	for id in _collision_batches.keys():
		if not is_instance_valid(_collision_batches[id].body.get_ref()):_collision_batches.erase(id)
	for batch:Dictionary in new_batches:
		batch.root=weakref(root);batch.origin_revision=_frame.metadata().origin_revision;_collision_batches[batch.body.get_ref().get_instance_id()]=batch
	return {"ok":true,"node":root,"features":prepared.size(),"vertices":vertices,"collision_faces":collision_face_count,"visible_faces":visible_face_count,"input_face_work":faces,"collision_mode":mode,"collision_body_count":native_body_count,"anchor_groups":groups.size(),"maximum_native_surface_slope":maximum_slope,"maximum_native_slope_by_class":slopes,"origin_revision":_frame.metadata().origin_revision,"actual_support_and_drivability_unverified":true}


## Exact triangle order and per-range original way metadata. Only the collision
## representation changes; render vertices, normals, UVs and indices do not.
func _create_collision_batch(holder: Node3D, tile: String, index: int, faces: PackedVector3Array, ranges: Array[Dictionary], anchor_local: Vector3, anchor_source: Array) -> Dictionary:
	var body:=StaticBody3D.new();body.name="RoadCollisionBatch_%d"%index
	body.collision_layer=1;body.collision_mask=1;body.position=anchor_local
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
	var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	body.set_meta("source_road_batch",{"tile_key":tile,"batch_index":index,"face_count":faces.size()/3,"anchor_source_xyz":anchor_source.duplicate()})
	holder.add_child(body)
	var descriptor:Dictionary={"body":weakref(body),"collision":weakref(collision),"shape_id":shape.get_instance_id(),"tile_key":tile,"batch_index":index,"face_count":faces.size()/3,"ranges":ranges.duplicate(true),"anchor_source_xyz":anchor_source.duplicate(),"source_mapping_valid":true}
	shape.changed.connect(func():descriptor.source_mapping_valid=false)
	return descriptor

## Resolve a fresh native ray without pretending an aggregate body is one way.
## Missing/ambiguous native face data, replacement shapes and stale origins fail.
func resolve_source_hit(hit: Dictionary) -> Dictionary:
	var body:Variant=hit.get("collider")
	if not is_instance_valid(body) or not body is StaticBody3D or not _collision_batches.has(body.get_instance_id()):return _fail("Foreign or retired road collision body")
	var batch:Dictionary=_collision_batches[body.get_instance_id()]
	if not batch.source_mapping_valid:return _fail("Road collision resource mutated in place")
	var holder:Variant=batch.root.get_ref();var collision:Variant=batch.collision.get_ref()
	if not is_instance_valid(holder) or not holder.is_inside_tree() or not is_instance_valid(collision) or not body.is_inside_tree() or body.get_parent()!=holder or collision.get_parent()!=body or collision.disabled or body.collision_layer==0:return _fail("Road collision ownership is no longer live")
	if batch.origin_revision!=_frame.metadata().origin_revision:return _fail("Stale road source origin")
	if body.get_world_3d()!=holder.get_world_3d() or PhysicsServer3D.body_get_space(body.get_rid())!=holder.get_world_3d().space:return _fail("Road body belongs to another native space")
	if not collision.shape is ConcavePolygonShape3D or collision.shape.get_instance_id()!=batch.shape_id:return _fail("Road collision resource replaced")
	if hit.has("rid") and (not hit.rid is RID or hit.rid!=body.get_rid()):return _fail("Road hit RID mismatch")
	var shape_index:Variant=hit.get("shape")
	if not shape_index is int or shape_index<0 or shape_index>=PhysicsServer3D.body_get_shape_count(body.get_rid()) or body.shape_owner_get_owner(body.shape_find_owner(shape_index))!=collision:return _fail("Road hit shape is not owned geometry")
	var face:Variant=hit.get("face_index",-1)
	if not face is int or face<0 or face>=batch.face_count:return _fail("Native road face is missing or out of range")
	var low:=0;var high:int=batch.ranges.size()-1
	while low<=high:
		var middle:int=(low+high)/2;var row:Dictionary=batch.ranges[middle]
		if face<row.first_face:high=middle-1
		elif face>=row.first_face+row.face_count:low=middle+1
		else:return {"ok":true,"source_way":row.source_way,"name":row.name,"tile_key":batch.tile_key,"artifact_identity_sha256":_identity_sha,"origin_revision":batch.origin_revision,"native_face_index":face,"anchor_source_xyz":batch.anchor_source_xyz.duplicate(),"surface_class":row.get("surface_class","car_ribbon"),"source_face_index":row.source_first_face+face-row.first_face}
	return _fail("Native road face has no original source range")

func metadata() -> Dictionary:
	return {"configured": _configured, "artifact_identity_sha256": _identity_sha, "snapshot_manifest_sha256": _snapshot,
		"graph_owners": _graphs.keys(), "physical_tiles": _physical.keys(), "loaded_graph_owners": _loaded.keys(),
		"physical_scope": _manifest.get("physical_scope", {}).duplicate(true), "traffic_budget_owned_by_caller": "GLOBAL48ambient/7physics", "actor_or_bootstrap_mutated": false}
