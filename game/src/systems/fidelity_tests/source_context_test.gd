extends Node3D
## Pure state semantics plus an isolated native basement/capsule fixture.
## No production Player/Game save integration, rendered quality or city proof.
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const SNAPSHOT := "res://data/geography/osm-2026-10-27/manifest.json"
const REPORT_NAME := "source-context-report.json"
const BASE := [17384.7, 0.0, -80120.7]
const FEATURE := "qa-only/architectural-fixture"
const FLOOR := "qa-only/B2"
const SUPPORT := "qa-only/slab"
const RESIDENCY := "qa-only/physics-generation-1"
var definition: Dictionary = {}
var snapshot := ""
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var output := ""
var qa_session := ""
var _finished := false
var _body: CharacterBody3D
var _body_moves := false

func check(label: String, condition: bool, detail: String = "") -> bool:
	checks += 1
	print("[source-context] %s %s %s" % ["PASS" if condition else "FAIL", label, detail])
	if not condition: failures.append(label)
	return condition

func _state_is(result: Variant, domain: String, expected: String) -> bool:
	if typeof(result) != TYPE_DICTIONARY or typeof(result.get("ok")) != TYPE_BOOL or not result.ok: return false
	var state: Variant = result.get(domain)
	return typeof(state) == TYPE_DICTIONARY and typeof(state.get("state")) == TYPE_STRING and state.state == expected

func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

func _fixture_hash(label: String) -> String:
	return _sha(("SYNTHETIC QA FIXTURE, NOT SINGAPORE SURVEY: " + label).to_utf8_buffer())

func _profile() -> Dictionary:
	# Matches current Player._ready capsule(.36,1.75) and local offset(0,.9,0),
	# but this fixture deliberately does NOT instantiate or change Player.
	return {"profile_id": "qa-player-capsule-.36-1.75-offset-.9", "radius_m": .36, "height_m": 1.75,
		"center_offset_xyz": [0.0, .9, 0.0], "min_support_normal_y": cos(deg_to_rad(52.0)),
		"max_support_drop_m": .35, "max_support_rise_m": .1, "max_support_lateral_m": .4}

func _floor_definition(id: String = FLOOR, dry: bool = true) -> Dictionary:
	return {"feature_id": FEATURE, "floor_id": id, "geometry_sha256": _fixture_hash(id + " collision geometry"),
		"support_ids": [SUPPORT], "volumes": [{"volume_id": id + "/dry-envelope", "min_xyz": [BASE[0] - 12.0, -20.5, BASE[2] - 12.0],
		"max_xyz": [BASE[0] + 12.0, -17.9, BASE[2] + 12.0], "dry": dry}],
		"provenance": "Reconstructed isolated QA box; not actual MBS basement/datum"}

func _fixture(with_floor: bool = true, origin: Array = BASE) -> Dictionary:
	var frame := Frame.new()
	var context := Context.new()
	var configured: bool = frame.configure(definition, origin, snapshot)
	configured = configured and context.configure(frame, _fixture_hash("geometry manifest"), _fixture_hash("unresolved vertical manifest"), _profile(), get_world_3d())
	for kind: String in Context.KINDS:
		configured = configured and context.register_provider(kind, "qa-only/" + kind, "fixture://" + kind + "/not-live-source")
	if with_floor: configured = configured and context.register_floor(_floor_definition())
	return {"frame": frame, "context": context, "configured": configured}

func _observation(context: Variant, query: Dictionary, kind: String, state: String, payload: Dictionary = {}) -> Dictionary:
	var result: Dictionary = context.bind_observation(query, kind, state, payload)
	if not result.ok:
		check("fixture observation binds " + kind + "/" + state, false, str(result))
		return {}
	return result.observation

func _domain(context: Variant, query: Dictionary, territory: String = "inside", land: String = "unknown", water: String = "water_column", physics: String = "unloaded") -> Dictionary:
	var result := {"territory": _observation(context, query, "territory", territory),
		"land": _observation(context, query, "land", land)}
	var payload := {"body_id": "qa-only/sea-column", "bottom_y": -100.0, "surface_y": 0.0} if water == "water_column" else {}
	result["water"] = _observation(context, query, "water", water, payload)
	if physics != "omitted": result["physics"] = _observation(context, query, "physics", physics)
	return result

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at < 0 or at + 1 >= args.size():
		push_error("Source-context test requires explicit isolated --qa-session")
		get_tree().quit(2)
		return
	var path: String = args[at + 1]
	if path.begins_with("/tmp/"): path = "/private/tmp/" + path.trim_prefix("/tmp/")
	if not _report_path_error(path, true).is_empty() or DirAccess.make_dir_absolute(path) != OK or not _report_path_error(path, false).is_empty():
		push_error("Source-context QA refuses unsafe/existing evidence paths")
		get_tree().quit(2)
		return
	qa_session = path
	output = path.path_join(REPORT_NAME)
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.ignore_time_scale = true
	add_child(watchdog)
	watchdog.timeout.connect(func():
		if not _finished:
			check("bounded source-context completion", false, "45-second watchdog")
			_finish())
	watchdog.start(45.0)
	_run.call_deferred()

