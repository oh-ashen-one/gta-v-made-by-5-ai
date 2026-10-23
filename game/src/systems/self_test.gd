class_name SelfTest
extends Node
## Bounded behavioral regression suite. Fixture repositioning is explicit test
## setup; it is never used by the rendered golden-path input driver.

signal finished(failures: int)

const TEST_SAVE := "/tmp/orchard_reach_wave2_fixture_save.json"
## Wave-M integration: downtown + street-life checks took the combined suite
## past 40 s of engine time; this is a hang guard, not a speed budget.
const WATCHDOG_SECONDS := 90.0
var failures := 0
var results: Array[Dictionary] = []
var _started_ms := 0
var _reported := false
var _watchdog_timer: Timer
var _state_restore_events := 0
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
		await _report()
		return
	_check("district contains 3D geometry", _count_meshes(world) > 400)
	_check("weathered surfaces and wall/roof clutter present (wave B materials)", _materials_ok(world), str(SurfaceDressing.stats) + " groups=%d" % world.get_tree().get_nodes_in_group("surface_dressing").size())
	_check("junction graph has 25 connected reference nodes", world.traffic_nodes.size() == 25)
	_check("pedestrian paths present", world.ped_lanes.size() >= 20)
	_check("civilian traffic populated", traffic.cars.size() >= 8)
	_check("pedestrians populated", traffic.peds.size() >= 20)
	_lighting_checks(world)
	var configured_peds := TrafficManager.PED_COUNT + TrafficManager.DINER_COUNT + CrowdDirector.EXTRA_WALKERS + PlazaLife.pool_size()
	var unique_peds: Dictionary = {}
	for pedestrian in traffic.peds:
		if is_instance_valid(pedestrian): unique_peds[pedestrian.get_instance_id()] = true
	_check("ambient population matches configured budget of %d unique actors" % configured_peds, traffic.peds.size() == configured_peds and unique_peds.size() == configured_peds)
	var diners := 0
	var away_from_junction := 0
	for index in traffic.peds.size():
		var pedestrian := traffic.peds[index]
		if pedestrian.has_meta("ambient_role") and pedestrian.has_method("take_damage"):
			diners += 1
		if index < TrafficManager.FOCUSED_PED_COUNT:
			var nearest := INF
			for junction in world.traffic_nodes:
				nearest = minf(nearest, pedestrian.global_position.distance_to(junction))
			if nearest > 14.0: away_from_junction += 1
	_check("market diners are reactive damageable NPCs", diners == TrafficManager.DINER_COUNT)
	_check("busy district walkers spawn along segments not junction piles", away_from_junction >= 34)
	_check("gameplay camera belongs to player", player.camera.current)
	_check("sprint 180 turns continuously (<=25 deg/frame at 30 fps, no facing flip)", Player.SKID_SWING_RATE / 30.0 <= deg_to_rad(25.0) and Player.FACE_MAX_RATE / 30.0 <= deg_to_rad(25.0) and Player.SKID_DECEL * 0.45 >= Player.SPRINT_SPEED - 1.0)
	_check("mission publishes initial objective", mission.stage == Mission.Stage.TO_PACKAGE and not mission.current_objective().is_empty())
	_check("initial objective marker survives HUD setup order", mission.get_meta("marker", Vector3.ZERO).distance_to(world.locations["package"]) < 0.01)
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
	var ew_green: GeometryInstance3D   # MeshInstance3D post lamp or JunctionSignals MultiMesh
	var ns_green: GeometryInstance3D
	for lamp in get_tree().get_nodes_in_group("traffic_lamps"):
		if int(lamp.get_meta("lamp_index", -1)) == 2:
			if int(lamp.get_meta("signal_axis", 0)) == 0: ew_green = lamp
			else: ns_green = lamp
	traffic._signal_clock = 6.0
	traffic._update_signal_lamps(true)
	var ew_material: StandardMaterial3D = ew_green.material_override if ew_green else null
	var ns_material: StandardMaterial3D = ns_green.material_override if ns_green else null
	_check("visible signal lamps agree with east-west right of way", ew_material != null and ns_material != null and ew_material.emission_enabled and not ns_material.emission_enabled)
	traffic._signal_clock = 20.0
	traffic._update_signal_lamps(true)
	ew_material = ew_green.material_override if ew_green else null
	ns_material = ns_green.material_override if ns_green else null
	_check("visible signal lamps switch with north-south right of way", ew_material != null and ns_material != null and not ew_material.emission_enabled and ns_material.emission_enabled)
	traffic._signal_clock = saved_signal_clock
	traffic._update_signal_lamps(true)
	var mouse_events := InputMap.action_get_events("fire")
	_check("fire maps to a mouse button rather than a keyboard code", not mouse_events.is_empty() and mouse_events[0] is InputEventMouseButton)
	var ammunition_before := Game.current_mag()
	var mouse_press := InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = true
	Input.parse_input_event(mouse_press)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame
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

	await _weapon_input_checks(main, player)

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
	# driving-q: chase-cam motion blur is wired and opens with speed; the road
	# keeps 16x anisotropic filtering and a bounded aggregate contrast.
	var mb: CarMotionBlur = car.fx.motion_blur if car.fx != null else null
	var comp: Compositor = car._camera.compositor
	_check("chase camera motion blur opens with speed", mb != null and comp != null and comp.compositor_effects.has(mb) and mb.shutter > 0.05 and car.speed_kmh() > 15.0, "shutter=%.2f speed=%.0f" % [mb.shutter if mb else -1.0, car.speed_kmh()])
	# rQ2: streaks only on near, low geometry (road, kerbs, median) and ungated taps are not gathered, so people/carts never ghost.
	_check("motion blur is gated to near road-level pixels (no ghosted pedestrians)", CarMotionBlur.GLSL.contains("float gate(") and CarMotionBlur.GLSL.contains("smoothstep(6.5, 12.0, z)") and CarMotionBlur.GLSL.contains("smoothstep(0.15, 0.6, gs)") and mb != null and mb.samples >= 20, "samples=%d" % [mb.samples if mb else -1])
	var road_sh := (Palette.road_asphalt() as ShaderMaterial).shader if Palette.road_asphalt() is ShaderMaterial else null
	_check("road filtering and aggregate contrast stay speckle-free", int(ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level")) == 4 and road_sh != null and road_sh.code.contains("0.72, 1.38"))
	# opus55 driving: the sprung body and the trailing chase camera stay wired.
	var car_fx: Node = car.fx
	var lean := Vector2(car_fx.last_roll, car_fx.last_pitch) if car_fx != null else Vector2.ZERO
	_check("car body rolls and pitches under load", car_fx != null and (absf(lean.x) > 0.004 or absf(lean.y) > 0.004), "roll=%.4f pitch=%.4f" % [lean.x, lean.y])
	var chase_gap := car._camera.global_position - car.global_position
	_check("chase camera trails behind the car", car._camera.current and car._camera.top_level and chase_gap.length() > 3.0 and chase_gap.length() < 9.0 and chase_gap.dot(-car.global_transform.basis.z) < 0.0, "gap=%.2f" % chase_gap.length())
	# driving C2: contact shadow under every car; struck cars take the momentum.
	_check("car carries a ground contact shadow", car_fx != null and car_fx.get_node_or_null("ContactShadow") is Decal)
	var shove_probe := Car.new()
	shove_probe.kind = "sedan"
	main.add_child(shove_probe)
	shove_probe.global_position = car.global_position + Vector3(30.0, 0.5, 30.0)
	await _ticks(2)
	var shove_from := shove_probe.global_position
	shove_probe.shove(Vector3(8.0, 0.0, 0.0), shove_from + Vector3(-1.0, 0.0, 0.8))
	await _ticks(20)
	_check("a rammed car is shoved by the impact", shove_probe.global_position.distance_to(shove_from) > 1.0, "moved=%.2f" % shove_probe.global_position.distance_to(shove_from))
	shove_probe.queue_free()
	await _driving_feel_checks(main, car)

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
	await _blocked_exit_checks(main, player, car)

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
	_check("on-foot gait: walk/run/sprint are distinct authored cycles at 0.85-1.2x rate, jump/land/stop clips exist; feet carry contact shadows", _gait_matches_speed(player))
	await _locomotion_q_checks(player)
	var jump_apex: float = pow(Player.JUMP_VELOCITY, 2.0) / (2.0 * 24.0)
	_check("on-foot jump is a human hop (0.40-0.70 m rise, under 0.5 s airtime)", jump_apex > 0.4 and jump_apex < 0.7 and 2.0 * Player.JUMP_VELOCITY / 24.0 < 0.5, "apex=%.2f" % jump_apex)

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
	var heli_fx := heli.presentation_state()
	_check("rotor spools up to a motion-blurred disc in flight", heli_fx["rotor_spin"] > 0.95 and heli_fx["disc_visible"] and not heli_fx["blades_visible"], str(heli_fx))
	_check("flight chase camera trails behind and above the aircraft", heli_fx["camera_current"] and heli_fx["camera_distance"] > 8.0 and heli_fx["camera_distance"] < 26.0 and heli_fx["camera_behind"] and heli_fx["camera_height"] > 1.0, str(heli_fx))
	_check("rotor downwash kicks up the ground near the pad", heli_fx["wash"] > 0.2 and heli_fx["wash_visible"], str(heli_fx))
	_check("chase camera looks down on the rotor disc; aviation grounds are planted (wave P)", heli_fx["camera_height"] > 5.5 and world.find_child("AviationGrounds", true, false) != null, str(heli_fx))
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
	_check("ground cushion settles a full-descent landing gently (wave P)", heli.last_touchdown_speed < 1.6, "touchdown=%.2f m/s" % heli.last_touchdown_speed)
	heli.exit_vehicle(player)
	_check("landed helicopter exits to walking", player.current_vehicle == null and Game.mode == Game.MODE_FOOT)
	await _waterfront_exit_check(player, heli)

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
	Game.settings = {"mouse_sensitivity": 1.7, "invert_y": true, "reduced_shake": true, "hud_visible": false}
	var saved := Game.save_game(TEST_SAVE)
	Game.settings = {"mouse_sensitivity": 1.0, "invert_y": false, "reduced_shake": false, "hud_visible": true}
	Game.health = 100.0
	mission.restart()
	var loaded := Game.load_game(TEST_SAVE)
	_check("save roundtrip restores health and mission checkpoint", saved and loaded and is_equal_approx(Game.health, 55.0) and mission.stage == Mission.Stage.TO_HELI)
	_check("save restoration updates package and objective", not mission.package_node.visible and mission.car_taken and mission.current_objective().contains("helicopter"))
	_check("save restores sensitivity and accessibility settings", is_equal_approx(Game.settings["mouse_sensitivity"], 1.7) and Game.settings["invert_y"] and Game.settings["reduced_shake"] and not Game.settings["hud_visible"])
	var previous_file := FileAccess.get_file_as_string(TEST_SAVE)
	var real_weapon := Game.carried_weapon
	Game.carried_weapon = "invalid_live_weapon"
	var invalid_saved := Game.save_game(TEST_SAVE)
	Game.carried_weapon = real_weapon
	_check("invalid live state cannot replace the last complete save", not invalid_saved and FileAccess.get_file_as_string(TEST_SAVE) == previous_file)
	Game.health = 65.0
	var replaced := Game.save_game(TEST_SAVE)
	Game.health = 100.0
	var reloaded := Game.load_game(TEST_SAVE)
	_check("atomic replacement updates an existing save", replaced and reloaded and is_equal_approx(Game.health, 65.0))
	_check("successful save leaves no temporary checkpoint file", not FileAccess.file_exists(TEST_SAVE + ".tmp-%d" % OS.get_process_id()))
	Events.state_restored.connect(func(): _state_restore_events += 1)
	Game.switch_weapon("smg")
	player._update_weapon_mesh()
	var smg_saved := Game.save_game(TEST_SAVE)
	Game.switch_weapon("pistol")
	player._update_weapon_mesh()
	player._reloading = true
	player._reload_timer = 1.0
	player._fire_cooldown = 0.8
	player._press_queue["fire"] = true
	var smg_loaded := Game.load_game(TEST_SAVE)
	_check("successful load publishes one state-restored event", smg_saved and smg_loaded and _state_restore_events == 1)
	_check("saved SMG restores held model and clears transient actions", Game.carried_weapon == "smg" and player._weapon_model != null and String(player._weapon_model.scene_file_path).contains("smg") and not player._reloading and player._fire_cooldown == 0.0 and player._press_queue.is_empty())
	_negative_save_checks(player, mission)
	await _wave5_checks(world, traffic, heli)
	await _street_life_checks(player, traffic)
	await _water_checks(world)
	await _downtown_plan_checks(world)
	_character_look_checks(player)
	for c in load("res://src/systems/perf_checks.gd").run(main):   # wave S performance piece
		_check(c[0], c[1], c[2])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	await _report()

func _waterfront_exit_check(player: Player, heli: Helicopter) -> void:
	# Reproduce the actual route4 landing pose where the pilot could exit but
	# could not subsequently walk. This is an explicit regression fixture.
	heli.force_exit()
	heli.global_position = Vector3(0.401198, 0.000189, -329.576294)
	heli.rotation = Vector3(0.0, 0.743854, 0.0)
	heli.velocity = Vector3.ZERO
	player.respawn_at(heli.global_position + heli.global_transform.basis.x * 3.0 + Vector3.UP * 0.5, 0.0)
	await _ticks(5)
	heli.interact(player)
	await _ticks(3)
	await _tap("interact")
	var start := player.global_position
	player.set_meta("_qa_motion_probe", true)
	player.yaw = -PI * 0.5
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _ticks(60)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var moved := player.global_position.distance_to(start)
	_check("waterfront helicopter exit permits actual on-foot movement", Game.mode == Game.MODE_FOOT and moved > 3.0, "moved=%.3f from=%s to=%s velocity=%s" % [moved, start, player.global_position, player.velocity])
	if moved <= 3.0:
		print("EXIT_MOTION_STATE ", player.get_meta("_qa_motion_state"))
		print("EXIT_HELI_STATE pos=%s rotation=%s pilot=%s" % [heli.global_position, heli.rotation, heli.pilot_is_player])
		for index in player.get_slide_collision_count():
			var contact := player.get_slide_collision(index)
			var body: CollisionObject3D = contact.get_collider()
			var shape: Node3D = body.shape_owner_get_owner(body.shape_find_owner(contact.get_collider_shape_index()))
			print("EXIT_DIAGNOSTIC body=%s shape=%s position=%s normal=%s" % [body.name, shape.name, shape.global_position, contact.get_normal()])
		var old_margin := player.safe_margin
		var old_stop := player.floor_stop_on_slope
		for probe in ["margin", "floor_stop", "both"]:
			player.safe_margin = 0.03 if probe != "floor_stop" else old_margin
			player.floor_stop_on_slope = false if probe != "margin" else old_stop
			player.global_position = start + Vector3.UP * 0.1
			player.velocity = Vector3.ZERO
			await _ticks(15)
			var probe_start := player.global_position
			Input.action_press("move_forward")
			Input.action_press("sprint")
			await _ticks(60)
			Input.action_release("move_forward")
			Input.action_release("sprint")
			print("EXIT_PROPERTY_PROBE setting=%s moved=%.3f pos=%s floor=%s wall=%s ceiling=%s" % [probe, player.global_position.distance_to(probe_start), player.global_position, player.is_on_floor(), player.is_on_wall(), player.is_on_ceiling()])
		player.safe_margin = old_margin
		player.floor_stop_on_slope = old_stop
		var old_heli_layer := heli.collision_layer
		var old_heli_mask := heli.collision_mask
		heli.collision_layer = 0
		heli.collision_mask = 0
		player.global_position = start + Vector3.UP * 0.1
		player.velocity = Vector3.ZERO
		await _ticks(15)
		var no_vehicle_start := player.global_position
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await _ticks(60)
		Input.action_release("move_forward")
		Input.action_release("sprint")
		print("EXIT_COLLISION_PROBE no_helicopter moved=%.3f pos=%s state=%s" % [player.global_position.distance_to(no_vehicle_start), player.global_position, player.get_meta("_qa_motion_state")])
		heli.collision_layer = old_heli_layer
		heli.collision_mask = old_heli_mask
	player.remove_meta("_qa_motion_probe")

func _blocked_exit_checks(main: Node, player: Player, car: Car) -> void:
	car.interact(player)
	await _ticks(2)
	var enclosure := StaticBody3D.new()
	enclosure.collision_layer = 1
	enclosure.collision_mask = 0
	main.add_child(enclosure)
	enclosure.global_transform = car.global_transform
	var walls := [
		[Vector3(1.45, 1.8, 0.0), Vector3(0.35, 4.0, 6.0)],
		[Vector3(-1.45, 1.8, 0.0), Vector3(0.35, 4.0, 6.0)],
		[Vector3(0.0, 1.8, 2.75), Vector3(3.2, 4.0, 0.35)],
		[Vector3(0.0, 1.8, -2.75), Vector3(3.2, 4.0, 0.35)],
	]
	for specification in walls:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = specification[1]
		shape.shape = box
		shape.position = specification[0]
		enclosure.add_child(shape)
	await _ticks(3)
	await _tap("interact")
	_check("blocked car exit preserves seated control without wall clipping", Game.mode == Game.MODE_CAR and player.current_vehicle == car and car.driver_is_player)
	enclosure.queue_free()
	await _ticks(3)
	await _tap("interact")
	_check("clearing blocked exit restores normal exit", Game.mode == Game.MODE_FOOT and player.current_vehicle == null and not car.driver_is_player)

func _state_fingerprint(player: Player, mission: Mission) -> Dictionary:
	return {"health": Game.health, "wanted_level": Game.wanted_level, "wanted_heat": Game.wanted_heat,
		"mission_stage": Game.mission_stage, "checkpoint": Game.checkpoint_index, "seed": Game.seed_value,
		"elapsed": Game.elapsed_seconds, "position": Game.player_position, "rotation": Game.player_rotation,
		"weapon": Game.carried_weapon, "ammo": Game.ammo.duplicate(true), "mode": Game.mode,
		"safe_position": Game.last_safe_position, "safe_rotation": Game.last_safe_rotation,
		"actor_position": player.global_position, "actor_yaw": player.yaw, "settings": Game.settings.duplicate(true), "state_restore_events": _state_restore_events,
		"scene_stage": mission.stage, "objective": mission.current_objective(), "package_visible": mission.package_node.visible}

func _negative_save_checks(player: Player, mission: Mission) -> void:
	Game.save_game(TEST_SAVE)
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	var cases: Array[Dictionary] = []
	var bad := valid.duplicate(true)
	bad["player_position"] = [1.0, 2.0]
	cases.append({"name": "truncated position vector", "data": bad})
	bad = valid.duplicate(true)
	bad["carried_weapon"] = "unknown_weapon"
	cases.append({"name": "unknown equipped weapon", "data": bad})
	bad = valid.duplicate(true)
	bad["ammo"]["pistol"]["mag"] = 400
	cases.append({"name": "out-of-range magazine", "data": bad})
	bad = valid.duplicate(true)
	bad["health"] = "healthy"
	cases.append({"name": "wrong health type", "data": bad})
	bad = valid.duplicate(true)
	bad["checkpoint_index"] = 99
	cases.append({"name": "invalid checkpoint index", "data": bad})
	bad = valid.duplicate(true)
	bad["wanted_level"] = 3
	bad["wanted_heat"] = 0.0
	cases.append({"name": "inconsistent pursuit state", "data": bad})
	bad = valid.duplicate(true)
	bad["last_safe_position"] = {"x": 0, "y": 0, "z": 0}
	cases.append({"name": "wrong safe-position type", "data": bad})
	bad = valid.duplicate(true)
	bad["settings"]["mouse_sensitivity"] = 100.0
	cases.append({"name": "out-of-range mouse sensitivity", "data": bad})
	bad = valid.duplicate(true)
	bad["settings"]["invert_y"] = "true"
	cases.append({"name": "wrong accessibility-setting type", "data": bad})
	var before := _state_fingerprint(player, mission)
	for test_case in cases:
		var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
		file.store_string(JSON.stringify(test_case["data"]))
		file.close()
		var accepted := Game.load_game(TEST_SAVE)
		_check("save rejects %s atomically" % test_case["name"], not accepted and _state_fingerprint(player, mission) == before)

func _weapon_input_checks(main: Node, player: Player) -> void:
	# Both mouse transitions occur before the next process frame. A queued
	# native press must survive even though the held state is already false.
	await _ticks(15)
	var before := Game.current_mag()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame
	await _ticks(2)
	_check("rapid native press and release is not dropped", Game.current_mag() == before - 1)

	# A disclosed floating test bay isolates the close-cover geometry from
	# changing district props/traffic. This bay exists only in --test.
	var bay := StaticBody3D.new()
	bay.collision_layer = 1
	bay.collision_mask = 0
	main.add_child(bay)
	bay.global_position = Vector3(0.0, 20.0, -246.0)
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.4, 40.0)
	floor_shape.shape = box
	bay.add_child(floor_shape)
	player.respawn_at(Vector3(0.0, 20.35, -240.0), 0.0)
	var target := NPC.new()
	main.add_child(target)
	target.global_position = Vector3(0.0, 20.35, -252.0)
	target.state = NPC.State.IDLE
	target.idle_time = 100.0
	Input.action_press("aim")
	for frame in 20:
		await _ticks(1)
		var aim_vector := target.global_position + Vector3.UP * 1.15 - player.camera.global_position
		player.yaw = atan2(-aim_vector.x, -aim_vector.z)
		player.pitch = atan2(aim_vector.y, Vector2(aim_vector.x, aim_vector.z).length())
	var aim_point := target.global_position + Vector3.UP * 1.15
	# Freeze the character animation for this fixture only. The cover is placed
	# relative to the muzzle and then several frames elapse before the shot;
	# with a heavier district those frames are longer and the aim pose drifted
	# far enough to move the muzzle off the 0.18 m cover between measurement and
	# fire. Freezing isolates the geometry under test without weakening it.
	if player._visual != null:
		player._visual.set_paused(true)
	var muzzle := player._muzzle_flash.global_position
	if player._visual != null and player._visual.loaded:
		muzzle = player._visual.weapon_muzzle_position()
	var cover := StaticBody3D.new()
	cover.collision_layer = 1
	cover.collision_mask = 0
	main.add_child(cover)
	cover.global_position = muzzle + (aim_point - muzzle).normalized() * 1.0
	var cover_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	cover_shape.shape = sphere
	cover.add_child(cover_shape)
	await _ticks(3)
	var camera_ray := PhysicsRayQueryParameters3D.create(player.camera.global_position, aim_point)
	camera_ray.collision_mask = 1 | 4
	camera_ray.exclude = [player.get_rid()]
	var camera_hit := player.get_world_3d().direct_space_state.intersect_ray(camera_ray)
	_check("close-cover fixture leaves camera sightline on target", not camera_hit.is_empty() and camera_hit["collider"] == target)
	var target_health := target.health
	await _tap("fire")
	_check("muzzle obstruction prevents damage through close cover", is_equal_approx(target.health, target_health))
	cover.queue_free()
	# The first (blocked) shot panics the target; since street-life M2 a
	# civilian flees on a randomised heading, so it would leave the aim line.
	# Hold it on its mark and keep the aim on it: this fixture tests the
	# muzzle obstruction, not tracking a runner.
	var target_mark := Vector3(0.0, 20.35, -252.0)
	for frame in 15:
		target.state = NPC.State.IDLE
		target.idle_time = 100.0
		target.velocity = Vector3.ZERO
		target.global_position = target_mark
		await _ticks(1)
		var re_aim := target.global_position + Vector3.UP * 1.15 - player.camera.global_position
		player.yaw = atan2(-re_aim.x, -re_aim.z)
		player.pitch = atan2(re_aim.y, Vector2(re_aim.x, re_aim.z).length())
	var fx_before: Dictionary = CombatFx.stats.duplicate()
	await _tap("fire")
	_check("clearing muzzle obstruction permits target damage", target.health < target_health)
	await _combat_fx_checks(player, fx_before)
	if player._visual != null:
		player._visual.set_paused(false)
	Input.action_release("aim")
	target.queue_free()
	bay.queue_free()
	player.respawn_at(Game.last_safe_position, Game.last_safe_rotation)
	player.pitch = -0.12
	Game.wanted_heat = 0.0
	Game.set_wanted(0)
	await _ticks(3)

## Combat piece: every shot shows a muzzle flash, tracer, impact and brass,
## a hit target staggers, recoil recovers, and sustained fire stays bounded.
func _combat_fx_checks(player: Player, before: Dictionary) -> void:
	var st: Dictionary = CombatFx.stats
	_check("shot produced muzzle flash, tracer, impact and ejected casing", st["muzzle"] > before["muzzle"] and st["tracer"] > before["tracer"] and st["impact"] > before["impact"] and st["casing"] > before["casing"], str(st))
	_check("struck NPC staggers and flinches", st["flinch"] > before["flinch"])
	var combat := player.get_node_or_null("PlayerCombat")
	_check("player recoil layer present and kicked by the shot", combat != null and (absf(combat.cam_kick) > 0.0005 or absf(combat.cam_kick_v) > 0.01))
	await _ticks(24)
	_check("recoil recovers within ~0.4 s", combat != null and absf(combat.cam_kick) < 0.003 and absf(combat.gun_kick) < 0.05, "cam=%.4f gun=%.3f" % [combat.cam_kick if combat else -1.0, combat.gun_kick if combat else -1.0])
	var fx := CombatFx.get_fx(get_tree())
	for i in 150:
		fx.shot(player.global_position + Vector3(0, 1.4, 0), Vector3.FORWARD, player.global_position + Vector3(0, 1.4, -12.0), true, Vector3.BACK, null, "pistol", true)
	var live: Dictionary = fx.live_counts()
	var bounded := true
	for kind in CombatFx.MAX_PARTICLES:
		if int(live[kind]) > int(CombatFx.MAX_PARTICLES[kind]): bounded = false
	_check("sustained fire keeps effect pools bounded", bounded and int(live["casings"]) <= CombatFx.MAX_CASINGS, str(live))
	await _combat_q_checks(player)

## Wave Q combat: the aimed pistol sits at shoulder height (integ-Q: arms
## extended under the sight line, readable from the OTS camera) with
## the barrel on the aim, interaction prompts are hidden mid-firefight, and a
## lethal hit hands the body to a ragdoll that comes to rest on the ground.
func _combat_q_checks(player: Player) -> void:
	var visual: Node = player._visual
	var layer: Node = null
	if visual != null and visual.get("skeleton") != null:
		layer = (visual.get("skeleton") as Node).get_node_or_null("AimIkLayer")
	var gun: Node3D = player.get("_weapon_model")
	await _ticks(6)
	var ok_gun := false
	var detail := "no layer/gun"
	if layer != null and gun != null and is_instance_valid(gun):
		var aim_dir := Basis.from_euler(Vector3(player.pitch, player.yaw, 0.0)) * Vector3.FORWARD
		var barrel := -gun.global_basis.z
		var h := gun.global_position.y - player.global_position.y
		ok_gun = float(layer.get("weight")) > 0.9 and h > 1.28 and h < 1.55 and barrel.normalized().dot(aim_dir.normalized()) > 0.96
		detail = "weight=%.2f gun_h=%.2f barrel_dot=%.3f" % [float(layer.get("weight")), h, barrel.normalized().dot(aim_dir.normalized())]
	_check("aim layer holds the pistol at shoulder height along the aim", ok_gun, detail)
	CombatFx.mark_combat()
	var prompts: Array[String] = []
	var grab := func(text: String) -> void: prompts.append(text)
	Events.interaction_prompt.connect(grab)
	await _ticks(2)
	Events.interaction_prompt.disconnect(grab)
	_check("no interaction prompt during a firefight", CombatFx.in_combat() and not prompts.is_empty() and prompts.all(func(t): return t == ""), str(prompts.slice(0, 3)))
	var victim := NPC.new()
	victim.is_police = true
	player.get_parent().add_child(victim)
	victim.global_position = player.global_position + Vector3(2.5, 0.0, -3.5)
	victim.state = NPC.State.IDLE
	victim.idle_time = 100.0
	await _ticks(10)
	var before_rag := Ragdoll.started
	victim.take_damage(500.0, player.global_position, true)
	await _ticks(150)
	var pb: Node3D = null
	if victim.character_visual != null and victim.character_visual.skeleton != null:
		pb = victim.character_visual.skeleton.get_node_or_null("Ragdoll/PB_pelvis") as Node3D
	var rest_h := pb.global_position.y - victim.global_position.y if pb != null else 99.0
	var drift := Vector2(pb.global_position.x - victim.global_position.x, pb.global_position.z - victim.global_position.z).length() if pb != null else 99.0
	# The pelvis ends on the ground (ragdoll ~0.1 m; the guarded fallback to the
	# authored fall pose ~0.36 m), never under the floor or flung away.
	_check("lethal hit ragdolls the body; it ends on the ground, never under it or flung", Ragdoll.started > before_rag and pb != null and rest_h > -0.05 and rest_h < 0.42 and drift < 3.0, "pelvis_h=%.2f drift=%.2f guard=%s" % [rest_h, drift, Ragdoll.last_blowup])
	victim.queue_free()

## Wave-5 additions: kerbside parking geometry, parked-car sleep, road-graph
## pursuit, aircraft ditch recovery, landmark set and the outdoor opening.
func _wave5_checks(world: WorldBuilder, traffic: TrafficManager, heli: Helicopter) -> void:
	var kerbside := 0
	var on_carriageway := 0
	for spot in world.parked_spots:
		if bool(spot.get("courtyard_only", false)): continue
		kerbside += 1
		var p: Vector3 = spot["pos"]
		var lateral := INF
		for x in WorldBuilder.X_LINES: lateral = minf(lateral, absf(p.x - x))
		for z in WorldBuilder.Z_LINES: lateral = minf(lateral, absf(p.z - z))
		if lateral + 1.05 <= WorldBuilder.ROAD_HALF: on_carriageway += 1
	_check("kerbside parked cars sit wholly on the carriageway", kerbside > 0 and on_carriageway == kerbside, "%d/%d" % [on_carriageway, kerbside])
	# Drivability of every kerbside car as parked: its own hull can pull out
	# toward the traffic lane and travel 12 m without striking anything.
	var drivable := 0
	var probed := 0
	var blocked_at: Array[String] = []
	# Static layout check: moving lane traffic is not a parking obstruction.
	var lane_traffic: Array = get_tree().get_nodes_in_group("ambient_vehicles")
	for body in lane_traffic: (body as CollisionObject3D).collision_layer = 0
	for v in get_tree().get_nodes_in_group("vehicles"):
		if not v is Car or v.has_ai or v.driver_is_player or not v.visible or v.get_meta("courtyard_only", false): continue
		var car_body := v as Car
		probed += 1
		var forward := -car_body.global_transform.basis.z
		var to_lane := Vector3.UP.cross(forward).normalized() * -1.0   # right of travel = toward road centre (left-hand traffic)
		var lifted := car_body.global_transform.translated(Vector3.UP * 0.05)
		var pull_out := forward * 6.0 + to_lane * 1.6
		if not car_body.test_move(lifted, pull_out) and not car_body.test_move(lifted.translated(pull_out), forward * 6.0):
			drivable += 1
		elif blocked_at.size() < 6:
			blocked_at.append(str(car_body.global_position.round()))
	_check("kerbside parked cars can pull out and drive 12 m unobstructed", probed > 0 and drivable >= int(probed * 0.9), "%d/%d blocked=%s" % [drivable, probed, blocked_at])
	for body in lane_traffic: if (body as AmbientVehicle).active: (body as CollisionObject3D).collision_layer = 8
	var sleeping := 0
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v is Car and not v.has_ai and not v.driver_is_player and v.visible and not v.is_physics_processing():
			sleeping += 1
	_check("settled parked cars stop ticking until taken", sleeping >= 20, "%d asleep" % sleeping)
	var chaser := Car.new()
	chaser.kind = "police"
	traffic.add_child(chaser)
	chaser.global_position = Vector3(-160.0, 0.3, -100.0)
	var goal := Vector3(0.0, 0.3, -60.0)
	var waypoint := traffic._pursuit_waypoint(chaser, goal)
	var on_graph := false
	for node in world.traffic_nodes:
		if Vector2(node.x - waypoint.x, node.z - waypoint.z).length() < 0.5: on_graph = true
	_check("police pursuit routes along junctions around a block", on_graph and waypoint.distance_to(goal) > 20.0, str(waypoint))
	# Leaving a junction must not flip the target back to it (critic finding).
	chaser.set_meta("pursuit_wp", -1)
	chaser.global_position = Vector3(-160.0, 0.3, -166.0)
	var first := traffic._pursuit_waypoint(chaser, goal)
	chaser.global_position = Vector3(-160.0, 0.3, -146.0)
	var second := traffic._pursuit_waypoint(chaser, goal)
	_check("pursuit commits to its next junction after leaving one", first.distance_to(second) < 0.5 and Vector2(first.x + 160.0, first.z + 166.0).length() > 30.0, "%s then %s" % [first, second])
	# At the goal's own junction the responder runs down the road toward a
	# mid-block goal instead of parking (critic pass 2).
	chaser.set_meta("pursuit_wp", -1)
	chaser.global_position = Vector3(-160.0, 0.3, 4.0)
	var mid_block := Vector3(-160.0, 0.3, -62.0)
	var closing := traffic._pursuit_waypoint(chaser, mid_block)
	_check("pursuit closes on a mid-block goal from its junction", Vector2(closing.x - mid_block.x, closing.z - mid_block.z).length() < 1.0, str(closing))
	chaser.queue_free()
	var parked_at := heli.global_position
	heli.global_position = Vector3(0.0, -6.0, -500.0)
	heli.velocity = Vector3.ZERO
	await _ticks(2)
	_check("ditched aircraft is recovered above its last supported position", heli.global_position.y > -1.0, str(heli.global_position))
	heli.global_position = parked_at
	heli.velocity = Vector3.ZERO
	await _ticks(2)
	# A carjacked driver flees away from the car and then rejoins a pavement
	# lane instead of standing frozen in the carriageway (wave 5 soak finding).
	# Disclosed fixture: borrow a live civilian (creating/freeing an actor here
	# trips the dummy renderer's known material-null diagnostic), then restore it.
	var victim: NPC = null
	for candidate in traffic.peds:
		if is_instance_valid(candidate) and not candidate.is_police and not candidate.is_hostile and candidate.state != NPC.State.DEAD and not candidate.has_meta("ambient_role"):
			victim = candidate
			break
	if victim == null:
		_check("carjacked driver flees from the car and rejoins a pavement lane", false, "no civilian available")
		return
	var restore := {"pos": victim.global_position, "lane": victim.lane, "index": victim.lane_index, "dir": victim.lane_dir, "state": victim.state, "health": victim.health}
	victim.become_displaced_pedestrian(Vector3(-155.0, 0.3, -116.0), Vector3(-153.4, 0.3, -118.0))
	var fled_away := victim._flee_dir.dot((Vector3(-155.0, 0.3, -116.0) - Vector3(-153.4, 0.3, -118.0)).normalized()) > 0.9
	victim._adopt_nearest_lane()
	_check("carjacked driver flees from the car and rejoins a pavement lane", fled_away and victim.lane.size() >= 2, "lane points %d" % victim.lane.size())
	victim.global_position = restore["pos"]
	victim.lane = restore["lane"]
	victim.lane_index = restore["index"]
	victim.lane_dir = restore["dir"]
	victim.state = restore["state"]
	victim.health = restore["health"]
	var placed := true
	for key in ["marina_bay_sands", "supertree_grove", "artscience_museum", "singapore_flyer", "merlion"]:
		placed = placed and world.locations.has(key)
	_check("all five required Singapore landmarks are placed", placed)
	_skyline_checks(world)
	_check("run opens outdoors on the heritage street, not inside the safe room", world.locations["player_start"].distance_to(world.locations["safe_room"]) > 40.0)
	var audio := Sfx.loop_metrics()
	var seam_ok := true
	var clip_ok := true
	for key in audio:
		var row: Dictionary = audio[key]
		if row["looped"] and row["seam_step"] > maxf(0.06, row["max_interior_step"] * 1.05): seam_ok = false
		if row["peak"] > 0.995: clip_ok = false
	_check("synthesized loops have continuous seams (objective, not listening)", seam_ok and audio.size() >= 5, str(audio))
	_check("synthesized sounds stay below full-scale clipping", clip_ok)

## Skyline piece (wave A, Opus 5.5): landmark footprints stay apart, the Flyer
## sits inside the fixed photo_06 aerial frame, roofs are dressed and the
## layered background city and landmark material upgrades are present.
func _skyline_checks(world: WorldBuilder) -> void:
	var mbs: Vector3 = world.locations["marina_bay_sands"]
	# Wave M (downtown-landmarks): mirrored true-scale footprint, SkyPark
	# cantilever north (-x) to the podium on the bay side (+z).
	var mbs_rect := Rect2(mbs.x - 185.0, mbs.z - 45.0, 309.0, 89.0)
	var circles := {"artscience_museum": 26.4, "singapore_flyer": 40.0, "supertree_grove": 28.0, "merlion": 5.4}
	var apart := true
	var keys := circles.keys()
	for i in keys.size():
		var a: Vector3 = world.locations[keys[i]]
		var ra: float = circles[keys[i]]
		if mbs_rect.grow(ra).has_point(Vector2(a.x, a.z)): apart = false
		for j in range(i + 1, keys.size()):
			var b: Vector3 = world.locations[keys[j]]
			if Vector2(a.x - b.x, a.z - b.z).length() < ra + float(circles[keys[j]]): apart = false
	_check("skyline: landmark footprints do not overlap each other", apart)
	# photo_06_aerial_district camera (fixed comparison view): 62 deg vertical FOV at 16:9.
	var cam := Vector3(250.0, 95.0, 250.0)
	var fwd := (Vector3(-40.0, 0.0, -60.0) - cam).normalized()
	var to_flyer: Vector3 = world.locations["singapore_flyer"] + Vector3(0.0, 85.0, 0.0) - cam
	var flat_fwd := Vector2(fwd.x, fwd.z).normalized()
	var flat_to := Vector2(to_flyer.x, to_flyer.z).normalized()
	var half_h := rad_to_deg(atan(tan(deg_to_rad(31.0)) * 16.0 / 9.0))
	var off := rad_to_deg(flat_fwd.angle_to(flat_to))
	_check("skyline: Singapore Flyer lies inside the photo_06 aerial frame", absf(off) < half_h - 5.0, "%.1f deg of %.1f" % [off, half_h])
	var root := world.get_node_or_null("District")
	var deck := root.get_node_or_null("RoofKit_deck") if root else null
	_check("skyline: flat roofs carry weathered decks and roof plant", deck != null and world._roof_kit.roofs >= 100 and world._roof_kit.part_count("condenser") >= 200 and world._roof_kit.part_count("housing") >= 60,
		"roofs %d condensers %d housings %d" % [world._roof_kit.roofs, world._roof_kit.part_count("condenser"), world._roof_kit.part_count("housing")])
	var city_layers := 0
	if root:
		for child in root.get_children():
			if String(child.name).begins_with("SkylineCity_"): city_layers += 1
	_check("skyline: layered background city is built from batched tower archetypes", city_layers >= 5, str(city_layers))
	var upgraded := LandmarkLooks.material_for("mbs_curtain_glass") is ShaderMaterial and LandmarkLooks.material_for("st_vertical_garden") is ShaderMaterial
	_check("skyline: landmark facade and vertical-garden shaders are applied", upgraded)
	var sk: Dictionary = world.skyline_stats
	_check("skyline: background city wears at least 5 distinct facade systems", int(sk.get("materials", 0)) >= 5, str(sk))
	_check("skyline: no background tower stands in the bay", int(sk.get("over_water", -1)) == 0 and int(sk.get("placed", 0)) > 150, str(sk))
	# The shadow meshes must survive static batching with their shader intact.
	var shadow_layers := 0
	if root:
		for child in root.get_children():
			if String(child.name).begins_with("SkylineShadow_") and child is MeshInstance3D and (child as MeshInstance3D).mesh.surface_get_material(0) is ShaderMaterial:
				shadow_layers += 1
	_check("skyline: every background tower casts a ground shadow", int(sk.get("ground_shadows", 0)) == int(sk.get("placed", -1)) and shadow_layers >= 5, "%s layers %d" % [str(sk), shadow_layers])
	# Aerial perspective: the CBD across the bay (800 m) must haze at
	# least ~33% toward the pale sky colour (critic A2: far contrast was 95%).
	var fsh: Shader = load("res://assets/authored/shaders/skyline_facade.gdshader")
	var hre := RegEx.new()
	hre.compile("uniform float (haze_start|haze_density|haze_max) = ([0-9.]+);")
	var hv := {}
	for m in hre.search_all(fsh.code):
		hv[m.get_string(1)] = m.get_string(2).to_float()
	var hs := float(hv.size())
	var h_start: float = hv.get("haze_start", 1e9)
	var h_den: float = hv.get("haze_density", 0.0)
	var h_max: float = hv.get("haze_max", 0.0)
	var haze_800 := (1.0 - exp(-maxf(800.0 - h_start, 0.0) * h_den)) * h_max
	var haze_200 := (1.0 - exp(-maxf(200.0 - h_start, 0.0) * h_den)) * h_max
	_check("skyline: far CBD hazes toward the sky, near district stays crisp", hs == 3.0 and haze_800 >= 0.33 and haze_200 <= 0.1, "haze@800m=%.2f haze@200m=%.2f" % [haze_800, haze_200])
	# Round 4: land and city beyond the bay, and haze that stays below the sky.
	_check("skyline: hinterland city carpet, low-rise blocks and third tower layer run past the bay", int(sk.get("lowrise", 0)) >= 2000 and float(sk.get("carpet_km2", 0.0)) >= 20.0 and int(sk.get("far_towers", 0)) >= 200 and int(sk.get("promenade_trees", 0)) >= 60, str(sk))
	var hcol := RegEx.new()
	hcol.compile("uniform vec3 (haze_col|horizon_col) : source_color = vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\);")
	var lum := {}
	for m in hcol.search_all(fsh.code):
		lum[m.get_string(1)] = 0.2126 * m.get_string(2).to_float() + 0.7152 * m.get_string(3).to_float() + 0.0722 * m.get_string(4).to_float()
	var gap := float(lum.get("horizon_col", 0.0)) - float(lum.get("haze_col", 1.0))
	_check("skyline: aerial haze is darker than the horizon sky so far towers keep silhouettes", lum.size() == 2 and gap >= 0.10 and int(sk.get("atmosphere", 0)) >= 2, "gap %.2f %s" % [gap, str(lum)])

## driving-p: handbrake rotation, momentum exchange in a rear-end crash, a
## wall rebound that keeps some speed, and visible damage. Disclosed fixture
## moves on the open test road; the car is put back afterwards.
func _driving_feel_checks(main: Node, car: Car) -> void:
	var home := car.global_position
	car.global_position = Vector3(0.0, 0.3, -300.0)
	car.rotation = Vector3.ZERO
	car.velocity = Vector3(0.0, 0.0, -18.0)
	await _ticks(2)
	var yaw0 := car.rotation.y
	Input.action_press("jump")
	Input.action_press("move_left")
	var slide := 0.0
	for i in 40:
		await get_tree().physics_frame
		slide = maxf(slide, car.drift_amount())
	Input.action_release("jump")
	Input.action_release("move_left")
	var turned := absf(angle_difference(yaw0, car.rotation.y))
	_check("handbrake turn swings the car round with the tail sliding", turned > 0.7 and slide > 0.2, "yaw %.2f rad slide %.2f" % [turned, slide])
	# Rear-end a stationary car at ~65 km/h.
	car.global_position = Vector3(0.0, 0.3, -300.0)
	car.rotation = Vector3.ZERO
	car.velocity = Vector3.ZERO
	car._yaw_rate = 0.0
	car._steer = 0.0
	await _ticks(2)
	var parked := Car.new()
	parked.kind = "sedan"
	main.add_child(parked)
	parked.global_position = Vector3(0.0, 0.5, -314.0)
	await _ticks(3)
	var parked_from := parked.global_position
	car.last_impact = {}
	car.velocity = Vector3(0.0, 0.0, -18.0)
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
		if not car.last_impact.is_empty(): break
	Input.action_release("move_forward")
	var hit := car.last_impact.duplicate()
	await _ticks(30)
	var kept := float(hit.get("speed_after", 0.0)) / maxf(0.1, float(hit.get("speed_before", 1.0)))
	_check("rear-end crash shares momentum (our car keeps rolling, the struck car is shoved)", bool(hit.get("car", false)) and kept > 0.2 and kept < 0.75 and parked.global_position.distance_to(parked_from) > 2.0, "kept %.2f moved %.2f closing %.1f" % [kept, parked.global_position.distance_to(parked_from), float(hit.get("closing", 0.0))])
	if car.damage != null and parked.damage != null:
		_check("crash leaves dents on both cars and throws debris", car.damage.dent_count() > 0 and parked.damage.dent_count() > 0 and car.damage.debris_spawned > 0, "dents %d/%d debris %d" % [car.damage.dent_count(), parked.damage.dent_count(), car.damage.debris_spawned])
	parked.queue_free()
	# Wall: rebound with a little speed kept, never a dead stop and never through it.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(12.0, 3.0, 0.6)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	main.add_child(wall)
	wall.global_position = Vector3(0.0, 1.5, -320.0)
	car.global_position = Vector3(0.0, 0.3, -306.0)
	car.rotation = Vector3.ZERO
	car._yaw_rate = 0.0
	car.last_impact = {}
	car._impact_cooldown = 0.0
	await _ticks(2)
	car.velocity = Vector3(0.0, 0.0, -16.0)
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
		if not car.last_impact.is_empty(): break
	Input.action_release("move_forward")
	var wall_hit := car.last_impact.duplicate()
	await _ticks(4)
	_check("wall impact rebounds instead of stopping dead", not bool(wall_hit.get("car", true)) and float(wall_hit.get("speed_after", 0.0)) > 1.5 and car.velocity.z > 0.0 and car.global_position.z > -320.0, "after %.1f m/s vz %.1f" % [float(wall_hit.get("speed_after", 0.0)), car.velocity.z])
	wall.queue_free()
	car.velocity = Vector3.ZERO
	car._forward = 0.0
	car._yaw_rate = 0.0
	car.global_position = home
	car.rotation = Vector3.ZERO
	await _ticks(2)

func _ticks(count: int) -> void:
	for tick in count:
		await get_tree().physics_frame

func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	await _ticks(3)
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame
	await _ticks(3)

## Wave B materials: road is the lane-aware asphalt shader, dressing placed
## condensers and roof plant, and the floating infill roof shells were reshaped.
func _materials_ok(world: Node) -> bool:
	var road := Palette.road_asphalt() as ShaderMaterial
	var road_ok := road != null and road.shader != null and String(road.shader.resource_path).ends_with("road_asphalt.gdshader")
	var paving_ok := Palette.mat_textured(Palette.CONCRETE_LIGHT, "pavers", Vector3.ONE, 0.92) is ShaderMaterial
	var s: Dictionary = SurfaceDressing.stats
	# Infill roofs belong to RoofKit since wave-A integration; walls stay here.
	var dressed := int(s.get("condensers", 0)) >= 500 and int(s.get("infill", 0)) >= 50 and int(s.get("overlays", 0)) >= 1 and int(s.get("shop_floor", 0)) == 1
	# r3: carriageway tint stays neutral/cool (golden sun must not turn it brown)
	# and no large hard-standing slab (ground, aprons) uses the turf material.
	var tint: Vector3 = road.get_shader_parameter("tint")
	var neutral := tint.z >= tint.x
	return road_ok and paving_ok and dressed and neutral and _hard_standing_not_turf(world) and world.get_tree().get_nodes_in_group("surface_dressing").size() >= 4

func _hard_standing_not_turf(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh:
		var sz: Vector3 = ((node as MeshInstance3D).mesh as BoxMesh).size
		var m := (node as MeshInstance3D).material_override
		if sz.x >= 100.0 and sz.z >= 100.0 and m != null and String(m.get_meta("weathered_kind", "")) == "soil":
			return false
	for c in node.get_children():
		if not _hard_standing_not_turf(c):
			return false
	return true

## Downtown plan (wave M, loop/DOWNTOWN_PLAN.md): the plan is self-consistent,
## its copies of the fixed legacy values still match WorldBuilder, and every
## downtown piece that has landed runs its own checks through this suite.
func _downtown_plan_checks(world: WorldBuilder) -> void:
	var problems := DowntownPlan.validate()
	var legacy: Dictionary = DowntownPlan.LEGACY
	var legacy_ok: bool = legacy["player_start"] == WorldBuilder.PLAYER_START and legacy["mbs_pos"] == WorldBuilder.MBS_POS \
		and legacy["grove_pos"] == WorldBuilder.GROVE_POS and is_equal_approx(float(legacy["promenade_z"]), WorldBuilder.PROMENADE_Z) \
		and is_equal_approx(float(legacy["player_start_yaw_deg"]), WorldBuilder.PLAYER_START_YAW_DEG)
	_check("downtown plan is self-consistent and matches the fixed legacy anchors (%s)" % DowntownPlan.PLAN_VERSION, problems.is_empty() and legacy_ok, "; ".join(problems) + ("" if legacy_ok else " legacy mismatch"))
	for path: String in DowntownPlan.PIECE_TESTS:
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			_check("downtown piece test loads: " + path, false)
			continue
		var piece_test: Object = script.new()
		if piece_test.has_method("run"):
			await piece_test.run(world, self)

func _check(check_name: String, condition: bool, detail: String = "") -> void:
	if _reported:
		return
	if not condition:
		failures += 1
	results.append({"name": check_name, "passed": condition, "detail": detail})
	print("%s %s %s" % ["PASS" if condition else "FAIL", check_name, detail])

## Lighting piece (Opus 5.5 wave A): golden-hour rig and practicals.
func _lighting_checks(world: WorldBuilder) -> void:
	var we: WorldEnvironment = null
	var sun: DirectionalLight3D = null
	for c in world.get_children():
		if c is WorldEnvironment: we = c
		if c is DirectionalLight3D and c.name == "Sun": sun = c
	var env: Environment = we.environment if we != null else null
	_check("golden-hour environment: sky ambient, SSAO+SSIL, glow, clear sky gradient",
		env != null and env.background_mode == Environment.BG_SKY and env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY
		and env.ssao_enabled and env.ssil_enabled and env.glow_enabled and env.fog_sky_affect < 0.05 and env.adjustment_color_correction != null)
	var sky_code := ""
	if env != null and env.sky != null and env.sky.sky_material is ShaderMaterial:
		sky_code = (env.sky.sky_material as ShaderMaterial).shader.code
	_check("sky glow and clouds follow the sun light (LIGHT0)", sky_code.contains("LIGHT0_DIRECTION") and sky_code.contains("cloud"))
	# Round 2 (critic A1): humid cumulus sky, not an empty cobalt gradient.
	var sky_mat: ShaderMaterial = env.sky.sky_material if env != null and env.sky != null and env.sky.sky_material is ShaderMaterial else null
	var zen := Color.BLUE
	var cover := 0.0
	if sky_mat != null:
		var zv: Variant = sky_mat.get_shader_parameter("zenith_color")
		if zv == null: zv = RenderingServer.shader_get_parameter_default(sky_mat.shader.get_rid(), "zenith_color")
		if zv is Vector3: zen = Color(zv.x, zv.y, zv.z)
		elif zv is Color: zen = zv
		var cv: Variant = sky_mat.get_shader_parameter("cloud_coverage")
		if cv == null: cv = RenderingServer.shader_get_parameter_default(sky_mat.shader.get_rid(), "cloud_coverage")
		if cv != null: cover = float(cv)
	_check("sky is pale humid blue under shaded cumulus (no cobalt)", sky_code.contains("puff(") and sky_code.contains("above")
		and zen.s < 0.65 and cover >= 0.5, "zenith_s=%.2f coverage=%.2f" % [zen.s, cover])
	# Round 2: shade must stay darker than sun (A1 shadow ratios 0.58-0.59) and
	# the sun must not throw a warm veil across sun-facing frames.
	# Round 4 (critic A3) asks for a warm golden-hour haze, so the scatter cap
	# is a bounded veil (<= 0.25), not zero.
	_check("shadow contrast and bounded haze (ambient, crisp sun, sun scatter <= 0.25)", env != null and sun != null
		and env.ambient_light_energy <= 0.7 and sun.light_angular_distance <= 0.3 and env.fog_sun_scatter <= 0.25
		and env.volumetric_fog_density <= 0.0015 and env.adjustment_saturation <= 1.02,
		"" if env == null else "ambient=%.2f scatter=%.2f" % [env.ambient_light_energy, env.fog_sun_scatter])
	var elevation := -sun.rotation_degrees.x if sun != null else 0.0
	_check("warm low late-afternoon sun with soft shadows", sun != null and sun.shadow_enabled and elevation > 8.0 and elevation < 30.0
		and sun.light_color.r > sun.light_color.b + 0.3 and sun.light_angular_distance > 0.0, "elevation=%.1f" % elevation)
	var lit: WorldBuilder = world
	var lighting: Lighting = lit.get("_lighting")
	_check("void decks, arcades and street lamps carry practical lights", lighting != null and lighting.void_deck_lights >= 24
		and lighting.arcade_lights >= 150 and lighting.lamp_lights >= 40,
		"" if lighting == null else "void=%d arcade=%d lamps=%d" % [lighting.void_deck_lights, lighting.arcade_lights, lighting.lamp_lights])
	var district := world.get_node_or_null("District")
	var lights_node := district.get_node_or_null("PracticalLights") if district != null else null
	var bounded := lights_node != null and lights_node.get_child_count() > 0
	if bounded:
		for l in lights_node.get_children():
			if not (l is Light3D) or (l as Light3D).shadow_enabled or not (l as Light3D).distance_fade_enabled:
				bounded = false
				break
	_check("practical lights are shadowless and distance-culled (cluster budget)", bounded)
	var fixtures := 0
	if district != null:
		for c in district.get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("LightingFixtures_"):
				fixtures += (c as MultiMeshInstance3D).multimesh.instance_count
	_check("every practical has a modelled fixture", lighting != null and fixtures >= lighting.light_count, "fixtures=%d" % fixtures)
	# Round 3 (critic A2): weathered surfaces and >= 8 clutter types at street level.
	var dressing: StreetDressing = lighting.dressing if lighting != null else null
	var kinds := 0
	if dressing != null:
		for k in dressing.counts:
			if int(dressing.counts[k]) > 0: kinds += 1
	_check("streets are weathered and dressed (wear volumes, >= 8 clutter types)", dressing != null and dressing.weather_volumes >= 16 and kinds >= 8,
		"" if dressing == null else "volumes=%d kinds=%d" % [dressing.weather_volumes, kinds])
	# Round 4 (critic A3): kerbed median planters with painted noses, no domes.
	var domes := 0
	if district != null:
		for c in district.get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("StreetDressing_shrub"):
				domes += 1
	_check("median beds have painted noses and no dome shrubs", dressing != null and int(dressing.counts.get("median_nose", 0)) >= 32 and domes == 0,
		"noses=%d dome_batches=%d" % [0 if dressing == null else int(dressing.counts.get("median_nose", 0)), domes])
	_nearfield_checks(world)
	# Round 4: the low sun disc sits inside the heritage-avenue toward-sun view.
	if sun != null:
		var to_sun := sun.global_transform.basis.z.normalized()
		var fwd := (Vector3(-40.0, 5.0, -155.0) - Vector3(-150.0, 2.6, -157.0)).normalized()
		var ang := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(to_sun.x, to_sun.z)))
		_check("low sun is in frame on the heritage avenue (toward-sun view)", absf(ang) < 40.0 and to_sun.y > 0.15, "azimuth_off=%.1f elev=%.2f" % [ang, to_sun.y])

