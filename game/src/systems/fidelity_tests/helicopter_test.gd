extends Node3D
## Mechanical fixtures with the production Player/Helicopter classes.
## Explicit repositioning isolates camera/control/roof physics. This scene is
## NOT evidence of district appearance, geographic accuracy or a flown route.
var heli: Helicopter
var player: Player
var failures: Array[String] = []
var checks := 0
var metrics := {}
var _started := 0

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args():
		push_error("Helicopter regression requires isolated --qa-session directory")
		get_tree().quit(2)
		return
	_run.call_deferred()

func check(label: String, condition: bool, detail: String = "") -> bool:
	checks += 1
	print("[heli-fidelity] %s %s %s" % ["PASS" if condition else "FAIL", label, detail])
	if not condition: failures.append(label)
	return condition

func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func press_e() -> void:
	Input.action_press("interact")
	await get_tree().process_frame
	await frames(2)
	Input.action_release("interact")
	await get_tree().process_frame
	await frames(3)

func release_inputs() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back", "jump", "sprint", "interact"]:
		Input.action_release(action)

func platform(label: String, top: Vector3, size: Vector2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 2.0, size.y)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	(mesh.mesh as BoxMesh).size = shape.size
	mesh.material_override = Palette.mat(Color(0.3, 0.35, 0.38), 0.9)
	body.add_child(mesh)
	add_child(body)
	body.global_position = top - Vector3.UP
	return body

func _run() -> void:
	_started = Time.get_ticks_msec()
	release_inputs()
	Game.simulation_paused = false
	Game.health = Game.MAX_HEALTH
	Game.last_safe_position = Vector3(10, 0.2, 10)
	Game.last_safe_rotation = 0.0
	platform("GroundFixture", Vector3.ZERO, Vector2(50, 50))
	platform("OrdinaryRoofFixture", Vector3(80, 100, 0), Vector2(40, 40))
	platform("NarrowRoofFixture", Vector3(-80, 100, 50), Vector2(3.2, 6.4))
	platform("SubmergedSupportFixture", Vector3(-70, -2, 0), Vector2(30, 30))
	player = Player.new()
	player.name = "RealPlayer"
	player.position = Vector3(10, 0.2, 10)
	add_child(player)
	heli = Helicopter.new()
	heli.name = "RealHelicopter"
	heli.position = Vector3(0, 200, 0)
	add_child(heli)
	await frames(10)
	heli.set_physics_process(false)
	heli.set_process(false)
	heli.global_position = Vector3(0, 200, 0)
	heli.velocity = Vector3.ZERO
	heli.interact(player)
	await frames(2)
	if "--heli-exit-repair-probe" in OS.get_cmdline_user_args():
		heli.set_physics_process(true)
		await _refusal_checks()
		_finish()
		return
	check("production occupancy is exclusive", player.current_vehicle == heli and Game.mode == Game.MODE_HELI and heli.pilot_is_player and player.collision_layer == 0)
	_camera_checks()
	await _camera_obstruction_checks()
	await _camera_initial_overlap_checks()
	await _descent_checks()
	await _roof_exit_checks()
	await _refusal_checks()
	_finish()

