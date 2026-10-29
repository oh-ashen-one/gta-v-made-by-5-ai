extends Node3D
## Local furnished guest-floor fixtures. Never full-building/city/as-built proof.
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const GuestFloor = preload("res://src/world/mbs_interior/guest_floor.gd")
var checks:=0
var failures:Array[String]=[]
var candidate:Node3D
var receiving:Node3D
var player:Player
var capsule:Shape3D
var capsule_transform:=Transform3D.IDENTITY
var mask:=0
var player_layer:=0
var finished:=false
var tracking:=false
var travel:=0.0
var max_step:=0.0
var maximum_y:=-INF
var minimum_y:=INF
var previous:=Vector3.ZERO
var fixture_results:Array[Dictionary]=[]
var transition_calls:Dictionary={}
var native_e_doors:Array[String]=[]
var motion_trace:Array[Dictionary]=[]
var walk_target:=Vector3.ZERO
var walk_stage:=""
var walk_phase:=""
var gait_records:Array[Dictionary]=[]
var public_sprint_leg:=false
var lift_monitor:=false
var lift_previous:=Vector3.ZERO
var lift_peak_residual:=0.0
var lift_peak_step:=0.0
var lift_sample_count:=0
var lift_input_clear:=true
var lift_trace:Array[Dictionary]=[]

func _ready()->void:
	if not "--qa-session" in OS.get_cmdline_user_args():
		push_error("Guest-floor test requires isolated --qa-session")
		get_tree().quit(2)
		return
	get_tree().create_timer(900.0,true,true).timeout.connect(func():
		if not finished:
			check("bounded guest-floor verification",false,"900s")
			finish())
	run.call_deferred()

func check(label:String,ok:bool,detail:String="")->bool:
	checks+=1
	print("[mbs-guest-floor] %s %s %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)
	return ok

func frames(count:int)->void:
	for i in count:await get_tree().physics_frame

func _physics_process(delta:float)->void:
	if not tracking:return
	var p:=player.global_position
	travel+=p.distance_to(previous)
	max_step=maxf(max_step,p.distance_to(previous))
	maximum_y=maxf(maximum_y,p.y)
	minimum_y=minf(minimum_y,p.y)
	previous=p
	if lift_monitor:
		var actual_step:=p-lift_previous
		var expected_step:=player.velocity*delta
		var residual:float=(actual_step-expected_step).length()
		lift_peak_residual=maxf(lift_peak_residual,residual)
		lift_peak_step=maxf(lift_peak_step,actual_step.length())
		lift_sample_count+=1
		for action:String in ["move_forward","move_back","move_left","move_right","jump"]:
			lift_input_clear=lift_input_clear and Input.get_action_strength(action)==0.0
		lift_trace.append({"tick":Engine.get_physics_frames(),"position":p,"step":actual_step,"resolved_velocity":player.velocity,"expected_step":expected_step,"residual_m":residual})
		if lift_trace.size()>12:lift_trace.pop_front()
		lift_previous=p
	if Engine.get_physics_frames()%6==0:
		motion_trace.append({"tick":Engine.get_physics_frames(),"stage":walk_stage,"phase":walk_phase,"position":p,"target":walk_target,"yaw":player.yaw,"velocity":player.velocity,"floor":player.is_on_floor(),"forward":Input.get_action_strength("move_forward"),"sprint":Input.get_action_strength("sprint"),"controller":player.get_meta("_qa_motion_state",{}).duplicate(true)})
		if motion_trace.size()>12:motion_trace.pop_front()

func ray(a:Vector3,b:Vector3)->Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))

func body_pose(body:CollisionObject3D)->Dictionary:
	var result:Dictionary={"node":String(body.name),"node_origin":body.global_position,"node_euler":body.global_basis.get_euler()}
	if body is PhysicsBody3D:
		var physical:Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		result["physics_origin"]=physical.origin
		result["physics_euler"]=physical.basis.get_euler()
	return result

func hit_details(hits:Array[Dictionary])->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for hit:Dictionary in hits:
		var body:CollisionObject3D=hit.get("collider") as CollisionObject3D
		if body==null:continue
		var detail:Dictionary=body_pose(body)
		var owner:Node3D=body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape))) as Node3D
		if owner!=null:
			detail["shape_name"]=String(owner.name)
			detail["shape_global_transform"]=owner.global_transform
			detail["shape_local_transform"]=owner.transform
			if owner is CollisionShape3D:
				var resource:Shape3D=(owner as CollisionShape3D).shape
				detail["shape_class"]=resource.get_class()
				if resource is BoxShape3D:detail["box_size"]=(resource as BoxShape3D).size
		result.append(detail)
	return result

