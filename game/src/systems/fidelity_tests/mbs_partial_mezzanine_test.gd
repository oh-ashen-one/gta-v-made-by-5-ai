extends "res://src/systems/fidelity_tests/mbs_guest_floor_test.gd"
## Actual-source low service geometry/room/stair proof. Transport low receiving
## gates remain Root integration, never simulated ready/open by this fixture.
const Partial = preload("res://src/world/mbs_interior/partial_mezzanine.gd")
const Program = preload("res://src/world/mbs_interior/program_floor.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const Stack = preload("res://src/world/mbs_interior/floor_stack.gd")
var selected_tower := "T3"
var modules: Dictionary = {}
var frame: RefCounted
var context: RefCounted
var runtime: Node3D
var domain: RefCounted
var started_ms := 0
var measurements: Dictionary = {}

func _ready()->void:
	if not "--qa-session" in OS.get_cmdline_user_args():get_tree().quit(2);return
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--partial-tower="):selected_tower=arg.trim_prefix("--partial-tower=")
	if not selected_tower in ["T1","T2","T3"]:get_tree().quit(2);return
	started_ms=Time.get_ticks_msec()
	get_tree().create_timer(900.0,true,false,true).timeout.connect(func():
		if not finished:check("bounded low service factory fixture",false);finish())
	run.call_deferred()

func _hash(value:String)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(value.to_utf8_buffer());return hash.finish().hex_encode()

func _anchor(record:Dictionary)->Array:
	for tower:Dictionary in Reference.DATA.towers:
		if tower.tower==record.tower:return [float(tower.centroid_world_xz[0]),float(record.elevation_m),float(tower.centroid_world_xz[1])]
	return []

func _canonical(record:Dictionary,local:Vector3)->Array:
	var point:Array=_anchor(record);var x:Array=Reference.DATA.axis_south_xz;var z:Array=Reference.DATA.axis_bayward_xz
	return [float(point[0])+float(x[0])*float(local.x)+float(z[0])*float(local.z),float(point[1])+float(local.y),float(point[2])+float(x[1])*float(local.x)+float(z[1])*float(local.z)]

func _collect(node:Node,result:Array)->void:
	if node is CollisionObject3D and node.collision_layer!=0:result.append(node)
	for child:Node in node.get_children():_collect(child,result)

func _native_register(module:Node3D,record:Dictionary)->bool:
	var boxes:Array=[]
	if module is Partial:boxes=module.geometry_descriptor().dry_boxes_local
	else:
		var g:Dictionary=record.geometry
		for wing:Dictionary in module.get("_plan").wings:
			boxes.append({"id":String(wing.id)+"-normal-main","center":Vector3(0,1.415,(float(wing.inner_z)+float(wing.outer_z))*.5),"half":Vector3(float(g.length_m)*.5-float(g.core_bay_m),1.665,absf(float(wing.outer_z)-float(wing.inner_z))*.5)})
			for sign:float in [-1.0,1.0]:boxes.append({"id":String(wing.id)+"-normal-core-"+str(sign),"center":Vector3(sign*(float(g.length_m)*.5-float(g.core_bay_m)*.5),1.415,(float(wing.inner_z)+float(wing.core_z))*.5),"half":Vector3(float(g.core_bay_m)*.5,1.665,absf(float(wing.core_z)-float(wing.inner_z))*.5)})
	var volumes:Array=[]
	for box:Dictionary in boxes:volumes.append({"schema":Context.OBOX_SCHEMA,"volume_id":box.id,"center_xyz":_canonical(record,box.center),"half_extents_xyz":[float(box.half.x),float(box.half.y),float(box.half.z)],"axis_x_xyz":[Reference.DATA.axis_south_xz[0],0.0,Reference.DATA.axis_south_xz[1]],"axis_z_xyz":[Reference.DATA.axis_bayward_xz[0],0.0,Reference.DATA.axis_bayward_xz[1]],"dry":true})
	var structure:StaticBody3D=module.get_node_or_null("ProgramFloorSolidCollision") as StaticBody3D
	if not check("actual plain structural support exists "+String(record.id),structure!=null and structure.get_script()==null and structure.get_class()=="StaticBody3D"):return false
	var definition:Dictionary={"feature_id":Stack.FEATURE,"floor_id":record.id,"geometry_sha256":_hash(JSON.stringify({"record":record,"descriptor":module.geometry_descriptor() if module is Partial else module.report()},"",true,true)),"support_ids":["static/ProgramFloorSolidCollision"],"volumes":volumes,"provenance":"QA actual source placements; original reconstructed service galleries, not surveyed as-built"}
	if not check("precise local architecture volumes register "+String(record.id),context.register_floor(definition)):return false
	var bodies:Array=[];_collect(module,bodies)
	var minimum:Array=[INF,INF,INF];var maximum:Array=[-INF,-INF,-INF]
	var length_m:float=record.geometry.length_m;var cross_m:float=record.geometry.cross_m
	for x:float in [-length_m*.5,length_m*.5]:
		for z:float in [-cross_m*.5,cross_m*.5]:
			for y:float in [-.30,8.0]:
				var corner:Array=_canonical(record,Vector3(x,y,z))
				for axis in 3:minimum[axis]=minf(minimum[axis],corner[axis]);maximum[axis]=maxf(maximum[axis],corner[axis])
	return check("complete native bodies commit "+String(record.id),runtime.commit_region("partial-native/"+String(record.id),minimum,maximum,bodies,[{"body":structure,"feature_id":Stack.FEATURE,"floor_id":record.id,"support_id":"static/ProgramFloorSolidCollision"}]))

func _corridor(module:Node3D,wing:String)->Vector3:
	for row:Dictionary in module.get("_plan").wings:
		if row.id==wing:return Vector3(0,0,row.corridor_center_z)
	return Vector3(INF,INF,INF)

func _cross_wing(module:Node3D,target:Vector3,from_wing:String,to_wing:String)->bool:
	var x:float=-float(module.floor_record.geometry.length_m)*.5+float(module.floor_record.geometry.core_bay_m)+Partial.END_LINK_WIDTH*.5
	var from:Vector3=_corridor(module,from_wing);var to:Vector3=_corridor(module,to_wing)
	for local:Vector3 in [Vector3(x,0,from.z),Vector3(x,0,to.z),target]:
		walk_stage="real partial end-crosslink/"+to_wing
		if not await walk_to(module.to_global(local),.18):return false
	return true

func _rooms_and_doors(module:Node3D)->bool:
	candidate=module
	var current_wing:String="east"
	for desired_wing:String in ["east","west"]:
		var room:Dictionary={}
		for cell:Dictionary in module.rooms:
			if cell.wing==desired_wing:room=cell;break
		if not check("fully furnished low service room selected "+String(module.floor_record.id)+"/"+desired_wing,not room.is_empty() and room.objects.size()>=3):return false
		if desired_wing!=current_wing:
			if not await _cross_wing(module,room.entry_local,current_wing,desired_wing):return false
		else:
			if not await walk_public_to(room.entry_local,desired_wing):return false
		current_wing=desired_wing
		if not await native_e(room.id):return false
		var door:Node3D=module.doors[room.id];var shape:CollisionShape3D=door.get_node("MatchingLowDoorLeaf")
		if not check("native low door visible/collision height matches2.10m",absf((shape.shape as BoxShape3D).size.y-2.10)<.001):return false
		for point:Vector3 in module.room_route_local(room.id):
			walk_stage="low service room native walk/"+String(room.id)
			if not await walk_to(module.to_global(point),.18):return false
		if not await native_e(room.id):return false
	var east:Vector3=_corridor(module,"east")
	return await _cross_wing(module,east,"west","east")

func _stair_between(lower:Node3D,upper:Node3D,ascending:bool)->bool:
	candidate=lower
	var stair:Dictionary={}
	for portal:Dictionary in lower.portals:
		if portal.kind=="stair" and portal.wing=="east":stair=portal;break
	if not check("actual2.5m physical U flight exists",not stair.is_empty() and absf(stair.upper.y-2.5)<.001):return false
	if ascending:
		if not await walk_public_to(stair.lower,"east"):return false
		for point:Vector3 in stair.walk_route:
			walk_stage="actual2.5m U ascent/"+String(lower.floor_record.id)
			if not await walk_to(lower.to_global(point),.22):return false
		if not await walk_to(lower.to_global(stair.upper),.18):return false
	else:
		candidate=upper
		if not await walk_public_to(upper.to_local(lower.to_global(stair.upper)),"east"):return false
		candidate=lower
		for index in range(stair.walk_route.size()-1,-1,-1):
			walk_stage="actual2.5m U descent/"+String(lower.floor_record.id)
			if not await walk_to(lower.to_global(stair.walk_route[index]),.22):return false
	return true

func run()->void:
	Game.simulation_paused=false;Game.mode=Game.MODE_FOOT;Game.health=Game.MAX_HEALTH;Game.death_count=0
	for tower:String in ["T1","T2","T3"]:
		for level:String in ["B2","B2M"]:
			var record:Dictionary=Inventory.floor_record(tower+"-"+level)
			var plan:Dictionary=Partial.partial_plan(record)
			if not check("all six exact low inventory recipes plan "+String(record.id),plan.get("valid",false) and plan.rooms.size()==5 and plan.core_programs.size()==3 and plan.objects.size()>=15 and plan.geometry.storey_height_m==2.5 and plan.geometry.clear_height_m==2.3,plan.get("error","")):finish();return
	var invalid:Dictionary=Inventory.floor_record(selected_tower+"-B2M");invalid.geometry.cross_m=NAN
	var rejected:=Partial.new();add_child(rejected)
	check("invalid partial plan rejects before node/state mutation",not rejected.build(invalid).get("built",true) and rejected.get_child_count()==0 and rejected.rooms.is_empty() and rejected.doors.is_empty())
	rejected.queue_free()
	var raw:=FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json");var manifest:Dictionary=JSON.parse_string(raw)
	var lower_record:Dictionary=Inventory.floor_record(selected_tower+"-B2")
	frame=Frame.new()
	if not check("actual uncompressed tower source frame configures",frame.configure(manifest.georeference,_anchor(lower_record),_hash(raw),{"status":"staging","reference":"Reconstructed basement L1=0; no surveyed elevations"})):finish();return
	context=Context.new();var profile:Dictionary={"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":cos(deg_to_rad(52.0)),"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}
	if not check("shared actual World3D context configures",context.configure(frame,_hash(FileAccess.get_file_as_string("res://src/world/mbs_interior/partial_mezzanine.gd")),_hash("Reconstructed B2=-10/B2M=-7.5/B1=-5"),profile,get_world_3d())):finish();return
	domain=Domain.new()
	if not check("actual pinned Singapore domain loads",domain.configure("res://data/geography/domain/osm-2026-10-27","82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834",_hash(raw))):finish();return
	for entry:Dictionary in domain.provider_descriptors():context.register_provider(entry.kind,entry.provider_id,entry.source_reference)
	context.register_provider("physics","partial-native/v1","Actual owned source-positioned partial service floor collision")
	runtime=Runtime.new();add_child(runtime)
	if not check("production runtime binds actual domain/context",runtime.configure(frame,context,domain.observe)):finish();return
	var basis:Basis=Basis(Vector3(Reference.DATA.axis_south_xz[0],0,Reference.DATA.axis_south_xz[1]),Vector3.UP,Vector3(Reference.DATA.axis_bayward_xz[0],0,Reference.DATA.axis_bayward_xz[1]))
	for level:String in ["B2","B2M","B1"]:
		var record:Dictionary=Inventory.floor_record(selected_tower+"-"+level)
		var module:Node3D=Program.new() if level=="B1" else Partial.new();add_child(module)
		var projected:Dictionary=frame.to_local(_anchor(record));module.global_transform=Transform3D(basis,projected.position)
		record.geometry.storey_height_m=5.0 if level=="B1" else 2.5
		if not check("real original geometry builds "+String(record.id),module.build(record).get("built",false),module.report()):finish();return
		modules[level]=module
	await frames(5)
	for level:String in modules:
		if not _native_register(modules[level],modules[level].floor_record):finish();return
	var mezz:Node3D=modules.B2M;var lower:Node3D=modules.B2;var upper:Node3D=modules.B1
	check("central mezzanine has real void rather than hidden full slab",ray(mezz.to_global(Vector3(0,.4,0)),mezz.to_global(Vector3(0,-.4,0))).is_empty())
	check("lower central service base exists beneath open mezz void",not ray(lower.to_global(Vector3(0,.4,0)),lower.to_global(Vector3(0,-.4,0))).is_empty())
	for module:Node3D in [lower,mezz]:
		check("every required named service program remains physically furnished",module.program_coverage.size()==8 and module.rooms.size()==5 and module.furnishings.size()>=20)
		for wing:Dictionary in module.get("_plan").wings:
			var point:=Vector3(0,0,wing.corridor_center_z)
			var hit:Dictionary=ray(module.to_global(point+Vector3.UP*.1),module.to_global(point+Vector3.UP*2.6))
			check("actual low corridor ceiling preserves2.30m headroom",not hit.is_empty() and absf(module.to_local(hit.position).y-2.3)<.02)
	if not prepare_player():finish();return
	player.source_world_runtime=runtime;player.uses_source_world=true
	player.collision_layer=player_layer;player.collision_mask=mask;player.show();player.process_mode=Node.PROCESS_MODE_INHERIT
	player.respawn_at(lower.to_global(_corridor(lower,"east"))+Vector3.UP*.08,0)
	if not check("full production capsule binds actual source runtime",runtime.bind_player(player)):finish();return
	await frames(30);previous=player.global_position;travel=0;max_step=0;minimum_y=INF;maximum_y=-INF;tracking=true
	if not await _rooms_and_doors(lower):finish();return
	if not await _stair_between(lower,mezz,true):finish();return
	if not await _rooms_and_doors(mezz):finish();return
	if not await _stair_between(mezz,upper,true):finish();return
	var receiving:Dictionary=runtime.inspect_player(player)
	check("actual native upper B1 receiving floor supports player",receiving.get("ok",false) and receiving.support.floor_id==selected_tower+"-B1" and player.is_on_floor() and Game.death_count==0,str(receiving))
	if not await _stair_between(mezz,upper,false):finish();return
	if not await _stair_between(lower,mezz,false):finish();return
	check("continuous low service rooms/crosslinks/Ustairs return without teleport",travel>100 and max_step<.5 and Game.death_count==0 and player.global_position.y<1.0)
	measurements={"tower":selected_tower,"distance_m":travel,"max_step_m":max_step,"native_room_doors":native_e_doors,"gait_records":gait_records,"actual_source_basis":basis,"source_origin":frame.metadata().source_origin_xyz,"lower":lower.report(),"mezzanine":mezz.report(),"upper":upper.report(),"guarded_lift_and_stair_receiving_integration_tested":false}
	finish()

func finish()->void:
	if finished:return
	finished=true;tracking=false
	for action:String in ["move_forward","move_back","move_left","move_right","sprint","walk","jump","interact"]:
		if InputMap.has_action(action):Input.action_release(action)
	var result:Dictionary={"schema":"partial_mezzanine_native_fixture_v1","checks":checks,"failed":failures.size(),"failures":failures,"elapsed_s":float(Time.get_ticks_msec()-started_ms)/1000.0,"measurements":measurements,"six_recipes_statically_planned":true,"selected_actual_source_tower":selected_tower,"one_initial_actor_setup":true,"guarded_transport_integrated":false,"all_six_recipes_runtime_verified":false,"visual_fidelity_accepted":false,"full_building_completed":false}
	print("[partial-mezzanine] RESULT ",JSON.stringify(result))
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--partial-report="):
			var path:=arg.trim_prefix("--partial-report=");DirAccess.make_dir_recursive_absolute(path.get_base_dir());var file:=FileAccess.open(path,FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify(result,"\t")+"\n");file.close()
	Sfx.shutdown_audio();get_tree().quit(0 if failures.is_empty() else 1)
