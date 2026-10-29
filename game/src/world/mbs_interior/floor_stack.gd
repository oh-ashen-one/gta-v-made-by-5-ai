extends Node3D
## Actual-source, bounded native floor streaming. No actor mutation/reparenting,
## origin commit, invented geography, cabin or shaft-readiness assertion.
signal floor_committed(floor_id: String, collision_generation: String)
signal floor_retired(floor_id: String, region_id: String)
signal floor_unloaded(floor_id: String)
signal floor_load_failed(floor_id: String, status: String, error: String)
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const GuestFloor = preload("res://src/world/mbs_interior/guest_floor.gd")
const ProgramFloor = preload("res://src/world/mbs_interior/program_floor.gd")
const PublicL1 = preload("res://src/world/mbs_interior/public_l1.gd")
const FEATURE := "mbs-hotel/source-floor-stack-reconstruction"
const SCHEMA := "mbs_floor_stack_doors_v1"
var last_error := ""
var _frame: RefCounted
var _context: RefCounted
var _runtime: Node3D
var _configured := false
var _base_elevation := 0.0
var _datum_provenance := ""
var _max_active := 6
var _max_pending := 3
var _auto_stream := true
var _records: Dictionary = {}
var _orders: Dictionary = {}
var _entries: Dictionary = {}
var _definitions: Dictionary = {}
var _saved_doors: Dictionary = {}
var _geometry_overrides: Dictionary = {}
var _resort_mappings: Dictionary = {}
var _pins: Dictionary = {}
var _actor_claims: Dictionary = {}
var _busy := false
var _pending := 0
var _serial := 0
var _inventory_sha := ""
var _unload_guard: Callable
var _unload_guard_set := false
var _unload_guard_owner: RefCounted
var _auto_pending := false
var _auto_retry_after: Dictionary = {}
var _public_core_connections: Array[Dictionary] = []
var _public_arrival_corridor: Dictionary = {}

func _sha(value: String) -> String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(value.to_utf8_buffer());return hash.finish().hex_encode()

func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

func _xyz(value: Variant) -> bool:
	if not typeof(value) in [TYPE_ARRAY,TYPE_PACKED_FLOAT64_ARRAY] or value.size()!=3: return false
	for n: Variant in value:
		if not _number(n) or absf(float(n))>Frame.MAX_CANONICAL_COMPONENT_M: return false
	return true

func _axes(x: Variant,z: Variant) -> bool:
	if not _xyz(x) or not _xyz(z) or float(x[1])!=0.0 or float(z[1])!=0.0: return false
	return absf(float(x[0])*float(x[0])+float(x[2])*float(x[2])-1.0)<1e-12 and absf(float(z[0])*float(z[0])+float(z[2])*float(z[2])-1.0)<1e-12 and absf(float(x[0])*float(z[0])+float(x[2])*float(z[2]))<1e-12 and absf(float(x[0])*float(z[2])-float(x[2])*float(z[0])-1.0)<1e-12

func configure(frame: RefCounted,context: RefCounted,runtime: Node3D,base_elevation_m: Variant,datum_provenance: String,options: Dictionary = {}) -> bool:
	if _configured or not is_inside_tree() or not frame is Frame or not context is Context or not is_instance_valid(runtime) or not runtime is Runtime: last_error="Require a fresh in-tree stack and explicit common source objects";return false
	if not global_basis.get_scale().is_equal_approx(Vector3.ONE): last_error="Source floor stack cannot inherit compressed/scaled metres";return false
	if not _number(base_elevation_m) or absf(float(base_elevation_m))>1000.0 or datum_provenance.is_empty() or datum_provenance.length()>512: last_error="Explicit finite base elevation and datum provenance required";return false
	if not frame.metadata().configured or not context.metadata().configured or context.metadata().frame_instance_id!=frame.get_instance_id() or runtime.get("frame")!=frame or runtime.get("context")!=context or runtime.get_world_3d()!=get_world_3d() or context.metadata().physics_space_id!=get_world_3d().space.get_id(): last_error="Floor, actors, context and runtime must share one configured frame/World3D";return false
	for other: Node in get_tree().get_nodes_in_group("mbs_source_floor_stack"):
		if other!=self and other.get("_context")==context: last_error="This context already has a source floor-stack geometry authority";return false
	for key: Variant in options:
		if not key in ["max_active_floors","max_pending_requests","auto_stream","geometry_overrides","resort_mappings","unload_guard","public_core_connections","public_arrival_corridor"]: last_error="Unknown stack option";return false
	var active: Variant=options.get("max_active_floors",6)
	var pending: Variant=options.get("max_pending_requests",3)
	if not typeof(active)==TYPE_INT or active<3 or active>12 or not typeof(pending)==TYPE_INT or pending<1 or pending>4 or typeof(options.get("auto_stream",true))!=TYPE_BOOL: last_error="Bounded active/pending floor limits required";return false
	if not options.get("geometry_overrides",{}) is Dictionary or not options.get("resort_mappings",{}) is Dictionary: last_error="Mapping options must be dictionaries";return false
	if options.has("unload_guard") and (not options.unload_guard is Callable or not options.unload_guard.is_valid()): last_error="Invalid explicit unload guard";return false
	var public_requests: Variant=options.get("public_core_connections",[])
	var public_arrival: Variant=options.get("public_arrival_corridor",{})
	if not public_requests is Array or public_requests.size()>6 or not public_arrival is Dictionary: last_error="Explicit bounded public connection requests required";return false
	var public_seen: Dictionary={}
	for request: Variant in public_requests:
		if not PublicL1.validate_connection_request(request,false): last_error="Invalid source public core request";return false
		var target_record:=Inventory.floor_record(String(request.tower)+"-L1")
		if target_record.is_empty() or absf(float(request.target_floor_elevation_m)-(float(base_elevation_m)+float(target_record.elevation_m)))>.0001: last_error="Core target elevation differs from actual copied L1 record";return false
		var key: String=String(request.tower)+"-"+String(request.side)
		if public_seen.has(key): last_error="Duplicate public core side";return false
		public_seen[key]=true
	if not public_arrival.is_empty():
		if not PublicL1.validate_connection_request(public_arrival,true) or public_seen.has("T1-west"): last_error="Invalid/conflicting source arrival corridor";return false
		var arrival_record:=Inventory.floor_record("T1-L1")
		if arrival_record.is_empty() or absf(float(public_arrival.target_floor_elevation_m)-(float(base_elevation_m)+float(arrival_record.elevation_m)))>.0001: last_error="Arrival elevation differs from actual copied T1 L1 record";return false
	var data:=Inventory.load_inventory()
	if data.has("error"): last_error=data.error;return false
	var records: Dictionary={}
	var orders: Dictionary={}
	for record: Dictionary in (data.hotel_floors as Array)+(data.resort_program_floors as Array):
		var id:=String(record.id)
		var building:=String(record.get("tower",record.get("building","")))
		if records.has(id) or not _number(record.get("elevation_m")): last_error="Invalid duplicated/elevation inventory";return false
		records[id]=record.duplicate(true)
		if not orders.has(building): orders[building]=[]
		orders[building].append(id)
	for building: String in orders:
		orders[building].sort_custom(func(a: String,b: String): return float(records[a].elevation_m)<float(records[b].elevation_m))
		for index in orders[building].size()-1:
			if float(records[orders[building][index+1]].elevation_m)<=float(records[orders[building][index]].elevation_m): last_error="Adjacent inventory elevations must be strictly ordered";return false
	for id: Variant in options.get("geometry_overrides",{}):
		if not id is String or not records.has(id) or not options.geometry_overrides[id] is Dictionary: last_error="Invalid explicit floor geometry override";return false
	for id: Variant in options.get("resort_mappings",{}):
		if not id is String or not records.has(id) or records[id].has("tower") or not _valid_mapping(options.resort_mappings[id]): last_error="Invalid explicit resort source mapping";return false
	_records=records;_orders=orders;_frame=frame;_context=context;_runtime=runtime
	_base_elevation=float(base_elevation_m);_datum_provenance=datum_provenance
	_max_active=int(active);_max_pending=int(pending);_auto_stream=options.get("auto_stream",true)
	_geometry_overrides=options.get("geometry_overrides",{}).duplicate(true)
	_resort_mappings=options.get("resort_mappings",{}).duplicate(true)
	_public_core_connections.assign(public_requests.duplicate(true))
	_public_arrival_corridor=public_arrival.duplicate(true)
	_inventory_sha=_sha(FileAccess.get_file_as_string(Inventory.PATH))
	_configured=true
	add_to_group("mbs_source_floor_stack")
	if options.has("unload_guard"): set_unload_guard(options.unload_guard)
	return true

