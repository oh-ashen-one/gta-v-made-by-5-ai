class_name Lighting
extends RefCounted
## Late-afternoon lighting rig for Orchard Reach (lighting piece, Opus 5.5 wave A).
##
## Owns the sky, the sun, fog, tonemap/exposure, the colour grade and every
## practical light (street lamps, five-foot-way arcade lamps, void-deck tubes,
## hawker pendants). WorldBuilder calls in through a handful of one-line hooks;
## fixture meshes are collected here and emitted as a few MultiMesh draws.
##
## Debug A/B switches (never needed for normal play):
##   --lighting-gi=ssil|sdfgi       indirect light technique (default ssil)
##   --lighting-tonemap=aces|agx    tonemapper (default aces)
##   --lighting-off=vfog,ssil,ssao,lut,pcss   disable features for A/B

# Aerial R2: back to the parent's warm late-afternoon key (critic aerial-R1:
# the D1 swing to 75 deg / cooler key bleached the heritage road to luma 142
# vs 61 and turned the whole grade milky midday). The azimuth stays 61.
const SUN_ROTATION_DEG := Vector3(-19.0, 61.0, 0.0)
const SUN_COLOR := Color(1.0, 0.77, 0.54)
const SUN_ENERGY := 2.55
const SKY_ZENITH := Color(0.38, 0.48, 0.64)
const CLOUD_COVERAGE := 0.55
# Aerial R2: the parent's golden-hour dome; cumulus_sky.gdshader (wave D WIP)
# is kept on disk but its bright radiance fed the bleached street grade.
const SKY_SHADER := "res://assets/authored/shaders/golden_hour_sky.gdshader"
const HORIZON_COOL := Color(0.88, 0.85, 0.80)
const LAMP_COLOR := Color(1.0, 0.78, 0.52)
const TUBE_COLOR := Color(0.86, 0.94, 1.0)

var root: Node3D
var light_count := 0
var void_deck_lights := 0
var arcade_lights := 0
var lamp_lights := 0
var _fixtures := {}          # key -> {mesh, material, xforms: Array[Transform3D], shadow}
var _lights_node: Node3D
var bays: Array = []          # shophouse units, for StreetDressing clutter
var dressing: StreetDressing
var hawker_centres: Array = []
static var _ceiling_points: Array = []   # cached HDB void-deck ceiling grid (local)

static func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix + "="):
			return a.get_slice("=", 1)
	return fallback

