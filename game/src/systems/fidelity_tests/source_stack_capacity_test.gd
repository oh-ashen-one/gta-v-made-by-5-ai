extends Node3D
## Actual native floor preparation/occupancy capacity gate. All floor modules
## are production factories at their source anchors; no tiny proxy recipes.
## This does NOT claim full Hotel cabin/stair traversal or rendered quality.
const Stack = preload("res://src/world/mbs_interior/floor_stack.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const CURRENT := "T1-L24"
const NEXT := "T1-L25"
const PIN_OWNER := "qa-three-source-entries"
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var output := ""
var finished := false
var _started_us := 0
var _last_progress_us := 0
var _phase := "setup"
var _active_cap := 0
var _scope: Node3D
var _stack: Node3D
var _runtime: Node3D
var _context: RefCounted
var _frame: RefCounted
var _domain: RefCounted
var _player: Player
var _retirements: Array[Dictionary] = []
var _commits: Array[Dictionary] = []
var _progress: Array[Dictionary] = []

func check(label: String,value: bool,detail: Variant = "") -> bool:
	checks += 1
	print("[source-stack-capacity] %s %s %s" % ["PASS" if value else "FAIL",label,str(detail)])
	if not value: failures.append(label)
	return value

func _hash(text: String) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	hash.update(text.to_utf8_buffer()); return hash.finish().hex_encode()

func _safe(path: String) -> bool:
	if not path.begins_with("/private/tmp/singapore-fidelity/") or path!=path.simplify_path(): return false
	var parent := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/",false):
		var directory := DirAccess.open(parent)
		if directory!=null and directory.is_link(part): return false
		parent = parent.path_join(part)
	return true

func _ready() -> void:
	_started_us = Time.get_ticks_usec()
	var args := OS.get_cmdline_user_args(); var at := args.find("--qa-session")
	if at<0 or at+1>=args.size(): get_tree().quit(2); return
	var base: String = args[at+1]
	if base.begins_with("/tmp/"): base = "/private/tmp/"+base.trim_prefix("/tmp/")
	output = base.path_join("source-stack-capacity")
	if not _safe(output) or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK: get_tree().quit(2); return
	get_tree().create_timer(900.0,true,false,true).timeout.connect(func():
		if not finished: check("bounded two-case native capacity test",false,"900wall; Root outer960"); _finish())
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not finished and Time.get_ticks_usec()-_last_progress_us>=10000000: _sample()

func _sample() -> void:
	_last_progress_us = Time.get_ticks_usec()
	var row := {"phase":_phase,"capacity":_active_cap,"wall_s":float(_last_progress_us-_started_us)/1000000.0,"physics_tick":Engine.get_physics_frames()}
	if is_instance_valid(_stack):
		row["active_floors"] = _stack._active_count()
		row["maximum_active_floors"] = _stack._max_active
		row["protected_ids"] = _stack._protected_floors().keys()
	_progress.append(row)
	print("[source-stack-capacity] PROGRESS ",JSON.stringify(row,"",true,true))

func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _quiet() -> Dictionary:
	var quiet := 0
	var count := 0
	for i in 90:
		count += 1
		quiet = quiet+1 if _player.is_on_floor() and _player.velocity.length()<=.12 else 0
		if quiet>=3: break
		await get_tree().physics_frame
	return {"ok":quiet>=3,"frames":count,"quiet_samples":quiet,"velocity":[_player.velocity.x,_player.velocity.y,_player.velocity.z],"on_floor":_player.is_on_floor()}

func _configure(capacity: int) -> bool:
	_active_cap = capacity
	_phase = "configure-"+str(capacity)
	Game.simulation_paused = true; Game.mode = Game.MODE_FOOT; Game.health = Game.MAX_HEALTH; Game.death_count = 0
	_scope = Node3D.new(); _scope.name = "CapacityCase"+str(capacity); add_child(_scope)
	var raw: String = FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json")
	var manifest: Dictionary = JSON.parse_string(raw)
	var source_tower: Dictionary = {}
	for tower: Dictionary in Reference.DATA.towers:
		if tower.tower=="T1": source_tower = tower
	if source_tower.is_empty(): return check("actual T1 source reference exists",false)
	var record: Dictionary = Inventory.floor_record(CURRENT)
	_frame = Frame.new()
	if not check("source frame configures cap"+str(capacity),_frame.configure(manifest.georeference,[source_tower.centroid_world_xz[0],record.elevation_m,source_tower.centroid_world_xz[1]],_hash(raw),{"status":"staging","reference":"Capacity fixture L1=0 inventory reconstruction; not surveyed datum"})): return false
	_context = Context.new()
	var profile := {"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":cos(deg_to_rad(52.0)),"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}
	if not check("native Context configures cap"+str(capacity),_context.configure(_frame,_hash("Native capacity fixture "+str(capacity)+FileAccess.get_file_as_string(Inventory.PATH)),_hash("reconstructed relative inventory elevations"),profile,get_world_3d())): return false
	_domain = Domain.new()
	if not check("actual country/coast identity opens cap"+str(capacity),_domain.configure("res://data/geography/domain/osm-2026-10-27","82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834",_hash(raw))): return false
	for row: Dictionary in _domain.provider_descriptors(): _context.register_provider(row.kind,row.provider_id,row.source_reference)
	_context.register_provider("physics","capacity-native/v1","Actual owned production floor modules and Player, source placement; no city/cabin claim")
	_runtime = Runtime.new(); _scope.add_child(_runtime)
	if not check("same-frame source Runtime configures cap"+str(capacity),_runtime.configure(_frame,_context,_domain.observe)): return false
	for invalid in [2,19,18.5,true]:
		var refused := Stack.new(); _scope.add_child(refused)
		var accepted: bool = refused.configure(_frame,_context,_runtime,0.0,"Invalid capacity boundary fixture",{"max_active_floors":invalid,"auto_stream":false})
		var rejected: bool = not accepted and not refused.get("_configured") and refused.get_child_count()==0
		check("capacity boundary rejects without floor creation "+str(invalid)+" cap"+str(capacity),rejected)
		refused.queue_free()
		if not rejected: return false
	_stack = Stack.new(); _scope.add_child(_stack)
	if not check("requested bounded production Stack configures "+str(capacity),_stack.configure(_frame,_context,_runtime,0.0,"Explicit inventory reconstruction for native capacity, not current surveyed L1",{"max_active_floors":capacity,"auto_stream":false})): return false
	_stack.floor_retired.connect(func(id: String,region: String): _retirements.append({"capacity":_active_cap,"id":id,"region_id":region,"physics_tick":Engine.get_physics_frames()}))
	_stack.floor_committed.connect(func(id: String,generation: String): _commits.append({"capacity":_active_cap,"id":id,"generation":generation,"physics_tick":Engine.get_physics_frames()}))
	return true

func _native_snapshot(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id: String in ids:
		var node: Node3D = _stack.get_floor(id)
		var state: Dictionary = _stack.floor_state(id)
		if not is_instance_valid(node): result[id] = {"valid":false}; continue
		var bodies: Array[Dictionary] = []
		for body in _stack._entries[id].bodies:
			bodies.append({"id":body.get_instance_id(),"layer":body.collision_layer,"space_id":body.get_world_3d().space.get_id(),"stamp":body.get_meta(Context.COLLIDER_META,{})})
		result[id] = {"valid":state.local_collision_committed,"node_id":node.get_instance_id(),"generation":state.collision_generation,"bodies":bodies}
	return result

func _run_case(capacity: int) -> bool:
	if not _configure(capacity): return false
	for tower in ["T1","T2","T3"]:
		var id: String = tower+"-L1"
		_phase = "native-entry-neighborhood-"+id
		_sample()
		var prepared: Dictionary = await _stack.ensure_floor(id)
		if not check("real entry floor/neighbor modules commit "+id+" cap"+str(capacity),prepared.ready,prepared): return false
		if not check("three-entry source pin accepted "+id,_stack.pin_floor(id,PIN_OWNER)): return false
	var entry_ids: Array = _stack._protected_floors().keys()
	check("entry pins protect exactly nine native floor IDs cap"+str(capacity),entry_ids.size()==9 and _stack.report().active_floor_count==9,entry_ids)
	_phase = "native-current-window-"+CURRENT
	_sample()
	var current: Dictionary = await _stack.ensure_floor(CURRENT)
	if not check("actual high-floor current window commits cap"+str(capacity),current.ready,current): return false
	var module: Node3D = _stack.get_floor(CURRENT)
	if not check("current production floor has an actual room approach",not module.rooms.is_empty()): return false
	_player = Player.new(); _player.name = "NativeCapacityOccupant"
	_player.position = module.to_global(module.rooms[0].entry_local)+Vector3.UP*.10
	_player.uses_source_world = true; _player.source_world_runtime = _runtime; _scope.add_child(_player)
	if not check("actual production occupant binds cap"+str(capacity),_runtime.bind_player(_player)): return false
	Game.simulation_paused = false
	var quiet: Dictionary = await _quiet()
	if not check("real high-floor occupant settles cap"+str(capacity),quiet.ok,quiet): return false
	var support: Dictionary = _runtime.inspect_player(_player)
	if not check("current native floor actually supports source Player cap"+str(capacity),support.get("ok",false) and support.support.state=="supported" and support.support.floor_id==CURRENT and support.residency.state=="resident",support): return false
	check("explicit current-floor claim matches real native occupant",_stack.set_actor_floor(_player,CURRENT))
	var protected: Array = _stack._protected_floors().keys()
	var before: Dictionary = _native_snapshot(protected)
	var pose_before: Vector3 = _player.global_position
	var retired_before: int = _retirements.size()
	check("three entry groups plus current window protect twelve cap"+str(capacity),protected.size()==12 and _stack.report().active_floor_count==12,protected)
	_phase = "prepare-real-next-window-"+NEXT
	_sample()
	var target: Dictionary = await _stack.ensure_floor(NEXT)
	var preserved: bool = before==_native_snapshot(protected)
	var retired_protected := false
	for index in range(retired_before,_retirements.size()):
		if _retirements[index].id in protected: retired_protected = true
	check("preparing next window never evicts protected source bodies cap"+str(capacity),preserved and not retired_protected)
	check("capacity gate never relocates actual occupant cap"+str(capacity),_player.global_position.distance_to(pose_before)<.02 and Game.death_count==0)
	if capacity==12:
		check("old twelve-floor cap honestly reports protected capacity",not target.ready and target.status=="protected_capacity" and _stack.report().active_floor_count==12 and _stack.floor_ready(CURRENT),target)
	else:
		check("eighteen-floor reserve admits real next native window",target.ready and _stack.floor_ready(NEXT) and _stack.floor_ready(CURRENT) and _stack.report().active_floor_count==13 and _stack.report().active_floor_count<=capacity,target)
		var next_state: Dictionary = _stack.floor_state(NEXT)
		var owned: bool = not next_state.native_floor_probes.is_empty()
		for probe: Dictionary in next_state.native_floor_probes: owned = owned and probe.valid_owned_floor and probe.body_in_owned_complete_list and probe.excluded_rids==0
		check("prepared destination has actual owned native floor probes",owned,next_state.native_floor_probes)
		var denied: Dictionary = await _stack.unload_floor(CURRENT)
		check("larger cap still refuses occupied floor eviction",not denied.ok and denied.status=="protected" and before[CURRENT]==_native_snapshot([CURRENT])[CURRENT],denied)
	metrics["cap_"+str(capacity)] = {"entry_pin_ids":entry_ids,"current_floor":CURRENT,"destination_floor":NEXT,"current_native_support":support,"protected_ids":protected,"before":before,"target_result":target,"protected_preserved":preserved,"no_protected_retirement":not retired_protected,"active_after":_stack.report().active_floor_count,"maximum_active":capacity,"occupant_displacement_m":_player.global_position.distance_to(pose_before),"stage_preparation_only_not_stair_or_cabin_traversal":true}
	return true

func _cleanup_case() -> bool:
	_phase = "retire-owned-case-"+str(_active_cap)
	Game.simulation_paused = true
	if is_instance_valid(_player):
		_stack.clear_actor_floor(_player); _player.queue_free(); await _frames(3)
	_player = null
	for tower in ["T1","T2","T3"]: _stack.unpin_floor(tower+"-L1",PIN_OWNER)
	var live: Array = _stack.report().locally_committed_floors
	for id: String in live:
		var retired: Dictionary = await _stack.unload_floor(id)
		if not check("owned empty capacity case floor retires "+id,retired.ok,retired): return false
	if not check("first case completely retires before second geometry",_stack.report().active_floor_count==0 and _runtime._regions.is_empty()): return false
	_scope.queue_free(); await _frames(3)
	_stack = null; _runtime = null; _scope = null; _context = null; _frame = null; _domain = null
	return true

func _run() -> void:
	if not await _run_case(12): _finish(); return
	if not await _cleanup_case(): _finish(); return
	if not await _run_case(18): _finish(); return
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	Game.simulation_paused = true
	metrics["progress"] = _progress
	metrics["commits"] = _commits
	metrics["retirements"] = _retirements
	var report := {"schema":"source_stack_native_capacity_v1","checks":checks,"failed":failures.size(),"failures":failures,"metrics":metrics,"elapsed_wall_s":float(Time.get_ticks_usec()-_started_us)/1000000.0,"one_initial_player_setup_per_independent_case":true,"actual_source_footprints_and_reconstructed_floor_factories":true,"full_hotel_transitions_or_rendered_acceptance":false}
	var path: String = output.path_join("report.json")
	if not _safe(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): get_tree().quit(2); return
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: get_tree().quit(2); return
	file.store_string(JSON.stringify(report,"\t",true,true)); file.close()
	print("[source-stack-capacity] FINISHED checks=%d failed=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
