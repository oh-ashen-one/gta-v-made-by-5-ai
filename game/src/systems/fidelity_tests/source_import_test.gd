extends Node
## Load source-world scripts with the real project's autoloads, without
## constructing or accepting a world using unverified road geometry.
func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args(): get_tree().quit(2); return
	var failed := false
	for path in ["res://src/world/geography/source_world.gd", "res://src/world/geography/source_world_hud.gd", "res://src/world/geography/source_world_materials.gd", "res://src/systems/fidelity_tests/source_world_test.gd"]:
		var script: Script = load(path)
		var valid := script != null and script.can_instantiate()
		print("[source-import] ", "PASS " if valid else "FAIL ", path)
		failed = failed or not valid
	get_tree().quit(1 if failed else 0)
