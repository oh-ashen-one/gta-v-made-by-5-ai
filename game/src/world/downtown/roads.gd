extends RefCounted
## downtown-map: the downtown road network (DOWNTOWN_PLAN section 5).
##
## Every ROADS entry becomes an asphalt carriageway (one surface per material
## per cell), 16 cm kerbs with 3 m raised footways that open at junction
## mouths, Singapore markings (double yellow kerb lines, white lane dashes,
## double white centre lines on the arterials), planted medians on Bayfront
## Avenue, signals at arterial junctions, lamps and street trees. Surfaces
## follow Bridges.height_at(), so they climb onto the bridges without steps.
## build_lanes() publishes world.downtown_graph (left-hand lanes) and
## world.downtown_ped_lanes; legacy traffic_nodes are never touched.

const Bridges := preload("res://src/world/downtown/bridges.gd")
const STEP := 4.0
const FOOTWAY := 3.0
const ROAD_TOP := 0.06
const FOOT_TOP := 0.16
const WALK_TOP := 0.30
const LANE_W := 3.5

# ------------------------------------------------------------ queries
static func half_width(key: String) -> float:
	return float(DowntownPlan.ROADS[key]["width"]) * 0.5

## Legacy district carriageways (WorldBuilder._roads: 16 m wide, 760 m long).
static func on_legacy_road(x: float, z: float, margin: float = 0.0) -> bool:
	for lx: float in DowntownPlan.LEGACY["x_lines"]:
		if absf(x - lx) < 8.0 + margin and absf(z) < 380.0 + margin:
			return true
	for lz: float in DowntownPlan.LEGACY["z_lines"]:
		if absf(z - lz) < 8.0 + margin and absf(x) < 380.0 + margin:
			return true
	return false

static func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## True when (x, z) is on the carriageway of a downtown road other than `skip`
## (margin widens it), or on a vehicle bridge deck.
static func on_road(x: float, z: float, skip: String = "", margin: float = 0.0) -> bool:
	var p := Vector2(x, z)
	for key: String in DowntownPlan.ROADS:
		if key == skip:
			continue
		var pts: Array = DowntownPlan.ROADS[key]["pts"]
		var hw := half_width(key) + margin
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			if _dist_seg(p, Vector2(a.x, a.z), Vector2(b.x, b.z)) < hw:
				return true
	return false

static func in_water(x: float, z: float) -> bool:
	var Shoreline := preload("res://src/world/downtown/shoreline.gd")
	return Shoreline.is_water_ext(x, z) and not Bridges.on_deck(x, z, 0.5)

## Sample a polyline every ~STEP metres: [pos, dir] pairs (pos.y = 0).
static func samples(pts: Array, step: float = STEP) -> Array:
	var out: Array = []
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		a.y = 0.0
		b.y = 0.0
		var n := maxi(1, int(ceil(a.distance_to(b) / step)))
		var f := (b - a).normalized()
		for s in n + (1 if i == pts.size() - 2 else 0):
			out.append([a.lerp(b, float(s) / n), f])
	return out

static func left_of(f: Vector3) -> Vector3:
	# the left of travel direction f on the ground plane (UP x f)
	return Vector3(f.z, 0.0, -f.x)

