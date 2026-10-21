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

func setup(m: Node, w: WorldBuilder, dir: String) -> void:
	main = m
	world = w
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func _log_line(text: String) -> void:
	_log.append(text)
	print("[photo] ", text)

func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	var views := [
		{"name": "street_heritage", "pos": Vector3(-150.0, 2.4, -52.0), "look": Vector3(-40.0, 6.0, -70.0), "fov": 62.0},
		{"name": "street_wide", "pos": Vector3(-20.0, 3.2, -12.0), "look": Vector3(-120.0, 8.0, -30.0), "fov": 70.0},
		{"name": "hawker_interior", "pos": Vector3(-80.0, 2.6, -70.0), "look": Vector3(-90.0, 1.8, -96.0), "fov": 66.0},
		{"name": "housing_void_deck", "pos": Vector3(-214.0, 2.2, -104.0), "look": Vector3(-262.0, 12.0, -112.0), "fov": 68.0},
		{"name": "waterfront", "pos": Vector3(60.0, 6.0, -300.0), "look": Vector3(-40.0, 10.0, -60.0), "fov": 70.0},
		{"name": "aerial_district", "pos": Vector3(250.0, 95.0, 250.0), "look": Vector3(-40.0, 0.0, -60.0), "fov": 62.0},
		{"name": "aerial_waterfront", "pos": Vector3(40.0, 70.0, -250.0), "look": Vector3(-20.0, 0.0, 40.0), "fov": 64.0},
		{"name": "airfield", "pos": Vector3(215.0, 3.0, 215.0), "look": Vector3(245.0, 3.0, 240.0), "fov": 66.0},
	]
	var cam := Camera3D.new()
	cam.current = true
	cam.far = 2000.0
	add_child(cam)
	for view in views:
		cam.global_position = view["pos"]
		cam.fov = float(view["fov"])
		cam.look_at(view["look"], Vector3.UP)
		await get_tree().create_timer(0.35).timeout
		await _shot(String(view["name"]))
	_write_log()

func _shot(view_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	img.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	_shots += 1
	var path := "%s/photo_%02d_%s.png" % [out_dir, _shots, view_name]
	img.save_png(path)
	_log_line("saved %s" % path)

func _write_log() -> void:
	var f := FileAccess.open("%s/photo_log.json" % out_dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"views": _log, "note": "fixed-view captures from an authored camera; fixture-assisted, not player-reachable proof"}, "\t"))
		f.close()
	_log_line("done")
	get_tree().quit(0)