func capsule_clear(a:Vector3,b:Vector3,diagnostic_label:String="")->bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.transform=Transform3D(Basis.IDENTITY,a)*capsule_transform
	query.collision_mask=mask
	query.margin=maxf(.01,player.safe_margin)
	var initial:Array[Dictionary]=get_world_3d().direct_space_state.intersect_shape(query,16)
	if not initial.is_empty():
		if not diagnostic_label.is_empty():print("[mbs-guest-floor] CAPSULE_INITIAL_BLOCK ",JSON.stringify({"label":diagnostic_label,"transform":query.transform,"hits":hit_details(initial)}))
		return false
	query.motion=b-a
	var fraction:PackedFloat32Array=get_world_3d().direct_space_state.cast_motion(query)
	var clear:bool=fraction.size()==2 and fraction[0]>.999
	if not clear and not diagnostic_label.is_empty():
		var sample:float=minf(1.0,float(fraction[1])+.001) if fraction.size()==2 else 0.0
		query.transform.origin+=(b-a)*sample
		query.motion=Vector3.ZERO
		var blocked:Array[Dictionary]=get_world_3d().direct_space_state.intersect_shape(query,16)
		print("[mbs-guest-floor] CAPSULE_SWEEP_BLOCK ",JSON.stringify({"label":diagnostic_label,"from":a,"to":b,"fraction":fraction,"sample_transform":query.transform,"hits":hit_details(blocked)}))
	return clear

## Native non-mutating diagnostics: these query the production body RID and
## its real shapes at a supplied pose. No actor/collider transform is assigned.
func native_motion_diagnostic(label:String,pose:Transform3D,motion:Vector3)->Dictionary:
	var parameters:=PhysicsTestMotionParameters3D.new()
	parameters.from=pose
	parameters.motion=motion
	parameters.margin=player.safe_margin
	parameters.max_collisions=16
	parameters.recovery_as_collision=false
	var result:=PhysicsTestMotionResult3D.new()
	var blocked:=PhysicsServer3D.body_test_motion(player.get_rid(),parameters,result)
	var contacts:Array[Dictionary]=[]
	for index in result.get_collision_count():
		var body:=result.get_collider(index) as CollisionObject3D
		var shape_index:=result.get_collider_shape(index)
		var detail:Dictionary={"collider_id":result.get_collider_id(index),"collider_shape_index":shape_index,"local_shape_index":result.get_collision_local_shape(index),"normal":result.get_collision_normal(index),"point":result.get_collision_point(index),"depth_m":result.get_collision_depth(index)}
		if body!=null:
			detail.merge(body_pose(body))
			var shape_owner:Node3D=body.shape_owner_get_owner(body.shape_find_owner(shape_index)) as Node3D
			if shape_owner!=null:
				detail["shape_name"]=String(shape_owner.name)
				detail["shape_global_transform"]=shape_owner.global_transform
				if shape_owner is CollisionShape3D and (shape_owner as CollisionShape3D).shape is BoxShape3D:
					detail["box_size"]=((shape_owner as CollisionShape3D).shape as BoxShape3D).size
		contacts.append(detail)
	# Shape overlap supplements body-test recovery/floor contacts with ALL
	# nearby actual colliders, using the unchanged stricter QA query margin.
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.transform=pose*capsule_transform
	query.collision_mask=mask
	query.margin=maxf(.01,player.safe_margin)
	query.exclude=[player.get_rid()]
	var overlaps:=get_world_3d().direct_space_state.intersect_shape(query,32)
	var snapshot:Dictionary={"label":label,"pose":pose,"motion":motion,"body_safe_margin_m":parameters.margin,"body_blocked":blocked,"safe_fraction":result.get_collision_safe_fraction(),"unsafe_fraction":result.get_collision_unsafe_fraction(),"travel":result.get_travel(),"remainder":result.get_remainder(),"native_contacts":contacts,"capsule_shape":capsule.get_class(),"capsule_transform":capsule_transform,"strict_query_margin_m":query.margin,"overlap_shapes":hit_details(overlaps),"actor_pose_unchanged":player.global_transform}
	print("[mbs-guest-floor] NATIVE_MOTION_DIAGNOSTIC ",JSON.stringify(snapshot))
	return snapshot

func retained_west_entry_probe()->void:
	# Exact failed R7 pose/request, not a setup relocation. Capsule symmetry
	# makes current yaw irrelevant to its footprint; no body pose is changed.
	var before:=player.global_transform
	var pose:=player.global_transform
	pose.origin=Vector3(-18.69701,-.024059,6.215035)
	native_motion_diagnostic("retained R7 west:1 stop/request",pose,Vector3(-2.775994,-.5,6.207565)/float(Engine.physics_ticks_per_second))
	var horizontal_target:=Vector3(-19.27164,pose.origin.y,7.5)
	native_motion_diagnostic("retained R7 west:1 stop/target-horizontal",pose,(horizontal_target-pose.origin).normalized()*.15)
	check("retained failure native probes never relocate actor",player.global_transform.is_equal_approx(before))

func door_snapshot(door:Node3D)->Dictionary:
	var detail:=body_pose(door as CollisionObject3D)
	detail.merge({"id":door.get("door_id"),"opened":door.get("opened"),"commanded_angle":door.get("motion_angle"),"base_angle":door.get("base_angle"),"swing_delta":door.get("swing_delta"),"hinge_local":door.get("hinge_origin"),"node_local_transform":door.transform,"sync_to_physics":door.get("sync_to_physics")})
	return detail

