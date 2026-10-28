class_name SingaporeMapData
extends RefCounted
## Read-only raw source-data queries. Does not build/migrate the playable city.
## Returned dictionaries must not be mutated. Unknown source heights stay null.
## Dependency cells cover country/feature intersections, not centroid proximity.
const SCHEMA := "singapore_country_dependency_index_v1"
const IDENTITY_SCHEMA := "singapore_country_dependency_identity_v1"
const MAX_TILE_BYTES := 32 * 1024 * 1024
const MAX_METADATA_BYTES := 16 * 1024 * 1024
const MAX_QUERY_CELLS := 64
var last_error := ""
var stats: Dictionary = {}
var _base := ""
var _manifest: Dictionary = {}
var _index: Dictionary = {}
var _inventory: Dictionary = {}
var _cache: Dictionary = {}
var _lru: Array[String] = []
var _capacity := 12
var _key_re := RegEx.new()
var _hash_re := RegEx.new()

func _init() -> void:
	_key_re.compile("^-?[0-9]+_-?[0-9]+$")
	_hash_re.compile("^[0-9a-f]{64}$")
	_reset()

func _reset() -> void:
	last_error = ""
	_base = ""
	_manifest = {}
	_index = {}
	_inventory = {}
	_cache.clear()
	_lru.clear()
	stats = {"queries": 0, "failed_queries": 0, "cache_hits": 0, "cache_misses": 0,
		"tile_loads": 0, "evictions": 0, "max_cached_tiles": 0, "bytes_read": 0,
		"last_query_ms": 0.0, "last_query_dependency_files": 0, "last_query_features": 0}

func _fail(message: String) -> bool:
	last_error = message
	return false

func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

