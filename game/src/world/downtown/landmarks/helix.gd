extends RefCounted
## Helix Bridge (wave M, downtown-landmarks): walkable double-helix footbridge
## across the east channel from Marina Centre to the Bayfront.
##
## A gently curved 220 m deck (plan: real 280 m, compressed channel) ramps at
## <= 5 % from the quay level up to 3.6 m over the water. A major helix (two
## steel tubes, R 5.6 m) and a minor helix (two tubes, R 4.3 m) spiral round
## the walkway, tied by rungs; glass canopy panels shade the walk; four
## cantilevered viewing pods look out over the bay. Collision is one trimesh
## (deck, balustrades with gaps into the pods, pod floors and walls).

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")

const SAMPLES := 110
const AXIS_UP := 2.6
const R_MAJOR := 5.6
const R_MINOR := 4.3
const PITCH := 18.0
const HALF_W := 3.0
const RAMP_U := 0.3
const QUAY_Y := 0.36
const POD_U := [0.40, 0.52, 0.64, 0.76]

var from_p: Vector3
var to_p: Vector3
var deck_y := 3.6
var faces := PackedVector3Array()

func _pos(u: float) -> Vector3:
	var x := lerpf(from_p.x, to_p.x, u)
	var z := lerpf(from_p.z, to_p.z, u) - 6.0 * sin(PI * u)
	var y := deck_y
	if u < RAMP_U:
		y = lerpf(QUAY_Y, deck_y, smoothstep(0.0, 1.0, u / RAMP_U) * 0.25 + (u / RAMP_U) * 0.75)
	elif u > 1.0 - RAMP_U:
		var v := (1.0 - u) / RAMP_U
		y = lerpf(QUAY_Y, deck_y, smoothstep(0.0, 1.0, v) * 0.25 + v * 0.75)
	return Vector3(x, y, z)

func _frame(u: float) -> Array:
	var du := 1.0 / SAMPLES
	var t := (_pos(minf(u + du, 1.0)) - _pos(maxf(u - du, 0.0)))
	var flat := Vector3(t.x, 0.0, t.z).normalized()
	var side := flat.cross(Vector3.UP).normalized()   # points to +z (bay side) for a +x path
	return [t.normalized(), side]

