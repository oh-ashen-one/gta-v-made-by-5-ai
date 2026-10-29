extends Node3D
## Main-thread native adapter for an explicitly installed source world.
## A runtime is not installed in the legacy fictional bootstrap. Callers must
## commit complete collision neighborhoods and supply versioned domain data.
const Context = preload("res://src/world/geography/source_world_context.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
var context: RefCounted
var frame: RefCounted
var last_error := ""
var _domain: Callable
var _domain_owner: RefCounted
var _regions: Dictionary = {}
var _supports: Dictionary = {}
var _generation := 0
var _configured := false
var native_clearance_diagnostics: Dictionary = {}
var _profile_residency := "--profile-source-runtime" in OS.get_cmdline_user_args()
var _residency_cost := {"calls": 0, "total_us": 0, "max_us": 0, "body_liveness_checks": 0, "inventory_reference_visits": 0, "inventory_groups_validated": 0, "inventory_group_reuses": 0}
var _diagnose_motion := "--diagnose-source-motion" in OS.get_cmdline_user_args()
var _motion_decisions: Dictionary = {}
var _motion_rejections: Dictionary = {}
var _last_residency_diagnostic: Dictionary = {}
var _residency_diagnostic_serial := 0

func motion_diagnostics(actor: CharacterBody3D = null) -> Dictionary:
	var id: int = actor.get_instance_id() if is_instance_valid(actor) else 0
	return {"enabled":_diagnose_motion,"actor_id":id,"last_decision":_motion_decisions.get(id,{}).duplicate(true),"last_rejection":_motion_rejections.get(id,{}).duplicate(true),"last_residency_query":_last_residency_diagnostic.duplicate(true)}

func _diagnostic_vector(value: Vector3) -> Array:
	return [float(value.x),float(value.y),float(value.z)]

func _record_motion(actor: CharacterBody3D,allowed: bool,reason: String,delta: float,detail: Dictionary = {}) -> void:
	if not _diagnose_motion: return
	var actor_valid: bool = is_instance_valid(actor)
	var id: int = actor.get_instance_id() if actor_valid else 0
	var row := {"allowed":allowed,"reason":reason,"physics_tick":Engine.get_physics_frames(),"wall_us":Time.get_ticks_usec(),"delta_s":delta,"actor_id":id,"actor_valid":actor_valid,"detail":detail.duplicate(true)}
	if actor_valid:
		var inside: bool = actor.is_inside_tree()
		var basis: Basis = actor.global_basis if inside else actor.basis
		row.merge({"actor_name":String(actor.name),"inside_tree":inside,"requested_velocity":_diagnostic_vector(actor.velocity),"position":_diagnostic_vector(actor.global_position if inside else actor.position),"basis":[_diagnostic_vector(basis.x),_diagnostic_vector(basis.y),_diagnostic_vector(basis.z)],"rotation_y":actor.global_rotation.y if inside else actor.rotation.y})
	if actor_valid and not allowed and reason in ["player_profile_or_actor_type","car_hull_profile"]:
		var shapes: Array[Dictionary] = []
		for child: Node in actor.get_children():
			if not child is CollisionShape3D: continue
			var shape: Shape3D = child.shape
			var shape_row := {"name":String(child.name),"disabled":child.disabled,"position":_diagnostic_vector(child.position),"basis":[_diagnostic_vector(child.basis.x),_diagnostic_vector(child.basis.y),_diagnostic_vector(child.basis.z)],"class":shape.get_class() if shape!=null else "null"}
			if shape is CapsuleShape3D: shape_row.merge({"radius":shape.radius,"height":shape.height})
			elif shape is BoxShape3D: shape_row["size"] = _diagnostic_vector(shape.size)
			shapes.append(shape_row)
		row["actor_shape_profile"] = shapes
	if not _motion_decisions.has(id) and _motion_decisions.size()>=64:
		var old: Variant = _motion_decisions.keys()[0]
		_motion_decisions.erase(old); _motion_rejections.erase(old)
	_motion_decisions[id] = row
	if not allowed: _motion_rejections[id] = row.duplicate(true)

func _motion_refused(actor: CharacterBody3D,reason: String,delta: float,detail: Dictionary = {}) -> bool:
	_record_motion(actor,false,reason,delta,detail)
	return false

func _diagnostic_body_failure(body: Object,current_world: World3D) -> Dictionary:
	var result := {"body_id":body.get_instance_id(),"name":String((body as Node).name),"inside_tree":(body as Node).is_inside_tree(),"collision_layer":body.get("collision_layer")}
	if not result.inside_tree: result["reason"] = "body_outside_tree"
	elif int(result.collision_layer)==0: result["reason"] = "body_layer_zero"
	else:
		var actual: World3D = (body as CollisionObject3D).get_world_3d()
		result["reason"] = "body_world_mismatch" if actual!=current_world else "cached_body_invalid"
		result["actual_world_space"] = actual.space.get_id() if actual!=null else 0
		result["expected_world_space"] = current_world.space.get_id()
	return result

func residency_profile() -> Dictionary:
	var result := _residency_cost.duplicate(true)
	result["enabled"] = _profile_residency
	result["registered_regions"] = _regions.size()
	result["physics_tick"] = Engine.get_physics_frames()
	return result

func configure(source_frame: RefCounted, source_context: RefCounted, domain_adapter: Callable) -> bool:
	if _configured or not source_frame is Frame or not source_context is Context or not domain_adapter.is_valid(): return false
	var identity: Dictionary = source_context.metadata()
	if not identity.configured or identity.frame_instance_id != source_frame.get_instance_id() or identity.physics_space_id != get_world_3d().space.get_id(): return false
	frame = source_frame
	context = source_context
	_domain = domain_adapter
	# Callable does not retain its RefCounted target. Keep a source-data
	# adapter alive after a bootstrap coroutine/local variable returns.
	var target: Object = domain_adapter.get_object()
	if target is RefCounted: _domain_owner = target
	_configured = true
	add_to_group("source_world_runtime")
	return true

func bind_player(actor: Player) -> bool:
	if not _configured or not is_instance_valid(actor) or actor.get_world_3d() != get_world_3d(): return false
	# The context capsule must match the actual production body, not a weaker
	# fixture shape. Other orientations/scales require a different adapter.
	if not _valid_player_profile(actor): return false
	actor.source_world_runtime = self
	actor.uses_source_world = true
	return true

func bind_aircraft(actor: Helicopter) -> bool:
	if not _configured or not is_instance_valid(actor) or actor.get_world_3d() != get_world_3d(): return false
	actor.source_world_runtime = self
	actor.uses_source_world = true
	return true

func bind_car(actor: Car) -> bool:
	if not _configured or not is_instance_valid(actor) or actor.get_world_3d() != get_world_3d() or _car_envelope(actor) == Vector3.ZERO: return false
	actor.source_world_runtime = self
	actor.uses_source_world = true
	return true

func _car_envelope(actor: Car) -> Vector3:
	if not actor.global_basis.is_equal_approx(Basis(Vector3.UP, actor.global_rotation.y)): return Vector3.ZERO
	var shape_node: CollisionShape3D
	var count := 0
	for child: Node in actor.get_children():
		if child is CollisionShape3D and not child.disabled:
			count += 1
			shape_node = child
	if count != 1 or shape_node == null or not shape_node.shape is BoxShape3D or not shape_node.basis.is_equal_approx(Basis.IDENTITY): return Vector3.ZERO
	var half: Vector3 = (shape_node.shape as BoxShape3D).size * .5
	var offset := shape_node.position
	# Circumscribed horizontal envelope covers the full production hull even
	# while steering/spinning. This checks residency, not collision avoidance.
	var radius := Vector2(absf(offset.x) + half.x, absf(offset.z) + half.z).length() + .5
	return Vector3(radius, absf(offset.y) + half.y + .5, radius)

func _player_shape(actor: Player) -> CollisionShape3D:
	for child: Node in actor.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D and not child.disabled: return child
	return null

func _valid_player_profile(actor: Player) -> bool:
	if not is_instance_valid(actor) or actor.get_world_3d() != get_world_3d(): return false
	if not actor.global_basis.is_equal_approx(Basis(Vector3.UP, actor.global_rotation.y)): return false
	var count := 0
	for child: Node in actor.get_children():
		if child is CollisionShape3D and not child.disabled: count += 1
	var collision := _player_shape(actor)
	if count != 1 or collision == null or not collision.basis.is_equal_approx(Basis.IDENTITY): return false
	var profile: Dictionary = context.metadata().profile
	var capsule := collision.shape as CapsuleShape3D
	var offset: Array = profile.center_offset_xyz
	return is_equal_approx(capsule.radius, profile.radius_m) and is_equal_approx(capsule.height, profile.height_m) and collision.position.is_equal_approx(Vector3(offset[0], offset[1], offset[2]))

func _point(value: Variant) -> bool:
	if not typeof(value) in [TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] or value.size() != 3: return false
	for n in value:
		if not typeof(n) in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(n)): return false
	return true

