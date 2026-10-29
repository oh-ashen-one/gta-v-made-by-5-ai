extends Node
## Separate canonical source-v2 slot. This service never reads v1 as a parser,
## never writes v1 bytes and never treats a local position as a source anchor.
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const SCHEMA := "orchard_reach_source_save_v2"
const SCOPE := "onfoot_combat_inventory_settings_no_missions_doors_or_vehicles"
const MAX_BYTES := 65536
const DOC_KEYS := ["schema","version","scope","context_pose","stats"]
const STATS_KEYS := ["health","death_count","wanted_level","wanted_heat","elapsed_seconds","seed","mode","carried_weapon","ammo","settings","search_timer","since_damage"]
signal restore_required(reason: String, context_pose: Dictionary, token: String)
signal restored(reason: String, token: String)
signal recovery_committed(reason: String, token: String, death_count: int)
var last_result: Dictionary = {}
var _runtime: Node3D
var _player: Player
var _configured := false
var _legacy := ""
var _slot := ""
var _qa := ""
var _anchor: Dictionary = {}
var _anchor_status: Dictionary = {}
var _pending: Dictionary = {}
var _serial := 0
var _completed_recovery_serial := 0
var _last_completed_token := ""
var _busy := false
var _recovery_tokens: Dictionary = {}

func _exact(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

func _number(value: Variant,lo: float,hi: float) -> bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value)) and float(value)>=lo and float(value)<=hi

func _integer(value: Variant,lo: int,hi: int) -> bool:
	return _number(value,float(lo),float(hi)) and floor(float(value))==float(value)

func _hash(value: Variant) -> bool:
	if not value is String or value.length()!=64: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true

func _label(value: Variant,empty: bool = false,maximum: int = 256) -> bool:
	return value is String and value.length()<=maximum and (empty or not value.is_empty())

func _result(status: String,reason: String = "",extra: Dictionary = {}) -> Dictionary:
	last_result = {"ok":status in ["bound","captured","saved","applied","already_completed","anchor_captured","cancelled"],"status":status,"reason":reason}
	last_result.merge(extra,true)
	return last_result.duplicate(true)

func _absolute(path: String) -> String:
	var value: String = ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	if value.begins_with("/tmp/"): value = "/private/tmp/"+value.trim_prefix("/tmp/")
	return value

func _safe_path(path: String,allow_missing: bool = true) -> bool:
	if not path.is_absolute_path() or path!=path.simplify_path() or path.length()>2048 or path.get_file().is_empty(): return false
	var current := "/"
	for part in path.trim_prefix("/").split("/",false):
		var directory := DirAccess.open(current)
		if directory!=null and directory.is_link(part): return false
		current = current.path_join(part)
	if DirAccess.dir_exists_absolute(path): return false
	return allow_missing or FileAccess.file_exists(path)

## Bind one actual production player/runtime/world. qa_session defaults to the
## real command-line session; a QA run cannot fall back to the owner's slot.
func configure(runtime: Node3D,player: Player,legacy_save_path: String = "",qa_session: String = "") -> bool:
	if _configured or not is_inside_tree() or not is_instance_valid(runtime) or not runtime is Runtime or not runtime.is_inside_tree() or not runtime.context is Context or not is_instance_valid(player) or not player.is_inside_tree() or player.source_world_runtime!=runtime or not player.uses_source_world or runtime.get_world_3d()!=player.get_world_3d() or not runtime.context.metadata().configured or not runtime._valid_player_profile(player): _result("invalid","source_binding_mismatch"); return false
	var legacy_input: String = legacy_save_path
	if legacy_input.is_empty():
		legacy_input = String(Game.call("save_slot_path")) if Game.has_method("save_slot_path") else String(Game.get("_save_path"))
	var legacy: String = _absolute(legacy_input)
	if not _safe_path(legacy) or not legacy.get_file().ends_with(".json") or legacy.get_file().contains(".source-v2"): _result("invalid","unsafe_legacy_slot_path"); return false
	var args := OS.get_cmdline_user_args()
	var qa_marker: bool = args.has("--qa-session") or args.has("--test") or args.has("--capture")
	for arg in args:
		if arg.begins_with("--save-probe="): qa_marker = true
	var command_qa := ""
	var index := args.find("--qa-session")
	if index>=0 and index+1<args.size(): command_qa = _absolute(args[index+1])
	var qa: String = _absolute(qa_session) if not qa_session.is_empty() else command_qa
	if qa_marker:
		if command_qa.is_empty() or qa!=command_qa or not qa.is_absolute_path() or qa!=qa.simplify_path() or not legacy.begins_with(qa.trim_suffix("/")+"/"): _result("invalid","QA_requires_original_private_session_slot"); return false
	elif not qa.is_empty():
		if not qa.is_absolute_path() or qa!=qa.simplify_path() or not legacy.begins_with(qa.trim_suffix("/")+"/"): _result("invalid","invalid_explicit_QA_scope"); return false
	var slot: String = legacy.trim_suffix(".json")+".source-v2.json"
	if slot==legacy or not _safe_path(slot): _result("invalid","unsafe_source_sibling_slot"); return false
	_runtime = runtime; _player = player; _legacy = legacy; _slot = slot; _qa = qa
	_configured = true
	_result("bound")
	return true

