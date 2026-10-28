extends "res://src/world/mbs_interior/guest_floor.gd"
## Furnished PROGRAM reconstruction, not a surveyed MBS fit-out.
## Inherits the production SwingDoor, persistence, public-core routing and exact
## U-stair/lift interfaces from GuestFloor. Root owns placement/cabins/streaming.
## API: program_plan(record), build(record), report(), inherited door APIs.
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")
const Canopy = preload("res://src/world/downtown/canopy.gd")
const MAX_PROGRAM_SPACES := 24
const MAX_PROGRAM_OBJECTS := 320
const RESORT_PROFILES := {
	"SHOPPES": Vector2(140.0, 76.0), "EXPO": Vector2(128.0, 90.0),
	"CASINO": Vector2(100.0, 70.0), "THEATRE": Vector2(92.0, 60.0),
	"MUSEUM": Vector2(100.0, 70.0)
}
const FLOOR_PROGRAMS := ["hotel_service_basement", "public_l1", "jin_ting_wan_dining", "roof_service_mezzanine", "roof_pool_dining", "spa", "paiza_residence", "public_observation", "back_of_house_parking_loading", "retail_galleria", "coach_entry", "expo_public_program", "fitness_centre", "casino_gaming", "casino_public_program", "theatre_public_program", "museum_public_program"]
const CORE_PROGRAMS := ["service_corridor", "roof_service_corridor", "connected_grand_atrium", "public_circulation", "service_circulation", "stairs", "public_stairs", "egress_stairs", "public_mezzanine_stair", "guest_lifts", "guest_service_lifts", "service_lifts", "lifts", "mezzanine_lift_landing", "staff_lift_landing", "public_stairs_lift_landing", "ticket_lift_arrival"]
const RECIPES := {
	"arrival_concierge":"reception", "checkin":"reception", "private_checkin":"reception", "reception":"reception", "observation_deck_box_office":"reception", "ticketing":"reception", "foyer_ticketing":"reception",
	"luggage_store":"storage", "bulk_stores":"storage", "engineering_store":"storage", "linen_store":"linen", "staff_store":"storage", "retail_service_stores":"storage", "service_store":"storage", "luggage_staging":"storage",
	"linen_laundry_transfer":"laundry", "staff_changing":"changing", "guest_changing":"changing", "changing":"changing", "staff_pantry":"kitchen", "pantry":"kitchen", "kitchen":"kitchen", "service_kitchen":"kitchen", "show_kitchen":"kitchen", "restaurant_back_of_house":"kitchen", "concessions":"kitchen",
	"plant":"plant", "plant_rooms":"plant", "plant_service":"plant", "electrical_mechanical_plant":"plant", "water_tanks":"tanks", "parking":"parking", "vehicle_loading":"parking", "loading_transfer":"loading", "staff_arrival":"lounge", "coach_waiting":"lounge",
	"main_dining":"dining", "private_dining":"dining", "dining_room":"dining", "restaurant":"dining", "LAVO_dining":"dining", "Spago_dining":"dining", "CE_LA_VI_dining":"dining", "restaurant_seating":"dining", "restaurants":"dining",
	"bar_lounge":"bar", "residence_bar":"bar", "tea_lounge":"lounge", "restaurant_lounge":"lounge", "relaxation_lounge":"relaxation", "VIP_lounge":"lounge", "business_lounge":"lounge", "pre_function":"lounge",
	"toilets":"toilets", "public_toilets":"toilets", "treatment_rooms":"treatment", "wet_treatment":"wet", "water_garden":"garden", "tropical_garden":"garden", "shared_infinity_pool_segment":"pool", "pool_deck":"deck", "viewing_rail":"observation", "public_observation_promenade":"observation",
	"retail_units":"retail", "exhibition_hall":"exhibition", "meeting_rooms":"meeting", "gym_floor":"gym", "exercise_studio":"studio", "gaming_floor":"gaming", "cashier":"reception", "auditorium":"auditorium", "stage_backstage":"backstage", "exhibition_gallery":"gallery", "interactive_gallery":"gallery", "learning_studio":"meeting"
}
var program_coverage: Array[Dictionary] = []
var furnishings: Array[Dictionary] = []
var _program_plan: Dictionary = {}
var _open_roof := false
var _solid_components := 0
var _private_vehicle_instances := 0