func prepare_player()->bool:
	player=Player.new()
	player.set_meta("_qa_motion_probe",true)
	player.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(player)
	mask=player.collision_mask
	player_layer=player.collision_layer
	player.collision_layer=0
	player.collision_mask=0
	player.hide()
	for child:Node in player.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			capsule=(child as CollisionShape3D).shape
			capsule_transform=(child as CollisionShape3D).transform
			break
	return check("actual production capsule and transform reused",capsule is CapsuleShape3D and is_equal_approx((capsule as CapsuleShape3D).radius,.36) and is_equal_approx((capsule as CapsuleShape3D).height,1.75) and capsule_transform.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(0,.9,0))) and not player.can_process())

func run()->void:
	Game.simulation_paused=false
	Game.mode=Game.MODE_FOOT
	Game.health=Game.MAX_HEALTH
	Game.death_count=0
	var inventory:=Inventory.validate_inventory()
	if not check("whole deterministic inventory validates",inventory.get("valid",false),str(inventory)):
		finish();return
	check("1850normalized units including775suites",inventory.units==1850 and inventory.suites==775)
	check("every guest floor has a reusable factory plan",Inventory.guest_floor_ids().size()==159)
	var variants:Dictionary={}
	for id:String in Inventory.guest_floor_ids():
		var plan:Dictionary=GuestFloor.plan(Inventory.floor_record(id))
		if not check("full furnished-floor recipe "+id,plan.get("valid",false),str(plan.get("error",""))):
			finish();return
		for cell:Dictionary in plan.rooms:
			if not cell.is_suite:continue
			var label:String=String(cell.wing)+":"+str(int(cell.bedrooms))
			var clearance:=INF
			for bedroom:Dictionary in cell.bedroom_layouts:
				clearance=minf(clearance,float(bedroom.clear_window_aisle_m))
				if not check("full kingbed and window aisle "+String(cell.id)+" bedroom"+str(bedroom.index),is_equal_approx(float(bedroom.bed_width_m),1.95) and float(bedroom.clear_window_aisle_m)>=.74):finish();return
			if not variants.has(label) or clearance<float(variants[label].clearance):variants[label]={"floor_id":id,"unit_id":String(cell.id),"clearance":clearance,"case":label}
	if not check("all bedroom-count variants represented in both mirrored wings",variants.size()==6):finish();return
	# JSON numbers arrive as floats. Canonical keys must use integer spelling,
	# otherwise str(1.0) silently creates east:1.0 instead of advertised east:1.
	for required:String in ["east:1","west:1","east:2","west:2","east:3","west:3"]:
		if not check("canonical variant key "+required,variants.has(required),str(variants.keys())):finish();return
	print("[mbs-guest-floor] AVAILABLE_VARIANTS ",JSON.stringify(variants.keys()))
	if not prepare_player():finish();return
	_light_fixture()
	var filter:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--mbs-guest-variant="):filter=arg.trim_prefix("--mbs-guest-variant=")
	if not filter.is_empty():
		if not check("recognized variant filter",variants.has(filter),filter+" available="+str(variants.keys())):finish();return
	for label:String in ["east:1","west:1","east:2","west:2","east:3","west:3"]:
		if not filter.is_empty() and label!=filter:continue
		var item:Dictionary=variants[label]
		if not await fixture(item.floor_id,item.unit_id,label):finish();return
	check("local tests never certify privateasbuilt/wholecity/building",not Inventory.load_inventory().coverage.full_building_completed)
	finish()