func _valid_mapping(value: Variant) -> bool:
	if not value is Dictionary or not value.get("source_anchor_xz") is Array or value.source_anchor_xz.size()!=2 or not value.get("geometry") is Dictionary or not value.get("provenance") is String or value.provenance.is_empty() or value.provenance.length()>512: return false
	for n: Variant in value.source_anchor_xz:
		if not _number(n) or absf(float(n))>Frame.MAX_CANONICAL_COMPONENT_M: return false
	return _axes(value.get("axis_x_xyz"),value.get("axis_z_xyz"))

func install_resort_mapping(id: String,mapping: Dictionary) -> bool:
	id=Inventory.normalize_floor_id(id)
	if not _configured or _busy or not _records.has(id) or _records[id].has("tower") or _definitions.has(id) or not _valid_mapping(mapping): return false
	_resort_mappings[id]=mapping.duplicate(true);_auto_retry_after.erase(id)
	return true

func set_unload_guard(callback: Callable) -> bool:
	if not callback.is_valid(): return false
	_unload_guard=callback;_unload_guard_set=true
	var owner: Object=callback.get_object()
	if owner is RefCounted: _unload_guard_owner=owner
	return true

func release_unload_guard(expected: Callable) -> bool:
	if not _unload_guard_set or _unload_guard != expected: return false
	_unload_guard = Callable(); _unload_guard_set = false; _unload_guard_owner = null
	return true

func adjacent_floor_ids(id: String) -> Array[String]:
	id=Inventory.normalize_floor_id(id)
	var result: Array[String]=[]
	if not _records.has(id): return result
	var record: Dictionary=_records[id]
	var building:=String(record.get("tower",record.get("building","")))
	var order: Array=_orders[building]
	var at:=order.find(id)
	if at>0: result.append(order[at-1])
	if at+1<order.size(): result.append(order[at+1])
	return result

func _recipe(id: String) -> Dictionary:
	if not _records.has(id): return {"ok":false,"status":"unknown_floor","error":"Floor is absent from the inventory"}
	var record: Dictionary=_records[id].duplicate(true)
	var placement: Dictionary={}
	if record.has("tower"):
		for tower: Dictionary in Reference.DATA.towers:
			if tower.tower!=record.tower: continue
			var centroid: Array=tower.centroid_world_xz
			placement={"anchor_xyz":[float(centroid[0]),_base_elevation+float(record.elevation_m),float(centroid[1])],"axis_x_xyz":[float(Reference.DATA.axis_south_xz[0]),0.0,float(Reference.DATA.axis_south_xz[1])],"axis_z_xyz":[float(Reference.DATA.axis_bayward_xz[0]),0.0,float(Reference.DATA.axis_bayward_xz[1])],"source_id":tower.id,"provenance":"Actual OSM tower centroid and source axes; inventory private floor geometry is reconstructed"}
		if placement.is_empty(): return {"ok":false,"status":"pending_root_source_mapping","error":"Tower source ID missing"}
		if _geometry_overrides.has(id): record.geometry=_geometry_overrides[id].duplicate(true)
		elif record.level=="L1":
			# Perimeter programs cannot create a low slab/ceiling across the real
			# continuous public loft. Root still owns actual connecting wall doors.
			var width: float=Reference.ATRIUM_ENGINEERING.approx_width_m[record.tower]
			record.geometry.atrium_void_active=true
			record.geometry.void_min_z_m=-width*.5;record.geometry.void_max_z_m=width*.5
			record["stack_geometry_adaptation"]="L1_PERIMETER_WINGS_PRESERVE_HISTORICAL_ATRIUM_WIDTH_NOT_CURRENT_SURVEY"
	else:
		if not _resort_mappings.has(id): return {"ok":false,"status":"pending_root_source_mapping","error":"Resort requires explicit source anchor/axes/geometry; no invented permanent placeholder","requires_root_mapping":true}
		var mapping: Dictionary=_resort_mappings[id]
		record["geometry"]=mapping.geometry.duplicate(true)
		placement={"anchor_xyz":[float(mapping.source_anchor_xz[0]),_base_elevation+float(record.elevation_m),float(mapping.source_anchor_xz[1])],"axis_x_xyz":mapping.axis_x_xyz.duplicate(),"axis_z_xyz":mapping.axis_z_xyz.duplicate(),"source_id":String(record.building)+"/explicit-root-mapping","provenance":mapping.provenance}
	if record.has("tower") and record.level=="L1":
		var public_join: Dictionary=_forward_public_l1_adapters(record)
		if not public_join.ok: return public_join
	var building:=String(record.get("tower",record.get("building","")))
	var order: Array=_orders[building]
	var index:=order.find(id)
	var has_upper:=index+1<order.size()
	if not record.get("geometry") is Dictionary: return {"ok":false,"status":"pending_root_recipe_change","error":"Complete explicit floor geometry required"}
	if has_upper:
		var rise: float=float(_records[order[index+1]].elevation_m)-float(record.elevation_m)
		record.geometry.storey_height_m=rise
		if not _number(record.geometry.get("clear_height_m")) or float(record.geometry.clear_height_m)+.20>rise+.00001:
			return {"ok":false,"status":"pending_root_recipe_change","error":"Actual adjacent elevations cannot fit current full-height recipe; partial mezzanine/vertical zones required","floor_id":id,"upper_floor_id":order[index+1],"actual_rise_m":rise,"required_headroom_plus_slab_m":float(record.geometry.get("clear_height_m",0))+.20,"requires_root_recipe_change":true}
	record["has_upper_floor"]=has_upper
	var planned: Dictionary=GuestFloor.plan(record) if record.factory=="guest_floor_v1" else ProgramFloor.program_plan(record)
	if not planned.get("valid",false): return {"ok":false,"status":"pending_root_recipe_change","error":planned.get("error","Unsupported factory"),"requires_root_recipe_change":true}
	var projected: Dictionary=_frame.to_local(placement.anchor_xyz)
	if not projected.ok: return {"ok":false,"status":"pending_root_origin_transaction","error":projected.get("error","Outside active frame"),"requires_root_rebase":true}
	return {"ok":true,"record":record,"plan":planned,"placement":placement,"projected":projected}

