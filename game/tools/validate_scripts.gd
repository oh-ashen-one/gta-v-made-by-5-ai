extends Node
## Validate dynamically loaded entry points with the project's real autoloads.
## --check-only --script bypasses those autoloads and cannot check Game/Sfx refs.
func _ready() -> void:
	var failures := 0
	for path in ["res://src/main.gd", "res://src/systems/self_test.gd", "res://src/systems/capture_director.gd", "res://src/systems/asset_review.gd"]:
		var source: Script = load(path)
		var valid := source != null and source.can_instantiate()
		print("SCRIPT_VALIDATION %s %s" % ["PASS" if valid else "FAIL", path])
		if not valid: failures += 1
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures == 0 else 1)
