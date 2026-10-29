extends RefCounted
## Physical core geometry in INDIVIDUAL tower-own axes. Original reconstruction,
## retaining the tested stair/cabin dimensions; no actor moves or source scaling.
## The caller owns the single floor Kit/body, native commit, context and leases.
const Layout=preload("res://src/world/mbs_interior/source_core_layout.gd")
const Looks=preload("res://src/world/downtown/landmarks/looks.gd")
const SCHEMA="mbs_source_core_geometry_v1"
const SLAB=.20
const STAIR_WIDTH=3.20
const FLIGHT_WIDTH=1.25
const RUN=2.70
const LANDING=1.20
const GUARD_CENTRE=1.54
const MAX_SLAB_CELLS=256

static func _number(value:Variant)->bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

static func _transform(component:Dictionary)->Transform3D:
	return Transform3D(Basis(Vector3.UP,float(component.rotation_y_rad)),Vector3(float(component.own_origin_xz[0]),0,float(component.own_origin_xz[1])))

static func _rect_bounds(points:Array)->Array:
	var bounds:Array=[INF,INF,-INF,-INF]
	for p:Array in points:
		bounds=[minf(bounds[0],p[0]),minf(bounds[1],p[1]),maxf(bounds[2],p[0]),maxf(bounds[3],p[1])]
	return bounds

static func _rect(x0:float,z0:float,x1:float,z1:float)->Array:
	return [[x0,z0],[x1,z0],[x1,z1],[x0,z1]]

static func _inside_rect(x:float,z:float,box:Array)->bool:
	return x>float(box[0]) and x<float(box[2]) and z>float(box[1]) and z<float(box[3])

static func _unique_sorted(values:Array)->Array:
	values.sort();var result:Array=[]
	for value:float in values:
		if result.is_empty() or absf(value-float(result.back()))>.00001:result.append(value)
	return result

