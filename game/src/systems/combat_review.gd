extends Node
## Combat QA footage (combat piece): over-the-shoulder pistol aim, a burst at
## a shophouse wall, a hostile at ~14 m hit twice (flinch/stagger) and killed,
## a reload, then a short firefight with two police officers. Uses the real
## input actions, the real player camera, real NPC AI and damage. Run with
## `--fixed-fps 30` so every simulated frame is captured; writes frames.jsonl
## for tools/encode_capture.py plus close stills of the muzzle flash and the
## wall impacts. QA fixture only, never mission proof; touches no save slot.

const FPS := 30.0
var main: Node
var out_dir := "/tmp/combat-review"
var player: Player
var _frame := 0
var _rows: Array[String] = []
var _phase := ""
var _recording := true
var _log: Array[String] = []

func setup(m: Node) -> void:
	main = m
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			out_dir = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	_run.call_deferred()

func _note(text: String) -> void:
	print("[combat-review] ", text)
	_log.append(text)

func _physics_process(_delta: float) -> void:
	# Footage fixture: the player cannot die mid-take.
	if Game.health < 60.0:
		Game.health = Game.MAX_HEALTH
		Events.health_changed.emit(Game.health, Game.MAX_HEALTH)

func _frame_step() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if _recording:
		var img := get_viewport().get_texture().get_image()
		var file := "frames/f%04d.jpg" % _frame
		img.save_jpg(out_dir + "/" + file, 0.9)
		_rows.append(JSON.stringify({"file": file, "seconds": _frame / FPS, "phase": _phase}))
		_frame += 1

func _still(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out_dir + "/" + name + ".png")
	_note("still " + name)

func _frames(seconds: float) -> void:
	for i in int(seconds * FPS):
		await _frame_step()

## Turn the view onto `point` over `seconds`, recording.
func _aim_at(point: Vector3, seconds: float) -> void:
	var n := maxi(1, int(seconds * FPS))
	var y0 := player.yaw
	var p0 := player.pitch
	for i in n:
		var d := point - player.camera.global_position
		var ty := atan2(-d.x, -d.z)
		var tp := clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.25, 0.85)
		var k := smoothstep(0.0, 1.0, float(i + 1) / n)
		player.yaw = lerp_angle(y0, ty, k)
		player.pitch = lerpf(p0, tp, k)
		await _frame_step()

func _track(point_fn: Callable) -> void:
	var d: Vector3 = point_fn.call() - player.camera.global_position
	player.yaw = atan2(-d.x, -d.z)
	player.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.25, 0.85)

## Press fire once while tracking; returns after `hold` seconds. Saves the
## frame on which the shot lands as `still_name` if given.
func _shoot(point_fn: Callable, hold: float, still_name: String = "") -> void:
	var guard := 0
	while (player._fire_cooldown > 0.0 or player._reloading) and guard < 90:
		_track(point_fn)
		await _frame_step()
		guard += 1
	var before := int(CombatFx.stats["muzzle"])
	_track(point_fn)
	player._press_queue["fire"] = true
	var waited := 0
	while int(CombatFx.stats["muzzle"]) == before and waited < 6:
		_track(point_fn)
		await _frame_step()
		waited += 1
	if still_name != "":
		_still(still_name)
	for i in maxi(0, int(hold * FPS) - waited):
		_track(point_fn)
		await _frame_step()

func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 8.0)
	q.collision_mask = 1
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3) + Vector3.UP * 0.05 if not hit.is_empty() else p

func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1 | 8
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## The visible shop back wall (thin box), not the set-back envelope.
func _thin_wall(collider: Object) -> bool:
	if not collider is Node:
		return false
	for child in (collider as Node).get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var size: Vector3 = ((child as CollisionShape3D).shape as BoxShape3D).size
			return minf(size.x, size.z) < 0.3
	return false

func _has_mesh(collider: Object) -> bool:
	if not collider is Node:
		return false
	var node := collider as Node
	for holder in [node, node.get_parent()]:
		if holder == null:
			continue
		for child in holder.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).visible:
				return true
	return false