# ------------------------------------------------------------ build
static func build(m) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7702
	var white: Array[Transform3D] = []
	var yellow: Array[Transform3D] = []
	for key: String in DowntownPlan.ROADS:
		var road: Dictionary = DowntownPlan.ROADS[key]
		var pts: Array = road["pts"]
		var hw := half_width(key)
		var skip := func(p: Vector3) -> bool:
			return on_legacy_road(p.x, p.z, -0.2) or in_water(p.x, p.z)
		_ribbon(m, "asphalt", pts, 0.0, hw, ROAD_TOP, skip, true, 0.6)
		# footways both sides, open at the mouths of crossing roads
		for side: float in [-1.0, 1.0]:
			var off := side * (hw + FOOTWAY * 0.5)
			var fskip := func(p: Vector3) -> bool:
				return on_legacy_road(p.x, p.z, 4.0) or in_water(p.x, p.z) or on_road(p.x, p.z, key, 0.5) or Bridges.on_deck(p.x, p.z, 1.0)
			_ribbon(m, "pavers", pts, off, FOOTWAY * 0.5, FOOT_TOP, fskip, true, 0.4, "kerb")
		_markings(m, key, road, white, yellow)
		if float(road.get("median", 0.0)) > 0.0:
			_median(m, key, pts, float(road["median"]), rng)
		_street_dressing(m, key, road, rng)
	# vehicle bridge deck markings
	for p: Dictionary in Bridges.profiles():
		if p["kind"] != "vehicle":
			continue
		var c: Vector3 = p["c"]
		var d: Vector3 = p["d"]
		var span: float = p["span"]
		var pts2 := [c - d * (span + 4.0), c + d * (span + 4.0)]
		var lanes: int = p["lanes"]
		for s: Array in samples(pts2, 12.0):
			var q: Vector3 = s[0]
			var f: Vector3 = s[1]
			var l := left_of(f)
			for k in range(1, lanes):
				for sd: float in [-1.0, 1.0]:
					white.append(_mark(q + l * sd * k * LANE_W, f, Vector3(0.14, 1.0, 5.0)))
			for sd2: float in [-1.0, 1.0]:
				white.append(_mark(q + l * sd2 * 0.18, f, Vector3(0.12, 1.0, 12.0)))
	_batch_marks(m, white, "paint_white")
	_batch_marks(m, yellow, "paint_yellow")
	_walks(m, rng)
	_signals(m)
	street_furniture(m)

## A surface ribbon along pts, offset `off` to the left of travel, half width
## hw, top `top` above Bridges.height_at(). Skipped samples split it into runs.
## Skirts drop each edge to the ground (they are the kerb faces of footways).
static func _ribbon(m, key: String, pts: Array, off: float, hw: float, top: float, skip: Callable, collide: bool, thick: float, skirt_key: String = "") -> void:
	var ss := samples(pts)
	var run: Array = []
	var runs: Array = []
	var last_bad := Vector3.INF
	var last_bad_f := Vector3.ZERO
	for s: Array in ss:
		var p: Vector3 = s[0]
		var f: Vector3 = s[1]
		var c := p + left_of(f) * off
		if skip.call(c):
			if not run.is_empty():
				# close the run exactly at the boundary (bisection), not on the 4 m grid
				var good: Vector3 = run[run.size() - 1][0]
				if good.distance_to(c) < STEP * 1.5 and f.dot(run[run.size() - 1][1]) > 0.99:
					run.append([_edge(good, c, skip), f])
			if run.size() >= 2: runs.append(run)
			run = []
			last_bad = c
			last_bad_f = f
			continue
		if run.is_empty() and last_bad != Vector3.INF and last_bad.distance_to(c) < STEP * 1.5 and f.dot(last_bad_f) > 0.99:
			run.append([_edge(c, last_bad, skip), f])
		run.append([c, f])
	if run.size() >= 2: runs.append(run)
	for r: Array in runs:
		var flat_a := Vector3.INF
		var flat_b := Vector3.INF
		var flat_f := Vector3.ZERO
		for i in r.size() - 1:
			var a: Vector3 = r[i][0]
			var b: Vector3 = r[i + 1][0]
			if a.distance_to(b) > STEP * 2.5:
				continue   # a bend: the two legs are joined by the joint fan
			var fa: Vector3 = r[i][1]
			var fb: Vector3 = r[i + 1][1]
			var la := left_of(fa)
			var lb := left_of(fb)
			var ha := Bridges.height_at(a.x, a.z)
			var hb := Bridges.height_at(b.x, b.z)
			var a0 := a + la * hw
			var a1 := a - la * hw
			var b0 := b + lb * hw
			var b1 := b - lb * hw
			a0.y = Bridges.height_at(a0.x, a0.z) + top
			a1.y = Bridges.height_at(a1.x, a1.z) + top
			b0.y = Bridges.height_at(b0.x, b0.z) + top
			b1.y = Bridges.height_at(b1.x, b1.z) + top
			m.quad_up(key, a0, b0, b1, a1)
			var sk := skirt_key if skirt_key != "" else key
			for edge: Array in [[a0, b0, 1.0], [a1, b1, -1.0]]:
				var e0: Vector3 = edge[0]
				var e1: Vector3 = edge[1]
				if e0.y > 0.015 or e1.y > 0.015:
					m.quad_side(sk, e0, e1, Vector3(e1.x, -0.02, e1.z), Vector3(e0.x, -0.02, e0.z), edge[2])
			if not collide:
				continue
			if ha > 0.05 or hb > 0.05:
				if flat_a != Vector3.INF:
					_flat_col(m, flat_a, flat_b, hw, top)
					flat_a = Vector3.INF
				var ca := a
				var cb := b
				ca.y = ha + top
				cb.y = hb + top
				m.pitched_box(ca, cb, hw * 2.0, thick, Vector3(0, -thick * 0.5, 0))
			elif top > 0.1:
				# flat raised runs merge into one box per straight stretch
				if flat_a != Vector3.INF and fa.dot(flat_f) > 0.999 and flat_b.distance_to(a) < 0.01:
					flat_b = b
				else:
					if flat_a != Vector3.INF:
						_flat_col(m, flat_a, flat_b, hw, top)
					flat_a = a
					flat_b = b
					flat_f = fa
		if flat_a != Vector3.INF:
			_flat_col(m, flat_a, flat_b, hw, top)
	# joint fans at polyline bends
	for i in range(1, pts.size() - 1):
		var v: Vector3 = pts[i]
		var fin: Vector3 = (pts[i] - pts[i - 1]).normalized()
		var fout: Vector3 = (pts[i + 1] - pts[i]).normalized()
		var fm := (fin + fout).normalized()
		var c2 := v + left_of(fm) * off
		c2.y = 0.0
		if skip.call(c2):
			continue
		var n := 10
		for k in n:
			var a2 := TAU * k / n
			var b2 := TAU * (k + 1) / n
			var pa := c2 + Vector3(cos(a2), 0, sin(a2)) * hw
			var pb := c2 + Vector3(cos(b2), 0, sin(b2)) * hw
			var cc := c2
			pa.y = Bridges.height_at(pa.x, pa.z) + top
			pb.y = Bridges.height_at(pb.x, pb.z) + top
			cc.y = Bridges.height_at(cc.x, cc.z) + top + 0.002
			m.quad_up(key, cc, pa, pb, cc)
		if collide and Bridges.height_at(c2.x, c2.z) > 0.05:
			var ctop := c2
			ctop.y = Bridges.height_at(c2.x, c2.z) + top
			m.col_box(Vector3(hw * 2.0, thick, hw * 2.0), ctop - Vector3(0, thick * 0.5, 0))

