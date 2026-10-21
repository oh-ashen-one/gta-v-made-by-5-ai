extends Node3D
## Fixture-assisted imported-rig QA in the real district, never mission proof.
var main: Node
var out_dir := "../docs/wave-02/character-render"
func setup(m: Node) -> void:
	main=m
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):out_dir=arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()
func _run() -> void:
	await get_tree().create_timer(.4).timeout
	Game.simulation_paused=true
	main.hud.visible=false
	var player: Player=main.player
	player.global_position=Vector3(-40,.25,-149)
	player.rotation=Vector3.ZERO
	var visual: CharacterVisual=player.get("_visual")
	if visual==null or not visual.loaded:
		push_error("character fixture has no imported rig");get_tree().quit(2);return
	visual.ignore_simulation_pause=true
	var cam:=Camera3D.new();cam.current=true;cam.fov=45;add_child(cam)
	var shots=[
		["idle_front",Vector3(2.4,1.4,-3.2),0.0,false,false],
		["idle_side",Vector3(3.2,1.4,.1),0.0,false,false],
		["aim_front",Vector3(2.2,1.5,-3.0),0.0,true,false],
		["aim_side",Vector3(3.2,1.5,.1),0.0,true,false],
		["run_side",Vector3(3.8,1.5,.2),5.0,false,false],
		["reload_front",Vector3(2.4,1.5,-3.0),0.0,true,true],
		["fall",Vector3(3,2.3,-3),0.0,false,false]]
	for shot in shots:
		visual.set_motion(shot[2],shot[3],true,shot[4])
		if shot[0]=="fall":visual.play_death()
		cam.global_position=player.global_position+shot[1]
		cam.look_at(player.global_position+Vector3(0,1,0))
		await get_tree().create_timer(.65 if shot[0]!="fall" else 1.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir+"/"+shot[0]+".png")
		print("[character-review] ",shot[0])
	get_tree().quit()
