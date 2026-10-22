class_name BoatMeshes
extends RefCounted
## Procedural boats for the bay (original, generated in code).
## Local frame: +X is the bow, +Y up, the waterline sits at y = 0.
## Vertex colour alpha selects the material response in bay_boat.gdshader:
## 1.0 paint, 0.8 varnished wood, 0.68 polished steel, 0.5 glass,
## 0.2 hull tint (per instance), 0.0 canopy tint (per instance).

const PAINT := 1.0
const WOOD := 0.8
const GLASS := 0.5
const CHROME := 0.68
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
		stripe: Color, topside: Color, boot: Color, bottom: Color, deck: Color, topside2 := Color(-1, -1, -1, -1)) -> void:
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
	var seg_cols := [stripe, topside, topside if topside2.r < 0.0 else topside2, boot, bottom, bottom, bottom]
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

## Round tube between two points (rails, stanchions, spotlight barrels).
func tube(a: Vector3, b: Vector3, r: float, col: Color, sides: int = 6) -> void:
	var ax := (b - a)
	if ax.length() < 1e-4:
		return
	var t := ax.normalized()
	var s := t.cross(Vector3.UP)
	if s.length() < 0.01:
		s = t.cross(Vector3.RIGHT)
	s = s.normalized()
	var u := s.cross(t).normalized()
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var n0 := s * cos(a0) + u * sin(a0)
		var n1 := s * cos(a1) + u * sin(a1)
		quad(a + n0 * r, a + n1 * r, b + n1 * r, b + n0 * r, col, (n0 + n1) * 0.5, n0, n1, n1, n0)

## Low-poly ellipsoid (heads, cowlings, fenders) with smooth normals.
func ellipsoid(c: Vector3, rad: Vector3, col: Color, seg: int = 8, rings: int = 6, basis := Basis.IDENTITY) -> void:
	for i in rings:
		var p0 := PI * float(i) / float(rings) - PI * 0.5
		var p1 := PI * float(i + 1) / float(rings) - PI * 0.5
		for k in seg:
			var a0 := TAU * float(k) / float(seg)
			var a1 := TAU * float(k + 1) / float(seg)
			var d := [Vector3(cos(p0) * cos(a0), sin(p0), cos(p0) * sin(a0)), Vector3(cos(p0) * cos(a1), sin(p0), cos(p0) * sin(a1)),
				Vector3(cos(p1) * cos(a1), sin(p1), cos(p1) * sin(a1)), Vector3(cos(p1) * cos(a0), sin(p1), cos(p1) * sin(a0))]
			var v: Array[Vector3] = []
			var nn: Array[Vector3] = []
			for q: Vector3 in d:
				v.append(c + basis * (q * rad))
				nn.append((basis * (q / rad)).normalized())
			var out := (v[0] + v[1] + v[2] + v[3]) * 0.25 - c
			if i == 0:
				tri(v[0], v[2], v[3], col, out, nn[0], nn[2], nn[3])
			elif i == rings - 1:
				tri(v[0], v[1], v[2], col, out, nn[0], nn[1], nn[2])
			else:
				quad(v[0], v[1], v[2], v[3], col, out, nn[0], nn[1], nn[2], nn[3])

