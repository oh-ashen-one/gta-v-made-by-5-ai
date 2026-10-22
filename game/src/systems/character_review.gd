extends Node3D
## Fixture-assisted imported-rig QA in the real district, never mission proof.
## Characters piece (wave D) adds close-up views (portrait, chest-up 3/4,
## back) and a crowd line-up of ten civilians built by the real CharacterVisual
## path, so wardrobe/body variety is judged in rendered frames.
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
		["reload_front",Vector3(2.4,1.5,-3.0),0.0,true,true]]
	for shot in shots:
		visual.set_motion(shot[2],shot[3],true,shot[4])
		cam.global_position=player.global_position+shot[1]
		cam.look_at(player.global_position+Vector3(0,1,0))
		await _save(shot[0], .65)
	# Close-ups: the head-and-torso framing fills most of the frame height.
	visual.set_motion(0.0,false,true,false)
	var close=[
		["close_portrait",Vector3(0.55,1.62,-1.05),Vector3(0,1.56,0),30.0],
		["close_chest34",Vector3(0.95,1.55,-1.55),Vector3(0,1.33,0),38.0],
		["close_back34",Vector3(-0.8,1.62,1.7),Vector3(0,1.28,0),40.0],
		["close_side_profile",Vector3(1.25,1.6,-0.15),Vector3(0,1.5,0),32.0]]
	for shot in close:
		cam.fov=shot[3]
		cam.global_position=player.global_position+shot[1]
		cam.look_at(player.global_position+shot[2])
		await _save(shot[0], .6)
	# Crowd line-up: ten civilians through the real CharacterVisual path.
	player.visible=false
	var crowd: Array[CharacterVisual]=[]
	var signatures := {}
	var base:=player.global_position
	for i in 10:
		var v:=CharacterVisual.new()
		add_child(v)
		if not v.configure("civilian", i):
			continue
		v.ignore_simulation_pause=true
		var row:=i/5
		var col:=i%5
		v.global_position=base+Vector3((col-2)*1.05+row*0.5,0,-row*1.5+abs(col-2)*0.25)
		v.rotation.y=(col-2)*0.12
		v.set_motion(0.0 if (i%3)!=0 else 1.1,false,true,false)
		crowd.append(v)
		signatures[CharacterLook.outfit_signature(v.outfit) if not v.outfit.is_empty() else str(i)]=true
	print("[character-review] crowd distinct outfits=",signatures.size()," of ",crowd.size())
	cam.fov=50
	cam.global_position=base+Vector3(0.3,1.7,-6.8)
	cam.look_at(base+Vector3(0,1.05,-0.6))
	await _save("crowd_lineup", 1.0)
	cam.fov=34
	cam.global_position=base+Vector3(-1.2,1.6,-3.6)
	cam.look_at(base+Vector3(-0.6,1.35,-0.4))
	await _save("crowd_close", .5)
	for v in crowd: v.queue_free()
	player.visible=true
	visual.play_death()
	cam.fov=45
	cam.global_position=player.global_position+Vector3(3,2.3,-3)
	cam.look_at(player.global_position+Vector3(0,1,0))
	await _save("fall", 1.4)
	get_tree().quit()
func _save(label: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir+"/"+label+".png")
	print("[character-review] ",label)
