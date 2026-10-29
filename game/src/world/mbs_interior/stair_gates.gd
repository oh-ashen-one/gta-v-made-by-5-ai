extends Node3D
## Native stair fire-door interlock. Local reconstructed geometry only.
## Root owns floor loading/pins/context registration and physical retirement.
signal floor_requested(floor_id:String)
signal protection_changed(floor_id:String,protected:bool)
signal gate_state_changed(gate_id:String,state:String)
const GuestFloor=preload("res://src/world/mbs_interior/guest_floor.gd")
const Inventory=preload("res://src/world/mbs_interior/inventory.gd")
const Kit=preload("res://src/world/downtown/landmarks/kit.gd")
const Looks=preload("res://src/world/downtown/landmarks/looks.gd")
const GEOMETRY_VERSION="mbs-stair-fire-door-v4-destination-height"
const WIDTH=1.30
const HEIGHT=2.35
const LEAF_THICKNESS=.075
const FRAME_THICKNESS=.15
const LANDING_WIDTH=3.2
const GATE_EDGE_SETBACK=.45
const OCCUPANCY_MASK=2|4|8
const MAX_BOUND_FLOORS=32

class StairDoor extends GuestFloor.SwingDoor:
	func _refresh_prompt()->void:
		prompt_text="[E] Close stair door" if opened else "[E] Open stair door"
	func _physics_process(delta:float)->void:
		if not is_instance_valid(coordinator):return
		if not coordinator._gate_motion_allowed(door_id,delta):return
		super._physics_process(delta)

var doors:Dictionary={}
var _floors:Dictionary={}
var _gates:Dictionary={}
var _built:=true # Production SwingDoor.can_interact adapter contract.
var _protected:Array[String]=[]
var _refresh_physics_tick:=-1
var _refresh_process_frame:=-1
var _retirement_prepared:Dictionary={}

func _unit_upright(node:Node3D)->bool:
	return node.is_inside_tree() and node.global_basis.get_scale().is_equal_approx(Vector3.ONE) and node.global_basis.y.is_equal_approx(Vector3.UP) and node.global_basis.is_equal_approx(node.global_basis.orthonormalized())

func _read(provider:Callable,id:String)->Dictionary:
	if not provider.is_valid():return {"valid":false,"ready":false,"reason":"invalid_provider"}
	var raw:Variant=provider.call(id)
	if not raw is Dictionary:return {"valid":false,"ready":false,"reason":"invalid_readiness_type"}
	if raw.get("floor_id","")!=id or typeof(raw.get("ready"))!=TYPE_BOOL or not raw.get("collision_generation","") is String:
		return {"valid":false,"ready":false,"reason":"wrong_floor_or_readiness_schema"}
	var generation:String=raw.collision_generation
	var result:Dictionary={"valid":not generation.is_empty(),"ready":bool(raw.ready) and not generation.is_empty(),"generation":generation,"reason":"ready" if bool(raw.ready) and not generation.is_empty() else "receiving_floor_not_ready"}
	if raw.has("receiving_door_height_m") or raw.has("receiving_clear_height_m"):
		for field:String in ["receiving_door_height_m","receiving_clear_height_m"]:
			if not typeof(raw.get(field)) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(raw[field])):return {"valid":false,"ready":false,"reason":"invalid_receiving_geometry"}
		result["receiving_door_height_m"]=float(raw.receiving_door_height_m);result["receiving_clear_height_m"]=float(raw.receiving_clear_height_m)
	return result

