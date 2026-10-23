extends Node
## --street-review (street-life piece): live junction footage and numbers.
##
## The player stands on foot at the corner of a signalled junction in normal
## play (live traffic, signals and crowds, real third-person camera and HUD),
## then a fixed eye-level camera across the junction, then a raised corner
## camera. Every second it counts, within 30 m of the junction centre, lane
## vehicles moving or queued and living pedestrians, and which signal axis is
## green. Rendered: frames are JPEG viewport readbacks with a frames.jsonl
## timeline for game/tools/encode_capture.py, plus a PNG still per shot.
## Headless: numbers only. Writes street_review.json and exits.

const FPS := 15.0
const RADIUS := 30.0
var main: Node
var world: WorldBuilder
var traffic: TrafficManager
var out_dir := "user://street_review"
var _log: FileAccess
var _index := 0
var _t0 := 0
var _samples: Array[Dictionary] = []
var _headless := false

func setup(m: Node, dir: String) -> void:
	main = m
	world = m.world
	traffic = m.traffic
	out_dir = dir
	_headless = DisplayServer.get_name() == "headless"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

## (name, junction centre, player spot, player yaw deg, fixed cam, fixed look, seconds)
func _shots() -> Array:
	return [
		{"name": "junction_player", "junction": Vector3(0.0, 0.0, -160.0), "player": Vector3(-13.5, 0.45, -146.5), "yaw": -45.0, "seconds": 14.0},
		{"name": "junction_eye", "junction": Vector3(0.0, 0.0, -160.0), "cam": Vector3(-13.0, 1.65, -133.0), "look": Vector3(2.0, 1.2, -170.0), "fov": 62.0, "seconds": 14.0},
		{"name": "junction_raised", "junction": Vector3(-160.0, 0.0, 0.0), "cam": Vector3(-178.0, 7.5, 18.0), "look": Vector3(-157.0, 0.5, -6.0), "fov": 60.0, "seconds": 12.0},
	]

func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	Game.simulation_paused = false
	if main.has_method("_start_game"):
		main._start_game()
	if "--people-review" in OS.get_cmdline_user_args():
		await _people_review()
		return
	var player: Node3D = main.player
	player.visible = true
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	if not _headless:
		_log = FileAccess.open(out_dir.path_join("frames.jsonl"), FileAccess.WRITE)
	_t0 = Time.get_ticks_usec()
	for shot in _shots():
		var junction: Vector3 = shot["junction"]
		if shot.has("player"):
			player.respawn_at(shot["player"], deg_to_rad(float(shot["yaw"])))
			player.pitch = -0.1
			if player.get("camera") != null:
				player.camera.current = true
		else:
			# Keep the player out of the shot, on the pavement behind the lens.
			player.respawn_at((shot["cam"] as Vector3) * Vector3(1, 0, 1) + Vector3(0, 0.45, 0) - ((shot["look"] as Vector3) - (shot["cam"] as Vector3)).normalized() * Vector3(4, 0, 4), 0.0)
			cam.fov = shot["fov"]
			cam.global_position = shot["cam"]
			cam.look_at(shot["look"], Vector3.UP)
			cam.make_current()
		# Let the cut seed and traffic roll before recording.
		await get_tree().create_timer(2.5).timeout
		if main.get("hud") != null:
			main.hud.clear_notifications()
		var start := Time.get_ticks_usec()
		var next := start
		var next_sample := start
		var still_saved := false
		var dur := float(shot["seconds"])
		while true:
			var now := Time.get_ticks_usec()
			var u := float(now - start) / (dur * 1000000.0)
			if u >= 1.0:
				break
			if now >= next_sample:
				next_sample += 1000000
				var s := _sample(junction)
				s["shot"] = shot["name"]
				s["t"] = float(now - _t0) / 1000000.0
				_samples.append(s)
			if _headless:
				await get_tree().process_frame
				continue
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
					if not still_saved and u >= 0.45:
						img.save_png(out_dir.path_join("still_%s.png" % shot["name"]))
						still_saved = true
	if _log:
		_log.close()
	_write_report()
	Game.simulation_paused = true
	Sfx.shutdown_audio()
	await get_tree().create_timer(.15, true, false, true).timeout
	get_tree().quit(0)

