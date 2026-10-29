extends Node3D
## Actual controller/service/Game/Player + source-positioned native FloorStack.
## National SourceWorld auto-boot is disabled: this is component integration,
## not a prepared city/terrain/road build or continuous travel acceptance.
const World = preload("res://src/world/geography/source_world.gd")
const Controller = preload("res://src/world/geography/source_session_controller.gd")
const Service = preload("res://src/world/geography/source_save_service.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const Stack = preload("res://src/world/mbs_interior/floor_stack.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const SourceHUD = preload("res://src/world/geography/source_world_hud.gd")
const HOME = "T2-L24"
const REMOTE = "T3-L24"
const BLOCKER = "T1-L24"
const FOREIGN_HOME = "qa-controller/retain-home"
const FOREIGN_CAPACITY = "qa-controller/capacity-blocker"
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var finished := false
var qa := ""
var output := ""
var world: Node3D
var controller: Node
var service: Node
var stack: Node3D
var runtime: Node3D
var frame: RefCounted
var context: RefCounted
var domain: RefCounted
var player: Player
var v1 := ""
var slot := ""
var v1_bytes := PackedByteArray()
var remote_bytes := PackedByteArray()
var remote_document: Dictionary = {}
var commits: Array[Dictionary] = []
var restores: Array[Dictionary] = []
var requirements: Array[Dictionary] = []
var setup_relocations: Array[Dictionary] = []
var cancel_when_prepared := ""
var arm_cancel_load := false
var cancel_receipt: Dictionary = {}
var mutate_next_load := false
var mutation_done := false
var mutated_bytes := PackedByteArray()
var arm_busy_probe := false
var inside_busy_probe := false
var busy_probes:Array[Dictionary]=[]

func check(label: String, ok: bool, detail: Variant = "") -> bool:
	checks += 1
	print("[source-controller] %s %s %s" % ["PASS" if ok else "FAIL",label,str(detail)])
	if not ok: failures.append(label)
	return ok

func _safe(path: String) -> bool:
	if not path.begins_with("/private/tmp/singapore-fidelity/") or path != path.simplify_path(): return false
	var current := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/",false):
		var directory := DirAccess.open(current)
		if directory != null and directory.is_link(part): return false
		current = current.path_join(part)
	return true

func _write(path: String, bytes: PackedByteArray) -> bool:
	if not _safe(path) or not path.begins_with(qa+"/") or DirAccess.dir_exists_absolute(path): return false
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes); file.flush()
	var complete: bool = file.get_error() == OK and file.get_length() == bytes.size()
	file.close()
	return complete

func _digest(value: String) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	hash.update(value.to_utf8_buffer()); return hash.finish().hex_encode()

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--qa-session")
	if index < 0 or index+1 >= args.size(): get_tree().quit(2); return
	qa = args[index+1]
	if qa.begins_with("/tmp/"): qa = "/private/tmp/"+qa.trim_prefix("/tmp/")
	output = qa.path_join("source-controller")
	if not _safe(output) or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK: get_tree().quit(2); return
	get_tree().create_timer(1100.0,true,false,true).timeout.connect(func():
		if not finished: check("bounded native controller fixture",false); _finish())
	_run.call_deferred()

func _frames(count: int) -> void:
	for index in count: await get_tree().physics_frame

