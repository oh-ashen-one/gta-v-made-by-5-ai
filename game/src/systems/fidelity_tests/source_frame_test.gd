extends Node
## Coordinate/identity arithmetic only. No world, actors, physics or save slot.
const Frame = preload("res://src/world/geography/source_frame.gd")
const SNAPSHOT := "res://data/geography/osm-2026-10-27/manifest.json"
const REPORT_NAME := "source-frame-report.json"
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var output := ""
var qa_session := ""
var _finished := false

func check(label: String, ok: bool, detail: String = "") -> bool:
	checks += 1
	print("[source-frame] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok: failures.append(label)
	return ok

func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

func _owned(path: String) -> bool:
	if path != path.simplify_path() or not path.begins_with("/private/tmp/singapore-fidelity/"): return false
	var parent := "/private/tmp"
	var parts := path.trim_prefix("/private/tmp/").split("/", false)
	for i in parts.size():
		var part: String = parts[i]
		var folder := DirAccess.open(parent)
		if folder == null or folder.is_link(part): return false
		var next := parent.path_join(part)
		if not folder.dir_exists(part):
			# Only a missing final session component is allowed; its verified
			# parent must already exist. Regular files/dangling links refuse.
			return i == parts.size() - 1 and not _entry_present(next)
		parent = next
	return true

## Directory enumeration notices existing entries without opening/following
## the report leaf. FileAccess.file_exists alone misses dangling symlinks.
func _entry_present(path: String) -> bool:
	var folder := DirAccess.open(path.get_base_dir())
	if folder == null: return true # Failure to prove absence is a refusal.
	var leaf := path.get_file()
	if folder.is_link(leaf): return true
	folder.include_hidden = true
	if folder.list_dir_begin() != OK: return true
	for i in 4096:
		var entry := folder.get_next()
		if entry.is_empty():
			folder.list_dir_end()
			return false
		if entry == leaf:
			folder.list_dir_end()
			return true
	folder.list_dir_end()
	return true # Oversized/unreadable evidence directory fails closed.

func _report_path_error(session: String, require_fresh_session: bool) -> String:
	if not _owned(session): return "QA session has an unsafe path, ancestor or entry"
	if require_fresh_session:
		if _entry_present(session): return "QA session must be fresh; existing entries are refused"
		return ""
	if not DirAccess.dir_exists_absolute(session): return "QA session directory disappeared"
	if _entry_present(session.path_join(REPORT_NAME)): return "Report leaf already exists or is a link"
	return ""

func _write_guarded_report(session: String, destination: String, content: String) -> Dictionary:
	if destination != session.path_join(REPORT_NAME): return {"ok": false, "error": "Output no longer matches its checked report path"}
	var path_error := _report_path_error(session, false)
	if not path_error.is_empty(): return {"ok": false, "error": path_error}
	# Immediate recheck above is an ownership guard, not an O_EXCL primitive.
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "Cannot create source-frame report"}
	file.store_string(content)
	file.flush()
	var complete := file.get_error() == OK and file.get_length() == content.to_utf8_buffer().size()
	file.close()
	return {"ok": true} if complete else {"ok": false, "error": "Incomplete source-frame report write"}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at < 0 or at + 1 >= args.size():
		push_error("Source-frame test requires an explicit private --qa-session")
		get_tree().quit(2)
		return
	var qa: String = args[at + 1]
	if qa.begins_with("/tmp/"): qa = "/private/tmp/" + qa.trim_prefix("/tmp/")
	if not _report_path_error(qa, true).is_empty() or DirAccess.make_dir_absolute(qa) != OK or not _report_path_error(qa, false).is_empty():
		push_error("Source-frame test refuses unsafe paths or existing evidence")
		get_tree().quit(2)
		return
	qa_session = qa
	output = qa.path_join(REPORT_NAME)
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.ignore_time_scale = true
	add_child(watchdog)
	watchdog.timeout.connect(func():
		if not _finished:
			check("bounded coordinate test completion", false, "20-second watchdog")
			_finish())
	watchdog.start(20.0)
	_run.call_deferred()

func _error_m(a: Array, b: Array) -> float:
	var error := 0.0
	for i in 3: error = maxf(error, absf(float(a[i]) - float(b[i])))
	return error

func _run() -> void:
	_qa_path_guard_checks()
	var bytes := FileAccess.get_file_as_bytes(SNAPSHOT)
	var manifest: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not check("actual snapshot frame exists", typeof(manifest) == TYPE_DICTIONARY and typeof(manifest.get("georeference")) == TYPE_DICTIONARY):
		_finish()
		return
	var definition: Dictionary = manifest.georeference.duplicate(true)
	var snapshot := _sha(bytes)
	metrics["actual_manifest_sha256"] = snapshot
	metrics["actual_source_snapshot_utc"] = manifest.get("source_snapshot_utc")
	_configuration_checks(definition, snapshot)
	_adversarial_type_checks(definition, snapshot)
	_precision_and_axes_checks(definition, snapshot)
	_rebase_transaction_checks(definition, snapshot)
	_repeated_rebase_checks(definition, snapshot)
	_checked_cache_checks(definition, snapshot)
	_pose_checks(definition, snapshot)
	_finish()

func _fixture_sentinel(path: String, content: String) -> bool:
	if not path.begins_with(qa_session.path_join("path-guard-fixtures") + "/") or not _owned(path.get_base_dir()) or _entry_present(path): return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(content)
	file.close()
	return true

