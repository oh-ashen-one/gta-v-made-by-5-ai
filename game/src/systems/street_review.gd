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
	if "--downtown" in OS.get_cmdline_user_args():
		return _downtown_shots()
	return [
		{"name": "junction_player", "junction": Vector3(0.0, 0.0, -160.0), "player": Vector3(-13.5, 0.45, -146.5), "yaw": -45.0, "seconds": 14.0},
		{"name": "junction_eye", "junction": Vector3(0.0, 0.0, -160.0), "cam": Vector3(-13.0, 1.65, -133.0), "look": Vector3(2.0, 1.2, -170.0), "fov": 62.0, "seconds": 14.0},
		{"name": "junction_raised", "junction": Vector3(-160.0, 0.0, 0.0), "cam": Vector3(-178.0, 7.5, 18.0), "look": Vector3(-157.0, 0.5, -6.0), "fov": 60.0, "seconds": 12.0},
	]

## downtown-life (wave S): normal play on foot at the downtown junctions and
## plazas the critics shoot. The player stands on the pavement or plaza with
## the real third-person camera looking at the spot `junction`.
func _downtown_shots() -> Array:
	var spots := [
		["dt_cecil_market", Vector3(-430.0, 0.0, 0.0), Vector3(-439.5, 0.5, 17.0)],
		["dt_cecil_collyer", Vector3(-430.0, 0.0, -320.0), Vector3(-421.5, 0.5, -306.0)],
		["dt_raffles_place", Vector3(-380.0, 0.0, -40.0), Vector3(-400.0, 0.5, -70.0)],
		["dt_esplanade_drive", Vector3(-662.0, 0.0, -358.0), Vector3(-646.0, 0.5, -372.5)],
		["dt_bayfront_avenue", Vector3(-118.0, 0.0, -780.0), Vector3(-100.0, 0.5, -763.0)],
		["dt_marina_blvd", Vector3(400.0, 0.0, -480.0), Vector3(389.0, 0.5, -466.0)],
		["dt_mbs_event_plaza", Vector3(-122.0, 0.3, -648.0), Vector3(-103.0, 0.8, -633.0)],
		["dt_merlion_terrace", Vector3(-478.0, 1.3, -392.0), Vector3(-462.0, 1.9, -378.0)],
		["dt_boat_quay", Vector3(-525.0, 0.3, 60.0), Vector3(-524.0, 0.8, 84.0)],
	]
	var out: Array = []
	for sp in spots:
		var j: Vector3 = sp[1]
		var pl: Vector3 = sp[2]
		var d := j - pl
		out.append({"name": sp[0], "junction": j, "player": pl, "yaw": rad_to_deg(atan2(-d.x, -d.z)), "seconds": 9.0})
	return out

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
	# downtown-life: what the lens sees. People within 30 m of the camera,
	# what they are doing, anyone standing on a live carriageway, and moving
	# lane cars within 80 m in front of it.
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam != null else junction
	var cf := -cam.global_transform.basis.z if cam != null else Vector3.FORWARD
	cf.y = 0.0
	cf = cf.normalized()
	var cam_peds := 0
	var acts := {}
	var in_lane := 0
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NPC
		if npc == null or not npc.visible or npc.state == NPC.State.DEAD:
			continue
		var gp := npc.global_position
		if StreetRaster.at(gp.x, gp.z) == 1 and npc.state != NPC.State.FLEE and Vector2(gp.x - cp.x, gp.z - cp.z).length() < 80.0:
			in_lane += 1
			if "--street-debug" in OS.get_cmdline_user_args():
				print("[street-review] in-lane: %s state=%d lane=%d roamer=%s act=%s" % [str(gp.snapped(Vector3.ONE * 0.1)), npc.state, npc.lane.size(), npc.has_meta("roamer"), activities(npc)])
		if Vector2(gp.x - cp.x, gp.z - cp.z).length() > RADIUS:
			continue
		cam_peds += 1
		for a in activities(npc):
			acts[a] = int(acts.get(a, 0)) + 1
	var moving80 := 0
	if amb != null:
		for v in amb.vehicles:
			if not v.active or v.speed < 1.0:
				continue
			var rel := v.global_position - cp
			rel.y = 0.0
			if rel.length() < 80.0 and (rel.length() < 8.0 or rel.normalized().dot(cf) > 0.25):
				moving80 += 1
	return {"vehicles_moving": moving, "vehicles_queued": queued, "pedestrians": peds, "distinct_outfits": outfits.size(),
		"cam_peds_30": cam_peds, "activities": acts, "peds_in_live_lane": in_lane, "moving_80_in_view": moving80,
		"ew_green": traffic.signal_allows(Vector3(1, 0, 0)), "ns_green": traffic.signal_allows(Vector3(0, 0, 1)),
		"lit_signal_lenses": _lit_lenses()}