func bind_floor(module:Node3D,id:String,upper_id:String,provider:Callable,receiving_record:Dictionary={})->Dictionary:
	# Complete validation before creating any nodes or changing bound state.
	if not is_inside_tree() or not is_instance_valid(module) or not _unit_upright(module) or module.get_world_3d()!=get_world_3d() or not provider.is_valid():
		return {"bound":false,"error":"In-tree upright unit-scale module and valid exact-floor provider required"}
	if _floors.has(id):return {"bound":false,"error":"Floor already bound"}
	if _floors.size()>=MAX_BOUND_FLOORS:return {"bound":false,"error":"Bound streamed-floor gate budget exceeded"}
	var record:Variant=module.get("floor_record")
	var physical_portals:Variant=module.get("portals")
	if not record is Dictionary or record.get("id","")!=id or not physical_portals is Array or not bool(module.get("_built")):
		return {"bound":false,"error":"Exact completed factory floor identity/portals required"}
	var upper:Dictionary=Inventory.floor_record(upper_id) if receiving_record.is_empty() else receiving_record.duplicate(true)
	if upper.get("id","")!=upper_id:return {"bound":false,"error":"Exact receiving record identity required"}
	var g:Dictionary=record.get("geometry",{})
	if upper.is_empty() or upper.get("tower")!=record.get("tower") or upper_id==id:
		return {"bound":false,"error":"Actual same-tower upper inventory floor required"}
	for key:String in ["length_m","cross_m","storey_height_m","clear_height_m"]:
		if not g.has(key) or not is_finite(float(g[key])):return {"bound":false,"error":"Missing bounded factory geometry"}
	if float(g.length_m)<30 or float(g.length_m)>120 or float(g.cross_m)<20 or float(g.cross_m)>100 or float(g.storey_height_m)<2.5 or float(g.storey_height_m)>6.0:
		return {"bound":false,"error":"Unsupported stair geometry/member domain"}
	var rise:float=float(g.storey_height_m)
	if not is_equal_approx(float(upper.elevation_m)-float(record.elevation_m),rise):
		return {"bound":false,"error":"Receiving inventory elevation does not match actual stair rise"}
	if rise<2.9 and (g.get("partial_mezzanine_schema","")!="mbs_partial_mezzanine_v1" or not record.get("level","") in ["B2","B2M"]):return {"bound":false,"error":"Low stair rise needs explicit partial service factory"}
	var receiving_g:Dictionary=upper.get("geometry",{})
	var raw_height:Variant=receiving_g.get("core_door_height_m",HEIGHT)
	var raw_clear:Variant=receiving_g.get("clear_height_m",0.0)
	if not typeof(raw_height) in [TYPE_INT,TYPE_FLOAT] or not typeof(raw_clear) in [TYPE_INT,TYPE_FLOAT]:return {"bound":false,"error":"Typed numeric receiving geometry required"}
	var receiving_height:float=raw_height
	var receiving_clear:float=raw_clear
	var low_receiver:bool=absf(receiving_height-2.10)<.001
	var header_height:float=.10 if low_receiver else .20
	if not is_finite(receiving_height) or not is_finite(receiving_clear) or (not low_receiver and absf(receiving_height-HEIGHT)>.001) or receiving_clear<receiving_height+header_height+.04:return {"bound":false,"error":"Receiving door/header cannot fit declared actual headroom"}
	if low_receiver and receiving_g.get("partial_mezzanine_schema","")!="mbs_partial_mezzanine_v1":return {"bound":false,"error":"Low receiving doorway requires explicit partial factory contract"}
	var lower_proof:=_read(provider,id)
	if not lower_proof.valid:return {"bound":false,"error":"Bound floor needs exact current collision generation"}
	var plans:Array[Dictionary]=[]
	var seen:Dictionary={}
	for portal:Dictionary in physical_portals:
		if portal.get("kind")!="stair":continue
		var wing:String=portal.get("wing","")
		if not wing in ["east","west"] or seen.has(wing):return {"bound":false,"error":"Exactly one actual stair per physical wing"}
		seen[wing]=true
		var side:float=-1.0 if wing=="east" else 1.0
		var route:Variant=portal.get("walk_route",[])
		if not route is Array or route.size()<9 or not portal.get("upper") is Vector3 or not portal.get("lower") is Vector3:return {"bound":false,"error":"Actual U-stair landing route required"}
		var landing:Vector3=route[-1]
		var endpoint:Vector3=route[-2]
		var past_edge:Vector3=portal.upper
		var core:float=side*(float(g.cross_m)*.5-5.6)
		var expected_x:float=-float(g.length_m)*.5+1.80+.78
		if absf(landing.x-expected_x)>.001 or absf(endpoint.x-expected_x)>.001 or absf(landing.y-rise)>.001 or absf(endpoint.y-rise)>.001 or absf(landing.z-(core+side*.6))>.001 or absf(endpoint.z-(core+side*1.2))>.001 or absf(past_edge.z-(core-side*.6))>.001:
			return {"bound":false,"error":"Factory stair landing changed: explicit integration revision needed"}
		var lower_entry:Vector3=portal.lower
		var lower_landing:Vector3=route[1]
		if lower_entry.distance_to(Vector3(expected_x-1.56,0,core-side*.60))>.001 or lower_landing.distance_to(Vector3(expected_x-1.56,0,core+side*.60))>.001:
			return {"bound":false,"error":"Factory lower-flight entry changed: explicit integration revision needed"}
		var gate_id:=id+"-"+wing+"-stair-fire-door"
		# At every intermediate storey the previous flight's upper landing and
		# the next flight's lower landing share this 3.2m cross-landing. A solid
		# pier over the lower-flight lane seals that real next-floor entrance.
		# Both lanes therefore have independent native interlocked leaves; the
		# existing upper-return ID/position is retained for current integrations.
		for lane:String in ["upper_return","lower_departure"]:
			var center_x:float=expected_x if lane=="upper_return" else expected_x-1.56
			var leaf_id:String=gate_id if lane=="upper_return" else id+"-"+wing+"-stair-lower-entry-door"
			plans.append({"id":leaf_id,"wing":wing,"lane":lane,"side":side,"x":center_x,"landing_x":expected_x-.78,"edge_z":core,"plane_z":core+side*GATE_EDGE_SETBACK,"rise":rise,"lower_id":id,"upper_id":upper_id,"lower_generation":lower_proof.generation,"base_angle":0.0,"hinge":Vector3(center_x-WIDTH*.5,rise,core+side*GATE_EDGE_SETBACK),"build_landing_frame":lane=="upper_return","height":receiving_height,"clear_height":receiving_clear,"header_height":header_height,"requires_receiving_geometry":low_receiver})
	if plans.size()!=4:return {"bound":false,"error":"Both actual U-stair lanes in both wings are required"}
	var holder:=Node3D.new()
	holder.name="OwnedStairFireDoors"
	module.add_child(holder)
	var entry:Dictionary={"module":module,"holder":holder,"provider":provider,"lower_generation":lower_proof.generation,"upper_id":upper_id,"gate_ids":[]}
	_floors[id]=entry
	_retirement_prepared.erase(id)
	for plan:Dictionary in plans:
		_build_gate(holder,plan)
		entry.gate_ids.append(plan.id)
	refresh_now()
	return {"bound":true,"floor_id":id,"upper_id":upper_id,"gate_ids":entry.gate_ids.duplicate(),"geometry_version":GEOMETRY_VERSION,"actor_pose_writes":0,"context_registered_by_component":false}

