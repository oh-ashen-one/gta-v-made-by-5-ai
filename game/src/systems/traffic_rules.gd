extends RefCounted
## traffic-flow (wave T): the road rules the lane traffic obeys, derived from
## the painted road itself so behaviour and markings agree.
##
## Integration S: the rendered Marina Bay drive spent 317 s of 663 s waiting
## (4 tows at Collyer Quay), the headless drive jammed at the Raffles Avenue /
## Bayfront corner, and queued cars stood on zebra crossings. Lane cars held
## their nose 10 m from every junction centre whatever the width of the road
## they were crossing, so on 14-24 m downtown roads the first car of every
## queue stood on (or past) the zebra and the stop line, and unsignalled
## T-junctions ran on the global signal clock with no lamps.
##
## This file answers, per directed lane edge:
##  - keep-clear intervals (zebras) in edge distance s, from the same
##    sampling the road painter uses (DowntownRoads._markings) and the legacy
##    district's crossing bands (WorldBuilder._junctions);
##  - the hold line (front bumper) just behind the painted stop line;
##  - the junction control: signal (lamps exist), major road (priority at an
##    unsignalled junction) or give way (the minor road of that junction).

const Roads := preload("res://src/world/downtown/roads.gd")
const Bridges := preload("res://src/world/downtown/bridges.gd")

const CONTROL_NONE := 0     # a bend: drive through
const CONTROL_SIGNAL := 1   # signal lamps at this junction: obey the phase
const CONTROL_MAJOR := 2    # unsignalled junction, priority road: go
const CONTROL_YIELD := 3    # unsignalled junction, minor road: give way

## Zebra crossings: [centre: Vector3, along: Vector3 (road direction), half_across: float, half_len: float].
static func zebras() -> Array:
	var out: Array = []
	# Downtown: the exact rule the painter uses (a zebra 3.5 m outside every
	# junction mouth, 3 m long along the road).
	for key: String in DowntownPlan.ROADS:
		var road: Dictionary = DowntownPlan.ROADS[key]
		var pts: Array = road["pts"]
		var hw := Roads.half_width(key)
		var prev_mouth := false
		var dash := 0
		for s: Array in Roads.samples(pts, 3.0):
			var p: Vector3 = s[0]
			var f: Vector3 = s[1]
			dash += 1
			if Roads.on_legacy_road(p.x, p.z, 1.0) or Roads.in_water(p.x, p.z) or Bridges.on_deck(p.x, p.z, 1.0):
				prev_mouth = false
				continue
			var mouth := Roads.on_road(p.x, p.z, key, 2.0)
			if mouth != prev_mouth and dash > 1:
				var dir := -1.0 if mouth else 1.0
				out.append([p + f * dir * 3.5, f, hw, 1.5])
			prev_mouth = mouth
	# Legacy district: a crossing band ROAD_HALF + 1.6 m out on every arm.
	for x: float in WorldBuilder.X_LINES:
		for z: float in WorldBuilder.Z_LINES:
			for d: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
				for side: float in [-1.0, 1.0]:
					out.append([Vector3(x, 0.0, z) + d * (WorldBuilder.ROAD_HALF + 1.6) * side, d, WorldBuilder.ROAD_HALF, 0.6])
	return out

## Downtown junction centres that carry signal lamps (DowntownRoads._signals).
static func signalled_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for j: Dictionary in Roads.junctions():
		var p: Vector3 = j["pos"]
		if not j["arterial"] or Roads.on_legacy_road(p.x, p.z, 10.0):
			continue
		out.append(p)
	return out

## The DowntownPlan road a lane segment lies on ("" if none): rank by kind and width.
static func road_rank(p: Vector3, q: Vector3) -> float:
	var mid := (p + q) * 0.5
	var best := -1.0
	for key: String in DowntownPlan.ROADS:
		var road: Dictionary = DowntownPlan.ROADS[key]
		var pts: Array = road["pts"]
		for k in pts.size() - 1:
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[k + 1]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var t := clampf(Vector2(mid.x - a.x, mid.z - a.z).dot(ab) / maxf(0.01, ab.length_squared()), 0.0, 1.0)
			if Vector2(mid.x - a.x, mid.z - a.z).distance_to(ab * t) < 2.0:
				var kind_rank := {"arterial": 100.0, "street": 50.0, "lane": 0.0}.get(String(road.get("kind", "street")), 50.0) as float
				best = maxf(best, kind_rank + float(road["width"]))
	if best < 0.0 and Roads.on_legacy_road(mid.x, mid.z, 0.5):
		best = 116.0   # legacy district avenues: signalled 16 m arterials
	return best

## Keep-clear intervals (Vector2(s_lo, s_hi), sorted) of a straight lane edge
## from a to b; `zs` is zebras().
static func clear_intervals(a: Vector3, dir: Vector3, left: Vector3, length: float, zs: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for z: Array in zs:
		var f: Vector3 = z[1]
		if absf(f.dot(dir)) < 0.8:
			continue
		var rel: Vector3 = (z[0] as Vector3) - a
		rel.y = 0.0
		var along := rel.dot(dir)
		if along < -3.0 or along > length + 3.0:
			continue
		if absf(rel.dot(left)) > float(z[2]) + 0.5:
			continue
		var hl := float(z[3]) + 0.45
		out.append(Vector2(along - hl, along + hl))
	out.sort_custom(func(u: Vector2, v: Vector2) -> bool: return u.x < v.x)
	return out
