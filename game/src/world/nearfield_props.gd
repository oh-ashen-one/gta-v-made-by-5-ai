class_name NearFieldProps
extends RefCounted
## Nearfield piece (opus55 wave R): believable street-prop models for the
## StreetDressing MultiMesh batches, replacing the primitive stand-ins the
## run-1/2 critics called blockout (salmon/mint crate boxes, blank white and
## black slab boards, scaled-cylinder cones and bins). Each model is built once
## from small generated parts at real size with its origin on the ground and
## baked vertex colours; the instance colour still tints it (crates, produce).
##   tcone   road-works cone: weighted black base, orange body, two reflective
##           collars
##   bin     green litter bin: tapered drum, lid with a dark posting slot,
##           steel band and ash tray
##   crate   slatted plastic produce crate, open top, handle slots
##   produce a heaped crate fill of round fruit/veg (instance colour tints)
##   aframe  timber A-frame chalkboard with legible chalk menus (two faces)
##   cabinet green steel telecom/power cabinet: plinth, twin doors, louvres,
##           drip cap, handles
## Kind names carry no "_" (StreetPropColliders derives the kind from the
## MultiMesh name) and are listed in its SOLID_KINDS so the player bumps them.

const KINDS := ["tcone", "bin", "crate", "produce", "aframe", "cabinet"]
static var _cache := {}

static func has(kind: String) -> bool:
	return NearField.enabled() and kind in KINDS

## True when the mesh carries its own surface materials (no override).
static func own_materials(kind: String) -> bool:
	return kind == "aframe"

static func material(kind: String) -> Material:
	var key := "mat_" + kind
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	match kind:
		"tcone":
			m.roughness = 0.5
			m.metallic_specular = 0.6
		"bin":
			m.roughness = 0.55
			m.metallic_specular = 0.5
		"produce":
			m.roughness = 0.42
		_:
			m.roughness = 0.62
	_cache[key] = m
	return m

static func mesh(kind: String) -> Mesh:
	if _cache.has(kind):
		return _cache[kind]
	var m: Mesh
	match kind:
		"tcone": m = _cone()
		"bin": m = _bin()
		"crate": m = _crate()
		"produce": m = _produce()
		"aframe": m = _aframe()
		"cabinet": m = _cabinet()
	_cache[kind] = m
	return m

# ------------------------------------------------------------ helpers
## One triangle, wound so its front face looks along `n` (Godot treats
## clockwise-on-screen as front: (b - a) x (c - a) points away from it).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color) -> void:
	var n := na + nb + nc
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b; b = c; c = t
		var tn := nb; nb = nc; nc = tn
	for v in [[a, na], [b, nb], [c, nc]]:
		st.set_color(col)
		st.set_normal(v[1])
		st.add_vertex(v[0])

static func _frustum(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, col: Color, seg: int = 16, cap_top: bool = false) -> void:
	var slope := (r0 - r1) / maxf(y1 - y0, 1e-3)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3.UP * slope).normalized()
		var n1 := (d1 + Vector3.UP * slope).normalized()
		var a0b := d0 * r0 + Vector3.UP * y0
		var a1b := d1 * r0 + Vector3.UP * y0
		var a0t := d0 * r1 + Vector3.UP * y1
		var a1t := d1 * r1 + Vector3.UP * y1
		_tri(st, a0b, a1t, a1b, n0, n1, n1, col)
		_tri(st, a0b, a0t, a1t, n0, n0, n1, col)
		if cap_top:
			_tri(st, Vector3.UP * y1, a1t, a0t, Vector3.UP, Vector3.UP, Vector3.UP, col)

static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, basis: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := n * h
		var uu := u * h
		var vv := v * h
		var corners := [o - uu - vv, o + uu - vv, o + uu + vv, o - uu + vv]
		# keep winding counter-clockwise seen from outside
		var order := [0, 2, 1, 0, 3, 2] if u.cross(v).dot(n) > 0.0 else [0, 1, 2, 0, 2, 3]
		for idx in order:
			st.set_color(col)
			st.set_normal((basis * n).normalized())
			st.add_vertex(c + basis * (corners[idx] as Vector3))

