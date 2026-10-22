class_name BoatMeshes
extends RefCounted
## Procedural boats for the bay (original, generated in code).
## Local frame: +X is the bow, +Y up, the waterline sits at y = 0.
## Vertex colour alpha selects the material response in bay_boat.gdshader:
## 1.0 paint, 0.8 varnished wood, 0.5 glass, 0.2 hull tint (per instance),
## 0.0 canopy tint (per instance).

const PAINT := 1.0
const WOOD := 0.8
const GLASS := 0.5
const HULL_TINT := 0.2
const ROOF_TINT := 0.0

var st := SurfaceTool.new()

func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

static func _c(r: float, g: float, b: float, a: float) -> Color:
	var c := Color(r, g, b).srgb_to_linear()
	c.a = a
	return c

## Clockwise-from-outside triangles (Godot front faces) whatever order the
## caller passes; `outward` disambiguates.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, outward: Vector3, na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(outward) > 0.0:
		var tmp := b
		b = c
		c = tmp
		var tn := nb
		nb = nc
		nc = tn
	var flat := outward.normalized() if n.length() < 1e-6 else (-(b - a).cross(c - a)).normalized()
	for pair in [[a, na], [b, nb], [c, nc]]:
		st.set_color(col)
		st.set_normal(flat if (pair[1] as Vector3) == Vector3.ZERO else pair[1])
		st.add_vertex(pair[0])

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, outward: Vector3, na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO, nd := Vector3.ZERO) -> void:
	tri(a, b, c, col, outward, na, nb, nc)
	tri(a, c, d, col, outward, na, nc, nd)

func box(center: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.BACK, Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3.FORWARD, Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)],
	]
	for f in faces:
		var n: Vector3 = basis * (f[0] as Vector3)
		quad(center + basis * f[1], center + basis * f[2], center + basis * f[3], center + basis * f[4], col, n)