func _box(kit,label:String,mat:Material,center:Vector3,size:Vector3)->void:
	kit.box(mat,center,size,Basis.IDENTITY,false)
	kit.col_box(size,center)
	kit.body.get_child(kit.body.get_child_count()-1).name=label.validate_node_name()

func _build_gate(holder:Node3D,p:Dictionary)->void:
	var metal:=Looks.get_mat("steel_satin")
	if bool(p.build_landing_frame):
		var kit=Kit.new(holder,"StairFireDoorFrames_"+String(p.wing))
		var mat:=Looks.get_mat("concrete_fair")
		var landing_x:float=p.landing_x
		# Two 1.30m apertures, centered on the actual +/-0.78m U flights:
		# outer piers0.17m / centre pier0.26m / outer piers0.17m. Every visible
		# pier/leaf has matching real collision; neither lane is an open bypass.
		var intervals:Array[Vector2]=[Vector2(landing_x-LANDING_WIDTH*.5,landing_x-.78-WIDTH*.5),Vector2(landing_x-.78+WIDTH*.5,landing_x+.78-WIDTH*.5),Vector2(landing_x+.78+WIDTH*.5,landing_x+LANDING_WIDTH*.5)]
		for bounds:Vector2 in intervals:
			_box(kit,"StairFireDoorPier"+str(bounds.x),mat,Vector3((bounds.x+bounds.y)*.5,float(p.rise)+float(p.height)*.5,p.plane_z),Vector3(bounds.y-bounds.x,p.height,FRAME_THICKNESS))
		for offset:float in [-.78,.78]:
			_box(kit,"StairFireDoorLintel"+str(offset),mat,Vector3(landing_x+offset,float(p.rise)+float(p.height)+float(p.header_height)*.5,p.plane_z),Vector3(WIDTH,p.header_height,FRAME_THICKNESS))
		# Existing tall returns still prevent going around the landing closure.
		for end:float in [-1.0,1.0]:
			_box(kit,"StairFireDoorSideReturn"+str(end),mat,Vector3(landing_x+end*1.48,float(p.rise)+float(p.height)*.5,float(p.edge_z)+float(p.side)*.5),Vector3(.12,p.height,1.40))
		kit.commit(holder,"StairFireDoorFrameMaterials_"+String(p.wing),true)
	var door:=StairDoor.new()
	door.name=("StairFireDoor_"+String(p.wing)+"_"+String(p.lane)).validate_node_name()
	door.door_id=p.id;door.base_angle=0.0;door.swing_delta=float(p.side)*PI*.5
	door.hinge_origin=p.hinge;door.leaf_width=WIDTH;door.motion_angle=0.0
	door.transition_kind="stair";door.coordinator=self
	door.collision_layer=1;door.collision_mask=0;door.sync_to_physics=true
	door.transform=Transform3D(Basis.IDENTITY,p.hinge+Vector3(WIDTH*.5,0,0))
	holder.add_child(door)
	var leaf=Kit.new()
	# The actual visible leaf and collision share exactly the same dimensions.
	leaf.box(metal,Vector3(0,float(p.height)*.5,0),Vector3(WIDTH,p.height,LEAF_THICKNESS),Basis.IDENTITY,false)
	leaf.box(Looks.get_mat("steel_bronze"),Vector3(WIDTH*.32,1.05,-float(p.side)*.055),Vector3(.14,.035,.05),Basis.IDENTITY,false)
	leaf.commit(door,"StairFireDoorLeafMaterials",true)
	var shape:=CollisionShape3D.new();shape.name="VisibleStairFireDoorLeaf"
	var box:=BoxShape3D.new();box.size=Vector3(WIDTH,p.height,LEAF_THICKNESS)
	shape.shape=box;shape.position.y=float(p.height)*.5;door.add_child(shape)
	var label:=Label3D.new();label.name="StairDoorSign";label.text="STAIR";label.font_size=36;label.pixel_size=.0015
	label.position=Vector3(0,1.7,-float(p.side)*.045)
	if float(p.side)>0:label.rotation.y=PI
	door.add_child(label)
	doors[p.id]=door
	var state:=p.duplicate(true)
	state.merge({"door":door,"holder":holder,"ready":false,"ready_generation":"","open_generation":"","close_requested":false,"state":"CLOSED_UNREADY","last_observation":{}})
	_gates[p.id]=state

