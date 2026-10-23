class_name NearField
extends RefCounted
## Nearfield piece (opus55 wave D): the bottom 40 % of every street frame.
## Critic materials-B3 / driving-C2: kerbs, sign bases and median beds read as
## blockout boxes, the median plants as faceted blades, two-wheelers as
## primitives with no collision, sign faces blank. This module replaces them
## with generated, batched geometry:
##  - swept precast kerb units with a rounded arris (kerb_stone shader: unit
##    joints, chipped arris, foot grime, tyre scuffs, painted bands);
##  - median islands: kerbed beds with bull-nosed painted ends, soil, dense
##    multi-layer shrubs (alpha leaf cards, vertex AO, translucency) and
##    legible keep-left signs on galvanised posts;
##  - bicycles and scooters as multi-material models with collision;
##  - pictogram sign plates (no-parking, no-entry, bus stop...) for posts;
##  - a framed bus shelter instead of the bare blue glass slab.
## All visuals are MultiMesh / merged ArrayMesh per 160 m cell.

const SURF := "res://assets/authored/surfaces/"
const SHADERS := "res://assets/authored/shaders/"
const X_LINES: Array[float] = [-320.0, -160.0, 0.0, 160.0, 320.0]
const Z_LINES: Array[float] = [-320.0, -160.0, 0.0, 160.0, 320.0]
const ROAD_HALF := 8.0

static var stats := {}
static var _cache := {}

static func _count(k: String, n: int = 1) -> void:
	stats[k] = int(stats.get(k, 0)) + n

static func enabled() -> bool:
	return not "--nearfield-off" in OS.get_cmdline_user_args()

## Generated library (loop/GENERATED_ASSETS.md; git-ignored provider files,
## private build use). Every caller falls back to the authored maps when a
## provider file is absent, so a clean public checkout still builds.
const PROV := "res://assets/providers/higgsfield/"

static func prov(file: String) -> Texture2D:
	var key := "prov:" + file
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	if ResourceLoader.exists(PROV + file) and not "--nearfield-no-provider" in OS.get_cmdline_user_args():
		t = load(PROV + file)
	_cache[key] = t
	return t

## Weathered cast concrete (provider concrete_weathered: streaks, pores,
## algae) on world triplanar UVs: median noses, planter walls, sign bases.
static func concrete_mat(tint: Color = Color(0.86, 0.85, 0.82), tile_m: float = 2.4) -> Material:
	var key := "concrete_mat:%s:%.2f" % [tint.to_html(), tile_m]
	if _cache.has(key):
		return _cache[key]
	var alb := prov("concrete_weathered_albedo.png")
	var m: Material
	if alb == null:
		m = Palette.weathered_surface(Color(0.60, 0.59, 0.56), "concrete", 0.9)
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = alb
		sm.albedo_color = tint
		sm.normal_enabled = true
		sm.normal_texture = prov("concrete_weathered_normal.png")
		sm.normal_scale = 0.9
		sm.roughness_texture = prov("concrete_weathered_rough.png")
		sm.roughness = 1.0
		sm.uv1_triplanar = true
		sm.uv1_world_triplanar = true
		sm.uv1_triplanar_sharpness = 4.0
		sm.uv1_scale = Vector3.ONE / tile_m
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m = sm
	_cache[key] = m
	return m

## Grey interlocking pavers (provider footpath_pavers, ~3 m tile, texture
## is ~0.88 aspect-stretched) for the paved median noses.
static func pavers_mat(tint: Color = Color(0.92, 0.91, 0.88)) -> Material:
	var key := "pavers_mat:" + tint.to_html()
	if _cache.has(key):
		return _cache[key]
	var alb := prov("footpath_pavers_albedo.png")
	var m: Material
	if alb == null:
		m = concrete_mat()
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = alb
		sm.albedo_color = tint
		sm.normal_enabled = true
		sm.normal_texture = prov("footpath_pavers_normal.png")
		sm.roughness_texture = prov("footpath_pavers_rough.png")
		sm.uv1_triplanar = true
		sm.uv1_world_triplanar = true
		sm.uv1_triplanar_sharpness = 6.0
		sm.uv1_scale = Vector3(1.0 / 3.0, 1.0 / 3.0, 0.88 / 3.0)
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m = sm
	_cache[key] = m
	return m

## Photographic plant cards (provider foliage_median_atlas, 2 x 2 cells:
## 0 mondo grass + spider lily, 1 ixora, 2 croton, 3 bird's-nest fern).
static func card_material() -> ShaderMaterial:
	if _cache.has("card_mat"):
		return _cache["card_mat"]
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + "foliage_card.gdshader")
	m.set_shader_parameter("leaf_tex", prov("foliage_median_atlas.png"))
	_cache["card_mat"] = m
	return m

static func cards_available() -> bool:
	return prov("foliage_median_atlas.png") != null

# ------------------------------------------------------------ materials
static func kerb_material() -> ShaderMaterial:
	if _cache.has("kerb_mat"):
		return _cache["kerb_mat"]
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + "kerb_stone.gdshader")
	m.set_shader_parameter("weather_masks", Palette.weather_masks())
	var pc := prov("concrete_weathered_albedo.png")
	if pc != null:
		# provider concrete: mean albedo (0.59, 0.564, 0.516); the shader
		# normalises by it so the tint keeps the LOOK_DEV granite value
		m.set_shader_parameter("grain_tex", pc)
		m.set_shader_parameter("grain_nrm", prov("concrete_weathered_normal.png"))
		m.set_shader_parameter("grain_mean", Vector3(0.59, 0.564, 0.516))
		m.set_shader_parameter("grain_scale", 0.42)
		m.set_shader_parameter("grain_colour", 0.55)
	else:
		m.set_shader_parameter("grain_tex", load(SURF + "concrete_albedo.png"))
		m.set_shader_parameter("grain_nrm", load(SURF + "concrete_normal.png"))
	_cache["kerb_mat"] = m
	return m

static func leaf_material() -> ShaderMaterial:
	if _cache.has("leaf_mat"):
		return _cache["leaf_mat"]
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + "shrub_leaf.gdshader")
	m.set_shader_parameter("leaf_tex", load(SURF + "shrub_leaves_albedo.png"))
	m.set_shader_parameter("leaf_nrm", load(SURF + "shrub_leaves_normal.png"))
	_cache["leaf_mat"] = m
	return m