func _physics_process(delta: float) -> void:
	if _body_moves and is_instance_valid(_body):
		_body.velocity.y -= 9.8 * delta
		_body.move_and_slide()

func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _run() -> void:
	var bytes := FileAccess.get_file_as_bytes(SNAPSHOT)
	var manifest: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not check("actual source snapshot frame loads", typeof(manifest) == TYPE_DICTIONARY and typeof(manifest.get("georeference")) == TYPE_DICTIONARY):
		_finish()
		return
	definition = manifest.georeference.duplicate(true)
	snapshot = _sha(bytes)
	metrics["snapshot_manifest_sha256"] = snapshot
	metrics["geometry_and_vertical_inputs"] = "Explicitly synthetic fixture versions; no surveyed elevation claim"
	_qa_path_guard_checks()
	_configuration_and_registry_checks()
	_independent_domain_checks()
	_restore_semantics_checks()
	_adversarial_checks()
	_provider_key_spelling_checks()
	_transition_checks()
	await _native_basement_checks()
	_finish()

func _configuration_and_registry_checks() -> void:
	var fixture: Dictionary = _fixture()
	var context: Variant = fixture.context
	if not check("explicit immutable context configures", fixture.configured): return
	var metadata: Dictionary = context.metadata()
	check("context does not certify unknown vertical reference", not metadata.elevation_verified_by_context and fixture.frame.metadata().elevation_reference.status == "unknown")
	check("reconfiguration is refused", not context.configure(fixture.frame, _fixture_hash("geometry manifest"), _fixture_hash("unresolved vertical manifest"), _profile(), get_world_3d()) and context.metadata() == metadata)
	check("provider cannot be silently replaced", not context.register_provider("water", "another", "fixture://another") and context.metadata() == metadata)
	check("floor record cannot be replaced", not context.register_floor(_floor_definition()) and context.metadata() == metadata)
	var detached: Dictionary = context.floor_record(FEATURE, FLOOR)
	detached.floor.volumes[0].min_xyz[1] = -9999.0
	check("floor arrays are detached from caller", context.floor_record(FEATURE, FLOOR).floor.volumes[0].min_xyz[1] == -20.5)
	metadata.profile.radius_m = 4.0
	metadata.providers.water.provider_id = "tampered"
	check("profile/provider metadata are detached", context.metadata().profile.radius_m == .36 and context.metadata().providers.water.provider_id == "qa-only/water")
	var unconfigured := Context.new()
	check("unconfigured context refuses queries/restores", not unconfigured.begin_query([0, 0, 0]).ok and not unconfigured.make_restore_pose([0, 0, 0], 0, FEATURE, FLOOR).ok)
	for value in [null, true, 1.5, {}, "wrong"]:
		var fresh := Context.new()
		check("typed invalid frame rejected " + str(typeof(value)), not fresh.configure(value, _fixture_hash("g"), _fixture_hash("v"), _profile(), get_world_3d()))
	for field: String in Context.PROFILE_KEYS:
		for value in [null, true, {}, "wrong"]:
			var bad: Dictionary = _profile()
			bad[field] = "" if field == "profile_id" and typeof(value) == TYPE_STRING else value
			var fresh := Context.new()
			check("typed profile rejection " + field + "/" + str(typeof(value)), not fresh.configure(fixture.frame, _fixture_hash("g"), _fixture_hash("v"), bad, get_world_3d()))
	for field: String in Context.FLOOR_KEYS:
		for value in [null, true, 1.5, {}, "wrong"]:
			var bad: Dictionary = _floor_definition("qa-only/bad")
			bad[field] = "" if field in ["feature_id", "floor_id", "provenance"] and typeof(value) == TYPE_STRING else value
			check("typed floor rejection " + field + "/" + str(typeof(value)), not context.register_floor(bad))
	check("rejected registry writes preserve registered floors", context.metadata().registered_floor_count == 1)
	for field: String in Context.VOLUME_KEYS:
		for value in [null, 1.5, {}, "wrong"]:
			var bad: Dictionary = _floor_definition("qa-only/bad-volume")
			bad.volumes[0][field] = "" if field == "volume_id" and typeof(value) == TYPE_STRING else value
			check("typed volume rejection " + field + "/" + str(typeof(value)), not context.register_floor(bad))
	var reversed: Dictionary = _floor_definition("qa-only/reversed")
	reversed.volumes[0].max_xyz[1] = reversed.volumes[0].min_xyz[1]
	check("zero-thickness floor envelope is refused", not context.register_floor(reversed))
	for value in [Vector3.ZERO, PackedFloat32Array([0, -20, 0]), [0, INF, 0], [true, 0, 0], [0, 0]]:
		check("canonical context refuses premature/nonfinite input " + str(typeof(value)), not context.begin_query(value).ok)
	var point: Array = [BASE[0] + .001, -20.0, BASE[2] + .001]
	var query: Dictionary = context.begin_query(PackedFloat64Array(point))
	check("double canonical point survives distant frame projection", query.ok and query.query.source_xyz == point and query.query.local_sample.position.distance_to(Vector3(.001, -20.0, .001)) < .000001)

