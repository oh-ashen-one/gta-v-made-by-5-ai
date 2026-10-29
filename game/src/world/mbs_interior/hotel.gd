extends Node3D
## Source-site vertical integration: shared floor streamer, physical shafts,
## native moving support identities and retained floor leases. No actor warp.
const Cabins = preload("res://src/world/mbs_interior/cabins.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const StairGates = preload("res://src/world/mbs_interior/stair_gates.gd")
signal transport_ready(shaft_id: String)
signal floor_request_finished(floor_id: String, ready: bool, detail: Dictionary)
var _frame: RefCounted
var _context: RefCounted
var _runtime: Node3D
var _stack: Node3D
var _base := 0.0
var _configured := false
var _shafts: Dictionary = {}
var _pending: Array[String] = []
var _draining := false
var _pins: Dictionary = {}
var _last_errors: Dictionary = {}
var _retry_after: Dictionary = {}
var _stairs: Node3D
var _stair_entries: Dictionary = {}
var _building := false
var _previous_unload_guard: Callable
var _previous_guard_set := false
var _previous_guard_owner: RefCounted

func _hash(value: String) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(value.to_utf8_buffer())
	return hash.finish().hex_encode()

func _placement(tower_id: String) -> Dictionary:
	for tower: Dictionary in Reference.DATA.towers:
		if tower.tower == tower_id:
			var anchor: Array = [tower.centroid_world_xz[0], _base, tower.centroid_world_xz[1]]
			var projected: Dictionary = _frame.to_local(anchor)
			if not projected.ok: return projected
			return {"ok": true, "anchor": anchor, "projected": projected.position,
				"axis_x": [Reference.DATA.axis_south_xz[0], 0.0, Reference.DATA.axis_south_xz[1]],
				"axis_z": [Reference.DATA.axis_bayward_xz[0], 0.0, Reference.DATA.axis_bayward_xz[1]], "source_id": tower.id}
	return {"ok": false, "error": "Unknown actual source tower"}

func _source(placement: Dictionary, point: Array) -> Array:
	return [float(placement.anchor[0]) + float(placement.axis_x[0]) * float(point[0]) + float(placement.axis_z[0]) * float(point[2]),
		float(placement.anchor[1]) + float(point[1]),
		float(placement.anchor[2]) + float(placement.axis_x[2]) * float(point[0]) + float(placement.axis_z[2]) * float(point[2])]

## Root creates the context/domain/public site and configures its FloorStack
## first. The same datum/base and World3D must be used by every component.
func build(frame: RefCounted, context: RefCounted, runtime: Node3D, stack: Node3D, base_elevation_m: float, shaft_specs: Array = []) -> Dictionary:
	if _configured or _building or get_child_count() != 0 or not is_inside_tree() or not is_finite(base_elevation_m) or absf(base_elevation_m) > 1000.0: return {"built": false, "error": "Fresh in-tree source hotel and explicit base required"}
	if not is_instance_valid(stack) or not is_instance_valid(runtime) or runtime.get("frame") != frame or runtime.get("context") != context or stack.get("_frame") != frame or stack.get("_context") != context or not is_equal_approx(float(stack.get("_base_elevation")), base_elevation_m): return {"built": false, "error": "Hotel/floor/actors must share source frame/context/base"}
	if get_world_3d() != runtime.get_world_3d() or get_world_3d() != stack.get_world_3d() or context.metadata().physics_space_id != get_world_3d().space.get_id(): return {"built": false, "error": "Hotel construction requires the exact shared native World3D"}
	for other: Node in get_tree().get_nodes_in_group("mbs_source_hotel"):
		if other != self and other.get("_context") == context: return {"built": false, "error": "This source context already has a hotel transport authority"}
	_frame = frame; _context = context; _runtime = runtime; _stack = stack; _base = base_elevation_m
	var specs: Array = shaft_specs.duplicate(true)
	if specs.is_empty():
		for tower in ["T1", "T2", "T3"]:
			for wing in ["east", "west"]:
				for kind in ["guest_lift", "service_lift"]: specs.append({"tower": tower, "wing": wing, "kind": kind, "initial_floor_id": tower + "-L1"})
	if specs.size() > 18: return {"built": false, "error": "Maximum eighteen owned reconstructed shafts"}
	var plans: Array[Dictionary] = []
	var seen: Dictionary = {}
	for spec in specs:
		if not spec is Dictionary or not spec.get("tower") is String or not spec.get("wing") is String or not spec.get("kind") is String: return {"built": false, "error": "Explicit tower/wing/kind required"}
		var descriptor: Dictionary = Cabins.inventory_descriptor(spec.tower, spec.wing, spec.kind, spec.get("initial_floor_id", String(spec.tower) + "-L1"))
		var placement := _placement(spec.tower)
		if not descriptor.get("valid", false) or not placement.ok: return {"built": false, "error": "Invalid source shaft descriptor or active source window"}
		for stop:Dictionary in descriptor.descriptor.stops:
			var planned:Dictionary=_stack.planned_floor_record(stop.floor_id) if _stack.has_method("planned_floor_record") else Inventory.floor_record(stop.floor_id)
			if planned.is_empty() or not planned.get("geometry") is Dictionary:return {"built":false,"error":"Explicit planned receiving floor unavailable: "+String(stop.floor_id)}
			var g:Dictionary=planned.geometry
			stop["receiving_door_height_m"]=g.get("core_door_height_m",Cabins.DOOR_H)
			stop["receiving_clear_height_m"]=g.get("clear_height_m",0.0)
		var normalized:Dictionary=Cabins.validate_descriptor(descriptor.descriptor)
		if not normalized.valid:return {"built":false,"error":"Planned stop dimensions rejected: "+String(normalized.get("error",""))}
		descriptor.descriptor=normalized.descriptor
		var key: String = descriptor.descriptor.shaft_id
		if seen.has(key): return {"built": false, "error": "Duplicate shaft identity"}
		seen[key] = true
		plans.append({"key": key, "descriptor": descriptor.descriptor, "placement": placement})
	_building = true
	add_to_group("mbs_source_hotel")
	var build_revision: int = frame.metadata().origin_revision
	for plan: Dictionary in plans:
		var placement: Dictionary = plan.placement
		var root := Node3D.new()
		root.name = "SourceShaft_" + String(plan.key).replace("-", "_")
		add_child(root)
		var x: Array = placement.axis_x; var z: Array = placement.axis_z
		root.global_transform = Transform3D(Basis(Vector3(x[0], 0, x[2]), Vector3.UP, Vector3(z[0], 0, z[2])), placement.projected)
		var cabin := Cabins.new()
		root.add_child(cabin)
		var key: String = plan.key
		_shafts[key] = {"node": cabin, "root": root, "descriptor": plan.descriptor, "placement": placement, "region_id": "", "registered": false}
		var result: Dictionary = cabin.build(plan.descriptor, func(id: String) -> Dictionary: return _ready_for_cabin(key, id))
		if not result.get("built", false): return await _rollback_build("Native shaft build failed: " + key)
		cabin.floor_requested.connect(_on_floor_requested)
		cabin.state_changed.connect(_on_transport_state)
	_stairs = StairGates.new()
	add_child(_stairs)
	_stairs.floor_requested.connect(func(id: String): _on_floor_requested("stair", id))
	_stairs.protection_changed.connect(_on_stair_protection)
	# Actual server insertion happens between physics boundaries; do not stamp
	# an ahead-of-physics transform or advertise readiness from node existence.
	for tick in 4: await get_tree().physics_frame
	if frame.metadata().origin_revision != build_revision: return await _rollback_build("Source origin changed during native shaft construction")
	for key: String in _shafts:
		if not _register_native_shaft(key): return await _rollback_build("Source shaft collision registration failed: " + key)
		transport_ready.emit(key)
	_previous_guard_set = bool(_stack.get("_unload_guard_set"))
	if _previous_guard_set:
		_previous_unload_guard = _stack.get("_unload_guard")
		if not _previous_unload_guard.is_valid(): return await _rollback_build("Existing floor guard is invalid; transport cannot replace it")
		var owner: Object = _previous_unload_guard.get_object()
		if owner is RefCounted: _previous_guard_owner = owner
	if not _stack.set_unload_guard(_before_floor_unload): return await _rollback_build("Floor unload guard unavailable")
	_stack.floor_committed.connect(_on_floor_committed)
	_stack.floor_retired.connect(_on_floor_retired)
	_configured = true; _building = false
	_bind_loaded_floors()
	return {"built": true, "shafts": _shafts.size(), "actor_pose_writes": 0, "full_MBS_completed": false}

func _rollback_build(error: String) -> Dictionary:
	# Context architecture records are immutable and deliberately retained.
	# Exact recipe retry reuses them; no failed geometry or lease stays live.
	for entry: Dictionary in _shafts.values():
		if not String(entry.get("region_id", "")).is_empty(): _runtime.retire_region(entry.region_id)
	for child: Node in get_children(): child.queue_free()
	for tick in 3: await get_tree().physics_frame
	_shafts.clear(); _stair_entries.clear(); _stairs = null
	_building = false; _configured = false
	remove_from_group("mbs_source_hotel")
	return {"built": false, "error": error, "owned_geometry_reaped": get_child_count() == 0, "immutable_recipe_records_retained": true}

func _collect(node: Node, bodies: Array) -> void:
	if node is CollisionObject3D and node.collision_layer != 0: bodies.append(node)
	for child: Node in node.get_children(): _collect(child, bodies)

func _register_native_shaft(key: String) -> bool:
	var entry: Dictionary = _shafts[key]
	var cabin: Node3D = entry.node
	if not cabin.shaft_collision_ready(): return false
	var descriptor: Dictionary = entry.descriptor
	var placement: Dictionary = entry.placement
	var lower := INF; var upper := -INF
	for stop: Dictionary in descriptor.stops:
		lower = minf(lower, stop.elevation_m - 0.4)
		upper = maxf(upper, stop.elevation_m + Cabins.HEIGHT + 0.4)
	var center: Array = [descriptor.center_xz[0], (lower + upper) * 0.5, descriptor.center_xz[1]]
	var half: Array = [Cabins.WIDTH * 0.5 + 0.8, (upper - lower) * 0.5, Cabins.DEPTH * 0.5 + 0.8]
	var feature := "mbs-hotel/physical-shaft/" + key
	# Geometry identity is build data, never readable GDScript source. Release
	# PCKs may strip/remap that source while retaining the same actual geometry.
	var definition := {"feature_id": feature, "floor_id": "CABIN", "geometry_sha256": _hash(JSON.stringify({"schema": "mbs_source_shaft_geometry_v1", "geometry_manifest_sha256": _context.metadata().geometry_manifest_sha256, "descriptor": descriptor, "canonical_anchor": placement.anchor})),
		"support_ids": ["moving-platform"], "volumes": [{"schema": Context.OBOX_SCHEMA, "volume_id": "enclosed-dry-shaft", "center_xyz": _source(placement, center),
			"half_extents_xyz": half, "axis_x_xyz": placement.axis_x, "axis_z_xyz": placement.axis_z, "dry": true}],
		"provenance": "Reconstructed enclosed shaft/cabin at actual tower source anchor; relative stop elevations not surveyed"}
	var registered: Dictionary = _context.floor_record(feature, "CABIN")
	if registered.ok:
		if registered.floor.geometry_sha256 != definition.geometry_sha256: return false
	elif not _context.register_floor(definition): return false
	var minimum: Array = [INF, INF, INF]; var maximum: Array = [-INF, -INF, -INF]
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var point := _source(placement, [float(center[0]) + sx * float(half[0]), float(center[1]) + sy * float(half[1]), float(center[2]) + sz * float(half[2])])
				for axis in 3:
					minimum[axis] = minf(minimum[axis], point[axis]); maximum[axis] = maxf(maximum[axis], point[axis])
	var bodies: Array = []
	_collect(cabin, bodies)
	var region := "mbs-shaft/" + key
	if not _runtime.commit_region(region, minimum, maximum, bodies, [{"body": cabin.cabin, "feature_id": feature, "floor_id": "CABIN", "support_id": "moving-platform"}]): return false
	entry.region_id = region
	var lease: Dictionary = _runtime.region_status(region)
	if not lease.live: return false
	entry.region_id = region; entry.registered = true; entry.residency_token = lease.residency_token
	return true

func _ready_for_cabin(key: String, id: String) -> Dictionary:
	var observed: Dictionary = _stack.ready_for_floor(id)
	var shaft_ready: bool = _configured and _shafts.has(key) and _shafts[key].registered and is_instance_valid(_shafts[key].node) and _shafts[key].node.shaft_collision_ready()
	if shaft_ready:
		var lease: Dictionary = _runtime.region_status(_shafts[key].region_id)
		shaft_ready = lease.live and lease.residency_token == _shafts[key].residency_token and lease.origin_revision == _frame.metadata().origin_revision
	return {"ready": bool(observed.ready), "floor_id": id, "collision_generation": String(observed.collision_generation), "travel_ready": shaft_ready and bool(observed.ready)}

func _on_floor_requested(_key: String, id: String) -> void:
	if not _pending.has(id) and _pending.size() < 32: _pending.append(id)
	if not _draining: _drain_requests.call_deferred()

func _drain_requests() -> void:
	if _draining: return
	_draining = true
	while not _pending.is_empty() and is_inside_tree():
		var id: String = _pending.pop_front()
		var result: Dictionary = await _stack.ensure_floor(id)
		_bind_loaded_floors()
		if not result.get("ready", false): _last_errors[id] = result.duplicate(true)
		else: _last_errors.erase(id)
		if not result.get("ready", false) and result.get("status", "") in ["pending_budget", "pending_busy", "protected_capacity", "neighbor_commit_pending", "physics_commit_pending"]:
			_retry_after[id] = Time.get_ticks_msec() + 1500
		floor_request_finished.emit(id, bool(result.get("ready", false)), result)
	_draining = false

func _on_floor_committed(_id: String, _generation: String) -> void:
	_bind_loaded_floors()

func _bind_loaded_floors() -> void:
	if not _configured: return
	var report: Dictionary = _stack.report()
	for id: String in report.locally_committed_floors:
		var floor_node: Node3D = _stack.get_floor(id)
		if floor_node == null: continue
		_bind_stair_floor(id, floor_node)
		for entry: Dictionary in _shafts.values():
			var cabin: Node3D = entry.node
			if cabin.report().bound_floor_ids.has(id): continue
			for stop: Dictionary in entry.descriptor.stops:
				if stop.floor_id == id: cabin.bind_floor(id, floor_node, stop.portal_id)

func _before_floor_unload(id: String) -> bool:
	if _previous_guard_set:
		if not _previous_unload_guard.is_valid(): return false
		var permitted: Variant = _previous_unload_guard.call(id)
		if typeof(permitted) != TYPE_BOOL or not permitted: return false
	if is_instance_valid(_stairs) and not _stairs.prepare_floor_retirement(id): return false
	# Preflight every relevant controller before the non-yielding unbind pass.
	var bound: Array[Node3D] = []
	for entry: Dictionary in _shafts.values():
		var cabin: Node3D = entry.node
		var state: Dictionary = cabin.report()
		if not state.bound_floor_ids.has(id): continue
		if float(state.landing_fractions.get(id, 0.0)) > .001 or (state.target_floor_id == id and state.state == "MOVING"): return false
		var floor_node: Node3D = _stack.get_floor(id)
		if floor_node != null:
			for stop: Dictionary in entry.descriptor.stops:
				if stop.floor_id == id and floor_node.doors.has(stop.portal_id) and (floor_node.doors[stop.portal_id].opened or floor_node.doors[stop.portal_id].ready_to_open): return false
		bound.append(cabin)
	for cabin: Node3D in bound:
		if not cabin.unbind_floor(id):
			_bind_loaded_floors.call_deferred()
			return false
	return true

func _stair_readiness(lower: String, id: String) -> Dictionary:
	var floor_state: Dictionary = _stack.ready_for_floor(id)
	var inserted: bool = _stair_entries.has(lower) and _stair_entries[lower].get("registered", false)
	var observed:Dictionary={"floor_id": id, "ready": bool(floor_state.ready) and (id == lower or inserted), "collision_generation": String(floor_state.collision_generation)}
	var actual:Node3D=_stack.get_floor(id)
	if is_instance_valid(actual) and actual.get("floor_record") is Dictionary:
		var g:Dictionary=actual.floor_record.get("geometry",{})
		observed["receiving_door_height_m"]=g.get("core_door_height_m",Cabins.DOOR_H)
		observed["receiving_clear_height_m"]=g.get("clear_height_m",0.0)
	return observed

func _bind_stair_floor(id: String, floor_node: Node3D) -> void:
	if not is_instance_valid(_stairs) or _stair_entries.has(id): return
	var record: Dictionary = Inventory.floor_record(id)
	var upper := ""
	for neighbor: String in _stack.adjacent_floor_ids(id):
		if float(Inventory.floor_record(neighbor).elevation_m) > float(record.elevation_m): upper = neighbor
	if upper.is_empty(): return
	var has_flight := false
	for portal: Dictionary in floor_node.portals:
		if portal.kind == "stair" and portal.get("physical_flights", false): has_flight = true
	if not has_flight: return
	_stair_entries[id] = {"upper": upper, "registered": false, "region_id": ""}
	var receiving:Dictionary=_stack.planned_floor_record(upper) if _stack.has_method("planned_floor_record") else Inventory.floor_record(upper)
	var result: Dictionary = _stairs.bind_floor(floor_node, id, upper, func(target: String): return _stair_readiness(id, target),receiving)
	if not result.get("bound", false):
		_stair_entries.erase(id)
		_last_errors["stair/" + id] = result
		return
	_register_stair_region.call_deferred(id)

func _register_stair_region(id: String) -> void:
	for tick in 4: await get_tree().physics_frame
	if not _stair_entries.has(id) or not _stack.floor_state(id).local_collision_committed: return
	var state: Dictionary = _stack.floor_state(id)
	var floor_region: Dictionary = _runtime.region_status(state.region_id)
	if not floor_region.live: return
	var bodies: Array = _stairs.owned_collision_bodies(id)
	if bodies.is_empty(): return
	for body: CollisionObject3D in bodies:
		if not body.is_inside_tree() or PhysicsServer3D.body_get_space(body.get_rid()) != get_world_3d().space or not (PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).is_equal_approx(body.global_transform): return
	var region := "mbs-stair-interlocks/" + id
	if not _runtime.commit_region(region, floor_region.minimum_source_xyz, floor_region.maximum_source_xyz, bodies, []): return
	_stair_entries[id].region_id = region
	_stair_entries[id].registered = true
	_stairs.refresh_now()

func _on_stair_protection(id: String, protected: bool) -> void:
	if protected: _stack.pin_floor(id, "source-stair-interlock")
	else: _stack.unpin_floor(id, "source-stair-interlock")

func _on_floor_retired(id: String, region: String) -> void:
	if _stair_entries.has(id):
		var owned: String = _stair_entries[id].region_id
		if not owned.is_empty(): _runtime.retire_region(owned)
	if is_instance_valid(_stairs): _stairs.floor_retired(id, region)
	_stair_entries.erase(id)

func retry_floor(id: String) -> void:
	_retry_after.erase(id)
	_on_floor_requested("root-retry", id)

func get_cabin(shaft_id: String) -> Node3D:
	return _shafts[shaft_id].node if _shafts.has(shaft_id) and is_instance_valid(_shafts[shaft_id].node) else null

func _physics_process(_delta: float) -> void:
	if not _configured or Engine.get_physics_frames() % 30 != 0: return
	# Bindings can be rebuilt after a refused partial unload handshake, while
	# transient capacity waits retry outside physics. Recipe errors remain
	# explicit integration work rather than an unbounded reload storm.
	_bind_loaded_floors()
	for key: String in _shafts: _refresh_pins(key)
	for id: String in _retry_after.keys():
		if Time.get_ticks_msec() >= int(_retry_after[id]):
			_retry_after.erase(id)
			_on_floor_requested("transient-retry", id)

func _on_transport_state(key: String, _state: String, _detail: String) -> void:
	_refresh_pins(key)

func _refresh_pins(key: String) -> void:
	if not _configured or not _shafts.has(key): return
	var state: Dictionary = _shafts[key].node.report()
	var requested: Array[String] = []
	if not String(state.target_floor_id).is_empty(): requested.append(state.target_floor_id)
	if float(state.gate_fraction) > .001 or state.state in ["OPEN", "CLOSING"]:
		if not requested.has(state.current_floor_id): requested.append(state.current_floor_id)
	var old: Array = _pins.get(key, [])
	for id: String in old:
		if not requested.has(id): _stack.unpin_floor(id, key)
	var retained: Array[String] = []
	for id: String in requested:
		if _stack.pin_floor(id, key): retained.append(id)
	_pins[key] = retained

func report() -> Dictionary:
	var shafts: Dictionary = {}
	for key: String in _shafts: shafts[key] = _shafts[key].node.report()
	return {"configured": _configured, "source_shafts": shafts, "floor_stack": _stack.report() if _configured else {},
		"pending_floor_requests": _pending.duplicate(), "load_errors": _last_errors.duplicate(true),
		"actor_pose_writes": 0, "actor_reparents": 0, "full_MBS_completed": false, "default_city_migrated": false}

func _exit_tree() -> void:
	if is_instance_valid(_stack) and _stack.get("_unload_guard") == _before_floor_unload:
		if _previous_guard_set:
			if _previous_unload_guard.is_valid(): _stack.set_unload_guard(_previous_unload_guard)
			# If that earlier owner disappeared, keep the installed guard latch.
			# This callback becomes invalid on teardown, so Stack remains closed
			# until root explicitly installs a replacement authority.
		else: _stack.release_unload_guard(_before_floor_unload)
	if is_instance_valid(_stack):
		for key: String in _pins:
			for id: String in _pins[key]: _stack.unpin_floor(id, key)
	_pins.clear()
	if is_instance_valid(_stack) and is_instance_valid(_stairs):
		for id: String in _stairs.protected_floor_ids(): _stack.unpin_floor(id, "source-stair-interlock")
	if not is_instance_valid(_runtime): return
	for entry: Dictionary in _stair_entries.values():
		if not String(entry.get("region_id", "")).is_empty(): _runtime.retire_region(entry.region_id)
	for entry: Dictionary in _shafts.values():
		if not String(entry.get("region_id", "")).is_empty(): _runtime.retire_region(entry.region_id)