func is_bound_to(runtime: Object,player: Object) -> bool:
	return _configured and is_instance_valid(_runtime) and is_instance_valid(_player) and _runtime.is_inside_tree() and _player.is_inside_tree() and runtime==_runtime and player==_player and _player.source_world_runtime==_runtime and _player.uses_source_world and _runtime.get_world_3d()==_player.get_world_3d() and _runtime._valid_player_profile(_player)

func metadata() -> Dictionary:
	return {"schema":SCHEMA,"configured":_configured,"slot_path":_slot,"legacy_path":_legacy,"qa_session":_qa,"scope":SCOPE,"has_source_anchor":not _anchor.is_empty(),"anchor_restore_state":_anchor_status.duplicate(true),"pending_token":pending_token(),"pending_reason":_pending.get("reason",""),"pending_kind":_pending.get("kind",""),"completed_recovery_serial":_completed_recovery_serial,"legacy_save_read_or_written":false,"mission_doors_vehicle_NPC_state_included":false}

func pending_token() -> String:
	return String(_pending.get("token",""))

func _set_hold(held: bool) -> void:
	# Game validates exact currently installed service ownership. configure()
	# itself remains independent and cannot take over another live session.
	if Game.has_method("set_source_recovery_hold"): Game.call("set_source_recovery_hold",self,held)

func _validate_stats(stats: Variant) -> bool:
	if not _exact(stats,STATS_KEYS): return false
	if not _number(stats.health,.01,Game.MAX_HEALTH) or not _integer(stats.death_count,0,2147483647) or not _integer(stats.wanted_level,0,3) or not _number(stats.wanted_heat,0,100000000.0): return false
	var heat: float = stats.wanted_heat
	var level: int = 3 if heat>=100.0 else (2 if heat>=45.0 else (1 if heat>=12.0 else 0))
	if int(stats.wanted_level)!=level or not _number(stats.elapsed_seconds,0,1000000000.0) or not _integer(stats.seed,0,2147483647) or not _integer(stats.mode,Game.MODE_FOOT,Game.MODE_FOOT): return false
	if not _number(stats.search_timer,0,1000000.0) or not _number(stats.since_damage,0,1000000.0) or not stats.carried_weapon in ["pistol","smg"]: return false
	if not _exact(stats.ammo,["pistol","smg"]): return false
	for weapon in ["pistol","smg"]:
		var slot: Variant = stats.ammo[weapon]
		if not _exact(slot,["mag","reserve"]) or not _integer(slot.mag,0,12 if weapon=="pistol" else 30) or not _integer(slot.reserve,0,1000000): return false
	if not _exact(stats.settings,["mouse_sensitivity","invert_y","reduced_shake","hud_visible"]) or not _number(stats.settings.mouse_sensitivity,.2,3.0): return false
	for flag in ["invert_y","reduced_shake","hud_visible"]:
		if not stats.settings[flag] is bool: return false
	return true

