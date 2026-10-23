class_name Palette
extends RefCounted
## Shared look-development palette (END_GOAL ART-01 / ART-04).
## One warm late-afternoon tropical look, applied consistently.

static func mat(color: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

static func emissive(color: Color, energy: float = 1.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m

## Procedural surface textures (ART-04): no external image assets, but the
## materials stop reading as flat plastic.
static var _tex_cache := {}
static var _mat_cache := {}

static func tex(kind: String) -> NoiseTexture2D:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var n := FastNoiseLite.new()
	match kind:
		"asphalt":
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = 0.09
			n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		"concrete":
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX
			n.frequency = 0.025
		"plaster":
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX
			n.frequency = 0.05
		"tile":
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX
			n.frequency = 0.11
		"metal":
			n.noise_type = FastNoiseLite.TYPE_VALUE
			n.frequency = 0.08
		_:
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX
			n.frequency = 0.04
	n.seed = 4200 + kind.length() * 37
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	_tex_cache[kind] = t
	return t

static func mat_textured(color: Color, kind: String, _uv_scale: Vector3, rough: float = 0.9, metal: float = 0.0, weathered: bool = true) -> Material:
	# World-space mapping: pavers represent a two-metre tile; other maps four metres.
	# The previous per-box UV stretch and shared cache produced kilometre-long stripes.
	# Wave B: exterior asphalt, paving, concrete and render use weathered
	# surface shaders (tyre wear, patches, cracks, grime, rain streaks).
	if weathered and kind in WEATHERED_KINDS and not "--clean-surfaces" in OS.get_cmdline_user_args():
		return weathered_surface(color, kind, rough, metal)
	var key := "%s|%s|%.2f|%.2f" % [kind, color.to_html(), rough, metal]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	var path := "res://assets/authored/surfaces/" + kind
	if ResourceLoader.exists(path + "_albedo.png"):
		m.albedo_texture = load(path + "_albedo.png")
		m.normal_enabled = true
		m.normal_texture = load(path + "_normal.png")
		m.normal_scale = 0.07 if kind == "asphalt" else 0.3
		m.roughness_texture = load(path + "_roughness.png")
	else:
		m.albedo_texture = tex(kind)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * (0.5 if kind == "pavers" else 0.25)
	m.uv1_triplanar_sharpness = 8.0
	m.roughness = rough
	if kind == "asphalt":
		m.roughness_texture = null
		# A low sun rakes across asphalt; 0.96 roughness crushed the carriageway
		# to a black void in the first wave-3 street render.
		m.roughness = 0.80
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m

## --- Weathered surfaces (wave B "materials") ------------------------------
## Original world-space shaders under assets/authored/shaders/. One cached
## ShaderMaterial per (kind, colour, roughness), so the static batcher still
## merges every box that shares it.
const WEATHERED_KINDS := ["asphalt", "pavers", "concrete", "plaster", "soil"]
const SURF_DIR := "res://assets/authored/surfaces/"
const SHADER_DIR := "res://assets/authored/shaders/"
static var _weather_cache := {}

static func weather_masks() -> Texture2D:
	return load(SURF_DIR + "weather_masks.png")

static func weathered_surface(color: Color, kind: String, rough: float = 0.9, metal: float = 0.0, lot: bool = true) -> ShaderMaterial:
	var key := "%s|%s|%.2f|%.2f|%s" % [kind, color.to_html(), rough, metal, lot]
	if _weather_cache.has(key):
		return _weather_cache[key]
	var m := ShaderMaterial.new()
	m.set_shader_parameter("weather_masks", weather_masks())
	match kind:
		"asphalt":
			m.shader = load(SHADER_DIR + "road_asphalt.gdshader")
			m.set_shader_parameter("albedo_tex", load(SURF_DIR + "asphalt_albedo.png"))
			m.set_shader_parameter("normal_tex", load(SURF_DIR + "asphalt_normal.png"))
			m.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
			m.set_shader_parameter("road_grid", 0.0 if lot else 1.0)
			# nearfield (opus55 D): graded aggregate tile for fine grain
			m.set_shader_parameter("agg_tex", load(SURF_DIR + "asphalt_aggregate_albedo.png"))
			m.set_shader_parameter("agg_nrm", load(SURF_DIR + "asphalt_aggregate_normal.png"))
			# nearfield R: photographic asphalt from the generated library
			var ph := NearField.prov("road_asphalt_albedo.png") if NearField.enabled() else null
			if ph != null:
				m.set_shader_parameter("photo_tex", ph)
				m.set_shader_parameter("photo_nrm", NearField.prov("road_asphalt_normal.png"))
				m.set_shader_parameter("photo_k", 0.85)
				m.set_shader_parameter("grain_k", 0.22)
		"pavers":
			m.shader = load(SHADER_DIR + "paving.gdshader")
			m.set_shader_parameter("albedo_tex", load(SURF_DIR + "pavers_albedo.png"))
			m.set_shader_parameter("normal_tex", load(SURF_DIR + "pavers_normal.png"))
			m.set_shader_parameter("rough_tex", load(SURF_DIR + "pavers_roughness.png"))
			m.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
			m.set_shader_parameter("base_rough", rough)
			if NearField.enabled():
				m.set_shader_parameter("lift", 1.16)
		_:
			m.shader = load(SHADER_DIR + "weathered_wall.gdshader")
			m.set_shader_parameter("albedo_tex", load(SURF_DIR + kind + "_albedo.png"))
			m.set_shader_parameter("normal_tex", load(SURF_DIR + kind + "_normal.png"))
			m.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
			m.set_shader_parameter("base_rough", rough)
			m.set_shader_parameter("metal", metal)
			m.set_shader_parameter("peel", 1.0 if kind == "plaster" else 0.0)
			m.set_shader_parameter("slabs", 1.0 if kind == "concrete" else 0.0)
			if kind == "soil":
				m.set_shader_parameter("streaks", 0.0)
				m.set_shader_parameter("turf", 1.0)
	m.set_meta("weathered_kind", kind)
	_weather_cache[key] = m
	return m

## The district carriageways: lane-aware tyre tracks, oil lines, gutters,
## reinstatement patches, trench strips, manhole covers and cracking.
static func road_asphalt(color: Color = ASPHALT) -> Material:
	if "--clean-surfaces" in OS.get_cmdline_user_args():
		return mat_textured(color, "asphalt", Vector3.ONE, 0.9, 0.0, false)
	return weathered_surface(color, "asphalt", 0.9, 0.0, false)

static var _paint_cache := {}

## Worn carriageway markings (lane dashes, kerb lines, junction stripes).
static func road_paint(color: Color, rough: float = 0.75) -> Material:
	if "--clean-surfaces" in OS.get_cmdline_user_args():
		return mat(color, rough)
	var key := color.to_html()
	if _paint_cache.has(key):
		return _paint_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_DIR + "road_paint.gdshader")
	m.set_shader_parameter("weather_masks", weather_masks())
	m.set_shader_parameter("paint", Vector3(color.r, color.g, color.b))
	m.set_meta("weathered_kind", "paint")
	_paint_cache[key] = m
	return m

static var _grime_overlay: ShaderMaterial = null

## Multiply pass for imported building modules and facade sheets (next_pass).
static func grime_overlay() -> ShaderMaterial:
	if _grime_overlay == null:
		_grime_overlay = ShaderMaterial.new()
		_grime_overlay.shader = load(SHADER_DIR + "grime_overlay.gdshader")
		_grime_overlay.set_shader_parameter("weather_masks", weather_masks())
		_grime_overlay.render_priority = 1
	return _grime_overlay

static var _corrugated_cache := {}

## Weathered corrugated-steel cladding/roofing (sheds, hangars, workshops).
static func corrugated(color: Color, rust: float = 1.0) -> Material:
	if "--clean-surfaces" in OS.get_cmdline_user_args():
		return mat(color, 0.6, 0.4)
	var key := "%s|%.2f" % [color.to_html(), rust]
	if _corrugated_cache.has(key):
		return _corrugated_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_DIR + "corrugated_metal.gdshader")
	m.set_shader_parameter("weather_masks", weather_masks())
	m.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
	m.set_shader_parameter("rust", rust)
	m.set_meta("weathered_kind", "corrugated")
	_corrugated_cache[key] = m
	return m

