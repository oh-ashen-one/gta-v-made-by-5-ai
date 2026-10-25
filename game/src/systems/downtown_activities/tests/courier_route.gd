extends Node3D
## Controls-based route from the normal player start: heritage pickup,
## cancellation/repeat, Jubilee + Helix walk, MBS handover, return and repeat.
## No position assignments, respawns, forced stages or vehicle teleports.
const Courier = preload("res://src/systems/downtown_activities/courier.gd")
var main: Node
var activity: Node
var player: Player
var checks := 0
var failures: Array[String] = []
var _started := 0
var _travel := 0.0
var _last_position := Vector3.ZERO
var _max_step := 0.0
var _initial_deaths := 0
var _curb_jumps := 0

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player) or Game.simulation_paused: return
	var step := player.global_position.distance_to(_last_position)
	_max_step = maxf(_max_step, step)
	_travel += step
	_last_position = player.global_position

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args():
		push_error("Courier route requires --qa-session <isolated directory>")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _check(label: String, passed: bool, detail: String = "") -> bool:
	checks += 1
	print("[courier-test] %s %s %s" % ["PASS" if passed else "FAIL", label, detail])
	if not passed: failures.append(label + " " + detail)
	return passed

func _run() -> void:
	_started = Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	player = main.player
	activity = get_tree().get_first_node_in_group("downtown_activity")
	if activity == null:
		activity = Courier.new()
		main.add_child(activity)
		activity.setup(main.world, player)
	main.started = true
	main.hud.show_title(false)
	Game.simulation_paused = false
	_initial_deaths = Game.death_count
	_last_position = player.global_position
	await get_tree().create_timer(0.5).timeout
	_check("far pickup rejected", not activity.use_station("heritage", player) and activity.stage == Courier.Stage.IDLE)
	_check("unknown station rejected", not activity.use_station("unknown", player))
	var route_start: Array[Vector3] = [Vector3(-164, 0, -22), Vector3(-164, 0, -300), Vector3(-164, 0, -337), activity.stations.heritage.global_position]
	if not await _walk(route_start, "heritage approach"):
		_finish()
		return
	_check("dispatch physically reachable", activity.can_use_station("heritage"))
	var stranger := Node.new()
	_check("foreign actor rejected", not activity.use_station("heritage", stranger))
	stranger.free()
	Game.simulation_paused = true
	_check("paused handover rejected", not activity.can_use_station("heritage"))
	Game.simulation_paused = false
	player.busy = true
	_check("busy transition rejected", not activity.can_use_station("heritage"))
	player.busy = false
	for mode in [Game.MODE_CAR, Game.MODE_HELI]:
		Game.mode = mode
		_check("vehicle mode rejects handover %d" % mode, not activity.can_use_station("heritage"))
	Game.mode = Game.MODE_FOOT
	await _press_e()
	_check("E picks up parcel", activity.stage == Courier.Stage.OUTBOUND)
	var snapshot: Dictionary = activity.serialize_state()
	var saved_stage: int = main.mission.stage
	var saved_marker: Vector3 = main.mission.get_meta("marker", Vector3.ZERO)
	_check("snapshot survives JSON roundtrip", activity.restore_state(JSON.parse_string(JSON.stringify(snapshot))))
	_check("invalid snapshot rejected atomically", not activity.restore_state({"version": 1, "stage": 99, "completed_runs": 0}) and activity.serialize_state() == snapshot)
	_check("fractional state rejected", not Courier.valid_state({"version": 1, "stage": 1.5, "completed_runs": 0}))
	_check("legacy empty payload rejected by parser", not Courier.valid_state({}))
	await _press_e()
	_check("E returns parcel to cancel", activity.stage == Courier.Stage.IDLE and activity.completed_runs == 0)
	await _press_e()
	_check("cancelled run can restart", activity.stage == Courier.Stage.OUTBOUND)
	_check("remote destination rejected", not activity.use_station("bayfront", player))
	# A temporary test wall proves the production E contract respects line of
	# sight. It is removed before travel; the world route is never modified.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 5, 0.3)
	shape.shape = box
	wall.add_child(shape)
	main.add_child(wall)
	wall.global_position = player.global_position.lerp(activity.stations.heritage.global_position, 0.5) + Vector3(0, 1.5, 0)
	wall.look_at(wall.global_position + (activity.stations.heritage.global_position - player.global_position).normalized(), Vector3.UP)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("wall blocks handover", not activity.can_use_station("heritage"))
	wall.queue_free()
	await get_tree().physics_frame
	var outbound := _bayfront_path()
	if not await _walk(outbound, "Jubilee and Helix to MBS"):
		_finish()
		return
	_check("MBS destination physically reachable", activity.can_use_station("bayfront"))
	await _press_e()
	_check("E handover creates return receipt", activity.stage == Courier.Stage.RECEIPT)
	_check("delivery cannot be duplicated", not activity.use_station("bayfront", player) and activity.completed_runs == 0)
	_check("story objective unchanged", main.mission.stage == saved_stage and main.mission.get_meta("marker", Vector3.ZERO) == saved_marker)
	var receipt: Dictionary = activity.serialize_state()
	_check("receipt checkpoint restores", activity.restore_state(JSON.parse_string(JSON.stringify(receipt))) and activity.stage == Courier.Stage.RECEIPT)
	outbound.reverse()
	outbound.append(activity.stations.heritage.global_position)
	if not await _walk(outbound, "receipt return"):
		_finish()
		return
	await _press_e()
	_check("return completes once", activity.stage == Courier.Stage.IDLE and activity.completed_runs == 1)
	await _press_e()
	_check("completed route repeatable", activity.stage == Courier.Stage.OUTBOUND and activity.completed_runs == 1)
	await _press_e()
	_check("repeat cancellation keeps completion count", activity.stage == Courier.Stage.IDLE and activity.completed_runs == 1)
	_check("route has no teleport steps", _max_step < 2.0, "max_step=%.3f travel=%.1fm" % [_max_step, _travel])
	_check("route has no deaths", Game.death_count == _initial_deaths)
	activity.reset_state()
	_check("new game resets activity", activity.stage == Courier.Stage.IDLE and activity.completed_runs == 0)
	_finish()

