extends Node
## Locomotion QA (Opus 5.5 locomotion piece). Third-person footage through the
## real player camera and real input actions of: standing -> walk, walk
## straight, walk weaving, run, sprint, a sharp 180, the run stop, a standing
## jump and a running jump. Then contact-sheet stills of one full walk, run and
## sprint cycle from the side and from behind (simulation paused, clip
## sampled at 8 evenly spaced phases), and numeric gait metrics per phase:
## clip, playback rate, stance width (ankle-to-ankle, lateral) at mid-stance,
## airborne (flight) frames, planted-foot slip.
## Run with `--fixed-fps 30` so every simulated frame is captured. QA fixture
## only; touches no save slot.

const FPS := 30.0
const START := Vector3(-171.0, 0.45, -30.0)
const ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "jump", "aim"]
var main: Node
var out_dir := "/tmp/locomotion-review"
var _frame := 0
var _rows: Array[String] = []
var _phase := ""
var _metrics := {}
var _attach := {}
var _prev_feet := {}
var _ground_y := 0.0
var _metrics_only := false # --loco-metrics-only: skeleton metrics, no frames (headless)

func setup(m: Node) -> void:
	main = m
	for arg in OS.get_cmdline_user_args():
		if arg == "--loco-metrics-only":
			_metrics_only = true
		if arg.begins_with("--capture-dir="):
			out_dir = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	DirAccess.make_dir_recursive_absolute(out_dir + "/sheets")
	_run.call_deferred()

func _release() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)

func _run() -> void:
	var player: Player = main.player
	main.hud.visible = false
	await get_tree().create_timer(0.5).timeout
	player.respawn_at(START, 0.0)
	player.pitch = -0.10
	for i in 30:
		await get_tree().physics_frame
	var visual: CharacterVisual = player.get("_visual")
	_ground_y = player.global_position.y
	# [phase, seconds, {action: strength}, yaw rate rad/s, jump at frame]
	var script := [
		["stand", 1.0, {}, 0.0, -1],
		["walk_start", 2.4, {"move_forward": 1.0, "walk": 1.0}, 0.0, -1],
		["walk_weave", 2.6, {"move_forward": 1.0, "walk": 1.0}, 0.55, -1],
		["run", 2.6, {"move_forward": 1.0}, 0.0, -1],
		["sprint", 2.6, {"move_forward": 1.0, "sprint": 1.0}, 0.0, -1],
		["turn_180", 1.6, {"move_back": 1.0}, 0.0, -1],
		["run_stop", 1.6, {}, 0.0, -1],
		["jump_stand", 1.6, {}, 0.0, 6],
		["run_up", 1.0, {"move_forward": 1.0}, 0.0, -1],
		["jump_run", 1.4, {"move_forward": 1.0}, 0.0, 4],
		["land_stop", 1.4, {}, 0.0, -1],
		["aim_strafe", 2.0, {"aim": 1.0, "move_right": 1.0}, 0.0, -1],
		["aim_back", 2.0, {"aim": 1.0, "move_back": 1.0}, 0.0, -1],
	]
	for step in script:
		_phase = step[0]
		_release()
		for action in step[2]:
			Input.action_press(action, step[2][action])
		var frames := int(step[1] * FPS)
		for f in frames:
			if _phase == "run_stop" and f < 30:
				player.yaw += PI / 30.0 # swing the camera back behind the player
			if step[3] != 0.0:
				player.yaw += step[3] * sin(float(f) / FPS * TAU / 2.6) / FPS * 2.0
			if f == step[4]:
				Input.action_press("jump")
			elif f == step[4] + 2:
				Input.action_release("jump")
			await get_tree().physics_frame
			_measure(player, visual)
			var file := "frames/f%04d.jpg" % _frame
			if not _metrics_only:
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img.save_jpg(out_dir + "/" + file, 0.9)
			_rows.append(JSON.stringify({"file": file, "seconds": _frame / FPS, "phase": _phase,
				"clip": visual.current_clip() if visual else "", "rate": snappedf(visual.animator.speed_scale, 0.01) if visual else 0.0,
				"speed": snappedf(Vector2(player.velocity.x, player.velocity.z).length(), 0.01),
				"pelvis_y": snappedf(_bone_pos(visual, "pelvis").y - _ground_y, 0.005),
				"knee_l": snappedf(_knee_flex(visual, "l"), 0.1), "knee_r": snappedf(_knee_flex(visual, "r"), 0.1),
				"foot_l": _v(_bone_pos(visual, "foot.l")), "hand_l": _v(_bone_pos(visual, "hand.l"))}))
			_frame += 1
	_release()
	var fh := FileAccess.open(out_dir + "/frames.jsonl", FileAccess.WRITE)
	fh.store_string("\n".join(_rows) + "\n")
	fh.close()
	if not _metrics_only:
		await _contact_sheets(player, visual)
	var report := {}
	for phase in _metrics:
		var m: Dictionary = _metrics[phase]
		var slip: Array = m["slip"]
		slip.sort()
		var widths: Array = m["width"]
		widths.sort()
		report[phase] = {"frames": m["frames"], "clips": m["clips"], "rate_min": m["rate_min"], "rate_max": m["rate_max"],
			"speed_max": m["speed_max"], "airborne_flight_frames": m["flight"],
			"stance_width_median_m": widths[widths.size() / 2] if widths.size() > 0 else -1.0,
			"planted_slip_median_mps": slip[slip.size() / 2] if slip.size() > 0 else -1.0}
	var rh := FileAccess.open(out_dir + "/gait_metrics.json", FileAccess.WRITE)
	rh.store_string(JSON.stringify(report, "  "))
	rh.close()
	print("[locomotion-review] metrics ", JSON.stringify(report))
	print("[locomotion-review] frames=", _frame)
	get_tree().quit()