func _qa_path_guard_checks() -> void:
	var root := qa_session.path_join("path-guard-fixtures")
	if not check("own QA guard fixture directory creates", DirAccess.make_dir_absolute(root) == OK): return
	var directory := DirAccess.open(root)
	if not check("own QA guard fixture directory opens", directory != null): return
	var sentinel := "SOURCE_FRAME_OWN_SCRATCH_SENTINEL_DO_NOT_MODIFY"
	var target_dir := root.path_join("directory-target")
	DirAccess.make_dir_absolute(target_dir)
	var target_report := target_dir.path_join(REPORT_NAME)
	if not check("own directory-link sentinel writes", _fixture_sentinel(target_report, sentinel)): return
	var link := root.path_join("directory-link")
	if not check("own directory-link fixture creates", directory.create_link(target_dir, link) == OK): return
	check("session-directory symlink is refused by actual writer", not _write_guarded_report(link, link.path_join(REPORT_NAME), "MUST_NOT_OVERWRITE").ok)
	check("directory-link target sentinel stays unchanged", FileAccess.get_file_as_string(target_report) == sentinel)
	var dangling_dir := root.path_join("dangling-report-session")
	DirAccess.make_dir_absolute(dangling_dir)
	var missing_target := root.path_join("never-created-target.json")
	var dangling_leaf := dangling_dir.path_join(REPORT_NAME)
	if not check("own dangling report-leaf fixture creates", directory.create_link(missing_target, dangling_leaf) == OK): return
	check("dangling report-leaf link is refused by actual writer", not _write_guarded_report(dangling_dir, dangling_leaf, "MUST_NOT_CREATE_TARGET").ok)
	check("dangling target stays absent and link stays intact", not _entry_present(missing_target) and DirAccess.open(dangling_dir).is_link(REPORT_NAME))
	var regular_dir := root.path_join("existing-report-session")
	DirAccess.make_dir_absolute(regular_dir)
	var regular_leaf := regular_dir.path_join(REPORT_NAME)
	if not check("own existing-report sentinel writes", _fixture_sentinel(regular_leaf, sentinel)): return
	check("existing regular report is refused by actual writer", not _write_guarded_report(regular_dir, regular_leaf, "MUST_NOT_OVERWRITE").ok)
	check("existing report sentinel stays unchanged", FileAccess.get_file_as_string(regular_leaf) == sentinel)
	var directory_leaf_session := root.path_join("directory-report-session")
	if not check("own report-directory session creates", DirAccess.make_dir_absolute(directory_leaf_session) == OK): return
	if not check("own existing report-directory leaf creates", DirAccess.make_dir_absolute(directory_leaf_session.path_join(REPORT_NAME)) == OK): return
	check("existing report directory is refused by actual writer", not _write_guarded_report(directory_leaf_session, directory_leaf_session.path_join(REPORT_NAME), "MUST_NOT_WRITE").ok)
	check("existing QA session cannot be reused even without report", not _report_path_error(qa_session, true).is_empty())
	var late := root.path_join("late-leaf-session")
	check("fresh owned session path is eligible initially", _report_path_error(late, true).is_empty())
	DirAccess.make_dir_absolute(late)
	check("fresh owned report path passes pre-write check", _report_path_error(late, false).is_empty())
	var late_target := root.path_join("late-missing-target.json")
	if not check("own late link insertion fixture creates", directory.create_link(late_target, late.path_join(REPORT_NAME)) == OK): return
	check("pre-write recheck refuses a link inserted after initial validation", not _write_guarded_report(late, late.path_join(REPORT_NAME), "MUST_NOT_CREATE_TARGET").ok and not _entry_present(late_target))
	var safe := root.path_join("safe-write-session")
	if not check("positive writer fixture is fresh and creates", _report_path_error(safe, true).is_empty() and DirAccess.make_dir_absolute(safe) == OK): return
	var safe_leaf := safe.path_join(REPORT_NAME)
	var safe_payload := "{\"owned_fixture\":true}"
	check("actual writer creates a new owned regular report", _write_guarded_report(safe, safe_leaf, safe_payload).ok and FileAccess.get_file_as_string(safe_leaf) == safe_payload)
	check("actual writer refuses to overwrite its own completed report", not _write_guarded_report(safe, safe_leaf, "MUST_NOT_OVERWRITE").ok and FileAccess.get_file_as_string(safe_leaf) == safe_payload)
	metrics["qa_path_guard_scope"] = "Only this fresh QA session's scratch sentinels/links were created; no user file or external link target used"

