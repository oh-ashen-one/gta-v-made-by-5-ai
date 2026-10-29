extends Node3D
## One reconstructed physical lift shaft. Parent owns source placement, floor
## streaming/residency and save integration. NEVER assigns/reparents an actor.
signal floor_requested(shaft_id: String, floor_id: String)
signal state_changed(shaft_id: String, state: String, detail: String)
signal arrived(shaft_id: String, floor_id: String)
const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const SCHEMA := "mbs_physical_cabin_v1"
const DESC_KEYS := ["schema", "shaft_id", "center_xz", "entry_sign", "initial_floor_id", "stops", "speed_mps", "acceleration_mps2"]
const STOP_KEYS := ["floor_id", "elevation_m", "label", "portal_id", "kind", "height_status"]
const OPTIONAL_STOP_KEYS := ["receiving_door_height_m", "receiving_clear_height_m"]
const WIDTH := 2.20
const DEPTH := 2.80
const HEIGHT := 2.70
const DOOR_W := 1.30
const DOOR_H := 2.35
const ALIGN_M := .012

class CabinPanel extends Node3D:
	var coordinator: Node
	var prompt_text := "[E] Lift destinations"
	func _ready() -> void: add_to_group("interactables")
	func can_interact() -> bool:
		return is_visible_in_tree() and is_instance_valid(coordinator) and coordinator.get("_built")
	func interact(actor: Node) -> void:
		if can_interact(): coordinator.panel_interact(actor)

var _has_low_receivers := false
var _cabin_gate_setback := .10
var _built := false
var _descriptor: Dictionary = {}
var _stops: Dictionary = {}
var _ordered: Array[String] = []
var _bindings: Dictionary = {}
var _external_ready: Dictionary = {}
var _ready_callback: Callable
var _center := Vector2.ZERO
var _sign := 1.0
var cabin: AnimatableBody3D
var panel: CabinPanel
var _cabin_gates: Array[AnimatableBody3D] = []
var _shaft_gates: Dictionary = {}
var _owned_rids: Array[RID] = []
var _gate_fraction := 0.0
var _landing_fraction: Dictionary = {}
var _motion_y := 0.0
var _velocity_y := 0.0
var _at_floor := ""
var _target := ""
var _queue: Array[String] = []
var _state := "UNBUILT"
var _detail := ""
var _last_requested := ""
var _dwell_elapsed := 0.0
var _built_tick := -1
var _last_blockage: Dictionary = {}
var _last_door_probe: Dictionary = {}
var _ui: CanvasLayer
var _ui_label: Label
var _selection := 0
var _mouse_before := Input.MOUSE_MODE_CAPTURED
var _ui_open := false
var _floor_buttons: Dictionary = {}

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

static func _text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 256

static func _exact(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

## Current inventory provides explicit relative reconstructed elevations and
## fixed core axes, including basements/terminal programs. Not an as-built lift.
static func inventory_descriptor(tower: String, wing: String, kind: String, initial_floor_id: String = "") -> Dictionary:
	if not tower in ["T1", "T2", "T3"] or not wing in ["east", "west"] or not kind in ["guest_lift", "service_lift"]: return {"valid": false, "error": "Unknown inventory shaft axis"}
	var stops: Array[Dictionary] = []
	var center: Array[float] = []
	var side := -1.0 if wing == "east" else 1.0
	for id: String in Inventory.floor_ids():
		if not id.begins_with(tower + "-"): continue
		var record: Dictionary = Inventory.floor_record(id)
		if not _number(record.get("elevation_m")): return {"valid": false, "error": "Inventory floor lacks finite relative elevation"}
		for core: Dictionary in record.get("cores", []):
			if core.kind != kind or core.wing != wing: continue
			var expected: Array[float] = [float(core.local_x_m), float(core.threshold_z_m) + side * DEPTH * .5]
			if not center.is_empty() and (absf(center[0] - expected[0]) > .001 or absf(center[1] - expected[1]) > .001): return {"valid": false, "error": "Inventory cores do not share one fixed vertical axis"}
			center = expected
			stops.append({"floor_id": id, "elevation_m": float(record.elevation_m), "label": tower + " " + String(record.level), "portal_id": String(core.id), "kind": kind, "height_status": "INVENTORY_RECONSTRUCTED_RELATIVE_ELEVATION_NOT_SURVEYED"})
	stops.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.elevation_m) < float(b.elevation_m))
	if stops.is_empty(): return {"valid": false, "error": "No inventory stops for shaft"}
	return {"valid": true, "descriptor": {"schema": SCHEMA, "shaft_id": tower + "-" + wing + "-" + kind, "center_xz": center, "entry_sign": -side,
		"initial_floor_id": String(stops[0].floor_id) if initial_floor_id.is_empty() else initial_floor_id, "stops": stops, "speed_mps": 2.0, "acceleration_mps2": 1.25}, "private_asbuilt_verified": false}

