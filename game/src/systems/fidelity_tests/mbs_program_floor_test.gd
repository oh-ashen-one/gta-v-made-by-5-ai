extends "res://src/systems/fidelity_tests/mbs_guest_floor_test.gd"
## Inherits the exact production Player/native-E/LOS/capsule diagnostics from
## the guest fixture. One explicit setup pose, then ordinary continuous walking.
## All-record planning coverage is reported separately from selected runtime QA.
const ProgramFloor = preload("res://src/world/mbs_interior/program_floor.gd")
var plan_results: Array[Dictionary] = []
var runtime_program_doors: Array[String] = []
var tested_floor := ""
var tested_wing := "west"
var _program_started := 0

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args():
		push_error("Program-floor fixture requires private --qa-session")
		get_tree().quit(2);return
	_program_started=Time.get_ticks_msec()
	get_tree().create_timer(900.0,true,true).timeout.connect(func():
		if not finished:
			check("bounded program-floor verification",false,"900s")
			finish())
	run.call_deferred()

func check(label: String,ok: bool,detail: String = "") -> bool:
	checks+=1
	print("[mbs-program-floor] %s %s %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok: failures.append(label)
	return ok

func run() -> void:
	Game.simulation_paused=false;Game.mode=Game.MODE_FOOT
	Game.health=Game.MAX_HEALTH;Game.death_count=0
	var data:=Inventory.load_inventory()
	if not check("deterministic inventory is readable",not data.has("error")): finish();return
	var records: Array[Dictionary] = []
	for record: Dictionary in data.hotel_floors:
		if record.factory=="program_module": records.append(record)
	var hotel_count:=records.size()
	for record: Dictionary in data.resort_program_floors: records.append(record)
	if not check("all hotel and resort program records are included",hotel_count==30 and records.size()==57,"hotel%d resort%d"%[hotel_count,records.size()-hotel_count]): finish();return
	for record: Dictionary in records:
		var proposed:=ProgramFloor.program_plan(record)
		if not check("bounded nonempty furnished recipe "+String(record.id),proposed.get("valid",false),str(proposed.get("error",""))): finish();return
		var no_empty:=true
		for cell: Dictionary in proposed.rooms:
			no_empty=no_empty and not (cell.objects as Array).is_empty()
			for object: Dictionary in cell.objects:
				var size: Vector3=object.size
				no_empty=no_empty and size.x>0 and size.y>0 and size.z>0
		check("named rooms have real bounded furnishing geometry "+String(record.id),no_empty and proposed.object_count<=ProgramFloor.MAX_PROGRAM_OBJECTS)
		plan_results.append({"floor_id":record.id,"geometry_status":proposed.geometry_status,"program_spaces":proposed.space_count,"furnished_rooms":proposed.rooms.size(),"objects":proposed.object_count,"plan_only":true})
	var selected_id:="T2-L5"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mbs-program-floor="): selected_id=arg.trim_prefix("--mbs-program-floor=")
		if arg.begins_with("--mbs-program-wing="): tested_wing=arg.trim_prefix("--mbs-program-wing=")
	if not check("recognized physical wing",tested_wing in ["east","west"]): finish();return
	var selected: Dictionary={}
	for record: Dictionary in records:
		if record.id==selected_id: selected=record;break
	if not check("selected runtime floor is in full inventory",not selected.is_empty(),selected_id): finish();return
	if not prepare_player(): finish();return
	_light_fixture()
	await program_fixture(selected,tested_wing)
	finish()

func program_fixture(record: Dictionary,wing: String) -> bool:
	tested_floor=record.id
	candidate=ProgramFloor.new()
	add_child(candidate)
	var bad:=record.duplicate(true)
	bad["geometry"]={"length_m":1.0e12}
	check("invalid dimensions reject before state or construction",not candidate.build(bad).get("built",true) and candidate.get_child_count()==0 and candidate.rooms.is_empty() and candidate.doors.is_empty())
	bad=record.duplicate(true);bad["program"]="unimplemented_permanent_empty_room"
	check("unknown program rejects before construction",not candidate.build(bad).get("built",true) and candidate.get_child_count()==0)
	var result: Dictionary=candidate.build(record)
	if not check("selected furnished/colliding program floor builds",result.get("built",false),str(result)): return false
	check("all requested spaces have physical implementations",result.program_spaces_built==ProgramFloor.program_plan(record).space_count and result.furnishing_object_count>=result.program_rooms_built)
	check("runtime limits remain truthful",not result.current_private_asbuilt_verified and not result.integrated_city_traversal_verified and not result.all_program_floors_runtime_verified and not result.full_building_completed and not result.permanent_empty_fallback)
	transition_calls.clear()
	candidate.transition_requested.connect(func(_floor_id: String,portal_id: String,_kind: String): transition_calls[portal_id]=int(transition_calls.get(portal_id,0))+1)
	await frames(6)
	if bool(candidate.floor_record.geometry.atrium_void_active): check("real atrium void has no slab or hidden ceiling",ray(Vector3(0,4,0),Vector3(0,-1,0)).is_empty())
	var selected: Array[Dictionary] = []
	for cell: Dictionary in candidate.rooms:
		if cell.wing==wing: selected.append(cell)
	if not check("selected wing contains furnished cells",not selected.is_empty()): return false
	var first: Dictionary=selected[0]
	player.collision_layer=player_layer;player.collision_mask=mask
	player.show();player.process_mode=Node.PROCESS_MODE_INHERIT
	# The ONLY setup relocation. It is a local QA fixture, not a city approach.
	player.respawn_at(candidate.to_global(first.entry_local)+Vector3.UP*.10,0)
	await frames(25);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	travel=0;max_step=0;maximum_y=-INF;minimum_y=INF
	previous=player.global_position;tracking=true
	for cell: Dictionary in selected:
		if not await walk_public_to(cell.entry_local,wing): return false
		var outside: Vector3=candidate.to_global(cell.entry_local)
		var inside: Vector3=candidate.to_global(cell.inside_local)
		check("closed native program door physically blocks capsule "+String(cell.id),not capsule_clear(outside,inside))
		if cell.id==first.id and not await blocked_e(cell.id): return false
		if not await native_e(cell.id): return false
		if not check("opened native door clears full-size capsule "+String(cell.id),capsule_clear(outside,inside,"program door entry "+String(cell.id))): return false
		if not await walk_to(inside,.18): return false
		var view: Vector3=candidate.to_global(cell.view_local)
		if not check("reserved full-size aisle reaches furnished room back "+String(cell.id),capsule_clear(inside,view,"program left aisle "+String(cell.id))): return false
		if not await walk_to(view,.18): return false
		var look_at: Vector3=candidate.to_global(Vector3(float(cell.center_x),0,float(cell.inner_z)+float(cell.side)*float(cell.depth_m)*.55))
		var look:=look_at-player.global_position
		player.yaw=atan2(-look.x,-look.z)
		await frames(18)
		await still("program_"+String(record.id)+"_"+String(cell.program))
		if not await walk_to(inside,.18): return false
		if not await walk_to(outside,.18): return false
		runtime_program_doors.append(cell.id)
	var saved: Dictionary=candidate.serialize_state()
	candidate.set_door_open(first.id,false)
	await frames(60)
	var roundtrip: Dictionary=JSON.parse_string(JSON.stringify(saved))
	check("JSON door persistence restores native room doors",candidate.restore_state(roundtrip) and bool(candidate.doors[first.id].opened))
	var foreign:=roundtrip.duplicate(true);foreign.floor_id="WRONG-FLOOR"
	check("persistence refuses foreign floor state",not candidate.restore_state(foreign))
	await frames(60)
	for portal: Dictionary in candidate.portals:
		if portal.get("wing","")!=wing or not String(portal.kind) in ["guest_lift","service_lift"]: continue
		if not await walk_public_to(portal.landing,wing): return false
		await frames(20)
		check("lift is interlocked without root physical cabin "+String(portal.id),not candidate.set_door_open(portal.id,true))
		if not await native_e(portal.id,true): return false
	check("continuous selected-wing route has no jump/teleport/death",max_step<.50 and minimum_y>-.20 and Game.death_count==0,"travel%.2f maxstep%.4f minY%.3f"%[travel,max_step,minimum_y])
	tracking=false
	fixture_results.append({"floor_id":record.id,"wing":wing,"native_program_doors":runtime_program_doors.duplicate(),"travel_m":travel,"max_step_m":max_step,"minimum_y_m":minimum_y,"whole_floor_other_wing_runtime_verified":false,"whole_city_traversal_verified":false,"stairs_runtime_exercised":false,"pool_swimming_exercised":false})
	return failures.is_empty()

func still(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var folder:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mbs-program-stills-dir="): folder=arg.trim_prefix("--mbs-program-stills-dir=")
	if folder.is_empty(): return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check("actual production Player viewport capture "+label,get_viewport().get_texture().get_image().save_png(folder.path_join(label+".png"))==OK)

func walk_to(target: Vector3,radius: float) -> bool:
	# Turn in place before a new straight walking leg, as a human can. This
	# avoids a QA controller sprinting a broad 180-degree arc into furniture;
	# the actor still traverses every metre through the production controller.
	Input.action_release("move_forward");Input.action_release("sprint")
	await frames(6)
	for i in 60:
		var delta:=target-player.global_position
		if Vector2(delta.x,delta.z).length()<=radius: break
		var desired:=atan2(-delta.x,-delta.z)
		player.yaw=lerp_angle(player.yaw,desired,.24)
		if absf(wrapf(player.yaw-desired,-PI,PI))<.025: break
		await get_tree().physics_frame
	return await super.walk_to(target,radius)

func finish() -> void:
	if finished: return
	finished=true;tracking=false
	for action: String in ["move_forward","move_back","move_left","move_right","sprint","jump","interact"]: Input.action_release(action)
	var result: Dictionary={"checks":checks,"failed":failures.size(),"failures":failures,"elapsed_s":float(Time.get_ticks_msec()-_program_started)/1000.0,"planned_floor_coverage":plan_results,"runtime_fixture":fixture_results,"selected_floor":tested_floor,"selected_wing":tested_wing,"actual_native_program_doors":runtime_program_doors,"private_asbuilt_verified":false,"rendered_fidelity_accepted":false,"full_building_completed":false}
	print("[mbs-program-floor] RESULT ",JSON.stringify(result))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mbs-program-report="):
			var path:=arg.trim_prefix("--mbs-program-report=")
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var file:=FileAccess.open(path,FileAccess.WRITE)
			if file!=null: file.store_string(JSON.stringify(result,"\t")+"\n");file.close()
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures.is_empty() else 1)