## Lofted hull. Returns sheer height per station for deck furniture.
func hull(length: float, beam: float, freeboard: float, bow_rise: float, stern_rise: float, draft: float,
		stripe: Color, topside: Color, boot: Color, bottom: Color, deck: Color) -> void:
	var stations := 22
	var rings: Array = []
	for i in stations + 1:
		var u := float(i) / float(stations)
		var x := -length * 0.5 + u * length
		var hw := beam * 0.5
		if u > 0.58:
			hw *= (1.0 - pow((u - 0.58) / 0.42, 2.1)) * 0.96 + 0.04
		hw *= 0.80 + 0.20 * smoothstep(0.0, 0.22, u)
		var sheer := freeboard + bow_rise * pow(maxf(u - 0.62, 0.0) / 0.38, 2.0) + stern_rise * pow(maxf(0.2 - u, 0.0) / 0.2, 2.0)
		var keel := -draft * (1.0 - 0.85 * pow(maxf(u - 0.7, 0.0) / 0.3, 1.5))
		# starboard profile from gunwale to keel: (half width, height)
		var prof := [Vector2(hw, sheer), Vector2(hw * 1.0, sheer - 0.16), Vector2(hw * 0.985, (sheer - 0.16) * 0.45),
			Vector2(hw * 0.95, 0.07), Vector2(hw * 0.92, -0.04), Vector2(hw * 0.70, keel * 0.55), Vector2(hw * 0.32, keel * 0.92), Vector2(0.0, keel)]
		rings.append({"x": x, "p": prof, "sheer": sheer})
	var seg_cols := [stripe, topside, topside, boot, bottom, bottom, bottom]
	for side in [1.0, -1.0]:
		for i in stations:
			var r0: Dictionary = rings[i]
			var r1: Dictionary = rings[i + 1]
			for j in 7:
				var a0: Vector2 = r0["p"][j]
				var b0: Vector2 = r0["p"][j + 1]
				var a1: Vector2 = r1["p"][j]
				var b1: Vector2 = r1["p"][j + 1]
				var pa := Vector3(r0["x"], a0.y, a0.x * side)
				var pb := Vector3(r0["x"], b0.y, b0.x * side)
				var pc := Vector3(r1["x"], b1.y, b1.x * side)
				var pd := Vector3(r1["x"], a1.y, a1.x * side)
				var out := Vector3(0.0, (a0.y + b0.y) * 0.5 - 0.0, side * 3.0)
				out = Vector3(0.0, 0.0, side) if j < 4 else Vector3(0.0, -0.6, side * 0.8)
				var na := _sec_normal(r0["p"], j, side)
				var nb := _sec_normal(r0["p"], j + 1, side)
				var nc := _sec_normal(r1["p"], j + 1, side)
				var nd := _sec_normal(r1["p"], j, side)
				quad(pa, pb, pc, pd, seg_cols[j], out, na, nb, nc, nd)
	# deck
	for i in stations:
		var r0: Dictionary = rings[i]
		var r1: Dictionary = rings[i + 1]
		var w0: float = (r0["p"][0] as Vector2).x * 0.94
		var w1: float = (r1["p"][0] as Vector2).x * 0.94
		var y0: float = float(r0["sheer"]) - 0.08
		var y1: float = float(r1["sheer"]) - 0.08
		quad(Vector3(r0["x"], y0, -w0), Vector3(r0["x"], y0, w0), Vector3(r1["x"], y1, w1), Vector3(r1["x"], y1, -w1), deck, Vector3.UP)
	# transom
	var r: Dictionary = rings[0]
	var centre := Vector3(r["x"], 0.0, 0.0)
	for side in [1.0, -1.0]:
		for j in 7:
			var a: Vector2 = r["p"][j]
			var b: Vector2 = r["p"][j + 1]
			tri(centre, Vector3(r["x"], a.y, a.x * side), Vector3(r["x"], b.y, b.x * side), seg_cols[j], Vector3.LEFT)
		tri(centre, Vector3(r["x"], (r["p"][0] as Vector2).y - 0.08, 0.0), Vector3(r["x"], (r["p"][0] as Vector2).y, (r["p"][0] as Vector2).x * side), stripe, Vector3.LEFT)

func _sec_normal(prof: Array, j: int, side: float) -> Vector3:
	var a: Vector2 = prof[maxi(j - 1, 0)]
	var b: Vector2 = prof[mini(j + 1, prof.size() - 1)]
	var t := b - a
	var n := Vector2(t.y, -t.x)
	if n.x < 0.0:
		n = -n
	n = n.normalized()
	return Vector3(0.0, n.y, n.x * side).normalized()

func finish() -> ArrayMesh:
	return st.commit()