## Invoke AFTER main-thread geometry/physics commit, at a physics boundary.
## `bodies` must enumerate the neighborhood's complete collision, including
## walls/ceilings/doors. The adapter cannot infer completeness from floor hits.
## `supports` binds stable IDs to their actual owned bodies and registered floor.
func commit_region(id: String, minimum: Array, maximum: Array, bodies: Array, supports: Array) -> bool:
	if not _configured or id.is_empty() or _regions.has(id) or _regions.size() >= 256 or not _point(minimum) or not _point(maximum) or bodies.is_empty(): return false
	for axis in 3:
		if float(minimum[axis]) >= float(maximum[axis]): return false
	var references: Array[WeakRef] = []
	var body_ids := PackedStringArray()
	for body in bodies:
		if not body is CollisionObject3D or not is_instance_valid(body) or not body.is_inside_tree() or body.get_world_3d() != get_world_3d() or body.collision_layer == 0: return false
		references.append(weakref(body))
		body_ids.append(str(body.get_instance_id()))
	var inventory_hash := HashingContext.new()
	inventory_hash.start(HashingContext.HASH_SHA256)
	inventory_hash.update(",".join(body_ids).to_utf8_buffer())
	var inventory_key: String = inventory_hash.finish().hex_encode()
	var stamps: Array[Dictionary] = []
	var token := id + "/generation-" + str(_generation + 1)
	for support in supports:
		if not support is Dictionary or not support.get("body") in bodies: return false
		var body: CollisionObject3D = support.body
		if _supports.has(body.get_instance_id()): return false
		var stamped: Dictionary = context.make_collider_stamp(support.get("feature_id"), support.get("floor_id"), support.get("support_id"), token)
		if not stamped.ok: return false
		stamps.append({"body": body, "stamp": stamped.stamp})
	_generation += 1
	_regions[id] = {"minimum": minimum.duplicate(), "maximum": maximum.duplicate(), "bodies": references, "body_inventory_key": inventory_key,
		"origin_revision": frame.metadata().origin_revision, "token": token}
	if _diagnose_motion: _regions[id]["diagnostic_inventory_ids"] = body_ids.duplicate()
	for entry: Dictionary in stamps:
		var body: CollisionObject3D = entry.body
		body.set_meta(Context.COLLIDER_META, entry.stamp)
		_supports[body.get_instance_id()] = {"region": id, "body": weakref(body), "stamp": entry.stamp.duplicate(true)}
	return true

