extends Node
## Wave T performance piece: CPU frame attribution per physics tick and per
## frame (headless or rendered).
##
## Godot's TIME_PHYSICS_PROCESS / TIME_PROCESS monitors are the WORST tick /
## frame of the last second, so they over-state the steady cost. This probe
## timestamps every tick instead:
##   script_tick_ms  first -> last _physics_process of one tick (scripts,
##                   move_and_slide, animation in physics mode)
##   engine_tick_ms  last script of tick k -> first script of tick k+1 inside
##                   the same frame (solver step, sync, flush_queries, Area
##                   callbacks, deferred calls)
##   process_ms      first -> last _process of one frame
## and then switches off one script family at a time (process_mode DISABLED
## on every node running that script, so its subtree stops too).
## Headless frames are free-running, so `--cpu-budget-render-ms=N` (default
## 12) sleeps N ms per frame to give the real ~1.5 ticks per frame.
##   --cpu-budget                       default views, top families
##   --cpu-budget-views=a,b             subset of views
##   --cpu-budget-seconds=N             seconds per sample (default 3)
##   --cpu-budget-families=N            families toggled per view (default 10)

var main: Node
var out_dir := "user://cpu_budget"
var _rows: Array[Dictionary] = []
var _render_ms := 12.0

var _t_first := 0
var _t_last := 0
var _last_tick_frame := -1
var _script_ticks: Array[float] = []
var _engine_ticks: Array[float] = []
var _ticks := 0
var _p_first := 0
var _process: Array[float] = []
var _recording := false

const VIEWS := [
	{"name": "street_opening", "pos": Vector3(-150.0, 2.6, -157.0), "look": Vector3(-40.0, 5.0, -155.0)},
	{"name": "drive_avenue", "pos": Vector3(-6.0, 3.0, -120.0), "look": Vector3(-6.0, 2.0, 40.0)},
	{"name": "downtown_street", "pos": Vector3(-360.0, 2.0, -300.0), "look": Vector3(-360.0, 4.0, -200.0)},
	{"name": "aerial_district", "pos": Vector3(250.0, 95.0, 250.0), "look": Vector3(-40.0, 0.0, -60.0)},
	{"name": "aerial_downtown", "pos": Vector3(-150.0, 120.0, -260.0), "look": Vector3(-420.0, 20.0, -720.0)},
	{"name": "heli_bay_down", "pos": Vector3(10.0, 112.0, -320.0), "look": Vector3(-25.0, 0.0, -400.0)},
]

class _Stamp extends Node:
	var probe: Node
	var kind := 0   # 0 physics first, 1 physics last, 2 process first, 3 process last, 4 render sleep
	func _physics_process(_d: float) -> void:
		if kind == 0: probe._phys_first()
		elif kind == 1: probe._phys_last()
	func _process(_d: float) -> void:
		if kind == 2: probe._proc_first()
		elif kind == 3: probe._proc_last()
		elif kind == 4 and probe._render_ms > 0.0 and DisplayServer.get_name() == "headless":
			OS.delay_usec(int(probe._render_ms * 1000.0))

func _stamp(kind: int, prio: int) -> void:
	var n := _Stamp.new()
	n.probe = self
	n.kind = kind
	n.process_priority = prio
	n.process_physics_priority = prio
	n.set_physics_process(kind <= 1)
	n.set_process(kind >= 2)
	get_tree().root.add_child.call_deferred(n)

func _phys_first() -> void:
	var now := Time.get_ticks_usec()
	if _recording and _last_tick_frame == Engine.get_process_frames() and _t_last > 0:
		_engine_ticks.append((now - _t_last) / 1000.0)
	_t_first = now

func _phys_last() -> void:
	_t_last = Time.get_ticks_usec()
	_last_tick_frame = Engine.get_process_frames()
	if _recording:
		_script_ticks.append((_t_last - _t_first) / 1000.0)
		_ticks += 1

func _proc_first() -> void:
	_p_first = Time.get_ticks_usec()

func _proc_last() -> void:
	if _recording:
		_process.append((Time.get_ticks_usec() - _p_first) / 1000.0)

func setup(m: Node, dir: String) -> void:
	main = m
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_render_ms = float(_arg("--cpu-budget-render-ms=", "12"))
	_stamp(0, -1000000)
	_stamp(1, 1000000)
	_stamp(2, -1000000)
	_stamp(3, 1000000)
	_stamp(4, 1000001)
	_run()

static func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return fallback

static func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"n": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in values:
		total += v
	return {"n": values.size(), "mean": snappedf(total / values.size(), 0.01), "p50": snappedf(sorted[int(sorted.size() * 0.5)], 0.01),
		"p95": snappedf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], 0.01), "max": snappedf(sorted[-1], 0.01)}