static func program_plan(record: Dictionary) -> Dictionary:
	if record.get("factory", "") != "program_module": return {"valid":false,"error":"Not an inventory program_module record."}
	if not record.get("id") is String or String(record.id).is_empty() or String(record.id).length()>100 or String(record.id).validate_node_name()!=String(record.id): return {"valid":false,"error":"Missing/invalid floor ID."}
	if not String(record.get("program", "")) in FLOOR_PROGRAMS: return {"valid":false,"error":"Unknown program floor recipe."}
	if not record.get("units",[]) is Array or not (record.get("units",[]) as Array).is_empty(): return {"valid":false,"error":"Guest unit inventory cannot be dropped into a program floor."}
	if bool(record.get("permanent_empty_fallback",false)): return {"valid":false,"error":"Permanent empty program fallback is forbidden."}
	if not record.get("source_facts",[]) is Array: return {"valid":false,"error":"Source fact IDs must be an array."}
	if record.has("has_upper_floor") and typeof(record.has_upper_floor)!=TYPE_BOOL: return {"valid":false,"error":"has_upper_floor override must be explicit boolean."}
	if not record.get("level") is String: return {"valid":false,"error":"Missing explicit level label."}
	var building_id:=String(record.get("tower",record.get("building","")))
	if not building_id in ["T1","T2","T3"] and not RESORT_PROFILES.has(building_id): return {"valid":false,"error":"Unknown inventory building."}
	if String(record.id)!=building_id+"-"+String(record.level): return {"valid":false,"error":"Record ID/building/level mismatch."}
	if not record.has("elevation_m") or not typeof(record.elevation_m) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(record.elevation_m)) or float(record.elevation_m)<-100.0 or float(record.elevation_m)>400.0: return {"valid":false,"error":"Missing/nonfinite/unsupported floor elevation."}
	var geo: Dictionary = {}
	var geometry_status := "RECONSTRUCTED_INVENTORY_DIMENSIONS"
	if record.has("geometry"):
		if not record.geometry is Dictionary: return {"valid":false,"error":"Geometry must be a complete dictionary."}
		geo = (record.geometry as Dictionary).duplicate(true)
	else:
		var building := String(record.get("building", ""))
		if not RESORT_PROFILES.has(building): return {"valid":false,"error":"Missing geometry and unknown resort building."}
		var size: Vector2 = RESORT_PROFILES[building]
		geo = {"length_m":size.x,"cross_m":size.y,"clear_height_m":3.08,"storey_height_m":3.45,"core_bay_m":6.2,"corridor_width_m":3.2,"void_min_z_m":0.0,"void_max_z_m":0.0,"atrium_void_active":false,"all_dimensions_reconstructed":true}
		geometry_status = "EXPLICIT_RECONSTRUCTED_RESORT_PROFILE_NOT_SOURCE_FOOTPRINT"
	for key: String in ["length_m","cross_m","clear_height_m","storey_height_m","core_bay_m","corridor_width_m","void_min_z_m","void_max_z_m"]:
		if not geo.has(key) or not typeof(geo[key]) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(geo[key])): return {"valid":false,"error":"Missing/nonfinite program geometry: "+key}
	if not geo.has("atrium_void_active") or typeof(geo.atrium_void_active)!=TYPE_BOOL: return {"valid":false,"error":"Explicit atrium-void state is required."}
	var length_m: float = geo.length_m
	var cross_m: float = geo.cross_m
	var height: float = geo.clear_height_m
	var bay: float = geo.core_bay_m
	var corridor: float = geo.corridor_width_m
	if length_m<30.0 or length_m>320.0 or cross_m<28.0 or cross_m>180.0 or height<2.7 or height>5.25 or float(geo.storey_height_m)<height+SLAB or float(geo.storey_height_m)>5.5 or bay<6.2 or bay>10.0 or corridor<2.6 or corridor>5.0: return {"valid":false,"error":"Unsupported bounded program-floor construction dimensions."}
	if float(geo.void_min_z_m)>0 or float(geo.void_max_z_m)<0 or float(geo.void_min_z_m)<-cross_m*.5 or float(geo.void_max_z_m)>cross_m*.5: return {"valid":false,"error":"Atrium boundaries do not fit program floor."}
	if not bool(geo.get("atrium_void_active",false)) and (absf(float(geo.void_min_z_m))>.001 or absf(float(geo.void_max_z_m))>.001): return {"valid":false,"error":"Inactive void requires zero boundaries."}
	var requested: Array[Dictionary] = []
	if record.has("program_spaces"):
		if not record.program_spaces is Array: return {"valid":false,"error":"Invalid program-space inventory."}
		for entry: Variant in record.program_spaces:
			if not entry is Dictionary or not entry.get("id") is String or not entry.get("program") is String: return {"valid":false,"error":"Incomplete program-space record."}
			requested.append((entry as Dictionary).duplicate(true))
	else:
		if not record.get("rooms_required") is Array: return {"valid":false,"error":"Missing named program spaces/rooms_required."}
		var names: Array = (record.rooms_required as Array).duplicate()
		var extras: Dictionary = {
			"back_of_house_parking_loading":["parking","loading_transfer","bulk_stores","plant_service"],
			"coach_entry":["coach_waiting","luggage_staging","vehicle_loading","ticketing"],
			"retail_galleria":[], "expo_public_program":["exhibition_hall","meeting_rooms","pre_function","service_store"],
			"fitness_centre":["gym_floor","exercise_studio","changing","reception"],
			"casino_gaming":["gaming_floor","cashier","bar_lounge","VIP_lounge"],
			"casino_public_program":["restaurants","VIP_lounge","kitchen","reception"],
			"theatre_public_program":["auditorium","stage_backstage","foyer_ticketing","concessions"],
			"museum_public_program":["exhibition_gallery","interactive_gallery","learning_studio","ticketing"]}
		for value: Variant in extras.get(String(record.program),[]):
			if not names.has(value): names.append(value)
		for value: Variant in names:
			if not value is String: return {"valid":false,"error":"Program names must be strings."}
			requested.append({"id":String(record.id)+"-"+value,"program":value,"status":"RECONSTRUCTED_ROOM_OR_LAYOUT_UNLESS_OPERATOR_PROGRAM_FACT"})
	if requested.is_empty() or requested.size()>MAX_PROGRAM_SPACES: return {"valid":false,"error":"Program-space inventory empty or exceeds bounded member budget."}
	var seen: Dictionary = {}
	var cells: Array[Dictionary] = []
	var cores: Array[Dictionary] = []
	for entry: Dictionary in requested:
		var id := String(entry.get("id",""))
		var program := String(entry.get("program",""))
		if id.is_empty() or id.length()>180 or id.validate_node_name()!=id or seen.has(id): return {"valid":false,"error":"Invalid/duplicate program-space identity."}
		seen[id]=true
		if program in CORE_PROGRAMS: cores.append(entry)
		elif RECIPES.has(program):
			var cell := entry.duplicate(true)
			cell["recipe"]=RECIPES[program]
			cell["weight"]=1.5 if cell.recipe in ["pool","auditorium"] else 1.0
			cells.append(cell)
		else: return {"valid":false,"error":"Unimplemented named program cannot become an empty placeholder: "+program}
	if cells.size()<2: return {"valid":false,"error":"Program floor requires furnished spaces in both physical wings."}
	var wings: Array[Dictionary] = []
	var planned: Array[Dictionary] = []
	var all_objects: Array[Dictionary] = []
	for side: float in [-1.0,1.0]:
		var wing_name := "east" if side<0 else "west"
		var inside: float = geo.void_min_z_m if side<0 else geo.void_max_z_m
		var outside := side*cross_m*.5
		var width := absf(outside-inside)
		var depth := width-corridor
		if depth<7.0: return {"valid":false,"error":"Program wing cannot preserve clear room circulation: "+wing_name}
		var assigned: Array[Dictionary] = []
		var total_weight := 0.0
		for index in cells.size():
			if (index%2==0) != (side<0): continue
			assigned.append(cells[index]);total_weight+=float(cells[index].weight)
		var x := -length_m*.5+bay
		var run := length_m-bay*2.0
		for entry: Dictionary in assigned:
			var frontage := run*float(entry.weight)/total_weight
			if frontage<7.0: return {"valid":false,"error":"Program cells cannot retain full furniture/entry aisle: "+String(entry.id)}
			var cell := entry.duplicate(true)
			cell.merge({"wing":wing_name,"center_x":x+frontage*.5,"frontage_m":frontage,"depth_m":depth,"inner_z":inside+side*corridor,"side":side,"entry_u":-frontage*.5+1.0,"private_asbuilt_verified":false},true)
			cell["entry_local"]=_p(cell,cell.entry_u,0,-1.10)
			cell["inside_local"]=_p(cell,cell.entry_u,0,1.70)
			cell["view_local"]=_p(cell,cell.entry_u,0,depth-.90)
			var layout := _recipe_layout(cell)
			if not layout.get("valid",false): return layout
			cell["objects"]=layout.objects
			for object: Dictionary in layout.objects: all_objects.append(object)
			planned.append(cell);x+=frontage
		wings.append({"id":wing_name,"side":side,"inner_z":inside,"outer_z":outside,"room_inner_z":inside+side*corridor,"corridor_center_z":inside+side*corridor*.5,"core_z":side*(cross_m*.5-5.6),"depth_m":width})
	if all_objects.size()>MAX_PROGRAM_OBJECTS: return {"valid":false,"error":"Furnishing budget exceeded before construction."}
	var has_upper := bool(record.get("has_upper_floor",true))
	if not record.has("has_upper_floor"):
		if String(record.get("tower","")) in ["T1","T2","T3"]: has_upper=String(record.level)!="L57"
		else:
			var terminal: Dictionary={"SHOPPES":"L1","EXPO":"L5","CASINO":"L4","THEATRE":"L2","MUSEUM":"L3"}
			has_upper=String(record.level)!=String(terminal.get(String(record.get("building","")),""))
	return {"valid":true,"rooms":planned,"wings":wings,"core_programs":cores,"geometry":geo,"geometry_status":geometry_status,"floor_id":String(record.id),"objects":all_objects,"object_count":all_objects.size(),"space_count":requested.size(),"open_roof":String(record.program) in ["roof_pool_dining","public_observation"],"has_upper_floor":has_upper,"private_asbuilt_verified":false}

