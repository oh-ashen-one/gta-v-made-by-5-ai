extends Node
## downtown-blocks capture views (`--blocks-photos`, optional `--capture-dir=ABS`).
## Free-camera stills at street level (CBD streets, Raffles Place, Boat Quay,
## Shenton Way, MBFC), a chase-height drive-by along Cecil Street and
## helicopter-height aerials. They are fixture-assisted look evidence (the
## camera is placed, nobody drives), labelled as such in blocks_photo_log.json.
## Added views only; the fixed comparison cameras are untouched.

const VIEWS := [
	{"name": "bq_river_walk", "pos": Vector3(-527.0, 1.7, -165.0), "look": Vector3(-512.0, 7.0, -60.0), "fov": 64.0},
	{"name": "bq_from_north_bank", "pos": Vector3(-597.0, 2.2, 30.0), "look": Vector3(-505.0, 22.0, 95.0), "fov": 62.0},
	{"name": "cecil_street", "pos": Vector3(-428.0, 1.7, -160.0), "look": Vector3(-433.0, 30.0, 60.0), "fov": 66.0},
	{"name": "raffles_place", "pos": Vector3(-377.0, 1.7, -28.0), "look": Vector3(-400.0, 100.0, -150.0), "fov": 70.0},
	{"name": "chulia_corner", "pos": Vector3(-318.0, 1.7, -166.0), "look": Vector3(-450.0, 35.0, -220.0), "fov": 66.0},
	{"name": "shenton_way", "pos": Vector3(398.0, 1.7, -70.0), "look": Vector3(401.0, 28.0, 150.0), "fov": 66.0},
	{"name": "mbfc_corner", "pos": Vector3(394.0, 1.7, -338.0), "look": Vector3(480.0, 55.0, -430.0), "fov": 66.0},
	{"name": "drive_cecil_1", "pos": Vector3(-432.5, 2.1, -140.0), "look": Vector3(-432.5, 1.2, -100.0), "fov": 72.0},
	{"name": "drive_cecil_2", "pos": Vector3(-432.5, 2.1, -40.0), "look": Vector3(-432.5, 1.2, 0.0), "fov": 72.0},
	{"name": "drive_cecil_3", "pos": Vector3(-432.5, 2.1, 90.0), "look": Vector3(-432.5, 1.2, 130.0), "fov": 72.0},
	{"name": "heli_cbd", "pos": Vector3(-250.0, 170.0, 160.0), "look": Vector3(-460.0, 40.0, -110.0), "fov": 62.0},
	{"name": "heli_shenton_mbfc", "pos": Vector3(240.0, 220.0, 240.0), "look": Vector3(470.0, 40.0, -330.0), "fov": 62.0},
	{"name": "heli_cbd_high", "pos": Vector3(-200.0, 330.0, 430.0), "look": Vector3(-430.0, 0.0, -180.0), "fov": 60.0},
	{"name": "dt_aerial_marina_bay", "pos": Vector3(-900.0, 260.0, -200.0), "look": Vector3(-150.0, 0.0, -650.0), "fov": 62.0},
]

var out_dir := "user://blocks_photos"
var _log: Array = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			out_dir = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var main := get_tree().current_scene
	if main != null and main.get("hud") != null:
		main.hud.show_title(false)
		if main.hud.has_method("set_gameplay_visible"):
			main.hud.set_gameplay_visible(false)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--blocks-views="):
			only = arg.trim_prefix("--blocks-views=")
	var cam := Camera3D.new()
	cam.far = 3000.0
	add_child(cam)
	var i := 0
	for v in VIEWS:
		i += 1
		if only != "" and not String(v["name"]) in only.split(","):
			continue
		cam.make_current()
		cam.global_position = v["pos"]
		cam.fov = float(v["fov"])
		cam.look_at(v["look"], Vector3.UP)
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			continue
		var t0 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		var frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		img.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
		var path := "%s/blocks_%02d_%s.png" % [out_dir, i, v["name"]]
		img.save_png(path)
		_log.append({"name": v["name"], "pos": str(v["pos"]), "look": str(v["look"]), "fov": v["fov"], "frame_ms": frame_ms,
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)})
		print("[blocks-photo] saved ", path, " frame_ms=", frame_ms)
	var f := FileAccess.open("%s/blocks_photo_log.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"views": _log, "note": "fixture-assisted free-camera stills (downtown-blocks); drive_* views are a placed chase-height camera, not a driven car"}, "\t"))
		f.close()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