static func plan(record:Dictionary)->Dictionary:
	var tower:String=record.get("tower","")
	var layout:Dictionary=Layout.for_tower(tower)
	var g:Variant=record.get("geometry")
	if not layout.get("valid",false) or not g is Dictionary or not record.get("id") is String:return {"valid":false,"error":"Explicit tower floor and geometry required"}
	for key:String in ["storey_height_m","clear_height_m"]:
		if not _number(g.get(key)):return {"valid":false,"error":"Nonfinite core floor height"}
	var rise:float=g.storey_height_m;var clear:float=g.clear_height_m
	if rise<2.5 or rise>6.0 or clear<2.30 or clear+SLAB>rise+.00001:return {"valid":false,"error":"Core stairs/headroom cannot fit this floor interval"}
	if typeof(record.get("has_upper_floor",true))!=TYPE_BOOL or typeof(record.get("has_lower_floor",true))!=TYPE_BOOL:return {"valid":false,"error":"Explicit Boolean neighboring-floor flags required"}
	var bank:Array=_rect_bounds(layout.own_bank_polygon)
	var cutouts:Array[Dictionary]=[];var stairs:Array[Dictionary]=[];var ports:Array[Dictionary]=[]
	for component:Dictionary in layout.components:
		if component.kind=="lift":
			var threshold:Array=component.own_threshold_xz
			var hole:Array=[float(threshold[0])-Layout.SHAFT_HALF_WIDTH,float(threshold[1])+Layout.SHAFT_MIN_Z,float(threshold[0])+Layout.SHAFT_HALF_WIDTH,float(threshold[1])+Layout.SHAFT_BACK_Z]
			cutouts.append({"id":component.id,"kind":"continuous_lift_shaft","bounds_xz":hole})
			var alias:String=component.legacy_core_alias;var wing:String=alias.get_slice("-",0);var kind:String=alias.trim_prefix(wing+"-")
			ports.append({"id":String(record.id)+"-"+alias,"kind":kind,"wing":wing,"source_core_schema":SCHEMA,"source_core_alias":alias,"landing":Vector3(threshold[0],0,float(threshold[1])-.60),"cabin_center":Vector3(component.own_cabin_center_xz[0],0,component.own_cabin_center_xz[1]),"entry_sign":-1.0,"opening_width_m":1.30,"actor_teleport":false})
		else:
			var pose:Transform3D=_transform(component)
			var corners:Array=[]
			for local:Array in _rect(-STAIR_WIDTH*.5,0.0,STAIR_WIDTH*.5,LANDING+RUN+LANDING):
				var v:Vector3=pose*Vector3(local[0],0,local[1]);corners.append([float(v.x),float(v.z)])
			var bounds:Array=_rect_bounds(corners)
			# A floor above another stair must leave the complete incoming
			# headroom aperture, including the rear midlanding. The declared
			# bottom floor instead retains its real foundation support slab.
			if record.get("has_lower_floor",true):cutouts.append({"id":component.id,"kind":"incoming_stair_well","bounds_xz":bounds})
			var local_route:Array[Vector3]=[Vector3(-.78,0,-.60),Vector3(-.78,0,.60),Vector3(-.78,0,LANDING),Vector3(-.78,rise*.5,LANDING+RUN),Vector3(-.78,rise*.5,LANDING+RUN+.60),Vector3(.78,rise*.5,LANDING+RUN+.60),Vector3(.78,rise*.5,LANDING+RUN),Vector3(.78,rise,LANDING),Vector3(.78,rise,.60)]
			var route:Array[Vector3]=[]
			for p:Vector3 in local_route:route.append(pose*p)
			var alias:String=component.legacy_core_alias;var wing:String=alias.trim_suffix("-stair")
			var descriptor:Dictionary={"id":String(record.id)+"-"+alias,"kind":"stair","wing":wing,"source_core_schema":SCHEMA,"source_core_alias":alias,"source_core_local_pose":pose,"source_core_local_side":1.0,"source_core_rise_m":rise,"lower":pose*Vector3(-.78,0,-.60),"upper":pose*Vector3(.78,rise,-.60),"walk_route":route,"physical_flights":true,"actor_teleport":false,"adjacent_floor_collision_required":true}
			stairs.append(descriptor);ports.append(descriptor.duplicate(true))
	var xs:Array=[bank[0],bank[2]];var zs:Array=[bank[1],bank[3]]
	for hole:Dictionary in cutouts:
		var b:Array=hole.bounds_xz
		if b[0]<bank[0]-.0001 or b[1]<bank[1]-.0001 or b[2]>bank[2]+.0001 or b[3]>bank[3]+.0001:return {"valid":false,"error":"Core aperture exceeds actual bank"}
		xs.append_array([b[0],b[2]]);zs.append_array([b[1],b[3]])
	xs=_unique_sorted(xs);zs=_unique_sorted(zs)
	var cells:Array[Dictionary]=[];var support_area:=0.0;var cut_area:=0.0
	for xi in xs.size()-1:
		for zi in zs.size()-1:
			var x0:float=xs[xi];var x1:float=xs[xi+1];var z0:float=zs[zi];var z1:float=zs[zi+1]
			if x1-x0<.00001 or z1-z0<.00001:continue
			var removed:=false
			for hole:Dictionary in cutouts:
				if _inside_rect((x0+x1)*.5,(z0+z1)*.5,hole.bounds_xz):removed=true;break
			if removed:cut_area+=(x1-x0)*(z1-z0);continue
			cells.append({"bounds_xz":[x0,z0,x1,z1]});support_area+=(x1-x0)*(z1-z0)
	if cells.size()>MAX_SLAB_CELLS:return {"valid":false,"error":"Core slab work budget exceeded"}
	return {"valid":true,"schema":SCHEMA,"floor_id":record.id,"tower":tower,"rise_m":rise,"clear_height_m":clear,"has_upper_floor":record.get("has_upper_floor",true),"has_lower_floor":record.get("has_lower_floor",true),"bank_bounds_xz":bank,"slab_cells":cells,"cutouts":cutouts,"slab_support_area_m2":support_area,"slab_cut_area_m2":cut_area,"stair_ports":stairs,"portals":ports,"core_layout":layout,"physics_or_traversal_verified":false,"private_asbuilt_verified":false}

