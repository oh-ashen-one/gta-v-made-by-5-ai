extends RefCounted
## Shared authored entrance contract, consumed by placement, keep-outs and QA.
const PATH := "res://data/mbs-interior/city_access.json"
static var _data: Dictionary = {}
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _data = parsed
	return _data
static func offset(key: String) -> Vector3:
	var p: Array = data()[key]
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
static func entrance() -> Vector3:
	return DowntownPlan.anchor("marina_bay_sands") + offset("entrance_offset")
static func exit_position() -> Vector3:
	return DowntownPlan.anchor("marina_bay_sands") + offset("exit_offset")
static func approach_contains(p: Vector3) -> bool:
	var r: Array = data().approach_rect_relative_xz
	var m := DowntownPlan.anchor("marina_bay_sands")
	return Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3])).has_point(Vector2(p.x-m.x,p.z-m.z))
static func valid_visit(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=2: return false
	if typeof(value.get("version")) not in [TYPE_INT,TYPE_FLOAT]: return false
	return float(value.version)==1.0 and typeof(value.get("space"))==TYPE_STRING and value.space in ["lobby","guest","spa"]
