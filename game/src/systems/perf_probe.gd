extends Node
## Headless CPU cost attribution (wave 5). Runs the live district and samples
## Godot's own per-frame process/physics timers while switching off one actor
## family at a time. CPU-side evidence only: headless has no render cost, and a
## shared machine adds noise, so read relative deltas, not absolute budgets.

var main: Node
var out_dir := "user://perf"
var _phase := ""
var _rows: Array[Dictionary] = []

func setup(m: Node, dir: String) -> void:
	main = m
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func _sample(seconds: float) -> Dictionary:
	var physics: Array[float] = []
	var process: Array[float] = []
	var frames: Array[float] = []
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	return {"phase": _phase, "frames": frames.size(), "physics_ms": _stats(physics), "process_ms": _stats(process), "frame_interval_ms": _stats(frames)}

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in values: total += v
	return {"mean": snappedf(total / values.size(), 0.01), "p50": snappedf(sorted[int(sorted.size() * 0.5)], 0.01),
		"p95": snappedf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], 0.01), "max": snappedf(sorted[-1], 0.01)}

func _set_family(nodes: Array, enabled: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.set_physics_process(enabled)
			n.set_process(enabled)

func _run() -> void:
	for i in 90:
		await get_tree().physics_frame
	var traffic: TrafficManager = main.traffic
	var peds: Array = traffic.peds.duplicate()
	var ai_cars: Array = traffic.cars.duplicate()
	var parked: Array = []
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v is Car and not traffic.cars.has(v): parked.append(v)
	var hostiles: Array = main.mission._hostiles.duplicate()
	print("[perf] peds=", peds.size(), " ai_cars=", ai_cars.size(), " parked_or_pooled=", parked.size(), " hostiles=", hostiles.size(),
		" nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_phase = "baseline"; _rows.append(await _sample(6.0))
	_phase = "no_pedestrians"; _set_family(peds, false); _rows.append(await _sample(6.0)); _set_family(peds, true)
	_phase = "no_ai_traffic"; _set_family(ai_cars, false); _rows.append(await _sample(6.0)); _set_family(ai_cars, true)
	_phase = "no_parked_cars"; _set_family(parked, false); _rows.append(await _sample(6.0)); _set_family(parked, true)
	_phase = "no_traffic_manager"; traffic.set_process(false); traffic.set_physics_process(false); _rows.append(await _sample(6.0)); traffic.set_process(true); traffic.set_physics_process(true)
	_phase = "no_actors_at_all"; _set_family(peds, false); _set_family(ai_cars, false); _set_family(parked, false); _set_family(hostiles, false); traffic.set_process(false)
	_rows.append(await _sample(6.0))
	_set_family(peds, true); _set_family(ai_cars, true); _set_family(parked, true); _set_family(hostiles, true); traffic.set_process(true)
	_phase = "baseline_again"; _rows.append(await _sample(6.0))
	for row in _rows: print("[perf] ", JSON.stringify(row))
	var f := FileAccess.open(out_dir + "/perf_probe.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"note": "Headless CPU attribution; Godot TIME_PHYSICS_PROCESS/TIME_PROCESS monitors per frame; shared machine.", "rows": _rows}, "\t"))
	f.close()
	Sfx.shutdown_audio()
	get_tree().quit(0)