func _safe_key(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.length() < 64 and _key_re.search(value) != null

func _safe_filename(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.ends_with(".json") and _safe_key(value.trim_suffix(".json"))

func _valid_frame(frame: Variant) -> bool:
	return typeof(frame) == TYPE_DICTIONARY and frame.get("source_crs") == "EPSG:4326" and frame.get("survey_crs") == "EPSG:3414" \
		and frame.get("metres_per_unit") == 1.0 and frame.get("distance_compression") == false \
		and frame.get("origin_easting") == 30000.0 and frame.get("origin_northing") == 30000.0 \
		and frame.get("world_axes") == {"x": "south", "y": "up", "z": "west"}

func _read_bytes(path: String, limit: int) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("Cannot read source data: " + path)
		return PackedByteArray()
	if f.get_length() <= 0 or f.get_length() > limit:
		_fail("Source file size is outside its bounded contract: " + path)
		return PackedByteArray()
	return f.get_buffer(f.get_length())

func open_snapshot(directory: String, index_path: String, cache_capacity: int = 12) -> bool:
	_reset()
	var started := Time.get_ticks_usec()
	if cache_capacity < 1 or cache_capacity > 64:
		return _fail("Cache capacity must be in 1..64")
	var base := directory.trim_suffix("/")
	if base != base.simplify_path() or DirAccess.open(base) == null:
		return _fail("Snapshot directory is not a normalized existing directory")
	var raw := _read_bytes(base.path_join("manifest.json"), MAX_METADATA_BYTES)
	if raw.is_empty(): return false
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not _valid_frame(parsed.get("georeference")):
		return _fail("Snapshot frame is missing, compressed or incompatible")
	if typeof(parsed.get("tiles")) != TYPE_ARRAY or int(parsed.get("tile_metres", 0)) <= 0:
		return _fail("Snapshot inventory/tile size is invalid")
	var entries: Dictionary = {}
	for entry in parsed["tiles"]:
		if typeof(entry) != TYPE_DICTIONARY or not _safe_filename(entry.get("file")):
			return _fail("Unsafe canonical tile filename")
		var name: String = entry["file"]
		if entries.has(name) or typeof(entry.get("sha256")) != TYPE_STRING or _hash_re.search(entry["sha256"]) == null:
			return _fail("Duplicate tile or invalid source checksum")
		if int(entry.get("bytes", 0)) <= 0 or int(entry.get("bytes", 0)) > MAX_TILE_BYTES or int(entry.get("features", -1)) < 0:
			return _fail("Invalid canonical tile size/count")
		entries[name] = entry
	var index_raw := _read_bytes(index_path, MAX_METADATA_BYTES)
	if index_raw.is_empty(): return false
	# This separately tracked descriptor authenticates the entire dependency
	# table. The canonical manifest does not inventory it, avoiding a hash cycle.
	var identity_raw := _read_bytes(base.path_join("spatial-index.identity.json"), MAX_METADATA_BYTES)
	if identity_raw.is_empty(): return false
	var identity: Variant = JSON.parse_string(identity_raw.get_string_from_utf8())
	if typeof(identity) != TYPE_DICTIONARY or identity.get("schema") != IDENTITY_SCHEMA \
		or identity.get("index_sha256") != _sha(index_raw) or int(identity.get("index_bytes", 0)) != index_raw.size() \
		or identity.get("snapshot_manifest_sha256") != _sha(raw):
		return _fail("Spatial dependency index identity/checksum mismatch")
	var idx: Variant = JSON.parse_string(index_raw.get_string_from_utf8())
	if typeof(idx) != TYPE_DICTIONARY or idx.get("schema") != SCHEMA or typeof(idx.get("cells")) != TYPE_DICTIONARY:
		return _fail("Spatial dependency index schema is invalid")
	if idx.get("snapshot_manifest_sha256") != _sha(raw) or idx.get("georeference") != parsed["georeference"] or idx.get("tile_metres") != parsed["tile_metres"]:
		return _fail("Spatial index belongs to a different snapshot/frame")
	var boundary := _read_bytes(base.path_join("singapore-boundary.geojson"), MAX_METADATA_BYTES)
	if boundary.is_empty() or idx.get("boundary_sha256") != _sha(boundary):
		return _fail("Spatial index country boundary checksum mismatch")
	if identity.get("boundary_sha256") != _sha(boundary):
		return _fail("Spatial identity belongs to a different country boundary")
	if int(idx.get("indexed_cells", -1)) != idx["cells"].size() or identity.get("indexed_cells") != idx.get("indexed_cells") \
		or int(idx.get("owner_files", -1)) != entries.size() or identity.get("owner_files") != idx.get("owner_files") \
		or identity.get("features_indexed") != idx.get("features_indexed"):
		return _fail("Spatial index inventory/count mismatch")
	var referenced: Dictionary = {}
	for key in idx["cells"]:
		if not _safe_key(key) or typeof(idx["cells"][key]) != TYPE_ARRAY:
			return _fail("Unsafe dependency cell")
		for name in idx["cells"][key]:
			if not _safe_filename(name) or not entries.has(name):
				return _fail("Dependency references an unsafe/missing canonical tile")
			referenced[name] = true
	var feature_count := 0
	for name in entries:
		feature_count += int(entries[name]["features"])
		if int(entries[name]["features"]) > 0 and not referenced.has(name):
			return _fail("Spatial index omits a nonempty canonical owner")
	if int(idx.get("features_indexed", -1)) != feature_count:
		return _fail("Spatial index feature inventory mismatch")
	_base = base
	_manifest = parsed
	_index = idx
	_inventory = entries
	_capacity = cache_capacity
	stats["metadata_load_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	return true

func metadata() -> Dictionary:
	return _manifest

func spatial_metadata() -> Dictionary:
	return _index

func clear_cache() -> void:
	_cache.clear()
	_lru.clear()

func cached_tile_count() -> int:
	return _cache.size()

func _touch(name: String) -> void:
	_lru.erase(name)
	_lru.append(name)

func _numeric(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

func _coordinate_bounds(value: Variant, bounds: Array, depth: int = 0) -> bool:
	if depth > 8 or typeof(value) != TYPE_ARRAY or value.is_empty(): return false
	if _numeric(value[0]):
		if value.size() != 2 or not _numeric(value[1]): return false
		bounds[0] = minf(bounds[0], float(value[0]))
		bounds[1] = minf(bounds[1], float(value[1]))
		bounds[2] = maxf(bounds[2], float(value[0]))
		bounds[3] = maxf(bounds[3], float(value[1]))
		return true
	for child in value:
		if not _coordinate_bounds(child, bounds, depth + 1): return false
	return true

func _load_owner(name: String) -> Dictionary:
	if _cache.has(name):
		stats["cache_hits"] += 1
		_touch(name)
		return _cache[name]
	stats["cache_misses"] += 1
	var folder := DirAccess.open(_base)
	if folder == null or folder.is_link(name):
		_fail("Canonical tile symlink or directory failure: " + name)
		return {}
	var bytes := _read_bytes(_base.path_join(name), MAX_TILE_BYTES)
	if bytes.is_empty(): return {}
	var expected: Dictionary = _inventory[name]
	if bytes.size() != int(expected["bytes"]) or _sha(bytes) != expected["sha256"]:
		_fail("Canonical tile checksum/size mismatch: " + name)
		return {}
	var payload: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(payload) != TYPE_DICTIONARY or payload.get("tile") != name.trim_suffix(".json") or typeof(payload.get("features")) != TYPE_ARRAY or payload["features"].size() != int(expected["features"]):
		_fail("Canonical tile schema/count mismatch: " + name)
		return {}
	var bounds_list: Array[Rect2] = []
	for feature in payload["features"]:
		if typeof(feature) != TYPE_DICTIONARY or typeof(feature.get("id")) != TYPE_STRING or typeof(feature.get("kind")) != TYPE_STRING or typeof(feature.get("geometry")) != TYPE_DICTIONARY:
			_fail("Feature identity/geometry is invalid: " + name)
			return {}
		var b := [INF, INF, -INF, -INF]
		if not _coordinate_bounds(feature["geometry"].get("coordinates"), b):
			_fail("Feature has invalid/nonfinite projected coordinates: " + name)
			return {}
		bounds_list.append(Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1]))
	var entry := {"features": payload["features"], "bounds": bounds_list}
	_cache[name] = entry
	_touch(name)
	while _cache.size() > _capacity:
		var evicted: String = _lru.pop_front()
		_cache.erase(evicted)
		stats["evictions"] += 1
	stats["max_cached_tiles"] = maxi(stats["max_cached_tiles"], _cache.size())
	stats["tile_loads"] += 1
	stats["bytes_read"] += bytes.size()
	return entry

func _touches(a: Rect2, b: Rect2) -> bool:
	return a.position.x <= b.end.x and a.end.x >= b.position.x and a.position.y <= b.end.y and a.end.y >= b.position.y

## Broadphase candidates only: precise geometry/country clipping stays with
## the renderer. Cache limits do not retain/limit caller-owned query results.
func features_in_region(region: Rect2, kinds: Array[String] = []) -> Array[Dictionary]:
	last_error = ""
	var result: Array[Dictionary] = []
	stats["queries"] += 1
	var started := Time.get_ticks_usec()
	if _base.is_empty() or not region.position.is_finite() or not region.size.is_finite() or not region.end.is_finite() or region.size.x <= 0 or region.size.y <= 0:
		_fail("Open a snapshot and request a finite positive region")
		stats["failed_queries"] += 1
		return result
	var size := float(_manifest["tile_metres"])
	# Reject excessive axis spans before int conversion or multiplication: a
	# huge finite rectangle can otherwise wrap the signed 64-bit cell product.
	if region.size.x / size > MAX_QUERY_CELLS or region.size.y / size > MAX_QUERY_CELLS \
		or absf(region.position.x / size) > 1000000.0 or absf(region.position.y / size) > 1000000.0 \
		or absf(region.end.x / size) > 1000000.0 or absf(region.end.y / size) > 1000000.0:
		_fail("Query exceeds bounded safe cell domain")
		stats["failed_queries"] += 1
		return result
	var x0 := int(floor(region.position.x / size))
	var z0 := int(floor(region.position.y / size))
	var x1 := int(floor(region.end.x / size))
	var z1 := int(floor(region.end.y / size))
	var span_x := x1 - x0 + 1
	var span_z := z1 - z0 + 1
	if span_x > MAX_QUERY_CELLS or span_z > MAX_QUERY_CELLS or span_x * span_z > MAX_QUERY_CELLS:
		_fail("Query exceeds bounded cell budget; stream smaller regions")
		stats["failed_queries"] += 1
		return result
	var requested: Dictionary = {}
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			for name in _index["cells"].get("%d_%d" % [x, z], []): requested[name] = true
	var names := requested.keys()
	names.sort()
	var seen: Dictionary = {}
	for name in names:
		var owner := _load_owner(name)
		if owner.is_empty():
			stats["failed_queries"] += 1
			return [] # No partial world accepted after an owner read failure.
		for i in owner["features"].size():
			var feature: Dictionary = owner["features"][i]
			if not kinds.is_empty() and not feature["kind"] in kinds: continue
			if not _touches(owner["bounds"][i], region): continue
			var key: String = feature["kind"] + "|" + feature["id"]
			if seen.has(key):
				if seen[key] != feature:
					_fail("Conflicting duplicate source identity: " + key)
					stats["failed_queries"] += 1
					return []
				continue
			seen[key] = feature
			result.append(feature)
	stats["last_query_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	stats["last_query_dependency_files"] = names.size()
	stats["last_query_features"] = result.size()
	return result
