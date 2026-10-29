extends Node3D
## Incomplete public-L1 stage: sourced continuous/tapered atrium envelope.
## Arup 2012 pp21-23 is historical engineering evidence, not current fit-out.
## Metric roof heights, precise boundaries and entry locations remain unknown.
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")
const Canopy = preload("res://src/world/downtown/canopy.gd")
const SourceFrame = preload("res://src/world/geography/source_frame.gd")
const FLOOR_THICKNESS := 0.24
const WALL_THICKNESS := 0.24
# Supported construction domain, not an architectural assertion. These bounds
# exceed the source hotel dimensions but refuse pathological configuration work.
const MAX_ZONE_LENGTH_M := 1000.0
const MAX_ZONE_WIDTH_M := 500.0
const MAX_ROOF_HEIGHT_M := 300.0
const MAX_SITE_SPAN_M := 2000.0
const MAX_ABS_FLOOR_ELEVATION_M := 1000.0
const MAX_STRUCTURAL_MEMBER_BUDGET := 16000.0
const PUBLIC_AISLE_WIDTH_M := 4.0
const AISLE_FURNITURE_BUFFER_M := 0.50
const FURNITURE_WALL_BUFFER_M := 0.25
# The operator documents 3 m vessels in the historic Rising Forest installation.
# These are deliberately generic original containers, NOT a copy of that artwork.
const TREE_VESSEL_HEIGHT_M := 3.0
const PUBLIC_STONE_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec2 plan;
float stone_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float stone_noise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(stone_hash(i), stone_hash(i + vec2(1,0)), f.x), mix(stone_hash(i + vec2(0,1)), stone_hash(i + vec2(1,1)), f.x), f.y);
}
void vertex() { plan = VERTEX.xz; }
void fragment() {
    // Large, near-flush pale stone slabs. All scales are metres, so the long
    // atrium quads cannot stretch a texture into the previous amber streaks.
    vec2 slab = plan / vec2(2.4, 1.2);
    vec2 edge = min(fract(slab), 1.0 - fract(slab));
    vec2 aa = max(fwidth(slab) * 1.1, vec2(0.0001));
    float joint = 1.0 - min(smoothstep(0.0012, 0.0012 + aa.x, edge.x), smoothstep(0.0024, 0.0024 + aa.y, edge.y));
    float grain = stone_noise(plan * 3.4) * 0.006 + stone_noise(plan * 0.43) * 0.012;
    float piece = stone_hash(floor(slab)) * 0.012;
    ALBEDO = vec3(0.79, 0.80, 0.77) + grain + piece - joint * 0.055;
    ROUGHNESS = 0.64 + stone_noise(plan * 0.7) * 0.045;
    METALLIC = 0.0;
    SPECULAR = 0.28;
}
"""
const UNBUILT_AREAS := ["hotel_guest_floor_inventory", "all_guestrooms_and_suites", "hotel_service_and_back_of_house", "hotel_lift_and_stair_cores", "paiza_T2_L55", "public_deck_T3_L56", "public_mezzanine_L57", "guest_pool_restaurants_L57", "shoppes_L1", "shoppes_B1", "shoppes_B2", "casino_B2M", "coach_B2M", "underground_links", "bayfront_station"]

var zones: Array[Dictionary] = []
var corridors: Array[Dictionary] = []
var sections: Array[Dictionary] = []
var furniture: Array[Dictionary] = []
var portal_local: Dictionary = {}
var public_path_local: Array[Vector3] = []
var _assumptions: Array[Dictionary] = []
var _built := false
var _source_position := Vector3.ZERO
var _source_basis := Basis.IDENTITY
var _report: Dictionary = {}
var _floor_material: Material
var _tree_layout: Array[Dictionary] = []
var _entrance_tower := "T1"
var _entrance_offset := 0.0
var _entrance_sign := 1.0
var _entrance_x := 0.0
var _door_width := 4.0
var _door_height := 4.8
var _east_inset_ratio := 0.14
var core_connections: Array[Dictionary] = []
var arrival_corridor: Dictionary = {}

func build(config: Dictionary = {}) -> Dictionary:
	if _built: return {"built": false, "error": "Already built; construct a new module for another plan."}
	# Transaction boundary: validation builds temporary value-only state. A failed
	# request must not move this node, append zones or create child/collision nodes.
	var plan: Dictionary = _validated_plan(config)
	if not plan.get("valid", false): return {"built": false, "error": plan.get("error", "Invalid plan"), "full_requested_interior_verified": false}
	zones.assign(plan.zones)
	sections.assign(plan.sections)
	furniture.assign(plan.furniture)
	core_connections.assign(plan.get("core_connections",[]))
	arrival_corridor=plan.get("arrival_corridor",{}).duplicate(true)
	_assumptions.assign(plan.assumptions)
	_source_position = plan.position
	_source_basis = plan.basis
	# Source coordinates are ABSOLUTE world coordinates even under a translated,
	# rotated unit parent. Assigning local transform here was an earlier API bug.
	global_transform = Transform3D(_source_basis, _source_position)
	_entrance_tower = plan.entrance_tower
	_entrance_offset = plan.entrance_offset
	_entrance_sign = plan.entrance_sign
	_entrance_x = plan.entrance_x
	_door_width = plan.door_width
	_door_height = plan.door_height
	_east_inset_ratio = plan.east_inset_ratio
	# Module-local material: never mutate the cached exterior Palette/Looks mats.
	var stone_shader := Shader.new()
	stone_shader.code = PUBLIC_STONE_SHADER
	var stone := ShaderMaterial.new()
	stone.shader = stone_shader
	_floor_material = stone
	var kit = Kit.new(self, "MBSPublicL1Collision")
	var glass = Kit.new()
	_build_continuous_envelope(kit, glass)
	for i in zones.size():
		var zone: Dictionary = zones[i]
		var marker := Node3D.new()
		marker.name = "PublicAtrium" + String(zone.tower)
		marker.position = zone.center
		marker.set_meta("source_id", zone.source_id)
		marker.set_meta("geometry_status", "HISTORICAL_PROFILE_WITH_UNVERIFIED_METRIC_HEIGHTS_AND_FITOUT")
		add_child(marker)
		marker.add_to_group("mbs_interior_public_nodes")
		_furnish(kit, zone)
		var sign_x: float = (zone.center as Vector3).x + float(zone.length_m) * 0.20
		# Attach wayfinding to the landward frame, not an unsupported label in air.
		_sign(_edge(_section_at(sign_x), -1.0, 2.25) + Vector3(0, 0, 0.09), "TOWER " + String(zone.tower).trim_prefix("T") + "\nHOTEL ATRIUM", 0.0, 3.2)
		if i + 1 < zones.size():
			corridors.append({"from": zone.id, "to": zones[i + 1].id, "a": zone.center, "b": zones[i + 1].center, "kind": "CONTINUOUS_FULL_HEIGHT_ATRIUM", "metric_status": "HISTORICAL_APPROX_WIDTHS_UNVERIFIED_PRECISE_BOUNDARY"})
	_build_approach(kit, glass)
	for connection: Dictionary in core_connections: _build_connection_adapter(kit,glass,connection)
	if not arrival_corridor.is_empty(): _build_arrival_adapter(kit,glass,arrival_corridor)
	_build_path()
	kit.commit(self, "MBSPublicL1Structure", true)
	glass.commit(self, "MBSPublicL1Glazing", false)
	_built = true
	_report = {"built": true, "module": "source_backed_continuous_public_L1_stage_r2", "source": Reference.DATA.source.duplicate(true), "engineering_source": Reference.ATRIUM_ENGINEERING.duplicate(true), "topology_sources": Reference.DATA.topology_sources.duplicate(true), "tower_source_ids": [], "public_nodes_built": [], "continuous_atrium": true, "isolated_low_tunnels_built": 0, "geometry_metric_status": "HISTORICAL_APPROX_WIDTHS_WITH_EXPLICIT_UNVERIFIED_HEIGHTS_BOUNDARIES", "roof_heights_metric_verified": false, "entrance_metric_verified": false, "floor_elevations_verified": false, "architectural_identity_and_fitout_verified": false, "entire_floor_space_inventory_complete": false, "full_requested_interior_verified": false, "unbuilt_areas": UNBUILT_AREAS.duplicate(), "assumptions": _assumptions.duplicate(true), "triangle_count": kit.tris + glass.tris, "collision_shapes": kit.shapes, "retail_connection_built": false, "expected_approx_hotel_rooms": 1850, "room_inventory_created": 0, "profile_sections": sections.duplicate(true), "construction_budget": plan.construction_budget.duplicate(true), "reserved_public_aisle_width_m": PUBLIC_AISLE_WIDTH_M, "furniture_items": furniture.size(), "furniture_layout": furniture.duplicate(true)}
	for zone: Dictionary in zones:
		_report.tower_source_ids.append(zone.source_id)
		_report.public_nodes_built.append(zone.id)
	_report["planting_visual_stage"] = {"generic_vessel_height_m": TREE_VESSEL_HEIGHT_M, "tree_layout": _tree_layout.duplicate(true), "source_fit": "HISTORICAL_TALL_PLANTED_COMPOSITION_ONLY", "artwork_replica": false, "current_fitout_verified": false}
	_report["floor_finish_status"] = "ORIGINAL_PALE_STONE_STAGING_MATERIAL_NOT_VERIFIED_INSTALLED_STONE"
	_report["core_connections"]=core_connections.duplicate(true)
	_report["arrival_corridor"]=arrival_corridor.duplicate(true)
	if plan.has("coordinate_context"): _report["coordinate_context"] = plan.coordinate_context.duplicate(true)
	return report()

func _validated_plan(config: Dictionary) -> Dictionary:
	if not is_inside_tree(): return {"valid": false, "error": "Add the module to the tree before building absolute source placement."}
	if not String(config.get("entrance_tower", "T1")) in ["T3", "T2", "T1"]: return {"valid": false, "error": "Unknown entrance tower."}
	if not String(config.get("entrance_side", "bayward")) in ["bayward", "landward"]: return {"valid": false, "error": "Unknown entrance facade."}
	if not basis.get_scale().is_equal_approx(Vector3.ONE): return {"valid": false, "error": "Module must have unit scale."}
	if get_parent() is Node3D and not (get_parent() as Node3D).global_basis.get_scale().is_equal_approx(Vector3.ONE): return {"valid": false, "error": "Parent scale would compress source metres."}
	var arrival_request: Variant=config.get("arrival_corridor",{})
	if not arrival_request is Dictionary: return {"valid":false,"error":"Arrival corridor must be an explicit dictionary."}
	var arrival_on: bool=not arrival_request.is_empty()
	if arrival_on and not validate_connection_request(arrival_request,true): return {"valid":false,"error":"Incomplete/nonfinite arrival corridor request."}
	if arrival_on and (String(config.get("entrance_tower","T1"))!="T1" or String(config.get("entrance_side","bayward"))!="bayward"): return {"valid":false,"error":"Reconstructed arrival must join the existing T1 bayward entrance."}
	var door_width: float = float(config.get("entrance_width_m", arrival_request.get("width_m",4.0) if arrival_on else 4.0))
	var door_height: float = float(config.get("entrance_height_m", arrival_request.get("height_m",4.8) if arrival_on else 4.8))
	var clearance: float = float(config.get("corridor_width_m", 6.0))
	var inset: float = float(config.get("east_upper_wall_inset_ratio", 0.14))
	var elevation: float = float(config.get("floor_elevation_m", 0.0))
	var offset: float = float(config.get("entrance_along_offset_m", arrival_request.get("along_offset_m",0.0) if arrival_on else 0.0))
	if not is_finite(door_width) or not is_finite(door_height) or not is_finite(clearance) or not is_finite(inset) or not is_finite(elevation) or not is_finite(offset): return {"valid": false, "error": "Dimensions must be finite."}
	if door_width > MAX_ZONE_LENGTH_M or door_height > MAX_ROOF_HEIGHT_M or clearance > MAX_ZONE_WIDTH_M or absf(offset) > MAX_ZONE_LENGTH_M or absf(elevation) > MAX_ABS_FLOOR_ELEVATION_M: return {"valid": false, "error": "Configuration exceeds supported metric construction domain."}
	if door_width < 2.4 or door_height < 2.5 or clearance < 4.0 or inset < 0.0 or inset > 0.3: return {"valid": false, "error": "Invalid clear opening or staged wall inclination."}
	var new_zones: Array[Dictionary] = []
	var new_sections: Array[Dictionary] = []
	var assumptions: Array[Dictionary] = []
	var dimensions: Dictionary = config.get("atrium_dimensions", {})
	var widths: Dictionary = Reference.ATRIUM_ENGINEERING.approx_width_m
	# Deliberate visual defaults only. No floor-to-floor conversion is presented
	# as a survey; the primary source gives storey counts, not these elevations.
	var height_defaults := {"T3": 27.0, "T2": 47.0, "T1": 76.0}
	var entry_x := 0.0
	for source: Dictionary in Reference.DATA.towers:
		var tower: String = source.tower
		var overrides: Dictionary = dimensions.get(tower, {})
		var center: Array = source.centroid_local_xz
		var length_m: float = float(overrides.get("length_m", float(source.source_long_extent_m) * 0.78))
		var width_m: float = float(overrides.get("width_m", widths[tower]))
		var h: float = float(overrides.get("roof_height_m", overrides.get("wall_height_m", height_defaults[tower])))
		if not is_finite(length_m) or not is_finite(width_m) or not is_finite(h) or length_m < 12.0 or width_m < 8.0 or h < 12.0: return {"valid": false, "error": "Invalid staged envelope dimension."}
		if length_m > MAX_ZONE_LENGTH_M or width_m > MAX_ZONE_WIDTH_M or h > MAX_ROOF_HEIGHT_M: return {"valid": false, "error": "Envelope exceeds supported metric construction domain."}
		if clearance > width_m - 1.0 or door_height > h - 0.5: return {"valid": false, "error": "Opening does not fit staged continuous envelope."}
		var zone := {"id": "hotel_" + tower + "_L1", "tower": tower, "source_id": source.id, "center": Vector3(float(center[0]), 0, float(center[1])), "length_m": length_m, "width_m": width_m, "wall_height_m": h}
		new_zones.append(zone)
		new_sections.append({"center": zone.center, "width_m": width_m, "height_m": h, "tower": tower})
		assumptions.append({"field": zone.id + ".envelope", "value": {"longitudinal_extent_m": length_m, "width_m": width_m, "roof_height_m": h}, "width_status": "HISTORICAL_ARUP_2012_APPROXIMATE" if not overrides.has("width_m") else "UNVERIFIED_OVERRIDE", "height_status": "UNVERIFIED_METRIC_STAGING_VALUE_NOT_STOREY_CONVERSION", "longitudinal_extent_status": "UNVERIFIED_OSM_DERIVED_STAGING", "why": "Historical source establishes continuous taper and approximate widths/storey counts, not current as-built section elevations/boundary."})
		if tower == String(config.get("entrance_tower", "T1")):
			if absf(offset) + door_width * 0.5 > length_m * 0.5 - 1.0: return {"valid": false, "error": "Entrance exceeds staged facade extent."}
			entry_x = float(center[0]) + offset
	if float(new_sections[0].height_m) >= float(new_sections[1].height_m) or float(new_sections[1].height_m) >= float(new_sections[2].height_m): return {"valid": false, "error": "Roof profile must rise continuously T3 to T1."}
	var north: Dictionary = new_sections[0].duplicate(true)
	var south: Dictionary = new_sections[-1].duplicate(true)
	north.center -= Vector3.RIGHT * float(new_zones[0].length_m) * 0.5
	south.center += Vector3.RIGHT * float(new_zones[-1].length_m) * 0.5
	north.tower = "UNVERIFIED_NORTH_CAP"
	south.tower = "UNVERIFIED_SOUTH_CAP"
	new_sections.push_front(north)
	new_sections.append(south)
	# Float-only estimate is evaluated before any ceil-to-int conversion or
	# construction/member loop. Bounded five-section planning cannot amplify a
	# finite but huge input into billions of iterations.
	var member_budget := 256.0 # conservative fixed furniture/tree/door/cap allowance
	var total_span := 0.0
	for i in new_sections.size() - 1:
		var a: Vector3 = new_sections[i].center
		var b: Vector3 = new_sections[i + 1].center
		var dx: float = b.x - a.x
		if not is_finite(dx) or dx <= 0.0 or dx > MAX_SITE_SPAN_M: return {"valid": false, "error": "Invalid or unsupported longitudinal section span."}
		total_span += dx
		var side_divisions: float = ceil(dx / 5.0)
		var roof_divisions: float = ceil(a.distance_to(b) / 7.0)
		member_budget += 2.0 * (side_divisions + 1.0) * 19.0 + 7.0 * (roof_divisions + 1.0)
	if not is_finite(member_budget) or total_span > MAX_SITE_SPAN_M or member_budget > MAX_STRUCTURAL_MEMBER_BUDGET: return {"valid": false, "error": "Plan exceeds supported structural-member construction budget."}
	var construction_budget := {"estimated_member_upper_bound": member_budget, "maximum_members": MAX_STRUCTURAL_MEMBER_BUDGET, "site_span_m": total_span, "maximum_site_span_m": MAX_SITE_SPAN_M, "maximum_zone_length_m": MAX_ZONE_LENGTH_M, "maximum_zone_width_m": MAX_ZONE_WIDTH_M, "maximum_roof_height_m": MAX_ROOF_HEIGHT_M, "validated_before_integer_conversion_or_construction": true}
	assumptions.append({"field": "continuous_roof_and_linking_walls", "status": "HISTORICAL_FORM_WITH_STAGED_EXACT_PROFILE", "east_upper_wall_inset_ratio": inset, "why": "Arup shows vertical west and inclined east linking walls/trussed roofs. Exact current section heights, inset, truss spacing and structural connections are not surveyed here. Historic 47m/27m wall spans are not relabeled as roof elevations."})
	assumptions.append({"field": "entrance_and_floor_elevation", "status": "UNVERIFIED_STAGING_OPENING", "floor_elevation_m": elevation, "why": "No current surveyed hotel entrance/elevation was established."})
	var furniture_plan: Dictionary = _planned_furniture(new_sections, new_zones, inset)
	if not furniture_plan.get("valid", false): return furniture_plan
	var connections: Dictionary=_planned_connections(config,new_sections,new_zones,furniture_plan.items,inset,elevation,door_width,door_height,entry_x)
	if not connections.get("valid",false): return connections
	if (not connections.core_connections.is_empty() or not connections.arrival_corridor.is_empty()) and not config.has("source_frame"): return {"valid":false,"error":"Integrated public/core/arrival openings require the actual common source frame."}
	var adapter_budget: float=64.0*connections.core_connections.size()+(64.0 if not connections.arrival_corridor.is_empty() else 0.0)
	if member_budget+adapter_budget>MAX_STRUCTURAL_MEMBER_BUDGET: return {"valid":false,"error":"Connection adapters exceed bounded member budget."}
	construction_budget.estimated_member_upper_bound=member_budget+adapter_budget
	var origin: Array = Reference.DATA.origin_world_xz
	var south_axis: Array = Reference.DATA.axis_south_xz
	var bay: Array = Reference.DATA.axis_bayward_xz
	var canonical: Array = [float(origin[0]), elevation, float(origin[1])]
	var placement: Vector3
	var coordinate_context: Dictionary = {}
	if config.has("source_frame"):
		var frame: Variant = config.source_frame
		if not frame is SourceFrame: return {"valid": false, "error": "Require an actual configured source frame."}
		# Subtract the canonical active origin in doubles before making an
		# engine vector. This is source-world placement, not fixture translation.
		var projected: Dictionary = frame.to_local(canonical)
		if not projected.ok: return {"valid": false, "error": projected.get("error", "Source placement failed")}
		placement = projected.position
		coordinate_context = {"canonical_origin_xyz": canonical, "frame": frame.metadata(), "origin_subtracted_before_vector": true}
	else:
		placement = Vector3(float(origin[0]), elevation, float(origin[1]))
	var result := {"valid": true, "construction_budget": construction_budget, "furniture": furniture_plan.items, "zones": new_zones, "sections": new_sections, "assumptions": assumptions, "position": placement, "basis": Basis(Vector3(float(south_axis[0]), 0, float(south_axis[1])), Vector3.UP, Vector3(float(bay[0]), 0, float(bay[1]))), "entrance_tower": String(config.get("entrance_tower", "T1")), "entrance_offset": offset, "entrance_sign": -1.0 if config.get("entrance_side", "bayward") == "landward" else 1.0, "entrance_x": entry_x, "door_width": door_width, "door_height": door_height, "east_inset_ratio": inset}
	result["core_connections"]=connections.core_connections
	result["arrival_corridor"]=connections.arrival_corridor
	if not coordinate_context.is_empty(): result["coordinate_context"] = coordinate_context
	return result

func _edge(section: Dictionary, side: float, y: float = 0.0) -> Vector3:
	var p: Vector3 = section.center
	p.y = y
	p.z += side * float(section.width_m) * 0.5
	# Bayward/west side vertical; landward/east profile slopes inward.
	if side < 0.0: p.z += float(section.width_m) * _east_inset_ratio * y / float(section.height_m)
	return p

func _section_at(x: float) -> Dictionary:
	return _sample_sections(sections, x)

func _sample_sections(profile: Array[Dictionary], x: float) -> Dictionary:
	for i in profile.size() - 1:
		var a: Dictionary = profile[i]
		var b: Dictionary = profile[i + 1]
		if x <= float((b.center as Vector3).x) + 0.0001:
			var u := clampf((x - float((a.center as Vector3).x)) / float((b.center as Vector3).x - (a.center as Vector3).x), 0.0, 1.0)
			return {"center": (a.center as Vector3).lerp(b.center, u), "width_m": lerpf(a.width_m, b.width_m, u), "height_m": lerpf(a.height_m, b.height_m, u)}
	return profile[-1].duplicate(true)

func _build_continuous_envelope(kit, glass) -> void:
	for i in sections.size() - 1:
		var a: Dictionary = sections[i]
		var b: Dictionary = sections[i + 1]
		var a0 := _edge(a, -1.0)
		var a1 := _edge(a, 1.0)
		var b0 := _edge(b, -1.0)
		var b1 := _edge(b, 1.0)
		_floor_prism(kit, a0, b0, b1, a1)
		for side: float in [-1.0, 1.0]:
			_build_side(kit, glass, a, b, side)
		var ra := _edge(a, -1.0, a.height_m)
		var rb := _edge(a, 1.0, a.height_m)
		var rc := _edge(b, 1.0, b.height_m)
		var rd := _edge(b, -1.0, b.height_m)
		# A continuous planar/sloping envelope, not three greenhouse vaults.
		var roof_material: Material = Looks.get_mat("glass_canopy") if i in [1, 2] else Looks.get_mat("soffit")
		glass.quad(roof_material, ra, rb, rc, rd)
		if i not in [1, 2]: glass.quad(roof_material, rd, rc, rb, ra)
		_collision_quad(kit, ra, rb, rc, rd)
		_truss_roof(kit, a, b)
	for section: Dictionary in [sections[0], sections[-1]]:
		var p0 := _edge(section, -1.0)
		var p1 := _edge(section, 1.0)
		var p2 := _edge(section, 1.0, section.height_m)
		var p3 := _edge(section, -1.0, section.height_m)
		glass.quad(Looks.get_mat("glass_clear"), p0, p1, p2, p3)
		_collision_quad(kit, p0, p1, p2, p3)
		kit.beam(Looks.get_mat("steel_white"), p3, p2, 0.25, 0.30)

func _floor_prism(kit, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	kit.quad(_floor_material, a, d, c, b)
	var down := Vector3.DOWN * FLOOR_THICKNESS
	for pair: Array in [[a, b], [b, c], [c, d], [d, a]]:
		kit.quad(_floor_material, pair[0], pair[1], pair[1] + down, pair[0] + down)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a, b, c, d, a + down, b + down, c + down, d + down])
	var node := CollisionShape3D.new()
	node.shape = shape
	kit.body.add_child(node)
	kit.shapes += 1

func _collision_quad(kit, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	kit.col_trimesh(PackedVector3Array([a, b, c, a, c, d]))

func _build_side(kit, glass, a: Dictionary, b: Dictionary, side: float) -> void:
	var cuts: Array[float] = [0.0, 1.0]
	var ax: float = (a.center as Vector3).x
	var bx: float = (b.center as Vector3).x
	if side == _entrance_sign:
		for x: float in [_entrance_x - _door_width * 0.5, _entrance_x + _door_width * 0.5]:
			if x > ax and x < bx: cuts.append((x - ax) / (bx - ax))
	for connection: Dictionary in core_connections:
		if float(connection.side_sign)!=side: continue
		for x: float in [float(connection.center_x)-float(connection.width_m)*.5,float(connection.center_x)+float(connection.width_m)*.5]:
			if x>ax and x<bx: cuts.append((x-ax)/(bx-ax))
	cuts.sort()
	for j in cuts.size() - 1:
		var u0: float = cuts[j]
		var u1: float = cuts[j + 1]
		var lo := _section_at(lerpf(ax, bx, u0))
		var hi := _section_at(lerpf(ax, bx, u1))
		var mid_x := lerpf(ax, bx, (u0 + u1) * 0.5)
		var bottom: float = _opening_height(side,mid_x)
		_wall_patch(kit, glass, lo, hi, side, bottom)
	# Side steelwork is staged RHS-like trusses/transoms, not room floors.
	var divisions := maxi(1, int(ceil((bx - ax) / 5.0)))
	for k in divisions + 1:
		var x := lerpf(ax, bx, float(k) / divisions)
		if _opening_near(side,x,.15): continue
		var section := _section_at(x)
		var p0 := _edge(section, side)
		var top := _edge(section, side, section.height_m)
		kit.beam(Looks.get_mat("steel_white"), p0, top, 0.18, 0.22)
		if k < divisions:
			var next := _section_at(lerpf(ax, bx, float(k + 1) / divisions))
			for y: float in [5.0, 13.0, 21.0, 29.0, 37.0, 45.0, 53.0, 61.0, 69.0]:
				if y >= minf(section.height_m, next.height_m) - 0.5: continue
				var p := _edge(section, side, y)
				var q := _edge(next, side, y)
				kit.beam(Looks.get_mat("steel_bronze"), p, q, 0.12, 0.12)
				kit.beam(Looks.get_mat("steel_white"), p, _edge(next, side, minf(y + 8.0, next.height_m)), 0.10, 0.12)

func _wall_patch(kit, glass, a: Dictionary, b: Dictionary, side: float, bottom: float) -> void:
	var p0 := _edge(a, side, bottom)
	var p1 := _edge(b, side, bottom)
	var p2 := _edge(b, side, b.height_m)
	var p3 := _edge(a, side, a.height_m)
	glass.quad(Looks.get_mat("glass_clear"), p0, p1, p2, p3)
	_collision_quad(kit, p0, p1, p2, p3)
	if bottom < 0.1:
		# Low plinth sits on the exact same edge as the side glazing. Ends are
		# shared vertices at joins, so no staggered connector endpoint exists.
		var delta := Vector3.UP * 0.15
		kit.beam(Looks.get_mat("granite_dark"), p0 + delta, p1 + delta, 0.20, 0.30)

func _truss_roof(kit, a: Dictionary, b: Dictionary) -> void:
	var spans := maxi(1, int(ceil((b.center as Vector3).distance_to(a.center) / 7.0)))
	for i in spans + 1:
		var section := _section_at(lerpf((a.center as Vector3).x, (b.center as Vector3).x, float(i) / spans))
		var p := _edge(section, -1.0, section.height_m)
		var q := _edge(section, 1.0, section.height_m)
		kit.beam(Looks.get_mat("steel_white"), p, q, 0.22, 0.30)
		kit.beam(Looks.get_mat("steel_white"), p - Vector3.UP * 1.0, q - Vector3.UP * 1.0, 0.12, 0.18)
		for j in 5:
			var t0 := float(j) / 5.0
			var t1 := float(j + 1) / 5.0
			kit.beam(Looks.get_mat("steel_white"), p.lerp(q, t0), p.lerp(q, t1) - Vector3.UP * 1.0, 0.10, 0.12)

func _build_approach(kit, glass) -> void:
	var section := _section_at(_entrance_x)
	var at := _edge(section, _entrance_sign)
	portal_local = {"hotel_entrance": at, "outside": at + Vector3(0, 0, _entrance_sign * 6.0), "inside": at - Vector3(0, 0, _entrance_sign * 3.0)}
	var center := at + Vector3(0, -FLOOR_THICKNESS * 0.5, _entrance_sign * 4.0)
	kit.box(_floor_material, center, Vector3(_door_width + 3.0, FLOOR_THICKNESS, 8.0), Basis.IDENTITY, false)
	kit.col_box(Vector3(_door_width + 3.0, FLOOR_THICKNESS, 8.0), center)
	var frame := Looks.get_mat("steel_satin")
	var bronze := Looks.get_mat("steel_bronze")
	# A flush, visually distinct sill, with no raised lip across the real opening.
	kit.box(Looks.get_mat("granite_dark"), at + Vector3(0, 0.004, 0), Vector3(_door_width, 0.008, 0.22))
	for side: float in [-1.0, 1.0]:
		# Keep the complete configured opening clear. Park the glazed leaves at
		# ninety degrees OUTSIDE its edges, rather than sealing a tested doorway.
		var leaf_x := side * (_door_width * 0.5 + 0.12)
		var hinge := at + Vector3(leaf_x, 0, 0)
		# In a reconstructed arrival corridor, park leaves into the tall loft
		# rather than blocking the perimeter corridor's parallel through-route.
		var tip := hinge + Vector3(0, 0, _entrance_sign * (-1.10 if not arrival_corridor.is_empty() else 1.10))
		var leaf_h := minf(3.40, _door_height - 0.24)
		kit.box(frame, at + Vector3(side * (_door_width * 0.5 + 0.08), _door_height * 0.5, 0), Vector3(0.12, _door_height, 0.16))
		glass.quad(Looks.get_mat("glass_clear"), hinge + Vector3.UP * 0.10, tip + Vector3.UP * 0.10, tip + Vector3.UP * leaf_h, hinge + Vector3.UP * leaf_h)
		for y: float in [0.08, leaf_h]:
			kit.beam(frame, hinge + Vector3.UP * y, tip + Vector3.UP * y, 0.045, 0.055)
		for base: Vector3 in [hinge, tip]:
			kit.beam(frame, base + Vector3.UP * 0.08, base + Vector3.UP * leaf_h, 0.045, 0.045)
		var handle := hinge.lerp(tip, 0.78) + Vector3(-side * 0.075, 0, 0)
		kit.beam(bronze, handle + Vector3.UP * 0.92, handle + Vector3.UP * 1.58, 0.035, 0.035)
		for y: float in [0.96, 1.54]:
			kit.beam(bronze, handle + Vector3.UP * y, handle + Vector3(side * 0.075, y, 0), 0.025, 0.025)
		# Full solid parked-leaf volume, outside the 4 m clear route.
		kit.col_box(Vector3(0.05, leaf_h, 1.10), hinge.lerp(tip, 0.5) + Vector3.UP * leaf_h * 0.5)
		var leaf_collision: CollisionShape3D = kit.body.get_child(kit.body.get_child_count() - 1)
		leaf_collision.name = "ParkedGlazedDoorLeaf" + ("Left" if side < 0 else "Right")
	kit.box(frame, at + Vector3.UP * _door_height, Vector3(_door_width + 0.28, 0.18, 0.20))
	kit.box(bronze, at + Vector3(0, _door_height - 0.12, 0), Vector3(_door_width + 0.08, 0.035, 0.12))
	var portal := Node3D.new()
	portal.name = "PhysicalHotelEntranceStage"
	portal.position = at
	portal.set_meta("source_status", "UNVERIFIED_STAGING_OPENING")
	add_child(portal)
	portal.add_to_group("mbs_interior_portals")
	_sign(at + Vector3(-_door_width * 0.5 - 1.65, 2.30, _entrance_sign * 0.12), "HOTEL LOBBY\nTOWERS 1 / 2 / 3", PI if _entrance_sign < 0 else 0.0, 3.0)
	_assumptions.append({"field": "entrance_door_articulation", "status": "ORIGINAL_GENERIC_OPEN_GLAZED_LEAVES_NOT_SURVEYED_DOOR_DESIGN", "clear_opening_m": _door_width, "why": "Detail is confined to opening edges/overhead sign; both parked leaves have solid collision and the flush sill adds no physical step."})

func _planned_furniture(profile: Array[Dictionary], anchors: Array[Dictionary], inset: float) -> Dictionary:
	var items: Array[Dictionary] = []
	for zone: Dictionary in anchors:
		var c: Vector3 = zone.center
		var length_m: float = zone.length_m
		for side: float in [-1.0, 1.0]:
			for index in 2:
				var x: float = c.x + length_m * (-0.25 if index == 0 else 0.25)
				var id: String = String(zone.tower) + ("_east_" if side < 0 else "_west_") + str(index)
				var bench := _planned_lounge_item(profile, x, side, Vector3(2.0, 0.5, 0.5), "bench", String(zone.tower), id + "_bench", inset)
				if not bench.get("valid", false): return bench
				items.append(bench.item)
				var planter := _planned_lounge_item(profile, x + 2.8, side, Vector3(1.8, TREE_VESSEL_HEIGHT_M, 1.8), "planter", String(zone.tower), id + "_planter", inset)
				if not planter.get("valid", false): return planter
				items.append(planter.item)
		if zone.tower == "T1":
			# Reception has its own lounge bay, not the same X/Z as a bench.
			var counter := _planned_lounge_item(profile, c.x + length_m * 0.05, -1.0, Vector3(5.2, 1.24, 1.3), "reception", "T1", "T1_reception", inset)
			if not counter.get("valid", false): return counter
			items.append(counter.item)
	return {"valid": true, "items": items}

func _planned_lounge_item(profile: Array[Dictionary], x: float, side: float, size: Vector3, kind: String, tower: String, id: String, inset: float) -> Dictionary:
	var half_x := size.x * 0.5
	var half_z := size.z * 0.5
	if x - half_x < float((profile[0].center as Vector3).x) + FURNITURE_WALL_BUFFER_M or x + half_x > float((profile[-1].center as Vector3).x) - FURNITURE_WALL_BUFFER_M:
		return {"valid": false, "error": "Furniture footprint exceeds supported public envelope: " + id}
	# A bent/tapered atrium needs each whole furniture footprint checked against
	# its LOCAL centreline and side walls, rather than a fixed tower-anchor Z.
	var samples: Array[float] = [x - half_x, x, x + half_x]
	for profile_anchor: Dictionary in profile:
		var sx: float = (profile_anchor.center as Vector3).x
		if sx > x - half_x and sx < x + half_x: samples.append(sx)
	var min_center := INF
	var max_center := -INF
	var east_limit := -INF
	var west_limit := INF
	for at: float in samples:
		var sample := _sample_sections(profile, at)
		var sample_z: float = (sample.center as Vector3).z
		min_center = minf(min_center, sample_z)
		max_center = maxf(max_center, sample_z)
		# Include the inclined east wall at the item's top, not only its base.
		var east_top: float = sample_z - float(sample.width_m) * 0.5 + float(sample.width_m) * inset * size.y / float(sample.height_m)
		east_limit = maxf(east_limit, east_top)
		west_limit = minf(west_limit, sample_z + float(sample.width_m) * 0.5)
	var section := _sample_sections(profile, x)
	var center_z: float = (section.center as Vector3).z
	var preferred: float = center_z + side * float(section.width_m) * 0.31
	var z: float
	var aisle_clearance: float
	var wall_clearance: float
	if side > 0:
		z = maxf(preferred, max_center + PUBLIC_AISLE_WIDTH_M * 0.5 + AISLE_FURNITURE_BUFFER_M + half_z)
		aisle_clearance = z - half_z - max_center
		wall_clearance = west_limit - z - half_z
	else:
		z = minf(preferred, min_center - PUBLIC_AISLE_WIDTH_M * 0.5 - AISLE_FURNITURE_BUFFER_M - half_z)
		aisle_clearance = min_center - z - half_z
		wall_clearance = z - half_z - east_limit
	if wall_clearance < FURNITURE_WALL_BUFFER_M:
		return {"valid": false, "error": "Furniture cannot preserve central public aisle and wall clearance: " + id}
	return {"valid": true, "item": {"id": id, "tower": tower, "kind": kind, "position": Vector3(x, 0, z), "size": size, "minimum_centerline_to_inner_edge_m": aisle_clearance, "minimum_wall_clearance_m": wall_clearance, "status": "STAGED_LOUNGE_LAYOUT_NOT_CURRENT_AS_BUILT_FITOUT"}}

func _furnish(kit, zone: Dictionary) -> void:
	var transforms: Array = []
	var trees: Array = []
	var upholstery := Palette.mat(Color(0.32, 0.34, 0.30), 0.91)
	for item: Dictionary in furniture:
		if item.tower != zone.tower: continue
		var p: Vector3 = item.position
		var size: Vector3 = item.size
		match String(item.kind):
			"bench":
				transforms.append(Kit.xf(p))
				# Reuse the existing original bench; the quiet seat pads stay inside
				# its complete 2 x .5 x .5 m physical envelope.
				for x: float in [-0.48, 0.48]:
					kit.box(upholstery, p + Vector3(x, 0.480, 0), Vector3(0.92, 0.035, 0.46))
			"planter": _tree_vessel(kit, item, trees)
			"reception": _reception(kit, p)
		# Keep complete matching physical collision; nothing is hidden/disabled.
		kit.col_box(size, p + Vector3.UP * size.y * 0.5)
		var shape: CollisionShape3D = kit.body.get_child(kit.body.get_child_count() - 1)
		shape.name = String(item.id)
		shape.set_meta("furnishing_id", item.id)
	var c: Vector3 = zone.center
	var width_m: float = zone.width_m
	for side: float in [-1.0, 1.0]:
		var light := OmniLight3D.new()
		light.position = c + Vector3(0, minf(float(zone.wall_height_m) - 1.0, 7.0), side * width_m * 0.22)
		light.light_color = Color(1.0, 0.96, 0.87)
		light.light_energy = 0.85
		light.omni_range = maxf(width_m, 15.0)
		light.shadow_enabled = false
		add_child(light)
	Realm.benches(self, "Atrium" + String(zone.tower) + "Benches", transforms)
	Canopy.emit(self, trees, "Atrium" + String(zone.tower) + "OriginalTrees", 350.0)
	_assumptions.append({"field": String(zone.id) + ".loose_furniture_and_lights", "status": "STAGING_ASSUMPTION", "reserved_public_aisle_width_m": PUBLIC_AISLE_WIDTH_M, "why": "The same 25 original furniture items follow the sampled continuous-envelope centreline/width with full solid collision. Generic tall tree vessels respond to the historical planted composition; exact artwork/placement and current fit-out are not reproduced or verified."})

func _tree_vessel(kit, item: Dictionary, trees: Array) -> void:
	var p: Vector3 = item.position
	var h: float = (item.size as Vector3).y
	var stone := Palette.mat(Color(0.52, 0.51, 0.46), 0.76)
	var rim := Looks.get_mat("steel_bronze")
	# Generic unornamented vessel: original Kit frustums, without the distinctive
	# artist's surface/pattern or a traced artwork mesh. The full 1.8 m square
	# bounding volume remains collidable rather than permitting clipped corners.
	kit.cyl(stone, p, 0.54, 0.82, h - 0.08, 24, false)
	kit.cyl(rim, p + Vector3.UP * (h - 0.08), 0.82, 0.84, 0.08, 24, false)
	kit.cyl(Looks.get_mat("soil_bed"), p + Vector3.UP * (h - 0.045), 0.76, 0.76, 0.012, 24)
	kit.cyl(Looks.get_mat("granite_dark"), p + Vector3.UP * 0.025, 0.55, 0.55, 0.05, 24)
	var target_width := 2.1 if item.tower == "T3" else (3.8 if item.tower == "T2" else 4.8)
	var target_height := 4.5 if item.tower == "T3" else (5.6 if item.tower == "T2" else 6.2)
	var top := h - 0.04 + target_height
	var east := -INF
	var west := INF
	# The leaves may overhang their vessel above 3 m, but may not intersect the
	# inclined glazed wall. Sample the full proposed X footprint as for furniture.
	var samples: Array[float] = [p.x - target_width * 0.5, p.x, p.x + target_width * 0.5]
	for section: Dictionary in sections:
		var x: float = (section.center as Vector3).x
		if x > samples[0] and x < samples[2]: samples.append(x)
	for x: float in samples:
		var section := _section_at(x)
		east = maxf(east, _edge(section, -1.0, top).z)
		west = minf(west, _edge(section, 1.0, top).z)
	var cap_clear := minf(p.x - (sections[0].center as Vector3).x, (sections[-1].center as Vector3).x - p.x) - 0.25
	var width := minf(target_width, minf(minf(p.z - east, west - p.z) - 0.18, cap_clear) * 2.0)
	# Existing original downtown mesh/material, normalized by its real mesh AABB.
	# No new third-party download, provider asset, sculpture copy or tree motion.
	var mesh := Canopy.mesh("tembusu")
	var bounds := mesh.get_aabb()
	# Scale about the source trunk at X/Z zero, not the asymmetric crown centre.
	# Using twice each maximum extent bounds every vertex while keeping the
	# physical stem and the visible trunk centred in the same vessel.
	var extent_x := maxf(absf(bounds.position.x), absf(bounds.end.x))
	var extent_z := maxf(absf(bounds.position.z), absf(bounds.end.z))
	var tree_scale := Vector3(width * 0.5 / extent_x, target_height / bounds.size.y, width * 0.5 / extent_z)
	var tree_basis := Basis.IDENTITY.scaled(tree_scale)
	var source_base := Vector3(0, bounds.position.y, 0)
	var tree_xf := Transform3D(tree_basis, p + Vector3.UP * (h - 0.04) - tree_basis * source_base)
	trees.append(["tembusu", tree_xf, Color(1.03, 1.08, 0.96, 0.0)])
	# Solid central stem above the solid vessel; wholly inside its existing
	# footprint, so it cannot introduce a new obstruction in the public spine.
	var species: Dictionary = Canopy.SPECIES.tembusu
	var stem_height: float = (float(species.trunk) + float(species.hh) * 0.30) * tree_scale.y - 0.04
	var stem_radius: float = 0.32 * float(species.r) / 5.0 + 0.12
	kit.col_box(Vector3(stem_radius * 2.0 * tree_scale.x, stem_height, stem_radius * 2.0 * tree_scale.z), p + Vector3.UP * (h + stem_height * 0.5))
	var stem: CollisionShape3D = kit.body.get_child(kit.body.get_child_count() - 1)
	stem.name = String(item.id) + "_TreeStem"
	stem.set_meta("furnishing_id", String(item.id) + "_TreeStem")
	_tree_layout.append({"furnishing_id": item.id, "vessel_height_m": h, "tree_height_above_vessel_m": target_height, "tree_width_m": width, "tree_top_m": top, "minimum_overhead_wall_clearance_m": minf(p.z - width * 0.5 - east, west - p.z - width * 0.5), "tree_source": "ORIGINAL_PROJECT_DOWNTOWN_TEMBUSU_MESH", "artwork_replica": false})

func _reception(kit, p: Vector3) -> void:
	var stone := Palette.mat(Color(0.73, 0.73, 0.67), 0.62)
	var timber := Looks.get_mat("timber")
	var bronze := Looks.get_mat("steel_bronze")
	var dark := Looks.get_mat("signage")
	# Layered original counter within the same 5.2 x 1.24 x 1.3 m full collider.
	kit.box(dark, p + Vector3.UP * 0.075, Vector3(5.0, 0.15, 1.12))
	kit.box(stone, p + Vector3.UP * 0.63, Vector3(5.0, 0.96, 1.10))
	for x: float in [-1.65, 0.0, 1.65]:
		kit.box(timber, p + Vector3(x, 0.63, 0.558), Vector3(1.56, 0.82, 0.035))
		kit.box(bronze, p + Vector3(x - 0.79, 0.63, 0.584), Vector3(0.018, 0.82, 0.020))
	kit.box(stone, p + Vector3.UP * 1.18, Vector3(5.2, 0.12, 1.3))
	kit.box(bronze, p + Vector3(0, 1.095, 0.60), Vector3(5.10, 0.025, 0.025))
	for x: float in [-1.40, 1.40]:
		kit.box(dark, p + Vector3(x, 1.27, -0.23), Vector3(0.18, 0.06, 0.18))
		kit.box(dark, p + Vector3(x, 1.43, -0.24), Vector3(0.48, 0.28, 0.045))
	_sign(p + Vector3(0, 1.88, -0.61), "RECEPTION\nHOTEL ASSISTANCE", 0.0, 2.8)

func _sign(at: Vector3, title: String, yaw: float, width: float = 3.2) -> void:
	var frame := Node3D.new()
	frame.name = "AtriumWayfinding"
	frame.position = at
	frame.rotation.y = yaw
	frame.set_meta("design_status", "ORIGINAL_GENERIC_WAYFINDING_NOT_VERIFIED_OPERATOR_SIGNAGE")
	add_child(frame)
	var backing := MeshInstance3D.new()
	var panel := BoxMesh.new()
	panel.size = Vector3(width, 0.74, 0.055)
	backing.mesh = panel
	backing.material_override = Palette.mat(Color(0.075, 0.085, 0.080), 0.82)
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame.add_child(backing)
	var label := Label3D.new()
	label.text = title
	label.font_size = 60
	label.pixel_size = 0.0040
	label.outline_size = 2
	label.modulate = Color(0.94, 0.95, 0.88)
	label.position.z = 0.040
	frame.add_child(label)

func _build_path() -> void:
	var entry_index := 0
	for i in zones.size():
		if zones[i].tower == _entrance_tower: entry_index = i
	if arrival_corridor.is_empty(): public_path_local = [portal_local.outside, portal_local.inside, zones[entry_index].center]
	else: public_path_local.assign(arrival_corridor.local_route)
	for i in range(entry_index + 1, zones.size()): public_path_local.append(zones[i].center)
	for i in range(zones.size() - 2, -1, -1): public_path_local.append(zones[i].center)

func walking_route_world(include_return: bool = false) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point: Vector3 in public_path_local: result.append(to_global(point))
	if include_return:
		for i in range(public_path_local.size() - 2, -1, -1): result.append(to_global(public_path_local[i]))
	return result

func doorway_world() -> Dictionary:
	if not _built: return {}
	var result: Dictionary={"center": to_global(portal_local.hotel_entrance), "outside": to_global(portal_local.outside), "inside": to_global(portal_local.inside), "normal": global_basis.z * _entrance_sign, "metric_verified": false}
	if portal_local.has("actual_outer_facade"):
		result["actual_outer_facade"]=to_global(portal_local.actual_outer_facade)
		result["external_arrival"]=to_global(portal_local.external_arrival)
	return result

func join_probes_local(inset: float = 0.75) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _built: return result
	for i in range(1, sections.size() - 1):
		var section: Dictionary = sections[i]
		var x: float = (section.center as Vector3).x
		for side: float in [-1.0, 1.0]:
			var a := _edge(_section_at(x - 1.25), side)
			var b := _edge(_section_at(x + 1.25), side)
			var center := _edge(section, side)
			var toward := Vector3(0, 0, -side)
			var intentional_door: bool = side == _entrance_sign and absf(x - _entrance_x) < _door_width * 0.5 + 0.5
			var opening_width: float=_door_width
			for connection: Dictionary in core_connections:
				if float(connection.side_sign)==side and absf(x-float(connection.center_x))<float(connection.width_m)*.5+.5:
					intentional_door=true;opening_width=connection.width_m
			var escape_pairs: Array[Dictionary] = []
			var offsets: Array[float] = [-0.35, 0.0, 0.35]
			if intentional_door: offsets = [-opening_width * 0.5 - 1.0, opening_width * 0.5 + 1.0]
			for offset: float in offsets:
				var at := _edge(_section_at(x + offset), side)
				escape_pairs.append({"inside": at + toward * inset, "outside": at - toward, "x_offset": offset})
			result.append({"join": section.tower, "side": side, "edge": center, "normal_in": toward, "walk_a": a + toward * inset, "walk_b": b + toward * inset, "intentional_doorway": intentional_door, "escape_pairs": escape_pairs, "same_shared_edge_vertices": true})
	return result

func report() -> Dictionary:
	var result := _report.duplicate(true)
	result["source_placement_preserved"] = global_position.is_equal_approx(_source_position) and global_basis.is_equal_approx(_source_basis)
	result["metres_per_unit_preserved"] = global_basis.get_scale().is_equal_approx(Vector3.ONE)
	result["integration_requirements"] = ["Replace old solid MBS tower/podium collision with actual hollow floor/wall shells; do not insert this into solids.", "Migrate the entire complex into the uncompressed geography frame including Bayfront Avenue and separated retail; do not leave duplicate legacy MBS in its fictional frame.", "This is L1 stage only: current exact metric plans/elevations/doors and all room/service/upper/retail inventories remain incomplete.", "Expand source-world player/aircraft/save bounds consistently before traversing the full real site.", "Render against actual MBS reference photos and measure integrated source boundaries; standalone tests are not whole-world/fidelity acceptance."]
	return result

static func default_core_connection_requests(elevation_m: float = 0.0) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for tower: String in ["T1","T2","T3"]:
		result.append({"tower":tower,"side":"east","along_offset_m":-3.0 if tower=="T1" else 0.0,"width_m":2.0,"height_m":2.45,"corridor_width_m":2.6,"target_floor_elevation_m":elevation_m})
	return result

static func default_arrival_request(elevation_m: float = 0.0) -> Dictionary:
	return {"tower":"T1","side":"west","along_offset_m":0.0,"width_m":2.6,"height_m":2.7,"corridor_width_m":2.6,"target_cross_m":61.40207,"target_floor_elevation_m":elevation_m,"outside_approach_m":4.5}

static func _connection_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

static func validate_connection_request(request: Variant,arrival: bool = false) -> bool:
	if not request is Dictionary: return false
	var keys: Array=["tower","side","along_offset_m","width_m","height_m","corridor_width_m","target_floor_elevation_m"]
	if arrival: keys.append_array(["target_cross_m","outside_approach_m"])
	if request.size()!=keys.size(): return false
	for key: String in keys:
		if not request.has(key): return false
	if not request.tower is String or not request.tower in ["T1","T2","T3"] or not request.side is String or not request.side in ["east","west"]: return false
	for key: String in keys:
		if key in ["tower","side"]: continue
		if not _connection_number(request[key]): return false
	if absf(float(request.along_offset_m))>10 or float(request.width_m)<2.0 or float(request.width_m)>3.0 or float(request.height_m)<2.2 or float(request.height_m)>3.0 or float(request.corridor_width_m)<2.6 or float(request.corridor_width_m)>4.0 or absf(float(request.target_floor_elevation_m))>MAX_ABS_FLOOR_ELEVATION_M: return false
	if arrival and (request.tower!="T1" or request.side!="west" or absf(float(request.along_offset_m))>.0001 or float(request.width_m)<2.4 or float(request.height_m)<2.5 or float(request.target_cross_m)<45 or float(request.target_cross_m)>90 or float(request.outside_approach_m)<2.0 or float(request.outside_approach_m)>7.0): return false
	return true

func _planning_edge(section: Dictionary,side: float,y: float,inset: float) -> Vector3:
	var p: Vector3=section.center;p.y=y
	p.z+=side*float(section.width_m)*.5
	if side<0: p.z+=float(section.width_m)*inset*y/float(section.height_m)
	return p

func _connection_source(tower_id: String,delta: Array,elevation: float) -> Array:
	for source: Dictionary in Reference.DATA.towers:
		if source.tower!=tower_id: continue
		var anchor: Array=source.centroid_world_xz
		var x: Array=Reference.DATA.axis_south_xz;var z: Array=Reference.DATA.axis_bayward_xz
		return [float(anchor[0])+float(x[0])*float(delta[0])+float(z[0])*float(delta[2]),elevation+float(delta[1]),float(anchor[1])+float(x[1])*float(delta[0])+float(z[1])*float(delta[2])]
	return []

func _connection_volume(tower: String,id: String,zone: Dictionary,start: Vector3,end: Vector3,width: float,elevation: float) -> Dictionary:
	# Geometry is local and bounded; canonical centres use the original DOUBLE
	# source tower anchor before any engine vector/global transform conversion.
	var center: Vector3=(start+end)*.5
	var lo: float=minf(start.y,end.y)-.30
	var hi: float=maxf(start.y,end.y)+2.60
	return {"schema":"singapore_upright_obox_v1","volume_id":id+"-adapter-dry","center_xyz":_connection_source(tower,[float(center.x-(zone.center as Vector3).x),(lo+hi)*.5,float(center.z-(zone.center as Vector3).z)],elevation),"half_extents_xyz":[width*.5,(hi-lo)*.5,absf(end.z-start.z)*.5],"axis_x_xyz":[Reference.DATA.axis_south_xz[0],0.0,Reference.DATA.axis_south_xz[1]],"axis_z_xyz":[Reference.DATA.axis_bayward_xz[0],0.0,Reference.DATA.axis_bayward_xz[1]],"dry":true}

func _planned_connections(config: Dictionary,profile: Array[Dictionary],anchors: Array[Dictionary],items: Array,inset: float,elevation: float,entry_width: float,entry_height: float,entry_x: float) -> Dictionary:
	var requests: Variant=config.get("core_connections",[])
	if not requests is Array or requests.size()>6: return {"valid":false,"error":"Core connections require a bounded explicit array."}
	var result: Array[Dictionary]=[];var seen: Dictionary={}
	for request: Variant in requests:
		if not validate_connection_request(request,false): return {"valid":false,"error":"Incomplete/nonfinite core aperture request."}
		var zone: Dictionary={}
		for anchor: Dictionary in anchors:
			if anchor.tower==request.tower: zone=anchor;break
		var side: float=-1.0 if request.side=="east" else 1.0
		var id: String=String(request.tower)+"-L1-"+String(request.side)+"-core"
		if seen.has(id): return {"valid":false,"error":"Duplicate core aperture."}
		seen[id]=true
		var x: float=(zone.center as Vector3).x+float(request.along_offset_m)
		var width: float=request.width_m;var height: float=request.height_m
		var delta: float=float(request.target_floor_elevation_m)-elevation
		if absf(delta)>.20 or height-maxf(0,delta)<2.2 or absf(float(request.along_offset_m))+width*.5+.25>float(zone.length_m)*.5: return {"valid":false,"error":"Unsupported core height/footprint join."}
		var entrance_side: float=-1.0 if config.get("entrance_side","bayward")=="landward" else 1.0
		if side==entrance_side and absf(x-entry_x)<(width+entry_width)*.5+.30: return {"valid":false,"error":"Core aperture overlaps the public entrance."}
		var sample:=_sample_sections(profile,x)
		var wall:=_planning_edge(sample,side,0,inset)
		var inward_edge: float=wall.z
		for at: float in [x-width*.5,x+width*.5]:
			var edge:=_planning_edge(_sample_sections(profile,at),side,0,inset)
			inward_edge=maxf(inward_edge,edge.z) if side<0 else minf(inward_edge,edge.z)
		var target_edge: float=(zone.center as Vector3).z+side*float(zone.width_m)*.5
		var start:=Vector3(x,.004,inward_edge-side*1.50)
		var end:=Vector3(x,delta+.004,target_edge+side*(float(request.corridor_width_m)*.5+.45))
		var corridor:=Vector3(x,delta,target_edge+side*float(request.corridor_width_m)*.5)
		var low_z:=minf((sample.center as Vector3).z,end.z)
		var high_z:=maxf((sample.center as Vector3).z,end.z)
		for item: Dictionary in items:
			var p: Vector3=item.position;var size: Vector3=item.size
			if absf(p.x-x)<size.x*.5+width*.5+.45 and p.z+size.z*.5>low_z and p.z-size.z*.5<high_z: return {"valid":false,"error":"Core approach intersects retained public furnishing: "+String(item.id)}
		var data: Dictionary={"id":id,"tower":request.tower,"side":request.side,"side_sign":side,"target_floor_id":String(request.tower)+"-L1","center_x":x,"along_offset_m":request.along_offset_m,"width_m":width,"height_m":height,"corridor_width_m":request.corridor_width_m,"floor_delta_m":delta,"glass_threshold_local":wall,"adapter_start_local":start,"adapter_end_local":end,"target_corridor_local":corridor,"local_route":[sample.center,start,Vector3(x,.004,wall.z),corridor],"target_source_xyz":_connection_source(request.tower,[float(request.along_offset_m),0,side*(float(zone.width_m)*.5+float(request.corridor_width_m)*.5)],float(request.target_floor_elevation_m)),"source_dry_volumes":[_connection_volume(request.tower,id,zone,start,end,width,elevation)],"metric_status":"RECONSTRUCTED_APERTURE_AND_ADAPTER_NOT_SURVEYED_DOOR","opening_height_difference_m":delta}
		result.append(data)
	var arrival: Dictionary={}
	var raw_arrival: Dictionary=config.get("arrival_corridor",{})
	if not raw_arrival.is_empty():
		if not validate_connection_request(raw_arrival,true): return {"valid":false,"error":"Incomplete/nonfinite arrival corridor request."}
		if seen.has("T1-L1-west-core"): return {"valid":false,"error":"Arrival owns the one matched T1 west guard aperture."}
		var zone: Dictionary=anchors[-1]
		var x: float=(zone.center as Vector3).x
		var delta: float=float(raw_arrival.target_floor_elevation_m)-elevation
		if absf(delta)>.0001 or absf(entry_width-float(raw_arrival.width_m))>.0001 or absf(entry_height-float(raw_arrival.height_m))>.0001 or absf(entry_x-x)>.0001: return {"valid":false,"error":"Arrival and existing public entrance must share exact threshold/height/aperture."}
		var outside_z: float=(zone.center as Vector3).z+float(raw_arrival.target_cross_m)*.5+float(raw_arrival.outside_approach_m)
		var inside_z: float=(zone.center as Vector3).z+float(zone.width_m)*.5-1.50
		var start:=Vector3(x,.004,inside_z)
		var end:=Vector3(x,.004,outside_z)
		var outer:=Vector3(x,0,(zone.center as Vector3).z+float(raw_arrival.target_cross_m)*.5)
		var corridor:=Vector3(x,0,(zone.center as Vector3).z+float(zone.width_m)*.5+float(raw_arrival.corridor_width_m)*.5)
		if outside_z<=inside_z+4.0: return {"valid":false,"error":"Arrival has no actual exterior-to-loft corridor length."}
		var id:="T1-L1-west-arrival"
		for item: Dictionary in items:
			var p: Vector3=item.position;var size: Vector3=item.size
			if absf(p.x-x)<size.x*.5+float(raw_arrival.width_m)*.5+.45 and p.z+size.z*.5>float((zone.center as Vector3).z) and p.z-size.z*.5<outside_z: return {"valid":false,"error":"Arrival approach intersects retained public furnishing: "+String(item.id)}
		arrival={"id":id,"tower":"T1","side":"west","target_floor_id":"T1-L1","width_m":raw_arrival.width_m,"adapter_width_m":float(raw_arrival.width_m)+1.0,"height_m":raw_arrival.height_m,"center_x":x,"along_offset_m":0.0,"target_cross_m":raw_arrival.target_cross_m,"outer_facade_local":outer,"adapter_start_local":start,"adapter_end_local":end,"target_corridor_local":corridor,"local_route":[end-Vector3(0,0,.50),outer+Vector3(0,.004,.8),outer+Vector3(0,.004,-.8),corridor,Vector3(x,.004,(zone.center as Vector3).z+float(zone.width_m)*.5),Vector3(x,0,(zone.center as Vector3).z)],"target_source_xyz":_connection_source("T1",[0,0,float(zone.width_m)*.5+float(raw_arrival.corridor_width_m)*.5],float(raw_arrival.target_floor_elevation_m)),"outer_facade_source_xyz":_connection_source("T1",[0,0,float(raw_arrival.target_cross_m)*.5],float(raw_arrival.target_floor_elevation_m)),"source_dry_volumes":[_connection_volume("T1",id,zone,start,end,float(raw_arrival.width_m)+1.0,elevation)],"metric_status":"RECONSTRUCTED_EXTERIOR_ARRIVAL_AND_PERIMETER_PARTITIONS_NOT_AS_BUILT","floor_delta_m":0.0}
	return {"valid":true,"core_connections":result,"arrival_corridor":arrival}

func _opening_height(side: float,x: float) -> float:
	if side==_entrance_sign and absf(x-_entrance_x)<_door_width*.5-.0001: return _door_height
	for connection: Dictionary in core_connections:
		if float(connection.side_sign)==side and absf(x-float(connection.center_x))<float(connection.width_m)*.5-.0001: return connection.height_m
	return 0.0

func _opening_near(side: float,x: float,margin: float) -> bool:
	if side==_entrance_sign and absf(x-_entrance_x)<_door_width*.5+margin: return true
	for connection: Dictionary in core_connections:
		if float(connection.side_sign)==side and absf(x-float(connection.center_x))<float(connection.width_m)*.5+margin: return true
	return false

func _matched_beam(kit,material: Material,a: Vector3,b: Vector3,width: float,height: float) -> void:
	kit.beam(material,a,b,width,height)
	var z: Vector3=(b-a).normalized();var x: Vector3=Vector3.UP.cross(z)
	if x.length_squared()<1e-6: x=Vector3.RIGHT.cross(z)
	x=x.normalized();var y: Vector3=z.cross(x).normalized()
	kit.col_box(Vector3(width,height,a.distance_to(b)),(a+b)*.5,Basis(x,y,z))

func _adapter_slab(kit,connection: Dictionary) -> void:
	var a: Vector3=connection.adapter_start_local;var b: Vector3=connection.adapter_end_local
	var half: float=float(connection.get("adapter_width_m",connection.width_m))*.5
	var low: Vector3=a if a.z<b.z else b;var high: Vector3=b if a.z<b.z else a
	_floor_prism(kit,Vector3(a.x-half,low.y,low.z),Vector3(a.x+half,low.y,low.z),Vector3(a.x+half,high.y,high.z),Vector3(a.x-half,high.y,high.z))

func _connection_frame(kit,glass,id: String,center: Vector3,width: float,height: float,outward: float,inclined: bool,park_outwards: bool = false) -> void:
	var steel:=Looks.get_mat("steel_satin")
	for side: float in [-1.0,1.0]:
		var x: float=center.x+side*(width*.5+.07)
		var base: Vector3=_edge(_section_at(x),outward,0) if inclined else Vector3(x,center.y,center.z)
		var top: Vector3=_edge(_section_at(x),outward,height) if inclined else base+Vector3.UP*height
		_matched_beam(kit,steel,base,top,.10,.12)
		var hinge:=base+Vector3(side*.07,.08,0)
		var tip:=hinge+Vector3(0,0,outward*(.95 if park_outwards else -.95))
		var leaf_height: float=height-.22
		glass.quad(Looks.get_mat("glass_clear"),hinge,tip,tip+Vector3.UP*leaf_height,hinge+Vector3.UP*leaf_height)
		kit.col_box(Vector3(.05,leaf_height,.95),hinge.lerp(tip,.5)+Vector3.UP*leaf_height*.5)
		for at: Vector3 in [hinge,tip]: _matched_beam(kit,steel,at,at+Vector3.UP*leaf_height,.035,.035)
		for y: float in [0,leaf_height]: _matched_beam(kit,steel,hinge+Vector3.UP*y,tip+Vector3.UP*y,.035,.035)
	var left: Vector3=_edge(_section_at(center.x-width*.5),outward,height+.07) if inclined else center+Vector3(-width*.5,height+.07,0)
	var right: Vector3=_edge(_section_at(center.x+width*.5),outward,height+.07) if inclined else center+Vector3(width*.5,height+.07,0)
	_matched_beam(kit,steel,left,right,.12,.12)
	var marker:=Node3D.new();marker.name=id.validate_node_name();marker.position=center
	marker.set_meta("reconstructed_public_connection",true);add_child(marker)

func _build_connection_adapter(kit,glass,connection: Dictionary) -> void:
	_adapter_slab(kit,connection)
	_connection_frame(kit,glass,connection.id,connection.glass_threshold_local,connection.width_m,connection.height_m,connection.side_sign,true)
	_assumptions.append({"field":connection.id,"status":"RECONSTRUCTED_PUBLIC_CORE_OPENING_NOT_SURVEYED","why":"Physical glass and matching perimeter guard are split only at the validated aperture; target is the source-positioned L1 corridor, never a teleported duplicate."})

func _build_arrival_adapter(kit,glass,connection: Dictionary) -> void:
	_adapter_slab(kit,connection)
	_connection_frame(kit,glass,connection.id,connection.outer_facade_local,connection.width_m,connection.height_m,1.0,false,true)
	portal_local["actual_outer_facade"]=connection.outer_facade_local
	portal_local["external_arrival"]=connection.local_route[0]
	_assumptions.append({"field":connection.id,"status":"RECONSTRUCTED_ACTUAL_SOURCE_FACADE_ARRIVAL_NOT_AS_BUILT_LAYOUT","why":"An explicit reserved corridor passes between coherently reflowed west programs and through matching facade/guard openings; no actor relocation or disabled wall."})
