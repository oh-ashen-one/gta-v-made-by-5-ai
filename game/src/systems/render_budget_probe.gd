extends Node
## Rendered draw-call / frame-time attribution (wave-M integration).
## Free camera at a few street, driving-height and aerial vantage points; for
## each, samples Godot's render monitors with the street-life families shown,
## then with one family hidden at a time (people, lane cars, avenue dressing and
## signals). Draw counts do not depend on machine load; frame times on a shared
## GPU do, so read them as relative. Run through loop/render.sh only.

var main: Node
var out_dir := "user://render_budget"
var _rows: Array[Dictionary] = []

func setup(m: Node, dir: String) -> void:
	main = m
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func _sample(view: String, phase: String, seconds: float) -> void:
	# Let visibility changes settle before sampling.
	for i in 6:
		await get_tree().process_frame
	var draws: Array[float] = []
	var prims: Array[float] = []
	var frames: Array[float] = []
	var last := Time.get_ticks_usec()
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var row := {"view": view, "phase": phase, "frames": frames.size(), "draw_calls": _stats(draws), "primitives": _stats(prims), "frame_ms": _stats(frames)}
	_rows.append(row)
	print("[budget] ", JSON.stringify(row))

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in values:
		total += v
	return {"mean": snappedf(total / values.size(), 0.01), "p50": snappedf(sorted[int(sorted.size() * 0.5)], 0.01),
		"p95": snappedf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], 0.01)}

func _show(nodes: Array, on: bool) -> void:
	for n in nodes:
		if is_instance_valid(n) and n is Node3D:
			(n as Node3D).visible = on

func _run() -> void:
	for i in 60:
		await get_tree().physics_frame
	if main.get("hud") != null:
		main.hud.set_gameplay_visible(false)
	var traffic: TrafficManager = main.traffic
	var people: Array = traffic.peds.duplicate()
	if traffic.crowd != null:
		for r in traffic.crowd.roamers:
			if not people.has(r):
				people.append(r)
	var cars: Array = []
	if traffic.ambient != null:
		cars = traffic.ambient.vehicles.duplicate()
	var dressing: Array = []
	if traffic.dressing != null:
		dressing.append(traffic.dressing)
	if traffic.signals != null:
		dressing.append(traffic.signals)
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	var views := [
		{"name": "street_opening", "pos": Vector3(-150.0, 2.6, -157.0), "look": Vector3(-40.0, 5.0, -155.0)},
		{"name": "drive_avenue", "pos": Vector3(-6.0, 3.0, -120.0), "look": Vector3(-6.0, 2.0, 40.0)},
		{"name": "downtown_street", "pos": Vector3(-360.0, 2.0, -300.0), "look": Vector3(-360.0, 4.0, -200.0)},
		{"name": "aerial_district", "pos": Vector3(250.0, 95.0, 250.0), "look": Vector3(-40.0, 0.0, -60.0)},
	]
	for v in views:
		cam.global_position = v["pos"]
		cam.look_at(v["look"], Vector3.UP)
		cam.fov = 64.0
		await get_tree().create_timer(1.5).timeout
		var name_v := String(v["name"])
		await _sample(name_v, "all", 3.0)
		_show(people, false)
		await _sample(name_v, "no_people", 3.0)
		_show(people, true)
		_show(cars, false)
		await _sample(name_v, "no_lane_cars", 3.0)
		_show(cars, true)
		_show(dressing, false)
		await _sample(name_v, "no_dressing_signals", 3.0)
		_show(dressing, true)
	var f := FileAccess.open(out_dir + "/render_budget.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"note": "Rendered draw calls per family (hidden one at a time); frame_ms on a shared GPU is relative only.", "rows": _rows}, "\t"))
	f.close()
	Sfx.shutdown_audio()
	get_tree().quit(0)
