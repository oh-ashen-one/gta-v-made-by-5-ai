extends Node
## Normal source-world orchestration. File validation/application belongs to
## the service; floor preparation belongs to the actual native floor stack.
const Service = preload("res://src/world/geography/source_save_service.gd")
const Stack = preload("res://src/world/mbs_interior/floor_stack.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
var service: Node
var _world: Node3D
var _retry := false
var _preparing := ""
var _last_notice := ""
var _anchor_clock := 0.0
var _prepared_tokens: Dictionary = {}
var _queued_floor: Dictionary = {}
var _pinned: Dictionary = {}
var _attempts: Dictionary = {}
var _retry_floors: Dictionary = {}

func configure(world: Node3D) -> bool:
	if is_instance_valid(service) or not is_instance_valid(world): return false
	_world = world
	service = Service.new()
	service.name = "SourceSaveService"
	add_child(service)
	if not service.configure(world.source_runtime,world.player,Game.save_slot_path(),"","supported_native_surface") or not Game.install_source_session(service):
		service.queue_free()
		service = null
		return false
	service.restore_required.connect(_on_restore_required)
	service.restored.connect(_on_restored)
	if is_instance_valid(world.floor_stack): world.floor_stack.floor_committed.connect(_on_floor_committed)
	# Binding occurs only after actual world/actor collision insertion. The
	# next physics boundary captures the initial canonical supported anchor.
	_anchor_clock = 1.0
	return true

func capture_initial_anchor() -> bool:
	return is_instance_valid(service) and Game.source_session_owns(service) and service.capture_anchor()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(service) or not is_instance_valid(_world) or not _world.ready_for_play or Game.simulation_paused: return
	if not Game.source_session_owns(service):
		for token in _pinned.keys(): _release_pin(token)
		_queued_floor.clear()
		return
	var current: String = service.pending_token()
	for token in _prepared_tokens.keys():
		if token != current: _release_pin(token)
	for token in _retry_floors.keys():
		if token != current: _retry_floors.erase(token)
	if _preparing.is_empty() and _retry_floors.has(current) and Time.get_ticks_msec() >= int(_retry_floors[current].after):
		_queued_floor = {"id":_retry_floors[current].id,"token":current}
		_retry_floors.erase(current)
	if not _queued_floor.is_empty() and _preparing.is_empty():
		var queued := _queued_floor.duplicate()
		_queued_floor.clear()
		_preparing = queued.token
		_prepare_floor.call_deferred(queued.id,queued.token)
	if _retry and _preparing.is_empty():
		_retry = false
		service.retry_pending(service.pending_token())
		_handle_failed_load()
	if not service.pending_token().is_empty(): return
	_anchor_clock += delta
	if _anchor_clock >= 1.0:
		_anchor_clock = 0.0
		service.capture_anchor()

func save_game() -> bool:
	if not is_instance_valid(service) or not Game.source_session_owns(service) or service.metadata().get("transaction_busy",false): return false
	var saved: bool = Game.save_game()
	Events.toast("Progress saved." if saved else "Save after standing on a clear, supported surface.","good" if saved else "normal")
	return saved

func load_game() -> bool:
	if not is_instance_valid(service) or not Game.source_session_owns(service) or service.metadata().get("transaction_busy",false): return false
	var applied: bool = Game.load_game()
	_handle_failed_load()
	if not applied and service.pending_token().is_empty(): Events.toast("No compatible source-world save is available.","normal")
	return applied

func _on_restore_required(reason: String,pose: Dictionary,token: String) -> void:
	if not Game.source_session_owns(service) or token.is_empty() or token != service.pending_token(): return
	if reason == "fresh_physics_boundary_required":
		_retry = true
		return
	var source: Dictionary = pose.get("source_pose",{})
	if source.get("feature_id","") == Stack.FEATURE and not Inventory.floor_record(source.get("floor_id","")).is_empty() and not _prepared_tokens.has(token):
		_prepared_tokens[token] = true
		Events.toast("Preparing your saved position…","normal")
		_queued_floor = {"id":String(source.floor_id),"token":token}
		return
	if _preparing == token or _queued_floor.get("token", "") == token or _retry_floors.has(token): return
	var key := token+"/"+reason
	if key == _last_notice: return
	_last_notice = key
	Events.toast("The saved position is not ready or is obstructed.","warn")
	# A refused manual load leaves the current playable scene intact. Death
	# recovery remains held until its actual checkpoint can be prepared.
	if service.metadata().pending_kind == "load":
		if service.cancel_pending(token) or service.pending_token() != token: _release_pin(token)
		_prepared_tokens.erase(token)

func _prepare_floor(id: String,token: String) -> void:
	if not is_instance_valid(service) or token != service.pending_token() or not is_instance_valid(_world.floor_stack):
		_preparing = ""
		if is_instance_valid(service) and token == service.pending_token(): _on_restore_required("checkpoint_floor_loader_unavailable",{},token)
		return
	if not Game.source_session_owns(service):
		_preparing = ""
		return
	_attempts[token] = int(_attempts.get(token,0))+1
	var stack: Node3D = _world.floor_stack
	var owner := "source-restore/"+token
	if not stack.pin_floor(id,owner):
		_preparing = ""
		if not _schedule_floor_retry(id,token): _on_restore_required("checkpoint_floor_pin_unavailable",{},token)
		return
	_pinned[token] = {"stack":weakref(stack),"id":id,"owner":owner}
	var result: Dictionary = await stack.ensure_floor(id)
	_preparing = ""
	if not is_instance_valid(service) or not Game.source_session_owns(service) or token != service.pending_token():
		_release_pin(token)
		return
	if result.get("ready",false): _retry = true
	elif not _schedule_floor_retry(id,token): _on_restore_required("checkpoint_floor_not_ready",{},token)

func _schedule_floor_retry(id: String,token: String) -> bool:
	if int(_attempts.get(token,0)) >= 8: return false
	_retry_floors[token] = {"id":id,"after":Time.get_ticks_msec()+int(minf(8.0,pow(2.0,int(_attempts.get(token,0)))))*1000}
	return true

func _handle_failed_load() -> void:
	if not Game.source_session_owns(service) or service.metadata().get("transaction_busy",false): return
	var token: String = service.pending_token()
	if not token.is_empty() and service.metadata().pending_kind == "load" and service.last_result.get("status", "") in ["invalid","blocked"]:
		if service.last_result.get("reason", "") != "source_slot_changed_during_pending_restore" and (_preparing == token or _queued_floor.get("token", "") == token or _retry_floors.has(token)): return
		if service.cancel_pending(token) or service.pending_token() != token: _release_pin(token)
		Events.toast("That save could not be restored; your current position is unchanged.","warn")

func _on_restored(reason: String,token: String) -> void:
	_release_pin(token)
	_prepared_tokens.erase(token)
	_last_notice = ""
	Events.toast("Progress restored." if reason == "load" else "Recovered at your last safe position.","good")

func _on_floor_committed(_floor_id: String,_generation: String) -> void:
	if is_instance_valid(service) and not service.pending_token().is_empty(): _retry = true

func _release_pin(token: String) -> void:
	_retry_floors.erase(token)
	_attempts.erase(token)
	_prepared_tokens.erase(token)
	if not _pinned.has(token): return
	var pin: Dictionary = _pinned[token]
	var stack: Object = pin.stack.get_ref()
	if is_instance_valid(stack): stack.unpin_floor(pin.id,pin.owner)
	_pinned.erase(token)

func _exit_tree() -> void:
	for token in _pinned.keys(): _release_pin(token)
	if is_instance_valid(service): Game.uninstall_source_session(service)