func retire_region(id: String) -> void:
	_regions.erase(id)
	var ids: Array = _regions.keys()
	ids.sort()
	for key in _supports.keys():
		if _supports[key].region != id: continue
		var known: Dictionary = _supports[key]
		var body: Variant = known.body.get_ref()
		var replacement := ""
		if is_instance_valid(body):
			for candidate in ids:
				var region: Dictionary = _regions[candidate]
				if region.origin_revision != frame.metadata().origin_revision: continue
				for reference: WeakRef in region.bodies:
					if reference.get_ref() == body:
						replacement = candidate
						break
				if not replacement.is_empty(): break
		if not replacement.is_empty():
			# Geometry remains physically committed and referenced by a live
			# adjacent region. Transfer its lease; never erase a shared floor.
			var old: Dictionary = known.stamp
			var renewed: Dictionary = context.make_collider_stamp(old.feature_id, old.floor_id, old.support_id, _regions[replacement].token)
			if renewed.ok:
				body.set_meta(Context.COLLIDER_META, renewed.stamp)
				_supports[key] = {"region": replacement, "body": weakref(body), "stamp": renewed.stamp.duplicate(true)}
				continue
		if is_instance_valid(body): body.remove_meta(Context.COLLIDER_META)
		_supports.erase(key)

func region_status(id: String) -> Dictionary:
	var missing := {"live": false, "region_id": id, "residency_token": "", "origin_revision": -1}
	if not _configured or not _regions.has(id): return missing
	var region: Dictionary = _regions[id]
	if region.origin_revision != frame.metadata().origin_revision: return missing
	for reference: WeakRef in region.bodies:
		var body: Variant = reference.get_ref()
		if not is_instance_valid(body) or not body.is_inside_tree() or body.collision_layer == 0 or body.get_world_3d() != get_world_3d(): return missing
		if body is PhysicsBody3D and (PhysicsServer3D.body_get_space(body.get_rid()) != get_world_3d().space or PhysicsServer3D.body_get_shape_count(body.get_rid()) == 0): return missing
	for support: Dictionary in _supports.values():
		if support.region != id: continue
		var body: Variant = support.body.get_ref()
		if not is_instance_valid(body) or not body.has_meta(Context.COLLIDER_META) or not context._same_stamp(body.get_meta(Context.COLLIDER_META), support.stamp): return missing
	return {"live": true, "region_id": id, "residency_token": region.token, "origin_revision": region.origin_revision,
		"minimum_source_xyz": region.minimum.duplicate(), "maximum_source_xyz": region.maximum.duplicate()}

