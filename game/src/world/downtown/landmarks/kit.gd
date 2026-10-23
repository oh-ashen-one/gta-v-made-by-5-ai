extends RefCounted
## Landmark mesh kit (wave M, downtown-landmarks piece).
##
## Procedural geometry accumulator: every primitive is appended to one vertex
## stream per material and committed as a single multi-surface ArrayMesh, so
## a whole landmark costs one draw call per material instead of one per box.
## Collision goes into one StaticBody3D per landmark (box shapes and, for the
## few walk surfaces that need it, one trimesh). All geometry is original.
##
## Winding: callers list quad / triangle corners counter-clockwise as seen from
## the outside (right-hand normal points out). Godot treats clockwise as the
## front face, so the kit emits (a, c, b).

var _surf := {}
var body: StaticBody3D
var shapes := 0
var trimeshes := 0
var tris := 0

func _init(parent: Node3D = null, body_name: String = "LandmarkCollision") -> void:
	if parent != null:
		body = StaticBody3D.new()
		body.name = body_name
		body.collision_layer = 1
		body.collision_mask = 0
		parent.add_child(body)

func _s(mat: Material) -> Dictionary:
	var key := mat.get_instance_id()
	if not _surf.has(key):
		_surf[key] = {"mat": mat, "v": PackedVector3Array(), "n": PackedVector3Array()}
	return _surf[key]

