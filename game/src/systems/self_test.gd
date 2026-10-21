class_name SelfTest
extends Node
## Headless acceptance checks (VERIFY-01 / SYSTEM-02).
## Run: godot --headless -- --test
## Prints PASS / FAIL lines and exits non-zero when a check fails.

signal finished(failures: int)

var failures := 0
var results: Array[String] = []
var _frames := 0

func run(main: Node) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run_checks(main)
	await _behaviour_checks(main)
	_report()

## Behavioural regression checks added after the wave-1 independent review
## found a death-in-vehicle softlock, a scripted-input path that never reached
## the game, traffic that destroyed itself and a wanted level that never fell.
func _behaviour_checks(main: Node) -> void:
	print("--- behavioural checks ---")
	var player = main.get_node_or_null("Player")
	var traffic = main.get_node_or_null("Traffic")

	# 1. control ownership: entering and then dying in a car must not leave the
	#    player bound to the vehicle
	if player and traffic and traffic.cars.size() > 0:
		var car: Car = traffic.cars[0]
		car.interact(player)
		await get_tree().process_frame
		_check("vehicle entry takes control", Game.mode == Game.MODE_CAR)
		_check("player is bound to the vehicle", player.current_vehicle == car)
		player.respawn_at(Game.last_safe_position, Game.last_safe_rotation)
		await get_tree().process_frame
		_check("death in a vehicle releases control", player.current_vehicle == null)
		_check("death in a vehicle returns to foot", Game.mode == Game.MODE_FOOT)
		_check("gameplay camera returns to the player", player.camera.current)
		var can_move: bool = await _can_walk(player)
		_check("the player can still walk after a vehicle death", can_move)

	# 2. scripted input must reach the same code path as a human press
	if player and traffic and traffic.cars.size() > 0:
		var car2: Car = traffic.cars[1]
		player.global_position = car2.global_position + Vector3(1.6, 0.2, 0.0)
		player.current_vehicle = null
		Game.set_mode(Game.MODE_FOOT)
		await get_tree().process_frame
		Input.action_press("interact")
		await get_tree().process_frame
		await get_tree().process_frame
		Input.action_release("interact")
		_check("a scripted interact press takes the vehicle", Game.mode == Game.MODE_CAR)
		player.respawn_at(player.global_position, player.rotation.y)

	# 3. traffic longevity: AI cars must survive ordinary street contact
	if traffic:
		var disabled := 0
		for c in traffic.cars:
			if is_instance_valid(c) and c.disabled:
				disabled += 1
		_check("no civilian traffic car is wrecked by street contact", disabled == 0, " (%d disabled of %d)" % [disabled, traffic.cars.size()])

	# 4. wanted lifecycle: heat must fall when nobody is looking
	Game.wanted_heat = 46.0
	Game.set_wanted(2)
	for i in 10:
		Game.decay_heat(2.0)
	_check("the wanted level falls as heat decays", Game.wanted_level < 2, " (now %d)" % Game.wanted_level)
	Game.wanted_level = 0
	Game.wanted_heat = 0.0
	Game.set_wanted(0)

	# 5. pause must pause
	Game.simulation_paused = true
	var before: Vector3 = player.global_position
	for i in 30:
		await get_tree().process_frame
	_check("the world is frozen while paused", player.global_position.distance_to(before) < 0.01)
	Game.simulation_paused = false

	# 6. the mission package must be pickable and must advance the mission
	var mission = main.get_node_or_null("Mission")
	if mission and player:
		var pkg = mission.get_node_or_null("MissionPackage")
		if pkg:
			player.global_position = pkg.global_position + Vector3(1.0, 0.3, 0.0)
			player.current_vehicle = null
			Game.set_mode(Game.MODE_FOOT)
			await get_tree().process_frame
			Input.action_press("interact")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("interact")
			_check("the mission package can be picked up", not pkg.visible)
			_check("picking up the package advances the mission", mission.stage > 0, " (stage %d)" % mission.stage)


func _can_walk(player: Node) -> bool:
	# walk on open road, not inside the safe room, so the check measures the
	# control path rather than a wall
	player.global_position = Vector3(0.0, 0.4, -300.0)
	await get_tree().process_frame
	var start: Vector3 = player.global_position
	Input.action_press("move_forward")
	for i in 20:
		await get_tree().process_frame
	Input.action_release("move_forward")
	return player.global_position.distance_to(start) > 0.2

func _check(name: String, condition: bool, detail: String = "") -> void:
	var verdict := "PASS" if condition else "FAIL"
	if not condition:
		failures += 1
	results.append("%s  %s %s" % [verdict, name, detail])
	print("%s  %s %s" % [verdict, name, detail])

func _run_checks(main: Node) -> void:
	print("=== Orchard Reach wave-1 headless checks ===")
	var world = main.get_node_or_null("World")
	_check("world builder present", world != null)
	if world:
		var mesh_count := _count_meshes(world)
		_check("district has real 3D meshes", mesh_count > 400, " (%d meshes)" % mesh_count)
		_check("traffic junction graph", world.traffic_nodes.size() == 25, " (%d nodes)" % world.traffic_nodes.size())
		_check("pedestrian lanes", world.ped_lanes.size() >= 20, " (%d lanes)" % world.ped_lanes.size())
	var player = main.get_node_or_null("Player")
	_check("player spawned", player != null)
	if player:
		_check("player has third-person camera", player.camera != null and player.camera.current)
		_check("player stands on the district", player.global_position.y > 0.0, " (y=%.2f)" % player.global_position.y)
	var traffic = main.get_node_or_null("Traffic")
	if traffic:
		_check("civilian traffic spawned", traffic.cars.size() >= 8, " (%d cars)" % traffic.cars.size())
		_check("pedestrians spawned", traffic.peds.size() >= 20, " (%d peds)" % traffic.peds.size())
	var mission = main.get_node_or_null("Mission")
	_check("mission running", mission != null and mission.stage == 0)
	if mission:
		_check("mission objective published", mission.current_objective() != "")
	_check("helicopter present", main.get_node_or_null("Helicopter") != null)
	_check("hud present", main.get_node_or_null("HUD") != null)

	Game.health = 55.0
	Game.mission_stage = 3
	var saved: bool = Game.save_game()
	_check("save writes a file", saved)
	Game.health = 100.0
	Game.mission_stage = 0
	var loaded: bool = Game.load_game()
	_check("load restores state", loaded and is_equal_approx(Game.health, 55.0) and Game.mission_stage == 3)
	_check("save file exists on disk", FileAccess.file_exists(Game.SAVE_PATH))

	var pkg = main.get_node_or_null("Mission/MissionPackage")
	_check("mission package is an interactable", pkg != null and pkg.is_in_group("interactables"))
	var heli = main.get_node_or_null("Helicopter")
	if heli:
		_check("helicopter can be boarded", heli.has_method("interact") and heli.has_method("exit_vehicle"))
	var cars := get_tree().get_nodes_in_group("vehicles")
	_check("vehicles present in world", cars.size() >= 10, " (%d)" % cars.size())
	var npcs := get_tree().get_nodes_in_group("npcs")
	_check("npcs present in world", npcs.size() >= 20, " (%d)" % npcs.size())

func _count_meshes(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			n += 1
		n += _count_meshes(child)
	return n

func _report() -> void:
	print("--- summary ---")
	var passed := 0
	for r in results:
		if r.begins_with("PASS"):
			passed += 1
	print("%d/%d checks passed, %d failed" % [passed, results.size(), failures])
	finished.emit(failures)