## A crew member or passenger (about 1.75 m standing). `at` is the seat or deck
## point under the hips/feet, facing +X rotated by `yaw`. Readable at 10-30 m:
## head with hair and sunglasses, shoulders, arms reaching forward when seated
## at a helm (`reach`), legs bent over the seat edge.
func person(at: Vector3, yaw: float, seated: bool, shirt: Color, reach: float = 0.0, skin_tone: int = 0) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var skins := [_c(0.76, 0.56, 0.42, PAINT), _c(0.55, 0.38, 0.26, PAINT), _c(0.86, 0.68, 0.54, PAINT), _c(0.42, 0.28, 0.19, PAINT)]
	var skin: Color = skins[skin_tone % skins.size()]
	var hair := _c(0.06, 0.05, 0.05, PAINT)
	var shorts := _c(0.16, 0.18, 0.24, PAINT) if skin_tone % 2 == 0 else _c(0.70, 0.64, 0.50, PAINT)
	var hip_y := at.y + (0.0 if seated else 0.86)
	if seated:
		# thighs forward along the seat, shins down
		for side in [-1.0, 1.0]:
			box(at + bs * Vector3(0.20, 0.07, side * 0.10), Vector3(0.44, 0.15, 0.15), shorts, bs)
			box(at + bs * Vector3(0.40, -0.22, side * 0.10), Vector3(0.12, 0.48, 0.12), skin, bs)
	else:
		for side in [-1.0, 1.0]:
			box(at + bs * Vector3(0.0, 0.62, side * 0.10), Vector3(0.16, 0.48, 0.15), shorts, bs)
			box(at + bs * Vector3(0.0, 0.20, side * 0.10), Vector3(0.12, 0.40, 0.12), skin, bs)
			box(at + bs * Vector3(0.05, 0.03, side * 0.10), Vector3(0.24, 0.07, 0.10), _c(0.9, 0.9, 0.88, PAINT), bs)
	var hip := Vector3(at.x, hip_y, at.z)
	# torso: tapered from hips to shoulders, slight forward lean when seated
	var lean := Basis(Vector3.FORWARD, -0.10 if seated else 0.0)
	var tb := bs * lean
	box(hip + tb * Vector3(0.0, 0.16, 0.0), Vector3(0.22, 0.30, 0.34), shirt, tb)
	box(hip + tb * Vector3(0.0, 0.43, 0.0), Vector3(0.25, 0.26, 0.44), shirt, tb)
	var neck := hip + tb * Vector3(0.0, 0.60, 0.0)
	box(neck, Vector3(0.09, 0.08, 0.09), skin, tb)
	var head := neck + tb * Vector3(0.01, 0.13, 0.0)
	ellipsoid(head, Vector3(0.10, 0.12, 0.09), skin, 8, 6, bs)
	ellipsoid(head + bs * Vector3(-0.015, 0.035, 0.0), Vector3(0.105, 0.10, 0.097), hair, 8, 4, bs)
	box(head + bs * Vector3(0.085, 0.015, 0.0), Vector3(0.03, 0.035, 0.16), _c(0.02, 0.02, 0.025, GLASS), bs)
	# arms: upper arm down from the shoulder, forearm to the hands
	for side in [-1.0, 1.0]:
		var sh := hip + tb * Vector3(0.0, 0.52, side * 0.25)
		var elbow := sh + bs * Vector3(0.10 + reach * 0.18, -0.26 + reach * 0.06, side * 0.02)
		var hand := elbow + bs * Vector3(0.12 + reach * 0.10, 0.04 + reach * 0.18, -side * 0.05 * reach)
		tube(sh, elbow, 0.055, shirt if reach > 0.0 else skin, 5)
		tube(elbow, hand, 0.045, skin, 5)
		ellipsoid(hand, Vector3(0.05, 0.04, 0.04), skin, 5, 3)

static func half_width(L: float, B: float, x: float) -> float:
	var u := (x + L * 0.5) / L
	var hw := B * 0.5
	if u > 0.58:
		hw *= (1.0 - pow((u - 0.58) / 0.42, 2.1)) * 0.96 + 0.04
	hw *= 0.80 + 0.20 * smoothstep(0.0, 0.22, u)
	return hw

