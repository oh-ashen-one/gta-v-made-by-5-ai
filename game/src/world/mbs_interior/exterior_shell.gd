extends Node3D
## Persistent source-positioned MBS exterior, independent of streamed rooms.
## Original envelope reconstruction, NOT a surveyed/current interior plan.
## Root must reconcile floor/core masks before whole-hotel integration.
const CoreLayout = preload("res://src/world/mbs_interior/source_core_layout.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const SCHEMA := "mbs_source_exterior_shell_v1"
const TOP_DEPTH := 30.0
const LINK_HEIGHT := 77.45
const OBSERVATION_Y := 191.30
const PARK_Y := 194.75
const BOAT_LENGTH := 340.0
const BOAT_DECK_WIDTH := 38.0
const BOAT_MAX_WIDTH := 40.0
const NORTH_CANTILEVER := 66.5
const LOW_DECK_END := 70.0
const ROOF_STAIR_RUN := 5.6
const ROOF_STAIR_WIDTH := 3.2
const ROOF_STAIR_COUNT := 20
const MAX_APERTURES := 96
const AXES := {
		"T3": {
				"south": [
						0.9904357262105997,
						-0.1379748971577146
				],
				"bayward": [
						0.1379748971577146,
						0.9904357262105997
				],
				"source_id": "way/172307471"
		},
		"T2": {
				"south": [
						0.9996723967757053,
						0.025594904272465385
				],
				"bayward": [
						-0.025594904272465385,
						0.9996723967757053
				],
				"source_id": "way/172307472"
		},
		"T1": {
				"south": [
						0.9811472491261639,
						0.1932616763152001
				],
				"bayward": [
						-0.1932616763152001,
						0.9811472491261639
				],
				"source_id": "way/116801004"
		}
}
const VOID_MASKS := {
	"T3":{"min_z":-9.48941,"max_z":5.15,"top_y":27.0},
	"T2":{"min_z":-10.15,"max_z":15.47127,"top_y":47.0},
	"T1":{"min_z":-20.35512,"max_z":20.15,"top_y":76.0},
}
const ARUP_PDF := "https://www.arup.com/globalassets/downloads/arup-journal/the-arup-journal-2012-issue-1.pdf"
const ARUP_PROJECT := "https://www.arup.com/en-us/projects/marina-bay-sands-integrated-resort/"
var _built := false
var _frame: RefCounted
var _plan: Dictionary = {}
var _report: Dictionary = {}
var _base := 0.0
var _projection_error := ""
var _facade_faces := PackedVector3Array()
var _roof_faces := PackedVector3Array()
var _barrier_boxes: Array[Dictionary] = []
var _surface_patches: Array[Dictionary] = []
var facade_bodies: Array[StaticBody3D] = []
var roof_body: StaticBody3D

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

static func _hash(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(JSON.stringify(value,"",true,true).to_utf8_buffer())
	return hash.finish().hex_encode()

static func _point(value: Variant, count: int) -> bool:
	if not value is Array or value.size()!=count:return false
	for component: Variant in value:
		if not _number(component):return false
	return true

static func _own_to_common(tower: Dictionary, point: Array) -> Array:
	var u: Array=tower.axis_south;var v: Array=tower.axis_bayward;var center: Array=tower.center_common_xz
	return [float(center[0])+float(u[0])*float(point[0])+float(v[0])*float(point[1]),float(center[1])+float(u[1])*float(point[0])+float(v[1])*float(point[1])]

static func _canonical(point: Array,base: float) -> Array:
	var origin: Array=Reference.DATA.origin_world_xz;var u: Array=Reference.DATA.axis_south_xz;var v: Array=Reference.DATA.axis_bayward_xz
	return [float(origin[0])+float(u[0])*float(point[0])+float(v[0])*float(point[2]),base+float(point[1]),float(origin[1])+float(u[1])*float(point[0])+float(v[1])*float(point[2])]

## Offset computation uses source doubles BEFORE any Vector is constructed.
static func _tower(source: Dictionary) -> Dictionary:
	var name: String=source.tower;var axes: Dictionary=AXES[name]
	var center: Array=source.centroid_world_xz
	var common: Array=source.centroid_local_xz.duplicate()
	var u: Array=axes.south;var v: Array=axes.bayward
	var ring: Array=[];var bounds: Array=[INF,INF,-INF,-INF]
	var source_ring: Array=source.footprint_rings_world_xz[0].duplicate(true)
	if source_ring.front()==source_ring.back():source_ring.pop_back()
	for xy: Array in source_ring:
		var dx: float=float(xy[0])-float(center[0]);var dz: float=float(xy[1])-float(center[1])
		var common_u: float=dx*float(Reference.DATA.axis_south_xz[0])+dz*float(Reference.DATA.axis_south_xz[1])
		var common_v: float=dx*float(Reference.DATA.axis_bayward_xz[0])+dz*float(Reference.DATA.axis_bayward_xz[1])
		var own: Array=[common_u*float(u[0])+common_v*float(u[1]),common_u*float(v[0])+common_v*float(v[1])]
		ring.append(own)
		bounds=[minf(bounds[0],own[0]),minf(bounds[1],own[1]),maxf(bounds[2],own[0]),maxf(bounds[3],own[1])]
	return {"tower":name,"source_id":source.id,"source_ground_ring_world_xz":source_ring,"center_common_xz":common,"axis_south":u.duplicate(),"axis_bayward":v.duplicate(),"ground_own_ring":ring,"ground_own_bounds":bounds,"source_height_tag_m":193.0,"source_height_status":"source_tag_NOT_SURVEYED","upper_depth_m":TOP_DEPTH,"upper_status":"RECONSTRUCTED_CANDIDATE_NOT_METRIC_ASBUILT","mask":VOID_MASKS[name].duplicate(true)}

static func _profile_point(tower: Dictionary,index: int,y: float) -> Array:
	var p: Array=tower.ground_own_ring[index]
	var bounds: Array=tower.ground_own_bounds
	var cross: float=float(bounds[3])-float(bounds[1])
	var t: float=clampf(y/LINK_HEIGHT,0.0,1.0)
	# Smooth east-leg curve; west edge stays fixed. The exact curvature is an
	# explicit reconstruction, not traced Arup artwork or surveyed structure.
	var ease: float=t*(2.0-t)
	var target_scale: float=lerpf(1.0,TOP_DEPTH/cross,ease)
	var own: Array=[float(p[0]),float(bounds[3])+(float(p[1])-float(bounds[3]))*target_scale]
	return _own_to_common(tower,own)

static func profile_ring(tower: Dictionary,y: float) -> Array:
	var ring: Array=[]
	for index in tower.ground_own_ring.size():ring.append(_profile_point(tower,index,y))
	return ring

static func _own_rect(tower: Dictionary,center: Array,size: Array) -> Array:
	var result: Array=[]
	for sign: Array in [[-1.0,-1.0],[1.0,-1.0],[1.0,1.0],[-1.0,1.0]]:
		result.append(_own_to_common(tower,[float(center[0])+float(sign[0])*float(size[0])*.5,float(center[1])+float(sign[1])*float(size[1])*.5]))
	return result

static func _bank(tower: Dictionary) -> Dictionary:
	var layout: Dictionary=CoreLayout.for_tower(String(tower.tower))
	if not layout.get("valid",false):return layout
	layout["ring_common_xz"]=[]
	for point: Array in layout.own_bank_polygon:layout.ring_common_xz.append(_own_to_common(tower,point))
	for component: Dictionary in layout.components:
		component["ring_common_xz"]=[]
		for point: Array in component.own_operational_polygon:component.ring_common_xz.append(_own_to_common(tower,point))
	layout["current_common_axis_atrium_masks_compatible"]=false
	layout["requires_individual_tower_floor_and_mask_relayout"]=true
	return layout

static func _distance(a: Array,b: Array) -> float:
	return sqrt(pow(float(a[0])-float(b[0]),2.0)+pow(float(a[1])-float(b[1]),2.0))

static func _boat(towers: Array) -> Dictionary:
	var knots: Array=[]
	for tower: Dictionary in towers:
		var bounds: Array=tower.ground_own_bounds
		var mid_cross: float=float(bounds[3])-TOP_DEPTH*.5
		var start: float=float(bounds[0])+(4.0 if tower.tower=="T3" else 0.0)
		knots.append(_own_to_common(tower,[start,mid_cross]))
		knots.append(_own_to_common(tower,[float(bounds[2]),mid_cross]))
	var u: Array=towers[0].axis_south
	var support: Array=knots.front().duplicate()
	var north: Array=[float(support[0])-float(u[0])*NORTH_CANTILEVER,float(support[1])-float(u[1])*NORTH_CANTILEVER]
	var line: Array=[north]
	line.append_array(knots)
	var total: float=0.0
	for index in line.size()-1:total+=_distance(line[index],line[index+1])
	var tail_axis: Array=towers.back().axis_south
	var tail: Array=line.back()
	var extension: float=BOAT_LENGTH-total
	line.append([float(tail[0])+float(tail_axis[0])*extension,float(tail[1])+float(tail_axis[1])*extension])
	var distances: Array=[0.0]
	for index in line.size()-1:distances.append(float(distances.back())+_distance(line[index],line[index+1]))
	return {"centerline_common_xz":line,"station_distances_m":distances,"length_m":float(distances.back()),"nominal_deck_width_m":BOAT_DECK_WIDTH,"maximum_hull_width_m":BOAT_MAX_WIDTH,"north_cantilever_m":NORTH_CANTILEVER,"bearing_station_m":NORTH_CANTILEVER,"bearing_line_common_xz":support,"bearing_line_status":"RECONSTRUCTED_INSIDE_T3_SOURCE_UPPER_NOT_SURVEYED_COLUMN_XY","observation_elevation_m":OBSERVATION_Y,"park_elevation_m":PARK_Y,"low_terrace_end_station_m":LOW_DECK_END,"stair_end_station_m":LOW_DECK_END+ROOF_STAIR_RUN,"roof_connection_status":"RECONSTRUCTED_REAL_STAIRS_NOT_ASBUILT_CIRCULATION"}

static func _packed(ring: Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for point: Array in ring:result.append(Vector2(float(point[0]),float(point[1])))
	return result

static func _area(ring: PackedVector2Array) -> float:
	var result: float=0.0
	for index in ring.size():result+=ring[index].cross(ring[(index+1)%ring.size()])
	return result*.5

static func _inside(point: Array,ring: Array) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(float(point[0]),float(point[1])),_packed(ring))

static func _apertures(config: Dictionary,towers: Array) -> Dictionary:
	var raw: Variant=config.get("facade_apertures",[])
	if not raw is Array or raw.size()>MAX_APERTURES:return {"valid":false,"error":"Bounded explicit facade apertures required."}
	var seen: Dictionary={};var result: Array=[]
	for item: Variant in raw:
		if not item is Dictionary:return {"valid":false,"error":"Facade aperture must be a dictionary."}
		for key in item:
			if key not in ["id","tower","edge_index","u0","u1","y0_m","y1_m"]:return {"valid":false,"error":"Unknown aperture key."}
		if not item.get("id") is String or String(item.id).is_empty() or seen.has(item.id) or not item.get("tower") is String or not AXES.has(item.tower):return {"valid":false,"error":"Unique aperture ID and actual source tower required."}
		if not typeof(item.get("edge_index"))==TYPE_INT:return {"valid":false,"error":"Actual source ring edge index required."}
		for key in ["u0","u1","y0_m","y1_m"]:
			if not _number(item.get(key)):return {"valid":false,"error":"Finite aperture extent required."}
		var tower: Dictionary={}
		for t: Dictionary in towers:
			if t.tower==item.tower:tower=t
		if item.edge_index<0 or item.edge_index>=tower.ground_own_ring.size() or float(item.u0)<0 or float(item.u1)>1 or float(item.u1)<=float(item.u0) or float(item.y0_m)<0 or float(item.y1_m)>OBSERVATION_Y or float(item.y1_m)-float(item.y0_m)<1.8:return {"valid":false,"error":"Aperture is outside source edge/profile or lacks human headroom."}
		var edge: float=_distance(_profile_point(tower,item.edge_index,0),_profile_point(tower,(item.edge_index+1)%tower.ground_own_ring.size(),0))
		if edge*(float(item.u1)-float(item.u0))<1.2:return {"valid":false,"error":"Opening narrower than full-size accessible passage."}
		seen[item.id]=true;result.append(item.duplicate(true))
	return {"valid":true,"values":result}

static func reference_plan(config: Dictionary={}) -> Dictionary:
	for key in config:
		if key not in ["base_elevation_m","base_elevation_provenance","facade_apertures","roof_apertures","collision_enabled"]:return {"valid":false,"error":"Unknown shell configuration field: "+str(key)}
	var base: Variant=config.get("base_elevation_m",0.0)
	if not _number(base) or absf(float(base))>1000.0:return {"valid":false,"error":"Finite source base required."}
	if config.has("base_elevation_m") and (not config.get("base_elevation_provenance") is String or String(config.base_elevation_provenance).is_empty()):return {"valid":false,"error":"Explicit base requires datum provenance."}
	if config.has("collision_enabled") and not config.collision_enabled is bool:return {"valid":false,"error":"Collision policy must be explicit boolean."}
	var towers: Array=[];var banks: Array=[]
	for source: Dictionary in Reference.DATA.towers:
		if not AXES.has(source.tower) or String(AXES[source.tower].source_id)!=String(source.id):return {"valid":false,"error":"Source tower IDs changed; re-audit individual axes."}
		var tower: Dictionary=_tower(source);towers.append(tower);banks.append(_bank(tower))
	var openings: Dictionary=_apertures(config,towers)
	if not openings.valid:return openings
	var holes: Array=[];var ids: Dictionary={}
	# Operational core poses are defined but not integrated; only explicit Root reservations
	# create openings. Default reference geometry has NO collision.
	var custom: Variant=config.get("roof_apertures",[])
	if not custom is Array or custom.size()>MAX_APERTURES:return {"valid":false,"error":"Bounded explicit roof aperture array required."}
	for item: Variant in custom:
		if not item is Dictionary or not item.get("id") is String or String(item.id).is_empty() or not item.get("ring_common_xz") is Array:return {"valid":false,"error":"Roof opening needs ID and canonical-offset polygon."}
		var ring: Array=item.ring_common_xz
		if ring.size()<3 or ring.size()>12:return {"valid":false,"error":"Bounded convex roof opening required."}
		for point: Variant in ring:
			if not _point(point,2) or absf(float(point[0]))>400 or absf(float(point[1]))>150:return {"valid":false,"error":"Invalid roof aperture coordinate."}
		if not Geometry2D.is_polygon_clockwise(_packed(ring)):ring=ring.duplicate(true)
		if absf(_area(_packed(ring)))<.2 or not Geometry2D.decompose_polygon_in_convex(_packed(ring)).size()==1:return {"valid":false,"error":"Roof opening must be nondegenerate convex polygon."}
		holes.append({"id":item.id,"ring_common_xz":ring.duplicate(true),"purpose":"explicit_root_roof_aperture","factory_alignment_verified":false})
	for hole: Dictionary in holes:
		if ids.has(hole.id):return {"valid":false,"error":"Duplicate roof aperture ID."}
		ids[hole.id]=true
	var result: Dictionary={"valid":true,"schema":SCHEMA,"base_elevation_m":float(base),"base_elevation_provenance":config.get("base_elevation_provenance","STAGING zero relative datum, NOT surveyed"),"source":Reference.DATA.source.duplicate(true),"towers":towers,"core_bank_candidates":banks,"boat":_boat(towers),"facade_apertures":openings.values,"roof_apertures":holes,"collision_enabled":config.get("collision_enabled",false),"physical_build_requires_explicit_root_masks":true,"source_ground_rings_preserved":true,"roof_and_profile_status":"ORIGINAL_RECONSTRUCTION_CONSTRAINED_BY_PUBLISHED_STRUCTURE_AND_SOURCE_GROUND","whole_building_integrated":false,"interior_factory_alignment_verified":false,"requires_root_factory_contract":{"exterior_face_owner":"persistent_shell","individual_tower_basis_required":true,"current_constant_rectangle_must_not_be_widened":true,"core_entry_side_must_be_explicit":true,"required_unit_ids_and_programs_must_be_preserved":true,"roof_apertures_need_matching_receivers_and_occupancy_guards":true},"unresolved":["Current rectangular floors/core portals require source-conforming relayout","Every preserved private room/program needs native fit and circulation proof","Exact 2026 facade/refurbishment/interior details are not surveyed","Source-based arrival/loft masks need coupled native proof","Roof water/program fit and receiving apertures require Root integration"],"historical_sources":[{"url":ARUP_PDF,"pages":[16,17,18,19,24,25,26,27,28,29,30],"facts":"historical curved east/vertical west, 340m, max40m, 66.5m north cantilever, 191/195m public levels"},{"url":ARUP_PROJECT,"facts":"nominal38m width,340m length"}],"dry_volumes":[],"moves_actors":false,"commits_source_frame":false}
	result["geometry_sha256"]=_hash(result)
	return result

## A synchronous geometry snapshot, not a rebase. Root owns its lifetime and
## any later source-frame transaction; this component never repositions actors.
func build(frame: RefCounted,config: Dictionary={}) -> Dictionary:
	if _built or not is_inside_tree() or frame==null or not frame.has_method("to_local") or not frame.metadata().get("configured",false):return {"built":false,"error":"Fresh in-tree shell and configured source frame required."}
	if not global_transform.is_equal_approx(Transform3D.IDENTITY):return {"built":false,"error":"Source shell attaches at the common untransformed SourceFrame root."}
	var planned: Dictionary=reference_plan(config)
	if not planned.valid:return {"built":false,"error":planned.error}
	if planned.collision_enabled and (not config.has("facade_apertures") or not config.has("roof_apertures") or planned.roof_apertures.is_empty()):return {"built":false,"error":"Physical shell requires explicit matching facade/roof reservations; unresolved candidate banks are never silently capped."}
	_frame=frame;_plan=planned;_base=float(planned.base_elevation_m)
	var epoch: int=int(frame.metadata().origin_revision)
	var glass=Kit.new();var trim=Kit.new();var roof=Kit.new();var hull=Kit.new()
	_build_towers(glass,trim)
	_build_boat(roof,hull,trim)
	if not _projection_error.is_empty():return {"built":false,"error":_projection_error}
	if int(frame.metadata().origin_revision)!=epoch:return {"built":false,"error":"Source frame changed during staged geometry; rebuild snapshot."}
	if glass.tris+trim.tris+roof.tris+hull.tris>180000 or _roof_faces.size()>120000 or _facade_faces.size()>150000:return {"built":false,"error":"Bounded source geometry budget exceeded before commit."}
	glass.commit(self,"SourceTowerCurtainGlass",true)
	trim.commit(self,"SourceTowerFramesAndRoofGuards",true)
	roof.commit(self,"SourceSkyParkSupportedDeck",true)
	hull.commit(self,"SourceBoatStructuralHull",true)
	if planned.collision_enabled:
		var facade:=_body("SourceExteriorFacadeCollision",_facade_faces)
		if facade!=null:facade_bodies.append(facade)
		var barrier:=StaticBody3D.new();barrier.name="SourceRoofBarrierCollision";barrier.collision_layer=1;barrier.collision_mask=0
		add_child(barrier)
		for item: Dictionary in _barrier_boxes:
			var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=item.size;shape.shape=box;shape.transform=item.transform;barrier.add_child(shape)
		if not _barrier_boxes.is_empty():facade_bodies.append(barrier)
		else:barrier.queue_free()
		roof_body=_body("SourceRoofSupportCollision",_roof_faces)
	_built=true
	_report={"built":true,"schema":SCHEMA,"geometry_sha256":planned.geometry_sha256,"frame_instance_id":frame.get_instance_id(),"origin_revision":epoch,"plan":planned.duplicate(true),"triangle_count":glass.tris+trim.tris+roof.tris+hull.tris,"roof_collision_triangle_count":_roof_faces.size()/3,"facade_collision_triangle_count":_facade_faces.size()/3,"barrier_shape_count":_barrier_boxes.size(),"roof_surface_patches":_surface_patches.duplicate(true),"facade_body_count":facade_bodies.size(),"roof_body_present":is_instance_valid(roof_body),"native_collision_committed":false,"source_support_registered":false,"dry_volumes":[],"whole_building_integrated":false,"interior_factory_alignment_verified":false,"gameplay_or_visual_acceptance":"NOT_TESTED"}
	return report()

func _v(point: Array) -> Vector3:
	var projected: Dictionary=_frame.to_local(_canonical(point,_base))
	if not projected.get("ok",false):_projection_error=String(projected.get("error","Source projection failed"));return Vector3.ZERO
	return projected.position

func _body(body_name: String,faces: PackedVector3Array) -> StaticBody3D:
	if faces.is_empty():return null
	var body:=StaticBody3D.new();body.name=body_name;body.collision_layer=1;body.collision_mask=0
	var shape:=CollisionShape3D.new();var mesh:=ConcavePolygonShape3D.new();mesh.set_faces(faces);mesh.backface_collision=true;shape.shape=mesh;body.add_child(shape);add_child(body)
	return body

func _tri(kit,material: Material,a: Array,b: Array,c: Array,faces: String="") -> void:
	var va: Vector3=_v(a);var vb: Vector3=_v(b);var vc: Vector3=_v(c)
	if (vb-va).cross(vc-va).length_squared()<.00000001:return
	kit.tri(material,va,vb,vc)
	if faces=="roof":_roof_faces.append_array([va,vc,vb])
	elif faces=="facade":_facade_faces.append_array([va,vc,vb])

func _poly(kit,material: Material,points: Array,faces: String="") -> void:
	for index in range(1,points.size()-1):_tri(kit,material,points[0],points[index],points[index+1],faces)

func _beam(kit,material: Material,a: Array,b: Array,width: float,height: float,collision: bool=false) -> void:
	var va: Vector3=_v(a);var vb: Vector3=_v(b);kit.beam(material,va,vb,width,height)
	if not collision:return
	var delta: Vector3=vb-va
	if delta.length()<.001:return
	var z: Vector3=delta.normalized();var x: Vector3=Vector3.UP.cross(z).normalized()
	if x.length_squared()<.01:x=Vector3.RIGHT
	var y: Vector3=z.cross(x).normalized()
	_barrier_boxes.append({"size":Vector3(width,height,delta.length()),"transform":Transform3D(Basis(x,y,z),(va+vb)*.5)})

static func _lerp_point(a: Array,b: Array,t: float) -> Array:
	return [lerpf(float(a[0]),float(b[0]),t),lerpf(float(a[1]),float(b[1]),t)]

static func _clip_z(points: Array,boundary: float,keep_above: bool) -> Array:
	var result: Array=[]
	if points.is_empty():return result
	var previous: Array=points.back();var previous_inside: bool=float(previous[2])>=boundary-.000001 if keep_above else float(previous[2])<=boundary+.000001
	for current: Array in points:
		var inside: bool=float(current[2])>=boundary-.000001 if keep_above else float(current[2])<=boundary+.000001
		if inside!=previous_inside:
			var t: float=(boundary-float(previous[2]))/(float(current[2])-float(previous[2]))
			result.append([lerpf(previous[0],current[0],t),lerpf(previous[1],current[1],t),boundary])
		if inside:result.append(current)
		previous=current;previous_inside=inside
	return result

func _facade_panel(kit,material: Material,tower: Dictionary,points: Array,y1: float) -> void:
	var mask: Dictionary=tower.mask
	if y1<=float(mask.top_y)+.00001:
		for polygon: Array in [_clip_z(points,float(tower.center_common_xz[1])+float(mask.min_z),false),_clip_z(points,float(tower.center_common_xz[1])+float(mask.max_z),true)]:_poly(kit,material,polygon,"facade")
	else:_poly(kit,material,points,"facade")

func _is_open(tower: String,edge: int,u0: float,u1: float,y0: float,y1: float) -> bool:
	for aperture: Dictionary in _plan.facade_apertures:
		if aperture.tower==tower and aperture.edge_index==edge and u0>=float(aperture.u0)-.000001 and u1<=float(aperture.u1)+.000001 and y0>=float(aperture.y0_m)-.000001 and y1<=float(aperture.y1_m)+.000001:return true
	return false

func _build_towers(glass,trim) -> void:
	var glazing: Material=Looks.get_mat("glass_clear");var metal: Material=Looks.get_mat("steel_white")
	for tower: Dictionary in _plan.towers:
		var heights: Array=[0.0,LINK_HEIGHT,float(tower.mask.top_y),OBSERVATION_Y]
		var y: float=1.55
		while y<OBSERVATION_Y:heights.append(y);y+=3.45
		for aperture: Dictionary in _plan.facade_apertures:
			if aperture.tower==tower.tower:heights.append(float(aperture.y0_m));heights.append(float(aperture.y1_m))
		heights.sort();var levels: Array=[]
		for value: float in heights:
			if levels.is_empty() or absf(float(levels.back())-value)>.0001:levels.append(value)
		for edge in tower.ground_own_ring.size():
			var next: int=(edge+1)%tower.ground_own_ring.size()
			var edge_length: float=_distance(_profile_point(tower,edge,0),_profile_point(tower,next,0))
			var us: Array=[0.0,1.0];var divisions: int=maxi(1,ceili(edge_length/2.8))
			for step in range(1,divisions):us.append(float(step)/float(divisions))
			for aperture: Dictionary in _plan.facade_apertures:
				if aperture.tower==tower.tower and aperture.edge_index==edge:us.append(float(aperture.u0));us.append(float(aperture.u1))
			us.sort();var parameters: Array=[]
			for value: float in us:
				if parameters.is_empty() or absf(float(parameters.back())-value)>.00001:parameters.append(value)
			for level in levels.size()-1:
				var y0: float=levels[level];var y1: float=levels[level+1]
				var a0: Array=_profile_point(tower,edge,y0);var b0: Array=_profile_point(tower,next,y0);var a1: Array=_profile_point(tower,edge,y1);var b1: Array=_profile_point(tower,next,y1)
				for part in parameters.size()-1:
					var u0: float=parameters[part];var u1: float=parameters[part+1]
					if _is_open(String(tower.tower),edge,u0,u1,y0,y1):continue
					var p0: Array=_lerp_point(a0,b0,u0);var p1: Array=_lerp_point(a0,b0,u1);var p2: Array=_lerp_point(a1,b1,u1);var p3: Array=_lerp_point(a1,b1,u0)
					var points: Array=[[p0[0],y0,p0[1]],[p1[0],y0,p1[1]],[p2[0],y1,p2[1]],[p3[0],y1,p3[1]]]
					_facade_panel(glass,glazing,tower,points,y1)
				# Profile-aligned mullions stop at the same atrium mask; no visible bar
				# or hidden collider stretches across an intentionally open public loft.
				for u_value: float in parameters:
					var p0: Array=_lerp_point(a0,b0,u_value);var p1: Array=_lerp_point(a1,b1,u_value)
					if y1<=float(tower.mask.top_y)+.00001 and maxf(p0[1],p1[1])>float(tower.center_common_xz[1])+float(tower.mask.min_z) and minf(p0[1],p1[1])<float(tower.center_common_xz[1])+float(tower.mask.max_z):continue
					if _is_open(String(tower.tower),edge,maxf(0.0,u_value-.00001),minf(1.0,u_value+.00001),y0,y1):continue
					_beam(trim,metal,[p0[0],y0,p0[1]],[p1[0],y1,p1[1]],.075,.075)
			for aperture: Dictionary in _plan.facade_apertures:
				if aperture.tower!=tower.tower or aperture.edge_index!=edge:continue
				var lower_a: Array=_lerp_point(_profile_point(tower,edge,aperture.y0_m),_profile_point(tower,next,aperture.y0_m),aperture.u0)
				var lower_b: Array=_lerp_point(_profile_point(tower,edge,aperture.y0_m),_profile_point(tower,next,aperture.y0_m),aperture.u1)
				var upper_a: Array=_lerp_point(_profile_point(tower,edge,aperture.y1_m),_profile_point(tower,next,aperture.y1_m),aperture.u0)
				var upper_b: Array=_lerp_point(_profile_point(tower,edge,aperture.y1_m),_profile_point(tower,next,aperture.y1_m),aperture.u1)
				_beam(trim,metal,[lower_a[0],aperture.y0_m,lower_a[1]],[upper_a[0],aperture.y1_m,upper_a[1]],.10,.10)
				_beam(trim,metal,[lower_b[0],aperture.y0_m,lower_b[1]],[upper_b[0],aperture.y1_m,upper_b[1]],.10,.10)
				_beam(trim,metal,[upper_a[0],aperture.y1_m,upper_a[1]],[upper_b[0],aperture.y1_m,upper_b[1]],.10,.10)

static func _at(boat: Dictionary,distance: float) -> Dictionary:
	var distances: Array=boat.station_distances_m;var line: Array=boat.centerline_common_xz
	for index in distances.size()-1:
		if distance<=float(distances[index+1])+.00001:
			var a: Array=line[index];var b: Array=line[index+1];var length: float=float(distances[index+1])-float(distances[index]);var t: float=clampf((distance-float(distances[index]))/length,0.0,1.0)
			return {"point":_lerp_point(a,b,t),"tangent":[(float(b[0])-float(a[0]))/length,(float(b[1])-float(a[1]))/length]}
	var a: Array=line[-2];var b: Array=line[-1];var length: float=_distance(a,b)
	return {"point":b.duplicate(),"tangent":[(float(b[0])-float(a[0]))/length,(float(b[1])-float(a[1]))/length]}

static func _boat_edge(boat: Dictionary,distance: float,side: float,width: float) -> Array:
	var at: Dictionary=_at(boat,distance);var p: Array=at.point;var t: Array=at.tangent
	# Narrow rounded north nose; full-width stern avoids clipping the T1 roof.
	var half: float=width*.5*sin(minf(distance/14.0,1.0)*PI*.5)
	return [float(p[0])-float(t[1])*half*side,float(p[1])+float(t[0])*half*side]

static func _cross(a: Vector2,b: Vector2,p: Vector2) -> float:
	return (b-a).cross(p-a)

static func _clip_line(poly: PackedVector2Array,a: Vector2,b: Vector2,inside: bool,orientation: float) -> PackedVector2Array:
	var result:=PackedVector2Array()
	if poly.is_empty():return result
	var previous: Vector2=poly[-1];var dp: float=_cross(a,b,previous)*orientation;var was_in: bool=dp>=-.000001 if inside else dp<=.000001
	for current: Vector2 in poly:
		var dc: float=_cross(a,b,current)*orientation;var is_in: bool=dc>=-.000001 if inside else dc<=.000001
		if is_in!=was_in:
			var ratio: float=dp/(dp-dc);result.append(previous.lerp(current,ratio))
		if is_in:result.append(current)
		previous=current;dp=dc;was_in=is_in
	return result

static func _subtract(poly: PackedVector2Array,hole: PackedVector2Array) -> Array:
	var remaining: PackedVector2Array=poly;var result: Array=[]
	var orientation: float=1.0 if _area(hole)>0 else -1.0
	for index in hole.size():
		var a: Vector2=hole[index];var b: Vector2=hole[(index+1)%hole.size()]
		var outside: PackedVector2Array=_clip_line(remaining,a,b,false,orientation)
		if outside.size()>=3 and absf(_area(outside))>.00001:result.append(outside)
		remaining=_clip_line(remaining,a,b,true,orientation)
		if remaining.size()<3:break
	return result

func _roof_patch(kit,material: Material,ring: Array,y: float,id: String) -> void:
	var pieces: Array=[_packed(ring)]
	for aperture: Dictionary in _plan.roof_apertures:
		var next: Array=[]
		for piece: PackedVector2Array in pieces:next.append_array(_subtract(piece,_packed(aperture.ring_common_xz)))
		pieces=next
	for polygon: PackedVector2Array in pieces:
		if polygon.size()<3:continue
		var points: Array=[];var footprint: Array=[]
		# Fan only convex clipped pieces; source canonical roof polygons remain in
		# report, and the identical triangles become actual native collision.
		if _area(polygon)<0:polygon.reverse()
		for point: Vector2 in polygon:points.append([float(point.x),y,float(point.y)]);footprint.append([float(point.x),float(point.y)])
		points.reverse() # Upward right-hand normal in X/Y/Z from X/Z polygon.
		_poly(kit,material,points,"roof")
		_surface_patches.append({"surface_id":id,"elevation_m":_base+y,"ring_common_xz":footprint,"source_ring_xyz":footprint.map(func(p: Array)->Array:return _canonical([p[0],y,p[1]],_base)),"dry":false,"role":"actual_architectural_support_NOT_complete_interior"})

func _build_boat(deck,hull,trim) -> void:
	var boat: Dictionary=_plan.boat;var stations: Array=[0.0,14.0,LOW_DECK_END,LOW_DECK_END+ROOF_STAIR_RUN,BOAT_LENGTH]
	stations.append_array(boat.station_distances_m)
	var d: float=2.0
	while d<BOAT_LENGTH:stations.append(d);d+=2.0
	stations.sort();var values: Array=[]
	for station: float in stations:
		if values.is_empty() or absf(float(values.back())-station)>.00001:values.append(station)
	var stone: Material=Looks.get_mat("granite_light");var hull_mat: Material=Looks.get_mat("hull_panel");var rail: Material=Looks.get_mat("steel_satin")
	for index in values.size()-1:
		var d0: float=values[index];var d1: float=values[index+1]
		var a: Array=_boat_edge(boat,d0,-1,BOAT_DECK_WIDTH);var b: Array=_boat_edge(boat,d0,1,BOAT_DECK_WIDTH);var c: Array=_boat_edge(boat,d1,1,BOAT_DECK_WIDTH);var e: Array=_boat_edge(boat,d1,-1,BOAT_DECK_WIDTH)
		var height: float=OBSERVATION_Y if d1<=LOW_DECK_END+.0001 else PARK_Y
		if d0>=LOW_DECK_END+ROOF_STAIR_RUN-.0001 or d1<=LOW_DECK_END+.0001:_roof_patch(deck,stone,[a,e,c,b],height,"north-observation" if height==OBSERVATION_Y else "main-skypark")
		# Cantilever depth is reconstructed within published3.55..10m family;
		# no solid cube occupies the L56 service/restaurant rooms inside this hull.
		var depth0: float=3.55+6.45*minf(d0/NORTH_CANTILEVER,1.0);var depth1: float=3.55+6.45*minf(d1/NORTH_CANTILEVER,1.0)
		for side: float in [-1.0,1.0]:
			var top0: Array=_boat_edge(boat,d0,side,BOAT_MAX_WIDTH);var top1: Array=_boat_edge(boat,d1,side,BOAT_MAX_WIDTH)
			var bottom0: Array=_boat_edge(boat,d0,side,24.0);var bottom1: Array=_boat_edge(boat,d1,side,24.0)
			_poly(hull,hull_mat,[[top0[0],height-.24,top0[1]],[bottom0[0],height-depth0,bottom0[1]],[bottom1[0],height-depth1,bottom1[1]],[top1[0],height-.24,top1[1]]])
			if d1<=LOW_DECK_END+.0001 or d0>=LOW_DECK_END+ROOF_STAIR_RUN-.0001:
				var p0: Array=_boat_edge(boat,d0,side,BOAT_DECK_WIDTH);var p1: Array=_boat_edge(boat,d1,side,BOAT_DECK_WIDTH)
				_beam(trim,rail,[p0[0],height+1.10,p0[1]],[p1[0],height+1.10,p1[1]],.045,.045)
				# Continuous physical glass guard; not a traversable support body.
				_beam(trim,Looks.get_mat("glass_clear"),[p0[0],height+.56,p0[1]],[p1[0],height+.56,p1[1]],.065,1.12,true)
		var lower_a: Array=_boat_edge(boat,d0,-1,24.0);var lower_b: Array=_boat_edge(boat,d0,1,24.0);var lower_c: Array=_boat_edge(boat,d1,1,24.0);var lower_d: Array=_boat_edge(boat,d1,-1,24.0)
		_poly(hull,hull_mat,[[lower_a[0],height-depth0,lower_a[1]],[lower_b[0],height-depth0,lower_b[1]],[lower_c[0],height-depth1,lower_c[1]],[lower_d[0],height-depth1,lower_d[1]]])
	_build_roof_stairs(deck,trim)
	# Stern closure is a thin face; no cap closes vertical circulation holes.
	var left: Array=_boat_edge(boat,BOAT_LENGTH,-1,BOAT_MAX_WIDTH);var right: Array=_boat_edge(boat,BOAT_LENGTH,1,BOAT_MAX_WIDTH)
	_poly(hull,hull_mat,[[left[0],PARK_Y-.24,left[1]],[left[0],PARK_Y-10,left[1]],[right[0],PARK_Y-10,right[1]],[right[0],PARK_Y-.24,right[1]]])
	_beam(trim,rail,[left[0],PARK_Y+.56,left[1]],[right[0],PARK_Y+.56,right[1]],.065,1.12,true)

func _build_roof_stairs(deck,trim) -> void:
	var boat: Dictionary=_plan.boat;var stone: Material=Looks.get_mat("granite_light");var rail: Material=Looks.get_mat("steel_satin")
	var rise: float=(PARK_Y-OBSERVATION_Y)/ROOF_STAIR_COUNT
	for step in ROOF_STAIR_COUNT:
		var d0: float=LOW_DECK_END+ROOF_STAIR_RUN*float(step)/ROOF_STAIR_COUNT;var d1: float=LOW_DECK_END+ROOF_STAIR_RUN*float(step+1)/ROOF_STAIR_COUNT;var y: float=OBSERVATION_Y+rise*float(step+1)
		var a: Array=_boat_edge(boat,d0,-1,ROOF_STAIR_WIDTH);var b: Array=_boat_edge(boat,d0,1,ROOF_STAIR_WIDTH);var c: Array=_boat_edge(boat,d1,1,ROOF_STAIR_WIDTH);var e: Array=_boat_edge(boat,d1,-1,ROOF_STAIR_WIDTH)
		_roof_patch(deck,stone,[a,e,c,b],y,"north-main-connecting-stair-"+str(step))
		_poly(deck,stone,[[a[0],y-rise,a[1]],[b[0],y-rise,b[1]],[b[0],y,b[1]],[a[0],y,a[1]]],"roof")
		for side: float in [-1.0,1.0]:
			var p0: Array=_boat_edge(boat,d0,side,ROOF_STAIR_WIDTH);var p1: Array=_boat_edge(boat,d1,side,ROOF_STAIR_WIDTH)
			_beam(trim,rail,[p0[0],y+.55,p0[1]],[p1[0],y+.55,p1[1]],.055,1.1,true)
	for station: float in [LOW_DECK_END,LOW_DECK_END+ROOF_STAIR_RUN]:
		var y: float=OBSERVATION_Y if station==LOW_DECK_END else PARK_Y
		for side: float in [-1.0,1.0]:
			var inner: Array=_boat_edge(boat,station,side,ROOF_STAIR_WIDTH);var outer: Array=_boat_edge(boat,station,side,BOAT_DECK_WIDTH)
			_beam(trim,rail,[inner[0],y+.55,inner[1]],[outer[0],y+.55,outer[1]],.055,1.1,true)

func collision_bodies() -> Array:
	var result: Array=[]
	result.append_array(facade_bodies)
	if is_instance_valid(roof_body):result.append(roof_body)
	return result

func roof_support_body() -> StaticBody3D:
	return roof_body

func report() -> Dictionary:
	return _report.duplicate(true)