func _forward_public_l1_adapters(record: Dictionary) -> Dictionary:
	var matching: Array[Dictionary]=[]
	for request: Dictionary in _public_core_connections:
		if request.tower==record.tower: matching.append(request)
	var arrival: Dictionary=_public_arrival_corridor if record.id=="T1-L1" else {}
	if matching.is_empty() and arrival.is_empty(): return {"ok":true}
	var g: Dictionary=record.geometry
	for key: String in ["corridor_width_m","cross_m","clear_height_m","void_min_z_m","void_max_z_m"]:
		if not _number(g.get(key)): return {"ok":false,"status":"pending_root_recipe_change","error":"Complete actual L1 geometry required for public joins","requires_root_recipe_change":true}
	if not bool(g.get("atrium_void_active",false)) or not g.get("atrium_core_openings",[]) is Array or not (g.get("atrium_core_openings",[]) as Array).is_empty(): return {"ok":false,"status":"pending_root_recipe_change","error":"Public joins need one explicit uncapped L1 edge, not duplicate pre-existing cuts","requires_root_recipe_change":true}
	var cuts: Array=[]
	var half: float=float(Reference.ATRIUM_ENGINEERING.approx_width_m[record.tower])*.5
	if absf(float(g.void_min_z_m)+half)>.001 or absf(float(g.void_max_z_m)-half)>.001: return {"ok":false,"status":"pending_root_recipe_change","error":"Public and perimeter atrium edges differ; explicit matched source adaptation required","requires_root_recipe_change":true}
	for request: Dictionary in matching:
		if absf(float(request.corridor_width_m)-float(g.corridor_width_m))>.001 or float(request.height_m)>float(g.clear_height_m)-.10: return {"ok":false,"status":"pending_root_recipe_change","error":"Core corridor/headroom differs from actual public request","requires_root_recipe_change":true}
		cuts.append({"id":String(record.id)+"-"+String(request.side)+"-core","wing":request.side,"center_x":request.along_offset_m,"width_m":request.width_m,"height_m":request.height_m})
	if not arrival.is_empty():
		if absf(float(arrival.target_cross_m)-float(g.cross_m))>.001 or absf(float(arrival.corridor_width_m)-float(g.corridor_width_m))>.001 or float(arrival.height_m)>float(g.clear_height_m)-.10: return {"ok":false,"status":"pending_root_recipe_change","error":"Arrival facade/corridor dimensions differ from actual T1 source recipe","requires_root_recipe_change":true}
		var reserved: Dictionary={"id":"T1-L1-west-arrival","wing":"west","center_x":arrival.along_offset_m,"width_m":arrival.width_m,"height_m":arrival.height_m}
		g["public_arrival_corridor"]=reserved
		cuts.append(reserved.duplicate(true))
	g["atrium_core_openings"]=cuts
	return {"ok":true}

func _not_ready(id: String,status: String,error: String,detail: Dictionary = {}) -> Dictionary:
	var result: Dictionary={"ready":false,"floor_id":id,"collision_generation":"","travel_ready":false,"status":status,"error":error,"transient":true}
	result.merge(detail,true);return result

func _canonical(placement: Dictionary,local: Vector3) -> Array:
	var a: Array=placement.anchor_xyz
	var x: Array=placement.axis_x_xyz
	var z: Array=placement.axis_z_xyz
	return [float(a[0])+float(x[0])*float(local.x)+float(z[0])*float(local.z),float(a[1])+float(local.y),float(a[2])+float(x[2])*float(local.x)+float(z[2])*float(local.z)]

func _basis(placement: Dictionary) -> Basis:
	var x: Array=placement.axis_x_xyz;var z: Array=placement.axis_z_xyz
	return Basis(Vector3(x[0],0,x[2]),Vector3.UP,Vector3(z[0],0,z[2]))

func _volume(placement: Dictionary,id: String,at: Vector3,half: Vector3) -> Dictionary:
	return {"schema":Context.OBOX_SCHEMA,"volume_id":id,"center_xyz":_canonical(placement,at),"half_extents_xyz":[float(half.x),float(half.y),float(half.z)],"axis_x_xyz":placement.axis_x_xyz.duplicate(),"axis_z_xyz":placement.axis_z_xyz.duplicate(),"dry":true}

func _subtract_rect(rectangle: Rect2,hole: Rect2) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	if not rectangle.intersects(hole): result.append(rectangle);return result
	var cut:=rectangle.intersection(hole)
	for r: Rect2 in [Rect2(rectangle.position,Vector2(cut.position.x-rectangle.position.x,rectangle.size.y)),Rect2(Vector2(cut.end.x,rectangle.position.y),Vector2(rectangle.end.x-cut.end.x,rectangle.size.y)),Rect2(Vector2(cut.position.x,rectangle.position.y),Vector2(cut.size.x,cut.position.y-rectangle.position.y)),Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,rectangle.end.y-cut.end.y))]:
		if r.size.x>.001 and r.size.y>.001: result.append(r)
	return result

func _volumes(recipe: Dictionary,module: Node3D) -> Array:
	var result: Array=[]
	var g: Dictionary=recipe.record.geometry
	var placement: Dictionary=recipe.placement
	var h: float=g.clear_height_m
	var low: float=-.25
	var high: float=h
	var end: float=float(g.length_m)*.5-float(g.core_bay_m)
	for wing: Dictionary in recipe.plan.wings:
		var rects: Array[Rect2]=[Rect2(Vector2(-end,minf(wing.inner_z,wing.outer_z)),Vector2(end*2.0,absf(float(wing.outer_z)-float(wing.inner_z))))]
		if module is ProgramFloor:
			for object: Dictionary in module.furnishings:
				if object.kind!="pool": continue
				var p: Vector3=object.position;var size: Vector3=object.size
				var hole:=Rect2(Vector2(p.x-size.x*.5,p.z-size.z*.5),Vector2(size.x,size.z))
				var remaining: Array[Rect2]=[]
				for rectangle: Rect2 in rects: remaining.append_array(_subtract_rect(rectangle,hole))
				rects=remaining
		for i in rects.size():
			var r: Rect2=rects[i]
			result.append(_volume(placement,String(wing.id)+"-wing-"+str(i),Vector3(r.get_center().x,(high+low)*.5,r.get_center().y),Vector3(r.size.x*.5,(high-low)*.5,r.size.y*.5)))
		for direction: float in [-1.0,1.0]:
			var x: float=direction*(float(g.length_m)*.5-float(g.core_bay_m)*.5)
			var width: float=absf(float(wing.core_z)-float(wing.inner_z))
			result.append(_volume(placement,String(wing.id)+"-core-approach-"+str(direction),Vector3(x,(high+low)*.5,(float(wing.core_z)+float(wing.inner_z))*.5),Vector3(float(g.core_bay_m)*.5,(high-low)*.5,width*.5)))
		# The exact inherited U-stair footprint is wholly outside the atrium
		# boundary. This is the physical stairwell air, never a whole-site AABB.
		if recipe.record.has_upper_floor:
			var rise: float=g.storey_height_m
			result.append(_volume(placement,String(wing.id)+"-physical-U-stairwell",Vector3(-float(g.length_m)*.5+1.8,(rise+2.0+low)*.5,float(wing.core_z)+float(wing.side)*2.60),Vector3(1.60,(rise+2.0-low)*.5,2.60)))
	return result

func _is_stable_floor_structure(body: Variant) -> bool:
	# AnimatableBody3D INHERITS StaticBody3D. A broad `is StaticBody3D`
	# therefore includes the moving SwingDoors and is not a support policy.
	if not body is StaticBody3D or body is AnimatableBody3D or body.get_class()!="StaticBody3D" or body.get_script()!=null: return false
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
	var module: Node=body.get_parent()
	if not module is GuestFloor: return false
	var expected: String="ProgramFloorSolidCollision" if module is ProgramFloor else "GuestFloorSolidCollision"
	return String(body.name)==expected

