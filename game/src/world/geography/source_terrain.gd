class_name SingaporeSourceTerrain
extends RefCounted
## Coarse source DEM samples in EGM96, not live ground/collision or a sea plane.
## Source XZ arithmetic stays double. No default map or source-datum alignment.
const MANIFEST_SCHEMA := "singapore_skadi_terrain_manifest_v1"
const IDENTITY_SCHEMA := "singapore_skadi_terrain_identity_v1"
const VERTICAL := "EGM96 geoid metres"
const MAX_MANIFEST_BYTES := 4 * 1024 * 1024
const CHUNK_BYTES := 7396
const STORED := 43
const MAX_CHUNKS := 5000
const MAX_COORDINATE := 10000000.0
var last_error := ""
var _configured := false
var _base := ""
var _identity_sha := ""
var _manifest_sha := ""
var _manifest: Dictionary = {}
var _inventory: Dictionary = {}
var _cache: Dictionary = {}
var _lru: Array[String] = []
var _capacity := 8
var _sha_re := RegEx.new()
var _stats := {"file_reads":0,"tile_loads":0,"cache_hits":0,"evictions":0,"queries":0,"max_cached_chunks":0}

func _init() -> void:
	_sha_re.compile("^[0-9a-f]{64}$")

func _hash(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and _sha_re.search(value) != null
func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))
func _integer(value: Variant,lower: int,upper: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= lower and float(value) <= upper
func _text(value: Variant,expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected
func _fail(message: String) -> bool:
	last_error = message
	return false
func _digest(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()
func _read(path: String,maximum: int) -> PackedByteArray:
	var f := FileAccess.open(path,FileAccess.READ)
	if f == null or f.get_length() <= 0 or f.get_length() > maximum:
		_fail("Terrain source missing or outside bounded byte contract")
		return PackedByteArray()
	_stats.file_reads += 1
	return f.get_buffer(f.get_length())
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

func configure(directory: String,expected_identity_sha256: String,expected_snapshot_manifest_sha256: String,cache_capacity: int = 8) -> bool:
	if _configured: return _fail("Terrain identity is immutable; create a new provider")
	if not _hash(expected_identity_sha256) or not _hash(expected_snapshot_manifest_sha256) or cache_capacity < 1 or cache_capacity > 64: return _fail("Explicit trusted identity/snapshot and1..64 cache capacity required")
	var base: String = directory.trim_suffix("/")
	var folder := DirAccess.open(base)
	if base != base.simplify_path() or folder == null or folder.is_link("identity.json") or folder.is_link("manifest.json"): return _fail("Unsafe/unavailable terrain directory or symlink source")
	var iraw: PackedByteArray = _read(base.path_join("identity.json"),65536)
	if iraw.is_empty() or _digest(iraw) != expected_identity_sha256: return _fail("Terrain identity checksum mismatch")
	var identity: Variant = JSON.parse_string(iraw.get_string_from_utf8())
	if not identity is Dictionary or not _text(identity.get("schema"),IDENTITY_SCHEMA) or not _integer(identity.get("version"),1,1) or not identity.get("manifest") is Dictionary or not _integer(identity.get("chunk_count"),1,MAX_CHUNKS): return _fail("Invalid terrain identity/version")
	if not _text(identity.manifest.get("file"),"manifest.json") or not _hash(identity.manifest.get("sha256")) or not _integer(identity.manifest.get("bytes"),1,MAX_MANIFEST_BYTES) or not _text(identity.get("vertical_reference"),VERTICAL): return _fail("Unsafe terrain manifest descriptor")
	if not _text(identity.get("snapshot_manifest_sha256"),expected_snapshot_manifest_sha256): return _fail("Terrain snapshot differs from intended frame/context")
	var raw: PackedByteArray = _read(base.path_join("manifest.json"),MAX_MANIFEST_BYTES)
	if raw.size() != int(identity.manifest.bytes) or _digest(raw) != identity.manifest.sha256: return _fail("Terrain manifest checksum/size mismatch")
	var m: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not m is Dictionary or not _text(m.get("schema"),MANIFEST_SCHEMA) or not _integer(m.get("version"),1,1) or not _text(m.get("vertical_reference"),VERTICAL) or not m.get("bindings") is Dictionary or not m.get("grid") is Dictionary or not m.get("chunks") is Array: return _fail("Invalid terrain manifest/schema")
	if not _text(m.bindings.get("snapshot_manifest_sha256"),expected_snapshot_manifest_sha256) or not _hash(m.bindings.get("country_wgs84_sha256")) or not _hash(m.bindings.get("pbf_sha256")) or not _hash(m.bindings.get("projection_implementation_sha256")) or not _frame_valid(m.bindings.get("georeference")): return _fail("Terrain source/frame binding mismatch")
	for row: Array in [["spacing_metres",25],["chunk_metres",1000],["cells_per_chunk",40],["core_samples",41],["halo_samples",1],["stored_samples",43],["native_posting_arcseconds",1]]:
		if not _integer(m.grid.get(row[0]),row[1],row[1]): return _fail("Unsupported terrain grid/resolution")
	if not _text(m.grid.get("encoding"),"float32_little_endian_row_z_ascending_column_x_ascending") or not _text(m.grid.get("void_encoding"),"canonical float32 NaN") or typeof(m.grid.get("derived_spacing_is_new_measurement_resolution")) != TYPE_BOOL or m.grid.derived_spacing_is_new_measurement_resolution: return _fail("Unsupported terrain encoding/resolution authority")
	if m.chunks.size() != int(identity.chunk_count): return _fail("Terrain inventory count mismatch")
	var inventory: Dictionary = {}
	for item in m.chunks:
		if not item is Dictionary or not item.get("chunk_xz") is Array or item.chunk_xz.size() != 2: return _fail("Invalid terrain chunk identity")
		if not _integer(item.chunk_xz[0],-10000,10000) or not _integer(item.chunk_xz[1],-10000,10000): return _fail("Unbounded terrain chunk index")
		var key: String = "%d_%d" % [int(item.chunk_xz[0]),int(item.chunk_xz[1])]
		if inventory.has(key) or not _text(item.get("file"),key+".f32") or not _hash(item.get("sha256")) or not _integer(item.get("bytes"),CHUNK_BYTES,CHUNK_BYTES): return _fail("Unsafe/duplicate terrain chunk descriptor")
		inventory[key] = item.duplicate(true)
	_base = base
	_identity_sha = expected_identity_sha256
	_manifest_sha = identity.manifest.sha256
	_manifest = m
	_inventory = inventory
	_capacity = cache_capacity
	_configured = true
	last_error = ""
	return true

func metadata() -> Dictionary:
	return {"configured":_configured,"identity_sha256":_identity_sha,"manifest_sha256":_manifest_sha,
		"bindings":_manifest.get("bindings",{}).duplicate(true),"grid":_manifest.get("grid",{}).duplicate(true),
		"vertical_reference":VERTICAL,"chunk_count":_inventory.size(),"stats":_stats.duplicate(true),
		"sources":_manifest.get("sources",[]).duplicate(true),"attribution":_manifest.get("attribution",{}).duplicate(true),"limitations":_manifest.get("limitations",[]).duplicate(true),
		"world_y_alignment_verified":false,"current_survey_ground_verified":false,"physical_support_verified":false}

func _load(key: String) -> Dictionary:
	if _cache.has(key):
		_stats.cache_hits += 1
		_lru.erase(key)
		_lru.append(key)
		return _cache[key]
	if not _inventory.has(key): return {}
	var item: Dictionary = _inventory[key]
	var folder := DirAccess.open(_base)
	if folder == null or folder.is_link(item.file):
		_fail("Terrain chunk symlink/directory failure")
		return {}
	var raw: PackedByteArray = _read(_base.path_join(item.file),CHUNK_BYTES)
	if raw.size() != CHUNK_BYTES or _digest(raw) != item.sha256:
		_fail("Terrain chunk checksum/size mismatch")
		return {}
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false
	stream.data_array = raw
	var values := PackedFloat32Array()
	values.resize(STORED*STORED)
	for index in STORED*STORED:
		var value: float = stream.get_float()
		if is_inf(value) or (is_finite(value) and absf(value) > 32767.0):
			_fail("Terrain chunk contains invalid elevation encoding")
			return {}
		values[index] = value
	var entry := {"values":values,"sha256":item.sha256,"chunk_xz":item.chunk_xz.duplicate()}
	_cache[key] = entry
	_lru.append(key)
	while _cache.size() > _capacity:
		_cache.erase(_lru.pop_front())
		_stats.evictions += 1
	_stats.tile_loads += 1
	_stats.max_cached_chunks = maxi(int(_stats.max_cached_chunks),_cache.size())
	return entry

func _height(values: PackedFloat32Array,x: float,z: float,tx: int,tz: int) -> Dictionary:
	var gx: float = x/25.0-float(tx*40-1)
	var gz: float = z/25.0-float(tz*40-1)
	if gx < 0.0 or gx > 42.0 or gz < 0.0 or gz > 42.0: return {"known":false}
	var ix: int = mini(int(floor(gx)),41)
	var iz: int = mini(int(floor(gz)),41)
	var u: float = gx-float(ix)
	var v: float = gz-float(iz)
	var sum := 0.0
	for corner: Array in [[0,0,(1.0-u)*(1.0-v)],[1,0,u*(1.0-v)],[0,1,(1.0-u)*v],[1,1,u*v]]:
		var weight: float = corner[2]
		if weight == 0.0: continue
		var value: float = values[(iz+int(corner[1]))*STORED+ix+int(corner[0])]
		if not is_finite(value): return {"known":false}
		sum += value*weight
	return {"known":true,"height":sum}

func sample(source_xyz: Variant) -> Dictionary:
	var result := {"ok":false,"state":"unknown","height_m_egm96":null,"normal_state":"unknown","normal_source_xyz":null,
		"vertical_reference":VERTICAL,"reason":"","provenance":{"world_y_alignment_verified":false,"surveyed_ground":false,"physical_support":false,"hydrology":false,"new25mmeasurement_resolution":false}}
	if not _configured:
		result.reason = "Terrain provider not configured"
		return result
	if not typeof(source_xyz) in [TYPE_ARRAY,TYPE_PACKED_FLOAT64_ARRAY] or source_xyz.size() != 3:
		result.reason = "Canonical source position requires three double-array components"
		return result
	for value in source_xyz:
		if not _number(value) or absf(float(value)) > MAX_COORDINATE:
			result.reason = "Nonfinite/unbounded canonical source coordinate"
			return result
	last_error = ""
	_stats.queries += 1
	var x: float = source_xyz[0]
	var z: float = source_xyz[2]
	var tx: int = int(floor(x/1000.0))
	var tz: int = int(floor(z/1000.0))
	var key: String = "%d_%d" % [tx,tz]
	if not _inventory.has(key):
		result.ok = true
		result.reason = "No compiled DEM chunk; not outside-city or zero ground"
		return result
	var tile: Dictionary = _load(key)
	if tile.is_empty():
		result.reason = last_error
		return result
	var values: PackedFloat32Array = tile.values
	var height: Dictionary = _height(values,x,z,tx,tz)
	result.ok = true
	result.provenance.merge({"identity_sha256":_identity_sha,"manifest_sha256":_manifest_sha,
		"snapshot_manifest_sha256":_manifest.bindings.snapshot_manifest_sha256,"chunk":key,"chunk_sha256":tile.sha256,
		"grid_spacing_m":25.0,"native_posting_arcseconds":1,"coverage":"compiled1kmDEM reference patch; territory/coast/inlandwater remain separate"})
	if not height.known:
		result.reason = "Source void or incomplete interpolation stencil"
		return result
	result.state = "sampled_dem"
	result.height_m_egm96 = height.height
	var xp: Dictionary = _height(values,x+25.0,z,tx,tz)
	var xm: Dictionary = _height(values,x-25.0,z,tx,tz)
	var zp: Dictionary = _height(values,x,z+25.0,tx,tz)
	var zm: Dictionary = _height(values,x,z-25.0,tx,tz)
	if xp.known and xm.known and zp.known and zm.known:
		var dx: float = (xp.height-xm.height)/50.0
		var dz: float = (zp.height-zm.height)/50.0
		var length: float = sqrt(dx*dx+1.0+dz*dz)
		result.normal_state = "derived_dem"
		result.normal_source_xyz = [-dx/length,1.0/length,-dz/length]
	result.reason = "Coarse/interpolated EGM96 DEM; not current surveyed ground or an architectural floor"
	return result

func observe(source_xyz: Variant) -> Dictionary:
	return sample(source_xyz)

func chunk_grid(tx: int,tz: int) -> Dictionary:
	if not _configured: return {"ok":false,"state":"unknown"}
	var key: String = "%d_%d" % [tx,tz]
	var entry: Dictionary = _load(key)
	if entry.is_empty(): return {"ok":false,"state":"unknown","reason":"Missing/invalid source chunk"}
	return {"ok":true,"state":"source_dem_grid","chunk_xz":[tx,tz],"core_global_index_min_xz":[tx*40,tz*40],
		"stored_global_index_min_xz":[tx*40-1,tz*40-1],"stored_samples":43,"spacing_m":25.0,
		"heights_egm96_m":entry.values.duplicate(),"void":"NaN","chunk_sha256":entry.sha256,"vertical_reference":VERTICAL}