func _subtract_box(box: Dictionary, cut: Dictionary) -> Array[Dictionary]:
	var low: Array = []
	var high: Array = []
	for axis in 3:
		low.append(maxf(box.low[axis], cut.minimum[axis]))
		high.append(minf(box.high[axis], cut.maximum[axis]))
		if low[axis] >= high[axis]: return [box]
	var remainder: Array[Dictionary] = []
	var core: Dictionary = box.duplicate(true)
	for axis in 3:
		if core.low[axis] < low[axis]:
			var left: Dictionary = core.duplicate(true)
			left.high[axis] = low[axis]
			remainder.append(left)
			core.low[axis] = low[axis]
		if core.high[axis] > high[axis]:
			var right: Dictionary = core.duplicate(true)
			right.low[axis] = high[axis]
			remainder.append(right)
			core.high[axis] = high[axis]
	return remainder

func _resident(point: Array, half_extents: Vector3) -> Dictionary:
	if not _profile_residency: return _resident_impl(point, half_extents)
	var started := Time.get_ticks_usec()
	var result := _resident_impl(point, half_extents)
	var elapsed := Time.get_ticks_usec() - started
	_residency_cost.calls += 1; _residency_cost.total_us += elapsed
	_residency_cost.max_us = maxi(_residency_cost.max_us, elapsed)
	return result

