extends Node3D
## Isolated native physics/control tests; no city, player save or visible game.
class TestCar extends Car:
	var command:=Vector3.ZERO
	func _ready() -> void:
		collision_layer=8;collision_mask=1|2|4|8;platform_floor_layers=1
		_collision_shape=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(2,1.5,4.5)
		_collision_shape.shape=shape;_collision_shape.position.y=.75;add_child(_collision_shape)
		add_to_group("vehicles")
	func _player_control(_delta: float) -> void:
		velocity.x=command.x;velocity.z=command.z
		_forward=command.dot(-global_transform.basis.z)
	func _step_low_kerb(_delta: float) -> void:pass
class TestPerson extends NPC:
	var hits:=0
	func _ready() -> void:
		collision_layer=4;collision_mask=1|8;add_to_group("actors")
		body_root=Node3D.new();add_child(body_root)
		var collider:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.32;shape.height=1.8
		collider.shape=shape;collider.position.y=.9;add_child(collider)
	func _physics_process(_delta: float) -> void:pass
	func _process(_delta: float) -> void:pass
	func take_damage(amount: float,from_position: Vector3,by_player: bool=true) -> void:
		hits+=1
		super.take_damage(amount,from_position,by_player)
var rows: Array=[]
var fixture: Node3D
func _ready() -> void:run.call_deferred()
func check(name: String,ok: bool) -> void:
	rows.append({"name":name,"passed":ok});print("DRIVING_CHECK ",name," ",ok)
func box(pos: Vector3,extent: Vector3,layer: int=1) -> StaticBody3D:
	var body:=StaticBody3D.new();body.collision_layer=layer
	var shape:=CollisionShape3D.new();var resource:=BoxShape3D.new();resource.size=extent;shape.shape=resource
	body.add_child(shape);fixture.add_child(body);body.position=pos;return body
func car_at(pos: Vector3,velocity: Vector3) -> TestCar:
	var car:=TestCar.new();fixture.add_child(car);car.position=pos
	car.driver_is_player=true;car.command=velocity;car.velocity=velocity;return car
func person_at(pos: Vector3,hp: float=100) -> TestPerson:
	var npc:=TestPerson.new();fixture.add_child(npc);npc.position=pos;npc.health=hp;return npc
func ticks(n: int) -> void:
	for i in n:await get_tree().physics_frame
	await get_tree().process_frame
func fresh() -> void:
	if fixture:fixture.queue_free();await ticks(2)
	fixture=Node3D.new();add_child(fixture)
	box(Vector3(0,-.25,0),Vector3(60,.5,160))
	Game.simulation_paused=false;Game.wanted_heat=0;Game.set_wanted(0)
	await ticks(2)
