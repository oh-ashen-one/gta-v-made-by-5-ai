extends Node
## Characters piece: OFFLINE bake of the rebuilt character look meshes
## (CharacterLook._build) for the player and civilian rigs. Run headless:
##   python3 game/tools/bounded_run.py --seconds 600 --log ABS.log -- \
##     godot --headless --path game res://tools/bake_character_look.tscn
## Writes res://assets/providers/baked_characters/<rig>_look_<ver>.res + .json
## (private, git-ignored, derived from the private provider rigs).
func _ready() -> void:
	var ok := true
	for role in ["player", "civilian"]:
		if not CharacterVisual.available(role):
			print("[bake] missing rig for ", role)
			ok = false
			continue
		var t0 := Time.get_ticks_msec()
		var out := CharacterLook.bake(role)
		print("[bake] ", role, " -> ", out, " in ", Time.get_ticks_msec() - t0, " ms")
		ok = ok and out != ""
	get_tree().quit(0 if ok else 1)
