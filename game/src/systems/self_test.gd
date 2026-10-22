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
	var configured_peds := TrafficManager.PED_COUNT + TrafficManager.DINER_COUNT
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
	var ew_green: MeshInstance3D
	var ns_green: MeshInstance3D
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
	_check("on-foot gait: clip, playback rate and stride follow ground speed; feet carry contact shadows", _gait_matches_speed(player))

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
	await _water_checks(world)
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
	await _ticks(15)
	await _tap("fire")
	_check("clearing muzzle obstruction permits target damage", target.health < target_health)
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
	var mbs_rect := Rect2(mbs.x - 122.0, mbs.z - 30.0, 307.0, 67.2)
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
	# Round 4: the low sun disc sits inside the heritage-avenue toward-sun view.
	if sun != null:
		var to_sun := sun.global_transform.basis.z.normalized()
		var fwd := (Vector3(-40.0, 5.0, -155.0) - Vector3(-150.0, 2.6, -157.0)).normalized()
		var ang := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(to_sun.x, to_sun.z)))
		_check("low sun is in frame on the heritage avenue (toward-sun view)", absf(ang) < 40.0 and to_sun.y > 0.15, "azimuth_off=%.1f elev=%.2f" % [ang, to_sun.y])

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


## On-foot piece: the walk clip plays at walking pace and the run clip's rate
## and stride scale with sprint speed, so planted feet do not slide.
func _gait_matches_speed(player: Player) -> bool:
	var cv: CharacterVisual = player.get("_visual")
	if cv == null or not cv.loaded:
		return true # primitive fallback body has no clips
	cv.set_motion(1.5)
	var walk_ok := cv._current == "walk" and absf(cv.animator.speed_scale - 1.5 / CharacterVisual.WALK_CLIP_SPEED) < 0.01
	cv.set_motion(6.8)
	var run_ok := cv._current == "run" and cv.stride_amp > 1.1 and cv.animator.speed_scale > 1.0 and cv.animator.speed_scale < 1.6
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