## Boundary between a kept point and a skipped one, to ~3 cm.
static func _edge(good: Vector3, bad: Vector3, skip: Callable) -> Vector3:
	var a := good
	var b := bad
	for i in 7:
		var mid := (a + b) * 0.5
		if skip.call(mid):
			b = mid
		else:
			a = mid
	return a

static func _flat_col(m, a: Vector3, b: Vector3, hw: float, top: float) -> void:
	var ca := Vector3(a.x, top, a.z)
	var cb := Vector3(b.x, top, b.z)
	m.pitched_box(ca, cb, hw * 2.0, top + 0.05, Vector3(0, -(top + 0.05) * 0.5, 0))

static func _mark(p: Vector3, f: Vector3, size: Vector3) -> Transform3D:
	var h := Bridges.height_at(p.x, p.z)
	var ahead := p + f * 1.0
	var h2 := Bridges.height_at(ahead.x, ahead.z)
	var fwd := Vector3(f.x, h2 - h, f.z).normalized()
	var across := Vector3.UP.cross(fwd).normalized()
	var up := fwd.cross(across).normalized()
	var basis := Basis(across * size.x, up * 0.02, fwd * size.z)
	return Transform3D(basis, Vector3(p.x, h + 0.075, p.z))

static func _markings(m, key: String, road: Dictionary, white: Array[Transform3D], yellow: Array[Transform3D]) -> void:
	var pts: Array = road["pts"]
	var hw := half_width(key)
	var lanes: int = road["lanes"]
	var median := float(road.get("median", 0.0))
	var dash := 0
	var prev_mouth := false
	for s: Array in samples(pts, 3.0):
		var p: Vector3 = s[0]
		var f: Vector3 = s[1]
		var l := left_of(f)
		dash += 1
		if on_legacy_road(p.x, p.z, 1.0) or in_water(p.x, p.z) or Bridges.on_deck(p.x, p.z, 1.0):
			prev_mouth = false
			continue
		var mouth := on_road(p.x, p.z, key, 2.0)
		if mouth != prev_mouth and dash > 1:
			# zebra crossing and stop line at each junction mouth (approach side)
			var dir := -1.0 if mouth else 1.0
			var zc := p + f * dir * 3.5
			var across := hw - 1.0
			var k2 := -across + 0.5
			while k2 < across:
				white.append(_mark(zc + l * k2, f, Vector3(0.5, 1.0, 3.0)))
				k2 += 1.1
			var stop_side := 1.0 if mouth else -1.0
			white.append(_mark(p + f * dir * 6.6 + l * stop_side * (median * 0.5 + (hw - median * 0.5) * 0.5), f, Vector3(hw - median * 0.5 - 0.6, 1.0, 0.4)))
		prev_mouth = mouth
		if mouth or dash % 2 == 0:
			continue
		for side: float in [-1.0, 1.0]:
			# double yellow no-parking lines along both kerbs
			for o: float in [hw - 0.35, hw - 0.58]:
				yellow.append(_mark(p + l * side * o, f, Vector3(0.12, 1.0, 6.05)))
			# lane dividers (dashed white)
			for k in range(1, lanes):
				if dash % 4 == 1:
					white.append(_mark(p + l * side * (median * 0.5 + k * LANE_W), f, Vector3(0.14, 1.0, 4.0)))
		if median <= 0.0:
			if lanes >= 2:
				for o2: float in [-0.18, 0.18]:
					white.append(_mark(p + l * o2, f, Vector3(0.12, 1.0, 6.05)))
			elif dash % 4 == 1:
				white.append(_mark(p, f, Vector3(0.14, 1.0, 4.0)))