static func sheer_height(L: float, freeboard: float, bow_rise: float, stern_rise: float, x: float) -> float:
	var u := (x + L * 0.5) / L
	return freeboard + bow_rise * pow(maxf(u - 0.62, 0.0) / 0.38, 2.0) + stern_rise * pow(maxf(0.2 - u, 0.0) / 0.2, 2.0)

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
	# skipper standing at the stern helm, passengers on the benches
	b.person(Vector3(-L * 0.5 + 0.35, 1.10, 0.25), 0.0, false, _c(0.20, 0.24, 0.30, PAINT), 0.6, 1)
	var shirts := [_c(0.90, 0.88, 0.82, PAINT), _c(0.80, 0.25, 0.20, PAINT), _c(0.25, 0.45, 0.70, PAINT), _c(0.95, 0.75, 0.30, PAINT), _c(0.30, 0.55, 0.40, PAINT), _c(0.85, 0.50, 0.60, PAINT)]
	var n := 0
	for k in 4:
		for zz in [-0.75, 0.0, 0.75]:
			if (k * 3 + int(zz * 4.0 + 3.0)) % 4 == 1:
				continue
			b.person(Vector3(x0 + 0.9 + k * 1.45 - 0.05, 1.37, zz), 0.0, true, shirts[n % shirts.size()], 0.0, n)
			n += 1
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
	# sightseers on the sun deck along the rails, a deckhand on the foredeck
	var shirts := [_c(0.90, 0.88, 0.82, PAINT), _c(0.80, 0.25, 0.20, PAINT), _c(0.25, 0.45, 0.70, PAINT), _c(0.95, 0.75, 0.30, PAINT), _c(0.30, 0.55, 0.40, PAINT)]
	var spots := [[x0 + 0.9, 1.75, 1.6], [x0 + 2.2, 1.85, -1.5], [x0 + 3.6, 1.75, 1.5], [x0 + 5.6, 1.75, -1.6], [x0 + 7.4, 1.95, 1.6], [x0 + 9.0, 1.75, -1.5]]
	for k in spots.size():
		var sp: Array = spots[k]
		b.person(Vector3(sp[0], 3.35, sp[2]), -float(sp[1]) * signf(float(sp[2])), false, shirts[k % shirts.size()], 0.0, k)
	b.person(Vector3(x1 + 1.6, 1.45, 0.6), 0.3, false, _c(0.95, 0.95, 0.95, PAINT), 0.0, 3)
	return b.finish()

