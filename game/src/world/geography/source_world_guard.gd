extends "res://src/world/geography/source_runtime.gd"
## Root-controlled source architecture readiness interlock. A real void stays
## a void. This does not infer land from a ray miss or turn a mask into a floor.
signal architecture_required(requirement: Dictionary)
const MASK_SCHEMA := "singapore_source_world_architecture_guard_v1"
var _architecture: Callable
var _architecture_owner: RefCounted
var _masks: Array[Dictionary] = []
var _mask_identity := ""
var _guard_configured := false
var last_transition: Dictionary = {}
var _last_request := ""
var guard_configuration_error := ""

func _guard_fail(reason: String) -> bool:
	guard_configuration_error = reason
	return false

## Callback(mask_id, canonical point, actor) returns a source-bound assessment:
## state required / known_physical_void / not_required / unknown;
## floor_ids, ready, provenance. Required.ready must represent actual same-
## epoch native floor+neighbor lifecycle, not a planned recipe or file presence.
func configure_architecture(mask_path: String, expected_sha256: String, assessment: Callable) -> bool:
	if _guard_configured or not _configured or not assessment.is_valid() or expected_sha256.length()!=64 or mask_path != mask_path.simplify_path(): return _guard_fail("Fresh source runtime, exact path/hash and assessment callback required")
	var file := FileAccess.open(mask_path,FileAccess.READ)
	if file==null or file.get_length()<2 or file.get_length()>262144: return _guard_fail("Mask file unavailable or outside byte bound")
	var raw := file.get_buffer(file.get_length())
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(raw)
	if hash.finish().hex_encode()!=expected_sha256: return _guard_fail("Exact Root mask bytes differ from pinned SHA256")
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not parsed is Dictionary or parsed.get("schema")!="terrain_root_holes_v1" or parsed.get("snapshot_manifest_sha256")!=frame.metadata().snapshot_manifest_sha256 or not parsed.get("masks") is Array or parsed.masks.is_empty() or parsed.masks.size()>64: return _guard_fail("Root mask schema/snapshot/bounded inventory mismatch")
	var masks: Array[Dictionary] = []
	var seen: Dictionary = {}
	var vertex_count := 0
	for row in parsed.masks:
		if not row is Dictionary or not row.get("mask_id") is String or seen.has(row.mask_id) or not row.get("geometry") is Dictionary or not row.get("provenance") is String: return _guard_fail("Invalid or duplicate Root mask descriptor")
		var geometry: Dictionary = row.geometry
		if not geometry.get("type") in ["Polygon","MultiPolygon"] or not geometry.get("coordinates") is Array or geometry.coordinates.is_empty(): return _guard_fail("Only nonempty source Polygon/MultiPolygon accepted")
		# The four OSM masks are MultiPolygons, but Root's separately declared
		# constructed public-loft footprint is a Polygon. Wrap its exact rings
		# once for common iteration; no coordinate/ring/hash mutation occurs.
		var input_polygons: Array = [geometry.coordinates] if geometry.type=="Polygon" else geometry.coordinates
		var polygons: Array = []
		for polygon in input_polygons:
			if not polygon is Array or polygon.is_empty(): return _guard_fail("Empty or malformed source polygon")
			var rings: Array = []
			for ring in polygon:
				if not ring is Array or ring.size()<4 or ring[0]!=ring[-1]: return _guard_fail("Source ring must preserve its explicit closure")
				var points: Array = []
				for point in ring:
					vertex_count += 1
					if vertex_count>20000 or not point is Array or point.size()!=2: return _guard_fail("Source point shape or vertex work bound exceeded")
					for value in point:
						if not typeof(value) in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or absf(float(value))>Frame.MAX_CANONICAL_COMPONENT_M: return _guard_fail("Source point is nonfinite or outside canonical domain")
					points.append([float(point[0]),float(point[1])])
				rings.append(points)
			polygons.append(rings)
		masks.append({"mask_id":row.mask_id,"polygons":polygons,"source_geometry_type":geometry.type,"source_feature_ids":row.get("source_feature_ids",[]).duplicate(),"provenance":row.provenance})
		seen[row.mask_id] = true
	_masks = masks
	_mask_identity = expected_sha256
	_architecture = assessment
	if assessment.get_object() is RefCounted: _architecture_owner = assessment.get_object()
	_guard_configured = true
	guard_configuration_error = ""
	return true

func architecture_guard_metadata() -> Dictionary:
	return {"schema":MASK_SCHEMA,"configured":_guard_configured,"root_masks_sha256":_mask_identity,"masks":_masks.size(),"configuration_error":guard_configuration_error,"geometry_is_land_or_dry_floor":false,"missing_floor_is_known_void":false,"root_assessment_required":true,"last_transition":last_transition.duplicate(true)}

func _side(a: Array,b: Array,x: float,z: float) -> float:
	return (float(b[0])-float(a[0]))*(z-float(a[1]))-(float(b[1])-float(a[1]))*(x-float(a[0]))

