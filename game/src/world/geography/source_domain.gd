class_name SingaporeSourceDomain
extends RefCounted
## Immutable data-only domain adapter. Source doubles never become absolute
## engine vectors. Territory/coast enclosure do not establish dryland/water Y.
const DATA_SCHEMA := "singapore_source_domain_dataset_v1"
const IDENTITY_SCHEMA := "singapore_source_domain_identity_v1"
const RESULT_SCHEMA := "singapore_source_domain_result_v1"
const REGISTRY_VERSION := "singapore_source_domain_registry_v1"
const MAX_CANONICAL_COMPONENT_M := 10000000.0
const MAX_BYTES := 16 * 1024 * 1024
const MAX_IDENTITY_BYTES := 128 * 1024
const MAX_VERTICES := 250000
const MAX_POLYGONS := 4096
const MAX_RINGS := 8192
const FRAME := {"source_crs":"EPSG:4326","survey_crs":"EPSG:3414","origin_easting":30000.0,"origin_northing":30000.0,"world_axes":{"x":"south","y":"up","z":"west"},"metres_per_unit":1.0,"distance_compression":false,"legacy_plan_alignment_applied":false}
var last_error := ""
var _configured := false
var _identity: Dictionary = {}
var _territory: Array = []
var _coast: Array = []
var _descriptors: Array = []
var _stats := {"file_reads":0,"json_decodes":0,"queries":0,"segments_tested":0,"vertices_cached":0,"edge_references_cached":0}
var _sha_re := RegEx.new()

func _init() -> void:
	_sha_re.compile("^[0-9a-f]{64}$")

func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

