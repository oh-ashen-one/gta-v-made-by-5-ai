extends "res://src/systems/fidelity_tests/mbs_guest_floor_test.gd"
## Scoped local native fixture. No source-site/full-building acceptance.
const Gates=preload("res://src/world/mbs_interior/stair_gates.gd")
var gates:Node3D
var upper_floor:Node3D
var upper_neighbor:Node3D
var site:Node3D
var gate_id:=""
var stair:Dictionary={}
var lower_id:="T3-L47"
var upper_id:="T3-L48"
var neighbor_id:="T3-L49"
var requests:Array[String]=[]
var allow_delayed_load:=false
var loading:=false
var readiness_override:=""
var lower_generation:="fixture-lower-47-v1"
var upper_generation:="fixture-upper-48-v1"
var neighbor_generation:="fixture-neighbor-49-v1"
var _started:=0
var native_gate_actions:Array[Dictionary]=[]
var retirement_observation:Dictionary={}

func _ready()->void:
	if not "--qa-session" in OS.get_cmdline_user_args():
		push_error("Stair-gate fixture requires private --qa-session")
		get_tree().quit(2);return
	_started=Time.get_ticks_msec()
	get_tree().create_timer(330.0,true,true).timeout.connect(func():
		if not finished:check("bounded stair gate fixture",false,"330s");finish())
	run.call_deferred()

func _native_floor_support(module:Node3D,elevation:float,local_point:Vector3)->bool:
	if not is_instance_valid(module) or not bool(module.get("_built")):return false
	var point:=site.to_global(Vector3(local_point.x,elevation,local_point.z))
	var q:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.8,point-Vector3.UP*.10,1)
	var hit:=get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and module.is_ancestor_of(hit.collider) and absf((hit.position as Vector3).y-point.y)<.015

func _actual_upper_ready()->bool:
	return _native_floor_support(candidate,0,stair.lower) and _native_floor_support(upper_floor,3.45,stair.upper) and _native_floor_support(upper_neighbor,6.90,stair.upper)

func _readiness(id:String)->Dictionary:
	if id==lower_id:return {"floor_id":id,"ready":_native_floor_support(candidate,0,stair.lower),"collision_generation":lower_generation}
	if id==upper_id:
		if readiness_override=="wrong_id":return {"floor_id":"T1-L48","ready":true,"collision_generation":upper_generation}
		if readiness_override=="missing_generation":return {"floor_id":id,"ready":true,"collision_generation":""}
		return {"floor_id":id,"ready":_actual_upper_ready() and readiness_override!="revoked","collision_generation":upper_generation if is_instance_valid(upper_floor) else "","required_neighbors":[{"floor_id":lower_id,"collision_generation":lower_generation},{"floor_id":neighbor_id,"collision_generation":neighbor_generation}]}
	return {"floor_id":id,"ready":false,"collision_generation":""}

func _on_requested(id:String)->void:
	requests.append(id)
	if allow_delayed_load and not loading and not is_instance_valid(upper_floor):
		loading=true
		_delayed_load.call_deferred()

func _delayed_load()->void:
	# Real delayed full factory floors, no plane/actor relocation. Lower plus
	# upper plus its next neighbor mirror FloorStack's non-transitive ±1 proof.
	await get_tree().create_timer(.25).timeout
	upper_floor=GuestFloor.new();site.add_child(upper_floor);upper_floor.position.y=3.45
	var upper_result:Dictionary=upper_floor.build(Inventory.floor_record(upper_id))
	check("actual receiving full furnished floor builds",upper_result.get("built",false))
	upper_neighbor=GuestFloor.new();site.add_child(upper_neighbor);upper_neighbor.position.y=6.90
	var neighbor_result:Dictionary=upper_neighbor.build(Inventory.floor_record(neighbor_id))
	check("actual receiving required upper neighbor builds",neighbor_result.get("built",false))
	await frames(5)
	check("receiving floor native support exists after physics insertion",_actual_upper_ready())
	gates.refresh_now()
	loading=false

