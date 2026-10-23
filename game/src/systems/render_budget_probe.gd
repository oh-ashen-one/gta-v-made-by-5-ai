extends Node
## Rendered draw-call / frame-time attribution (wave-M integration; extended by
## the wave-S performance piece).
## Free camera at fixed street, driving-height, downtown and aerial vantage
## points. For each view it samples Godot's render monitors with everything on,
## then with one feature or family switched off at a time. Every row reports
## frame time, the viewport's measured GPU time, total / visible-pass /
## shadow-pass draw calls and primitives, and CPU process/physics time.
## Draw counts do not depend on machine load; times on a shared GPU do, so read
## them as relative. Run through loop/render.sh only.
##   --render-budget                      default views and phases
##   --render-budget-views=a,b            subset of views (names below)
##   --render-budget-phases=all,no_shadows,...   subset of phases
##   --render-budget-seconds=N            seconds per sample (default 2.5)

var main: Node
var out_dir := "user://render_budget"
var _first: Node
var _last: Node
var _pfirst: Node
var _plast: Node
var _rows: Array[Dictionary] = []
var _vp_rid: RID

const VIEWS := [
	{"name": "street_opening", "pos": Vector3(-150.0, 2.6, -157.0), "look": Vector3(-40.0, 5.0, -155.0)},
	{"name": "drive_avenue", "pos": Vector3(-6.0, 3.0, -120.0), "look": Vector3(-6.0, 2.0, 40.0)},
	{"name": "downtown_street", "pos": Vector3(-360.0, 2.0, -300.0), "look": Vector3(-360.0, 4.0, -200.0)},
	{"name": "aerial_district", "pos": Vector3(250.0, 95.0, 250.0), "look": Vector3(-40.0, 0.0, -60.0)},
	# Wave S: over the Marina Bay downtown itself (CBD + MBS + bay).
	{"name": "aerial_downtown", "pos": Vector3(-150.0, 120.0, -260.0), "look": Vector3(-420.0, 20.0, -720.0)},
]
const DEFAULT_PHASES := ["all", "no_occlusion", "perf_director_off", "no_shadows", "no_ssao", "no_ssil", "no_vfog", "no_msaa", "no_taa", "no_trees",
	"no_people", "people_frozen", "lane_traffic_sim_off", "no_lane_cars", "no_parked_cars", "no_dressing_signals",
	"no_downtown_blocks", "no_downtown_landmarks", "no_downtown_map"]

func setup(m: Node, dir: String) -> void:
	main = m
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

static func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return fallback

func _info(kind: int, what: int) -> float:
	return float(RenderingServer.viewport_get_render_info(_vp_rid, kind, what))