func _configuration_checks(definition: Dictionary, snapshot: String) -> void:
	var frame := Frame.new()
	check("unconfigured frame refuses conversion and rebase", not frame.to_local([0, 0, 0]).ok and not frame.prepare_rebase([1, 0, 0]).ok)
	var variants: Array[Dictionary] = []
	var compressed: Dictionary = definition.duplicate(true)
	compressed.distance_compression = true
	variants.append(compressed)
	var origin: Dictionary = definition.duplicate(true)
	origin.origin_easting = 0.0
	variants.append(origin)
	var axes: Dictionary = definition.duplicate(true)
	axes.world_axes.x = "north"
	variants.append(axes)
	var crs: Dictionary = definition.duplicate(true)
	crs.survey_crs = "EPSG:4326"
	variants.append(crs)
	var additional: Dictionary = definition.duplicate(true)
	additional["rotation_deg"] = 12.0
	variants.append(additional)
	var implicit_legacy: Dictionary = definition.duplicate(true)
	implicit_legacy.erase("legacy_plan_alignment_applied")
	variants.append(implicit_legacy)
	var bool_unit: Dictionary = definition.duplicate(true)
	bool_unit.metres_per_unit = true
	variants.append(bool_unit)
	for i in variants.size():
		check("wrong/compressed/implicit frame variant " + str(i) + " is rejected", not frame.configure(variants[i], [0, 0, 0], snapshot) and not frame.metadata().configured)
	check("nonfinite origin is refused before state mutation", not frame.configure(definition, [INF, 0, 0], snapshot) and not frame.metadata().configured)
	check("premature Vector3 canonical origin is refused", not frame.configure(definition, Vector3.ZERO, snapshot) and not frame.metadata().configured)
	check("float32 packed canonical origin is refused", not frame.configure(definition, PackedFloat32Array([0, 0, 0]), snapshot))
	check("invalid snapshot checksum is refused", not frame.configure(definition, [0, 0, 0], "not-a-snapshot"))
	check("unknown elevation metadata field is refused", not frame.configure(definition, [0, 0, 0], snapshot, {"verified": true}))
	check("failed configuration can retry exact source frame", frame.configure(definition, [0, 0, 0], snapshot), frame.last_error)
	var saved: Dictionary = frame.metadata()
	check("identity cannot be reconfigured after success", not frame.configure(definition, [1, 2, 3], snapshot) and frame.metadata() == saved)
	var copy: Dictionary = frame.metadata()
	copy.source_origin_xyz[0] = 999.0
	copy.georeference.world_axes.x = "mutated"
	copy.elevation_reference.status = "surveyed"
	check("returned metadata is detached from immutable identity", frame.metadata() == saved)
	check("unknown vertical reference is explicit and not verified", saved.elevation_reference.status == "unknown" and not saved.elevation_verified_by_module)
	var input_origin := PackedFloat64Array([0.0, 0.0, 0.0])
	var input_vertical := {"status": "unknown", "reference": "UNRESOLVED"}
	var detached := Frame.new()
	detached.configure(definition, input_origin, snapshot, input_vertical)
	input_origin[0] = 900.0
	input_vertical.status = "surveyed"
	check("configuration detaches mutable input containers", detached.metadata().source_origin_xyz[0] == 0.0 and detached.metadata().elevation_reference.status == "unknown")

## A boolean rejection is not enough if a nested helper emitted a script
## error. The parent must also require the supervisor's fatal_errors=[];
## R1's arithmetic report was green while bool!=float failed in the log.
func _adversarial_type_checks(definition: Dictionary, snapshot: String) -> void:
	var bad_values: Array = [true, false, 1.25, 7, "wrong", null, [], {}, Vector3.ZERO]
	for field: String in definition:
		for i in bad_values.size():
			var candidate: Variant = bad_values[i]
			if typeof(definition[field]) == TYPE_BOOL and typeof(candidate) == TYPE_BOOL:
				if candidate == definition[field]: continue # This is valid, not a negative case.
			var bad: Dictionary = definition.duplicate(true)
			bad[field] = candidate
			var frame := Frame.new()
			var rejected: Variant = frame.configure(bad, [0, 0, 0], snapshot)
			check("typed frame rejection " + field + " variant " + str(i), typeof(rejected) == TYPE_BOOL and rejected == false and not frame.metadata().configured)
	for axis: String in ["x", "y", "z"]:
		for value in [true, 1.25, null, [], {}]:
			var bad: Dictionary = definition.duplicate(true)
			bad.world_axes[axis] = value
			var frame := Frame.new()
			check("typed nested axis rejection " + axis + " type " + str(typeof(value)), not frame.configure(bad, [0, 0, 0], snapshot) and not frame.metadata().configured)
	for field: String in ["status", "reference", "source_reference"]:
		for value in [true, 1.25, null, [], {}]:
			var vertical := {"status": "unknown", "reference": "UNRESOLVED", "source_reference": ""}
			vertical[field] = value
			var frame := Frame.new()
			check("typed configuration elevation rejection " + field + " type " + str(typeof(value)), not frame.configure(definition, [0, 0, 0], snapshot, vertical))
	var non_string_key: Dictionary = {false: "unknown"}
	check("non-string elevation key is rejected without comparison", not Frame.new().configure(definition, [0, 0, 0], snapshot, non_string_key))
	var frame := Frame.new()
	if not check("adversarial plan/pose fixture configures", frame.configure(definition, [0, 0, 0], snapshot)): return
	var original: Dictionary = frame.metadata()
	var prepared: Dictionary = frame.prepare_rebase([512, 0, 0])
	if not check("adversarial plan fixture prepares", prepared.ok): return
	for value in [true, 1.25, "wrong", null, [], {}]:
		check("invalid local-vector query is rejected by the API", not frame.to_source_current_live(value).ok and not frame.local_after_rebase_current_live(prepared.plan, value).ok and frame.metadata() == original)
	for field: String in ["schema", "frame_fingerprint", "snapshot_manifest_sha256", "plan_sha256", "frame_instance_id", "from_revision", "to_revision", "origin_before", "origin_after", "canonical_delta_xyz", "translation_local"]:
		for value in [true, 1.25, null, {}, "wrong"]:
			var bad: Dictionary = prepared.plan.duplicate(true)
			bad[field] = value
			var result: Dictionary = frame.validate_rebase(bad)
			check("typed plan rejection " + field + " type " + str(typeof(value)), not result.ok and not frame.commit_rebase(bad) and frame.metadata() == original)
	var made: Dictionary = frame.make_source_pose([1.0, -20.0, 2.0], 0.25, "fixture/feature", "fixture_B2")
	if not check("adversarial pose fixture creates", made.ok): return
	for field: String in ["schema", "snapshot_manifest_sha256", "frame_fingerprint", "elevation_reference", "source_xyz", "heading_rad", "feature_id", "floor_id", "room_id"]:
		for value in [true, 1.25, null, {}, []]:
			if field == "heading_rad" and typeof(value) == TYPE_FLOAT: continue # Finite numeric headings are valid.
			var bad: Dictionary = made.pose.duplicate(true)
			bad[field] = value
			check("typed pose rejection " + field + " type " + str(typeof(value)), not frame.validate_source_pose(bad).ok and frame.metadata() == original)
	for field: String in ["status", "reference", "source_reference"]:
		for value in [true, 1.25, null, [], {}]:
			var bad: Dictionary = made.pose.duplicate(true)
			bad.elevation_reference[field] = value
			check("typed nested pose elevation rejection " + field + " type " + str(typeof(value)), not frame.validate_source_pose(bad).ok)
	var implicit_vertical: Dictionary = made.pose.duplicate(true)
	implicit_vertical.elevation_reference = {}
	check("pose cannot omit explicit unresolved elevation identity", not frame.validate_source_pose(implicit_vertical).ok)
	for value: float in [INF, NAN]:
		var bad: Dictionary = made.pose.duplicate(true)
		bad.heading_rad = value
		check("nonfinite pose heading is rejected through validation", not frame.validate_source_pose(bad).ok)

