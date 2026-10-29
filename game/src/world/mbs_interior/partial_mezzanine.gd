extends "res://src/world/mbs_interior/program_floor.gd"
## Original partial service galleries at actual inventory B2/B2M elevations.
## Parent owns source placement, complete B2/M/B1 residency and transport guards.
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const SCHEMA := "mbs_partial_mezzanine_v1"
const SERVICE_CLEAR := 2.30
const PASSAGE_HEIGHT := 2.10
const HEADER_HEIGHT := .10
const WING_DEPTH := 10.0
const END_LINK_WIDTH := 3.0
const ROOM_HEIGHT := 2.20
var _partial_plan: Dictionary = {}

static func partial_plan(record: Dictionary) -> Dictionary:
	if record.get("factory","") != "program_module" or not record.get("tower","") in ["T1","T2","T3"] or not record.get("level","") in ["B2","B2M"]: return {"valid":false,"error":"Explicit hotel B2/B2M inventory record required; resort source mapping remains Root-owned."}
	var tower: String=record.tower
	if record.get("id","") != tower+"-"+String(record.level):return {"valid":false,"error":"Floor ID and level mismatch."}
	var original:Dictionary=Inventory.floor_record(record.id)
	if original.is_empty() or not typeof(record.get("elevation_m")) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(record.elevation_m)) or absf(float(record.elevation_m)-float(original.elevation_m))>.00001:return {"valid":false,"error":"Actual reconstructed inventory elevation must be preserved."}
	if not record.get("geometry") is Dictionary or not record.get("program_spaces") is Array or not record.get("units",[]) is Array or not (record.get("units",[]) as Array).is_empty():return {"valid":false,"error":"Complete geometry/program inventory required, no guest-room dropping."}
	var g:Dictionary=record.geometry.duplicate(true)
	for key:String in ["length_m","cross_m","core_bay_m","corridor_width_m"]:
		if not typeof(g.get(key)) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(g[key])):return {"valid":false,"error":"Missing finite footprint dimension: "+key}
	var length_m:float=g.length_m;var cross_m:float=g.cross_m
	if length_m<55 or length_m>70 or cross_m<36 or cross_m>65 or absf(float(g.core_bay_m)-6.2)>.001 or absf(float(g.corridor_width_m)-2.6)>.001:return {"valid":false,"error":"Unsupported footprint/core; a different explicit partial plan is required."}
	var upper_id:String=tower+("-B2M" if record.level=="B2" else "-B1")
	var upper:Dictionary=Inventory.floor_record(upper_id)
	var rise:float=float(upper.elevation_m)-float(record.elevation_m)
	if absf(rise-2.5)>.00001:return {"valid":false,"error":"This factory requires the actual2.5m inventory interval."}
	var mezz:bool=record.level=="B2M"
	var inner:float=cross_m*.5-WING_DEPTH
	var room_end:float=length_m*.5-float(g.core_bay_m)-END_LINK_WIDTH
	if inner<8 or room_end<18:return {"valid":false,"error":"Insufficient double-height zone or furnished room frontage."}
	g.merge({"clear_height_m":SERVICE_CLEAR,"storey_height_m":rise,"atrium_void_active":mezz,"void_min_z_m":-inner if mezz else 0.0,"void_max_z_m":inner if mezz else 0.0,"core_door_height_m":PASSAGE_HEIGHT,"partial_mezzanine_schema":SCHEMA,"all_dimensions_reconstructed":true},true)
	var expected:Dictionary={}
	for item:Dictionary in original.program_spaces:expected[item.id]=String(item.program)
	var furnished:Array[Dictionary]=[];var cores:Array[Dictionary]=[];var seen:Dictionary={}
	for value:Variant in record.program_spaces:
		if not value is Dictionary or not value.get("id") is String or not value.get("program") is String or seen.has(value.id) or expected.get(value.id,"")!=value.program:return {"valid":false,"error":"Exact named program coverage required before construction."}
		seen[value.id]=true
		if value.program in CORE_PROGRAMS:cores.append(value.duplicate(true))
		elif RECIPES.has(value.program):
			var cell:Dictionary=value.duplicate(true);cell["recipe"]=RECIPES[value.program];furnished.append(cell)
		else:return {"valid":false,"error":"Unknown program cannot become a labelled empty room."}
	if seen.size()!=expected.size() or furnished.size()!=5:return {"valid":false,"error":"Every required service program must remain furnished/present."}
	var wings:Array[Dictionary]=[];var planned:Array[Dictionary]=[];var objects:Array[Dictionary]=[]
	for side:float in [-1.0,1.0]:
		var wing_name:String="east" if side<0 else "west"
		var assigned:Array[Dictionary]=[]
		for index in furnished.size():
			if (index%2==0)==(side<0):assigned.append(furnished[index])
		var frontage:float=room_end*2.0/assigned.size()
		if frontage<10:return {"valid":false,"error":"Full furnishing/entry aisle cannot fit."}
		for index in assigned.size():
			var cell:Dictionary=assigned[index].duplicate(true)
			cell.merge({"wing":wing_name,"center_x":-room_end+(index+.5)*frontage,"frontage_m":frontage,"depth_m":WING_DEPTH-float(g.corridor_width_m),"inner_z":side*(inner+float(g.corridor_width_m)),"side":side,"entry_u":-frontage*.5+1.0,"private_asbuilt_verified":false},true)
			cell["entry_local"]=_p(cell,cell.entry_u,0,-1.1);cell["inside_local"]=_p(cell,cell.entry_u,0,1.7);cell["view_local"]=_p(cell,cell.entry_u,0,float(cell.depth_m)-.9)
			var layout:Dictionary=_recipe_layout(cell)
			if not layout.get("valid",false):return layout
			for object:Dictionary in layout.objects:
				if float((object.size as Vector3).y)>SERVICE_CLEAR-.05:return {"valid":false,"error":"A furnishing exceeds actual low service headroom."}
			cell["objects"]=layout.objects;objects.append_array(layout.objects);planned.append(cell)
		wings.append({"id":wing_name,"side":side,"inner_z":side*inner,"outer_z":side*cross_m*.5,"room_inner_z":side*(inner+float(g.corridor_width_m)),"corridor_center_z":side*(inner+float(g.corridor_width_m)*.5),"core_z":side*(cross_m*.5-5.6),"depth_m":WING_DEPTH})
	var platforms:Array[Dictionary]=[]
	var end:float=length_m*.5-float(g.core_bay_m)
	if mezz:
		for wing:Dictionary in wings:platforms.append({"id":String(wing.id)+"-service-wing","center":Vector3(0,0,(float(wing.inner_z)+float(wing.outer_z))*.5),"size":Vector2(end*2,WING_DEPTH)})
		for sign:float in [-1.0,1.0]:platforms.append({"id":"end-crosslink-"+str(sign),"center":Vector3(sign*(end-END_LINK_WIDTH*.5),0,0),"size":Vector2(END_LINK_WIDTH,inner*2)})
	else:platforms.append({"id":"lower-full-service-base","center":Vector3.ZERO,"size":Vector2(end*2,cross_m)})
	var probes:Array[Vector3]=[]
	for wing:Dictionary in wings:
		for fraction:float in [-.50,.50]:probes.append(Vector3(room_end*fraction,0,wing.corridor_center_z))
	return {"valid":true,"schema":SCHEMA,"geometry":g,"role":"partial_mezzanine" if mezz else "lower_doubleheight_base","rooms":planned,"objects":objects,"core_programs":cores,"wings":wings,"platforms":platforms,"room_end_x_m":room_end,"central_void_rect":Rect2(Vector2(-room_end,-inner),Vector2(room_end*2,inner*2)),"floor_probe_points_local":probes,"required_group_floor_ids":[tower+"-B2",tower+"-B2M",tower+"-B1"],"upper_floor_id":upper_id,"upper_core_door_height_m":PASSAGE_HEIGHT if mezz==false else 2.35,"core_door_height_m":PASSAGE_HEIGHT,"has_upper_floor":true,"open_roof":false,"geometry_status":"RECONSTRUCTED_PARTIAL_SERVICE_GALLERIES_NOT_CURRENT_ASBUILT"}

