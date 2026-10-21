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
	_report()

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
