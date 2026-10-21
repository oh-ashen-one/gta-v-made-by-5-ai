extends SceneTree
var observed := {}
var game: Node
var main: Node
var notices: Array[String]=[]
var prompt := ""
const SAVE := "/tmp/critic-wave2-save.json"

func _initialize() -> void: call_deferred("run_probe")
func ticks(count:int) -> void:
	for i in count: await physics_frame
func key(code:int,down:bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=down
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func tap(code:int) -> void:
	key(code,true)
	await ticks(2)
	key(code,false)
	await ticks(2)
func box(parent:Node,position:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new()
	body.collision_layer=1
	var shape:=CollisionShape3D.new()
	var mesh:=BoxShape3D.new()
	mesh.size=size
	shape.shape=mesh
	body.add_child(shape)
	parent.add_child(body)
	body.global_position=position
	return body
func weapon_path(player:Node)->String:
	return player._weapon_model.scene_file_path if player._weapon_model else "none"

func run_probe()->void:
	game=root.get_node("Game")
	if game._save_path!=SAVE:
		push_error("QA save isolation failed; refusing probe")
		quit(3)
		return
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene=main
	root.get_node("Events").notify.connect(func(text:String,_kind:String):notices.append(text))
	root.get_node("Events").interaction_prompt.connect(func(text:String):prompt=text)
	await ticks(8)
	var player:Node3D=main.player
	observed["save_path"]=game._save_path
	await tap(KEY_ENTER)
	await tap(KEY_Q)
	observed["weapon_before_save"]={"id":game.carried_weapon,"model":weapon_path(player)}
	await tap(KEY_ESCAPE)
	await tap(KEY_F3)
	await tap(KEY_2)
	await tap(KEY_3)
	await tap(KEY_4)
	await tap(KEY_5)
	var expected_settings:Dictionary=game.settings.duplicate(true)
	await tap(KEY_F3)
	observed["pause_settings_close"]={"paused":game.simulation_paused,"panel":main.hud._pause_panel.visible,"settings":main.hud.settings_visible(),"mouse_visible":Input.mouse_mode==Input.MOUSE_MODE_VISIBLE}
	var before:=player.global_position
	key(KEY_W,true)
	await ticks(30)
	key(KEY_W,false)
	observed["paused_movement_m"]=player.global_position.distance_to(before)
	game.health=73.0
	notices.clear()
	await tap(KEY_F5)
	var first_bytes:=FileAccess.get_file_as_string(SAVE)
	var first_data:Dictionary=JSON.parse_string(first_bytes)
	observed["native_f5"]={"notices":notices.duplicate(),"health":first_data.get("health"),"settings_match":first_data.get("settings")==expected_settings,"weapon":first_data.get("carried_weapon")}
	game.health=67.0
	var second_saved:bool=game.save_game()
	var second_bytes:=FileAccess.get_file_as_string(SAVE)
	var second_data:Dictionary=JSON.parse_string(second_bytes)
	observed["replacement"]={"saved":second_saved,"new_health":second_data.get("health"),"bytes_changed":first_bytes!=second_bytes,"temporary_absent":not FileAccess.file_exists(SAVE+".tmp-%d"%OS.get_process_id())}
	game.health=-1.0
	var rejected:bool=game.save_game()
	observed["invalid_write"]={"saved":rejected,"previous_bytes_preserved":FileAccess.get_file_as_string(SAVE)==second_bytes}
	game.health=68.0
	var blocked_temp:=SAVE+".tmp-%d"%OS.get_process_id()
	var created:=DirAccess.make_dir_absolute(blocked_temp)
	var refused:bool=game.save_game()
	observed["temporary_open_failure"]={"fixture_created":created==OK,"saved":refused,"previous_bytes_preserved":FileAccess.get_file_as_string(SAVE)==second_bytes}
	DirAccess.remove_absolute(blocked_temp)
	# Restore different live values, then exercise the actual title F6 path.
	await tap(KEY_ESCAPE)
	await tap(KEY_Q)
	observed["weapon_before_continue"]={"id":game.carried_weapon,"model":weapon_path(player)}
	game.health=41.0
	game.settings={"mouse_sensitivity":1.0,"invert_y":false,"reduced_shake":false,"hud_visible":true}
	await tap(KEY_F9)
	notices.clear()
	await tap(KEY_F6)
	observed["title_f6_success"]={"started":main.started,"paused":game.simulation_paused,"title_visible":main.hud._title_panel.visible,"health":game.health,"settings_match":game.settings==expected_settings,"hud_hidden":not main.hud._objective_label.visible,"notices":notices.duplicate(),"weapon":game.carried_weapon,"weapon_model":weapon_path(player)}
	before=player.global_position
	key(KEY_W,true)
	await ticks(30)
	key(KEY_W,false)
	observed["continued_movement_m"]=player.global_position.distance_to(before)
	# Retest corruption against the new settings-bearing format.
	game.simulation_paused=true
	var corrupt:=second_data.duplicate(true)
	corrupt["settings"]["invert_y"]="yes"
	var malformed:=FileAccess.open("/tmp/critic-wave2-bad-settings.json",FileAccess.WRITE)
	malformed.store_string(JSON.stringify(corrupt))
	malformed.close()
	var unchanged:=JSON.stringify({"health":game.health,"settings":game.settings,"weapon":game.carried_weapon})
	var accepted:bool=game.load_game("/tmp/critic-wave2-bad-settings.json")
	observed["malformed_settings"]={"accepted":accepted,"state_unchanged":unchanged==JSON.stringify({"health":game.health,"settings":game.settings,"weapon":game.carried_weapon})}
	game.simulation_paused=false
	box(main,Vector3(0,19.8,-246),Vector3(30,.4,30))
	var car:Node3D=main.traffic.cars[0]
	car.has_ai=false
	car.disabled=true
	car.global_position=Vector3(0,20.3,-246)
	car.rotation=Vector3.ZERO
	car.velocity=Vector3.ZERO
	player.respawn_at(Vector3(3.4,20.4,-246),0.0)
	await ticks(12)
	observed["disabled_car"]={"target_absent":player._interaction_target()==null,"prompt":prompt}
	car.disabled=false
	await ticks(3)
	observed["enabled_car"]={"target_selected":player._interaction_target()==car,"prompt":prompt}
	var report:=FileAccess.open("/tmp/orchard_gameplay_critic_probe_r3.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(observed,"\t"))
	report.close()
	print("[critic-probe-r3] ",JSON.stringify(observed))
	quit(0)
