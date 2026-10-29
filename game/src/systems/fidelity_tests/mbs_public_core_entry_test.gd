extends "res://src/systems/fidelity_tests/mbs_guest_floor_test.gd"
## Actual-source exterior facade -> reserved L1 arrival -> tall loft -> all
## three source L1 east cores. One setup spawn; production Player/E throughout.
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const Site = preload("res://src/world/mbs_interior/site.gd")
const PublicL1 = preload("res://src/world/mbs_interior/public_l1.gd")
const ProgramFloor = preload("res://src/world/mbs_interior/program_floor.gd")
const Stack = preload("res://src/world/mbs_interior/floor_stack.gd")
const Hotel = preload("res://src/world/mbs_interior/hotel.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
var frame: RefCounted
var context: RefCounted
var runtime: Node3D
var domain: RefCounted
var site: Node3D
var stack: Node3D
var hotel: Node3D
var _started_core := 0
var _source_support_gates: Array[Dictionary] = []
var _native_core_actions: Array[Dictionary] = []
var _metrics: Dictionary = {}

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args(): get_tree().quit(2);return
	_started_core=Time.get_ticks_msec()
	get_tree().create_timer(900.0,true,false,true).timeout.connect(func():
		if not finished:
			check("bounded actual-source public/core entry",false)
			finish())
	run.call_deferred()

func check(label: String,ok: bool,detail: String = "") -> bool:
	checks+=1
	print("[mbs-public-core-entry] %s %s %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok: failures.append(label)
	return ok

func _digest(text: String) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(text.to_utf8_buffer());return hash.finish().hex_encode()

func _transaction_checks(config: Dictionary) -> bool:
	var loft:=PublicL1.new();add_child(loft)
	var original:=loft.transform
	var bad:=config.duplicate(true);bad["source_frame"]=frame
	bad.core_connections[0].width_m=NAN
	check("nonfinite core rejects before geometry/state/transform mutation",not loft.build(bad).get("built",true) and loft.get_child_count()==0 and loft.zones.is_empty() and loft.core_connections.is_empty() and loft.transform==original)
	bad=config.duplicate(true);bad["source_frame"]=frame
	bad.arrival_corridor.target_cross_m=1.0e8
	check("unsupported arrival rejects transactionally",not loft.build(bad).get("built",true) and loft.get_child_count()==0 and loft.zones.is_empty() and loft.arrival_corridor.is_empty() and loft.transform==original)
	var legacy: Dictionary=loft._validated_plan({"source_frame":frame})
	check("legacy default plan still has original entrance and no optional connections",legacy.get("valid",false) and legacy.core_connections.is_empty() and legacy.arrival_corridor.is_empty() and legacy.door_width==4.0 and legacy.door_height==4.8 and loft.get_child_count()==0)
	loft.queue_free();await frames(3)
	var program:=ProgramFloor.new();add_child(program)
	var invalid:=Inventory.floor_record("T1-L1")
	invalid.geometry.atrium_void_active=true;invalid.geometry.void_min_z_m=-20.0;invalid.geometry.void_max_z_m=20.0
	invalid.geometry.public_arrival_corridor={"id":"T1-L1-west-arrival","wing":"west","center_x":0.0,"width_m":2.6,"height_m":2.7}
	check("arrival without matching physical guard opening rejects before construction",not program.build(invalid).get("built",true) and program.get_child_count()==0 and program.rooms.is_empty())
	program.queue_free();await frames(3)
	return failures.is_empty()

func _opening_queries(loft: Node3D,connection: Dictionary,arrival: bool) -> bool:
	var side: float=1.0 if arrival else float(connection.side_sign)
	var threshold: Vector3=connection.outer_facade_local if arrival else connection.glass_threshold_local
	var from: Vector3=threshold-Vector3(0,-.004,side*.85)
	var to: Vector3=connection.target_corridor_local
	if arrival:
		from=threshold+Vector3(0,.004,.85);to=threshold+Vector3(0,.004,-.85)
	for aperture_offset: float in [0.0,-(float(connection.width_m)*.5-.45),float(connection.width_m)*.5-.45]:
		if not check("actual full capsule clears intended opening "+String(connection.id)+"/"+str(aperture_offset),capsule_clear(loft.to_global(from+Vector3(aperture_offset,0,0)),loft.to_global(to+Vector3(aperture_offset,0,0)))): return false
	for direction: float in [-1.0,1.0]:
		var outside_offset: float=direction*(float(connection.width_m)*.5+1.0)
		var a: Vector3=threshold+Vector3(outside_offset,0,-side*.85)
		var b: Vector3=threshold+Vector3(outside_offset,0,side*.85)
		if arrival:
			a=threshold+Vector3(outside_offset,0,.85);b=threshold+Vector3(outside_offset,0,-.85)
		check("outside-cut wall blocks actual capsule "+String(connection.id)+"/"+str(direction),not capsule_clear(loft.to_global(a),loft.to_global(b)))
		check("outside-cut full-height glass remains above low guard "+String(connection.id)+"/"+str(direction),not ray(loft.to_global(a+Vector3.UP*1.70),loft.to_global(b+Vector3.UP*1.70)).is_empty())
	return failures.is_empty()

func _support_gate(label: String) -> bool:
	var state: Dictionary=runtime.inspect_player(player)
	var ok: bool=state.get("ok",false) and state.support.state=="supported" and state.water.state=="dry_indoor" and Game.death_count==0
	_source_support_gates.append({"label":label,"ok":ok,"source_xyz":state.get("source_xyz",[]),"support":state.get("support",{}),"water":state.get("water",{}).get("state","")})
	return check("actual source support and dry envelope "+label,ok,str(state.get("support",{})))

func _walk_public_route(loft: Node3D,route: Array,label: String) -> bool:
	for index in route.size():
		walk_stage=label+"/"+str(index)
		if not await walk_to(loft.to_global(route[index]),.18): return false
		if not _support_gate(walk_stage): return false
	return true

func run() -> void:
	Game.simulation_paused=false;Game.mode=Game.MODE_FOOT;Game.health=Game.MAX_HEALTH;Game.death_count=0
	var raw:=FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json")
	var manifest: Dictionary=JSON.parse_string(raw)
	frame=Frame.new()
	var origin: Array=[Reference.DATA.origin_world_xz[0],0.0,Reference.DATA.origin_world_xz[1]]
	if not check("actual uncompressed source frame and staged datum",frame.configure(manifest.georeference,origin,_digest(raw),{"status":"staging","reference":"Reconstructed MBS L1=0; vertical datum not surveyed","source_reference":"Actual OSM source centroids/axes and explicit reconstructed public/perimeter programs"})): finish();return
	domain=Domain.new()
	if not check("actual pinned Singapore domain loads",domain.configure("res://data/geography/domain/osm-2026-10-27","82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834",_digest(raw))): finish();return
	context=Context.new()
	var profile: Dictionary={"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":cos(deg_to_rad(52.0)),"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}
	var geometry_manifest_hash: String=_digest(FileAccess.get_file_as_string("res://src/world/mbs_interior/public_l1.gd")+FileAccess.get_file_as_string("res://src/world/mbs_interior/program_floor.gd")+FileAccess.get_file_as_string("res://src/world/mbs_interior/floor_stack.gd")+FileAccess.get_file_as_string("res://src/world/mbs_interior/hotel.gd")+FileAccess.get_file_as_string(Inventory.PATH))
	if not check("one live context binds public/perimeter/transport",context.configure(frame,geometry_manifest_hash,_digest("Explicit reconstructed L1=0; no surveyed elevation claim"),profile,get_world_3d())): finish();return
	for provider_descriptor: Dictionary in domain.provider_descriptors(): check("actual domain provider "+String(provider_descriptor.kind),context.register_provider(provider_descriptor.kind,provider_descriptor.provider_id,provider_descriptor.source_reference))
	check("native physics provider explicit",context.register_provider("physics","source-native-neighborhood/v1","Actual source public/core/arrival/floor/transport commitments"))
	runtime=Runtime.new();add_child(runtime)
	if not check("runtime retains actual shared domain and common frame",runtime.configure(frame,context,domain.observe)): finish();return
	var config: Dictionary={"core_connections":PublicL1.default_core_connection_requests(0.0),"arrival_corridor":PublicL1.default_arrival_request(0.0)}
	if not await _transaction_checks(config): finish();return
	stack=Stack.new();add_child(stack)
	if not check("matched copied L1 geometry configures before source construction",stack.configure(frame,context,runtime,0.0,"Explicit reconstructed MBS L1=0; no surveyed/private floorplan claim",{"max_active_floors":12,"auto_stream":false,"public_core_connections":config.core_connections,"public_arrival_corridor":config.arrival_corridor})): finish();return
	site=Site.new();add_child(site)
	var built: Dictionary=site.build(frame,context,runtime,config)
	if not check("actual source Site builds matched public/arrival apertures",built.get("built",false),str(built.get("error",""))): finish();return
	await frames(3)
	if not check("actual public source collision commits with normalized dry volumes",site.commit_native_floor().ok): finish();return
	var loft: Node3D=site.public_l1
	var report: Dictionary=loft.report()
	if not check("three cores and actual exterior arrival are explicit",report.core_connections.size()==3 and not report.arrival_corridor.is_empty() and report.arrival_corridor.local_route.size()>=6): finish();return
	for tower: String in ["T1","T2","T3"]:
		var ready: Dictionary=await stack.ensure_floor(tower+"-L2")
		if not check("source L2/full neighbours cold commit "+tower,ready.ready,str(ready)): finish();return
		ready=await stack.ensure_floor(tower+"-L1")
		if not check("actual source L1/perimeter/upper/lower neighbours commit "+tower,ready.ready,str(ready)): finish();return
		var l1_floor: Node3D=stack.get_floor(tower+"-L1")
		check("all named L1 programs remain furnished "+tower,l1_floor.report().program_spaces_built==Inventory.floor_record(tower+"-L1").program_spaces.size() and not l1_floor.rooms.is_empty())
		check("paired physical guard aperture forwarded "+tower,not l1_floor.floor_record.geometry.get("atrium_core_openings",[]).is_empty())
	var arrival: Dictionary=report.arrival_corridor
	var t1: Node3D=stack.get_floor("T1-L1")
	var facade_expected: Vector3=t1.to_global(Vector3(0,0,float(t1.floor_record.geometry.cross_m)*.5))
	check("arrival facade adapter matches actual source Program outer wall",facade_expected.distance_to(loft.to_global(arrival.outer_facade_local))<.002)
	for connection: Dictionary in report.core_connections:
		var join_floor: Node3D=stack.get_floor(connection.target_floor_id)
		var actual_local: Vector3=join_floor.to_local(loft.to_global(connection.target_corridor_local))
		var expected_z: float=float(join_floor.floor_record.geometry.void_min_z_m)-float(join_floor.floor_record.geometry.corridor_width_m)*.5
		var canonical: Dictionary=frame.to_source_current_live(loft.to_global(connection.target_corridor_local))
		var error:=0.0
		for axis in 3: error=maxf(error,absf(float(canonical.source_xyz[axis])-float(connection.target_source_xyz[axis])))
		check("exact actual source L1 corridor join and zero height difference "+String(connection.tower),absf(actual_local.x-float(connection.along_offset_m))<.002 and absf(actual_local.z-expected_z)<.002 and absf(actual_local.y)<.002 and error<.002,str({"actual_local":actual_local,"target_source_xyz":connection.target_source_xyz,"canonical_error_m":error}))
	var gap: Dictionary=t1.floor_record.geometry.public_arrival_corridor
	var left_edge:=-INF;var right_edge:=INF
	for room: Dictionary in t1.rooms:
		if room.wing!="west": continue
		var lo: float=float(room.center_x)-float(room.frontage_m)*.5
		var hi: float=float(room.center_x)+float(room.frontage_m)*.5
		if hi<0: left_edge=maxf(left_edge,hi+.075)
		if lo>0: right_edge=minf(right_edge,lo-.075)
	check("reflowed west programs retain actual full-width arrival aisle",is_finite(left_edge) and is_finite(right_edge) and right_edge-left_edge>=2.6-.001 and gap.width_m==2.6,str([left_edge,right_edge]))
	hotel=Hotel.new();add_child(hotel)
	var specs: Array=[]
	for tower: String in ["T1","T2","T3"]: specs.append({"tower":tower,"wing":"east","kind":"guest_lift","initial_floor_id":tower+"-L1"})
	var transport: Dictionary=await hotel.build(frame,context,runtime,stack,0.0,specs)
	if not check("actual source Hotel binds real native lift/stair interfaces",transport.get("built",false),str(transport)): finish();return
	await frames(20)
	if not prepare_player(): finish();return
	_light_fixture()
	if not _opening_queries(loft,arrival,true): finish();return
	for connection: Dictionary in report.core_connections:
		if not _opening_queries(loft,connection,false): finish();return
	# The only setup pose is outside the actual modeled outer T1 facade, not
	# the former point hidden inside a reconstructed west program/party wall.
	var spawn: Vector3=loft.to_global(arrival.local_route[0])
	var source_spawn: Array=frame.to_source_current_live(spawn).source_xyz
	var facade: Vector3=loft.to_global(arrival.outer_facade_local)
	check("initial pose is outside actual source-positioned outer facade",spawn.distance_to(facade)>3.5 and (loft.to_local(spawn)).z>(arrival.outer_facade_local as Vector3).z+3.5)
	check("production public walking route now starts outside actual facade",loft.walking_route_world()[0].distance_to(spawn)<.002)
	player.collision_layer=player_layer;player.collision_mask=mask;player.show()
	player.respawn_at(spawn+Vector3.UP*.10,0)
	if not check("production Player binds to same source runtime",runtime.bind_player(player)): finish();return
	player.process_mode=Node.PROCESS_MODE_INHERIT;await frames(35);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	source_spawn=frame.to_source_current_live(player.global_position).source_xyz
	previous=player.global_position;travel=0;max_step=0;minimum_y=INF;maximum_y=-INF;tracking=true
	if not _support_gate("outside actual facade"): finish();return
	await still("01_outside_T1_actual_facade")
	if not await _walk_public_route(loft,arrival.local_route,"exterior arrival through real reserved corridor"): finish();return
	await still("02_arrived_in_tall_public_loft")
	for connection: Dictionary in report.core_connections:
		if not await _walk_public_route(loft,connection.local_route,"loft to "+String(connection.id)): finish();return
		candidate=stack.get_floor(connection.target_floor_id)
		var lift: Dictionary={};var stair: Dictionary={}
		for portal: Dictionary in candidate.portals:
			if portal.get("wing","")!="east": continue
			if portal.kind=="guest_lift": lift=portal
			if portal.kind=="stair": stair=portal
		if not check("native source lift and stair interfaces exist "+String(connection.tower),not lift.is_empty() and not stair.is_empty()): finish();return
		if not await walk_public_to(lift.landing,"east"): finish();return
		if not await native_e(lift.id): finish();return
		_native_core_actions.append({"tower":connection.tower,"kind":"guest_lift","id":lift.id,"source_position":frame.to_source_current_live(player.global_position).source_xyz,"actual_E":true})
		if not _support_gate("native L1 lift "+String(connection.tower)): finish();return
		await still("core_"+String(connection.tower)+"_native_lift")
		if not await walk_public_to(stair.lower,"east"): finish();return
		# Stop before the closed fire door on the REAL upper landing, matching
		# its existing constrained native fixture; no gate/collider is bypassed.
		for ascending_index in stair.walk_route.size()-1:
			if not await walk_to(candidate.to_global(stair.walk_route[ascending_index]),.22): finish();return
		var stairs: Node3D=hotel.get("_stairs")
		var door_id: String=String(connection.target_floor_id)+"-east-stair-fire-door"
		var door: Node3D=stairs.doors.get(door_id)
		if not check("actual interlocked source stair door present "+String(connection.tower),door!=null): finish();return
		var stair_descriptor: Dictionary={}
		for gate_geometry: Dictionary in stairs.geometry_descriptor(connection.target_floor_id).gates:
			if gate_geometry.wing=="east": stair_descriptor=gate_geometry;break
		if not check("exact east stair geometry descriptor present "+String(connection.tower),not stair_descriptor.is_empty()): finish();return
		var approach:=Vector3(stair.upper.x,float(candidate.floor_record.geometry.storey_height_m),float(stair_descriptor.gate_plane_z_local_m)-.62)
		if not await walk_to(candidate.to_global(approach),.12): finish();return
		var floor_node: Node3D=candidate;candidate=stairs
		if not await native_e(door_id): finish();return
		candidate=floor_node
		_native_core_actions.append({"tower":connection.tower,"kind":"stair_fire_door","id":door_id,"source_position":frame.to_source_current_live(player.global_position).source_xyz,"actual_E":true})
		if not await walk_to(candidate.to_global(stair.upper),.18): finish();return
		if not _support_gate("actual upper receiving floor "+String(connection.tower)): finish();return
		for descending_index in range(stair.walk_route.size()-1,-1,-1):
			if not await walk_to(candidate.to_global(stair.walk_route[descending_index]),.22): finish();return
		if not await walk_public_to(candidate.to_local(loft.to_global(connection.target_corridor_local)),"east"): finish();return
		var reverse: Array=connection.local_route.duplicate();reverse.reverse()
		if not await _walk_public_route(loft,reverse,"return from "+String(connection.id)): finish();return
	check("three actual source cores reached with six native door actions",_native_core_actions.size()==6)
	check("continuous exterior/loft/core route has no teleport jump or death",travel>250 and max_step<.50 and minimum_y>-.20 and Game.death_count==0,"travel%.2f maxstep%.4f minY%.3f"%[travel,max_step,minimum_y])
	check("visual/source completion claims remain false",not report.architectural_identity_and_fitout_verified and not report.full_requested_interior_verified and frame.metadata().origin_revision==0 and hotel.report().actor_pose_writes==0)
	_metrics={"distance_m":travel,"max_step_m":max_step,"source_support_gates":_source_support_gates,"native_core_actions":_native_core_actions,"actual_source_spawn_xyz":source_spawn,"arrival":arrival,"core_connections":report.core_connections,"public_visual_fidelity_accepted":false,"all_private_asbuilt_verified":false,"whole_building_completed":false,"one_initial_spawn_no_later_actor_pose_writes":true}
	finish()

func still(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var folder:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mbs-public-core-stills-dir="): folder=arg.trim_prefix("--mbs-public-core-stills-dir=")
	if folder.is_empty(): return
	DirAccess.make_dir_recursive_absolute(folder);await RenderingServer.frame_post_draw
	check("actual Player source viewport capture "+label,get_viewport().get_texture().get_image().save_png(folder.path_join(label+".png"))==OK)

func finish() -> void:
	if finished: return
	finished=true;tracking=false
	for action: String in ["move_forward","move_back","move_left","move_right","sprint","walk","jump","interact"]:
		if InputMap.has_action(action): Input.action_release(action)
	var result: Dictionary={"checks":checks,"failed":failures.size(),"failures":failures,"elapsed_s":float(Time.get_ticks_msec()-_started_core)/1000.0,"metrics":_metrics,"native_actions":_native_core_actions,"whole_building_completed":false,"public_visual_fidelity_accepted":false,"owner_playtest":false}
	print("[mbs-public-core-entry] RESULT ",JSON.stringify(result))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mbs-public-core-report="):
			var path:=arg.trim_prefix("--mbs-public-core-report=");DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var file:=FileAccess.open(path,FileAccess.WRITE)
			if file!=null: file.store_string(JSON.stringify(result,"\t")+"\n");file.close()
	Sfx.shutdown_audio();get_tree().quit(0 if failures.is_empty() else 1)
