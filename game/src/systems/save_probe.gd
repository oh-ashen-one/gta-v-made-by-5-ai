extends Node
## Two-process save/relaunch probe (wave 5). `--save-probe=write` starts a run,
## walks the real player a few metres with ordinary input, changes health and
## weapon, saves through Game.save_game() and quits. A separate process launched
## with `--save-probe=read` loads that file through the real Continue path and
## checks the restored player/state. Works headless and in the packaged app.
## Pass an explicit `--save-path=` (task-owned file) to both processes.

var main: Node
var _phase := "write"
var _report_path := ""
var _checks: Array[Dictionary] = []

func setup(m: Node, phase: String, report_path: String) -> void:
	main = m
	_phase = phase
	_report_path = report_path
	_run.call_deferred()

func _check(label: String, passed: bool, detail: Variant = "") -> void:
	_checks.append({"label": label, "passed": passed, "detail": str(detail)})
	print("[save-probe] ", "PASS " if passed else "FAIL ", label, " ", detail)

func _run() -> void:
	# Never touch the player's real save slot: require a task-owned path.
	if String(Game.get("_save_path")) == Game.SAVE_PATH:
		_check("explicit task-owned --save-path supplied", false)
		get_tree().quit(2)
		return
	for i in 20:
		await get_tree().physics_frame
	var player: Player = main.player
	if _phase == "write":
		main._new_game()
		var start := player.global_position
		Input.action_press("move_forward")
		for i in 90:
			await get_tree().physics_frame
		Input.action_release("move_forward")
		for i in 20:
			await get_tree().physics_frame
		_check("player walked with ordinary input before saving", player.global_position.distance_to(start) > 2.0, player.global_position.distance_to(start))
		Game.health = 73.0
		Game.switch_weapon("smg")
		var saved := Game.save_game()
		_check("save written through Game.save_game", saved and FileAccess.file_exists(Game.get("_save_path")))
		var expected := {"position": [player.global_position.x, player.global_position.y, player.global_position.z], "health": Game.health, "weapon": Game.carried_weapon, "stage": main.mission.stage}
		_write(expected)
	else:
		var expected: Dictionary = _read_expected()
		main._continue_game()
		for i in 10:
			await get_tree().physics_frame
		var p: Array = expected.get("position", [0, 0, 0])
		var want := Vector3(float(p[0]), float(p[1]), float(p[2]))
		_check("fresh process found the expected record", not expected.is_empty())
		_check("continue restored player position", player.global_position.distance_to(want) < 1.5, "%s vs %s" % [player.global_position, want])
		_check("continue restored health", is_equal_approx(Game.health, float(expected.get("health", -1.0))), Game.health)
		_check("continue restored carried weapon", Game.carried_weapon == String(expected.get("weapon", "")), Game.carried_weapon)
		_check("game is running after continue", main.started and not Game.simulation_paused)
		_write(expected)
	var failures := 0
	for c in _checks:
		if not c["passed"]: failures += 1
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures == 0 else 1)

func _read_expected() -> Dictionary:
	var f := FileAccess.open(_report_path.get_basename() + "-write.json", FileAccess.READ)
	if f == null: return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY: return {}
	return parsed.get("expected", {})

func _write(expected: Dictionary) -> void:
	var f := FileAccess.open(_report_path.get_basename() + "-%s.json" % _phase, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({"phase": _phase, "pid": OS.get_process_id(), "executable": OS.get_executable_path(), "save_path": Game.get("_save_path"), "expected": expected, "checks": _checks}, "\t"))
	f.close()