func build(record:Dictionary)->Dictionary:
	if _built:return {"built":false,"error":"Already built."}
	var planned:Dictionary=partial_plan(record)
	if not planned.get("valid",false):return {"built":false,"error":planned.get("error","Invalid partial plan")}
	if not basis.get_scale().is_equal_approx(Vector3.ONE) or (is_inside_tree() and not global_basis.get_scale().is_equal_approx(Vector3.ONE)):return {"built":false,"error":"Uncompressed unit metre scale required."}
	_partial_plan=planned;_program_plan=planned;_plan=planned;floor_record=record.duplicate(true);floor_record.geometry=planned.geometry.duplicate(true)
	rooms.assign(planned.rooms);furnishings.assign(planned.objects);_height=SERVICE_CLEAR;_open_roof=false;_make_materials()
	var kit=Kit.new(self,"ProgramFloorSolidCollision")
	for platform:Dictionary in planned.platforms:_slab(kit,platform)
	for wing:Dictionary in planned.wings:
		_build_core_approaches(kit,wing,planned.geometry,false)
		_build_stair(kit,wing,planned.geometry)
		_low_lifts(kit,wing,planned.geometry)
		_outer_shell(kit,wing,planned.geometry)
	for cell:Dictionary in rooms:_low_room(kit,cell)
	if planned.role=="partial_mezzanine":_gallery_guards(kit)
	else:_central_service_fitout(kit)
	for entry:Dictionary in planned.core_programs:program_coverage.append({"id":entry.id,"program":entry.program,"implementation":"CONNECTED_FURNISHED_PARTIAL_GALLERIES_AND_NATIVE_CORES","private_asbuilt_verified":false})
	kit.commit(self,"PartialMezzanineMaterialBatches",true);_program_plan["static_collision_shapes"]=kit.shapes;_built=true
	return report()

