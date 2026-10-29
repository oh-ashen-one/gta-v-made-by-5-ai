extends Node3D
## Actual production Player/Runtime and private source-v2 files on synthetic
## native dry-room geometry. Not MBS layout, whole-world save or visual proof.
const Service = preload("res://src/world/geography/source_save_service.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var qa := ""
var output := ""
var finished := false
var runtime: Node3D
var context: RefCounted
var frame: RefCounted
var player: Player
var service: Node
var floor_body: StaticBody3D
var floor_geometry := ""
var saved_bytes := PackedByteArray()
var v1_bytes := PackedByteArray()
var expected: Dictionary = {}
var _next_physics: Callable
var _physics_done := false
var _physics_result := false
var _required: Array[Dictionary] = []
var _recoveries: Array[Dictionary] = []

func check(label: String,value: bool,detail: Variant = "") -> bool:
	checks += 1
	print("[source-save] %s %s %s" % ["PASS" if value else "FAIL",label,str(detail)])
	if not value: failures.append(label)
	return value

func _hash(text: String) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	hash.update(text.to_utf8_buffer()); return hash.finish().hex_encode()

func _safe(path: String) -> bool:
	if not path.begins_with("/private/tmp/singapore-fidelity/") or path!=path.simplify_path(): return false
	var current := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/",false):
		var directory := DirAccess.open(current)
		if directory!=null and directory.is_link(part): return false
		current = current.path_join(part)
	return true

func _write(path: String,raw: PackedByteArray) -> bool:
	if not _safe(path) or not path.begins_with(qa+"/") or DirAccess.dir_exists_absolute(path): return false
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return false
	file.store_buffer(raw); file.close(); return true

func _write_document(document: Dictionary) -> bool:
	return _write(service.metadata().slot_path,JSON.stringify(document,"\t",true,true).to_utf8_buffer())

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--qa-session")
	if index<0 or index+1>=args.size(): get_tree().quit(2); return
	qa = args[index+1]
	if qa.begins_with("/tmp/"): qa = "/private/tmp/"+qa.trim_prefix("/tmp/")
	output = qa.path_join("source-save")
	if not _safe(output) or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK: get_tree().quit(2); return
	get_tree().create_timer(120.0,true,false,true).timeout.connect(func():
		if not finished: check("bounded source-save QA",false); _finish())
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	if _next_physics.is_valid():
		var callback := _next_physics
		_next_physics = Callable()
		_physics_result = bool(callback.call())
		_physics_done = true

func _physics(callback: Callable) -> bool:
	_physics_done = false; _next_physics = callback
	while not _physics_done: await get_tree().physics_frame
	return _physics_result

func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _domain(_point: Array) -> Dictionary:
	return {"territory":{"state":"inside"},"land":{"state":"unknown"},"water":{"state":"unknown"}}

func _source(local: Vector3) -> Array:
	return [float(local.x),float(local.y),-1000.0+float(local.z)]

func _register_floor(id: String,geometry: String) -> bool:
	return context.register_floor({"feature_id":"qa-source/dry-room","floor_id":id,"geometry_sha256":geometry,"support_ids":["native-floor"],"volumes":[{"volume_id":"actual-fixture-room","min_xyz":_source(Vector3(-10,-20.5,-10)),"max_xyz":_source(Vector3(10,-16,10)),"dry":true}],"provenance":"QA-only synthetic enclosed native room; not Singapore surveyed ground or actual MBS architecture"})

func _commit(id: String,region: String) -> bool:
	return runtime.commit_region(region,_source(Vector3(-12,-25,-12)),_source(Vector3(12,-12,12)),[floor_body],[{"body":floor_body,"feature_id":"qa-source/dry-room","floor_id":id,"support_id":"native-floor"}])

func _snapshot() -> Dictionary:
	return {"position":player.global_position,"yaw":player.yaw,"stats":service._live_stats(),"v1":FileAccess.get_file_as_bytes(service.metadata().legacy_path),"v2":FileAccess.get_file_as_bytes(service.metadata().slot_path)}

func _unchanged(before: Dictionary) -> bool:
	return player.global_position==before.position and player.yaw==before.yaw and service._live_stats()==before.stats and FileAccess.get_file_as_bytes(service.metadata().legacy_path)==before.v1 and FileAccess.get_file_as_bytes(service.metadata().slot_path)==before.v2

func _run() -> void:
	Game.simulation_paused = true
	frame = Frame.new()
	var snapshot: String = FileAccess.get_sha256("res://data/geography/osm-2026-10-27/manifest.json")
	if not check("canonical source frame configures",frame.configure(Frame.EXPECTED_FRAME,[0.0,0.0,-1000.0],snapshot,{"status":"staging","reference":"QA synthetic B2; not source terrain"})): _finish(); return
	context = Context.new()
	var profile := {"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":cos(deg_to_rad(52.0)),"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}
	if not check("source context binds actual native world",context.configure(frame,_hash("save-fixture-room-and-ceiling"),_hash("save-fixture-staging-Y"),profile,get_world_3d())): _finish(); return
	for kind in Context.KINDS: context.register_provider(kind,"qa-save/"+kind,"Synthetic fixture provider, no source city/hydrology claim")
	runtime = Runtime.new(); add_child(runtime)
	if not check("production runtime configures",runtime.configure(frame,context,_domain)): _finish(); return
	floor_geometry = _hash("save-fixture-floor-plus-obstruction-variant")
	_register_floor("B2",floor_geometry)
	floor_body = StaticBody3D.new(); floor_body.position = Vector3(0,-20.125,0); floor_body.collision_layer = 1
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(20,.25,20); shape.shape = box
	floor_body.add_child(shape); add_child(floor_body)
	await _frames(4)
	if not check("actual floor collision and source support commit",_commit("B2","qa-room")): _finish(); return
	player = Player.new(); player.position = Vector3(0,-19.95,0); player.uses_source_world = true; player.source_world_runtime = runtime; add_child(player)
	if not check("actual production player binds",runtime.bind_player(player)): _finish(); return
	Game.simulation_paused = false; await _frames(75); Game.simulation_paused = true
	service = Service.new(); add_child(service)
	var v1: String = qa.path_join("source-save-legacy.json")
	v1_bytes = "{\"version\":1,\"owner_legacy_sentinel\":\"PRESERVE EXACT BYTES\"}\n".to_utf8_buffer()
	if not check("private v1 sentinel creates",_write(v1,v1_bytes)): _finish(); return
	var wrong := Service.new(); add_child(wrong)
	check("QA refuses owner user slot without writing",not wrong.configure(runtime,player,Game.SAVE_PATH,qa))
	wrong.queue_free()
	if not check("service binds separate private sibling",service.configure(runtime,player,v1,qa),service.last_result): _finish(); return
	check("source sibling is distinct and remains in QA scope",service.metadata().slot_path==v1.trim_suffix(".json")+".source-v2.json" and service.metadata().slot_path.begins_with(qa+"/"))
	if Game.has_method("install_source_session"): check("Game ownership binding accepts complete service API",Game.call("install_source_session",service))
	service.restore_required.connect(func(reason: String,pose: Dictionary,token: String): _required.append({"reason":reason,"pose":pose,"token":token}))
	service.recovery_committed.connect(func(reason: String,token: String,count: int): _recoveries.append({"reason":reason,"token":token,"death_count":count}))
	Game.health = 37.0; Game.death_count = 7; Game.wanted_heat = 50.0; Game.wanted_level = 2
	Game.carried_weapon = "smg"; Game.ammo = {"pistol":{"mag":8,"reserve":64},"smg":{"mag":11,"reserve":44}}
	Game.elapsed_seconds = 84.0; Game.seed_value = 1234; Game.search_timer = 4.0; Game.set("_since_damage",2.0)
	Game.settings = {"mouse_sensitivity":1.4,"invert_y":true,"reduced_shake":true,"hud_visible":true}
	if not check("actual supported onfoot anchor captures",service.capture_anchor(),service.last_result): _finish(); return
	if not check("complete validated v2 publishes atomically",service.save(),service.last_result): _finish(); return
	check("v1 exact bytes survive initial v2 save",FileAccess.get_file_as_bytes(v1)==v1_bytes)
	check("has_save validates only the v2 document",service.has_save())
	saved_bytes = FileAccess.get_file_as_bytes(service.metadata().slot_path)
	expected = JSON.parse_string(saved_bytes.get_string_from_utf8())
	metrics["saved_pose"] = expected.context_pose
	metrics["saved_stats"] = expected.stats
	player.global_position += Vector3(3,0,1) # Explicit fixture setup relocation, not service fallback.
	Game.health = 88.0; Game.carried_weapon = "pistol"; Game.ammo.pistol.mag = 2
	await get_tree().process_frame
	var before: Dictionary = _snapshot()
	check("load outside physics queues without state mutation",not service.load() and service.last_result.status=="pending" and _unchanged(before),service.last_result)
	var load_token: String = service.pending_token()
	check("pending load exposes exact source residency request",not _required.is_empty() and _required[-1].token==load_token and _required[-1].pose==expected.context_pose)
	if not check("fresh native physics boundary applies v2",await _physics(service.retry_pending.bind(load_token)),service.last_result): _finish(); return
	var actual: Dictionary = frame.to_source_current_live(player.global_position)
	check("canonical saved pose and heading restore exactly",actual.source_xyz==expected.context_pose.source_pose.source_xyz and player.yaw==expected.context_pose.source_pose.heading_rad)
	check("full scalar combat state restores with selected SMG",Game.health==37.0 and Game.death_count==7 and Game.carried_weapon=="smg" and Game.current_mag()==11 and Game.current_reserve()==44 and Game.wanted_heat==50.0 and Game.wanted_level==2)
	check("transient reset does not reset restored weapon",not player.busy and not player.aiming and Game.carried_weapon=="smg")
	check("v2 load leaves both slot files unchanged",FileAccess.get_file_as_bytes(v1)==v1_bytes and FileAccess.get_file_as_bytes(service.metadata().slot_path)==saved_bytes)

	# Reject an occupied/hidden passenger proxy and cabin support identity.
	var helicopter := Helicopter.new(); helicopter.position = Vector3(6,-19.95,5); helicopter.uses_source_world = true; helicopter.source_world_runtime = runtime; add_child(helicopter); runtime.bind_aircraft(helicopter)
	helicopter.interact(player)
	check("occupied hidden aircraft proxy cannot overwrite v2/anchor",not service.save() and not service.capture_anchor() and FileAccess.get_file_as_bytes(service.metadata().slot_path)==saved_bytes)
	helicopter.disabled = true
	var deaths: int = Game.death_count
	check("disabled aircraft recovery applies safe source anchor",await _physics(service.request_recovery.bind("disabled_aircraft")),service.last_result)
	check("disabled aircraft recovery exits actual vehicle without death",player.current_vehicle==null and not helicopter.pilot_is_player and Game.death_count==deaths and Game.carried_weapon=="smg")
	var recovery_token: String = service.last_result.get("token","")
	check("completed disabled token cannot apply twice",service.request_recovery("disabled_aircraft",recovery_token) and Game.death_count==deaths)
	runtime.retire_region("qa-room")
	var cabin_geometry: String = _hash("QA native cabin logical identity only")
	context.register_floor({"feature_id":"mbs-hotel/physical-shaft/QA","floor_id":"CABIN","geometry_sha256":cabin_geometry,"support_ids":["moving-platform"],"volumes":[{"volume_id":"QA logical cabin","min_xyz":_source(Vector3(-10,-20.5,-10)),"max_xyz":_source(Vector3(10,-16,10)),"dry":true}],"provenance":"QA-only native support identity, not actual physical lift mechanics"})
	runtime.commit_region("qa-cabin",_source(Vector3(-12,-25,-12)),_source(Vector3(12,-12,12)),[floor_body],[{"body":floor_body,"feature_id":"mbs-hotel/physical-shaft/QA","floor_id":"CABIN","support_id":"moving-platform"}])
	check("native cabin support cannot become source onfoot anchor",not service.capture_anchor() and not service.save() and FileAccess.get_file_as_bytes(service.metadata().slot_path)==saved_bytes)
	runtime.retire_region("qa-cabin"); _commit("B2","qa-room")

	# A floor missing from the registry is pending, with no pose/stats writes.
	var missing: Dictionary = expected.duplicate(true)
	missing.context_pose.source_pose.floor_id = "PENDING-B2"
	missing.context_pose.floor_geometry_sha256 = _hash("pending-fixture-native-floor")
	_write_document(missing)
	Game.health = 63.0; player.global_position += Vector3(2,0,1)
	before = _snapshot()
	check("missing floor queues source restore without mutation",not (await _physics(service.load)) and service.last_result.status=="pending" and _unchanged(before),service.last_result)
	var pending: String = service.pending_token()
	metrics["pending_floor"] = service.last_result.duplicate(true)
	runtime.retire_region("qa-room")
	_register_floor("PENDING-B2",missing.context_pose.floor_geometry_sha256)
	_commit("PENDING-B2","qa-pending-ready")
	check("same transaction applies after actual floor/lease commit",await _physics(service.retry_pending.bind(pending)),service.last_result)
	check("pending source floor identity is honored",runtime.inspect_player(player).support.floor_id=="PENDING-B2")
	runtime.retire_region("qa-pending-ready"); _commit("B2","qa-room")
	_write(service.metadata().slot_path,saved_bytes)

	# Changed geometry must stay blocked; valid stats alone cannot move actor.
	var changed: Dictionary = expected.duplicate(true)
	changed.context_pose.geometry_manifest_sha256 = "0".repeat(64)
	_write_document(changed); before = _snapshot()
	check("changed source geometry blocks without partial stats",not (await _physics(service.load)) and service.last_result.status=="blocked" and _unchanged(before),service.last_result)
	service.cancel_pending(service.pending_token())
	_write(service.metadata().slot_path,saved_bytes)

	# Same support body also contains a low ceiling. Never exclude it wholesale.
	var ceiling := CollisionShape3D.new(); var low := BoxShape3D.new(); low.size = Vector3(20,.2,20); ceiling.shape = low; ceiling.position.y = 1.325
	floor_body.add_child(ceiling); await _frames(4)
	before = _snapshot()
	check("same-body ceiling blocks fresh restore and preserves state",not (await _physics(service.load)) and service.last_result.status=="blocked" and _unchanged(before),service.last_result)
	metrics["same_body_ceiling"] = service.last_result.duplicate(true)
	pending = service.pending_token(); ceiling.disabled = true; await _frames(3)
	check("same blocked transaction succeeds after native clearance",await _physics(service.retry_pending.bind(pending)),service.last_result)

	# Entire document/stats validation precedes any native application.
	var invalids: Array[Dictionary] = []
	var value: Dictionary = expected.duplicate(true); value.stats.health = "37"; invalids.append(value)
	value = expected.duplicate(true); value.stats.ammo.smg.mag = 31; invalids.append(value)
	value = expected.duplicate(true); value.stats.wanted_level = 0; invalids.append(value)
	value = expected.duplicate(true); value.stats.settings.invert_y = 1; invalids.append(value)
	value = expected.duplicate(true); value.stats["legacy_position"] = [0,0,0]; invalids.append(value)
	value = expected.duplicate(true); value.version = 1; invalids.append(value)
	for index in invalids.size():
		_write_document(invalids[index]); before = _snapshot()
		check("malformed complete v2 stats rejected before mutation "+str(index),not service.load() and service.last_result.status=="invalid" and _unchanged(before))
	_write(service.metadata().slot_path,"{broken JSON".to_utf8_buffer()); before = _snapshot()
	check("corrupt JSON cannot partially load",not service.load() and not service.has_save() and _unchanged(before))
	_write(service.metadata().slot_path,saved_bytes)
	var old_health: float = Game.health; Game.health = NAN
	check("nonfinite live stats cannot replace valid slot",not service.save() and FileAccess.get_file_as_bytes(service.metadata().slot_path)==saved_bytes)
	Game.health = old_health

	# Lethal recovery increments exactly once only after native source restore.
	service.capture_anchor()
	Game.health = 0.0; player.alive = false; player.visible = false
	deaths = Game.death_count
	await get_tree().process_frame
	before = _snapshot()
	check("pending death changes no stats/pose/files",not service.request_recovery("death") and service.last_result.status=="pending" and _unchanged(before),service.last_result)
	pending = service.pending_token()
	check("source controls held while death is pending",Game.call("source_controls_held") if Game.has_method("source_controls_held") else Game.health<=0.0)
	if not check("native source death recovery applies",await _physics(service.retry_pending.bind(pending)),service.last_result): _finish(); return
	check("death increments once after apply and preserves weapon",Game.death_count==deaths+1 and Game.health==Game.MAX_HEALTH and Game.carried_weapon=="smg" and player.alive and player.visible)
	check("replaying same completed death token never increments again",service.request_recovery("death",pending) and Game.death_count==deaths+1)
	check("healthy duplicate death request is rejected",not service.request_recovery("death") and Game.death_count==deaths+1)
	check("source recovery never rewrites original source save",FileAccess.get_file_as_bytes(service.metadata().slot_path)==saved_bytes)
	check("all operations preserve original v1 exact bytes",FileAccess.get_file_as_bytes(v1)==v1_bytes)
	metrics["required_requests"] = _required
	metrics["committed_recoveries"] = _recoveries
	metrics["service"] = service.metadata()
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	Game.simulation_paused = true
	if Game.has_method("uninstall_source_session") and is_instance_valid(service): Game.call("uninstall_source_session",service)
	var report := {"schema":"source_save_native_fixture_v1","checks":checks,"failed":failures.size(),"failures":failures,"metrics":metrics,"synthetic_dry_room_not_MBS_or_city":true,"fixture_relocations_explicit":true,"visual_or_whole_world_acceptance":false}
	var path: String = output.path_join("report.json")
	if not _safe(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): get_tree().quit(2); return
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: get_tree().quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("[source-save] FINISHED checks=%d failed=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