func run() -> void:
	await fresh()
	var car:=car_at(Vector3(0,.04,8),Vector3(0,0,-12))
	var people: Array[TestPerson]=[person_at(Vector3(0,.04,4)),person_at(Vector3(0,.04,0)),person_at(Vector3(0,.04,-4))]
	await ticks(75)
	check("crosses_multiple_pedestrians_without_stopping",car.position.z< -5 and absf(car.velocity.z)>11.8)
	check("all_three_hits_register_once",people.all(func(p):return p.hits==1 and p.state==NPC.State.DEAD))
	check("pedestrians_do_not_damage_car",is_equal_approx(car.health,100.0))
	check("runover_uses_real_crime_damage_path",Game.wanted_heat>0)
	await fresh()
	car=car_at(Vector3(0,.04,8),Vector3(0,0,-12))
	var near:=person_at(Vector3(1.2,.04,3));var miss:=person_at(Vector3(2.4,.04,-1))
	await ticks(65)
	check("grazing_contact_registers",near.hits==1)
	check("nearby_sidewalk_person_not_hit",miss.hits==0 and is_equal_approx(miss.health,100.0))
	await fresh()
	box(Vector3(0,2,2),Vector3(12,4,.5))
	car=car_at(Vector3(0,.04,8),Vector3(0,0,-12));var behind:=person_at(Vector3(0,.04,-2))
	await ticks(60)
	check("wall_remains_solid",car.position.z>4.3)
	check("no_damage_through_wall",behind.hits==0)
	await fresh()
	car=car_at(Vector3(0,.04,-8),Vector3(0,0,9));var reverse:=person_at(Vector3(0,.04,-4))
	await ticks(60)
	check("reverse_contact_registers_without_stop",reverse.hits==1 and car.position.z>0 and car.velocity.z>8.8)
	await fresh()
	car=car_at(Vector3(0,.04,8),Vector3.ZERO);var fast:=person_at(Vector3(0,.04,3))
	await ticks(2);car.command=Vector3(0,0,-600);car.velocity=car.command
	await ticks(2)
	check("sweep_catches_high_speed_crossing",fast.hits==1)
	await fresh()
	car=car_at(Vector3(0,.04,0),Vector3(0,0,-4));var overlap:=person_at(Vector3(0,.04,-1),500)
	await ticks(5)
	check("initial_overlap_detected_once",overlap.hits==1 and overlap.health<500)
	await fresh()
	car=car_at(Vector3(0,.04,0),Vector3.ZERO);car.set_physics_process(false)
	var proxy:=Player.new();proxy._ensure_walk_action();proxy.current_vehicle=car;proxy.yaw=.4;proxy.pitch=-.2
	Game.settings.mouse_sensitivity=1.0;Game.settings.invert_y=false
	proxy._apply_mouse_look(Vector2(180,60))
	check("mouse_routes_to_car_orbit",absf(car.camera_yaw_offset)>.1 and absf(car.camera_pitch_offset)>.01)
	check("driving_look_preserves_hidden_foot_camera",is_equal_approx(proxy.yaw,.4) and is_equal_approx(proxy.pitch,-.2))
	var pitch:=car.camera_pitch_offset;car.reset_camera_look();Game.settings.invert_y=true
	proxy._apply_mouse_look(Vector2(0,60));check("car_look_honors_invert_y",pitch*car.camera_pitch_offset<0)
	car.apply_look_motion(Vector2(0,100000),.003,false)
	check("pitch_is_bounded",car.camera_pitch_offset>=-.95 and car.camera_pitch_offset<=.32)
	Game.simulation_paused=true;var prior:=car.camera_yaw_offset;car.apply_look_motion(Vector2(100,0),.003,false)
	check("pause_blocks_camera_input",is_equal_approx(prior,car.camera_yaw_offset));Game.simulation_paused=false
	car.reset_camera_look();check("camera_recenter",is_zero_approx(car.camera_yaw_offset) and is_zero_approx(car.camera_pitch_offset))
	car.camera_yaw_offset=1.0
	var reset_key:=InputEventKey.new();reset_key.physical_keycode=KEY_C;reset_key.keycode=KEY_C;reset_key.pressed=true
	proxy._unhandled_input(reset_key)
	check("C_key_recenters_car_camera",is_zero_approx(car.camera_yaw_offset))
	var fx:=preload("res://src/actors/car_fx.gd").new();car.add_child(fx);fx.car=car;fx.set_process(false);fx.set_physics_process(false)
	var camera:=Camera3D.new();car.add_child(camera);camera.top_level=true;fx.camera=camera
	fx._update_camera(.1);var old_pos:=camera.global_position
	car.apply_look_motion(Vector2(600,0),.0025,false)
	for i in 20:fx._update_camera(.05)
	check("render_camera_actually_orbits",camera.global_position.distance_to(old_pos)>3.0)
	check("orbit_does_not_steer_car",is_zero_approx(car.rotation.y))
	car.reset_camera_look();box(Vector3(0,2,3.5),Vector3(8,4,.5));await ticks(3)
	fx._cam_snap=true;fx._update_camera(.1)
	check("orbit_camera_respects_wall_collision",camera.global_position.z<3.1)
	for child in fixture.get_children():
		if child is StaticBody3D and child.position.z>3.0:child.collision_layer=8
	await ticks(2);fx._cam_snap=true;fx._update_camera(.1)
	check("orbit_camera_respects_vehicle_collision",camera.global_position.z<3.1)
	proxy.free()
	var failed:=rows.filter(func(row):return not row.passed).size()
	var result:={"checks":rows,"passed":failed==0,"failed":failed}
	var destination:="user://driving_controls_test.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):destination=arg.trim_prefix("--report=")
	FileAccess.open(destination,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DRIVING_RESULT ",JSON.stringify(result));get_tree().quit(0 if failed==0 else 1)
