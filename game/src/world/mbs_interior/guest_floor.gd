extends Node3D
## Reusable furnished/colliding PRIVATE RECONSTRUCTION for every inventory guest
## floor. Local axes X=south, Z=west, Y=up; root owns source/elevation placement.
## This factory never relocates an actor or claims current private as-built plans.
signal transition_requested(floor_id: String, portal_id: String, kind: String)
signal door_state_changed(floor_id: String, door_id: String, open: bool)
const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const WALL := 0.15
const DOOR_WIDTH := 1.30
const DOOR_HEIGHT := 2.35
const SLAB := 0.20

class SwingDoor extends AnimatableBody3D:
	var door_id := ""
	var base_angle := 0.0
	var swing_delta := 0.0
	var opened := false
	var transition_kind := ""
	var ready_to_open := false
	var coordinator: Node
	var hinge_origin := Vector3.ZERO
	var leaf_width := 1.30
	var motion_angle := 0.0
	var prompt_text := "[E] Open door"
	func _ready()->void:
		add_to_group("interactables")
		_refresh_prompt()
	func can_interact()->bool:
		return is_visible_in_tree() and is_instance_valid(coordinator) and bool(coordinator.get("_built"))
	func interact(_actor:Node)->void:
		if can_interact(): coordinator.request_interaction(door_id)
	func _refresh_prompt()->void:
		prompt_text = "[E] Call " + transition_kind.replace("_", " ") if not transition_kind.is_empty() and not ready_to_open else "[E] Close door" if opened else "[E] Open door"
	func _physics_process(delta: float) -> void:
		# sync_to_physics restores the last accepted node transform after each
		# setter. Separate rotation/position writes overwrite the queued rotation.
		# Integrate a separate commanded angle and submit ONE complete transform.
		motion_angle = move_toward(motion_angle, base_angle + (swing_delta if opened else 0.0), delta * 2.8)
		var leaf_basis := Basis(Vector3.UP, motion_angle)
		transform = Transform3D(leaf_basis, hinge_origin + leaf_basis * Vector3(leaf_width * .5, 0, 0))
	func set_open(value: bool) -> bool:
		if value and not transition_kind.is_empty() and not ready_to_open: return false
		opened = value
		_refresh_prompt()
		return true

var rooms: Array[Dictionary] = []
var portals: Array[Dictionary] = []
var doors: Dictionary = {}
var floor_record: Dictionary = {}
var _built := false
var _height := 3.08
var _plan: Dictionary = {}
var _materials: Dictionary = {}