static func _recipe_layout(cell: Dictionary) -> Dictionary:
	var recipe := String(cell.recipe)
	var kinds: Array[String] = []
	match recipe:
		"reception": kinds.assign(["counter","sofa","display","planter"])
		"storage": kinds.assign(["shelf","shelf","crate","shelf"])
		"linen": kinds.assign(["linen_rack","linen_rack","trolley"])
		"laundry": kinds.assign(["washer","dryer","linen_rack","trolley"])
		"changing": kinds.assign(["lockers","bench","lockers","vanity"])
		"kitchen": kinds.assign(["range","sink_counter","fridge","prep_counter"])
		"plant": kinds.assign(["plant_cabinet","pump","plant_cabinet","tank"])
		"tanks": kinds.assign(["tank","tank","pump"])
		"parking": kinds.assign(["parking_bay","parking_bay"])
		"loading": kinds.assign(["pallet","pallet","shelf","trolley"])
		"dining": kinds.assign(["dining_set","dining_set","dining_set","sideboard"])
		"lounge","relaxation": kinds.assign(["sofa","sofa","coffee_table","planter"])
		"bar": kinds.assign(["bar_counter","dining_set","sofa","sideboard"])
		"toilets": kinds.assign(["wc_cubicle","vanity","wc_cubicle"])
		"treatment": kinds.assign(["treatment_bed","treatment_bed","treatment_trolley","vanity"])
		"wet": kinds.assign(["spa_tub","treatment_bed","vanity"])
		"garden": kinds.assign(["garden_bed","bench","garden_bed"])
		"pool": kinds.assign(["pool"])
		"deck","observation": kinds.assign(["lounger","lounger","viewing_rail","planter"])
		"retail": kinds.assign(["display_rack","display_case","display_rack","counter"])
		"exhibition": kinds.assign(["expo_booth","expo_booth","display","meeting_set"])
		"meeting": kinds.assign(["meeting_set","display","sideboard"])
		"gym": kinds.assign(["treadmill","cycle","weight_rack","treadmill"])
		"studio": kinds.assign(["exercise_mat","exercise_mat","weight_rack","display"])
		"gaming": kinds.assign(["gaming_table","slot_bank","gaming_table","slot_bank"])
		"auditorium": kinds.assign(["seat_row","seat_row","stage","seat_row"])
		"backstage": kinds.assign(["vanity","costume_rack","shelf","trolley"])
		"gallery": kinds.assign(["display_case","display","display_case","bench"])
		_: return {"valid":false,"error":"No concrete furnishing recipe: "+recipe}
	var u0 := -float(cell.frontage_m)*.5+2.20
	var u1 := float(cell.frontage_m)*.5-.40
	var v0 := 2.70
	var v1 := float(cell.depth_m)-1.80
	var available := Vector2(u1-u0,v1-v0)
	if available.x<=0 or available.y<=0: return {"valid":false,"error":"No safe furnishing rectangle."}
	var max_size := Vector2.ZERO
	for kind: String in kinds:
		var size := _object_size(kind)
		if kind=="pool": size=Vector3(available.x-.20,1.10,minf(7.0,available.y-.20))
		if size.x<=0 or size.y<=0 or size.z<=0: return {"valid":false,"error":"Unknown or degenerate furnishing: "+kind}
		max_size.x=maxf(max_size.x,size.x);max_size.y=maxf(max_size.y,size.z)
	var columns := clampi(int(floor((available.x+.85)/(max_size.x+.85))),1,4)
	var rows := clampi(int(floor((available.y+.95)/(max_size.y+.95))),1,4)
	if max_size.x>available.x+.001 or max_size.y>available.y+.001: return {"valid":false,"error":"Full-size furnishing cannot fit safe rectangle: "+String(cell.id)}
	var capacity := columns*rows
	var count := mini(maxi(kinds.size(),int(floor(available.x*available.y/18.0))),capacity)
	if recipe=="pool": count=1
	var objects: Array[Dictionary] = []
	for i in count:
		var kind := kinds[i%kinds.size()]
		var size := _object_size(kind)
		if kind=="pool": size=Vector3(available.x-.20,1.10,minf(7.0,available.y-.20))
		var col := i%columns
		var row := int(i/columns)
		var u := u0+(float(col)+.5)*available.x/columns
		var v := v0+(float(row)+.5)*available.y/rows
		objects.append({"id":String(cell.id)+"-fitout-"+str(i),"space_id":cell.id,"kind":kind,"u":u,"v":v,"size":size,"position":_p(cell,u,0,v),"side":cell.side})
	if objects.is_empty(): return {"valid":false,"error":"Empty program fit-out is forbidden."}
	return {"valid":true,"objects":objects}

static func _object_size(kind: String) -> Vector3:
	match kind:
		"parking_bay": return Vector3(2.8,2.2,5.2)
		"dining_set","meeting_set","gaming_table": return Vector3(2.4,1.4,2.4)
		"expo_booth": return Vector3(2.8,2.4,2.2)
		"stage": return Vector3(2.8,2.3,2.2)
		"wc_cubicle": return Vector3(1.60,2.35,2.20)
		"spa_tub": return Vector3(2.20,.80,2.20)
		"treatment_bed": return Vector3(.95,.90,2.15)
		"lounger": return Vector3(.85,.80,2.10)
		"treadmill": return Vector3(1.10,1.5,2.0)
		"cycle": return Vector3(.85,1.5,1.55)
		"garden_bed": return Vector3(2.0,1.6,2.0)
		"exercise_mat": return Vector3(.85,.04,1.90)
		"sofa": return Vector3(2.2,.95,.90)
		"counter","bar_counter": return Vector3(2.8,1.5,.90)
		"seat_row": return Vector3(2.25,1.10,1.05)
		"tank": return Vector3(1.40,2.20,1.40)
		"pump": return Vector3(1.45,1.30,1.15)
		"shelf","linen_rack","display_rack","costume_rack","weight_rack": return Vector3(2.0,2.20,.75)
		"plant_cabinet","fridge": return Vector3(1.10,2.20,.85)
		"lockers": return Vector3(2.0,1.95,.66)
		"washer","dryer": return Vector3(1.10,1.65,1.10)
		"pallet","crate": return Vector3(1.40,1.40,1.20)
		"trolley","treatment_trolley": return Vector3(.85,1.15,.65)
		"display_case": return Vector3(1.30,1.70,.85)
		"display": return Vector3(1.5,2.15,.45)
		"viewing_rail": return Vector3(2.0,1.25,.15)
		"slot_bank": return Vector3(2.10,1.85,.95)
		"bench": return Vector3(2.0,.50,.50)
		"coffee_table": return Vector3(1.2,.55,.75)
		"vanity": return Vector3(2.0,2.2,.80)
		"sideboard","sink_counter","prep_counter","range": return Vector3(2.0,1.15,.80)
		"planter": return Vector3(.9,1.25,.9)
	return Vector3.ZERO