static func _batch_marks(m, xforms: Array[Transform3D], key: String) -> void:
	m._mm(m._unit_mesh("box"), xforms, m.mat(key), false, 0.0, "DowntownMarkings")

## Raised planted median (Bayfront Avenue), broken at junction mouths, solid.
static func _median(m, key: String, pts: Array, width: float, rng: RandomNumberGenerator) -> void:
	var skip := func(p: Vector3) -> bool:
		return on_road(p.x, p.z, key, 6.0) or in_water(p.x, p.z) or Bridges.on_deck(p.x, p.z, 4.0) or Bridges.height_at(p.x, p.z) > 0.05
	_ribbon(m, "kerb", pts, 0.0, width * 0.5, 0.26, skip, true, 0.9)
	_ribbon(m, "turf", pts, 0.0, width * 0.5 - 0.3, 0.30, skip, false, 0.3)
	var k := 0
	for s: Array in samples(pts, 9.0):
		var p: Vector3 = s[0]
		k += 1
		if k % 3 != 0 or skip.call(p):
			continue
		m.tree(Vector3(p.x, 0.3, p.z), rng.randf_range(0.85, 1.15), rng)

## Lamps on both kerbs every ~32 m, street trees on the arterials' footways.
static func _street_dressing(m, key: String, road: Dictionary, rng: RandomNumberGenerator) -> void:
	var pts: Array = road["pts"]
	var hw := half_width(key)
	var arterial := String(road["kind"]) == "arterial"
	var i := 0
	for s: Array in samples(pts, 16.0):
		var p: Vector3 = s[0]
		var f: Vector3 = s[1]
		var l := left_of(f)
		i += 1
		for side: float in [-1.0, 1.0]:
			var lp := p + l * side * (hw + 0.55)
			if on_legacy_road(lp.x, lp.z, 6.0) or in_water(lp.x, lp.z) or on_road(lp.x, lp.z, key, 3.0) or Bridges.on_deck(lp.x, lp.z, 2.0):
				continue
			var h := Bridges.height_at(lp.x, lp.z)
			if (i + (1 if side > 0.0 else 0)) % 2 == 0:
				m.lamp(Vector3(lp.x, h + FOOT_TOP, lp.z), "modern")
			elif arterial and h < 0.05:
				var tp := p + l * side * (hw + FOOTWAY - 0.6)
				m.tree(Vector3(tp.x, FOOT_TOP, tp.z), rng.randf_range(0.75, 1.05), rng)

