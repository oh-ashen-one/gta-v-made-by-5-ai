extends Node
## `--traffic-review` (traffic-flow, wave T): live junction footage in normal
## play. A street-level camera stands at a corner of each named downtown
## junction for SECONDS of simulated traffic; every 0.5 s it saves a frame
## (rendered runs only) and measures the junction: lane cars within 30 m of
## its centre, cars standing on a zebra or inside the box, the longest
## standstill, and how many cars crossed the junction. Writes
## traffic_review.json. Headless runs measure only (no frames).

const SECONDS := 45.0
const SPOTS := [
	# name, junction centre, camera, look-at
	{"name": "collyer_quay_cecil", "centre": Vector3(-430.0, 0.0, -320.0), "cam": Vector3(-447.0, 2.4, -301.0), "look": Vector3(-420.0, 1.0, -326.0)},
	{"name": "raffles_bayfront_corner", "centre": Vector3(-790.0, 0.0, -780.0), "cam": Vector3(-808.0, 2.4, -756.0), "look": Vector3(-782.0, 1.0, -786.0)},
	{"name": "esplanade_connaught", "centre": Vector3(-660.0, 0.0, -360.0), "cam": Vector3(-676.0, 2.4, -340.0), "look": Vector3(-652.0, 1.0, -366.0)},
	{"name": "collyer_quay_legacy", "centre": Vector3(-320.0, 0.0, -320.0), "cam": Vector3(-338.0, 2.4, -302.0), "look": Vector3(-312.0, 1.0, -326.0)},
]

var main: Node
var player: Player
var traffic: TrafficManager
var out_dir := "user://traffic_review"
var _results := {}

func setup(main_node: Node, p: Player, t: TrafficManager, dir: String) -> void:
	main = main_node
	player = p
	traffic = t
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	Game.simulation_paused = false
	if main.get("hud") != null:
		main.hud.clear_notifications()
		main.hud.set_gameplay_visible(false)
	var cam := Camera3D.new()
	cam.far = 2000.0
	cam.fov = 62.0
	add_child(cam)
	cam.make_current()
	var amb := traffic.ambient
	for spot: Dictionary in SPOTS:
		var centre: Vector3 = spot["centre"]
		# The player stands behind the lens on the pavement (traffic yields
		# to a player in the road, so keep him out of it).
		var back: Vector3 = (spot["cam"] as Vector3) - ((spot["look"] as Vector3) - (spot["cam"] as Vector3)).normalized() * 2.5
		player.respawn_at(Vector3(back.x, 0.6, back.z), 0.0)
		cam.global_position = spot["cam"]
		cam.look_at(spot["look"], Vector3.UP)
		await get_tree().create_timer(4.0).timeout   # let the camera cut settle
		var near_sum := 0
		var near_min := 999
		var samples := 0
		var zebra := 0
		var boxed := 0
		var max_idle := 0.0
		var seen := {}
		var crossed := 0
		var t := 0.0
		var k := 0
		while t < SECONDS:
			await get_tree().create_timer(0.5).timeout
			t += 0.5
			k += 1
			var n := 0
			for v in amb.vehicles:
				if not v.active:
					continue
				var d := Vector2(v.global_position.x - centre.x, v.global_position.z - centre.z).length()
				if d < 30.0:
					n += 1
				if d < 14.0 and not seen.has(v):
					seen[v] = true
					crossed += 1
				if d > 60.0 or v.speed > 0.3:
					continue
				if v.j_len > 0.0 and v.s < amb._entry(v.edge):
					boxed += 1
				elif amb._on_zebra(v.edge, v.s, v.dims.z * 0.5):
					zebra += 1
				max_idle = maxf(max_idle, v.idle_time)
			near_sum += n
			near_min = mini(near_min, n)
			samples += 1
			if not _headless() and k % 1 == 0:
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				if img != null:
					img.save_jpg("%s/%s_%03d.jpg" % [out_dir, spot["name"], k], 0.88)
		var r := {"mean_within_30m": snappedf(float(near_sum) / maxf(1, samples), 0.1), "min_within_30m": near_min, "zebra_stop_samples": zebra,
			"box_stop_samples": boxed, "max_idle_s": snappedf(max_idle, 0.1), "cars_through_per_min": snappedf(crossed * 60.0 / SECONDS, 0.1)}
		_results[spot["name"]] = r
		print("[traffic-review] %s %s" % [spot["name"], JSON.stringify(r)])
	var f := FileAccess.open(out_dir + "/traffic_review.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"results": _results, "stats": amb.stats, "seconds_per_spot": SECONDS}, "\t", false))
		f.close()
	print("[traffic-review] done")
	Game.simulation_paused = true
	Sfx.shutdown_audio()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0)