func _native_gate_e(expected_open:bool)->bool:
	var door:Node3D=gates.doors[gate_id]
	release_motion_input()
	if not await settle_native_motion("stair E"):return false
	Input.action_release("interact")
	await get_tree().process_frame;await get_tree().process_frame
	if not check("native E selects exact visible stair door",player._interaction_target()==door):return false
	if not check("native E stair door has production LOS",player._interaction_visible(door)):return false
	check("stair prompt contains only product wording",door.prompt_text=="[E] Open stair door" or door.prompt_text=="[E] Close stair door")
	var before:=player.global_position
	var process_start:=Engine.get_process_frames()
	Input.action_press("interact");await frames(6)
	await get_tree().process_frame;await get_tree().process_frame
	Input.action_release("interact");await frames(5)
	await get_tree().process_frame;await get_tree().process_frame
	var action:Dictionary={"opened":door.opened,"expected_open":expected_open,"player_instance_id":player.get_instance_id(),"gate_state":gates.report().gates[gate_id],"door_physics":door_snapshot(door),"process_frames":Engine.get_process_frames()-process_start,"before":before,"after":player.global_position,"movement_m":player.global_position.distance_to(before),"exact_target":player._interaction_target()==door}
	native_gate_actions.append(action)
	print("[mbs-stair-gate] NATIVE_E ",JSON.stringify(action))
	return check("actual E stair state matches readiness",door.opened==expected_open and action.movement_m<.02)

func _closed_body_crossings()->bool:
	var descriptor:Dictionary=gates.geometry_descriptor(lower_id)
	var pass_all:=true
	for geometry:Dictionary in descriptor.gates:
		var side:float=geometry.side
		var plane:float=geometry.gate_plane_z_local_m
		var hinge:Vector3=geometry.hinge_local
		var landing_center:float=hinge.x+Gates.WIDTH*.5-.78
		# Sweep full capsule through door/pier/return positions. No endpoint is
		# beyond existing guard bounds; all routes through the landing block.
		for dx:float in [-1.05,-.70,-.35,0.0,.35,.70,1.05]:
			var from:=site.to_global(Vector3(landing_center+dx,geometry.rise_m,plane+side*.65))
			var to:=site.to_global(Vector3(landing_center+dx,geometry.rise_m,plane-side*.65))
			pass_all=check("full capsule cannot bypass closed landing gate "+String(geometry.wing)+"/"+str(dx),not capsule_clear(from,to)) and pass_all
	return pass_all

func _attempt_unready_crossing()->bool:
	if not await settle_native_motion("unready stair barrier"):return false
	var door:Node3D=gates.doors[gate_id]
	var target:Vector3=site.to_global(stair.upper)
	var direction:=target-player.global_position
	player.yaw=atan2(-direction.x,-direction.z)
	var start:=player.global_position
	var until:=Time.get_ticks_msec()+1200
	Input.action_press("walk");Input.action_press("move_forward")
	while Time.get_ticks_msec()<until:await get_tree().physics_frame
	release_motion_input()
	if not await settle_native_motion("blocked stair barrier"):return false
	var at:Vector3=site.to_local(player.global_position)
	var side:float=-1
	var plane:float=float(gates.geometry_descriptor(lower_id).gates[0].gate_plane_z_local_m)
	var safe:bool=side*(at.z-plane)>.36 and at.y>3.30
	print("[mbs-stair-gate] CLOSED_NATIVE_ATTEMPT ",JSON.stringify({"before":start,"after":player.global_position,"local":at,"plane_z":plane,"gate_opened":door.opened,"safe":safe}))
	return check("production Player physically stopped before unloaded edge",safe and not door.opened)