func _live_stats(recovery: bool = false,death: bool = false) -> Dictionary:
	return {"health":Game.MAX_HEALTH if recovery else Game.health,"death_count":Game.death_count+(1 if death else 0),"wanted_level":0 if recovery else Game.wanted_level,"wanted_heat":0.0 if recovery else Game.wanted_heat,"elapsed_seconds":Game.elapsed_seconds,"seed":Game.seed_value,"mode":Game.MODE_FOOT if recovery else Game.mode,"carried_weapon":Game.carried_weapon,"ammo":Game.ammo.duplicate(true),"settings":Game.settings.duplicate(true),"search_timer":0.0 if recovery else Game.search_timer,"since_damage":0.0 if recovery else float(Game.get("_since_damage"))}

func _pose_structure(pose: Variant) -> bool:
	if not _exact(pose,Context.RESTORE_KEYS) or pose.schema!=Context.RESTORE_SCHEMA: return false
	for field in ["geometry_manifest_sha256","vertical_manifest_sha256","floor_geometry_sha256"]:
		if not _hash(pose[field]): return false
	var source: Variant = pose.source_pose
	if not _exact(source,Frame.POSE_KEYS) or source.schema!=Frame.POSE_SCHEMA or not _hash(source.snapshot_manifest_sha256) or not _hash(source.frame_fingerprint): return false
	if not source.source_xyz is Array or source.source_xyz.size()!=3 or not _number(source.heading_rad,-1000000.0,1000000.0): return false
	for n in source.source_xyz:
		if not _number(n,-Frame.MAX_CANONICAL_COMPONENT_M,Frame.MAX_CANONICAL_COMPONENT_M): return false
	if not _label(source.feature_id) or not _label(source.floor_id) or not _label(source.room_id,true): return false
	# On-foot anchor only. An occupied hidden passenger proxy or moving cabin
	# cannot become the source recovery point even if a crafted save saysFOOT.
	if source.floor_id.to_upper()=="CABIN" or source.feature_id.begins_with("mbs-hotel/physical-shaft/"): return false
	var elevation: Variant = source.elevation_reference
	if not _exact(elevation,["status","reference","source_reference"]) or not elevation.status in ["unknown","staging","source_tag","surveyed"] or not _label(elevation.reference,false,160) or not _label(elevation.source_reference,true,512): return false
	return true

func _validate_document(value: Variant) -> Dictionary:
	if not _exact(value,DOC_KEYS) or value.schema!=SCHEMA or not _integer(value.version,2,2) or value.scope!=SCOPE or not _validate_stats(value.stats) or not _pose_structure(value.context_pose): return {"ok":false,"status":"invalid","reason":"invalid_source_v2_envelope_or_complete_stats"}
	return {"ok":true,"document":value.duplicate(true)}

func _compatible(pose: Dictionary) -> Dictionary:
	var identity: Dictionary = _runtime.context.metadata()
	if pose.geometry_manifest_sha256!=identity.geometry_manifest_sha256 or pose.vertical_manifest_sha256!=identity.vertical_manifest_sha256: return {"ok":false,"status":"blocked","reason":"source_geometry_or_vertical_version_changed"}
	var checked: Dictionary = _runtime.context.validate_restore_pose(pose)
	if not checked.get("ok",false): return {"ok":false,"status":"blocked","reason":"source_frame_snapshot_or_elevation_changed","detail":checked}
	return {"ok":true}

func _capture_pose() -> Dictionary:
	if not is_bound_to(_runtime,_player): return {"ok":false,"reason":"source_binding_lost"}
	if Game.mode!=Game.MODE_FOOT or _player.current_vehicle!=null or not _player.visible or not _player.is_visible_in_tree() or not _player.alive or _player.busy: return {"ok":false,"reason":"onfoot_visible_unoccupied_anchor_required"}
	var state: Dictionary = _runtime.inspect_player(_player)
	if not state.get("ok",false) or state.residency.state!="resident" or state.support.state!="supported" or state.clearance.state!="clear" or state.water.state=="submerged": return {"ok":false,"reason":"fresh_supported_clear_source_anchor_required","detail":state}
	var captured: Dictionary = _runtime.capture_player_pose(_player)
	if not captured.get("ok",false) or not _pose_structure(captured.pose): return {"ok":false,"reason":"moving_cabin_or_invalid_source_pose"}
	return {"ok":true,"pose":captured.pose.duplicate(true),"state":state}

