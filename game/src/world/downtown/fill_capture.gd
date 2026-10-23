extends Node
## downtown-fill capture views (`--fill-photos`, optional `--capture-dir=ABS`,
## `--fill-views=a,b` to pick views). Added views only; the fixed comparison
## cameras in photo_capture.gd / capture_director.gd are untouched.
##   street_*: free-camera stills at eye height at the MBS arrival forecourt,
##             Merlion Park, NS Square and the Esplanade waterfront;
##   air_*:    free-camera stills ~110-140 m over the Bayfront / Marina Centre;
##   chase_*:  the real helicopter, flown by held input at ~110 m with the
##             game's own chase camera; 6 consecutive frames 0.2 s apart per
##             leg, so the rotor disc is judged in every chase frame.
## The player never touches the save slot (run with --qa-session).

const STREET := [
	{"name": "street_mbs_arrival", "pos": Vector3(-203.0, 1.7, -763.0), "look": Vector3(-160.0, 7.0, -738.0), "fov": 66.0},
	{"name": "street_mbs_walk_end", "pos": Vector3(-246.0, 1.7, -760.0), "look": Vector3(-214.0, 14.0, -722.0), "fov": 66.0},
	{"name": "street_merlion_park", "pos": Vector3(-470.0, 1.7, -395.0), "look": Vector3(-118.0, 90.0, -705.0), "fov": 60.0},
	{"name": "street_ns_square", "pos": Vector3(-632.0, 1.8, -586.0), "look": Vector3(-545.0, 6.0, -648.0), "fov": 66.0},
	{"name": "street_ns_square_cafe", "pos": Vector3(-596.0, 1.7, -598.0), "look": Vector3(-530.0, 4.0, -628.0), "fov": 64.0},
	{"name": "street_esplanade_waterfront", "pos": Vector3(-650.0, 1.7, -390.0), "look": Vector3(-712.0, 15.0, -500.0), "fov": 64.0},
	{"name": "air_bayfront_110", "pos": Vector3(-520.0, 110.0, -600.0), "look": Vector3(-150.0, 0.0, -880.0), "fov": 62.0},
	{"name": "air_marina_centre_110", "pos": Vector3(-450.0, 110.0, -640.0), "look": Vector3(-760.0, 0.0, -900.0), "fov": 62.0},
	{"name": "air_dtx_heli_bayfront", "pos": Vector3(-650.0, 140.0, -560.0), "look": Vector3(-250.0, 0.0, -800.0), "fov": 62.0},
	{"name": "air_dtx_heli_marina_centre", "pos": Vector3(-380.0, 165.0, -520.0), "look": Vector3(-770.0, 30.0, -780.0), "fov": 62.0},
	# plan views for placement checks (not judged)
	{"name": "dbg_top_esplanade", "pos": Vector3(-650.0, 70.0, -399.0), "look": Vector3(-650.0, 0.0, -400.0), "fov": 60.0},
	{"name": "dbg_top_mbs", "pos": Vector3(-170.0, 150.0, -739.0), "look": Vector3(-170.0, 0.0, -740.0), "fov": 60.0},
	{"name": "dbg_top_ns", "pos": Vector3(-580.0, 110.0, -617.0), "look": Vector3(-580.0, 0.0, -618.0), "fov": 60.0},
	{"name": "dbg_warp_a", "pos": Vector3(-641.0, 2.0, -383.0), "look": Vector3(-656.0, 0.2, -393.0), "fov": 60.0},
	{"name": "dbg_warp_b", "pos": Vector3(-655.0, 9.0, -376.0), "look": Vector3(-655.0, 0.0, -392.0), "fov": 60.0},
	{"name": "dbg_top_merlion", "pos": Vector3(-485.0, 80.0, -379.0), "look": Vector3(-485.0, 0.0, -380.0), "fov": 60.0},
]
## heli start, heading target (flown toward at cruise)
const CHASE := [
	{"name": "chase_bayfront", "pos": Vector3(-560.0, 110.0, -520.0), "toward": Vector3(-150.0, 110.0, -900.0)},
	{"name": "chase_marina_centre", "pos": Vector3(-400.0, 110.0, -1040.0), "toward": Vector3(-640.0, 110.0, -700.0)},
]

var out_dir := "user://fill_photos"
var _log: Array = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			out_dir = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	if img.get_width() != 1280:
		img.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	var path := "%s/%s.jpg" % [out_dir, label]
	img.save_jpg(path, 0.92)
	_log.append({"name": label, "draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)})
	print("[fill-photo] saved ", path)

func _run() -> void:
	var main := get_tree().current_scene
	await get_tree().create_timer(1.0).timeout
	if main != null and main.get("hud") != null:
		main.hud.show_title(false)
		main.hud.clear_notifications()
		main.set("started", true)
	Game.simulation_paused = false
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fill-views="):
			only = arg.trim_prefix("--fill-views=")
	var headless := DisplayServer.get_name() == "headless"
	var cam := Camera3D.new()
	cam.far = 3000.0
	add_child(cam)
	if main != null and main.get("hud") != null:
		main.hud.set_gameplay_visible(false)
	for v in STREET:
		if only != "" and not String(v["name"]) in only.split(","):
			continue
		cam.make_current()
		cam.global_position = v["pos"]
		cam.fov = float(v["fov"])
		cam.look_at(v["look"], Vector3.UP)
		await get_tree().create_timer(1.2).timeout
		if not headless:
			await _save(v["name"])
	var heli := main.get_node_or_null("Helicopter") as Helicopter if main != null else null
	var player: Player = main.get("player") if main != null else null
	if heli != null and player != null:
		for c in CHASE:
			if only != "" and not String(c["name"]) in only.split(","):
				continue
			if not heli.pilot_is_player:
				player.respawn_at(heli.global_position + Vector3(3.0, 0.5, 0.0), 0.0)
				await get_tree().create_timer(0.4).timeout
				heli.interact(player)
			if main.get("hud") != null:
				main.hud.set_gameplay_visible(true)
				main.hud.clear_notifications()
			var to: Vector3 = c["toward"] - c["pos"]
			heli.global_position = c["pos"]
			heli.rotation.y = atan2(-to.x, -to.z)
			heli.velocity = Vector3.ZERO
			heli.rotor_spin = 1.0
			Input.action_press("move_forward", 0.75)
			await get_tree().create_timer(5.0).timeout
			if main.get("hud") != null:
				main.hud.clear_notifications()
			for k in 6:
				await get_tree().create_timer(0.2).timeout
				if not headless:
					await _save("%s_%d" % [c["name"], k])
			Input.action_release("move_forward")
			await get_tree().create_timer(1.5).timeout
			if not headless:
				await _save("%s_hover" % c["name"])
	var f := FileAccess.open("%s/fill_photo_log.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"views": _log, "note": "street_*/air_* are placed free-camera stills; chase_* are the real helicopter flown by held input with its chase camera"}, "\t"))
		f.close()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
