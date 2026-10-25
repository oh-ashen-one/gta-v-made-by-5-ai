extends RefCounted
## Shared material set for the downtown landmarks (one cached instance per key,
## so the static batcher and the kit's per-material surfaces stay merged).
## Palette follows docs/LOOK_DEV.md: no pure white, no pure black, glass is a
## cool tint with a satin sheen, steel is painted, stone is granite.

static var _cache := {}

static func get_mat(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m: Material = _make(key)
	_cache[key] = m
	return m

static func _std(c: Color, rough: float, metal: float = 0.0, spec: float = 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = spec
	return m

static func _make(key: String) -> Material:
	match key:
		"granite_paving":
			return _plaza_paving()
		"granite_light":
			return Palette.mat_textured(Color(0.70, 0.68, 0.64), "concrete", Vector3.ONE, 0.82)
		"granite_dark":
			return Palette.mat_textured(Color(0.36, 0.36, 0.35), "concrete", Vector3.ONE, 0.8)
		"concrete_fair":
			return Palette.mat_textured(Color(0.68, 0.67, 0.64), "concrete", Vector3.ONE, 0.9)
		"turf":
			return DowntownLawn.or_default(Palette.mat_textured(Color(0.23, 0.34, 0.15), "soil", Vector3.ONE, 0.95))
		"soil_bed":
			return Palette.mat_textured(Color(0.20, 0.16, 0.12), "soil", Vector3.ONE, 0.98)
		"steel_white":
			return _std(Color(0.80, 0.81, 0.80), 0.34, 0.55)
		"steel_satin":
			return _std(Color(0.62, 0.64, 0.65), 0.38, 0.8)
		"steel_dark":
			return _std(Color(0.16, 0.17, 0.18), 0.45, 0.6)
		"steel_bronze":
			return _std(Color(0.42, 0.33, 0.24), 0.42, 0.7)
		"aluminium_shade":
			return _std(Color(0.66, 0.64, 0.58), 0.42, 0.75)
		"hull_panel":
			return _std(Color(0.74, 0.75, 0.74), 0.4, 0.35)
		"glass_dark":
			# Opaque curtain-wall glass: satin enough not to clip in the low sun.
			return _std(Color(0.10, 0.16, 0.19), 0.12, 0.45, 0.7)
		"window_glass":
			return _std(Color(0.22, 0.30, 0.33), 0.1, 0.5, 0.8)
		"glass_green":
			return _std(Color(0.16, 0.24, 0.24), 0.14, 0.4, 0.7)
		"glass_clear":
			var g := _std(Color(0.42, 0.56, 0.60, 0.32), 0.05, 0.1, 0.8)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			return g
		"glass_canopy":
			var gc := _std(Color(0.70, 0.80, 0.82, 0.38), 0.08, 0.2, 0.8)
			gc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gc.cull_mode = BaseMaterial3D.CULL_DISABLED
			return gc
		"interior_warm":
			var iw := _std(Color(0.46, 0.38, 0.30), 0.7)
			iw.emission_enabled = true
			iw.emission = Color(0.95, 0.72, 0.45)
			iw.emission_energy_multiplier = 0.35
			return iw
		"light_strip":
			var ls := _std(Color(1.0, 0.86, 0.62), 0.4)
			ls.emission_enabled = true
			ls.emission = Color(1.0, 0.82, 0.55)
			ls.emission_energy_multiplier = 2.2
			return ls
		"pool_water":
			var pw := _std(Color(0.10, 0.42, 0.52), 0.04, 0.0, 0.9)
			return pw
		"pond_water":
			return _std(Color(0.05, 0.10, 0.11), 0.03, 0.0, 0.9)
		"soffit":
			var so := _std(Color(0.78, 0.76, 0.72), 0.6)
			so.emission_enabled = true
			so.emission = Color(0.85, 0.80, 0.72)
			so.emission_energy_multiplier = 0.32
			return so
		"deck_stone":
			return Palette.mat_textured(Color(0.66, 0.62, 0.56), "pavers", Vector3.ONE, 0.8)
		"timber":
			return _std(Color(0.42, 0.30, 0.20), 0.72)
		"planting":
			return LandmarkLooks.material_for("st_canopy_planting")
		"vertical_garden":
			return LandmarkLooks.material_for("st_vertical_garden")
		"hedge":
			return _std(Color(0.16, 0.27, 0.12), 0.95)
		"shrub_light":
			return _std(Color(0.26, 0.38, 0.15), 0.95)
		"lotus_white":
			return _std(Color(0.85, 0.84, 0.80), 0.42, 0.05)
		"fullerton_granite":
			return Palette.mat_textured(Color(0.80, 0.76, 0.66), "plaster", Vector3.ONE, 0.86)
		"fullerton_shadow":
			return _std(Color(0.36, 0.33, 0.28), 0.9)
		"terracotta":
			return _std(Color(0.48, 0.27, 0.20), 0.82)
		"render_cream":
			return Palette.mat_textured(Color(0.82, 0.78, 0.68), "plaster", Vector3.ONE, 0.88)
		"supertree_steel":
			return _std(Color(0.36, 0.22, 0.20), 0.6, 0.55)
		"dome_frame":
			return _std(Color(0.30, 0.31, 0.31), 0.45, 0.65)
		"signage":
			return _std(Color(0.12, 0.13, 0.14), 0.5, 0.3)
		"bollard":
			return _std(Color(0.30, 0.30, 0.30), 0.5, 0.6)
		"red_cladding":
			return _std(Color(0.55, 0.12, 0.10), 0.5, 0.3)
		"tower_glass":
			return LandmarkLooks.material_for("mbs_curtain_glass")
	return _std(Color(0.6, 0.6, 0.6), 0.8)

static func _plaza_paving() -> Material:
	# Use the already-generated private granite set at its authored scale:
	# a 4x4 tile of 600 mm slabs covers 2.4 m, including on sloped approaches.
	# World triplanar mapping avoids stretched joints across giant plaza quads.
	var prefix := "res://assets/providers/higgsfield/plaza_granite_pavers_"
	if "--astra-plaza-material-off" in OS.get_cmdline_user_args() or not ResourceLoader.exists(prefix + "albedo.png"):
		return Palette.mat_textured(Color(0.60, 0.59, 0.56), "pavers", Vector3.ONE, 0.86)
	var m := _std(Color(0.88, 0.87, 0.85), 0.88)
	m.resource_name = "AstraPlazaGranite600mm"
	m.albedo_texture = load(prefix + "albedo.png")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE / 2.4
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if ResourceLoader.exists(prefix + "normal.png"):
		m.normal_enabled = true
		m.normal_texture = load(prefix + "normal.png")
		m.normal_scale = 0.35
	if ResourceLoader.exists(prefix + "rough.png"):
		m.roughness_texture = load(prefix + "rough.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return m