func capture() -> Dictionary:
	var captured: Dictionary = _capture_pose()
	if not captured.get("ok",false): return _result("invalid",captured.get("reason","capture_refused"),{"detail":captured})
	var document := {"schema":SCHEMA,"version":2,"scope":SCOPE,"context_pose":captured.pose,"stats":_live_stats()}
	var valid: Dictionary = _validate_document(document)
	if not valid.ok: return _result("invalid",valid.reason)
	return _result("captured","",{"document":valid.document})

func capture_anchor() -> bool:
	var captured: Dictionary = _capture_pose()
	if not captured.get("ok",false): _result("invalid",captured.get("reason","anchor_refused")); return false
	_anchor = captured.pose.duplicate(true)
	var query: Dictionary = _runtime.context.begin_query(_anchor.source_pose.source_xyz)
	_anchor_status = _runtime.context.preflight_restore(_anchor,query.query,_runtime._native_player_observations(query.query,_player)) if query.get("ok",false) else {"status":"pending","reason":"origin_or_physics_context_required"}
	_result("anchor_captured","",{"restore_state":_anchor_status.duplicate(true)})
	return true

func _read_document() -> Dictionary:
	if not _configured or not _safe_path(_slot,false): return {"ok":false,"status":"invalid","reason":"source_slot_unavailable_or_unsafe"}
	var file := FileAccess.open(_slot,FileAccess.READ)
	if file==null or file.get_length()<2 or file.get_length()>MAX_BYTES: return {"ok":false,"status":"invalid","reason":"source_slot_size_or_access"}
	var raw: PackedByteArray = file.get_buffer(file.get_length())
	if raw.size()!=file.get_length(): return {"ok":false,"status":"invalid","reason":"incomplete_source_slot_read"}
	if raw.get_string_from_utf8().to_utf8_buffer()!=raw: return {"ok":false,"status":"invalid","reason":"invalid_source_UTF8"}
	var parser := JSON.new()
	if parser.parse(raw.get_string_from_utf8())!=OK: return {"ok":false,"status":"invalid","reason":"corrupt_source_JSON"}
	var checked: Dictionary = _validate_document(parser.data)
	if not checked.ok: return checked
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(raw)
	checked["file_sha256"] = hash.finish().hex_encode()
	return checked

func has_save() -> bool:
	# A valid document may still need a different current geometry/floor. Keep
	# it visible; load reports pending/blocked instead of erasing the old slot.
	return is_bound_to(_runtime,_player) and _read_document().get("ok",false)

func save() -> bool:
	if _busy or not _pending.is_empty(): _result("blocked","another_source_transaction_pending"); return false
	var captured: Dictionary = capture()
	if not captured.ok: return false
	if not _safe_path(_slot) or not _safe_path(_legacy): _result("invalid","source_slot_path_changed"); return false
	var payload: PackedByteArray = JSON.stringify(captured.document,"\t",true,true).to_utf8_buffer()
	if payload.size()>MAX_BYTES: _result("invalid","source_slot_exceeds_bound"); return false
	var directory: String = _slot.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: _result("invalid","source_directory_unavailable"); return false
	var temporary: String = _slot+".tmp-"+str(OS.get_process_id())+"-"+str(get_instance_id())+"-"+str(Time.get_ticks_usec())
	if not _safe_path(temporary) or FileAccess.file_exists(temporary): _result("invalid","temporary_source_slot_exists_or_unsafe"); return false
	_busy = true
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: _busy = false; _result("invalid","source_temporary_open_failed"); return false
	file.store_buffer(payload); file.flush()
	var complete: bool = file.get_error()==OK and file.get_length()==payload.size()
	file.close()
	if not complete or not _safe_path(_slot) or not _safe_path(temporary,false):
		DirAccess.remove_absolute(temporary); _busy = false; _result("invalid","source_temporary_write_or_path_failed"); return false
	# Validate the actual complete bytes before the single same-directory rename.
	var written: PackedByteArray = FileAccess.get_file_as_bytes(temporary)
	if written!=payload or DirAccess.rename_absolute(temporary,_slot)!=OK:
		DirAccess.remove_absolute(temporary); _busy = false; _result("invalid","source_atomic_publish_failed"); return false
	_busy = false
	_anchor = captured.document.context_pose.duplicate(true)
	_anchor_status = {"status":"captured_not_cold_restore_proof"}
	_result("saved","",{"bytes":payload.size(),"slot_path":_slot})
	return true