func _floor_snapshot(id:String,entry:Dictionary)->Dictionary:
	if not is_instance_valid(entry.module) or not is_instance_valid(entry.holder) or not _unit_upright(entry.module):
		return {"valid":false,"ready":false,"generation":"","reason":"owned_floor_or_transform_invalid"}
	var lower:=_read(entry.provider,id)
	var upper:=_read(entry.provider,entry.upper_id)
	if not lower.valid or lower.get("generation","")!=entry.lower_generation:
		return {"valid":false,"ready":false,"generation":"","reason":"stale_bound_floor_generation"}
	if not bool(lower.ready):
		return {"valid":true,"ready":false,"generation":upper.get("generation",""),"reason":"lower_complete_floor_group_not_ready","required_lower_floor_id":id}
	for key:String in entry.gate_ids:
		var plan:Dictionary=_gates[key]
		if bool(plan.requires_receiving_geometry) and (not upper.has("receiving_door_height_m") or not upper.has("receiving_clear_height_m")):
			return {"valid":false,"ready":false,"generation":"","reason":"low_receiving_geometry_not_observed"}
		if upper.has("receiving_door_height_m") and (absf(float(upper.receiving_door_height_m)-float(plan.height))>.001 or absf(float(upper.receiving_clear_height_m)-float(plan.clear_height))>.001):
			return {"valid":false,"ready":false,"generation":"","reason":"receiving_geometry_changed"}
	return upper

