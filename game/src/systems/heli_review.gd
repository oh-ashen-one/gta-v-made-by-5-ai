extends Node
## Helicopter review capture (opus55 helicopter piece). `--heli-review`
## boards the aircraft at the aviation pad and flies a scripted sortie with
## real input actions: spool-up, take-off downwash, banking S-turns over the
## district, a low hover over the bay (spray), approach and landing on the
## waterfront pad, then two close beauty frames of the airframe. Stills go to
## --capture-dir, a JPEG sequence to <dir>/frames for encoding.

var main: Node
var world: WorldBuilder
var player: Player
var heli: Helicopter
var out_dir := "user://heli_review"
var _frame := 0
var _recording := true
var _log: Array[String] = []

func setup(m: Node, w: WorldBuilder, dir: String) -> void:
	main = m
	world = w
	player = m.get("player")
	out_dir = dir
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("frames"))
	_run()

func _note(text: String) -> void:
	var line := "[heli-review] %.2fs %s" % [Time.get_ticks_msec() / 1000.0, text]
	print(line)
	_log.append(line)

func _process(_delta: float) -> void:
	if not _recording or DisplayServer.get_name() == "headless":
		return
	_frame += 1
	if _frame % 2 == 0:
		_grab("frames/f_%05d.jpg" % (_frame / 2), true)

func _grab(rel: String, jpg: bool) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	if jpg:
		img.save_jpg(out_dir.path_join(rel), 0.85)
	else:
		img.save_png(out_dir.path_join(rel))

func _shot(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_grab("%s.png" % label, false)
	else:
		await get_tree().physics_frame
	var state := heli.presentation_state() if heli != null else {}
	_note("shot %s pos=%s spin=%.2f wash=%.2f bank=%.2f" % [label, heli.global_position, state.get("rotor_spin", 0.0), state.get("wash", 0.0), heli.get_child(0).rotation.z if heli else 0.0])

func _release() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "jump", "sprint"]:
		Input.action_release(a)

func _seconds(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame

## Hold altitude `alt`, steer toward `target` (xz) with forward demand `fwd`,
## plus an optional constant yaw bias for S-turns. Ends after `t` seconds or
## within `reach` metres.
func _fly(target: Vector3, alt: float, fwd: float, t: float, yaw_bias: float = 0.0, reach: float = 6.0) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame
		var offset := target - heli.global_position
		offset.y = 0.0
		if offset.length() < reach and yaw_bias == 0.0:
			break
		_release()
		var forward := -heli.global_transform.basis.z
		var dir := offset.normalized()
		var angle := atan2(forward.z * dir.x - forward.x * dir.z, forward.dot(dir))
		var yaw := clampf(angle * 1.2, -1.0, 1.0) if yaw_bias == 0.0 else yaw_bias
		if yaw > 0.02:
			Input.action_press("move_left", clampf(yaw, 0.0, 1.0))
		elif yaw < -0.02:
			Input.action_press("move_right", clampf(-yaw, 0.0, 1.0))
		var demand := fwd * clampf(offset.length() / 40.0, 0.15, 1.0) * maxf(0.2, cos(angle)) if yaw_bias == 0.0 else fwd
		if demand > 0.0:
			Input.action_press("move_forward", demand)
		var dy := alt - heli.global_position.y
		if dy > 1.0:
			Input.action_press("jump", clampf(dy / 8.0, 0.2, 1.0))
		elif dy < -1.0:
			Input.action_press("sprint", clampf(-dy / 4.0, 0.2, 1.0))
	_release()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	heli = main.get_node_or_null("Helicopter") as Helicopter
	if heli == null or player == null:
		_note("FAIL no helicopter")
		_finish(1)
		return
	player.respawn_at(heli.global_position + Vector3(3.0, 0.5, 0.0), 0.0)
	await get_tree().physics_frame
	heli.interact(player)
	await _seconds(0.6)
	await _shot("h01_boarded_spoolup")
	await _seconds(1.8)
	await _shot("h02_rotor_disc_on_pad")
	# take-off: lift through the downwash band
	Input.action_press("jump", 0.6)
	await _seconds(1.1)
	await _shot("h03_takeoff_downwash")
	await _seconds(0.6)
	_release()
	await _fly(heli.global_position + Vector3(0, 0, -1), 45.0, 0.0, 3.0, 0.0, 9999.0)
	# banking S-turns at speed over the district
	await _fly(Vector3.ZERO, 50.0, 1.0, 2.5, 0.0, 9999.0)
	await _fly(Vector3.ZERO, 50.0, 1.0, 2.2, 0.9)
	await _shot("h04_bank_left")
	await _fly(Vector3.ZERO, 50.0, 1.0, 1.2, 0.9)
	await _fly(Vector3.ZERO, 50.0, 1.0, 2.6, -0.9)
	await _shot("h05_bank_right")
	await _fly(Vector3.ZERO, 50.0, 1.0, 1.0, -0.9)
	# cruise to the bay, then a low hover over open water
	var bay := Vector3(-30.0, 0.0, -400.0)
	await _fly(bay, 45.0, 1.0, 25.0, 0.0, 20.0)
	await _fly(bay, 45.0, 0.3, 4.0, 0.0, 3.0)
	await _fly(bay, 7.0, 0.0, 9.0, 0.0, -1.0)
	await _shot("h06_low_hover_spray")
	# approach and land on the waterfront pad
	var pad: Vector3 = world.locations["helipad_secondary"]
	await _fly(pad, 12.0, 0.5, 14.0, 0.0, 2.0)
	await _fly(pad, 12.0, 0.0, 2.0, 0.0, 0.0)
	var end := Time.get_ticks_msec() + 14000
	var shot_taken := false
	while Time.get_ticks_msec() < end and not heli.is_landed():
		await get_tree().physics_frame
		_release()
		Input.action_press("sprint", 0.5)
		if not shot_taken and heli.global_position.y < 5.0:
			shot_taken = true
			await _shot("h07_landing_downwash")
	_release()
	await _seconds(1.0)
	await _shot("h08_landed_rotor_running")
	# close beauty frames of the airframe, HUD hidden
	var hud: Node = main.get("hud")
	if hud:
		hud.set("visible", false)
	var cam := Camera3D.new()
	cam.fov = 45.0
	main.add_child(cam)
	var fwd := -heli.global_transform.basis.z
	var side := heli.global_transform.basis.x
	cam.global_position = heli.global_position + fwd * 9.0 + side * 5.5 + Vector3.UP * 2.6
	cam.look_at(heli.global_position + Vector3.UP * 1.9, Vector3.UP)
	cam.current = true
	await _seconds(0.5)
	await _shot("h09_closeup_front_quarter")
	cam.global_position = heli.global_position - side * 10.0 + fwd * 1.5 + Vector3.UP * 3.4
	cam.look_at(heli.global_position + Vector3.UP * 2.0 + fwd * 0.5, Vector3.UP)
	await _seconds(0.5)
	await _shot("h10_closeup_side")
	_recording = false
	_finish(0)

func _finish(code: int) -> void:
	var f := FileAccess.open(out_dir.path_join("heli_review_log.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log))
		f.close()
	_note("done frames=%d" % (_frame / 2))
	get_tree().quit(code)
