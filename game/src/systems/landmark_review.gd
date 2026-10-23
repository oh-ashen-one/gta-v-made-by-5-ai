extends Node
## --landmark-review: capture spec of the downtown-landmarks piece (wave M).
##  1. Street-level and helicopter-height stills at every landmark (free
##     fixture camera, HUD hidden; look evidence, not reachability proof).
##  2. Third-person footage of the REAL player walking across the Helix
##     Bridge end to end (player controller + its own camera), frames as JPEG
##     with frames.jsonl for game/tools/encode_capture.py, plus walk.json with
##     the sampled path (proof the deck is walkable in the rendered build).
## Output: --capture-dir=ABS. Never writes the player's save slot.

const FPS := 15.0
var main: Node
var world: WorldBuilder
var out_dir := "user://landmark_review"
var _log: Array[String] = []

func setup(m: Node, w: WorldBuilder, dir: String) -> void:
	main = m
	world = w
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func _views() -> Array:
	var mbs := DowntownPlan.anchor("marina_bay_sands")
	var fl := DowntownPlan.anchor("singapore_flyer")
	var fyaw := deg_to_rad(-35.0)
	var fb := Basis(Vector3.UP, fyaw)
	var g := DowntownPlan.anchor("gardens_supertree_grove")
	var path: Array = world.get_meta("helix_path", [])
	var hmid: Vector3 = path[int(path.size() * 0.42)] if path.size() > 10 else Vector3(-400, 3.6, -748)
	var hfar: Vector3 = path[path.size() - 1] if path.size() > 10 else Vector3(-270, 0.4, -745)
	return [
		{"name": "mbs_podium_entrance", "pos": Vector3(-104.0, 3.2, -647.0), "look": Vector3(-118.0, 34.0, -690.0), "fov": 72.0},
		{"name": "mbs_event_plaza_promenade", "pos": Vector3(-20.0, 2.0, -627.0), "look": Vector3(-170.0, 42.0, -690.0), "fov": 68.0},
		{"name": "helix_on_bridge", "pos": hmid + Vector3(0, 1.7, 0), "look": hfar + Vector3(40.0, 30.0, 20.0), "fov": 66.0},
		{"name": "helix_from_quay", "pos": Vector3(-505.0, 2.2, -722.0), "look": Vector3(-385.0, 5.0, -752.0), "fov": 64.0},
		{"name": "merlion_park_to_mbs", "pos": Vector3(-470.0, 2.96, -395.0), "look": Vector3(-118.0, 90.0, -705.0), "fov": 60.0},
		{"name": "fullerton_frontage", "pos": Vector3(-452.0, 1.8, -335.0), "look": Vector3(-500.0, 16.0, -280.0), "fov": 66.0},
		{"name": "esplanade_under_durians", "pos": Vector3(-662.0, 1.8, -505.0), "look": Vector3(-700.0, 28.0, -545.0), "fov": 74.0},
		{"name": "esplanade_waterfront", "pos": Vector3(-650.0, 1.7, -390.0), "look": Vector3(-712.0, 15.0, -500.0), "fov": 64.0},
		{"name": "flyer_terminal", "pos": fl + fb * Vector3(18.0, 1.8, -78.0), "look": fl + Vector3(0, 55.0, 0), "fov": 70.0},
		{"name": "supertree_grove_inside", "pos": g + Vector3(-6.0, 1.8, 2.0), "look": g + Vector3(-34.0, 26.0, -20.0), "fov": 76.0},
		{"name": "gardens_to_mbs", "pos": Vector3(40.0, 1.7, -960.0), "look": Vector3(-118.0, 90.0, -705.0), "fov": 66.0},
		{"name": "artscience_pond", "pos": Vector3(-262.0, 1.9, -618.0), "look": Vector3(-292.0, 22.0, -595.0), "fov": 70.0},
		{"name": "heli_mbs_bay", "pos": Vector3(60.0, 150.0, -500.0), "look": mbs + Vector3(0, 110.0, 0), "fov": 62.0},
		{"name": "heli_mbs_north", "pos": Vector3(-480.0, 220.0, -560.0), "look": mbs + Vector3(-40.0, 150.0, 0), "fov": 62.0},
		{"name": "heli_skypark_deck", "pos": Vector3(-330.0, 270.0, -650.0), "look": mbs + Vector3(-40.0, 196.0, 0), "fov": 60.0},
		{"name": "aerial_marina_bay", "pos": Vector3(-900.0, 260.0, -200.0), "look": Vector3(-150.0, 0.0, -650.0), "fov": 62.0},
	]