## Non-yielding snapshot pass then commit pass for every bound wing.
## The provider MUST be a pure synchronous readiness query, never a loader.
func refresh_now(force:bool=true)->Dictionary:
	var tick:=Engine.get_physics_frames()
	var process_frame:=Engine.get_process_frames()
	if not force and tick==_refresh_physics_tick and process_frame==_refresh_process_frame:
		return {"refreshed":false,"physics_tick":tick,"process_frame":process_frame}
	_refresh_physics_tick=tick;_refresh_process_frame=process_frame
	var snapshots:Dictionary={}
	for id:String in _floors:snapshots[id]=_floor_snapshot(id,_floors[id])
	for key:String in _gates:
		var state:Dictionary=_gates[key]
		var observed:Dictionary=snapshots.get(state.lower_id,{"valid":false,"ready":false,"reason":"unbound_floor"})
		var ready:bool=bool(observed.get("valid",false)) and bool(observed.get("ready",false))
		var generation:String=observed.get("generation","")
		state.ready=ready;state.ready_generation=generation;state.last_observation=observed.duplicate(true)
		var door:StairDoor=state.door
		if not is_instance_valid(door):
			state.ready=false;state.close_requested=true
			_set_state(state,"OWNER_FLOOR_MISSING")
			continue
		door.ready_to_open=ready
		if not ready or (not String(state.open_generation).is_empty() and state.open_generation!=generation):
			state.close_requested=true
	_update_protection()
	return {"refreshed":true,"physics_tick":tick,"process_frame":process_frame,"gate_count":_gates.size()}

func _physics_process(_delta:float)->void:
	refresh_now(false)

func _occupants(state:Dictionary)->Array[Dictionary]:
	if not is_inside_tree() or not is_instance_valid(state.get("holder")):return []
	var query:=PhysicsShapeQueryParameters3D.new()
	var box:=BoxShape3D.new()
	# Covers threshold AND entire opening-leaf sweep. Holding collision here
	# pauses closing and pins support; the player is never pushed/repositioned.
	box.size=Vector3(WIDTH+.80,float(state.height)+.25,WIDTH+.80)
	query.shape=box
	var local:=Vector3(state.x,float(state.rise)+float(state.height)*.5+.025,float(state.plane_z)-float(state.side)*WIDTH*.35)
	query.transform=(state.holder as Node3D).global_transform*Transform3D(Basis.IDENTITY,local)
	query.collision_mask=OCCUPANCY_MASK;query.margin=.01
	return get_world_3d().direct_space_state.intersect_shape(query,32)