func _collect_bodies(root: Node,bodies: Array,statics: Array) -> void:
	if root is CollisionObject3D and root.collision_layer!=0:
		bodies.append(root)
		# Moving doors remain in the COMPLETE collision neighbourhood, but may
		# never acquire a persistent source floor/support identity.
		if _is_stable_floor_structure(root): statics.append(root)
	for child: Node in root.get_children(): _collect_bodies(child,bodies,statics)

func _vector_detail(value: Vector3) -> Array:
	return [float(value.x),float(value.y),float(value.z)]

func _transform_detail(value: Transform3D) -> Dictionary:
	return {"origin_xyz":_vector_detail(value.origin),"basis_xyz":[_vector_detail(value.basis.x),_vector_detail(value.basis.y),_vector_detail(value.basis.z)]}

func _shape_detail(owner: Variant) -> Dictionary:
	if not is_instance_valid(owner): return {"owner_class":"FREED_OR_NONE"}
	if not owner is CollisionShape3D: return {"owner_class":owner.get_class() if is_instance_valid(owner) else "NONE"}
	var shape: Shape3D=owner.shape
	var result: Dictionary={"owner_path":String(owner.get_path()) if owner.is_inside_tree() else String(owner.name),"disabled":owner.disabled,"local_transform":_transform_detail(owner.transform),"shape_class":shape.get_class() if shape!=null else "NONE"}
	if shape is BoxShape3D: result["size_xyz"]=_vector_detail(shape.size)
	elif shape is CapsuleShape3D: result.merge({"radius_m":shape.radius,"height_m":shape.height})
	elif shape is CylinderShape3D: result.merge({"radius_m":shape.radius,"height_m":shape.height})
	elif shape is ConvexPolygonShape3D:
		result["point_count"]=shape.points.size()
		var points: Array=[]
		for index in mini(16,shape.points.size()): points.append(_vector_detail(shape.points[index]))
		result["first_local_points_xyz"]=points
	return result

func _body_detail(body: Variant) -> Dictionary:
	if not is_instance_valid(body): return {"exists":false}
	var result: Dictionary={"exists":true,"native_class":body.get_class(),"path":String(body.get_path()) if body.is_inside_tree() else String(body.name),"inside_tree":body.is_inside_tree(),"collision_layer":body.collision_layer,"stable_owned_structure":_is_stable_floor_structure(body),"source_support_meta":body.get_meta(Context.COLLIDER_META,{}),"node_transform":_transform_detail(body.global_transform if body.is_inside_tree() else body.transform)}
	if body.is_inside_tree(): result["node_space_id"]=body.get_world_3d().space.get_id()
	if body is PhysicsBody3D:
		var native_space: RID=PhysicsServer3D.body_get_space(body.get_rid())
		result["native_space_id"]=native_space.get_id()
		if native_space==get_world_3d().space:
			var physical: Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			result["physical_transform"]=_transform_detail(physical)
			result["physical_node_origin_error_m"]=physical.origin.distance_to(body.global_position)
	var owners: Variant=body.get_shape_owners()
	result["shape_owner_count"]=owners.size()
	var shapes: Array=[]
	for index in mini(8,owners.size()): shapes.append(_shape_detail(body.shape_owner_get_owner(owners[index])))
	result["first_shape_owners"]=shapes
	return result

func _native_failure(entry: Dictionary,reason: String,details: Dictionary,capture: bool) -> bool:
	if capture: entry["native_body_failure"]={"reason":reason,"physics_tick":Engine.get_physics_frames(),"origin_revision":_frame.metadata().origin_revision,"details":details}
	return false

func _native_bodies_valid(entry: Dictionary,check_doors: bool = false) -> bool:
	if not is_instance_valid(entry.get("node")) or not entry.node.is_inside_tree() or entry.get("bodies",[]).is_empty(): return _native_failure(entry,"missing_module_or_complete_body_list",{},check_doors)
	var expected: Dictionary=_frame.to_local(entry.placement.anchor_xyz)
	if not expected.ok or entry.node.global_position.distance_to(expected.position)>.002 or not entry.node.global_basis.is_equal_approx(_basis(entry.placement)): return _native_failure(entry,"module_source_pose_mismatch",{"expected":expected,"actual":_transform_detail(entry.node.global_transform)},check_doors)
	var space: RID=get_world_3d().space
	for body: Variant in entry.bodies:
		if not is_instance_valid(body) or not body is CollisionObject3D: return _native_failure(entry,"dead_or_invalid_collision_object",{},check_doors)
		if not body.is_inside_tree() or body.get_world_3d()!=get_world_3d() or body.collision_layer==0: return _native_failure(entry,"body_tree_world_or_layer_mismatch",_body_detail(body),check_doors)
		if body is PhysicsBody3D:
			if PhysicsServer3D.body_get_space(body.get_rid())!=space: return _native_failure(entry,"native_body_space_mismatch",_body_detail(body),check_doors)
			if _is_stable_floor_structure(body) or check_doors:
				var physical: Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
				if not physical.is_equal_approx(body.global_transform): return _native_failure(entry,"native_node_pose_mismatch",_body_detail(body),check_doors)
		elif body is Area3D and PhysicsServer3D.area_get_space(body.get_rid())!=space: return _native_failure(entry,"native_area_space_mismatch",_body_detail(body),check_doors)
	if check_doors:
		for door: Node3D in entry.node.doors.values():
			var desired: float=float(door.base_angle)+(float(door.swing_delta) if door.opened else 0.0)
			if absf(wrapf(float(door.motion_angle)-desired,-PI,PI))>.002: return _native_failure(entry,"restored_door_not_settled",{"door":_body_detail(door),"motion_angle":door.motion_angle,"desired_angle":desired,"opened":door.opened},true)
		entry["native_body_failure"]={}
	return true

func _shared_public_lofts() -> Array:
	var lofts: Array=[];var seen: Dictionary={}
	for marker: Node in get_tree().get_nodes_in_group("mbs_interior_public_nodes"):
		var loft: Node=marker.get_parent()
		if not loft is PublicL1 or seen.has(loft.get_instance_id()) or not loft.is_inside_tree() or loft.get_world_3d()!=get_world_3d() or not bool(loft.get("_built")): continue
		var coordinate: Dictionary=loft.report().get("coordinate_context",{})
		var snapshot: Dictionary=coordinate.get("frame",{})
		if snapshot.get("frame_fingerprint","")!=_frame.metadata().frame_fingerprint or snapshot.get("origin_revision",-1)!=_frame.metadata().origin_revision or snapshot.get("source_origin_xyz",[])!=_frame.metadata().source_origin_xyz: continue
		seen[loft.get_instance_id()]=true;lofts.append(loft)
	return lofts