static func sign_material() -> ShaderMaterial:
	if _cache.has("sign_mat"):
		return _cache["sign_mat"]
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + "street_sign.gdshader")
	m.set_shader_parameter("sign_tex", load(SURF + "street_signs_albedo.png"))
	_cache["sign_mat"] = m
	return m

static func _std(color: Color, rough: float, metal: float = 0.0, vcol: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = vcol
	return m

static func galvanised() -> StandardMaterial3D:
	if not _cache.has("galv"):
		var m := _std(Color(0.62, 0.63, 0.62), 0.42, 0.75)
		m.albedo_texture = load(SURF + "metal_albedo.png")
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 2.0
		_cache["galv"] = m
	return _cache["galv"]

# --------------------------------------------------------- kerb sweeps
## Road-kerb cross-section (x = out from the road, y = up), foot to back.
## 0.13 m upstand above the 0.06 m carriageway, battered face, 30 mm
## rounded arris, 0.26 m bed width, back at paver level.
const KERB_PROFILE := [
	Vector2(-0.02, 0.0), Vector2(0.0, 0.06), Vector2(0.02, 0.17), Vector2(0.026, 0.182),
	Vector2(0.036, 0.194), Vector2(0.05, 0.2), Vector2(0.27, 0.2), Vector2(0.29, 0.19), Vector2(0.30, 0.15),
]
const KERB_ARRIS := [0.0, 0.0, 0.5, 1.0, 1.0, 0.6, 0.0, 0.5, 0.0]
const KERB_FACE := [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 2.0]

## Median kerb: taller (0.32 m) island upstand, both faces shown.
const MEDIAN_PROFILE := [
	Vector2(-0.02, 0.0), Vector2(0.0, 0.06), Vector2(0.025, 0.29), Vector2(0.032, 0.304),
	Vector2(0.044, 0.316), Vector2(0.06, 0.32), Vector2(0.18, 0.32), Vector2(0.20, 0.30), Vector2(0.21, 0.27),
]

## Sweep a profile along a polyline path (XZ points at y=0). The profile's +x
## points to the path's left-hand normal * side. Appends into st.
static func sweep(st: SurfaceTool, path: PackedVector3Array, profile: Array, arris: Array, faces: Array, side: float, painted: PackedFloat32Array, phase: float = 0.0, along0: float = 0.0) -> void:
	var n := path.size()
	if n < 2:
		return
	var along := PackedFloat32Array()
	along.resize(n)
	var acc := along0
	for i in n:
		if i > 0:
			acc += path[i].distance_to(path[i - 1])
		along[i] = acc
	var plen := PackedFloat32Array()
	plen.resize(profile.size())
	var pa := 0.0
	for j in profile.size():
		if j > 0:
			pa += (profile[j] as Vector2).distance_to(profile[j - 1])
		plen[j] = pa
	var outs: Array[Vector3] = []
	for i in n:
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == n - 1:
			t = path[n - 1] - path[n - 2]
		else:
			t = (path[i + 1] - path[i - 1])
		t.y = 0.0
		t = t.normalized()
		outs.append(Vector3(-t.z, 0.0, t.x) * side)
	for i in n - 1:
		for j in profile.size() - 1:
			var q := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]
			if side < 0.0:
				q = [[i, j], [i + 1, j + 1], [i + 1, j], [i, j], [i, j + 1], [i + 1, j + 1]]
			for v in q:
				var a: int = v[0]
				var b: int = v[1]
				var pr: Vector2 = profile[b]
				var o: Vector3 = outs[a]
				# face normal from the profile segment (flat shading per band)
				var seg: Vector2 = (profile[j + 1] as Vector2) - (profile[j] as Vector2)
				var pn := Vector2(-seg.y, seg.x).normalized()
				# rounded arris gets a smooth normal from neighbouring segments
				if float(arris[b]) > 0.3 and b > 0 and b < profile.size() - 1:
					var s0: Vector2 = (profile[b] as Vector2) - (profile[b - 1] as Vector2)
					var s1: Vector2 = (profile[b + 1] as Vector2) - (profile[b] as Vector2)
					pn = (Vector2(-s0.y, s0.x).normalized() + Vector2(-s1.y, s1.x).normalized()).normalized()
				var nrm := (o * pn.x + Vector3.UP * pn.y).normalized()
				# profile x is measured from the road toward the back: the road
				# face looks back along -out
				st.set_normal(nrm)
				st.set_color(Color(painted[a] if painted.size() > a else 0.0, phase, 0.0, 1.0))
				st.set_uv(Vector2(along[a], plen[b]))
				st.set_uv2(Vector2(float(arris[b]), float(faces[b])))
				st.add_vertex(path[a] + o * pr.x + Vector3.UP * pr.y)

static func _kerb_mi(root: Node3D, st: SurfaceTool, name: String) -> MeshInstance3D:
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = kerb_material()
	mi.set_meta("nearfield", true)
	root.add_child(mi)
	return mi

## Road kerbs on both sides of every carriageway, broken at junction mouths,
## one mesh per 160 m cell.
static func build_road_kerbs(root: Node3D) -> void:
	var cells := {}
	for axis in 2:
		var lines: Array[float] = X_LINES if axis == 0 else Z_LINES
		var crosses: Array[float] = Z_LINES if axis == 0 else X_LINES
		for line in lines:
			for side: float in [-1.0, 1.0]:
				var starts: Array[float] = [-380.0]
				var ends: Array[float] = []
				for c in crosses:
					ends.append(c - ROAD_HALF - 0.3)
					starts.append(c + ROAD_HALF + 0.3)
				ends.append(380.0)
				for k in starts.size():
					var a := starts[k]
					var b := ends[k]
					if b - a < 1.0:
						continue
					var key := Vector2i(floori((line + 400.0) / 160.0), floori(((a + b) * 0.5 + 400.0) / 160.0)) if axis == 0 else Vector2i(floori(((a + b) * 0.5 + 400.0) / 160.0), floori((line + 400.0) / 160.0))
					if not cells.has(key):
						var st0 := SurfaceTool.new()
						st0.begin(Mesh.PRIMITIVE_TRIANGLES)
						cells[key] = st0
					var st: SurfaceTool = cells[key]
					var path := PackedVector3Array()
					var steps := int(ceil((b - a) / 8.0))
					for s in steps + 1:
						var t := lerpf(a, b, float(s) / steps)
						var lat := line + side * ROAD_HALF
						path.append(Vector3(lat, 0.0, t) if axis == 0 else Vector3(t, 0.0, lat))
					# profile +x points away from the road centre
					var sd := side if axis == 0 else -side
					var paint := PackedFloat32Array()
					sweep(st, path, KERB_PROFILE, KERB_ARRIS, KERB_FACE, -sd, paint)
					_count("road_kerb_m", int(b - a))
	for key in cells:
		_kerb_mi(root, cells[key], "NearfieldKerb_%d_%d" % [key.x, key.y])