func _bayfront_path() -> Array[Vector3]:
	var points: Array[Vector3] = [Vector3(-330, 0, -337), Vector3(-440, 0, -338), Vector3(-458, 0, -344), Vector3(-460, 0, -372), Vector3(-488, 0, -380), Vector3(-521, 0, -384), Vector3(-521, 0, -400), Vector3(-657.5, 0, -400), Vector3(-657, 0, -409), Vector3(-648, 0, -440), Vector3(-648, 0, -560), Vector3(-647, 0, -630), Vector3(-647, 0, -659), Vector3(-641, 0, -666), Vector3(-560, 0, -666), Vector3(-500, 0, -666), Vector3(-488, 0, -668), Vector3(-489, 0, -700), Vector3(-492, 0, -733), Vector3(-498, 0, -741), Vector3(-497, 0, -745.2), Vector3(-487, 0, -745.4)]
	var bridge: Dictionary = DowntownPlan.BRIDGES["helix_bridge"]
	for u: float in [0.04, 0.12, 0.22, 0.32, 0.42, 0.5, 0.58, 0.68, 0.78, 0.88, 0.96, 1.0]:
		var a: Vector3 = bridge["from"]
		var b: Vector3 = bridge["to"]
		points.append(Vector3(lerpf(a.x, b.x, u), 0, lerpf(a.z, b.z, u) - 6 * sin(PI * u)))
	# Around the north end of the solid Shoppes podium to the promenade.
	var mbs := DowntownPlan.anchor("marina_bay_sands")
	points.append_array([Vector3(-258, 0, -745), Vector3(-258, 0, -732), Vector3(mbs.x - 204, 0, -732), Vector3(mbs.x - 204, 0, -665), Vector3(mbs.x - 204, 0, -635), activity.stations.bayfront.global_position])
	return points

func _walk(points: Array[Vector3], label: String) -> bool:
	for i in points.size():
		var target := points[i]
		var arrival_radius := 2.0 if i == points.size() - 1 else 3.0
		var deadline := Time.get_ticks_msec() + 75000
		var best := INF
		var last_progress := Time.get_ticks_msec()
		var sidesteps := 0
		while Time.get_ticks_msec() < deadline:
			await get_tree().physics_frame
			var delta := target - player.global_position
			delta.y = 0
			if delta.length() < arrival_radius: break
			if delta.length() < best - 0.5:
				best = delta.length()
				last_progress = Time.get_ticks_msec()
			if Time.get_ticks_msec() - last_progress > 4000:
				# Baseline diagnostic only: bypass no physics, use the actual jump
				# input at the already reported 0.3m heritage curb. Default test
				# forbids this so a successful jump cannot hide a missing ramp.
				if "--courier-baseline-curb-jump" in OS.get_cmdline_user_args() and absf(player.global_position.z + 326.66) < 1.0 and _curb_jumps == 0:
					_curb_jumps += 1
					print("[courier-route] BASELINE CURB JUMP; this does not prove a seamless walk")
					Input.action_press("jump")
					await get_tree().create_timer(0.2).timeout
					Input.action_release("jump")
					last_progress = Time.get_ticks_msec()
					continue
				if sidesteps >= 4:
					_release()
					return _check(label, false, "stalled waypoint %d target=%s at=%s" % [i, target, player.global_position])
				var colliders: Array[String] = []
				for contact in player.get_slide_collision_count():
					var collider := player.get_slide_collision(contact).get_collider()
					if collider is Node3D: colliders.append("%s @ %s" % [collider.get_path(), collider.global_position])
				print("[courier-route] sidestep %d at %s contacts=%s" % [sidesteps, player.global_position, colliders])
				Input.action_release("sprint")
				Input.action_release("move_forward")
				var side := "move_right" if sidesteps % 2 == 0 else "move_left"
				Input.action_press(side)
				await get_tree().create_timer(0.9 + sidesteps * 0.4).timeout
				Input.action_release(side)
				sidesteps += 1
				last_progress = Time.get_ticks_msec()
				best = (target - player.global_position).length()
			player.yaw = lerp_angle(player.yaw, atan2(-delta.x, -delta.z), 0.18)
			Input.action_press("move_forward")
			Input.action_press("sprint")
		_release()
		if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() >= arrival_radius + 0.5:
			return _check(label, false, "timeout waypoint %d at=%s" % [i, player.global_position])
		print("[courier-route] %s %d/%d at=%s" % [label, i + 1, points.size(), player.global_position])
	return _check(label, true)

func _press_e() -> void:
	_release()
	await get_tree().create_timer(0.2).timeout
	Input.action_press("interact")
	await get_tree().create_timer(0.08).timeout
	Input.action_release("interact")
	await get_tree().create_timer(0.15).timeout

func _release() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact"]: Input.action_release(action)

func _finish() -> void:
	_release()
	print("[courier-test] RESULT ", JSON.stringify({"checks": checks, "failures": failures, "travel_m": _travel, "max_step_m": _max_step, "curb_jumps": _curb_jumps, "elapsed_s": (Time.get_ticks_msec() - _started) / 1000.0}))
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures.is_empty() else 1)