func _slab(kit,patch:Dictionary)->void:
	var point:Vector3=patch.center;var size:Vector2=patch.size
	_solid(kit,String(patch.id)+"Slab",_materials.stone,point-Vector3.UP*SLAB*.5,Vector3(size.x,SLAB,size.y))

func _outer_shell(kit,wing:Dictionary,g:Dictionary)->void:
	var end:float=float(g.length_m)*.5-float(g.core_bay_m)
	var height:float=4.8 if _partial_plan.role=="lower_doubleheight_base" else SERVICE_CLEAR
	if _partial_plan.role=="lower_doubleheight_base":_solid(kit,String(wing.id)+"OuterServiceWall",_materials.wall,Vector3(0,height*.5,wing.outer_z),Vector3(end*2,height,.15))
	for x:float in [-1.0,1.0]:
		_solid(kit,String(wing.id)+"EndServiceWall"+str(x),_materials.wall,Vector3(x*float(g.length_m)*.5,SERVICE_CLEAR*.5,(float(wing.inner_z)+float(wing.core_z))*.5),Vector3(.15,SERVICE_CLEAR,absf(float(wing.core_z)-float(wing.inner_z))))
	for x:float in [-float(_partial_plan.room_end_x_m)*.65,0,float(_partial_plan.room_end_x_m)*.65]:_light(Vector3(x,2.05,wing.corridor_center_z),.70,8.0)

func _low_door(id:String,hinge:Vector3,kind:String="",side:float=1.0)->SwingDoor:
	var door:=SwingDoor.new();door.name=("LowDoor_"+id).validate_node_name();door.door_id=id;door.coordinator=self
	door.hinge_origin=hinge;door.leaf_width=DOOR_WIDTH;door.base_angle=0;door.motion_angle=0;door.swing_delta=-side*PI*.5;door.transition_kind=kind
	door.collision_layer=1;door.collision_mask=0;door.sync_to_physics=true;door.transform=Transform3D(Basis.IDENTITY,hinge+Vector3(DOOR_WIDTH*.5,0,0));add_child(door)
	var leaf=Kit.new();leaf.box(Looks.get_mat("timber"),Vector3(0,PASSAGE_HEIGHT*.5,0),Vector3(DOOR_WIDTH,PASSAGE_HEIGHT,.075),Basis.IDENTITY,false)
	leaf.box(Looks.get_mat("steel_satin"),Vector3(DOOR_WIDTH*.32,1.0,-side*.055),Vector3(.16,.035,.05),Basis.IDENTITY,false);leaf.commit(door,"LowServiceDoorMaterials",true)
	var shape:=CollisionShape3D.new();shape.name="MatchingLowDoorLeaf";var box:=BoxShape3D.new();box.size=Vector3(DOOR_WIDTH,PASSAGE_HEIGHT,.075);shape.shape=box;shape.position.y=PASSAGE_HEIGHT*.5;door.add_child(shape)
	doors[id]=door;return door