func build(world: WorldBuilder, root: Node3D) -> Dictionary:
	var b: Dictionary = DowntownPlan.BRIDGES["helix_bridge"]
	from_p = b["from"]
	to_p = b["to"]
	deck_y = float(b["deck_y"])
	var holder := Node3D.new()
	holder.name = "HelixBridge"
	root.add_child(holder)
	var kit := Kit.new(holder, "HelixCollision")
	var steel := Looks.get_mat("steel_satin")
	var steel_w := Looks.get_mat("steel_white")
	var deck := Looks.get_mat("granite_light")
	var under := Looks.get_mat("steel_dark")
	# Arc length table.
	var pts: Array[Vector3] = []
	var arc: Array[float] = []
	var acc := 0.0
	for i in SAMPLES + 1:
		var u := float(i) / SAMPLES
		var p := _pos(u)
		if i > 0:
			acc += p.distance_to(pts[i - 1])
		pts.append(p)
		arc.append(acc)
	# Deck slab, underside box girder, kerb light strips.
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in SAMPLES + 1:
		var fr := _frame(float(i) / SAMPLES)
		var side: Vector3 = fr[1]
		lefts.append(pts[i] - side * HALF_W)
		rights.append(pts[i] + side * HALF_W)
	for i in SAMPLES:
		kit.quad(deck, rights[i], rights[i + 1], lefts[i + 1], lefts[i])
		var d := Vector3(0, -0.9, 0)
		kit.quad(under, rights[i] + d, rights[i + 1] + d, rights[i + 1], rights[i])
		kit.quad(under, lefts[i], lefts[i + 1], lefts[i + 1] + d, lefts[i] + d)
		kit.quad(under, lefts[i] + d, lefts[i + 1] + d, rights[i + 1] + d, rights[i] + d)
		var s0 := (rights[i] - lefts[i]).normalized() * 0.18
		var s1 := (rights[i + 1] - lefts[i + 1]).normalized() * 0.18
		kit.beam(Looks.get_mat("light_strip"), lefts[i] + s0 + Vector3(0, 0.04, 0), lefts[i + 1] + s1 + Vector3(0, 0.04, 0), 0.08, 0.04)
		kit.beam(Looks.get_mat("light_strip"), rights[i] - s0 + Vector3(0, 0.04, 0), rights[i + 1] - s1 + Vector3(0, 0.04, 0), 0.08, 0.04)
		# Walk surface for the trimesh.
		faces.append_array([lefts[i], rights[i], rights[i + 1], lefts[i], rights[i + 1], lefts[i + 1]])
	# Balustrades, with openings into the viewing pods on the bay side.
	var pod_centres: Array[Vector3] = []
	for pu: float in POD_U:
		var fr := _frame(pu)
		pod_centres.append(_pos(pu) + (fr[1] as Vector3) * (R_MAJOR + 2.6))
	for i in SAMPLES:
		var mid_u := (i + 0.5) / SAMPLES
		Realm.glass_rail(kit, lefts[i], lefts[i + 1], 1.2)
		_wall(lefts[i], lefts[i + 1], 1.25)
		var gap := false
		for pu: float in POD_U:
			if absf(mid_u - pu) * arc[SAMPLES] < 1.6:
				gap = true
		if not gap:
			Realm.glass_rail(kit, rights[i + 1], rights[i], 1.2)
			_wall(rights[i], rights[i + 1], 1.25)
	# The two helices: major (R 5.6, thick tubes) and minor (R 4.3), same hand.
	var helix_start := 0.035
	var helix_end := 0.965
	var members := [[R_MAJOR, 0.0, 0.24], [R_MAJOR, PI, 0.24], [R_MINOR, PI * 0.5, 0.15], [R_MINOR, PI * 1.5, 0.15]]
	var nodes := {}
	for mi in members.size():
		var r: float = members[mi][0]
		var ph: float = members[mi][1]
		var line := PackedVector3Array()
		var list: Array[Vector3] = []
		var steps := SAMPLES * 3
		for k in steps + 1:
			var u := lerpf(helix_start, helix_end, float(k) / steps)
			var fr := _frame(u)
			var side: Vector3 = fr[1]
			var axis := _pos(u) + Vector3(0, AXIS_UP, 0)
			var s := u * arc[SAMPLES]
			var th := TAU * s / PITCH + ph
			var p := axis + side * (r * cos(th)) + Vector3.UP * (r * sin(th))
			line.append(p)
			list.append(p)
		kit.tube(steel_w if mi < 2 else steel, line, members[mi][2], 10 if mi < 2 else 7)
		nodes[mi] = list
	# Rungs tying major to minor helix every third station, and hoop ties.
	var count: int = (nodes[0] as Array).size()
	for k in range(0, count, 3):
		kit.beam(steel, nodes[0][k], nodes[2][k], 0.07, 0.07)
		kit.beam(steel, nodes[1][k], nodes[3][k], 0.07, 0.07)
		if k % 12 == 0:
			kit.beam(steel, nodes[2][k], nodes[1][k], 0.06, 0.06)
			kit.beam(steel, nodes[3][k], nodes[0][k], 0.06, 0.06)
	# Canopy: glass panels over the walk in alternating 15 m runs.
	var glass := Looks.get_mat("glass_canopy")
	for i in SAMPLES:
		var u0 := float(i) / SAMPLES
		var u1 := float(i + 1) / SAMPLES
		if u0 < 0.08 or u1 > 0.92:
			continue
		if int(floor(u0 * arc[SAMPLES] / 15.0)) % 2 == 1:
			continue
		var segs := 4
		for k in segs:
			var a0 := deg_to_rad(55.0 + 70.0 * k / segs)
			var a1 := deg_to_rad(55.0 + 70.0 * (k + 1) / segs)
			var f0 := _frame(u0)
			var f1 := _frame(u1)
			var c0 := _pos(u0) + Vector3(0, AXIS_UP, 0)
			var c1 := _pos(u1) + Vector3(0, AXIS_UP, 0)
			var rr := R_MINOR - 0.35
			var p00: Vector3 = c0 + (f0[1] as Vector3) * rr * cos(a0) + Vector3.UP * rr * sin(a0)
			var p01: Vector3 = c0 + (f0[1] as Vector3) * rr * cos(a1) + Vector3.UP * rr * sin(a1)
			var p10: Vector3 = c1 + (f1[1] as Vector3) * rr * cos(a0) + Vector3.UP * rr * sin(a0)
			var p11: Vector3 = c1 + (f1[1] as Vector3) * rr * cos(a1) + Vector3.UP * rr * sin(a1)
			kit.quad(glass, p00, p10, p11, p01)
			if i % 4 == 0:
				kit.beam(steel, p00, p01, 0.05, 0.05)
	# Viewing pods: round cantilevered decks with glass balustrades.
	for pi_ in POD_U.size():
		var pu: float = POD_U[pi_]
		var pc := pod_centres[pi_]
		var fr := _frame(pu)
		var side: Vector3 = fr[1]
		var dy := _pos(pu).y
		var rad := 3.4
		var sides := 16
		var prev := Vector3.ZERO
		for k in sides + 1:
			var a := TAU * k / sides
			var p := Vector3(pc.x + cos(a) * rad, dy, pc.z + sin(a) * rad)
			if k > 0:
				kit.tri(deck, pc, p, prev)
				kit.quad(under, p - Vector3(0, 0.6, 0), prev - Vector3(0, 0.6, 0), prev, p)
				faces.append_array([pc, prev, p])
				var mid := (prev + p) * 0.5
				if (mid - pc).normalized().dot(-side) < 0.75:
					Realm.glass_rail(kit, prev, p, 1.2)
					_wall(prev, p, 1.25)
			prev = p
		# Floor link from the deck edge through the helix to the pod.
		var e0 := _pos(pu - 0.006) + side * HALF_W
		var e1 := _pos(pu + 0.006) + side * HALF_W
		var o0 := e0 + side * (R_MAJOR + 2.6 - rad - HALF_W + 0.5)
		var o1 := e1 + side * (R_MAJOR + 2.6 - rad - HALF_W + 0.5)
		kit.quad(deck, e0, o0, o1, e1)
		faces.append_array([e0, e1, o1, e0, o1, o0])
		Realm.glass_rail(kit, e0, o0, 1.2)
		Realm.glass_rail(kit, o1, e1, 1.2)
		_wall(e0, o0, 1.25)
		_wall(e1, o1, 1.25)
	# Piers in the channel.
	var pier := Looks.get_mat("concrete_fair")
	for pu: float in [0.24, 0.41, 0.59, 0.76]:
		var p := _pos(pu)
		kit.cyl(pier, Vector3(p.x, -2.5, p.z), 1.1, 0.9, p.y - 0.9 + 2.5, 12, true)
		kit.box(under, Vector3(p.x, p.y - 1.2, p.z), Vector3(2.2, 0.6, 8.0), Basis(Vector3.UP, 0.0))
	# Landing plazas at both ends (granite, raised 6 cm over the quay).
	for end_p: Vector3 in [_pos(0.0), _pos(1.0)]:
		var off := -10.0 if end_p.x < (from_p.x + to_p.x) * 0.5 else 10.0
		var c := end_p + Vector3(off * 0.5, 0, 0)
		kit.box(Looks.get_mat("granite_paving"), Vector3(c.x, QUAY_Y * 0.5 - 0.2, c.z), Vector3(absf(off) + 8.0, QUAY_Y + 0.4, 16.0))
		kit.col_box(Vector3(absf(off) + 8.0, 1.0, 16.0), Vector3(c.x, QUAY_Y - 0.5, c.z))
		# downtown-polish (wave S): the 0.36 m plaza stood as a lip over the
		# 0-0.10 m quay and walks (the player capsule has no step-up), so the
		# helix could not be walked onto. Granite edge ramps on the three land
		# sides (the fourth carries the deck).
		var half := Vector2((absf(off) + 8.0) * 0.5, 8.0)
		for n: Vector2 in [Vector2(signf(off), 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]:
			var edge := Vector3(c.x + n.x * half.x, QUAY_Y, c.z + n.y * half.y)
			var length := half.y * 2.0 if n.x != 0.0 else half.x * 2.0
			var p0 := Vector3(edge.x + n.x * 1.8, -0.02, edge.z + n.y * 1.8)
			kit.col_beam(p0, edge, length, 0.4)
			var dz := (edge - p0).normalized()
			var dx := Vector3.UP.cross(dz).normalized()
			var dy := dz.cross(dx).normalized()
			kit.box(Looks.get_mat("granite_paving"), (p0 + edge) * 0.5 - dy * 0.05, Vector3(length, 0.1, p0.distance_to(edge)), Basis(dx, dy, dz))
		var sign := Label3D.new()
		sign.text = "HELIX BRIDGE"
		sign.font_size = 96
		sign.pixel_size = 0.01
		sign.modulate = Color(0.9, 0.88, 0.82)
		sign.position = end_p + Vector3(off * 0.35, 3.2, 0.0)
		sign.rotation.y = -PI * 0.5 if off < 0.0 else PI * 0.5
		holder.add_child(sign)
		kit.box(Looks.get_mat("signage"), end_p + Vector3(off * 0.35 - signf(off) * 0.2, 2.4, 0.0), Vector3(0.3, 2.0, 2.6))
	kit.col_trimesh(faces)
	kit.commit(holder, "HelixBridgeMesh", true)
	world.locations["helix_bridge_west"] = _pos(0.0)
	world.locations["helix_bridge_east"] = _pos(1.0)
	world.set_meta("helix_path", pts)
	return {"shapes": kit.shapes, "tris": kit.tris, "length": arc[SAMPLES]}

## Vertical collision wall (balustrade) between two deck-edge points.
func _wall(a: Vector3, b: Vector3, h: float) -> void:
	var up := Vector3(0, h, 0)
	faces.append_array([a, b, b + up, a, b + up, a + up])