func fixture(id:String,unit_id:String,variant:String)->bool:
	walk_stage=variant+"/setup"
	tracking=false
	lift_monitor=false
	player.process_mode=Node.PROCESS_MODE_DISABLED
	player.collision_layer=0
	player.collision_mask=0
	player.hide()
	if is_instance_valid(receiving):
		receiving.queue_free()
		await frames(3)
	if is_instance_valid(candidate):
		candidate.queue_free()
		await frames(3)
	candidate=GuestFloor.new()
	add_child(candidate)
	var record:=Inventory.floor_record(id)
	var invalid:=record.duplicate(true)
	invalid.geometry.length_m=1.0e12
	check("invalid floor fails before children/state",not candidate.build(invalid).get("built",true) and candidate.get_child_count()==0 and candidate.rooms.is_empty())
	var result:Dictionary=candidate.build(record)
	if not check("actual furnished colliding floor builds "+id,result.get("built",false),str(result)):return false
	transition_calls.clear()
	candidate.transition_requested.connect(func(_floor_id:String,portal_id:String,_kind:String): transition_calls[portal_id]=int(transition_calls.get(portal_id,0))+1)
	check("all inventory units built "+id,result.guest_rooms_built==record.units.size())
	check("runtime report preserves completion limits "+id,not result.current_private_asbuilt_verified and not result.full_building_completed and not result.integrated_city_traversal_verified)
	await frames(5)
	if record.geometry.atrium_void_active:
		check("public atrium void not capped by low slab or ceiling",ray(Vector3(0,4,0),Vector3(0,-1,0)).is_empty())
	var selected:Array[Dictionary]=[]
	for cell:Dictionary in candidate.rooms:
		if cell.id==unit_id:selected.append(cell)
	if selected.is_empty():return check("fixture selected inventoryunit exists",false)
	var first:Dictionary=selected[0]
	check("public route refuses a private-room shortcut",candidate.public_route_local(first.inside_local,first.entry_local,String(first.wing)).is_empty())
	player.collision_layer=player_layer
	player.collision_mask=mask
	player.show()
	player.process_mode=Node.PROCESS_MODE_INHERIT
	# Explicit between-fixture setup only. No relocation during the walking loop.
	player.respawn_at(candidate.to_global(first.entry_local)+Vector3.UP*.1,0)
	await frames(20)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	travel=0;max_step=0;maximum_y=-INF;minimum_y=INF
	previous=player.global_position
	tracking=true
	for cell:Dictionary in selected:
		if not await walk_to(candidate.to_global(cell.entry_local),.4):return false
		var outside:Vector3=candidate.to_global(cell.entry_local)
		var inside:Vector3=candidate.to_global(cell.inside_local)
		check("actual room door blocks production capsule whenclosed "+String(cell.id),not capsule_clear(outside,inside))
		if not await blocked_e(String(cell.id)):return false
		if not await native_e(String(cell.id)):return false
		check("production capsule clears opened roomdoor "+String(cell.id),capsule_clear(outside,inside,"opened roomdoor "+String(cell.id)))
		var route:Array[Vector3]=candidate.room_route_local(cell.id)
		for route_index in route.size():
			if not await walk_to(candidate.to_global(route[route_index]),.4):return false
			if route_index==1:
				await frames(15)
				await still(id+"_"+String(cell.id)+"_furnished_entry")
		# Separate bathroom is entered through its actual sidewall door.
		if not await walk_to(candidate.to_global(cell.inside_local),.4):return false
		var previous_bath:Vector3=cell.inside_local
		for approach:Vector3 in cell.bath_route_local:
			if not check("actual capsule clears intended bath foyer "+String(cell.id),capsule_clear(candidate.to_global(previous_bath),candidate.to_global(approach),"bath foyer "+String(cell.id))):return false
			# A 1.10m clear cross-gallery leaves 0.36m beyond the full
			# capsule+query-margin width; 0.10m corner arrival prevents cutting it.
			if not await walk_to(candidate.to_global(approach),.10):return false
			previous_bath=approach
		if not await native_e(String(cell.id)+"-bath"):return false
		if not await walk_to(candidate.to_global(cell.bath_outside_local),.22):return false
		if not await walk_to(candidate.to_global(cell.bath_inside_local),.22):return false
		await frames(12)
		await still(id+"_"+String(cell.id)+"_bathroom")
		if not await walk_to(candidate.to_global(cell.bath_outside_local),.22):return false
		for reverse_index in range(cell.bath_route_local.size()-2,-1,-1):
			if not await walk_to(candidate.to_global(cell.bath_route_local[reverse_index]),.10):return false
		for bedroom:Dictionary in cell.bedroom_layouts:
			if not await walk_to(candidate.to_global(bedroom.living_gallery),.10):return false
			if not await walk_to(candidate.to_global(bedroom.door_approach),.22):return false
			var bedroom_id:String=String(cell.id)+"-bedroom-"+str(bedroom.index)
			check("closed bedroom door blocks actual capsule "+bedroom_id,not capsule_clear(candidate.to_global(bedroom.door_approach),candidate.to_global(bedroom.door_inside)))
			if not await native_e(bedroom_id):return false
			check("opened bedroom door clears actual capsule "+bedroom_id,capsule_clear(candidate.to_global(bedroom.door_approach),candidate.to_global(bedroom.door_inside),"opened bedroomdoor "+bedroom_id))
			if bedroom_id=="R-T2-L41-02-bedroom-1":retained_west_entry_probe()
			# Door now aligns with the clear bed/window aisle. Travel in and
			# out along that corridor, without a sprint-speed 0.3m lateral jog.
			var bedroom_route:Array[Vector3]=[bedroom.door_inside,bedroom.window,bedroom.door_inside,bedroom.door_approach,bedroom.living_gallery]
			var previous_bedroom:Vector3=bedroom.door_approach
			for route_index in bedroom_route.size():
				var target:Vector3=bedroom_route[route_index]
				walk_stage=bedroom_id+"/route_segment_"+str(route_index)
				if not check("full capsule clears continuous bedroom route "+walk_stage,capsule_clear(candidate.to_global(previous_bedroom),candidate.to_global(target),walk_stage)):return false
				print("[mbs-guest-floor] ROUTE_SEGMENT ",JSON.stringify({"stage":walk_stage,"actual_from":player.global_position,"planned_from":candidate.to_global(previous_bedroom),"target":candidate.to_global(target)}))
				if not await walk_to(candidate.to_global(target),.22):return false
				previous_bedroom=target
			check("actualPlayer reached full kingbed window aisle "+bedroom_id,true,str(bedroom.clear_window_aisle_m))
		if not await walk_to(candidate.to_global(cell.entry_local),.4):return false
	var saved:Dictionary=candidate.serialize_state()
	candidate.set_door_open(first.id,false)
	check("floor-scoped roomdoor persistence restores",candidate.restore_state(saved) and (candidate.doors[first.id] as AnimatableBody3D).get("opened"))
	var lifted:Dictionary={}
	for portal:Dictionary in candidate.portals:
		if portal.wing!=first.wing:continue
		if String(portal.kind) in ["guest_lift","service_lift"] and not lifted.has(portal.kind):
			if not await walk_public_to(portal.landing,String(portal.wing)):return false
			await frames(15) # settle normal locomotion before relocation assertion
			check("landing cannot open without physicalcabin/interlock",not candidate.set_door_open(portal.id,true))
			if not await native_e(portal.id,true):return false
			lifted[portal.kind]=true
		if portal.kind=="linen_service_room":
			if not await walk_public_to(portal.landing,String(portal.wing)):return false
			if not await native_e(portal.id):return false
			await frames(60)
			if not await walk_to(candidate.to_global(portal.inside),.35):return false
			if not await walk_to(candidate.to_global(portal.landing),.35):return false
	# The published stair contract requires the real next-level receiving
	# collision before crossing. A current-floor ceiling is not an upper floor.
	var next_id:String=String(record.tower)+"-L"+str(int(record.level_number)+1)
	var next_record:Dictionary=Inventory.floor_record(next_id)
	if not check("next inventory floor exists before stair transition",not next_record.is_empty(),next_id):return false
	var rise:float=float(next_record.elevation_m)-float(record.elevation_m)
	if not check("adjacent physical elevation matches stair rise",is_equal_approx(rise,float(record.geometry.storey_height_m))):return false
	receiving=GuestFloor.new()
	add_child(receiving)
	receiving.position.y=rise
	var receiving_result:Dictionary=receiving.build_receiving_core_interface_for_qa(next_record)
	if not check("actual next-floor receiving core interface loaded",receiving_result.get("built",false) and not receiving_result.get("full_floor_built",true),str(receiving_result)):return false
	await frames(5)
	for portal:Dictionary in candidate.portals:
		if portal.wing==first.wing and portal.kind=="stair":
			if not await walk_public_to(portal.lower,String(portal.wing)):return false
			for target:Vector3 in portal.walk_route:
				if not await walk_to(candidate.to_global(target),.28):return false
			check("actual Player climbs physical U stair withoutjump "+id,player.global_position.y>float(record.geometry.storey_height_m)-.25)
			var upper:Vector3=candidate.to_global(portal.upper)
			var support:Dictionary=ray(upper+Vector3.UP,upper-Vector3.UP*.5)
			if not check("upper approach is supported by next floor not lower ceiling",not support.is_empty() and absf(float((support.get("position",Vector3.ZERO) as Vector3).y)-rise)<.005):return false
			if not await walk_to(upper,.18):return false
			check("actualPlayer crosses loaded receiving approach",absf(player.global_position.y-(rise-.025))<.05 and player.is_on_floor())
			for index in range(portal.walk_route.size()-1,-1,-1):
				if not await walk_to(candidate.to_global(portal.walk_route[index]),.28):return false
	check("continuous fixture walking has no teleport/death "+id,max_step<.5 and minimum_y>-.20 and Game.death_count==0,"travel%.2f maxstep%.4f minY%.3f maxY%.3f"%[travel,max_step,minimum_y,maximum_y])
	fixture_results.append({"floor_id":id,"travel_m":travel,"max_step_m":max_step,"maximum_y_m":maximum_y,"private_asbuilt_verified":false,"source_site_traversal":false,"variant":variant,"unit_id":unit_id,"native_e_doors":native_e_doors.duplicate()})
	tracking=false
	return failures.is_empty()

