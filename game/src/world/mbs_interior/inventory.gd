extends RefCounted
## Whole-program reconstruction inventory. Data coverage is not runtime completion.
const PATH := "res://data/mbs-interior/inventory.json"
static var _cache: Dictionary = {}
static var _floors: Dictionary = {}
static var _units: Dictionary = {}

static func _ensure_loaded() -> bool:
	if not _cache.is_empty(): return true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary: return false
	_cache = parsed
	for record: Dictionary in _cache.hotel_floors:
		_floors[String(record.id)] = record
		for unit: Dictionary in record.units: _units[String(unit.id)] = unit
	for record: Dictionary in _cache.resort_program_floors: _floors[String(record.id)] = record
	return true

static func load_inventory() -> Dictionary:
	if not _ensure_loaded(): return {"error": "Missing or invalid MBS interior inventory."}
	return _cache.duplicate(true)

static func normalize_floor_id(id: String) -> String:
	var parts: PackedStringArray = id.split("-")
	if parts.size() == 2 and parts[1].begins_with("L") and parts[1].substr(1).is_valid_int():
		return parts[0] + "-L" + str(int(parts[1].substr(1)))
	return id

static func floor_record(id: String) -> Dictionary:
	_ensure_loaded()
	return (_floors.get(normalize_floor_id(id), {}) as Dictionary).duplicate(true)

static func floor_ids(guest_only: bool = false) -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	for key: String in _floors:
		if not guest_only or _floors[key].factory == "guest_floor_v1": result.append(key)
	result.sort()
	return result

static func guest_floor_ids() -> Array[String]:
	return floor_ids(true)

static func unit_record(id: String) -> Dictionary:
	_ensure_loaded()
	return (_units.get(id, {}) as Dictionary).duplicate(true)

static func connections_for(id: String) -> Array[Dictionary]:
	_ensure_loaded()
	var canonical := normalize_floor_id(id)
	var result: Array[Dictionary] = []
	for edge: Dictionary in _cache.connections:
		if edge.from_floor == canonical or edge.to_floor == canonical: result.append(edge.duplicate(true))
	return result

static func validate_inventory() -> Dictionary:
	var data := load_inventory()
	if data.has("error"): return {"valid": false, "errors": [data.error]}
	var errors: Array[String] = []
	var suites := 0
	var count := 0
	var seen: Dictionary = {}
	for record: Dictionary in data.hotel_floors:
		if record.factory == "guest_floor_v1" and record.units.is_empty(): errors.append("Empty guest floor " + String(record.id))
		for unit: Dictionary in record.units:
			count += 1
			if unit.is_suite: suites += 1
			if seen.has(unit.id): errors.append("Duplicate room ID " + String(unit.id))
			seen[unit.id] = true
			if unit.floor_id != record.id: errors.append("Room floor mismatch " + String(unit.id))
	for edge: Dictionary in data.connections:
		if not _floors.has(edge.from_floor) or not _floors.has(edge.to_floor): errors.append("Orphan connection " + String(edge.id))
		if edge.get("actor_teleport", false): errors.append("Actor teleport connection " + String(edge.id))
	if count != 1850 or suites != 775: errors.append("Normalized unit/suite count differs from reconstruction contract.")
	return {"valid": errors.is_empty(), "errors": errors, "units": count, "suites": suites, "guest_floors": guest_floor_ids().size(), "program_floors": _floors.size(), "full_building_completed": false, "private_asbuilt_verified": false}