static func validate_descriptor(value: Variant) -> Dictionary:
	if not _exact(value, DESC_KEYS) or typeof(value.schema) != TYPE_STRING or value.schema != SCHEMA or not _text(value.shaft_id) or not _text(value.initial_floor_id): return {"valid": false, "error": "Invalid cabin descriptor schema/identity"}
	if not typeof(value.center_xz) in [TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] or value.center_xz.size() != 2: return {"valid": false, "error": "Cabin center requires two LOCAL metre doubles"}
	for component in value.center_xz:
		if not _number(component) or absf(float(component)) > 2048.0: return {"valid": false, "error": "Cabin center must already be relative to the active source origin"}
	if not _number(value.entry_sign) or not float(value.entry_sign) in [-1.0, 1.0] or not _number(value.speed_mps) or not _number(value.acceleration_mps2): return {"valid": false, "error": "Invalid cabin motion policy"}
	if float(value.speed_mps) < .2 or float(value.speed_mps) > 5.0 or float(value.acceleration_mps2) < .2 or float(value.acceleration_mps2) > 3.0: return {"valid": false, "error": "Unbounded cabin speed/acceleration"}
	if typeof(value.stops) != TYPE_ARRAY or value.stops.size() < 2 or value.stops.size() > 128: return {"valid": false, "error": "Require a bounded multi-stop shaft"}
	var ids: Array[String] = []
	var stops: Array[Dictionary] = []
	for stop in value.stops:
		if not stop is Dictionary: return {"valid":false,"error":"Invalid cabin stop type"}
		for key:String in STOP_KEYS:
			if not stop.has(key):return {"valid":false,"error":"Missing required cabin stop field"}
		for key:Variant in stop:
			if not key in STOP_KEYS and not key in OPTIONAL_STOP_KEYS:return {"valid":false,"error":"Unknown cabin stop field"}
		for key in ["floor_id", "label", "portal_id", "kind", "height_status"]:
			if not _text(stop[key]): return {"valid": false, "error": "Missing explicit stop identity/status"}
		if not stop.kind in ["guest_lift", "service_lift"] or ids.has(stop.floor_id) or not _number(stop.elevation_m) or absf(float(stop.elevation_m)) > 2048.0: return {"valid": false, "error": "Invalid/duplicate stop or relative height"}
		var opening:float=DOOR_H
		var clear:float=0.0 # Explicit legacy normal descriptor, no claimed metric ceiling.
		if stop.has("receiving_door_height_m"):
			if not _number(stop.receiving_door_height_m):return {"valid":false,"error":"Invalid receiving door height"}
			opening=float(stop.receiving_door_height_m)
		if stop.has("receiving_clear_height_m"):
			if not _number(stop.receiving_clear_height_m):return {"valid":false,"error":"Invalid receiving clear height"}
			clear=float(stop.receiving_clear_height_m)
		var low:bool=absf(opening-2.10)<.001
		if not low and absf(opening-DOOR_H)>.001:return {"valid":false,"error":"Unsupported receiving door height"}
		if low and (not stop.has("receiving_clear_height_m") or clear<2.30-.001):return {"valid":false,"error":"Low stop needs explicit adequate receiving headroom"}
		if clear!=0.0 and (clear<opening+(.10 if low else .20)+.04 or clear>5.25):return {"valid":false,"error":"Receiving opening/header cannot fit floor"}
		var normalized_stop:Dictionary=stop.duplicate(true)
		normalized_stop["receiving_door_height_m"]=opening;normalized_stop["receiving_clear_height_m"]=clear
		ids.append(stop.floor_id)
		stops.append(normalized_stop)
	if not ids.has(value.initial_floor_id): return {"valid": false, "error": "Initial floor is not a stop"}
	stops.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.elevation_m) < float(b.elevation_m))
	for index in range(1, stops.size()):
		if float(stops[index].elevation_m) - float(stops[index - 1].elevation_m) < .15: return {"valid": false, "error": "Coincident floor stops require an explicit parent alias plan"}
	var normalized: Dictionary = value.duplicate(true)
	normalized.stops = stops
	return {"valid": true, "descriptor": normalized}

func build(value: Variant, ready_for_floor: Callable) -> Dictionary:
	if _built or get_child_count() != 0 or not is_inside_tree(): return {"built": false, "error": "Build a new owned cabin node inside its final parent"}
	var validated: Dictionary = validate_descriptor(value)
	if not validated.valid or not ready_for_floor.is_valid(): return {"built": false, "error": validated.get("error", "Missing explicit readiness callback")}
	if not _upright_unit(): return {"built": false, "error": "Parent must supply upright unit source placement"}
	_descriptor = validated.descriptor
	_ready_callback = ready_for_floor
	_center = Vector2(float(_descriptor.center_xz[0]), float(_descriptor.center_xz[1]))
	_sign = float(_descriptor.entry_sign)
	for stop: Dictionary in _descriptor.stops:
		_stops[stop.floor_id] = stop.duplicate(true)
		_ordered.append(stop.floor_id)
		_landing_fraction[stop.floor_id] = 0.0
	for stop:Dictionary in _descriptor.stops:
		if float(stop.receiving_door_height_m)<DOOR_H-.001:_has_low_receivers=true
	_cabin_gate_setback=.24 if _has_low_receivers else .10
	_at_floor = _descriptor.initial_floor_id
	_motion_y = float(_stops[_at_floor].elevation_m)
	_make_cabin()
	_make_shaft()
	_make_ui()
	_built = true
	_built_tick = Engine.get_physics_frames()
	process_physics_priority = -30
	_change("IDLE", "Closed cabin; call a resident landing")
	_publish_transforms()
	return report()

