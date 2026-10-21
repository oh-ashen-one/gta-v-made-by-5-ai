extends SceneTree
## Headless measurement of the police-officer spawn path that wave 2 observed
## as repeated ~735-762 ms combat stalls (package-soak-r2/frame_stalls.jsonl).
## No renderer: this times resource load, PackedScene instantiate, skeleton /
## AnimationPlayer setup and the NPC build path in isolation.
##
## Run: godot --headless --log-file /tmp/profile.log --path game \
##        --script res://tools/profile_officer_spawn.gd

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	# Palette / AssetLibrary / Events are autoload singletons in project.godot;
	# in a SceneTree script they still exist, so the NPC build path is real.
	var role := "officer"
	var t0 := Time.get_ticks_usec()
	var packed := load("res://assets/providers/%s_rigged.glb" % role) as PackedScene
	var t_load := Time.get_ticks_usec()
	print("[profile] first_load_us=", t_load - t0, " ok=", packed != null)
	if packed == null:
		quit(2)
		return
	for i in 3:
		var a := Time.get_ticks_usec()
		var inst := packed.instantiate()
		var b := Time.get_ticks_usec()
		root.add_child(inst)
		var c := Time.get_ticks_usec()
		# walk to the skeleton/animator the way CharacterVisual.configure does
		var sk := _find_type(inst, "Skeleton3D")
		var ap := _find_type(inst, "AnimationPlayer")
		var d := Time.get_ticks_usec()
		var clip_count: int = ap.get_animation_list().size() if ap != null else 0
		for full_name in (ap.get_animation_list() if ap != null else []):
			var clip: Animation = ap.get_animation(full_name)
			clip.loop_mode = Animation.LOOP_LINEAR
		var e := Time.get_ticks_usec()
		print("[profile] instantiate_%d: instantiate_us=%d add_child_us=%d find_us=%d clip_setup_us=%d clips=%d skel=%s" % [
			i, b - a, c - b, d - c, e - d, clip_count, str(sk != null)])
		inst.free()
	var t_pistol := Time.get_ticks_usec()
	var pistol := load("res://assets/providers/pistol_held.glb") as PackedScene
	var p_inst := pistol.instantiate() if pistol != null else null
	var t_pistol_end := Time.get_ticks_usec()
	print("[profile] pistol_load_instantiate_us=", t_pistol_end - t_pistol, " ok=", p_inst != null)
	if p_inst != null:
		p_inst.free()
	var t_npc := Time.get_ticks_usec()
	var npc := NPC.new()
	root.add_child(npc)
	var t_npc_end := Time.get_ticks_usec()
	print("[profile] npc_ready_first_us=", t_npc_end - t_npc, " visual_loaded=", npc.character_visual != null and npc.character_visual.loaded)
	var t_npc2 := Time.get_ticks_usec()
	var npc2 := NPC.new()
	root.add_child(npc2)
	var t_npc2_end := Time.get_ticks_usec()
	print("[profile] npc_ready_second_us=", t_npc2_end - t_npc2)
	quit(0)

func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_type(child, type_name)
		if found != null:
			return found
	return null
