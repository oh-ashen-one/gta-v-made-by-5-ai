extends Node
## On-foot QA (wave C): a close-character still plus third-person footage of
## the player walking, jogging, sprinting, turning sharply, stopping and
## reversing on the heritage five-foot way. Uses the real input actions and
## the real player camera. Run with `--fixed-fps 30` so every simulated frame
## is captured; writes frames.jsonl for tools/encode_capture.py and prints
## foot-slip metrics (planted-foot ground speed) for each phase.
## QA fixture only, never mission proof; touches no save slot.

const FPS := 30.0
# Opening heritage five-foot way (x = -171), running south toward the bay.
const START := Vector3(-171.0, 0.45, -30.0)
const START_YAW := 0.0
var main: Node
var out_dir := "/tmp/onfoot-review"
var _frame := 0
var _rows: Array[String] = []
var _phase := ""
var _slip := {}
var _feet := {}
var _attach := {}
var _was_low := {}

func setup(m: Node) -> void:
	main = m
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			out_dir = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	_run.call_deferred()

func _run() -> void:
	var player: Player = main.player
	main.hud.visible = false
	await get_tree().create_timer(0.5).timeout
	player.respawn_at(START, deg_to_rad(START_YAW))
	player.pitch = -0.12
	for i in 20:
		await get_tree().physics_frame
	var visual: CharacterVisual = player.get("_visual")
	# Close-character stills: 3/4 front and back at ~1.8 m, chest height.
	Game.simulation_paused = true
	visual.ignore_simulation_pause = true
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	var fwd := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	var shots := [["close_front34", fwd * 1.7 + right * 0.9 + Vector3.UP * 1.5, Vector3.UP * 1.35],
		["close_back34", -fwd * 1.8 + right * 0.8 + Vector3.UP * 1.6, Vector3.UP * 1.25],
		["full_front34", fwd * 3.2 + right * 1.6 + Vector3.UP * 1.3, Vector3.UP * 0.95]]
	for shot in shots:
		cam.global_position = player.global_position + shot[1]
		cam.look_at(player.global_position + shot[2])
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir + "/" + shot[0] + ".png")
		print("[onfoot-review] still ", shot[0])
	cam.current = false
	player.camera.current = true
	visual.ignore_simulation_pause = false
	Game.simulation_paused = false
	# Footage script: [phase, seconds, {action: strength}]
	var script := [
		["idle", 1.2, {}],
		["walk", 2.6, {"move_forward": 0.45}],
		["jog", 2.2, {"move_forward": 1.0}],
		["sprint", 2.6, {"move_forward": 1.0, "sprint": 1.0}],
		["sharp_reverse", 2.0, {"move_back": 1.0}],
		["stop", 1.8, {}],
		["sidestep_right", 0.8, {"move_right": 1.0}],
		["cut_left", 0.9, {"move_forward": 1.0, "move_left": 1.0}],
		["stop_2", 1.8, {}],
	]
	var still_at := {"walk": 2.0, "jog": 1.8, "sprint": 2.2, "sharp_reverse": 0.45, "stop": 0.3, "cut_left": 0.4}
	for step in script:
		_phase = step[0]
		for action in ["move_forward", "move_back", "move_left", "move_right", "sprint"]:
			Input.action_release(action)
		for action in step[2]:
			Input.action_press(action, step[2][action])
		var frames := int(step[1] * FPS)
		for f in frames:
			await get_tree().physics_frame
			_measure_slip(visual)
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var file := "frames/f%04d.jpg" % _frame
			img.save_jpg(out_dir + "/" + file, 0.9)
			_rows.append(JSON.stringify({"file": file, "seconds": _frame / FPS, "phase": _phase}))
			if still_at.has(_phase) and f == int(still_at[_phase] * FPS):
				img.save_png(out_dir + "/motion_" + _phase + ".png")
			_frame += 1
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint"]:
		Input.action_release(action)
	var fh := FileAccess.open(out_dir + "/frames.jsonl", FileAccess.WRITE)
	fh.store_string("\n".join(_rows) + "\n")
	fh.close()
	var report := {}
	for phase in _slip:
		var s: Array = _slip[phase]
		s.sort()
		# Median: contact and lift-off frames skim the ground while still moving.
		report[phase] = {"planted_samples": s.size(), "median_planted_foot_speed_mps": s[s.size() / 2] if s.size() > 0 else 0.0}
	print("[onfoot-review] foot_slip ", JSON.stringify(report))
	var rh := FileAccess.open(out_dir + "/foot_slip.json", FileAccess.WRITE)
	rh.store_string(JSON.stringify(report, "  "))
	rh.close()
	print("[onfoot-review] frames=", _frame)
	get_tree().quit()

## Planted-foot world speed: an ankle at contact height on two consecutive
## frames should not move over the ground. Median per phase.
func _measure_slip(visual: CharacterVisual) -> void:
	if visual == null or visual.skeleton == null:
		return
	var sk := visual.skeleton
	var dt := 1.0 / FPS
	var pos := {}
	for bone in ["foot.l", "foot.r"]:
		var att: BoneAttachment3D = _attach.get(bone)
		if att == null:
			att = BoneAttachment3D.new()
			att.bone_name = bone
			sk.add_child(att)
			_attach[bone] = att
			continue
		pos[bone] = att.global_position
	if pos.size() < 2:
		return
	var low: float = minf(pos["foot.l"].y, pos["foot.r"].y)
	if _phase == "jog" and OS.get_environment("ONFOOT_DEBUG") != "":
		var sk_l: Vector3 = sk.get_bone_global_pose(sk.find_bone("foot.l")).origin
		print("[dbg] f=", _frame, " anim=", visual.animator.current_animation, " pos=", snappedf(visual.animator.current_animation_position, 0.001), " rate=", visual.animator.speed_scale, " skL=", sk_l, " wL=", pos["foot.l"], " wR=", pos["foot.r"], " body=", visual.global_position)
	for bone in pos:
		var p: Vector3 = pos[bone]
		var planted: bool = p.y < visual.global_position.y + 0.145
		if _feet.has(bone) and planted and _was_low.get(bone, false):
			var prev: Vector3 = _feet[bone]
			var v := Vector2(p.x - prev.x, p.z - prev.z).length() / dt
			if not _slip.has(_phase):
				_slip[_phase] = []
			_slip[_phase].append(v)
		_feet[bone] = p
		_was_low[bone] = planted