func _opening_occupants(state:Dictionary)->Array[Dictionary]:
	if not is_inside_tree() or not is_instance_valid(state.get("holder")):return []
	var query:=PhysicsShapeQueryParameters3D.new()
	var box:=BoxShape3D.new()
	# Conservative quarter-sweep envelope: hinge..tip in X and receiving-side
	# plane..tip in Z. Unlike the closing/threshold volume it does not include
	# the safe staircase side of a closed door. No actor is moved to clear it.
	box.size=Vector3(WIDTH,state.height,WIDTH)
	query.shape=box
	var local:=Vector3(float(state.hinge.x)+WIDTH*.5,float(state.rise)+float(state.height)*.5,float(state.plane_z)-float(state.side)*WIDTH*.5)
	query.transform=(state.holder as Node3D).global_transform*Transform3D(Basis.IDENTITY,local)
	query.collision_mask=OCCUPANCY_MASK;query.margin=.01
	return get_world_3d().direct_space_state.intersect_shape(query,32)

func _blocker_ids(hits:Array[Dictionary])->Array[int]:
	var ids:Array[int]=[]
	for hit:Dictionary in hits:
		var body:CollisionObject3D=hit.get("collider") as CollisionObject3D
		if body!=null and not ids.has(body.get_instance_id()):ids.append(body.get_instance_id())
	return ids

