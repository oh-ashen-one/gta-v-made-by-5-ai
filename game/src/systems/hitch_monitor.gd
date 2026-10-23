class_name HitchMonitor
extends Node
## Wave T performance piece: opt-in hitch log (`--hitch-log=ABS_FILE.jsonl`).
## Every frame interval above HITCH_MS is written with the game time, mode and
## the last few gameplay events (vehicle entered/exited, mode changes), and a
## summary of the worst frame within WINDOW_S after each vehicle entry / exit.
## The capture route only records stalls above 100 ms; the acceptance for
## mode switches is 50 ms.

const HITCH_MS := 50.0
const WINDOW_S := 3.0

var _file: FileAccess
var _last := 0
var _t0 := 0
var _events: Array = []        # [t_s, name]
var _windows: Array = []       # {name, t, worst_ms}

static func path_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hitch-log="):
			return a.trim_prefix("--hitch-log=")
	return ""

func setup(path: String) -> void:
	name = "HitchMonitor"
	process_priority = -1000000
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)
	_t0 = Time.get_ticks_usec()
	Events.vehicle_entered.connect(func(v: Node) -> void: _event("vehicle_entered:" + String(v.name)))
	Events.vehicle_exited.connect(func(_v: Node) -> void: _event("vehicle_exited"))
	Events.mode_changed.connect(func(m: int) -> void: _event("mode:%d" % m))

func _event(n: String) -> void:
	var t := (Time.get_ticks_usec() - _t0) / 1000000.0
	_events.append([t, n])
	if _events.size() > 8:
		_events.pop_front()
	_windows.append({"name": n, "t": snappedf(t, 0.01), "worst_ms": 0.0, "over_50": 0})

func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last == 0:
		_last = now
		return
	var ms := (now - _last) / 1000.0
	_last = now
	var t := (now - _t0) / 1000000.0
	for w in _windows:
		if t - float(w["t"]) <= WINDOW_S:
			w["worst_ms"] = maxf(float(w["worst_ms"]), snappedf(ms, 0.1))
			if ms > HITCH_MS:
				w["over_50"] = int(w["over_50"]) + 1
	if ms > HITCH_MS and _file != null:
		_file.store_line(JSON.stringify({"t": snappedf(t, 0.01), "ms": snappedf(ms, 0.1), "mode": Game.mode, "recent": _events.slice(-3)}))
		_file.flush()

func _exit_tree() -> void:
	if _file != null:
		_file.store_line(JSON.stringify({"summary_windows": _windows}))
		_file.close()
		_file = null
