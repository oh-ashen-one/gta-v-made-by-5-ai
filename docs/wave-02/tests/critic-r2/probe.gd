extends SceneTree
var observed := {}
var game: Node
var main: Node
var notices: Array[String] = []
var prompt := ""

func _initialize() -> void:
	call_deferred("run_probe")

func ticks(count: int) -> void:
	for i in count: await physics_frame

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: int) -> void:
	key(code,true)
	await ticks(2)
	key(code,false)
	await ticks(2)

func box(parent: Node, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var mesh := BoxShape3D.new()
	mesh.size = size
	shape.shape = mesh
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = position
	return body

func run_probe() -> void:
	game=root.get_node("Game")
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene=main
	root.get_node("Events").notify.connect(func(text: String, _kind: String): notices.append(text))
	root.get_node("Events").interaction_prompt.connect(func(text: String): prompt=text)
	await ticks(8)
	var player: Node3D=main.player
	observed["initial_title"]={"started":main.started,"paused":game.simulation_paused}
	var before:=player.global_position
	key(KEY_W,true)
	await ticks(35)
	key(KEY_W,false)
	observed["movement_behind_title_m"]=player.global_position.distance_to(before)
	# Read-only native F6 dispatch; never writes the owner's save.
	notices.clear()
	await tap(KEY_F6)
	observed["title_f6"]={"started":main.started,"paused":game.simulation_paused,"notices":notices.duplicate()}
	if main.started: await tap(KEY_F9)
	await tap(KEY_ENTER)
	observed["enter_started"]=main.started
	before=player.global_position
	key(KEY_W,true)
	await ticks(35)
	key(KEY_W,false)
	observed["native_w_movement_m"]=player.global_position.distance_to(before)
	await tap(KEY_F9)
	observed["after_f9"]={"started":main.started,"paused":game.simulation_paused}
	await tap(KEY_ENTER)
	observed["after_title_enter"]={"started":main.started,"paused":game.simulation_paused}
	before=player.global_position
	key(KEY_W,true)
	await ticks(35)
	key(KEY_W,false)
	observed["movement_after_title_enter_m"]=player.global_position.distance_to(before)
	await tap(KEY_ESCAPE)
	observed["pause_before_settings"]={"paused":game.simulation_paused,"panel":main.hud._pause_panel.visible}
	await tap(KEY_F3)
	await tap(KEY_F3)
	observed["pause_after_settings"]={"paused":game.simulation_paused,"panel":main.hud._pause_panel.visible,"settings":main.hud.settings_visible()}
	# Save tests are isolated and simulation is frozen to make state comparison exact.
	game.simulation_paused=true
	game.health=73.0
	game.wanted_heat=0.0
	game.set_wanted(0)
	main.mission.restore_stage(0)
	game.checkpoint_index=0
	var valid_path:="/tmp/orchard_critic_r2_valid_save.json"
	var bad_path:="/tmp/orchard_critic_r2_bad_save.json"
	var saved:bool=game.save_game(valid_path)
	var valid:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(valid_path))
	game.health=51.0
	var loaded:bool=game.load_game(valid_path)
	observed["valid_save"]={"saved":saved,"loaded":loaded,"health":game.health}
	var cases:={"empty_position":{"player_position":[]},"unknown_weapon":{"carried_weapon":"laser"},"negative_health":{"health":-1},"bad_ammo":{"ammo":{"pistol":{"mag":999,"reserve":0},"smg":{"mag":30,"reserve":5}}},"inconsistent_stage":{"mission_stage":5,"checkpoint_index":0}}
	var malformed_results:={}
	for label in cases:
		var candidate:=valid.duplicate(true)
		candidate.merge(cases[label],true)
		var file:=FileAccess.open(bad_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(candidate))
		file.close()
		game.health=73.0
		var state_before:=JSON.stringify({"health":game.health,"ammo":game.ammo,"stage":main.mission.stage,"weapon":game.carried_weapon,"position":player.global_position,"mode":game.mode})
		var accepted:bool=game.load_game(bad_path)
		var state_after:=JSON.stringify({"health":game.health,"ammo":game.ammo,"stage":main.mission.stage,"weapon":game.carried_weapon,"position":player.global_position,"mode":game.mode})
		malformed_results[label]={"accepted":accepted,"state_unchanged":state_before==state_after}
	observed["malformed_saves"]=malformed_results
	# Disclosed floating fixture isolates interaction from live city collisions.
	main.hud.set_paused(false)
	game.simulation_paused=false
	box(main,Vector3(0,19.8,-246),Vector3(30,.4,30))
	var car:Node3D=main.traffic.cars[0]
	car.has_ai=false
	car.disabled=false
	car.health=100.0
	car.global_position=Vector3(0,20.3,-246)
	car.rotation=Vector3.ZERO
	car.velocity=Vector3.ZERO
	player.respawn_at(Vector3(3.4,20.4,-246),0.0)
	var wall:=box(main,Vector3(1.7,21.5,-246),Vector3(.3,3,8))
	await ticks(12)
	observed["wall_blocks_target"]=player._interaction_target()==null
	await tap(KEY_E)
	observed["wall_blocks_native_entry"]=player.current_vehicle==null
	wall.queue_free()
	await ticks(5)
	observed["clear_target_is_car"]=player._interaction_target()==car
	await tap(KEY_E)
	observed["clear_native_entry"]=player.current_vehicle==car
	await tap(KEY_E)
	player.respawn_at(Vector3(3.4,20.4,-246),0.0)
	car.disabled=true
	await ticks(5)
	observed["disabled_car"]={"target_selected":player._interaction_target()==car,"prompt":prompt}
	await tap(KEY_E)
	observed["disabled_car"]["entry_rejected"]=player.current_vehicle==null
	car.disabled=false
	main.mission.package_node.global_position=Vector3(2.6,20.2,-246)
	await ticks(3)
	observed["nearest_package_selected"]=player._interaction_target()==main.mission.package_node
	main.mission.package_node.visible=false
	await ticks(3)
	observed["hidden_package_skipped"]=player._interaction_target()==car
	var report:=FileAccess.open("/tmp/orchard_gameplay_critic_probe_r2.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(observed,"\t"))
	report.close()
	print("[critic-probe-r2] ",JSON.stringify(observed))
	quit(0)