func _upright_unit() -> bool:
	return global_basis.get_scale().is_equal_approx(Vector3.ONE) and global_basis.y.distance_to(Vector3.UP) < .00001 and absf(global_basis.determinant() - 1.0) < .00001

func _box(body: CollisionObject3D, kit: Variant, mat: Material, center: Vector3, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	kit.box(mat, center, size, Basis.IDENTITY, false)

func _moving_body(label: String, initial_position: Vector3) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = label
	body.transform = Transform3D(Basis.IDENTITY, initial_position)
	body.collision_layer = 1
	body.collision_mask = 1
	body.sync_to_physics = true
	add_child(body)
	_owned_rids.append(body.get_rid())
	return body

func _make_cabin() -> void:
	cabin = _moving_body("PhysicalCabin", Vector3(_center.x, _motion_y, _center.y))
	var kit = Kit.new()
	_box(cabin, kit, Looks.get_mat("granite_light"), Vector3(0, -.08, 0), Vector3(WIDTH - .12, .16, DEPTH - .24))
	_box(cabin, kit, Looks.get_mat("steel_bronze"), Vector3(0, HEIGHT + .06, 0), Vector3(WIDTH, .12, DEPTH - .24))
	for side in [-1.0, 1.0]: _box(cabin, kit, Looks.get_mat("timber"), Vector3(side * (WIDTH * .5 - .06), HEIGHT * .5, 0), Vector3(.12, HEIGHT, DEPTH - .24))
	_box(cabin, kit, Looks.get_mat("timber"), Vector3(0, HEIGHT * .5, -_sign * (DEPTH * .5 - .06)), Vector3(WIDTH, HEIGHT, .12))
	kit.commit(cabin, "CabinMaterials", true)
	for side in [-1.0, 1.0]: _cabin_gates.append(_make_gate("CabinGate" + str(side), _motion_y, side, false))
	panel = CabinPanel.new()
	panel.name = "NativeELiftPanel"
	panel.coordinator = self
	add_child(panel)
	var face = Kit.new()
	face.box(Looks.get_mat("steel_bronze"), Vector3.ZERO, Vector3(.22, .34, .05), Basis.IDENTITY, false)
	face.commit(panel, "PanelFace", true)

func _make_gate(label: String, y: float, side: float, landing: bool, opening_height:float=DOOR_H) -> AnimatableBody3D:
	var gate: AnimatableBody3D = _moving_body(label, _gate_center(y, side, 0.0, landing))
	gate.collision_mask = 0
	var kit = Kit.new()
	# Mixed-height shafts keep a real20mm receiving-grille top gap beneath
	# each explicit opening. Legacy all-normal geometry remains unchanged;
	# visible mesh and native shape always share the same leaf dimensions.
	var leaf_height:float=opening_height-.02 if _has_low_receivers and landing else opening_height
	_box(gate, kit, Looks.get_mat("steel_bronze"), Vector3(0, leaf_height * .5, 0), Vector3(DOOR_W * .5, leaf_height, .07))
	kit.commit(gate, "GateLeaf", true)
	return gate

func _make_shaft() -> void:
	var static_body := StaticBody3D.new()
	static_body.name = "ClosedShaftEnclosure"
	static_body.collision_layer = 1
	add_child(static_body)
	_owned_rids.append(static_body.get_rid())
	var kit = Kit.new()
	var bottom: float = float(_stops[_ordered[0]].elevation_m) - .30
	var top: float = float(_stops[_ordered[-1]].elevation_m) + HEIGHT + .30
	for side in [-1.0, 1.0]: _box(static_body, kit, Looks.get_mat("granite_light"), Vector3(_center.x + side * (WIDTH * .5 + .14), (bottom + top) * .5, _center.y), Vector3(.16, top - bottom, DEPTH + .45))
	_box(static_body, kit, Looks.get_mat("granite_light"), Vector3(_center.x, (bottom + top) * .5, _center.y - _sign * (DEPTH * .5 + .16)), Vector3(WIDTH + .4, top - bottom, .16))
	var previous := bottom
	for id: String in _ordered:
		var y: float = float(_stops[id].elevation_m)
		var receiving_height:float=_stops[id].receiving_door_height_m
		if y > previous: _box(static_body, kit, Looks.get_mat("granite_light"), Vector3(_center.x, (previous + y) * .5, _center.y + _sign * (DEPTH * .5 + .07)), Vector3(WIDTH + .4, y - previous, .10))
		for side in [-1.0, 1.0]: _box(static_body, kit, Looks.get_mat("granite_light"), Vector3(_center.x + side * ((WIDTH + .4 + DOOR_W) * .25), y + receiving_height * .5, _center.y + _sign * (DEPTH * .5 + .07)), Vector3((WIDTH + .4 - DOOR_W) * .5, receiving_height, .10))
		previous = maxf(previous, y + receiving_height)
		_shaft_gates[id] = [_make_gate(id.validate_node_name() + "LandingGateLeft", y, -1.0, true,receiving_height), _make_gate(id.validate_node_name() + "LandingGateRight", y, 1.0, true,receiving_height)]
	if top > previous: _box(static_body, kit, Looks.get_mat("granite_light"), Vector3(_center.x, (top + previous) * .5, _center.y + _sign * (DEPTH * .5 + .07)), Vector3(WIDTH + .4, top - previous, .10))
	kit.commit(static_body, "ShaftMaterials", true)

## Bind an actually built GuestFloor/ProgramFloor. No floor reparenting/motion.
func bind_floor(floor_id: String, floor_node: Node3D, portal_id: String) -> bool:
	if not _built or not _stops.has(floor_id) or not is_instance_valid(floor_node) or not floor_node.is_inside_tree() or not floor_node.has_signal("transition_requested") or not floor_node.has_method("confirm_transition_ready"): return false
	if floor_node.get_world_3d().space != get_world_3d().space or typeof(floor_node.get("portals")) != TYPE_ARRAY or typeof(floor_node.get("doors")) != TYPE_DICTIONARY: return false
	if _bindings.has(floor_id):
		var previous: Variant = _bindings[floor_id].node
		if (is_instance_valid(previous) and previous.is_inside_tree()) or float(_landing_fraction[floor_id]) > .001: return false
		_bindings.erase(floor_id)
		_external_ready.erase(floor_id)
	var found: Dictionary = {}
	for portal: Dictionary in floor_node.get("portals"):
		if portal.id == portal_id: found = portal
	if found.is_empty() or found.kind != _stops[floor_id].kind or portal_id != _stops[floor_id].portal_id: return false
	var expected := to_global(Vector3(_center.x, float(_stops[floor_id].elevation_m), _center.y))
	if floor_node.to_global(found.cabin_expected_center).distance_to(expected) > .04: return false
	var threshold := to_global(Vector3(_center.x, float(_stops[floor_id].elevation_m), _center.y + _sign * DEPTH * .5))
	if floor_node.to_global(found.threshold).distance_to(threshold) > .04: return false
	if not _receiving_geometry_ok(floor_id,floor_node,portal_id):return false
	if not floor_node.confirm_transition_ready(portal_id, false): return false
	_bindings[floor_id] = {"node": floor_node, "portal_id": portal_id}
	_external_ready[floor_id] = false
	if not floor_node.is_connected("transition_requested", _on_floor_transition): floor_node.connect("transition_requested", _on_floor_transition)
	return true

## Parent must retain floor collision until landing/cabin doors close, and pin
## the active destination. This is an explicit safe pre-unload handshake.
func unbind_floor(floor_id: String) -> bool:
	if not _bindings.has(floor_id) or float(_landing_fraction[floor_id]) > .001 or _external_ready.get(floor_id, false) or (_target == floor_id and _state == "MOVING"): return false
	var node: Variant = _bindings[floor_id].node
	if is_instance_valid(node) and node.is_connected("transition_requested", _on_floor_transition): node.disconnect("transition_requested", _on_floor_transition)
	_bindings.erase(floor_id)
	_external_ready.erase(floor_id)
	return true

func _on_floor_transition(floor_id: String, portal_id: String, kind: String) -> void:
	if _bindings.has(floor_id) and _bindings[floor_id].portal_id == portal_id and _stops[floor_id].kind == kind: request_floor(floor_id)

func request_floor(floor_id: String) -> bool:
	if not _built or not _stops.has(floor_id): return false
	if _state == "EMERGENCY": return false
	if floor_id == _at_floor and absf(_motion_y - float(_stops[floor_id].elevation_m)) <= ALIGN_M and _state in ["IDLE", "OPEN", "WAIT_READY"]:
		_target = floor_id
		_change("WAIT_READY", "Checking landing collision")
	elif not _queue.has(floor_id) and floor_id != _target: _queue.append(floor_id)
	return true

func _receiving_geometry_ok(id:String,node:Node3D,portal_id:String)->bool:
	if not _stops.has(id) or not is_instance_valid(node) or not bool(node.get("_built")):return false
	var record:Variant=node.get("floor_record")
	if not record is Dictionary or record.get("id","")!=id or not record.get("geometry") is Dictionary:return false
	var g:Dictionary=record.geometry
	var expected:float=_stops[id].receiving_door_height_m
	var declared:Variant=g.get("core_door_height_m",DOOR_H)
	var clear:Variant=g.get("clear_height_m")
	if not _number(declared) or not _number(clear) or absf(float(declared)-expected)>.001:return false
	var required_clear:float=_stops[id].receiving_clear_height_m
	if float(clear)<expected+(.10 if expected<DOOR_H-.001 else .20)+.04 or (required_clear>0.0 and absf(float(clear)-required_clear)>.001):return false
	if not node.get("doors") is Dictionary:return false
	var door:Variant=node.get("doors").get(portal_id)
	if not door is AnimatableBody3D or not door.is_inside_tree() or door.get_world_3d()!=get_world_3d():return false
	var shapes:=0
	for child:Node in door.get_children():
		if child is CollisionShape3D and not child.disabled:
			var actual_box:BoxShape3D=child.shape as BoxShape3D
			if actual_box==null or absf(actual_box.size.y-expected)>.001:return false
			shapes+=1
	return shapes==1

func _readiness(floor_id: String) -> Dictionary:
	if not _bindings.has(floor_id) or not is_instance_valid(_bindings[floor_id].node) or not _bindings[floor_id].node.is_inside_tree(): return {"ready": false, "reason": "Floor and landing interlock are not bound/resident"}
	if not shaft_collision_ready(): return {"ready": false, "reason": "Owned shaft collision has not committed"}
	if not _receiving_geometry_ok(floor_id,_bindings[floor_id].node,_bindings[floor_id].portal_id):return {"ready":false,"reason":"Actual receiving geometry no longer matches planned opening"}
	var value: Variant = _ready_callback.call(floor_id)
	if not _exact(value, ["ready", "floor_id", "collision_generation", "travel_ready"]) or typeof(value.ready) != TYPE_BOOL or typeof(value.travel_ready) != TYPE_BOOL or typeof(value.floor_id) != TYPE_STRING or value.floor_id != floor_id or not _text(value.collision_generation): return {"ready": false, "reason": "Readiness callback is not a valid collision lease"}
	var structure:Node=_bindings[floor_id].node.get_node_or_null("ProgramFloorSolidCollision")
	if structure==null:structure=_bindings[floor_id].node.get_node_or_null("GuestFloorSolidCollision")
	var stamp:Variant=structure.get_meta("singapore_source_support_v1",{}) if structure!=null else {}
	var low:bool=float(_stops[floor_id].receiving_door_height_m)<DOOR_H-.001
	if low and (not stamp is Dictionary or stamp.is_empty()):return {"ready":false,"reason":"Low receiving floor lacks actual source collision generation"}
	if stamp is Dictionary and not stamp.is_empty() and (stamp.get("floor_id","")!=floor_id or stamp.get("residency_token","")!=value.collision_generation):return {"ready":false,"reason":"Readiness generation differs from actual receiving support"}
	return value.duplicate(true)

## Parent combines this OWN-shaft proof with its floor/neighbor collision
## lease. It does not claim source geography, world saves or foreign geometry.
func shaft_collision_ready() -> bool:
	if not _built or not is_inside_tree() or not _upright_unit() or Engine.get_physics_frames() < _built_tick + 3: return false
	var space: RID = get_world_3d().space
	for rid: RID in _owned_rids:
		if not rid.is_valid() or PhysicsServer3D.body_get_space(rid) != space or PhysicsServer3D.body_get_shape_count(rid) == 0: return false
	return true

func _confirm(id: String, ready: bool) -> void:
	if not _bindings.has(id) or not is_instance_valid(_bindings[id].node): return
	if _external_ready.get(id, false) == ready: return
	_bindings[id].node.confirm_transition_ready(_bindings[id].portal_id, ready)
	_external_ready[id] = ready

func _external_closed() -> bool:
	for id: String in _bindings:
		var floor_node: Variant = _bindings[id].node
		if not is_instance_valid(floor_node): continue
		var door: Variant = floor_node.get("doors").get(_bindings[id].portal_id)
		if not is_instance_valid(door) or bool(door.get("opened")) or absf(float(door.get("motion_angle")) - float(door.get("base_angle"))) > .012: return false
		var physical: Transform3D = PhysicsServer3D.body_get_state(door.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		var expected: Basis = floor_node.global_basis * Basis(Vector3.UP, float(door.get("base_angle")))
		if physical.basis.x.distance_to(expected.x) > .012 or physical.basis.z.distance_to(expected.z) > .012: return false
	return true

func _native_aligned() -> bool:
	var pose: Transform3D = PhysicsServer3D.body_get_state(cabin.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	return absf(to_local(pose.origin).y - _motion_y) <= ALIGN_M

func _gate_center(y: float, side: float, fraction: float, landing: bool) -> Vector3:
	# Landing safety grille stays BEHIND GuestFloor's native E door, so it
	# cannot occlude that door's interaction ray while the lift is absent.
	return Vector3(_center.x + side * (DOOR_W * .25 + fraction * .72), y, _center.y + _sign * (DEPTH * .5 + (-.07 if landing else -_cabin_gate_setback)))

func _publish_transforms() -> void:
	# ONE complete transform per AnimatableBody setter, from commanded scalar
	# state. Never read/modify/write position then rotation with sync_to_physics.
	cabin.transform = Transform3D(Basis.IDENTITY, Vector3(_center.x, _motion_y, _center.y))
	for index in 2:
		var side := -1.0 if index == 0 else 1.0
		_cabin_gates[index].transform = Transform3D(Basis.IDENTITY, _gate_center(_motion_y, side, _gate_fraction, false))
		for id: String in _ordered: _shaft_gates[id][index].transform = Transform3D(Basis.IDENTITY, _gate_center(float(_stops[id].elevation_m), side, float(_landing_fraction[id]), true))
	panel.transform = Transform3D(Basis.IDENTITY, Vector3(_center.x + .65, _motion_y + .75, _center.y - _sign * .35))

func _doors_physically_closed() -> bool:
	if _gate_fraction > .001 or not _external_closed(): return false
	for id: String in _ordered:
		if float(_landing_fraction[id]) > .001: return false
	var physical_cabin: Transform3D = PhysicsServer3D.body_get_state(cabin.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	for index in 2:
		var side := -1.0 if index == 0 else 1.0
		var pose: Transform3D = PhysicsServer3D.body_get_state(_cabin_gates[index].get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		if pose.origin.distance_to(physical_cabin * Vector3(side * DOOR_W * .25, 0, _sign * (DEPTH * .5 - _cabin_gate_setback))) > ALIGN_M: return false
		for id: String in _ordered:
			var landing_pose: Transform3D = PhysicsServer3D.body_get_state(_shaft_gates[id][index].get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			if landing_pose.origin.distance_to(to_global(_gate_center(float(_stops[id].elevation_m), side, 0.0, true))) > ALIGN_M: return false
	return true

func _door_hit_details(hits: Array[Dictionary]) -> Array[Dictionary]:
	var details: Array[Dictionary] = []
	for hit: Dictionary in hits:
		var body: Variant = hit.get("collider")
		if not is_instance_valid(body) or not body is CollisionObject3D:
			details.append({"body": "INVALID_NATIVE_COLLIDER", "shape_index": hit.get("shape")})
			continue
		var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		var owner: Variant = body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape)))
		var detail := {"body": String(body.name), "path": String(body.get_path()), "collider_id": body.get_instance_id(),
			"rid_id": body.get_rid().get_id(), "shape_index": int(hit.shape), "collision_layer": body.collision_layer,
			"native_body_origin": physical.origin, "node_origin": body.global_position,
			"relative_to_cabin": to_local(physical.origin) - Vector3(_center.x, _motion_y, _center.y)}
		if owner is CollisionShape3D and owner.shape != null:
			var shape: Variant = owner.shape
			var physical_shape: Transform3D = physical * owner.transform
			detail["shape_name"] = String(owner.name)
			detail["shape_class"] = shape.get_class()
			detail["native_shape_origin"] = physical_shape.origin
			detail["native_shape_basis"] = [physical_shape.basis.x, physical_shape.basis.y, physical_shape.basis.z]
			var half := Vector3.ZERO
			if shape is BoxShape3D:
				half = shape.size * .5
				detail["box_size"] = shape.size
			elif shape is CapsuleShape3D:
				half = Vector3(shape.radius, shape.height * .5, shape.radius)
				detail["capsule_radius"] = shape.radius
				detail["capsule_height"] = shape.height
			if half != Vector3.ZERO:
				var lower := Vector3(INF, INF, INF)
				var upper := Vector3(-INF, -INF, -INF)
				for index in 8:
					var corner: Vector3 = physical_shape * Vector3(half.x if index & 1 else -half.x, half.y if index & 2 else -half.y, half.z if index & 4 else -half.z)
					lower = lower.min(corner)
					upper = upper.max(corner)
				detail["native_shape_aabb_min"] = lower
				detail["native_shape_aabb_max"] = upper
		details.append(detail)
	return details

func _controlled_collision_rids()->Array[RID]:
	var result:Array[RID]=[]
	for child:Node in get_children():
		if child is AnimatableBody3D:result.append(child.get_rid())
	return result

func _door_obstructed() -> bool:
	if _has_low_receivers:return _door_obstructed_split()
	var box := BoxShape3D.new()
	box.size = Vector3(DOOR_W - .04, 2.10, .70)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = global_transform * Transform3D(Basis.IDENTITY, Vector3(_center.x, _motion_y + 1.10, _center.y + _sign * DEPTH * .5))
	query.collision_mask = 1 | 2 | 8
	query.margin = .005
	var exclusions: Array[RID] = _controlled_collision_rids()
	var landing_doors: Array[Dictionary] = []
	for id: String in _bindings:
		if not is_instance_valid(_bindings[id].node): continue
		var door: Variant = _bindings[id].node.get("doors").get(_bindings[id].portal_id)
		if door is CollisionObject3D:
			exclusions.append(door.get_rid())
			landing_doors.append({"floor_id": id, "body": String(door.name), "rid_id": door.get_rid().get_id()})
	# The exclude PROPERTY getter returns a copy. Append to the local array,
	# then assign ONCE; query.exclude.append(...) never updated native filters.
	# Paired same-tick diagnostic reproduces the previous effective filter so
	# QA can identify the exact removed leaf without changing sensor geometry.
	query.exclude = _controlled_collision_rids()
	var legacy_hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(query, 16)
	query.exclude = exclusions
	var hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(query, 16)
	_last_door_probe = {"physics_tick": Engine.get_physics_frames(), "query_origin": query.transform.origin,
		"query_size": box.size, "collision_mask": query.collision_mask, "owned_exclusion_count": _controlled_collision_rids().size(),"owned_static_enclosure_excluded":false,
		"actual_exclusion_count": query.exclude.size(), "expected_exclusion_count": exclusions.size(),
		"landing_doors": landing_doors, "legacy_owned_only_hits": _door_hit_details(legacy_hits),
		"controlling_hits": _door_hit_details(hits)}
	return not hits.is_empty()

func _door_obstructed_split()->bool:
	var receiving_height:float=_stops[_at_floor].receiving_door_height_m
	var leaf_height:float=receiving_height-.02
	var exclusions:Array[RID]=_controlled_collision_rids()
	var landing_doors:Array[Dictionary]=[]
	for id:String in _bindings:
		if not is_instance_valid(_bindings[id].node):continue
		var door:Variant=_bindings[id].node.doors.get(_bindings[id].portal_id)
		if door is CollisionObject3D:exclusions.append(door.get_rid());landing_doors.append({"floor_id":id,"body":String(door.name),"rid_id":door.get_rid().get_id()})
	var definitions:Array[Dictionary]=[
		{"label":"cabin-side-tall-clearance","size":Vector3(DOOR_W-.04,DOOR_H-.04,.16),"center":Vector3(_center.x,_motion_y+DOOR_H*.5,_center.y+_sign*(DEPTH*.5-_cabin_gate_setback))},
		{"label":"receiving-opening-clearance","size":Vector3(DOOR_W-.04,leaf_height-.02,.50),"center":Vector3(_center.x,_motion_y+(leaf_height+.02)*.5,_center.y+_sign*(DEPTH*.5+.08))}]
	var hits:Array[Dictionary]=[];var segments:Array[Dictionary]=[]
	for definition:Dictionary in definitions:
		var box:=BoxShape3D.new();box.size=definition.size
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=box;query.transform=global_transform*Transform3D(Basis.IDENTITY,definition.center);query.collision_mask=1|2|8;query.margin=.005;query.exclude=exclusions
		var observed:Array[Dictionary]=get_world_3d().direct_space_state.intersect_shape(query,32)
		hits.append_array(observed)
		segments.append({"label":definition.label,"query_origin":query.transform.origin,"query_size":box.size,"margin_m":query.margin,"hits":_door_hit_details(observed)})
	_last_door_probe={"physics_tick":Engine.get_physics_frames(),"segmented_receiving_policy":true,"receiving_door_height_m":receiving_height,"receiver_grille_leaf_height_m":leaf_height,"cabin_internal_height_m":HEIGHT,"cabin_gate_setback_m":_cabin_gate_setback,"segments":segments,"actual_exclusion_count":exclusions.size(),"expected_exclusion_count":exclusions.size(),"owned_static_enclosure_excluded":false,"landing_doors":landing_doors,"controlling_hits":_door_hit_details(hits)}
	return not hits.is_empty()

func _can_move(dy: float) -> bool:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = cabin.global_transform
	parameters.motion = global_basis * Vector3(0, dy, 0)
	parameters.margin = .001
	parameters.recovery_as_collision = false
	parameters.exclude_bodies = _controlled_collision_rids()
	var result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(cabin.get_rid(), parameters, result):
		_last_blockage = {}
		return true
	var collider: Variant = result.get_collider(0) if result.get_collision_count() > 0 else null
	var shape_name:="UNKNOWN"
	if collider is CollisionObject3D and result.get_collision_count()>0:
		var owner:Node=collider.shape_owner_get_owner(collider.shape_find_owner(result.get_collider_shape(0)))
		if owner!=null:shape_name=String(owner.name)
	_last_blockage = {"collider": String(collider.name) if collider is Node else "UNKNOWN","shape_name":shape_name,"owned_static_enclosure_excluded":false, "motion_dy_m": dy,
		"position": result.get_collision_point(0) if result.get_collision_count() > 0 else Vector3.ZERO,
		"normal": result.get_collision_normal(0) if result.get_collision_count() > 0 else Vector3.ZERO}
	return false

func _change(state: String, detail: String) -> void:
	if state != _state or detail != _detail:
		if state == "OPEN" and _state != "OPEN": _dwell_elapsed = 0.0
		_state = state
		_detail = detail
		state_changed.emit(_descriptor.get("shaft_id", ""), state, detail)

func emergency_stop(reason: String = "Emergency stop requested") -> void:
	if not _built: return
	_velocity_y = 0.0
	for id: String in _ordered: _confirm(id, false)
	_change("EMERGENCY", reason)

func resume_after_safety_check() -> bool:
	if not _built or _state != "EMERGENCY": return false
	if _target.is_empty(): _target = _at_floor
	var ready: Dictionary = _readiness(_target)
	if not ready.ready or not ready.get("travel_ready", false): return false
	_change("CLOSING", "Retrying closed-door/path checks")
	return true

func _physics_process(delta: float) -> void:
	if not _built: return
	if Game.simulation_paused:
		_velocity_y = 0.0
		_publish_transforms()
		return
	if not _upright_unit() or not is_finite(delta) or delta <= 0.0 or delta > .10:
		emergency_stop("Invalid placement or delayed physics step")
		return
	if _state == "OPEN": _dwell_elapsed += delta
	if (_state == "IDLE" or (_state == "OPEN" and _dwell_elapsed >= 2.0 and _gate_fraction >= .999)) and not _queue.is_empty():
		_target = _queue.pop_front()
		_change("CLOSING", "Closing cabin and landing doors")
	if _state == "OPEN":
		var ready: Dictionary = _readiness(_at_floor)
		if not ready.ready or not _native_aligned():
			emergency_stop("Landing lost alignment/residency")
		else: _confirm(_at_floor, true)
	if _state == "CLOSING":
		if _door_obstructed():
			var ready: Dictionary = _readiness(_at_floor)
			if ready.ready and absf(_motion_y - float(_stops[_at_floor].elevation_m)) <= ALIGN_M and _native_aligned():
				if not _target.is_empty() and not _queue.has(_target): _queue.push_front(_target)
				_target = ""
				_change("OPEN", "Doorway obstructed; waiting for clear threshold")
			else: emergency_stop("Door path obstructed away from a safe landing")
		else:
			for id: String in _ordered: _confirm(id, false)
			if _doors_physically_closed(): _change("WAIT_READY", "Waiting for resident destination and shaft")
	if _state == "WAIT_READY":
		var ready: Dictionary = _readiness(_target)
		if not ready.ready or not ready.get("travel_ready", false):
			if _last_requested != _target:
				_last_requested = _target
				floor_requested.emit(_descriptor.shaft_id, _target)
		elif absf(_motion_y - float(_stops[_target].elevation_m)) <= .0001 and _native_aligned():
			_at_floor = _target
			_target = ""
			_last_requested = ""
			_change("OPEN", "Cabin aligned; landing collision ready")
			_confirm(_at_floor, true)
			arrived.emit(_descriptor.shaft_id, _at_floor)
		elif _doors_physically_closed(): _change("MOVING", "Physical shaft travel")
	if _state == "MOVING":
		var ready: Dictionary = _readiness(_target)
		if not ready.ready or not ready.get("travel_ready", false) or not _doors_physically_closed(): emergency_stop("Travel collision lease or door interlock lost")
		else:
			var target_y: float = float(_stops[_target].elevation_m)
			var remaining := target_y - _motion_y
			var desired := signf(remaining) * minf(float(_descriptor.speed_mps), sqrt(2.0 * float(_descriptor.acceleration_mps2) * absf(remaining)))
			_velocity_y = move_toward(_velocity_y, desired, float(_descriptor.acceleration_mps2) * delta)
			var next_y := move_toward(_motion_y, target_y, absf(_velocity_y) * delta)
			if not _can_move(next_y - _motion_y): emergency_stop("Native cabin sweep blocked; no actor relocation")
			else:
				_motion_y = next_y
				if absf(_motion_y - target_y) <= .0001:
					_velocity_y = 0.0
					_change("WAIT_READY", "Stopped; verifying native alignment")
	var open_now: bool = _state == "OPEN" and absf(_motion_y - float(_stops[_at_floor].elevation_m)) <= ALIGN_M and absf(_velocity_y) < .001
	if _state == "EMERGENCY" and absf(_motion_y - float(_stops[_at_floor].elevation_m)) <= ALIGN_M and _native_aligned():
		var safe_landing: Dictionary = _readiness(_at_floor)
		open_now = safe_landing.ready
		if open_now: _confirm(_at_floor, true)
	_gate_fraction = move_toward(_gate_fraction, 1.0 if open_now else 0.0, delta * 1.25)
	for id: String in _ordered: _landing_fraction[id] = move_toward(float(_landing_fraction[id]), 1.0 if open_now and id == _at_floor else 0.0, delta * 1.25)
	_publish_transforms()
	if _ui_open: _ui_label.text = "Lift · " + _state + "\n" + _detail + "\n[E] Confirm highlighted floor · Esc closes"

func panel_interact(_actor: Node) -> void:
	if _ui_open:
		request_floor(_ordered[_selection])
		_close_panel()
		return
	_selection = (_ordered.find(_at_floor) + 1) % _ordered.size()
	_ui_open = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ui.show()
	_floor_buttons[_ordered[_selection]].grab_focus()

func _close_panel() -> void:
	_ui_open = false
	if is_instance_valid(_ui): _ui.hide()
	Input.mouse_mode = _mouse_before

func _unhandled_input(event: InputEvent) -> void:
	if _ui_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: _close_panel()

func _button_floor(id: String) -> void:
	request_floor(id)
	_close_panel()

func _focus_floor(index: int) -> void:
	_selection = index

func _make_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 15
	add_child(_ui)
	var background := PanelContainer.new()
	background.position = Vector2(24, 72)
	background.custom_minimum_size = Vector2(320, 440)
	_ui.add_child(background)
	var content := VBoxContainer.new()
	background.add_child(content)
	_ui_label = Label.new()
	content.add_child(_ui_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(310, 300)
	content.add_child(scroll)
	var floors := VBoxContainer.new()
	scroll.add_child(floors)
	for index in _ordered.size():
		var id: String = _ordered[index]
		var button := Button.new()
		button.text = String(_stops[id].label)
		button.pressed.connect(_button_floor.bind(id))
		button.focus_entered.connect(_focus_floor.bind(index))
		floors.add_child(button)
		_floor_buttons[id] = button
	var stop := Button.new()
	stop.text = "Emergency stop"
	stop.pressed.connect(func(): emergency_stop(); _close_panel())
	content.add_child(stop)
	var resume := Button.new()
	resume.text = "Retry safety checks"
	resume.pressed.connect(func(): resume_after_safety_check(); _close_panel())
	content.add_child(resume)
	_ui.hide()

func report() -> Dictionary:
	return {"built": _built, "shaft_id": _descriptor.get("shaft_id", ""), "state": _state, "detail": _detail,
		"current_floor_id": _at_floor, "target_floor_id": _target, "commanded_y_m": _motion_y, "velocity_y_mps": _velocity_y,
		"gate_fraction": _gate_fraction, "landing_fractions": _landing_fraction.duplicate(true), "queue": _queue.duplicate(), "bound_floor_ids": _bindings.keys(),
		"last_blockage": _last_blockage.duplicate(true),
		"last_door_probe": _last_door_probe.duplicate(true),"receiving_stop_geometry":_stops.duplicate(true),"mixed_low_receiving_policy":_has_low_receivers,"cabin_internal_height_m":HEIGHT,"cabin_gate_height_m":DOOR_H,"cabin_gate_setback_m":_cabin_gate_setback,
		"actor_pose_assignments": 0, "actor_reparents": 0, "private_asbuilt_verified": false, "source_world_or_whole_MBS_completed": false}

func _exit_tree() -> void:
	if _ui_open: _close_panel()