static func launch() -> ArrayMesh:
	## Sport runabout (water round 4, critic: "a toy box hull, no occupant,
	## no windows, no railings"). Deep-V hull with a two-tone glossy finish
	## (per-instance colour above a dark chine band), wrap-around windshield
	## in a polished frame, bow rail on stanchions, twin spotlights, helm
	## console with wheel, upholstered seats, a driver and a passenger, stern
	## grab rail and an outboard.
	var b := BoatMeshes.new()
	var L := 7.6
	var B := 2.5
	var fb := 0.95
	var br := 0.55
	var white := _c(0.95, 0.95, 0.93, PAINT)
	var chrome := _c(0.80, 0.82, 0.84, CHROME)
	var glass := _c(0.09, 0.13, 0.16, GLASS)
	var seat := _c(0.88, 0.84, 0.74, PAINT)
	var navy := _c(0.035, 0.05, 0.09, PAINT)
	b.hull(L, B, fb, br, 0.0, 0.62, white, _c(1, 1, 1, HULL_TINT), navy, navy, _c(0.86, 0.85, 0.80, PAINT), navy)
	var sh := func(x: float) -> float: return BoatMeshes.sheer_height(L, fb, br, 0.0, x)
	var hw := func(x: float) -> float: return BoatMeshes.half_width(L, B, x)
	# rubbing strake: a polished strip just below the gunwale, both sides
	for side in [-1.0, 1.0]:
		var xs := -L * 0.5 + 0.05
		while xs < L * 0.5 - 0.5:
			var xe := minf(xs + 0.6, L * 0.5 - 0.35)
			b.tube(Vector3(xs, sh.call(xs) - 0.17, side * (hw.call(xs) + 0.01)), Vector3(xe, sh.call(xe) - 0.17, side * (hw.call(xe) + 0.01)), 0.025, chrome, 4)
			xs = xe
	# foredeck: raised non-skid deck from the windshield to the bow
	var fx0 := 0.55
	for k in 6:
		var xa := fx0 + float(k) * (L * 0.5 - 0.25 - fx0) / 6.0
		var xb := fx0 + float(k + 1) * (L * 0.5 - 0.25 - fx0) / 6.0
		var ya: float = sh.call(xa) + 0.05
		var yb: float = sh.call(xb) + 0.05
		var wa: float = hw.call(xa) * 0.86
		var wb: float = hw.call(xb) * 0.86
		b.quad(Vector3(xa, ya, -wa), Vector3(xa, ya, wa), Vector3(xb, yb, wb), Vector3(xb, yb, -wb), white, Vector3.UP)
	# cockpit sole, sides and seats
	var cy: float = sh.call(-0.5)
	b.box(Vector3(-1.4, cy - 0.30, 0.0), Vector3(4.2, 0.06, B * 0.80), _c(0.62, 0.60, 0.55, PAINT))
	b.box(Vector3(-0.55, cy - 0.06, 0.48), Vector3(0.62, 0.42, 0.62), seat)
	b.box(Vector3(-0.78, cy + 0.38, 0.48), Vector3(0.14, 0.62, 0.60), seat, Basis(Vector3.BACK, 0.22))
	b.box(Vector3(-0.55, cy - 0.06, -0.48), Vector3(0.62, 0.42, 0.62), seat)
	b.box(Vector3(-0.78, cy + 0.38, -0.48), Vector3(0.14, 0.62, 0.60), seat, Basis(Vector3.BACK, 0.22))
	b.box(Vector3(-3.05, cy - 0.04, 0.0), Vector3(0.75, 0.46, B * 0.78), seat)
	b.box(Vector3(-3.38, cy + 0.36, 0.0), Vector3(0.14, 0.50, B * 0.78), seat, Basis(Vector3.BACK, 0.15))
	# helm console (starboard) and passenger console
	b.box(Vector3(0.25, cy + 0.12, 0.48), Vector3(0.62, 0.78, 0.66), white)
	b.box(Vector3(0.25, cy + 0.12, -0.48), Vector3(0.62, 0.70, 0.66), white)
	b.box(Vector3(0.05, cy + 0.53, 0.48), Vector3(0.24, 0.05, 0.50), _c(0.08, 0.08, 0.09, PAINT), Basis(Vector3.BACK, 0.5))
	b.tube(Vector3(0.0, cy + 0.52, 0.48), Vector3(-0.07, cy + 0.66, 0.48), 0.02, chrome, 4)
	b.ellipsoid(Vector3(-0.09, cy + 0.69, 0.48), Vector3(0.03, 0.17, 0.17), _c(0.06, 0.06, 0.06, PAINT), 10, 3, Basis(Vector3.BACK, 0.45))
	# wrap-around windshield: raked centre panes and swept side panes in a frame
	var wx := 0.62
	var wy: float = cy + 0.50
	var wh := 0.52
	var rake := Basis(Vector3.BACK, 0.62)
	b.box(Vector3(wx, wy + wh * 0.42, 0.0), Vector3(0.03, wh, 1.95), glass, rake)
	for side in [-1.0, 1.0]:
		var bs := Basis(Vector3.UP, -side * 1.31)
		b.box(Vector3(wx - 0.37, wy + wh * 0.40, side * 1.07), Vector3(0.03, wh * 0.80, 0.72), glass, bs)
	var top_c := Vector3(wx - wh * 0.36, wy + wh * 0.84, 0.0)
	b.tube(top_c + Vector3(0, 0, -0.98), top_c + Vector3(0, 0, 0.98), 0.025, chrome, 5)
	for side in [-1.0, 1.0]:
		b.tube(top_c + Vector3(0, 0, side * 0.98), Vector3(wx - 0.72, wy + wh * 0.78, side * 1.16), 0.025, chrome, 5)
		b.tube(Vector3(wx - 0.72, wy + wh * 0.78, side * 1.16), Vector3(wx - 0.80, wy - 0.02, side * 1.17), 0.025, chrome, 5)
		b.tube(Vector3(wx + 0.15, wy, side * 0.98), top_c + Vector3(0, 0, side * 0.98), 0.022, chrome, 5)
		# spotlight on the frame: polished barrel with a lens
		var sp := top_c + Vector3(0.05, 0.10, side * 0.62)
		b.tube(top_c + Vector3(0, 0.0, side * 0.62), sp, 0.018, chrome, 4)
		b.tube(sp + Vector3(-0.07, 0, 0), sp + Vector3(0.10, 0, 0), 0.07, chrome, 8)
		b.box(sp + Vector3(0.105, 0, 0), Vector3(0.015, 0.11, 0.11), _c(1.0, 0.97, 0.85, GLASS))
	# bow rail on stanchions, meeting in a pulpit over the stem
	var rail_h := 0.42
	for side in [-1.0, 1.0]:
		var pts: Array[Vector3] = []
		var xr := 0.75
		while xr < L * 0.5 - 0.55:
			pts.append(Vector3(xr, sh.call(xr) + 0.05, side * (hw.call(xr) - 0.07)))
			xr += 0.55
		pts.append(Vector3(L * 0.5 - 0.42, sh.call(L * 0.5 - 0.42) + 0.05, side * 0.10))
		for k in pts.size():
			b.tube(pts[k], pts[k] + Vector3(0, rail_h, 0), 0.018, chrome, 4)
			if k > 0:
				b.tube(pts[k - 1] + Vector3(0, rail_h, 0), pts[k] + Vector3(0, rail_h, 0), 0.022, chrome, 5)
	b.tube(Vector3(L * 0.5 - 0.42, sh.call(L * 0.5 - 0.42) + 0.05 + rail_h, -0.10), Vector3(L * 0.5 - 0.42, sh.call(L * 0.5 - 0.42) + 0.05 + rail_h, 0.10), 0.022, chrome, 5)
	# cleats, fenders, stern grab rail
	for side in [-1.0, 1.0]:
		b.box(Vector3(L * 0.5 - 0.9, sh.call(L * 0.5 - 0.9) + 0.08, side * 0.35), Vector3(0.18, 0.05, 0.05), chrome)
		b.tube(Vector3(-L * 0.5 + 0.35, sh.call(-L * 0.5) + 0.0, side * (B * 0.5 - 0.12)), Vector3(-L * 0.5 + 0.35, sh.call(-L * 0.5) + 0.30, side * (B * 0.5 - 0.12)), 0.018, chrome, 4)
	b.tube(Vector3(-L * 0.5 + 0.35, sh.call(-L * 0.5) + 0.30, -(B * 0.5 - 0.12)), Vector3(-L * 0.5 + 0.35, sh.call(-L * 0.5) + 0.30, B * 0.5 - 0.12), 0.02, chrome, 5)
	# outboard: cowling, leg and cavitation plate
	var ox := -L * 0.5 - 0.30
	b.ellipsoid(Vector3(ox, fb + 0.35, 0.0), Vector3(0.36, 0.38, 0.26), _c(0.05, 0.05, 0.06, PAINT), 10, 6)
	b.box(Vector3(ox + 0.05, fb + 0.30, 0.0), Vector3(0.50, 0.06, 0.53), _c(0.75, 0.75, 0.76, CHROME))
	b.box(Vector3(ox - 0.02, fb - 0.35, 0.0), Vector3(0.22, 1.05, 0.14), _c(0.06, 0.06, 0.07, PAINT))
	b.box(Vector3(ox, -0.40, 0.0), Vector3(0.42, 0.04, 0.26), _c(0.06, 0.06, 0.07, PAINT))
	# crew: driver at the helm, passenger, someone on the stern bench
	b.person(Vector3(-0.55, cy + 0.17, 0.48), 0.0, true, _c(0.92, 0.70, 0.25, PAINT), 1.0, 0)
	b.person(Vector3(-0.55, cy + 0.17, -0.48), 0.0, true, _c(0.15, 0.42, 0.62, PAINT), 0.0, 2)
	b.person(Vector3(-3.0, cy + 0.19, 0.45), 0.0, true, _c(0.85, 0.22, 0.18, PAINT), 0.0, 1)
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
