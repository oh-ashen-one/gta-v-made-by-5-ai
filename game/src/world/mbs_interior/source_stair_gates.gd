extends "res://src/world/mbs_interior/stair_gates.gd"
## Explicit core-pose adapter. Existing legacy rectangle/end-bay binder remains
## unchanged. Floor identity, actual receivers and all native motion guards stay.
const Core=preload("res://src/world/mbs_interior/source_core_geometry.gd")
const SOURCE_BINDING_SCHEMA="mbs_source_stair_binding_v1"

func _same_vector(a:Variant,b:Variant)->bool:
	return a is Vector3 and b is Vector3 and a.distance_to(b)<.00001

func _same_portal(actual:Dictionary,expected:Dictionary)->bool:
	for key:String in ["id","kind","wing","source_core_schema","source_core_alias","source_core_local_side","source_core_rise_m"]:
		if actual.get(key)!=expected.get(key):return false
	if not actual.get("source_core_local_pose") is Transform3D or not actual.source_core_local_pose.is_equal_approx(expected.source_core_local_pose):return false
	for key:String in ["lower","upper"]:
		if not _same_vector(actual.get(key),expected[key]):return false
	var route:Variant=actual.get("walk_route")
	if not route is Array or route.size()!=expected.walk_route.size():return false
	for index in route.size():
		if not _same_vector(route[index],expected.walk_route[index]):return false
	return true

func bind_floor(module:Node3D,id:String,upper_id:String,provider:Callable,receiving_record:Dictionary={})->Dictionary:
	if not is_inside_tree() or not is_instance_valid(module) or not _unit_upright(module) or module.get_world_3d()!=get_world_3d() or not provider.is_valid():return {"bound":false,"error":"Owned in-tree unit-scale source floor and provider required"}
	if _floors.has(id) or _floors.size()>=MAX_BOUND_FLOORS:return {"bound":false,"error":"Duplicate or over-budget source floor gates"}
	var record:Variant=module.get("floor_record");var portals:Variant=module.get("portals")
	if not bool(module.get("_built")) or module.get("source_core_schema")!=Core.SCHEMA or not record is Dictionary or record.get("id")!=id or not portals is Array:return {"bound":false,"error":"Completed source-core factory and exact floor identity required"}
	var construction:Dictionary=Core.plan(record)
	if not construction.get("valid",false) or not construction.has_upper_floor:return {"bound":false,"error":"Source core plan has no constructible outgoing stairs"}
	if receiving_record.get("id")!=upper_id or receiving_record.get("tower")!=record.tower or upper_id==id or not receiving_record.get("geometry") is Dictionary:return {"bound":false,"error":"Explicit actual same-tower receiving recipe required"}
	var rise:float=construction.rise_m
	if not is_equal_approx(float(receiving_record.get("elevation_m",INF))-float(record.get("elevation_m",-INF)),rise):return {"bound":false,"error":"Actual receiving elevation differs from physical source stair"}
	var rg:Dictionary=receiving_record.geometry
	for key:String in ["clear_height_m"]:
		if not Core._number(rg.get(key)):return {"bound":false,"error":"Typed finite receiving headroom required"}
	var raw_height:Variant=rg.get("core_door_height_m",HEIGHT)
	if not Core._number(raw_height):return {"bound":false,"error":"Typed finite receiving doorway height required"}
	var height:float=raw_height;var clear:float=rg.clear_height_m
	var low:bool=absf(height-2.10)<.001
	var header:float=.10 if low else .20
	if (not low and absf(height-HEIGHT)>.001) or clear<height+header+.04:return {"bound":false,"error":"Source receiver cannot contain its full physical gate/header"}
	if low and rg.get("partial_mezzanine_schema","")!="mbs_partial_mezzanine_v1":return {"bound":false,"error":"Low source receiver needs the explicit service floor recipe"}
	var lower:Dictionary=_read(provider,id)
	if not lower.valid:return {"bound":false,"error":"Actual lower collision generation required"}
	var plans:Array[Dictionary]=[];var seen:Dictionary={}
	for actual:Dictionary in portals:
		if actual.get("kind")!="stair":continue
		var wing:String=actual.get("wing","");var expected:Dictionary={}
		for candidate:Dictionary in construction.stair_ports:
			if candidate.wing==wing:expected=candidate;break
		if expected.is_empty() or seen.has(wing) or not _same_portal(actual,expected):return {"bound":false,"error":"Source stair pose/route/identity differs from the full-size core contract"}
		seen[wing]=true
		for lane:String in ["upper_return","lower_departure"]:
			var x:float=.78 if lane=="upper_return" else -.78
			var gate_id:String=id+"-"+wing+("-stair-fire-door" if lane=="upper_return" else "-stair-lower-entry-door")
			var leaf_plane:float=GATE_EDGE_SETBACK-HINGE_FRAME_CLEARANCE
			plans.append({"id":gate_id,"wing":wing,"lane":lane,"side":1.0,"x":x,"landing_x":0.0,"edge_z":0.0,"plane_z":leaf_plane,"frame_plane_z":GATE_EDGE_SETBACK,"rise":rise,"lower_id":id,"upper_id":upper_id,"lower_generation":lower.generation,"base_angle":0.0,"hinge":Vector3(x-WIDTH*.5,rise,leaf_plane),"build_landing_frame":lane=="upper_return","height":height,"clear_height":clear,"header_height":header,"requires_receiving_geometry":low,"source_core_local_pose":expected.source_core_local_pose})
	if seen.size()!=2 or plans.size()!=4:return {"bound":false,"error":"Both full-size source U-stairs and four independent leaves required"}
	# All validation above precedes scene mutation. Per-stair pose holders
	# ensure inherited leaf/occupancy/static queries use the identical frame.
	var holder:=Node3D.new();holder.name="OwnedSourceCoreStairGates";module.add_child(holder)
	var entry:Dictionary={"module":module,"holder":holder,"provider":provider,"lower_generation":lower.generation,"upper_id":upper_id,"gate_ids":[],"binding_schema":SOURCE_BINDING_SCHEMA}
	_floors[id]=entry;_retirement_prepared.erase(id)
	var frames:Dictionary={}
	for plan:Dictionary in plans:
		if not frames.has(plan.wing):
			var pose_holder:=Node3D.new();pose_holder.name="SourceStairPose_"+String(plan.wing)
			pose_holder.transform=plan.source_core_local_pose;holder.add_child(pose_holder);frames[plan.wing]=pose_holder
		_build_gate(frames[plan.wing],plan);entry.gate_ids.append(plan.id)
	refresh_now()
	return {"bound":true,"floor_id":id,"upper_id":upper_id,"gate_ids":entry.gate_ids.duplicate(),"binding_schema":SOURCE_BINDING_SCHEMA,"geometry_version":GEOMETRY_VERSION,"actor_pose_writes":0,"native_source_core_traversal_verified":false}

func geometry_descriptor(id:String)->Dictionary:
	var result:Dictionary=super.geometry_descriptor(id)
	if result.is_empty():return result
	result["binding_schema"]=SOURCE_BINDING_SCHEMA
	result["gate_coordinates_are_stair_local_not_floor_local"]=true
	for gate:Dictionary in result.gates:
		var state:Dictionary=_gates[gate.gate_id]
		gate["stair_to_floor_local"]=state.source_core_local_pose
		gate["receiving_approach_floor_local"]=state.source_core_local_pose*gate.receiving_approach_local
	return result
