extends "res://src/systems/fidelity_tests/mbs_guest_floor_test.gd"
## Coupled actual-source cold-load/retire/stair proof. Initial actor setup only;
## no post-build translation, actor relocation, origin commit or cabin proof.
const SourceFrame = preload("res://src/world/geography/source_frame.gd")
const SourceContext = preload("res://src/world/geography/source_world_context.gd")
const SourceRuntime = preload("res://src/world/geography/source_runtime.gd")
const SourceDomain = preload("res://src/world/geography/source_domain.gd")
const SourceSite = preload("res://src/world/mbs_interior/site.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const Stack = preload("res://src/world/mbs_interior/floor_stack.gd")
var stack: Node3D
var source_frame: RefCounted
var source_context: RefCounted
var source_runtime: Node3D
var source_domain: RefCounted
var source_site: Node3D
var stack_metrics: Dictionary = {}
var _started_stack := 0
var _retirement_observations: Array[Dictionary] = []
var _known_bodies: Dictionary = {}
var _commit_events: Array[Dictionary] = []
var _guard_refuses := false
const LOWER := "T2-L24"
const UPPER := "T2-L25"
const REMOTE := "T3-L24"

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args(): get_tree().quit(2);return
	_started_stack=Time.get_ticks_msec()
	get_tree().create_timer(900.0,true,false,true).timeout.connect(func():
		if not finished:
			check("bounded source floor-stack verification",false)
			finish())
	run.call_deferred()

func check(label: String,ok: bool,detail: String = "") -> bool:
	checks+=1
	print("[mbs-floor-stack] %s %s %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok: failures.append(label)
	return ok

func _digest(value: String) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(value.to_utf8_buffer());return hash.finish().hex_encode()

func _unload_guard(_id: String) -> bool:
	return not _guard_refuses

func _collect_physical(node: Node,result: Array) -> void:
	if node is CollisionObject3D and node.collision_layer!=0: result.append(node)
	for child: Node in node.get_children(): _collect_physical(child,result)

func _on_committed(id: String,generation: String) -> void:
	var module: Node3D=stack.get_floor(id)
	var bodies: Array=[]
	if is_instance_valid(module): _collect_physical(module,bodies)
	var references: Array=[]
	for body: CollisionObject3D in bodies: references.append(weakref(body))
	_known_bodies[id]=references
	_commit_events.append({"id":id,"generation":generation,"body_count":bodies.size(),"floor_ready_at_event":stack.floor_ready(id),"physics_tick":Engine.get_physics_frames()})

func _on_retired(id: String,region: String) -> void:
	var alive:=0;var stamps_removed:=true
	for reference: WeakRef in _known_bodies.get(id,[]):
		var body: Variant=reference.get_ref()
		if is_instance_valid(body):
			alive+=1
			if body is StaticBody3D: stamps_removed=stamps_removed and not body.has_meta(SourceContext.COLLIDER_META)
	var regions: Dictionary=source_runtime.get("_regions")
	_retirement_observations.append({"id":id,"region_absent_before_free":not regions.has(region),"bodies_still_alive":alive,"static_stamps_removed":stamps_removed,"physics_tick":Engine.get_physics_frames()})

func run() -> void:
	Game.simulation_paused=false;Game.mode=Game.MODE_FOOT;Game.health=Game.MAX_HEALTH;Game.death_count=0
	var raw:=FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json")
	var manifest: Dictionary=JSON.parse_string(raw)
	var lower_record:=Inventory.floor_record(LOWER)
	var tower: Dictionary=Reference.DATA.towers[1]
	var origin: Array=[tower.centroid_world_xz[0],float(lower_record.elevation_m),tower.centroid_world_xz[1]]
	source_frame=SourceFrame.new()
	if not check("real source frame uses actual T2 centroid and inventory elevation",source_frame.configure(manifest.georeference,origin,_digest(raw),{"status":"staging","reference":"MBS reconstructed hotel L1=0; surveyed vertical datum unresolved","source_reference":"Pinned OSM frame and explicit inventory elevation reconstruction"})): finish();return
	source_context=SourceContext.new()
	var profile: Dictionary={"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":cos(deg_to_rad(52.0)),"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}
	var geometry:=_digest(FileAccess.get_file_as_string("res://src/world/mbs_interior/floor_stack.gd")+FileAccess.get_file_as_string("res://src/world/mbs_interior/guest_floor.gd")+FileAccess.get_file_as_string("res://src/world/mbs_interior/program_floor.gd")+FileAccess.get_file_as_string(Inventory.PATH))
	if not check("shared live World3D context is explicit",source_context.configure(source_frame,geometry,_digest("MBS L1=0 reconstructed inventory elevations; no surveyed datum claim"),profile,get_world_3d())): finish();return
	source_domain=SourceDomain.new()
	if not check("actual pinned Singapore domain loads",source_domain.configure("res://data/geography/domain/osm-2026-10-27","82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834",_digest(raw))): finish();return
	for descriptor: Dictionary in source_domain.provider_descriptors(): check("actual domain provider "+String(descriptor.kind),source_context.register_provider(descriptor.kind,descriptor.provider_id,descriptor.source_reference))
	check("native collision provider explicit",source_context.register_provider("physics","source-native-neighborhood/v1","Owned actual-source site/floor-stack native physics commit"))
	source_runtime=SourceRuntime.new();add_child(source_runtime)
	if not check("runtime uses same frame/context/domain owner",source_runtime.configure(source_frame,source_context,source_domain.observe)): finish();return
	source_site=SourceSite.new();add_child(source_site)
	var public_result: Dictionary=source_site.build(source_frame,source_context,source_runtime)
	if not check("existing public site shares actual frame and no duplicate fictional hotel",public_result.get("built",false),str(public_result.get("error",""))): finish();return
	await frames(3)
	if not check("public source site native collision committed",source_site.commit_native_floor().ok): finish();return
	stack=Stack.new();add_child(stack)
	if not check("stack configures explicit common refs and datum",stack.configure(source_frame,source_context,source_runtime,0.0,"Reconstructed hotel L1=0 for native stack proof; external vertical datum unresolved",{"max_active_floors":6,"max_pending_requests":3,"auto_stream":false,"unload_guard":_unload_guard})): finish();return
	stack.floor_committed.connect(_on_committed);stack.floor_retired.connect(_on_retired)
	check("cold floor cannot claim collision or shaft readiness",not stack.floor_ready(LOWER) and not stack.ready_for_floor(LOWER).travel_ready and stack.get_floor(LOWER)==null)
	var seed: Dictionary=stack.serialize_state()
	var source_unit_id: String=lower_record.units[0].id
	seed.floor_doors[LOWER]={"floor_id":LOWER,"room_doors":{source_unit_id:false},"current_private_asbuilt_verified":false}
	check("empty-stack door JSON accepts actual R-prefixed source unit ID",stack.restore_state(seed) and stack.get_child_count()==0)
	var foreign_seed:=seed.duplicate(true)
	foreign_seed.floor_doors[LOWER].room_doors[Inventory.floor_record(REMOTE).units[0].id]=true
	check("door JSON rejects another floor's source unit without partial mutation",not stack.restore_state(foreign_seed) and stack.serialize_state().floor_doors[LOWER].room_doors.size()==1)
	var duplicate:=Stack.new();add_child(duplicate)
	check("duplicate geometry authority for same source context refused",not duplicate.configure(source_frame,source_context,source_runtime,0.0,"Duplicate rejected fixture",{"auto_stream":false}))
	duplicate.queue_free();await frames(3)
	var missing: Dictionary=await stack.ensure_floor("SHOPPES-L1")
	check("missing resort anchor remains transient without placeholder",not missing.ready and missing.status=="pending_root_source_mapping" and stack.get_child_count()==0)
	var mezz: Dictionary=await stack.ensure_floor("T2-B2M")
	check("incompatible actual mezzanine rise fails without flattening or empty floor",not mezz.ready and mezz.status=="pending_root_recipe_change" and mezz.get("actual_rise_m",0)==2.5 and stack.get_child_count()==0,str(mezz))
	# Actual registrations exercise narrow spa voids and roof-pool exclusions,
	# with NO actor in these local programs and no swimming/fit-out claim.
	var spa: Dictionary=await stack.ensure_floor("T2-L5")
	if not check("actual source spa neighbourhood cold-loads",spa.ready,str(spa)): finish();return
	var spa_node: Node3D=stack.get_floor("T2-L5")
	var source_void: Dictionary=source_frame.to_source_current_live(spa_node.to_global(Vector3(0,.5,0)))
	var begun: Dictionary=source_context.begin_query(source_void.source_xyz)
	var void_state: Dictionary=source_context.evaluate(begun.query,{})
	check("registered source dry volumes do not fill spa atrium void",void_state.indoor.dry_volume_matches.is_empty())
	for id: String in ["T2-L4","T2-L5","T2-L6"]:
		var retired: Dictionary=await stack.unload_floor(id)
		if not check("empty spa neighbour safely retires "+id,retired.ok,str(retired)): finish();return
	var roof: Dictionary=await stack.ensure_floor("T3-L57")
	if not check("roof program source modules register actual pool exclusion",roof.ready,str(roof)): finish();return
	var roof_node: Node3D=stack.get_floor("T3-L57")
	var pool: Dictionary={}
	for object: Dictionary in roof_node.furnishings:
		if object.kind=="pool": pool=object;break
	if not check("actual roof module has its reconstructed pool geometry",not pool.is_empty()): finish();return
	var source_pool: Dictionary=source_frame.to_source_current_live(roof_node.to_global((pool.position as Vector3)+Vector3.UP*.10))
	begun=source_context.begin_query(source_pool.source_xyz)
	var pool_state: Dictionary=source_context.evaluate(begun.query,{})
	check("registered dry volumes exclude actual pool footprint",pool_state.indoor.dry_volume_matches.is_empty())
	check("terminal roof has receiving-only stair portals",roof_node.portals.any(func(portal: Dictionary): return portal.kind=="stair" and portal.get("receiving_only",false)))
	for id: String in ["T3-L56","T3-L57"]:
		var retired: Dictionary=await stack.unload_floor(id)
		if not check("empty roof component safely retires "+id,retired.ok,str(retired)): finish();return
	var lower: Dictionary=await stack.ensure_floor(LOWER)
	if not check("lower guest source floor waits for both committed neighbours",lower.ready and stack.floor_ready(LOWER),str(lower)): finish();return
	var upper: Dictionary=await stack.ensure_floor(UPPER)
	if not check("second adjacent full guest source floor commits before walking",upper.ready and stack.floor_ready(UPPER),str(upper)): finish();return
	for id: String in [LOWER,UPPER]:
		var node: Node3D=stack.get_floor(id)
		var actual: Dictionary=source_frame.to_source_current_live(node.global_position)
		var rec:=Inventory.floor_record(id)
		check("actual double source anchor preserved "+id,absf(float(actual.source_xyz[0])-float(tower.centroid_world_xz[0]))<.001 and absf(float(actual.source_xyz[2])-float(tower.centroid_world_xz[1]))<.001 and absf(float(actual.source_xyz[1])-float(rec.elevation_m))<.001)
		check("real nonaxis source basis and metric scale "+id,node.global_basis.is_equal_approx(Basis(Vector3(Reference.DATA.axis_south_xz[0],0,Reference.DATA.axis_south_xz[1]),Vector3.UP,Vector3(Reference.DATA.axis_bayward_xz[0],0,Reference.DATA.axis_bayward_xz[1]))) and node.global_basis.get_scale().is_equal_approx(Vector3.ONE))
		check("only stable static floor bodies are stamped "+id,stack.floor_state(id).static_support_count>0 and stack.floor_state(id).body_count>stack.floor_state(id).static_support_count)
	check("floor commits never imply cabin/shaft travel readiness",not stack.ready_for_floor(LOWER).travel_ready and not stack.ready_for_floor(UPPER).travel_ready)
	if not prepare_player(): finish();return
	_light_fixture()
	candidate=stack.get_floor(LOWER)
	var cell: Dictionary={}
	for item: Dictionary in candidate.rooms:
		if item.wing=="west": cell=item;break
	if not check("actual lower source floor has west guest room",not cell.is_empty()): finish();return
	player.collision_layer=player_layer;player.collision_mask=mask;player.show()
	# Only initial QA setup, already at the actual source-frame projection.
	player.respawn_at(candidate.to_global(cell.entry_local)+Vector3.UP*.10,0)
	if not check("production Player binds to same source runtime",source_runtime.bind_player(player)): finish();return
	player.process_mode=Node.PROCESS_MODE_INHERIT
	await frames(35);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	previous=player.global_position;travel=0;max_step=0;minimum_y=INF;maximum_y=-INF;tracking=true
	var source_state: Dictionary=source_runtime.inspect_player(player)
	if not check("native source floor support and registered dry domain",source_state.get("ok",false) and source_state.support.get("floor_id","")==LOWER and source_state.water.state=="dry_indoor",str(source_state)): finish();return
	var denied: Dictionary=await stack.unload_floor(LOWER)
	check("occupied source floor cannot retire",not denied.ok and denied.status=="protected" and stack.floor_ready(LOWER))
	denied=await stack.unload_floor(UPPER)
	check("occupied floor stair neighbour cannot retire",not denied.ok and denied.status=="protected" and stack.get_floor(UPPER)!=null)
	if not await blocked_e(cell.id): finish();return
	if not await native_e(cell.id): finish();return
	if not await walk_to(candidate.to_global(cell.inside_local),.18): finish();return
	if not await walk_to(candidate.to_global(cell.entry_local),.18): finish();return
	var remote_loaded: Dictionary=await stack.ensure_floor(REMOTE)
	if not check("bounded cold remote load preserves occupied neighbour set",remote_loaded.ready and stack.floor_ready(LOWER) and stack.report().active_floor_count<=6,str(remote_loaded)): finish();return
	var remote: Node3D=stack.get_floor(REMOTE)
	var remote_id: String=remote.rooms[0].id
	# Explicit empty-floor state fixture, NOT a claim of native E at a remote
	# actor position. Actual native E was exercised above without relocation.
	remote.set_door_open(remote_id,true);await frames(65)
	var old_generation: String=stack.ready_for_floor(REMOTE).collision_generation
	var registered_before: int=source_context.metadata().registered_floor_count
	check("explicit remote pin accepted",stack.pin_floor(REMOTE,"qa-empty-state-roundtrip"))
	denied=await stack.unload_floor(REMOTE)
	check("pinned floor cannot retire",not denied.ok and denied.status=="protected")
	stack.unpin_floor(REMOTE,"qa-empty-state-roundtrip")
	_guard_refuses=true
	denied=await stack.unload_floor(REMOTE)
	check("root cabin unload guard can hold owned floor",not denied.ok and denied.status=="cabin_guard" and stack.get_floor(REMOTE)!=null)
	_guard_refuses=false
	var retired: Dictionary=await stack.unload_floor(REMOTE)
	if not check("empty floor retires before owned node destruction",retired.ok and stack.get_floor(REMOTE)==null and not stack.floor_ready(REMOTE),str(retired)): finish();return
	var reloaded: Dictionary=await stack.ensure_floor(REMOTE)
	if not check("cold reload creates fresh collision generation",reloaded.ready and reloaded.collision_generation!=old_generation,str(reloaded)): finish();return
	remote=stack.get_floor(REMOTE)
	check("source-ID door state survives retire/reload",bool(remote.doors[remote_id].opened) and absf(float(remote.doors[remote_id].motion_angle)-(float(remote.doors[remote_id].base_angle)+float(remote.doors[remote_id].swing_delta)))<.002)
	check("reload reuses immutable source-floor identity",source_context.metadata().registered_floor_count==registered_before)
	upper=await stack.ensure_floor(UPPER)
	if not check("upper receiving full floor is committed before actual stair travel",upper.ready): finish();return
	var stairs: Dictionary={}
	for portal: Dictionary in candidate.portals:
		if portal.kind=="stair" and portal.wing==cell.wing: stairs=portal;break
	if not check("actual lower U-stair portal exists",not stairs.is_empty()): finish();return
	if not await walk_public_to(stairs.lower,cell.wing): finish();return
	for target: Vector3 in stairs.walk_route:
		if not await walk_to(candidate.to_global(target),.22): finish();return
	if not await walk_to(candidate.to_global(stairs.upper),.18): finish();return
	var rise: float=float(Inventory.floor_record(UPPER).elevation_m)-float(lower_record.elevation_m)
	check("actual adjacent elevation drives copied stair rise",is_equal_approx(float(candidate.floor_record.geometry.storey_height_m),rise))
	source_state=source_runtime.inspect_player(player)
	if not check("actual receiving full floor supports production Player",source_state.get("ok",false) and source_state.support.get("floor_id","")==UPPER and absf(player.global_position.y-(rise-.025))<.06,str(source_state)): finish();return
	denied=await stack.unload_floor(LOWER)
	check("upper occupant protects lower stair neighbour",not denied.ok and denied.status=="protected")
	for index in range(stairs.walk_route.size()-1,-1,-1):
		if not await walk_to(candidate.to_global(stairs.walk_route[index]),.22): finish();return
	check("continuous source stair/room walking has no actor relocation or death",max_step<.50 and minimum_y>-.20 and maximum_y>rise-.20 and Game.death_count==0,"travel%.2f maxstep%.4f minY%.3f maxY%.3f"%[travel,max_step,minimum_y,maximum_y])
	check("retirement events observed actual native stamps removed before free",not _retirement_observations.is_empty() and _retirement_observations.all(func(item: Dictionary): return item.region_absent_before_free and item.bodies_still_alive>0 and item.static_stamps_removed))
	check("source frame epoch was never committed by streamer",source_frame.metadata().origin_revision==0 and stack.report().origin_commits_performed==0 and stack.report().actor_pose_mutations==0)
	stack_metrics={"actual_source_origin_xyz":origin,"source_frame_revision":source_frame.metadata().origin_revision,"lower":LOWER,"upper":UPPER,"distance_m":travel,"max_step_m":max_step,"native_room_door":cell.id,"remote_state_seed":"EXPLICIT_EMPTY_FLOOR_API_NOT_NATIVE_REMOTE_E","stack_report":stack.report(),"commit_events":_commit_events,"retirements":_retirement_observations,"whole_building_completed":false,"cabin_travel_verified":false,"swimming_or_pool_ceiling_clearance_verified":false}
	finish()

func finish() -> void:
	if finished: return
	finished=true;tracking=false
	for action: String in ["move_forward","move_back","move_left","move_right","sprint","walk","jump","interact"]: Input.action_release(action)
	var result: Dictionary={"checks":checks,"failed":failures.size(),"failures":failures,"elapsed_s":float(Time.get_ticks_msec()-_started_stack)/1000.0,"metrics":stack_metrics,"whole_building_completed":false,"rendered_fidelity_accepted":false,"owner_playtest":false}
	print("[mbs-floor-stack] RESULT ",JSON.stringify(result))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mbs-floor-stack-report="):
			var path:=arg.trim_prefix("--mbs-floor-stack-report=");DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var file:=FileAccess.open(path,FileAccess.WRITE)
			if file!=null: file.store_string(JSON.stringify(result,"\t")+"\n");file.close()
	Sfx.shutdown_audio();get_tree().quit(0 if failures.is_empty() else 1)
