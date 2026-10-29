class_name SingaporeRuntimeCityTiles
extends RefCounted
## Immutable mesh-data provider. Root owns ArrayMesh/material/physics/World
## commit and rebases; canonical anchor is never made an absolute Vector3 here.
const SCHEMA := "singapore_source_city_geometry_v1"
const IDENTITY := "singapore_source_city_identity_v1"
const YMODE := "EGM96_DEM_game_world_reference_not_current_survey"
const MAX_META := 32 * 1024 * 1024
const MAX_BLOB := 64 * 1024 * 1024
var last_error := ""
var _configured := false
var _base := ""
var _identity_sha := ""
var _manifest_sha := ""
var _manifest: Dictionary = {}
var _meshes: Dictionary = {}
var _catalogs: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _catalog_cache: Dictionary = {}
var _mesh_lru: Array[String] = []
var _catalog_lru: Array[String] = []
var _capacity := 2
var _sha_re := RegEx.new()
var _key_re := RegEx.new()
var _stats := {"file_reads":0,"mesh_loads":0,"catalog_loads":0,"cache_hits":0,"evictions":0,"max_cached_mesh_tiles":0}
func _init() -> void:
	_sha_re.compile("^[0-9a-f]{64}$")
	_key_re.compile("^-?[0-9]+_-?[0-9]+$")