# --------------------------------------------------------------- medians
## A median island: two long kerbs joined by bull-nosed painted ends, a
## mulched bed, dense shrubs and a keep-left sign on each nose.
## centre: island centre at road level; along_z: island runs along z.
static func build_median(root: Node3D, centre: Vector3, along_z: bool, span: float, soil_mat: Material, shrubs: Dictionary, signs: Array, rng: RandomNumberGenerator) -> void:
	var half_w := 0.8
	var ax := Vector3(0, 0, 1) if along_z else Vector3(1, 0, 0)
	var lat := Vector3(1, 0, 0) if along_z else Vector3(0, 0, 1)
	var straight := span * 0.5 - half_w
	# closed outline: right side forward, nose arc, left side back, nose arc
	var path := PackedVector3Array()
	var painted := PackedFloat32Array()
	var steps := int(ceil(straight * 2.0 / 6.0))
	for s in steps + 1:
		var t := lerpf(-straight, straight, float(s) / steps)
		path.append(centre + ax * t + lat * half_w)
		painted.append(1.0 if absf(t) > straight - 2.0 else 0.0)
	for k in range(1, 17):
		var a := PI * 0.5 - PI * float(k) / 16.0
		path.append(centre + ax * (straight + cos(a) * half_w) + lat * (sin(a) * half_w))
		painted.append(1.0)
	for s in range(1, steps + 1):
		var t := lerpf(straight, -straight, float(s) / steps)
		path.append(centre + ax * t - lat * half_w)
		painted.append(1.0 if absf(t) > straight - 2.0 else 0.0)
	for k in range(1, 17):
		var a := -PI * 0.5 - PI * float(k) / 16.0
		path.append(centre + ax * (-straight + cos(a) * half_w) + lat * (sin(a) * half_w))
		painted.append(1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the outline runs clockwise seen from above when along_z, so flip
	sweep(st, _inset(path, centre, ax, lat, straight, half_w), MEDIAN_PROFILE, KERB_ARRIS, KERB_FACE, 1.0 if along_z else -1.0, painted, 0.25)
	var mi := _kerb_mi(root, st, "NearfieldMedianKerb")
	mi.position = Vector3.ZERO
	# bed: soil top inside the kerb, a hard painted-concrete nose deck at ends
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.24, 0.28, straight * 2.0 - 2.4) if along_z else Vector3(straight * 2.0 - 2.4, 0.28, 1.24)
	bed.mesh = bm
	bed.material_override = soil_mat
	bed.position = centre + Vector3(0, 0.15, 0)
	root.add_child(bed)
	for e: float in [-1.0, 1.0]:
		var nose := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = 0.62
		nm.bottom_radius = 0.62
		nm.height = 0.3
		nm.radial_segments = 24
		nose.mesh = nm
		nose.material_override = pavers_mat()
		nose.position = centre + ax * e * straight + Vector3(0, 0.155, 0)
		root.add_child(nose)
		var deck := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(1.24, 0.3, 1.2) if along_z else Vector3(1.2, 0.3, 1.24)
		deck.mesh = dm
		deck.material_override = pavers_mat()
		deck.position = centre + ax * e * (straight - 0.6) + Vector3(0, 0.155, 0)
		root.add_child(deck)
		# keep-left sign faces oncoming traffic on the nose
		var facing := ax * e
		signs.append({"pos": centre + ax * e * (straight - 0.15), "face": facing, "cell": 0, "h": 1.45, "size": 0.62})
		# back-to-back twin plate: an island sign reads from both approaches
		# (critic: blank placard backs read as blockout)
		signs.append({"pos": centre + ax * e * (straight - 0.15), "face": -facing, "cell": 0, "h": 1.45, "size": 0.62, "nopost": true})
		_count("median_nose")
	# planting: designed drifts (3-9 m) of one species, two staggered rows
	# plus a sparse centre row, kept off the nose decks. Photo cards when the
	# generated atlas is present, else the authored leaf-card clumps.
	var cards := cards_available()
	var t := -straight + 1.3
	var drift_left := 0.0
	var kind := "ixora"
	while t < straight - 1.3:
		if drift_left <= 0.0:
			var roll := rng.randf()
			if cards:
				kind = "fern" if roll < 0.30 else ("ixora" if roll < 0.58 else ("croton" if roll < 0.82 else "mondo"))
			else:
				kind = "ixora" if roll < 0.32 else ("broad" if roll < 0.7 else "hedge")
			drift_left = rng.randf_range(3.0, 9.0)
		var rows: Array[float] = [-0.32, 0.32]
		if rng.randf() < 0.35:
			rows.append(0.0)
		for row: float in rows:
			if rng.randf() < 0.06:
				continue
			var p := centre + ax * (t + rng.randf_range(-0.15, 0.15) + (0.22 if row > 0.1 else 0.0)) + lat * (row + rng.randf_range(-0.07, 0.07)) + Vector3(0, 0.29, 0)
			var sc := rng.randf_range(0.82, 1.12)
			var hs := sc
			if cards:
				match kind:
					"mondo": sc = rng.randf_range(0.62, 0.80); hs = sc * rng.randf_range(0.9, 1.1)
					"fern": sc = rng.randf_range(0.72, 0.92); hs = sc
					"croton": sc = rng.randf_range(0.70, 0.92); hs = sc * rng.randf_range(0.9, 1.05)
					_: sc = rng.randf_range(0.70, 0.90); hs = sc * rng.randf_range(0.88, 1.02)
				p.y -= 0.03
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, hs, sc)), p)
			var tint := Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.16))
			tint = tint.lerp(Color(1.04, 1.0, 0.86), rng.randf() * 0.3)
			if not shrubs.has(kind):
				shrubs[kind] = []
			shrubs[kind].append([xf, tint])
			_count("median_shrub")
		var step := rng.randf_range(0.48, 0.62) if cards else rng.randf_range(0.55, 0.75)
		t += step
		drift_left -= step