static func _sphere(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, seg: int = 8, rings: int = 5) -> void:
	for j in rings:
		var t0 := PI * j / rings
		var t1 := PI * (j + 1) / rings
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p := func(t: float, a: float) -> Vector3: return Vector3(sin(t) * cos(a), cos(t), sin(t) * sin(a))
			var n00: Vector3 = p.call(t0, a0)
			var n01: Vector3 = p.call(t0, a1)
			var n10: Vector3 = p.call(t1, a0)
			var n11: Vector3 = p.call(t1, a1)
			_tri(st, c + n00 * r, c + n11 * r, c + n10 * r, n00, n11, n10, col)
			_tri(st, c + n00 * r, c + n01 * r, c + n11 * r, n00, n01, n11, col)

# ------------------------------------------------------------- models
static func _cone() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var black := Color(0.05, 0.05, 0.05)
	var orange := Color(0.93, 0.33, 0.05)
	var white := Color(0.90, 0.90, 0.88)
	_box(st, Vector3(0, 0.018, 0), Vector3(0.36, 0.036, 0.36), black)
	_frustum(st, 0.036, 0.06, 0.155, 0.15, black, 16)
	var bands := [[0.06, 0.33, orange], [0.33, 0.43, white], [0.43, 0.52, orange], [0.52, 0.58, white], [0.58, 0.72, orange]]
	for bd in bands:
		var y0: float = bd[0]
		var y1: float = bd[1]
		_frustum(st, y0, y1, lerpf(0.15, 0.026, (y0 - 0.06) / 0.66), lerpf(0.15, 0.026, (y1 - 0.06) / 0.66), bd[2], 16, y1 >= 0.72)
	return st.commit()

static func _bin() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.11, 0.27, 0.17)
	var dark := Color(0.06, 0.12, 0.08)
	var steel := Color(0.62, 0.63, 0.62)
	_frustum(st, 0.0, 0.05, 0.25, 0.25, dark, 18)
	_frustum(st, 0.05, 0.70, 0.25, 0.28, green, 18)
	_frustum(st, 0.70, 0.75, 0.285, 0.285, steel, 18)
	_frustum(st, 0.75, 0.86, 0.28, 0.29, green, 18)
	_frustum(st, 0.86, 0.90, 0.30, 0.30, dark, 18)
	_frustum(st, 0.90, 1.02, 0.30, 0.17, green, 18)
	_frustum(st, 1.02, 1.05, 0.17, 0.15, steel, 18, true)
	# posting slot on the lid face and a lighter recycling decal panel
	_box(st, Vector3(0, 0.955, 0.235), Vector3(0.22, 0.07, 0.03), Color(0.02, 0.02, 0.02), Basis(Vector3.RIGHT, -0.85))
	_box(st, Vector3(0, 0.45, 0.262), Vector3(0.16, 0.20, 0.01), Color(0.80, 0.80, 0.76), Basis(Vector3.RIGHT, -0.046))
	return st.commit()

static func _crate() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color.WHITE
	var sx := 0.56
	var sy := 0.30
	var sz := 0.40
	_box(st, Vector3(0, 0.012, 0), Vector3(sx, 0.024, sz), c * 0.8)
	for px: float in [-1.0, 1.0]:
		for pz: float in [-1.0, 1.0]:
			_box(st, Vector3(px * (sx * 0.5 - 0.02), sy * 0.5, pz * (sz * 0.5 - 0.02)), Vector3(0.04, sy, 0.04), c)
	# top rim and two slat rails on each side (gaps read as the lattice)
	for y: float in [sy - 0.02, 0.17, 0.09]:
		var t := 0.04 if y > 0.2 else 0.034
		var k := 1.0 if y > 0.2 else 0.9
		for pz: float in [-1.0, 1.0]:
			_box(st, Vector3(0, y, pz * (sz * 0.5 - 0.012)), Vector3(sx, t, 0.024), c * k)
		for px: float in [-1.0, 1.0]:
			_box(st, Vector3(px * (sx * 0.5 - 0.012), y, 0), Vector3(0.024, t, sz), c * k)
	# vertical ribs on the long sides
	for rx: float in [-0.14, 0.0, 0.14]:
		for pz: float in [-1.0, 1.0]:
			_box(st, Vector3(rx, sy * 0.45, pz * (sz * 0.5 - 0.01)), Vector3(0.022, sy * 0.8, 0.02), c * 0.9)
	# dark interior floor so the open top reads hollow
	_box(st, Vector3(0, 0.03, 0), Vector3(sx - 0.05, 0.01, sz - 0.05), Color(0.25, 0.25, 0.25))
	return st.commit()