func _resident_impl(point: Array, half_extents: Vector3) -> Dictionary:
	var low: Array = []
	var high: Array = []
	for axis in 3:
		low.append(float(point[axis]) - float(half_extents[axis]))
		high.append(float(point[axis]) + float(half_extents[axis]))
	var uncovered: Array[Dictionary] = [{"low": low, "high": high}]
	var tokens: Dictionary = {}
	var ids: Array = _regions.keys()
	ids.sort()
	# Regions often share native walls/floors. Validate each unique body once
	# within THIS synchronous query; never cache readiness across a frame or
	# a mutation. Every live region token remains included, even where its
	# stamped support body is also listed in the neighboring region.
	var checked_bodies: Dictionary = {}
	var checked_inventories: Dictionary = {}
	var inventory_failures: Variant = null
	var body_failures: Variant = null
	var current_origin: int = frame.metadata().origin_revision
	var current_world := get_world_3d()
	var trace: Variant = null
	if _diagnose_motion:
		inventory_failures = {}; body_failures = {}
		_residency_diagnostic_serial += 1
		trace = {"query_serial":_residency_diagnostic_serial,"physics_tick":Engine.get_physics_frames(),"origin_revision":current_origin,"center_source_xyz":point.duplicate(),"half_extents_xyz":_diagnostic_vector(half_extents),"minimum_source_xyz":low.duplicate(),"maximum_source_xyz":high.duplicate(),"registered_regions":ids.size(),"invalid_regions":[],"live_regions":[]}
	for id in ids:
		var region: Dictionary = _regions[id]
		if region.origin_revision != current_origin:
			if _diagnose_motion and trace.invalid_regions.size()<16: trace.invalid_regions.append({"region_id":id,"reason":"stale_origin","region_origin_revision":region.origin_revision,"current_origin_revision":current_origin})
			continue
		var valid := true
		var key: String = region.body_inventory_key
		# Initial map cells can intentionally share one complete collision
		# neighborhood. Identical ordered native IDs need only one scan INSIDE
		# this synchronous query. Nothing survives into the next query/tick.
		if checked_inventories.has(key):
			valid = checked_inventories[key]
			if _profile_residency: _residency_cost.inventory_group_reuses += 1
		else:
			if _profile_residency: _residency_cost.inventory_groups_validated += 1
			for reference: WeakRef in region.bodies:
				if _profile_residency: _residency_cost.inventory_reference_visits += 1
				var body: Variant = reference.get_ref()
				if not is_instance_valid(body):
					valid = false
					if _diagnose_motion:
						var reference_index: int = region.bodies.find(reference)
						var expected_ids: PackedStringArray = region.get("diagnostic_inventory_ids",PackedStringArray())
						inventory_failures[key] = {"reason":"freed_body_reference","reference_index":reference_index,"original_body_id":expected_ids[reference_index] if reference_index<expected_ids.size() else "not_recorded"}
					break
				var body_id: int = body.get_instance_id()
				if not checked_bodies.has(body_id):
					if _profile_residency: _residency_cost.body_liveness_checks += 1
					checked_bodies[body_id] = body.is_inside_tree() and body.collision_layer != 0 and body.get_world_3d() == current_world
					if _diagnose_motion and not checked_bodies[body_id]: body_failures[body_id] = _diagnostic_body_failure(body,current_world)
				if not checked_bodies[body_id]:
					valid = false
					if _diagnose_motion: inventory_failures[key] = body_failures.get(body_id,{"reason":"cached_invalid_body","body_id":body_id}).duplicate(true)
					break
			checked_inventories[key] = valid
		if not valid:
			if _diagnose_motion and trace.invalid_regions.size()<16: trace.invalid_regions.append({"region_id":id,"inventory_key":key,"inventory_size":region.bodies.size(),"minimum_source_xyz":region.minimum.duplicate(),"maximum_source_xyz":region.maximum.duplicate(),"failure":inventory_failures.get(key,{"reason":"cached_invalid_inventory"}).duplicate(true)})
			continue
		if _diagnose_motion and trace.live_regions.size()<16: trace.live_regions.append({"region_id":id,"token":region.token,"inventory_key":key,"minimum_source_xyz":region.minimum.duplicate(),"maximum_source_xyz":region.maximum.duplicate()})
		tokens[region.token] = true
		var remaining: Array[Dictionary] = []
		for box: Dictionary in uncovered:
			remaining.append_array(_subtract_box(box, region))
			if remaining.size() > 4096:
				if _diagnose_motion:
					trace.merge({"ok":false,"reason":"box_union_fragment_work_limit","uncovered_fragment_count":remaining.size(),"first_uncovered_fragments":remaining.slice(0,16)},true)
					_last_residency_diagnostic = trace
				return {} # Same bounded work; request a coalesced neighborhood.
		uncovered = remaining
	# Include all live tokens: an overlapping neighbor's support must not be
	# rejected merely because an earlier box also covered the query.
	if _diagnose_motion:
		trace.merge({"ok":uncovered.is_empty(),"reason":"resident" if uncovered.is_empty() else "uncovered_source_envelope","live_token_count":tokens.size(),"uncovered_fragment_count":uncovered.size(),"first_uncovered_fragments":uncovered.slice(0,16)},true)
		_last_residency_diagnostic = trace
	return {"tokens": tokens, "token": "union/" + str(_generation)} if uncovered.is_empty() else {}

func _bound(query: Dictionary, kind: String, state: String, payload: Dictionary = {}) -> Dictionary:
	var result: Dictionary = context.bind_observation(query, kind, state, payload)
	return result.observation if result.ok else {}

func _domain_observations(query: Dictionary) -> Dictionary:
	var observations: Dictionary = {}
	if not _domain.is_valid(): return observations
	var supplied: Variant = _domain.call(query.source_xyz.duplicate())
	if not supplied is Dictionary: return observations
	for kind in ["territory", "land", "water"]:
		var value: Variant = supplied.get(kind)
		if value is Dictionary and value.get("state") is String and value.get("payload", {}) is Dictionary:
			observations[kind] = _bound(query, kind, value.state, value.get("payload", {}))
	return observations