func _precision_and_axes_checks(definition: Dictionary, snapshot: String) -> void:
	var far_origin: Array[float] = [17384.7, -18.5, -80120.7]
	var point: Array[float] = [17384.705412828924, -18.5, -80120.70113909859]
	var frame := Frame.new()
	if not check("frame configures near actual country extreme", frame.configure(definition, PackedFloat64Array(far_origin), snapshot)): return
	var local: Dictionary = frame.to_local(PackedFloat64Array(point))
	if not check("double subtraction precedes bounded local vector", local.ok): return
	var restored: Dictionary = frame.to_source_current_live(local.position)
	check("80km source-coordinate roundtrip retains submillimetre detail", restored.ok and _error_m(point, restored.source_xyz) < 0.000001, str(restored))
	var point_mm: Array[float] = [point[0] + 0.001, point[1] + 0.001, point[2] + 0.001]
	var local_mm: Dictionary = frame.to_local(point_mm)
	var delta: Vector3 = local_mm.position - local.position
	check("millimetre increments survive in each local axis", absf(delta.x - 0.001) < 0.0000001 and absf(delta.y - 0.001) < 0.0000001 and absf(delta.z - 0.001) < 0.0000001, str(delta))
	var raw_a := Vector3(point[0], point[1], point[2])
	var raw_b := Vector3(point_mm[0], point_mm[1], point_mm[2])
	metrics["engine_precision_measurement"] = {"absolute_vector3_mm_delta_xyz": [raw_b.x - raw_a.x, raw_b.y - raw_a.y, raw_b.z - raw_a.z], "origin_relative_mm_delta_xyz": [delta.x, delta.y, delta.z], "scope": "Actual engine numeric representation measurement; not physics or rendering acceptance"}
	check("far conversion requests a new local window instead of losing precision", not frame.to_local([0, 0, 0]).ok and frame.to_local([0, 0, 0]).requires_rebase)
	check("nonfinite canonical conversion is refused", not frame.to_local([NAN, 0, 0]).ok)
	check("absolute Vector3 cannot masquerade as canonical doubles", not frame.to_local(raw_a).ok)
	check("oversized or nonfinite local vector is refused", not frame.to_source_current_live(Vector3(3000, 0, 0)).ok and not frame.to_source_current_live(Vector3(INF, 0, 0)).ok)
	var control := Frame.new()
	if not check("control-point frame configures", control.configure(definition, [400.0, 0.0, -900.0], snapshot)): return
	var source: Dictionary = control.svy21_to_source(30908.2819, 29603.0787, 17.75)
	var expected: Array[float] = [396.9213, 17.75, -908.2819]
	check("official numeric control obeys south/west metre axes", source.ok and _error_m(source.source_xyz, expected) < 0.0000001)
	var svy: Dictionary = control.source_to_svy21(source.source_xyz)
	check("SVY21 adapter roundtrip retains E N elevation", svy.ok and _error_m(svy.svy21_enh, [30908.2819, 29603.0787, 17.75]) < 0.0000001)
	var east: Dictionary = control.svy21_to_source(30918.2819, 29603.0787, 17.75)
	var north: Dictionary = control.svy21_to_source(30908.2819, 29613.0787, 17.75)
	check("ten metres east is negative source Z", absf(float(east.source_xyz[2]) - float(source.source_xyz[2]) + 10.0) < 0.0000001)
	check("ten metres north is negative source X", absf(float(north.source_xyz[0]) - float(source.source_xyz[0]) + 10.0) < 0.0000001)
	var underground: Dictionary = control.to_local([400.0, -20.0, -900.0])
	check("basement coordinates below legacy death plane remain representable", underground.ok and underground.position.y == -20.0)
	var a: Dictionary = control.to_local([400.0, 0.0, -900.0])
	var b: Dictionary = control.to_local([403.0, 0.0, -896.0])
	check("source metres retain physical 3-4-5 distance without compression", a.ok and b.ok and absf(a.position.distance_to(b.position) - 5.0) < 0.000001)

