extends RefCounted
## Downtown blocks geometry kit (wave M, downtown-blocks). Original work.
##
## Builds building shells as one ArrayMesh per block with the per-vertex data
## the shared dt_facade shader reads (see the header of
## assets/authored/shaders/dt_facade.gdshader):
##   UV = metres along the facade / above the building ground,
##   UV2 = (building height, lobby band height),
##   COLOR = (cladding, tint, floor height, seed).
## Footprints are 2D polygons in the ground plane (x, z). Every prism also
## records a collision box (its axis-aligned bounds) for the piece's single
## StaticBody3D.

var st: SurfaceTool
var verts := 0
## Collision boxes: Array of [size: Vector3, centre: Vector3]
var boxes: Array = []
## Footprint bounds of everything added (for tests): Array[Rect2]
var footprints: Array[Rect2] = []

func begin() -> void:
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	verts = 0

func commit() -> ArrayMesh:
	if verts == 0:
		return null
	return st.commit()

# ------------------------------------------------------------ footprints
static func rect(cx: float, cz: float, w: float, d: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hd := d * 0.5
	return PackedVector2Array([Vector2(cx - hw, cz - hd), Vector2(cx + hw, cz - hd), Vector2(cx + hw, cz + hd), Vector2(cx - hw, cz + hd)])

static func chamfer(cx: float, cz: float, w: float, d: float, c: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hd := d * 0.5
	c = minf(c, minf(hw, hd) * 0.9)
	return PackedVector2Array([
		Vector2(cx - hw + c, cz - hd), Vector2(cx + hw - c, cz - hd), Vector2(cx + hw, cz - hd + c), Vector2(cx + hw, cz + hd - c),
		Vector2(cx + hw - c, cz + hd), Vector2(cx - hw + c, cz + hd), Vector2(cx - hw, cz + hd - c), Vector2(cx - hw, cz - hd + c)])

static func rounded(cx: float, cz: float, w: float, d: float, r: float, seg: int = 4) -> PackedVector2Array:
	var hw := w * 0.5
	var hd := d * 0.5
	r = minf(r, minf(hw, hd) * 0.95)
	var pts := PackedVector2Array()
	var corners := [Vector2(cx + hw - r, cz - hd + r), Vector2(cx + hw - r, cz + hd - r), Vector2(cx - hw + r, cz + hd - r), Vector2(cx - hw + r, cz - hd + r)]
	var start_ang := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for k in 4:
		for s in seg + 1:
			var a: float = start_ang[k] + PI * 0.5 * float(s) / float(seg)
			pts.append(corners[k] + Vector2(cos(a), sin(a)) * r)
	return pts

static func oval(cx: float, cz: float, w: float, d: float, seg: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for s in seg:
		var a := TAU * float(s) / float(seg)
		pts.append(Vector2(cx + cos(a) * w * 0.5, cz + sin(a) * d * 0.5))
	return pts

## One corner sliced off diagonally (corner 0..3 = -x-z, +x-z, +x+z, -x+z).
static func clipped(cx: float, cz: float, w: float, d: float, c: float, corner: int) -> PackedVector2Array:
	var base := rect(cx, cz, w, d)
	var pts := PackedVector2Array()
	for i in 4:
		var p := base[i]
		if i == corner:
			var prev := base[(i + 3) % 4]
			var next := base[(i + 1) % 4]
			pts.append(p + (prev - p).normalized() * c)
			pts.append(p + (next - p).normalized() * c)
		else:
			pts.append(p)
	return pts

## Re-entrant (notched) corners: a cross-shaped plan.
static func notched(cx: float, cz: float, w: float, d: float, n: float) -> PackedVector2Array:
	var hw := w * 0.5
	var hd := d * 0.5
	n = minf(n, minf(hw, hd) * 0.4)
	return PackedVector2Array([
		Vector2(cx - hw + n, cz - hd), Vector2(cx + hw - n, cz - hd), Vector2(cx + hw - n, cz - hd + n), Vector2(cx + hw, cz - hd + n),
		Vector2(cx + hw, cz + hd - n), Vector2(cx + hw - n, cz + hd - n), Vector2(cx + hw - n, cz + hd), Vector2(cx - hw + n, cz + hd),
		Vector2(cx - hw + n, cz + hd - n), Vector2(cx - hw, cz + hd - n), Vector2(cx - hw, cz - hd + n), Vector2(cx - hw + n, cz - hd + n)])

static func scaled(poly: PackedVector2Array, s: Vector2, about: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(about + (p - about) * s)
	return out

static func centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(maxi(1, poly.size()))

static func bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r

# ------------------------------------------------------------ emitters
func _v(p: Vector3, n: Vector3, uv: Vector2, uv2: Vector2, col: Color) -> void:
	st.set_normal(n)
	st.set_color(col)
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.add_vertex(p)
	verts += 1

## Front faces in Godot are clockwise seen from the viewer, i.e.
## cross(b - a, c - a) points AWAY from the outward normal.
func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, uv2: Vector2, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		_v(a, n, ua, uv2, col); _v(c, n, uc, uv2, col); _v(b, n, ub, uv2, col)
	else:
		_v(a, n, ua, uv2, col); _v(b, n, ub, uv2, col); _v(c, n, uc, uv2, col)

## Extrude a footprint from y0 to the top plane y1 (+ optional slope:
## top y = y1 + slope.x * (x - cx) + slope.y * (z - cz)). info keys:
## cid, tint, fl, seed, H (building height), lobby (band height, metres
## above ground_y), ground_y. Returns the max top height.
func prism(poly: PackedVector2Array, y0: float, y1: float, info: Dictionary, slope := Vector2.ZERO, cap_top := true, cap_bottom := false, collide := true) -> float:
	var col := Color((float(info.get("cid", 0)) + 0.5) / 10.0, float(info.get("tint", 0.5)), float(info.get("fl", 0.5)), float(info.get("seed", 0.0)))
	var gy: float = info.get("ground_y", 0.0)
	var uv2 := Vector2(float(info.get("H", y1 - gy)), float(info.get("lobby", 0.0)))
	var c := centroid(poly)
	var n_pts := poly.size()
	var tops := PackedFloat32Array()
	var ymax := y1
	for p in poly:
		var ty := y1 + slope.x * (p.x - c.x) + slope.y * (p.y - c.y)
		tops.append(ty)
		ymax = maxf(ymax, ty)
	for i in n_pts:
		var a2 := poly[i]
		var b2 := poly[(i + 1) % n_pts]
		var e := b2 - a2
		var L := e.length()
		if L < 0.01:
			continue
		var n := Vector3(e.y, 0.0, -e.x).normalized()
		var mid := (a2 + b2) * 0.5
		if n.dot(Vector3(mid.x - c.x, 0.0, mid.y - c.y)) < 0.0:
			n = -n
		# u is measured from the face centre (+ an optional shift), so window
		# bays sit symmetrically on every face and a mullion meets each corner.
		var t := Vector3(n.z, 0.0, -n.x)
		var along := t.dot(Vector3(e.x, 0.0, e.y)) >= 0.0
		var ush: float = info.get("u_shift", 0.0)
		var ua := (-L * 0.5 if along else L * 0.5) + ush
		var ub := (L * 0.5 if along else -L * 0.5) + ush
		var A := Vector3(a2.x, y0, a2.y)
		var B := Vector3(b2.x, y0, b2.y)
		var At := Vector3(a2.x, tops[i], a2.y)
		var Bt := Vector3(b2.x, tops[(i + 1) % n_pts], b2.y)
		var uA := Vector2(ua, y0 - gy)
		var uB := Vector2(ub, y0 - gy)
		var uAt := Vector2(ua, At.y - gy)
		var uBt := Vector2(ub, Bt.y - gy)
		_tri(A, B, Bt, n, uA, uB, uBt, uv2, col)
		_tri(A, Bt, At, n, uA, uBt, uAt, uv2, col)
	var idx := Geometry2D.triangulate_polygon(poly)
	if cap_top and idx.size() >= 3:
		var r := bounds(poly)
		var ext := maxf(r.size.x, r.size.y)
		var rot := int(float(info.get("seed", 0.0)) * 4.0) % 4
		var nrm := Vector3(-slope.x, 1.0, -slope.y).normalized()
		for k in range(0, idx.size(), 3):
			var pa := poly[idx[k]]; var pb := poly[idx[k + 1]]; var pc := poly[idx[k + 2]]
			_tri(Vector3(pa.x, tops[idx[k]], pa.y), Vector3(pb.x, tops[idx[k + 1]], pb.y), Vector3(pc.x, tops[idx[k + 2]], pc.y), nrm,
				_roof_uv(pa, r, ext, rot), _roof_uv(pb, r, ext, rot), _roof_uv(pc, r, ext, rot), uv2, col)
	if cap_bottom and idx.size() >= 3:
		for k in range(0, idx.size(), 3):
			var qa := poly[idx[k]]; var qb := poly[idx[k + 1]]; var qc := poly[idx[k + 2]]
			_tri(Vector3(qa.x, y0, qa.y), Vector3(qb.x, y0, qb.y), Vector3(qc.x, y0, qc.y), Vector3.DOWN, qa, qb, qc, uv2, col)
	var bb := bounds(poly)
	footprints.append(bb)
	if collide:
		var top := (y1 + ymax) * 0.5
		boxes.append([Vector3(bb.size.x, top - y0, bb.size.y), Vector3(bb.get_center().x, (y0 + top) * 0.5, bb.get_center().y)])
	return ymax

static func _roof_uv(p: Vector2, r: Rect2, ext: float, rot: int) -> Vector2:
	var q := (p - r.position) / maxf(ext, 1.0)
	match rot:
		1: return Vector2(1.0 - q.y, q.x)
		2: return Vector2(1.0 - q.x, 1.0 - q.y)
		3: return Vector2(q.y, 1.0 - q.x)
	return q

## Gable roof over an axis-aligned rect, ridge along z (shophouse rows).
## Roof faces get UV in metres (along the ridge, down the slope).
func gable_z(x0: float, x1: float, z0: float, z1: float, y: float, rise: float, info: Dictionary, overhang: float = 0.5) -> void:
	var col := Color((float(info.get("cid", 9)) + 0.5) / 10.0, float(info.get("tint", 0.5)), 0.5, float(info.get("seed", 0.0)))
	var uv2 := Vector2(float(info.get("H", y)), 0.0)
	var xm := (x0 + x1) * 0.5
	var xa := x0 - overhang
	var xb := x1 + overhang
	var ya := y - overhang * rise / ((x1 - x0) * 0.5)
	var ridge := y + rise
	var slope_len := Vector2(xm - xa, ridge - ya).length()
	for side in [-1.0, 1.0]:
		var xe: float = xa if side < 0.0 else xb
		var n := Vector3(side * rise, (x1 - x0) * 0.5, 0.0).normalized()
		var P0 := Vector3(xe, ya, z0 - 0.15); var P1 := Vector3(xe, ya, z1 + 0.15)
		var R0 := Vector3(xm, ridge, z0 - 0.15); var R1 := Vector3(xm, ridge, z1 + 0.15)
		_tri(P0, P1, R1, n, Vector2(z0, slope_len), Vector2(z1, slope_len), Vector2(z1, 0.0), uv2, col)
		_tri(P0, R1, R0, n, Vector2(z0, slope_len), Vector2(z1, 0.0), Vector2(z0, 0.0), uv2, col)
	# gable end walls (plaster, facade coordinates)
	var wall_col := Color((9.0 + 0.5) / 10.0, float(info.get("tint", 0.5)), 0.5, float(info.get("seed", 0.0)))
	var gy: float = info.get("ground_y", 0.0)
	for zs in [z0, z1]:
		var nz := Vector3(0, 0, -1) if zs == z0 else Vector3(0, 0, 1)
		_tri(Vector3(x0, y, zs), Vector3(x1, y, zs), Vector3(xm, ridge, zs), nz, Vector2(x0, y - gy), Vector2(x1, y - gy), Vector2(xm, ridge - gy), uv2, wall_col)