static var _five_foot: Material = null

## Encaustic heritage tiles for the shophouse five-foot ways (CONCEPT-01/02).
static func five_foot_tiles() -> Material:
	if "--clean-surfaces" in OS.get_cmdline_user_args():
		return mat_textured(Color(.65, .68, .62), "pavers", Vector3.ONE, .86)
	if _five_foot == null:
		var m := ShaderMaterial.new()
		m.shader = load(SHADER_DIR + "encaustic_tiles.gdshader")
		m.set_shader_parameter("weather_masks", weather_masks())
		m.set_meta("weathered_kind", "encaustic")
		_five_foot = m
	return _five_foot

static var _grime_overlay_light: ShaderMaterial = null

## Light variant for conservation shophouses: kept, repainted pastel fronts
## (CONCEPT-01/02) get only a low splash band at the base, no streaks.
static func grime_overlay_light() -> ShaderMaterial:
	if _grime_overlay_light == null:
		_grime_overlay_light = grime_overlay().duplicate() as ShaderMaterial
		_grime_overlay_light.set_shader_parameter("band_k", 0.45)
		_grime_overlay_light.set_shader_parameter("band_h", 0.45)
		_grime_overlay_light.set_shader_parameter("streak_k", 0.0)
		_grime_overlay_light.set_shader_parameter("mott_k", 0.12)
	return _grime_overlay_light