func _physically_closed(state:Dictionary)->bool:
	var door:StairDoor=state.door
	if not is_instance_valid(door) or not is_instance_valid(state.get("holder")) or door.opened or absf(door.motion_angle-door.base_angle)>.001:return false
	var actual:Transform3D=PhysicsServer3D.body_get_state(door.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var expected:Transform3D=(state.holder as Node3D).global_transform*Transform3D(Basis(Vector3.UP,door.base_angle),door.hinge_origin+Basis(Vector3.UP,door.base_angle)*Vector3(WIDTH*.5,0,0))
	return actual.is_equal_approx(expected)

func _gate_motion_allowed(id:String,delta:float=1.0/60.0)->bool:
	if not _gates.has(id):return false
	refresh_now(false)
	var state:Dictionary=_gates[id]
	var door:StairDoor=state.door
	if bool(state.close_requested):
		if not _physically_closed(state) and not _occupants(state).is_empty():
			_set_state(state,"HOLD_OCCUPIED")
			return false
		if not _physically_closed(state) and not _static_leaf_step_clear(state,door.base_angle,delta):
			_set_state(state,"HOLD_BLOCKED_GEOMETRY")
			return false
		door.set_open(false)
		if _physically_closed(state):
			state.close_requested=false;state.open_generation=""
			_set_state(state,"CLOSED_READY" if state.ready else "CLOSED_UNREADY")
		else:_set_state(state,"CLOSING")
	elif door.opened:
		var target:float=door.base_angle+door.swing_delta
		if absf(door.motion_angle-target)>.001:
			var opening_hits:=_opening_occupants(state)
			if not opening_hits.is_empty():
				state["opening_blocker_ids"]=_blocker_ids(opening_hits)
				_set_state(state,"OPENING_HOLD_OCCUPIED")
				return false
			if not _static_leaf_step_clear(state,target,delta):
				_set_state(state,"OPENING_HOLD_BLOCKED_GEOMETRY")
				return false
		else:_set_state(state,"OPEN")
	return true

func _static_leaf_step_clear(state:Dictionary,target:float,delta:float)->bool:
	if not is_finite(delta) or delta<=0.0 or delta>.10:return false
	var door:StairDoor=state.door
	var next:float=move_toward(door.motion_angle,target,delta*2.8)
	var shape:=BoxShape3D.new()
	# Two millimetres mechanical edge contact tolerance, never a Player or
	# doorway enlargement. Static frame/header/ceiling bodies remain queried.
	shape.size=Vector3(WIDTH-.004,float(state.height)-.004,LEAF_THICKNESS-.002)
	var hits:Array[Dictionary]=[]
	var steps:int=maxi(2,int(ceil(absf(next-door.motion_angle)/.04)))
	for index in steps+1:
		var fraction:float=float(index)/steps
		var angle:float=lerpf(door.motion_angle,next,fraction)
		var basis:=Basis(Vector3.UP,angle)
		var centre:Vector3=door.hinge_origin+basis*Vector3(WIDTH*.5,float(state.height)*.5,0)
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape
		query.transform=(state.holder as Node3D).global_transform*Transform3D(basis,centre)
		query.collision_mask=1;query.margin=.0001;query.exclude=[door.get_rid()]
		hits.append_array(get_world_3d().direct_space_state.intersect_shape(query,16))
	state["last_static_probe"]={"physics_tick":Engine.get_physics_frames(),"from_angle":door.motion_angle,"to_angle":next,"mechanical_edge_inset_m":.002,"angular_samples":steps+1,"only_own_leaf_excluded":true,"blocking_body_ids":_blocker_ids(hits)}
	return hits.is_empty()

func _set_state(state:Dictionary,value:String)->void:
	if state.state==value:return
	state.state=value
	gate_state_changed.emit.call_deferred(state.id,value)

func request_interaction(id:String)->bool:
	if not _gates.has(id):return false
	refresh_now()
	var state:Dictionary=_gates[id]
	var door:StairDoor=state.door
	if not is_instance_valid(door):return false
	if door.opened:
		state.close_requested=true
		return true
	if not state.ready or state.close_requested or not _physically_closed(state):
		var required_lower:String=state.last_observation.get("required_lower_floor_id","")
		if not required_lower.is_empty():_emit_floor_request.call_deferred(required_lower)
		_emit_floor_request.call_deferred(state.upper_id)
		return false
	var opening_hits:=_opening_occupants(state)
	if not opening_hits.is_empty():
		state["opening_blocker_ids"]=_blocker_ids(opening_hits)
		_set_state(state,"CLOSED_OPENING_OCCUPIED")
		return false
	state["opening_blocker_ids"]=[]
	door.ready_to_open=true
	if not door.set_open(true):return false
	state.open_generation=state.ready_generation
	_set_state(state,"OPENING")
	_update_protection()
	return true

func _emit_floor_request(id:String)->void:
	# This method is always deferred; a signal listener may now start an
	# asynchronous ensure_floor outside the physics callback.
	floor_requested.emit(id)

func _update_protection()->void:
	var next:Array[String]=[]
	for state:Dictionary in _gates.values():
		if not _physically_closed(state) or not _occupants(state).is_empty():
			for id:String in [state.lower_id,state.upper_id]:
				if not next.has(id):next.append(id)
	for id:String in _protected:
		if not next.has(id):protection_changed.emit(id,false)
	for id:String in next:
		if not _protected.has(id):protection_changed.emit(id,true)
	_protected=next

func protected_floor_ids()->Array[String]:
	refresh_now()
	return _protected.duplicate()

## Root calls BEFORE retiring collision. A false result retains actual support;
## never free a receiving floor first and ask the door to rescue its occupant.
func prepare_floor_retirement(id:String)->bool:
	refresh_now()
	var safe:=true
	for state:Dictionary in _gates.values():
		if state.lower_id!=id and state.upper_id!=id:continue
		state.close_requested=true
		if not _physically_closed(state) or not _occupants(state).is_empty():safe=false
	_update_protection()
	if safe and _floors.has(id):_retirement_prepared[id]=_floors[id].lower_generation
	return safe

## Notification AFTER root retired registry ownership and honored its actor/pin
## guard. Only assemblies belonging to this exact lower floor are removed.
func floor_retired(id:String,_retired_region:String="")->Dictionary:
	# FloorStack's two-argument floor_retired signal is accepted directly.
	# A stale notification cannot remove a freshly rebound floor's gates.
	if _floors.has(id):
		var bound:Dictionary=_floors[id]
		if _retirement_prepared.get(id,"")!=bound.lower_generation:return {"removed":false,"error":"Exact bound generation needs prior safe retirement preflight"}
		var current:=_read(bound.provider,id)
		if current.valid and current.get("generation","")==bound.lower_generation:return {"removed":false,"error":"Root must retire this collision generation before gate ownership removal"}
	if not prepare_floor_retirement(id):return {"removed":false,"error":"Gate moving/open/occupied; root must retain collision"}
	if not _floors.has(id):return {"removed":true,"owned_gates_removed":0}
	var entry:Dictionary=_floors[id]
	var count:int=entry.gate_ids.size()
	for key:String in entry.gate_ids:
		doors.erase(key);_gates.erase(key)
	_floors.erase(id)
	_retirement_prepared.erase(id)
	if is_instance_valid(entry.holder):entry.holder.queue_free()
	_update_protection()
	return {"removed":true,"owned_gates_removed":count,"foreign_nodes_removed":0}

func owned_collision_bodies(id:String="")->Array[CollisionObject3D]:
	var bodies:Array[CollisionObject3D]=[]
	for floor_id:String in _floors:
		if not id.is_empty() and id!=floor_id:continue
		if is_instance_valid(_floors[floor_id].holder):_collect_owned(_floors[floor_id].holder,bodies)
	return bodies

func _collect_owned(node:Node,bodies:Array[CollisionObject3D])->void:
	if node is CollisionObject3D and (node as CollisionObject3D).collision_layer!=0:bodies.append(node)
	for child:Node in node.get_children():_collect_owned(child,bodies)

func geometry_descriptor(id:String)->Dictionary:
	if not _floors.has(id):return {}
	var geometry:Array[Dictionary]=[]
	for key:String in _floors[id].gate_ids:
		var state:Dictionary=_gates[key]
		geometry.append({"gate_id":key,"wing":state.wing,"lane":state.lane,"hinge_local":state.hinge,"opening_center_x_local_m":state.x,"landing_center_x_local_m":state.landing_x,"receiving_approach_local":Vector3(state.x,state.rise,float(state.plane_z)-float(state.side)*(WIDTH+.75)),"opening_width_m":WIDTH,"height_m":state.height,"receiving_door_height_m":state.height,"receiving_clear_height_m":state.clear_height,"header_height_m":state.header_height,"thickness_m":LEAF_THICKNESS,"landing_width_m":LANDING_WIDTH,"edge_z_local_m":state.edge_z,"gate_plane_z_local_m":state.plane_z,"rise_m":state.rise,"side":state.side})
	return {"version":GEOMETRY_VERSION,"floor_id":id,"upper_id":_floors[id].upper_id,"bound_collision_generation":_floors[id].lower_generation,"gates":geometry,"root_context_registration_required":true,"actor_pose_writes":0,"asbuilt_verified":false}

func report()->Dictionary:
	var statuses:Dictionary={}
	for key:String in _gates:
		var state:Dictionary=_gates[key]
		statuses[key]={"lower_id":state.lower_id,"upper_id":state.upper_id,"state":state.state,"ready":state.ready,"ready_generation":state.ready_generation,"open_generation":state.open_generation,"close_requested":state.close_requested,"opened":state.door.opened if is_instance_valid(state.door) else false,"motion_angle":state.door.motion_angle if is_instance_valid(state.door) else null,"physically_closed":_physically_closed(state),"readiness_observation":state.last_observation.duplicate(true),"opening_blocker_ids":state.get("opening_blocker_ids",[]).duplicate(),"last_static_probe":state.get("last_static_probe",{}).duplicate(true),"receiving_door_height_m":state.height,"receiving_clear_height_m":state.clear_height}
	return {"geometry_version":GEOMETRY_VERSION,"bound_floors":_floors.keys(),"gates":statuses,"protected_floor_ids":_protected.duplicate(),"actor_pose_writes":0,"actor_velocity_writes":0,"actor_reparents":0,"context_registered_by_component":false,"full_building_completed":false}
