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

func build(config: Dictionary = {}) -> Dictionary:
	if _built: return {"built": false, "error": "Already built; construct a new module for another plan."}
	# Transaction boundary: validation builds temporary value-only state. A failed
	# request must not move this node, append zones or create child/collision nodes.
	var plan: Dictionary = _validated_plan(config)
	if not plan.get("valid", false): return {"built": false, "error": plan.get("error", "Invalid plan"), "full_requested_interior_verified": false}
	zones.assign(plan.zones)
	sections.assign(plan.sections)
	furniture.assign(plan.furniture)
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
	if plan.has("coordinate_context"): _report["coordinate_context"] = plan.coordinate_context.duplicate(true)
	return report()

func _validated_plan(config: Dictionary) -> Dictionary:
	if not is_inside_tree(): return {"valid": false, "error": "Add the module to the tree before building absolute source placement."}
	if not String(config.get("entrance_tower", "T1")) in ["T3", "T2", "T1"]: return {"valid": false, "error": "Unknown entrance tower."}
	if not String(config.get("entrance_side", "bayward")) in ["bayward", "landward"]: return {"valid": false, "error": "Unknown entrance facade."}
	if not basis.get_scale().is_equal_approx(Vector3.ONE): return {"valid": false, "error": "Module must have unit scale."}
	if get_parent() is Node3D and not (get_parent() as Node3D).global_basis.get_scale().is_equal_approx(Vector3.ONE): return {"valid": false, "error": "Parent scale would compress source metres."}
	var door_width: float = float(config.get("entrance_width_m", 4.0))
	var door_height: float = float(config.get("entrance_height_m", 4.8))
	var clearance: float = float(config.get("corridor_width_m", 6.0))
	var inset: float = float(config.get("east_upper_wall_inset_ratio", 0.14))
	var elevation: float = float(config.get("floor_elevation_m", 0.0))
	var offset: float = float(config.get("entrance_along_offset_m", 0.0))
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
	cuts.sort()
	for j in cuts.size() - 1:
		var u0: float = cuts[j]
		var u1: float = cuts[j + 1]
		var lo := _section_at(lerpf(ax, bx, u0))
		var hi := _section_at(lerpf(ax, bx, u1))
		var mid_x := lerpf(ax, bx, (u0 + u1) * 0.5)
		var gap: bool = side == _entrance_sign and absf(mid_x - _entrance_x) < _door_width * 0.5 - 0.0001
		var bottom: float = _door_height if gap else 0.0
		_wall_patch(kit, glass, lo, hi, side, bottom)
	# Side steelwork is staged RHS-like trusses/transoms, not room floors.
	var divisions := maxi(1, int(ceil((bx - ax) / 5.0)))
	for k in divisions + 1:
		var x := lerpf(ax, bx, float(k) / divisions)
		if side == _entrance_sign and absf(x - _entrance_x) < _door_width * 0.5 + 0.15: continue
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
		var tip := hinge + Vector3(0, 0, _entrance_sign * 1.10)
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
	public_path_local = [portal_local.outside, portal_local.inside, zones[entry_index].center]
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
	return {"center": to_global(portal_local.hotel_entrance), "outside": to_global(portal_local.outside), "inside": to_global(portal_local.inside), "normal": global_basis.z * _entrance_sign, "metric_verified": false}

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
			var escape_pairs: Array[Dictionary] = []
			var offsets: Array[float] = [-0.35, 0.0, 0.35]
			if intentional_door: offsets = [-_door_width * 0.5 - 1.0, _door_width * 0.5 + 1.0]
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