func _rebase_transaction_checks(definition: Dictionary, snapshot: String) -> void:
	var frame := Frame.new()
	frame.configure(definition, [0, 0, 0], snapshot)
	var before: Dictionary = frame.metadata()
	check("zero translation is not a rebase", not frame.prepare_rebase([0, 0, 0]).ok and frame.metadata() == before)
	var huge: Dictionary = frame.prepare_rebase([80000.0, 0, 0])
	check("huge jump requires a new context without frame mutation", not huge.ok and huge.requires_new_context and frame.metadata() == before)
	var ready: Dictionary = frame.prepare_rebase([512.25, 8.0, -512.5])
	if not check("bounded rebase prepares without changing frame", ready.ok and frame.metadata() == before): return
	var plan: Dictionary = ready.plan
	check("local shift has old-origin minus new-origin sign", plan.translation_local == Vector3(-512.25, -8.0, 512.5))
	var other := Frame.new()
	other.configure(definition, [0, 0, 0], snapshot)
	check("rebase plan cannot be committed to another frame instance", not other.commit_rebase(plan) and other.metadata().origin_revision == 0)
	var modifications := ["origin_after", "canonical_delta_xyz", "translation_local", "from_revision", "snapshot_manifest_sha256", "frame_fingerprint", "plan_sha256", "extra_field", "packed_after"]
	for field: String in modifications:
		var bad: Dictionary = plan.duplicate(true)
		match field:
			"origin_after": bad.origin_after[0] += 0.125
			"canonical_delta_xyz": bad.canonical_delta_xyz[1] += 0.125
			"translation_local": bad.translation_local += Vector3(0.125, 0, 0)
			"from_revision": bad.from_revision = 4
			"snapshot_manifest_sha256": bad.snapshot_manifest_sha256 = "0".repeat(64)
			"frame_fingerprint": bad.frame_fingerprint = "1".repeat(64)
			"plan_sha256": bad.plan_sha256 = "2".repeat(64)
			"extra_field": bad["extra_field"] = true
			"packed_after": bad.origin_after = PackedFloat64Array(bad.origin_after)
		check("tampered plan " + field + " is rejected atomically", not frame.commit_rebase(bad) and frame.metadata() == before)
	var competing: Dictionary = frame.prepare_rebase([0, 0, 512])
	var old_point: Array[float] = [23.125, -20.0, 41.25]
	var old_local: Dictionary = frame.to_local(old_point)
	var standin := {"position": old_local.position, "velocity": Vector3(7.75, -2.5, 38.0), "heading": 1.23456789}
	var old_velocity: Vector3 = standin.velocity
	var old_heading: float = standin.heading
	# This is explicit coordinator MATH, not an actor/physics integration claim.
	var updated: Dictionary = frame.local_after_rebase_current_live(plan, standin.position)
	if not check("current-live stand-in projection leaves frame unchanged", updated.ok and frame.metadata() == before): return
	standin.position = updated.position
	if not check("valid bounded transaction commits once", frame.commit_rebase(plan), frame.last_error): return
	var after: Dictionary = frame.metadata()
	var actual: Dictionary = frame.to_source_current_live(standin.position)
	check("rebase changes local origin but not canonical source pose", actual.ok and _error_m(actual.source_xyz, old_point) < 0.000001)
	check("translation math leaves stand-in velocity and heading unchanged", standin.velocity == old_velocity and standin.heading == old_heading)
	check("already applied plan cannot be applied twice", not frame.commit_rebase(plan) and frame.metadata() == after)
	check("competing old-revision plan is stale", not frame.commit_rebase(competing.plan) and frame.metadata() == after)
	check("stale plan cannot project cache positions either", not frame.local_after_rebase_current_live(plan, Vector3.ZERO).ok)
	plan.origin_after[0] += 100.0
	check("committed origin does not alias caller plan arrays", frame.metadata() == after)
	var fractional := Frame.new()
	fractional.configure(definition, [0, 0, 0], snapshot)
	var old_position := Vector3(1023.999939, 31.12345, -1023.999937)
	var canonical: Dictionary = fractional.to_source_current_live(old_position)
	var fractional_plan: Dictionary = fractional.prepare_rebase([1023.999931, 31.123441, -1023.999921])
	if not check("bounded fractional rebase prepares", canonical.ok and fractional_plan.ok): return
	var new_position: Dictionary = fractional.local_after_rebase_current_live(fractional_plan.plan, old_position)
	var naive: Vector3 = old_position + fractional_plan.plan.translation_local
	if not check("non-grid current-live reconstruction is prepared", new_position.ok and fractional.commit_rebase(fractional_plan.plan)): return
	var preserved: Dictionary = fractional.to_source_current_live(new_position.position)
	var naive_source: Dictionary = fractional.to_source_current_live(naive)
	var exact_error := _error_m(preserved.source_xyz, canonical.source_xyz)
	metrics["non_grid_translation"] = {"reconstructed_source_error_m": exact_error,
		"native_delta_addition_error_m": _error_m(naive_source.source_xyz, canonical.source_xyz),
		"scope": "Actual engine numeric study; no actor movement performed"}
	check("non-grid rebasing preserves prior physical canonical position", preserved.ok and exact_error < 0.00000001, str(metrics.non_grid_translation))