func _new_token(kind: String) -> String:
	_serial += 1
	return "source-"+kind+":"+str(get_instance_id())+":"+str(_serial)

func _completed_recovery(token: String) -> bool:
	return _recovery_tokens.get(token,"")=="completed"

func load() -> bool:
	if not is_bound_to(_runtime,_player) or _busy: _result("invalid","source_binding_lost_or_busy"); return false
	if not _pending.is_empty(): return retry_pending()
	var read: Dictionary = _read_document()
	if not read.get("ok",false): _result(read.get("status","invalid"),read.get("reason","read_failed")); return false
	_pending = {"kind":"load","reason":"load","token":_new_token("load"),"document":read.document.duplicate(true),"file_sha256":read.file_sha256}
	_set_hold(true)
	return retry_pending()

func _emit_required(reason: String) -> void:
	var pose: Dictionary = _pending.get("document",{}).get("context_pose",{}).duplicate(true)
	restore_required.emit(reason,pose,pending_token())

func retry_pending(token: String = "") -> bool:
	if not is_bound_to(_runtime,_player) or _busy: _result("invalid","source_binding_lost_or_busy"); return false
	if _pending.is_empty():
		if not token.is_empty() and (token==_last_completed_token or _completed_recovery(token)): _result("already_completed","",{"token":token}); return true
		_result("invalid","no_matching_pending_source_restore"); return false
	if not token.is_empty() and token!=pending_token(): _result("invalid","different_pending_restore_token"); return false
	if _pending.kind=="recovery":
		if _anchor.is_empty():
			var saved: Dictionary = _read_document()
			if saved.get("ok",false) and _compatible(saved.document.context_pose).get("ok",false): _anchor = saved.document.context_pose.duplicate(true)
		if _anchor.is_empty():
			_result("pending","no_valid_source_onfoot_anchor",{"token":pending_token()})
			_emit_required("no_valid_source_onfoot_anchor")
			return false
		# Recovery keeps current ammunition/settings/death accounting through a
		# streaming wait; load intentionally restores its complete saved snapshot.
		_pending.document = {"schema":SCHEMA,"version":2,"scope":SCOPE,"context_pose":_anchor.duplicate(true),"stats":_live_stats(true,_pending.reason=="death")}
	var document: Dictionary = _pending.get("document",{})
	var valid: Dictionary = _validate_document(document)
	if not valid.ok: _result("invalid",valid.reason,{"token":pending_token()}); return false
	if _pending.kind=="load" and (not _safe_path(_slot,false) or FileAccess.get_sha256(_slot)!=_pending.file_sha256): _result("blocked","source_slot_changed_during_pending_restore",{"token":pending_token()}); return false
	var compatible: Dictionary = _compatible(document.context_pose)
	if not compatible.ok: _result(compatible.status,compatible.reason,{"token":pending_token()}); _emit_required(compatible.reason); return false
	if not Engine.is_in_physics_frame():
		_result("pending","fresh_physics_boundary_required",{"token":pending_token()})
		_emit_required("fresh_physics_boundary_required")
		return false
	# No yield or scene callback between fresh Runtime preflight+actual pose
	# application and committing the already fully validated scalar state.
	_busy = true
	var applied: Dictionary = _runtime.restore_player_pose(_player,document.context_pose)
	if not applied.get("ok",false) or applied.get("status")!="applied":
		_busy = false
		var status: String = applied.get("status","invalid")
		_result(status,applied.get("reason",str(applied.get("reasons",applied.get("error","restore_not_ready")))),{"token":pending_token(),"detail":applied.duplicate(true)})
		_emit_required(last_result.reason)
		return false
	var transaction: Dictionary = _pending.duplicate(true)
	_apply_stats(document.stats)
	_anchor = document.context_pose.duplicate(true)
	_anchor_status = {"status":"applied","physics_tick":applied.physics_tick}
	_last_completed_token = transaction.token
	if transaction.kind=="recovery":
		_completed_recovery_serial = maxi(_completed_recovery_serial,int(String(transaction.token).get_slice(":",2)))
		_recovery_tokens[transaction.token] = "completed"
	_pending.clear()
	_busy = false
	_set_hold(false)
	_result("applied","",{"token":transaction.token,"kind":transaction.kind,"physics_tick":applied.physics_tick})
	# Signals occur only after the complete state commit. No legacy parser or
	# reset_action_state() default can overwrite the restored selected weapon.
	Events.health_changed.emit(Game.health,Game.MAX_HEALTH)
	Events.wanted_changed.emit(Game.wanted_level)
	Events.ammo_changed.emit(Game.current_mag(),Game.current_reserve())
	Events.settings_changed.emit(Game.settings.duplicate(true))
	Events.state_restored.emit()
	restored.emit(transaction.reason,transaction.token)
	if transaction.kind=="recovery": recovery_committed.emit(transaction.reason,transaction.token,Game.death_count)
	return true