## Procedural facade sheets (ART-03/ART-04). A 144 m block of plain boxes reads
## as a prototype; a window/floor grid on the same box reads as a building.
## BoxMesh faces are 0..1 UV, so one sheet is one facade elevation.
static var _facade_cache := {}

static func facade(kind: String) -> StandardMaterial3D:
	if _facade_cache.has(kind):
		return _facade_cache[kind]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _facade_image(kind)
	m.roughness = 0.82
	# BoxMesh faces are 0..1, so without a repeat a 46 m rear extension would
	# show six 7 m windows. Repeat horizontally to keep a human window scale.
	match kind:
		"shopback": m.uv1_scale = Vector3(3.0, 2.0, 1.0)
		"hdb": m.uv1_scale = Vector3(2.0, 1.0, 1.0)
		"workshop": m.uv1_scale = Vector3(2.0, 1.0, 1.0)
		_: m.uv1_scale = Vector3(2.0, 2.0, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not "--clean-surfaces" in OS.get_cmdline_user_args():
		m.next_pass = grime_overlay()
	_facade_cache[kind] = m
	return m

## Wave B: repainted variants of a facade sheet, so a district of infill
## blocks is not one cream colour (paint fades and is redone unit by unit).
const FACADE_TINTS := [
	Color(1.0, 1.0, 1.0), Color(0.86, 0.87, 0.88), Color(0.97, 0.86, 0.80),
	Color(0.95, 0.90, 0.74), Color(0.84, 0.90, 0.84), Color(0.74, 0.73, 0.71),
	Color(0.90, 0.84, 0.88),
]
static var _facade_variant_cache := {}

static func facade_variant(kind: String, index: int) -> StandardMaterial3D:
	var i := posmod(index, FACADE_TINTS.size())
	if i == 0:
		return facade(kind)
	var key := "%s|%d" % [kind, i]
	if _facade_variant_cache.has(key):
		return _facade_variant_cache[key]
	var m := facade(kind).duplicate() as StandardMaterial3D
	m.albedo_color = FACADE_TINTS[i]
	m.next_pass = facade(kind).next_pass
	_facade_variant_cache[key] = m
	return m

static func _facade_image(kind: String) -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	match kind:
		"office":
			img.fill(Color(0.30, 0.35, 0.39))
			for fy in 16:
				for fx in 10:
					var lit := (fx * 7 + fy * 13) % 11 == 0
					var col := Color(0.98, 0.80, 0.52) if lit else Color(0.15, 0.21, 0.27).lerp(Color(0.22, 0.31, 0.38), float((fx + fy) % 5) / 5.0)
					img.fill_rect(Rect2i(6 + fx * 25, 5 + fy * 16, 21, 13), col)
			for fx in 11:
				img.fill_rect(Rect2i(fx * 25, 0, 2, 256), Color(0.44, 0.47, 0.48))
		"hdb":
			img.fill(Color(0.78, 0.75, 0.69))
			for fy in 14:
				img.fill_rect(Rect2i(0, 4 + fy * 18, 256, 3), Color(0.66, 0.63, 0.58))
				for fx in 8:
					var lit := (fx * 5 + fy * 3) % 9 == 0
					var col := Color(1.0, 0.86, 0.62) if lit else Color(0.24, 0.28, 0.31)
					img.fill_rect(Rect2i(8 + fx * 31, 8 + fy * 18, 20, 11), col)
					if (fx + fy) % 4 == 0:
						img.fill_rect(Rect2i(8 + fx * 31, 19 + fy * 18, 20, 2), Color(0.55, 0.55, 0.52))
		"shopback":
			img.fill(Color(0.72, 0.69, 0.62))
			for fy in 6:
				for fx in 6:
					var col := Color(0.26, 0.30, 0.30) if (fx + fy) % 3 != 0 else Color(0.62, 0.57, 0.46)
					img.fill_rect(Rect2i(12 + fx * 40, 14 + fy * 40, 24, 22), col)
			for fx in 5:
				img.fill_rect(Rect2i(30 + fx * 50, 0, 3, 256), Color(0.60, 0.57, 0.52))
		"workshop":
			img.fill(Color(0.55, 0.57, 0.58))
			for fx in 32:
				img.fill_rect(Rect2i(fx * 8, 0, 3, 256), Color(0.46, 0.48, 0.50).lerp(Color(0.63, 0.65, 0.66), float(fx % 3) / 3.0))
			img.fill_rect(Rect2i(96, 96, 64, 160), Color(0.40, 0.42, 0.43))
			for fy in 8:
				img.fill_rect(Rect2i(96, 96 + fy * 20, 64, 2), Color(0.52, 0.54, 0.55))
		"glass":
			img.fill(Color(0.30, 0.38, 0.44))
			for fy in 20:
				for fx in 12:
					var col := Color(0.36, 0.46, 0.52).lerp(Color(0.52, 0.60, 0.63), float((fx * 3 + fy * 5) % 7) / 7.0)
					img.fill_rect(Rect2i(3 + fx * 21, 3 + fy * 12, 18, 10), col)
			for fy in 21:
				img.fill_rect(Rect2i(0, fy * 12, 256, 2), Color(0.20, 0.23, 0.25))
		_:
			img.fill(Color(0.72, 0.70, 0.65))
	if not "--clean-surfaces" in OS.get_cmdline_user_args():
		_weather_facade(img, kind)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Wave B: bake tropical weathering into a facade sheet: dirty rain streaks
## running down from every window sill, algae mottling and a faded top band.
## Deterministic per kind; the sheet still tiles (drips wrap vertically).
static func _weather_facade(img: Image, kind: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var mott := FastNoiseLite.new()
	mott.seed = 911 + kind.length() * 13
	mott.frequency = 0.035
	mott.fractal_octaves = 3
	var streak := FastNoiseLite.new()
	streak.seed = 377 + kind.length() * 7
	streak.frequency = 1.0
	streak.fractal_octaves = 2
	var src := img.duplicate() as Image
	for x in w:
		var drip := 0.0
		# two passes so drips that start near the bottom wrap over the top edge
		for pass_i in 2:
			for y in h:
				var c := src.get_pixel(x, y)
				var lum := (c.r + c.g + c.b) / 3.0
				var above := src.get_pixel(x, (y - 1 + h) % h)
				var above_lum := (above.r + above.g + above.b) / 3.0
				var is_wall := lum > 0.42
				if is_wall and above_lum < 0.36:
					drip = 1.0
				elif not is_wall:
					drip = 0.0
				else:
					drip *= 0.955
				if pass_i == 0:
					continue
				var col_streak := streak.get_noise_2d(float(x) * 0.9, float(y) * 0.025) * 0.5 + 0.5
				var m := mott.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				var k := 1.0
				if is_wall:
					k -= drip * (0.22 + 0.25 * col_streak)
					k -= smoothstep(0.62, 0.9, col_streak) * 0.10
				k -= smoothstep(0.45, 0.85, m) * 0.16
				var out := Color(c.r * k, c.g * (k + 0.015 * m), c.b * (k - 0.02 * m))
				img.set_pixel(x, y, out)

static func glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.55, 0.62, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.35
	m.roughness = 0.08
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

const ROOF_TILE := Color(0.42, 0.20, 0.15)
const ROOF_TILE_2 := Color(0.50, 0.26, 0.18)
const PLASTER := Color(0.85, 0.81, 0.73)
const PLASTER_2 := Color(0.78, 0.74, 0.66)
const CONCRETE := Color(0.55, 0.54, 0.51)
const CONCRETE_LIGHT := Color(0.62, 0.60, 0.56)
# r3: slightly cool so golden-hour sun reads neutral grey, not brown (R/B<=1.3).
# nearfield (opus55 D): the r3 blue (B/R 1.56) rendered shade as navy ink under
# the blue sky fill (critic B3: B-R +18). Near-neutral, a touch cool.
const ASPHALT := Color(0.168, 0.172, 0.184)
const ASPHALT_EDGE := Color(0.30, 0.30, 0.31)
const PAINT_LINE := Color(0.85, 0.83, 0.72)
const GLASS := Color(0.44, 0.56, 0.62)
const METAL := Color(0.35, 0.36, 0.38)
const METAL_DARK := Color(0.16, 0.17, 0.18)
const FOLIAGE := Color(0.16, 0.32, 0.17)
const FOLIAGE_LIGHT := Color(0.26, 0.42, 0.20)
const TRUNK := Color(0.24, 0.18, 0.13)
const SHOP_WARM := Color(1.0, 0.76, 0.42)
const SKIN := Color(0.72, 0.55, 0.44)
const WATER := Color(0.16, 0.31, 0.36)

## Muted pastel shophouse frontages, kept in one family so the street reads as
## one place rather than an asset collage (ART-01 / ART-04). Wave 3 widens the
## hue range: the first pass plus a warm sun turned the whole street peach.
const FRONTAGES := [
	Color(0.50, 0.70, 0.66),   # Peranakan teal
	Color(0.84, 0.60, 0.55),   # dusty rose
	Color(0.86, 0.73, 0.42),   # ochre
	Color(0.57, 0.70, 0.48),   # sage
	Color(0.66, 0.61, 0.79),   # lilac
	Color(0.80, 0.56, 0.42),   # terracotta
	Color(0.46, 0.62, 0.76),   # strait blue
]

## Public-housing paint schemes. Real estates are repainted in batches, so a
## district shows several schemes, not one. Used to break the clone-HDB grid.
const HDB_TINTS := [
	Color(0.94, 0.93, 0.89),   # off-white
	Color(0.86, 0.88, 0.90),   # pale blue-grey
	Color(0.95, 0.90, 0.78),   # cream
	Color(0.88, 0.82, 0.76),   # warm sand
	Color(0.82, 0.87, 0.84),   # pale mint
	Color(0.92, 0.86, 0.84),   # dusty rose
]

const SIGN_TEXT := [
	"Kopitiam", "Hardware", "Barber", "Money Changer", "Bakery", "Repair Shop",
	"Phone Repair", "Sari Textiles", "Rice Shop", "Clinic", "Laundry", "Stationery",
]
