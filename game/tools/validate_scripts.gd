extends Node
## Validate dynamically loaded entry points with the project's real autoloads.
## --check-only --script bypasses those autoloads and cannot check Game/Sfx refs.
func _ready() -> void:
	var failures := 0
	for path in ["res://src/main.gd", "res://src/systems/self_test.gd", "res://src/systems/capture_director.gd", "res://src/systems/asset_review.gd", "res://src/systems/photo_capture.gd", "res://src/systems/character_review.gd", "res://src/systems/ui_review.gd", "res://src/world/interior_detail.gd"]:
		var source: Script = load(path)
		var valid := source != null and source.can_instantiate()
		print("SCRIPT_VALIDATION %s %s" % ["PASS" if valid else "FAIL", path])
		if not valid: failures += 1
	var frame := Image.create(8, 8, false, Image.FORMAT_RGB8)
	frame.fill(Color.BLACK)
	var jpeg := frame.save_jpg_to_buffer(0.8)
	var encoded := jpeg.size() > 2 and jpeg[0] == 255 and jpeg[1] == 216
	print("SCRIPT_VALIDATION %s bounded JPEG buffer encoder" % ["PASS" if encoded else "FAIL"])
	if not encoded: failures += 1
	var constants := ClassDB.class_get_integer_constant_list("Performance")
	for monitor in ["OBJECT_COUNT", "OBJECT_NODE_COUNT", "OBJECT_ORPHAN_NODE_COUNT", "MEMORY_STATIC", "RENDER_VIDEO_MEM_USED", "RENDER_TOTAL_DRAW_CALLS_IN_FRAME"]:
		if monitor in constants:
			var id := ClassDB.class_get_integer_constant("Performance", monitor)
			print("PERFORMANCE_MONITOR %s id=%d value=%s" % [monitor, id, Performance.get_monitor(id)])
		else:
			print("PERFORMANCE_MONITOR UNAVAILABLE ", monitor)
	var has_qa_log := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-engine-log="): has_qa_log = true
	if has_qa_log:
		var capture: Node = load("res://src/systems/capture_director.gd").new()
		capture.set("_engine_log_path", capture._resolve_engine_log_path())
		capture._scan_runtime_log()
		var scan: Dictionary = capture.get("_runtime_log_scan")
		var checked: bool = bool(scan.get("checked", false)) and scan.get("fatal_errors", []).is_empty()
		print("QA_ENGINE_LOG_SCAN %s checked=%s fatal_count=%d classified_count=%d path=%s" % ["PASS" if checked else "FAIL", checked, scan.get("fatal_errors", []).size(), scan.get("classified_nonfatal", []).size(), scan.get("path", "")])
		if not checked: failures += 1
		capture.free()
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures == 0 else 1)
