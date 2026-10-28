class_name SingaporeSourceFrame
extends RefCounted
## Canonical source XYZ remains double-valued until its active origin has
## been subtracted. This class moves no actors, cameras, physics or FX.
const FRAME_SCHEMA := "singapore_source_frame_v1"
const REBASE_SCHEMA := "singapore_source_rebase_v1"
const POSE_SCHEMA := "singapore_source_pose_v1"
const LOCAL_SAMPLE_SCHEMA := "singapore_local_sample_v1"
const REBASE_PREVIEW_SCHEMA := "singapore_rebase_preview_v1"
const MAX_CANONICAL_COMPONENT_M := 10000000.0
const MAX_LOCAL_COMPONENT_M := 2048.0
const MAX_REBASE_COMPONENT_M := 1024.0
const RECOMMENDED_REBASE_COMPONENT_M := 512.0
const EXPECTED_FRAME := {
	"source_crs": "EPSG:4326", "survey_crs": "EPSG:3414",
	"origin_easting": 30000.0, "origin_northing": 30000.0,
	"world_axes": {"x": "south", "y": "up", "z": "west"},
	"metres_per_unit": 1.0, "distance_compression": false,
	"legacy_plan_alignment_applied": false,
}
const PLAN_KEYS := ["schema", "frame_instance_id", "frame_fingerprint", "snapshot_manifest_sha256",
	"from_revision", "to_revision", "origin_before", "origin_after", "canonical_delta_xyz",
	"translation_local", "plan_sha256"]
const POSE_KEYS := ["schema", "snapshot_manifest_sha256", "frame_fingerprint", "elevation_reference",
	"source_xyz", "heading_rad", "feature_id", "floor_id", "room_id"]
const SAMPLE_KEYS := ["schema", "frame_instance_id", "frame_fingerprint", "snapshot_manifest_sha256",
	"origin_revision", "source_origin_xyz", "source_xyz", "position", "sample_sha256"]
const PREVIEW_KEYS := ["schema", "frame_instance_id", "frame_fingerprint", "snapshot_manifest_sha256",
	"from_revision", "to_revision", "origin_before", "origin_after", "source_xyz", "position",
	"plan_sha256", "preview_sha256"]

var last_error := ""
var _configured := false
var _origin: Array[float] = []
var _revision := 0
var _snapshot := ""
var _fingerprint := ""
var _vertical: Dictionary = {}
var _last_commit_sha := ""
var _sha_re := RegEx.new()

func _init() -> void:
	_sha_re.compile("^[0-9a-f]{64}$")

func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

func _error(message: String, needs_new_context: bool = false) -> Dictionary:
	return {"ok": false, "error": message, "requires_new_context": needs_new_context}

func _point(value: Variant) -> Dictionary:
	# Reject Vector3/PackedFloat32Array: precision lost before entry cannot be
	# recovered by copying the values into a double container afterward.
	if not typeof(value) in [TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] or value.size() != 3:
		return _error("Canonical XYZ requires an Array or PackedFloat64Array of three numbers")
	var point: Array[float] = []
	for component in value:
		if not _number(component) or absf(float(component)) > MAX_CANONICAL_COMPONENT_M:
			return _error("Canonical coordinate is nonfinite or outside the supported source domain")
		point.append(float(component))
	return {"ok": true, "point": point}

func _has_exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