## --street-review --people-review: every kind of person with every prop in
## a lineup on a mid-block pavement (simulation paused, lineup animating),
## front, walking side-on and from behind. PNG stills only.
func _people_review() -> void:
	var player: Node3D = main.player
	var base := Vector3(-10.6, 0.25, -60.0)
	player.respawn_at(base + Vector3(30.0, 0.2, 40.0), 0.0)
	var specs := [
		[CrowdPeople.Kind.WOMAN, "phone"], [CrowdPeople.Kind.WOMAN, "cup"], [CrowdPeople.Kind.WOMAN, "umbrella"],
		[CrowdPeople.Kind.WOMAN, "handbag"], [CrowdPeople.Kind.MAN, "backpack"], [CrowdPeople.Kind.ELDER_F, "shopping"],
		[CrowdPeople.Kind.ELDER_M, "cup"], [CrowdPeople.Kind.CHILD, "backpack"], [CrowdPeople.Kind.WOMAN, "none"],
		[CrowdPeople.Kind.MAN, "phone"], [CrowdPeople.Kind.CHILD, "none"], [CrowdPeople.Kind.WOMAN, "shopping"],
	]
	var lineup: Array[NPC] = []
	for i in specs.size():
		var n := NPC.new()
		n.set_meta("people_kind", int(specs[i][0]))
		n.set_meta("people_prop", String(specs[i][1]))
		traffic.add_child(n)
		n.global_position = base + Vector3(0.0, 0.0, -float(i) * 1.15)
		n.state = NPC.State.IDLE
		n.idle_time = 9999.0
		lineup.append(n)
	await get_tree().process_frame
	await get_tree().process_frame
	Game.simulation_paused = true
	for n in get_tree().get_nodes_in_group("npcs"):
		if not (n in lineup):
			(n as Node3D).visible = false
	for v in get_tree().get_nodes_in_group("ambient_vehicles"):
		(v as Node3D).visible = false
	for n in lineup:
		n.character_visual.ignore_simulation_pause = true
		n.character_visual.set_paused(false)
		for mi in n.character_visual.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).visibility_range_begin = 0.0
	var cam := Camera3D.new()
	cam.far = 2000.0
	add_child(cam)
	cam.fov = 50.0
	cam.make_current()
	var mid := base + Vector3(0.0, 0.0, -float(specs.size() - 1) * 0.575)
	var views := [
		["people_front", 0.0, Vector3(7.2, 1.45, 0.0), -PI * 0.5],
		["people_front_close", 0.0, Vector3(2.0, 1.4, 3.6), -PI * 0.5],
		["people_walk_side", 1.5, Vector3(7.2, 1.3, 0.0), 0.0],
		["people_back", 0.0, Vector3(7.2, 1.45, 0.0), PI * 0.5],
	]
	for v in views:
		for n in lineup:
			n.rotation.y = float(v[3])
			n.character_visual.set_motion(float(v[1]))
		cam.global_position = mid + (v[2] as Vector3) + (Vector3(0.0, 0.0, 0.0))
		var look := mid + Vector3(0.0, 1.0, 0.0)
		if String(v[0]) == "people_front_close":
			look = base + Vector3(0.0, 1.15, -2.3)
			cam.global_position = base + Vector3(2.6, 1.45, -1.0)
		cam.look_at(look, Vector3.UP)
		for f in 40:
			await get_tree().process_frame
		if "--people-debug" in OS.get_cmdline_user_args():
			for n in [lineup[0], lineup[1], lineup[2], lineup[9]]:
				var sk: Skeleton3D = n.character_visual.skeleton
				var hid: int = sk.find_bone("hand.l")
				print("[people-debug] ", v[0], " prop=", n.get_meta("people")["prop"], " hand.l=", sk.get_bone_global_pose(hid).origin.snapped(Vector3.ONE * 0.01),
					" forearm=", sk.get_bone_global_pose(sk.find_bone("forearm.l")).origin.snapped(Vector3.ONE * 0.01),
					" expected=", PeoplePose.posed_hand_rest(sk, "hand.l").origin.snapped(Vector3.ONE * 0.01), " processed=", (sk.get_node("PeoplePose") as PeoplePose).processed)
		if not _headless:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(out_dir.path_join("%s.png" % v[0]))
	var census := CrowdPeople.census(lineup)
	print("[people-review] census=", census)
	var f := FileAccess.open(out_dir.path_join("people_review.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"census": census, "kinds": CrowdPeople.stats}, "\t"))
		f.close()
	Sfx.shutdown_audio()
	await get_tree().create_timer(.15, true, false, true).timeout
	get_tree().quit(0)

func _sample(junction: Vector3) -> Dictionary:
	var moving := 0
	var queued := 0
	var amb := traffic.ambient
	if amb != null:
		for v in amb.vehicles:
			if not v.active:
				continue
			if Vector2(v.global_position.x - junction.x, v.global_position.z - junction.z).length() > RADIUS:
				continue
			if v.speed > 1.0:
				moving += 1
			else:
				queued += 1
	for c in traffic.cars:
		if is_instance_valid(c) and not c.disabled and c.has_ai and c.global_position.distance_to(junction) < RADIUS:
			if c.velocity.length() > 1.0:
				moving += 1
			else:
				queued += 1
	var peds := 0
	var outfits := {}
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NPC
		if npc == null or not npc.visible or npc.state == NPC.State.DEAD:
			continue
		if Vector2(npc.global_position.x - junction.x, npc.global_position.z - junction.z).length() > RADIUS:
			continue
		peds += 1
		if npc.character_visual != null:
			outfits[npc.character_visual.get("_wardrobe_variant")] = true
	return {"vehicles_moving": moving, "vehicles_queued": queued, "pedestrians": peds, "distinct_outfits": outfits.size(),
		"ew_green": traffic.signal_allows(Vector3(1, 0, 0)), "ns_green": traffic.signal_allows(Vector3(0, 0, 1)),
		"lit_signal_lenses": _lit_lenses()}

func _lit_lenses() -> int:
	var lit := 0
	for lamp in get_tree().get_nodes_in_group("traffic_lamps"):
		if lamp is GeometryInstance3D and (lamp as GeometryInstance3D).material_override != null:
			var m := (lamp as GeometryInstance3D).material_override as StandardMaterial3D
			if m != null and m.emission_enabled and m.emission_energy_multiplier > 1.0:
				lit += 1
	return lit

func _write_report() -> void:
	var by_shot := {}
	for s in _samples:
		var k: String = s["shot"]
		if not by_shot.has(k):
			by_shot[k] = {"samples": 0, "min_vehicles": 999, "mean_vehicles": 0.0, "min_peds": 999, "mean_peds": 0.0, "min_lit": 999}
		var b: Dictionary = by_shot[k]
		var veh := int(s["vehicles_moving"]) + int(s["vehicles_queued"])
		b["samples"] = int(b["samples"]) + 1
		b["min_vehicles"] = mini(int(b["min_vehicles"]), veh)
		b["mean_vehicles"] = float(b["mean_vehicles"]) + veh
		b["min_peds"] = mini(int(b["min_peds"]), int(s["pedestrians"]))
		b["mean_peds"] = float(b["mean_peds"]) + int(s["pedestrians"])
		b["min_lit"] = mini(int(b["min_lit"]), int(s["lit_signal_lenses"]))
	for k in by_shot:
		var b: Dictionary = by_shot[k]
		b["mean_vehicles"] = snappedf(float(b["mean_vehicles"]) / maxf(1.0, b["samples"]), 0.1)
		b["mean_peds"] = snappedf(float(b["mean_peds"]) / maxf(1.0, b["samples"]), 0.1)
		print("[street-review] %s: vehicles within %d m min=%d mean=%.1f; pedestrians min=%d mean=%.1f; lit lens sets min=%d" % [k, int(RADIUS), b["min_vehicles"], b["mean_vehicles"], b["min_peds"], b["mean_peds"], b["min_lit"]])
	var f := FileAccess.open(out_dir.path_join("street_review.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"radius_m": RADIUS, "frames": _index, "summary": by_shot, "samples": _samples,
			"note": "live gameplay at signalled junctions; counts are lane vehicles (moving > 1 m/s or queued) and living pedestrians within the radius of the junction centre"}, "\t"))
		f.close()
	print("[street-review] frames=", _index, " dir=", out_dir)