## Promenades, river walks and plazas (pavers at +0.3, raised with collision).
static func _walks(m, rng: RandomNumberGenerator) -> void:
	for key: String in DowntownPlan.PROMENADES:
		var walk: Dictionary = DowntownPlan.PROMENADES[key]
		var pts: Array = walk["pts"].duplicate()
		var hw := float(walk["width"]) * 0.5
		var legacy: Vector2 = walk.get("legacy_span_x", Vector2.ZERO)
		var skip := func(p: Vector3) -> bool:
			if legacy != Vector2.ZERO and p.x > legacy.x + 0.4 and p.x < legacy.y - 0.4:
				return true
			return in_water(p.x, p.z) or on_road(p.x, p.z, "", 0.5) or on_legacy_road(p.x, p.z, 0.5)
		# walks sit at kerb height (0.16) so they are stepped onto from the
		# ground anywhere; only the west shore extension matches the legacy
		# promenade deck it continues (0.30)
		var walk_top := WALK_TOP if legacy != Vector2.ZERO else FOOT_TOP
		_ribbon(m, "pavers_warm", pts, 0.0, hw, walk_top, skip, true, 0.3, "granite_coping")
		# trees + lamps along the inland edge of the wider walks
		var i := 0
		for s: Array in samples(pts, 14.0):
			var p: Vector3 = s[0]
			var f: Vector3 = s[1]
			i += 1
			if skip.call(p):
				continue
			var l := left_of(f)
			for side: float in [-1.0, 1.0]:
				var q := p + l * side * (hw - 1.4)
				if in_water(q.x, q.z) or skip.call(q):
					continue
				var h := maxf(Bridges.height_at(q.x, q.z) + 0.065, WALK_TOP if legacy != Vector2.ZERO else FOOT_TOP)
				if i % 2 == 0:
					m.lamp(Vector3(q.x, h, q.z), "heritage")
				elif hw >= 6.0 and i % 4 == 1 and Bridges.height_at(q.x, q.z) < 0.05:
					var tq := p + l * side * (hw - 3.5)
					if not in_water(tq.x, tq.z):
						m.tree(Vector3(tq.x, WALK_TOP if legacy != Vector2.ZERO else FOOT_TOP, tq.z), rng.randf_range(0.9, 1.3), rng)

## Signals at every junction where an arterial meets another road.
static func _signals(m) -> void:
	var done := {}
	for j: Dictionary in junctions():
		var p: Vector3 = j["pos"]
		if not j["arterial"] or on_legacy_road(p.x, p.z, 10.0):
			continue
		var k := Vector2i(roundi(p.x), roundi(p.z))
		if done.has(k):
			continue
		done[k] = true
		var r := float(j["r"]) + 1.2
		m.world._traffic_light(Vector3(p.x - r, 0.16, p.z - r), 0)
		m.world._traffic_light(Vector3(p.x + r, 0.16, p.z + r), 1)
	m.stats["signals"] = done.size() * 2

## Street-name blades (white on blue, real road names as public wayfinding
## facts) at every downtown junction, and bus shelters on the arterials.
static func street_furniture(m) -> void:
	var post_mat := Palette.mat_textured(Palette.METAL_DARK, "metal", Vector3.ONE, 0.6, 0.4)
	var done := {}
	for j: Dictionary in junctions():
		var p: Vector3 = j["pos"]
		if on_legacy_road(p.x, p.z, 12.0) or not DowntownPlan.ROADS.has(j["roads"][0]) or not DowntownPlan.ROADS.has(j["roads"][1]):
			continue
		var k := Vector2i(roundi(p.x), roundi(p.z))
		if done.has(k):
			continue
		done[k] = true
		var r := float(j["r"]) + 2.0
		var pole := Vector3(p.x + r, FOOT_TOP, p.z - r)
		if in_water(pole.x, pole.z) or on_road(pole.x, pole.z, "", 0.3):
			pole = Vector3(p.x - r, FOOT_TOP, p.z + r)
		if in_water(pole.x, pole.z) or on_road(pole.x, pole.z, "", 0.3):
			continue
		m.world._cyl(Vector3(0.1, 3.1, 0.1), pole + Vector3(0.0, 1.55, 0.0), post_mat)
		for n in 2:
			var road_key: String = j["roads"][n]
			var d: Vector3 = j["dirs"][n]
			var text := road_key.replace("_", " ").capitalize().replace("Quay", "Quay")
			m.world._street_blade(pole + Vector3(0.0, 2.95 - n * 0.35, 0.0), absf(d.x) > absf(d.z), text)
	# bus shelters on the bay-side footways of the arterials running along x
	for key: String in ["bayfront_avenue", "bayfront_avenue_north", "esplanade_drive", "collyer_quay", "marina_way", "anson_road"]:
		var pts: Array = DowntownPlan.ROADS[key]["pts"]
		var hw := half_width(key)
		var n2 := 0
		for s: Array in samples(pts, 90.0):
			var q: Vector3 = s[0]
			n2 += 1
			if n2 % 2 == 0:
				continue
			var at := Vector3(q.x, FOOT_TOP, q.z - hw - FOOTWAY * 0.5 - 0.2)
			if on_legacy_road(at.x, at.z, 6.0) or on_road(at.x, at.z, key, 8.0) or in_water(at.x, at.z) or Bridges.height_at(at.x, at.z) > 0.0:
				continue
			m.world._bus_shelter(at)

