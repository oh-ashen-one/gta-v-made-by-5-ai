extends Node
## Fixture-assisted UI/save evidence, not an OS-input or human playtest.
const FIXTURE_LABEL := "orchard-reach-package-roundtrip-v1"
const TIMEOUT_SECONDS := 45.0
var main: Node
var folder := "../docs/wave-02/ui-review"
var _save_path := ""
var _load_phase := false
var _finished := false
var _started_ticks := 0
var _checks: Array[Dictionary] = []
var _captures: Array[Dictionary] = []
var _saved_data: Dictionary = {}
var _writer_report: Dictionary = {}
var _initial_save_sha256 := ""

func setup(value: Node) -> void:
	main = value
	_started_ticks = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	_load_phase = "--ui-review-load" in args
	var save_arguments := 0
	for arg in args:
		if arg.begins_with("--capture-dir="):
			folder = arg.trim_prefix("--capture-dir=")
		elif arg.begins_with("--save-path="):
			_save_path = arg.trim_prefix("--save-path=")
			save_arguments += 1
	_check("capture_directory", DirAccess.make_dir_recursive_absolute(folder) == OK)
	_check("qa_save_guard", "--qa-session" in args and save_arguments == 1 and _safe_save_path(), {
		"explicit_path": _save_path,
		"requires": "--qa-session and a non-symlink /tmp/orchard-reach-ui-review-*.json task save"})
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run.call_deferred()

func _canonical_temp_path(path: String) -> String:
	var normalized := path.simplify_path()
	if normalized.begins_with("/tmp/"):
		normalized = "/private/tmp/" + normalized.trim_prefix("/tmp/")
	return normalized

func _safe_save_path() -> bool:
	# /tmp itself is the standard macOS alias; reject symlinks below it.
	if _save_path != _save_path.simplify_path():
		return false
	var path := _canonical_temp_path(_save_path)
	if not path.begins_with("/private/tmp/"):
		return false
	if not path.get_file().begins_with("orchard-reach-ui-review-") or not path.ends_with(".json"):
		return false
	if _canonical_temp_path(String(Game.get("_save_path"))) != path:
		return false
	var parent := "/private/tmp"
	var parts := path.trim_prefix("/private/tmp/").split("/", false)
	for index in parts.size():
		var directory := DirAccess.open(parent)
		if directory == null or directory.is_link(parts[index]):
			return false
		parent = parent.path_join(parts[index])
		if index < parts.size() - 1 and not DirAccess.dir_exists_absolute(parent):
			return false
	return true

func _check(label: String, passed: bool, details: Dictionary = {}) -> bool:
	_checks.append({"label": label, "passed": passed, "details": details})
	print("[ui-review] ", "PASS " if passed else "FAIL ", label)
	return passed

func _all_passed() -> bool:
	for check in _checks:
		if not bool(check["passed"]): return false
	return true

func _capture(label: String) -> bool:
	await get_tree().create_timer(0.5).timeout
	if _finished: return false
	await RenderingServer.frame_post_draw
	if _finished: return false
	var raster := get_viewport().get_texture().get_image()
	var path := folder.path_join(label + ".png")
	var result := raster.save_png(path)
	_captures.append({"label": label, "path": path, "ticks_msec": Time.get_ticks_msec(),
		"process_frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(),
		"raster_width": raster.get_width(), "raster_height": raster.get_height(),
		"paused": Game.simulation_paused, "title_visible": main.hud._title_panel.visible,
		"pause_visible": main.hud._pause_panel.visible, "settings_visible": main.hud.settings_visible()})
	return _check("capture_" + label, result == OK and raster.get_width() > 0 and raster.get_height() > 0)

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	if file.get_length() > 1048576:
		file.close()
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _run() -> void:
	if not _all_passed():
		_finish()
		return
	_check("rendered_display", DisplayServer.get_name() != "headless")
	_check("title_ready", not main.started and Game.simulation_paused and main.hud._title_panel.visible)
	if not _all_passed():
		_finish()
		return
	if _load_phase: await _run_load()
	else: await _run_write()
	_finish()

