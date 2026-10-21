extends SceneTree
func _initialize()->void:call_deferred("run_probe")
func run_probe()->void:
	var game:=root.get_node("Game")
	if game._save_path!="/tmp/critic-wave2-save.json":quit(3);return
	var main:Node=load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene=main
	for i in 8:await physics_frame
	var before:Dictionary=game.settings.duplicate(true)
	var press:=InputEventKey.new()
	press.keycode=KEY_F6
	press.physical_keycode=KEY_F6
	press.pressed=true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	for i in 2:await physics_frame
	press=InputEventKey.new()
	press.keycode=KEY_F6
	press.physical_keycode=KEY_F6
	press.pressed=false
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	for i in 2:await physics_frame
	var out:={"settings_before":before,"settings_after":game.settings,"health":game.health,"started":main.started,"paused":game.simulation_paused,"title_visible":main.hud._title_panel.visible,"hud_hidden":not main.hud._objective_label.visible,"weapon":game.carried_weapon,"weapon_model":main.player._weapon_model.scene_file_path}
	var file:=FileAccess.open("/tmp/orchard_gameplay_critic_relaunch_r3.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(out,"\t"))
	file.close()
	print("[critic-relaunch-r3] ",JSON.stringify(out))
	quit(0)