func _repeated_rebase_checks(definition: Dictionary, snapshot: String) -> void:
	var frame := Frame.new()
	var center: Array[float] = [17384.7, 0.0, -80120.7]
	frame.configure(definition, center, snapshot)
	var offsets: Array = [[-12.25, -18.5, 0.123456], [5.875, 245.125, 35.5], [201.123, 1.5, -112.25]]
	var maximum_error := 0.0
	var consistent := true
	var prepare_was_pure := true
	for step in 219:
		center[2] += 512.0 # Disclosed canonical-motion arithmetic, not game flight.
		var canonical: Array = []
		var locals: Array[Vector3] = []
		for offset: Array in offsets:
			var point: Array[float] = [center[0] + float(offset[0]), center[1] + float(offset[1]), center[2] + float(offset[2])]
			var position: Dictionary = frame.to_local(point)
			if not position.ok:
				consistent = false
				break
			canonical.append(point)
			locals.append(position.position)
		if not consistent: break
		var previous: Dictionary = frame.metadata()
		var prepared: Dictionary = frame.prepare_rebase(center)
		prepare_was_pure = prepare_was_pure and frame.metadata() == previous
		if not prepared.ok:
			consistent = false
			break
		for i in locals.size():
			var updated: Dictionary = frame.local_after_rebase_current_live(prepared.plan, locals[i])
			if not updated.ok:
				consistent = false
				break
			locals[i] = updated.position
		if not consistent: break
		if not frame.commit_rebase(prepared.plan):
			consistent = false
			break
		for i in locals.size():
			var source: Dictionary = frame.to_source_current_live(locals[i])
			if not source.ok:
				consistent = false
				break
			maximum_error = maxf(maximum_error, _error_m(source.source_xyz, canonical[i]))
	metrics["repeated_rebase_math"] = {"rebases": frame.metadata().origin_revision, "canonical_motion_span_m": 219 * 512.0,
		"standins_per_step": offsets.size(), "maximum_canonical_roundtrip_error_m": maximum_error,
		"real_actors_physics_terrain_or_camera_exercised": false}
	check("219 bounded rebases retain source continuity over112km math exercise", consistent and frame.metadata().origin_revision == 219 and maximum_error < 0.0001, str(metrics.repeated_rebase_math))
	check("all rebase preparations are pure", prepare_was_pure)

func _pose_checks(definition: Dictionary, snapshot: String) -> void:
	var frame := Frame.new()
	frame.configure(definition, [17384.7, 0, -80120.7], snapshot)
	var source: Array[float] = [17384.705412828924, -18.5, -80120.70113909859]
	var result: Dictionary = frame.make_source_pose(source, 1.23456789012345, "fixture/feature", "fixture_floor_B2", "")
	if not check("canonical pose has versioned source identity", result.ok): return
	var text := JSON.stringify(result.pose, "", true, true)
	var parsed: Variant = JSON.parse_string(text)
	var restored := Frame.new()
	restored.configure(definition, [17400.0, 0, -80000.0], snapshot)
	var valid: Dictionary = restored.validate_source_pose(parsed)
	check("JSON source pose survives a different active origin", valid.ok and _error_m(valid.pose.source_xyz, source) < 0.0000001 and absf(float(valid.pose.heading_rad) - 1.23456789012345) < 0.000000000001)
	check("JSON pose retains floor and unresolved elevation identity", valid.ok and valid.pose.floor_id == "fixture_floor_B2" and valid.pose.elevation_reference.status == "unknown")
	var local: Dictionary = restored.to_local(source)
	var roundtrip: Dictionary = restored.to_source_current_live(local.position)
	check("restored canonical pose does not depend on old origin revision", roundtrip.ok and _error_m(roundtrip.source_xyz, source) < 0.0001)
	var other := Frame.new()
	other.configure(definition, [17400, 0, -80000], "0".repeat(64))
	check("different source snapshot cannot silently load the pose", not other.validate_source_pose(parsed).ok)
	var datum := Frame.new()
	datum.configure(definition, [17400, 0, -80000], snapshot, {"status": "staging", "reference": "DIFFERENT_LOCAL_ZERO"})
	check("different elevation reference cannot silently load the pose", not datum.validate_source_pose(parsed).ok)
	check("legacy engine-local save is not reinterpreted as real geography", not frame.validate_source_pose({"version": 1, "player_position": [1, 2, 3]}).ok)
	var bad: Dictionary = result.pose.duplicate(true)
	bad.source_xyz = Vector3(1, 2, 3)
	check("premature vector source pose is rejected", not frame.validate_source_pose(bad).ok)
	check("nonfinite pose heading is refused", not frame.make_source_pose(source, INF).ok)
	check("identifier type is validated", not frame.make_source_pose(source, 0.0, 4).ok)