func _run_write() -> void:
	if not await _capture("01_title"): return
	main._new_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_check("new_game_started", main.started and not Game.simulation_paused and not main.hud._title_panel.visible)
	if not await _capture("02_start"): return
	main._toggle_pause()
	_check("pause_open", Game.simulation_paused and main.hud._pause_panel.visible)
	if not await _capture("03_pause"): return
	main._toggle_settings()
	_check("settings_open", Game.simulation_paused and main.hud.settings_visible())
	if not await _capture("04_settings"): return
	main._toggle_settings()
	_check("settings_return_to_pause", Game.simulation_paused and main.hud._pause_panel.visible and not main.hud.settings_visible())
	if not await _capture("05_return_to_pause"): return
	# Deliberate QA state: no claim that gameplay earned these values.
	Game.health = 83.0
	Game.settings["mouse_sensitivity"] = 1.3
	Game.settings["invert_y"] = true
	Game.settings["reduced_shake"] = true
	Game.settings["hud_visible"] = true
	Game.ammo["smg"] = {"mag": 17, "reserve": 123}
	Game.switch_weapon("smg")
	main.player._update_weapon_mesh()
	Events.health_changed.emit(Game.health, Game.MAX_HEALTH)
	Events.settings_changed.emit(Game.settings.duplicate(true))
	_verify_fixture("writer")
	if not _check("save_game_returned_true", Game.save_game()): return
	_saved_data = _read_json(_save_path)
	_check("saved_json_valid", not _saved_data.is_empty() and Game._validate_save_data(_saved_data))
	_check("saved_fixture_values", _saved_data.get("health") == 83.0 and _saved_data.get("carried_weapon") == "smg"
		and _saved_data.get("settings", {}).get("mouse_sensitivity") == 1.3
		and _saved_data.get("ammo", {}).get("smg", {}).get("mag") == 17
		and _saved_data.get("ammo", {}).get("smg", {}).get("reserve") == 123)
	_initial_save_sha256 = FileAccess.get_sha256(_save_path)
	_check("save_digest_available", not _initial_save_sha256.is_empty())
	main._toggle_pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _capture("06_saved_fixture")

func _run_load() -> void:
	if not await _capture("11_relaunch_title"): return
	_writer_report = _read_json(folder.path_join("ui-review-write.json"))
	_saved_data = _read_json(_save_path)
	if not _check("prior_writer_report", _writer_report.get("fixture_label") == FIXTURE_LABEL
		and _writer_report.get("phase") == "write" and _writer_report.get("passed") == true): return
	if not _check("fresh_process_same_executable", int(_writer_report.get("process_id", -1)) != OS.get_process_id()
		and _writer_report.get("executable") == OS.get_executable_path()): return
	if not _check("saved_json_valid", not _saved_data.is_empty() and Game._validate_save_data(_saved_data)): return
	_initial_save_sha256 = FileAccess.get_sha256(_save_path)
	if not _check("writer_save_digest_matches", not _initial_save_sha256.is_empty()
		and _writer_report.get("save_sha256") == _initial_save_sha256): return
	# Exact title Continue handler; no direct load_game call in this phase.
	main._continue_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_check("continue_started", main.started and not Game.simulation_paused and not main.hud._title_panel.visible)
	_verify_fixture("loaded")
	var position: Array = _saved_data.get("player_position", [])
	if position.size() == 3:
		var expected := Vector3(float(position[0]), float(position[1]), float(position[2]))
		_check("loaded_player_position", main.player.global_position.distance_to(expected) < 0.01)
	else: _check("loaded_player_position", false)
	if not await _capture("12_continue_fixture"): return
	main._toggle_settings()
	_check("loaded_settings_open", Game.simulation_paused and main.hud.settings_visible())
	if not await _capture("13_loaded_settings"): return
	main._toggle_settings()
	_check("loaded_settings_return_to_game", not Game.simulation_paused and not main.hud.settings_visible() and not main.hud._pause_panel.visible)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not await _capture("14_return_to_game"): return
	_check("load_did_not_rewrite_save", FileAccess.get_sha256(_save_path) == _initial_save_sha256)