# --------------------------------------------------------------- environment
## Builds WorldEnvironment + sun + bounce under `parent`. Returns the nodes.
static func build_environment(parent: Node) -> Dictionary:
	var env := Environment.new()
	var sky_mat := ShaderMaterial.new()
	# SKY_SHADER: see the constant (aerial R2 restored the golden-hour dome).
	sky_mat.shader = load(SKY_SHADER)
	# Humid tropical sky under a cumulus deck (round 2, critic A1). Set here so
	# the self-test can read them; the shader defaults match.
	sky_mat.set_shader_parameter("zenith_color", SKY_ZENITH)
	sky_mat.set_shader_parameter("cloud_coverage", CLOUD_COVERAGE)
	# Explicit so SkylineHorizon.sync() can read the horizon for the far-city haze.
	sky_mat.set_shader_parameter("horizon_cool", HORIZON_COOL)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Ambient and reflections come from the sky itself: blue from above, gold
	# from the sun-side horizon. Shadows are now tinted by the sky instead of
	# one flat blue-black (critic 5, defect 8).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# 75 % sky, 25 % warm pavement grey: shade reads blue-lifted, not violet.
	# Wave A integration: lighting-A4 measured the shade as sepia (blue/red
	# 0.51-0.63 vs 0.72-1.23 in the references); lean the fill toward the sky.
	# Aerial R2: reverted (the bluer fill cast the enclosed workshop floor
	# cold blue, RGB 30,40,57 vs 60,59,61).
	env.ambient_light_sky_contribution = 0.72
	env.ambient_light_color = Color(0.62, 0.65, 0.70)
	env.ambient_light_energy = 0.52
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	var tonemap := _arg("--lighting-tonemap", "aces")
	if tonemap == "agx":
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 1.0
	else:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.04
		env.tonemap_white = 9.0   # keep sunlit white plaster and chrome off the clip (critic A2)

	# Aerial perspective: warm haze that takes its colour from the sky, so far
	# towers sink into gold toward the sun and blue-grey away from it. The sky
	# itself is left clear (fog_sky_affect 0) so the gradient stays visible.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	# Wave A integration: lighting-A4 found aerial views milky (2nd-pct luma 68
	# vs 44 baseline) and glass towers washed to cream. The skyline piece's
	# shader haze already layers the far city, so the global fog is thinner and
	# less warm, and the sun-side warmth comes from sun scatter instead.
	# Aerial R2: reverted to the parent; the far-city depth now comes from the
	# darker graded skyline haze (AerialAtmosphere.HAZE) instead of thicker fog.
	env.fog_light_color = Color(0.88, 0.85, 0.80)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.22
	env.fog_density = 0.00038
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env.fog_height = 24.0
	env.fog_height_density = 0.0009

	# Light volumetric haze: sun shafts through canopies and arcade columns.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0009
	env.volumetric_fog_albedo = Color(1.0, 0.93, 0.84)
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.6
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.0

	# Contact darkening in five-foot ways, void decks and under canopies.
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.6
	env.ssao_power = 1.7
	env.ssao_detail = 0.7
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.28
	env.ssao_ao_channel_affect = 0.3

	if _arg("--lighting-gi", "ssil") == "sdfgi":
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.4
		env.sdfgi_energy = 1.0
		env.sdfgi_bounce_feedback = 0.4
	# Screen-space bounce: sunlit pavement warms the shaded arcade ceilings and
	# the void-deck soffit.
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.9
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0

	# Restrained bloom: only HDR sources (sun disc, lamp bulbs, shop strips,
	# void-deck tubes) cross the threshold.
	env.glow_enabled = true
	env.glow_normalized = false
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.45)
	env.set_glow_level(5, 0.2)
	env.glow_intensity = 0.42
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Above sunlit white plaster (~1.3 linear under a 3.1 sun): only emitters bloom.
	env.glow_hdr_threshold = 1.6
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 10.0

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.0
	env.adjustment_color_correction = _grade_lut()

	var off := _arg("--lighting-off", "").split(",")
	if "vfog" in off: env.volumetric_fog_enabled = false
	if "ssil" in off: env.ssil_enabled = false
	if "ssao" in off: env.ssao_enabled = false
	if "lut" in off: env.adjustment_color_correction = null
	if "fog" in off: env.fog_enabled = false
	if "glow" in off: env.glow_enabled = false
	if "skyamb" in off:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.55, 0.65)
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.name = "GoldenHourEnvironment"
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Late-afternoon western sun (~23 deg, round 2: 14.5 left the ground at
	# sin(14.5)=0.25 of the sun, so roads read near-black and shade ratios
	# collapsed). Still long raking shadows (2.4x object height), gold facades, deep but
	# sky-filled shade under the five-foot ways (ART-07).
	sun.rotation_degrees = SUN_ROTATION_DEG
	sun.light_energy = SUN_ENERGY
	sun.light_color = SUN_COLOR
	sun.light_angular_distance = 0.0 if "pcss" in off else 0.15   # crisp leaf/pole shadows (0.5+ smeared the dappling, critic A1)
	sun.light_volumetric_fog_energy = 1.0
	sun.shadow_enabled = true
	# Wave A integration: lighting-A4 saw stair-stepped self-shadow blocks on the
	# player's shirt and trousers at this grazing sun; more normal bias and a
	# little more blur remove the acne without detaching contact shadows.
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 2.0
	sun.shadow_blur = 0.85
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 280.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.40
	sun.directional_shadow_blend_splits = true
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	parent.add_child(sun)

	var bounce := DirectionalLight3D.new()
	bounce.name = "GroundBounce"
	# Warm pavement bounce aimed upward: soffits, arcade ceilings and the void
	# deck pick up gold from the sunlit ground.
	bounce.rotation_degrees = Vector3(62.0, 40.0, 0.0)
	bounce.light_energy = 0.12
	bounce.light_color = Color(1.0, 0.78, 0.56)
	bounce.light_specular = 0.0
	bounce.shadow_enabled = false
	bounce.light_volumetric_fog_energy = 0.0
	bounce.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(bounce)
	# Aerial D1: long shadows and no froxel veil once the camera climbs.
	var aerial := AerialAtmosphere.attach(parent, env, sun)
	return {"environment": we, "sun": sun, "bounce": bounce, "aerial": aerial}

## Procedural 3D colour-grade LUT (sRGB in -> sRGB out): teal-leaning shadows,
## warm highlights, a gentle S-curve. Original, generated at startup.
static func _grade_lut() -> ImageTexture3D:
	var n := 24
	var images: Array[Image] = []
	for b in n:
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				var c := Vector3(r, g, b) / float(n - 1)
				var l := c.dot(Vector3(0.2126, 0.7152, 0.0722))
				var shadow_w := pow(1.0 - l, 2.2)
				var high_w := pow(l, 1.8)
				c += Vector3(-0.012, 0.004, 0.014) * shadow_w
				c += Vector3(0.042, 0.012, -0.045) * high_w
				# gentle S-curve around mid-grey
				var s := Vector3(_smooth(c.x), _smooth(c.y), _smooth(c.z))
				c = c.lerp(s, 0.22)
				img.set_pixel(r, g, Color(clampf(c.x, 0.0, 1.0), clampf(c.y, 0.0, 1.0), clampf(c.z, 0.0, 1.0)))
		images.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, images)
	return tex