static func plan(record: Dictionary) -> Dictionary:
	if record.get("factory", "") != "guest_floor_v1": return {"valid": false, "error": "Not an inventory guest floor."}
	var g: Dictionary = record.get("geometry", {})
	for field: String in ["length_m", "cross_m", "clear_height_m", "storey_height_m", "core_bay_m", "corridor_width_m", "void_min_z_m", "void_max_z_m"]:
		if not g.has(field) or not is_finite(float(g[field])): return {"valid": false, "error": "Missing/nonfinite floor dimension: " + field}
	var length_m: float = g.length_m
	var cross_m: float = g.cross_m
	var h: float = g.clear_height_m
	var bay: float = g.core_bay_m
	var corridor: float = g.corridor_width_m
	if length_m < 30 or length_m > 120 or cross_m < 20 or cross_m > 100 or h < 2.7 or h > 4.2 or float(g.storey_height_m) < h + SLAB or float(g.storey_height_m) > 5.0 or bay < 6.2 or bay > 10 or corridor < 2.4 or corridor > 4.0:
		return {"valid": false, "error": "Unsupported guest-floor construction domain."}
	if float(g.void_min_z_m)>0.0 or float(g.void_max_z_m)<0.0 or float(g.void_min_z_m)<-cross_m*.5 or float(g.void_max_z_m)>cross_m*.5:
		return {"valid": false, "error": "Void boundaries exceed the supported floor footprint."}
	if not bool(g.get("atrium_void_active",false)) and (absf(float(g.void_min_z_m))>.001 or absf(float(g.void_max_z_m))>.001):
		return {"valid": false, "error": "Inactive void must have zero boundaries."}
	var units: Array = record.get("units", [])
	if units.size() < 2 or units.size() > 24: return {"valid": false, "error": "Unsupported guest-floor room/member budget."}
	var result: Array[Dictionary] = []
	var wings: Array[Dictionary] = []
	var seen: Dictionary = {}
	for side: float in [-1.0, 1.0]:
		var wing_name := "east" if side < 0 else "west"
		var inside: float = float(g.void_min_z_m) if side < 0 else float(g.void_max_z_m)
		var outside: float = side * cross_m * 0.5
		var wing_width: float = absf(outside - inside)
		var room_depth := wing_width - corridor
		if room_depth < 5.8: return {"valid": false, "error": "Wing cannot fit furnished rooms and clear corridor: " + wing_name}
		var row: Array[Dictionary] = []
		var total_weight := 0.0
		for unit: Dictionary in units:
			if unit.get("wing", "") != wing_name: continue
			var weight: float = float(unit.get("frontage_weight", 0))
			if not is_finite(weight) or weight < 0.5 or weight > 8.0 or seen.has(unit.get("id", "")): return {"valid": false, "error": "Invalid or duplicate unit weight/identity."}
			seen[String(unit.id)] = true
			row.append(unit)
			total_weight += weight
		if row.is_empty(): return {"valid": false, "error": "Both physical wings need a nonempty room program."}
		var room_inner := inside + side * corridor
		var x := -length_m * 0.5 + bay
		var run := length_m - bay * 2.0
		for unit: Dictionary in row:
			var frontage := run * float(unit.frontage_weight) / total_weight
			var bedrooms: int = int(unit.get("bedrooms", 1))
			if unit.is_suite and room_depth<7.4:return {"valid":false,"error":"Suite foyer/bedroom depth cannot fit furnished circulation: "+String(unit.id)}
			if frontage < 4.2 or bedrooms < 1 or bedrooms > 3: return {"valid": false, "error": "Room cannot retain bedroom/door clearances: " + String(unit.id)}
			var cell := unit.duplicate(true)
			cell.merge({"center_x": x + frontage * 0.5, "frontage_m": frontage, "depth_m": room_depth, "inner_z": room_inner, "side": side, "actual_reconstructed_area_m2": frontage * room_depth, "bath_width_m": minf(3.2, frontage - 1.6), "living_width_m": clampf(frontage * 0.36, 3.2, 5.4)}, true)
			if unit.is_suite and (frontage - float(cell.living_width_m)) / bedrooms < 3.8: return {"valid": false, "error": "Suite cannot retain full king beds and window aisles: " + String(unit.id)}
			var bath_left:float=frontage*.5-float(cell.bath_width_m)
			var living_divider:float=-frontage*.5+float(cell.living_width_m)
			cell["social_bar_u"]=minf(living_divider+.65,bath_left-.65)
			cell["social_bar_v"]=.45
			cell["dining_u"]=minf(living_divider+2.4,bath_left-2.40)
			cell["dining_v"]=1.80
			cell["coffee_table_v"]=maxf(room_depth*.68-1.2,4.25)
			# The suite foyer has a rear cross-gallery and a dedicated clear
			# side approach to its bath. Do not navigate through dining furniture.
			cell["bath_route_local"]=[_p(cell,-frontage*.5+.85,0,3.40),_p(cell,bath_left-.80,0,3.40),_p(cell,bath_left-.80,0,1.35)] if unit.is_suite else [_p(cell,bath_left-.80,0,1.35)]
			cell["bedroom_layouts"] = []
			if unit.is_suite:
				var bedroom_width:float=(frontage-float(cell.living_width_m))/bedrooms
				var divider:float=-frontage*.5+float(cell.living_width_m)
				for bedroom_index in bedrooms:
					var left:float=divider+float(bedroom_index)*bedroom_width
					var right:float=left+bedroom_width
					# Whole full-size bed/table envelope is 2.51m; move it toward
					# the right wall, reserving an actual continuous left-side aisle.
					var bed_u:float=right-.15-1.255
					var aisle_left:float=left+WALL*.5
					var aisle_right:float=bed_u-1.255
					var aisle_u:float=(aisle_left+aisle_right)*.5
					var door_u:float=left+.72
					cell.bedroom_layouts.append({"index":bedroom_index+1,"left_u":left,"right_u":right,"bed_u":bed_u,"bed_width_m":1.95,"bedframe_width_m":2.11,"whole_furniture_width_m":2.51,"clear_window_aisle_m":aisle_right-aisle_left,"door_approach":_p(cell,door_u,0,3.40),"door_inside":_p(cell,door_u,0,4.90),"aisle_start":_p(cell,aisle_u,0,4.90),"window":_p(cell,aisle_u,0,room_depth-.70),"living_gallery":_p(cell,-frontage*.5+.85,0,3.40)})
			result.append(cell)
			x += frontage
		wings.append({"id": wing_name, "side": side, "inner_z": inside, "outer_z": outside, "room_inner_z": room_inner, "corridor_center_z": inside + side * corridor * 0.5, "core_z": side * (cross_m * 0.5 - 5.6), "depth_m": wing_width})
	if seen.size() != units.size(): return {"valid": false, "error": "Unknown room wing leaves an unbuilt unit."}
	return {"valid": true, "rooms": result, "wings": wings, "geometry": g.duplicate(true), "floor_id": String(record.id), "estimated_room_limit": 24, "preserves_atrium_void": true, "private_asbuilt_verified": false}

func build(record: Dictionary) -> Dictionary:
	if _built: return {"built": false, "error": "Already built."}
	var candidate := plan(record)
	if not candidate.get("valid", false): return {"built": false, "error": candidate.get("error", "Invalid floor")}
	if not basis.get_scale().is_equal_approx(Vector3.ONE) or (is_inside_tree() and not global_basis.get_scale().is_equal_approx(Vector3.ONE)): return {"built": false, "error": "Use uncompressed local metre scale."}
	_plan = candidate
	floor_record = record.duplicate(true)
	rooms.assign(candidate.rooms)
	_height = candidate.geometry.clear_height_m
	_make_materials()
	var kit = Kit.new(self, "GuestFloorSolidCollision")
	var g: Dictionary = candidate.geometry
	for wing: Dictionary in candidate.wings:
		_build_wing(kit, wing, g)
	for cell: Dictionary in rooms:
		_build_room(kit, cell)
	kit.commit(self, "GuestFloorMaterialBatches", true)
	_built = true
	return report()

