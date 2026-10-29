extends RefCounted
## Versioned, source-conforming hotel allocation boundary. The deterministic
## authoring compiler is plan_source_floors.py; this validates its full inventory
## and physical reservations before Root's source floor factory consumes them.
## No geometry/actor/save mutation occurs here. Undocumented interiors are a
## disclosed reconstruction, never surveyed/as-built rooms.
const Inventory=preload("res://src/world/mbs_interior/inventory.gd")
const Exterior=preload("res://src/world/mbs_interior/exterior_shell.gd")
const Cores=preload("res://src/world/mbs_interior/source_core_layout.gd")
const SCHEMA:="mbs_source_floor_allocation_v1"
const MAX_FLOORS:=216
const MAX_ROOMS_PER_FLOOR:=32
var _document:Dictionary={}
var _report:Dictionary={}

static func _polygon(raw:Variant)->PackedVector2Array:
	var result:=PackedVector2Array()
	if not raw is Array or raw.size()<3 or raw.size()>32:return result
	for p:Variant in raw:
		if not p is Array or p.size()!=2:return PackedVector2Array()
		for n:Variant in p:
			if not typeof(n) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(n)):return PackedVector2Array()
		result.append(Vector2(float(p[0]),float(p[1])))
	return result

static func _area(poly:PackedVector2Array)->float:
	var sum:float=0.0
	for i in poly.size():sum+=poly[i].cross(poly[(i+1)%poly.size()])
	return absf(sum*.5)

static func _contained(outer:PackedVector2Array,inner:PackedVector2Array)->bool:
	if outer.size()<3 or inner.size()<3:return false
	# Full polygon subtraction, not corners-only containment.
	var pieces:Array[PackedVector2Array]=Geometry2D.clip_polygons(inner,outer)
	for piece:PackedVector2Array in pieces:
		if _area(piece)>.00001:return false
	return true

static func _overlap(a:PackedVector2Array,b:PackedVector2Array)->bool:
	if a.size()<3 or b.size()<3:return false
	for piece:PackedVector2Array in Geometry2D.intersect_polygons(a,b):
		if _area(piece)>.00001:return true
	return false

static func _profile_own(tower:Dictionary,height:float)->PackedVector2Array:
	var result:=PackedVector2Array();var center:Array=tower.center_common_xz;var u:Array=tower.axis_south;var v:Array=tower.axis_bayward
	for p:Array in Exterior.profile_ring(tower,height):
		var dx:float=float(p[0])-float(center[0]);var dz:float=float(p[1])-float(center[1])
		result.append(Vector2(dx*float(u[0])+dz*float(u[1]),dx*float(v[0])+dz*float(v[1])))
	return result

static func _same_polygon(a:PackedVector2Array,b:PackedVector2Array)->bool:
	if a.size()!=b.size():return false
	for index in a.size():
		if a[index].distance_to(b[index])>.0001:return false
	return true

