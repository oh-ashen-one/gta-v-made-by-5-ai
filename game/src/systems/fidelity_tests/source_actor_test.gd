extends Node3D
## Actual production Player/Helicopter in a labeled source-domain fixture.
## Not a Singapore terrain, MBS route, save-file or rendering acceptance test.
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
var checks := 0
var failures: Array[String] = []
var finished := false
var frame: RefCounted
var context: RefCounted
var runtime: Node3D
var player: Player
var metrics: Dictionary = {}
var output := ""
const REPORT_NAME := "source-actor-report.json"
const BASE := [17384.7, 0.0, -80120.7]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at < 0 or at + 1 >= args.size():
		get_tree().quit(2)
		return
	output = args[at + 1]
	if not _report_path_error(output, true).is_empty() or DirAccess.make_dir_absolute(output) != OK or not _report_path_error(output, false).is_empty():
		get_tree().quit(2)
		return
	get_tree().create_timer(75.0, true, false, true).timeout.connect(func():
		if not finished:
			check("bounded native source actor test", false)
			finish())
	run.call_deferred()

func check(label: String, value: bool, details: Variant = "") -> bool:
	checks += 1
	print("[source-actor] %s %s %s" % ["PASS" if value else "FAIL", label, str(details)])
	if not value: failures.append(label)
	return value