func _verify_fixture(prefix: String) -> void:
	_check(prefix + "_health", is_equal_approx(Game.health, 83.0), {"actual": Game.health})
	_check(prefix + "_settings", is_equal_approx(float(Game.settings["mouse_sensitivity"]), 1.3)
		and bool(Game.settings["invert_y"]) and bool(Game.settings["reduced_shake"]) and bool(Game.settings["hud_visible"]), Game.settings.duplicate(true))
	_check(prefix + "_weapon_ammo", Game.carried_weapon == "smg" and Game.current_mag() == 17 and Game.current_reserve() == 123)
	_check(prefix + "_mission", Game.mission_stage == 0 and Game.checkpoint_index == 0 and main.mission.stage == 0)
	_check(prefix + "_player_ready", main.player.alive and main.player.visible and Game.mode == Game.MODE_FOOT)
	var visual: CharacterVisual = main.player._visual
	var weapon: Node3D = main.player._weapon_model
	if visual != null and visual.loaded:
		_check(prefix + "_held_smg", is_instance_valid(weapon) and weapon.visible
			and weapon.get_parent() == visual.weapon_socket and visual._weapon_kind == "smg",
			{"representation": "rigged_provider", "scene": weapon.scene_file_path if is_instance_valid(weapon) else ""})
	elif is_instance_valid(weapon):
		_check(prefix + "_held_smg", weapon.visible and weapon.scene_file_path.contains("smg"), {"representation": "provider_without_rig"})
	else:
		var mesh: MeshInstance3D = main.player._weapon_mesh
		_check(prefix + "_held_smg", mesh.visible and mesh.mesh is BoxMesh and is_equal_approx((mesh.mesh as BoxMesh).size.z, 0.62),
			{"representation": "procedural_fallback", "provider_visual_verified": false})

func _on_timeout() -> void:
	if _finished: return
	_check("bounded_completion", false, {"timeout_seconds": TIMEOUT_SECONDS})
	_finish()

func _finish() -> void:
	if _finished: return
	_finished = true
	var passed := _all_passed()
	var passed_checks: Array[String] = []
	for check in _checks:
		if bool(check["passed"]): passed_checks.append(String(check["label"]))
	var report := {"fixture_label": FIXTURE_LABEL, "phase": "load" if _load_phase else "write",
		"evidence_kind": "fixture-assisted UI and cross-process save roundtrip; not OS-input or human acceptance",
		"passed": passed, "checks": _checks, "passed_checks": passed_checks, "captures": _captures,
		"process_id": OS.get_process_id(), "writer_process_id": _writer_report.get("process_id"),
		"executable": OS.get_executable_path(), "engine_version": Engine.get_version_info(),
		"editor_feature": OS.has_feature("editor"), "display_server": DisplayServer.get_name(),
		"startup_ready_ticks_msec": _started_ticks, "completed_ticks_msec": Time.get_ticks_msec(),
		"probe_elapsed_msec": Time.get_ticks_msec() - _started_ticks, "timeout_seconds": TIMEOUT_SECONDS,
		"save_path": _save_path, "save_sha256": _initial_save_sha256,
		"native_quit_requested": true, "exit_code_requested": 0 if passed else 1}
	var report_path := folder.path_join("ui-review-load.json" if _load_phase else "ui-review-write.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		passed = false
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.flush()
		passed = passed and file.get_error() == OK
		file.close()
	if passed != bool(report["passed"]):
		report["passed"] = false
		report["exit_code_requested"] = 1
		report["report_write_failed"] = true
	print("[ui-review-report] ", JSON.stringify(report))
	if passed: main._quit_game()
	else:
		Sfx.shutdown_audio()
		get_tree().quit(1)
