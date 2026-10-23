extends RefCounted
## downtown-fill (wave T, round 2): near-field fill in front of the street
## cameras at the arrival points. Critic gap: "the bottom 40% of the frame (the
## plaza between camera and crowd) reads as an empty, uniform slab" and "no bare
## paved square larger than 12 x 12 m within 30 m of each camera".
##   - a paving layout: dark granite joint bands on a 3 m grid with 9 m
##     feature courses and worn / stained setts, over every slab in the wedge;
##   - furniture clusters on a jittered 6 m grid inside each camera's forward
##     wedge (5..32 m): planters with ferns, umbrella tables, bench + bin pairs,
##     bike racks, bollard groups and wayfinding totems;
##   - helipad rings, the review walk corridors, fountains and existing palms
##     stay clear (Plazas._clear plus a spacing check).
## Original procedural geometry on the landmarks' shared materials.

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")

const NONE := -999.0
## [name, pos, look] of the street stills this fills in front of.
const CAMS := [
	["street_mbs_arrival", Vector3(-203.0, 1.7, -763.0), Vector3(-160.0, 7.0, -738.0)],
	["street_mbs_walk_end", Vector3(-246.0, 1.7, -760.0), Vector3(-214.0, 14.0, -722.0)],
	["dt_merlion_park_to_mbs", Vector3(-470.0, 1.7, -395.0), Vector3(-118.0, 90.0, -705.0)],
	["street_ns_square", Vector3(-632.0, 1.8, -586.0), Vector3(-545.0, 6.0, -648.0)],
	["street_ns_square_cafe", Vector3(-596.0, 1.7, -598.0), Vector3(-530.0, 4.0, -628.0)],
]
const HALF_DEG := 40.0
const R_NEAR := 4.5
const R_FAR := 32.0

static func _in_wedge(cam: Array, p: Vector2, r_far: float = R_FAR, r_near: float = 0.0) -> bool:
	var c: Vector3 = cam[1]
	var lk: Vector3 = cam[2]
	var d := p - Vector2(c.x, c.z)
	var l := d.length()
	if l > r_far or l < r_near:
		return false
	var f := Vector2(lk.x - c.x, lk.z - c.z).normalized()
	return rad_to_deg(absf(f.angle_to(d))) < HALF_DEG + 8.0

