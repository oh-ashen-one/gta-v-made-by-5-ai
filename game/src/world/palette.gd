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

static func mat_textured(color: Color, kind: String, _uv_scale: Vector3, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	# World-space mapping: pavers represent a two-metre tile; other maps four metres.
	# The previous per-box UV stretch and shared cache produced kilometre-long stripes.
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
	_facade_cache[kind] = m
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
			img.fill(Color(0.80, 0.76, 0.68))
			for fy in 6:
				for fx in 6:
					var col := Color(0.26, 0.30, 0.30) if (fx + fy) % 3 != 0 else Color(0.92, 0.84, 0.66)
					img.fill_rect(Rect2i(12 + fx * 40, 14 + fy * 40, 24, 22), col)
			for fx in 5:
				img.fill_rect(Rect2i(30 + fx * 50, 0, 3, 256), Color(0.66, 0.63, 0.57))
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
	return ImageTexture.create_from_image(img)

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
const ASPHALT := Color(0.215, 0.215, 0.225)
const ASPHALT_EDGE := Color(0.26, 0.26, 0.27)
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
## one place rather than an asset collage (ART-01 / ART-04).
const FRONTAGES := [
	Color(0.62, 0.71, 0.68),
	Color(0.78, 0.66, 0.62),
	Color(0.80, 0.70, 0.47),
	Color(0.67, 0.72, 0.60),
	Color(0.72, 0.68, 0.76),
	Color(0.74, 0.62, 0.55),
	Color(0.60, 0.67, 0.72),
]

const SIGN_TEXT := [
	"Kopitiam", "Hardware", "Barber", "Money Changer", "Bakery", "Repair Shop",
	"Phone Repair", "Sari Textiles", "Rice Shop", "Clinic", "Laundry", "Stationery",
]