## Readable activities of one person (downtown-life QA census).
static func activities(npc: NPC) -> Array:
	var out: Array = []
	if npc.has_meta("plaza_activity"):
		out.append(String(npc.get_meta("plaza_activity")))
	elif npc.state == NPC.State.IDLE and (npc.has_meta("loiter_pair") or npc.has_meta("chatting")):
		out.append("talking")
	elif npc.state == NPC.State.IDLE:
		out.append("standing")
	elif npc.companion != null or npc.has_meta("leads"):
		out.append("walking_together")
	else:
		out.append("walking")
	if npc.has_meta("people"):
		var prop := String((npc.get_meta("people") as Dictionary).get("prop", "none"))
		if prop == "phone":
			out.append("phone")
		elif prop == "cup":
			out.append("drink")
		elif prop in ["handbag", "shopping", "backpack"]:
			out.append("bags")
		elif prop == "umbrella":
			out.append("umbrella")
	return out

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
			by_shot[k] = {"samples": 0, "min_vehicles": 999, "mean_vehicles": 0.0, "min_peds": 999, "mean_peds": 0.0, "min_lit": 999,
				"min_cam_peds_30": 999, "max_in_lane": 0, "moving80_share": 0.0, "activity_kinds": {}}
		var b: Dictionary = by_shot[k]
		var veh := int(s["vehicles_moving"]) + int(s["vehicles_queued"])
		b["samples"] = int(b["samples"]) + 1
		b["min_vehicles"] = mini(int(b["min_vehicles"]), veh)
		b["mean_vehicles"] = float(b["mean_vehicles"]) + veh
		b["min_peds"] = mini(int(b["min_peds"]), int(s["pedestrians"]))
		b["mean_peds"] = float(b["mean_peds"]) + int(s["pedestrians"])
		b["min_lit"] = mini(int(b["min_lit"]), int(s["lit_signal_lenses"]))
		b["min_cam_peds_30"] = mini(int(b["min_cam_peds_30"]), int(s.get("cam_peds_30", 0)))
		b["max_in_lane"] = maxi(int(b["max_in_lane"]), int(s.get("peds_in_live_lane", 0)))
		b["moving80_share"] = float(b["moving80_share"]) + (1.0 if int(s.get("moving_80_in_view", 0)) > 0 else 0.0)
		for a in (s.get("activities", {}) as Dictionary):
			b["activity_kinds"][a] = maxi(int(b["activity_kinds"].get(a, 0)), int(s["activities"][a]))
	for k in by_shot:
		var b: Dictionary = by_shot[k]
		b["mean_vehicles"] = snappedf(float(b["mean_vehicles"]) / maxf(1.0, b["samples"]), 0.1)
		b["mean_peds"] = snappedf(float(b["mean_peds"]) / maxf(1.0, b["samples"]), 0.1)
		b["moving80_share"] = snappedf(float(b["moving80_share"]) / maxf(1.0, b["samples"]), 0.01)
		print("[street-review] %s: vehicles within %d m min=%d mean=%.1f; pedestrians min=%d mean=%.1f; lit lens sets min=%d" % [k, int(RADIUS), b["min_vehicles"], b["mean_vehicles"], b["min_peds"], b["mean_peds"], b["min_lit"]])
		print("[street-review] %s: lens people within 30 m min=%d; moving car within 80 m in %.0f%% of samples; people in live lanes max=%d; activities=%s" % [k, b["min_cam_peds_30"], 100.0 * float(b["moving80_share"]), b["max_in_lane"], str(b["activity_kinds"])])
	var f := FileAccess.open(out_dir.path_join("street_review.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"radius_m": RADIUS, "frames": _index, "summary": by_shot, "samples": _samples,
			"note": "live gameplay at signalled junctions; counts are lane vehicles (moving > 1 m/s or queued) and living pedestrians within the radius of the junction centre"}, "\t"))
		f.close()
	print("[street-review] frames=", _index, " dir=", out_dir)