func _make_materials() -> void:
	_materials = {"wall": Palette.mat_textured(Color(0.81, 0.77, 0.68), "plaster", Vector3.ONE, 0.86), "ceiling": Palette.mat(Color(0.90, 0.87, 0.79), 0.92), "carpet": Palette.mat_textured(Color(0.23, 0.22, 0.20), "fabric", Vector3.ONE, 0.95), "linen": Palette.mat(Color(0.92, 0.89, 0.82), 0.94), "throw": Palette.mat(Color(0.40, 0.34, 0.25), 0.9), "leather": Palette.mat(Color(0.33, 0.24, 0.17), 0.66), "screen": Palette.mat(Color(0.025, 0.03, 0.033), 0.13, 0.2), "mirror": Palette.mat(Color(0.64, 0.68, 0.67), 0.07, 0.8)}

func _solid(kit, name: String, mat: Material, p: Vector3, size: Vector3) -> void:
	kit.box(mat, p, size, Basis.IDENTITY, false)
	kit.col_box(size, p)
	var shape: CollisionShape3D = kit.body.get_child(kit.body.get_child_count() - 1)
	shape.name = name.validate_node_name()
	shape.set_meta("reconstructed_component", name)

func _floor_ceiling(kit, name: String, center: Vector3, size: Vector2, ceiling: bool = true) -> void:
	_solid(kit, name + "Floor", _materials.carpet, center - Vector3.UP * SLAB * 0.5, Vector3(size.x, SLAB, size.y))
	if ceiling: _solid(kit, name + "Ceiling", _materials.ceiling, center + Vector3.UP * (_height + SLAB * 0.5), Vector3(size.x, SLAB, size.y))

func _build_wing(kit, wing: Dictionary, g: Dictionary) -> void:
	var side: float = wing.side
	var length_m: float = g.length_m
	var corridor: float = g.corridor_width_m
	var bay: float = g.core_bay_m
	var center_z: float = (float(wing.inner_z) + float(wing.outer_z)) * 0.5
	# Central room band plus corridor-only core landings. The remainder of each
	# end core is a real stair/shaft opening, not a hidden solid floor plug.
	_floor_ceiling(kit, String(wing.id) + "Main", Vector3(0, 0, center_z), Vector2(length_m - bay * 2, wing.depth_m))
	_build_core_approaches(kit,wing,g,true)
	# Exterior glazing is physical and has opaque piers, sill and upper frame.
	_solid(kit, String(wing.id) + "WindowSill", Looks.get_mat("granite_light"), Vector3(0, 0.32, wing.outer_z), Vector3(length_m, 0.64, WALL))
	_solid(kit, String(wing.id) + "FacadeGlazing", Looks.get_mat("glass_clear"), Vector3(0, 1.84, wing.outer_z), Vector3(length_m, 2.40, 0.08))
	_solid(kit, String(wing.id) + "FacadeTop", Looks.get_mat("timber"), Vector3(0, _height - 0.08, wing.outer_z), Vector3(length_m, 0.16, WALL))
	for end: float in [-1.0, 1.0]:
		_solid(kit, String(wing.id) + "EndWall" + str(end), _materials.wall, Vector3(end * length_m * 0.5, _height * 0.5, center_z), Vector3(WALL, _height, wing.depth_m))
	if bool(g.atrium_void_active):
		# No slab, ceiling, connector or hidden collider crosses this open void.
		_solid(kit, String(wing.id) + "AtriumGuard", Looks.get_mat("glass_clear"), Vector3(0, 0.62, wing.inner_z), Vector3(length_m, 1.24, 0.10))
		kit.beam(Looks.get_mat("steel_bronze"), Vector3(-length_m * .5, 1.28, wing.inner_z), Vector3(length_m * .5, 1.28, wing.inner_z), .10, .08)
	_build_stair(kit, wing, g)
	_build_service_closet(kit, wing, g)
	_build_lift_landing(kit, wing, g)
	for x: float in [-length_m * 0.25, 0, length_m * 0.25]:
		_light(Vector3(x, _height - 0.22, wing.corridor_center_z), 1.2, 7.5)

func _build_core_approaches(kit,wing:Dictionary,g:Dictionary,with_ceiling:bool=true)->void:
	for end:float in [-1.0,1.0]:
		var x:float=end*(float(g.length_m)*.5-float(g.core_bay_m)*.5)
		_floor_ceiling(kit,String(wing.id)+"CoreLanding"+str(end),Vector3(x,0,(float(wing.inner_z)+float(wing.core_z))*.5),Vector2(g.core_bay_m,absf(float(wing.core_z)-float(wing.inner_z))),with_ceiling)

func build_receiving_core_interface_for_qa(record:Dictionary)->Dictionary:
	# A temporary receiving structure from the real NEXT inventory level.
	# This is the same approach-floor geometry normal Guest/Program floors use,
	# not a raised current-floor ceiling or a replacement for that full floor.
	if _built:return {"built":false,"error":"Already built."}
	var g:Dictionary=record.get("geometry",{})
	for field:String in ["length_m","cross_m","core_bay_m","clear_height_m","void_min_z_m","void_max_z_m"]:
		if not g.has(field) or not is_finite(float(g[field])):return {"built":false,"error":"Invalid receiving-floor geometry."}
	if float(g.length_m)<30 or float(g.length_m)>120 or float(g.cross_m)<20 or float(g.cross_m)>100 or float(g.core_bay_m)<6.2 or float(g.core_bay_m)>10 or float(g.clear_height_m)<2.7 or float(g.clear_height_m)>4.2:return {"built":false,"error":"Unsupported receiving-floor domain."}
	var wings:Array[Dictionary]=[]
	for side:float in [-1.0,1.0]:
		var inside:float=float(g.void_min_z_m) if side<0 else float(g.void_max_z_m)
		var core:float=side*(float(g.cross_m)*.5-5.6)
		if side*(core-inside)<=0:return {"built":false,"error":"Receiving approach would cross atrium/core."}
		wings.append({"id":"east" if side<0 else "west","side":side,"inner_z":inside,"core_z":core})
	floor_record=record.duplicate(true)
	_height=g.clear_height_m
	_make_materials()
	var kit=Kit.new(self,"ReceivingFloorCoreCollision")
	for wing:Dictionary in wings:_build_core_approaches(kit,wing,g,false)
	kit.commit(self,"ReceivingFloorCoreMaterials",true)
	_built=true
	return {"built":true,"floor_id":record.id,"scope":"QA_PHYSICAL_NEXT_FLOOR_CORE_APPROACH_ONLY","full_floor_built":false,"guest_rooms_built":0,"source_asbuilt_verified":false,"actor_teleport":false}