## Wave Q: a still from a temporary close camera (footage paused).
func _close_still(name: String, cam_pos: Vector3, look: Vector3, fov: float = 40.0) -> void:
	var was := _recording
	_recording = false
	var cam := Camera3D.new()
	cam.fov = fov
	main.add_child(cam)
	cam.global_position = cam_pos
	cam.look_at(look)
	cam.current = true
	await _frame_step()
	_still(name)
	player.camera.current = true
	cam.queue_free()
	_recording = was

func _pelvis_of(n: NPC) -> Vector3:
	var v: Node = n.character_visual
	if v != null and v.get("skeleton") != null:
		var sk: Skeleton3D = v.get("skeleton")
		var pb := sk.get_node_or_null("Ragdoll/PB_pelvis") as Node3D
		if pb != null:
			return pb.global_position
		var id := sk.find_bone("pelvis")
		if id >= 0:
			return sk.global_transform * sk.get_bone_global_pose(id).origin
	return n.global_position + Vector3.UP * 0.3

func _corpse_still(name: String, n: NPC) -> void:
	var c := _pelvis_of(n)
	var away := c - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var side := away.cross(Vector3.UP).normalized()
	await _close_still(name, c - away * 2.2 + side * 1.3 + Vector3.UP * 1.25, c, 45.0)
	_note("%s pelvis %s height above ground %.2f" % [name, c, c.y - _ground(c).y + 0.05])

func _spawn(pos: Vector3, police: bool, health: float) -> NPC:
	var n := NPC.new()
	n.is_police = police
	n.is_hostile = not police
	n.health = health
	main.add_child(n)
	n.global_position = _ground(pos)
	n.state = NPC.State.IDLE
	n.idle_time = 1000.0
	return n