func _hash(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and _sha_re.search(value) != null

func _count(value: Variant, maximum: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= 0.0 and float(value) <= maximum

func _text(value: Variant, expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected

func _false(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and not value

func _version(value: Variant) -> bool:
	return _number(value) and float(value) == 1.0

func _frame_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != FRAME.size(): return false
	for key: String in ["source_crs","survey_crs"]:
		if not _text(value.get(key),FRAME[key]): return false
	for key: String in ["origin_easting","origin_northing","metres_per_unit"]:
		if not _number(value.get(key)) or float(value[key]) != float(FRAME[key]): return false
	for key: String in ["distance_compression","legacy_plan_alignment_applied"]:
		if not _false(value.get(key)): return false
	if not value.get("world_axes") is Dictionary or value.world_axes.size() != 3: return false
	for axis: String in ["x","y","z"]:
		if not _text(value.world_axes.get(axis),FRAME.world_axes[axis]): return false
	return true

func _bindings_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 7: return false
	for field: String in ["snapshot_manifest_sha256","country_wgs84_sha256","coastline_sha256","coast_identity_sha256","pbf_sha256","projection_implementation_sha256"]:
		if not _hash(value.get(field)): return false
	return typeof(value.get("source_snapshot_utc")) == TYPE_STRING and not value.source_snapshot_utc.is_empty()

func _counts_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2: return false
	for kind: String in ["territory","coast_enclosure"]:
		var counts: Variant = value.get(kind)
		if not counts is Dictionary or counts.size() != 3 or not _count(counts.get("polygons"),MAX_POLYGONS) or not _count(counts.get("rings"),MAX_RINGS) or not _count(counts.get("vertices"),MAX_VERTICES): return false
	return true

func _descriptors_valid(value: Variant, domain_hash: String) -> bool:
	if not value is Array or value.size() != 3: return false
	var expected: Array = _expected_descriptors(domain_hash)
	for i in 3:
		if not value[i] is Dictionary or value[i].size() != 4: return false
		for field: String in ["kind","provider_id","source_reference","registry_version"]:
			if not _text(value[i].get(field),expected[i][field]): return false
	return true

func _fail(message: String) -> bool:
	last_error = message
	return false

func _digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _read(path: String, maximum: int) -> PackedByteArray:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		_fail("Domain source file unavailable")
		return PackedByteArray()
	if file.get_length() <= 0 or file.get_length() > maximum:
		_fail("Domain source exceeds bounded byte contract")
		return PackedByteArray()
	_stats.file_reads += 1
	return file.get_buffer(file.get_length())

func _parse(bytes: PackedByteArray) -> Variant:
	_stats.json_decodes += 1
	return JSON.parse_string(bytes.get_string_from_utf8())

func _expected_descriptors(domain_hash: String) -> Array:
	var result: Array = []
	for kind: String in ["territory","land","water"]:
		result.append({"kind":kind,"provider_id":"singapore-source-domain/"+kind+"/v1/"+domain_hash,
			"source_reference":"source-domain/v1/"+domain_hash,"registry_version":REGISTRY_VERSION})
	return result

func _bounds(flat: PackedFloat64Array) -> Array:
	var bounds: Array = [INF,INF,-INF,-INF]
	for i in range(0,flat.size(),2):
		bounds[0] = minf(bounds[0],flat[i])
		bounds[1] = minf(bounds[1],flat[i+1])
		bounds[2] = maxf(bounds[2],flat[i])
		bounds[3] = maxf(bounds[3],flat[i+1])
	return bounds

func _bucket(z: float, low: float, height: float, count: int) -> int:
	return clampi(int(floor((z-low)/height*count)),0,count-1) if count > 1 else 0

func _pack_ring(raw: Variant) -> Dictionary:
	if not raw is Array or raw.size() < 8 or raw.size()%2 != 0 or raw.size() > MAX_VERTICES*2:
		return {"ok":false,"error":"Invalid closed double ring"}
	var flat := PackedFloat64Array()
	for value in raw:
		if not _number(value) or absf(float(value)) > MAX_CANONICAL_COMPONENT_M: return {"ok":false,"error":"Nonfinite/unbounded source ring"}
		flat.append(float(value))
	if flat[0] != flat[-2] or flat[1] != flat[-1]: return {"ok":false,"error":"Ring is not explicitly closed"}
	var bounds: Array = _bounds(flat)
	var area := 0.0
	var ox: float = flat[0]
	var oz: float = flat[1]
	for i in range(0,flat.size()-2,2):
		area += (flat[i]-ox)*(flat[i+3]-oz)-(flat[i+2]-ox)*(flat[i+1]-oz)
	if not is_finite(area) or area == 0.0 or bounds[0] >= bounds[2] or bounds[1] >= bounds[3]:
		return {"ok":false,"error":"Degenerate source ring"}
	# Z stripes index edges without changing coordinates. Cap index references
	# to eight per source edge; pathological rings fall back to one linear bin.
	var edges: int = (flat.size() >> 1)-1
	var count := 32 if edges >= 32 else 1
	var references := 0
	for i in range(0,flat.size()-2,2):
		var first: int = _bucket(minf(flat[i+1],flat[i+3]),bounds[1],bounds[3]-bounds[1],count)
		var last: int = _bucket(maxf(flat[i+1],flat[i+3]),bounds[1],bounds[3]-bounds[1],count)
		references += last-first+1
	if references > edges*8+32: count = 1
	var bins: Array = []
	for i in count: bins.append(PackedInt32Array())
	references = 0
	for i in range(0,flat.size()-2,2):
		var first: int = _bucket(minf(flat[i+1],flat[i+3]),bounds[1],bounds[3]-bounds[1],count)
		var last: int = _bucket(maxf(flat[i+1],flat[i+3]),bounds[1],bounds[3]-bounds[1],count)
		for b in range(first,last+1):
			var bucket_edges: PackedInt32Array = bins[b]
			bucket_edges.append(i)
			bins[b] = bucket_edges
			references += 1
	return {"ok":true,"ring":{"flat":flat,"bounds":bounds,"bins":bins},"vertices":flat.size() >> 1,"edge_references":references}

func _pack_collection(raw: Variant, expected: Variant) -> Dictionary:
	if not raw is Array or not expected is Dictionary or not _count(expected.get("polygons"),MAX_POLYGONS) or not _count(expected.get("rings"),MAX_RINGS) or not _count(expected.get("vertices"),MAX_VERTICES):
		return {"ok":false,"error":"Invalid domain inventory"}
	if raw.size() != int(expected.polygons): return {"ok":false,"error":"Polygon inventory mismatch"}
	var packed: Array = []
	var vertices := 0
	var ring_count := 0
	var references := 0
	var ids: Dictionary = {}
	for polygon in raw:
		if not polygon is Dictionary or typeof(polygon.get("id")) != TYPE_STRING or polygon.id.is_empty() or ids.has(polygon.id) or not polygon.get("rings") is Array or polygon.rings.is_empty():
			return {"ok":false,"error":"Invalid/duplicate polygon identity"}
		ids[polygon.id] = true
		var rings: Array = []
		for raw_ring in polygon.rings:
			var compiled: Dictionary = _pack_ring(raw_ring)
			if not compiled.ok: return compiled
			rings.append(compiled.ring)
			vertices += int(compiled.vertices)
			references += int(compiled.edge_references)
			ring_count += 1
			if vertices > MAX_VERTICES or ring_count > MAX_RINGS: return {"ok":false,"error":"Domain vertex/ring budget exceeded"}
		var outer_bounds: Array = rings[0].bounds
		if not polygon.get("bounds_xz") is Array or polygon.bounds_xz.size() != 4: return {"ok":false,"error":"Invalid polygon bounds"}
		for value in polygon.bounds_xz:
			if not _number(value): return {"ok":false,"error":"Invalid numeric polygon bounds"}
		if polygon.bounds_xz != outer_bounds: return {"ok":false,"error":"Polygon bounds differ from exact ring"}
		for hole: Dictionary in rings.slice(1):
			if hole.bounds[0] < outer_bounds[0] or hole.bounds[1] < outer_bounds[1] or hole.bounds[2] > outer_bounds[2] or hole.bounds[3] > outer_bounds[3]:
				return {"ok":false,"error":"Hole outside source exterior bounds"}
		packed.append({"id":polygon.id,"bounds":outer_bounds,"rings":rings})
	if vertices != int(expected.vertices) or ring_count != int(expected.rings): return {"ok":false,"error":"Domain ring/vertex inventory mismatch"}
	return {"ok":true,"polygons":packed,"vertices":vertices,"rings":ring_count,"edge_references":references}

## Configure exactly once, off the frame-critical path. Bind the expected
## snapshot to the intended SourceFrame. No default map or lazy file reload.
func configure(directory: String, expected_identity_sha256: String, expected_snapshot_manifest_sha256: String) -> bool:
	if _configured: return _fail("Domain identity is immutable; create a new adapter")
	if not _hash(expected_identity_sha256) or not _hash(expected_snapshot_manifest_sha256): return _fail("Explicit trusted domain and snapshot hashes required")
	var base: String = directory.trim_suffix("/")
	var folder := DirAccess.open(base)
	if base != base.simplify_path() or folder == null or folder.is_link("identity.json") or folder.is_link("domain.json"):
		return _fail("Unsafe/unavailable domain directory or symlink source")
	var identity_raw: PackedByteArray = _read(base.path_join("identity.json"),MAX_IDENTITY_BYTES)
	if identity_raw.is_empty() or _digest(identity_raw) != expected_identity_sha256: return _fail("Domain identity checksum mismatch")
	var identity: Variant = _parse(identity_raw)
	if not identity is Dictionary or not _text(identity.get("schema"),IDENTITY_SCHEMA) or not _version(identity.get("version")) or not _text(identity.get("registry_version"),REGISTRY_VERSION) or not identity.get("dataset") is Dictionary or not _bindings_valid(identity.get("bindings")) or not _counts_valid(identity.get("counts")):
		return _fail("Invalid domain identity/schema/version")
	if not _text(identity.dataset.get("file"),"domain.json") or not _hash(identity.dataset.get("sha256")) or not _count(identity.dataset.get("bytes"),MAX_BYTES) or int(identity.dataset.bytes) <= 0:
		return _fail("Unsafe dataset file or byte/hash contract")
	if identity.bindings.get("snapshot_manifest_sha256") != expected_snapshot_manifest_sha256:
		return _fail("Domain snapshot differs from intended context")
	if not _descriptors_valid(identity.get("provider_descriptors"),identity.dataset.sha256): return _fail("Domain provider registry differs from exact versioned descriptors")
	var bytes: PackedByteArray = _read(base.path_join("domain.json"),MAX_BYTES)
	if bytes.size() != int(identity.dataset.bytes) or _digest(bytes) != identity.dataset.sha256: return _fail("Domain dataset checksum/size mismatch")
	var data: Variant = _parse(bytes)
	if not data is Dictionary or not _text(data.get("schema"),DATA_SCHEMA) or not _version(data.get("version")) or not _text(data.get("registry_version"),REGISTRY_VERSION) or not _frame_valid(data.get("georeference")) or not _bindings_valid(data.get("bindings")) or data.bindings != identity.bindings or not _counts_valid(data.get("counts")) or data.get("counts") != identity.get("counts"):
		return _fail("Domain dataset source/frame/inventory mismatch")
	var contract: Variant = data.get("semantic_contract")
	if not contract is Dictionary or not _false(contract.get("territory_is_land")) or not _false(contract.get("coast_enclosure_is_dryland")) or not _text(contract.get("land_state"),"unknown") or not _text(contract.get("water_state"),"unknown") or not _false(contract.get("finite_water_columns_available")) or not _text(contract.get("territory_boundary"),"inclusive") or not _false(contract.get("inland_water_resolved")) or not _false(contract.get("terrain_elevation_resolved")) or not _false(contract.get("tides_resolved")) or not _false(contract.get("source_completeness_certified")):
		return _fail("Unsupported domain semantic authority")
	var territory: Dictionary = _pack_collection(data.get("territory"),data.counts.get("territory"))
	var coast: Dictionary = _pack_collection(data.get("coast_enclosure"),data.counts.get("coast_enclosure"))
	if not territory.ok or not coast.ok: return _fail(territory.get("error",coast.get("error","Invalid domain geometry")))
	if int(territory.vertices)+int(coast.vertices) > MAX_VERTICES or territory.polygons.size()+coast.polygons.size() > MAX_POLYGONS or int(territory.rings)+int(coast.rings) > MAX_RINGS:
		return _fail("Combined domain cache inventory exceeds bounds")
	_identity = identity.duplicate(true)
	_identity["trusted_identity_sha256"] = expected_identity_sha256
	_identity["data_scope"] = data.get("data_scope","")
	_territory = territory.polygons
	_coast = coast.polygons
	_descriptors = identity.provider_descriptors.duplicate(true)
	_stats.vertices_cached = int(territory.vertices)+int(coast.vertices)
	_stats.edge_references_cached = int(territory.edge_references)+int(coast.edge_references)
	_configured = true
	last_error = ""
	return true

func provider_descriptors() -> Array:
	return _descriptors.duplicate(true)

func metadata() -> Dictionary:
	return {"configured":_configured,"schema":RESULT_SCHEMA,"registry_version":REGISTRY_VERSION,
		"identity":_identity.duplicate(true),"stats":_stats.duplicate(true),"elevation_or_hydrology_verified":false}

func _relation_ring(x: float,z: float,ring: Dictionary) -> String:
	var bounds: Array = ring.bounds
	if x < bounds[0] or x > bounds[2] or z < bounds[1] or z > bounds[3]: return "outside"
	var flat: PackedFloat64Array = ring.flat
	var bins: Array = ring.bins
	var candidates: PackedInt32Array = bins[_bucket(z,bounds[1],bounds[3]-bounds[1],bins.size())]
	var inside := false
	for index: int in candidates:
		_stats.segments_tested += 1
		var ax: float = flat[index]
		var az: float = flat[index+1]
		var bx: float = flat[index+2]
		var bz: float = flat[index+3]
		var dx: float = x-ax
		var dz: float = z-az
		var cross: float = dx*(bz-az)-dz*(bx-ax)
		if cross == 0.0 and x >= minf(ax,bx) and x <= maxf(ax,bx) and z >= minf(az,bz) and z <= maxf(az,bz): return "boundary"
		if (az>z) != (bz>z) and dx < (z-az)*(bx-ax)/(bz-az): inside = not inside
	return "inside" if inside else "outside"

func _relation_collection(x: float,z: float,polygons: Array) -> String:
	var boundary := false
	for polygon: Dictionary in polygons:
		var bounds: Array = polygon.bounds
		if x < bounds[0] or x > bounds[2] or z < bounds[1] or z > bounds[3]: continue
		var outer: String = _relation_ring(x,z,polygon.rings[0])
		if outer == "outside": continue
		if outer == "boundary":
			boundary = true
			continue
		var excluded := false
		for hole: Dictionary in polygon.rings.slice(1):
			var relation: String = _relation_ring(x,z,hole)
			if relation == "boundary":
				boundary = true
				excluded = true
				break
			if relation == "inside":
				excluded = true
				break
		if not excluded: return "inside"
	return "boundary" if boundary else "outside"

## Context-compatible rows, with coast relation kept only in diagnostics.
## No physical support, dry ground or finite 3D water column is invented.
func observe(source_xyz: Variant) -> Dictionary:
	var result := {"ok":false,"schema":RESULT_SCHEMA,"registry_version":REGISTRY_VERSION,
		"territory":{"state":"unknown","payload":{}},"land":{"state":"unknown","payload":{}},"water":{"state":"unknown","payload":{}},
		"diagnostics":{"coast_enclosure_relation":"unknown","territory_relation":"unknown","hydrology":"unresolved","terrain_elevation":"unresolved","tides":"unresolved"}}
	if not _configured:
		last_error = "Source domain is not configured"
		result.diagnostics["error"] = last_error
		return result
	if not typeof(source_xyz) in [TYPE_ARRAY,TYPE_PACKED_FLOAT64_ARRAY] or source_xyz.size() != 3:
		last_error = "Canonical source position must be a three-double array"
		result.diagnostics["error"] = last_error
		return result
	for component in source_xyz:
		if not _number(component) or absf(float(component)) > MAX_CANONICAL_COMPONENT_M:
			last_error = "Nonfinite/unbounded canonical source coordinate"
			result.diagnostics["error"] = last_error
			return result
	_stats.queries += 1
	var before: int = _stats.segments_tested
	var territory: String = _relation_collection(float(source_xyz[0]),float(source_xyz[2]),_territory)
	var coast: String = _relation_collection(float(source_xyz[0]),float(source_xyz[2]),_coast)
	result.ok = true
	result.territory.state = "outside" if territory == "outside" else "inside"
	result.diagnostics["territory_relation"] = territory
	result.diagnostics["coast_enclosure_relation"] = coast
	result.diagnostics["boundary_policy"] = "inclusive; no artificial tolerance band; IEEE64 scalar arithmetic"
	result.diagnostics["land_reason"] = "Coast enclosure does not resolve inland water or dryland"
	result.diagnostics["water_reason"] = "No source-bound finite bottom/surface column or complete dry classification"
	result.diagnostics["snapshot_manifest_sha256"] = _identity.bindings.snapshot_manifest_sha256
	result.diagnostics["domain_identity_sha256"] = _identity.trusted_identity_sha256
	result.diagnostics["segments_tested"] = int(_stats.segments_tested)-before
	last_error = ""
	return result
