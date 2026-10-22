extends Node3D
## Wave 1 bootstrap: builds the district, spawns the player, traffic, NPCs and
## the mission, and wires the shell (title, pause, HUD, debug diagnostics).

var world: WorldBuilder
var player: Player
var traffic: TrafficManager
var mission: Mission
var hud: HUD
var started := false
var _settings_return_to_pause := false
var _capture_director: Node = null

func _ready() -> void:
	print("[wave1] main ready, args=", OS.get_cmdline_user_args())
	var args := OS.get_cmdline_user_args()
	# QA-only fixed backing resolution; the actual viewport is also measured.
	# Window API: https://docs.godotengine.org/en/stable/classes/class_window.html
	if "--qa-session" in args or "--capture" in args or "--test" in args:
		for arg in args:
			if arg.begins_with("--qa-render-size="):
				var dimensions := arg.trim_prefix("--qa-render-size=").split("x")
				if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
					var target := Vector2i(int(dimensions[0]),int(dimensions[1]))
					if target.x >= 640 and target.x <= 2560 and target.y >= 360 and target.y <= 1440:
						get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
						get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
						get_window().content_scale_size=target
						get_window().content_scale_factor=1.0
						print("[qa-render-size] requested_backing=",target)
	if "--asset-review" in args:
		add_child(load("res://src/systems/asset_review.gd").new())
		return
	world = WorldBuilder.new()
	world.name = "World"
	add_child(world)
	world.build(Game.seed_value)

	player = Player.new()
	player.name = "Player"
	add_child(player)
	# Wave 5: the run opens outdoors on the heritage five-foot way opposite the
	# hawker hall, looking up the avenue to the bay (WORLD-03 opening view).
	player.global_position = world.locations["player_start"]
	player.yaw = deg_to_rad(WorldBuilder.PLAYER_START_YAW_DEG)
	player.pitch = WorldBuilder.PLAYER_START_PITCH
	player.rotation.y = player.yaw
	Game.mark_safe_position(player.global_position, player.yaw)

	traffic = TrafficManager.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(world, player)

	mission = Mission.new()
	mission.name = "Mission"
	add_child(mission)
	mission.setup(world, player, traffic)

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(world, player, mission)
	Events.objective_marker_changed.connect(hud.set_marker)

	# helicopter at the aviation compound, parked on the primary pad
	var heli := Helicopter.new()
	heli.name = "Helicopter"
	add_child(heli)
	heli.global_position = world.locations["helipad_primary"] + Vector3(0.0, 0.6, 0.0)
	print("[launch] world_ui_ready_ms=",Time.get_ticks_msec()," executable=",OS.get_executable_path()," editor_binary=",OS.has_feature("editor"))

	if "--character-review" in args:
		var review: Node = _qa_system("res://src/systems/character_review.gd")
		add_child(review)
		review.setup(self)
		return

	if "--onfoot-review" in args:
		hud.show_title(false)
		started = true
		Game.simulation_paused = false
		var onfoot: Node = _qa_system("res://src/systems/onfoot_review.gd")
		add_child(onfoot)
		onfoot.setup(self)
		return

	if "--test" in args:
		# Regression input belongs to active gameplay, not the title overlay.
		# Native mouse events are legitimately consumed by visible menus.
		hud.show_title(false)
		started=true
		Game.simulation_paused=false
		var tester := SelfTest.new()
		add_child(tester)
		await tester.run(self)
		get_tree().quit(1 if tester.failures > 0 else 0)
		return

	if "--photos" in args or "--gameplay-photos" in args:
		var photo_dir := "captures"
		for arg in args:
			if arg.begins_with("--capture-dir="):
				photo_dir = arg.split("=")[1]
		var shooter: Node = _qa_system("res://src/systems/photo_capture.gd")
		add_child(shooter)
		shooter.setup(self, world, photo_dir)
		# the frames are evidence of the district, not of the title screen
		hud.show_title(false)
		started = true
		return

	for arg in args:
		if arg.begins_with("--save-probe="):
			var report := "user://save_probe.json"
			for other in args:
				if other.begins_with("--save-probe-report="):
					report = other.trim_prefix("--save-probe-report=")
			hud.show_title(false)
			var probe_node: Node = _qa_system("res://src/systems/save_probe.gd")
			add_child(probe_node)
			probe_node.setup(self, arg.trim_prefix("--save-probe="), report)
			return

	if "--perf-probe" in args:
		var perf_dir := "user://perf"
		for arg in args:
			if arg.begins_with("--capture-dir="):
				perf_dir = arg.trim_prefix("--capture-dir=")
		hud.show_title(false)
		started = true
		Game.simulation_paused = false
		var perf: Node = _qa_system("res://src/systems/perf_probe.gd")
		add_child(perf)
		perf.setup(self, perf_dir)
		return

	if "--sightline-probe" in args:
		var probe_dir := "user://sightlines"
		for arg in args:
			if arg.begins_with("--capture-dir="):
				probe_dir = arg.trim_prefix("--capture-dir=")
		hud.show_title(false)
		started = true
		Game.simulation_paused = false
		var probe: Node = _qa_system("res://src/systems/sightline_probe.gd")
		add_child(probe)
		probe.setup(self, probe_dir)
		return

	if "--capture" in args:
		_capture_director = _qa_system("res://src/systems/capture_director.gd")
		add_child(_capture_director)
		_capture_director.setup(self, player, world, mission, traffic)
		hud.show_title(false)
		started = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Game.simulation_paused = true
		hud.show_title(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if "--ui-review" in args:
			var review: Node = _qa_system("res://src/systems/ui_review.gd")
			add_child(review)
			review.setup(self)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and hud.settings_visible():
		if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5]:
			_apply_setting_key(event.keycode)
			return
	if event.is_action_pressed("pause"):
		if hud.settings_visible():
			_toggle_settings()
			return
		if not started:
			return
		_toggle_pause()
	if not started:
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_ENTER: _new_game()
				KEY_F6: _continue_game()
				KEY_F3: _toggle_settings()
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F12:
				_take_screenshot()
			KEY_F5:
				if Game.save_game():
					Events.toast("Progress saved.", "info")
			KEY_F6:
				if Game.load_game():
					Events.toast("Progress loaded.", "info")
				else:
					# A rejected load must leave the current run untouched, so the
					# message must not claim a new game was started (wave-2 F6).
					Events.toast("Save unreadable or incompatible - progress unchanged.", "bad")
			KEY_F7:
				player.respawn_at(Game.last_safe_position, Game.last_safe_rotation)
			KEY_F10:
				if mission:
					mission.restart()
			KEY_F8:
				Game.settings["hud_visible"] = not bool(Game.settings["hud_visible"])
				hud.set_gameplay_visible(bool(Game.settings["hud_visible"]))
			KEY_F9:
				started = false
				Game.simulation_paused = true
				hud.show_title(true)
				hud.set_paused(false)
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F3:
				_toggle_settings()
			KEY_1:
				Game.settings["mouse_sensitivity"] = clampf(float(Game.settings["mouse_sensitivity"]) - 0.1, 0.2, 3.0)
				hud.refresh_settings()
			KEY_2:
				Game.settings["mouse_sensitivity"] = clampf(float(Game.settings["mouse_sensitivity"]) + 0.1, 0.2, 3.0)
				hud.refresh_settings()
			KEY_3:
				Game.settings["invert_y"] = not bool(Game.settings["invert_y"])
				hud.refresh_settings()
			KEY_4:
				Game.settings["reduced_shake"] = not bool(Game.settings["reduced_shake"])
				hud.refresh_settings()
			KEY_5:
				Game.settings["hud_visible"] = not bool(Game.settings["hud_visible"])
				hud.set_gameplay_visible(bool(Game.settings["hud_visible"]))
				hud.refresh_settings()
	if event.is_action_pressed("debug_panel"):
		_toggle_debug()

