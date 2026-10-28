class_name SingaporeSourceWorldContext
extends RefCounted
## Source-domain composition and restore PRECONDITIONS only. No actor movement,
## scene loading, recovery, save-file writes, or implicit source-world switch.
const Frame = preload("res://src/world/geography/source_frame.gd")
const QUERY_SCHEMA := "singapore_source_query_v1"
const OBSERVATION_SCHEMA := "singapore_source_observation_v1"
const RESTORE_SCHEMA := "singapore_source_restore_v1"
const TRANSITION_SCHEMA := "singapore_context_transition_v1"
const COLLIDER_META := "singapore_source_support_v1"
const KINDS := ["territory", "land", "water", "physics"]
const QUERY_KEYS := ["schema", "context_instance_id", "frame_instance_id", "frame_fingerprint", "snapshot_manifest_sha256", "geometry_manifest_sha256", "vertical_manifest_sha256", "profile_sha256", "origin_revision", "registry_revision", "source_xyz", "local_sample", "physics_tick", "physics_space_id", "query_sha256"]
const OBSERVATION_KEYS := ["schema", "context_instance_id", "frame_instance_id", "frame_fingerprint", "snapshot_manifest_sha256", "geometry_manifest_sha256", "vertical_manifest_sha256", "profile_sha256", "origin_revision", "registry_revision", "source_xyz", "physics_tick", "physics_space_id", "query_sha256", "provider_id", "kind", "state", "payload", "observation_sha256"]
const RESTORE_KEYS := ["schema", "source_pose", "geometry_manifest_sha256", "vertical_manifest_sha256", "floor_geometry_sha256"]
const PROFILE_KEYS := ["profile_id", "radius_m", "height_m", "center_offset_xyz", "min_support_normal_y", "max_support_drop_m", "max_support_rise_m", "max_support_lateral_m"]
const FLOOR_KEYS := ["feature_id", "floor_id", "geometry_sha256", "support_ids", "volumes", "provenance"]
const VOLUME_KEYS := ["volume_id", "min_xyz", "max_xyz", "dry"]
const OBOX_SCHEMA := "singapore_upright_obox_v1"
const OBOX_KEYS := ["schema", "volume_id", "center_xyz", "half_extents_xyz", "axis_x_xyz", "axis_z_xyz", "dry"]
const OBOX_BASIS_TOLERANCE := 0.000000000001
const DOUBLE_ROUNDING_FACTOR := 8.0 * 0.0000000000000002220446049250313
const CONTACT_KEYS := ["state", "feature_id", "floor_id", "support_id", "collider_instance_id", "contact_source_xyz", "normal_source_xyz"]

var last_error := ""
var _frame: Variant = null
var _world: World3D
var _configured := false
var _identity: Dictionary = {}
var _profile: Dictionary = {}
var _providers: Dictionary = {}
var _floors: Dictionary = {}
var _registry_revision := 0
var _sha_re := RegEx.new()

func _init() -> void:
	_sha_re.compile("^[0-9a-f]{64}$")

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _invalid_restore(failure: Dictionary) -> Dictionary:
	# Restore is a tagged decision API even when its input/query is invalid.
	# Invalid is never pending/ready and must not authorize actor application.
	return {"ok": false, "status": "invalid", "error": failure.get("error", "Invalid restore precondition")}

func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

func _label(value: Variant, allow_empty: bool = false) -> bool:
	return typeof(value) == TYPE_STRING and value.length() <= 256 and (allow_empty or not value.is_empty())

func _hash(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and _sha_re.search(value) != null

func _provider_kind(value: Variant) -> String:
	# Named property assignment on an untyped Godot Dictionary can add a
	# StringName key. Normalize this native spelling, never arbitrary values.
	if not typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]: return ""
	var kind := String(value)
	return kind if kind in KINDS else ""

