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
	# Diagnostic: the same portrait with sun shadows off (shadow-acne check).
	cam.fov=30
	cam.global_position=player.global_position+Vector3(0.55,1.62,-1.05)
	cam.look_at(player.global_position+Vector3(0,1.56,0))
	var suns:=get_tree().root.find_children("*","DirectionalLight3D",true,false)
	for l in suns: (l as DirectionalLight3D).shadow_enabled=false
	await _save("diag_noshadow_portrait", .4)
	for l in suns: (l as DirectionalLight3D).shadow_enabled=true
	# Wave Q acceptance views: chest-height medium shot at ~2.5 m (the judge's
	# framing), a close over-the-shoulder aim and the gun hand from its side.
	cam.fov=40
	cam.global_position=player.global_position+Vector3(0.9,1.38,-2.35)
	cam.look_at(player.global_position+Vector3(0,1.2,0))
	await _save("chest_medium_2m5", .6)
	visual.set_motion(0.0,true,true,false)
	cam.fov=50
	cam.global_position=player.global_position+Vector3(0.55,1.62,1.25)
	cam.look_at(player.global_position+Vector3(0.1,1.3,-2.0))
	await _save("aim_over_shoulder", .7)
	cam.fov=30
	cam.global_position=player.global_position+Vector3(-1.05,1.45,-0.9)
	cam.look_at(player.global_position+Vector3(-0.05,1.32,-0.45))
	await _save("aim_hand_close", .5)
	cam.fov=32
	cam.global_position=player.global_position+Vector3(0.6,1.5,-1.6)
	cam.look_at(player.global_position+Vector3(-0.05,1.35,-0.45))
	await _save("aim_front_close", .5)
	visual.set_motion(0.0,false,true,false)
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
	await _people_review(base)
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