func _build_stair(kit, wing: Dictionary, g: Dictionary) -> void:
	var side: float = wing.side
	var x := -float(g.length_m) * .5 + 1.80
	var z := float(wing.core_z)
	var rise: float = g.storey_height_m
	var flight_width := 1.25
	var step_count := 10
	var run := 2.7
	var landing := 1.2
	# Two physical U flights. Visible treads and continuous inclined walk collision
	# share the same footprint; slope~33deg fits production floor_max_angle52.
	for stage in 2:
		var fx := x + (-0.78 if stage == 0 else 0.78)
		var low: float = 0.0 if stage == 0 else rise * .5
		for step in step_count:
			var u := float(step + 1) / step_count
			var along := landing + (float(step) + .5) / step_count * run
			if stage == 1: along = landing + run - (float(step) + .5) / step_count * run
			kit.box(Looks.get_mat("concrete_fair"), Vector3(fx, low + rise * .5 * u - .06, z + side * along), Vector3(flight_width, .12, run / step_count), Basis.IDENTITY, false)
		var a := Vector3(fx - flight_width * .5, low, z + side * (landing if stage == 0 else landing + run))
		var b := Vector3(fx + flight_width * .5, low, a.z)
		var c := Vector3(b.x, low + rise * .5, z + side * (landing + run if stage == 0 else landing))
		var d := Vector3(a.x, c.y, c.z)
		kit.col_trimesh(PackedVector3Array([a,b,c,a,c,d]))
	_solid(kit, String(wing.id) + "StairLowerLanding", Looks.get_mat("concrete_fair"), Vector3(x, -0.10, z + side * landing * .5), Vector3(3.2, .2, landing))
	_solid(kit, String(wing.id) + "StairMidLanding", Looks.get_mat("concrete_fair"), Vector3(x, rise * .5 - .10, z + side * (landing + run + landing * .5)), Vector3(3.2, .2, landing))
	_solid(kit, String(wing.id) + "StairUpperLanding", Looks.get_mat("concrete_fair"), Vector3(x, rise - .10, z + side * landing * .5), Vector3(3.2, .2, landing))
	for offset: float in [-1.48, 1.48]:
		_solid(kit, String(wing.id) + "StairGuard" + str(offset), _materials.wall, Vector3(x + offset, rise * .5 + .50, z + side * 2.6), Vector3(.12, rise + 1.0, 5.2))
	_solid(kit,String(wing.id)+"StairMidGuard",_materials.wall,Vector3(x,rise*.5+.55,z+side*(landing+run+landing)),Vector3(3.2,1.10,.10))
	_solid(kit,String(wing.id)+"StairCentreGuard",_materials.wall,Vector3(x,rise*.5+.5,z+side*(landing+run*.5)),Vector3(.10,rise+1.0,run))
	var id: String = String(floor_record.id) + "-" + String(wing.id) + "-stair"
	portals.append({"id": id, "kind": "stair", "wing": wing.id, "lower": Vector3(x - .78, 0, z - side*.60), "upper": Vector3(x + .78, rise, z - side*.60), "physical_flights": true, "walk_route": [Vector3(x-.78,0,z-side*.60),Vector3(x-.78,0,z+side*.6),Vector3(x-.78,0,z+side*landing),Vector3(x-.78,rise*.5,z+side*(landing+run)),Vector3(x-.78,rise*.5,z+side*(landing+run+.6)),Vector3(x+.78,rise*.5,z+side*(landing+run+.6)),Vector3(x+.78,rise*.5,z+side*(landing+run)),Vector3(x+.78,rise,z+side*landing),Vector3(x+.78,rise,z+side*.6)], "actor_teleport": false, "adjacent_floor_collision_required": true})