func _public_surface_covers(loft: Node3D,world_point: Vector3) -> String:
	var p: Vector3=loft.to_local(world_point)
	if absf(p.y)<.10 and p.x>=float((loft.sections[0].center as Vector3).x)-.25 and p.x<=float((loft.sections[-1].center as Vector3).x)+.25:
		var section: Dictionary=loft._section_at(p.x)
		if p.z>=float(loft._edge(section,-1.0).z)-.25 and p.z<=float(loft._edge(section,1.0).z)+.25: return "actual_continuous_public_floor_or_edge"
	var adapters: Array=loft.core_connections.duplicate()
	if not loft.arrival_corridor.is_empty(): adapters.append(loft.arrival_corridor)
	for adapter: Dictionary in adapters:
		var a: Vector3=adapter.adapter_start_local;var b: Vector3=adapter.adapter_end_local
		var adapter_width: float=adapter.get("adapter_width_m",adapter.width_m)
		if absf(p.x-a.x)<=adapter_width*.5+.25 and p.z>=minf(a.z,b.z)-.25 and p.z<=maxf(a.z,b.z)+.25 and p.y>=minf(a.y,b.y)-.10 and p.y<=maxf(a.y,b.y)+.10: return "actual_public_adapter_"+String(adapter.id)
	var entrance: Vector3=loft.portal_local.hotel_entrance
	var sign: float=loft.get("_entrance_sign")
	var entrance_width: float=loft.get("_door_width")
	var outward: float=(p.z-entrance.z)*sign
	if absf(p.y)<.10 and absf(p.x-entrance.x)<=(entrance_width+3.0)*.5+.25 and outward>=-.25 and outward<=8.25: return "actual_legacy_entrance_approach_floor"
	return ""

func _floor_probe_observation(entry: Dictionary,wing: Dictionary,x: float) -> Dictionary:
	var local:=Vector3(x,0,wing.corridor_center_z)
	var at: Vector3=entry.node.to_global(local)
	var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*.15,at-Vector3.UP*.35,1)
	var hit: Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
	var observation: Dictionary={"wing":wing.id,"probe_local_xyz":_vector_detail(local),"probe_world_xyz":_vector_detail(at),"ray_from_xyz":_vector_detail(query.from),"ray_to_xyz":_vector_detail(query.to),"physics_tick":Engine.get_physics_frames(),"mask":1,"excluded_rids":0,"hit":not hit.is_empty(),"valid_owned_floor":false}
	if hit.is_empty(): observation["reason"]="no_native_hit";return observation
	var body: CollisionObject3D=hit.collider
	var owner_id: int=body.shape_find_owner(int(hit.shape))
	var owner: Object=body.shape_owner_get_owner(owner_id)
	var canonical: Dictionary=_frame.to_source_current_live(hit.position)
	var height_error: float=absf((hit.position as Vector3).y-at.y)
	observation.merge({"actual_body_path":String(body.get_path()),"native_class":body.get_class(),"stable_floor_structure":_is_stable_floor_structure(body),"body_in_owned_complete_list":body in entry.bodies,"shape_index":int(hit.shape),"shape_owner":_shape_detail(owner),"contact_world_xyz":_vector_detail(hit.position),"contact_local_xyz":_vector_detail(entry.node.to_local(hit.position)),"contact_source_xyz":canonical.get("source_xyz",[]),"height_error_m":height_error,"normal_xyz":_vector_detail(hit.normal),"source_support_meta":body.get_meta(Context.COLLIDER_META,{})})
	var valid: bool=_is_stable_floor_structure(body) and body in entry.bodies and height_error<=.015 and (hit.normal as Vector3).y>=.95 and canonical.ok
	observation["valid_owned_floor"]=valid
	observation["reason"]="owned_structure_supported" if valid else "wrong_owner_structure_height_or_normal"
	return observation

func _floor_probes_valid(entry: Dictionary,recipe: Dictionary) -> bool:
	var adapted: bool=not recipe.record.geometry.get("atrium_core_openings",[]).is_empty() or not recipe.record.geometry.get("public_arrival_corridor",{}).is_empty()
	var lofts: Array=_shared_public_lofts() if adapted else []
	var observations: Array=[];var legacy_centres: Array=[];var selections: Array=[]
	var corridor_half_run: float=float(recipe.record.geometry.length_m)*.5-float(recipe.record.geometry.core_bay_m)
	var complete:=true
	for wing: Dictionary in recipe.plan.wings:
		# Retain the OLD fixed-centre observation even when a legitimate shared
		# public overlay occupies it. It never substitutes for our own proof.
		legacy_centres.append(_floor_probe_observation(entry,wing,0.0))
		var xs: Array[float]=[0.0]
		if adapted:
			xs.clear()
			for fraction: float in [-.25,-.5,.25,.5,-.75,.75]:
				var candidate_x: float=corridor_half_run*fraction
				var candidate_world: Vector3=entry.node.to_global(Vector3(candidate_x,0,wing.corridor_center_z))
				var conflict:=""
				for loft: Node3D in lofts:
					conflict=_public_surface_covers(loft,candidate_world)
					if not conflict.is_empty(): break
				selections.append({"wing":wing.id,"candidate_x_m":candidate_x,"known_public_overlap":conflict,"chosen":conflict.is_empty() and xs.size()<2})
				if conflict.is_empty() and xs.size()<2: xs.append(candidate_x)
			if lofts.is_empty() or xs.size()!=2: complete=false
		for x: float in xs:
			var observation:=_floor_probe_observation(entry,wing,x)
			observations.append(observation)
			if not observation.valid_owned_floor: complete=false
	entry["native_floor_probe_diagnostics"]={"adapted_l1":adapted,"shared_public_lofts":lofts.size(),"legacy_centre_observations":legacy_centres,"deterministic_geometry_selections":selections,"required_owned_probe_count":4 if adapted else 2,"actual_owned_probes":observations,"complete":complete,"reason":"all_owned_structure_probes_supported" if complete else ("missing_actual_shared_public_geometry" if adapted and lofts.is_empty() else "owned_probe_plan_or_native_support_failed"),"physics_tick":Engine.get_physics_frames()}
	if not entry.get("probe_plan_logged",false):
		entry["probe_plan_logged"]=true
		print("[mbs-floor-stack] NATIVE_FLOOR_PROBE_PLAN ",JSON.stringify(entry.native_floor_probe_diagnostics))
	if complete:
		entry["native_floor_probes"]=observations
	return complete and observations.size()==(4 if adapted else 2)

func _local_committed(id: String) -> bool:
	if not _configured or not _entries.has(id): return false
	var entry: Dictionary=_entries[id]
	if entry.get("status","")!="committed" or int(entry.get("origin_revision",-1))!=int(_frame.metadata().origin_revision) or String(entry.get("collision_generation","")).is_empty() or not _native_bodies_valid(entry): return false
	for support: Dictionary in entry.supports:
		var stamp: Dictionary=support.body.get_meta(Context.COLLIDER_META,{})
		if stamp.get("residency_token","")!=entry.collision_generation or stamp.get("feature_id","")!=FEATURE or stamp.get("floor_id","")!=id: return false
	return true

func floor_ready(id: String) -> bool:
	id=Inventory.normalize_floor_id(id)
	if not _local_committed(id): return false
	for neighbor: String in adjacent_floor_ids(id):
		if not _local_committed(neighbor): return false
	return true

func ready_for_floor(id: String) -> Dictionary:
	# Exact synchronous cabin callback shape. Root alone adds shaft/cabin proof.
	id=Inventory.normalize_floor_id(id)
	return {"ready":floor_ready(id),"floor_id":id,"collision_generation":String(_entries.get(id,{}).get("collision_generation","")),"travel_ready":false}

func get_floor(id: String) -> Node3D:
	id=Inventory.normalize_floor_id(id)
	return _entries[id].node if _local_committed(id) else null