## The sweep's profile foot sits on the outline; nothing to inset.
static func _inset(path: PackedVector3Array, _c: Vector3, _ax: Vector3, _lat: Vector3, _s: float, _w: float) -> PackedVector3Array:
	return path

# --------------------------------------------------------------- shrubs
## Photo plant clump: `cards` vertical cards crossed about the stem, each
## textured with one atlas cell (bottom edge on the ground, 1 m tall and wide
## at scale 1), emitted in both windings so cull_back keeps one consistent
## hemispherical normal per side. A low inner skirt card fills the base.
const CARD_CELL := {"mondo": 0, "ixora": 1, "croton": 2, "fern": 3}

static func card_mesh(kind: String) -> Mesh:
	var key := "card_" + kind
	if _cache.has(key):
		return _cache[key]
	var cell: int = CARD_CELL.get(kind, 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u0 := Vector2((cell % 2) * 0.5, (cell / 2) * 0.5)
	var pivot := Vector3(0, -0.45, 0)
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind) & 0xffff
	var cards := 3 if kind != "mondo" else 4
	for k in cards:
		var a := PI * float(k) / cards + r.randf_range(-0.12, 0.12)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var w := 0.5 * r.randf_range(0.92, 1.06)
		var h := r.randf_range(0.94, 1.04)
		var tilt := Vector3(-dir.z, 0.0, dir.x) * r.randf_range(-0.06, 0.06)
		var vs := [-dir * w + Vector3(0, -0.03, 0), dir * w + Vector3(0, -0.03, 0), dir * w + Vector3(0, h, 0) + tilt, -dir * w + Vector3(0, h, 0) + tilt]
		var flip := k % 2 == 1
		var uvs := [Vector2(0.006, 0.494), Vector2(0.494, 0.494), Vector2(0.494, 0.006), Vector2(0.006, 0.006)]
		for side in 2:
			var order := [0, 1, 2, 0, 2, 3] if side == 0 else [0, 2, 1, 0, 3, 2]
			for idx in order:
				var v: Vector3 = vs[idx]
				var uv: Vector2 = uvs[idx]
				if flip:
					uv.x = 0.5 - uv.x
				var nrm := (v - pivot).normalized()
				nrm = (nrm + Vector3.UP * 0.25).normalized()
				st.set_normal(nrm)
				var occ := clampf(0.30 + 0.75 * (v.y / h), 0.3, 1.0)
				st.set_color(Color(1, 1, 1, occ))
				st.set_uv(u0 + uv)
				st.add_vertex(v)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh

## A dense shrub clump of crossed leaf cards (atlas cells: 0 broad dark,
## 1 broad light, 2 small hedge, 3 flowering). Normals are spherical from the
## clump centre so the mass shades like a canopy; vertex colour carries an
## occlusion term (dark core and underside, lit crown).
static func shrub_mesh(kind: String) -> Mesh:
	var key := "shrub_" + kind
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind) & 0xffff
	var cells: Array[int] = [0, 1, 0, 1]
	var radius := Vector3(0.52, 0.50, 0.52)
	var n := 46
	match kind:
		"hedge":
			cells = [2, 2, 0, 2]
			radius = Vector3(0.50, 0.46, 0.50)
			n = 52
		"ixora":
			cells = [2, 3, 3, 0]
			radius = Vector3(0.48, 0.50, 0.48)
			n = 48
	var centre := Vector3(0, radius.y * 0.42, 0)
	for k in n:
		# points biased to the outer shell, more cards in the crown
		var dir := Vector3(r.randf_range(-1, 1), r.randf_range(-0.25, 1.0), r.randf_range(-1, 1)).normalized()
		var depth := pow(r.randf(), 0.45)
		var p := centre + dir * radius * depth
		p.y = maxf(p.y, 0.02)
		var size := r.randf_range(0.32, 0.46) * (0.8 + 0.3 * depth)
		var cell: int = cells[r.randi() % cells.size()]
		# card faces outward and up, random roll
		var nrm := (dir + Vector3.UP * 0.6).normalized()
		var tang := nrm.cross(Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized()).normalized()
		if tang.length() < 0.1:
			tang = Vector3.RIGHT
		var bit := nrm.cross(tang).normalized()
		var uv0 := Vector2((cell % 2) * 0.5, (cell / 2) * 0.5)
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		var verts: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		var aos: Array[float] = []
		for c: Vector2 in corners:
			var v := p + (tang * c.x + bit * c.y) * size * 0.5
			v.y = maxf(v.y, -0.04)
			verts.append(v)
			uvs.append(uv0 + (c * 0.5 + Vector2(0.5, 0.5)) * 0.5)
			var rel := (v - centre) / radius
			var outer := clampf(rel.length(), 0.0, 1.0)
			var up := clampf(v.y / (radius.y * 1.4), 0.0, 1.0)
			aos.append(clampf(0.28 + 0.45 * outer + 0.40 * up, 0.25, 1.0))
		for idx in [0, 1, 2, 0, 2, 3]:
			var v: Vector3 = verts[idx]
			var sn := ((v - centre * 0.6).normalized() * 0.75 + Vector3.UP * 0.35).normalized()
			st.set_normal(sn)
			st.set_color(Color(aos[idx], aos[idx], aos[idx], 1.0))
			st.set_uv(uvs[idx])
			st.add_vertex(v)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh

static func emit_shrubs(root: Node3D, shrubs: Dictionary) -> void:
	for kind in shrubs:
		var cells := {}
		for item in shrubs[kind]:
			var xf: Transform3D = item[0]
			var c := Vector2i(floori((xf.origin.x + 400.0) / 160.0), floori((xf.origin.z + 400.0) / 160.0))
			if not cells.has(c):
				cells[c] = []
			cells[c].append(item)
		for c in cells:
			var arr: Array = cells[c]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			var cards := cards_available() and CARD_CELL.has(kind)
			mm.mesh = card_mesh(kind) if cards else shrub_mesh(kind)
			mm.instance_count = arr.size()
			for i in arr.size():
				mm.set_instance_transform(i, arr[i][0])
				mm.set_instance_color(i, arr[i][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "NearfieldShrub_%s_%d_%d" % [kind, c.x, c.y]
			mmi.multimesh = mm
			mmi.material_override = card_material() if cards else leaf_material()
			mmi.visibility_range_end = 260.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(mmi)

## One standalone shrub (planters, shelters).
static func shrub_instance(root: Node3D, pos: Vector3, scale: float = 1.0, kind: String = "broad") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if cards_available() and CARD_CELL.has(kind):
		mi.mesh = card_mesh(kind)
		mi.material_override = card_material()
		pos.y -= 0.12
	else:
		mi.mesh = shrub_mesh(kind)
		mi.material_override = leaf_material()
	mi.position = pos
	mi.scale = Vector3.ONE * scale
	mi.set_meta("nearfield", true)
	root.add_child(mi)
	return mi

# ---------------------------------------------------------------- signs
## Sign plate: a square card (alpha-cut to the pictogram's shape) with a
## galvanised back, on a post with clamp bands. cell indexes the atlas:
## 0 keep-left, 1 no parking, 2 no entry, 3 crossing, 4 bus stop,
## 5 no stopping, 6 speed 40, 7 school zone.
static func plate_mesh() -> Mesh:
	if _cache.has("plate"):
		return _cache["plate"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := [Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	# front (+z), back (-z) offset 6 mm
	# Godot front faces wind clockwise on screen (wave D had both faces
	# reversed, so the galvanised back showed through from the front)
	for idx in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.BACK)
		st.set_uv(uv[idx])
		st.set_uv2(Vector2(1, 0))
		st.add_vertex(q[idx] + Vector3(0, 0, 0.003))
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.FORWARD)
		st.set_uv(uv[idx])
		st.set_uv2(Vector2(0, 0))
		st.add_vertex(q[idx] - Vector3(0, 0, 0.003))
	var m := st.commit()
	_cache["plate"] = m
	return m

static func post_mesh() -> Mesh:
	if _cache.has("post"):
		return _cache["post"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := CylinderMesh.new()
	c.top_radius = 0.038
	c.bottom_radius = 0.038
	c.height = 1.0
	c.radial_segments = 14
	c.rings = 1
	st.append_from(c, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	var cap := SphereMesh.new()
	cap.radius = 0.04
	cap.height = 0.05
	cap.radial_segments = 12
	cap.rings = 4
	cap.is_hemisphere = true
	st.append_from(cap, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	st.generate_normals()
	var m := st.commit()
	_cache["post"] = m
	return m

## signs: [{pos, face (Vector3 the plate faces), cell, h (plate centre height
## above pos), size}] -> batched posts, clamps and plates.
static func emit_signs(root: Node3D, signs: Array) -> void:
	if signs.is_empty():
		return
	var posts: Array[Transform3D] = []
	var clamps: Array[Transform3D] = []
	var plates: Array[Transform3D] = []
	var cellv: Array[int] = []
	for s in signs:
		var pos: Vector3 = s["pos"]
		var face: Vector3 = (s["face"] as Vector3).normalized()
		var h: float = s["h"]
		var sz: float = s["size"]
		var top := h + sz * 0.5 + 0.02
		var b := Basis.looking_at(-face, Vector3.UP)   # local +z faces `face`
		if not s.get("nopost", false):
			posts.append(Transform3D(Basis.from_scale(Vector3(1, top, 1)), pos))
			for dy: float in [-0.28, 0.28]:
				clamps.append(Transform3D(b * Basis.from_scale(Vector3(0.10, 0.035, 0.09)), pos + Vector3(0, h + dy * sz, 0) + face * 0.0))
		plates.append(Transform3D(b * Basis.from_scale(Vector3(sz, sz, 1.0)), pos + Vector3(0, h, 0) + face * 0.05))
		cellv.append(int(s["cell"]))
		_count("sign_plate")
	_mm(root, "NearfieldSignPosts", post_mesh(), galvanised(), posts)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_mm(root, "NearfieldSignClamps", box, galvanised(), clamps)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plate_mesh()
	mm.instance_count = plates.size()
	for i in plates.size():
		mm.set_instance_transform(i, plates[i])
		mm.set_instance_custom_data(i, Color(float(cellv[i]), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "NearfieldSignPlates"
	mmi.multimesh = mm
	mmi.material_override = sign_material()
	root.add_child(mmi)

static func _mm(root: Node3D, name: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D], shadow: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi

# ------------------------------------------------------- two-wheelers
## Multi-surface models: surface 0 paint (takes the instance colour),
## 1 rubber, 2 bright metal, 3 seat/black plastic, 4 lamps.
static func two_wheeler_mesh(motor: bool) -> Mesh:
	var key := "scooter" if motor else "bike"
	if _cache.has(key):
		return _cache[key]
	var sts: Array[SurfaceTool] = []
	for i in 5:
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(s)
	var wb := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))   # torus axis -> z
	var tube := func(st: SurfaceTool, a: Vector3, b: Vector3, rad: float, seg: int = 8) -> void:
		var c := CylinderMesh.new()
		c.top_radius = rad
		c.bottom_radius = rad
		c.height = 1.0
		c.radial_segments = seg
		c.rings = 1
		c.cap_top = false
		c.cap_bottom = false
		var d := b - a
		var y := d.normalized()
		var x := y.cross(Vector3.BACK)
		if x.length() < 0.1:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		var z := x.cross(y)
		st.append_from(c, 0, Transform3D(Basis(x, y * d.length(), z), (a + b) * 0.5))
	var blob := func(st: SurfaceTool, c: Vector3, s: Vector3, rot: Basis = Basis.IDENTITY) -> void:
		var sp := SphereMesh.new()
		sp.radius = 0.5
		sp.height = 1.0
		sp.radial_segments = 16
		sp.rings = 8
		st.append_from(sp, 0, Transform3D(rot * Basis.from_scale(s), c))
	if not motor:
		var wr := 0.335
		for wx: float in [-0.53, 0.53]:
			var tyre := TorusMesh.new()
			tyre.inner_radius = 0.30
			tyre.outer_radius = 0.34
			tyre.rings = 28
			tyre.ring_segments = 8
			sts[1].append_from(tyre, 0, Transform3D(wb, Vector3(wx, wr, 0)))
			var rim := TorusMesh.new()
			rim.inner_radius = 0.285
			rim.outer_radius = 0.302
			rim.rings = 28
			rim.ring_segments = 4
			sts[2].append_from(rim, 0, Transform3D(wb, Vector3(wx, wr, 0)))
			for k in 16:
				var a := TAU * k / 16.0
				var side := 0.012 if k % 2 == 0 else -0.012
				tube.call(sts[2], Vector3(wx, wr, side * 2.0), Vector3(wx + cos(a) * 0.29, wr + sin(a) * 0.29, 0.0), 0.0035, 4)
			tube.call(sts[2], Vector3(wx, wr, -0.05), Vector3(wx, wr, 0.05), 0.018, 8)   # hub
		var rear := Vector3(-0.53, wr, 0)
		var front := Vector3(0.53, wr, 0)
		var crank := Vector3(-0.04, 0.29, 0)
		var seat := Vector3(-0.21, 0.80, 0)
		var head := Vector3(0.40, 0.84, 0)
		var head_low := Vector3(0.43, 0.70, 0)
		for side: float in [-0.045, 0.045]:
			tube.call(sts[0], rear + Vector3(0, 0, side), crank + Vector3(0, 0, side * 0.4), 0.011)   # chainstays
			tube.call(sts[0], rear + Vector3(0, 0, side), seat + Vector3(0.02, -0.06, side * 0.3), 0.010)   # seatstays
			tube.call(sts[0], head_low + Vector3(0, 0, side * 0.6), front + Vector3(0, 0, side), 0.012)   # fork legs
		tube.call(sts[0], crank, seat + Vector3(0.02, -0.06, 0), 0.017)   # seat tube
		tube.call(sts[0], crank, head_low, 0.020)   # down tube
		tube.call(sts[0], seat + Vector3(0.02, -0.08, 0), head + Vector3(0, -0.02, 0), 0.016)   # top tube
		tube.call(sts[0], head_low, head + Vector3(-0.01, 0.06, 0), 0.022)   # head tube
		tube.call(sts[2], seat + Vector3(0.02, -0.06, 0), seat, 0.012)   # seat post
		blob.call(sts[3], seat + Vector3(-0.02, 0.025, 0), Vector3(0.27, 0.06, 0.13))   # saddle
		tube.call(sts[2], head + Vector3(-0.01, 0.06, 0), head + Vector3(-0.06, 0.18, 0), 0.012)   # stem
		tube.call(sts[2], head + Vector3(-0.06, 0.18, -0.27), head + Vector3(-0.06, 0.18, 0.27), 0.011)   # bars
		for gz: float in [-0.27, 0.27]:
			tube.call(sts[3], head + Vector3(-0.06, 0.18, gz * 0.75), head + Vector3(-0.06, 0.18, gz * 1.08), 0.016)   # grips
		var ring := CylinderMesh.new()
		ring.top_radius = 0.09
		ring.bottom_radius = 0.09
		ring.height = 0.006
		ring.radial_segments = 18
		sts[2].append_from(ring, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), crank + Vector3(0, 0, 0.06)))   # chainring
		tube.call(sts[2], crank + Vector3(0.0, 0, 0.07), crank + Vector3(0.08, -0.12, 0.10), 0.01)   # crank arm
		tube.call(sts[2], crank + Vector3(0.0, 0, -0.07), crank + Vector3(-0.08, 0.12, -0.10), 0.01)
		sts[3].append_from(_box(), 0, Transform3D(Basis.from_scale(Vector3(0.09, 0.02, 0.10)), crank + Vector3(0.08, -0.12, 0.14)))   # pedals
		sts[3].append_from(_box(), 0, Transform3D(Basis.from_scale(Vector3(0.09, 0.02, 0.10)), crank + Vector3(-0.08, 0.12, -0.14)))
		tube.call(sts[2], rear + Vector3(0.02, 0, 0), crank + Vector3(0, 0, 0.06), 0.004, 4)   # chain
		# shared-bike basket and mudguards
		var bk := head + Vector3(0.14, -0.02, 0)
		for e in [Vector3(0.0, 0, -0.16), Vector3(0.0, 0, 0.16)]:
			tube.call(sts[0], bk + e + Vector3(-0.08, 0, 0), bk + e + Vector3(0.18, 0, 0), 0.006, 4)
			tube.call(sts[0], bk + e + Vector3(-0.08, 0.17, 0), bk + e + Vector3(0.18, 0.17, 0), 0.006, 4)
		for xx: float in [-0.08, 0.05, 0.18]:
			tube.call(sts[0], bk + Vector3(xx, 0, -0.16), bk + Vector3(xx, 0, 0.16), 0.006, 4)
			tube.call(sts[0], bk + Vector3(xx, 0.17, -0.16), bk + Vector3(xx, 0.17, 0.16), 0.006, 4)
			for zz: float in [-0.16, 0.16]:
				tube.call(sts[0], bk + Vector3(xx, 0, zz), bk + Vector3(xx, 0.17, zz), 0.006, 4)
		for wx: float in [-0.53, 0.53]:
			var prev := Vector3.ZERO
			for k in 9:
				var a := lerpf(0.25, 2.2, k / 8.0) if wx > 0 else lerpf(0.9, 2.9, k / 8.0)
				var pt := Vector3(wx + cos(a) * 0.37, wr + sin(a) * 0.37, 0)
				if k > 0:
					tube.call(sts[0], prev, pt, 0.022, 6)
				prev = pt
		blob.call(sts[4], head + Vector3(0.06, -0.06, 0), Vector3(0.05, 0.05, 0.05))   # lamp
		tube.call(sts[2], crank + Vector3(-0.08, 0, 0.05), Vector3(-0.2, 0.0, 0.18), 0.008, 4)   # kickstand
	else:
		var wr := 0.27
		for wx: float in [-0.62, 0.62]:
			var tyre := TorusMesh.new()
			tyre.inner_radius = 0.17
			tyre.outer_radius = 0.27
			tyre.rings = 26
			tyre.ring_segments = 10
			sts[1].append_from(tyre, 0, Transform3D(wb, Vector3(wx, wr, 0)))
			var hub := CylinderMesh.new()
			hub.top_radius = 0.17
			hub.bottom_radius = 0.17
			hub.height = 0.09
			hub.radial_segments = 20
			sts[2].append_from(hub, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(wx, wr, 0)))
		# rear cowl over the engine, floorboard, leg shield, front fender
		blob.call(sts[0], Vector3(-0.38, 0.60, 0), Vector3(0.86, 0.42, 0.40))
		blob.call(sts[0], Vector3(-0.50, 0.50, 0), Vector3(0.62, 0.34, 0.36))
		sts[3].append_from(_box(), 0, Transform3D(Basis.from_scale(Vector3(0.52, 0.06, 0.32)), Vector3(0.12, 0.33, 0)))   # floor mat
		blob.call(sts[0], Vector3(0.12, 0.29, 0), Vector3(0.62, 0.12, 0.36))   # floor pan
		blob.call(sts[0], Vector3(0.44, 0.66, 0), Vector3(0.20, 0.82, 0.44), Basis(Vector3.BACK, -0.28))   # leg shield
		blob.call(sts[0], Vector3(0.64, 0.50, 0), Vector3(0.40, 0.14, 0.20), Basis(Vector3.BACK, -0.35))   # front fender
		blob.call(sts[3], Vector3(-0.30, 0.86, 0), Vector3(0.74, 0.13, 0.32))   # seat
		tube.call(sts[2], Vector3(0.50, 0.62, 0), Vector3(0.56, 1.02, 0), 0.03)   # steering column
		blob.call(sts[0], Vector3(0.56, 1.06, 0), Vector3(0.22, 0.14, 0.36))   # headset cowl
		tube.call(sts[2], Vector3(0.54, 1.08, -0.36), Vector3(0.54, 1.08, 0.36), 0.013)   # bars
		for gz: float in [-0.36, 0.36]:
			tube.call(sts[3], Vector3(0.54, 1.08, gz * 0.72), Vector3(0.54, 1.08, gz * 1.05), 0.02)
			tube.call(sts[2], Vector3(0.53, 1.10, gz * 0.6), Vector3(0.50, 1.30, gz * 0.75), 0.006, 4)   # mirror stalks
			blob.call(sts[3], Vector3(0.50, 1.32, gz * 0.78), Vector3(0.02, 0.08, 0.11))   # mirrors
		blob.call(sts[4], Vector3(0.67, 1.06, 0), Vector3(0.04, 0.10, 0.12))   # headlamp
		blob.call(sts[4], Vector3(-0.83, 0.66, 0), Vector3(0.04, 0.06, 0.16))   # tail lamp
		tube.call(sts[2], Vector3(-0.30, 0.36, 0.16), Vector3(-0.85, 0.42, 0.18), 0.045, 10)   # exhaust
		sts[3].append_from(_box(), 0, Transform3D(Basis.from_scale(Vector3(0.36, 0.05, 0.30)), Vector3(-0.78, 0.70, 0)))   # rear rack
		tube.call(sts[2], Vector3(-0.10, 0.22, 0.12), Vector3(-0.22, 0.0, 0.26), 0.012, 4)   # side stand
	var mesh := ArrayMesh.new()
	var mats := [
		_std(Color.WHITE, 0.32 if motor else 0.45, 0.25 if motor else 0.35, true),
		_std(Color(0.035, 0.035, 0.038), 0.82),
		_std(Color(0.72, 0.73, 0.74), 0.28, 0.9),
		_std(Color(0.05, 0.05, 0.055), 0.55),
		_std(Color(0.95, 0.92, 0.85), 0.2),
	]
	(mats[0] as StandardMaterial3D).clearcoat_enabled = motor
	(mats[4] as StandardMaterial3D).emission_enabled = true
	(mats[4] as StandardMaterial3D).emission = Color(0.6, 0.55, 0.5)
	(mats[4] as StandardMaterial3D).emission_energy_multiplier = 0.15
	for i in sts.size():
		sts[i].generate_normals()
		sts[i].commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[i])
	_cache[key] = mesh
	return mesh

static func _box() -> BoxMesh:
	if not _cache.has("unitbox"):
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		_cache["unitbox"] = b
	return _cache["unitbox"]

## Collision for parked two-wheelers (layer 1, like other street furniture),
## one StaticBody3D per 160 m cell.
static func two_wheeler_collision(root: Node3D, xforms: Array, motor: bool) -> void:
	var cells := {}
	for xf: Transform3D in xforms:
		var c := Vector2i(floori((xf.origin.x + 400.0) / 160.0), floori((xf.origin.z + 400.0) / 160.0))
		if not cells.has(c):
			var body := StaticBody3D.new()
			body.name = "NearfieldTwoWheelerBody_%s_%d_%d" % ["s" if motor else "b", c.x, c.y]
			body.collision_layer = 1
			body.collision_mask = 0
			root.add_child(body)
			cells[c] = body
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.75, 1.05, 0.62) if motor else Vector3(1.70, 1.0, 0.45)
		shape.shape = bs
		var flat := Basis(Vector3.UP, atan2(-xf.basis.x.z, xf.basis.x.x))
		shape.transform = Transform3D(flat, xf.origin + Vector3(0, bs.size.y * 0.5 + 0.02, 0))
		(cells[c] as StaticBody3D).add_child(shape)
		_count("scooter_collider" if motor else "bike_collider")