func _independent_domain_checks() -> void:
	var fixture: Dictionary = _fixture(false)
	var context: Variant = fixture.context
	var query: Dictionary = context.begin_query([BASE[0], -20.0, BASE[2]]).query
	var missing: Dictionary = context.evaluate(query)
	check("cache miss is unknown in every independent domain", missing.ok and missing.territory.state == "unknown" and missing.land.state == "unknown" and missing.water.state == "unknown" and missing.residency.state == "unknown" and missing.support.state == "unknown")
	var inside: Dictionary = context.evaluate(query, {"territory": _observation(context, query, "territory", "inside")})
	check("territory inside never implies land/support", inside.territory.state == "inside" and inside.land.state == "unknown" and inside.support.state == "unknown")
	var outside: Dictionary = context.evaluate(query, {"territory": _observation(context, query, "territory", "outside"), "land": _observation(context, query, "land", "land")})
	check("territory and land remain independent", outside.territory.state == "outside" and outside.land.state == "land" and outside.support.state == "unknown")
	var data: Dictionary = _domain(context, query, "inside", "non_land")
	var state: Dictionary = context.evaluate(query, data)
	check("unloaded physics does not mean outside or void", state.territory.state == "inside" and state.land.state == "non_land" and state.residency.state == "unloaded" and state.support.state == "unknown")
	check("3D exterior query below water surface is submerged", state.water.state == "submerged")
	var above: Dictionary = context.begin_query([BASE[0], 10.0, BASE[2]]).query
	check("3D water has a surface rather than global negativeY rule", context.evaluate(above, _domain(context, above)).water.state == "above_surface")
	var below: Dictionary = context.begin_query([BASE[0], -101.0, BASE[2]]).query
	check("below known water bottom stays unresolved underground", context.evaluate(below, _domain(context, below)).water.state == "unknown")
	var indoors: Dictionary = _fixture()
	var indoor_query: Dictionary = indoors.context.begin_query([BASE[0], -20.0, BASE[2]]).query
	var indoor_state: Dictionary = indoors.context.evaluate(indoor_query, _domain(indoors.context, indoor_query, "inside", "non_land"))
	check("registered dry basement below-8 overrides exterior sea column", indoor_state.water.state == "dry_indoor" and indoor_state.water.outdoor_water_observation.state == "submerged" and indoor_state.indoor.dry_volume_matches.size() == 1)
	check("dry indoor volume is not resident collision/support", indoor_state.residency.state == "unloaded" and indoor_state.support.state == "unknown" and indoor_state.land.state == "non_land")
	var indoor_unknown: Dictionary = indoors.context.evaluate(indoor_query)
	check("dry architecture and unresolved external water stay explicit", indoor_unknown.water.state == "dry_indoor" and indoor_unknown.water.outdoor_water_observation.state == "unknown" and indoor_unknown.residency.state == "unknown")
	for y in [-21.0, -17.0]:
		var vertical_query: Dictionary = indoors.context.begin_query([BASE[0], y, BASE[2]]).query
		check("dry indoor exclusion is three-dimensional atY" + str(y), indoors.context.evaluate(vertical_query, _domain(indoors.context, vertical_query)).water.state == "submerged")
	var horizontal: Dictionary = indoors.context.begin_query([BASE[0] + 13.0, -20.0, BASE[2]]).query
	check("dry indoor exclusion has horizontal bounds", indoors.context.evaluate(horizontal, _domain(indoors.context, horizontal)).water.state == "submerged")
	indoors.context.register_floor(_floor_definition("qa-only/overlapping-floor"))
	var ambiguous_query: Dictionary = indoors.context.begin_query([BASE[0], -20.0, BASE[2]]).query
	var ambiguous: Dictionary = indoors.context.evaluate(ambiguous_query, _domain(indoors.context, ambiguous_query))
	check("conflicting dry-floor volumes stay unresolved without native identity", ambiguous.indoor.state == "ambiguous_registered" and ambiguous.water.state == "unknown")

