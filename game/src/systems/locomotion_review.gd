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
			await _record(player, visual)
	_release()
	await _extra_phases(player, visual)
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

## One captured frame: wait a simulated frame, measure, save the image.
## Headless metrics: also wait the process frame so one sample is one
## animation/skeleton update (2 physics ticks at --fixed-fps 30), like the
## rendered run; sampling per physics tick mixed stale and fresh poses.
func _record(player: Player, visual: CharacterVisual) -> void:
	await get_tree().physics_frame
	if _metrics_only:
		await get_tree().process_frame
		await get_tree().physics_frame
	if _low_cam != null and _low_cam.current:
		_follow_low_cam(player)
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
		"foot_l": _v(_bone_pos(visual, "foot.l")), "hand_l": _v(_bone_pos(visual, "hand.l")),
		"pos": _v(player.global_position), "yaw": snappedf(rad_to_deg(player.rotation.y), 0.1),
		"cam": _v(player.camera.global_position), "cam_yaw": snappedf(rad_to_deg(player.camera.global_rotation.y), 0.1),
		"hand_r": _v(_bone_pos(visual, "hand.r")), "head": _v(_bone_pos(visual, "head")),
		"head_yaw_rel": _head_dir(player, visual).x, "head_pitch": _head_dir(player, visual).y,
		"look_yaw": snappedf(rad_to_deg(float(player.get("_look_yaw"))), 0.1)}))
	_frame += 1

# Locomotion-Q additions (run-2 critic spec): a low full-figure tracking shot
# of the walk, aimed strafe and backpedal in the heritage five-foot way, and
# walking into the crowd and into a kerbside scooter/bike row.
var _low_cam: Camera3D
const ARCADE := Vector3(-150.0, 0.45, -148.0)
const ARCADE_YAW := -0.977 # -56 deg, the heritage_arcade gameplay view's line

var _low_front := false
var _obs := false
func _follow_low_cam(player: Player) -> void:
	var right := player.global_transform.basis.x
	var fwd := -player.global_transform.basis.z
	var target := player.global_position + right * 3.3 + fwd * 0.6 + Vector3.UP * 0.55
	if _low_front:
		# GTAV-02-style: a low camera ~4 m ahead, the figure walking at it.
		target = player.global_position + fwd * 3.1 + right * 0.45 + Vector3.UP * 0.62
		_low_cam.global_position = _low_cam.global_position.lerp(target, 0.35) if _low_cam.global_position.distance_to(target) < 2.0 else target
		_low_cam.look_at(player.global_position + Vector3.UP * 0.95)
		return
	if _obs:
		# Full-figure observer 3/4 in front of the aiming player.
		target = player.global_position + right * 2.4 - player.global_transform.basis.z * 3.0 + Vector3.UP * 1.05
		_low_cam.global_position = target
		_low_cam.look_at(player.global_position + Vector3.UP * 0.85)
		return
	_low_cam.global_position = _low_cam.global_position.lerp(target, 0.35) if _low_cam.global_position.distance_to(target) < 2.0 else target
	_low_cam.look_at(player.global_position + Vector3.UP * 0.8 + fwd * 0.3)

func _hold(player: Player, visual: CharacterVisual, phase: String, seconds: float, actions: Dictionary, yaw_rate := 0.0) -> void:
	_phase = phase
	_release()
	for action in actions:
		Input.action_press(action, actions[action])
	for f in int(seconds * FPS):
		if yaw_rate != 0.0:
			player.yaw += yaw_rate / FPS
		await _record(player, visual)

func _place(player: Player, pos: Vector3, yaw: float) -> void:
	_release()
	player.respawn_at(pos, yaw)
	player.pitch = -0.10
	for i in 20:
		await get_tree().physics_frame