func _checked_cache_checks(definition: Dictionary, snapshot: String) -> void:
	var frame := Frame.new()
	frame.configure(definition, [0, 0, 0], snapshot)
	var captured: Dictionary = frame.capture_current_local(Vector3(10, 0, 0))
	if not check("current live point becomes a revision-bound sample", captured.ok): return
	var stale: Dictionary = captured.sample
	var projected: Dictionary = frame.project_source_sample([10.0, 0.0, 0.0])
	check("canonical projection creates a checked current sample", projected.ok and frame.sample_to_source(projected.sample).source_xyz == [10.0, 0.0, 0.0])
	var first: Dictionary = frame.prepare_rebase([512, 0, 0])
	var prepared: Dictionary = frame.sample_after_rebase(first.plan, stale)
	if not check("checked sample prepares a separate future preview", prepared.ok): return
	var before: Dictionary = frame.metadata()
	check("future preview is never a current local sample", not frame.validate_local_sample(prepared.preview).ok and not frame.sample_to_local(prepared.preview).ok and not frame.sample_to_source(prepared.preview).ok)
	check("future preview cannot activate before commit", not frame.activate_rebase_preview(prepared.preview).ok and frame.metadata() == before)
	check("preview preflight is pure and bound to its plan", frame.validate_rebase_preview(first.plan, prepared.preview).ok and frame.metadata() == before)
	if not check("first cache rebase commits", frame.commit_rebase(first.plan)): return
	check("old cache is rejected after origin changed", not frame.sample_to_source(stale).ok and not frame.sample_to_local(stale).ok)
	check("committed preview still requires explicit activation", not frame.sample_to_source(prepared.preview).ok)
	var activated: Dictionary = frame.activate_rebase_preview(prepared.preview)
	if not check("matching committed preview activates", activated.ok): return
	var current: Dictionary = activated.sample
	check("activated cache retains canonical10 at origin512", frame.sample_to_source(current).source_xyz == [10.0, 0.0, 0.0] and frame.sample_to_local(current).position == Vector3(-502, 0, 0))
	var second: Dictionary = frame.prepare_rebase([1024, 0, 0])
	before = frame.metadata()
	check("current plan rejects old origin0 cache instead of treating it as522", not frame.sample_after_rebase(second.plan, stale).ok and frame.metadata() == before)
	var other := Frame.new()
	other.configure(definition, [0, 0, 0], snapshot)
	var other_plan: Dictionary = other.prepare_rebase([512, 0, 0])
	if not check("wrong-context fixture matches current origin and revision", other.commit_rebase(other_plan.plan) and other.metadata().origin_revision == frame.metadata().origin_revision and other.metadata().source_origin_xyz == frame.metadata().source_origin_xyz): return
	var foreign: Dictionary = other.capture_current_local(Vector3(10, 0, 0))
	check("same snapshot wrong-context cache is rejected", not frame.sample_to_source(foreign.sample).ok and not frame.sample_after_rebase(second.plan, foreign.sample).ok and frame.metadata() == before)
	for field: String in ["schema", "frame_instance_id", "frame_fingerprint", "snapshot_manifest_sha256", "origin_revision", "source_origin_xyz", "source_xyz", "position", "sample_sha256"]:
		for value in [true, 1.25, null, {}, "wrong"]:
			var bad: Dictionary = current.duplicate(true)
			bad[field] = value
			check("typed checked-cache rejection " + field + " type " + str(typeof(value)), not frame.validate_local_sample(bad).ok and not frame.sample_after_rebase(second.plan, bad).ok and frame.metadata() == before)
	var future_sample: Dictionary = current.duplicate(true)
	future_sample.origin_revision += 1
	check("sample cannot claim a future revision without commit", not frame.sample_to_source(future_sample).ok and frame.metadata() == before)
	var wrong_origin: Dictionary = current.duplicate(true)
	wrong_origin.source_origin_xyz[0] += 1.0
	check("same-revision sample cannot change its origin", not frame.validate_local_sample(wrong_origin).ok)
	var changed_point: Dictionary = current.duplicate(true)
	changed_point.source_xyz[0] += 0.25
	changed_point.position += Vector3(0.25, 0, 0)
	check("sample checksum catches a consistently changed cached point", not frame.validate_local_sample(changed_point).ok)
	var next: Dictionary = frame.sample_after_rebase(second.plan, current)
	if not check("current checked cache prepares second preview", next.ok): return
	for field: String in ["schema", "frame_instance_id", "frame_fingerprint", "snapshot_manifest_sha256", "from_revision", "to_revision", "origin_before", "origin_after", "source_xyz", "position", "plan_sha256", "preview_sha256"]:
		for value in [true, 1.25, null, {}, "wrong"]:
			var bad: Dictionary = next.preview.duplicate(true)
			bad[field] = value
			check("typed preview rejection " + field + " type " + str(typeof(value)), not frame.validate_rebase_preview(second.plan, bad).ok and not frame.activate_rebase_preview(bad).ok and frame.metadata() == before)
	var changed_preview: Dictionary = next.preview.duplicate(true)
	changed_preview.source_xyz[0] += 0.25
	changed_preview.position += Vector3(0.25, 0, 0)
	check("preview checksum catches a consistently changed point", not frame.validate_rebase_preview(second.plan, changed_preview).ok)
	var competing: Dictionary = frame.prepare_rebase([512, 0, 512])
	check("preview cannot be attached to a competing current plan", not frame.validate_rebase_preview(competing.plan, next.preview).ok)
	if not check("second cache rebase commits", frame.commit_rebase(second.plan)): return
	var second_sample: Dictionary = frame.activate_rebase_preview(next.preview)
	check("origin1024 cache still means canonical10", second_sample.ok and frame.sample_to_source(second_sample.sample).source_xyz == [10.0, 0.0, 0.0] and frame.sample_to_local(second_sample.sample).position == Vector3(-1014, 0, 0))
	if not second_sample.ok: return
	var return_plan: Dictionary = frame.prepare_rebase([0, 0, 0])
	var return_preview: Dictionary = frame.sample_after_rebase(return_plan.plan, second_sample.sample)
	if not check("return-to-original-origin fixture commits", return_preview.ok and frame.commit_rebase(return_plan.plan)): return
	check("same origin does not revive an old cache revision", frame.metadata().source_origin_xyz == stale.source_origin_xyz and not frame.sample_to_source(stale).ok)
	check("matching returned-origin preview still activates", frame.activate_rebase_preview(return_preview.preview).ok)
	var displaced := Frame.new()
	displaced.configure(definition, [0, 0, 0], snapshot)
	var dc: Dictionary = displaced.capture_current_local(Vector3(10, 0, 0))
	var pa: Dictionary = displaced.prepare_rebase([512, 0, 0])
	var pb: Dictionary = displaced.prepare_rebase([0, 0, 512])
	var wrong_preview: Dictionary = displaced.sample_after_rebase(pa.plan, dc.sample)
	displaced.commit_rebase(pb.plan)
	check("different committed plan cannot activate an unrelated preview", not displaced.activate_rebase_preview(wrong_preview.preview).ok)
	_carried_cache_cycles(definition, snapshot)