func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	if main != null and main.get("hud") != null:
		main.hud.set_gameplay_visible(false)
	Game.simulation_paused = false
	var cam := Camera3D.new()
	cam.far = 3000.0
	add_child(cam)
	cam.make_current()
	var records := []
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--landmark-views="):
			only = arg.trim_prefix("--landmark-views=")
	for view: Dictionary in _views():
		if only != "" and not only.split(",").has(String(view["name"])):
			continue
		cam.make_current()
		cam.global_position = view["pos"]
		cam.fov = float(view["fov"])
		cam.look_at(view["look"], Vector3.UP)
		await get_tree().create_timer(0.5).timeout
		for i in 3:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			if img.get_width() != 1280:
				img.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
			var path := out_dir.path_join("lm_%s.png" % view["name"])
			img.save_png(path)
			_log.append(path)
			records.append({"name": view["name"], "pos": str(view["pos"]), "look": str(view["look"]), "fov": view["fov"],
				"fps": Engine.get_frames_per_second(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
			print("[landmark-review] saved ", path)
	if not "--no-helix-walk" in OS.get_cmdline_user_args():
		await _helix_walk()
	var f := FileAccess.open(out_dir.path_join("landmark_review.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"stills": records, "note": "fixture camera stills (HUD hidden); helix_walk = real player controller"}, "\t"))
		f.close()
	Game.simulation_paused = true
	Sfx.shutdown_audio()
	await get_tree().create_timer(.15, true, false, true).timeout
	get_tree().quit(0)

func _helix_walk() -> void:
	var player = main.get("player")
	var path: Array = world.get_meta("helix_path", [])
	if player == null or path.size() < 10:
		return
	var walk_dir := out_dir.path_join("helix_walk")
	DirAccess.make_dir_recursive_absolute(walk_dir)
	var start: Vector3 = path[0]
	var goal: Vector3 = path[path.size() - 1]
	var dir0: Vector3 = ((path[3] as Vector3) - start).normalized()
	player.respawn_at(start - dir0 * 3.0 + Vector3(0, 0.6, 0), atan2(-dir0.x, -dir0.z))
	player.pitch = -0.05
	if main.get("hud") != null:
		main.hud.clear_notifications()
	for i in 30:
		await get_tree().physics_frame
	player.camera.current = true
	var log := FileAccess.open(walk_dir.path_join("frames.jsonl"), FileAccess.WRITE)
	Input.action_press("move_forward")
	var idx := 0
	var t0 := Time.get_ticks_usec()
	var next := t0
	var n := 0
	var samples := []
	var reached := false
	while Time.get_ticks_usec() - t0 < 150 * 1000000:
		await RenderingServer.frame_post_draw
		var p: Vector3 = player.global_position
		while idx < path.size() - 1 and Vector2(p.x - (path[idx] as Vector3).x, p.z - (path[idx] as Vector3).z).length() < 6.0:
			idx += 1
		var target: Vector3 = path[mini(idx + 2, path.size() - 1)]
		var d := Vector3(target.x - p.x, 0, target.z - p.z)
		if d.length() > 0.1:
			player.yaw = lerp_angle(player.yaw, atan2(-d.x, -d.z), 0.08)
		var now := Time.get_ticks_usec()
		if now >= next:
			next += int(1000000.0 / FPS)
			var img := get_viewport().get_texture().get_image()
			if img != null:
				if img.get_width() != 1280:
					img.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
				var file := "f_%05d.jpg" % n
				img.save_jpg(walk_dir.path_join(file), 0.86)
				if log:
					log.store_line(JSON.stringify({"file": file, "seconds": float(now - t0) / 1000000.0, "shot": "helix_walk"}))
				if n % 75 == 0:
					img.save_png(out_dir.path_join("lm_helix_walk_%03d.png" % (n / 75)))
				n += 1
				samples.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
		if Vector2(p.x - goal.x, p.z - goal.z).length() < 3.0:
			reached = true
			break
		if p.y < -0.5:
			break
	Input.action_release("move_forward")
	if log:
		log.close()
	var f := FileAccess.open(out_dir.path_join("helix_walk.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"reached_far_end": reached, "frames": n, "seconds": float(Time.get_ticks_usec() - t0) / 1000000.0, "samples": samples}))
		f.close()
	print("[landmark-review] helix walk reached=", reached, " frames=", n)