func _toggle_debug() -> void:
	hud.set_meta("debug", not hud.get_meta("debug", false))

func _toggle_pause() -> void:
	Game.simulation_paused = not Game.simulation_paused
	hud.set_paused(Game.simulation_paused)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Game.simulation_paused else Input.MOUSE_MODE_CAPTURED

func _start_game() -> void:
	started = true
	Game.simulation_paused = false
	hud.show_title(false)
	hud.set_paused(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.toast("The hawker centre is marked on your map.", "info")

func _new_game() -> void:
	mission.restart()
	hud.clear_notifications()
	Game.death_count = 0
	_start_game()

func _continue_game() -> void:
	if Game.load_game():
		_start_game()
		Events.toast("Progress restored.","good")
	else:
		Events.toast("No compatible save. Start a new game to begin.","warn")

func _quit_game() -> void:
	Sfx.shutdown_audio()
	get_tree().quit()

func _toggle_settings() -> void:
	var closing := hud.settings_visible()
	if not closing:
		_settings_return_to_pause = Game.simulation_paused and started
	hud.toggle_settings()
	Game.simulation_paused = hud.settings_visible() or not started or (closing and _settings_return_to_pause)
	hud.set_paused(closing and _settings_return_to_pause)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Game.simulation_paused else Input.MOUSE_MODE_CAPTURED

func _apply_setting_key(key: int) -> void:
	match key:
		KEY_1: Game.settings["mouse_sensitivity"]=clampf(float(Game.settings["mouse_sensitivity"])-.1,.2,3)
		KEY_2: Game.settings["mouse_sensitivity"]=clampf(float(Game.settings["mouse_sensitivity"])+.1,.2,3)
		KEY_3: Game.settings["invert_y"]=not bool(Game.settings["invert_y"])
		KEY_4: Game.settings["reduced_shake"]=not bool(Game.settings["reduced_shake"])
		KEY_5: Game.settings["hud_visible"]=not bool(Game.settings["hud_visible"])
	hud.set_gameplay_visible(bool(Game.settings["hud_visible"]))
	hud.refresh_settings()

func _take_screenshot() -> void:
	var folder := "user://screenshots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder=arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	var file := folder+"/native_%d.png"%Time.get_ticks_msec()
	var result := get_viewport().get_texture().get_image().save_png(file)
	print("[native-screenshot] ",file," result=",result," player=",player.global_position," mode=",Game.mode)

## QA entry points are loaded by path; a script that fails to parse used to
## leave the automation idling until its outer bound (wave 4 capture_director).
## Fail fast and loudly instead.
func _qa_system(path: String) -> Node:
	var script := load(path) as Script
	if script == null or not script.can_instantiate():
		push_error("QA system failed to load: " + path)
		get_tree().quit(3)
		return Node.new()
	return script.new()