func floor_state(id: String) -> Dictionary:
	id=Inventory.normalize_floor_id(id)
	if not _records.has(id): return _not_ready(id,"unknown_floor","Not an inventory floor")
	var entry: Dictionary=_entries.get(id,{})
	var result:=ready_for_floor(id)
	result.merge({"status":entry.get("status","unloaded"),"local_collision_committed":_local_committed(id),"required_neighbors":adjacent_floor_ids(id),"source_id":entry.get("placement",{}).get("source_id",""),"canonical_anchor_xyz":entry.get("placement",{}).get("anchor_xyz",[]).duplicate(),"origin_revision":entry.get("origin_revision",-1),"region_id":entry.get("region_id",""),"body_count":entry.get("bodies",[]).size(),"static_support_count":entry.get("supports",[]).size(),"native_floor_probes":entry.get("native_floor_probes",[]).duplicate(true),"saved_doors":_saved_doors.get(id,{}).duplicate(true),"error":entry.get("error","")},true)
	result["native_commit_diagnostics"]={"body_pose_failure":entry.get("native_body_failure",{}).duplicate(true),"floor_probes":entry.get("native_floor_probe_diagnostics",{}).duplicate(true)}
	return result

func pin_floor(id: String,owner: String) -> bool:
	id=Inventory.normalize_floor_id(id)
	if not _configured or not _records.has(id) or owner.is_empty() or owner.length()>128: return false
	if not _pins.has(id) and _pins.size()>=_max_active: return false
	if not _pins.has(id): _pins[id]={}
	_pins[id][owner]=true;return true

func unpin_floor(id: String,owner: String) -> bool:
	id=Inventory.normalize_floor_id(id)
	if not _pins.has(id) or not _pins[id].has(owner): return false
	_pins[id].erase(owner)
	if _pins[id].is_empty(): _pins.erase(id)
	return true

func set_actor_floor(actor: Node3D,id: String) -> bool:
	id=Inventory.normalize_floor_id(id)
	if not _configured or not is_instance_valid(actor) or not actor.is_inside_tree() or actor.get_world_3d()!=get_world_3d() or not _records.has(id): return false
	if not actor is Player and not actor is Helicopter: return false
	if actor.get("source_world_runtime")!=_runtime: return false
	_actor_claims[actor.get_instance_id()]={"actor":weakref(actor),"floor_id":id};return true

func clear_actor_floor(actor: Node3D) -> void:
	if is_instance_valid(actor): _actor_claims.erase(actor.get_instance_id())

func _bound_actors() -> Array:
	var result: Array=[];var seen: Dictionary={}
	for group: String in ["player","helicopters"]:
		for actor: Node in get_tree().get_nodes_in_group(group):
			if actor is Node3D and not seen.has(actor.get_instance_id()) and actor.get("source_world_runtime")==_runtime and actor.is_inside_tree() and actor.get_world_3d()==get_world_3d():
				seen[actor.get_instance_id()]=true;result.append(actor)
	return result

func _actor_floor(actor: Node3D) -> String:
	var point: Dictionary=_frame.to_source_current_live(actor.global_position)
	if not point.ok: return ""
	var best:="";var distance:=INF
	var pad:=12.0 if actor is Helicopter else 1.50
	var vertical:=25.0 if actor is Helicopter else 2.0
	for id: String in _records:
		var record: Dictionary=_records[id]
		var placement: Dictionary={}
		var g: Dictionary={}
		if _entries.has(id) and _entries[id].has("placement"):
			placement=_entries[id].placement;g=_entries[id].record.geometry
		else:
			# Cheap anchor-only detection; do not construct/validate 189 floors
			# each physics tick or silently create an unmapped resort footprint.
			if not record.has("tower"): continue
			for source: Dictionary in Reference.DATA.towers:
				if source.tower==record.tower:
					placement={"anchor_xyz":[source.centroid_world_xz[0],_base_elevation+float(record.elevation_m),source.centroid_world_xz[1]],"axis_x_xyz":[Reference.DATA.axis_south_xz[0],0.0,Reference.DATA.axis_south_xz[1]],"axis_z_xyz":[Reference.DATA.axis_bayward_xz[0],0.0,Reference.DATA.axis_bayward_xz[1]]}
			g=record.geometry
		if placement.is_empty(): continue
		var delta_x: float=float(point.source_xyz[0])-float(placement.anchor_xyz[0])
		var delta_z: float=float(point.source_xyz[2])-float(placement.anchor_xyz[2])
		var x: float=delta_x*float(placement.axis_x_xyz[0])+delta_z*float(placement.axis_x_xyz[2])
		var z: float=delta_x*float(placement.axis_z_xyz[0])+delta_z*float(placement.axis_z_xyz[2])
		var dy: float=absf(float(point.source_xyz[1])-float(placement.anchor_xyz[1]))
		if absf(x)<=float(g.length_m)*.5+pad and absf(z)<=float(g.cross_m)*.5+pad and dy<=vertical and dy<distance: best=id;distance=dy
	return best

func _protected_floors() -> Dictionary:
	var guarded: Dictionary={}
	for id: String in _pins:
		guarded[id]="explicit_pin"
		for neighbor: String in adjacent_floor_ids(id): guarded[neighbor]="pinned_neighbor"
	for key: Variant in _actor_claims.keys():
		var actor: Variant=_actor_claims[key].actor.get_ref()
		if not is_instance_valid(actor): _actor_claims.erase(key);continue
		var id: String=_actor_claims[key].floor_id
		guarded[id]="explicit_actor_claim"
		for neighbor: String in adjacent_floor_ids(id): guarded[neighbor]="claimed_neighbor"
	for actor: Node3D in _bound_actors():
		var id:=_actor_floor(actor)
		if id.is_empty(): continue
		guarded[id]="native_source_actor_or_aircraft"
		for neighbor: String in adjacent_floor_ids(id): guarded[neighbor]="occupied_neighbor"
	return guarded

func _active_count() -> int:
	var count:=0
	for entry: Dictionary in _entries.values():
		if is_instance_valid(entry.get("node")): count+=1
	return count

func _transition_live(module: Node3D) -> bool:
	for door: Node3D in module.doors.values():
		if not String(door.transition_kind).is_empty() and (bool(door.opened) or bool(door.ready_to_open)): return true
	return false

func _retire_one(id: String) -> Dictionary:
	if not _entries.has(id) or not is_instance_valid(_entries[id].get("node")): return {"ok":true,"floor_id":id,"already_unloaded":true}
	var protection:=_protected_floors()
	if protection.has(id): return {"ok":false,"floor_id":id,"status":"protected","error":protection[id]}
	var entry: Dictionary=_entries[id]
	if entry.get("status","") in ["building","waiting_physics","retiring"]: return {"ok":false,"floor_id":id,"status":"busy","error":"Owned floor lifecycle is in progress"}
	if int(entry.get("origin_revision",-1))!=int(_frame.metadata().origin_revision) and not _bound_actors().is_empty(): return {"ok":false,"floor_id":id,"status":"pending_root_origin_transaction","error":"Do not infer occupancy from mixed origin epochs"}
	# Root's cabin adapter can unbind/close its landing interlocks only after
	# occupancy/pins are checked. An invalid callback always holds closed.
	if _unload_guard_set:
		if not _unload_guard.is_valid(): return {"ok":false,"floor_id":id,"status":"guard_unavailable","error":"Explicit cabin unload guard is unavailable"}
		var allowed: Variant=_unload_guard.call(id)
		if typeof(allowed)!=TYPE_BOOL or not allowed: return {"ok":false,"floor_id":id,"status":"cabin_guard","error":"Root cabin/transition guard refused retirement"}
	if _transition_live(entry.node): return {"ok":false,"floor_id":id,"status":"active_transition","error":"Landing must be closed/interlocked before floor retirement"}
	_saved_doors[id]=entry.node.serialize_state().duplicate(true)
	entry.status="retiring"
	_runtime.retire_region(entry.region_id)
	entry.collision_generation=""
	# Observers can verify that actual body stamps/region are already retired
	# while the owned node is still alive. Destruction always happens afterward.
	floor_retired.emit(id,entry.region_id)
	entry.node.queue_free()
	for i in 3: await get_tree().physics_frame
	entry.node=null;entry.bodies=[];entry.supports=[];entry.status="unloaded"
	floor_unloaded.emit(id)
	return {"ok":true,"floor_id":id,"retired_before_free":true,"doors_retained":true}