func _extra_phases(player: Player, visual: CharacterVisual) -> void:
	# 1. Low full-figure walk (side tracking camera ~0.55 m above the paving).
	await _place(player, START + Vector3(0.0, 0.0, 3.0), 0.0)
	_low_cam = Camera3D.new()
	_low_cam.fov = 40.0
	add_child(_low_cam)
	_low_cam.current = true
	_follow_low_cam(player)
	await _hold(player, visual, "low_stand", 0.6, {})
	await _hold(player, visual, "low_walk", 3.4, {"move_forward": 1.0, "walk": 1.0})
	await _hold(player, visual, "low_stop", 0.8, {})
	await _place(player, START + Vector3(0.0, 0.0, 3.0), 0.0)
	_low_front = true
	_low_cam.current = true
	_follow_low_cam(player)
	await _hold(player, visual, "low_front_walk", 3.0, {"move_forward": 1.0, "walk": 1.0})
	_low_front = false
	_low_cam.current = false
	player.camera.current = true
	# 2. Aimed strafe and backpedal in the five-foot way.
	await _place(player, ARCADE, ARCADE_YAW)
	player.pitch = -0.34 # look down the aim line enough to see the feet
	await _hold(player, visual, "arcade_aim", 0.6, {"aim": 1.0})
	await _hold(player, visual, "arcade_strafe_r", 1.6, {"aim": 1.0, "move_right": 1.0})
	await _hold(player, visual, "arcade_strafe_l", 1.6, {"aim": 1.0, "move_left": 1.0})
	await _hold(player, visual, "arcade_back", 2.0, {"aim": 1.0, "move_back": 1.0})
	await _hold(player, visual, "arcade_fwd", 1.2, {"aim": 1.0, "move_forward": 1.0})
	# The same moves seen full-figure from an observer camera (legs in frame).
	await _place(player, ARCADE, ARCADE_YAW)
	_obs = true
	_low_cam.fov = 46.0
	_low_cam.current = true
	_follow_low_cam(player)
	await _hold(player, visual, "obs_aim", 0.5, {"aim": 1.0})
	await _hold(player, visual, "obs_strafe_r", 1.6, {"aim": 1.0, "move_right": 1.0})
	await _hold(player, visual, "obs_strafe_l", 1.6, {"aim": 1.0, "move_left": 1.0})
	await _hold(player, visual, "obs_back", 2.0, {"aim": 1.0, "move_back": 1.0})
	_obs = false
	_low_cam.current = false
	player.camera.current = true
	# 3. Into the crowd: start 7 m short of the densest knot of pedestrians.
	var crowd := _crowd_spot(player)
	if crowd.size() == 2:
		await _place(player, crowd[0], crowd[1])
		await _hold(player, visual, "crowd_walk", 4.0, {"move_forward": 1.0, "walk": 1.0})
		await _hold(player, visual, "crowd_run", 2.0, {"move_forward": 1.0})
	# 4. Into a kerbside scooter / bike row and a planter.
	for kind in ["scooter", "bike"]:
		var spot := _prop_spot(player, kind)
		if spot.size() == 2:
			await _place(player, spot[0], spot[1])
			await _hold(player, visual, "%s_walk" % kind, 3.0, {"move_forward": 1.0, "walk": 1.0})
			await _hold(player, visual, "%s_run" % kind, 1.6, {"move_forward": 1.0})

## A standing spot 7 m from the pedestrian with the most neighbours (within
## 8 m) near the opening street, facing them.
func _crowd_spot(player: Player) -> Array:
	var best: Node3D = null
	var best_n := 0
	var npcs := get_tree().get_nodes_in_group("npcs")
	for a in npcs:
		var na := a as Node3D
		if na == null or not na.visible or na.global_position.distance_to(START) > 160.0:
			continue
		# Pavement walkers only (not diners seated in the hawker centre).
		var va = na.get("velocity")
		if va == null or Vector2(va.x, va.z).length() < 0.4:
			continue
		var n := 0
		for b in npcs:
			var nb := b as Node3D
			if nb != null and nb != na and nb.visible and nb.global_position.distance_to(na.global_position) < 8.0:
				n += 1
		if n > best_n:
			best_n = n
			best = na
	if best == null:
		return []
	var dir := Vector3(1, 0, 0)
	var lane = best.get("lane_dir")
	var p := best.global_position
	# Approach along the pavement (the pedestrian's own lane line when known).
	var vel := Vector3(best.get("velocity")) if best.get("velocity") != null else Vector3.ZERO
	if Vector2(vel.x, vel.z).length() > 0.2:
		dir = Vector3(vel.x, 0, vel.z).normalized()
	var start := p + dir * 7.0
	start.y = p.y + 0.05
	print("[locomotion-review] crowd spot ", p, " neighbours ", best_n, " lane ", lane)
	return [start, atan2(dir.x, dir.z)]

func _prop_spot(player: Player, kind: String) -> Array:
	var best_d := INF
	var best: Transform3D
	for node in get_tree().current_scene.find_children("StreetDressing_%s_*" % kind, "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		for local_xf in mmi.get_meta("instance_xforms", []):
			var xf := mmi.global_transform * (local_xf as Transform3D)
			var d := xf.origin.distance_to(START)
			if d < best_d:
				best_d = d
				best = xf
	if best_d == INF:
		return []
	# Walk at the row along its own line so the player meets the props.
	var along := best.basis.x.normalized()
	along.y = 0.0
	along = along.normalized()
	var start := best.origin + along * 4.5
	start.y = best.origin.y + 0.4
	print("[locomotion-review] %s spot " % kind, best.origin)
	return [start, atan2(along.x, along.z)]

## integ-Q: where the (final, post-modifier) head points, as degrees of yaw
## off the line of travel (+ = left) and pitch (+ = up), measured against the
## head's bind pose (which faces the body's forward).
func _head_dir(player: Player, visual: CharacterVisual) -> Vector2:
	_bone_pos(visual, "head")
	var att: BoneAttachment3D = _attach.get("head")
	var sk := visual.skeleton if visual != null else null
	if att == null or sk == null:
		return Vector2.ZERO
	var facing := Vector3(-sin(player.rotation.y), 0.0, -cos(player.rotation.y))
	var rest_b := sk.get_bone_global_rest(sk.find_bone("head")).basis.orthonormalized()
	var skb := sk.global_basis.orthonormalized()
	var hf := att.global_basis.orthonormalized() * (rest_b.inverse() * (skb.inverse() * facing))
	var vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var travel := vel.normalized() if vel.length() > 0.3 else facing
	var flat := Vector3(hf.x, 0.0, hf.z).normalized()
	return Vector2(snappedf(rad_to_deg(travel.signed_angle_to(flat, Vector3.UP)), 0.1), snappedf(rad_to_deg(asin(clampf(hf.normalized().y, -1.0, 1.0))), 0.1))

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