func _valid_frame(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not _has_exact_keys(value, EXPECTED_FRAME.keys()): return false
	# Validate types BEFORE equality. Godot raises script errors for some
	# mismatched Variant operands (for example bool != float); that exception
	# can otherwise look like a successful rejection to a boolean caller.
	for key in ["source_crs", "survey_crs"]:
		if typeof(value[key]) != TYPE_STRING: return false
		if value[key] != EXPECTED_FRAME[key]: return false
	for key in ["origin_easting", "origin_northing", "metres_per_unit"]:
		if not _number(value[key]): return false
		if float(value[key]) != float(EXPECTED_FRAME[key]): return false
	for key in ["distance_compression", "legacy_plan_alignment_applied"]:
		if typeof(value[key]) != TYPE_BOOL: return false
		if value[key] != false: return false
	if typeof(value.world_axes) != TYPE_DICTIONARY or not _has_exact_keys(value.world_axes, ["x", "y", "z"]): return false
	for axis in ["x", "y", "z"]:
		if typeof(value.world_axes[axis]) != TYPE_STRING: return false
		if value.world_axes[axis] != EXPECTED_FRAME.world_axes[axis]: return false
	return true

func _normal_vertical(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY: return _error("Elevation reference requires explicit dictionary metadata")
	for key in value:
		if typeof(key) != TYPE_STRING or not key in ["status", "reference", "source_reference"]: return _error("Unknown elevation-reference field")
	var status: Variant = value.get("status", "unknown")
	var reference: Variant = value.get("reference", "UNRESOLVED")
	var source: Variant = value.get("source_reference", "")
	if typeof(status) != TYPE_STRING or not status in ["unknown", "staging", "source_tag", "surveyed"]:
		return _error("Unknown elevation-reference status")
	if typeof(reference) != TYPE_STRING or reference.is_empty() or reference.length() > 160:
		return _error("Elevation reference name is missing or too long")
	if typeof(source) != TYPE_STRING or source.length() > 512: return _error("Elevation source reference is invalid")
	return {"ok": true, "value": {"status": status, "reference": reference, "source_reference": source}}

func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

## One configuration per object. A different dataset/frame needs a new context.
func configure(frame: Variant, source_origin_xyz: Variant, snapshot_manifest_sha256: Variant, elevation_reference: Variant = {}) -> bool:
	if _configured:
		last_error = "Frame identity is immutable; create a new context"
		return false
	if not _valid_frame(frame):
		last_error = "Require the exact uncompressed EPSG:3414 source frame and axes"
		return false
	if typeof(snapshot_manifest_sha256) != TYPE_STRING or _sha_re.search(snapshot_manifest_sha256) == null:
		last_error = "Snapshot manifest identity must be a lowercase SHA256"
		return false
	var point := _point(source_origin_xyz)
	var vertical := _normal_vertical(elevation_reference)
	if not point.ok or not vertical.ok:
		last_error = point.error if not point.ok else vertical.error
		return false
	var identity := {"schema": FRAME_SCHEMA, "georeference": EXPECTED_FRAME,
		"snapshot_manifest_sha256": snapshot_manifest_sha256, "elevation_reference": vertical.value}
	# Fingerprint intentionally excludes active origin/revision/object ID, so a
	# canonical pose can be restored in a NEW local origin for the SAME dataset.
	var fingerprint := _sha(JSON.stringify(identity, "", true, true).to_utf8_buffer())
	_origin.assign(point.point)
	_snapshot = snapshot_manifest_sha256
	_vertical = vertical.value.duplicate(true)
	_fingerprint = fingerprint
	_configured = true
	last_error = ""
	return true

func metadata() -> Dictionary:
	return {"configured": _configured, "schema": FRAME_SCHEMA, "georeference": EXPECTED_FRAME.duplicate(true),
		"snapshot_manifest_sha256": _snapshot, "frame_fingerprint": _fingerprint,
		"source_origin_xyz": _origin.duplicate(), "origin_revision": _revision,
		"last_rebase_plan_sha256": _last_commit_sha,
		"elevation_reference": _vertical.duplicate(true), "elevation_verified_by_module": false,
		"max_local_component_m": MAX_LOCAL_COMPONENT_M, "max_rebase_component_m": MAX_REBASE_COMPONENT_M,
		"recommended_rebase_component_m": RECOMMENDED_REBASE_COMPONENT_M}

## Immediate projection; subtraction occurs before Vector3 creation. Retained
## coordinates must use project_source_sample rather than caching this vector.
func to_local(source_xyz: Variant) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	var parsed := _point(source_xyz)
	if not parsed.ok: return parsed
	var delta: Array[float] = []
	for i in 3:
		var component: float = float(parsed.point[i]) - _origin[i]
		if absf(component) > MAX_LOCAL_COMPONENT_M:
			var failure := _error("Source point is outside the bounded local window")
			failure["requires_rebase"] = true
			return failure
		delta.append(component)
	return {"ok": true, "position": Vector3(delta[0], delta[1], delta[2]), "origin_revision": _revision}

## Bare vectors have NO epoch/context evidence. This operation is ONLY for
## a current live physics value; retained caches must use local samples.
func to_source_current_live(local_position: Variant) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	if typeof(local_position) != TYPE_VECTOR3: return _error("Local positions require a Vector3")
	var position: Vector3 = local_position
	if not position.is_finite() or maxf(absf(position.x), maxf(absf(position.y), absf(position.z))) > MAX_LOCAL_COMPONENT_M:
		return _error("Local point is nonfinite or outside the bounded local window")
	var point: Array[float] = [_origin[0] + float(position.x), _origin[1] + float(position.y), _origin[2] + float(position.z)]
	var parsed := _point(point)
	if not parsed.ok: return parsed
	return {"ok": true, "source_xyz": point, "origin_revision": _revision,
		"epoch_validation": "unavailable_for_bare_vector_current_live_only"}

func _project_at(point: Array, origin: Array) -> Dictionary:
	var relative: Array[float] = []
	for i in 3:
		var component: float = float(point[i]) - float(origin[i])
		if absf(component) > MAX_LOCAL_COMPONENT_M:
			var failure := _error("Sample projection is outside the bounded local window")
			failure["requires_stream_out"] = true
			return failure
		relative.append(component)
	return {"ok": true, "position": Vector3(relative[0], relative[1], relative[2])}

func _sample_digest(sample: Dictionary) -> String:
	var position: Vector3 = sample.position
	var payload := {"schema": sample.schema, "frame_instance_id": sample.frame_instance_id,
		"frame_fingerprint": sample.frame_fingerprint, "snapshot_manifest_sha256": sample.snapshot_manifest_sha256,
		"origin_revision": sample.origin_revision, "source_origin_xyz": sample.source_origin_xyz,
		"source_xyz": sample.source_xyz, "position_xyz": [float(position.x), float(position.y), float(position.z)]}
	return _sha(JSON.stringify(payload, "", true, true).to_utf8_buffer())

func _make_current_sample(source: Array) -> Dictionary:
	var projected := _project_at(source, _origin)
	if not projected.ok: return projected
	var sample := {"schema": LOCAL_SAMPLE_SCHEMA, "frame_instance_id": get_instance_id(),
		"frame_fingerprint": _fingerprint, "snapshot_manifest_sha256": _snapshot,
		"origin_revision": _revision, "source_origin_xyz": _origin.duplicate(),
		"source_xyz": source.duplicate(), "position": projected.position}
	sample["sample_sha256"] = _sample_digest(sample)
	return {"ok": true, "sample": sample}

## Only capture values read from CURRENT live physics. Re-capturing a stale
## bare vector cannot recover its lost epoch; keep the original sample.
func capture_current_local(local_position: Variant) -> Dictionary:
	var source := to_source_current_live(local_position)
	if not source.ok: return source
	return _make_current_sample(source.source_xyz)

func project_source_sample(source_xyz: Variant) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	var source := _point(source_xyz)
	if not source.ok: return source
	return _make_current_sample(source.point)

func validate_local_sample(sample: Variant) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	if typeof(sample) != TYPE_DICTIONARY or not _has_exact_keys(sample, SAMPLE_KEYS): return _error("Require a checked local-sample envelope")
	for field in ["schema", "frame_fingerprint", "snapshot_manifest_sha256", "sample_sha256"]:
		if typeof(sample[field]) != TYPE_STRING: return _error("Invalid local-sample identity type")
	if sample.schema != LOCAL_SAMPLE_SCHEMA: return _error("A future preview is not a current local sample")
	if typeof(sample.frame_instance_id) != TYPE_INT or sample.frame_instance_id != get_instance_id(): return _error("Local sample belongs to another context")
	if sample.frame_fingerprint != _fingerprint or sample.snapshot_manifest_sha256 != _snapshot: return _error("Local-sample snapshot/frame mismatch")
	if typeof(sample.origin_revision) != TYPE_INT or sample.origin_revision != _revision: return _error("Local sample is stale or from a future origin revision")
	if typeof(sample.source_origin_xyz) != TYPE_ARRAY or typeof(sample.source_xyz) != TYPE_ARRAY: return _error("Local sample requires double Array coordinates")
	var origin := _point(sample.source_origin_xyz)
	var source := _point(sample.source_xyz)
	if not origin.ok or not source.ok: return _error("Invalid local-sample coordinates")
	if origin.point != _origin: return _error("Local-sample origin does not match the current revision")
	if typeof(sample.position) != TYPE_VECTOR3: return _error("Local sample projection must be a Vector3")
	var projected := _project_at(source.point, origin.point)
	if not projected.ok: return projected
	if not sample.position.is_finite() or sample.position != projected.position: return _error("Local-sample projection does not match its canonical point")
	if sample.sample_sha256 != _sample_digest(sample): return _error("Local-sample content checksum mismatch")
	return {"ok": true}

func sample_to_source(sample: Variant) -> Dictionary:
	var checked := validate_local_sample(sample)
	if not checked.ok: return checked
	return {"ok": true, "source_xyz": sample.source_xyz.duplicate(), "origin_revision": _revision}

func sample_to_local(sample: Variant) -> Dictionary:
	var checked := validate_local_sample(sample)
	if not checked.ok: return checked
	return {"ok": true, "position": sample.position, "origin_revision": _revision}

func _preview_digest(preview: Dictionary) -> String:
	var position: Vector3 = preview.position
	var payload := {"schema": preview.schema, "frame_instance_id": preview.frame_instance_id,
		"frame_fingerprint": preview.frame_fingerprint, "snapshot_manifest_sha256": preview.snapshot_manifest_sha256,
		"from_revision": preview.from_revision, "to_revision": preview.to_revision,
		"origin_before": preview.origin_before, "origin_after": preview.origin_after,
		"source_xyz": preview.source_xyz, "position_xyz": [float(position.x), float(position.y), float(position.z)],
		"plan_sha256": preview.plan_sha256}
	return _sha(JSON.stringify(payload, "", true, true).to_utf8_buffer())

func _validate_preview_shape(preview: Variant) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	if typeof(preview) != TYPE_DICTIONARY or not _has_exact_keys(preview, PREVIEW_KEYS): return _error("Invalid rebase-preview envelope")
	for field in ["schema", "frame_fingerprint", "snapshot_manifest_sha256", "plan_sha256", "preview_sha256"]:
		if typeof(preview[field]) != TYPE_STRING: return _error("Invalid preview identity type")
	if preview.schema != REBASE_PREVIEW_SCHEMA: return _error("Require a rebase-preview schema")
	if typeof(preview.frame_instance_id) != TYPE_INT or preview.frame_instance_id != get_instance_id(): return _error("Preview belongs to another context")
	if preview.frame_fingerprint != _fingerprint or preview.snapshot_manifest_sha256 != _snapshot: return _error("Preview snapshot/frame mismatch")
	if typeof(preview.from_revision) != TYPE_INT or typeof(preview.to_revision) != TYPE_INT: return _error("Preview revisions must be integers")
	if preview.from_revision < 0 or preview.to_revision != preview.from_revision + 1: return _error("Invalid preview revision transition")
	for field in ["origin_before", "origin_after", "source_xyz"]:
		if typeof(preview[field]) != TYPE_ARRAY: return _error("Preview requires double Array coordinates")
	var before := _point(preview.origin_before)
	var after := _point(preview.origin_after)
	var source := _point(preview.source_xyz)
	if not before.ok or not after.ok or not source.ok: return _error("Invalid preview coordinates")
	var delta: Array[float] = _delta(before.point, after.point)
	if delta == [0.0, 0.0, 0.0]: return _error("Preview requires a nonzero bounded rebase")
	for component in delta:
		if absf(component) > MAX_REBASE_COMPONENT_M: return _error("Preview translation exceeds the supported budget")
	var expected_plan := {"schema": REBASE_SCHEMA, "frame_instance_id": preview.frame_instance_id,
		"frame_fingerprint": preview.frame_fingerprint, "snapshot_manifest_sha256": preview.snapshot_manifest_sha256,
		"from_revision": preview.from_revision, "to_revision": preview.to_revision,
		"origin_before": before.point, "origin_after": after.point,
		"canonical_delta_xyz": delta, "translation_local": Vector3(delta[0], delta[1], delta[2])}
	if preview.plan_sha256 != _plan_digest(expected_plan): return _error("Preview origins/revisions do not reproduce the claimed plan")
	if typeof(preview.position) != TYPE_VECTOR3: return _error("Preview position must be a Vector3")
	var projected := _project_at(source.point, after.point)
	if not projected.ok: return projected
	if not preview.position.is_finite() or preview.position != projected.position: return _error("Preview projection was changed")
	if preview.preview_sha256 != _preview_digest(preview): return _error("Preview content checksum mismatch")
	return {"ok": true}

## Produces a FUTURE preview, not an immediately consumable sample.
func sample_after_rebase(plan: Variant, sample: Variant) -> Dictionary:
	var checked := validate_rebase(plan)
	if not checked.ok: return checked
	checked = validate_local_sample(sample)
	if not checked.ok: return checked
	var projected := _project_at(sample.source_xyz, plan.origin_after)
	if not projected.ok: return projected
	var preview := {"schema": REBASE_PREVIEW_SCHEMA, "frame_instance_id": get_instance_id(),
		"frame_fingerprint": _fingerprint, "snapshot_manifest_sha256": _snapshot,
		"from_revision": plan.from_revision, "to_revision": plan.to_revision,
		"origin_before": plan.origin_before.duplicate(), "origin_after": plan.origin_after.duplicate(),
		"source_xyz": sample.source_xyz.duplicate(), "position": projected.position, "plan_sha256": plan.plan_sha256}
	preview["preview_sha256"] = _preview_digest(preview)
	return {"ok": true, "preview": preview, "not_current_until_matching_commit_and_activation": true}

func validate_rebase_preview(plan: Variant, preview: Variant) -> Dictionary:
	var checked := validate_rebase(plan)
	if not checked.ok: return checked
	checked = _validate_preview_shape(preview)
	if not checked.ok: return checked
	if preview.from_revision != plan.from_revision or preview.to_revision != plan.to_revision or preview.origin_before != plan.origin_before or preview.origin_after != plan.origin_after or preview.plan_sha256 != plan.plan_sha256:
		return _error("Preview does not belong to this rebase plan")
	return {"ok": true}

## A preview cannot become a current sample until its exact plan committed.
func activate_rebase_preview(preview: Variant) -> Dictionary:
	var checked := _validate_preview_shape(preview)
	if not checked.ok: return checked
	if preview.to_revision != _revision or preview.origin_after != _origin or preview.plan_sha256 != _last_commit_sha:
		return _error("Commit the matching plan before activating this preview")
	return _make_current_sample(preview.source_xyz)

func svy21_to_source(easting: Variant, northing: Variant, elevation: Variant = 0.0) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	if not _number(easting) or not _number(northing) or not _number(elevation): return _error("SVY21 requires finite E/N/elevation numbers")
	var parsed := _point([30000.0 - float(northing), float(elevation), 30000.0 - float(easting)])
	return {"ok": true, "source_xyz": parsed.point} if parsed.ok else parsed

func source_to_svy21(source_xyz: Variant) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	var parsed := _point(source_xyz)
	if not parsed.ok: return parsed
	return {"ok": true, "svy21_enh": [30000.0 - float(parsed.point[2]), 30000.0 - float(parsed.point[0]), float(parsed.point[1])]}

func _delta(before: Array, after: Array) -> Array[float]:
	return [float(before[0]) - float(after[0]), float(before[1]) - float(after[1]), float(before[2]) - float(after[2])]

func _plan_digest(plan: Dictionary) -> String:
	var t: Vector3 = plan.translation_local
	var payload := {"schema": plan.schema, "frame_instance_id": plan.frame_instance_id,
		"frame_fingerprint": plan.frame_fingerprint, "snapshot_manifest_sha256": plan.snapshot_manifest_sha256,
		"from_revision": plan.from_revision, "to_revision": plan.to_revision,
		"origin_before": plan.origin_before, "origin_after": plan.origin_after,
		"canonical_delta_xyz": plan.canonical_delta_xyz, "translation_local_xyz": [float(t.x), float(t.y), float(t.z)]}
	return _sha(JSON.stringify(payload, "", true, true).to_utf8_buffer())

## Pure prepare: no pending-plan registry and no origin/revision mutation.
func prepare_rebase(new_source_origin_xyz: Variant) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	var target := _point(new_source_origin_xyz)
	if not target.ok: return target
	var delta: Array[float] = _delta(_origin, target.point)
	if delta == [0.0, 0.0, 0.0]: return _error("A zero translation does not require a rebase")
	for component in delta:
		if absf(component) > MAX_REBASE_COMPONENT_M:
			return _error("Rebase exceeds bounded translation; load a new context for a large jump", true)
	var plan := {"schema": REBASE_SCHEMA, "frame_instance_id": get_instance_id(),
		"frame_fingerprint": _fingerprint, "snapshot_manifest_sha256": _snapshot,
		"from_revision": _revision, "to_revision": _revision + 1,
		"origin_before": _origin.duplicate(), "origin_after": target.point.duplicate(),
		"canonical_delta_xyz": delta, "translation_local": Vector3(delta[0], delta[1], delta[2])}
	plan["plan_sha256"] = _plan_digest(plan)
	return {"ok": true, "plan": plan}

## This validates accidental mutation/staleness, not adversarial authorization.
func validate_rebase(plan: Variant) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	if typeof(plan) != TYPE_DICTIONARY or not _has_exact_keys(plan, PLAN_KEYS): return _error("Invalid rebase plan schema/fields")
	for field in ["schema", "frame_fingerprint", "snapshot_manifest_sha256", "plan_sha256"]:
		if typeof(plan[field]) != TYPE_STRING: return _error("Rebase identity/checksum fields must be strings")
	if plan.schema != REBASE_SCHEMA or typeof(plan.frame_instance_id) != TYPE_INT:
		return _error("Rebase plan belongs to another context")
	if plan.frame_instance_id != get_instance_id():
		return _error("Rebase plan belongs to another context")
	if plan.frame_fingerprint != _fingerprint or plan.snapshot_manifest_sha256 != _snapshot: return _error("Rebase identity mismatch")
	if typeof(plan.from_revision) != TYPE_INT or typeof(plan.to_revision) != TYPE_INT or plan.from_revision != _revision or plan.to_revision != _revision + 1:
		return _error("Rebase plan is stale or already applied")
	for field in ["origin_before", "origin_after", "canonical_delta_xyz"]:
		if typeof(plan[field]) != TYPE_ARRAY: return _error("Rebase plans require their original double Array fields")
	var before := _point(plan.origin_before)
	var after := _point(plan.origin_after)
	var given_delta := _point(plan.canonical_delta_xyz)
	if not before.ok or not after.ok or not given_delta.ok or before.point != _origin: return _error("Rebase source origins/delta are invalid")
	var delta: Array[float] = _delta(before.point, after.point)
	if delta == [0.0, 0.0, 0.0] or given_delta.point != delta: return _error("Rebase translation differs from its source origins")
	for component in delta:
		if absf(component) > MAX_REBASE_COMPONENT_M: return _error("Rebase exceeds bounded translation", true)
	if typeof(plan.translation_local) != TYPE_VECTOR3: return _error("Rebase local translation must be a Vector3")
	if not plan.translation_local.is_finite() or plan.translation_local != Vector3(delta[0], delta[1], delta[2]):
		return _error("Rebase local translation was changed")
	if plan.plan_sha256 != _plan_digest(plan): return _error("Rebase plan content checksum mismatch")
	return {"ok": true}

## Bare-vector helper ONLY for a CURRENT live physics value. It cannot
## detect old cache epochs; use sample_after_rebase for retained samples.
func local_after_rebase_current_live(plan: Variant, old_local_position: Variant) -> Dictionary:
	var checked := validate_rebase(plan)
	if not checked.ok: return checked
	var source := to_source_current_live(old_local_position)
	if not source.ok: return source
	var relative: Array[float] = []
	for i in 3:
		var component: float = float(source.source_xyz[i]) - float(plan.origin_after[i])
		if absf(component) > MAX_LOCAL_COMPONENT_M:
			var failure := _error("Rebased cache would leave the bounded local window; stream it out using canonical state")
			failure["requires_stream_out"] = true
			return failure
		relative.append(component)
	return {"ok": true, "position": Vector3(relative[0], relative[1], relative[2]),
		"source_xyz": source.source_xyz, "origin_revision": plan.to_revision,
		"epoch_validation": "unavailable_for_bare_vector_current_live_only"}

## Mutates ONLY this coordinate frame. The integrator must atomically shift
## all local state at one controlled physics boundary. Native translation
## vectors can round. Retained coordinates use checked sample/preview
## activation; bare current-live operations provide no cache epoch proof.
func commit_rebase(plan: Variant) -> bool:
	var checked := validate_rebase(plan)
	if not checked.ok:
		last_error = checked.error
		return false
	_origin.assign(plan.origin_after)
	_revision += 1
	_last_commit_sha = plan.plan_sha256
	last_error = ""
	return true

## Source-centric pose envelope only, NOT integration into Game's save schema.
func make_source_pose(source_xyz: Variant, heading_rad: Variant, feature_id: Variant = "", floor_id: Variant = "", room_id: Variant = "") -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	var point := _point(source_xyz)
	if not point.ok: return point
	if not _number(heading_rad) or absf(float(heading_rad)) > 1000000.0: return _error("Invalid finite heading")
	for label in [feature_id, floor_id, room_id]:
		if typeof(label) != TYPE_STRING or label.length() > 256: return _error("Invalid source feature/floor/room identifier")
	return {"ok": true, "pose": {"schema": POSE_SCHEMA, "snapshot_manifest_sha256": _snapshot,
		"frame_fingerprint": _fingerprint, "elevation_reference": _vertical.duplicate(true),
		"source_xyz": point.point.duplicate(), "heading_rad": float(heading_rad),
		"feature_id": feature_id, "floor_id": floor_id, "room_id": room_id}}

func validate_source_pose(pose: Variant) -> Dictionary:
	if not _configured: return _error("Configure a source frame first")
	if typeof(pose) != TYPE_DICTIONARY or not _has_exact_keys(pose, POSE_KEYS):
		return _error("Require a versioned canonical source pose; legacy local saves are not source coordinates")
	for field in ["schema", "snapshot_manifest_sha256", "frame_fingerprint"]:
		if typeof(pose[field]) != TYPE_STRING: return _error("Source pose identity fields must be strings")
	if pose.schema != POSE_SCHEMA:
		return _error("Require a versioned canonical source pose; legacy local saves are not source coordinates")
	if typeof(pose.elevation_reference) != TYPE_DICTIONARY or not _has_exact_keys(pose.elevation_reference, ["status", "reference", "source_reference"]):
		return _error("Source pose requires explicit elevation-reference identity")
	var vertical := _normal_vertical(pose.elevation_reference)
	if not vertical.ok: return vertical
	# Both dictionaries now contain only normalized string values.
	if pose.snapshot_manifest_sha256 != _snapshot or pose.frame_fingerprint != _fingerprint or vertical.value != _vertical:
		return _error("Source pose snapshot/frame/elevation identity mismatch")
	return make_source_pose(pose.source_xyz, pose.heading_rad, pose.feature_id, pose.floor_id, pose.room_id)