func _run() -> void:
	player = main.player
	await get_tree().create_timer(0.6).timeout
	# Pavement beside the opening shophouse row (x = -180, fronts face +x),
	# looking south along the five-foot way.
	var start := Vector3(-171.0, 0.45, -48.0)
	player.respawn_at(start, 0.0)
	player.pitch = -0.06
	main.hud.clear_notifications()
	Game.wanted_heat = 0.0
	Game.set_wanted(0)
	for i in 30:
		await get_tree().physics_frame
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var eye := player.global_position + Vector3.UP * 1.35
	if "--combat-probe" in OS.get_cmdline_user_args():
		for deg in range(0, 360, 10):
			for h in [1.35, 2.5]:
				var pd := fwd.rotated(Vector3.UP, deg_to_rad(deg))
				var e2: Vector3 = player.global_position + Vector3.UP * float(h)
				var pq := PhysicsRayQueryParameters3D.create(e2, e2 + pd * 30.0)
				pq.collision_mask = 1
				var ph := player.get_world_3d().direct_space_state.intersect_ray(pq)
				if ph.is_empty():
					_note("scan deg=%d h=%.1f none" % [deg, h])
				else:
					_note("scan deg=%d h=%.1f dist=%.1f n=%s %s" % [deg, h, e2.distance_to(ph["position"]), (ph["normal"] as Vector3).snapped(Vector3.ONE * 0.01), (ph["collider"] as Node).name])
		get_tree().quit()
		return
	# Wall target: the shophouse facade on the left at 6-16 m.
	var wall_point := Vector3.INF
	var wall_normal := Vector3.ZERO
	for deg in [45, 48, 42, 50, 38, 53, 56, 60, 65, 70]:
		for side in [1.0, -1.0]:
			var dir := fwd.rotated(Vector3.UP, deg_to_rad(deg) * side)
			var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 18.0)
			q.collision_mask = 1
			var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				var dist := eye.distance_to(hit["position"])
				var nrm: Vector3 = hit["normal"]
				_note("probe deg=%d side=%d dist=%.1f collider=%s visible_mesh=%s" % [deg, side, dist, (hit["collider"] as Node).get_path(), _has_mesh(hit["collider"])])
				if dist > 5.5 and dist < 16.0 and absf(nrm.y) < 0.3 and nrm.dot(-dir) > 0.6 and _thin_wall(hit["collider"]):
					wall_point = hit["position"]
					wall_normal = nrm
					break
		if wall_point != Vector3.INF:
			break
	if wall_point == Vector3.INF:
		wall_point = eye + fwd.rotated(Vector3.UP, 1.2) * 10.0
		wall_normal = -fwd.rotated(Vector3.UP, 1.2)
	_note("wall %s normal %s dist %.1f" % [wall_point, wall_normal, eye.distance_to(wall_point)])
	# Hostile ~14 m ahead with a clear line, police further up the street.
	var enemy_pos := player.global_position + fwd * 11.5
	for lateral in [0.0, 1.5, -1.5, 3.0]:
		var cand: Vector3 = player.global_position + fwd * 11.5 + fwd.cross(Vector3.UP) * lateral
		if _clear(eye, cand + Vector3.UP * 1.2):
			enemy_pos = cand
			break
	var hostile := _spawn(enemy_pos, false, 70.0)
	hostile.rotation.y = atan2(fwd.x, fwd.z)   # facing the player
	hostile.state = NPC.State.PURSUE   # wave Q: an armed hostile that fires back
	_note("hostile at %s (%.1f m)" % [hostile.global_position, hostile.global_position.distance_to(player.global_position)])
	for i in 20:
		await get_tree().physics_frame
	var chest := func(n: NPC) -> Vector3: return n.global_position + Vector3.UP * 1.2

	_phase = "ready"
	await _frames(0.7)
	_phase = "aim_wall"
	Input.action_press("aim")
	await _aim_at(wall_point + Vector3.UP * 0.2, 0.55)
	await _frames(0.45)
	_still("aim_wall")
	# Wave Q: the aim pose up close (head down the sights, two-hand grip).
	var hf := -player.camera.global_basis.z
	hf.y = 0.0
	hf = hf.normalized()
	var hr := hf.cross(Vector3.UP).normalized()
	var head := player.global_position + Vector3.UP * 1.58
	await _close_still("aim_pose_close_r", head + hf * 1.15 + hr * 0.75 + Vector3.UP * 0.02, head + hf * 0.3 - Vector3.UP * 0.05)
	await _close_still("aim_pose_close_l", head + hf * 1.15 - hr * 0.75 + Vector3.UP * 0.02, head + hf * 0.3 - Vector3.UP * 0.05)
	await _close_still("aim_pose_side", head + hr * 1.35 + hf * 0.25, head + hf * 0.28 - Vector3.UP * 0.05)
	await _close_still("aim_pose_over_shoulder", head - hf * 0.75 + hr * 0.38 + Vector3.UP * 0.12, head + hf * 4.0 - Vector3.UP * 0.1, 50.0)
	_phase = "burst_wall"
	var spots := []
	var tangent := wall_normal.cross(Vector3.UP).normalized()
	for k in 5:
		spots.append(wall_point + Vector3.UP * (0.25 - 0.18 * (k % 2)) + tangent * (-0.5 + 0.25 * k))
	for k in 5:
		var p: Vector3 = spots[k]
		await _shoot(func(): return p, 0.24, "flash_wall_%d" % k if k == 1 else "")
	await _frames(0.5)
	# Close stills: impact and muzzle from beside the action.
	_recording = false
	var cam := Camera3D.new()
	cam.fov = 45.0
	main.add_child(cam)
	cam.global_position = wall_point + wall_normal * 2.3 + tangent * 1.0 + Vector3.UP * 0.35
	cam.look_at(wall_point + Vector3.UP * 0.1)
	cam.current = true
	await _frame_step()
	await _frame_step()
	_still("impact_holes_close")
	var p_live: Vector3 = wall_point + tangent * 0.15 + Vector3.UP * 0.05
	player.camera.current = true
	await _shoot(func(): return p_live, 0.0)
	cam.current = true
	await _frame_step()
	_still("impact_live_close")
	# Muzzle close: camera off the gun's left-front quarter.
	var muzzle: Vector3 = player._visual.weapon_muzzle_position() if player._visual != null and player._visual.loaded else player.global_position + Vector3.UP * 1.4
	var aim_dir := (wall_point - muzzle).normalized()
	var mside := aim_dir.cross(Vector3.UP).normalized()
	player.camera.current = true
	await _frame_step()
	cam.global_position = muzzle + aim_dir * 0.9 - mside * 1.1 + Vector3.UP * 0.15
	cam.look_at(muzzle + aim_dir * 0.25)
	cam.current = true
	while player._fire_cooldown > 0.0:
		await _frame_step()
	var before := int(CombatFx.stats["muzzle"])
	player._press_queue["fire"] = true
	for i in 6:
		await _frame_step()
		if int(CombatFx.stats["muzzle"]) > before:
			_still("muzzle_flash_close")
			break
	await _frame_step()
	await _frame_step()
	_still("muzzle_smoke_close")
	player.camera.current = true
	cam.queue_free()
	_recording = true

	_phase = "aim_enemy"
	await _aim_at(chest.call(hostile), 0.5)
	_phase = "shoot_enemy"
	for k in 3:
		if hostile.state == NPC.State.DEAD:
			break
		await _shoot(func(): return chest.call(hostile), 0.5, "enemy_hit_%d" % k)
		_note("hostile health %.0f state %d" % [hostile.health, hostile.state])
	_phase = "enemy_down"
	for i in int(0.45 * FPS):
		await _frame_step()
	_still("enemy_falling")
	await _frames(0.9)
	await _corpse_still("corpse_rest_close", hostile)
	_phase = "reload"
	Input.action_release("aim")
	Input.action_press("reload")
	await _frame_step()
	Input.action_release("reload")
	await _frames(0.6)
	_still("reload")
	await _frames(1.1)

	_phase = "police"
	Game.wanted_heat = 50.0
	Game.set_wanted(2)
	var right := fwd.cross(Vector3.UP).normalized()
	var cops: Array[NPC] = []
	for spec in [[10.0, 3.0], [12.5, 6.0]]:
		var c: NPC = _spawn(player.global_position + fwd * float(spec[0]) + right * float(spec[1]), true, 100.0)
		c.state = NPC.State.PURSUE
		c.rotation.y = atan2(fwd.x, fwd.z)
		cops.append(c)
	Input.action_press("aim")
	await _aim_at(chest.call(cops[0]), 0.6)
	await _frames(0.8)
	var shots := 0
	for c in cops:
		for k in 4:
			if c.state == NPC.State.DEAD:
				break
			await _shoot(func(): return chest.call(c), 0.36, "police_firefight" if shots == 1 else "")
			shots += 1
			if Game.current_mag() == 0:
				Input.action_press("reload")
				await _frame_step()
				Input.action_release("reload")
				await _frames(1.6)
		if c != cops[-1]:
			await _aim_at(chest.call(cops[1]), 0.35)
	await _frames(1.2)
	_still("police_aftermath")
	Input.action_release("aim")
	await _frames(0.6)
	await _frames(1.5)
	for c in cops:
		if c.state == NPC.State.DEAD:
			await _corpse_still("police_corpse_close_%d" % cops.find(c), c)
	# Wave Q: magazine change up close (front-left quarter of the shooter).
	_recording = false
	if Game.current_mag() >= 12:
		Game.consume_ammo()
	var rf := -player.camera.global_basis.z
	rf.y = 0.0
	rf = rf.normalized()
	var rr := rf.cross(Vector3.UP).normalized()
	var chest_p := player.global_position + Vector3.UP * 1.3
	Input.action_press("reload")
	await _frame_step()
	Input.action_release("reload")
	var t0 := Time.get_ticks_msec()
	var marks := [0.30, 0.52, 0.72, 0.95, 1.22]
	var mi := 0
	var cam2 := Camera3D.new()
	cam2.fov = 42.0
	main.add_child(cam2)
	var sim_t := 0.0
	while mi < marks.size() and sim_t < 2.0:
		await get_tree().process_frame
		sim_t += get_process_delta_time()
		if sim_t >= float(marks[mi]):
			cam2.global_position = chest_p + rf * 1.05 - rr * 0.85 + Vector3.UP * 0.12
			cam2.look_at(chest_p + rf * 0.25)
			cam2.current = true
			await _frame_step()
			_still("reload_close_%d" % mi)
			player.camera.current = true
			mi += 1
	cam2.queue_free()
	_note("reload close stills %d (%.0f ms)" % [mi, Time.get_ticks_msec() - t0])

	var fh := FileAccess.open(out_dir + "/frames.jsonl", FileAccess.WRITE)
	fh.store_string("\n".join(_rows) + "\n")
	fh.close()
	_note("frames=%d stats=%s police_dead=%s" % [_frame, JSON.stringify(CombatFx.stats), str(cops.map(func(c): return c.state == NPC.State.DEAD))])
	var lh := FileAccess.open(out_dir + "/combat_review.log", FileAccess.WRITE)
	lh.store_string("\n".join(_log) + "\n")
	lh.close()
	get_tree().quit()