func _sample(view: String, phase: String, seconds: float) -> void:
	# Let visibility changes settle before sampling.
	for i in 8:
		await get_tree().process_frame
	var cols := {"draw_calls": [], "primitives": [], "frame_ms": [], "gpu_ms": [], "cpu_render_ms": [], "process_ms": [],
		"physics_ms": [], "script_ms": [], "phys_step_ms": [], "visible_draws": [], "shadow_draws": [], "visible_prims": [], "shadow_prims": [], "objects": []}
	var last := Time.get_ticks_usec()
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		cols["frame_ms"].append((now - last) / 1000.0)
		last = now
		cols["draw_calls"].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		cols["primitives"].append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		cols["objects"].append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		cols["process_ms"].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		cols["physics_ms"].append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		cols["script_ms"].append(float(_last.get_meta("t", 0) - _first.get_meta("t", 0)) / 1000.0)
		cols["phys_step_ms"].append(float(_plast.get_meta("t", 0) - _pfirst.get_meta("t", 0)) / 1000.0)
		cols["gpu_ms"].append(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
		cols["cpu_render_ms"].append(RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid))
		cols["visible_draws"].append(_info(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		cols["shadow_draws"].append(_info(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		cols["visible_prims"].append(_info(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
		cols["shadow_prims"].append(_info(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
	var row := {"view": view, "phase": phase, "frames": (cols["frame_ms"] as Array).size()}
	for k in cols:
		var arr: Array[float] = []
		for v in cols[k]:
			arr.append(float(v))
		row[k] = _stats(arr)
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
		"p95": snappedf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], 0.01), "max": snappedf(sorted[-1], 0.01)}

func _tick(nodes: Array, on: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

func _show(nodes: Array, on: bool) -> void:
	for n in nodes:
		if is_instance_valid(n) and n is Node3D:
			(n as Node3D).visible = on

func _trees() -> Array:
	var out := []
	for gi in main.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh = null
		if gi is MeshInstance3D:
			mesh = gi.mesh
		elif gi is MultiMeshInstance3D and gi.multimesh != null:
			mesh = gi.multimesh.mesh
		if mesh != null and ("rain_tree" in mesh.resource_path or "rain_tree" in String(gi.name).to_lower() or "RainTree" in String(gi.name)):
			out.append(gi)
	return out

## Timestamp probes: the first and last nodes to process (and physics-process)
## each frame bracket all script, animation and physics work.
class _Stamp extends Node:
	var physics := false
	func _process(_d: float) -> void:
		if not physics: set_meta("t", Time.get_ticks_usec())
	func _physics_process(_d: float) -> void:
		if physics: set_meta("t", Time.get_ticks_usec())

func _stamp(prio: int, physics: bool) -> Node:
	var n := _Stamp.new()
	n.physics = physics
	n.process_priority = prio
	n.process_physics_priority = prio
	get_tree().root.add_child.call_deferred(n)
	return n

func _run() -> void:
	_first = _stamp(-100000, false)
	_last = _stamp(100000, false)
	_pfirst = _stamp(-100000, true)
	_plast = _stamp(100000, true)
	for i in 60:
		await get_tree().physics_frame
	if main.get("hud") != null:
		main.hud.set_gameplay_visible(false)
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	var traffic: TrafficManager = main.traffic
	var people: Array = []
	people.append_array(traffic.peds)
	if traffic.crowd != null:
		for r in traffic.crowd.roamers:
			if not people.has(r):
				people.append(r)
	var cars: Array = []
	if traffic.ambient != null:
		cars.append_array(traffic.ambient.vehicles)
	var parked: Array = []
	for c in traffic.get_children():
		if c is CharacterBody3D and not people.has(c):
			parked.append(c)
	var dressing: Array = []
	if traffic.dressing != null:
		dressing.append(traffic.dressing)
	if traffic.signals != null:
		dressing.append(traffic.signals)
	var district: Node = main.world.get_node_or_null("District")
	var families := {"no_downtown_blocks": [], "no_downtown_landmarks": [], "no_downtown_map": []}
	if district != null:
		for c in district.get_children():
			var cn := String(c.name)
			if cn.begins_with("DowntownBlock"):
				families["no_downtown_blocks"].append(c)
			elif cn.begins_with("DowntownLandmark"):
				families["no_downtown_landmarks"].append(c)
			elif cn.begins_with("DowntownMap") or cn.begins_with("DowntownTrees"):
				families["no_downtown_map"].append(c)
	var trees := _trees()
	var env: Environment = null
	var we := main.world.find_child("GoldenHourEnvironment", true, false) as WorldEnvironment
	if we != null:
		env = we.environment
	var sun := main.world.find_child("Sun", true, false) as DirectionalLight3D
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	var want_views := _arg("--render-budget-views=", "").split(",", false)
	var phases := _arg("--render-budget-phases=", ",".join(DEFAULT_PHASES)).split(",", false)
	var secs := float(_arg("--render-budget-seconds=", "2.5"))
	var vp := get_viewport()
	for v in VIEWS:
		var name_v := String(v["name"])
		if not want_views.is_empty() and not want_views.has(name_v):
			continue
		cam.global_position = v["pos"]
		cam.look_at(v["look"], Vector3.UP)
		cam.fov = 64.0
		await get_tree().create_timer(1.5).timeout
		var shot: Image = null if DisplayServer.get_name() == "headless" else vp.get_texture().get_image()
		if shot != null:
			shot.save_jpg(out_dir + "/view_%s.jpg" % name_v, 0.85)
		for phase: String in phases:
			match phase:
				"all":
					await _sample(name_v, phase, secs)
				"no_shadows":
					if sun != null:
						sun.shadow_enabled = false
						await _sample(name_v, phase, secs)
						sun.shadow_enabled = true
				"no_ssao", "no_ssil", "no_vfog", "no_glow":
					if env != null:
						var prop: String = {"no_ssao": "ssao_enabled", "no_ssil": "ssil_enabled", "no_vfog": "volumetric_fog_enabled", "no_glow": "glow_enabled"}[phase]
						var was: bool = env.get(prop)
						env.set(prop, false)
						await _sample(name_v, phase, secs)
						env.set(prop, was)
				"no_msaa":
					var was_msaa := vp.msaa_3d
					vp.msaa_3d = Viewport.MSAA_DISABLED
					await _sample(name_v, phase, secs)
					vp.msaa_3d = was_msaa
				"no_taa":
					var was_taa := vp.use_taa
					vp.use_taa = false
					await _sample(name_v, phase, secs)
					vp.use_taa = was_taa
				"no_occlusion":
					vp.use_occlusion_culling = false
					await _sample(name_v, phase, secs)
					vp.use_occlusion_culling = true
				"perf_director_off":
					var pd := main.get_node_or_null("PerfDirector")
					if pd != null:
						pd.set_active(false)
						await _sample(name_v, phase, secs)
						pd.set_active(true)
				"no_trees":
					_show(trees, false)
					await _sample(name_v, phase, secs)
					_show(trees, true)
				"no_people":
					_show(people, false)
					await _sample(name_v, phase, secs)
					_show(people, true)
				"people_frozen":
					_tick(people, false)
					await _sample(name_v, phase, secs)
					_tick(people, true)
				"crowd_director_off":
					if traffic.crowd != null:
						traffic.crowd.process_mode = Node.PROCESS_MODE_DISABLED
						await _sample(name_v, phase, secs)
						traffic.crowd.process_mode = Node.PROCESS_MODE_INHERIT
				"lane_traffic_sim_off":
					if traffic.ambient != null:
						traffic.ambient.process_mode = Node.PROCESS_MODE_DISABLED
						await _sample(name_v, phase, secs)
						traffic.ambient.process_mode = Node.PROCESS_MODE_INHERIT
				"no_lane_cars":
					_show(cars, false)
					await _sample(name_v, phase, secs)
					_show(cars, true)
				"no_parked_cars":
					_show(parked, false)
					await _sample(name_v, phase, secs)
					_show(parked, true)
				"no_dressing_signals":
					_show(dressing, false)
					await _sample(name_v, phase, secs)
					_show(dressing, true)
				_:
					if families.has(phase):
						var nodes: Array = (families[phase] as Array).filter(func(n): return n != null)
						if not nodes.is_empty():
							_show(nodes, false)
							await _sample(name_v, phase, secs)
							_show(nodes, true)
	var f := FileAccess.open(out_dir + "/render_budget.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"note": "Rendered draw calls / GPU time per feature and family (switched off one at a time); times on a shared GPU are relative only.", "rows": _rows}, "\t"))
	f.close()
	Sfx.shutdown_audio()
	get_tree().quit(0)