# ------------------------------------------------------- canvas awning
## A shopfront awning: sagging canvas sloping 12 deg out from the wall over
## a 1.9 m projection, a 0.27 m scalloped valance on the front bar, steel
## front bar and two drop arms back to the facade. centre = old slab centre,
## yaw = shophouse yaw (outward = Basis(UP, yaw) * -Z).
static func canvas_awning(root: Node3D, centre: Vector3, yaw: float, colour: Color, seed_i: int) -> void:
	var b := Basis(Vector3.UP, yaw)
	var along := b * Vector3.RIGHT
	var out := b * Vector3(0, 0, -1)
	var width := 7.4
	var depth := 1.9
	var slope := tan(deg_to_rad(12.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 24
	var nv := 6
	var pt := func(i: int, j: int) -> Vector3:
		var x := (float(i) / nu - 0.5) * width
		var d := float(j) / nv * depth
		var sag := 0.07 * sin(PI * float(j) / nv) * (0.7 + 0.3 * absf(sin(PI * float(i) / nu * 4.0)))
		return centre + along * x + out * (d - depth * 0.5) + Vector3.UP * (slope * depth * 0.5 - slope * d - sag)
	for i in nu:
		for j in nv:
			var a: Vector3 = pt.call(i, j)
			var bb: Vector3 = pt.call(i + 1, j)
			var c: Vector3 = pt.call(i + 1, j + 1)
			var d: Vector3 = pt.call(i, j + 1)
			var n := (bb - a).cross(d - a).normalized()
			if n.y < 0.0:
				n = -n
			var uvs := [Vector2(float(i) / nu * width, float(j) / nv), Vector2(float(i + 1) / nu * width, float(j) / nv), Vector2(float(i + 1) / nu * width, float(j + 1) / nv), Vector2(float(i) / nu * width, float(j + 1) / nv)]
			var vs := [a, bb, c, d]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(n)
				st.set_uv(uvs[idx])
				st.add_vertex(vs[idx])
	# valance hanging from the front edge
	for i in nu:
		var a: Vector3 = pt.call(i, nv)
		var bb: Vector3 = pt.call(i + 1, nv)
		var drop := Vector3.UP * -0.30
		var uvs := [Vector2(float(i) / nu * width, 1.0), Vector2(float(i + 1) / nu * width, 1.0), Vector2(float(i + 1) / nu * width, 1.3), Vector2(float(i) / nu * width, 1.3)]
		var vs := [a, bb, bb + drop, a + drop]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(out)
			st.set_uv(uvs[idx])
			st.add_vertex(vs[idx])
	var mi := MeshInstance3D.new()
	mi.name = "NearfieldAwning"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + "canvas_awning.gdshader")
	var c2 := colour.darkened(0.22)
	m.set_shader_parameter("stripe_col", Vector3(c2.r, c2.g, c2.b))
	m.set_shader_parameter("plain", 1.0 if seed_i % 3 == 0 else 0.0)
	mi.material_override = m
	mi.set_meta("nearfield", true)
	root.add_child(mi)
	# steel front bar and drop arms
	var p0: Vector3 = pt.call(0, nv)
	var p1: Vector3 = pt.call(nu, nv)
	var bars := [[p0, p1, 0.022]]
	for e: float in [0.0, 1.0]:
		var wall: Vector3 = pt.call(int(e * nu), 0) + Vector3.UP * -0.55
		var front: Vector3 = pt.call(int(e * nu), nv)
		bars.append([wall, front, 0.016])
	for bar in bars:
		var a: Vector3 = bar[0]
		var c: Vector3 = bar[1]
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = bar[2]
		cm.bottom_radius = bar[2]
		cm.height = a.distance_to(c)
		cm.radial_segments = 8
		cm.rings = 1
		cyl.mesh = cm
		cyl.material_override = galvanised()
		var y := (c - a).normalized()
		var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
		cyl.transform = Transform3D(Basis(x, y, x.cross(y)), (a + c) * 0.5)
		cyl.set_meta("nearfield", true)
		root.add_child(cyl)
	_count("awning")

# ----------------------------------------------------------- bus shelter
## Framed bus shelter: twin posts, cantilevered roof with fascia, framed
## clear rear glazing with a frit band, perforated bench, a lit advert
## panel and a bus-stop pole. Collision on posts, rear panel and bench.
static func bus_shelter(root: Node3D, pos: Vector3, signs: Array) -> void:
	var frame := _std(Color(0.20, 0.22, 0.23), 0.45, 0.6)
	var roof := _std(Color(0.30, 0.32, 0.33), 0.5, 0.5)
	var fascia := _std(Color(0.10, 0.28, 0.42), 0.5, 0.3)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.80, 0.86, 0.86, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.metallic = 0.1
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frit := _std(Color(0.85, 0.86, 0.84), 0.6)
	var bench := _std(Color(0.55, 0.57, 0.58), 0.4, 0.8)
	var ad := StandardMaterial3D.new()
	ad.albedo_color = Color(0.95, 0.62, 0.30)
	ad.emission_enabled = true
	ad.emission = Color(1.0, 0.72, 0.42)
	ad.emission_energy_multiplier = 0.55
	ad.roughness = 0.15
	var parts := [
		# [size, offset, material]
		[Vector3(0.10, 2.65, 0.10), Vector3(-1.7, 1.325, -0.62), frame],
		[Vector3(0.10, 2.65, 0.10), Vector3(1.7, 1.325, -0.62), frame],
		[Vector3(4.2, 0.08, 1.9), Vector3(0, 2.68, 0.05), roof],
		[Vector3(4.24, 0.22, 0.06), Vector3(0, 2.62, 1.0), fascia],
		[Vector3(4.24, 0.22, 0.06), Vector3(0, 2.62, -0.9), frame],
		[Vector3(0.10, 0.10, 1.9), Vector3(-1.7, 2.58, 0.05), frame],
		[Vector3(0.10, 0.10, 1.9), Vector3(1.7, 2.58, 0.05), frame],
		[Vector3(3.3, 1.95, 0.02), Vector3(0, 1.30, -0.66), glass],
		[Vector3(3.3, 0.05, 0.05), Vector3(0, 2.28, -0.66), frame],
		[Vector3(3.3, 0.05, 0.05), Vector3(0, 0.32, -0.66), frame],
		[Vector3(0.05, 1.95, 0.05), Vector3(0, 1.30, -0.66), frame],
		[Vector3(3.3, 0.10, 0.025), Vector3(0, 1.55, -0.655), frit],
		[Vector3(2.4, 0.04, 0.42), Vector3(-0.3, 0.48, -0.38), bench],
		[Vector3(2.4, 0.30, 0.03), Vector3(-0.3, 0.68, -0.58), bench],
		[Vector3(0.06, 0.46, 0.40), Vector3(-1.45, 0.24, -0.38), frame],
		[Vector3(0.06, 0.46, 0.40), Vector3(0.85, 0.24, -0.38), frame],
		[Vector3(1.25, 1.85, 0.16), Vector3(2.35, 1.12, -0.55), frame],
		[Vector3(1.10, 1.65, 0.02), Vector3(2.35, 1.14, -0.465), ad],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.material_override = p[2]
		mi.position = pos + p[1]
		root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	root.add_child(body)
	for c in [[Vector3(0.12, 2.6, 0.12), Vector3(-1.7, 1.3, -0.62)], [Vector3(0.12, 2.6, 0.12), Vector3(1.7, 1.3, -0.62)],
			[Vector3(3.4, 2.0, 0.08), Vector3(0, 1.3, -0.66)], [Vector3(2.4, 0.5, 0.45), Vector3(-0.3, 0.25, -0.38)],
			[Vector3(1.3, 1.9, 0.2), Vector3(2.35, 1.12, -0.55)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c[0]
		cs.shape = bs
		cs.position = c[1]
		body.add_child(cs)
	signs.append({"pos": pos + Vector3(-2.4, 0, 0.75), "face": Vector3(0, 0, 1), "cell": 4, "h": 2.25, "size": 0.5})
	_count("bus_shelter")