func _build_service_closet(kit, wing:Dictionary, g:Dictionary)->void:
	var x:float=-float(g.length_m)*.5+4.90
	var side:float=wing.side
	var z:float=wing.core_z
	var id:String=String(floor_record.id)+"-"+String(wing.id)+"-linen-service"
	var depth:=3.6
	_floor_ceiling(kit,id,Vector3(x,0,z+side*depth*.5),Vector2(2.10,depth))
	for end:float in [-1.0,1.0]:
		_solid(kit,id+"Side"+str(end),_materials.wall,Vector3(x+end*1.05,_height*.5,z+side*depth*.5),Vector3(WALL,_height,depth))
	_solid(kit,id+"Back",_materials.wall,Vector3(x,_height*.5,z+side*depth),Vector3(2.10,_height,WALL))
	_wall_x_gap(kit,id+"Entry",z,x-1.05,x+1.05,x,1.12,_height)
	_door(id,Vector3(x-.56,0,z),1.12,0,-side*PI*.5)
	_solid(kit,id+"LinenCabinet",Looks.get_mat("timber"),Vector3(x,1.05,z+side*3.15),Vector3(1.65,2.10,.60))
	for row in 4:
		kit.box(_materials.linen,Vector3(x,0.45+float(row)*.40,z+side*2.80),Vector3(1.40,.18,.35))
	_label(Vector3(x,1.55,z-side*.07),"LINEN / SERVICE",.0015)
	portals.append({"id":id,"kind":"linen_service_room","wing":wing.id,"landing":Vector3(x,0,z-side*.60),"inside":Vector3(x,0,z+side*1.4),"actor_teleport":false})

func _build_lift_landing(kit, wing: Dictionary, g: Dictionary) -> void:
	var x := float(g.length_m) * .5 - float(g.core_bay_m) * .5
	var side: float = wing.side
	var z: float = wing.core_z
	# Fill the intervals between the two frame modules and end walls; no
	# narrow unmodeled slit leads around an interlocked landing door.
	for bounds:Vector2 in [Vector2(x-float(g.core_bay_m)*.5,x-2.5),Vector2(x-.10,x+.10),Vector2(x+2.5,x+float(g.core_bay_m)*.5)]:
		_solid(kit,String(wing.id)+"LiftClosure"+str(bounds.x),_materials.wall,Vector3((bounds.x+bounds.y)*.5,_height*.5,z),Vector3(bounds.y-bounds.x,_height,WALL))
	for service in 2:
		var cx := x + (-1.30 if service == 0 else 1.30)
		var kind := "guest_lift" if service == 0 else "service_lift"
		var id: String = String(floor_record.id) + "-" + String(wing.id) + "-" + kind
		# Landing floor only; never a fake shaft floor/cabin. Root coordinates a
		# physical cabin, shaft, loaded destination collision and landing interlock.
		_door(id, Vector3(cx - .65, 0, z), 1.30, 0.0, -side * PI * .5, kind)
		portals.append({"id": id, "kind": kind, "wing": wing.id, "landing": Vector3(cx, 0, z-side*.60), "threshold": Vector3(cx,0,z), "cabin_expected_center": Vector3(cx,0,z+side*1.4), "requires_physical_cabin": true, "loaded_collision_required": true, "actor_teleport": false})
		_wall_x_gap(kit, id + "Frame", z, cx - 1.20, cx + 1.20, cx, 1.30, _height)
		_label(Vector3(cx, 2.55, z - side * .05), "SERVICE" if service else "LIFTS", 0.0016)

static func _p(cell: Dictionary, u: float, y: float, v: float) -> Vector3:
	return Vector3(float(cell.center_x) + u, y, float(cell.inner_z) + float(cell.side) * v)

func _build_room(kit, cell: Dictionary) -> void:
	var half: float = float(cell.frontage_m) * .5
	var depth: float = cell.depth_m
	var side: float = cell.side
	var entry_u := -half + .85
	_wall_x_gap(kit, String(cell.id) + "EntryWall", cell.inner_z, float(cell.center_x)-half, float(cell.center_x)+half, float(cell.center_x)+entry_u, DOOR_WIDTH, _height)
	for end: float in [-1.0,1.0]:
		_solid(kit, String(cell.id) + "PartyWall" + str(end), _materials.wall, _p(cell,end*half,_height*.5,depth*.5),Vector3(WALL,_height,depth))
	var hinge := _p(cell,entry_u-DOOR_WIDTH*.5,0,0)
	_door(String(cell.id),hinge,DOOR_WIDTH,0,-side*PI*.5)
	cell["entry_local"] = _p(cell,entry_u,0,-1.15)
	cell["inside_local"] = _p(cell,entry_u,0,1.45)
	cell["view_local"] = _p(cell,entry_u,0,depth-1.1)
	_label(_p(cell,entry_u+1.0,1.55,-.08),String(cell.label),0.0018)
	# Ceiling and floor finish differ at the bath, while all collision is solid.
	kit.box(Looks.get_mat("granite_light"),_p(cell,half-float(cell.bath_width_m)*.5,.015,1.4),Vector3(cell.bath_width_m,.03,2.8))
	_build_bathroom(kit,cell)
	if cell.is_suite: _suite_fitout(kit,cell)
	else: _premier_fitout(kit,cell)
	_light(_p(cell,0,_height-.20,depth*.62),1.1,maxf(6.0,depth*.65))
	# Original trim/curtain folds keep material detail without copying room art.
	for end: float in [-1.0,1.0]:
		for fold in 4:
			kit.box(_materials.linen,_p(cell,end*(half-.18)-end*float(fold)*.06,_height*.5,depth-.20),Vector3(.08,_height-.12,.20))
	kit.box(Looks.get_mat("steel_bronze"),_p(cell,0,_height-.10,depth-.18),Vector3(cell.frontage_m,.08,.10))