func _ring_state(point: Array, ring: Array) -> String:
	var x: float = point[0]
	var z: float = point[2]
	var inside := false
	for i in range(1,ring.size()):
		var a: Array = ring[i-1]
		var b: Array = ring[i]
		var cross := _side(a,b,x,z)
		var magnitude: float = maxf(1.0,maxf(absf(float(b[0])-float(a[0])),absf(float(b[1])-float(a[1]))))
		# Scalar double-roundoff only; never inflate/snap source geometry.
		if absf(cross)<=magnitude*1e-9 and x>=minf(a[0],b[0])-1e-9 and x<=maxf(a[0],b[0])+1e-9 and z>=minf(a[1],b[1])-1e-9 and z<=maxf(a[1],b[1])+1e-9: return "boundary"
		if (float(a[1])>z)!=(float(b[1])>z):
			var crossing: float = float(a[0])+(z-float(a[1]))*(float(b[0])-float(a[0]))/(float(b[1])-float(a[1]))
			if x<crossing: inside = not inside
	return "inside" if inside else "outside"

func _contains(point: Array, mask: Dictionary) -> bool:
	for polygon: Array in mask.polygons:
		if _ring_state(point,polygon[0])=="outside": continue
		var hole := false
		for i in range(1,polygon.size()):
			if _ring_state(point,polygon[i])!="outside": hole = true; break
		if not hole: return true
	return false

## Partition the exact swept center segment at every source-ring intersection.
## Midpoint tests distinguish a real courtyard hole and a thin crossed island;
## equal-XY OSM node identities are not merged or used as a road connection.
func _crossed_points(start: Array,end: Array,mask: Dictionary) -> Array:
	var fractions: Array[float] = [0.0,1.0]
	var dx: float = float(end[0])-float(start[0])
	var dz: float = float(end[2])-float(start[2])
	for polygon: Array in mask.polygons:
		for ring: Array in polygon:
			for i in range(1,ring.size()):
				var a: Array = ring[i-1]
				var b: Array = ring[i]
				var ex: float = float(b[0])-float(a[0])
				var ez: float = float(b[1])-float(a[1])
				var denominator: float = dx*ez-dz*ex
				if absf(denominator)<1e-15: continue
				var ax: float = float(a[0])-float(start[0])
				var az: float = float(a[1])-float(start[2])
				var fraction: float = (ax*ez-az*ex)/denominator
				var edge_fraction: float = (ax*dz-az*dx)/denominator
				if fraction>0.0 and fraction<1.0 and edge_fraction>=0.0 and edge_fraction<=1.0: fractions.append(fraction)
	fractions.sort()
	var samples: Array = []
	for i in fractions.size():
		var values: Array[float] = [fractions[i]]
		if i>0: values.append((fractions[i-1]+fractions[i])*.5)
		for fraction: float in values:
			var point: Array = [float(start[0])+dx*fraction,float(start[1])+(float(end[1])-float(start[1]))*fraction,float(start[2])+dz*fraction]
			if _contains(point,mask): samples.append(point)
	return samples

func _assessed(start: Array,end: Array,actor: CharacterBody3D) -> bool:
	if not _guard_configured or not _architecture.is_valid(): return false
	for mask: Dictionary in _masks:
		for point: Array in _crossed_points(start,end,mask):
			var result: Variant = _architecture.call(String(mask.mask_id),point,actor)
			if not result is Dictionary or not result.get("state") in ["required","known_physical_void","not_required","unknown"] or not result.get("provenance") is String or result.provenance.is_empty(): return false
			last_transition = {"root_masks_sha256":_mask_identity,"mask_id":mask.mask_id,"source_feature_ids":mask.source_feature_ids.duplicate(),"source_xyz":point.duplicate(),"assessment":result.duplicate(true),"origin_revision":frame.metadata().origin_revision}
			if result.state in ["known_physical_void","not_required"]: continue
			if result.state=="required" and result.get("ready",false) and result.get("floor_ids") is Array and not result.floor_ids.is_empty(): continue
			var request_key: String = String(mask.mask_id)+"|"+JSON.stringify(result.get("floor_ids",[]))+"|"+str(frame.metadata().origin_revision)
			if request_key!=_last_request:
				_last_request = request_key
				architecture_required.emit(last_transition.duplicate(true))
			return false
	_last_request = ""
	return true

func motion_allowed(actor: CharacterBody3D,delta: float,aircraft: bool = false,extra_motion: Vector3 = Vector3.ZERO) -> bool:
	if not super.motion_allowed(actor,delta,aircraft,extra_motion): return false
	# Airborne aircraft may fly above a genuinely open atrium/roof. Their
	# actual collision still blocks existing architecture; landing foot exits
	# take the separate planned-floor guard below.
	if aircraft: return true
	var start: Dictionary = frame.to_source_current_live(actor.global_position)
	var end: Dictionary = frame.to_source_current_live(actor.global_position+actor.velocity*delta+extra_motion)
	if not start.get("ok",false) or not end.get("ok",false): return false
	return _assessed(start.source_xyz,end.source_xyz,actor)

func landing_exit_safe(local_position: Vector3) -> bool:
	if not super.landing_exit_safe(local_position): return false
	var actor := get_tree().get_first_node_in_group("player") as Player
	var point: Dictionary = frame.to_source_current_live(local_position)
	return actor!=null and point.get("ok",false) and _assessed(point.source_xyz,point.source_xyz,actor)