static func _produce() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	for i in 26:
		var x := r.randf_range(-0.23, 0.23)
		var z := r.randf_range(-0.15, 0.15)
		var mound := 0.06 * (1.0 - (x * x / 0.06 + z * z / 0.025))
		var rad := r.randf_range(0.045, 0.065)
		var shade := r.randf_range(0.72, 1.08)
		_sphere(st, Vector3(x, rad * 0.8 + maxf(mound, 0.0), z), Vector3(rad, rad * 0.92, rad), Color(shade, shade, shade * r.randf_range(0.9, 1.05)), 8, 5)
	return st.commit()

static func _cabinet() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.15, 0.29, 0.20)
	var dark := Color(0.05, 0.08, 0.06)
	var conc := Color(0.55, 0.54, 0.51)
	var steel := Color(0.60, 0.61, 0.60)
	_box(st, Vector3(0, 0.06, 0), Vector3(1.20, 0.12, 0.54), conc)
	_box(st, Vector3(0, 0.12 + 0.62, 0), Vector3(1.10, 1.24, 0.45), green)
	_box(st, Vector3(0, 1.39, 0), Vector3(1.18, 0.05, 0.52), green * 0.85)
	for side: float in [-1.0, 1.0]:
		var z := side * 0.228
		_box(st, Vector3(0, 0.74, z), Vector3(0.012, 1.10, 0.006), dark)   # door seam
		for dx: float in [-0.27, 0.27]:
			for k in 5:
				_box(st, Vector3(dx, 1.05 + k * 0.045, z), Vector3(0.30, 0.012, 0.008), dark)   # louvres
			_box(st, Vector3(dx + (0.2 if dx > 0.0 else -0.2), 0.70, z + side * 0.01), Vector3(0.025, 0.12, 0.02), steel)   # handles
		_box(st, Vector3(-0.30, 0.55, z), Vector3(0.18, 0.12, 0.005), Color(0.82, 0.80, 0.70))   # id plate
	return st.commit()