func build(record: Dictionary) -> Dictionary:
	if _built: return {"built":false,"error":"Already built."}
	var candidate := program_plan(record)
	if not candidate.get("valid",false): return {"built":false,"error":candidate.get("error","Invalid program record")}
	if not basis.get_scale().is_equal_approx(Vector3.ONE) or (is_inside_tree() and not global_basis.get_scale().is_equal_approx(Vector3.ONE)): return {"built":false,"error":"Uncompressed metre scale required."}
	_program_plan=candidate
	_plan=candidate
	floor_record=record.duplicate(true)
	floor_record["geometry"]=candidate.geometry.duplicate(true)
	rooms.assign(candidate.rooms)
	furnishings.assign(candidate.objects)
	_height=candidate.geometry.clear_height_m
	_open_roof=candidate.open_roof
	_make_materials()
	var kit=Kit.new(self,"ProgramFloorSolidCollision")
	for wing: Dictionary in candidate.wings: _program_shell(kit,wing,candidate.geometry)
	for cell: Dictionary in rooms: _program_room(kit,cell)
	for entry: Dictionary in candidate.core_programs:
		program_coverage.append({"id":entry.id,"program":entry.program,"implementation":"PHYSICAL_SHARED_CORE_AND_CORRIDOR","private_asbuilt_verified":false})
	kit.commit(self,"ProgramFloorMaterialBatches",true)
	_program_plan["static_collision_shapes"]=kit.shapes
	_built=true
	return report()

func _make_materials() -> void:
	super._make_materials()
	_materials["stone"]=Palette.mat_textured(Color(.72,.73,.69),"concrete",Vector3.ONE,.72,0,false)
	_materials["accent"]=Palette.mat(Color(.15,.22,.21),.78)
	_materials["felt"]=Palette.mat(Color(.10,.25,.20),.95)
	_materials["rubber"]=Palette.mat(Color(.07,.08,.08),.92)

func _floor_ceiling(kit, name: String, center: Vector3, size: Vector2, ceiling: bool = true) -> void:
	# Keep core helper signatures; open roof has real floor but no low false cap.
	_floor_patch(kit,name,center,size,ceiling and not _open_roof)

func _floor_patch(kit, name: String, center: Vector3, size: Vector2, ceiling: bool) -> void:
	var rectangles: Array[Rect2] = [Rect2(Vector2(center.x-size.x*.5,center.z-size.y*.5),size)]
	for object: Dictionary in furnishings:
		if object.kind!="pool": continue
		var p: Vector3=object.position
		var s: Vector3=object.size
		var hole:=Rect2(Vector2(p.x-s.x*.5,p.z-s.z*.5),Vector2(s.x,s.z))
		var remaining: Array[Rect2]=[]
		for rectangle: Rect2 in rectangles: remaining.append_array(_subtract_rect(rectangle,hole))
		rectangles=remaining
	for i in rectangles.size():
		var r: Rect2=rectangles[i]
		_solid(kit,name+"Floor"+str(i),_materials.stone,Vector3(r.get_center().x,-SLAB*.5,r.get_center().y),Vector3(r.size.x,SLAB,r.size.y))
	if ceiling: _solid(kit,name+"Ceiling",_materials.ceiling,center+Vector3.UP*(_height+SLAB*.5),Vector3(size.x,SLAB,size.y))

static func _subtract_rect(rectangle: Rect2,hole: Rect2) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	if not rectangle.intersects(hole): result.append(rectangle);return result
	var cut:=rectangle.intersection(hole)
	for r: Rect2 in [Rect2(rectangle.position,Vector2(cut.position.x-rectangle.position.x,rectangle.size.y)),Rect2(Vector2(cut.end.x,rectangle.position.y),Vector2(rectangle.end.x-cut.end.x,rectangle.size.y)),Rect2(Vector2(cut.position.x,rectangle.position.y),Vector2(cut.size.x,cut.position.y-rectangle.position.y)),Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,rectangle.end.y-cut.end.y))]:
		if r.size.x>.001 and r.size.y>.001: result.append(r)
	return result

func _program_shell(kit,wing: Dictionary,g: Dictionary) -> void:
	var length_m: float=g.length_m
	var bay: float=g.core_bay_m
	var center_z: float=(float(wing.inner_z)+float(wing.outer_z))*.5
	_floor_patch(kit,String(wing.id)+"Main",Vector3(0,0,center_z),Vector2(length_m-bay*2,wing.depth_m),not _open_roof)
	_build_core_approaches(kit,wing,g,not _open_roof)
	for end: float in [-1.0,1.0]:
		_solid(kit,String(wing.id)+"EndWall"+str(end),_materials.wall,Vector3(end*length_m*.5,(_height if not _open_roof else 1.25)*.5,center_z),Vector3(WALL,_height if not _open_roof else 1.25,wing.depth_m))
	var basement:=String(floor_record.get("level","")).begins_with("B")
	if _open_roof:
		_solid(kit,String(wing.id)+"ExteriorRoofGuard",Looks.get_mat("glass_clear"),Vector3(0,.62,wing.outer_z),Vector3(length_m,1.24,.10))
		kit.beam(Looks.get_mat("steel_satin"),Vector3(-length_m*.5,1.28,wing.outer_z),Vector3(length_m*.5,1.28,wing.outer_z),.07,.06)
	else:
		_solid(kit,String(wing.id)+"FacadeLower",_materials.wall,Vector3(0,.35,wing.outer_z),Vector3(length_m,.70,WALL))
		_solid(kit,String(wing.id)+"FacadeUpper",_materials.wall if basement else Looks.get_mat("glass_clear"),Vector3(0,(_height+.70)*.5,wing.outer_z),Vector3(length_m,_height-.70,.10))
		for x: float in [-length_m*.25,0,length_m*.25]: _solid(kit,String(wing.id)+"FacadePier"+str(x),_materials.wall,Vector3(x,_height*.5,wing.outer_z),Vector3(.22,_height,.24))
	if bool(g.atrium_void_active):
		_solid(kit,String(wing.id)+"AtriumGuard",Looks.get_mat("glass_clear"),Vector3(0,.62,wing.inner_z),Vector3(length_m,1.24,.10))
		kit.beam(Looks.get_mat("steel_bronze"),Vector3(-length_m*.5,1.28,wing.inner_z),Vector3(length_m*.5,1.28,wing.inner_z),.08,.06)
	if bool(_program_plan.has_upper_floor): _build_stair(kit,wing,g)
	else:
		# Terminal inventory levels receive the lower floor's actual U stair.
		# Do not invent an extra roof storey with an unsupported upper flight.
		var receiving:=Vector3(-length_m*.5+1.80+.78,0,float(wing.core_z)-float(wing.side)*.60)
		portals.append({"id":String(floor_record.id)+"-"+String(wing.id)+"-stair","kind":"stair","wing":wing.id,"lower":receiving,"upper":receiving,"landing":receiving,"physical_flights":false,"receiving_only":true,"walk_route":[receiving],"actor_teleport":false,"adjacent_floor_collision_required":true})
	_build_service_closet(kit,wing,g)
	_build_lift_landing(kit,wing,g)
	for x: float in [-length_m*.25,0,length_m*.25]:
		if not _open_roof: _light(Vector3(x,_height-.22,wing.corridor_center_z),.85,9.0)