func _sample(view: String, phase: String, seconds: float) -> Dictionary:
	for i in 10:
		await get_tree().physics_frame
	_script_ticks.clear()
	_engine_ticks.clear()
	_process.clear()
	_ticks = 0
	var frames: Array[float] = []
	var mon_phys: Array[float] = []
	_recording = true
	var t0 := Time.get_ticks_usec()
	var last := t0
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		mon_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_recording = false
	var s_mean: float = _stats(_script_ticks).get("mean", 0.0)
	var e_mean: float = _stats(_engine_ticks).get("mean", 0.0)
	var secs := (last - t0) / 1000000.0
	var row := {"view": view, "phase": phase, "frames": frames.size(), "ticks_per_frame": snappedf(float(_ticks) / maxf(1.0, frames.size()), 0.01),
		"script_tick_ms": _stats(_script_ticks), "engine_tick_ms": _stats(_engine_ticks), "tick_ms_est": snappedf(s_mean + e_mean, 0.01),
		"physics_ms_per_s": snappedf((s_mean + e_mean) * _ticks / maxf(0.001, secs), 0.1),
		"process_ms": _stats(_process), "frame_ms": _stats(frames), "monitor_physics_ms": _stats(mon_phys),
		"active_bodies": PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS),
		"pairs": PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS),
		"islands": PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ISLAND_COUNT)}
	_rows.append(row)
	print("[cpu-budget] %s %-28s tick %5.2f ms (script %5.2f + engine %5.2f) x %.2f/frame, process %5.2f ms, frame p50 %5.2f, active %d pairs %d" % [
		view, phase, s_mean + e_mean, s_mean, e_mean, row["ticks_per_frame"], float(_stats(_process).get("mean", 0.0)), float(_stats(frames).get("p50", 0.0)),
		row["active_bodies"], row["pairs"]])
	return row

func _families() -> Dictionary:
	var fam := {}
	for n in get_tree().root.find_children("*", "", true, false):
		if n is _Stamp or n == self:
			continue
		var key := ""
		var scr: Script = n.get_script()
		if scr != null and (n.is_physics_processing() or n.is_processing()):
			key = scr.resource_path.get_file()
			if key == "":
				key = "inner:" + String(n.get_class())
		elif n is AnimationMixer or n is Skeleton3D or n is SkeletonModifier3D:
			key = "engine:" + String(n.get_class())
		if key == "":
			continue
		if not fam.has(key):
			fam[key] = []
		fam[key].append(n)
	return fam

static func scr_name(sc: Script, n: Node) -> String:
	return sc.resource_path.get_file() if sc != null and sc.resource_path != "" else String(n.get_class())

func _census() -> Dictionary:
	var c := {}
	var shapes := 0
	for n in get_tree().root.find_children("*", "CollisionObject3D", true, false):
		var k := String(n.get_class())
		c[k] = int(c.get(k, 0)) + 1
		for o in (n as CollisionObject3D).get_shape_owners():
			shapes += (n as CollisionObject3D).shape_owner_get_shape_count(o)
	c["shapes"] = shapes
	return c

## Which actors run which simulation tier right now.
func _actor_tiers() -> Dictionary:
	var t := {"npc_near_moving": [], "npc_far": [], "npc_idle": [], "car_ai_near": [], "car_ai_far": [], "car_other_awake": []}
	var census := {}
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NPC
		if npc == null or not npc.is_inside_tree():
			continue
		var near: bool = npc.global_position.distance_squared_to(Game.player_position) <= npc._sim_near_sq()
		var key := "npc_%s_%s%s" % [NPC.State.keys()[npc.state].to_lower(), "near" if near else "far", "" if npc.is_physics_processing() else "_asleep"]
		census[key] = int(census.get(key, 0)) + 1
		if not npc.is_physics_processing():
			continue
		if npc.state == NPC.State.IDLE and npc.is_on_floor():
			t["npc_idle"].append(npc)
		elif near or npc.state != NPC.State.WALK or npc.is_hostile or npc.is_police:
			t["npc_near_moving"].append(npc)
		else:
			t["npc_far"].append(npc)
	for n in get_tree().root.find_children("*", "Car", true, false):
		var car := n as Car
		var near := car.global_position.distance_squared_to(Game.player_position) <= Car.SIM_NEAR * Car.SIM_NEAR
		var key := "car_%s_%s%s" % ["player" if car.driver_is_player else ("ai" if car.has_ai else "parked"), "near" if near else "far", "" if car.is_physics_processing() else "_asleep"]
		census[key] = int(census.get(key, 0)) + 1
		if not car.is_physics_processing() or car.driver_is_player:
			continue
		if car.has_ai:
			t["car_ai_near" if near else "car_ai_far"].append(car)
		else:
			t["car_other_awake"].append(car)
	census["ambient_vehicles"] = get_tree().root.find_children("*", "AmbientVehicle", true, false).size()
	t["census"] = census
	return t