func configure(document:Variant)->Dictionary:
	if not _document.is_empty():return {"configured":false,"error":"Use a fresh owned planner for a changed allocation."}
	if not document is Dictionary or document.get("schema","")!=SCHEMA:return {"configured":false,"error":"Invalid source allocation schema."}
	if document.get("source_inventory_sha256","")!=FileAccess.get_sha256(Inventory.PATH):return {"configured":false,"error":"Allocation inventory identity changed."}
	# Raw .gd hashes stay authoring provenance only: exported GDScript can be
	# compiled/remapped. Runtime validates actual profiles and core polygons.

	var floors:Variant=document.get("floors");var retained:Variant=document.get("program_records_retained_for_separate_source_polygon_planning")
	if not floors is Dictionary or floors.size()!=Inventory.guest_floor_ids().size() or floors.size()>MAX_FLOORS or not retained is Array:return {"configured":false,"error":"Complete bounded guest and program inventory required."}
	if not document.get("remaining_units") is Array or not document.remaining_units.is_empty():return {"configured":false,"error":"Unplaced rooms cannot become a completed allocation."}
	var source:Dictionary=Exterior.reference_plan();var towers:Dictionary={}
	if not source.get("valid",false):return {"configured":false,"error":"Source shell profile unavailable."}
	for tower:Dictionary in source.towers:towers[tower.tower]=tower
	var seen:Dictionary={};var moved:int=0;var cross_tower:int=0;var suites:int=0;var empty:Array[String]=[]
	for floor_id:String in Inventory.guest_floor_ids():
		if not floors.has(floor_id) or not floors[floor_id] is Dictionary:return {"configured":false,"error":"Missing exact guest floor: "+floor_id}
		var record:Dictionary=Inventory.floor_record(floor_id);var plan:Dictionary=floors[floor_id]
		if plan.get("floor_id")!=floor_id or plan.get("tower")!=record.tower or not is_equal_approx(float(plan.get("elevation_m",NAN)),float(record.elevation_m)):return {"configured":false,"error":"Floor identity/elevation mismatch: "+floor_id}
		if not plan.get("rooms") is Array or plan.rooms.is_empty() or plan.rooms.size()>MAX_ROOMS_PER_FLOOR:return {"configured":false,"error":"Unoccupied or unbounded original guest floor: "+floor_id}
		var base:PackedVector2Array=_profile_own(towers[record.tower],float(record.elevation_m));var top:PackedVector2Array=_profile_own(towers[record.tower],float(record.elevation_m)+float(record.geometry.clear_height_m))
		var core:Dictionary=Cores.for_tower(record.tower);var core_poly:PackedVector2Array=_polygon(core.own_bank_polygon)
		var declared_base:PackedVector2Array=_polygon(plan.get("source_floor_polygon"));var declared_top:PackedVector2Array=_polygon(plan.get("source_ceiling_polygon"));var declared_core:PackedVector2Array=_polygon(plan.get("core_bank_polygon"))
		if not _same_polygon(base,declared_base) or not _same_polygon(top,declared_top) or not _same_polygon(core_poly,declared_core):return {"configured":false,"error":"Allocation actual source/core geometry changed: "+floor_id}

		var void_poly:PackedVector2Array=_polygon(plan.get("lower_public_atrium_void",[]));var forbidden:Array[PackedVector2Array]=[core_poly]
		if not void_poly.is_empty():forbidden.append(void_poly)
		if not plan.get("corridors") is Array or plan.corridors.size()>12:return {"configured":false,"error":"Bounded explicit corridor inventory required."}
		for corridor:Variant in plan.corridors:
			if not corridor is Dictionary or float(corridor.get("clear_width_m",0))<2.60:return {"configured":false,"error":"Corridor narrows below the retained full-size route."}
			var poly:PackedVector2Array=_polygon(corridor.get("polygon"))
			if not _contained(base,poly) or not _contained(top,poly):return {"configured":false,"error":"Corridor exits source profile: "+floor_id}
			forbidden.append(poly)
		var spine:PackedVector2Array=_polygon(plan.get("bank_connector",[]))
		if not spine.is_empty():
			if not _contained(base,spine) or not _contained(top,spine):return {"configured":false,"error":"Core connector exits source profile."}
			forbidden.append(spine)
		var packed:Array[PackedVector2Array]=[]
		for room:Variant in plan.rooms:
			if not room is Dictionary or not room.get("id") is String or seen.has(room.id):return {"configured":false,"error":"Invalid or duplicate room ID."}
			var original:Dictionary=Inventory.unit_record(room.id)
			if original.is_empty() or room.get("unit")!=original or room.get("original_floor_id")!=original.floor_id or room.get("physical_floor_id")!=floor_id:return {"configured":false,"error":"Original room identity/type/bedroom inventory changed: "+String(room.id)}
			var poly:PackedVector2Array=_polygon(room.get("footprint_own_xz"))
			if not _contained(base,poly) or not _contained(top,poly):return {"configured":false,"error":"Room exits actual tapered source profile: "+String(room.id)}
			for obstruction:PackedVector2Array in forbidden+packed:
				if _overlap(poly,obstruction):return {"configured":false,"error":"Room crosses core, void, circulation or another room: "+String(room.id)}
			var profile:Variant=room.get("profile")
			if not profile is Dictionary:return {"configured":false,"error":"Explicit full-size furnishing profile missing."}
			var minimum_width:float=7.2 if original.bed_variant=="twin_queen" else 6.0
			var minimum_depth:float=7.0
			if original.is_suite:
				minimum_width={1:7.4,2:12.2,3:17.0}.get(int(original.bedrooms),INF);minimum_depth=8.0;suites+=1
				if original.entertainment=="billiards":minimum_width={1:10.0,2:13.8,3:17.6}.get(int(original.bedrooms),INF);minimum_depth=9.4

			if float(profile.get("frontage_m",0))<minimum_width-.00001 or float(profile.get("depth_m",0))<minimum_depth-.00001:return {"configured":false,"error":"Room drops full furniture/circulation requirements: "+String(room.id)}
			var fitout:Variant=room.get("fitout_contract")
			if not fitout is Dictionary or fitout.get("schema")!="mbs_full_room_fitout_contract_v4" or fitout.get("entertainment_program")!=original.entertainment or float(fitout.get("furnishing_scale",0))!=1.0:return {"configured":false,"error":"Named full-size private program missing: "+String(room.id)}
			if original.entertainment=="billiards":
				var table:Dictionary={}
				for object:Dictionary in fitout.get("objects",[]):
					if object.get("kind")=="billiards_table":table=object
				if table.is_empty() or table.get("size_xz_m")!=[2.83,1.56] or table.get("playing_bed_xz_m")!=[2.54,1.27] or float(table.get("cue_clearance_each_side_m",0))<1.45:return {"configured":false,"error":"Billiards may not become a label or shrunken table."}
			if not room.get("old_prototype_dimensions") is Dictionary or room.get("explicit_relayout_not_legacy_dimensions")!=true:return {"configured":false,"error":"Room dimension changes must stay explicit."}
			var u:Variant=room.get("frontage_own_axis");var v:Variant=room.get("into_room_own_axis")
			if not u is Array or not v is Array or u.size()!=2 or v.size()!=2 or absf(float(u[0])*float(v[1])-float(u[1])*float(v[0])-1.0)>.00001:return {"configured":false,"error":"Room requires a proper unscaled local orientation."}
			if absf(float(u[0])*float(u[0])+float(u[1])*float(u[1])-1.0)>.00001 or absf(float(v[0])*float(v[0])+float(v[1])*float(v[1])-1.0)>.00001 or absf(float(u[0])*float(v[0])+float(u[1])*float(v[1]))>.00001:return {"configured":false,"error":"Room transform compresses or shears physical dimensions."}
			seen[room.id]=true;packed.append(poly)
			if room.original_floor_id!=floor_id:moved+=1
			if String(room.original_floor_id).split("-")[0]!=String(record.tower):cross_tower+=1
	var inventory:Dictionary=Inventory.load_inventory();var expected_programs:Array=[]
	for record:Dictionary in inventory.hotel_floors+inventory.resort_program_floors:
		if record.factory!="guest_floor_v1":expected_programs.append(record)
	if retained!=expected_programs:return {"configured":false,"error":"A named private/public/service/resort program was lost or changed."}
	if seen.size()!=1850 or suites!=775:return {"configured":false,"error":"Complete1850-room/775-suite allocation required."}
	_document=document.duplicate(true)
	_report={"configured":true,"schema":SCHEMA,"guest_floor_count":floors.size(),"rooms":seen.size(),"suites":suites,"explicit_relocated_rooms":moved,"cross_tower_reconstructed_relocations":cross_tower,"program_floor_records_retained":retained.size(),"program_floor_geometry_planned":false,"all_original_guest_floors_occupied":empty.is_empty(),"native_factory_or_traversal_verified":false,"whole_building_complete":false,"private_asbuilt_verified":false}
	return report()

func floor_plan(id:String)->Dictionary:
	if _document.is_empty():return {"valid":false,"error":"Configure and validate the complete source allocation first."}
	var normalized:String=Inventory.normalize_floor_id(id)
	if not _document.floors.has(normalized):return {"valid":false,"error":"Program/roof/resort floor needs its own complete source polygon recipe; retained inventory is not built geometry."}
	var result:Dictionary=_document.floors[normalized].duplicate(true);result["valid"]=true;result["source_own_axes_required"]=true;result["exterior_face_owner"]="persistent_shell";result["core_support_owner"]="source_core_geometry";result["native_factory_or_traversal_verified"]=false
	return result

func report()->Dictionary:return _report.duplicate(true)