func _program_room(kit,cell: Dictionary) -> void:
	var half: float=float(cell.frontage_m)*.5
	var depth: float=cell.depth_m
	var side: float=cell.side
	_wall_x_gap(kit,String(cell.id)+"Entry",cell.inner_z,float(cell.center_x)-half,float(cell.center_x)+half,float(cell.center_x)+float(cell.entry_u),DOOR_WIDTH,_height)
	for end: float in [-1.0,1.0]: _solid(kit,String(cell.id)+"Partition"+str(end),_materials.wall,_p(cell,end*half,_height*.5,depth*.5),Vector3(WALL,_height,depth))
	_door(String(cell.id),_p(cell,float(cell.entry_u)-DOOR_WIDTH*.5,0,0),DOOR_WIDTH,0,-side*PI*.5)
	_label(_p(cell,float(cell.entry_u)+1.2,1.65,-.09),String(cell.program).replace("_"," ").to_upper(),.0021)
	for object: Dictionary in cell.objects: _furnishing(kit,cell,object)
	if not _open_roof: _light(_p(cell,0,_height-.20,depth*.58),.85,maxf(5.5,minf(11.0,depth*.6)))
	kit.box(Looks.get_mat("steel_bronze"),_p(cell,0,.06,.03),Vector3(cell.frontage_m,.12,.06))
	program_coverage.append({"id":cell.id,"program":cell.program,"recipe":cell.recipe,"furnishings":cell.objects.size(),"native_entry_door":cell.id,"clear_entry_gallery_depth_m":2.70,"reserved_left_aisle_width_m":2.05,"private_asbuilt_verified":false})

func _part(kit,object: Dictionary,label: String,mat: Material,offset: Vector3,size: Vector3) -> void:
	var p: Vector3=object.position
	p+=Vector3(offset.x,offset.y,float(object.side)*offset.z)
	_solid(kit,String(object.id)+label,mat,p,size)
	_solid_components+=1

func _round(kit,object: Dictionary,label: String,mat: Material,offset: Vector3,radius: float,height: float) -> void:
	var p: Vector3=object.position
	p+=Vector3(offset.x,offset.y,float(object.side)*offset.z)
	kit.cyl(mat,p,radius,radius,height,16)
	var shape:=CollisionShape3D.new()
	var cylinder:=CylinderShape3D.new()
	cylinder.radius=radius;cylinder.height=height
	shape.shape=cylinder;shape.position=p+Vector3.UP*height*.5
	shape.name=(String(object.id)+label).validate_node_name()
	shape.set_meta("reconstructed_component",String(object.id)+label)
	kit.body.add_child(shape);kit.shapes+=1;_solid_components+=1