func unload_floor(id: String) -> Dictionary:
	id=Inventory.normalize_floor_id(id)
	if not _configured or not _records.has(id): return {"ok":false,"floor_id":id,"error":"Unknown or unconfigured floor"}
	if _busy: return {"ok":false,"floor_id":id,"status":"busy","error":"One floor lifecycle mutation at a time"}
	_busy=true
	var result: Dictionary=await _retire_one(id)
	_busy=false;return result

func _evict_for(needed: Array[String]) -> bool:
	var new_count:=0
	for id: String in needed:
		if not _entries.has(id) or not is_instance_valid(_entries[id].get("node")): new_count+=1
	var remove_count:=maxi(0,_active_count()+new_count-_max_active)
	if remove_count==0: return true
	var candidates: Array[String]=[]
	for id: String in _entries:
		if not id in needed and is_instance_valid(_entries[id].get("node")) and _entries[id].get("status","")=="committed": candidates.append(id)
	candidates.sort_custom(func(a: String,b: String): return int(_entries[a].get("last_used",0))<int(_entries[b].get("last_used",0)))
	for id: String in candidates:
		var result: Dictionary=await _retire_one(id)
		if result.ok: remove_count-=1
		if remove_count<=0: return true
	return false

func _discard_failed(id: String,error: String) -> void:
	var entry: Dictionary=_entries[id]
	entry.error=error;entry.status="failed"
	if not String(entry.get("region_id","")).is_empty(): _runtime.retire_region(entry.region_id)
	entry.collision_generation=""
	if _protected_floors().has(id): entry.status="failed_retained_protected";return
	if is_instance_valid(entry.get("node")):
		entry.node.queue_free()
		for i in 3: await get_tree().physics_frame
	entry.node=null;entry.bodies=[];entry.supports=[]

func _load_one(id: String,recipe: Dictionary) -> Dictionary:
	if _local_committed(id): _entries[id].last_used=Time.get_ticks_msec();return {"ready":true,"floor_id":id}
	if int(recipe.projected.origin_revision)!=int(_frame.metadata().origin_revision): return _not_ready(id,"pending_root_origin_transaction","A preflight projection from another origin epoch cannot create native geometry")
	if _entries.has(id) and is_instance_valid(_entries[id].get("node")): return _not_ready(id,"pending_root_retirement","An uncommitted/stale retained floor cannot be overwritten")
	var module: Node3D=GuestFloor.new() if recipe.record.factory=="guest_floor_v1" else ProgramFloor.new()
	module.name="SourceFloor_"+id.replace("-","_")
	add_child(module)
	# Only this already origin-subtracted local projection enters a transform.
	module.global_transform=Transform3D(_basis(recipe.placement),recipe.projected.position)
	_serial+=1
	var region_id: String="mbs-floor-stack/"+str(get_instance_id())+"/"+id+"/"+str(_serial)
	var entry: Dictionary={"node":module,"record":recipe.record.duplicate(true),"placement":recipe.placement.duplicate(true),"status":"building","origin_revision":_frame.metadata().origin_revision,"region_id":region_id,"collision_generation":"","bodies":[],"supports":[],"last_used":Time.get_ticks_msec(),"error":""}
	_entries[id]=entry
	var built: Dictionary=module.build(recipe.record)
	if not built.get("built",false):
		await _discard_failed(id,String(built.get("error","Factory rejected copied record")))
		return _not_ready(id,"factory_failed",entry.error)
	if _saved_doors.has(id) and not module.restore_state(_saved_doors[id]):
		await _discard_failed(id,"Saved door identity was refused")
		return _not_ready(id,"door_state_failed",entry.error)
	var statics: Array=[]
	_collect_bodies(module,entry.bodies,statics)
	if statics.is_empty() or entry.bodies.size()>1024:
		await _discard_failed(id,"No stable physical floor or collision-body budget exceeded")
		return _not_ready(id,"collision_budget_failed",entry.error)
	var support_ids: Array[String]=[]
	for body: StaticBody3D in statics:
		var stable: String="static/"+String(module.get_path_to(body))
		support_ids.append(stable)
		entry.supports.append({"body":body,"feature_id":FEATURE,"floor_id":id,"support_id":stable})
	var volumes:=_volumes(recipe,module)
	# The root's explicit versioned manifest works in source AND compiled PCKs;
	# source-code introspection can be stripped and must not define save identity.
	var digest: String=_sha(JSON.stringify({"schema":"source_floor_recipe_v1","record":recipe.record,"placement":recipe.placement,"volumes":volumes,"datum":_datum_provenance,"base_elevation_m":_base_elevation,"declared_geometry_manifest_sha256":_context.metadata().geometry_manifest_sha256},"",true,true))
	var provenance: String=String(recipe.placement.provenance)+"; base datum: "+_datum_provenance
	if provenance.length()>256: provenance=String(recipe.placement.provenance).left(90)+"; datum "+_datum_provenance.left(70)+" #"+_sha(provenance)
	var definition: Dictionary={"feature_id":FEATURE,"floor_id":id,"geometry_sha256":digest,"support_ids":support_ids,"volumes":volumes,"provenance":provenance}
	var previous: Dictionary=_context.floor_record(FEATURE,id)
	if previous.ok:
		if previous.floor.geometry_sha256!=digest or previous.floor.support_ids!=support_ids:
			await _discard_failed(id,"Immutable source floor identity changed; new context required")
			return _not_ready(id,"requires_new_context",entry.error)
	elif not _context.register_floor(definition):
		await _discard_failed(id,String(_context.last_error))
		return _not_ready(id,"floor_registration_failed",entry.error)
	_definitions[id]=definition
	entry.status="waiting_physics"
	var committed:=false
	var deadline:=Time.get_ticks_msec()+8000
	for tick in 180:
		await get_tree().physics_frame
		if tick<2: continue
		if int(entry.origin_revision)!=int(_frame.metadata().origin_revision): break
		if _native_bodies_valid(entry,true) and _floor_probes_valid(entry,recipe): committed=true;break
		if Time.get_ticks_msec()>deadline: break
	if not committed:
		var diagnostics: Dictionary={"floor_id":id,"entry_origin_revision":entry.origin_revision,"current_origin_revision":_frame.metadata().origin_revision,"body_pose_failure":entry.get("native_body_failure",{}).duplicate(true),"floor_probe_failure":entry.get("native_floor_probe_diagnostics",{}).duplicate(true),"body_count":entry.bodies.size(),"static_support_count":entry.supports.size()}
		print("[mbs-floor-stack] NATIVE_COMMIT_FAILURE ",JSON.stringify(diagnostics))
		await _discard_failed(id,"Actual complete collision/door poses did not commit in the bounded current epoch")
		return _not_ready(id,"physics_commit_pending",entry.error,{"native_commit_diagnostics":diagnostics})
	var g: Dictionary=recipe.record.geometry
	var x: Array=recipe.placement.axis_x_xyz;var z: Array=recipe.placement.axis_z_xyz;var anchor: Array=recipe.placement.anchor_xyz
	var extent_x: float=absf(float(x[0]))*float(g.length_m)*.5+absf(float(z[0]))*float(g.cross_m)*.5+2.5
	var extent_z: float=absf(float(x[2]))*float(g.length_m)*.5+absf(float(z[2]))*float(g.cross_m)*.5+2.5
	# Region bounds describe this complete owned floor neighbourhood; they are
	# never used as a dry volume or claimed national/city collision coverage.
	var minimum: Array=[float(anchor[0])-extent_x,float(anchor[1])-4.0,float(anchor[2])-extent_z]
	var maximum: Array=[float(anchor[0])+extent_x,float(anchor[1])+maxf(float(g.clear_height_m),float(g.storey_height_m))+3.0,float(anchor[2])+extent_z]
	if not _runtime.commit_region(region_id,minimum,maximum,entry.bodies,entry.supports):
		await _discard_failed(id,"Runtime refused actual collision region/support stamps")
		return _not_ready(id,"region_commit_failed",entry.error)
	await get_tree().physics_frame
	if int(entry.origin_revision)!=int(_frame.metadata().origin_revision) or not _native_bodies_valid(entry):
		await _discard_failed(id,"Collision epoch/owned bodies changed during final native commit")
		return _not_ready(id,"commit_invalidated",entry.error)
	var stamp: Dictionary=statics[0].get_meta(Context.COLLIDER_META,{})
	if String(stamp.get("residency_token","")).is_empty():
		await _discard_failed(id,"Actual native support stamp missing")
		return _not_ready(id,"support_stamp_failed",entry.error)
	entry.collision_generation=String(stamp.residency_token);entry.status="committed"
	floor_committed.emit(id,entry.collision_generation)
	return {"ready":true,"floor_id":id,"collision_generation":entry.collision_generation,"travel_ready":false}

