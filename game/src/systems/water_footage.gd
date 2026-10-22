extends Node
## --water-footage: short fixed-camera footage of the bay for the water piece.
## Three moving shots (promenade dolly, Merlion jet, aerial pass over the
## boats). Frames are real viewport readbacks written as JPEG with a
## frames.jsonl timeline that game/tools/encode_capture.py turns into MP4.
## Stills of each shot's midpoint are saved as PNG next to them.
## Fixture camera, HUD hidden; not gameplay evidence.

const FPS := 15.0
var main: Node
var world: WorldBuilder
var out_dir := "user://water_footage"
var _log: FileAccess
var _index := 0
var _t0 := 0

func setup(m: Node, w: WorldBuilder, dir: String) -> void:
	main = m
	world = w
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func _shots() -> Array:
	var m: Vector3 = world.locations.get("merlion", Vector3(45.0, 0.3, -345.0))
	return [
		{"name": "promenade_dolly", "seconds": 6.0, "fov": 60.0,
			"from": Vector3(140.0, 2.6, -344.0), "to": Vector3(75.0, 2.6, -344.0),
			"look_from": Vector3(-60.0, 10.0, -560.0), "look_to": Vector3(-110.0, 14.0, -560.0)},
		{"name": "merlion_jet", "seconds": 5.0, "fov": 55.0,
			"from": m + Vector3(22.0, 2.4, -26.0), "to": m + Vector3(12.0, 2.2, -30.0),
			"look_from": m + Vector3(0.0, 4.0, -10.0), "look_to": m + Vector3(0.0, 4.0, -10.0)},
		{"name": "bay_aerial", "seconds": 6.0, "fov": 62.0,
			"from": Vector3(220.0, 75.0, -330.0), "to": Vector3(40.0, 75.0, -330.0),
			"look_from": Vector3(0.0, 0.0, -520.0), "look_to": Vector3(-160.0, 0.0, -520.0)},
	]

func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	if main != null and main.get("hud") != null:
		main.hud.set_gameplay_visible(false)
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	_log = FileAccess.open(out_dir.path_join("frames.jsonl"), FileAccess.WRITE)
	_t0 = Time.get_ticks_usec()
	for shot in _shots():
		var dur: float = shot["seconds"]
		var start := Time.get_ticks_usec()
		var next := start
		var mid_saved := false
		cam.fov = shot["fov"]
		while true:
			var now := Time.get_ticks_usec()
			var u := clampf(float(now - start) / (dur * 1000000.0), 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			cam.global_position = (shot["from"] as Vector3).lerp(shot["to"], e)
			cam.look_at((shot["look_from"] as Vector3).lerp(shot["look_to"], e), Vector3.UP)
			await RenderingServer.frame_post_draw
			if now >= next:
				next += int(1000000.0 / FPS)
				var img := get_viewport().get_texture().get_image()
				if img != null:
					if img.get_width() != 1280:
						img.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
					var file := "f_%05d.jpg" % _index
					img.save_jpg(out_dir.path_join(file), 0.88)
					if _log:
						_log.store_line(JSON.stringify({"file": file, "seconds": float(Time.get_ticks_usec() - _t0) / 1000000.0, "shot": shot["name"]}))
					_index += 1
					if not mid_saved and u >= 0.5:
						img.save_png(out_dir.path_join("still_%s.png" % shot["name"]))
						mid_saved = true
			if u >= 1.0:
				break
	if _log:
		_log.close()
	print("[water-footage] frames=", _index, " dir=", out_dir)
	await _perf_ab(cam)
	Game.simulation_paused = true
	Sfx.shutdown_audio()
	await get_tree().create_timer(.15, true, false, true).timeout
	get_tree().quit(0)

## GPU cost of the planar reflection: the photo_16 aerial pose measured with
## the reflection pass on, then off (RenderingServer per-viewport timers).
func _perf_ab(cam: Camera3D) -> void:
	var bay: BayWater = world.bay
	if bay == null:
		return
	cam.global_position = Vector3(120, 110, -120)
	cam.fov = 62.0
	cam.look_at(Vector3(-60, 40, -650), Vector3.UP)
	var main_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(main_rid, true)
	var refl_rid := RID()
	if bay.reflection_viewport != null:
		refl_rid = bay.reflection_viewport.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(refl_rid, true)
	var report := {}
	for mode in ["reflection_on", "reflection_off"]:
		bay.reflection_enabled = mode == "reflection_on"
		for i in 20:
			await RenderingServer.frame_post_draw
		var gpu := 0.0
		var refl := 0.0
		var cpu := 0.0
		var interval := 0.0
		var n := 90
		var last := Time.get_ticks_usec()
		for i in n:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			interval += float(now - last) / 1000.0
			last = now
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(main_rid)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(main_rid)
			if refl_rid.is_valid() and bay.reflection_active:
				refl += RenderingServer.viewport_get_measured_render_time_gpu(refl_rid)
		report[mode] = {"main_gpu_ms": snappedf(gpu / n, 0.01), "main_cpu_ms": snappedf(cpu / n, 0.01),
			"reflection_gpu_ms": snappedf(refl / n, 0.01), "frame_interval_ms": snappedf(interval / n, 0.01),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		if gpu <= 0.0:
			# Godot's Metal backend returns 0 for viewport GPU timestamps; say
			# so instead of reporting a fake 0 ms (critic water-A1).
			report[mode]["main_gpu_ms"] = null
			report[mode]["reflection_gpu_ms"] = null
			report[mode]["gpu_timer_note"] = "GPU timestamps unavailable on this backend; use frame_interval_ms (wall time per frame)"
	bay.reflection_enabled = true
	print("[water-perf] ", JSON.stringify(report))
	var f := FileAccess.open(out_dir.path_join("water_perf.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()

