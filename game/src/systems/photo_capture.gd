extends Node
## Fixed-view photo capture (VERIFY-03 "fixed-view screenshots").
##
## These frames are shot from a free camera at authored vantage points. They are
## evidence of what the district looks like, not proof that a player can reach
## those views, and the capture log labels them as fixture-assisted.

var main: Node
var world: WorldBuilder
var out_dir := "captures"
var _shots := 0
var _log: Array[String] = []
var _view_records: Array[Dictionary] = []
var _active_view: Dictionary = {}

func setup(m: Node, w: WorldBuilder, dir: String) -> void:
	main = m
	world = w
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	if "--gameplay-photos" in OS.get_cmdline_user_args():
		_run_gameplay()
	else:
		_run()

func _log_line(text: String) -> void:
	_log.append(text)
	print("[photo] ", text)

func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	# Fixed-view stills are look evidence, not gameplay evidence: hide the HUD so
	# the frame shows the district rather than the objective card.
	if main != null and main.get("hud") != null:
		main.hud.set_gameplay_visible(false)
	var views := [
		# Wave 3: the two former vantage points sat inside a shophouse module and
		# inside the hawker hall, so "street" evidence was actually an interior
		# wall. They now stand on the public carriageway and five-foot way.
		{"name": "street_heritage", "pos": Vector3(-150.0, 2.6, -157.0), "look": Vector3(-40.0, 5.0, -155.0), "fov": 64.0},
		{"name": "street_wide", "pos": Vector3(8.0, 5.5, -158.0), "look": Vector3(-150.0, 8.0, -160.0), "fov": 75.0},
		{"name": "hawker_interior", "pos": Vector3(-80.0, 2.6, -70.0), "look": Vector3(-90.0, 1.8, -96.0), "fov": 66.0},
		{"name": "housing_void_deck", "pos": Vector3(-214.0, 2.2, -104.0), "look": Vector3(-262.0, 12.0, -112.0), "fov": 68.0},
		{"name": "waterfront", "pos": Vector3(30.0, 2.2, -330.0), "look": Vector3(-88.0, 60.0, -705.0), "fov": 64.0},
		{"name": "aerial_district", "pos": Vector3(250.0, 95.0, 250.0), "look": Vector3(-40.0, 0.0, -60.0), "fov": 62.0},
		{"name": "aerial_waterfront", "pos": Vector3(42.0, 68.0, -356.0), "look": Vector3(-24.0, 22.0, -242.0), "fov": 68.0},
		{"name": "street_arcade", "pos": Vector3(-32, 2.0, -149), "look": Vector3(-130, 3.0, -146), "fov": 62.0},
		{"name": "airfield", "pos": world.locations["helipad_primary"]+Vector3(-20,3,24), "look": world.locations["helipad_primary"]+Vector3(0,1.8,0), "fov": 66.0},
	]
	views.append_array(InteriorDetail.inspection_views(world.locations["safe_room"]-Vector3(0,.2,0)))
	views.append({"name":"shoreline_reverse","pos":Vector3(96,3,-337),"look":Vector3(0,42,-780),"fov":64.0})
	# Wave 5: helicopter-height view over the bayside garden toward the far-shore
	# skyline (CONCEPT-03 composition), appended so earlier indices stay stable.
	views.append({"name":"bay_skyline_aerial","pos":Vector3(120,110,-120),"look":Vector3(-60,40,-650),"fov":62.0})
	var cam := Camera3D.new()
	cam.current = true
	cam.far = 2000.0
	add_child(cam)
	for view in views:
		_active_view=view
		cam.make_current()
		cam.global_position = view["pos"]
		cam.fov = float(view["fov"])
		cam.look_at(view["look"], Vector3.UP)
		await get_tree().create_timer(0.35).timeout
		await _shot(String(view["name"]))
	_write_log()

## Normal third-person gameplay frames: the real player avatar, the real HUD,
## live traffic and pedestrians. The manager asked for gameplay evidence rather
## than free-camera postcards, because a postcard cannot show whether the street
## is actually populated or playable.
func _run_gameplay() -> void:
	await get_tree().create_timer(0.8).timeout
	Game.simulation_paused = false
	if main.has_method("_start_game"):
		main._start_game()
	var player: Node3D = main.player
	player.visible = true
	var spots := [
		{"name": "opening_start", "pos": world.locations["player_start"], "yaw": deg_to_rad(WorldBuilder.PLAYER_START_YAW_DEG)},
		{"name": "heritage_arcade", "pos": Vector3(-150.0, 0.45, -148.0), "yaw": deg_to_rad(-56.0)},
		{"name": "heritage_road", "pos": Vector3(-34.0, 0.45, -156.0), "yaw": deg_to_rad(-38.0)},
		# Stand north of the pavilion looking south into it, so the hall reads as
		# a place rather than a stall counter filling the frame.
		{"name": "hawker_approach", "pos": Vector3(-100.0, 0.45, -122.0), "yaw": deg_to_rad(180.0)},
		{"name": "junction_traffic", "pos": Vector3(-12.0, 0.45, -52.0), "yaw": deg_to_rad(-18.0)},
		{"name": "waterfront_promenade", "pos": Vector3(64.0, 0.45, -336.0), "yaw": deg_to_rad(22.0)},
		{"name": "supertree_grove_vista", "pos": Vector3(-6.0, 0.45, -150.0), "yaw": deg_to_rad(18.0)},
	]
	for spot in spots:
		_active_view = spot
		player.respawn_at(spot["pos"], spot["yaw"])
		player.pitch = WorldBuilder.PLAYER_START_PITCH if spot["name"] == "opening_start" else -0.12
		# Let the AI settle and traffic roll into frame before the shutter.
		await get_tree().create_timer(2.4).timeout
		# respawn_at publishes a checkpoint toast; it is not part of the look.
		if main.get("hud") != null:
			main.hud.clear_notifications()
		if player.camera != null:
			player.camera.current = true
		await get_tree().create_timer(0.5).timeout
		await _shot("gameplay_" + String(spot["name"]))
	_write_log()

func _shot(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var native_size := img.get_size()
	_view_records.append({"name":view_name,"camera_position":str(_active_view.get("pos","")),"camera_look":str(_active_view.get("look","")),"fov":_active_view.get("fov",0),"render_pixels":[native_size.x,native_size.y],"saved_pixels":[1280,720]})
	img.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	_shots += 1
	var path := "%s/photo_%02d_%s.png" % [out_dir, _shots, view_name]
	img.save_png(path)
	_log_line("saved %s" % path)

func _write_log() -> void:
	var f := FileAccess.open("%s/photo_log.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"views": _log, "view_records":_view_records, "note": "fixed-view captures from an authored camera; fixture-assisted, not player-reachable proof"}, "\t"))
		f.close()
	_log_line("done")
	Game.simulation_paused = true
	Sfx.shutdown_audio()
	await get_tree().create_timer(.15,true,false,true).timeout
	get_tree().quit(0)