func _furnishing(kit,cell: Dictionary,object: Dictionary) -> void:
	var kind:=String(object.kind)
	var wood:=Looks.get_mat("timber")
	var steel:=Looks.get_mat("steel_satin")
	var dark:=Looks.get_mat("steel_dark")
	var stone: Material=_materials.stone
	match kind:
		"counter","bar_counter","sideboard","prep_counter","sink_counter","range","vanity":
			var width: float=(object.size as Vector3).x
			_part(kit,object,"RecessBase",dark,Vector3(0,.07,0),Vector3(width-.12,.14,.66))
			_part(kit,object,"Cabinet",wood,Vector3(0,.57,0),Vector3(width-.10,.86,.68))
			_part(kit,object,"Worktop",stone,Vector3(0,1.03,0),Vector3(width,.10,.80))
			for x: float in [-width*.25,width*.25]:
				_part(kit,object,"Handle"+str(x),steel,Vector3(x,.86,-.36),Vector3(.25,.025,.035))
			if kind in ["counter","bar_counter"]:
				_part(kit,object,"TerminalBase",dark,Vector3(.55,1.11,.10),Vector3(.18,.08,.20))
				_part(kit,object,"Terminal",_materials.screen,Vector3(.55,1.32,.10),Vector3(.47,.32,.055))
			if kind in ["sink_counter","vanity"]:
				_round(kit,object,"Basin",_materials.linen,Vector3(-.35,1.09,0),.24,.065)
				_part(kit,object,"Faucet",steel,Vector3(-.35,1.21,.24),Vector3(.035,.25,.035))
			if kind=="vanity": _part(kit,object,"Mirror",_materials.mirror,Vector3(0,1.75,.32),Vector3(width*.85,.85,.035))
			if kind=="range":
				for x: float in [-.45,.45]:
					for z: float in [-.20,.20]: _round(kit,object,"Hob"+str(x)+str(z),dark,Vector3(x,1.09,z),.13,.015)
		"sofa":
			_part(kit,object,"Base",wood,Vector3(0,.16,0),Vector3(2.05,.32,.78))
			_part(kit,object,"Seat",_materials.leather,Vector3(0,.48,-.08),Vector3(1.85,.26,.68))
			_part(kit,object,"Back",_materials.leather,Vector3(0,.72,.36),Vector3(2.05,.45,.16))
			for x: float in [-1.02,1.02]: _part(kit,object,"Arm"+str(x),_materials.leather,Vector3(x,.62,0),Vector3(.16,.40,.85))
		"bench":
			Realm.benches(self,String(object.id),[Kit.xf(object.position)])
			for x: float in [-.85,.85]: _part(kit,object,"Foot"+str(x),stone,Vector3(x,.22,0),Vector3(.18,.44,.50))
			_part(kit,object,"SeatSolid",wood,Vector3(0,.47,0),Vector3(2.0,.05,.45))
		"coffee_table":
			_part(kit,object,"TableBase",wood,Vector3(0,.23,0),Vector3(.80,.46,.50))
			_part(kit,object,"StoneTop",stone,Vector3(0,.51,0),Vector3(1.20,.08,.75))
		"dining_set","meeting_set","gaming_table":
			_table_set(kit,object,kind)
		"washer","dryer":
			_part(kit,object,"Machine",Looks.get_mat("hull_panel"),Vector3(0,.76,0),Vector3(1.05,1.52,.95))
			_part(kit,object,"Controls",_materials.screen,Vector3(0,1.40,-.485),Vector3(.82,.13,.035))
			_part(kit,object,"DrumWindow",Looks.get_mat("window_glass"),Vector3(0,.75,-.49),Vector3(.64,.65,.04))
			_part(kit,object,"DrumSurround",steel,Vector3(0,.75,-.515),Vector3(.69,.07,.035))
		"plant_cabinet","fridge","lockers":
			var width: float=(object.size as Vector3).x
			var height: float=(object.size as Vector3).y
			_part(kit,object,"Cabinet",steel if kind!="lockers" else wood,Vector3(0,height*.5,0),Vector3(width,height,.75 if kind!="lockers" else .55))
			var columns:=4 if kind=="lockers" else 2
			for i in columns:
				var x: float=-width*.5+(i+.5)*width/columns
				_part(kit,object,"DoorSeam"+str(i),dark,Vector3(x-width/columns*.48,height*.5,-.385 if kind!="lockers" else -.285),Vector3(.012,height*.92,.018))
				_part(kit,object,"Handle"+str(i),Looks.get_mat("steel_bronze"),Vector3(x,height*.54,-.40 if kind!="lockers" else -.30),Vector3(.025,.22,.04))
			if kind=="plant_cabinet":
				for row in 5: _part(kit,object,"Vent"+str(row),dark,Vector3(0,.28+row*.09,-.39),Vector3(width*.7,.018,.02))
		"shelf","linen_rack","display_rack","costume_rack","weight_rack":
			_shelf(kit,object,kind)
		"crate","pallet":
			for x: float in [-.45,0,.45]: _part(kit,object,"PalletRunner"+str(x),wood,Vector3(x,.06,0),Vector3(.14,.12,1.15))
			for i in 3:
				_part(kit,object,"PackedCrate"+str(i),_materials.wall,Vector3(0,.30+i*.38,0),Vector3(1.2,.36,1.05))
				_part(kit,object,"PackingBand"+str(i),wood,Vector3(0,.30+i*.38,-.53),Vector3(.045,.36,.015))
		"trolley","treatment_trolley":
			for x: float in [-.32,.32]:
				for z: float in [-.24,.24]: _part(kit,object,"Wheel"+str(x)+str(z),_materials.rubber,Vector3(x,.07,z),Vector3(.12,.14,.10))
			for y: float in [.25,.85]: _part(kit,object,"Shelf"+str(y),steel,Vector3(0,y,0),Vector3(.80,.05,.60))
			for x: float in [-.36,.36]: _part(kit,object,"Frame"+str(x),steel,Vector3(x,.57,.24),Vector3(.035,1.10,.035))
			_part(kit,object,"Handle",steel,Vector3(0,1.10,.24),Vector3(.76,.035,.035))
			_part(kit,object,"FoldedLinen",_materials.linen,Vector3(0,.93,0),Vector3(.58,.12,.42))
		"tank":
			_round(kit,object,"Tank",steel,Vector3.ZERO,.62,2.10)
			_round(kit,object,"Base",dark,Vector3.ZERO,.69,.12)
			_round(kit,object,"TopAccess",dark,Vector3(0,2.10,0),.27,.06)
			_part(kit,object,"Valve",Looks.get_mat("steel_bronze"),Vector3(0,.48,-.67),Vector3(.20,.16,.12))
		"pump":
			_part(kit,object,"Plinth",stone,Vector3(0,.10,0),Vector3(1.40,.20,1.10))
			_round(kit,object,"Pump",steel,Vector3(0,.20,0),.43,.78)
			_part(kit,object,"Motor",dark,Vector3(.49,.62,0),Vector3(.35,.55,.65))
			_part(kit,object,"Control",_materials.screen,Vector3(0,1.05,-.35),Vector3(.35,.20,.08))
		"wc_cubicle": _wc_stall(kit,object)
		"treatment_bed","lounger":
			var length_m: float=(object.size as Vector3).z
			_part(kit,object,"Base",wood,Vector3(0,.27,0),Vector3(.72,.54,length_m-.18))
			_part(kit,object,"Cushion",_materials.linen,Vector3(0,.60,0),Vector3(.84,.15,length_m-.08))
			_part(kit,object,"HeadCushion",_materials.throw,Vector3(0,.72,length_m*.34),Vector3(.68,.10,.35))
		"spa_tub": _raised_basin(kit,object)
		"garden_bed","planter":
			var s: Vector3=object.size
			Realm.planter(kit,object.position,Vector2(s.x,s.z),.45,false)
			_part(kit,object,"PlanterSolid",stone,Vector3(0,.225,0),Vector3(s.x,.45,s.z))
			var mesh:=Canopy.mesh("shrub")
			var bounds:=mesh.get_aabb()
			var fit:=Vector3((s.x-.15)/bounds.size.x,(s.y-.50)/bounds.size.y,(s.z-.15)/bounds.size.z)
			var planted_basis:=Basis.IDENTITY.scaled(fit)
			var origin: Vector3=object.position+Vector3.UP*.48-planted_basis*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
			Canopy.emit(self,[["shrub",Transform3D(planted_basis,origin),Color(1.0,1.04,.96,0)]],String(object.id)+"OriginalPlanting",140.0)
		"pool": _pool(kit,object)
		"viewing_rail":
			for x: float in [-.93,.93]: _part(kit,object,"Post"+str(x),steel,Vector3(x,.62,0),Vector3(.055,1.24,.055))
			_part(kit,object,"ClearGuard",Looks.get_mat("glass_clear"),Vector3(0,.61,0),Vector3(1.86,1.16,.045))
			_part(kit,object,"Handrail",steel,Vector3(0,1.23,0),Vector3(2.0,.055,.07))
		"parking_bay": _parking_bay(kit,object)
		"display","display_case":
			if kind=="display":
				_part(kit,object,"Stand",dark,Vector3(0,1.02,0),Vector3(1.45,2.04,.18))
				_part(kit,object,"Display",_materials.screen,Vector3(0,1.32,-.12),Vector3(1.25,1.20,.04))
				_label((object.position as Vector3)+Vector3(0,1.4,-float(object.side)*.145),String(cell.program).replace("_"," ").to_upper(),.0014)
			else:
				_part(kit,object,"Plinth",wood,Vector3(0,.48,0),Vector3(1.24,.96,.78))
				_part(kit,object,"Glass",Looks.get_mat("glass_clear"),Vector3(0,1.30,0),Vector3(1.24,.64,.78))
				_part(kit,object,"OriginalDisplayModel",stone,Vector3(0,1.10,0),Vector3(.52,.24,.36))
		"expo_booth":
			_part(kit,object,"BackPanel",_materials.wall,Vector3(0,1.15,.99),Vector3(2.75,2.30,.10))
			_part(kit,object,"SidePanel",_materials.accent,Vector3(-1.32,1.15,0),Vector3(.10,2.30,2.05))
			_part(kit,object,"Display",_materials.screen,Vector3(0,1.38,.92),Vector3(1.45,.85,.045))
			_part(kit,object,"Counter",wood,Vector3(.50,.48,-.55),Vector3(1.10,.96,.55))
		"treadmill":
			_part(kit,object,"Base",dark,Vector3(0,.15,0),Vector3(1.05,.30,1.95))
			_part(kit,object,"Belt",_materials.rubber,Vector3(0,.315,0),Vector3(.72,.03,1.65))
			for x: float in [-.44,.44]: _part(kit,object,"ConsoleArm"+str(x),steel,Vector3(x,.80,.70),Vector3(.055,1.10,.055))
			_part(kit,object,"Console",_materials.screen,Vector3(0,1.38,.70),Vector3(.94,.18,.25))
		"cycle":
			_part(kit,object,"Frame",steel,Vector3(0,.48,0),Vector3(.15,.95,1.25))
			_part(kit,object,"Flywheel",dark,Vector3(0,.39,-.35),Vector3(.17,.63,.65))
			_part(kit,object,"Seat",_materials.rubber,Vector3(0,1.08,.28),Vector3(.35,.12,.30))
			_part(kit,object,"Handle",dark,Vector3(0,1.35,-.55),Vector3(.70,.055,.20))
		"exercise_mat": _part(kit,object,"Mat",_materials.accent,Vector3(0,.02,0),Vector3(.85,.04,1.9))
		"slot_bank":
			for i in 3:
				var x: float=(i-1)*.68
				_part(kit,object,"Machine"+str(i),wood,Vector3(x,.70,0),Vector3(.62,1.40,.82))
				_part(kit,object,"Screen"+str(i),_materials.screen,Vector3(x,1.40,-.43),Vector3(.51,.65,.035))
				_part(kit,object,"Controls"+str(i),Looks.get_mat("steel_bronze"),Vector3(x,.95,-.46),Vector3(.48,.09,.06))
		"seat_row":
			for i in 3: _chair(kit,object,Vector3((i-1)*.73,0,0),"AuditoriumSeat"+str(i))
		"stage":
			_part(kit,object,"Stage",wood,Vector3(0,.16,.35),Vector3(2.8,.32,1.40))
			_part(kit,object,"Backdrop",_materials.accent,Vector3(0,1.30,1.02),Vector3(2.8,2.0,.08))
			var p: Vector3=object.position
			var a:=p+Vector3(-1.25,0,-float(object.side)*1.06)
			var b:=p+Vector3(-1.25,.32,float(object.side)*.35)
			kit.beam(wood,a-Vector3.UP*.06,b-Vector3.UP*.06,.75,.12)
			kit.col_beam(a,b,.75,.12)

