class_name SelfTest
extends Node
## Bounded behavioral regression suite. Fixture repositioning is explicit test
## setup; it is never used by the rendered golden-path input driver.

signal finished(failures: int)

const TEST_SAVE := "/tmp/orchard_reach_wave2_fixture_save.json"
const WATCHDOG_SECONDS := 40.0
var failures := 0
var results: Array[Dictionary] = []
var _started_ms := 0
var _reported := false
var _watchdog_timer: Timer
var _report_path := "user://wave2_test_report.json"

func run(main: Node) -> void:
	_started_ms = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-report="):
			_report_path = arg.trim_prefix("--test-report=")
	_watchdog_timer = Timer.new()
	_watchdog_timer.one_shot = true
	_watchdog_timer.ignore_time_scale = true
	add_child(_watchdog_timer)
	_watchdog_timer.timeout.connect(_watchdog)
	_watchdog_timer.start(WATCHDOG_SECONDS)
	print("=== Orchard Reach wave-2 bounded regression suite ===")
	await _ticks(3)
	var player := main.get_node_or_null("Player") as Player
	var world := main.get_node_or_null("World") as WorldBuilder
	var traffic := main.get_node_or_null("Traffic") as TrafficManager
	var mission := main.get_node_or_null("Mission") as Mission
	var heli := main.get_node_or_null("Helicopter") as Helicopter
	_check("world builder present", world != null)
	_check("player spawned", player != null)
	_check("traffic manager present", traffic != null)
	_check("mission running", mission != null)
	_check("helicopter present", heli != null)
	_check("hud present", main.get_node_or_null("HUD") != null)
	if not player or not world or not traffic or not mission or not heli:
		_report()
		return
	_check("district contains 3D geometry", _count_meshes(world) > 400)
	_check("junction graph has 25 connected reference nodes", world.traffic_nodes.size() == 25)
	_check("pedestrian paths present", world.ped_lanes.size() >= 20)
	_check("civilian traffic populated", traffic.cars.size() >= 8)
	_check("pedestrians populated", traffic.peds.size() >= 20)
	_check("gameplay camera belongs to player", player.camera.current)
	_check("mission publishes initial objective", mission.stage == Mission.Stage.TO_PACKAGE and not mission.current_objective().is_empty())
	_check("mission registered for save and checkpoint restoration", mission.is_in_group("mission"))
	_check("package is a real interactable", mission.package_node.is_in_group("interactables"))
	_check("road graph includes the fifth row", traffic._neighbours(24).size() == 2 and 19 in traffic._neighbours(24) and 23 in traffic._neighbours(24))
	var lane_target := traffic._lane_point(Vector3.ZERO, Vector3(160.0, 0.0, 0.0))
	_check("traffic target is near destination on the left lane", is_equal_approx(lane_target.x, 152.0) and lane_target.z < 0.0)
	var saved_signal_clock := traffic._signal_clock
	traffic._signal_clock = 6.0
	_check("east-west signal excludes north-south movement", traffic.signal_allows(Vector3.RIGHT) and not traffic.signal_allows(Vector3.FORWARD))
	traffic._signal_clock = 13.0
	_check("junction changeover clears both approaches", not traffic.signal_allows(Vector3.RIGHT) and not traffic.signal_allows(Vector3.FORWARD))
	traffic._signal_clock = 20.0
	_check("north-south signal excludes east-west movement", traffic.signal_allows(Vector3.FORWARD) and not traffic.signal_allows(Vector3.RIGHT))
	traffic._signal_clock = saved_signal_clock
	var mouse_events := InputMap.action_get_events("fire")
	_check("fire maps to a mouse button rather than a keyboard code", not mouse_events.is_empty() and mouse_events[0] is InputEventMouseButton)
	var ammunition_before := Game.current_mag()
	var mouse_press := InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = true
	Input.parse_input_event(mouse_press)
	Input.flush_buffered_events()
	print("DIAGNOSTIC fire action held=%s paused=%s mag=%d event_matches=%s" % [Input.is_action_pressed("fire"), Game.simulation_paused, Game.current_mag(), mouse_press.is_action("fire")])
	await _ticks(3)
	mouse_press = InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = false
	Input.parse_input_event(mouse_press)
	await _ticks(3)
	_check("real mouse-button event fires the equipped weapon", Game.current_mag() == ammunition_before - 1, "mag %d -> %d" % [ammunition_before, Game.current_mag()])

	var road_ray := PhysicsRayQueryParameters3D.create(Vector3(-160.0, 1.0, 95.0), Vector3(-160.0, 1.0, 120.0))
	road_ray.collision_mask = 1
	var road_hit := player.get_world_3d().direct_space_state.intersect_ray(road_ray)
	_check("mission avenue has no static trunk obstruction", road_hit.is_empty())

	# Isolate control probes on open road. These are disclosed fixture moves.
	var car := traffic.cars[0] as Car
	car.has_ai = false
	car.global_position = Vector3(0.0, 0.3, -300.0)
	car.rotation = Vector3.ZERO
	car.velocity = Vector3.ZERO
	player.respawn_at(car.global_position + Vector3(1.9, 0.4, 0.0), 0.0)
	await _ticks(3)
	await _tap("interact")
	_check("input interaction enters a car", Game.mode == Game.MODE_CAR and player.current_vehicle == car)
	_check("occupied player collision is disabled", player.collision_layer == 0 and player.collision_mask == 0)
	var car_start := car.global_position
	Input.action_press("move_forward")
	await _ticks(50)
	Input.action_release("move_forward")
	_check("driving input moves the car", car.global_position.distance_to(car_start) > 2.0)
	_check("occupant follows the moving car", player.global_position.distance_to(car.global_position) < 1.0)
	_check("authoritative position follows controlled vehicle", Game.player_position.distance_to(car.global_position) < 1.0)
	var nose_before := -car.global_transform.basis.z
	Input.action_press("move_forward")
	Input.action_press("move_left")
	await _ticks(20)
	Input.action_release("move_forward")
	Input.action_release("move_left")
	_check("left driving input turns left", (-car.global_transform.basis.z).x < nose_before.x - 0.05)

	# Incoming weapon rays must hit the car body rather than its hidden occupant.
	car._forward = 0.0
	car.velocity = Vector3.ZERO
	var shooter := NPC.new()
	shooter.is_police = true
	main.add_child(shooter)
	shooter.global_position = car.global_position + Vector3(7.0, 0.0, 0.0)
	shooter.state = NPC.State.IDLE
	shooter.idle_time = 100.0
	await _ticks(3)
	var car_health := car.health
	var occupant_health := Game.health
	shooter._shoot_at(player)
	_check("NPC weapon ray damages occupied car", car.health < car_health, "%.2f -> %.2f" % [car_health, car.health])
	_check("car body protects its occupant from that ray", is_equal_approx(Game.health, occupant_health))
	shooter.queue_free()
	await _tap("interact")
	_check("normal exit returns control and camera", Game.mode == Game.MODE_FOOT and player.current_vehicle == null and player.camera.current)
	await _ticks(2)
	_check("on-foot collision restored", player.collision_layer == 2 and player.collision_mask != 0)

	car.interact(player)
	await _ticks(2)
	var deaths_before := Game.death_count
	Game.damage_player(Game.MAX_HEALTH)
	await _ticks(2)
	_check("death is counted for honest golden-path evidence", Game.death_count == deaths_before + 1)
	_check("death in car releases both control owners", not car.driver_is_player and player.current_vehicle == null and Game.mode == Game.MODE_FOOT)
	_check("death restores visible player and gameplay camera", player.visible and player.camera.current and is_equal_approx(Game.health, Game.MAX_HEALTH))
	player.global_position = Vector3(160.0, 0.4, -300.0)
	player.yaw = 0.0
	var walk_start := player.global_position
	Input.action_press("move_forward")
	await _ticks(45)
	Input.action_release("move_forward")
	_check("walking still works after vehicle death", player.global_position.distance_to(walk_start) > 1.0)

	Game.wanted_heat = 46.0
	Game.set_wanted(2)
	Game.decay_heat(20.0)
	_check("wanted escalation decays when unobserved", Game.wanted_level == 0)
	Game.health = 40.0
	Game._since_damage = Game.REGEN_DELAY
	Game._regenerate(1.0)
	_check("health regenerates out of fire", Game.health > 40.0)
	Game.health = Game.MAX_HEALTH

	# Aircraft controls: lift, neutral hover, pause, landing and safe exit.
	player.respawn_at(heli.global_position + Vector3(3.0, 0.5, 0.0), 0.0)
	heli.interact(player)
	await _ticks(2)
	_check("helicopter control is exclusive", Game.mode == Game.MODE_HELI and player.current_vehicle == heli and heli.pilot_is_player)
	Input.action_press("jump")
	await _ticks(90)
	Input.action_release("jump")
	_check("lift input gains altitude", heli.global_position.y > 6.0)
	await _ticks(45)
	_check("neutral lift stabilizes hover", absf(heli.velocity.y) < 0.5)
	heli.exit_vehicle(player)
	_check("airborne helicopter rejects exit", player.current_vehicle == heli)
	Game.simulation_paused = true
	var paused_heli_position := heli.global_position
	var paused_heat := Game.wanted_heat
	await _ticks(10)
	_check("pause freezes aircraft", heli.global_position.distance_to(paused_heli_position) < 0.001)
	_check("pause freezes pursuit heat", is_equal_approx(Game.wanted_heat, paused_heat))
	Game.simulation_paused = false
	Input.action_press("sprint")
	for landing_tick in 360:
		await _ticks(1)
		if heli.is_landed():
			break
	Input.action_release("sprint")
	await _ticks(20)
	_check("controlled descent lands without disabling aircraft", heli.is_landed() and not heli.disabled, "position=%s velocity=%s health=%.1f floor=%s" % [heli.global_position, heli.velocity, heli.health, heli.is_on_floor()])
	heli.exit_vehicle(player)
	_check("landed helicopter exits to walking", player.current_vehicle == null and Game.mode == Game.MODE_FOOT)

	# Mission gates prevent the exact wave-one death/on-foot drive bypass.
	mission.restart()
	await _ticks(2)
	player.global_position = mission.package_node.global_position + Vector3(1.0, 0.3, 0.0)
	await _ticks(2)
	await _tap("interact")
	_check("package input pickup advances and hides pickup", mission.stage == Mission.Stage.TO_CAR and mission.package_taken and not mission.package_node.visible)
	car.interact(player)
	await _ticks(2)
	_check("taking car starts the authored driving leg", mission.stage == Mission.Stage.TO_AIRFIELD)
	player.respawn_at(world.locations["helipad_primary"] + Vector3(4.0, 0.6, 0.0), 0.0)
	await _ticks(3)
	_check("on-foot arrival cannot bypass driving leg", mission.stage == Mission.Stage.TO_AIRFIELD)
	Game.respawn()
	await _ticks(2)
	_check("death restores package checkpoint and requires new drive", mission.stage == Mission.Stage.TO_CAR and mission.package_taken and not mission.car_taken)
	mission.restore_stage(Mission.Stage.TO_HELI)
	_check("restoration rebuilds flags and objective", mission.car_taken and mission.current_objective().contains("helicopter") and not mission.package_node.visible)
	mission.restore_stage(Mission.Stage.DELIVER)
	player.global_position = world.locations["safe_room"]
	mission.delivery_completed()
	_check("delivery cannot be triggered remotely", mission.stage == Mission.Stage.DELIVER)
	mission.restart()
	await _ticks(3)
	_check("restart resets pickup checkpoint and prerequisites", mission.stage == Mission.Stage.TO_PACKAGE and mission.package_node.visible and not mission.package_taken and not mission.car_taken and not mission.landed and Game.checkpoint_index == 0)
	_check("restart retains exactly three mission guards", mission._hostiles.size() == 3 and mission.get_child_count() == 5)

	# Save checks use a dedicated fixture path, never the owner's manual save.
	Game.health = 55.0
	mission.restore_stage(Mission.Stage.TO_HELI)
	Game.checkpoint_index = 2
	Game.mark_safe_position(world.locations["helipad_primary"] + Vector3(3.6, 0.6, 0.0), 0.0)
	var saved := Game.save_game(TEST_SAVE)
	Game.health = 100.0
	mission.restart()
	var loaded := Game.load_game(TEST_SAVE)
	_check("save roundtrip restores health and mission checkpoint", saved and loaded and is_equal_approx(Game.health, 55.0) and mission.stage == Mission.Stage.TO_HELI)
	_check("save restoration updates package and objective", not mission.package_node.visible and mission.car_taken and mission.current_objective().contains("helicopter"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	_report()

func _ticks(count: int) -> void:
	for tick in count:
		await get_tree().physics_frame

func _tap(action: String) -> void:
	Input.action_press(action)
	await _ticks(3)
	Input.action_release(action)
	await _ticks(3)

func _check(check_name: String, condition: bool, detail: String = "") -> void:
	if _reported:
		return
	if not condition:
		failures += 1
	results.append({"name": check_name, "passed": condition, "detail": detail})
	print("%s %s %s" % ["PASS" if condition else "FAIL", check_name, detail])

func _count_meshes(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			count += 1
		count += _count_meshes(child)
	return count

func _watchdog() -> void:
	if _reported:
		return
	_check("suite finished before watchdog deadline", false, "40-second in-engine watchdog expired")
	_report(true)

func _report(timed_out: bool = false) -> void:
	if _reported:
		return
	_reported = true
	if _watchdog_timer:
		_watchdog_timer.stop()
	for action in InputMap.get_actions():
		Input.action_release(action)
	var data := {
		"suite": "wave2-regressions", "engine": Engine.get_version_info()["string"],
		"finished_utc": Time.get_datetime_string_from_system(true),
		"duration_ms": Time.get_ticks_msec() - _started_ms, "timed_out": timed_out,
		"total": results.size(), "passed": results.size() - failures, "failed": failures,
		"fixture_repositioning": true, "golden_path": false, "checks": results,
	}
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var output := FileAccess.open(_report_path, FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(data, "\t"))
		output.close()
	else:
		failures += 1
		push_error("Unable to write test report: " + _report_path)
	print("%d/%d checks passed, %d failed; report=%s" % [results.size() - failures, results.size(), failures, _report_path])
	finished.emit(failures)
	get_tree().quit(124 if timed_out else (1 if failures > 0 else 0))