func _apply_stats(stats: Dictionary) -> void:
	Game.health = float(stats.health); Game.death_count = int(stats.death_count)
	Game.wanted_level = int(stats.wanted_level); Game.wanted_heat = float(stats.wanted_heat)
	Game.elapsed_seconds = float(stats.elapsed_seconds); Game.seed_value = int(stats.seed)
	Game.carried_weapon = stats.carried_weapon
	Game.ammo = stats.ammo.duplicate(true); Game.settings = stats.settings.duplicate(true)
	Game.search_timer = float(stats.search_timer); Game.set("_since_damage",float(stats.since_damage))
	Game.player_seen = false
	Game.player_position = _player.global_position; Game.player_rotation = _player.yaw
	Game.last_seen_position = _player.global_position
	Game.set("_last_shot_at",-100.0); Game.set("_lost_search_msg_at",-100.0)
	Game.mode = Game.MODE_FOOT
	_player.reset_action_state(false)

func request_recovery(reason: String = "death",token: String = "") -> bool:
	if not is_bound_to(_runtime,_player) or _busy or not reason in ["death","disabled_aircraft"]: _result("invalid","recovery_binding_or_reason_invalid"); return false
	if not token.is_empty() and _completed_recovery(token): _result("already_completed","",{"token":token}); return true
	if not _pending.is_empty():
		if _pending.kind!="recovery" or (not token.is_empty() and token!=pending_token()): _result("blocked","another_source_restore_pending"); return false
		# A disabled-aircraft recovery can become a death before it applies.
		# Promote that SAME token exactly once rather than heal past a death or
		# create a second independent transaction/accounting increment.
		if reason=="death" and Game.health<=0.0 and _pending.reason!="death":
			var promoted: Dictionary = _live_stats(true,true)
			if not _validate_stats(promoted): _result("invalid","invalid_recovery_stats"); return false
			_pending.document.stats = promoted; _pending.reason = "death"
		return retry_pending(token)
	if not token.is_empty(): _result("invalid","unknown_recovery_token"); return false
	if reason=="death" and Game.health>0.0: _result("invalid","death_recovery_requires_current_death"); return false
	if reason=="disabled_aircraft" and Game.health<=0.0: _result("invalid","death_recovery_required"); return false
	var stats: Dictionary = _live_stats(true,reason=="death")
	if not _validate_stats(stats): _result("invalid","invalid_recovery_stats"); return false
	# Keep exact issued-token outcomes rather than evict old completed tokens
	# and accidentally count a replay twice. A conservative session bound holds
	# new requests explicitly rather than silently forgetting recovery history.
	if _recovery_tokens.size()>=65536: _result("blocked","recovery_token_session_history_bound"); return false
	var issued: String = _new_token("recovery")
	_recovery_tokens[issued] = "pending"
	_pending = {"kind":"recovery","reason":reason,"token":issued,"document":{}}
	_set_hold(true)
	return retry_pending()

func cancel_pending(token: String) -> bool:
	if _busy or token.is_empty() or token!=pending_token(): return false
	if _pending.kind=="recovery": _recovery_tokens[token] = "cancelled"
	_pending.clear()
	_set_hold(false)
	_result("cancelled","",{"token":token})
	return true