func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func sha(text: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(text.to_utf8_buffer())
	return h.finish().hex_encode()

func source(local: Vector3) -> Array:
	return [BASE[0] + float(local.x), BASE[1] + float(local.y), BASE[2] + float(local.z)]

func domain(_point: Array) -> Dictionary:
	# Deliberately synthetic domain provider. The real source bootstrap must
	# supply country/coast/3D hydrology; this is not their runtime integration.
	return {"territory": {"state": "inside"}, "land": {"state": "unknown"},
		"water": {"state": "water_column", "payload": {"body_id": "qa-only/exterior-sea", "bottom_y": -100.0, "surface_y": 0.0}}}

func box(label: String, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body

func run() -> void:
	_qa_path_guard_checks()
	var raw := FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json")
	var manifest: Dictionary = JSON.parse_string(raw)
	frame = Frame.new()
	check("actual source frame and snapshot configure", frame.configure(manifest.georeference, BASE, sha(raw)))
	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.position = Vector3(1495.0, -19.95, -6.0)
	add_child(player)
	context = Context.new()
	var profile := {"profile_id": "production-player-upright", "radius_m": 0.36, "height_m": 1.75,
		"center_offset_xyz": [0.0, 0.9, 0.0], "min_support_normal_y": cos(deg_to_rad(52.0)),
		"max_support_drop_m": 0.35, "max_support_rise_m": 0.1, "max_support_lateral_m": 0.4}
	check("context binds production physics world", context.configure(frame, sha("QA-fixture-geometry-not-MBS"), sha("QA-unresolved-vertical-reference"), profile, get_world_3d()))
	for kind in Context.KINDS: check("explicit fixture provider " + kind, context.register_provider(kind, "qa-only/" + kind, "fixture://not-Singapore-survey"))
	var definition := {"feature_id": "qa-only/basement", "floor_id": "B2", "geometry_sha256": sha("40m-floor-1m-slab-with-same-body-ceiling"), "support_ids": ["slab"],
		"volumes": [{"volume_id": "dry-room", "min_xyz": source(Vector3(1480, -20.5, -20)), "max_xyz": source(Vector3(1520, -17.9, 20)), "dry": true}],
		"provenance": "Synthetic production-actor test, not MBS floorplan or elevation"}
	check("register explicit dry basement", context.register_floor(definition))
	var floor := box("NativeBasementSlab", Vector3(1500, -20.5, 0), Vector3(40, 1, 40))
	# A ceiling on the SAME support body prevents a whole-body collision
	# exclusion from falsely approving the blocked restore below it.
	var ceiling := CollisionShape3D.new()
	var ceiling_shape := BoxShape3D.new()
	ceiling_shape.size = Vector3(3, 0.2, 3)
	ceiling.shape = ceiling_shape
	ceiling.position = Vector3(-5, 2.1, 6)
	floor.add_child(ceiling)
	var wall := box("NativeBasementWall", Vector3(1488, -18, 0), Vector3(0.2, 5, 40))
	runtime = Runtime.new()
	add_child(runtime)
	check("native runtime installs one context/domain", runtime.configure(frame, context, domain))
	await frames(3)
	check("commit whole bounded fixture neighborhood", runtime.commit_region("qa-basement", source(Vector3(1480, -40, -20)), source(Vector3(1500, 50, 20)), [floor, wall],
		[{"body": floor, "feature_id": "qa-only/basement", "floor_id": "B2", "support_id": "slab"}]))
	check("adjacent complete collision region commits without duplicate support stamp", runtime.commit_region("qa-basement-east", source(Vector3(1500, -40, -20)), source(Vector3(1520, 50, 20)), [floor, wall], []))
	check("actual Player capsule binds without weaker profile", runtime.bind_player(player))
	Game.health = Game.MAX_HEALTH
	Game.simulation_paused = false
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await frames(90)
	var start := player.global_position
	var state: Dictionary = runtime.inspect_player(player)
	check("actual Player remains alive below old death plane and outside old rectangle", Game.health == Game.MAX_HEALTH and start.y < -19.9 and start.x > 1494 and player.is_on_floor(), start)
	check("native registered support distinguishes dry basement from exterior sea", state.get("ok", false) and state.support.state == "supported" and state.water.state == "dry_indoor" and state.residency.state == "resident", state)
	var idle_saved: Dictionary = runtime.capture_player_pose(player)
	var idle_position := player.global_position
	var idle_restored: Dictionary = runtime.restore_player_pose(player, idle_saved.pose) if idle_saved.get("ok", false) else {}
	check("immediate idle resting pose restores at exact savedY without a walking prerequisite", idle_restored.get("status") == "applied" and player.global_position == idle_position, idle_restored)
	metrics["idle_resting_clearance"] = {"state": state.clearance, "position_xyz": [idle_position.x, idle_position.y, idle_position.z], "native": runtime.native_clearance_diagnostics.duplicate(true)}
	for blocked_case in [
		{"name": "same-support-body ceiling", "position": Vector3(1495, idle_position.y, 6)},
		{"name": "real wall", "position": Vector3(1488.2, idle_position.y, -6)},
		{"name": "deep floor penetration", "position": idle_position - Vector3.UP * 0.02}]:
		var blocked_pose: Dictionary = context.make_restore_pose(source(blocked_case.position), player.yaw, "qa-only/basement", "B2")
		var blocked: Dictionary = runtime.restore_player_pose(player, blocked_pose.pose)
		check("resting contact tolerance still rejects " + blocked_case.name, blocked.get("status") == "blocked" and blocked.get("reasons", []).has("capsule_clearance_blocked") and player.global_position == idle_position, blocked)
	player.yaw = -PI * 0.5
	Input.action_press("move_forward")
	await frames(150)
	Input.action_release("move_forward")
	await frames(30)
	var end := player.global_position
	check("actual locomotion traverses basement without relocation or death", end.distance_to(start) > 6.0 and Game.health == Game.MAX_HEALTH and absf(end.y - start.y) < 0.04, end)
	metrics["basement_walk_distance_m"] = end.distance_to(start)
	check("native Player crosses adjacent region seam without holding or source-coordinate reset", start.x < 1500 and end.x > 1502, end)
	var body_shape: CollisionShape3D = runtime._player_shape(player)
	body_shape.rotation.z = 0.15
	check("changed bound capsule orientation refuses motion and source capture", not runtime.motion_allowed(player, 1.0 / 60.0) and not runtime.capture_player_pose(player).get("ok", false))
	body_shape.rotation = Vector3.ZERO
	var saved: Dictionary = runtime.capture_player_pose(player)
	check("source pose captured from current native floor identity", saved.get("ok", false), saved)
	if saved.get("ok", false):
		# Actual captured resting pose is tested; no upward QA-only rewrite.
		var restored: Dictionary = runtime.restore_player_pose(player, saved.pose)
		check("actual captured resting source pose clears same-tick restore", restored.get("ok", false) and restored.get("status") == "applied", restored)
	var heli := Helicopter.new()
	heli.process_mode = Node.PROCESS_MODE_DISABLED
	heli.position = Vector3(1500, -10, 9)
	add_child(heli)
	check("actual aircraft uses same source runtime", runtime.bind_aircraft(heli))
	check("aircraft AGL sees actual negative-elevation slab without sea clamp", heli._probe_agl() > 9.5 and heli._probe_agl() < 10.5, heli._probe_agl())
	heli.process_mode = Node.PROCESS_MODE_INHERIT
	await frames(150)
	check("unpiloted aircraft lands on basement slab without legacy water recovery", heli.global_position.x > 1499 and heli.global_position.y < -18.5 and heli.is_on_floor(), heli.global_position)
	var exit_position: Vector3 = heli.landing_exit_position()
	check("source-aware aircraft exit accepts real dry supported negative-elevation floor", exit_position != Vector3.ZERO and exit_position.y < -19.8, exit_position)
	heli.interact(player)
	await frames(4)
	check("actual production boarding owns player proxy", player.current_vehicle == heli and heli.pilot_is_player)
	heli.exit_vehicle(player)
	await frames(8)
	check("actual production exit returns player to basement floor without water-plane rejection", player.current_vehicle == null and not heli.pilot_is_player and player.global_position.y < -19.8 and Game.health == Game.MAX_HEALTH, player.global_position)
	var car := Car.new()
	car.process_mode = Node.PROCESS_MODE_DISABLED
	car.position = Vector3(1506, -19.95, -8)
	add_child(car)
	check("production car hull binds to common source runtime", runtime.bind_car(car))
	car.has_ai = true; car.max_speed = 6.0; car.ai_target = Vector3(1506, -20, -14)
	Game.player_position = Vector3(-10000, 0, 0) # exercise the former far-AI shortcut
	car.process_mode = Node.PROCESS_MODE_INHERIT
	var car_start := car.global_position
	await frames(90)
	check("source far AI car uses supported native motion below old sea plane", car.global_position.distance_to(car_start) > .25 and car.is_on_floor() and car.global_position.y < -19.8, car.global_position)
	car.has_ai = false
	car.shove(Vector3(4, 0, 0), car.global_position)
	var shove_start := car.global_position
	await frames(15)
	check("source-bound car shove follows native motion", car.global_position.x > shove_start.x + .1 and car.is_on_floor(), car.global_position)
	runtime.retire_region("qa-basement")
	var shared: Dictionary = runtime.inspect_player(player)
	check("retiring west keeps shared live floor supported on east", shared.get("ok", false) and shared.support.state == "supported" and shared.residency.state == "resident", shared)
	if saved.get("ok", false):
		var transferred: Dictionary = runtime.restore_player_pose(player, saved.pose)
		check("shared-floor lease transfer preserves native capture and restore", transferred.get("ok", false) and transferred.get("status") == "applied", transferred)
	var before := player.global_position
	runtime.retire_region("qa-basement-east")
	var car_before := car.global_position
	car.shove(Vector3(8, 0, 0), car.global_position)
	Input.action_press("move_forward")
	await frames(30)
	Input.action_release("move_forward")
	check("unloaded collision holds actual Player without death or invented checkpoint", player.global_position.is_equal_approx(before) and Game.health == Game.MAX_HEALTH, player.global_position)
	check("unloaded collision holds car shove without legacy direct integration", car.global_position.is_equal_approx(car_before), car.global_position)
	if saved.get("ok", false):
		var pending: Dictionary = runtime.restore_player_pose(player, saved.pose)
		check("cold source restore waits and leaves actor unchanged", pending.get("ok", false) and pending.get("status") == "pending" and player.global_position.is_equal_approx(before), pending)
	runtime.queue_free()
	await frames(3)
	var heli_before := heli.global_position
	Input.action_press("move_forward")
	await frames(12)
	Input.action_release("move_forward")
	check("source-bound actors hold when runtime disappears instead of falling back to fictional bounds", player.global_position.is_equal_approx(before) and heli.global_position.is_equal_approx(heli_before) and Game.health == Game.MAX_HEALTH and heli.landing_exit_position() == Vector3.ZERO)
	check("source car retains source-mode hold after runtime teardown", car.uses_source_world and car.global_position.is_equal_approx(car_before))
	metrics["actual_player_used"] = true
	metrics["actual_helicopter_used"] = true
	metrics["owner_save_files_touched"] = false
	finish()

func finish() -> void:
	if finished: return
	finished = true
	for action in ["move_forward", "sprint", "jump"]: Input.action_release(action)
	var report := {"checks": checks, "failures": failures, "metrics": metrics, "scope": "Actual production actors/native source adapter in a synthetic basement only; no normal world migration, whole-MBS, national terrain, file-save, rebase or visual acceptance."}
	var written := _write_guarded_report(output, output.path_join(REPORT_NAME), JSON.stringify(report, "\t"))
	if not written.ok:
		push_error("Source-actor report write refused: " + written.error)
		get_tree().quit(2)
		return
	print("[source-actor] RESULT ", JSON.stringify(report))
	Sfx.shutdown_audio()
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
	if file == null: return {"ok": false, "error": "Cannot create source-actor report"}
	file.store_string(content)
	file.flush()
	var complete := file.get_error() == OK and file.get_length() == content.to_utf8_buffer().size()
	file.close()
	return {"ok": true} if complete else {"ok": false, "error": "Incomplete source-actor report write"}


func _fixture_sentinel(path: String, content: String) -> bool:
	if not path.begins_with(output.path_join("path-guard-fixtures") + "/") or not _owned(path.get_base_dir()) or _entry_present(path): return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(content)
	file.close()
	return true

func _qa_path_guard_checks() -> void:
	var root := output.path_join("path-guard-fixtures")
	if not check("own QA guard fixture directory creates", DirAccess.make_dir_absolute(root) == OK): return
	var directory := DirAccess.open(root)
	if not check("own QA guard fixture directory opens", directory != null): return
	var sentinel := "SOURCE_ACTOR_OWN_SCRATCH_SENTINEL_DO_NOT_MODIFY"
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
	check("existing QA session cannot be reused even without report", not _report_path_error(output, true).is_empty())
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