# ------------------------------------------------------------ graph
## Directed-free segment list: road and vehicle-bridge centrelines.
static func segments() -> Array:
	var segs: Array = []
	for key: String in DowntownPlan.ROADS:
		var road: Dictionary = DowntownPlan.ROADS[key]
		var pts: Array = road["pts"]
		var legacy: Vector2 = road.get("legacy_span_x", Vector2.ZERO)
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			if legacy != Vector2.ZERO:
				# keep only the parts beyond the existing district road
				if a.x > legacy.y and b.x < legacy.y:
					segs.append({"a": a, "b": Vector3(legacy.y, 0, a.z), "lanes": int(road["lanes"]), "road": key})
					if b.x < legacy.x:
						segs.append({"a": Vector3(legacy.x, 0, a.z), "b": b, "lanes": int(road["lanes"]), "road": key})
					continue
			segs.append({"a": a, "b": b, "lanes": int(road["lanes"]), "road": key, "arterial": String(road["kind"]) == "arterial"})
	for p: Dictionary in Bridges.profiles():
		if p["kind"] != "vehicle":
			continue
		var b2: Dictionary = DowntownPlan.BRIDGES[p["name"]]
		segs.append({"a": b2["from"], "b": b2["to"], "lanes": int(p["lanes"]), "road": p["name"], "arterial": true})
	return segs

static func _seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Variant:
	var r := b - a
	var s := d - c
	var den := r.cross(s)
	if absf(den) < 0.0001:
		return null
	var t := (c - a).cross(s) / den
	var u := (c - a).cross(r) / den
	if t < -0.001 or t > 1.001 or u < -0.001 or u > 1.001:
		return null
	return a + r * t

## Junction points (crossings, T-junctions and shared ends) between segments.
static func junctions() -> Array:
	var segs := segments()
	var out: Array = []
	for i in segs.size():
		for j in range(i + 1, segs.size()):
			var a: Vector3 = segs[i]["a"]
			var b: Vector3 = segs[i]["b"]
			var c: Vector3 = segs[j]["a"]
			var d: Vector3 = segs[j]["b"]
			var hit: Variant = _seg_cross(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z))
			if hit == null:
				continue
			var h: Vector2 = hit
			var r := maxf(half_width(segs[i]["road"]) if DowntownPlan.ROADS.has(segs[i]["road"]) else 12.0, half_width(segs[j]["road"]) if DowntownPlan.ROADS.has(segs[j]["road"]) else 12.0)
			out.append({"pos": Vector3(h.x, 0, h.y), "arterial": bool(segs[i].get("arterial", false)) or bool(segs[j].get("arterial", false)), "r": r,
				"roads": [segs[i]["road"], segs[j]["road"]], "dirs": [(b - a).normalized(), (d - c).normalized()]})
	return out