# ------------------------------------------------------------------ types
static func bumboat() -> ArrayMesh:
	var b := BoatMeshes.new()
	var L := 11.2
	var B := 3.1
	var white := _c(0.90, 0.88, 0.82, PAINT)
	var cream := _c(0.92, 0.86, 0.66, PAINT)
	b.hull(L, B, 0.95, 0.85, 0.35, 0.5, cream, _c(1, 1, 1, HULL_TINT), _c(0.08, 0.08, 0.08, PAINT), _c(0.36, 0.08, 0.06, PAINT), _c(0.45, 0.30, 0.17, WOOD))
	# arched canopy over the passenger well
	var x0 := -L * 0.5 + 1.7
	var x1 := L * 0.5 - 3.1
	var cx := (x0 + x1) * 0.5
	var seg_len := x1 - x0
	var top := 2.45
	for k in 4:
		var z := -1.2 + k * 0.8
		var tilt := (z + 0.4) * -0.28
		b.box(Vector3(cx, top - absf(z + 0.4) * 0.12, z + 0.4), Vector3(seg_len, 0.06, 0.84), _c(1, 1, 1, ROOF_TINT), Basis(Vector3.RIGHT, tilt))
	# valance band along both sides
	for side in [-1.0, 1.0]:
		b.box(Vector3(cx, top - 0.38, side * 1.52), Vector3(seg_len, 0.22, 0.04), _c(0.92, 0.90, 0.84, PAINT))
	# posts
	for k in 4:
		var px := x0 + 0.2 + k * (seg_len - 0.4) / 3.0
		for side in [-1.0, 1.0]:
			b.box(Vector3(px, 1.65, side * 1.42), Vector3(0.08, 1.55, 0.08), white)
	# bench rows and a stern helm box
	for k in 4:
		b.box(Vector3(x0 + 0.9 + k * 1.45, 1.2, 0.0), Vector3(0.45, 0.32, 2.2), _c(0.40, 0.26, 0.15, WOOD))
	b.box(Vector3(-L * 0.5 + 1.0, 1.35, 0.0), Vector3(1.0, 0.75, 1.6), _c(0.30, 0.20, 0.12, WOOD))
	# painted bow eyes (traditional bumboat motif)
	for side in [-1.0, 1.0]:
		var ex := L * 0.5 - 1.6
		b.box(Vector3(ex, 1.18, side * 0.92), Vector3(0.55, 0.30, 0.03), _c(0.95, 0.94, 0.90, PAINT), Basis(Vector3.UP, side * 0.38))
		b.box(Vector3(ex + 0.02, 1.18, side * 0.94), Vector3(0.22, 0.22, 0.03), _c(0.04, 0.04, 0.04, PAINT), Basis(Vector3.UP, side * 0.38))
	return b.finish()

static func cruiser() -> ArrayMesh:
	var b := BoatMeshes.new()
	var L := 18.4
	var B := 5.0
	var white := _c(0.93, 0.93, 0.91, PAINT)
	b.hull(L, B, 1.35, 0.6, 0.15, 0.8, white, white, _c(1, 1, 1, HULL_TINT), _c(0.10, 0.12, 0.16, PAINT), _c(0.62, 0.60, 0.56, PAINT))
	var x0 := -6.6
	var x1 := 4.6
	var cx := (x0 + x1) * 0.5
	var seg_len := x1 - x0
	# lower cabin wall, glazed band, roof slab with overhang
	b.box(Vector3(cx, 1.75, 0.0), Vector3(seg_len, 0.8, 4.3), white)
	b.box(Vector3(cx, 2.65, 0.0), Vector3(seg_len - 0.1, 1.0, 4.18), _c(0.10, 0.14, 0.17, GLASS))
	b.box(Vector3(cx + 0.2, 3.25, 0.0), Vector3(seg_len + 0.6, 0.2, 4.7), white)
	# window mullions
	for k in 9:
		var mx := x0 + 0.4 + k * (seg_len - 0.8) / 8.0
		for side in [-1.0, 1.0]:
			b.box(Vector3(mx, 2.65, side * 2.1), Vector3(0.10, 1.0, 0.06), white)
	# raked front glass and sundeck canopy on posts
	b.box(Vector3(x1 + 0.25, 2.5, 0.0), Vector3(0.12, 1.2, 4.1), _c(0.10, 0.14, 0.17, GLASS), Basis(Vector3.BACK, -0.35))
	for k in 3:
		for side in [-1.0, 1.0]:
			b.box(Vector3(x0 + 0.5 + k * 2.6, 3.95, side * 2.1), Vector3(0.07, 1.25, 0.07), white)
	b.box(Vector3(x0 + 3.1, 4.6, 0.0), Vector3(6.4, 0.08, 4.5), _c(1, 1, 1, ROOF_TINT))
	# rail around the upper deck
	for side in [-1.0, 1.0]:
		b.box(Vector3(cx, 3.85, side * 2.28), Vector3(seg_len, 0.05, 0.05), white)
	b.box(Vector3(x1 + 0.4, 3.85, 0.0), Vector3(0.05, 0.05, 4.5), white)
	# life rings on the cabin side
	for side in [-1.0, 1.0]:
		b.box(Vector3(x0 + 1.0, 1.8, side * 2.17), Vector3(0.6, 0.6, 0.06), _c(0.90, 0.30, 0.10, PAINT))
	return b.finish()