func _wall_x_gap(kit, id: String, z: float, x0: float, x1: float, center: float, width: float, h: float) -> void:
	for bounds: Vector2 in [Vector2(x0,center-width*.5),Vector2(center+width*.5,x1)]:
		if bounds.y-bounds.x > .01:_solid(kit,id+str(bounds.x),_materials.wall,Vector3((bounds.x+bounds.y)*.5,h*.5,z),Vector3(bounds.y-bounds.x,h,WALL))
	_solid(kit,id+"Lintel",_materials.wall,Vector3(center,(h+DOOR_HEIGHT)*.5,z),Vector3(width,h-DOOR_HEIGHT,WALL))

func _build_bathroom(kit, cell: Dictionary) -> void:
	var half: float = float(cell.frontage_m)*.5
	var width: float = cell.bath_width_m
	var left := half-width
	var side: float = cell.side
	var door_v := 1.35
	var bath_door_width := 1.12
	# Left side bathroom wall with an actual hinged opening into the bathroom.
	for bounds:Vector2 in [Vector2(0,door_v-bath_door_width*.5),Vector2(door_v+bath_door_width*.5,2.8)]:
		_solid(kit,String(cell.id)+"BathSide"+str(bounds.x),_materials.wall,_p(cell,left,_height*.5,(bounds.x+bounds.y)*.5),Vector3(WALL,_height,bounds.y-bounds.x))
	_solid(kit,String(cell.id)+"BathLintel",_materials.wall,_p(cell,left,(_height+DOOR_HEIGHT)*.5,door_v),Vector3(WALL,_height-DOOR_HEIGHT,bath_door_width))
	_solid(kit,String(cell.id)+"BathBack",_materials.wall,_p(cell,half-width*.5,_height*.5,2.8),Vector3(width,_height,WALL))
	_door(String(cell.id)+"-bath",_p(cell,left,0,door_v-bath_door_width*.5),bath_door_width,-side*PI*.5,side*PI*.5)
	cell["bath_outside_local"]=_p(cell,left-.80,0,door_v)
	cell["bath_inside_local"]=_p(cell,left+1.30,0,door_v)
	# Bathtub, rain shower, counter/basin/mirror and WC occupy distinct bays.
	_solid(kit,String(cell.id)+"Tub",Looks.get_mat("granite_light"),_p(cell,left+1.0,.32,2.30),Vector3(1.80,.64,.90))
	kit.box(_materials.linen,_p(cell,left+1.0,.66,2.30),Vector3(1.56,.05,.66))
	_solid(kit,String(cell.id)+"Vanity",Looks.get_mat("timber"),_p(cell,left+width*.32,.43,.42),Vector3(width*.52,.86,.65))
	kit.box(Looks.get_mat("granite_light"),_p(cell,left+width*.32,.90,.42),Vector3(width*.56,.10,.70))
	kit.cyl(_materials.linen,_p(cell,left+width*.32,.95,.43),.23,.27,.08,12)
	kit.box(_materials.mirror,_p(cell,left+width*.32,1.70,.14),Vector3(width*.52,1.10,.035))
	_solid(kit,String(cell.id)+"WC",_materials.linen,_p(cell,half-.42,.34,2.30),Vector3(.55,.68,.72))
	_solid(kit,String(cell.id)+"ShowerGlass",Looks.get_mat("glass_clear"),_p(cell,half-.70,1.2,.85),Vector3(.04,2.4,.80))
	kit.cyl(Looks.get_mat("steel_satin"),_p(cell,half-.35,2.50,.85),.16,.16,.04,12)
	kit.box(Looks.get_mat("steel_satin"),_p(cell,half-.35,2.25,.32),Vector3(.04,.50,.04))
	_light(_p(cell,half-width*.5,2.85,1.1),.65,4.0)

func _bed(kit, cell: Dictionary, u: float, v: float, width: float = 1.95) -> void:
	_solid(kit,String(cell.id)+"Bed"+str(u),Looks.get_mat("timber"),_p(cell,u,.24,v),Vector3(width+.16,.48,2.25))
	kit.box(_materials.linen,_p(cell,u,.57,v),Vector3(width,.22,2.14))
	kit.box(_materials.throw,_p(cell,u,.70,v-.60),Vector3(width,.06,.55))
	for sign:float in [-1.0,1.0]:
		kit.box(_materials.linen,_p(cell,u+sign*width*.25,.75,v+.62),Vector3(width*.43,.14,.48))
	kit.box(Looks.get_mat("timber"),_p(cell,u,1.05,v+1.16),Vector3(width+.40,1.50,.10))
	for slat in 8:
		kit.box(Looks.get_mat("steel_bronze"),_p(cell,u-width*.47+float(slat)*width/7.5,1.05,v+1.09),Vector3(.035,1.28,.04))
	for sign:float in [-1.0,1.0]:
		_solid(kit,String(cell.id)+"Nightstand"+str(u)+str(sign),Looks.get_mat("timber"),_p(cell,u+sign*(width*.5+.14),.42,v+.70),Vector3(.28,.84,.45))
		kit.cyl(Looks.get_mat("steel_bronze"),_p(cell,u+sign*(width*.5+.14),.85,v+.70),.035,.035,.38,8)
		kit.cyl(_materials.linen,_p(cell,u+sign*(width*.5+.14),1.18,v+.70),.17,.12,.22,10)