## avoid: Array of Vector3 already standing; fountains: Array of Vector3 (r 16 m).
## Ground heights and clearance come from plazas.gd (loaded at run time, not
## preloaded, so the two scripts do not preload each other).
static func build(kit: Kit, rng: RandomNumberGenerator, avoid: Array, fountains: Array,
		benches: Array, bollards: Array, umbrellas: Dictionary) -> Dictionary:
	var pz: GDScript = load("res://src/world/downtown/plazas.gd")
	var st := {"joints": 0, "clusters": 0, "planters": 0, "tables": 0, "bench_bins": 0, "racks": 0, "bollard_groups": 0, "totems": 0, "stains": 0}
	var joint: Material = Looks.get_mat("granite_dark")
	var light: Material = Looks.get_mat("granite_light")
	var steel: Material = Looks.get_mat("steel_dark")
	var placed: Array = avoid.duplicate()
	for cam: Array in CAMS:
		var c: Vector3 = cam[1]
		# --- paving layout: joint bands on a 3 m grid inside the wedge ---
		var x0 := floorf((c.x - R_FAR) / 3.0) * 3.0
		var z0 := floorf((c.z - R_FAR) / 3.0) * 3.0
		for i in 23:
			for j in 23:
				var gx := x0 + i * 3.0
				var gz := z0 + j * 3.0
				# segment along x from (gx, gz) and along z from (gx, gz)
				for axis in 2:
					var a := Vector2(gx, gz)
					var b := a + (Vector2(3.0, 0.0) if axis == 0 else Vector2(0.0, 3.0))
					var mid := (a + b) * 0.5
					if not _in_wedge(cam, mid, R_FAR + 2.0, 1.0):
						continue
					var y: float = pz.ground_y(mid.x, mid.y, NONE)
					if y == NONE or absf(pz.ground_y(a.x, a.y, NONE) - y) > 0.01 or absf(pz.ground_y(b.x, b.y, NONE) - y) > 0.01:
						continue
					var feature := (axis == 0 and int(round(gz / 3.0)) % 3 == 0) or (axis == 1 and int(round(gx / 3.0)) % 3 == 0)
					var w := 0.42 if feature else 0.07
					var mat := light if feature else joint
					var sz := Vector3(3.0 + w, 0.016, w) if axis == 0 else Vector3(w, 0.016, 3.0 + w)
					kit.box(mat, Vector3(mid.x, y + 0.008 + (0.002 if feature else 0.0), mid.y), sz)
					st["joints"] += 1
				# worn / stained sett patches
				var sp := Vector2(gx + rng.randf_range(0.4, 2.6), gz + rng.randf_range(0.4, 2.6))
				if rng.randf() < 0.16 and _in_wedge(cam, sp, R_FAR, 2.0):
					var sy: float = pz.ground_y(sp.x, sp.y, NONE)
					if sy != NONE:
						var s := rng.randf_range(0.6, 1.6)
						kit.box(joint, Vector3(sp.x, sy + 0.005, sp.y), Vector3(s, 0.01, s * rng.randf_range(0.5, 1.0)), Basis(Vector3.UP, rng.randf_range(0, PI)))
						st["stains"] += 1
		# --- furniture clusters on a jittered 6 m grid in the wedge ---
		var fx0 := c.x - R_FAR
		var fz0 := c.z - R_FAR
		for i in 15:
			for j in 15:
				var p := Vector2(fx0 + (i + rng.randf_range(0.2, 0.8)) * 4.5, fz0 + (j + rng.randf_range(0.2, 0.8)) * 4.5)
				if not _in_wedge(cam, p, R_FAR, R_NEAR):
					continue
				if rng.randf() < 0.1:
					continue
				var y: float = pz.ground_y(p.x, p.y, NONE)
				if y == NONE:
					continue
				var q := Vector3(p.x, y, p.y)
				if not pz._free(q):
					continue
				var ok := true
				for o: Vector3 in placed:
					if Vector2(o.x - q.x, o.z - q.z).length() < 3.2:
						ok = false
						break
				for f: Vector3 in fountains:
					if Vector2(f.x - q.x, f.z - q.z).length() < 16.0:
						ok = false
				# the whole footprint must sit on the same slab
				for off: Vector2 in [Vector2(1.6, 1.6), Vector2(-1.6, 1.6), Vector2(1.6, -1.6), Vector2(-1.6, -1.6)]:
					if absf(pz.ground_y(p.x + off.x, p.y + off.y, NONE) - y) > 0.01:
						ok = false
				if not ok:
					continue
				placed.append(q)
				st["clusters"] += 1
				var yaw := rng.randf_range(-PI, PI)
				var roll := rng.randf()
				if roll < 0.28:
					var size := Vector2(rng.randf_range(1.6, 2.8), rng.randf_range(1.1, 1.6))
					Realm.planter(kit, q, size, rng.randf_range(0.45, 0.65))
					kit.col_box(Vector3(size.x, 0.6, size.y), q + Vector3(0, 0.3, 0))
					st["planters"] += 1
				elif roll < 0.5:
					var fabrics := umbrellas.keys()
					(umbrellas[fabrics[rng.randi() % fabrics.size()]] as Array).append(Kit.xf(q, yaw))
					st["tables"] += 1
				elif roll < 0.7:
					benches.append(Kit.xf(q, yaw))
					var bin := q + Basis(Vector3.UP, yaw) * Vector3(1.4, 0, 0.0)
					kit.cyl(steel, bin, 0.28, 0.3, 0.92, 10)
					kit.cyl(light, bin + Vector3(0, 0.92, 0), 0.31, 0.31, 0.05, 10)
					st["bench_bins"] += 1
				elif roll < 0.82:
					var bs := Basis(Vector3.UP, yaw)
					for k in 5:
						var hp := q + bs * Vector3(-2.0 + k * 1.0, 0, 0)
						var e := bs * Vector3(0, 0, 0.35)
						kit.beam(steel, hp - e, hp - e + Vector3(0, 0.8, 0), 0.05, 0.05)
						kit.beam(steel, hp + e, hp + e + Vector3(0, 0.8, 0), 0.05, 0.05)
						kit.beam(steel, hp - e + Vector3(0, 0.8, 0), hp + e + Vector3(0, 0.8, 0), 0.05, 0.05)
					st["racks"] += 1
				elif roll < 0.93:
					for k in 3:
						var a := yaw + k * TAU / 3.0
						bollards.append(q + Vector3(cos(a) * 1.1, 0, sin(a) * 1.1))
					st["bollard_groups"] += 1
				else:
					var bs2 := Basis(Vector3.UP, yaw)
					kit.box(Looks.get_mat("signage"), q + Vector3(0, 1.1, 0), Vector3(0.7, 2.2, 0.18), bs2)
					kit.box(Looks.get_mat("light_strip"), q + Vector3(0, 2.05, 0), Vector3(0.6, 0.08, 0.2), bs2)
					kit.col_box(Vector3(0.7, 2.2, 0.2), q + Vector3(0, 1.1, 0), bs2)
					st["totems"] += 1
	return st