static func _solid(kit,label:String,material:Material,pose:Transform3D,center:Vector3,size:Vector3)->void:
	kit.box(material,pose*center,size,pose.basis,false)
	kit.col_box(size,pose*center,pose.basis)
	kit.body.get_child(kit.body.get_child_count()-1).name=label.validate_node_name()

static func _stair(kit,descriptor:Dictionary,rise:float)->void:
	var pose:Transform3D=descriptor.source_core_local_pose
	var concrete:Material=Looks.get_mat("concrete_fair")
	var sidewall:Material=Looks.get_mat("render_cream")
	for stage in 2:
		var x:float=-.78 if stage==0 else .78
		var low:float=0.0 if stage==0 else rise*.5
		for step in 10:
			var u:float=float(step+1)/10
			var along:float=LANDING+(float(step)+.5)/10*RUN
			if stage==1:along=LANDING+RUN-(float(step)+.5)/10*RUN
			kit.box(concrete,pose*Vector3(x,low+rise*.5*u-.06,along),Vector3(FLIGHT_WIDTH,.12,RUN/10),pose.basis,false)
		var a:=Vector3(x-FLIGHT_WIDTH*.5,low,LANDING if stage==0 else LANDING+RUN)
		var b:=Vector3(x+FLIGHT_WIDTH*.5,low,a.z)
		var c:=Vector3(b.x,low+rise*.5,LANDING+RUN if stage==0 else LANDING)
		var d:=Vector3(a.x,c.y,c.z)
		kit.col_trimesh(PackedVector3Array([pose*a,pose*b,pose*c,pose*a,pose*c,pose*d]))
	var prefix:String=descriptor.source_core_alias
	_solid(kit,prefix+"MidLanding",concrete,pose,Vector3(0,rise*.5-SLAB*.5,LANDING+RUN+LANDING*.5),Vector3(STAIR_WIDTH,SLAB,LANDING))
	for offset:float in [-GUARD_CENTRE,GUARD_CENTRE]:
		_solid(kit,prefix+"SideGuard"+str(offset),sidewall,pose,Vector3(offset,rise*.5+.50,2.6),Vector3(.12,rise+1.0,5.2))
	_solid(kit,prefix+"MidGuard",sidewall,pose,Vector3(0,rise*.5+.55,LANDING+RUN+LANDING),Vector3(STAIR_WIDTH,1.10,.10))
	_solid(kit,prefix+"CentreGuard",sidewall,pose,Vector3(0,rise*.5+.5,LANDING+RUN*.5),Vector3(.10,rise+1.0,RUN))

static func append_to_kit(kit,construction:Dictionary)->Dictionary:
	if not construction.get("valid",false) or construction.get("schema")!=SCHEMA or kit.body==null or not kit.body.is_inside_tree():return {"built":false,"error":"Owned live floor Kit and validated core plan required"}
	var material:Material=Looks.get_mat("granite_light")
	for index in construction.slab_cells.size():
		var b:Array=construction.slab_cells[index].bounds_xz
		_solid(kit,"SourceCoreSlab"+str(index),material,Transform3D.IDENTITY,Vector3((float(b[0])+float(b[2]))*.5,-SLAB*.5,(float(b[1])+float(b[3]))*.5),Vector3(float(b[2])-float(b[0]),SLAB,float(b[3])-float(b[1])))
	for stair:Dictionary in construction.stair_ports:
		# This floor owns its receiving landing. The lower floor does NOT
		# draw/collide a duplicate platform at this elevation. Native gates
		# require the real receiving module before allowing ascent.
		if construction.has_lower_floor:
			_solid(kit,String(stair.source_core_alias)+"ReceivingLanding",Looks.get_mat("concrete_fair"),stair.source_core_local_pose,Vector3(0,-SLAB*.5,LANDING*.5),Vector3(STAIR_WIDTH,SLAB,LANDING))
		if construction.has_upper_floor:_stair(kit,stair,float(construction.rise_m))
	return {"built":true,"schema":SCHEMA,"floor_id":construction.floor_id,"portals":construction.portals.duplicate(true),"slab_cells":construction.slab_cells.size(),"cutouts":construction.cutouts.duplicate(true),"context_registration_owned_by_root":true,"native_traversal_verified":false}