func _restore_semantics_checks() -> void:
	var fixture: Dictionary = _fixture()
	var context: Variant = fixture.context
	var made: Dictionary = context.make_restore_pose([BASE[0], -19.99, BASE[2]], .123456789012, FEATURE, FLOOR, "qa-only/room")
	if not check("context makes explicit versioned source pose", made.ok): return
	var saved: Variant = JSON.parse_string(JSON.stringify(made.pose, "", true, true))
	check("source pose JSON retains floor/snapshot/geometry/vertical IDs", context.validate_restore_pose(saved).ok and saved.source_pose.source_xyz[1] == -19.99 and saved.source_pose.floor_id == FLOOR)
	var cold: Dictionary = _fixture(false)
	check("cold restore waits for registered floor identity", cold.context.prepare_restore(saved).status == "pending" and cold.context.prepare_restore(saved).reason == "floor_identity_not_registered")
	cold.context.register_floor(_floor_definition())
	var prepare: Dictionary = cold.context.prepare_restore(saved)
	if not check("registered floor restore asks for fresh local physics", prepare.status == "query_required"): return
	var preflight: Dictionary = cold.context.preflight_restore(saved, prepare.query, _domain(cold.context, prepare.query))
	check("cold restore cannot apply into unloaded dry basement", preflight.status == "pending" and preflight.reasons.has("required_collision_not_resident") and preflight.state.water.state == "dry_indoor")
	var other_floor: Dictionary = _fixture(false)
	var changed: Dictionary = _floor_definition()
	changed.geometry_sha256 = _fixture_hash("changed floor")
	other_floor.context.register_floor(changed)
	check("changed floor geometry blocks restore instead of reinterpretation", other_floor.context.prepare_restore(saved).status == "blocked")
	var different: Dictionary = cold.context.begin_query([BASE[0] + 1.0, -19.99, BASE[2]]).query
	var different_result: Dictionary = cold.context.preflight_restore(saved, different)
	check("restore rejects observations at a different source point with invalid tag", not different_result.ok and different_result.get("status") == "invalid" and different_result.has("error"), str(different_result))
	var invalid_prepare: Dictionary = cold.context.prepare_restore({"version": 1})
	check("invalid restore preparation has explicit status and cannot authorize application", not invalid_prepare.ok and invalid_prepare.get("status") == "invalid" and invalid_prepare.has("error"), str(invalid_prepare))
	check("legacy local Game save is not source-world restore", not context.validate_restore_pose({"version": 1, "player_position": [1, 2, 3]}).ok)
	for field: String in Context.RESTORE_KEYS:
		for value in [null, true, 1.25, {}, "wrong"]:
			var bad: Dictionary = made.pose.duplicate(true)
			bad[field] = value
			check("typed restore envelope rejection " + field + "/" + str(typeof(value)), not context.validate_restore_pose(bad).ok)
	var mismatch: Dictionary = made.pose.duplicate(true)
	mismatch.geometry_manifest_sha256 = _fixture_hash("different geometry manifest")
	check("saved geometry manifest mismatch refuses implicit migration", not context.validate_restore_pose(mismatch).ok)
	mismatch = made.pose.duplicate(true)
	mismatch.vertical_manifest_sha256 = _fixture_hash("different vertical manifest")
	check("saved vertical manifest mismatch refuses implicit migration", not context.validate_restore_pose(mismatch).ok)
	mismatch = made.pose.duplicate(true)
	mismatch.source_pose.snapshot_manifest_sha256 = _fixture_hash("different source snapshot")
	check("saved source snapshot mismatch refuses implicit migration", not context.validate_restore_pose(mismatch).ok)