func run()->void:
	Game.simulation_paused=false;Game.mode=Game.MODE_FOOT;Game.health=Game.MAX_HEALTH;Game.death_count=0
	if not prepare_player():finish();return
	_light_fixture()
	site=Node3D.new();site.name="TranslatedRotatedUnitSite";add_child(site)
	site.position=Vector3(41,0,-23);site.rotation.y=.37
	candidate=GuestFloor.new();site.add_child(candidate)
	if not check("real lower guest floor builds",candidate.build(Inventory.floor_record(lower_id)).get("built",false)):finish();return
	for portal:Dictionary in candidate.portals:
		if portal.kind=="stair" and portal.wing=="east":stair=portal
	if not check("actual factory U stair exists",not stair.is_empty()):finish();return
	await frames(5)
	if not check("bound lower native support inserted before generation",_native_floor_support(candidate,0,stair.lower)):finish();return
	gates=Gates.new();add_child(gates)
	var invalid:Dictionary=gates.bind_floor(candidate,lower_id,"T1-L48",_readiness)
	check("invalid exact tower transition rejects transactionally",not invalid.get("bound",true) and gates.owned_collision_bodies().is_empty())
	var bound:Dictionary=gates.bind_floor(candidate,lower_id,upper_id,_readiness)
	if not check("both upper landing fire doors bind",bound.get("bound",false),str(bound)):finish();return
	gates.floor_requested.connect(_on_requested)
	gate_id=lower_id+"-east-stair-fire-door"
	await frames(6)
	check("owned registry bodies exposed without context stamp",gates.owned_collision_bodies(lower_id).size()==4 and not gates.report().context_registered_by_component)
	check("translated rotated source parent preserves gate local geometry",gates.doors[gate_id].global_transform.origin.distance_to(candidate.to_global(Vector3(stair.upper.x,3.45,float(gates.geometry_descriptor(lower_id).gates[0].gate_plane_z_local_m))))<.001)
	if not _closed_body_crossings():finish();return
	# The ONE declared player setup relocation; never moved by the component.
	player.collision_layer=player_layer;player.collision_mask=mask
	player.show();player.process_mode=Node.PROCESS_MODE_INHERIT
	player.respawn_at(site.to_global(stair.lower)+Vector3.UP*.10,0)
	await frames(20);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	travel=0;max_step=0;maximum_y=-INF;minimum_y=INF;previous=player.global_position;tracking=true
	for index in stair.walk_route.size()-1:
		walk_stage="ascending U stair/"+str(index)
		if not await walk_to(site.to_global(stair.walk_route[index]),.28):finish();return
	var descriptor:Dictionary=gates.geometry_descriptor(lower_id).gates[0]
	var before_gate:=Vector3(stair.upper.x,3.45,float(descriptor.gate_plane_z_local_m)-.62)
	if not await walk_to(site.to_global(before_gate),.12):finish();return
	if not _actual_upper_ready():
		if not await _native_gate_e(false):finish();return
	await frames(4)
	check("unready E requests exact receiver outside physics",requests==[upper_id])
	if not await _attempt_unready_crossing():finish();return
	allow_delayed_load=true
	if not await _native_gate_e(false):finish();return
	var wait_limit:=Time.get_ticks_msec()+12000
	while not _actual_upper_ready() and Time.get_ticks_msec()<wait_limit:await get_tree().physics_frame
	await frames(6);gates.refresh_now()
	if not check("receiver and required neighbor now physically ready",_actual_upper_ready()):finish();return
	check("receiving readiness never auto-opens door",not gates.doors[gate_id].opened)
	if not await _native_gate_e(true):finish();return
	await frames(70)
	if not check("native physical leaf clears full production capsule",capsule_clear(site.to_global(before_gate),site.to_global(stair.upper))):finish();return
	if not await walk_to(site.to_global(stair.upper),.14):finish();return
	check("player crossed onto real receiving floor alive",absf(player.global_position.y-(3.45-.025))<.05 and player.is_on_floor() and Game.death_count==0)
	# Return to the open threshold before revocation: support remains present.
	var threshold:=Vector3(stair.upper.x,3.45,float(descriptor.gate_plane_z_local_m))
	if not await walk_to(site.to_global(threshold),.10):finish();return
	upper_generation="fixture-upper-48-v2-injected"
	gates.refresh_now();await frames(3)
	check("open gate refuses changed receiving collision generation",gates.report().gates[gate_id].close_requested)
	readiness_override="revoked";gates.refresh_now();await frames(3)
	check("occupied revoked threshold blocks physical retirement",not gates.prepare_floor_retirement(upper_id) and gates.protected_floor_ids().has(upper_id))
	var occupied_state:Dictionary=gates.report().gates[gate_id]
	check("closing holds for real occupied threshold",occupied_state.state=="HOLD_OCCUPIED")
	check("retirement notification cannot remove occupied gate",not gates.floor_retired(lower_id).get("removed",true))
	if not await walk_to(site.to_global(stair.upper),.14):finish();return
	# Clear the full leaf-sweep envelope farther onto the loaded approach.
	var clear:Vector3=stair.upper+Vector3(0,0,1.30)
	if not await walk_to(site.to_global(clear),.14):finish();return
	await frames(90);gates.refresh_now()
	check("revocation closes physical gate after actor clears",gates.report().gates[gate_id].physically_closed)
	readiness_override="wrong_id";gates.refresh_now()
	check("wrong exact receiving ID fails closed",not gates.report().gates[gate_id].ready)
	readiness_override="missing_generation";gates.refresh_now()
	check("missing receiving generation fails closed",not gates.report().gates[gate_id].ready)
	readiness_override="";gates.refresh_now();await frames(5)
	if not await walk_to(site.to_global(stair.upper),.14):finish();return
	# This is a real receiving-side standing point INSIDE the opening sweep,
	# as retained R1 proved. Native E must not let a leaf push the actor.
	if not await _native_gate_e(false):finish();return
	var blocked_open:Dictionary=gates.report().gates[gate_id]
	if not check("opening sweep interlock identifies actual Player capsule",blocked_open.state=="CLOSED_OPENING_OCCUPIED" and blocked_open.opening_blocker_ids.has(player.get_instance_id())):finish();return
	if not await walk_to(site.to_global(clear),.14):finish();return
	if not await _native_gate_e(true):finish();return
	await frames(70)
	for index in range(stair.walk_route.size()-2,-1,-1):
		walk_stage="returning U stair/"+str(index)
		if not await walk_to(site.to_global(stair.walk_route[index]),.28):finish();return
	if not await settle_native_motion("returned lower floor"):finish();return
	gates.prepare_floor_retirement(upper_id);await frames(90)
	check("closed clear gate permits root retirement preflight",gates.prepare_floor_retirement(upper_id))
	check("lower flight retains full production headroom both directions",minimum_y>-.20 and maximum_y>3.3 and max_step<.5 and Game.death_count==0)
	# The receiving-floor preflight above protects incoming gates, but it is
	# NOT a retirement lease for their LOWER owner. Prepare the exact owner.
	if not check("exact bound lower owner generation has safe preflight",gates.prepare_floor_retirement(lower_id)):finish();return
	var before_children:=candidate.get_child_count()
	var own_holder:Node=candidate.get_node("OwnedStairFireDoors")
	var own_holder_id:=own_holder.get_instance_id()
	var foreign_nodes:Array[Node]=[]
	var foreign_ids:Array[int]=[]
	for child:Node in candidate.get_children():
		if child!=own_holder:
			foreign_nodes.append(child);foreign_ids.append(child.get_instance_id())
	var owned_body_ids:Array[int]=[]
	for body:CollisionObject3D in gates.owned_collision_bodies(lower_id):owned_body_ids.append(body.get_instance_id())
	var refused:Dictionary=gates.floor_retired(lower_id)
	if not check("live bound collision generation cannot lose gate ownership",not refused.get("removed",true) and String(refused.get("error",""))=="Root must retire this collision generation before gate ownership removal",str(refused)):finish();return
	# Retire only this fixture's declared generation token after exact-owner
	# preflight. Full floor geometry stays; no source region is fabricated.
	lower_generation=""
	var removed:Dictionary=gates.floor_retired(lower_id)
	await frames(4)
	await get_tree().process_frame
	await get_tree().process_frame
	var actual_foreign_ids:Array[int]=[]
	for child:Node in candidate.get_children():actual_foreign_ids.append(child.get_instance_id())
	var all_foreign_intact:=true
	for child:Node in foreign_nodes:
		all_foreign_intact=all_foreign_intact and is_instance_valid(child) and child.get_parent()==candidate
	retirement_observation={"lower_owner_preflight":lower_id,"upper_receiving_preflight":upper_id,"owner_generation_retired":lower_generation.is_empty(),"live_generation_refusal":refused,"retirement_result":removed,"children_before":before_children,"children_after":candidate.get_child_count(),"owned_holder_instance_id":own_holder_id,"owned_body_ids_before":owned_body_ids,"owned_bodies_after":gates.owned_collision_bodies(lower_id).size(),"foreign_ids_before":foreign_ids,"actual_children_ids_after":actual_foreign_ids,"all_foreign_nodes_intact":all_foreign_intact,"remaining_gate_ids":gates.doors.keys(),"remaining_bound_floors":gates.report().bound_floors}
	print("[mbs-stair-gate] RETIREMENT ",JSON.stringify(retirement_observation))
	check("retire removes only its owned two gate assemblies",removed.get("removed",false) and removed.get("owned_gates_removed",0)==2 and candidate.get_child_count()==before_children-1 and candidate.get("_built") and all_foreign_intact and actual_foreign_ids==foreign_ids and gates.owned_collision_bodies(lower_id).is_empty() and gates.doors.is_empty() and not gates.report().bound_floors.has(lower_id))
	fixture_results.append({"floor_id":lower_id,"upper_id":upper_id,"required_upper_neighbor":neighbor_id,"travel_m":travel,"max_step_m":max_step,"native_gate_actions":native_gate_actions,"source_site_tested":false,"all_floor_pairs_tested":false})
	finish()

func finish()->void:
	if finished:return
	finished=true;tracking=false
	release_motion_input();Input.action_release("interact")
	print("[mbs-stair-gate] RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"elapsed_s":float(Time.get_ticks_msec()-_started)/1000.0,"fixture":fixture_results,"gate_state":gates.report() if is_instance_valid(gates) else {},"native_E_actions":native_gate_actions,"retirement_observation":retirement_observation,"actor_pose_writes_during_traversal":0,"source_site_tested":false,"all_floor_pairs_tested":false,"full_building_completed":false}))
	Sfx.shutdown_audio();get_tree().quit(0 if failures.is_empty() else 1)
