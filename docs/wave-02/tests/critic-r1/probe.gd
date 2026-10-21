extends SceneTree

var observed := {}
var game: Node
var main: Node

func _initialize() -> void:
	call_deferred("run_probe")

func ticks(count: int) -> void:
	for i in count:
		await physics_frame

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: int) -> void:
	key(code, true)
	await ticks(2)
	key(code, false)
	await ticks(2)

func run_probe() -> void:
	game = root.get_node("Game")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await ticks(8)
	var player: Node3D = main.player
	observed["initial_title"] = {"started": main.started, "paused": game.simulation_paused}
	var before := player.global_position
	key(KEY_W, true)
	await ticks(35)
	key(KEY_W, false)
	observed["movement_behind_title_m"] = player.global_position.distance_to(before)
	await tap(KEY_ENTER)
	observed["enter_started"] = main.started
	before = player.global_position
	key(KEY_W, true)
	await ticks(35)
	key(KEY_W, false)
	observed["native_w_movement_m"] = player.global_position.distance_to(before)
	await tap(KEY_F9)
	observed["after_f9"] = {"started": main.started, "paused": game.simulation_paused}
	await tap(KEY_ENTER)
	observed["after_title_enter"] = {"started": main.started, "paused": game.simulation_paused}
	before = player.global_position
	key(KEY_W, true)
	await ticks(35)
	key(KEY_W, false)
	observed["movement_after_title_enter_m"] = player.global_position.distance_to(before)
	var fixture_path := "/tmp/orchard_gameplay_critic_bad_save.json"
	var fixture := FileAccess.open(fixture_path, FileAccess.WRITE)
	fixture.store_string('{"version":1,"health":12,"player_position":[]}')
	fixture.close()
	game.health = 73.0
	var result = game.load_game(fixture_path)
	observed["malformed_save"] = {"return_value": result, "health_after": game.health, "health_before": 73.0}
	var report := FileAccess.open("/tmp/orchard_gameplay_critic_probe.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(observed, "\t"))
	report.close()
	print("[critic-probe] ", JSON.stringify(observed))
	quit(0)
