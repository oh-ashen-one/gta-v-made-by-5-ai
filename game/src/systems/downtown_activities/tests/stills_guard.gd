extends Node
## Fast optional-capture guard smoke; no world, renderer, or gameplay fixture.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var probe: Node = load("res://src/systems/downtown_activities/tests/courier_route.gd").new()
	var args := OS.get_cmdline_user_args()
	var qa_index := args.find("--qa-session")
	assert(qa_index >= 0 and qa_index + 1 < args.size())
	var qa := String(args[qa_index + 1])
	var cases := [
		[qa.path_join("stills"), qa, true],
		[qa.replace("/private/tmp/", "/tmp/").path_join("stills"), qa, true],
		[qa + "-other/stills", qa, false],
		["stills", qa, false],
		[qa + "/../outside", qa, false],
		["/Users/midir/courier-stills", qa, false],
		[qa, qa, false],
	]
	var passed := true
	for item in cases:
		var result: bool = probe._safe_stills_path(item[0], item[1]) == item[2]
		print("[stills-guard] ", "PASS " if result else "FAIL ", item[0])
		passed = passed and result
	var configured: bool = probe._configure_stills()
	passed = passed and configured and probe._stills_dir.is_empty()
	await probe._capture_still("headless_must_skip")
	passed = passed and not DirAccess.dir_exists_absolute(qa.path_join("stills"))
	print("[stills-guard] headless skips readback/writes=", passed)
	probe.free()
	Sfx.shutdown_audio()
	get_tree().quit(0 if passed else 1)
