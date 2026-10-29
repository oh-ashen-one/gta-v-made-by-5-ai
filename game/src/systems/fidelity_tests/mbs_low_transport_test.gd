extends "res://src/systems/fidelity_tests/mbs_guest_floor_test.gd"
## Coupled actual low FloorStack + Hotel + native stair/cabin interfaces.
## One initial actor setup, no later pose/velocity/reparent writes.
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const Stack = preload("res://src/world/mbs_interior/floor_stack.gd")
const Hotel = preload("res://src/world/mbs_interior/hotel.gd")
const Cabins = preload("res://src/world/mbs_interior/cabins.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const LOW = "T3-B2"
const MEZZ = "T3-B2M"
const NORMAL = "T3-B1"
const SHAFT = "T3-east-guest_lift"
var frame:RefCounted
var context:RefCounted
var domain:RefCounted
var runtime:Node3D
var stack:Node3D
var hotel:Node3D
var lift:Node3D
var stairs:Node3D
var started_low:=0
var evidence:Dictionary={}
var native_actions:Array[Dictionary]=[]
var riding:=false
var ride_samples:=0
var ride_supported:=0
var peak_platform_velocity:=0.0
var peak_cabin_offset:=0.0

func _ready()->void:
	if not "--qa-session" in OS.get_cmdline_user_args():get_tree().quit(2);return
	started_low=Time.get_ticks_msec()
	get_tree().create_timer(1100.0,true,false,true).timeout.connect(func():
		if not finished:check("bounded native low transport",false);finish())
	run.call_deferred()

func _hash(text:String)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(text.to_utf8_buffer());return h.finish().hex_encode()

func _physics_process(delta:float)->void:
	super._physics_process(delta)
	if not riding or not is_instance_valid(lift) or not is_instance_valid(player):return
	ride_samples+=1
	if player.is_on_floor():ride_supported+=1
	peak_platform_velocity=maxf(peak_platform_velocity,absf(player.get_platform_velocity().y))
	peak_cabin_offset=maxf(peak_cabin_offset,absf(player.global_position.y-lift.cabin.global_position.y))

func _until(predicate:Callable,label:String,seconds:float=90.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while not predicate.call() and Time.get_ticks_msec()<deadline and not finished:await get_tree().physics_frame
	return check(label,not finished and bool(predicate.call()))

func _press(target:Node3D,label:String)->bool:
	if not await settle_native_motion(label):return false
	Input.action_release("interact");await frames(6);await get_tree().process_frame;await get_tree().process_frame
	if not check("native exact E target/LOS "+label,player._interaction_target()==target and player._interaction_visible(target)):return false
	var before:=player.global_position;var process_start:=Engine.get_process_frames()
	Input.action_press("interact");await frames(6);await get_tree().process_frame;await get_tree().process_frame
	Input.action_release("interact");await frames(5);await get_tree().process_frame;await get_tree().process_frame
	var action:Dictionary={"label":label,"target":String(target.name),"before":before,"after":player.global_position,"movement_m":player.global_position.distance_to(before),"held_process_frames":Engine.get_process_frames()-process_start}
	native_actions.append(action)
	return check("native action retains actual actor pose "+label,action.movement_m<.02 and action.held_process_frames>=2,str(action))

func _gate_geometry(owner:String,lane:String)->Dictionary:
	for entry:Dictionary in stairs.geometry_descriptor(owner).get("gates",[]):
		if entry.wing=="east" and entry.lane==lane:return entry
	return {}

func _landing(id:String)->Vector3:
	var floor:Node3D=stack.get_floor(id)
	for portal:Dictionary in floor.portals:
		if portal.kind=="guest_lift" and portal.wing=="east":return floor.to_global(portal.landing)
	return Vector3(INF,INF,INF)

func _cabin_centre(id:String)->Vector3:
	var descriptor:Dictionary=lift.get("_descriptor")
	return lift.to_global(Vector3(descriptor.center_xz[0],Inventory.floor_record(id).elevation_m,descriptor.center_xz[1]))

func _own_shape(body:StaticBody3D,name:String,at:Vector3,size:Vector3)->CollisionShape3D:
	var shape:=CollisionShape3D.new();shape.name=name;var box:=BoxShape3D.new();box.size=size;shape.shape=box;shape.position=at;body.add_child(shape);return shape

func _panel_destination(id:String)->bool:
	# Stand at the real panel side of the cabin. At the mathematical centre
	# an already-open hall leaf can be nearer than the panel; never force target.
	var sign:float=(lift.get("_descriptor") as Dictionary).entry_sign
	if not await walk_to(lift.cabin.to_global(Vector3(.45,0,-sign*.40)),.16):return false
	if not await _press(lift.panel,"actual cabin destination panel"):return false
	if not check("native E opens actual panel",bool(lift.get("_ui_open"))):return false
	var button:Button=(lift.get("_floor_buttons") as Dictionary)[id]
	button.grab_focus();await get_tree().process_frame
	if not check("real destination button receives GUI focus",button.has_focus()):return false
	var down:=InputEventKey.new();down.keycode=KEY_ENTER;down.physical_keycode=KEY_ENTER;down.pressed=true;Input.parse_input_event(down)
	await get_tree().process_frame;await get_tree().process_frame
	var up:=InputEventKey.new();up.keycode=KEY_ENTER;up.physical_keycode=KEY_ENTER;up.pressed=false;Input.parse_input_event(up)
	await get_tree().process_frame;await get_tree().process_frame
	var report:Dictionary=lift.report()
	return check("native GUI selects actual requested stop "+id,not bool(lift.get("_ui_open")) and (report.target_floor_id==id or report.queue.has(id)))

func _probe_has(label:String,shape_name:String)->bool:
	var probe:Dictionary=lift.report().last_door_probe
	for segment:Dictionary in probe.get("segments",[]):
		if segment.label==label:
			for hit:Dictionary in segment.hits:
				if hit.get("shape_name","")==shape_name:return true
	return false

func _leaf_dimensions(body:Node3D)->Dictionary:
	var collision:=0.0;var visible:=0.0
	for child:Node in body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:collision=maxf(collision,child.shape.size.y)
		if child is MeshInstance3D and child.mesh!=null:visible=maxf(visible,child.mesh.get_aabb().size.y)
	return {"collision_height_m":collision,"visible_height_m":visible}

func _stair(owner:String)->Dictionary:
	for portal:Dictionary in stack.get_floor(owner).portals:
		if portal.kind=="stair" and portal.wing=="east":return portal
	return {}

func _open_gate(geometry:Dictionary,label:String)->bool:
	var door:Node3D=stairs.doors[geometry.gate_id]
	if not door.opened:
		if not await _press(door,label):return false
		if not door.opened:
			if not await _until(func():return stairs.report().gates[geometry.gate_id].ready,"actual complete floor groups become ready "+label):return false
			if not await _press(door,label+" after actual group commit"):return false
	return await _until(func():return door.opened and absf(door.motion_angle-door.swing_delta)<.002,"actual native gate reaches open pose "+label)

func _descend(owner:String,probe_header:bool=false)->bool:
	var lower:Node3D=stack.get_floor(owner);var flight:Dictionary=_stair(owner);var top:Dictionary=_gate_geometry(owner,"upper_return")
	var upper_id:String=stairs.geometry_descriptor(owner).upper_id;var upper:Node3D=stack.get_floor(upper_id)
	candidate=upper
	var receiving:Vector3=upper.to_local(lower.to_global(Vector3(top.opening_center_x_local_m,top.rise_m,float(top.gate_plane_z_local_m)-float(top.side)*2.30)))
	if not await walk_public_to(receiving,"east"):return false
	var door:Node3D=stairs.doors[top.gate_id]
	if probe_header:
		var body:StaticBody3D=upper.get_node("ProgramFloorSolidCollision")
		var header:=_own_shape(body,"QaUnexpectedRealStairHeader",Vector3(top.opening_center_x_local_m,2.07,float(top.gate_plane_z_local_m)-float(top.side)*.35),Vector3(.80,.10,.45))
		await frames(4)
		if not await _press(door,"low stair leaf with real header intrusion"):return false
		if not door.opened:
			if not await _until(func():return stairs.report().gates[top.gate_id].ready,"low leaf dependency groups prepared"):return false
			if not await _press(door,"low header probe after actual readiness"):return false
		if not await _until(func():return stairs.report().gates[top.gate_id].state=="OPENING_HOLD_BLOCKED_GEOMETRY","same-body real stair header holds native motion"):return false
		if not check("real stair header body remains in native query",stairs.report().gates[top.gate_id].last_static_probe.blocking_body_ids.has(body.get_instance_id()) and absf(door.motion_angle)<1.4):return false
		evidence["stair_header_probe"]=stairs.report().gates[top.gate_id].last_static_probe
		header.queue_free();await frames(4)
	if not await _open_gate(top,"guarded top "+owner):return false
	if not await walk_to(lower.to_global(flight.upper),.18):return false
	candidate=lower
	for index in range(flight.walk_route.size()-1,1,-1):
		walk_stage="real guarded2.5 U descent/"+owner+"/"+str(index)
		if not await walk_to(lower.to_global(flight.walk_route[index]),.22):return false
	var below:String=""
	for id:String in stack.adjacent_floor_ids(owner):
		if Inventory.floor_record(id).elevation_m<lower.floor_record.elevation_m:below=id
	var entry:Dictionary=_gate_geometry(below,"lower_departure")
	if not check("preceding-floor lower entry is actual bound geometry "+owner,not entry.is_empty()):return false
	var below_node:Node3D=stack.get_floor(below)
	var before:Vector3=below_node.to_global(Vector3(entry.opening_center_x_local_m,entry.rise_m,float(entry.gate_plane_z_local_m)+float(entry.side)*.62))
	if not await walk_to(before,.12):return false
	if not await _open_gate(entry,"lower receiving entry "+owner):return false
	for index in range(1,-1,-1):
		walk_stage="guarded lower exit/"+owner
		if not await walk_to(lower.to_global(flight.walk_route[index]),.22):return false
	return true

func run()->void:
	Game.simulation_paused=false;Game.mode=Game.MODE_FOOT;Game.health=Game.MAX_HEALTH;Game.death_count=0
	var raw:=FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json");var manifest:Dictionary=JSON.parse_string(raw)
	var tower:Dictionary=Reference.DATA.towers[0]
	frame=Frame.new()
	if not check("actual T3 source origin and uncompressed basis",frame.configure(manifest.georeference,[tower.centroid_world_xz[0],-10.0,tower.centroid_world_xz[1]],_hash(raw),{"status":"staging","reference":"Reconstructed MBS relative basement elevations; no survey claim"})):finish();return
	context=Context.new();var profile:Dictionary={"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":cos(deg_to_rad(52.0)),"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}
	if not check("one native context configures",context.configure(frame,_hash(FileAccess.get_file_as_string("res://src/world/mbs_interior/hotel.gd")+FileAccess.get_file_as_string("res://src/world/mbs_interior/cabins.gd")+FileAccess.get_file_as_string("res://src/world/mbs_interior/stair_gates.gd")),_hash("Reconstructed low basement datum"),profile,get_world_3d())):finish();return
	domain=Domain.new()
	if not check("actual country source data",domain.configure("res://data/geography/domain/osm-2026-10-27","82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834",_hash(raw))):finish();return
	for entry:Dictionary in domain.provider_descriptors():context.register_provider(entry.kind,entry.provider_id,entry.source_reference)
	context.register_provider("physics","low-transport/native","Actual source low floor group, shaft, native door blockers and production Player")
	runtime=Runtime.new();add_child(runtime)
	if not check("common native runtime",runtime.configure(frame,context,domain.observe)):finish();return
	stack=Stack.new();add_child(stack)
	if not check("actual transformed low factory FloorStack",stack.configure(frame,context,runtime,0.0,"Reconstructed inventory L1=0, actual source horizontal placement",{"max_active_floors":8,"max_pending_requests":3,"auto_stream":false})):finish();return
	var legacy:Dictionary=Cabins.inventory_descriptor("T3","east","guest_lift","T3-L5").descriptor
	legacy.stops=legacy.stops.filter(func(stop:Dictionary):return stop.floor_id in ["T3-L5","T3-L6"])
	var normalized:Dictionary=Cabins.validate_descriptor(legacy)
	check("normal six-field stop descriptor remains backward compatible",normalized.valid and normalized.descriptor.stops[0].receiving_door_height_m==2.35)
	hotel=Hotel.new();add_child(hotel)
	var built:Dictionary=await hotel.build(frame,context,runtime,stack,0.0,[{"tower":"T3","wing":"east","kind":"guest_lift","initial_floor_id":LOW}])
	if not check("actual source height-aware Hotel/shaft builds",built.get("built",false),str(built)):finish();return
	lift=hotel.get_cabin(SHAFT);stairs=hotel.get("_stairs")
	# B1's normal +/-1 request gives local B2M collision but not B2M's full
	# B2/B2M/B1 group. A local generation must never masquerade as ready.
	var cold:Dictionary=await stack.ensure_floor(NORMAL)
	if not check("actual cold B1 request completes its own neighbourhood",cold.ready and stack.floor_ready(NORMAL)):finish();return
	if not await _until(func():return not _gate_geometry(MEZZ,"upper_return").is_empty(),"cold B1 incoming gate binds real local lower geometry"):finish();return
	var cold_gate:Dictionary=_gate_geometry(MEZZ,"upper_return")
	if not check("locally committed B2M remains group-unready at cold B1",not stack.floor_ready(MEZZ) and not String(stack.ready_for_floor(MEZZ).collision_generation).is_empty() and not stairs.report().gates[cold_gate.gate_id].ready):finish();return
	if not prepare_player():finish();return
	var mezz:Node3D=stack.get_floor(MEZZ)
	var initial:Vector3=mezz.to_global(Vector3(cold_gate.opening_center_x_local_m,cold_gate.rise_m,float(cold_gate.gate_plane_z_local_m)-float(cold_gate.side)*2.30))
	player.source_world_runtime=runtime;player.uses_source_world=true;player.collision_layer=player_layer;player.collision_mask=mask;player.process_mode=Node.PROCESS_MODE_INHERIT;player.show();player.respawn_at(initial+Vector3.UP*.08,0)
	if not check("actual full-size Player binds source",runtime.bind_player(player)):finish();return
	await frames(30);previous=player.global_position;travel=0;max_step=0;minimum_y=INF;maximum_y=-INF;tracking=true
	if not await _press(stairs.doors[cold_gate.gate_id],"cold B1 native request for lower complete group"):finish();return
	if not check("cold gate does not open from local generation alone",not stairs.doors[cold_gate.gate_id].opened):finish();return
	if not await _until(func():return stack.floor_ready(MEZZ) and stairs.report().gates[cold_gate.gate_id].ready,"native request prepares real B2M dependencies without deadlock"):finish();return
	var receiver:Node3D=stack.get_floor(MEZZ).doors[MEZZ+"-east-guest_lift"]
	var receiver_shape:CollisionShape3D=receiver.get_node("MatchingLowDoorLeaf")
	var receiver_box:BoxShape3D=receiver_shape.shape as BoxShape3D
	var original_size:Vector3=receiver_box.size
	receiver_box.size=Vector3(original_size.x,2.25,original_size.z);await frames(3)
	var mismatch:Dictionary=lift._readiness(MEZZ)
	check("actual receiver shape mismatch refuses before opening",not mismatch.get("ready",false),str(mismatch))
	evidence["actual_receiver_shape_mismatch"]=mismatch
	receiver_box.size=original_size;await frames(3)
	if not check("restored actual low receiver geometry revalidates generation",lift._readiness(MEZZ).get("ready",false)):finish();return
	for id:String in [LOW,MEZZ,NORMAL]:
		for gate:Node3D in (lift.get("_shaft_gates") as Dictionary)[id]:
			var dimensions:Dictionary=_leaf_dimensions(gate)
			var expected_leaf:float=2.33 if id==NORMAL else 2.08
			check("receiving grille mesh/collider fits actual opening "+id,absf(dimensions.collision_height_m-expected_leaf)<.001 and absf(dimensions.visible_height_m-expected_leaf)<.001,str(dimensions))
	for gate:Node3D in lift.get("_cabin_gates"):
		var dimensions:Dictionary=_leaf_dimensions(gate)
		check("cabin side retained normal2.35 leaf height",absf(dimensions.collision_height_m-2.35)<.001 and absf(dimensions.visible_height_m-2.35)<.001)
	if not await _descend(MEZZ):finish();return
	if not await _descend(LOW,true):finish();return
	if not check("guarded basement traversal reached real low source floor",runtime.inspect_player(player).support.floor_id==LOW and stack.floor_ready(LOW)):finish();return
	for owner:String in ["T3-B3",LOW,MEZZ]:
		var geometry:Dictionary=_gate_geometry(owner,"upper_return");var expected:float=2.35 if owner==MEZZ else 2.10
		var gate_door:Node3D=stairs.doors[geometry.gate_id];var shape:CollisionShape3D=gate_door.get_node("VisibleStairFireDoorLeaf")
		if not check("destination-specific native stair height "+owner,absf(float(geometry.height_m)-expected)<.001 and absf((shape.shape as BoxShape3D).size.y-expected)<.001):finish();return
	var lower:Node3D=stack.get_floor(LOW);candidate=lower
	if not await walk_public_to(lower.to_local(_landing(LOW)),"east"):finish();return
	var lower_hall:Node3D=lower.doors[LOW+"-east-guest_lift"];var low_before:=player.global_position
	if not await _press(lower_hall,"native low B2 cabin call"):finish();return
	if not await _until(func():return lift.report().state=="OPEN" and lift.report().current_floor_id==LOW and lift.report().gate_fraction>.999,"low B2 receiving opening physically clears"):finish();return
	await frames(20)
	if not check("low B2 full landing action never pushes waiting actor",player.global_position.distance_to(low_before)<.02):finish();return
	if not await walk_to(_cabin_centre(LOW),.18):finish();return
	if not await _panel_destination(MEZZ):finish();return
	riding=true
	if not await _until(func():return lift.report().state=="OPEN" and lift.report().current_floor_id==MEZZ and lift.report().gate_fraction>.999,"actual low-to-low2.5m cabin ride"):finish();return
	riding=false
	if not await walk_to(_landing(MEZZ),.18):finish();return
	if not check("full capsule exits actual2.10 mezz opening",runtime.inspect_player(player).support.floor_id==MEZZ):finish();return
	candidate=mezz
	if not await walk_to(_cabin_centre(MEZZ),.18):finish();return
	var enclosure:StaticBody3D=lift.get_node("ClosedShaftEnclosure");var desc:Dictionary=lift.get("_descriptor");var sign:float=desc.entry_sign;var y:float=Inventory.floor_record(MEZZ).elevation_m
	var cabin_header:=_own_shape(enclosure,"QaActualCabinSideHeader",Vector3(desc.center_xz[0],y+2.25,desc.center_xz[1]+sign*(Cabins.DEPTH*.5-.24)),Vector3(.60,.10,.12))
	await frames(4)
	if not await _panel_destination(NORMAL):finish();return
	if not await _until(func():return _probe_has("cabin-side-tall-clearance","QaActualCabinSideHeader"),"tall cabin-side header retained in native split query"):finish();return
	check("cabin side blocker holds actual aligned doors without motion",lift.report().state=="OPEN" and lift.report().current_floor_id==MEZZ and not lift.report().last_door_probe.owned_static_enclosure_excluded)
	evidence["cabin_side_header_probe"]=lift.report().last_door_probe
	cabin_header.queue_free();await frames(4)
	var receiving_header:=_own_shape(enclosure,"QaActualReceivingHeaderIntrusion",Vector3(desc.center_xz[0],y+2.04,desc.center_xz[1]+sign*(Cabins.DEPTH*.5+.08)),Vector3(.60,.10,.18))
	await frames(4)
	if not await _until(func():return _probe_has("receiving-opening-clearance","QaActualReceivingHeaderIntrusion"),"real low receiving header remains a positive obstruction"):finish();return
	evidence["receiving_header_probe"]=lift.report().last_door_probe
	check("low receiver blockage cannot force doors closed or bypass header",lift.report().state=="OPEN" and lift.report().current_floor_id==MEZZ)
	receiving_header.queue_free();await frames(4);riding=true
	if not await _until(func():return lift.report().state=="OPEN" and lift.report().current_floor_id==NORMAL and lift.report().gate_fraction>.999,"actual2.5m native ride reaches normal2.35 receiver",120):finish();return
	riding=false
	check("native platform carries full Player without actor assignment",ride_samples>30 and float(ride_supported)/maxf(1.0,ride_samples)>.90 and peak_platform_velocity>.2 and peak_cabin_offset<.16)
	if not await walk_to(_landing(NORMAL),.18):finish();return
	var support:Dictionary=runtime.inspect_player(player)
	check("normal B1 exit is actual source floor support",support.get("ok",false) and support.support.floor_id==NORMAL and player.is_on_floor(),str(support))
	var occupied:Dictionary=await stack.unload_floor(NORMAL)
	check("occupied receiving floor and group cannot unload",not occupied.ok)
	if not await walk_to(_landing(NORMAL)+Vector3(0,0,float(desc.entry_sign)*1.30),.18):finish();return
	runtime.retire_region("mbs-shaft/"+SHAFT)
	var stopped:float=lift.report().commanded_y_m;lift.request_floor(MEZZ);await frames(120)
	check("withdrawn real shaft lease keeps cabin closed and stationary",not hotel._ready_for_cabin(SHAFT,MEZZ).travel_ready and absf(lift.report().commanded_y_m-stopped)<.001 and lift.report().gate_fraction<.001)
	check("one initial spawn and continuous source low traversal",travel>50 and max_step<.5 and Game.death_count==0)
	evidence["native_actions"]=native_actions;evidence["hotel"]=hotel.report();evidence["distance_m"]=travel;evidence["max_step_m"]=max_step;evidence["ride_samples"]=ride_samples;evidence["ride_supported"]=ride_supported;evidence["peak_platform_velocity"]=peak_platform_velocity;evidence["peak_cabin_offset"]=peak_cabin_offset
	finish()

func finish()->void:
	if finished:return
	finished=true;tracking=false;riding=false
	for action:String in ["move_forward","move_back","move_left","move_right","sprint","walk","jump","interact"]:
		if InputMap.has_action(action):Input.action_release(action)
	print("[low-transport] RESULT ",JSON.stringify({"schema":"low_transport_native_fixture_v1","checks":checks,"failed":failures.size(),"failures":failures,"elapsed_s":float(Time.get_ticks_msec()-started_low)/1000.0,"evidence":evidence,"initial_player_spawns":1,"later_actor_pose_or_reparent_writes":0,"normal_legacy_native_suite_tested":false,"all_tower_low_transports_tested":false,"visual_or_whole_MBS_acceptance":false}))
	Sfx.shutdown_audio();get_tree().quit(0 if failures.is_empty() else 1)
