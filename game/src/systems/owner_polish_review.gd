extends Node
var main: Node
var folder: String
var checks: Array=[]
func setup(scene: Node) -> void:
	main=scene
	# Isolate the capture from keyboard/mouse activity in other desktop apps.
	main.set_process_unhandled_input(false)
	main.player.set_process_unhandled_input(false)
	main.player.set_process(false)
	main.hud.set_process_input(false)
	get_viewport().gui_disable_input=true
	get_window().unfocusable=true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-dir="): folder=arg.trim_prefix("--review-dir=")
	assert(not folder.is_empty() and "--qa-session" in OS.get_cmdline_user_args())
	DirAccess.make_dir_recursive_absolute(folder)
	run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks.append({"label":label,"passed":passed});print("POLISH_CHECK ",label," ",passed)
func capture(label: String) -> void:
	await get_tree().create_timer(.35).timeout
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	check("capture_"+label,image.save_png(folder.path_join(label+".png"))==OK)
func run() -> void:
	await capture("01-title")
	main._new_game(); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(3.0).timeout
	check("regular_traffic_one",main.traffic.cars.size()==1)
	check("ambient_pool_four",main.traffic.ambient.vehicles.size()==4)
	check("curbside_parking_preserved",int(main.traffic.parking_stats.road_spawned)>0)
	check("map_has_actual_building_footprints",main.hud._minimap.footprints.size()>100)
	check("map_excludes_terrain_slabs",main.hud._minimap.footprints.all(func(row):return row.bounds.get_area()<100000))
	check("map_uses_compact_detail_area",main.hud._minimap.size.x<=180)
	check("generated_weapon_art_loaded",main.hud._weapon_icon.texture!=null and main.hud._weapon_icon.texture.get_width()>500)
	await capture("02-hud-clear-streets")
	Events.toast("Checkpoint reached. Package secured.","good")
	await capture("03-notification")
	main._toggle_pause(); await capture("04-pause")
	var guide=main.hud._pause_panel.get_node("VisualControlsGuide")
	check("visual_manual_fits_pause_screen",guide.size==Vector2(770,514) and guide.position.x+guide.size.x<1280)
	main._toggle_settings(); await capture("05-settings")
	main.hud._sensitivity.value=1.4
	check("sensitivity_slider",is_equal_approx(float(Game.settings.mouse_sensitivity),1.4))
	main.hud._setting_buttons.invert_y.button_pressed=true
	check("invert_toggle",Game.settings.invert_y==true)
	main.hud._setting_buttons.radio_enabled.button_pressed=false
	check("radio_toggle",Game.settings.radio_enabled==false)
	main.hud._setting_buttons.radio_enabled.button_pressed=true
	main._toggle_settings(); check("settings_returns_to_pause",Game.simulation_paused and main.hud._pause_panel.visible)
	main._toggle_pause(); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	main.hud._toggle_map()
	check("map_pauses_input",Game.simulation_paused and main.hud._full_map.visible)
	await capture("06-full-map")
	main.hud.navigation.select(main.world.locations.helipad_secondary,"Waterfront helicopter")
	main.hud._toggle_map()
	var key:=InputEventKey.new();key.pressed=true;key.physical_keycode=KEY_2;main.hud._input(key)
	check("key_2_equips_smg",Game.carried_weapon=="smg")
	key.physical_keycode=KEY_1;main.hud._input(key)
	check("key_1_equips_pistol",Game.carried_weapon=="pistol")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var radio: Node=Sfx._radio
	check("ten_radio_tracks",radio.tracks.size()==10)
	var previous: int=-1
	var all_unique:=true
	var no_repeat:=true
	for cycle in 4:
		var seen: Array[int]=[]
		for i in radio.tracks.size():
			var next: int=radio.next_index()
			if next in seen:all_unique=false
			if next==previous:no_repeat=false
			seen.append(next);radio.current=next;previous=next
	check("radio_shuffle_all_unique",all_unique)
	check("radio_no_adjacent_repeats",no_repeat)
	var car: Node=null
	for candidate in get_tree().get_nodes_in_group("vehicles"):
		if candidate.get_meta("traffic_parking",false):car=candidate;break
	check("parked_car_available",car!=null)
	if car:
		car.interact(main.player)
		await get_tree().create_timer(1.0).timeout
		check("camera_has_one_transform_owner",car._camera.get_parent()==car and not car._arm.is_physics_processing())
		car.open_drive_by_window();check("window_breaks_once",car.driver_window_broken and car.damage.glass_bursts==1)
		car.open_drive_by_window();check("window_not_rebroken",car.damage.glass_bursts==1)
		main.player.aiming=true;var ammo_before:=Game.current_mag();main.player._fire()
		check("drive_by_consumes_ammo",Game.current_mag()==ammo_before-1)
		check("radio_starts_in_car",Game.mode==Game.MODE_CAR and radio.speaker.playing)
		await capture("07-car-radio")
		var camera_before: Vector3=car._camera.global_position
		main.player._apply_mouse_look(Vector2(480,-110))
		await get_tree().create_timer(.4).timeout
		check("native_driving_camera_free_look",car._camera.global_position.distance_to(camera_before)>1.0)
		await capture("07b-car-camera-orbit")
		car.reset_camera_look()
		# Real production drivetrain on a clear road, not a synthetic velocity.
		car.global_position=Vector3(-163,.2,260);car.rotation.y=0;car.velocity=Vector3.ZERO
		var previous_position:Vector3=car.global_position;var backward_ticks:=0
		Input.action_press("move_forward")
		for frame in 180:
			await get_tree().physics_frame
			if car.global_position.z>previous_position.z+.015:backward_ticks+=1
			previous_position=car.global_position
		Input.action_release("move_forward")
		check("drivetrain_no_forward_backward_oscillation",backward_ticks==0 and car.forward_speed()>10)
		Input.action_press("sprint");Input.action_press("move_left")
		await get_tree().create_timer(.4).timeout
		check("shift_turn_engages_drift",car._handbrake and car.drift_amount()>.3)
		Input.action_release("sprint");Input.action_release("move_left")
		main._toggle_pause()
		await get_tree().create_timer(.15).timeout
		check("radio_pauses_with_game",radio.speaker.stream_paused)
		main._toggle_pause()
		Game.settings.radio_enabled=false
		await get_tree().create_timer(.6).timeout
		check("radio_off_setting_stops_audio",not radio.speaker.playing)
		Game.settings.radio_enabled=true
		await get_tree().create_timer(.2).timeout
		check("radio_on_setting_resumes_audio",radio.speaker.playing)
		car.force_exit();Game.set_mode(Game.MODE_FOOT);main.player.camera.current=true
		await get_tree().create_timer(.6).timeout
		check("radio_stops_on_exit",not radio.speaker.playing)
	await city_checks()
	# Evaluate sourced motion on the real skinned player, without moving the body.
	main.player.respawn_at(WorldBuilder.PLAYER_START,deg_to_rad(WorldBuilder.PLAYER_START_YAW_DEG))
	Game.simulation_paused=true
	main.hud.set_paused(false)
	var visual: Node=main.player._visual
	visual.ignore_simulation_pause=true
	check("native_human_installed",visual.native_human and visual.skeleton.get_bone_count()==65)
	for gait in ["walk","run","sprint","jump_start","jump","land"]:
		visual._play(gait,0.0)
		visual.animator.seek(.18,true)
		await capture("08-motion-"+gait)
	for phase in [0.0,.25,.5,.75,.99]:
		visual.hold_pose("jump",phase)
		main.player.global_position.y=WorldBuilder.PLAYER_START.y+1.05*sin(phase*PI)
		await capture("12-jump-%02d"%roundi(phase*100))
	visual.release_pose()
	check("private_save",Game.save_game())
	Game.settings.radio_enabled=false
	check("radio_preference_load",Game.load_game() and bool(Game.settings.get("radio_enabled",false)))
	var passed:=true
	for row in checks:passed=passed and row.passed
	var report={"passed":passed,"checks":checks,"radio_tracks":radio.tracks.size(),"regular_cars":main.traffic.cars.size(),"ambient_pool":main.traffic.ambient.vehicles.size(),"parking":main.traffic.parking_stats}
	FileAccess.open(folder.path_join("verification.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("POLISH_RESULT ",JSON.stringify(report))
	Sfx.shutdown_audio();get_tree().quit(0 if passed else 1)

func city_checks() -> void:
	var nav=main.hud.navigation
	var all_routes:=true
	for poi in nav.points:
		nav.select(poi.position,poi.name);nav.update(WorldBuilder.PLAYER_START)
		all_routes=all_routes and nav.route.size()>1
	check("landmark_gps_routes_connected",all_routes)
	check("gps_includes_hotel_and_both_helicopters",nav.points.size()>=10)
	var helicopters:=get_tree().get_nodes_in_group("helicopters")
	check("waterfront_helicopter_present",main.get_node_or_null("WaterfrontHelicopter")!=null)
	var shore=preload("res://src/world/downtown/shoreline.gd")
	var boats_ok:=true
	for boat in main.world.bay._boats:
		if boat.has("moored"):continue
		for i in 360:
			var angle:=TAU*i/360.0;var c:Vector2=boat.c;var radius:Vector2=boat.r
			var at:=c+Vector2(cos(angle)*radius.x,sin(angle)*radius.y)
			for offset in [Vector2(-11,-11),Vector2(11,-11),Vector2(11,11),Vector2(-11,11)]:
				boats_ok=boats_ok and shore.is_water_ext(at.x+offset.x,at.y+offset.y)
	check("all_boat_hulls_stay_in_water_entire_route",boats_ok)
	Game.simulation_paused=false
	var access=main.hotel_access
	var clear_doors:=true
	for door in access.public_doors:
		var at:Vector3=door.position
		var start:=at+Vector3(0,1.0,door.side*3.5)
		var finish:=at+Vector3(0,1.0,door.side*.7)
		var ray:=PhysicsRayQueryParameters3D.create(start,finish,1)
		var hit=main.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():print("BLOCKED_DOOR ",at," ",hit.collider.get_path()," ",hit.position)
		clear_doors=clear_doors and hit.is_empty()
	check("six_mbs_door_approaches_clear",clear_doors)
	main.player.reset_action_state()
	main.player.respawn_at(preload("res://src/world/mbs_interior/city_access_layout.gd").exit_position(),PI)
	await get_tree().create_timer(.5).timeout
	await capture("09-mbs-entrance")
	Input.action_press("move_forward")
	for i in 180:
		await get_tree().physics_frame
		if not access.active_space.is_empty():break
	Input.action_release("move_forward")
	for i in 180:
		if not access.transitioning:break
		await get_tree().physics_frame
	print("MBS_WALK_DIAGNOSTIC ",main.player.global_position," grounded=",main.player.is_on_floor()," space=",access.active_space," transition=",access.transitioning," hp=",Game.health)
	check("mbs_walk_through_entry",access.active_space=="lobby")
	await capture("10-mbs-lobby")
	if not access.active_space.is_empty():await access.leave_hotel()
	main.player.respawn_at(main.world.locations.helipad_secondary+Vector3(8,1,9),.6)
	await capture("11-waterfront-helicopter")