static func _smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

# ----------------------------------------------------------------- practicals
func _ensure_lights_node() -> Node3D:
	if _lights_node == null:
		_lights_node = Node3D.new()
		_lights_node.name = "PracticalLights"
		root.add_child(_lights_node)
	return _lights_node

static var _no_practicals := "practicals" in _arg("--lighting-off", "").split(",")

func _omni(pos: Vector3, color: Color, energy: float, light_range: float, attenuation: float, fade_begin: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	if _no_practicals: l.visible = false
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = attenuation
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.0
	l.light_specular = 0.35
	l.distance_fade_enabled = true
	l.distance_fade_begin = fade_begin
	l.distance_fade_length = 25.0
	_ensure_lights_node().add_child(l)
	light_count += 1
	return l

func _spot(pos: Vector3, color: Color, energy: float, light_range: float, angle: float, fade_begin: float) -> SpotLight3D:
	var l := SpotLight3D.new()
	if _no_practicals: l.visible = false
	l.position = pos
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	l.light_color = color
	l.light_energy = energy
	l.spot_range = light_range
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.8
	l.spot_attenuation = 0.9
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.0
	l.light_specular = 0.4
	l.distance_fade_enabled = true
	l.distance_fade_begin = fade_begin
	l.distance_fade_length = 30.0
	_ensure_lights_node().add_child(l)
	light_count += 1
	return l

func _fixture(key: String, mesh: Mesh, material: Material, xform: Transform3D, shadow: bool = false) -> void:
	if not _fixtures.has(key):
		_fixtures[key] = {"mesh": mesh, "material": material, "xforms": [], "shadow": shadow}
	_fixtures[key]["xforms"].append(xform)

static func _emit_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.5
	return m

static var _unit_box: BoxMesh
static func _box_mesh() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box

static var _mats := {}
static func _m(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"tube": m = _emit_mat(TUBE_COLOR, 6.0)
		"tube_housing": m = Palette.mat(Color(0.78, 0.78, 0.76), 0.6, 0.2)
		"pendant_glow": m = _emit_mat(Color(1.0, 0.74, 0.46), 3.2)
		"pendant_cap": m = Palette.mat(Palette.METAL_DARK, 0.5, 0.5)
		"lamp_glow": m = _emit_mat(Color(1.0, 0.78, 0.50), 6.0)
		"stall_tube": m = _emit_mat(Color(0.95, 0.97, 1.0), 4.5)
		_: m = Palette.mat(Color.GRAY, 0.8)
	_mats[key] = m
	return m

## Street lamp head: warm bulb that blooms plus a downward spot pool on the
## pavement. Lamps are just coming on at golden hour, so they are restrained.
func street_lamp(pos: Vector3) -> void:
	_fixture("lamp_glow", _box_mesh(), _m("lamp_glow"), Transform3D(Basis.from_scale(Vector3(0.55, 0.10, 0.30)), pos + Vector3(0.0, 5.80, 0.0)))
	_spot(pos + Vector3(0.0, 5.6, 0.0), LAMP_COLOR, 3.2, 15.0, 58.0, 110.0)
	lamp_lights += 1

## One shophouse unit's five-foot way: a ceiling pendant over the arcade and a
## warm light that also spills into the recessed shop.
func arcade_bay(pos: Vector3, yaw: float, front_dir: Vector3) -> void:
	var basis := Basis(Vector3.UP, yaw)
	# Under the upper-floor overhang (soffit ~3.95 m), between shopfront and
	# the column line.
	var p := pos + front_dir * 4.4 + Vector3(0.0, 3.0, 0.0)
	_fixture("pendant_cord", _box_mesh(), _m("pendant_cap"), Transform3D(Basis.from_scale(Vector3(0.03, 1.2, 0.03)), p + Vector3(0, 0.75, 0)))
	_fixture("pendant_cap", _box_mesh(), _m("pendant_cap"), Transform3D(basis * Basis.from_scale(Vector3(0.50, 0.10, 0.50)), p + Vector3(0, 0.12, 0)))
	_fixture("pendant_glow", _box_mesh(), _m("pendant_glow"), Transform3D(basis * Basis.from_scale(Vector3(0.36, 0.14, 0.36)), p))
	_omni(p + Vector3(0.0, -0.3, 0.0), Color(1.0, 0.74, 0.46), 1.9, 7.5, 1.0, 60.0)
	arcade_lights += 1
	bays.append({"pos": pos, "yaw": yaw, "front": front_dir, "dir": Vector3(cos(yaw), 0.0, -sin(yaw))})

## HDB void deck: rows of fluorescent tube fittings on the soffit, lit with a
## cool-white grid so the deck reads instead of sitting as a black cave.
func void_deck(slab: Node3D) -> void:
	if slab == null:
		return
	var pts := _void_deck_points(slab)
	if pts.is_empty():
		return
	# The slab is a direct child of the district root, as are the lights.
	var xf := slab.transform
	var s := xf.basis.get_scale().x
	var k := 0
	for lp: Vector3 in pts:
		var wp: Vector3 = xf * lp
		var b := xf.basis.orthonormalized()
		_fixture("tube_housing", _box_mesh(), _m("tube_housing"), Transform3D(b * Basis.from_scale(Vector3(1.40, 0.07, 0.20)), wp + Vector3(0, -0.04, 0)))
		_fixture("tube", _box_mesh(), _m("tube"), Transform3D(b * Basis.from_scale(Vector3(1.25, 0.06, 0.09)), wp + Vector3(0, -0.10, 0)))
		if k % 3 == 0:
			_omni(wp + Vector3(0, -0.6, 0), TUBE_COLOR.lerp(Color(1.0, 0.95, 0.88), 0.5), 5.0, 12.0, 0.55, 70.0)
			void_deck_lights += 1
		k += 1

## Grid points on the slab's void-deck soffit, in slab-local space. Read once
## from the provider mesh: downward faces at the soffit height.
func _void_deck_points(slab: Node3D) -> Array:
	if not _ceiling_points.is_empty():
		return _ceiling_points
	var mi: MeshInstance3D = null
	for n in slab.find_children("*", "MeshInstance3D", true, false):
		mi = n
		break
	if mi == null or mi.mesh == null:
		return []
	var local := Transform3D.IDENTITY
	var p: Node = mi
	while p != null and p != slab:
		if p is Node3D:
			local = (p as Node3D).transform * local
		p = p.get_parent()
	# The soffit is the lowest large horizontal layer above head height. The
	# provider mesh is rendered double-sided and its soffit faces point up, so
	# both orientations count (the downward layer at 6.75 is a higher balcony).
	var layers := {}
	for si in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(v.size()))
		for i in range(0, idx.size() - 2, 3):
			var a: Vector3 = local * v[idx[i]]
			var b: Vector3 = local * v[idx[i + 1]]
			var c: Vector3 = local * v[idx[i + 2]]
			var y := (a.y + b.y + c.y) / 3.0
			if y < 3.0 or y > 8.5:
				continue
			var nrm := (b - a).cross(c - a)
			var area := nrm.length() * 0.5
			if area < 0.05 or absf(nrm.normalized().y) < 0.9:
				continue
			var key := snappedf(y, 0.25)
			if not layers.has(key):
				layers[key] = {"area": 0.0, "tris": []}
			layers[key]["area"] += area
			layers[key]["tris"].append([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
	var ceil_y := INF
	for key in layers:
		if layers[key]["area"] > 150.0 and key < ceil_y:
			ceil_y = key
	if ceil_y == INF:
		return []
	var tris: Array = layers[ceil_y]["tris"]
	var pts: Array = []
	var x := -17.0
	while x <= 18.5:
		var z := -13.0
		while z <= 21.5:
			var q := Vector2(x, z)
			for t in tris:
				if Geometry2D.point_is_inside_triangle(q, t[0], t[1], t[2]):
					pts.append(Vector3(x, ceil_y - 0.02, z))
					break
			z += 5.6
		x += 5.0
	_ceiling_points = pts
	return pts

## Hawker hall: cool tube over each stall counter and warm pendants over the
## dining floor (stall fronts glow like CONCEPT-01's hawker row).
func hawker_hall(centre: Vector3) -> void:
	hawker_centres.append(centre)
	for i in 6:
		var sp := centre + Vector3(-27.0 + i * 11.0, 0.25, -20.0)
		_fixture("stall_tube", _box_mesh(), _m("stall_tube"), Transform3D(Basis.from_scale(Vector3(5.5, 0.07, 0.12)), sp + Vector3(0.0, 2.75, 1.9)))
		_fixture("tube_housing", _box_mesh(), _m("tube_housing"), Transform3D(Basis.from_scale(Vector3(5.7, 0.08, 0.22)), sp + Vector3(0.0, 2.82, 1.9)))
		_omni(sp + Vector3(0.0, 2.5, 2.4), Color(0.95, 0.96, 1.0), 1.4, 6.5, 1.0, 70.0)
	for i in 4:
		for j in 3:
			var pp := centre + Vector3(-22.5 + i * 15.0, 4.2, -6.0 + j * 12.0)
			_fixture("pendant_cap", _box_mesh(), _m("pendant_cap"), Transform3D(Basis.from_scale(Vector3(0.7, 0.12, 0.7)), pp + Vector3(0, 0.12, 0)))
			_fixture("pendant_glow", _box_mesh(), _m("pendant_glow"), Transform3D(Basis.from_scale(Vector3(0.5, 0.16, 0.5)), pp))
			_omni(pp + Vector3(0, -0.4, 0), Color(1.0, 0.80, 0.56), 1.3, 11.0, 0.9, 80.0)

## Emits all collected fixtures as MultiMesh draws (one per fixture type),
## then the weathering volumes and street clutter (StreetDressing).
func finish() -> void:
	dressing = StreetDressing.build(root, bays, hawker_centres)
	for key in _fixtures:
		var g: Dictionary = _fixtures[key]
		var xforms: Array = g["xforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LightingFixtures_%s" % key
		mmi.multimesh = mm
		mmi.material_override = g["material"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if g["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		if OS.has_environment("LIGHTING_DEBUG"): print("[lighting] ", key, " n=", xforms.size(), " first=", xforms[0].origin, " last=", xforms[xforms.size()-1].origin)
	print("[lighting] practicals: %d lights (%d lamps, %d arcade, %d void deck), %d fixture batches" % [light_count, lamp_lights, arcade_lights, void_deck_lights, _fixtures.size()])