func _finish() -> void:
	release_inputs()
	Sfx.shutdown_audio()
	print("[heli-fidelity] RESULT ", JSON.stringify({"checks": checks, "failures": failures, "metrics": metrics, "mode": "exit_repair_probe" if "--heli-exit-repair-probe" in OS.get_cmdline_user_args() else "full", "fixture_assisted": true, "native_human_input": false, "rendered_appearance_acceptance": false, "elapsed_s": (Time.get_ticks_msec() - _started) / 1000.0}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _camera_checks() -> void:
	var foot_yaw := player.yaw
	var foot_pitch := player.pitch
	Game.settings["mouse_sensitivity"] = 1.0
	Game.settings["invert_y"] = false
	var yaw_before := heli._cam_yaw
	player._apply_mouse_look(Vector2(200, 80))
	check("shared mouse path changes helicopter orbit", absf(wrapf(heli._cam_yaw - yaw_before, -PI, PI)) > 0.3)
	check("helicopter look leaves hidden foot view alone", player.yaw == foot_yaw and player.pitch == foot_pitch)
	var samples: Array[float] = []
	for i in 4:
		heli._cam_yaw = 0.0
		heli.apply_look_motion(Vector2(-float(i) * PI * 0.5 / Player.MOUSE_SENS, 0), Player.MOUSE_SENS, false)
		heli._update_chase_camera(1.0 / 60.0)
		var bearing := atan2(heli._camera.global_basis.z.x, heli._camera.global_basis.z.z)
		samples.append(bearing)
		check("free orbit reaches cardinal %d" % i, absf(wrapf(bearing - float(i) * PI * 0.5, -PI, PI)) < 0.001)
	heli._cam_pitch = 0.0
	player._apply_mouse_look(Vector2(0, -20000))
	heli._update_chase_camera(1.0 / 60.0)
	check("look up reaches near vertical", (-heli._camera.global_basis.z).y > 0.999 and heli._cam_pitch > deg_to_rad(88.0))
	player._apply_mouse_look(Vector2(0, 40000))
	heli._update_chase_camera(1.0 / 60.0)
	check("look down reaches near vertical", (-heli._camera.global_basis.z).y < -0.999 and heli._cam_pitch < deg_to_rad(-88.0))
	heli._cam_pitch = 0.0
	Game.settings["invert_y"] = true
	player._apply_mouse_look(Vector2(0, 100))
	check("invert Y applies to aircraft look", heli._cam_pitch > 0.1)
	Game.settings["invert_y"] = false
	heli._cam_yaw = 1.1
	heli._cam_pitch = -0.4
	heli._update_chase_camera(1.0 / 60.0)
	var held_basis := heli._camera.global_basis
	var y_min := INF
	var y_max := -INF
	for fps in [30.0, 60.0, 144.0]:
		for i in int(fps * 2.0):
			heli.rotation.y += 0.01 # aircraft turn must not steer the look direction
			heli._body.rotation.z = sin(float(i) * 0.5) * 0.5
			heli._touch_dip = 0.16 if i % 2 == 0 else 0.0
			heli._update_chase_camera(1.0 / fps)
			y_min = minf(y_min, heli._camera.global_position.y)
			y_max = maxf(y_max, heli._camera.global_position.y)
	check("no-input view remains world-stable through turns and banks", held_basis.get_rotation_quaternion().angle_to(heli._camera.global_basis.get_rotation_quaternion()) < 0.0001)
	check("no vertical camera spring oscillation at30/60/144fps", y_max - y_min < 0.0001, "peak_to_peak_y=%.6f" % (y_max - y_min))
	check("orbit horizon has no aircraft bank roll", absf(heli._camera.global_basis.x.y) < 0.0001)
	var angles := Vector2(heli._cam_yaw, heli._cam_pitch)
	Game.simulation_paused = true
	player._apply_mouse_look(Vector2(200, 200))
	check("pause prevents aircraft look mutation", angles == Vector2(heli._cam_yaw, heli._cam_pitch))
	Game.simulation_paused = false
	metrics["cardinal_yaws"] = samples
	metrics["steady_camera_vertical_range_m"] = y_max - y_min

func _camera_obstruction_checks() -> void:
	heli.rotation.y = 0.0
	heli._cam_yaw = 0.0
	heli._cam_pitch = 0.0
	var wall := platform("CameraWallFixture", Vector3(0, 220, 6), Vector2(40, 1))
	# Platform helper makes2m tall body; make this wall tall around the pivot.
	(wall.get_child(0) as CollisionShape3D).shape = BoxShape3D.new()
	((wall.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = Vector3(40, 40, 1)
	wall.global_position.y = 203.2
	((wall.get_child(1) as MeshInstance3D).mesh as BoxMesh).size = Vector3(40, 40, 1)
	await frames(2)
	heli._update_chase_camera(1.0 / 60.0)
	check("orbit camera stays in front of intervening geometry", heli._camera.global_position.z < 5.4 and heli._cam_distance < 6.0)
	var probe := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.29
	probe.shape = ball
	probe.transform = Transform3D(Basis.IDENTITY, heli._camera.global_position)
	probe.collision_mask = 1
	check("camera sphere does not penetrate wall", get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty())
	wall.queue_free()
	await frames(2)
	var previous := heli._cam_distance
	var outward := true
	for i in 120:
		heli._update_chase_camera(1.0 / 60.0)
		outward = outward and heli._cam_distance >= previous and heli._cam_distance <= Helicopter.CAMERA_DISTANCE + 0.0001
		previous = heli._cam_distance
	check("cleared camera distance recovers without oscillation", outward and heli._cam_distance > 11.9)

func _camera_initial_overlap_checks() -> void:
	# A thin overhead beam clears the aircraft's body but overlaps the
	# camera pivot sphere and the requested horizontal orbit endpoint.
	heli._cam_yaw = PI * 0.5
	heli._cam_pitch = 0.0
	heli._update_chase_camera(1.0 / 60.0)
	var clear_before := heli._camera.global_transform
	var beam := platform("CameraPivotOverlapFixture", Vector3(0, 204.2, 0), Vector2(0.4, 30))
	var beam_size := Vector3(0.4, 0.4, 30)
	((beam.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = beam_size
	((beam.get_child(1) as MeshInstance3D).mesh as BoxMesh).size = beam_size
	await frames(2)
	heli._cam_yaw = 0.0
	heli._update_chase_camera(1.0 / 60.0)
	check("occupied pivot and endpoint retain a known-clear pose", heli._camera.global_position.is_equal_approx(clear_before.origin) and heli._camera_position_clear(heli._camera.global_position))
	heli._cam_has_clear_pose = false
	heli._cam_pitch = 0.0
	heli._update_chase_camera(1.0 / 60.0)
	check("first occupied-pivot frame finds a clear side without losing requested yaw", heli._camera_position_clear(heli._camera.global_position) and is_equal_approx(heli._cam_yaw, 0.0))
	heli._cam_pitch = -0.6
	heli._update_chase_camera(1.0 / 60.0)
	check("reverse sweep exits an initially overlapping pivot", heli._camera_position_clear(heli._camera.global_position) and heli._cam_distance < Helicopter.CAMERA_DISTANCE - 1.0)
	beam.queue_free()
	await frames(2)
	heli._cam_pitch = 0.0
	for i in 120: heli._update_chase_camera(1.0 / 60.0)
	check("clearing pivot obstruction restores requested orbit", heli._camera_position_clear(heli._camera.global_position) and absf(heli._camera.global_basis.z.x) < 0.001 and heli._camera.global_basis.z.z > 0.99)

func _descent_checks() -> void:
	heli.rotation = Vector3.ZERO
	heli.global_position = Vector3(0, 200, 0)
	heli.velocity = Vector3.ZERO
	heli._lift_input = 0.0
	heli._body.rotation = Vector3.ZERO
	heli.health = 100.0
	heli.disabled = false
	heli.set_physics_process(true)
	Input.action_press("sprint")
	await frames(120)
	metrics["high_descent_speed_mps"] = -heli.velocity.y
	metrics["descent_in_first2s_m"] = 200.0 - heli.global_position.y
	check("Shift reaches a substantially faster high-altitude descent", heli.velocity.y < -18.0 and heli.global_position.y < 175.0, "velocity_y=%.3f altitude=%.3f" % [heli.velocity.y, heli.global_position.y])
	Input.action_release("sprint")
	await frames(60)
	check("releasing descent arrests sink into hover", absf(heli.velocity.y) < 0.5)
	Input.action_press("sprint")
	for i in 900:
		await frames(1)
		if heli.is_landed(): break
	Input.action_release("sprint")
	await frames(5)
	check("fast descent still lands without damage", heli.is_on_floor() and heli.is_landed() and heli.health > 99.9 and not heli.disabled, "y=%.3f health=%.1f" % [heli.global_position.y, heli.health])
	check("landing cushion keeps touchdown gentle", heli.last_touchdown_speed < 1.6, "touchdown_mps=%.3f" % heli.last_touchdown_speed)
	await press_e()
	check("ordinary ground E exit restores foot control", player.current_vehicle == null and Game.mode == Game.MODE_FOOT and player.visible and player.collision_layer == 2)

func _roof_exit_checks() -> void:
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
		heli.global_position = Vector3(80, 103, 0)
		heli.velocity = Vector3.ZERO
		heli.rotation = Vector3(0, yaw, 0)
		player.respawn_at(Vector3(80, 100.1, 3.5), yaw)
		heli.interact(player) # explicit boarding fixture; flight/exit stay native physics/input
		Input.action_press("sprint")
		await frames(3) # invalidate floor contact cached before fixture relocation
		for i in 150:
			await frames(1)
			if heli.is_landed(): break
		Input.action_release("sprint")
		await frames(5)
		check("ordinary rooftop physically supports aircraft heading%.0f" % rad_to_deg(yaw), heli.is_on_floor() and heli.is_landed())
		var exit_pos := heli.landing_exit_position()
		check("unmarked roof has a supported clear exit heading%.0f" % rad_to_deg(yaw), exit_pos != Vector3.ZERO and absf(exit_pos.y - 100.0) < 0.3)
		await press_e()
		check("E exits an unmarked roof heading%.0f" % rad_to_deg(yaw), player.current_vehicle == null and Game.mode == Game.MODE_FOOT and player.visible)
		await frames(8)
		check("roof exit leaves live supported capsule heading%.0f" % rad_to_deg(yaw), player.is_on_floor() and absf(player.global_position.y - 100.0) < 0.2 and player.collision_mask == Player.COLLIDE_MASK)
		var start := player.global_position
		Input.action_press("move_forward")
		await frames(15)
		var first_step_m := player.global_position.distance_to(start)
		# The existing authored standstill acceleration takes about0.3s to
		# complete its first step. The original0.25s sample demanded0.3m
		# before that step had time to finish. Retain the early observation,
		# then demand real sustained movement, without changing locomotion.
		await frames(45)
		Input.action_release("move_forward")
		var moved := player.global_position.distance_to(start)
		var contacts: Array[String] = []
		for i in player.get_slide_collision_count():
			var collider := player.get_slide_collision(i).get_collider()
			if collider is Node: contacts.append(str((collider as Node).get_path()))
		var detail := "first0.25s=%.3fm total1s=%.3fm speed=%.3f floor=%s contacts=%s" % [first_step_m, moved, Vector2(player.velocity.x, player.velocity.z).length(), player.is_on_floor(), contacts]
		metrics["roof_walk_%.0f" % rad_to_deg(yaw)] = {"first_step_m": first_step_m, "one_second_m": moved, "contacts": contacts}
		check("on-foot movement remains usable on roof heading%.0f" % rad_to_deg(yaw), moved > 2.0 and player.is_on_floor() and Game.mode == Game.MODE_FOOT, detail)

func _refusal_checks() -> void:
	# Real capsule obstructions around an otherwise valid large roof.
	heli.global_position = Vector3(80, 103, 0)
	heli.velocity = Vector3.ZERO
	heli.rotation = Vector3.ZERO
	heli.interact(player)
	Input.action_press("sprint")
	await frames(3)
	for i in 160:
		await frames(1)
		if heli.is_landed(): break
	Input.action_release("sprint")
	await frames(5)
	var blocks: Array[StaticBody3D] = []
	for offset in [Vector3(2.8, 0, 0), Vector3(-2.8, 0, 0), Vector3(0, 0, 4), Vector3(0, 0, -4)]:
		blocks.append(platform("BlockedExitFixture", Vector3(80, 103, 0) + offset, Vector2(1, 1)))
	await frames(3)
	check("blocked roof capsule paths produce no exit", heli.is_on_floor() and heli.landing_exit_position() == Vector3.ZERO)
	await press_e()
	check("blocked roof exit retains pilot ownership", player.current_vehicle == heli and Game.mode == Game.MODE_HELI)
	await _wreck_recovery_check("blocked roof")
	for block in blocks: block.queue_free()
	await frames(3)
	heli.health = 100.0 # explicit repaired fixture for subsequent cases
	heli.disabled = false
	heli.interact(player)
	_repair_snapshot("reboard_immediate")
	await frames(6) # observe actual neutral support, not a forced landed flag
	_repair_snapshot("reboard_after_physics")
	# Wreck recovery/fixture repair can leave the aircraft above the roof.
	# Neutral collective correctly holds that altitude. Do not make this
	# positive test depend on a hovering aircraft being allowed to exit.
	if not heli.is_on_floor():
		await press_e()
		_repair_snapshot("hover_exit_refused")
		check("healthy repaired hover still refuses unsupported E exit", player.current_vehicle == heli and heli.pilot_is_player and Game.mode == Game.MODE_HELI)
	Input.action_press("sprint")
	await frames(3)
	for i in 150:
		await frames(1)
		if heli.is_on_floor() and heli.is_landed(): break
	Input.action_release("sprint")
	await frames(5)
	_repair_snapshot("native_setdown")
	check("native Shift sets repaired fixture down on its roof", heli.is_on_floor() and heli.is_landed(), str(metrics.get("repair_native_setdown", {})))
	await press_e()
	_repair_snapshot("after_exit_key")
	check("removing physical obstruction permits healthy E exit", player.current_vehicle == null and Game.mode == Game.MODE_FOOT, str(metrics.get("repair_after_exit_key", {})))
	heli.global_position = Vector3(-80, 103, 50)
	heli.velocity = Vector3.ZERO
	heli.rotation = Vector3.ZERO
	heli.interact(player)
	Input.action_press("sprint")
	await frames(3)
	for i in 160:
		await frames(1)
		if heli.is_landed(): break
	Input.action_release("sprint")
	await frames(5)
	check("narrow roof supports aircraft but has no safe foot space", heli.is_on_floor() and heli.landing_exit_position() == Vector3.ZERO)
	await press_e()
	check("unsafe narrow-roof exit retains occupancy", player.current_vehicle == heli and heli.pilot_is_player and Game.mode == Game.MODE_HELI)
	await _wreck_recovery_check("narrow roof")
	heli.health = 100.0 # explicit repaired fixture, not a production repair
	heli.disabled = false
	heli.interact(player)
	heli.global_position = Vector3(-70, 0, 0)
	heli.velocity = Vector3.ZERO
	Input.action_press("sprint")
	await frames(180)
	Input.action_release("sprint")
	check("submerged support never creates an underwater foot exit", heli.is_on_floor() and heli.landing_exit_position() == Vector3.ZERO)
	await press_e()
	check("underwater exit refusal preserves occupancy", player.current_vehicle == heli and not player.visible)
	await _wreck_recovery_check("submerged support")
	heli.health = 100.0
	heli.disabled = false
	heli.interact(player)
	heli.global_position = Vector3(0, 150, 0)
	heli.velocity = Vector3.ZERO
	await frames(4)
	await press_e()
	check("unsupported airborne exit remains refused", player.current_vehicle == heli and heli.pilot_is_player)

func _wreck_recovery_check(label: String) -> void:
	var health_before := Game.health
	var mission_before := Game.mission_stage
	heli.take_damage(1000.0, heli.global_position, false)
	await frames(3)
	check("native damage disables occupied aircraft on " + label, heli.disabled and heli.health <= 0.0 and heli.pilot_is_player and player.current_vehicle == heli)
	await press_e()
	check("actual E recovers disabled pilot from " + label, player.current_vehicle == null and Game.mode == Game.MODE_FOOT and player.visible and player.alive and not player.busy and not heli.pilot_is_player and player.global_position.distance_to(Game.last_safe_position) < 0.4)
	check("wreck recovery preserves player health and mission on " + label, is_equal_approx(Game.health, health_before) and Game.mission_stage == mission_before)

func _repair_snapshot(label: String) -> void:
	var row := {"heli_position": str(heli.global_position), "heli_velocity": str(heli.velocity), "floor": heli.is_on_floor(), "landed": heli.is_landed(), "pilot": heli.pilot_is_player, "disabled": heli.disabled, "lift": heli._lift_input, "exit_position": str(heli.landing_exit_position()), "mode": Game.mode, "player_vehicle": str(player.current_vehicle), "player_busy": player.busy, "interact_held": Input.is_action_pressed("interact"), "interact_armed": player._press_armed.get("interact", true)}
	metrics["repair_" + label] = row
	print("[heli-fidelity] REPAIR_DIAGNOSTIC ", label, " ", JSON.stringify(row))