func _chair(kit,object: Dictionary,offset: Vector3,label: String) -> void:
	_part(kit,object,label+"Seat",_materials.leather,offset+Vector3(0,.46,0),Vector3(.57,.14,.57))
	_part(kit,object,label+"Back",_materials.leather,offset+Vector3(0,.79,.25),Vector3(.57,.64,.10))
	for x: float in [-.22,.22]:
		for z: float in [-.22,.22]: _part(kit,object,label+"Leg"+str(x)+str(z),Looks.get_mat("timber"),offset+Vector3(x,.21,z),Vector3(.055,.42,.055))

func _table_set(kit,object: Dictionary,kind: String) -> void:
	var top: Material=_materials.felt if kind=="gaming_table" else _materials.stone
	_part(kit,object,"TableTop",top,Vector3(0,.78,0),Vector3(1.20,.10,.80))
	for x: float in [-.48,.48]:
		for z: float in [-.28,.28]: _part(kit,object,"TableLeg"+str(x)+str(z),Looks.get_mat("timber"),Vector3(x,.36,z),Vector3(.075,.72,.075))
	for z: float in [-.89,.89]:
		_chair(kit,object,Vector3(0,0,z),"Chair"+str(z))
	if kind=="dining_set":
		for x: float in [-.32,.32]: _round(kit,object,"PlaceSetting"+str(x),_materials.linen,Vector3(x,.84,0),.16,.012)
	elif kind=="meeting_set": _part(kit,object,"ConferenceUnit",_materials.screen,Vector3(0,.86,0),Vector3(.35,.06,.25))
	else:
		for x: float in [-.35,0,.35]: _part(kit,object,"CardLayout"+str(x),_materials.linen,Vector3(x,.84,0),Vector3(.12,.006,.16))

func _shelf(kit,object: Dictionary,kind: String) -> void:
	var steel:=Looks.get_mat("steel_satin")
	for x: float in [-.94,.94]:
		for z: float in [-.31,.31]: _part(kit,object,"Upright"+str(x)+str(z),steel,Vector3(x,1.05,z),Vector3(.055,2.10,.055))
	for row in 4:
		var y:=.20+row*.52
		_part(kit,object,"Shelf"+str(row),steel,Vector3(0,y,0),Vector3(1.94,.05,.68))
		for col in 3:
			var x: float=(col-1)*.55
			var material: Material=_materials.linen if kind in ["linen_rack","costume_rack"] else _materials.rubber if kind=="weight_rack" else Looks.get_mat("timber")
			_part(kit,object,"Contents"+str(row)+str(col),material,Vector3(x,y+.16,0),Vector3(.46,.26,.48))

func _wc_stall(kit,object: Dictionary) -> void:
	var p: Vector3=object.position
	var side: float=object.side
	for x: float in [-.77,.77]: _part(kit,object,"Partition"+str(x),_materials.wall,Vector3(x,1.12,0),Vector3(.06,2.24,2.18))
	_part(kit,object,"Back",_materials.wall,Vector3(0,1.12,1.07),Vector3(1.60,2.24,.06))
	for x: float in [-.65,.65]: _part(kit,object,"FrontPier"+str(x),_materials.wall,Vector3(x,1.12,-1.07),Vector3(.30,2.24,.06))
	_door(String(object.id)+"-stall",p+Vector3(-.50,0,-side*1.07),1.0,0,-side*PI*.5)
	_part(kit,object,"WCBase",_materials.linen,Vector3(0,.28,.46),Vector3(.48,.56,.66))
	_part(kit,object,"Cistern",_materials.linen,Vector3(0,.62,.82),Vector3(.55,.74,.22))
	portals.append({"id":String(object.id)+"-stall","kind":"program_wc_stall","space_id":object.space_id,"landing":p+Vector3(0,0,-side*1.75),"inside":p+Vector3(0,0,-side*.10),"actor_teleport":false})

func _raised_basin(kit,object: Dictionary) -> void:
	_part(kit,object,"BasinBase",_materials.stone,Vector3(0,.10,0),Vector3(2.15,.20,2.15))
	for x: float in [-1.0,1.0]: _part(kit,object,"RimX"+str(x),_materials.stone,Vector3(x,.42,0),Vector3(.15,.64,2.15))
	for z: float in [-1.0,1.0]: _part(kit,object,"RimZ"+str(z),_materials.stone,Vector3(0,.42,z),Vector3(1.85,.64,.15))
	var p: Vector3=object.position
	kit.box(Looks.get_mat("pool_water"),p+Vector3.UP*.62,Vector3(1.84,.025,1.84))