func _premier_fitout(kit,cell:Dictionary)->void:
	var half:float=float(cell.frontage_m)*.5
	var depth:float=cell.depth_m
	var bed_width:=minf(1.95,float(cell.frontage_m)-2.30)
	var u:float=-minf(float(cell.frontage_m)*.22,2.2) if depth<8.0 else minf(float(cell.frontage_m)*.17,1.15)
	u=maxf(u,-half+1.60+bed_width*.5+.28)
	if cell.bed_variant=="twin_queen":
		_bed(kit,cell,u-.82,depth-1.25,1.40)
		_bed(kit,cell,u+.82,depth-1.25,1.40)
	else:_bed(kit,cell,u,depth-1.25,bed_width)
	var desk_u:=half-.75
	_solid(kit,String(cell.id)+"Desk",Looks.get_mat("timber"),_p(cell,desk_u,.76,depth-.70),Vector3(1.20,.10,.60))
	kit.box(_materials.screen,_p(cell,desk_u,1.3,depth-.55),Vector3(.75,.48,.035))
	_solid(kit,String(cell.id)+"Armoire",Looks.get_mat("timber"),_p(cell,half-.36,1.1,4.1),Vector3(.64,2.20,1.40))
	kit.box(Looks.get_mat("steel_bronze"),_p(cell,half-.70,1.0,4.1),Vector3(.03,.08,.65))
	if depth>=9.0:_sofa(kit,cell,.25,5.5,1.65)

func _sofa(kit,cell:Dictionary,u:float,v:float,width:float)->void:
	_solid(kit,String(cell.id)+"Sofa"+str(u),_materials.leather,_p(cell,u,.44,v),Vector3(width,.88,.82))
	kit.box(_materials.linen,_p(cell,u,.48,v-.10),Vector3(width-.15,.10,.60))
	kit.box(Looks.get_mat("timber"),_p(cell,u,.10,v),Vector3(width-.10,.20,.68))

func _suite_fitout(kit,cell:Dictionary)->void:
	var half:float=float(cell.frontage_m)*.5
	var depth:float=cell.depth_m
	var living:float=cell.living_width_m
	var divider:float=-half+living
	var bedroom_front:=4.05
	var bedrooms:int=cell.bedrooms
	var bedroom_width:float=(float(cell.frontage_m)-living)/bedrooms
	_solid(kit,String(cell.id)+"LivingDivider",_materials.wall,_p(cell,divider,_height*.5,(bedroom_front+depth)*.5),Vector3(WALL,_height,depth-bedroom_front))
	for i in bedrooms:
		var left:=divider+float(i)*bedroom_width
		var right:=left+bedroom_width
		var door_center:=left+.72
		_wall_x_gap(kit,String(cell.id)+"BedroomFront"+str(i),float(cell.inner_z)+float(cell.side)*bedroom_front,float(cell.center_x)+left,float(cell.center_x)+right,float(cell.center_x)+door_center,1.15,_height)
		if i>0:_solid(kit,String(cell.id)+"BedroomPartition"+str(i),_materials.wall,_p(cell,left,_height*.5,(bedroom_front+depth)*.5),Vector3(WALL,_height,depth-bedroom_front))
		_door(String(cell.id)+"-bedroom-"+str(i+1),_p(cell,door_center-.575,0,bedroom_front),1.15,0,-float(cell.side)*PI*.5)
		_bed(kit,cell,float(cell.bedroom_layouts[i].bed_u),depth-1.25,1.95)
	_sofa(kit,cell,-half+living-.95,depth*.68,1.65)
	_solid(kit,String(cell.id)+"CoffeeTable",Looks.get_mat("granite_light"),_p(cell,-half+living-1.0,.30,float(cell.coffee_table_v)),Vector3(1.0,.60,.62))
	kit.box(_materials.screen,_p(cell,divider-.12,1.50,depth*.68),Vector3(.05,.90,1.50))
	_solid(kit,String(cell.id)+"SocialBar",Looks.get_mat("timber"),_p(cell,float(cell.social_bar_u),.56,float(cell.social_bar_v)),Vector3(1.0,1.12,.65))
	# Compact dining joins the front circulation bay while preserving the left
	# through-aisle. Geometric choices are reconstruction, not a sample-plan copy.
	if float(cell.frontage_m)>11.0:
		_solid(kit,String(cell.id)+"Dining",Looks.get_mat("timber"),_p(cell,float(cell.dining_u),.76,float(cell.dining_v)),Vector3(1.35,.12,.75))
		for offset:Vector2 in [Vector2(-.85,-.55),Vector2(-.85,.55),Vector2(.85,-.55),Vector2(.85,.55),Vector2(0,-.65),Vector2(0,.65)]:
			var at:=_p(cell,float(cell.dining_u)+offset.x,.45,float(cell.dining_v)+offset.y)
			_solid(kit,String(cell.id)+"DiningChair"+str(offset),_materials.leather,at,Vector3(.42,.90,.42))
			kit.box(Looks.get_mat("timber"),at-Vector3.UP*.29,Vector3(.36,.32,.36))

func _door(id:String,hinge:Vector3,width:float,base:float,swing:float,transition_kind:String="")->SwingDoor:
	var door:=SwingDoor.new()
	door.name="Door_"+id.replace("-","_")
	door.door_id=id
	door.hinge_origin=hinge
	door.leaf_width=width
	door.coordinator=self
	door.motion_angle=base
	door.transform=Transform3D(Basis(Vector3.UP,base),hinge+Basis(Vector3.UP,base)*Vector3(width*.5,0,0))
	door.base_angle=base
	door.swing_delta=swing
	door.transition_kind=transition_kind
	door.collision_layer=1
	door.collision_mask=0
	door.sync_to_physics=true
	add_child(door)
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(width,DOOR_HEIGHT,.075)
	shape.shape=box
	shape.position=Vector3(0,DOOR_HEIGHT*.5,0)
	door.add_child(shape)
	var leaf=Kit.new()
	leaf.box(Looks.get_mat("timber"),shape.position,box.size,Basis.IDENTITY,false)
	leaf.box(Looks.get_mat("steel_bronze"),Vector3(width*.5-.12,1.02,-.055),Vector3(.08,.035,.09))
	leaf.commit(door,"DoorLeafMaterial",true)
	doors[id]=door
	return door