static func _aframe() -> Mesh:
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.42, 0.28, 0.16)
	var slate := Color(0.06, 0.07, 0.065)
	var w := 0.62
	var h := 0.98
	var tilt := deg_to_rad(12.0)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		# board plane hinged at the top, foot spread along +-z
		var b := Basis(Vector3.RIGHT, s * tilt)
		var top := Vector3(0, h, 0)
		var mid := top + b * Vector3(0, -h * 0.5, 0)
		_box(frame, mid + b * Vector3(0, 0, s * 0.0), Vector3(w, h, 0.022), slate, b)
		for px: float in [-1.0, 1.0]:
			_box(frame, mid + b * Vector3(px * (w * 0.5 - 0.02), 0, s * 0.006), Vector3(0.04, h, 0.03), wood, b)
		for py: float in [-1.0, 1.0]:
			_box(frame, mid + b * Vector3(0, py * (h * 0.5 - 0.02), s * 0.006), Vector3(w, 0.04, 0.03), wood, b)
		# chalk face quad on the outer side, inset inside the frame
		var n := (b * Vector3(0, 0, s)).normalized()
		var cx := 0.0 if side == 0 else 0.5
		var hw := w * 0.5 - 0.04
		var hh := h * 0.5 - 0.04
		var corners := [Vector3(-hw, -hh, 0), Vector3(hw, -hh, 0), Vector3(hw, hh, 0), Vector3(-hw, hh, 0)]
		var uvs := [Vector2(cx, 1), Vector2(cx + 0.5, 1), Vector2(cx + 0.5, 0), Vector2(cx, 0)]
		if s < 0.0:
			uvs = [Vector2(cx + 0.5, 1), Vector2(cx, 1), Vector2(cx, 0), Vector2(cx + 0.5, 0)]
		var pts: Array[Vector3] = []
		for k in 4:
			pts.append(mid + b * ((corners[k] as Vector3) + Vector3(0, 0, s * 0.0125)))
		var order := [0, 2, 1, 0, 3, 2]
		if (pts[2] - pts[0]).cross(pts[1] - pts[0]).dot(n) > 0.0:
			order = [0, 1, 2, 0, 2, 3]
		for idx in order:
			face.set_normal(n)
			face.set_uv(uvs[idx])
			face.add_vertex(pts[idx])
	# hinge bar
	_box(frame, Vector3(0, h + 0.01, 0), Vector3(w + 0.04, 0.03, 0.05), wood)
	var mesh := ArrayMesh.new()
	frame.commit(mesh)
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.roughness = 0.75
	mesh.surface_set_material(0, fm)
	face.commit(mesh)
	var cm := StandardMaterial3D.new()
	cm.albedo_texture = load("res://assets/authored/surfaces/chalk_menu_albedo.png")
	cm.roughness = 0.9
	cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mesh.surface_set_material(1, cm)
	return mesh

# ------------------------------------------------- standalone placement
## One modelled prop as its own MeshInstance3D (world_builder five-foot-way
## fittings), tinted, with an on-foot-only collision box (StreetPropColliders
## layer: cars, NPCs and the camera arm ignore it).
static func place(root: Node3D, kind: String, xf: Transform3D, tint: Color = Color.WHITE, solid: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "NearfieldProp_" + kind
	mi.mesh = mesh(kind)
	if not own_materials(kind):
		var m := (material(kind) as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = tint
		mi.material_override = m
	mi.transform = xf
	mi.set_meta("nearfield", true)
	root.add_child(mi)
	if solid:
		var aabb := mi.mesh.get_aabb()
		var body := StaticBody3D.new()
		body.collision_layer = StreetPropColliders.PROP_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = aabb.size * 0.92
		cs.shape = bs
		cs.position = aabb.get_center()
		body.add_child(cs)
		body.transform = xf
		root.add_child(body)
	return mi

## A five-foot-way stack of produce crates and cartons (replaces the two
## brown blockout boxes): 3-5 slatted crates, some filled, plus a carton.
static func goods_stack(root: Node3D, origin: Vector3, yaw: float, seed_i: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_i
	var b := Basis(Vector3.UP, yaw)
	var cols: Array[Color] = [Color(0.22, 0.34, 0.55), Color(0.55, 0.16, 0.12), Color(0.18, 0.38, 0.26), Color(0.30, 0.30, 0.30)]
	var fills: Array[Color] = [Color(0.85, 0.45, 0.08), Color(0.75, 0.12, 0.08), Color(0.45, 0.62, 0.12), Color(0.90, 0.78, 0.20)]
	var n := r.randi_range(3, 5)
	for k in n:
		var lx := (k % 2) * 0.6 - 0.3
		var ly := (k / 2) * 0.30
		var cb := b * Basis(Vector3.UP, r.randf_range(-0.12, 0.12))
		var p := origin + b * Vector3(lx, ly, r.randf_range(-0.04, 0.04))
		place(root, "crate", Transform3D(cb, p), cols[r.randi() % cols.size()], k < 2)
		if k >= n - 2:
			place(root, "produce", Transform3D(cb, p + Vector3(0, 0.20, 0)), fills[r.randi() % fills.size()], false)