func blocked_e(id:String)->bool:
	var door:Node3D=candidate.doors[id]
	await frames(12)
	var blocker:=StaticBody3D.new()
	blocker.name="QA_LOS_Obstruction"
	blocker.collision_layer=1
	blocker.collision_mask=0
	blocker.position=(player.global_position+door.global_position)*.5+Vector3.UP*1.0
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(1.5,2.4,.12)
	shape.shape=box;blocker.add_child(shape);add_child(blocker)
	await frames(3)
	var invisible:bool=not player._interaction_visible(door) and player._interaction_target()!=door
	check("production LOS excludes occluded exact door "+id,invisible)
	Input.action_release("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_press("interact")
	await frames(6)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("interact")
	await frames(5)
	await get_tree().process_frame
	await get_tree().process_frame
	var remained_closed:bool=not bool(door.get("opened"))
	check("native E cannot open through obstruction "+id,remained_closed)
	blocker.queue_free();await frames(3)
	return invisible and remained_closed

func native_e(id:String,request_only:bool=false)->bool:
	var door:Node3D=candidate.doors.get(id)
	if not check("production door adapter exists "+id,door!=null and door.is_in_group("interactables") and door.has_method("interact") and not String(door.get("prompt_text")).is_empty()):return false
	Input.action_release("interact")
	await frames(12)
	await get_tree().process_frame
	await get_tree().process_frame
	if not check("native interaction selects exact door "+id,player._interaction_target()==door):return false
	if not check("production LOS permits door "+id,player._interaction_visible(door)):return false
	var was_open:bool=door.get("opened")
	var requests:int=int(transition_calls.get(id,0))
	var before:=player.global_position
	if request_only:
		lift_monitor=true
		lift_previous=before
		lift_peak_residual=0;lift_peak_step=0;lift_sample_count=0
		lift_input_clear=true;lift_trace.clear()
	var press_process_frame:=Engine.get_process_frames()
	Input.action_press("interact")
	await frames(6)
	# Player polls held interact in _process, not _physics_process. Physics
	# catch-up alone can consume six ticks without a polling opportunity.
	await get_tree().process_frame
	await get_tree().process_frame
	var held_process_frames:=Engine.get_process_frames()-press_process_frame
	Input.action_release("interact")
	await frames(5)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[mbs-guest-floor] NATIVE_E_PROCESS_WINDOW ",JSON.stringify({"door_id":id,"held_process_frames":held_process_frames,"armed_after":player.get("_press_armed"),"transition_requests":transition_calls.get(id,0),"opened":door.get("opened")}))
	if not check("held native E spans production process polling "+id,held_process_frames>=2):return false
	var ok:bool
	if request_only:
		ok=int(transition_calls.get(id,0))==requests+1 and not bool(door.get("opened")) and player.global_position.distance_to(before)<.02
	else:ok=bool(door.get("opened"))!=was_open
	if not check("production E action "+id,ok):return false
	if not native_e_doors.has(id):native_e_doors.append(id)
	await frames(60)
	var expected_angle:float=float(door.get("base_angle"))+(float(door.get("swing_delta")) if bool(door.get("opened")) else 0.0)
	var physical:Transform3D=PhysicsServer3D.body_get_state((door as CollisionObject3D).get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	if request_only:
		lift_monitor=false
		var float_error:float=maxf(.00001,player.global_position.length()*.00000024)
		var correction_bound:float=player.safe_margin+float_error
		var movement:Dictionary={"door_id":id,"before":before,"after":player.global_position,"delta":player.global_position-before,"samples":lift_sample_count,"max_frame_step_m":lift_peak_step,"max_physics_residual_m":lift_peak_residual,"safe_margin_m":player.safe_margin,"float_error_m":float_error,"correction_bound_m":correction_bound,"no_movement_input":lift_input_clear,"recent":lift_trace}
		print("[mbs-guest-floor] LIFT_REQUEST_MOTION ",JSON.stringify(movement))
		if not check("liftrequest never teleportsactor",lift_sample_count>=60 and lift_input_clear and lift_peak_step<.02 and lift_peak_residual<=correction_bound,str(movement)):return false
	print("[mbs-guest-floor] DOOR_PHYSICAL_STATE ",JSON.stringify(door_snapshot(door)))
	if not check("physical door reaches commanded open/closed pose "+id,absf(wrapf(door.rotation.y-expected_angle,-PI,PI))<.002 and absf(float(door.get("motion_angle"))-expected_angle)<.002 and physical.origin.distance_to(door.global_position)<.002 and physical.basis.is_equal_approx(door.global_basis)):return false
	return true

func walk_public_to(target_local:Vector3,wing:String)->bool:
	var actual_local:Vector3=candidate.to_local(player.global_position)
	var route:Array[Vector3]=candidate.public_route_local(actual_local,target_local,wing)
	if not check("public portal route follows corridor/endbays",not route.is_empty(),str({"from":actual_local,"to":target_local,"wing":wing,"waypoints":route})):return false
	# Module route points use the finished floor reference Y=0. This projects
	# only the analytic sweep start onto that reference; actor position is
	# untouched and its production controller performs every physical segment.
	var previous_local:=Vector3(actual_local.x,0,actual_local.z)
	for waypoint:Vector3 in route:
		walk_stage="public/"+wing+"/"+str(waypoint)
		if not check("full capsule clears public corridor segment",capsule_clear(candidate.to_global(previous_local),candidate.to_global(waypoint),"public corridor/endbay")):return false
		public_sprint_leg=true
		var walked:bool=await walk_to(candidate.to_global(waypoint),.18)
		public_sprint_leg=false
		if not walked:return false
		previous_local=waypoint
	return true

func release_motion_input()->void:
	for action:String in ["move_forward","move_back","move_left","move_right","sprint","walk","jump"]:
		Input.action_release(action)

func settle_native_motion(label:String)->bool:
	release_motion_input()
	walk_phase="settle/"+label
	var started:=Time.get_ticks_msec()
	var quiet_frames:=0
	# Releasing native inputs invokes the production braking/stop animation.
	# Never assign actor position/velocity, heading, speed or controller state.
	while Time.get_ticks_msec()-started<2500:
		await get_tree().physics_frame
		var horizontal:=Vector2(player.velocity.x,player.velocity.z).length()
		if horizontal<.05:
			quiet_frames+=1
			if quiet_frames>=3:return true
		else:quiet_frames=0
	return check("native locomotion settles with released input "+label,false,str(player.velocity))

func walk_to(target:Vector3,radius:float)->bool:
	var allow_sprint:bool=public_sprint_leg
	walk_target=target
	if not await settle_native_motion("before leg"):return false
	var turn_started:=Time.get_ticks_msec()
	walk_phase="stopped-camera-turn"
	while Time.get_ticks_msec()-turn_started<2000:
		var direction:=target-player.global_position
		if Vector2(direction.x,direction.z).length()<=radius:break
		var desired:=atan2(-direction.x,-direction.z)
		player.yaw=lerp_angle(player.yaw,desired,.24)
		if absf(wrapf(player.yaw-desired,-PI,PI))<.01:break
		await get_tree().physics_frame
	var turn_delta:=target-player.global_position
	if Vector2(turn_delta.x,turn_delta.z).length()>radius:
		if not check("camera aligned while stopped",absf(wrapf(player.yaw-atan2(-turn_delta.x,-turn_delta.z),-PI,PI))<.01):return false
	var started_tick:=Time.get_ticks_msec()
	var start_position:=player.global_position
	var initial:=player.global_position.distance_to(target)
	# Long public corridor legs may sprint; constrained room/stair legs use
	# the real WALK action (1.5m/s), with the unchanged arrival radii.
	var nominal_speed:float=Player.SPRINT_SPEED if allow_sprint else Player.WALK_SPEED
	# A wall-second is not a simulated second when the heavy source scene is
	# slower than real time. Budget the actual physics clock and intended gait;
	# retain a separate finite monotonic cap and no-progress failure watchdog.
	# Sprint legs still brake to WALK, so the slow gait is the conservative
	# budget basis. None of these values changes the production actor speed.
	var physics_started:int=Engine.get_physics_frames()
	var physics_rate:int=Engine.physics_ticks_per_second
	var time_scale:float=Engine.time_scale
	var simulation_budget:float=initial/Player.WALK_SPEED*1.75+12.0
	var wall_budget:float=clampf(simulation_budget*6.0+15.0,30.0,360.0)
	var deadline:int=started_tick+int(wall_budget*1000.0)
	var simulation_elapsed:=0.0
	var best_remaining:float=initial
	var last_progress_sim:=0.0
	var termination_reason:="arrival"
	var braking:=false
	while player.global_position.distance_to(target)>radius and simulation_elapsed<simulation_budget and Time.get_ticks_msec()<deadline:
		await get_tree().physics_frame
		if Engine.physics_ticks_per_second!=physics_rate or not is_equal_approx(Engine.time_scale,time_scale):
			termination_reason="physics_clock_changed"
			break
		simulation_elapsed=float(Engine.get_physics_frames()-physics_started)/float(physics_rate)*time_scale
		var d:=target-player.global_position
		var full_remaining:float=d.length()
		if full_remaining<best_remaining-.025:
			best_remaining=full_remaining;last_progress_sim=simulation_elapsed
		if simulation_elapsed-last_progress_sim>6.0:
			termination_reason="no_progress_6_sim_seconds"
			break
		var remaining:=Vector2(d.x,d.z).length()
		var speed:=Vector2(player.velocity.x,player.velocity.z).length()
		var stopping_distance:=speed*speed/(2.0*Player.DECEL)+speed/float(Engine.physics_ticks_per_second)
		if braking:
			if speed<.05:
				if player.global_position.distance_to(target)<=radius:break
				braking=false
			else:continue
		if remaining<=radius+stopping_distance and speed>.10:
			release_motion_input()
			walk_phase="native-braking"
			braking=true
			continue
		player.yaw=lerp_angle(player.yaw,atan2(-d.x,-d.z),.20)
		Input.action_press("move_forward")
		# Sprint has no tight corner/reversal mandate. It is reserved for
		# a straight public leg, returning to walk well before the target.
		if allow_sprint and remaining>4.0:
			Input.action_release("walk");Input.action_press("sprint")
			walk_phase="public-straight-sprint"
		else:
			Input.action_release("sprint");Input.action_press("walk")
			walk_phase="constrained-native-walk"
	if player.global_position.distance_to(target)>radius:
		if termination_reason=="arrival": termination_reason="wall_watchdog" if Time.get_ticks_msec()>=deadline else "simulation_budget"
		var requested_velocity:Vector3=player.get_meta("_qa_motion_state",{}).get("requested",player.velocity)
		native_motion_diagnostic("timeout before releasing actual requested step",player.global_transform,requested_velocity/float(Engine.physics_ticks_per_second))
		print("[mbs-guest-floor] PRE_SETTLE_TIMEOUT ",JSON.stringify({"stage":walk_stage,"phase":walk_phase,"reason":termination_reason,"pose":player.global_transform,"target":target,"velocity":player.velocity,"requested_velocity":requested_velocity,"controller":player.get_meta("_qa_motion_state",{}),"elapsed_sim_s":simulation_elapsed,"simulation_budget_s":simulation_budget,"elapsed_wall_s":float(Time.get_ticks_msec()-started_tick)/1000.0,"wall_budget_s":wall_budget,"last_progress_sim_s":last_progress_sim,"recent":motion_trace}))
	if not await settle_native_motion("at leg end"):return false
	var ok:=player.global_position.distance_to(target)<=radius+.08 and termination_reason!="physics_clock_changed"
	gait_records.append({"stage":walk_stage,"allow_public_sprint":allow_sprint,"nominal_speed_mps":nominal_speed,"budget_gait_speed_mps":Player.WALK_SPEED,"start":start_position,"end":player.global_position,"target":target,"arrival_radius_m":radius,"distance_after_native_settle_m":player.global_position.distance_to(target),"elapsed_s":float(Time.get_ticks_msec()-started_tick)/1000.0,"elapsed_sim_s":simulation_elapsed,"simulation_budget_s":simulation_budget,"wall_budget_s":wall_budget,"termination_reason":termination_reason,"actor_or_velocity_assigned":false})
	if not ok:
		var probe_motion:=player.velocity/float(Engine.physics_ticks_per_second)
		native_motion_diagnostic("actual failed walk requested step",player.global_transform,probe_motion)
		var target_step:=target-player.global_position
		target_step.y=0.0
		if target_step.length()>.15:target_step=target_step.normalized()*.15
		native_motion_diagnostic("actual failed walk toward target",player.global_transform,target_step)
		var contacts:Array[Dictionary]=[]
		for index in player.get_slide_collision_count():
			var contact:=player.get_slide_collision(index)
			var body:=contact.get_collider() as CollisionObject3D
			var owner:Node3D=body.shape_owner_get_owner(body.shape_find_owner(contact.get_collider_shape_index())) if body!=null else null
			contacts.append({"body":String(body.name) if body!=null else "UNKNOWN","shape":String(owner.name) if owner!=null else "UNKNOWN","normal":contact.get_normal(),"position":contact.get_position()})
		var nearby_doors:Array[Dictionary]=[]
		if is_instance_valid(candidate) and candidate.get("doors") is Dictionary:
			for id:String in candidate.doors:
				var door:Node3D=candidate.doors[id]
				if door.global_position.distance_to(player.global_position)<3.0:nearby_doors.append(door_snapshot(door))
		print("[mbs-guest-floor] MOTION_INPUT_TRACE ",JSON.stringify({"stage":walk_stage,"phase":walk_phase,"player":player.global_position,"target":target,"leg":{"initial_distance_m":initial,"remaining_distance_m":player.global_position.distance_to(target),"elapsed_s":float(Time.get_ticks_msec()-started_tick)/1000.0,"budget_s":float(deadline-started_tick)/1000.0,"displacement_m":player.global_position.distance_to(start_position)},"busy":player.busy,"alive":player.alive,"paused":Game.simulation_paused,"mode":Game.mode,"input":{"forward":Input.get_action_strength("move_forward"),"back":Input.get_action_strength("move_back"),"left":Input.get_action_strength("move_left"),"right":Input.get_action_strength("move_right"),"sprint":Input.get_action_strength("sprint")},"velocity":player.velocity,"controller":player.get_meta("_qa_motion_state",{}),"last_samples":motion_trace,"nearby_doors":nearby_doors}))
		check("continuous productionPlayer walking",false,"at%s target%s contacts%s"%[player.global_position,target,contacts])
	walk_phase="idle"
	return ok

func still(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	var folder:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mbs-guest-stills-dir="):folder=arg.trim_prefix("--mbs-guest-stills-dir=")
	if folder.is_empty():return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(label+".png"))

func _light_fixture()->void:
	var world:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color(.43,.56,.66)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.80,.85,.90);env.ambient_light_energy=.65
	world.environment=env;add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.light_energy=1.1;sun.shadow_enabled=true;add_child(sun)

func finish()->void:
	if finished:return
	finished=true;tracking=false;lift_monitor=false
	for action:String in ["move_forward","move_back","move_left","move_right","sprint","walk","jump","interact"]:Input.action_release(action)
	var variants_exercised:Array[String]=[]
	for item:Dictionary in fixture_results:
		if not variants_exercised.has(item.variant):variants_exercised.append(item.variant)
	print("[mbs-guest-floor] RESULT ",JSON.stringify({"variants_exercised":variants_exercised,"full_suite_variant_matrix_exercised":variants_exercised.size()==6,"required_suite_variants":["east:1","west:1","east:2","west:2","east:3","west:3"],"native_e_doors":native_e_doors,"checks":checks,"failures":failures,"fixtures":fixture_results,"gait_policy":"stop-settle/turn-in-place/native-walk; sprint only explicit straight public legs","gait_records":gait_records,"all1850rooms_physically_tested":false,"full_building_completed":false,"current_private_asbuilt_verified":false}))
	Sfx.shutdown_audio();get_tree().quit(0 if failures.is_empty() else 1)