## Nearfield R (opus55): modelled, collidable street props, legible sign
## faces, photo plant cards and a street-name blade that fits its text.
func _nearfield_checks(world: Node) -> void:
	if not NearField.enabled():
		return
	var found := {}
	for n in world.find_children("StreetDressing_*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		var kind := String(mmi.name).trim_prefix("StreetDressing_").get_slice("_", 0)
		if kind in NearFieldProps.KINDS and mmi.multimesh != null and mmi.multimesh.mesh == NearFieldProps.mesh(kind) and mmi.multimesh.instance_count > 0:
			found[kind] = int(found.get(kind, 0)) + mmi.multimesh.instance_count
	var have := ["tcone", "bin", "crate", "aframe"].all(func(k: String) -> bool: return found.has(k))
	_check("nearfield: cones, bins, crates and A-frame menus are modelled props (no primitive stand-ins)", have and ["tcone", "bin", "crate", "aframe"].all(func(k: String) -> bool: return k in StreetPropColliders.SOLID_KINDS), str(found))
	var two_ok := found.size() >= 0 and ["bike", "scooter"].all(func(k: String) -> bool: return k in StreetPropColliders.SOLID_KINDS)
	var two_models := world.find_children("StreetDressing_scooter*", "MultiMeshInstance3D", true, false)
	two_ok = two_ok and not two_models.is_empty() and (two_models[0] as MultiMeshInstance3D).multimesh.mesh == NearField.two_wheeler_mesh(true)
	_check("nearfield: parked bikes and scooters are multi-part models with on-foot collision", two_ok and StreetPropColliders.shape_count >= 500, "prop_boxes=%d" % StreetPropColliders.shape_count)
	# Godot front faces wind clockwise: the face side's (b - a) x (c - a) points away from its normal.
	var plate := NearField.plate_mesh().surface_get_arrays(0)
	var pv: PackedVector3Array = plate[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = plate[Mesh.ARRAY_NORMAL]
	_check("nearfield: sign plates show their pictogram face to the viewer", pv.size() >= 6 and (pv[1] - pv[0]).cross(pv[2] - pv[0]).dot(pn[0]) < 0.0)
	# R2 layered ground wear: lane resurfacing seams, saw-cut patch seams, kerb silt,
	# chipped markings, per-unit paver/tile variation (guards against merge reverts).
	var sh_dir := "res://assets/authored/shaders/"
	var wear_ok := true
	for pair in [["road_asphalt", "resurfacing panels"], ["road_asphalt", "silt fan"], ["road_asphalt", "sawcut"], ["road_paint", "chipped thermoplastic"], ["paving", "sunken / rocking slabs"], ["encaustic_tiles", "chipped corners"], ["leaf_litter", "curled leaves"]]:
		var path: String = sh_dir + pair[0] + (".gdshaderinc" if pair[0] == "leaf_litter" else ".gdshader")
		var f := FileAccess.open(path, FileAccess.READ)
		wear_ok = wear_ok and f != null and f.get_as_text().contains(pair[1])
	_check("nearfield: ground shaders carry layered wear (patch seams, resurfacing, silt, chipped paint, unit variation)", wear_ok)
	var cards_ok := true
	if NearField.cards_available():
		var shrubs := world.find_children("NearfieldShrub_*", "MultiMeshInstance3D", true, false)
		cards_ok = not shrubs.is_empty() and shrubs.all(func(n: Node) -> bool: return (n as GeometryInstance3D).material_override == NearField.card_material())
	_check("nearfield: median beds use photo plant cards when the generated atlas is present", cards_ok and int(NearField.stats.get("median_shrub", 0)) > 2000)
	var blade_ok := false
	for l in world.find_children("*", "Label3D", true, false):
		var lab := l as Label3D
		if lab.text == "Kampong Sirih Road":
			var w := ThemeDB.fallback_font.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lab.font_size).x * lab.pixel_size
			blade_ok = w > 1.0 and w <= 2.3
	_check("nearfield: street-name lettering fits inside its blade", blade_ok)

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
	_check("suite finished before watchdog deadline", false, "%d-second in-engine watchdog expired" % int(WATCHDOG_SECONDS))
	await _report(true)

func _report(timed_out: bool = false) -> void:
	if _reported:
		return
	_reported = true
	if _watchdog_timer:
		_watchdog_timer.stop()
	for action in InputMap.get_actions():
		Input.action_release(action)
	Game.simulation_paused = true
	Sfx.shutdown_audio()
	await get_tree().create_timer(0.15, true, false, true).timeout
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

## Street life (Opus wave A): camera-centred lane traffic, crowds, avenue
## canopy and taking a stopped ambient car.
## Wave M street-life: lane traffic and crowds adopt the downtown-map graph
## (synthetic graph here; the real one lands with the downtown-map piece).
func _downtown_adoption_checks(traffic: TrafficManager) -> void:
	var probe := AmbientTraffic.new()
	probe.traffic = traffic
	probe.nodes = traffic.world.traffic_nodes.duplicate()
	probe._build_edges()
	var legacy_edges := probe.edges.size()
	var legacy_nodes := probe.nodes.size()
	var corner := traffic.world.traffic_nodes.find(Vector3(320.0, 0.1, -320.0))
	var g := {"nodes": [Vector3(320.0, 0.0, -320.0), Vector3(400.0, 0.0, -320.0), Vector3(400.0, 0.0, -480.0), Vector3(560.0, 0.0, -320.0), Vector3(400.0, 3.6, -560.0)],
		"edges": [Vector2i(0, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(2, 4)], "lanes": [1, 2, 1, 2], "links": [Vector2i(0, corner)]}
	var added := probe.adopt_downtown(g)
	var two_lane := -1
	var bridge := -1
	var signals_ok := true
	for e in range(legacy_edges, probe.edges.size()):
		var ed: Dictionary = probe.edges[e]
		# Signals hold at the 3-road junction (and the legacy corner), not at bends.
		var to_junction := int(ed["to"]) == legacy_nodes or int(ed["to"]) == corner
		if bool(ed["signal"]) != to_junction:
			signals_ok = false
		if (ed["offs"] as Array).size() == 2 and two_lane < 0 and int(ed["to"]) == legacy_nodes + 1:
			two_lane = e
		if float(ed["y1"]) > 3.0:
			bridge = e
	var lat := -1.0
	var lift := -1.0
	if two_lane >= 0:
		var ed2: Dictionary = probe.edges[two_lane]
		lat = (probe.lane_point(two_lane, 0, 20.0) - (ed2["a"] as Vector3)).dot(ed2["left"])
	if bridge >= 0:
		lift = probe.lane_point(bridge, 0, float(probe.edges[bridge]["len"])).y
	_check("downtown road graph adopted by lane traffic (left-hand, merged, deck height)", corner >= 0 and added == 8 and probe.nodes.size() == legacy_nodes + 4 \
			and absf(lat - 5.25) < 0.05 and lift > 3.6 and signals_ok and probe.edges[0]["offs"] == AmbientTraffic.LANE_OFFSETS,
			"added=%d nodes=%d lat=%.2f lift=%.2f" % [added, probe.nodes.size(), lat, lift])
	probe.free()
	var crowd_probe := CrowdDirector.new()
	var walks := crowd_probe.adopt_downtown([[Vector3(400.0, 0.3, -330.0), Vector3(400.0, 0.3, -470.0)], [Vector3.ZERO]])
	crowd_probe.free()
	_check("downtown walks adopted by the crowd director", walks == 1, "walks=%d" % walks)

## Street-life M2: the crowd is women, men, elders and children with hair,
## skirts and props, not one recoloured young man; walkers off the pavement
## head back to it; taxis carry a legend sign; tail lamps are lens clusters.
func _people_checks(traffic: TrafficManager) -> void:
	var walkers: Array = []
	for p in traffic.peds:
		if is_instance_valid(p) and not p.is_police and not p.is_hostile:
			walkers.append(p)
	var c := CrowdPeople.census(walkers)
	var total := 0
	for k in ["man", "woman", "elder_m", "elder_f", "child"]:
		total += int(c.get(k, 0))
	var women := int(c.get("woman", 0)) + int(c.get("elder_f", 0))
	_check("crowd is women, men, elders and children (M2)", total >= walkers.size() * 0.9 and women >= total * 0.35 and int(c.get("child", 0)) >= 5 \
		and int(c.get("elder_m", 0)) + int(c.get("elder_f", 0)) >= 8, str(c))
	var hair := 0
	var skirts := 0
	var props := 0
	var posed := 0
	for p in walkers:
		var cv: CharacterVisual = p.character_visual
		if cv == null or cv.skeleton == null:
			continue
		if cv.skeleton.find_child("PeopleHair", true, false) != null: hair += 1
		if cv.skeleton.find_child("PeopleSkirt", true, false) != null: skirts += 1
		if cv.skeleton.find_child("People*", true, false) != null and String((p as Node).get_meta("people", {}).get("prop", "none")) != "none": props += 1
		if cv.skeleton.get_node_or_null("PeoplePose") != null: posed += 1
	_check("people carry hair, skirts, props and poses (M2)", hair >= walkers.size() * 0.3 and skirts >= 15 and props >= walkers.size() * 0.35 and posed >= 20,
		"hair=%d skirts=%d props=%d posed=%d of %d" % [hair, skirts, props, posed, walkers.size()])
	var probe := NPC.new()
	traffic.add_child(probe)
	probe.global_position = Vector3(0.0, 0.3, -80.0)    # mid-block, in the road
	var back := probe._pavement_return()
	probe.global_position = Vector3(0.0, 0.3, -158.0)   # on the junction crossing
	var cross := probe._pavement_return()
	probe.global_position = Vector3(10.6, 0.3, -80.0)   # on the pavement
	var pave := probe._pavement_return()
	probe.queue_free()
	_check("walkers off the pavement return to it, crossings allowed (M2)", back != Vector3.INF and absf(back.x) > WorldBuilder.ROAD_HALF and cross == Vector3.INF and pave == Vector3.INF, str(back))
	var taxi_ok := false
	var lamp_ok := false
	for v in get_tree().get_nodes_in_group("ambient_vehicles"):
		var av := v as AmbientVehicle
		if av == null:
			continue
		for mi in av.find_children("*", "MeshInstance3D", true, false):
			var sm := (mi as MeshInstance3D).material_override as ShaderMaterial
			if sm != null and sm.shader != null:
				if sm.shader.code.contains("T A X I"): taxi_ok = true
				if sm.shader.code.contains("uniform float brake"): lamp_ok = true
	_check("taxi roof signs carry a legend; tail lamps are lens clusters (M2)", taxi_ok and lamp_ok)

func _street_life_checks(player: Player, traffic: TrafficManager) -> void:
	var amb := traffic.ambient
	_check("street life systems present", amb != null and traffic.crowd != null and traffic.dressing != null)
	if amb == null or traffic.crowd == null or traffic.dressing == null:
		return
	_downtown_adoption_checks(traffic)
	_people_checks(traffic)
	print("[street-test] mode=", Game.mode, " vehicle=", player.current_vehicle)
	if player.current_vehicle != null:
		await _tap("interact")
		await _ticks(5)
	player.respawn_at(Vector3(-171.0, 0.45, -60.0), PI)
	if player.camera != null:
		player.camera.current = true
	await _ticks(12)
	var near := amb.count_near(amb._focus, AmbientTraffic.SPAWN_RADIUS + 5.0)
	_check("camera-centred lane traffic is dense", near >= 45, "%d within %d m of %s" % [near, int(AmbientTraffic.SPAWN_RADIUS), amb._focus.round()])
	var wrong := 0
	var checked := 0
	for v in amb.vehicles:
		if not v.active or v.s < AmbientTraffic.ENTRY:
			continue
		var ed: Dictionary = amb.edges[v.edge]
		var lateral: float = (v.global_position - (ed["a"] as Vector3)).dot(ed["left"])
		checked += 1
		if lateral < 1.0 or lateral > 5.5:
			wrong += 1
	_check("ambient traffic keeps to the left-hand lanes", checked > 20 and wrong == 0, "%d/%d off-lane" % [wrong, checked])
	var before := {}
	for v in amb.vehicles:
		if v.active:
			before[v] = v.global_position
	await _ticks(150)
	var moved := 0
	var total := 0
	var held := 0
	for v in before:
		if not is_instance_valid(v) or not v.active:
			continue
		total += 1
		if (v as Node3D).global_position.distance_to(before[v]) > 3.0:
			moved += 1
	for v in amb.vehicles:
		if v.active and v.speed < 0.6 and v.s > AmbientTraffic.ENTRY:
			held += 1
	_check("ambient traffic flows and queues", total > 20 and moved >= int(total * 0.35) and held >= 1, "%d/%d moved, %d holding %s" % [moved, total, held, amb.hold_reasons()])
	var overlaps := 0
	for i in amb.vehicles.size():
		var a := amb.vehicles[i]
		if not a.active:
			continue
		for j in range(i + 1, amb.vehicles.size()):
			var b := amb.vehicles[j]
			if b.active and a.global_position.distance_to(b.global_position) < 2.2:
				overlaps += 1
	_check("ambient vehicles never overlap", overlaps == 0, "%d overlapping pairs" % overlaps)
	var walkers := traffic.crowd.count_near(traffic.crowd._focus, 130.0)
	_check("camera-centred crowd on the pavements", walkers >= 40, "%d roamers within 130 m" % walkers)
	var overhang := 0
	for xf in traffic.dressing.trees:
		# Rain-tree crown radius is ~10.5 m at unit scale.
		if 10.5 * xf.basis.get_scale().x - (AvenueDressing.TRUNK_OFFSET - WorldBuilder.ROAD_HALF) >= 3.0:
			overhang += 1
	_check("avenue tree crowns overhang the carriageway", traffic.dressing.trees.size() >= 150 and overhang == traffic.dressing.trees.size(), "%d trees, %d overhang" % [traffic.dressing.trees.size(), overhang])
	# Take a stopped ambient car through the normal interaction input.
	var target: AmbientVehicle = null
	var best := INF
	for v in amb.vehicles:
		if v.active and v.kind != "bus" and v.s > AmbientTraffic.ENTRY + 6.0:
			var d := v.global_position.distance_to(player.global_position)
			if d < best:
				best = d
				target = v
	var taken := false
	if target != null and Game.mode == Game.MODE_FOOT:
		target.vmax = 0.0
		target.speed = 0.0
		var side := target.global_transform.basis.x
		player.respawn_at(target.global_position + side * 2.3 + Vector3(0, 0.45, 0), 0.0)
		await _ticks(4)
		var promoted_before: int = amb.stats["promoted"]
		await _tap("interact")
		await _ticks(2)
		taken = Game.mode == Game.MODE_CAR and player.current_vehicle is Car and int(amb.stats["promoted"]) == promoted_before + 1
		if taken:
			await _tap("interact")
			await _ticks(5)
	_check("a stopped ambient car can be taken with interact", taken, "mode=%d promoted=%d" % [Game.mode, int(amb.stats["promoted"])])

## On-foot piece: the walk clip plays at walking pace and the run clip's rate
## and stride scale with sprint speed, so planted feet do not slide.
func _gait_matches_speed(player: Player) -> bool:
	var cv: CharacterVisual = player.get("_visual")
	if cv == null or not cv.loaded:
		return true # primitive fallback body has no clips
	# Locomotion piece: walk, run and sprint are three authored gaits; at the
	# player's own speeds each plays within 0.85-1.2x of its authored rate.
	var gaits := {Player.WALK_SPEED: "walk", Player.RUN_SPEED: "run", Player.SPRINT_SPEED: "sprint"}
	var walk_ok := cv.gait_v2
	for speed in gaits:
		cv.set_motion(speed)
		walk_ok = walk_ok and cv._current == gaits[speed] and cv.animator.speed_scale >= 0.85 and cv.animator.speed_scale <= 1.2
	var run_ok := cv._clips.has("jump_start") and cv._clips.has("land") and cv._clips.has("stop") and cv.stride_amp == 1.0
	# Airborne: the jump clip must keep a non-zero rate (a zero rate froze the
	# crossfade into the air pose for the whole flight).
	cv.set_air_velocity(2.0, 5.0)
	cv.set_motion(0.0, false, false)
	run_ok = run_ok and cv.current_clip() == "jump" and cv.animator.speed_scale > 0.5
	cv.set_air_velocity(99.0, 5.0)
	cv.set_motion(0.0)
	var shadows_ok := cv.contact_shadows.size() == 3 and cv._foot_ids.size() == 2 and cv._foot_ids[0] >= 0 and cv._foot_ids[1] >= 0
	return walk_ok and run_ok and cv.motion != null and shadows_ok

## Water piece (Opus 5.5 loop): the bay must stay real water, not a tinted
## plane, with moving boats and a falling-water Merlion jet.
func _water_checks(world: WorldBuilder) -> void:
	var bay: BayWater = world.bay
	var shader_ok := bay != null and bay.water_material != null and bay.water_material.shader != null \
		and bay.water_material.shader.resource_path.ends_with("bay_water.gdshader")
	_check("bay water uses the animated water shader, not a flat material", shader_ok)
	if bay == null:
		return
	var cap_value: Variant = bay.water_material.get_shader_parameter("spec_cap")
	var cap: float = float(cap_value) if cap_value != null else -1.0
	_check("water sun glint is capped so no light blows a white disc", cap > 0.0 and cap <= 0.5, "spec_cap=%s" % cap)
	_check("water surface sits below the promenade deck with a seawall face", BayWater.LEVEL < -0.5 and bay.water.layers == BayWater.WATER_LAYER)
	var before := bay.boat_positions()
	await _ticks(30)
	var after := bay.boat_positions()
	var moved := 0
	for i in mini(before.size(), after.size()):
		if before[i].distance_to(after[i]) > 0.5:
			moved += 1
	_check("boats are on the bay and moving, ships ride at anchor offshore", bay.boat_count >= 12 and moved >= 10 and bay.anchored_ships >= 10, "boats=%d moved=%d anchored=%d" % [bay.boat_count, moved, bay.anchored_ships])
	var jet_ok := bay.jet != null and bay.jet.material_override is ShaderMaterial and bay.legacy_spray_hidden >= 1
	_check("Merlion jet is translucent falling water, opaque legacy strut hidden", jet_ok, "legacy_hidden=%d" % bay.legacy_spray_hidden)
	# water round 2: the periodic sine-sum swell read as straight streaks from
	# the air; the surface must stay a non-periodic multi-octave noise field
	# with whitecaps, and the avenue ends must stay capped as railed jetties.
	var code: String = bay.water_material.shader.code
	var wc_value: Variant = bay.water_material.get_shader_parameter("whitecaps")
	var wc: float = float(wc_value) if wc_value != null else 0.55
	_check("bay water is a non-periodic multi-octave wave field with whitecaps", code.contains("sea_field") and not code.contains("swell_gradient") and wc > 0.0, "whitecaps=%s" % wc)
	_check("avenue ends over the bay are railed jetty decks, not bare road slabs", bay.get_node_or_null("JettyRailPosts") != null)
	_check("sea continues to the horizon through a skirt sharing the water material", bay.horizon_skirt != null and bay.horizon_skirt.material_override == bay.water_material and code.contains("horizon_colour"))
	# water round 3: Marina Bay is a calm dammed reservoir. Whitecaps are gated
	# to open sea, every moving hull carries a Kelvin wedge plus a widening
	# turbulent stern trail, and the quays carry a lapping wet line.
	_check("bay stays glassy; foam is event-driven (Kelvin wakes, stern trail, quay wet line)", code.contains("* open_sea;") and code.contains("trail_foam") and code.contains("0.354") and code.contains("wet_line") and bay.boat_count >= 17)
	# water round 4: boats under way throw raised white water (bow spray
	# sheets, churned stern mound, ballistic droplets), every foam source is
	# rendered as lacy aerated foam, and the runabouts carry crew and rails.
	var wash := bay.wash
	var wash_ok := wash != null and wash.sheets != null and wash.sheets.instance_count == bay.moving_boats \
		and wash.churns != null and wash.churns.instance_count == bay.moving_boats and wash.droplet_quads >= bay.moving_boats * 100
	_check("moving boats throw raised spray sheets, stern churn and droplets", wash_ok, "moving=%d droplets=%d" % [bay.moving_boats, wash.droplet_quads if wash != null else 0])
	_check("wake and quay foam is lacy coverage, not smooth strokes", code.contains("lace_foam(") and code.contains("cell_edge(") and not code.contains("ring = smoothstep(1.5, 1.0, e)"))
	var launch_tris := BoatMeshes.launch().get_faces().size() / 3
	_check("runabout hull is a detailed crewed model (rails, windshield, driver)", launch_tris >= 1500, "tris=%d" % launch_tris)


## Locomotion-Q (Opus 5.5): foot locking, weighted starts, the sprint skid,
## authored backpedal, pedestrian personal space and street-prop collision.
func _locomotion_q_checks(player: Player) -> void:
	var cv: CharacterVisual = player.get("_visual")
	if cv == null or not cv.loaded:
		return
	cv.set_travel_direction(PI)
	cv.set_motion(1.3, true)
	var back_ok := cv.current_clip() == "aim_back" and cv.animator.speed_scale > 0.0
	cv.set_travel_direction(0.0)
	cv.set_motion(0.0)
	_check("locomotion-Q: planted-foot lock (leg IK) on the player; aimed backpedal is its own clip played forward, plus a skid clip",
		cv.foot_lock != null and back_ok and cv._clips.has("skid"), "clip=%s rate=%.2f" % [cv.current_clip(), cv.animator.speed_scale])
	_check("locomotion-Q: street props (scooters, bikes, planters...) collide with the on-foot player",
		StreetPropColliders.shape_count > 100 and (player.collision_mask & StreetPropColliders.PROP_LAYER) != 0, "boxes=%d" % StreetPropColliders.shape_count)
	# Standstill -> walk builds over a step, not in 0.14 s.
	player.respawn_at(Vector3(160.0, 0.4, -300.0), 0.0)
	await _ticks(10)
	Input.action_press("move_forward")
	Input.action_press("walk")
	var ticks := 0
	while ticks < 90 and player.velocity.length() < Player.WALK_SPEED - 0.05:
		await _ticks(1)
		ticks += 1
	Input.action_release("walk")
	_check("locomotion-Q: standstill to walk speed takes a real first step (>= 0.3 s)", ticks >= 18 and ticks < 90, "%.2f s" % (ticks / 60.0))
	# Sprint, then a sharp reversal: plant and skid, then face the other way.
	Input.action_press("sprint")
	await _ticks(80)
	var before := player.rotation.y
	Input.action_release("move_forward")
	Input.action_press("move_back")
	var skidded := false
	for i in 40:
		await _ticks(1)
		skidded = skidded or cv.current_clip() == "skid"
	await _ticks(30)
	Input.action_release("move_back")
	Input.action_release("sprint")
	var turned := absf(wrapf(player.rotation.y - before, -PI, PI)) > 2.6
	_check("locomotion-Q: a sharp 180 at a sprint plants a skid, then pivots", skidded and turned,
		"skid=%s turned=%.2f rad" % [skidded, absf(wrapf(player.rotation.y - before, -PI, PI))])
	await _ticks(20)
	# Pedestrians never share the player's space.
	var dummy := CharacterBody3D.new()
	dummy.collision_layer = 0
	get_tree().current_scene.add_child(dummy)
	dummy.collision_layer = 4
	dummy.add_to_group("npcs")
	dummy.global_position = player.global_position + Vector3(0.15, 0.0, 0.0)
	var avoid := PlayerAvoidance.new()
	for i in 6:
		avoid.steer(player, Vector3.ZERO, 1.0 / 60.0)
	var gap := Vector2(dummy.global_position.x - player.global_position.x, dummy.global_position.z - player.global_position.z).length()
	dummy.queue_free()
	_check("locomotion-Q: a pedestrian inside the player's personal space is shouldered clear", gap > 0.45, "gap=%.2f m" % gap)



## Characters piece (wave Q): rebuilt look mesh with all body regions, the
## procedural weapon grip on the right hand, and a varied crowd wardrobe that
## never repeats the player's outfit.
func _character_look_checks(player: Player) -> void:
	if not CharacterLook.enabled or not CharacterVisual.available("player"):
		return
	var info := CharacterLook.build_for_rig("player")
	var regions: PackedInt32Array = info.get("regions", PackedInt32Array())
	var all_regions := regions.size() == 8
	for r in [CharacterLook.R_SKIN, CharacterLook.R_SHIRT, CharacterLook.R_HAIR, CharacterLook.R_PANTS, CharacterLook.R_SHOE, CharacterLook.R_FACE]:
		all_regions = all_regions and regions.size() == 8 and regions[r] > 50
	_check("character look mesh has skin, face, hair, shirt, trousers and shoes", all_regions, str(regions))
	_check("player mitten fingers fold away for the jointed procedural hands", int(info.get("grip_verts", 0)) > 150, "folded=%d" % int(info.get("grip_verts", 0)))
	var fist := CharacterHands.build_hand(1.0, true)
	var relaxed := CharacterHands.build_hand(-1.0, false)
	_check("procedural hands: 4 jointed fingers + thumb in fist and relaxed poses", fist.get_surface_count() == 1 and fist.surface_get_array_len(0) > 2500 and relaxed.surface_get_array_len(0) == fist.surface_get_array_len(0), "verts=%d" % fist.surface_get_array_len(0))
	if ResourceLoader.exists("res://assets/providers/higgsfield/fabric_denim_albedo.png"):
		_check("character cloth uses the woven fabric set (flannel, denim, batik, jersey)", bool(info.get("fabrics", false)), str(info.get("fabrics", false)))
	var player_sig := CharacterLook.outfit_signature(CharacterLook.player_outfit())
	var sigs := {}
	var clash := false
	for i in 12:
		var o := CharacterLook.civilian_outfit(1000 + i * 7919)
		var sig := CharacterLook.outfit_signature(o)
		sigs[sig] = true
		clash = clash or sig == player_sig
	_check("crowd wardrobe: >= 8 distinct civilians, none in the player's outfit", sigs.size() >= 8 and not clash, "distinct=%d" % sigs.size())
	# Wave R: the look mesh is baked OFFLINE (load time) and matches a fresh build.
	var path := CharacterVisual.asset_path("player")
	var src_mesh: ArrayMesh = null
	var pm := (load(path) as PackedScene).instantiate()
	for node in pm.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh is ArrayMesh and (node as MeshInstance3D).mesh.get_surface_count() >= 2:
			src_mesh = (node as MeshInstance3D).mesh
			break
	var baked := CharacterLook._load_baked(src_mesh, path) if src_mesh != null else {}
	pm.free()
	_check("characters-R: player look mesh is baked offline and matches a fresh build (no runtime rebuild at load)",
		not baked.is_empty() and baked["regions"] == regions, "bake=%s" % CharacterLook.baked_path(path))
	_check("characters-R: hidden body skin under the clothes is dressed (no skin shards through the shirt/jeans)",
		int(info.get("dressed", 0)) > 50, "dressed=%d" % int(info.get("dressed", 0)))
	# Wave R: the combat aim layer seats the pistol by the characters' grip frames.
	var gf := CharacterHands.grip_frames()
	var prof := [[-0.03, 0.015, -0.02, 0.028], [-0.018, 0.015, -0.02, 0.028], [-0.006, 0.015, -0.02, 0.028], [0.006, 0.015, -0.02, 0.028], [0.018, 0.015, -0.02, 0.028], [0.03, 0.015, -0.02, 0.028]]
	var grip_r := CharacterHands.build_grip(true, prof)
	var grip_l := CharacterHands.build_grip(false, prof)
	_check("characters-R: gun and support hands publish grip frames and close fingers round the grip", gf.has("pistol_r") and gf.has("pistol_l")
		and grip_r.surface_get_array_len(0) > 2000 and grip_l.surface_get_array_len(0) > 2000, "verts=%d/%d" % [grip_r.surface_get_array_len(0), grip_l.surface_get_array_len(0)])
	var probe_cv := CharacterVisual.new()
	probe_cv.grip_frames = gf
	var probe_layer := AimIkLayer.new()
	probe_layer.visual = probe_cv
	var gb_t := Basis.looking_at(Vector3(0.3, -0.2, -1.0).normalized(), Vector3.UP)
	var hb_t := probe_layer._hand_basis(gb_t, "pistol", "r")
	var seat_err := ((hb_t * (gf["pistol_r"] as Transform3D).basis).get_rotation_quaternion().angle_to(gb_t.get_rotation_quaternion()))
	var off_err := (probe_layer._wrist_from_gun(gb_t, "pistol", "r") - hb_t * (gf["pistol_r"] as Transform3D).origin).length()
	probe_layer.free()
	probe_cv.free()
	_check("characters-R: the aim layer seats the pistol by the published grip frame (gun pose recovered exactly)", seat_err < 0.001 and off_err < 0.0001, "ang=%.4f off=%.5f" % [seat_err, off_err])
	var cv: CharacterVisual = player.get("_visual")
	if cv != null and cv.hands != null:
		_check("characters-R: the player's visual hands its grip frames to the aim layer (no second arm IK)", cv.grip_frames.has("pistol_r"), "")
	var heads := {}
	for i in 12:
		var hs: Vector4 = CharacterLook.civilian_outfit(500 + i * 7919)["head_shape"]
		heads["%d,%d,%d" % [int(hs.x * 4.0), int(hs.y * 4.0), int(hs.z * 4.0)]] = true
	_check("characters-R: civilians get their own head build (jaw, nose, brow, hair volume)", heads.size() >= 10, "distinct=%d" % heads.size())
	var hmin := 9.0
	var hmax := 0.0
	var elders := 0
	var builds := {}
	for i in 40:
		var o: Dictionary = CharacterLook.civilian_outfit(900 + i * 7919)
		hmin = minf(hmin, o["height"])
		hmax = maxf(hmax, o["height"])
		elders += 1 if (o["hair_col"] as Vector4).w > 0.4 and fmod((o["hair_col"] as Vector4).w, 2.0) > 0.4 else 0
		builds[int(((o["skin_col"] as Vector4).w + 0.3) * 3.0)] = true
	_check("characters-R2: the crowd spans heights (>=15 cm at 1.8 m), builds and older adults", (hmax - hmin) * 1.8 >= 0.15 and builds.size() >= 3 and elders >= 4, "spread=%.2fm builds=%d elders=%d/40" % [(hmax - hmin) * 1.8, builds.size(), elders])
	_character_people_checks()
	_character_stance_checks(player)

## Wave S (characters S1): civilians on the look mesh keep street-life's
## people (women, elders, children, skirts, skin tones) via instance params.
func _character_people_checks() -> void:
	var cpath := CharacterVisual.asset_path("civilian")
	var cm: ArrayMesh = null
	var cmodel := (load(cpath) as PackedScene).instantiate()
	for node in cmodel.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh is ArrayMesh and (node as MeshInstance3D).mesh.get_surface_count() >= 2:
			cm = (node as MeshInstance3D).mesh
			break
	var cbaked := CharacterLook._load_baked(cm, cpath) if cm != null else {}
	cmodel.free()
	_check("characters-S: the civilian look mesh is baked offline (crowd load needs no runtime rebuild)", not cbaked.is_empty(), CharacterLook.baked_path(cpath))
	if not cbaked.is_empty():
		var bf := CharacterLook._backfill_mesh(cbaked)
		var bf_tris := bf.surface_get_array_index_len(0) / 3 if bf.get_surface_count() == 1 else 0
		_check("characters-S: civilian head backfill closes the cracked face (head-only back faces, skinned)", bf_tris > 300 and bf_tris < 8000, "tris=%d" % bf_tris)
	var sigs := {}
	var tones := {}
	var bad_face := 0
	var bad_legs := 0
	var women := 0
	var elders_grey := 0
	var elders := 0
	for i in 60:
		var pp := CrowdPeople.pick(31 + i * 104729)
		var o := CharacterLook.person_outfit(pp, CharacterLook.civilian_outfit(77 + i * 7919))
		var per: Vector4 = o["person"]
		var fc: Vector4 = o["face_col"]
		sigs[CharacterLook.outfit_signature(o) + "|%d" % int(per.x)] = true
		var sk: Vector4 = o["skin_col"]
		tones["%d" % int(sk.x * 40.0)] = true
		if bool(pp["female"]):
			women += 1
			if fc.x > 0.0 or per.x < 0.5:
				bad_face += 1
		if bool(pp.get("skirt", false)) != (per.z > 0.5):
			bad_legs += 1
		if int(pp["kind"]) in [CrowdPeople.Kind.ELDER_M, CrowdPeople.Kind.ELDER_F]:
			elders += 1
			if fmod((o["hair_col"] as Vector4).w, 2.0) > 0.5:
				elders_grey += 1
	_check("characters-S: street-life people map onto the look outfit (women unstubbled, skirt legs, grey elders, >=5 skin tones, >=50/60 distinct)",
		bad_face == 0 and bad_legs == 0 and women > 10 and elders_grey == elders and tones.size() >= 5 and sigs.size() >= 50,
		"women=%d bad_face=%d bad_legs=%d elders=%d/%d tones=%d distinct=%d" % [women, bad_face, bad_legs, elders_grey, elders, tones.size(), sigs.size()])

## Characters T1: weight-shifted idle (soles planted, one knee soft, mirrored
## for half the crowd), adult head scale, skinned skirts and attached parts
## that hide with their carrier.
func _character_stance_checks(player: Player) -> void:
	var cv: CharacterVisual = player.get("_visual")
	if cv == null or not cv.loaded or "--legacy-idle" in OS.get_cmdline_user_args():
		return
	var sk := cv.skeleton
	var head := sk.find_bone("head")
	var anim := cv.animator.get_animation(cv._clips.get("idle", ""))
	var ok_anim := anim != null and anim.has_meta("idle_stance") and cv._clips.has("idle_b")
	var detail := "anim=%s" % ok_anim
	var planted := false
	var knees := false
	var shift := 0.0
	if ok_anim:
		var prefix := IdleStance._track_prefix(anim)
		var g := IdleStance._globals(anim, prefix, sk)
		var rest_foot_l := sk.get_bone_global_rest(sk.find_bone("foot.l")).origin
		var rest_foot_r := sk.get_bone_global_rest(sk.find_bone("foot.r")).origin
		var fl := g[sk.find_bone("foot.l")].origin
		var fr := g[sk.find_bone("foot.r")].origin
		planted = absf(fl.y - rest_foot_l.y) < 0.02 and absf(fr.y - rest_foot_r.y) < 0.02
		var kl := (g[sk.find_bone("shin.l")].origin - g[sk.find_bone("thigh.l")].origin).normalized().angle_to((fl - g[sk.find_bone("shin.l")].origin).normalized())
		var kr := (g[sk.find_bone("shin.r")].origin - g[sk.find_bone("thigh.r")].origin).normalized().angle_to((fr - g[sk.find_bone("shin.r")].origin).normalized())
		knees = absf(kl - kr) > 0.08
		shift = absf(g[sk.find_bone("pelvis")].origin.x - sk.get_bone_global_rest(sk.find_bone("pelvis")).origin.x)
		detail = "feet dy=%.3f/%.3f knees=%.2f/%.2f rad pelvis shift=%.3f" % [fl.y - rest_foot_l.y, fr.y - rest_foot_r.y, kl, kr, shift]
	_check("characters-T: weight-shifted idle (pelvis over one leg, one soft knee, both soles planted, mirrored idle_b)",
		ok_anim and planted and knees and shift > 0.025, detail)
	var hs := sk.get_bone_pose_scale(head).x if head >= 0 else 1.0
	_check("characters-T: adult head proportion (head bone scaled to ~1:7.5 of height)", hs > 0.85 and hs < 0.95, "head scale=%.2f" % hs)
	var holder := Node3D.new()
	add_child(holder)
	var v := CharacterVisual.new()
	holder.add_child(v)
	if v.configure("civilian", 4):
		var pp := CrowdPeople.person(CrowdPeople.Kind.WOMAN, 9001)
		pp["skirt"] = true
		pp["prop"] = "shopping"
		CrowdPeople.dress(holder, v, pp)
		var skirt := v.skeleton.find_child("PeopleSkirt", true, false) as MeshInstance3D
		var bag := v.skeleton.find_child("PeopleShopping", true, false) as MeshInstance3D
		var centre_err := INF
		if bag != null and bag.custom_aabb.size != Vector3.ZERO:
			var rest_xf := v.skeleton.get_bone_global_rest(v.skeleton.find_bone("hand.r")) * bag.transform
			centre_err = (rest_xf * bag.custom_aabb.get_center()).distance_to(CrowdPeople.BODY_CENTRE)
		_check("characters-T: skirts are skinned to the legs and a carried bag hides with its carrier (shared visibility centre)",
			skirt != null and skirt.skin != null and centre_err < 0.01, "skirt_skinned=%s bag_centre_err=%.3f" % [skirt != null and skirt.skin != null, centre_err])
	holder.queue_free()