static func build_lanes(m, w: WorldBuilder) -> void:
	var segs := segments()
	var nodes: Array[Vector3] = []
	var find := func(p: Vector3) -> int:
		for k in nodes.size():
			if Vector2(nodes[k].x - p.x, nodes[k].z - p.z).length() < 1.5:
				return k
		nodes.append(Vector3(p.x, 0.1, p.z))
		return nodes.size() - 1
	var edges: Array[Vector2i] = []
	var lanes: Array[int] = []
	for s: Dictionary in segs:
		var a: Vector3 = s["a"]
		var b: Vector3 = s["b"]
		var ts: Array[float] = [0.0, 1.0]
		for o: Dictionary in segs:
			if o == s:
				continue
			var hit: Variant = _seg_cross(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(o["a"].x, o["a"].z), Vector2(o["b"].x, o["b"].z))
			if hit != null:
				var h: Vector2 = hit
				var ab := Vector2(b.x - a.x, b.z - a.z)
				ts.append(clampf((h - Vector2(a.x, a.z)).dot(ab) / ab.length_squared(), 0.0, 1.0))
		ts.sort()
		var prev := -1
		for t in ts:
			var q := a.lerp(b, t)
			var idx: int = find.call(q)
			if prev >= 0 and idx != prev:
				var e := Vector2i(mini(prev, idx), maxi(prev, idx))
				if not edges.has(e):
					edges.append(e)
					lanes.append(int(s["lanes"]))
			prev = idx
	for k in nodes.size():
		nodes[k].y = Bridges.height_at(nodes[k].x, nodes[k].z) + 0.1
	var links: Array[Vector2i] = []
	for k in nodes.size():
		for li in w.traffic_nodes.size():
			var tn := w.traffic_nodes[li]
			if Vector2(tn.x - nodes[k].x, tn.z - nodes[k].z).length() < 1.5:
				links.append(Vector2i(k, li))
	# kerbside parking on the quieter streets (left kerb of travel)
	var parked: Array[Dictionary] = []
	var kinds := ["sedan", "coupe", "van"]
	for key: String in ["cecil_street", "central_boulevard", "marina_way", "connaught_drive", "north_bridge_road", "anson_road"]:
		var pts: Array = DowntownPlan.ROADS[key]["pts"]
		var hw := half_width(key)
		var n := 0
		for s2: Array in samples(pts, 23.0):
			var p: Vector3 = s2[0]
			var f: Vector3 = s2[1]
			n += 1
			if n % 2 == 0 or on_road(p.x, p.z, key, 14.0) or on_legacy_road(p.x, p.z, 14.0):
				continue
			var spot := p + left_of(f) * (hw - 1.35)
			parked.append({"pos": Vector3(spot.x, 0.3, spot.z), "heading": atan2(-f.x, -f.z), "kind": kinds[parked.size() % 3], "road": key})
	w.downtown_graph = {"nodes": nodes, "edges": edges, "lanes": lanes, "links": links, "parked": parked,
		"lane_width": LANE_W, "left_hand": true, "plan": DowntownPlan.PLAN_VERSION}
	# pedestrian polylines: footway centrelines of every road + every walk
	var peds: Array = []
	for key2: String in DowntownPlan.ROADS:
		var pts2: Array = DowntownPlan.ROADS[key2]["pts"]
		var hw2 := half_width(key2)
		for side: float in [-1.0, 1.0]:
			var line: Array[Vector3] = []
			for s3: Array in samples(pts2, 20.0):
				var p3: Vector3 = s3[0] + left_of(s3[1]) * side * (hw2 + FOOTWAY * 0.5)
				if in_water(p3.x, p3.z):
					continue
				line.append(Vector3(p3.x, Bridges.height_at(p3.x, p3.z) + 0.25, p3.z))
			if line.size() >= 2:
				peds.append(line)
	for key3: String in DowntownPlan.PROMENADES:
		var line2: Array[Vector3] = []
		for s4: Array in samples(DowntownPlan.PROMENADES[key3]["pts"], 20.0):
			var p4: Vector3 = s4[0]
			if not in_water(p4.x, p4.z):
				line2.append(Vector3(p4.x, maxf(Bridges.height_at(p4.x, p4.z), 0.3) + 0.1, p4.z))
		if line2.size() >= 2:
			peds.append(line2)
	w.downtown_ped_lanes = peds
	m.stats["graph_nodes"] = nodes.size()
	m.stats["graph_edges"] = edges.size()
	m.stats["graph_links"] = links.size()
	print("[downtown-map] lane graph: %d nodes, %d edges, %d legacy links, %d parked, %d ped lanes" % [nodes.size(), edges.size(), links.size(), parked.size(), peds.size()])