func _set_family(nodes: Array, on: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

func _ground(p: Vector3) -> Vector3:
	var space := (main as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 400.0, p.z), Vector3(p.x, -50.0, p.z), 1)
	var hit := space.intersect_ray(q)
	return (hit["position"] as Vector3) + Vector3(0.0, 0.3, 0.0) if hit else Vector3(p.x, 1.0, p.z)

func _run() -> void:
	for i in 120:
		await get_tree().physics_frame
	if main.get("hud") != null:
		main.hud.set_gameplay_visible(false)
	var census := _census()
	print("[cpu-budget] census ", JSON.stringify(census))
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	var want := _arg("--cpu-budget-views=", "").split(",", false)
	var secs := float(_arg("--cpu-budget-seconds=", "3"))
	var top_n := int(_arg("--cpu-budget-families=", "10"))
	var player: Node3D = main.player
	for v in VIEWS:
		var vn := String(v["name"])
		if not want.is_empty() and not want.has(vn):
			continue
		cam.global_position = v["pos"]
		cam.look_at(v["look"], Vector3.UP)
		cam.fov = 64.0
		var pv: Vector3 = v["pos"]
		if pv.y < 20.0:
			player.global_position = _ground(pv + (v["look"] - pv).normalized() * 4.0)
			player.set("velocity", Vector3.ZERO)
		cam.make_current()
		await get_tree().create_timer(2.0).timeout
		var base := await _sample(vn, "all", secs)
		var tiers := _actor_tiers()
		print("[cpu-budget] %s actors %s" % [vn, JSON.stringify(tiers["census"])])
		for tk in ["npc_near_moving", "npc_far", "npc_idle", "car_ai_near", "car_ai_far", "car_other_awake"]:
			if (tiers[tk] as Array).is_empty():
				continue
			_set_family(tiers[tk], false)
			await _sample(vn, "off:%s(%d)" % [tk, (tiers[tk] as Array).size()], secs)
			_set_family(tiers[tk], true)
		var fam := _families()
		# Engine-side per-frame work: skeleton modifiers and animation mixers,
		# switched off by class (frame time is the measure here).
		if _arg("--cpu-budget-engine=", "1") == "1":
			var by_class := {}
			for n in get_tree().root.find_children("*", "SkeletonModifier3D", true, false):
				var sc: Script = n.get_script()
				var k := scr_name(sc, n)
				if not by_class.has(k): by_class[k] = []
				by_class[k].append(n)
			by_class["AnimationMixer"] = get_tree().root.find_children("*", "AnimationMixer", true, false)
			for k in by_class:
				var arr: Array = by_class[k]
				var was: Array = []
				for n in arr:
					was.append(n.active)
					n.active = false
				await _sample(vn, "inactive:%s(%d)" % [k, arr.size()], secs)
				for i in arr.size():
					if is_instance_valid(arr[i]):
						arr[i].active = was[i]
		# Measure one family at a time, biggest node counts first.
		var keys: Array = fam.keys()
		keys.sort_custom(func(a, b): return (fam[a] as Array).size() > (fam[b] as Array).size())
		var tried := 0
		var deltas: Array = []
		var only := _arg("--cpu-budget-only=", "").split(",", false)
		if not only.is_empty():
			keys = keys.filter(func(k): return only.has(k))
		for k in keys:
			if tried >= top_n:
				break
			if String(k).begins_with("engine:"):
				continue
			if k in ["main.gd", "game_state.gd", "events.gd", "audio.gd"]:
				continue
			tried += 1
			_set_family(fam[k], false)
			var r := await _sample(vn, "off:%s(%d)" % [k, (fam[k] as Array).size()], secs)
			_set_family(fam[k], true)
			deltas.append({"family": k, "count": (fam[k] as Array).size(), "tick_saved_ms": snappedf(float(base["tick_ms_est"]) - float(r["tick_ms_est"]), 0.01),
				"process_saved_ms": snappedf(float(base["process_ms"].get("mean", 0.0)) - float(r["process_ms"].get("mean", 0.0)), 0.01)})
		var all_nodes: Array = []
		for k in keys:
			if String(k).begins_with("engine:") or k in ["main.gd", "game_state.gd", "events.gd", "audio.gd"]:
				continue
			all_nodes.append_array(fam[k])
		_set_family(all_nodes, false)
		var bare := await _sample(vn, "off:all_scripts", secs)
		_set_family(all_nodes, true)
		print("[cpu-budget] %s deltas %s" % [vn, JSON.stringify(deltas)])
		_rows.append({"view": vn, "deltas": deltas, "bare_engine_tick_ms": bare["tick_ms_est"]})
	var f := FileAccess.open(out_dir + "/cpu_budget.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"census": census, "render_ms_emulated": _render_ms if DisplayServer.get_name() == "headless" else 0.0, "rows": _rows}, "\t"))
	f.close()
	Sfx.shutdown_audio()
	get_tree().quit(0)