## Wave S (characters S1): street-life people on the look mesh, dressed by
## the real CrowdPeople path (women, elders, a child, props, skirts), each in
## a chest-height medium shot at ~2.5 m, then a dressed group, then the live
## crowd at Raffles Place and the MBS Event Plaza (simulation running so the
## crowd director fills the plaza around the player).
const PEOPLE_KINDS := [1, 0, 2, 1, 0, 3, 1, 4, 0, 1]
func _people_review(base: Vector3) -> void:
	var people: Array[Node3D] = []
	for i in PEOPLE_KINDS.size():
		var holder := Node3D.new()
		add_child(holder)
		var v := CharacterVisual.new()
		holder.add_child(v)
		if not v.configure("civilian", 211 + i * 37):
			holder.queue_free()
			continue
		v.ignore_simulation_pause = true
		var seed_value := 7001 + i * 104729
		var p := CrowdPeople.person(int(PEOPLE_KINDS[i]), seed_value)
		if i == 3:
			p["skirt"] = true
			p["dress"] = true
		CrowdPeople.dress(holder, v, p)
		# Review fixture: the in-game near-lens cull (NPC.NEAR_HIDE) would hide
		# the hair/props in the 1-2.5 m shots.
		for g in v.find_children("People*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).visibility_range_begin = 0.0
		if OS.get_environment("ORCHARD_LOOK_LODBIAS") != "" and v.look_mesh != null:
			v.look_mesh.lod_bias = float(OS.get_environment("ORCHARD_LOOK_LODBIAS"))
		if OS.get_environment("ORCHARD_LOOK_FLATHEAD") != "" and v.look_mesh != null and i == 3:
			v.look_mesh.set_instance_shader_parameter("head_shape", Vector4(0, 0, 0, 1))
		holder.global_position = base + Vector3(-12.0 + i * 3.0, 0.0, 0.0)
		holder.rotation.y = 0.35 if i % 2 == 0 else -0.3
		v.set_motion(0.0, false, true, false)
		people.append(holder)
		print("[character-review] person ", i, " ", p["name"], " prop=", p.get("prop", "none"), " skirt=", p.get("skirt", false),
			" look=", v.look_mesh != null)
	await get_tree().create_timer(0.3).timeout
	var cam := get_viewport().get_camera_3d()
	cam.fov = 40
	var shown := 0
	for i in people.size():
		if shown >= 8:
			break
		var hp := people[i].global_position
		var fwd := -people[i].global_basis.z
		var side := people[i].global_basis.x
		cam.global_position = hp + fwd * 2.4 + side * 0.55 + Vector3(0, 1.38, 0)
		cam.look_at(hp + Vector3(0, 1.22, 0))
		await _save("person_%02d_%s" % [i, String((people[i].get_meta("people") as Dictionary)["name"])], 0.45)
		shown += 1
	# Face crop at ~1.2 m of two of them (skin breakup, eyes, brows).
	for i in [0, 2, 3, 6]:
		if i >= people.size():
			continue
		var hp2 := people[i].global_position
		var fwd2 := -people[i].global_basis.z
		cam.fov = 30
		cam.global_position = hp2 + fwd2 * 1.1 + people[i].global_basis.x * 0.25 + Vector3(0, 1.6, 0)
		cam.look_at(hp2 + Vector3(0, 1.55, 0))
		await _save("person_face_%02d" % i, 0.4)
	# Group: all of them in two loose rows, chest-height camera at ~4 m.
	for i in people.size():
		var row := i / 5
		var col := i % 5
		people[i].global_position = base + Vector3((col - 2) * 0.95 + row * 0.45, 0.0, -row * 1.4 + absf(col - 2) * 0.2)
		people[i].rotation.y = (col - 2) * 0.15 + (0.4 if row == 1 else 0.0)
	cam.fov = 50
	cam.global_position = base + Vector3(0.3, 1.6, -6.4)
	cam.look_at(base + Vector3(0, 1.1, -0.6))
	await _save("people_group", 0.6)
	cam.fov = 34
	cam.global_position = base + Vector3(-1.2, 1.5, -3.6)
	cam.look_at(base + Vector3(-0.6, 1.3, -0.4))
	await _save("people_group_close", 0.4)
	for h in people:
		h.queue_free()
	# Live crowd stills (the real crowd director, not fixtures).
	var player: Player = main.player
	for spot in [["crowd_raffles_place", Vector3(-377.0, 0.3, -40.0), Vector3(-372.0, 1.5, -46.0), Vector3(-385.0, 1.1, -95.0)],
			["crowd_mbs_event_plaza", Vector3(-150.0, 0.5, -640.0), Vector3(-146.0, 1.5, -636.0), Vector3(-90.0, 1.1, -648.0)]]:
		player.global_position = spot[1]
		player.visible = false
		Game.simulation_paused = false
		cam.fov = 55
		cam.global_position = spot[2]
		cam.look_at(spot[3])
		await get_tree().create_timer(6.0).timeout
		_aim_at_crowd(cam, spot[1])
		await _save(spot[0], 0.1)
		Game.simulation_paused = true
	player.global_position = base

## Points the camera at the densest group of live pedestrians within 70 m of
## `centre`, from 5 m away at chest height (the review judges the people, so
## the frame must hold them, not whatever the fixed pose happened to face).
func _aim_at_crowd(cam: Camera3D, centre: Vector3) -> void:
	var peds: Array = main.traffic.peds if main.traffic != null else []
	var best := Vector3.INF
	var best_n := 0
	for a in peds:
		if not (a is Node3D) or not is_instance_valid(a) or (a as Node3D).global_position.distance_to(centre) > 70.0:
			continue
		var pa := (a as Node3D).global_position
		var n := 0
		for b in peds:
			if b is Node3D and is_instance_valid(b) and (b as Node3D).global_position.distance_to(pa) < 7.0:
				n += 1
		if n > best_n:
			best_n = n
			best = pa
	print("[character-review] crowd near ", centre, ": best cluster ", best_n, " at ", best)
	if best_n < 3:
		return
	var away := (cam.global_position - best)
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(0, 0, 1)
	cam.global_position = best + away.normalized() * 5.5 + Vector3(0, 1.5, 0)
	cam.look_at(best + Vector3(0, 1.1, 0))