func _carried_cache_cycles(definition: Dictionary, snapshot: String) -> void:
	var frame := Frame.new()
	var base: Array[float] = [17384.7, 0.0, -80120.7]
	frame.configure(definition, base, snapshot)
	var first: Dictionary = frame.capture_current_local(Vector3(10.125, -20.005, 3.14159))
	if not check("carried non-grid cache fixture captures once", first.ok): return
	var cache: Dictionary = first.sample
	var original: Array = frame.sample_to_source(cache).source_xyz
	var maximum_drift := 0.0
	var maximum_native_error := 0.0
	var consistent := true
	var rejected_old := true
	var rejected_future := true
	for step in 219:
		# Rebase around the same logical cached point. The cache is carried
		# forward, NOT rebuilt from a fresh canonical input each iteration.
		var target: Array[float] = [base[0] + sin(float(step) * 0.37) * 600.0 + 0.1234,
			base[1] + sin(float(step) * 0.13) * 20.0 + 0.0067,
			base[2] + cos(float(step) * 0.29) * 600.0 - 0.2468]
		var plan: Dictionary = frame.prepare_rebase(target)
		if not plan.ok:
			consistent = false
			break
		var prepared: Dictionary = frame.sample_after_rebase(plan.plan, cache)
		if not prepared.ok:
			consistent = false
			break
		var previous: Dictionary = frame.metadata()
		rejected_future = rejected_future and not frame.sample_to_source(prepared.preview).ok and not frame.activate_rebase_preview(prepared.preview).ok and frame.metadata() == previous
		if not frame.commit_rebase(plan.plan):
			consistent = false
			break
		rejected_old = rejected_old and not frame.sample_to_source(cache).ok
		var activated: Dictionary = frame.activate_rebase_preview(prepared.preview)
		if not activated.ok:
			consistent = false
			break
		cache = activated.sample
		var source: Dictionary = frame.sample_to_source(cache)
		var local: Dictionary = frame.sample_to_local(cache)
		if not source.ok or not local.ok:
			consistent = false
			break
		maximum_drift = maxf(maximum_drift, _error_m(source.source_xyz, original))
		var physical: Dictionary = frame.to_source_current_live(local.position)
		if not physical.ok:
			consistent = false
			break
		maximum_native_error = maxf(maximum_native_error, _error_m(physical.source_xyz, original))
	metrics["carried_checked_cache_cycles"] = {"rebases": frame.metadata().origin_revision, "canonical_input_captures": 1,
		"canonical_refetched_each_step": false, "maximum_cached_source_drift_m": maximum_drift,
		"maximum_native_projection_error_m": maximum_native_error,
		"scope": "Revision-bound cache envelopes and math only; no actual actor/camera/FX integration"}
	check("carried cache survives219 non-grid origin cycles without canonical drift", consistent and frame.metadata().origin_revision == 219 and maximum_drift < 0.000000001 and maximum_native_error < 0.0001, str(metrics.carried_checked_cache_cycles))
	check("every carried old cache epoch is rejected", rejected_old)
	check("every future preview refuses pre-commit consumption", rejected_future)

func _finish() -> void:
	if _finished: return
	_finished = true
	var report := {"checks": checks, "failures": failures, "metrics": metrics,
		"scope": "Coordinate/identity arithmetic and stand-in translations only. No actor/camera/FX integration, physical support, map completeness, rendered quality or performance acceptance.",
		"world_or_owner_save_touched": false, "rendered_acceptance": false}
	report["qa_path_guard_rechecked_before_write"] = true
	var written := _write_guarded_report(qa_session, output, JSON.stringify(report, "\t", true, true))
	if not written.ok:
		push_error("Source-frame report write refused: " + written.error)
		get_tree().quit(2)
		return
	print("[source-frame] RESULT ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