func ensure_floor(id: String) -> Dictionary:
	id=Inventory.normalize_floor_id(id)
	if not _configured: return _not_ready(id,"unconfigured","Configure common source objects and explicit base datum first")
	if not _records.has(id): return _not_ready(id,"unknown_floor","Floor is not in inventory")
	if _pending>=_max_pending: return _not_ready(id,"pending_budget","Bounded request queue is full")
	_pending+=1
	var wait_deadline:=Time.get_ticks_msec()+15000
	while _busy:
		if Time.get_ticks_msec()>wait_deadline:
			_pending-=1;return _not_ready(id,"pending_busy","Bounded lifecycle wait elapsed")
		await get_tree().physics_frame
	_busy=true
	var needed: Array[String]=adjacent_floor_ids(id)
	if not needed.has(id): needed.append(id)
	var recipes: Dictionary={}
	for required: String in needed:
		var recipe:=_recipe(required)
		if not recipe.ok:
			_busy=false;_pending-=1
			var failure:=_not_ready(id,recipe.status,recipe.error,recipe)
			failure.floor_id=id;failure["blocked_neighbor_or_floor"]=required
			floor_load_failed.emit(id,failure.status,failure.error)
			return failure
		recipes[required]=recipe
	if not await _evict_for(needed):
		_busy=false;_pending-=1;return _not_ready(id,"protected_capacity","Active floor cap cannot evict an occupied/pinned neighbour or transition")
	for required: String in needed:
		var result: Dictionary=await _load_one(required,recipes[required])
		if not result.get("ready",false):
			_busy=false;_pending-=1
			result["requested_floor_id"]=id;floor_load_failed.emit(id,String(result.status),String(result.error));return result
	_busy=false;_pending-=1
	var ready:=floor_state(id)
	ready["status"]="ready" if ready.ready else "neighbor_commit_pending"
	return ready

func _physics_process(_delta: float) -> void:
	if not _configured or not _auto_stream or _auto_pending or _busy or Engine.get_physics_frames()%15!=0: return
	for actor: Node3D in _bound_actors():
		var id:=_actor_floor(actor)
		if id.is_empty() or floor_ready(id) or Time.get_ticks_msec()<int(_auto_retry_after.get(id,0)): continue
		_auto_pending=true;_auto_load.call_deferred(id);return

func _auto_load(id: String) -> void:
	var result: Dictionary=await ensure_floor(id)
	if not result.get("ready",false): _auto_retry_after[id]=Time.get_ticks_msec()+1500
	_auto_pending=false

func serialize_state() -> Dictionary:
	var saved:=_saved_doors.duplicate(true)
	for id: String in _entries:
		if is_instance_valid(_entries[id].get("node")) and _entries[id].get("status","")=="committed": saved[id]=_entries[id].node.serialize_state().duplicate(true)
	return {"schema":SCHEMA,"inventory_sha256":_inventory_sha,"floor_doors":saved}

func _door_belongs_to_floor(id: String,door: String) -> bool:
	# Guest inventory uses R-T2-L24-01, not the floor-ID prefix. Preserve its
	# exact source unit namespace and only the actual derived private doors.
	if door.begins_with(id+"-"): return not door.ends_with("-guest_lift") and not door.ends_with("-service_lift")
	for unit: Dictionary in _records[id].get("units",[]):
		var unit_id:=String(unit.id)
		if door==unit_id or door==unit_id+"-bath": return true
		if bool(unit.get("is_suite",false)):
			for index in int(unit.get("bedrooms",1)):
				if door==unit_id+"-bedroom-"+str(index+1): return true
	return false

func restore_state(data: Dictionary) -> bool:
	# Pure source-ID door data only. Root owns save files/pose/context restores.
	if not _configured or _busy or _active_count()!=0 or data.get("schema","")!=SCHEMA or data.get("inventory_sha256","")!=_inventory_sha or not data.get("floor_doors") is Dictionary or data.floor_doors.size()>_records.size(): return false
	var accepted: Dictionary={}
	for id: Variant in data.floor_doors:
		if not id is String or not _records.has(id): return false
		var state: Variant=data.floor_doors[id]
		if not state is Dictionary or state.get("floor_id","")!=id or not state.get("room_doors") is Dictionary or state.room_doors.size()>512: return false
		if state.has("current_private_asbuilt_verified") and (typeof(state.current_private_asbuilt_verified)!=TYPE_BOOL or state.current_private_asbuilt_verified): return false
		for door: Variant in state.room_doors:
			if not door is String or door.length()>256 or typeof(state.room_doors[door])!=TYPE_BOOL or not _door_belongs_to_floor(id,door): return false
		accepted[id]=state.duplicate(true)
	_saved_doors=accepted;return true

func report() -> Dictionary:
	var ready: Array[String]=[];var committed: Array[String]=[]
	for id: String in _entries:
		if _local_committed(id): committed.append(id)
		if floor_ready(id): ready.append(id)
	return {"configured":_configured,"active_floor_count":_active_count(),"maximum_active_floors":_max_active,"pending_requests":_pending,"ready_floors":ready,"locally_committed_floors":committed,"registered_floor_count":_definitions.size(),"base_elevation_m":_base_elevation,"datum_provenance":_datum_provenance,"common_source_frame":true,"origin_commits_performed":0,"actor_pose_mutations":0,"shaft_travel_ready":false,"full_building_completed":false,"source_city_complete":false}

func _exit_tree() -> void:
	if not is_instance_valid(_runtime): return
	for entry: Dictionary in _entries.values():
		if not String(entry.get("region_id","")).is_empty(): _runtime.retire_region(entry.region_id)