func _pool(kit,object: Dictionary) -> void:
	var s: Vector3=object.size
	var p: Vector3=object.position
	_part(kit,object,"BasinBottom",_materials.stone,Vector3(0,-1.10,0),Vector3(s.x,.20,s.z))
	for x: float in [-1.0,1.0]: _part(kit,object,"PoolWallX"+str(x),_materials.stone,Vector3(x*(s.x*.5-.08),-.49,0),Vector3(.16,1.02,s.z))
	for z: float in [-1.0,1.0]: _part(kit,object,"PoolWallZ"+str(z),_materials.stone,Vector3(0,-.49,z*(s.z*.5-.08)),Vector3(s.x-.32,1.02,.16))
	kit.box(Looks.get_mat("pool_water"),p+Vector3.UP*-.16,Vector3(s.x-.34,.025,s.z-.34))
	# Physical shallow entry treads share one continuous walk ramp. No actor move.
	var ramp_length:=minf(2.4,s.z-.50)
	var x: float=-s.x*.5+.70
	for i in 5:
		var z: float=-s.z*.5+.20+(i+.5)*ramp_length/5.0
		_part(kit,object,"PoolEntryTread"+str(i),_materials.stone,Vector3(x,-.10-float(i+1)*.18,z),Vector3(.90,.12,ramp_length/5.0))
	var a:=p+Vector3(x,0,float(object.side)*(-s.z*.5+.17))
	var b:=p+Vector3(x,-1.0,float(object.side)*(-s.z*.5+.17+ramp_length))
	kit.col_beam(a,b,.90,.10)
	var water:=Area3D.new()
	water.name=(String(object.id)+"WaterVolume").validate_node_name()
	water.position=p+Vector3.DOWN*.59;water.collision_layer=0;water.collision_mask=2
	water.set_meta("water_program","RECONSTRUCTED_POOL_SEGMENT_NOT_CONNECTED_REAL_INFINITY_POOL")
	var cs:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(s.x-.34,.82,s.z-.34);cs.shape=box;water.add_child(cs);add_child(water)
	water.add_to_group("mbs_program_water")

func _parking_bay(kit,object: Dictionary) -> void:
	var p: Vector3=object.position
	for x: float in [-1.32,1.32]: kit.box(_materials.linen,p+Vector3(x,.006,0),Vector3(.065,.012,5.10))
	_part(kit,object,"WheelStop",_materials.rubber,Vector3(0,.06,2.15),Vector3(1.60,.12,.16))
	_part(kit,object,"ChargePedestal",Looks.get_mat("steel_satin"),Vector3(1.10,.65,2.25),Vector3(.22,1.30,.22))
	# Already delivered private source, not a new provider call. An absent car
	# leaves an equipped vacant parking bay, not an empty program room.
	var holder:=Node3D.new()
	holder.name=(String(object.id)+"ExistingPrivateSedan").validate_node_name()
	add_child(holder)
	var vehicle:=AssetLibrary.instantiate("sedan_clean.glb",holder)
	if vehicle==null:
		holder.queue_free();return
	var bounds:=AABB()
	var first:=true
	var stack: Array=[[vehicle,Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array=stack.pop_back()
		var node: Node=item[0]
		var xf: Transform3D=item[1]
		if node is Node3D: xf=xf*(node as Node3D).transform
		if node is CollisionObject3D:
			(node as CollisionObject3D).collision_layer=0;(node as CollisionObject3D).collision_mask=0
		if node is AnimationPlayer: (node as AnimationPlayer).stop()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh!=null:
			var aabb: AABB=xf*(node as MeshInstance3D).get_aabb()
			bounds=aabb if first else bounds.merge(aabb);first=false
		for child: Node in node.get_children(): stack.append([child,xf])
	if first or bounds.size.x<.01 or bounds.size.y<.01 or bounds.size.z<.01:
		holder.queue_free();return
	var fit:=Vector3(2.10,1.55,4.65)/bounds.size
	holder.scale=fit
	holder.position=p-Vector3(bounds.get_center().x*fit.x,bounds.position.y*fit.y,bounds.get_center().z*fit.z)
	# Standard fitted body/cabin volumes follow the existing vehicle strategy;
	# never draw coarse collision boxes over the selected detailed visual asset.
	kit.col_box(Vector3(2.02,.75,4.55),p+Vector3.UP*.45)
	kit.col_box(Vector3(1.65,.65,2.45),p+Vector3.UP*1.10)
	_private_vehicle_instances+=1
	_solid_components+=2

func _label(p: Vector3,text: String,pixel: float) -> void:
	# Two-sided generic physical placard, readable from either mirrored wing.
	# No copied operator logo, art, brand fit-out or unlabeled empty-room claim.
	var backing:=MeshInstance3D.new()
	var box:=BoxMesh.new();box.size=Vector3(clampf(text.length()*.075,1.60,3.50),.37,.035)
	backing.mesh=box;backing.material_override=Palette.mat(Color(.08,.10,.09),.85)
	backing.position=p;backing.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backing)
	for side: float in [-1.0,1.0]:
		var label:=Label3D.new()
		label.text=text;label.font_size=44;label.pixel_size=maxf(pixel,.0028)
		label.modulate=Color(.94,.95,.90);label.outline_size=1
		label.position=p+Vector3(0,0,side*.025);label.rotation.y=0 if side>0 else PI
		add_child(label)

func room_route_local(id: String) -> Array[Vector3]:
	for cell: Dictionary in rooms:
		if cell.id==id: return [cell.entry_local,cell.inside_local,cell.view_local,cell.inside_local,cell.entry_local]
	return []

func report() -> Dictionary:
	return {
		"built":_built,"floor_id":floor_record.get("id",""),"program":floor_record.get("program",""),
		"source_facts":floor_record.get("source_facts",[]).duplicate(),"source_status":floor_record.get("source_status","RECONSTRUCTED"),
		"program_rooms_built":rooms.size(),"program_spaces_built":program_coverage.size(),"program_coverage":program_coverage.duplicate(true),
		"furnishing_object_count":furnishings.size(),"fitout_solid_component_count":_solid_components,"static_collision_shapes":_program_plan.get("static_collision_shapes",0),"private_vehicle_instances":_private_vehicle_instances,
		"door_count":doors.size(),"physical_portals":portals.duplicate(true),"geometry_status":_program_plan.get("geometry_status","NOT_BUILT"),"geometry":_program_plan.get("geometry",{}).duplicate(true),"has_upper_floor":_program_plan.get("has_upper_floor",false),
		"preserves_atrium_void":true,"local_coordinates_only":true,"permanent_empty_fallback":false,
		"current_private_asbuilt_verified":false,"integrated_city_traversal_verified":false,"all_program_floors_runtime_verified":false,"full_building_completed":false,
		"requires":"Root source site placement, real adjacent floors, physical cabin interlocks, streamed collision, exterior doorway, lower-storey pool clearance, water behavior and whole-building verification."
	}