func tri(mat: Material, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var s := _s(mat)
	s["v"].append_array([a, c, b])
	s["n"].append_array([n, n, n])
	tris += 1

func tri_n(mat: Material, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var s := _s(mat)
	s["v"].append_array([a, c, b])
	s["n"].append_array([na, nc, nb])
	tris += 1

func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a) + (c - a).cross(d - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var s := _s(mat)
	s["v"].append_array([a, c, b, a, d, c])
	s["n"].append_array([n, n, n, n, n, n])
	tris += 2

func quad_n(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	var s := _s(mat)
	s["v"].append_array([a, c, b, a, d, c])
	s["n"].append_array([na, nc, nb, na, nd, nc])
	tris += 2

## Axis box (optionally rotated by basis) centred at c.
func box(mat: Material, c: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY, skip_bottom: bool = true) -> void:
	var h := size * 0.5
	var p := []
	for i in 8:
		var l := Vector3(h.x if (i & 1) else -h.x, h.y if (i & 2) else -h.y, h.z if (i & 4) else -h.z)
		p.append(c + basis * l)
	# corners: bit0 x, bit1 y, bit2 z
	quad(mat, p[2], p[6], p[7], p[3])        # top (+y)
	if not skip_bottom:
		quad(mat, p[0], p[1], p[5], p[4])    # bottom (-y)
	quad(mat, p[1], p[3], p[7], p[5])        # +x
	quad(mat, p[0], p[4], p[6], p[2])        # -x
	quad(mat, p[4], p[5], p[7], p[6])        # +z
	quad(mat, p[0], p[2], p[3], p[1])        # -z

## Box spanning two points along its long axis (beams, rails, members).
func beam(mat: Material, p0: Vector3, p1: Vector3, w: float, h: float, up_hint: Vector3 = Vector3.UP) -> void:
	var d := p1 - p0
	var length := d.length()
	if length < 1e-4:
		return
	var z := d / length
	var x := up_hint.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	box(mat, (p0 + p1) * 0.5, Vector3(w, h, length), Basis(x, y, z), false)

## Smooth cylinder / frustum, base centre at c.
func cyl(mat: Material, c: Vector3, r0: float, r1: float, height: float, sides: int = 12, cap_top: bool = true) -> void:
	var slope := (r0 - r1) / maxf(height, 1e-3)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		quad_n(mat, c + d0 * r0, c + d0 * r1 + Vector3(0, height, 0), c + d1 * r1 + Vector3(0, height, 0), c + d1 * r0, n0, n0, n1, n1)
		if cap_top and r1 > 0.0:
			tri(mat, c + Vector3(0, height, 0), c + d1 * r1 + Vector3(0, height, 0), c + d0 * r1 + Vector3(0, height, 0))

## Tube along a polyline with parallel-transported rings and smooth normals.
func tube(mat: Material, pts: PackedVector3Array, r: float, sides: int = 6) -> void:
	if pts.size() < 2:
		return
	var t0 := (pts[1] - pts[0]).normalized()
	var ref := Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var nrm := ref.cross(t0).normalized()
	var rings := []
	for i in pts.size():
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == pts.size() - 1:
			t = pts[i] - pts[i - 1]
		else:
			t = pts[i + 1] - pts[i - 1]
		t = t.normalized()
		nrm = (nrm - t * nrm.dot(t)).normalized()
		var bin := t.cross(nrm)
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			ring.append(nrm * cos(a) + bin * sin(a))
		rings.append(ring)
	for i in pts.size() - 1:
		for k in sides:
			var k1 := (k + 1) % sides
			var da: Vector3 = rings[i][k]
			var db: Vector3 = rings[i][k1]
			var dc: Vector3 = rings[i + 1][k1]
			var dd: Vector3 = rings[i + 1][k]
			quad_n(mat, pts[i] + da * r, pts[i] + db * r, pts[i + 1] + dc * r, pts[i + 1] + dd * r, da, db, dc, dd)

## Loft through rings of equal size. Each ring is listed counter-clockwise
## seen from the end the rings advance toward. smooth: per-vertex normals.
func loft(mat: Material, rings: Array, closed: bool = true, smooth: bool = false) -> void:
	if rings.size() < 2:
		return
	var m: int = rings[0].size()
	var segs := m if closed else m - 1
	for i in rings.size() - 1:
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		for j in segs:
			var jn := (j + 1) % m
			if smooth:
				quad_n(mat, r0[j], r0[jn], r1[jn], r1[j], _ring_n(rings, i, j, closed), _ring_n(rings, i, jn, closed), _ring_n(rings, i + 1, jn, closed), _ring_n(rings, i + 1, j, closed))
			else:
				quad(mat, r0[j], r0[jn], r1[jn], r1[j])

func _ring_n(rings: Array, i: int, j: int, closed: bool) -> Vector3:
	var m: int = rings[0].size()
	var ring: PackedVector3Array = rings[i]
	var ia := maxi(i - 1, 0)
	var ib := mini(i + 1, rings.size() - 1)
	var along: Vector3 = (rings[ib] as PackedVector3Array)[j] - (rings[ia] as PackedVector3Array)[j]
	var ja := (j - 1 + m) % m if closed else maxi(j - 1, 0)
	var jb := (j + 1) % m if closed else mini(j + 1, m - 1)
	var across: Vector3 = ring[jb] - ring[ja]
	var n := across.cross(along)
	return n.normalized() if n.length_squared() > 1e-10 else Vector3.UP

## Flat polygon cap (convex, CCW seen from the outside).
func cap(mat: Material, ring: PackedVector3Array) -> void:
	for j in range(1, ring.size() - 1):
		tri(mat, ring[0], ring[j], ring[j + 1])

func is_empty() -> bool:
	return _surf.is_empty()

func to_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in _surf:
		var s: Dictionary = _surf[key]
		if (s["v"] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s["v"]
		arrays[Mesh.ARRAY_NORMAL] = s["n"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, s["mat"])
	return mesh

func commit(parent: Node3D, node_name: String, shadows: bool = true, vis_end: float = 0.0) -> MeshInstance3D:
	if is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = to_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = 30.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	_surf.clear()
	return mi

# ---------------------------------------------------------------- collision
func col_box(size: Vector3, c: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	if body == null:
		return
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, c)
	body.add_child(cs)
	shapes += 1

## Oriented box between two ground points (walk ramps, deck segments).
func col_beam(p0: Vector3, p1: Vector3, w: float, h: float) -> void:
	var d := p1 - p0
	var length := d.length()
	if length < 1e-3:
		return
	var z := d / length
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	col_box(Vector3(w, h, length), (p0 + p1) * 0.5 - y * h * 0.5, Basis(x, y, z))

func col_trimesh(faces: PackedVector3Array) -> void:
	if body == null or faces.is_empty():
		return
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	shapes += 1
	trimeshes += 1

# ---------------------------------------------------------------- instancing
static func multimesh(parent: Node3D, node_name: String, mesh: Mesh, transforms: Array, shadows: bool = false, vis_end: float = 0.0) -> MultiMeshInstance3D:
	if transforms.is_empty() or mesh == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = 30.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	return mmi

## Transform that places a +y-up unit element at p, facing yaw.
static func xf(p: Vector3, yaw: float = 0.0, s: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(s), p)

## Basis whose +y follows n (surface normal) and +z follows the projected hint.
static func basis_up(n: Vector3, hint: Vector3) -> Basis:
	var y := n.normalized()
	var z := (hint - y * hint.dot(y))
	if z.length_squared() < 1e-6:
		z = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)