func set_door_open(id:String,value:bool)->bool:
	var door:SwingDoor=doors.get(id)
	if door==null or not door.set_open(value):return false
	door_state_changed.emit(String(floor_record.id),id,value)
	return true

func request_interaction(id:String)->bool:
	var door:SwingDoor=doors.get(id)
	if door==null:return false
	if not door.transition_kind.is_empty():
		transition_requested.emit(String(floor_record.id),id,door.transition_kind)
		return true
	return set_door_open(id,not door.opened)

func confirm_transition_ready(id:String,ready:bool)->bool:
	var door:SwingDoor=doors.get(id)
	if door==null or door.transition_kind.is_empty():return false
	door.ready_to_open=ready
	return set_door_open(id,ready)

func closest_interaction(world_position:Vector3,max_distance:float=2.3)->Dictionary:
	var best:Dictionary={}
	var best_distance:=max_distance
	for id:String in doors:
		var door:SwingDoor=doors[id]
		var d:=world_position.distance_to(door.global_position+Vector3.UP*.9)
		if d<best_distance:
			best_distance=d
			best={"id":id,"kind":door.transition_kind,"action":"Open" if not door.opened else "Close","distance_m":d}
	return best

func serialize_state()->Dictionary:
	var states:Dictionary={}
	for id:String in doors:
		var door:SwingDoor=doors[id]
		if door.transition_kind.is_empty():states[id]=door.opened
	return {"floor_id":floor_record.get("id",""),"room_doors":states,"current_private_asbuilt_verified":false}

func restore_state(state:Dictionary)->bool:
	if state.get("floor_id","")!=floor_record.get("id",""):return false
	for id:String in state.get("room_doors",{}):
		if doors.has(id) and (doors[id] as SwingDoor).transition_kind.is_empty():set_door_open(id,bool(state.room_doors[id]))
	return true

func public_route_local(start:Vector3,target:Vector3,wing_id:String)->Array[Vector3]:
	# Same-wing public-floor navigation only. It never crosses a room as a
	# shortcut and never bridges a low atrium void. Root handles other floors.
	var route:Array[Vector3]=[]
	if not _built or absf(start.y)>.25 or absf(target.y)>.25:return route
	var wing:Dictionary={}
	for item:Dictionary in _plan.wings:
		if item.id==wing_id:wing=item;break
	if wing.is_empty():return route
	var g:Dictionary=_plan.geometry
	if not _public_point(start,wing,g) or not _public_point(target,wing,g):return route
	var room_end:float=float(g.length_m)*.5-float(g.core_bay_m)
	var start_bank:int=-1 if start.x < -room_end else 1 if start.x > room_end else 0
	var target_bank:int=-1 if target.x < -room_end else 1 if target.x > room_end else 0
	if start_bank!=0 and start_bank==target_bank:
		route.append(Vector3(target.x,0,target.z))
		return route
	# Fixed outer-wing cores have deep end-bay approaches; travel back to
	# the true inner corridor before walking longitudinally past room cells.
	route.append(Vector3(start.x,0,wing.corridor_center_z))
	route.append(Vector3(target.x,0,wing.corridor_center_z))
	route.append(Vector3(target.x,0,target.z))
	return route

func _public_point(point:Vector3,wing:Dictionary,g:Dictionary)->bool:
	if absf(point.x)>float(g.length_m)*.5:return false
	var outward:float=float(wing.side)*(point.z-float(wing.inner_z))
	var room_end:float=float(g.length_m)*.5-float(g.core_bay_m)
	var depth:float=float(g.corridor_width_m) if absf(point.x)<=room_end else absf(float(wing.core_z)-float(wing.inner_z))
	return outward>=0.0 and outward<=depth

func room_route_local(id:String)->Array[Vector3]:
	for cell:Dictionary in rooms:
		if cell.id==id:return [cell.entry_local,cell.inside_local,cell.view_local,cell.inside_local,cell.entry_local]
	return []

func _light(p:Vector3,energy:float,reach:float)->void:
	var light:=OmniLight3D.new()
	light.position=p
	light.light_color=Color(1.0,.84,.64)
	light.light_energy=energy
	light.omni_range=reach
	light.shadow_enabled=false
	add_child(light)

func _label(p:Vector3,text:String,pixel:float)->void:
	var label:=Label3D.new()
	label.position=p
	label.text=text
	label.font_size=38
	label.pixel_size=pixel
	label.modulate=Color(.73,.62,.43)
	add_child(label)

func report()->Dictionary:
	return {"built":_built,"floor_id":floor_record.get("id",""),"guest_rooms_built":rooms.size(),"door_count":doors.size(),"physical_portals":portals.duplicate(true),"preserves_atrium_void":true,"local_coordinates_only":true,"current_private_asbuilt_verified":false,"integrated_city_traversal_verified":false,"all1850rooms_runtime_verified":false,"full_building_completed":false,"requires":"Root physical stair/lift/shaft/streaming/source-placement coordinator; events never move actors."}