func _low_room(kit,cell:Dictionary)->void:
	var half:float=float(cell.frontage_m)*.5;var side:float=cell.side;var z:float=cell.inner_z;var cx:float=cell.center_x
	var door_x:float=cx+float(cell.entry_u)
	for bounds:Vector2 in [Vector2(cx-half,door_x-DOOR_WIDTH*.5),Vector2(door_x+DOOR_WIDTH*.5,cx+half)]:
		_solid(kit,String(cell.id)+"Front"+str(bounds.x),_materials.wall,Vector3((bounds.x+bounds.y)*.5,ROOM_HEIGHT*.5,z),Vector3(bounds.y-bounds.x,ROOM_HEIGHT,.15))
	_solid(kit,String(cell.id)+"LowHeader",_materials.wall,Vector3(door_x,PASSAGE_HEIGHT+HEADER_HEIGHT*.5,z),Vector3(DOOR_WIDTH,HEADER_HEIGHT,.15))
	# Own the left partition once; last room in a wing owns its right boundary.
	_solid(kit,String(cell.id)+"LeftPartition",_materials.wall,Vector3(cx-half,ROOM_HEIGHT*.5,z+side*float(cell.depth_m)*.5),Vector3(.15,ROOM_HEIGHT,cell.depth_m))
	if absf(cx+half-float(_partial_plan.room_end_x_m))<.001:_solid(kit,String(cell.id)+"RightPartition",_materials.wall,Vector3(cx+half,ROOM_HEIGHT*.5,z+side*float(cell.depth_m)*.5),Vector3(.15,ROOM_HEIGHT,cell.depth_m))
	_low_door(String(cell.id),Vector3(door_x-DOOR_WIDTH*.5,0,z),"",side)
	_label(Vector3(door_x,1.65,z-side*.10),String(cell.program).replace("_"," ").to_upper(),.0016)
	for object:Dictionary in cell.objects:_furnishing(kit,cell,object)
	program_coverage.append({"id":cell.id,"program":cell.program,"implementation":"FURNISHED_COLLIDING_LOW_SERVICE_ROOM","objects":cell.objects.size(),"private_asbuilt_verified":false})

func _low_lifts(kit,wing:Dictionary,g:Dictionary)->void:
	var x:float=float(g.length_m)*.5-float(g.core_bay_m)*.5;var side:float=wing.side;var z:float=wing.core_z
	var extent:float=float(g.core_bay_m)*.5
	for bounds:Vector2 in [Vector2(x-extent,x-1.3-DOOR_WIDTH*.5),Vector2(x-1.3+DOOR_WIDTH*.5,x+1.3-DOOR_WIDTH*.5),Vector2(x+1.3+DOOR_WIDTH*.5,x+extent)]:
		_solid(kit,String(wing.id)+"LowLiftPier"+str(bounds.x),_materials.wall,Vector3((bounds.x+bounds.y)*.5,SERVICE_CLEAR*.5,z),Vector3(bounds.y-bounds.x,SERVICE_CLEAR,.15))
	for index in 2:
		var kind:String="guest_lift" if index==0 else "service_lift";var cx:float=x+(-1.3 if index==0 else 1.3)
		var id:String=String(floor_record.id)+"-"+String(wing.id)+"-"+kind
		_solid(kit,id+"LowHeader",Looks.get_mat("steel_satin"),Vector3(cx,PASSAGE_HEIGHT+HEADER_HEIGHT*.5,z),Vector3(DOOR_WIDTH,HEADER_HEIGHT,.15))
		_low_door(id,Vector3(cx-DOOR_WIDTH*.5,0,z),kind,side)
		portals.append({"id":id,"kind":kind,"wing":wing.id,"landing":Vector3(cx,0,z-side*.60),"threshold":Vector3(cx,0,z),"cabin_expected_center":Vector3(cx,0,z+side*1.4),"core_door_height_m":PASSAGE_HEIGHT,"clear_height_m":SERVICE_CLEAR,"requires_physical_cabin":true,"loaded_collision_required":true,"actor_teleport":false})

func _gallery_guards(kit)->void:
	var g:Dictionary=_partial_plan.geometry;var x:float=_partial_plan.room_end_x_m;var z:float=float(g.cross_m)*.5-WING_DEPTH
	for side:float in [-1.0,1.0]:
		_solid(kit,"MezzOpenEdgeZ"+str(side),Looks.get_mat("steel_satin"),Vector3(0,.55,side*z),Vector3(x*2,1.10,.10))
		_solid(kit,"MezzOpenEdgeX"+str(side),Looks.get_mat("steel_satin"),Vector3(side*x,.55,0),Vector3(.10,1.10,z*2))
		kit.beam(Looks.get_mat("steel_dark"),Vector3(-x,1.15,side*z),Vector3(x,1.15,side*z),.06,.06)