func _bone_pos(visual: CharacterVisual, bone: String) -> Vector3:
	if visual == null or visual.skeleton == null or visual.skeleton.find_bone(bone) < 0:
		return Vector3.ZERO
	var att: BoneAttachment3D = _attach.get(bone)
	if att == null:
		att = BoneAttachment3D.new()
		att.bone_name = bone
		visual.skeleton.add_child(att)
		_attach[bone] = att
	return att.global_position

## Knee flexion in degrees (0 = straight leg): angle between thigh and shin.
func _knee_flex(visual: CharacterVisual, side: String) -> float:
	var hip := _bone_pos(visual, "thigh." + side)
	var knee := _bone_pos(visual, "shin." + side)
	var ankle := _bone_pos(visual, "foot." + side)
	if (knee - hip).length() < 0.01 or (ankle - knee).length() < 0.01:
		return -1.0
	return rad_to_deg((knee - hip).angle_to(ankle - knee))

func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.005), snappedf(p.y, 0.005), snappedf(p.z, 0.005)]

func _foot_positions(visual: CharacterVisual) -> Dictionary:
	var pos := {}
	if visual == null or visual.skeleton == null:
		return pos
	for bone in ["foot.l", "foot.r"]:
		var att: BoneAttachment3D = _attach.get(bone)
		if att == null:
			att = BoneAttachment3D.new()
			att.bone_name = bone
			visual.skeleton.add_child(att)
			_attach[bone] = att
		pos[bone] = att.global_position
	return pos

func _measure(player: Player, visual: CharacterVisual) -> void:
	if visual == null:
		return
	var feet := _foot_positions(visual)
	if feet.size() < 2:
		return
	if not _metrics.has(_phase):
		_metrics[_phase] = {"frames": 0, "clips": {}, "rate_min": 99.0, "rate_max": 0.0, "speed_max": 0.0, "flight": 0, "slip": [], "width": []}
	var m: Dictionary = _metrics[_phase]
	m["frames"] += 1
	var clip := visual.current_clip()
	m["clips"][clip] = int(m["clips"].get(clip, 0)) + 1
	if clip in CharacterVisual.LOCOMOTION:
		m["rate_min"] = minf(m["rate_min"], visual.animator.speed_scale)
		m["rate_max"] = maxf(m["rate_max"], visual.animator.speed_scale)
	m["speed_max"] = maxf(m["speed_max"], Vector2(player.velocity.x, player.velocity.z).length())
	# Flat-foot ankle height above the visual root (its y carries the sole
	# alignment offset and the landing dip).
	var base := visual.global_position.y
	var l: Vector3 = feet["foot.l"]
	var r: Vector3 = feet["foot.r"]
	# Ankle bones sit ~0.13 m above the sole when the foot is flat.
	var lift_l := l.y - base - 0.13
	var lift_r := r.y - base - 0.13
	if player.is_on_floor() and lift_l > 0.035 and lift_r > 0.035 and clip in CharacterVisual.LOCOMOTION:
		m["flight"] += 1
	var right := player.global_transform.basis.x
	if (lift_l < 0.02) != (lift_r < 0.02):   # single support: mid-stance width
		m["width"].append(absf((l - r).dot(right)))
	for bone in feet:
		var p: Vector3 = feet[bone]
		var planted: bool = p.y - base - 0.13 < 0.02
		if planted and _prev_feet.has(bone) and _prev_feet[bone][1]:
			var prev: Vector3 = _prev_feet[bone][0]
			m["slip"].append(Vector2(p.x - prev.x, p.z - prev.z).length() * FPS)
		_prev_feet[bone] = [p, planted]

## One full cycle per gait from the side and from behind, 8 phases each.
func _contact_sheets(player: Player, visual: CharacterVisual) -> void:
	if visual == null:
		return
	player.respawn_at(START + Vector3(0.0, 0.0, 6.0), 0.0)
	for i in 20:
		await get_tree().physics_frame
	Game.simulation_paused = true
	visual.ignore_simulation_pause = true
	var cam := Camera3D.new()
	cam.fov = 32.0
	add_child(cam)
	cam.current = true
	var fwd := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	var views := {"side": right * 4.6 + Vector3.UP * 1.0, "behind": -fwd * 4.6 + Vector3.UP * 1.15}
	for clip in ["walk", "run", "sprint"]:
		if not visual._clips.has(clip):
			continue
		var anim := visual.animator.get_animation(visual._clips[clip])
		for view in views:
			cam.global_position = player.global_position + views[view]
			cam.look_at(player.global_position + Vector3.UP * 0.9)
			for k in 8:
				visual._current = clip
				visual.animator.play(visual._clips[clip], 0.0)
				visual.animator.speed_scale = 0.0
				visual.animator.seek(anim.length * float(k) / 8.0, true)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img.save_jpg(out_dir + "/sheets/%s_%s_%d.jpg" % [clip, view, k], 0.92)
	cam.current = false
	player.camera.current = true
	visual.ignore_simulation_pause = false
	Game.simulation_paused = false