func _adversarial_checks() -> void:
	var fixture: Dictionary = _fixture()
	var context: Variant = fixture.context
	var query: Dictionary = context.begin_query([BASE[0], -20.0, BASE[2]]).query
	var before: Dictionary = context.metadata()
	for field: String in Context.QUERY_KEYS:
		for value in [null, true, 1.25, {}, "wrong"]:
			var bad: Dictionary = query.duplicate(true)
			bad[field] = value
			check("typed query rejection " + field + "/" + str(typeof(value)), not context.validate_query(bad).ok and not context.evaluate(bad).ok and context.metadata() == before)
	var actual: Dictionary = _observation(context, query, "physics", "unloaded")
	for field: String in Context.OBSERVATION_KEYS:
		for value in [null, true, 1.25, {}, "wrong"]:
			var bad: Dictionary = actual.duplicate(true)
			bad[field] = {"unexpected": true} if field == "payload" and typeof(value) == TYPE_DICTIONARY else value
			var result: Dictionary = context.evaluate(query, {"physics": bad})
			check("typed observation remains unknown " + field + "/" + str(typeof(value)), result.ok and result.residency.state == "unknown" and result.support.state == "unknown" and context.metadata() == before)
	for kind: String in ["territory", "land", "water", "physics"]:
		check("unrecognized provider state refused " + kind, not context.bind_observation(query, kind, "definitely-fine").ok)
	for payload in [true, null, 1.0, [], "wrong", {"bottom_y": true, "surface_y": 0.0, "body_id": "bad"}]:
		check("malformed water payload refuses safely " + str(typeof(payload)), not context.bind_observation(query, "water", "water_column", payload).ok)
	var unknown: Dictionary = {"residency_token": RESIDENCY, "support": {"state": "unknown"}, "clearance": "unknown"}
	for key: String in ["residency_token", "support", "clearance"]:
		for value in [true, null, [], 1.0]:
			var bad: Dictionary = unknown.duplicate(true)
			bad[key] = value
			check("malformed physics payload refuses " + key + "/" + str(typeof(value)), not context.bind_observation(query, "physics", "resident", bad).ok)
	var foreign: Dictionary = _fixture()
	var foreign_query: Dictionary = foreign.context.begin_query(query.source_xyz).query
	check("same snapshot foreign context query refuses", not context.validate_query(foreign_query).ok)
	var changed: Dictionary = actual.duplicate(true)
	changed.snapshot_manifest_sha256 = _fixture_hash("wrong snapshot")
	check("stale snapshot contact never becomes resident", context.evaluate(query, {"physics": changed}).residency.state == "unknown")
	context.register_floor(_floor_definition("qa-only/new-floor"))
	check("floor registry changes invalidate earlier local queries", not context.validate_query(query).ok)

func _transition_checks() -> void:
	var fixture: Dictionary = _fixture()
	var context: Variant = fixture.context
	var frame: Variant = fixture.frame
	var point: Array = [BASE[0] + 10.125, -20.005, BASE[2] + 3.14159]
	var sample: Dictionary = frame.project_source_sample(point).sample
	var query: Dictionary = context.begin_query(point).query
	var before: Dictionary = frame.metadata()
	var transition: Dictionary = context.prepare_transition([BASE[0] + 512.1234, 0.0, BASE[2] - 31.2468], [sample])
	if not check("context transition prepares checked caches without commit", transition.ok and frame.metadata() == before and not transition.moves_or_commits_anything): return
	check("context refuses future cache activation before matching commit", not context.activate_transition(transition.transition).ok and frame.metadata() == before)
	if not check("root-style explicit frame commit succeeds", frame.commit_rebase(transition.plan)): return
	check("origin change invalidates query instead of reinterpreting local sample", not context.validate_query(query).ok)
	var activated: Dictionary = context.activate_transition(transition.transition)
	check("context activates canonical cache after matching explicit commit", activated.ok and frame.sample_to_source(activated.samples[0]).source_xyz == point and not activated.moves_or_commits_anything)
	var current: Dictionary = context.begin_query(point).query
	var stale: Dictionary = _observation(context, current, "physics", "unloaded")
	stale.origin_revision = int(stale.origin_revision) - 1
	check("stale origin physics cannot be trusted at new query", context.evaluate(current, {"physics": stale}).residency.state == "unknown")
	check("context refuses stale caches for another transition", not context.prepare_transition(BASE, [sample]).ok)
	for key: String in ["schema", "context_instance_id", "registry_revision", "plan_sha256", "previews"]:
		for value in [null, true, 1.5, {}, "wrong"]:
			var bad: Dictionary = transition.transition.duplicate(true)
			bad[key] = value
			check("typed transition rejection " + key + "/" + str(typeof(value)), not context.activate_transition(bad).ok)