func _native_player_observations(query: Dictionary, actor: Player) -> Dictionary:
	var result := _domain_observations(query)
	var region := _resident(query.source_xyz, Vector3(0.8, 2.2, 0.8))
	if region.is_empty():
		result["physics"] = _bound(query, "physics", "unloaded")
		return result
	var position: Vector3 = query.local_sample.position
	var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 0.1, position + Vector3.DOWN * 0.35, 1)
	ray.exclude = [actor.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var support := {"state": "unsupported"}
	if not hit.is_empty() and _supports.has(hit.collider_id):
		var known: Dictionary = _supports[hit.collider_id]
		if known.region in _regions and region.tokens.has(_regions[known.region].token):
			var stamp: Dictionary = known.stamp
			var canonical: Dictionary = frame.to_source_current_live(hit.position)
			if canonical.ok:
				var normal: Vector3 = hit.normal
				support = {"state": "supported", "feature_id": stamp.feature_id, "floor_id": stamp.floor_id,
					"support_id": stamp.support_id, "collider_instance_id": hit.collider_id,
					"contact_source_xyz": canonical.source_xyz, "normal_source_xyz": [normal.x, normal.y, normal.z]}
	var shape := _player_shape(actor)
	var clear := "unknown"
	if shape != null:
		var probe := PhysicsShapeQueryParameters3D.new()
		probe.shape = shape.shape
		probe.transform = Transform3D(actor.global_basis, position) * shape.transform
		probe.collision_mask = Player.COLLIDE_MASK
		probe.exclude = [actor.get_rid()]
		clear = _player_clearance(probe, actor, support, hit)
	result["physics"] = _bound(query, "physics", "resident", {"residency_token": _supports[hit.collider_id].stamp.residency_token if support.state == "supported" else region.token, "clearance": clear, "support": support})
	return result

func _player_clearance(probe: PhysicsShapeQueryParameters3D, actor: Player, support: Dictionary, floor_hit: Dictionary) -> String:
	var space := get_world_3d().direct_space_state
	var intersections := space.intersect_shape(probe, 33)
	native_clearance_diagnostics = {"physics_tick": Engine.get_physics_frames(), "query_center_xyz": [probe.transform.origin.x, probe.transform.origin.y, probe.transform.origin.z], "overlap_shapes": intersections.size(), "contacts": []}
	if intersections.is_empty(): return "clear"
	if support.state != "supported" or floor_hit.is_empty() or intersections.size() >= 33: return "blocked"
	# CharacterBody resting contacts can retain a millimetre of solver slop.
	# Do not shift the saved pose, shrink the capsule, or exclude the support
	# body: it may also contain a ceiling or wall. Inspect ALL native contact
	# pairs instead, requiring shallow upward contacts at the capsule's foot.
	for intersection: Dictionary in intersections:
		if intersection.collider_id != floor_hit.collider_id: return "blocked"
	var contacts := space.collide_shape(probe, 33)
	if contacts.is_empty() or contacts.size() % 2 != 0 or contacts.size() >= 66: return "blocked"
	var capsule := probe.shape as CapsuleShape3D
	if capsule == null: return "blocked"
	var coordinate_magnitude := maxf(absf(probe.transform.origin.x), maxf(absf(probe.transform.origin.y), absf(probe.transform.origin.z)))
	var float_roundoff := maxf(0.00001, coordinate_magnitude * 2.0 * 0.00000011920928955078125)
	var tolerance := actor.safe_margin * 2.0 + float_roundoff
	native_clearance_diagnostics["solver_safe_margin_m"] = actor.safe_margin
	native_clearance_diagnostics["local_float_roundoff_m"] = float_roundoff
	native_clearance_diagnostics["maximum_floor_contact_depth_m"] = tolerance
	var bottom := probe.transform.origin.y - capsule.height * 0.5
	var minimum_normal: float = context.metadata().profile.min_support_normal_y
	for index in range(0, contacts.size(), 2):
		var separation: Vector3 = contacts[index + 1] - contacts[index]
		var depth := separation.length()
		var measured_normal := separation / depth if depth > 0.0000001 else Vector3.ZERO
		native_clearance_diagnostics.contacts.append({"depth_m": depth, "query_xyz": [contacts[index].x, contacts[index].y, contacts[index].z], "other_xyz": [contacts[index + 1].x, contacts[index + 1].y, contacts[index + 1].z], "normal_xyz": [measured_normal.x, measured_normal.y, measured_normal.z]})
		if depth > tolerance: return "blocked"
		if depth <= 0.0000001: continue
		var normal := separation / depth
		if normal.y < minimum_normal: return "blocked"
		var foot_band := capsule.radius * (1.0 - normal.y) + tolerance
		if contacts[index + 1].y > bottom + foot_band: return "blocked"
	return "clear"

func inspect_player(actor: Player) -> Dictionary:
	if not _configured or actor.source_world_runtime != self or not _valid_player_profile(actor): return {"ok": false}
	var canonical: Dictionary = frame.to_source_current_live(actor.global_position)
	if not canonical.ok: return canonical
	var begun: Dictionary = context.begin_query(canonical.source_xyz)
	if not begun.ok: return begun
	return context.evaluate(begun.query, _native_player_observations(begun.query, actor))

## Hold safely on missing data; no Y-death-plane, invented ground or teleport.
## Check both current and prospective neighborhoods to prevent flying/walking
## into an unloaded chunk. Flight does not demand a floor under the aircraft.
func motion_allowed(actor: CharacterBody3D, delta: float, aircraft: bool = false, extra_motion: Vector3 = Vector3.ZERO) -> bool:
	if not _configured: return _motion_refused(actor,"runtime_unconfigured",delta)
	if actor.get_world_3d() != get_world_3d(): return _motion_refused(actor,"actor_world_mismatch",delta)
	if delta <= 0.0: return _motion_refused(actor,"nonpositive_delta",delta)
	var car_half := Vector3.ZERO
	if actor is Car:
		if actor.source_world_runtime != self: return _motion_refused(actor,"car_runtime_binding",delta)
		car_half = _car_envelope(actor)
		if car_half == Vector3.ZERO: return _motion_refused(actor,"car_hull_profile",delta)
	elif not aircraft and (not actor is Player or not _valid_player_profile(actor)): return _motion_refused(actor,"player_profile_or_actor_type",delta)
	if not extra_motion.is_finite(): return _motion_refused(actor,"nonfinite_extra_motion",delta)
	var start: Dictionary = frame.to_source_current_live(actor.global_position)
	var target := actor.global_position + actor.velocity * delta + extra_motion
	var end: Dictionary = frame.to_source_current_live(target)
	if not start.ok or not end.ok: return _motion_refused(actor,"source_frame_projection",delta,{"start":start,"end":end})
	var half := Vector3(8, 5, 8) if aircraft else Vector3(0.8, 2.2, 0.8)
	if actor is Car: half = car_half
	var middle: Array = []
	var swept := half
	for axis in 3:
		middle.append((float(start.source_xyz[axis]) + float(end.source_xyz[axis])) * 0.5)
		swept[axis] += absf(float(end.source_xyz[axis]) - float(start.source_xyz[axis])) * 0.5
	if _resident(middle, swept).is_empty(): return _motion_refused(actor,"swept_residency",delta,{"start_source_xyz":start.source_xyz,"end_source_xyz":end.source_xyz,"residency":_last_residency_diagnostic if _diagnose_motion else {}})
	for local in [actor.global_position, target]:
		var canonical: Dictionary = frame.to_source_current_live(local)
		if not canonical.ok: return _motion_refused(actor,"endpoint_source_projection",delta,{"projection":canonical})
		if _resident(canonical.source_xyz, half).is_empty(): return _motion_refused(actor,"endpoint_residency",delta,{"point_source_xyz":canonical.source_xyz,"residency":_last_residency_diagnostic if _diagnose_motion else {}})
		var begun: Dictionary = context.begin_query(canonical.source_xyz)
		if not begun.ok: return _motion_refused(actor,"endpoint_query_invalid",delta,{"query":begun})
		var state: Dictionary = context.evaluate(begun.query, _domain_observations(begun.query))
		if not state.ok or state.territory.state != "inside": return _motion_refused(actor,"endpoint_territory_or_domain",delta,{"point_source_xyz":canonical.source_xyz,"state":state})
	if _diagnose_motion: _record_motion(actor,true,"allowed",delta,{"start_source_xyz":start.source_xyz,"end_source_xyz":end.source_xyz,"extra_motion":_diagnostic_vector(extra_motion)})
	return true

func player_is_submerged(actor: Player) -> bool:
	var state := inspect_player(actor)
	return state.get("ok", false) and state.water.state == "submerged" and state.residency.state == "resident"

func aircraft_agl(actor: Helicopter) -> float:
	# Only actual support geometry can cushion descent in a source world.
	var origin := actor.global_position + Vector3.UP * 0.8
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 40, 1)
	ray.exclude = [actor.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return maxf(actor.global_position.y - hit.position.y, 0.0) if not hit.is_empty() else 40.0

func landing_exit_safe(local_position: Vector3) -> bool:
	var actor := get_tree().get_first_node_in_group("player") as Player
	if actor == null or actor.source_world_runtime != self or not _valid_player_profile(actor): return false
	var canonical: Dictionary = frame.to_source_current_live(local_position)
	if not canonical.ok: return false
	var begun: Dictionary = context.begin_query(canonical.source_xyz)
	if not begun.ok: return false
	var observations := _native_player_observations(begun.query, actor)
	var state: Dictionary = context.evaluate(begun.query, observations)
	# A local, physically observed step out of a vehicle is separate from cold
	# save restoration. Outdoor hydrology may be unresolved; do not relabel it
	# dry, but allow an actual supported clear surface. Known immersion refuses.
	return state.get("ok", false) and state.territory.state == "inside" and state.residency.state == "resident" and state.support.state == "supported" and state.clearance.state == "clear" and state.water.state != "submerged"

func capture_player_pose(actor: Player) -> Dictionary:
	var state := inspect_player(actor)
	if not state.get("ok", false) or state.support.state != "supported" or state.residency.state != "resident": return {"ok": false, "error": "Source save requires current resident native support"}
	return context.make_restore_pose(state.source_xyz, actor.yaw, state.support.feature_id, state.support.floor_id)

## Data-only policy classification. This is not a restore authorization: the
## mutating method below always obtains its own fresh Context/native proof.
func supports_unknown_water_restore(checked: Dictionary) -> bool:
	if not checked.get("ok", false) or checked.get("status") != "pending" or checked.get("reasons", []) != ["three_dimensional_water_unresolved"]: return false
	var state: Dictionary = checked.get("state", {})
	return state.get("ok", false) and state.territory.state == "inside" and state.residency.state == "resident" and state.support.state == "supported" and state.clearance.state == "clear" and state.water.state == "unknown"

## Synchronous current-tick application. A cold/missing floor remains pending;
## this operation never overwrites owner saves or interprets old local poses.
func restore_player_pose(actor: Player, saved: Dictionary, allow_supported_unknown_water: bool = false) -> Dictionary:
	if actor.source_world_runtime != self or not _valid_player_profile(actor): return {"ok": false, "status": "invalid", "error": "Player/profile/world binding mismatch"}
	var prepared: Dictionary = context.prepare_restore(saved)
	if not prepared.ok or prepared.get("status") != "query_required": return prepared
	var point: Array = saved.source_pose.source_xyz
	var begun: Dictionary = context.begin_query(point)
	if not begun.ok: return begun
	var checked: Dictionary = context.preflight_restore(saved, begun.query, _native_player_observations(begun.query, actor))
	var native_surface_policy := false
	# Explicit gameplay policy, separate from source hydrology knowledge. The
	# strict Context remains unchanged. A real supported/clear/resident saved
	# pose may resume while ONLY water classification is unresolved; missing
	# collision, wrong-floor support, ceilings and known immersion still fail.
	if allow_supported_unknown_water:
		native_surface_policy = supports_unknown_water_restore(checked)
	if not native_surface_policy and (not checked.ok or checked.get("status") != "ready"): return checked
	# No yield between native query, revision/tick validation and application.
	if not context.validate_query(begun.query).ok: return {"ok": false, "status": "invalid"}
	actor.respawn_at(begun.query.local_sample.position, float(saved.source_pose.heading_rad))
	return {"ok": true, "status": "applied", "physics_tick": Engine.get_physics_frames(), "restore_policy": "supported_native_surface" if native_surface_policy else "strict", "water_state": "unknown" if native_surface_policy else checked.get("state", {}).get("water", {}).get("state", "unknown"), "hydrology_reclassified": false}