func _hash(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and _sha_re.search(value) != null
func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))
func _integer(value: Variant,lower: int,upper: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= lower and float(value) <= upper
func _text(value: Variant,expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected
func _key(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.length() < 64 and _key_re.search(value) != null
func _point(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for n in value:
		if not _number(n) or absf(float(n)) > 10000000.0: return false
	return true
func _frame_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: String in ["origin_easting","origin_northing","metres_per_unit"]:
		if not _number(value.get(key)): return false
	if float(value.origin_easting) != 30000.0 or float(value.origin_northing) != 30000.0 or float(value.metres_per_unit) != 1.0: return false
	if not _text(value.get("source_crs"),"EPSG:4326") or not _text(value.get("survey_crs"),"EPSG:3414"): return false
	for key: String in ["distance_compression","legacy_plan_alignment_applied"]:
		if typeof(value.get(key)) != TYPE_BOOL or value[key]: return false
	if not value.get("world_axes") is Dictionary: return false
	return _text(value.world_axes.get("x"),"south") and _text(value.world_axes.get("y"),"up") and _text(value.world_axes.get("z"),"west")
func _fail(message: String) -> bool:
	last_error = message
	return false
func _digest(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()
func _read(relative: String,maximum: int,expected: String,expected_bytes: int) -> PackedByteArray:
	if not _hash(expected) or relative != relative.simplify_path() or relative.begins_with("/") or ".." in relative: _fail("Unsafe city artifact descriptor"); return PackedByteArray()
	var parent := DirAccess.open(_base.path_join(relative.get_base_dir()))
	if parent == null or parent.is_link(relative.get_file()): _fail("Missing/symlink city artifact"); return PackedByteArray()
	var f := FileAccess.open(_base.path_join(relative),FileAccess.READ)
	if f == null or f.get_length() != expected_bytes or f.get_length() <= 0 or f.get_length() > maximum: _fail("City artifact byte bound mismatch"); return PackedByteArray()
	var raw: PackedByteArray = f.get_buffer(f.get_length())
	_stats.file_reads += 1
	if _digest(raw) != expected: _fail("City artifact checksum mismatch"); return PackedByteArray()
	return raw

func configure(directory: String,identity_sha256: String,snapshot_sha256: String,dem_identity_sha256: String,world_y_policy: Dictionary,cache_capacity: int = 2) -> bool:
	if _configured: return _fail("City geometry identity is immutable")
	if not _hash(identity_sha256) or not _hash(snapshot_sha256) or not _hash(dem_identity_sha256) or cache_capacity < 1 or cache_capacity > 8: return _fail("Explicit city/source/DEM identities and bounded cache required")
	if not _text(world_y_policy.get("mode"),YMODE) or not _number(world_y_policy.get("offset_m")): return _fail("Explicit game EGM96 world-Y policy required")
	var base: String = directory.trim_suffix("/")
	var folder := DirAccess.open(base)
	if folder == null or base != base.simplify_path() or folder.is_link("identity.json") or folder.is_link("meshes") or folder.is_link("catalogs"): return _fail("Unsafe/unavailable city dataset")
	var file := FileAccess.open(base.path_join("identity.json"),FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > 65536: return _fail("City identity unavailable/bounded")
	var iraw: PackedByteArray = file.get_buffer(file.get_length())
	if _digest(iraw) != identity_sha256: return _fail("City identity checksum mismatch")
	var identity: Variant = JSON.parse_string(iraw.get_string_from_utf8())
	if not identity is Dictionary or not _text(identity.get("schema"),IDENTITY) or not _integer(identity.get("version"),1,1) or not identity.get("manifest") is Dictionary or not _text(identity.get("snapshot_sha256"),snapshot_sha256) or not _text(identity.get("dem_identity_sha256"),dem_identity_sha256): return _fail("City identity/schema/source mismatch")
	if not _text(identity.manifest.get("file"),"manifest.json") or not _integer(identity.manifest.get("bytes"),1,MAX_META) or not _hash(identity.manifest.get("sha256")): return _fail("Invalid city manifest descriptor")
	_base = base
	var raw: PackedByteArray = _read("manifest.json",MAX_META,identity.manifest.sha256,int(identity.manifest.bytes))
	if raw.is_empty(): return false
	var m: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not m is Dictionary or not _text(m.get("schema"),SCHEMA) or not _integer(m.get("version"),1,1) or not m.get("bindings") is Dictionary or not m.get("world_y_policy") is Dictionary or not m.get("meshes") is Array or not m.get("catalogs") is Array or not _frame_valid(m.get("georeference")) or not m.get("mesh_format") is Dictionary: return _fail("Invalid city manifest schema")
	if not _text(m.bindings.get("snapshot_sha"),snapshot_sha256) or not _text(m.bindings.get("dem_identity"),dem_identity_sha256) or not _text(m.world_y_policy.get("mode"),YMODE) or not _number(m.world_y_policy.get("offset_m")) or float(m.world_y_policy.offset_m) != float(world_y_policy.offset_m): return _fail("City source/DEM/Y policy differs from intended context")
	if not _integer(m.mesh_format.get("stride_bytes"),32,32) or not _integer(m.mesh_format.get("index_bytes"),4,4) or not _text(m.mesh_format.get("byte_order"),"little") or typeof(m.mesh_format.get("local_anchor_subtracted_before_float")) != TYPE_BOOL or not m.mesh_format.local_anchor_subtracted_before_float: return _fail("Unsupported city local mesh encoding")
	if m.meshes.size() > 5000 or m.catalogs.size() > 2000: return _fail("City inventory exceeds bounds")
	var meshes: Dictionary = {}
	var catalogs: Dictionary = {}
	for item in m.meshes:
		if not item is Dictionary or not _key(item.get("key")) or meshes.has(item.key) or not _text(item.get("file"),"meshes/"+item.key+".json") or not _text(item.get("binary_file"),"meshes/"+item.key+".mesh") or not _hash(item.get("sha256")) or not _hash(item.get("binary_sha256")) or not _integer(item.get("bytes"),1,MAX_META) or not _integer(item.get("binary_bytes"),1,MAX_BLOB): return _fail("Unsafe/duplicate mesh descriptor")
		meshes[item.key] = item.duplicate(true)
	for item in m.catalogs:
		if not item is Dictionary or not _key(item.get("key")) or catalogs.has(item.key) or not _text(item.get("file"),"catalogs/"+item.key+".json") or not _hash(item.get("sha256")) or not _integer(item.get("bytes"),1,MAX_META): return _fail("Unsafe/duplicate catalog descriptor")
		catalogs[item.key] = item.duplicate(true)
	_manifest = m
	_meshes = meshes
	_catalogs = catalogs
	_identity_sha = identity_sha256
	_manifest_sha = identity.manifest.sha256
	_capacity = cache_capacity
	_configured = true
	last_error = ""
	return true

func metadata() -> Dictionary:
	return {"configured":_configured,"identity_sha256":_identity_sha,"manifest_sha256":_manifest_sha,
		"bindings":_manifest.get("bindings",{}).duplicate(true),"world_y_policy":_manifest.get("world_y_policy",{}).duplicate(true),
		"counts":_manifest.get("counts",{}).duplicate(true),"exclusions":_manifest.get("exclusions",[]).duplicate(true),
		"mesh_tile_count":_meshes.size(),"catalog_page_count":_catalogs.size(),"stats":_stats.duplicate(true),"scene_or_physics_committed":false}
func mesh_keys() -> Array:
	return _meshes.keys().duplicate()
func mesh_keys_for_cell(tx: int,tz: int) -> Array:
	var key: String = "%d_%d" % [tx,tz]
	return [key] if _meshes.has(key) else []
func _touch(key: String,lru: Array[String]) -> void:
	lru.erase(key)
	lru.append(key)
func _trim(cache: Dictionary,lru: Array[String]) -> void:
	while cache.size() > _capacity:
		cache.erase(lru.pop_front())
		_stats.evictions += 1

func catalog(owner: String) -> Dictionary:
	if not _configured or not _key(owner) or not _catalogs.has(owner): return {"ok":false,"state":"unknown","reason":"No versioned source catalog"}
	if _catalog_cache.has(owner):
		_stats.cache_hits += 1
		_touch(owner,_catalog_lru)
		return {"ok":true,"catalog":_catalog_cache[owner].duplicate(true)}
	var item: Dictionary = _catalogs[owner]
	var raw: PackedByteArray = _read(item.file,MAX_META,item.sha256,int(item.bytes))
	if raw.is_empty(): return {"ok":false,"state":"unknown","reason":last_error}
	var data: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not data is Dictionary or not _text(data.get("schema"),SCHEMA) or not _text(data.get("owner"),owner) or not data.get("features") is Array: return {"ok":false,"state":"unknown","reason":"Invalid city catalog schema"}
	_catalog_cache[owner] = data
	_touch(owner,_catalog_lru)
	_trim(_catalog_cache,_catalog_lru)
	_stats.catalog_loads += 1
	return {"ok":true,"catalog":data.duplicate(true)}

func _decode_surface(raw: PackedByteArray,row: Dictionary) -> Dictionary:
	for field: String in ["vertex_count","index_count","vertex_offset_bytes","index_offset_bytes"]:
		if not _integer(row.get(field),0,MAX_BLOB): return {"ok":false,"reason":"Invalid mesh buffer count/offset"}
	var vc: int = int(row.vertex_count)
	var ic: int = int(row.index_count)
	var vo: int = int(row.vertex_offset_bytes)
	var io: int = int(row.index_offset_bytes)
	if vc < 3 or vc > 1000000 or ic < 3 or ic > 6000000 or ic%3 != 0 or vo+vc*32 > raw.size() or io+ic*4 > raw.size() or io != vo+vc*32: return {"ok":false,"reason":"Mesh buffer outside bounded source range"}
	if not _hash(row.get("topology_sha256")) or _digest(raw.slice(vo,io+ic*4)) != row.topology_sha256: return {"ok":false,"reason":"Surface collision topology hash mismatch"}
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.data_array = raw
	stream.seek(vo)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	positions.resize(vc);normals.resize(vc);uvs.resize(vc)
	for index in vc:
		var x: float = stream.get_float();var y: float = stream.get_float();var z: float = stream.get_float()
		var nx: float = stream.get_float();var ny: float = stream.get_float();var nz: float = stream.get_float()
		var u: float = stream.get_float();var v: float = stream.get_float()
		for n in [x,y,z,nx,ny,nz,u,v]:
			if not is_finite(n): return {"ok":false,"reason":"Nonfinite local mesh data"}
		if x < -.01 or x > 1000.01 or z < -.01 or z > 1000.01 or absf(y) > 20000.0 or absf(nx*nx+ny*ny+nz*nz-1.0) > .001: return {"ok":false,"reason":"Local mesh coordinate/normal contract mismatch"}
		positions[index] = Vector3(x,y,z) # Data were anchor-subtracted offline.
		normals[index] = Vector3(nx,ny,nz)
		uvs[index] = Vector2(u,v)
	var indices := PackedInt32Array()
	indices.resize(ic)
	stream.seek(io)
	for index in ic:
		var vertex: int = stream.get_u32()
		if vertex < 0 or vertex >= vc: return {"ok":false,"reason":"Mesh triangle references missing vertex"}
		indices[index] = vertex
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"ok":true,"role":row.get("role","unresolved"),"arrays":arrays,"topology_sha256":row.topology_sha256,"collision_topology":"same arrays vertex/index only; no scene/physics authority"}

func tile(tx: int,tz: int) -> Dictionary:
	var key: String = "%d_%d" % [tx,tz]
	if not _configured or not _meshes.has(key): return {"ok":false,"state":"unknown","reason":"No compiled mesh tile; not empty traversable land"}
	if _mesh_cache.has(key):
		_stats.cache_hits += 1
		_touch(key,_mesh_lru)
		return _mesh_cache[key].duplicate(true)
	var item: Dictionary = _meshes[key]
	var raw: PackedByteArray = _read(item.file,MAX_META,item.sha256,int(item.bytes))
	if raw.is_empty(): return {"ok":false,"state":"unknown","reason":last_error}
	var meta: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not meta is Dictionary or not _text(meta.get("schema"),SCHEMA) or not _point(meta.get("anchor_source_xyz")) or not meta.get("features") is Array or not meta.get("binary") is Dictionary or meta.features.size() > 20000: return {"ok":false,"state":"unknown","reason":"Invalid spatial mesh metadata"}
	if meta.anchor_source_xyz != [float(tx)*1000.0,0.0,float(tz)*1000.0] or not _text(meta.binary.get("file"),key+".mesh") or not _text(meta.binary.get("sha256"),item.binary_sha256) or not _integer(meta.binary.get("bytes"),int(item.binary_bytes),int(item.binary_bytes)): return {"ok":false,"state":"unknown","reason":"Mesh anchor/binary identity mismatch"}
	var bytes: PackedByteArray = _read(item.binary_file,MAX_BLOB,item.binary_sha256,int(item.binary_bytes))
	if bytes.is_empty(): return {"ok":false,"state":"unknown","reason":last_error}
	var features: Array = []
	var seen: Dictionary = {}
	var expected_offset := 0
	for feature in meta.features:
		if not feature is Dictionary or typeof(feature.get("feature_key")) != TYPE_STRING or seen.has(feature.feature_key) or not _key(feature.get("catalog_owner")) or not _catalogs.has(feature.catalog_owner) or not feature.get("surfaces") is Array or feature.surfaces.size() > 2048: return {"ok":false,"state":"unknown","reason":"Invalid logical mesh feature/catalog owner"}
		seen[feature.feature_key] = true
		var surfaces: Array = []
		for row in feature.surfaces:
			if not row is Dictionary or not _integer(row.get("vertex_offset_bytes"),expected_offset,expected_offset): return {"ok":false,"state":"unknown","reason":"Overlapping or missing mesh buffer ranges"}
			var decoded: Dictionary = _decode_surface(bytes,row)
			if not decoded.ok: return {"ok":false,"state":"unknown","reason":decoded.reason}
			surfaces.append(decoded)
			expected_offset = int(row.index_offset_bytes)+int(row.index_count)*4
		features.append({"feature_key":feature.feature_key,"fragment_key":feature.feature_key+"@"+key,"catalog_owner":feature.catalog_owner,
			"logical_feature_source_sha256":feature.get("logical_feature_source_sha256"),"surfaces":surfaces,"physical_support_verified":false})
	if expected_offset != bytes.size(): return {"ok":false,"state":"unknown","reason":"Unaccounted mesh binary tail"}
	var result := {"ok":true,"schema":SCHEMA,"tile_key":key,"anchor_source_xyz":meta.anchor_source_xyz.duplicate(),
		"features":features,"terrain_reference":meta.get("terrain_reference",{}).duplicate(true),"scene_or_physics_committed":false,
		"identity_sha256":_identity_sha,"metadata_sha256":item.sha256,"binary_sha256":item.binary_sha256}
	_mesh_cache[key] = result
	_touch(key,_mesh_lru)
	_trim(_mesh_cache,_mesh_lru)
	_stats.mesh_loads += 1
	_stats.max_cached_mesh_tiles = maxi(int(_stats.max_cached_mesh_tiles),_mesh_cache.size())
	last_error = ""
	return result.duplicate(true)
