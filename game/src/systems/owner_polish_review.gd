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
	await capture("02-hud-clear-streets")
	Events.toast("Checkpoint reached. Package secured.","good")
	await capture("03-notification")
	main._toggle_pause(); await capture("04-pause")
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
	main.hud.open_weapon_wheel()
	check("wheel_pauses_input",Game.simulation_paused and main.hud._wheel_open)
	main.hud._wheel.selected="smg"
	await capture("06-weapon-wheel")
	main.hud.close_weapon_wheel(true)
	check("wheel_equips_smg",Game.carried_weapon=="smg" and not Game.simulation_paused)
	main.hud.open_weapon_wheel(); main.hud._wheel.selected="pistol"; main.hud.close_weapon_wheel(false)
	check("wheel_cancel_preserves_weapon",Game.carried_weapon=="smg")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var radio: Node=Sfx._radio
	check("five_radio_tracks",radio.tracks.size()==5)
	var previous: int=-1
	var all_unique:=true
	var no_repeat:=true
	for cycle in 4:
		var seen: Array[int]=[]
		for i in 5:
			var next: int=radio.next_index()
			if next in seen:all_unique=false
			if next==previous:no_repeat=false
			seen.append(next);radio.current=next;previous=next
	check("radio_shuffle_five_unique",all_unique)
	check("radio_no_adjacent_repeats",no_repeat)
	var car: Node=null
	for candidate in get_tree().get_nodes_in_group("vehicles"):
		if candidate.get_meta("traffic_parking",false):car=candidate;break
	check("parked_car_available",car!=null)
	if car:
		car.interact(main.player)
		await get_tree().create_timer(1.0).timeout
		check("radio_starts_in_car",Game.mode==Game.MODE_CAR and radio.speaker.playing)
		await capture("07-car-radio")
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
	# Evaluate sourced motion on the real skinned player, without moving the body.
	main.player.respawn_at(WorldBuilder.PLAYER_START,deg_to_rad(WorldBuilder.PLAYER_START_YAW_DEG))
	Game.simulation_paused=true
	main.hud.set_paused(false)
	var visual: Node=main.player._visual
	visual.ignore_simulation_pause=true
	check("sourced_run_installed",String(visual._clips.get("run","")).begins_with("sourced/"))
	for gait in ["walk","run","sprint"]:
		visual._play(gait,0.0)
		visual.animator.seek(.18,true)
		await capture("08-motion-"+gait)
	check("private_save",Game.save_game())
	Game.settings.radio_enabled=false
	check("radio_preference_load",Game.load_game() and bool(Game.settings.get("radio_enabled",false)))
	var passed:=true
	for row in checks:passed=passed and row.passed
	var report={"passed":passed,"checks":checks,"radio_tracks":radio.tracks.size(),"regular_cars":main.traffic.cars.size(),"ambient_pool":main.traffic.ambient.vehicles.size(),"parking":main.traffic.parking_stats}
	FileAccess.open(folder.path_join("verification.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("POLISH_RESULT ",JSON.stringify(report))
	Sfx.shutdown_audio();get_tree().quit(0 if passed else 1)