func _provider_key_spelling_checks() -> void:
	var fixture: Dictionary = _fixture()
	var context: Variant = fixture.context
	var query: Dictionary = context.begin_query([BASE[0], -20.0, BASE[2]]).query
	var plain: Dictionary = _domain(context, query)
	var named: Dictionary = {}
	for key in plain: named[StringName(key)] = plain[key]
	var named_state: Dictionary = context.evaluate(query, named)
	check("StringName provider keys normalize to exact known kinds", _state_is(named_state, "territory", "inside") and _state_is(named_state, "residency", "unloaded") and _state_is(named_state, "support", "unknown"), JSON.stringify(named_state))
	var dot_added: Dictionary = _domain(context, query, "inside", "unknown", "water_column", "omitted")
	dot_added.physics = plain.physics
	var dot_types: Array[Dictionary] = []
	for key in dot_added: dot_types.append({"key": String(key), "variant_type": typeof(key), "type_name": type_string(typeof(key))})
	metrics["native_dictionary_provider_key_types"] = dot_types
	var dot_state: Dictionary = context.evaluate(query, dot_added)
	check("new dot-assigned provider key works without changing security identity", _state_is(dot_state, "territory", "inside") and _state_is(dot_state, "residency", "unloaded"), JSON.stringify({"types": dot_types, "result": dot_state}))
	var rebound: Dictionary = context.bind_observation(query, &"physics", "unloaded")
	check("StringName kind adapter emits canonical String identity", rebound.ok and typeof(rebound.observation.kind) == TYPE_STRING and rebound.observation.kind == "physics")
	var fresh := Context.new()
	fresh.configure(fixture.frame, _fixture_hash("geometry"), _fixture_hash("vertical"), _profile(), get_world_3d())
	check("StringName provider registration preserves one canonical identity", fresh.register_provider(&"physics", "qa/named", "fixture://named") and not fresh.register_provider("physics", "qa/duplicate", "fixture://duplicate"))
	for key in [null, true, 7, 1.5, Vector3.ZERO, &"not-a-provider", "not-a-provider", &"PHYSICS", "physics "]:
		var invalid: Dictionary = {key: plain.physics}
		check("noncanonical provider map key rejects " + str(key), not context.evaluate(query, invalid).ok)
		check("noncanonical provider kind cannot bind " + str(key), not context.bind_observation(query, key, "unloaded").ok)