func _central_service_fitout(kit)->void:
	var g:Dictionary=_partial_plan.geometry;var inner:float=float(g.cross_m)*.5-WING_DEPTH
	# Occupied transfer/engineering hall: preserve a continuous four-metre spine.
	for x:float in [-6.0,0.0,6.0]:
		for side:float in [-1.0,1.0]:
			var p:=Vector3(x,0,side*minf(inner-2.0,5.5))
			var object:Dictionary={"id":String(floor_record.id)+"-central-service-"+str(x)+"-"+str(side),"space_id":String(floor_record.id)+"-service_corridor","kind":"trolley" if x==0 else "plant_cabinet","position":p,"size":_object_size("trolley" if x==0 else "plant_cabinet"),"side":side}
			_furnishing(kit,{},object);furnishings.append(object)
		kit.beam(Looks.get_mat("steel_dark"),Vector3(x,4.45,-inner),Vector3(x,4.45,inner),.12,.15)
		_light(Vector3(x,4.1,0),1.0,9.0)

func geometry_descriptor()->Dictionary:
	if not _built:return {}
	var boxes:Array[Dictionary]=[]
	for patch:Dictionary in _partial_plan.platforms:
		var height:float=SERVICE_CLEAR
		if _partial_plan.role=="lower_doubleheight_base":
			# Split lower base: low edges beneath mezz, tall CENTRAL void only.
			var end:float=float(_partial_plan.geometry.length_m)*.5-float(_partial_plan.geometry.core_bay_m)
			var inner:float=float(_partial_plan.geometry.cross_m)*.5-WING_DEPTH;var rx:float=_partial_plan.room_end_x_m
			boxes.append({"id":"lower-central-doubleheight","center":Vector3(0,2.275,0),"half":Vector3(rx,2.525,inner)})
			for wing:Dictionary in _partial_plan.wings:boxes.append({"id":String(wing.id)+"-low-service","center":Vector3(0,1.025,(float(wing.inner_z)+float(wing.outer_z))*.5),"half":Vector3(end,1.275,WING_DEPTH*.5)})
			for sign:float in [-1.0,1.0]:boxes.append({"id":"lower-under-end-crosslink-"+str(sign),"center":Vector3(sign*(end-END_LINK_WIDTH*.5),1.025,0),"half":Vector3(END_LINK_WIDTH*.5,1.275,inner)})
		else:boxes.append({"id":patch.id,"center":patch.center+Vector3.UP*1.025,"half":Vector3((patch.size as Vector2).x*.5,1.275,(patch.size as Vector2).y*.5)})
	for wing:Dictionary in _partial_plan.wings:
		for sign:float in [-1.0,1.0]:boxes.append({"id":String(wing.id)+"-core-"+str(sign),"center":Vector3(sign*(float(_partial_plan.geometry.length_m)*.5-3.1),1.025,(float(wing.inner_z)+float(wing.core_z))*.5),"half":Vector3(3.1,1.275,absf(float(wing.inner_z)-float(wing.core_z))*.5)})
		boxes.append({"id":String(wing.id)+"-real-U-stair-air","center":Vector3(-float(_partial_plan.geometry.length_m)*.5+1.8,2.125, float(wing.core_z)+float(wing.side)*2.6),"half":Vector3(1.6,2.375,2.6)})
	return {"schema":SCHEMA,"role":_partial_plan.role,"floor_id":floor_record.id,"required_group_floor_ids":_partial_plan.required_group_floor_ids.duplicate(),"upper_floor_id":_partial_plan.upper_floor_id,"core_door_height_m":PASSAGE_HEIGHT,"core_header_height_m":HEADER_HEIGHT,"upper_receiving_door_height_m":_partial_plan.upper_core_door_height_m,"service_clear_height_m":SERVICE_CLEAR,"slab_thickness_m":SLAB,"dry_boxes_local":boxes,"native_floor_probe_points_local":_partial_plan.floor_probe_points_local.duplicate(),"actual_platforms_local":_partial_plan.platforms.duplicate(true),"central_open_void_local":_partial_plan.central_void_rect,"source_placement_owned_by_root":true,"shaft_travel_ready":false,"private_asbuilt_verified":false}

func report()->Dictionary:
	var result:Dictionary=super.report()
	result["partial_mezzanine"]=geometry_descriptor();result["core_door_height_m"]=PASSAGE_HEIGHT;result["service_clear_height_m"]=SERVICE_CLEAR
	result["requires"]="Root exact source dispatch, actual B2/B2M/B1 group residency, destination-height stair/cabin guards, low receiving openings and complete native/rendered whole-building verification."
	return result