static func launch() -> ArrayMesh:
	var b := BoatMeshes.new()
	var L := 7.2
	var B := 2.4
	var white := _c(0.94, 0.94, 0.92, PAINT)
	b.hull(L, B, 0.8, 0.45, 0.05, 0.4, _c(1, 1, 1, HULL_TINT), white, _c(0.08, 0.08, 0.08, PAINT), _c(0.12, 0.12, 0.13, PAINT), _c(0.70, 0.68, 0.62, PAINT))
	b.box(Vector3(-0.2, 1.2, 0.0), Vector3(1.0, 0.8, 1.2), white)
	b.box(Vector3(0.35, 1.75, 0.0), Vector3(0.08, 0.55, 1.15), _c(0.10, 0.14, 0.17, GLASS), Basis(Vector3.BACK, -0.5))
	b.box(Vector3(-0.9, 1.6, 0.0), Vector3(0.06, 1.6, 0.06), white)
	b.box(Vector3(-0.9, 2.42, 0.0), Vector3(1.4, 0.05, 1.7), _c(1, 1, 1, ROOF_TINT))
	b.box(Vector3(-2.2, 1.05, 0.0), Vector3(1.2, 0.4, 1.8), _c(0.20, 0.22, 0.25, PAINT))
	return b.finish()

## Anchored container ship for the outer roads (Singapore's anchorage on the
## horizon, CONCEPT-03). Coarse on purpose: it is only ever seen through haze.
static func cargo_ship() -> ArrayMesh:
	var b := BoatMeshes.new()
	var L := 190.0
	var B := 30.0
	var white := _c(0.90, 0.89, 0.86, PAINT)
	b.hull(L, B, 12.0, 4.0, 1.5, 9.0, _c(0.88, 0.88, 0.86, PAINT), _c(1, 1, 1, HULL_TINT), _c(0.10, 0.10, 0.10, PAINT), _c(0.40, 0.10, 0.07, PAINT), _c(0.45, 0.20, 0.14, PAINT))
	# accommodation block and funnel at the stern
	b.box(Vector3(-L * 0.5 + 22.0, 24.0, 0.0), Vector3(16.0, 24.0, 24.0), white)
	b.box(Vector3(-L * 0.5 + 22.0, 33.0, 0.0), Vector3(8.0, 1.8, 30.0), white)
	b.box(Vector3(-L * 0.5 + 21.0, 31.0, 0.0), Vector3(16.2, 2.2, 24.2), _c(0.10, 0.13, 0.16, GLASS))
	b.box(Vector3(-L * 0.5 + 12.0, 34.0, 0.0), Vector3(6.0, 10.0, 5.0), _c(0.20, 0.20, 0.22, PAINT))
	# container stacks in bays along the deck
	var cols := [_c(0.62, 0.16, 0.10, PAINT), _c(0.12, 0.25, 0.50, PAINT), _c(0.80, 0.45, 0.10, PAINT), _c(0.55, 0.56, 0.55, PAINT), _c(0.15, 0.40, 0.30, PAINT), _c(0.75, 0.72, 0.65, PAINT)]
	var x := -L * 0.5 + 36.0
	var k := 0
	while x < L * 0.5 - 30.0:
		var tiers := 3 + (k * 7) % 4
		for t in tiers:
			for row in 3:
				b.box(Vector3(x, 12.0 + 1.3 + t * 2.6, -9.0 + row * 9.0), Vector3(12.0, 2.5, 8.6), cols[(k * 3 + t + row * 2) % cols.size()])
		x += 13.0
		k += 1
	return b.finish()