func _exact(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

func _point(value: Variant) -> Dictionary:
	if not typeof(value) in [TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] or value.size() != 3: return _fail("Canonical point must use three double-valued array elements")
	var point: Array[float] = []
	for component in value:
		if not _number(component) or absf(float(component)) > Frame.MAX_CANONICAL_COMPONENT_M: return _fail("Invalid canonical coordinate")
		point.append(float(component))
	return {"ok": true, "point": point}

func _digest(value: Dictionary) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(JSON.stringify(value, "", true, true).to_utf8_buffer())
	return h.finish().hex_encode()

func _without(value: Dictionary, omitted: Array) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	for key in omitted: result.erase(key)
	return result

func _normal_profile(value: Variant) -> Dictionary:
	if not _exact(value, PROFILE_KEYS) or not _label(value.profile_id): return _fail("Require an explicit restore-capsule profile")
	for key in ["radius_m", "height_m", "min_support_normal_y", "max_support_drop_m", "max_support_rise_m", "max_support_lateral_m"]:
		if not _number(value[key]): return _fail("Restore profile values must be finite numbers")
	var offset: Dictionary = _point(value.center_offset_xyz)
	if not offset.ok: return offset
	if float(value.radius_m) <= 0.0 or float(value.radius_m) > 5.0 or float(value.height_m) < 2.0 * float(value.radius_m) or float(value.height_m) > 20.0: return _fail("Invalid restore-capsule dimensions")
	if float(value.min_support_normal_y) < 0.01 or float(value.min_support_normal_y) > 1.0: return _fail("Invalid support slope policy")
	for key in ["max_support_drop_m", "max_support_rise_m", "max_support_lateral_m"]:
		if float(value[key]) < 0.0 or float(value[key]) > 1.0: return _fail("Support probe must remain bounded to one metre")
	for component: float in offset.point:
		if absf(component) > 20.0: return _fail("Restore-capsule offset is unbounded")
	var result: Dictionary = value.duplicate(true)
	result.center_offset_xyz = offset.point
	for key in ["radius_m", "height_m", "min_support_normal_y", "max_support_drop_m", "max_support_rise_m", "max_support_lateral_m"]: result[key] = float(result[key])
	return {"ok": true, "profile": result}

## Hashes identify declared geometry/vertical manifests; they do not prove
## surveyed/as-built content or a resolved vertical datum. No reconfiguration.
func configure(frame: Variant, geometry_manifest_sha256: Variant, vertical_manifest_sha256: Variant, restore_profile: Variant, physics_world: Variant = null) -> bool:
	if _configured:
		last_error = "Context identity is immutable; use a new context"
		return false
	if not frame is Frame or not frame.metadata().configured or not _hash(geometry_manifest_sha256) or not _hash(vertical_manifest_sha256):
		last_error = "Require a configured source frame and explicit versioned geometry/vertical manifests"
		return false
	if physics_world != null and not physics_world is World3D:
		last_error = "Physics world must be an explicit World3D or null for data-only use"
		return false
	var normalized: Dictionary = _normal_profile(restore_profile)
	if not normalized.ok:
		last_error = normalized.error
		return false
	var meta: Dictionary = frame.metadata()
	_frame = frame
	_world = physics_world
	_profile = normalized.profile.duplicate(true)
	_identity = {"context_instance_id": get_instance_id(), "frame_instance_id": frame.get_instance_id(),
		"frame_fingerprint": meta.frame_fingerprint, "snapshot_manifest_sha256": meta.snapshot_manifest_sha256,
		"geometry_manifest_sha256": geometry_manifest_sha256, "vertical_manifest_sha256": vertical_manifest_sha256,
		"profile_sha256": _digest(_profile)}
	_configured = true
	last_error = ""
	return true

func metadata() -> Dictionary:
	var result: Dictionary = _identity.duplicate(true)
	result["configured"] = _configured
	result["registry_revision"] = _registry_revision
	result["profile"] = _profile.duplicate(true)
	result["providers"] = _providers.duplicate(true)
	result["registered_floor_count"] = _floors.size()
	result["physics_space_id"] = _space_id()
	result["origin_revision"] = _frame.metadata().origin_revision if _configured else -1
	result["elevation_verified_by_context"] = false
	return result

func _space_id() -> int:
	return _world.space.get_id() if _world != null and is_instance_valid(_world) else 0

## Explicit adapter registration only. This class invokes no third-party
## callbacks and cannot authenticate whether an adapter queried real physics.
func register_provider(kind: Variant, provider_id: Variant, source_reference: Variant) -> bool:
	var canonical_kind := _provider_kind(kind)
	if not _configured or canonical_kind.is_empty() or not _label(provider_id) or not _label(source_reference):
		last_error = "Invalid explicit source-provider descriptor"
		return false
	if _providers.has(canonical_kind):
		last_error = "Provider identity cannot be replaced in a live context"
		return false
	_providers[canonical_kind] = {"provider_id": provider_id, "source_reference": source_reference}
	_registry_revision += 1
	last_error = ""
	return true

func _floor_key(feature_id: String, floor_id: String) -> String:
	# JSON tuple avoids collisions from separators inside legitimate source IDs.
	return JSON.stringify([feature_id, floor_id])

func _normal_volume(value: Variant) -> Dictionary:
	# A schema-bearing volume is explicitly the oriented alternative. Unknown
	# schemas/hybrid fields must never fall back to a broader axis-aligned box.
	if typeof(value) == TYPE_DICTIONARY and value.has("schema"): return _normal_obox(value)
	if not _exact(value, VOLUME_KEYS) or not _label(value.volume_id) or typeof(value.dry) != TYPE_BOOL: return _fail("Invalid source-volume schema")
	var lower: Dictionary = _point(value.min_xyz)
	var upper: Dictionary = _point(value.max_xyz)
	if not lower.ok or not upper.ok: return _fail("Source volumes require canonical double bounds")
	for i in 3:
		if float(lower.point[i]) >= float(upper.point[i]): return _fail("Source volume must have positive extent in all axes")
	return {"ok": true, "volume": {"volume_id": value.volume_id, "min_xyz": lower.point, "max_xyz": upper.point, "dry": value.dry}}

func _normal_obox(value: Variant) -> Dictionary:
	if not _exact(value, OBOX_KEYS) or typeof(value.schema) != TYPE_STRING or value.schema != OBOX_SCHEMA or not _label(value.volume_id) or typeof(value.dry) != TYPE_BOOL: return _fail("Invalid upright oriented-volume schema")
	var center: Dictionary = _point(value.center_xyz)
	var half: Dictionary = _point(value.half_extents_xyz)
	var axis_x: Dictionary = _point(value.axis_x_xyz)
	var axis_z: Dictionary = _point(value.axis_z_xyz)
	if not center.ok or not half.ok or not axis_x.ok or not axis_z.ok: return _fail("Oriented volume requires finite canonical double arrays")
	for component: float in half.point:
		if component <= 0.0: return _fail("Oriented volume half-extents must all be positive")
	var x: Array = axis_x.point
	var z: Array = axis_z.point
	# Y is implicitly +Up; do not accept even a small tilt, scaled basis,
	# mirrored basis or independent shear. Tolerance is only double roundoff.
	if float(x[1]) != 0.0 or float(z[1]) != 0.0: return _fail("Oriented volume must be upright with implicit +Y Up")
	var length_x_sq := float(x[0]) * float(x[0]) + float(x[2]) * float(x[2])
	var length_z_sq := float(z[0]) * float(z[0]) + float(z[2]) * float(z[2])
	var dot_xz := float(x[0]) * float(z[0]) + float(x[2]) * float(z[2])
	var determinant := float(x[0]) * float(z[2]) - float(x[2]) * float(z[0])
	if absf(length_x_sq - 1.0) > OBOX_BASIS_TOLERANCE or absf(length_z_sq - 1.0) > OBOX_BASIS_TOLERANCE or absf(dot_xz) > OBOX_BASIS_TOLERANCE or absf(determinant - 1.0) > OBOX_BASIS_TOLERANCE: return _fail("Oriented volume X/Z basis must be unit, orthogonal and right-handed")
	# The enclosing canonical bounds must remain in the same finite coordinate
	# domain as every query; these bounds are validated, NEVER used as dry area.
	var enclosing: Array[float] = [absf(float(x[0])) * float(half.point[0]) + absf(float(z[0])) * float(half.point[2]), float(half.point[1]), absf(float(x[2])) * float(half.point[0]) + absf(float(z[2])) * float(half.point[2])]
	for i in 3:
		if absf(float(center.point[i])) + enclosing[i] > Frame.MAX_CANONICAL_COMPONENT_M: return _fail("Oriented volume extends outside the finite canonical coordinate domain")
	return {"ok": true, "volume": {"schema": OBOX_SCHEMA, "volume_id": value.volume_id,
		"center_xyz": center.point, "half_extents_xyz": half.point, "axis_x_xyz": axis_x.point, "axis_z_xyz": axis_z.point, "dry": value.dry}}

## A floor registration is an architectural statement, not a collision lease.
## Unloading geometry does not erase the floor identity or turn it into void.
func register_floor(definition: Variant) -> bool:
	if not _configured or not _exact(definition, FLOOR_KEYS):
		last_error = "Invalid floor registration"
		return false
	if not _label(definition.feature_id) or not _label(definition.floor_id) or not _hash(definition.geometry_sha256) or not _label(definition.provenance):
		last_error = "Floor identity/geometry/provenance must be explicit"
		return false
	if typeof(definition.support_ids) != TYPE_ARRAY or definition.support_ids.is_empty() or definition.support_ids.size() > 4096 or typeof(definition.volumes) != TYPE_ARRAY or definition.volumes.is_empty() or definition.volumes.size() > 4096:
		last_error = "Floor support IDs and source volumes must be bounded nonempty arrays"
		return false
	var ids: Array[String] = []
	for id in definition.support_ids:
		if not _label(id) or ids.has(id):
			last_error = "Floor support IDs must be unique strings"
			return false
		ids.append(id)
	var volumes: Array[Dictionary] = []
	var volume_ids: Array[String] = []
	for value in definition.volumes:
		var parsed: Dictionary = _normal_volume(value)
		if not parsed.ok or volume_ids.has(parsed.volume.volume_id):
			last_error = "Invalid or duplicate floor source volume"
			return false
		volumes.append(parsed.volume)
		volume_ids.append(parsed.volume.volume_id)
	var key := _floor_key(definition.feature_id, definition.floor_id)
	if _floors.has(key):
		last_error = "Registered floor identity is immutable in this context"
		return false
	_floors[key] = {"feature_id": definition.feature_id, "floor_id": definition.floor_id,
		"geometry_sha256": definition.geometry_sha256, "support_ids": ids, "volumes": volumes, "provenance": definition.provenance}
	_registry_revision += 1
	last_error = ""
	return true

func floor_record(feature_id: Variant, floor_id: Variant) -> Dictionary:
	if not _label(feature_id) or not _label(floor_id): return _fail("Invalid requested floor identity")
	var key := _floor_key(feature_id, floor_id)
	return {"ok": true, "floor": _floors[key].duplicate(true)} if _floors.has(key) else _fail("Floor identity is not registered yet")

func _inside(point: Array, volume: Dictionary) -> bool:
	if volume.has("schema"): return _inside_obox(point, volume)
	for i in 3:
		if float(point[i]) < float(volume.min_xyz[i]) or float(point[i]) > float(volume.max_xyz[i]): return false
	return true

func _inside_obox(point: Array, volume: Dictionary) -> bool:
	# Subtract in canonical double space BEFORE projection; do not construct an
	# absolute Vector3, Basis or broad AABB. Source boxes are not actor transforms.
	var dx := float(point[0]) - float(volume.center_xyz[0])
	var dy := float(point[1]) - float(volume.center_xyz[1])
	var dz := float(point[2]) - float(volume.center_xyz[2])
	var along_x := dx * float(volume.axis_x_xyz[0]) + dz * float(volume.axis_x_xyz[2])
	var along_z := dx * float(volume.axis_z_xyz[0]) + dz * float(volume.axis_z_xyz[2])
	# Inclusive faces/corners need a bounded scalar roundoff allowance when a
	# canonical point near80km is constructed from a rotated edge. This is not
	# a gameplay/capsule margin: ~1e-10m for a10m box near80km, well below1mm.
	var magnitude := 1.0
	for i in 3: magnitude = maxf(magnitude, maxf(absf(float(point[i])), absf(float(volume.center_xyz[i]))))
	var epsilon := DOUBLE_ROUNDING_FACTOR * magnitude + OBOX_BASIS_TOLERANCE * (float(volume.half_extents_xyz[0]) + float(volume.half_extents_xyz[2]))
	return absf(along_x) <= float(volume.half_extents_xyz[0]) + epsilon and absf(dy) <= float(volume.half_extents_xyz[1]) + epsilon and absf(along_z) <= float(volume.half_extents_xyz[2]) + epsilon

func _floor_contains(floor: Dictionary, point: Array) -> bool:
	for volume: Dictionary in floor.volumes:
		if _inside(point, volume): return true
	return false

func _dry_matches(point: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for floor: Dictionary in _floors.values():
		for volume: Dictionary in floor.volumes:
			if volume.dry and _inside(point, volume): result.append({"feature_id": floor.feature_id, "floor_id": floor.floor_id, "volume_id": volume.volume_id, "provenance": floor.provenance})
	return result

## Query position means the actor's source-space root/foot pose, NOT an
## absolute Vector3. Support offsets and capsule shape are in the profile.
func begin_query(source_xyz: Variant) -> Dictionary:
	if not _configured: return _fail("Configure source context first")
	var point: Dictionary = _point(source_xyz)
	if not point.ok: return point
	var sample: Dictionary = _frame.project_source_sample(point.point)
	if not sample.ok: return sample
	var query: Dictionary = _identity.duplicate(true)
	query.merge({"schema": QUERY_SCHEMA, "origin_revision": _frame.metadata().origin_revision,
		"registry_revision": _registry_revision, "source_xyz": point.point, "local_sample": sample.sample,
		"physics_tick": Engine.get_physics_frames(), "physics_space_id": _space_id()})
	query["query_sha256"] = _digest(_without(query, ["local_sample", "query_sha256"]))
	return {"ok": true, "query": query}

func validate_query(query: Variant) -> Dictionary:
	if not _configured or not _exact(query, QUERY_KEYS): return _fail("Invalid context query schema")
	for key in ["schema", "frame_fingerprint", "snapshot_manifest_sha256", "geometry_manifest_sha256", "vertical_manifest_sha256", "profile_sha256", "query_sha256"]:
		if typeof(query[key]) != TYPE_STRING: return _fail("Invalid query identity type")
	if query.schema != QUERY_SCHEMA: return _fail("Wrong context query schema")
	for key in ["context_instance_id", "frame_instance_id", "origin_revision", "registry_revision", "physics_tick", "physics_space_id"]:
		if typeof(query[key]) != TYPE_INT: return _fail("Invalid query epoch type")
	for key in _identity:
		if query[key] != _identity[key]: return _fail("Query belongs to another context/frame/snapshot/profile")
	if query.origin_revision != _frame.metadata().origin_revision or query.registry_revision != _registry_revision or query.physics_space_id != _space_id() or query.physics_tick < 0: return _fail("Query context/registry/origin is stale")
	if typeof(query.source_xyz) != TYPE_ARRAY: return _fail("Query must retain its normalized canonical Array")
	var point: Dictionary = _point(query.source_xyz)
	var sample: Dictionary = _frame.sample_to_source(query.local_sample)
	if not point.ok or not sample.ok or point.point != sample.source_xyz: return _fail("Query canonical point/local sample mismatch")
	if query.query_sha256 != _digest(_without(query, ["local_sample", "query_sha256"])): return _fail("Query contents changed")
	return {"ok": true}

func _payload_error(kind: String, state: String, payload: Variant) -> String:
	if typeof(payload) != TYPE_DICTIONARY: return "Provider payload must be a dictionary"
	if kind == "territory":
		return "" if state in ["inside", "outside", "unknown"] and payload.is_empty() else "Invalid territory state"
	if kind == "land":
		return "" if state in ["land", "non_land", "unknown"] and payload.is_empty() else "Invalid land state"
	if kind == "water":
		if state in ["dry", "unknown"] and payload.is_empty(): return ""
		if state != "water_column" or not _exact(payload, ["body_id", "bottom_y", "surface_y"]) or not _label(payload.body_id): return "Invalid 3D water-column observation"
		if not _number(payload.bottom_y) or not _number(payload.surface_y): return "Water-column bounds must be finite"
		if float(payload.bottom_y) >= float(payload.surface_y) or absf(float(payload.bottom_y)) > Frame.MAX_CANONICAL_COMPONENT_M or absf(float(payload.surface_y)) > Frame.MAX_CANONICAL_COMPONENT_M: return "Water-column bounds are invalid"
		return ""
	if kind != "physics" or not state in ["resident", "unloaded", "unknown"]: return "Invalid physics-residency state"
	if state != "resident": return "" if payload.is_empty() else "Unloaded/unknown physics cannot supply a contact"
	if not _exact(payload, ["residency_token", "support", "clearance"]) or not _label(payload.residency_token): return "Resident physics requires its collision generation token"
	if typeof(payload.clearance) != TYPE_STRING or not payload.clearance in ["clear", "blocked", "unknown"]: return "Invalid capsule clearance"
	if typeof(payload.support) != TYPE_DICTIONARY or typeof(payload.support.get("state")) != TYPE_STRING: return "Invalid support observation"
	if payload.support.state in ["unsupported", "unknown"]: return "" if _exact(payload.support, ["state"]) else "Empty support cannot carry a collider"
	if payload.support.state != "supported" or not _exact(payload.support, CONTACT_KEYS): return "Invalid physical-support schema"
	for key in ["feature_id", "floor_id", "support_id"]:
		if not _label(payload.support[key]): return "Invalid support source identity"
	if typeof(payload.support.collider_instance_id) != TYPE_INT or payload.support.collider_instance_id <= 0: return "Support requires a live collider instance ID"
	if not _point(payload.support.contact_source_xyz).ok or not _point(payload.support.normal_source_xyz).ok: return "Support contact/normal must use canonical double arrays"
	return ""

## Adapter helper. Call only AFTER a fresh observation at this exact query.
## Hashes detect accidental mutation; they are not signatures or physics proof.
func bind_observation(query: Variant, kind: Variant, state: Variant, payload: Variant = {}) -> Dictionary:
	var checked: Dictionary = validate_query(query)
	if not checked.ok: return checked
	var canonical_kind := _provider_kind(kind)
	if canonical_kind.is_empty() or not _providers.has(canonical_kind) or typeof(state) != TYPE_STRING: return _fail("Require a registered explicit provider and typed state")
	var issue := _payload_error(canonical_kind, state, payload)
	if not issue.is_empty(): return _fail(issue)
	var observation: Dictionary = _without(query, ["local_sample"])
	observation.merge({"schema": OBSERVATION_SCHEMA, "provider_id": _providers[canonical_kind].provider_id,
		"kind": canonical_kind, "state": state, "payload": payload.duplicate(true)}, true)
	observation["observation_sha256"] = _digest(_without(observation, ["observation_sha256"]))
	return {"ok": true, "observation": observation}

func _validate_observation(query: Dictionary, kind: String, observation: Variant) -> Dictionary:
	if not _providers.has(kind) or not _exact(observation, OBSERVATION_KEYS): return _fail("Missing or malformed " + kind + " provider observation")
	for key in ["schema", "frame_fingerprint", "snapshot_manifest_sha256", "geometry_manifest_sha256", "vertical_manifest_sha256", "profile_sha256", "query_sha256", "provider_id", "kind", "state", "observation_sha256"]:
		if typeof(observation[key]) != TYPE_STRING: return _fail("Invalid provider identity/state type")
	for key in ["context_instance_id", "frame_instance_id", "origin_revision", "registry_revision", "physics_tick", "physics_space_id"]:
		if typeof(observation[key]) != TYPE_INT: return _fail("Invalid provider epoch type")
	if observation.schema != OBSERVATION_SCHEMA or observation.kind != kind or observation.provider_id != _providers[kind].provider_id: return _fail("Wrong provider/schema/kind")
	for key in QUERY_KEYS:
		if key in ["schema", "source_xyz", "local_sample"]: continue
		if observation[key] != query[key]: return _fail("Provider observation belongs to another query/snapshot/origin")
	var point: Dictionary = _point(observation.source_xyz)
	if not point.ok or point.point != query.source_xyz: return _fail("Provider point does not match query")
	var issue := _payload_error(kind, observation.state, observation.payload)
	if not issue.is_empty(): return _fail(issue)
	if observation.observation_sha256 != _digest(_without(observation, ["observation_sha256"])): return _fail("Provider observation contents changed")
	return {"ok": true}

## Stamp data only: caller attaches this to its OWN collider after its actual
## geometry transform/collision commit. This method moves/stamps no object.
func make_collider_stamp(feature_id: Variant, floor_id: Variant, support_id: Variant, residency_token: Variant) -> Dictionary:
	var record: Dictionary = floor_record(feature_id, floor_id)
	if not _configured or not record.ok or not _label(support_id) or not record.floor.support_ids.has(support_id) or not _label(residency_token) or _space_id() == 0: return _fail("Collider stamp requires registered floor/support, resident generation and physics world")
	var stamp: Dictionary = _identity.duplicate(true)
	stamp.merge({"origin_revision": _frame.metadata().origin_revision, "source_origin_xyz": _frame.metadata().source_origin_xyz,
		"physics_space_id": _space_id(), "feature_id": feature_id, "floor_id": floor_id,
		"support_id": support_id, "floor_geometry_sha256": record.floor.geometry_sha256, "residency_token": residency_token})
	return {"ok": true, "stamp": stamp}

func _same_stamp(value: Variant, expected: Dictionary) -> bool:
	if not _exact(value, expected.keys()): return false
	for key in expected:
		if key == "source_origin_xyz":
			var point: Dictionary = _point(value[key])
			if not point.ok or point.point != expected[key]: return false
		else:
			if typeof(value[key]) != typeof(expected[key]) or value[key] != expected[key]: return false
	return true

func _support_result(query: Dictionary, payload: Dictionary) -> Dictionary:
	var contact: Dictionary = payload.support
	if contact.state != "supported": return {"state": contact.state}
	var record: Dictionary = floor_record(contact.feature_id, contact.floor_id)
	if not record.ok or not record.floor.support_ids.has(contact.support_id): return {"state": "unknown", "reason": "Contact floor/support identity is not registered"}
	if not _floor_contains(record.floor, query.source_xyz): return {"state": "unknown", "reason": "Contact floor does not contain the source pose"}
	var stamp: Dictionary = make_collider_stamp(contact.feature_id, contact.floor_id, contact.support_id, payload.residency_token)
	if not stamp.ok: return {"state": "unknown", "reason": stamp.error}
	var collider: Variant = instance_from_id(contact.collider_instance_id)
	if not is_instance_valid(collider) or not collider is CollisionObject3D or not collider.is_inside_tree() or collider.collision_layer == 0: return {"state": "unknown", "reason": "Support collider no longer exists/enables collision in a scene"}
	if collider.get_world_3d().space.get_id() != query.physics_space_id or not collider.has_meta(COLLIDER_META) or not _same_stamp(collider.get_meta(COLLIDER_META), stamp.stamp): return {"state": "unknown", "reason": "Collider world/snapshot/geometry/origin stamp is stale"}
	var point: Array = _point(contact.contact_source_xyz).point
	var normal: Array = _point(contact.normal_source_xyz).point
	var normal_length_sq := float(normal[0]) * float(normal[0]) + float(normal[1]) * float(normal[1]) + float(normal[2]) * float(normal[2])
	var dx := float(point[0]) - float(query.source_xyz[0])
	var dz := float(point[2]) - float(query.source_xyz[2])
	var dy := float(query.source_xyz[1]) - float(point[1])
	if absf(normal_length_sq - 1.0) > 0.01 or float(normal[1]) < float(_profile.min_support_normal_y) or dx * dx + dz * dz > float(_profile.max_support_lateral_m) * float(_profile.max_support_lateral_m) or dy < -float(_profile.max_support_rise_m) or dy > float(_profile.max_support_drop_m): return {"state": "unknown", "reason": "Physical contact is outside the bounded foot/slope policy"}
	return {"state": "supported", "feature_id": contact.feature_id, "floor_id": contact.floor_id,
		"support_id": contact.support_id, "collider_instance_id": contact.collider_instance_id, "contact_source_xyz": point}

## Missing/stale/invalid observations become explicit unknowns, NEVER outside,
## dry land, unsupported void, a sea-plane kill, or permission to move an actor.
func evaluate(query: Variant, observations: Variant = {}) -> Dictionary:
	var checked: Dictionary = validate_query(query)
	if not checked.ok: return checked
	if typeof(observations) != TYPE_DICTIONARY: return _fail("Observations must be a dictionary keyed by provider kind")
	var canonical_observations: Dictionary = {}
	for key in observations:
		var kind := _provider_kind(key)
		if kind.is_empty() or canonical_observations.has(kind): return _fail("Unexpected or duplicate provider-observation kind")
		canonical_observations[kind] = observations[key]
	var result := {"ok": true, "source_xyz": query.source_xyz.duplicate(), "physics_tick": query.physics_tick,
		"origin_revision": query.origin_revision, "territory": {"state": "unknown"}, "land": {"state": "unknown"},
		"water": {"state": "unknown"}, "residency": {"state": "unknown"}, "support": {"state": "unknown"},
		"clearance": {"state": "unknown"}, "indoor": {"dry_volume_matches": _dry_matches(query.source_xyz)}, "unresolved": []}
	for kind: String in KINDS:
		var valid: Dictionary = _validate_observation(query, kind, canonical_observations.get(kind))
		if not valid.ok:
			result.unresolved.append({"kind": kind, "reason": valid.error})
			continue
		var observation: Dictionary = canonical_observations[kind]
		if kind in ["territory", "land"]:
			result[kind] = {"state": observation.state, "provider_id": observation.provider_id}
		elif kind == "water":
			result.water = {"state": observation.state, "provider_id": observation.provider_id}
			if observation.state == "water_column":
				var y: float = float(query.source_xyz[1])
				var body: Dictionary = observation.payload
				result.water = {"state": "submerged" if y >= float(body.bottom_y) and y <= float(body.surface_y) else ("above_surface" if y > float(body.surface_y) else "unknown"), "body_id": body.body_id, "bottom_y": float(body.bottom_y), "surface_y": float(body.surface_y)}
		else:
			if query.physics_tick != Engine.get_physics_frames() or _space_id() == 0:
				result.unresolved.append({"kind": "physics", "reason": "Physics observation is not from this live physics tick/world"})
				continue
			result.residency = {"state": observation.state}
			if observation.state == "resident":
				result.residency["residency_token"] = observation.payload.residency_token
				result.support = _support_result(query, observation.payload)
				result.clearance = {"state": observation.payload.clearance}
	result.indoor["state"] = "unregistered"
	if not result.indoor.dry_volume_matches.is_empty():
		var identities: Array[String] = []
		var supported_dry_floor := false
		for match_record: Dictionary in result.indoor.dry_volume_matches:
			var key := _floor_key(match_record.feature_id, match_record.floor_id)
			if not identities.has(key): identities.append(key)
			if result.support.state == "supported" and result.support.feature_id == match_record.feature_id and result.support.floor_id == match_record.floor_id: supported_dry_floor = true
		result.indoor.state = "dry_registered" if identities.size() == 1 or supported_dry_floor else "ambiguous_registered"
		result.water = {"state": "dry_indoor" if result.indoor.state == "dry_registered" else "unknown", "outdoor_water_observation": result.water.duplicate(true), "dry_volume_matches": result.indoor.dry_volume_matches.duplicate(true)}
	return result

## Versioned pose DATA only. Caller must derive IDs from its current supported
## floor, preserve the owner's old save bytes, and write through Game separately.
func make_restore_pose(source_xyz: Variant, heading_rad: Variant, feature_id: Variant, floor_id: Variant, room_id: Variant = "") -> Dictionary:
	if not _configured: return _fail("Configure source context first")
	var pose: Dictionary = _frame.make_source_pose(source_xyz, heading_rad, feature_id, floor_id, room_id)
	var record: Dictionary = floor_record(feature_id, floor_id)
	if not pose.ok or not record.ok: return _fail("Source save requires a registered named feature/floor")
	if not _floor_contains(record.floor, pose.pose.source_xyz): return _fail("Source save point is not within the registered floor volume")
	return {"ok": true, "pose": {"schema": RESTORE_SCHEMA, "source_pose": pose.pose,
		"geometry_manifest_sha256": _identity.geometry_manifest_sha256, "vertical_manifest_sha256": _identity.vertical_manifest_sha256,
		"floor_geometry_sha256": record.floor.geometry_sha256}}

func validate_restore_pose(saved: Variant) -> Dictionary:
	if not _configured or not _exact(saved, RESTORE_KEYS): return _fail("Require a source-context pose; legacy local saves are not source geography")
	if typeof(saved.schema) != TYPE_STRING or saved.schema != RESTORE_SCHEMA: return _fail("Wrong source-context save schema")
	for key in ["geometry_manifest_sha256", "vertical_manifest_sha256", "floor_geometry_sha256"]:
		if not _hash(saved[key]): return _fail("Source save version identities must be SHA256 strings")
	if saved.geometry_manifest_sha256 != _identity.geometry_manifest_sha256 or saved.vertical_manifest_sha256 != _identity.vertical_manifest_sha256: return _fail("Saved geometry/vertical dataset changed; explicit migration is required")
	var pose: Dictionary = _frame.validate_source_pose(saved.source_pose)
	if not pose.ok: return pose
	if not _label(pose.pose.feature_id) or not _label(pose.pose.floor_id): return _fail("Source restore requires named feature and floor identities")
	var normalized: Dictionary = saved.duplicate(true)
	normalized.source_pose = pose.pose
	return {"ok": true, "pose": normalized}

func prepare_restore(saved: Variant) -> Dictionary:
	var checked: Dictionary = validate_restore_pose(saved)
	if not checked.ok: return _invalid_restore(checked)
	var pose: Dictionary = checked.pose.source_pose
	var record: Dictionary = floor_record(pose.feature_id, pose.floor_id)
	if not record.ok: return {"ok": true, "status": "pending", "reason": "floor_identity_not_registered", "required_feature_id": pose.feature_id, "required_floor_id": pose.floor_id}
	if record.floor.geometry_sha256 != checked.pose.floor_geometry_sha256: return {"ok": true, "status": "blocked", "reason": "floor_geometry_version_changed"}
	if not _floor_contains(record.floor, pose.source_xyz): return {"ok": true, "status": "blocked", "reason": "pose_outside_registered_floor_volume"}
	var query: Dictionary = begin_query(pose.source_xyz)
	if not query.ok:
		return {"ok": true, "status": "pending", "reason": "origin_context_or_streaming_required", "detail": query.error}
	return {"ok": true, "status": "query_required", "query": query.query}

## Run immediately before an integrator applies a pose at its controlled physics
## boundary. A ready result is NOT permission to apply it on a later tick.
func preflight_restore(saved: Variant, query: Variant, observations: Variant = {}) -> Dictionary:
	var prepared: Dictionary = prepare_restore(saved)
	if not prepared.ok or prepared.status != "query_required": return prepared
	var checked: Dictionary = validate_query(query)
	if not checked.ok: return _invalid_restore(checked)
	var valid: Dictionary = validate_restore_pose(saved)
	if not valid.ok: return _invalid_restore(valid)
	var pose: Dictionary = valid.pose.source_pose
	if query.source_xyz != pose.source_xyz: return _invalid_restore(_fail("Restore observations belong to a different source point"))
	var state: Dictionary = evaluate(query, observations)
	if not state.ok: return _invalid_restore(state)
	var pending: Array[String] = []
	var blocked: Array[String] = []
	if state.territory.state == "outside": blocked.append("outside_covered_territory")
	elif state.territory.state == "unknown": pending.append("territory_unresolved")
	if state.residency.state != "resident": pending.append("required_collision_not_resident")
	if state.support.state == "unknown": pending.append("fresh_physical_support_required")
	elif state.support.state == "unsupported": blocked.append("no_support_at_saved_pose")
	elif state.support.feature_id != pose.feature_id or state.support.floor_id != pose.floor_id: blocked.append("physical_support_floor_identity_mismatch")
	if state.clearance.state == "unknown": pending.append("capsule_clearance_unresolved")
	elif state.clearance.state == "blocked": blocked.append("capsule_clearance_blocked")
	if state.water.state == "submerged": blocked.append("source_pose_submerged")
	elif not state.water.state in ["dry", "dry_indoor", "above_surface"]: pending.append("three_dimensional_water_unresolved")
	if not blocked.is_empty(): return {"ok": true, "status": "blocked", "reasons": blocked, "pending": pending, "state": state}
	if not pending.is_empty(): return {"ok": true, "status": "pending", "reasons": pending, "state": state}
	return {"ok": true, "status": "ready", "current_local_sample": query.local_sample.duplicate(true),
		"source_pose": pose.duplicate(true), "physics_tick": query.physics_tick, "query_sha256": query.query_sha256,
		"registry_revision": _registry_revision, "state": state, "actor_or_save_mutated": false}

## Pure coordination of checked cache previews. Root must stage ALL actors,
## cameras, physics transforms, interpolation, FX and consumers before commit.
func prepare_transition(new_source_origin: Variant, current_samples: Variant) -> Dictionary:
	if not _configured or typeof(current_samples) != TYPE_ARRAY or current_samples.size() > 4096: return _fail("Transition requires a bounded array of current checked samples")
	var prepared: Dictionary = _frame.prepare_rebase(new_source_origin)
	if not prepared.ok: return prepared
	var previews: Array[Dictionary] = []
	for sample in current_samples:
		var preview: Dictionary = _frame.sample_after_rebase(prepared.plan, sample)
		if not preview.ok: return preview
		previews.append(preview.preview)
	return {"ok": true, "plan": prepared.plan, "transition": {"schema": TRANSITION_SCHEMA, "context_instance_id": get_instance_id(),
		"registry_revision": _registry_revision, "plan_sha256": prepared.plan.plan_sha256, "previews": previews},
		"moves_or_commits_anything": false, "old_queries_and_collider_stamps_invalid_after_commit": true}

func activate_transition(transition: Variant) -> Dictionary:
	if not _configured or not _exact(transition, ["schema", "context_instance_id", "registry_revision", "plan_sha256", "previews"]): return _fail("Invalid context transition")
	if typeof(transition.schema) != TYPE_STRING or transition.schema != TRANSITION_SCHEMA or typeof(transition.context_instance_id) != TYPE_INT or transition.context_instance_id != get_instance_id() or typeof(transition.registry_revision) != TYPE_INT or transition.registry_revision != _registry_revision or typeof(transition.previews) != TYPE_ARRAY or transition.previews.size() > 4096: return _fail("Stale/foreign context transition")
	# The exact plan must already have committed. Frame validates every preview;
	# comparing its matching plan identity prevents mixing competing previews.
	if not _hash(transition.plan_sha256): return _fail("Transition plan identity is missing")
	var meta: Dictionary = _frame.metadata()
	if transition.plan_sha256 != meta.last_rebase_plan_sha256: return _fail("Commit the exact transition plan first")
	var samples: Array[Dictionary] = []
	for preview in transition.previews:
		if typeof(preview) != TYPE_DICTIONARY or typeof(preview.get("plan_sha256")) != TYPE_STRING or preview.plan_sha256 != transition.plan_sha256: return _fail("Transition preview belongs to another plan")
		var activated: Dictionary = _frame.activate_rebase_preview(preview)
		if not activated.ok: return activated
		samples.append(activated.sample)
	return {"ok": true, "samples": samples, "moves_or_commits_anything": false}