func _box(parent: Node3D, label: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.position = center
	return body

func _native_payload(frame: Variant, query: Dictionary, floor: StaticBody3D) -> Dictionary:
	var local: Vector3 = query.local_sample.position
	var ray := PhysicsRayQueryParameters3D.create(local + Vector3.UP * .15, local + Vector3.DOWN * .35, 1)
	ray.exclude = [_body.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray)
	var capsule := CapsuleShape3D.new()
	capsule.radius = .36
	capsule.height = 1.75
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.transform = Transform3D(Basis.IDENTITY, local + Vector3(0, .9, 0))
	shape_query.margin = 0.0
	shape_query.collision_mask = 1
	shape_query.exclude = [_body.get_rid()]
	var overlaps: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(shape_query, 16)
	var support: Dictionary = {"state": "unsupported"}
	if not hit.is_empty() and hit.collider == floor:
		var point: Dictionary = frame.to_source_current_live(hit.position)
		var normal: Vector3 = hit.normal
		support = {"state": "supported", "feature_id": FEATURE, "floor_id": FLOOR, "support_id": SUPPORT,
			"collider_instance_id": floor.get_instance_id(), "contact_source_xyz": point.source_xyz,
			"normal_source_xyz": [float(normal.x), float(normal.y), float(normal.z)]}
	return {"residency_token": RESIDENCY, "support": support, "clearance": "clear" if overlaps.is_empty() else "blocked"}

func _native_basement_checks() -> void:
	var fixture: Dictionary = _fixture()
	var context: Variant = fixture.context
	var frame: Variant = fixture.frame
	var floor: StaticBody3D = _box(self, "QaBasementFloor", Vector3(0, -20.25, 0), Vector3(20, .5, 20))
	var stamp: Dictionary = context.make_collider_stamp(FEATURE, FLOOR, SUPPORT, RESIDENCY)
	if not check("native fixture collider has explicit current source stamp", stamp.ok): return
	floor.set_meta(Context.COLLIDER_META, stamp.stamp)
	_body = CharacterBody3D.new()
	_body.name = "QaProductionShapeOnly"
	_body.collision_layer = 2
	_body.collision_mask = 1
	_body.floor_max_angle = deg_to_rad(52.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = .36
	capsule.height = 1.75
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position = Vector3(0, .9, 0)
	_body.add_child(shape)
	add_child(_body)
	_body.position = Vector3(0, -19.0, 0)
	_body_moves = true
	await _frames(120)
	_body_moves = false
	var settled := _body.position
	check("real production-shape capsule is supported below old-8 death plane", _body.is_on_floor() and settled.y < -19.9 and settled.y > -20.2 and _body.velocity.length() < .01, str(settled))
	# A 5cm lift above the settled root supplies nonpenetrating restore clearance;
	# the native ray still probes the SAME live slab within profile drop distance.
	var source: Dictionary = frame.to_source_current_live(settled + Vector3.UP * .05)
	var query: Dictionary = context.begin_query(source.source_xyz).query
	var payload: Dictionary = _native_payload(frame, query, floor)
	check("native ray finds real basement slab and capsule volume is clear", payload.support.state == "supported" and payload.clearance == "clear", str(payload))
	var observations: Dictionary = _domain(context, query, "inside", "non_land", "water_column", "omitted")
	observations["physics"] = _observation(context, query, "physics", "resident", payload)
	var state: Dictionary = context.evaluate(query, observations)
	check("fresh native basement support is trusted independently of coast land", state.residency.state == "resident" and state.support.state == "supported" and state.water.state == "dry_indoor" and state.land.state == "non_land", str(state))
	var saved: Dictionary = context.make_restore_pose(query.source_xyz, .75, FEATURE, FLOOR)
	if not check("native supported basement pose can be represented", saved.ok): return
	var ready: Dictionary = context.preflight_restore(saved.pose, query, observations)
	check("known dry supported basement is ready below-8 without actor mutation", ready.ok and ready.status == "ready" and _body.position == settled and not ready.actor_or_save_mutated, str(ready))
	metrics["native_basement"] = {"settled_local_root_xyz": [float(settled.x), float(settled.y), float(settled.z)],
		"source_restore_xyz": source.source_xyz, "capsule_radius_m": capsule.radius, "capsule_height_m": capsule.height,
		"capsule_offset_xyz": [0.0, .9, 0.0], "native_floor_contact": _body.is_on_floor(),
		"restore_preflight": ready.get("status"), "actual_Player_used": false,
		"actual_MBS_or_terrain_datum": false, "no_Y_death_plane_in_context": true}
	for key: String in ["collider_instance_id", "contact_source_xyz", "normal_source_xyz", "feature_id", "floor_id", "support_id"]:
		for value in [null, true, 1.5, {}, "wrong"]:
			var bad_payload: Dictionary = payload.duplicate(true)
			bad_payload.support[key] = "" if key in ["feature_id", "floor_id", "support_id"] and typeof(value) == TYPE_STRING else value
			check("typed native contact rejection " + key + "/" + str(typeof(value)), not context.bind_observation(query, "physics", "resident", bad_payload).ok)
	var bad_stamp: Dictionary = stamp.stamp.duplicate(true)
	bad_stamp.origin_revision = true
	floor.set_meta(Context.COLLIDER_META, bad_stamp)
	check("malformed live collider stamp leaves support unknown", context.evaluate(query, observations).support.state == "unknown")
	for key: String in ["snapshot_manifest_sha256", "geometry_manifest_sha256", "vertical_manifest_sha256", "floor_geometry_sha256", "residency_token"]:
		var stale_stamp: Dictionary = stamp.stamp.duplicate(true)
		stale_stamp[key] = _fixture_hash("wrong identity " + key)
		floor.set_meta(Context.COLLIDER_META, stale_stamp)
		check("same-type stale collider identity refuses " + key, context.evaluate(query, observations).support.state == "unknown")
	floor.set_meta(Context.COLLIDER_META, stamp.stamp)
	var wrong_normal: Dictionary = payload.duplicate(true)
	wrong_normal.support.normal_source_xyz = [0.0, -1.0, 0.0]
	var wrong_obs: Dictionary = observations.duplicate(true)
	wrong_obs.physics = _observation(context, query, "physics", "resident", wrong_normal)
	check("downward normal is not usable floor support", context.evaluate(query, wrong_obs).support.state == "unknown")
	var far_contact: Dictionary = payload.duplicate(true)
	far_contact.support.contact_source_xyz[0] += 1.0
	wrong_obs.physics = _observation(context, query, "physics", "resident", far_contact)
	check("contact at another foot location is not support", context.evaluate(query, wrong_obs).support.state == "unknown")
	await _frames(2)
	var old_state: Dictionary = context.evaluate(query, observations)
	check("stale physics tick loses support/residency without becoming void", old_state.residency.state == "unknown" and old_state.support.state == "unknown" and old_state.territory.state == "inside" and old_state.water.state == "dry_indoor")
	check("source save cannot consume earlier-tick preflight", context.preflight_restore(saved.pose, query, observations).status == "pending")
	var ceiling: StaticBody3D = _box(self, "QaBlockedClearance", Vector3(0, -18.5, 0), Vector3(2, .2, 2))
	await _frames(2)
	query = context.begin_query(source.source_xyz).query
	payload = _native_payload(frame, query, floor)
	observations = _domain(context, query, "inside", "unknown", "water_column", "omitted")
	observations.physics = _observation(context, query, "physics", "resident", payload)
	var query_validation: Dictionary = context.validate_query(query)
	var saved_validation: Dictionary = context.validate_restore_pose(saved.pose)
	check("ceiling query still matches immutable saved canonical pose", query.source_xyz == saved.pose.source_pose.source_xyz, JSON.stringify({"query": query.source_xyz, "saved": saved.pose.source_pose.source_xyz}, "", true, true))
	check("ceiling query and saved pose still validate before preflight", query_validation.ok and saved_validation.ok, JSON.stringify({"query": query_validation, "saved": saved_validation}, "", true, true))
	var blocked: Dictionary = context.preflight_restore(saved.pose, query, observations)
	metrics["native_ceiling_preflight"] = {"payload": payload.duplicate(true), "decision": blocked.duplicate(true), "query_validation": query_validation, "saved_validation": saved_validation}
	check("real capsule ceiling overlap blocks restore despite valid support", payload.clearance == "blocked" and blocked.ok and blocked.get("status") == "blocked" and blocked.get("reasons", []).has("capsule_clearance_blocked") and _body.position == settled, JSON.stringify(blocked, "", true, true))
	ceiling.queue_free()
	await _frames(2)
	query = context.begin_query(source.source_xyz).query
	observations = _domain(context, query)
	var unloaded: Dictionary = context.preflight_restore(saved.pose, query, observations)
	check("unloaded physics waits rather than applying saved basement pose", unloaded.ok and unloaded.get("status") == "pending" and unloaded.state.support.state == "unknown" and _body.position == settled, JSON.stringify(unloaded, "", true, true))
	var rebase: Dictionary = context.prepare_transition([BASE[0] + 512.0, 0.0, BASE[2]], [query.local_sample])
	if not check("native stale-stamp fixture prepares an explicit transition", rebase.ok, JSON.stringify(rebase)): return
	if not check("native stale-stamp fixture explicitly commits new frame", frame.commit_rebase(rebase.plan)): return
	check("context/frame rebase itself moves no native fixture", _body.position == settled and floor.position == Vector3(0, -20.25, 0))
	query = context.begin_query(source.source_xyz).query
	# This uses the recorded old contact only as an intentional stale-provider
	# negative. Root must never stamp/rebind old contacts as fresh observations.
	observations = _domain(context, query, "inside", "unknown", "water_column", "omitted")
	observations.physics = _observation(context, query, "physics", "resident", payload)
	var stale_collider: Dictionary = context.evaluate(query, observations)
	check("old collider revision is refused even when adapter rebinds stale contact", _state_is(stale_collider, "support", "unknown"), JSON.stringify(stale_collider))
	check("source context never silently reapplies/rebases actual body", _body.position == settled)
	_body.queue_free()
	floor.queue_free()
	await _frames(2)

func _finish() -> void:
	if _finished: return
	_finished = true
	_body_moves = false
	var report := {"checks": checks, "failures": failures, "metrics": metrics,
		"scope": "Explicit source-domain/restore semantics and isolated native production-shape basement fixture only. No Player recovery/save/streaming/world bootstrap integration, whole Singapore/MBS completion, rendered or performance acceptance.",
		"production_actors_or_owner_save_touched": false, "rendered_acceptance": false}
	var written := _write_guarded_report(qa_session, output, JSON.stringify(report, "\t", true, true))
	if not written.ok:
		push_error("Source-context report write refused: " + written.error)
		get_tree().quit(2)
		return
	print("[source-context] RESULT ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

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
	if file == null: return {"ok": false, "error": "Cannot create source-context report"}
	file.store_string(content)
	file.flush()
	var complete := file.get_error() == OK and file.get_length() == content.to_utf8_buffer().size()
	file.close()
	return {"ok": true} if complete else {"ok": false, "error": "Incomplete source-context report write"}


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
	var sentinel := "SOURCE_CONTEXT_OWN_SCRATCH_SENTINEL_DO_NOT_MODIFY"
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