func _wait(predicate: Callable, label: String, timeout_seconds: float = 150.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(timeout_seconds*1000.0)
	while not bool(predicate.call()) and not finished and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return check(label,not finished and bool(predicate.call()))

func _native_key(code: Key) -> void:
	var press := InputEventKey.new(); press.keycode = code; press.physical_keycode = code; press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame; await get_tree().process_frame
	var release := InputEventKey.new(); release.keycode = code; release.physical_keycode = code; release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame; await get_tree().process_frame

func _stable_state() -> Dictionary:
	return {"position":player.global_position,"yaw":player.yaw,"health":Game.health,"deaths":Game.death_count,"weapon":Game.carried_weapon,"ammo":Game.ammo.duplicate(true),"v1":FileAccess.get_file_as_bytes(v1),"v2":FileAccess.get_file_as_bytes(slot)}

func _unchanged(before: Dictionary, expected_v2: PackedByteArray) -> bool:
	# Elapsed time is deliberately live while this component fixture runs.
	return player.global_position.distance_to(before.position) < .02 and absf(wrapf(player.yaw-before.yaw,-PI,PI)) < .001 and Game.health == before.health and Game.death_count == before.deaths and Game.carried_weapon == before.weapon and Game.ammo == before.ammo and FileAccess.get_file_as_bytes(v1) == before.v1 and FileAccess.get_file_as_bytes(slot) == expected_v2

func _controller_pins() -> Dictionary:
	var result: Dictionary = {}
	var pins: Dictionary = stack.get("_pins")
	for id: String in pins:
		for owner: String in pins[id]:
			if owner.begins_with("source-restore/"): result[id+"/"+owner] = true
	return result

func _on_required(reason: String, pose: Dictionary, token: String) -> void:
	requirements.append({"reason":reason,"token":token,"pose":pose.duplicate(true),"physics_tick":Engine.get_physics_frames()})
	if arm_cancel_load and service.metadata().pending_kind == "load":
		arm_cancel_load = false; cancel_when_prepared = token
	if mutate_next_load and reason == "fresh_physics_boundary_required" and service.metadata().pending_kind == "load":
		mutate_next_load = false
		mutated_bytes = FileAccess.get_file_as_bytes(slot)+"\n".to_utf8_buffer()
		mutation_done = _write(slot,mutated_bytes)

func _on_runtime_notify(_text:String,_kind:String)->void:
	if not arm_busy_probe or inside_busy_probe or not is_instance_valid(service) or not bool(service.metadata().get("transaction_busy",false)):return
	inside_busy_probe=true;arm_busy_probe=false
	var pins_before:Dictionary=_controller_pins()
	var token:String=service.pending_token()
	# Real production respawn notifications occur INSIDE Runtime application.
	# Probe only refused API requests; never destroy nodes or force state.
	var load_refused:bool=not controller.load_game()
	var uninstall_refused:bool=not Game.uninstall_source_session(service)
	busy_probes.append({"token":token,"pins_before":pins_before,"pins_after":_controller_pins(),"reentrant_load_refused":load_refused,"busy_uninstall_refused":uninstall_refused,"owner_retained":Game.source_session_owns(service),"transaction_still_busy":service.metadata().get("transaction_busy",false),"same_pending_token":service.pending_token()==token})
	inside_busy_probe=false

func _physics_process(_delta: float) -> void:
	if finished or cancel_when_prepared.is_empty() or not is_instance_valid(controller) or not is_instance_valid(service) or not is_instance_valid(stack): return
	var token := cancel_when_prepared
	if service.pending_token() != token or not String(controller.get("_preparing")).is_empty() or not (controller.get("_pinned") as Dictionary).has(token) or not stack.floor_ready(REMOTE): return
	# Observe the actual completed preparation before the controller's next
	# physics retry. Cancel through the real owner API; no readiness/state stub.
	cancel_when_prepared = ""
	var before := _stable_state()
	var pin_before := _controller_pins()
	var accepted: bool = service.cancel_pending(token)
	cancel_receipt = {"token":token,"accepted":accepted,"before":before,"pins_before":pin_before,"physics_tick":Engine.get_physics_frames(),"actual_remote_ready":stack.floor_ready(REMOTE)}

func _landing(id: String) -> Vector3:
	var module: Node3D = stack.get_floor(id)
	if module == null: return Vector3(INF,INF,INF)
	for portal: Dictionary in module.portals:
		if portal.kind == "guest_lift" and portal.wing == "east": return module.to_global(portal.landing)
	return Vector3(INF,INF,INF)

func _put_player(id: String, capture: bool = true) -> bool:
	# Explicit fixture arrangement, never a controller fallback or travel claim.
	Game.simulation_paused = true
	var controller_active: bool = is_instance_valid(controller) and controller.is_physics_processing()
	if controller_active: controller.set_physics_process(false)
	var loaded: Dictionary = await stack.ensure_floor(id)
	if not check("real source neighbourhood available for declared setup "+id,loaded.get("ready",false),loaded): return false
	var point := _landing(id)
	if not check("actual floor exposes supported landing for setup "+id,is_finite(point.x)): return false
	Game.health = Game.MAX_HEALTH
	player.respawn_at(point+Vector3.UP*.08,0)
	setup_relocations.append({"floor_id":id,"actual_module_landing":point,"kind":"EXPLICIT_FIXTURE_SETUP_NOT_CONTROLLER_TRAVEL"})
	Game.simulation_paused = false; await _frames(30); Game.simulation_paused = true
	var state: Dictionary = runtime.inspect_player(player)
	if not check("setup rests on actual native source floor "+id,state.get("ok",false) and state.support.state == "supported" and state.support.feature_id == Stack.FEATURE and state.support.floor_id == id and state.clearance.state == "clear",state): return false
	if controller_active: controller.set_physics_process(true)
	if capture and is_instance_valid(controller):
		if not check("ready onfoot checkpoint captures after native insertion "+id,controller.capture_initial_anchor(),service.last_result): return false
	return true

func _unload_remote() -> bool:
	Game.simulation_paused = true
	var ids: Array[String] = stack.adjacent_floor_ids(REMOTE)
	ids.append(REMOTE)
	for id: String in ids:
		var retired: Dictionary = await stack.unload_floor(id)
		if not check("empty real remote floor retires "+id,retired.get("ok",false),retired): return false
	return check("remote floor truly cold after native retirement",not stack.floor_ready(REMOTE) and stack.get_floor(REMOTE) == null)

func _run() -> void:
	Game.simulation_paused = true; Game.mode = Game.MODE_FOOT; Game.health = Game.MAX_HEALTH; Game.death_count = 0
	world = World.new(); world.auto_boot = false; world.name = "ActualSourceControllerComponentWorld"; add_child(world)
	world.set_process(false) # National streaming/bootstrap is not under test.
	var raw := FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json")
	var manifest: Dictionary = JSON.parse_string(raw)
	var tower: Dictionary = Reference.DATA.towers[1]
	var origin: Array = [tower.centroid_world_xz[0],float(Inventory.floor_record(HOME).elevation_m),tower.centroid_world_xz[1]]
	frame = Frame.new()
	if not check("actual uncompressed source frame configures",frame.configure(manifest.georeference,origin,_digest(raw),{"status":"staging","reference":"Controller integration uses reconstructed MBS L1=0 datum","source_reference":"Actual pinned source centroids/basis; not current surveyed elevation"})): _finish(); return
	context = Context.new()
	var profile := {"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":cos(deg_to_rad(52.0)),"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}
	var geometry := _digest(FileAccess.get_file_as_string("res://src/world/mbs_interior/floor_stack.gd")+FileAccess.get_file_as_string("res://src/world/mbs_interior/guest_floor.gd")+FileAccess.get_file_as_string("res://src/world/mbs_interior/program_floor.gd")+FileAccess.get_file_as_string(Inventory.PATH))
	if not check("common actual World3D context configures",context.configure(frame,geometry,_digest("Explicit controller QA reconstructed vertical datum"),profile,get_world_3d())): _finish(); return
	domain = Domain.new()
	if not check("actual pinned Singapore domain configures",domain.configure("res://data/geography/domain/osm-2026-10-27","82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834",_digest(raw))): _finish(); return
	for descriptor: Dictionary in domain.provider_descriptors(): context.register_provider(descriptor.kind,descriptor.provider_id,descriptor.source_reference)
	context.register_provider("physics","source-controller/native-v1","Actual owned source-positioned FloorStack and production Player observations")
	runtime = Runtime.new(); world.add_child(runtime)
	if not check("production runtime binds exact frame/context/domain",runtime.configure(frame,context,domain.observe)): _finish(); return
	stack = Stack.new(); world.add_child(stack)
	if not check("real bounded source FloorStack configures",stack.configure(frame,context,runtime,0.0,"Explicit reconstructed inventory elevations, no surveyed as-built claim",{"max_active_floors":6,"max_pending_requests":3,"auto_stream":false})): _finish(); return
	stack.floor_committed.connect(func(id: String, generation: String): commits.append({"id":id,"generation":generation,"physics_tick":Engine.get_physics_frames()}))
	player = Player.new(); player.process_mode = Node.PROCESS_MODE_DISABLED; world.add_child(player)
	if not check("production Player binds real source capsule",runtime.bind_player(player)): _finish(); return
	player.process_mode = Node.PROCESS_MODE_INHERIT
	world.source_frame = frame; world.source_context = context; world.source_runtime = runtime; world.domain = domain; world.player = player; world.floor_stack = stack
	if not await _put_player(HOME,false): _finish(); return
	v1 = ProjectSettings.globalize_path(Game.save_slot_path())
	if v1.begins_with("/tmp/"): v1 = "/private/tmp/"+v1.trim_prefix("/tmp/")
	v1_bytes = "{\"version\":1,\"controller_legacy_sentinel\":\"PRESERVE EXACT BYTES\"}\n".to_utf8_buffer()
	if not check("fresh private v1 sentinel creates without owner overwrite",not FileAccess.file_exists(v1) and _write(v1,v1_bytes)): _finish(); return
	controller = Controller.new(); world.add_child(controller); world.session_controller = controller
	if not check("production controller installs exact owner service",controller.configure(world)): _finish(); return
	service = controller.service; slot = service.metadata().slot_path
	service.restore_required.connect(_on_required)
	Events.notify.connect(_on_runtime_notify)
	service.restored.connect(func(reason: String, token: String): restores.append({"reason":reason,"token":token,"position":player.global_position,"physics_tick":Engine.get_physics_frames()}))
	await get_tree().physics_frame
	if not check("initial anchor verified before ready or unpause",controller.capture_initial_anchor() and not world.ready_for_play and Game.simulation_paused and service.metadata().has_source_anchor,service.metadata()): _finish(); return
	world.hud = SourceHUD.new(); world.add_child(world.hud); world.hud.setup_source(world,player)
	world.ready_for_play = true
	if not check("foreign caller pin remains independently owned",stack.pin_floor(HOME,FOREIGN_HOME)): _finish(); return
	if not await _put_player(REMOTE): _finish(); return
	Game.carried_weapon = "smg"; Game.ammo.smg.mag = 17
	Game.simulation_paused = false; await _native_key(KEY_F5)
	if not check("native SourceWorld F5 publishes real source-v2",FileAccess.file_exists(slot) and service.has_save() and FileAccess.get_file_as_bytes(v1) == v1_bytes,service.last_result): _finish(); return
	remote_bytes = FileAccess.get_file_as_bytes(slot); remote_document = JSON.parse_string(remote_bytes.get_string_from_utf8())
	if not check("saved pose identifies actual remote source floor",remote_document.context_pose.source_pose.feature_id == Stack.FEATURE and remote_document.context_pose.source_pose.floor_id == REMOTE): _finish(); return
	if not await _put_player(HOME): _finish(); return
	if not await _unload_remote(): _finish(); return
	var restore_count := restores.size()
	arm_busy_probe=true
	Game.simulation_paused = false; await _native_key(KEY_F6)
	if not await _wait(func(): return service.pending_token().is_empty() and String(controller.get("_preparing")).is_empty(),"cold native F6 finishes real preparation/application"): _finish(); return
	var loaded_state: Dictionary = runtime.inspect_player(player)
	if not check("controller cold load used actual native remote floor",loaded_state.get("ok",false) and loaded_state.support.floor_id == REMOTE and stack.floor_ready(REMOTE) and restores.size() == restore_count+1 and Game.carried_weapon == "smg" and Game.current_mag() == 17,service.last_result): _finish(); return
	if not check("actual Runtime callback exercised busy controller and uninstall guards",busy_probes.size()==1): _finish();return
	var busy_proof:Dictionary=busy_probes[0]
	if not check("reentrant controller load cannot release active restore pin",busy_proof.reentrant_load_refused and busy_proof.busy_uninstall_refused and busy_proof.owner_retained and busy_proof.transaction_still_busy and busy_proof.same_pending_token and not busy_proof.pins_before.is_empty() and busy_proof.pins_before==busy_proof.pins_after,busy_proof): _finish();return
	check("successful restore releases only its own pin",_controller_pins().is_empty() and (stack.get("_pins") as Dictionary).get(HOME,{}).has(FOREIGN_HOME))
	check("cold restore preserved both persisted slot files",FileAccess.get_file_as_bytes(v1) == v1_bytes and FileAccess.get_file_as_bytes(slot) == remote_bytes)

	# Actual cancellation after complete native preparation, before application.
	if not await _put_player(HOME): _finish(); return
	if not await _unload_remote(): _finish(); return
	arm_cancel_load = true; cancel_receipt.clear(); restore_count = restores.size()
	Game.simulation_paused = false; await _native_key(KEY_F6)
	if not await _wait(func(): return not cancel_receipt.is_empty(),"actual prepared token can be externally cancelled"): _finish(); return
	await _frames(4)
	if not check("external cancel reconciles exact owned pin and hold",cancel_receipt.accepted and not cancel_receipt.pins_before.is_empty() and service.pending_token().is_empty() and _controller_pins().is_empty() and not Game.source_controls_held() and restores.size() == restore_count and _unchanged(cancel_receipt.before,remote_bytes),cancel_receipt): _finish(); return

	# A changed sibling after queueing is a terminal manual refusal even though
	# that service hash branch emits no restore_required signal itself.
	if not check("remote geometry really ready for file-race isolation",stack.floor_ready(REMOTE)): _finish(); return
	mutate_next_load = true; mutation_done = false; restore_count = restores.size()
	var race_before := _stable_state()
	await _native_key(KEY_F6)
	if not await _wait(func(): return mutation_done and service.pending_token().is_empty(),"pending file replacement cancels without permanent control hold"): _finish(); return
	check("file-race refusal preserves actual actor stats and new bytes",not Game.source_controls_held() and restores.size() == restore_count and _unchanged(race_before,mutated_bytes),service.last_result)
	if not _write(slot,remote_bytes): check("restore exact private test bytes",false); _finish(); return

	# Deliberately unavailable real loader: no readiness stub or substitute.
	if not await _unload_remote(): _finish(); return
	world.floor_stack = null
	var unavailable_before := _stable_state()
	Game.simulation_paused = false
	await _native_key(KEY_F6)
	if not await _wait(func(): return service.pending_token().is_empty() and String(controller.get("_preparing")).is_empty(),"missing loader cancels healthy manual load",30.0): _finish(); return
	check("missing loader leaves current real source play intact",not Game.source_controls_held() and _unchanged(unavailable_before,remote_bytes) and _controller_pins().is_empty())
	world.floor_stack = stack

	# Real pin-owner budget is separate from physical active-floor capacity.
	# Known inventory pins do not claim those unloaded floors are ready.
	if not await _put_player(REMOTE): _finish(); return
	if not await _put_player(HOME,false): _finish(); return
	if not await _unload_remote(): _finish(); return
	var budget_ids: Array[String] = ["T1-L1","T1-L24","T2-L1","T2-L5","T3-L1"]
	for id: String in budget_ids:
		if not check("fixture native inventory pin consumes exact budget "+id,stack.pin_floor(id,"qa-controller/pin-budget/"+id)): _finish(); return
	if not check("actual FloorStack pin map reaches configured six-id budget",(stack.get("_pins") as Dictionary).size() == 6): _finish(); return
	var pin_deaths_before: int = Game.death_count
	var pin_death_position := player.global_position
	var pin_commit_count := commits.size()
	Game.damage_player(Game.MAX_HEALTH)
	var pin_token: String = service.pending_token()
	Game.simulation_paused = false
	if not await _wait(func(): return (controller.get("_retry_floors") as Dictionary).has(pin_token),"real unavailable pin budget schedules bounded same-token retry"): _finish(); return
	if not check("failed native pin acquisition keeps held player and original token",not pin_token.is_empty() and service.pending_token() == pin_token and Game.health == 0.0 and Game.death_count == pin_deaths_before and player.global_position.distance_to(pin_death_position) < .02 and _controller_pins().is_empty() and commits.size() == pin_commit_count): _finish(); return
	var released_budget_id: String = budget_ids[-1]
	if not check("one exact fixture pin releases without fake floor commit",stack.unpin_floor(released_budget_id,"qa-controller/pin-budget/"+released_budget_id) and commits.size() == pin_commit_count): _finish(); return
	if not await _wait(func(): return service.pending_token().is_empty(),"same recovery token acquires freed real pin budget and restores",180.0): _finish(); return
	var pin_recovered: Dictionary = runtime.inspect_player(player)
	if not check("pin-budget recovery uses real native target exactly once",pin_recovered.get("ok",false) and pin_recovered.support.floor_id == REMOTE and Game.health == Game.MAX_HEALTH and Game.death_count == pin_deaths_before+1 and not Game.source_controls_held() and _controller_pins().is_empty()): _finish(); return
	for id: String in budget_ids: stack.unpin_floor(id,"qa-controller/pin-budget/"+id)

	# Preserve a genuinely captured remote checkpoint; arrange current actor at
	# home, then fill all six native floor slots with protected real geometry.
	if not await _put_player(REMOTE): _finish(); return
	if not await _put_player(HOME,false): _finish(); return
	if not await _unload_remote(): _finish(); return
	var filled: Dictionary = await stack.ensure_floor(BLOCKER)
	if not check("native capacity blocker really fills remaining neighbourhood",filled.get("ready",false) and stack.report().active_floor_count == 6 and stack.pin_floor(BLOCKER,FOREIGN_CAPACITY),filled): _finish(); return
	var death_before: int = Game.death_count
	var death_position := player.global_position
	Game.damage_player(Game.MAX_HEALTH)
	var death_token: String = service.pending_token()
	if not check("actual lethal damage queues one owned recovery token",Game.health == 0.0 and not death_token.is_empty() and Game.source_controls_held()): _finish(); return
	Game.simulation_paused = false
	if not await _wait(func(): return (controller.get("_retry_floors") as Dictionary).has(death_token),"real protected capacity schedules bounded same-token retry"): _finish(); return
	check("failed native prep retains exact token checkpoint and hold",service.pending_token() == death_token and Game.death_count == death_before and player.global_position.distance_to(death_position) < .02 and not _controller_pins().is_empty())
	var commits_before_release := commits.size()
	if not check("only fixture-owned blocker pin releases",stack.unpin_floor(BLOCKER,FOREIGN_CAPACITY) and commits.size() == commits_before_release): _finish(); return
	if not await _wait(func(): return service.pending_token().is_empty(),"backoff re-prepares real floor without external commit trigger",180.0): _finish(); return
	var recovered: Dictionary = runtime.inspect_player(player)
	check("same death token restores exactly once on native target",recovered.get("ok",false) and recovered.support.floor_id == REMOTE and player.alive and player.visible and Game.health == Game.MAX_HEALTH and Game.death_count == death_before+1 and not Game.source_controls_held() and _controller_pins().is_empty(),service.last_result)
	check("completed token replay does not count a second death",service.request_recovery("death",death_token) and Game.death_count == death_before+1)

	# A stale controller must not route native/global wrappers to a replacement.
	Game.simulation_paused = true
	var replacement := Service.new(); world.add_child(replacement)
	if not check("replacement can stage without ownership takeover",replacement.configure(runtime,player,Game.save_slot_path(),qa,"supported_native_surface") and not Game.install_source_session(replacement)): _finish(); return
	if not check("explicit idle ownership switch succeeds",Game.uninstall_source_session(service) and Game.install_source_session(replacement)): _finish(); return
	var switched_before := _stable_state()
	check("old controller wrappers cannot operate replacement service",not controller.save_game() and not controller.load_game() and replacement.pending_token().is_empty() and _unchanged(switched_before,remote_bytes))
	if not check("restore exact original owner for teardown",Game.uninstall_source_session(replacement) and Game.install_source_session(service)): _finish(); return
	replacement.queue_free()
	controller.set_physics_process(false); controller.queue_free(); await _frames(4)
	check("owned controller teardown uninstalls and preserves foreign pins",Game.get("_source_session") == null and _controller_pins().is_empty() and (stack.get("_pins") as Dictionary).get(HOME,{}).has(FOREIGN_HOME) and FileAccess.get_file_as_bytes(v1) == v1_bytes)
	metrics["commits"] = commits; metrics["restores"] = restores; metrics["requirements"] = requirements; metrics["external_cancel"] = cancel_receipt
	metrics["explicit_setup_relocations"] = setup_relocations
	metrics["real_Runtime_busy_callback_probes"] = busy_probes
	metrics["actual_source_frame"] = frame.metadata()
	metrics["remaining_foreign_pin"] = (stack.get("_pins") as Dictionary).duplicate(true)
	_finish()

func _finish() -> void:
	if finished: return
	finished = true; Game.simulation_paused = true
	if is_instance_valid(controller):
		controller.set_physics_process(false)
		if is_instance_valid(service) and not service.pending_token().is_empty(): service.cancel_pending(service.pending_token())
		controller.queue_free()
	if is_instance_valid(stack):
		stack.unpin_floor(HOME,FOREIGN_HOME); stack.unpin_floor(BLOCKER,FOREIGN_CAPACITY)
		var owned_pins:Dictionary=(stack.get("_pins") as Dictionary).duplicate(true)
		for id:String in owned_pins:
			for owner:String in owned_pins[id]:
				if owner.begins_with("qa-controller/pin-budget/"):stack.unpin_floor(id,owner)
	if is_instance_valid(runtime): metrics["source_runtime_profile"] = runtime.residency_profile()
	var report := {"schema":"source_session_controller_native_fixture_v1","checks":checks,"failed":failures.size(),"failures":failures,"metrics":metrics,"actual_SourceWorld_class_with_auto_boot_disabled":true,"real_controller_service_Game_Player_FloorStack":true,"actual_source_centroids_basis_and_inventory":true,"national_artifact_boot_tested":false,"fixture_setup_relocations_explicit":true,"continuous_travel_tested":false,"visual_or_whole_world_acceptance":false}
	var path := output.path_join("report.json")
	if not _safe(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): get_tree().quit(2); return
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: get_tree().quit(2); return
	file.store_string(JSON.stringify(report,"\t")+"\n"); file.close()
	print("[source-controller] FINISHED checks=%d failed=%d" % [checks,failures.size()])
	Sfx.shutdown_audio(); get_tree().quit(0 if failures.is_empty() else 1)
