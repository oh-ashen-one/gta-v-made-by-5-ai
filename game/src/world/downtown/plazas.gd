extends RefCounted
## downtown-fill (wave T): street-level dressing of the downtown arrival
## points and squares. Critic gap (wave S): "the MBS arrival point, Merlion
## Park and NS Square are empty".
##   - MBS arrival courts (the Bayfront Avenue side between the hotel towers):
##     a drop-off loop round a granite fountain basin ringed by royal palms in
##     planters, a taxi / coach shelter, bollards along the kerb, flag poles,
##     lamps and benches; a palm-and-planter approach from the Helix landing.
##   - NS Square: floodlight masts at the corners, a cafe terrace with market
##     umbrellas and two food kiosks at the bay end, planters with palms and
##     benches along both waterside edges (the landing ring stays clear).
##   - Merlion Park terrace: palms in planters, a gelato cart under umbrellas,
##     benches facing the bay and a wayfinding board.
##   - Esplanade waterfront: planters with palms, benches and bins between
##     the rain trees.
## Original procedural work; reuses the project's palm.glb / fern.glb and the
## landmarks' shared materials. Big items (planters, kiosks, shelters,
## fountain rims, masts) collide; walk corridors of the owner's review routes
## and every helipad ring stay clear.

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")
const NearField = preload("res://src/world/downtown/plaza_nearfield.gd")

## Ground slabs (flat collision boxes) for prop heights: [AABB, ...]
static var _slabs: Array = []
static var _m := {}

static func _mat(key: String) -> Material:
	if _m.has(key):
		return _m[key]
	var m: Material
	match key:
		"fabric_cream": m = Palette.mat(Color(0.88, 0.84, 0.74), 0.85)
		"fabric_terracotta": m = Palette.mat(Color(0.66, 0.30, 0.20), 0.85)
		"fabric_teal": m = Palette.mat(Color(0.16, 0.42, 0.42), 0.85)
		"fabric_white": m = Palette.mat(Color(0.90, 0.90, 0.88), 0.7)
		"kiosk_green": m = Palette.mat(Color(0.18, 0.33, 0.26), 0.6, 0.3)
		"kiosk_red": m = Palette.mat(Color(0.52, 0.16, 0.12), 0.6, 0.3)
		"water":
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.10, 0.22, 0.24)
			w.roughness = 0.04
			w.metallic = 0.3
			m = w
		"flood_head": m = Palette.emissive(Color(1.0, 0.95, 0.85), 1.4)
		"flag_red": m = Palette.mat(Color(0.75, 0.12, 0.12), 0.8)
		"flag_blue": m = Palette.mat(Color(0.12, 0.25, 0.55), 0.8)
		"flag_gold": m = Palette.mat(Color(0.80, 0.62, 0.20), 0.8)
		_: m = Palette.mat(Color(0.5, 0.5, 0.5), 0.8)
	_m[key] = m
	return m

static func set_slabs(slabs: Array) -> void:
	_slabs = slabs

## Keep-out raster from fill.gd (buildings / standing volumes, 2 m cells).
static var _keep := PackedByteArray()
static func set_keep(keep: PackedByteArray) -> void:
	_keep = keep

static func _free(p: Vector3) -> bool:
	if not _clear(p):
		return false
	if _keep.is_empty():
		return true
	for o: Vector2 in [Vector2.ZERO, Vector2(1.8, 1.8), Vector2(-1.8, 1.8), Vector2(1.8, -1.8), Vector2(-1.8, -1.8)]:
		var cx := int(floor((p.x + o.x + 920.0) / 2.0))
		var cz := int(floor((p.z + o.y + 1080.0) / 2.0))
		if cx >= 0 and cz >= 0 and cx < 860 and cz < 740 and _keep[cz * 860 + cx] == 1:
			return false
	return true

## Finished ground height at (x, z): the highest flat slab top under it.
static func ground_y(x: float, z: float, fallback: float = 0.3) -> float:
	var best := -INF
	for a: AABB in _slabs:
		if x >= a.position.x and x <= a.end.x and z >= a.position.z and z <= a.end.z:
			best = maxf(best, a.end.y)
	return best if best > -INF else fallback

# ------------------------------------------------------------------ meshes
static var _meshes := {}

static func _umbrella(fabric: String) -> ArrayMesh:
	var key := "umb_" + fabric
	if _meshes.has(key):
		return _meshes[key]
	var k := Kit.new()
	var steel := Looks.get_mat("steel_dark")
	var wood := Looks.get_mat("timber")
	# table + four chairs
	k.cyl(steel, Vector3(0, 0, 0), 0.05, 0.05, 0.72, 8)
	k.cyl(wood, Vector3(0, 0.72, 0), 0.5, 0.5, 0.04, 14)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var d := Vector3(cos(a), 0, sin(a))
		var c := d * 0.95
		k.box(wood, c + Vector3(0, 0.45, 0), Vector3(0.42, 0.05, 0.42))
		k.box(steel, c + Vector3(0, 0.22, 0), Vector3(0.36, 0.44, 0.36))
		k.box(wood, c + d * 0.2 + Vector3(0, 0.72, 0), Vector3(0.42, 0.5, 0.05), Basis(Vector3.UP, -a + PI * 0.5))
	# umbrella: pole and an eight-panel canopy
	k.cyl(steel, Vector3(0, 0.76, 0), 0.03, 0.03, 1.7, 6)
	var apex := Vector3(0, 2.75, 0)
	var fab := _mat(fabric)
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var p0 := Vector3(cos(a0) * 1.5, 2.25, sin(a0) * 1.5)
		var p1 := Vector3(cos(a1) * 1.5, 2.25, sin(a1) * 1.5)
		k.tri(fab, apex, p1, p0)
		k.tri(fab, apex, p0, p1)
		# scalloped valance
		k.quad(fab, p0, p1, p1 - Vector3(0, 0.18, 0), p0 - Vector3(0, 0.18, 0))
	var m := k.to_mesh()
	_meshes[key] = m
	return m

static func _kiosk(colour: String) -> ArrayMesh:
	var key := "kiosk_" + colour
	if _meshes.has(key):
		return _meshes[key]
	var k := Kit.new()
	var body := _mat(colour)
	k.box(body, Vector3(0, 1.15, 0), Vector3(3.2, 2.3, 2.2))
	k.box(Looks.get_mat("steel_satin"), Vector3(0, 1.05, 1.16), Vector3(2.9, 0.1, 0.35))
	k.box(Looks.get_mat("glass_dark"), Vector3(0, 1.65, 1.11), Vector3(2.6, 0.95, 0.04))
	k.box(Looks.get_mat("light_strip"), Vector3(0, 2.16, 1.12), Vector3(2.7, 0.08, 0.04))
	# striped awning over the hatch
	for i in 6:
		var x := -1.4 + i * 0.56 + 0.28
		k.box(_mat("fabric_white") if i % 2 == 0 else body, Vector3(x, 2.5, 1.55), Vector3(0.56, 0.06, 1.0), Basis(Vector3.RIGHT, 0.3))
	k.box(body, Vector3(0, 2.62, 0), Vector3(3.5, 0.18, 2.5))
	var m := k.to_mesh()
	_meshes[key] = m
	return m

static func _mast() -> ArrayMesh:
	if _meshes.has("mast"):
		return _meshes["mast"]
	var k := Kit.new()
	var steel := Looks.get_mat("steel_white")
	k.cyl(Looks.get_mat("granite_dark"), Vector3.ZERO, 0.7, 0.7, 0.5, 10)
	k.cyl(steel, Vector3(0, 0.5, 0), 0.38, 0.22, 26.0, 10)
	k.box(steel, Vector3(0, 26.6, 0.3), Vector3(4.2, 1.4, 0.3))
	for i in 4:
		for j in 2:
			k.box(_mat("flood_head"), Vector3(-1.5 + i * 1.0, 26.25 + j * 0.7, 0.5), Vector3(0.8, 0.5, 0.12))
	var m := k.to_mesh()
	_meshes["mast"] = m
	return m

static func _flag(colour: String) -> ArrayMesh:
	var key := "flag_" + colour
	if _meshes.has(key):
		return _meshes[key]
	var k := Kit.new()
	k.cyl(Looks.get_mat("steel_satin"), Vector3.ZERO, 0.07, 0.05, 10.0, 8)
	k.box(_mat(colour), Vector3(0.95, 9.1, 0), Vector3(1.8, 1.1, 0.03))
	var m := k.to_mesh()
	_meshes[key] = m
	return m

# ------------------------------------------------------------------ helpers
## Review routes and lanes kept clear (x, z, radius).
static func _clear(p: Vector3) -> bool:
	for hk: String in DowntownPlan.HELIPADS:
		var hp: Vector3 = DowntownPlan.HELIPADS[hk]["pos"]
		if Vector2(hp.x - p.x, hp.z - p.z).length() < float(DowntownPlan.HELIPADS[hk]["radius"]) + 9.0:
			return false
	for seg: Array in WALK_CORRIDORS:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b)
		if q.distance_to(Vector2(p.x, p.z)) < 3.2:
			return false
	return true

const WALK_CORRIDORS := [
	[Vector2(-440, -338), Vector2(-458, -344)], [Vector2(-458, -344), Vector2(-460, -372)], [Vector2(-460, -372), Vector2(-488, -380)],
	[Vector2(-488, -380), Vector2(-521, -384)], [Vector2(-521, -384), Vector2(-521, -400)], [Vector2(-657, -409), Vector2(-648, -440)],
	[Vector2(-648, -440), Vector2(-648, -560)], [Vector2(-647, -560), Vector2(-647, -659)], [Vector2(-641, -666), Vector2(-488, -668)],
	[Vector2(-258, -745), Vector2(-247, -749)], [Vector2(-247, -749), Vector2(-241, -757)], [Vector2(-270, -745), Vector2(-258, -745)],
]

static func _planter_palm(kit: Kit, palms: Array, c: Vector3, size: Vector2, rng: RandomNumberGenerator) -> void:
	Realm.planter(kit, c, size, 0.6)
	kit.col_box(Vector3(size.x, 0.6, size.y), c + Vector3(0, 0.3, 0))
	var s := rng.randf_range(0.95, 1.3)
	palms.append(Kit.xf(c + Vector3(0, 0.62, 0), rng.randf_range(-PI, PI), Vector3(s, s * rng.randf_range(0.95, 1.2), s)))

# ------------------------------------------------------------------ build
static func build(world: WorldBuilder, holder: Node3D) -> Dictionary:
	var node := Node3D.new()
	node.name = "DowntownPlazas"
	holder.add_child(node)
	var kit := Kit.new(node, "DowntownPlazaCollision")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	var palms: Array = []
	var benches: Array = []
	var lamps: Array = []
	var bollards: Array = []
	var umbrellas := {"fabric_cream": [], "fabric_terracotta": [], "fabric_teal": []}
	var kiosks := {"kiosk_green": [], "kiosk_red": []}
	var masts: Array = []
	var flags := {"flag_red": [], "flag_blue": [], "flag_gold": []}
	var stats := {}
	stats["mbs"] = _mbs(kit, rng, palms, benches, lamps, bollards, flags, umbrellas)
	stats["ns_square"] = _ns_square(kit, rng, palms, benches, umbrellas, kiosks, masts)
	stats["merlion"] = _merlion(kit, rng, palms, benches, umbrellas, kiosks)
	stats["esplanade"] = _esplanade(kit, rng, palms, benches)
	var avoid: Array = []
	for t: Transform3D in palms:
		avoid.append(t.origin)
	for t: Transform3D in benches:
		avoid.append(t.origin)
	for f: String in umbrellas:
		for t: Transform3D in umbrellas[f]:
			avoid.append(t.origin)
	var mb: Vector3 = DowntownPlan.ANCHORS["marina_bay_sands"]["pos"]
	stats["nearfield"] = NearField.build(kit, rng, avoid, [Vector3(mb.x - 49.0, 0, -746.0), Vector3(mb.x + 49.0, 0, -746.0)], benches, bollards, umbrellas)
	kit.commit(node, "DowntownPlazaMesh", true, 900.0)
	Realm.flush_ferns(node, "DowntownPlazaFerns")
	Realm.glb_multimesh(node, "DowntownPlazaPalms", "palm.glb", palms, true, 520.0)
	Realm.benches(node, "DowntownPlazaBenches", benches)
	Realm.lamps(node, "DowntownPlazaLamps", lamps)
	Realm.bollards(node, "DowntownPlazaBollards", bollards)
	for f: String in umbrellas:
		Kit.multimesh(node, "DowntownPlazaUmbrellas", _umbrella(f), umbrellas[f], true, 320.0)
	for c: String in kiosks:
		Kit.multimesh(node, "DowntownPlazaKiosks", _kiosk(c), kiosks[c], true, 380.0)
	Kit.multimesh(node, "DowntownPlazaMasts", _mast(), masts, true, 1400.0)
	for f: String in flags:
		Kit.multimesh(node, "DowntownPlazaFlags", _flag(f), flags[f], true, 420.0)
	var n_umb := 0
	for f: String in umbrellas:
		n_umb += (umbrellas[f] as Array).size()
	stats["palms"] = palms.size()
	stats["benches"] = benches.size()
	stats["umbrella_tables"] = n_umb
	stats["shapes"] = kit.shapes
	world.set_meta("downtown_fill_plazas", stats)
	return stats

## MBS arrival: the Bayfront Avenue side between and beside the towers.
static func _mbs(kit: Kit, rng: RandomNumberGenerator, palms: Array, benches: Array, lamps: Array, bollards: Array, flags: Dictionary, umbrellas: Dictionary) -> int:
	var m: Vector3 = DowntownPlan.ANCHORS["marina_bay_sands"]["pos"]
	var n := 0
	var kerb_z := -764.5
	# drop-off courts between the towers
	for gx: float in [m.x - 49.0, m.x + 49.0]:
		var c := Vector3(gx, 0.0, -746.0)
		c.y = ground_y(c.x, c.z)
		# fountain basin: granite rim, dark reflecting water, a central bowl
		kit.cyl(Looks.get_mat("granite_light"), c, 7.5, 7.5, 0.55, 28)
		kit.cyl(_mat("water"), c + Vector3(0, 0.02, 0), 7.05, 7.05, 0.5, 28)
		kit.cyl(Looks.get_mat("granite_light"), c, 1.6, 1.2, 1.6, 16)
		kit.cyl(_mat("water"), c + Vector3(0, 1.58, 0), 1.15, 1.15, 0.04, 16)
		kit.col_box(Vector3(14.0, 0.55, 14.0), c + Vector3(0, 0.27, 0))
		# ring of palms in planters round the drive
		for i in 8:
			var a := TAU * i / 8.0 + 0.39
			var p := c + Vector3(cos(a) * 13.5, 0, sin(a) * 9.5)
			if p.z > kerb_z + 2.0 and _clear(p):
				_planter_palm(kit, palms, Vector3(p.x, ground_y(p.x, p.z), p.z), Vector2(2.2, 2.2), rng)
				n += 1
		# drive-loop paint: dark asphalt band round the fountain
		for i in 24:
			var a0 := TAU * i / 24.0
			var a1 := TAU * (i + 1) / 24.0
			var r0 := 8.6
			var r1 := 11.8
			var y := c.y + 0.012
			kit.quad(Looks.get_mat("granite_dark"), c + Vector3(cos(a0) * r0, 0, sin(a0) * r0 * 0.78) + Vector3(0, 0.012, 0), c + Vector3(cos(a1) * r0, 0, sin(a1) * r0 * 0.78) + Vector3(0, 0.012, 0),
				c + Vector3(cos(a1) * r1, 0, sin(a1) * r1 * 0.78) + Vector3(0, 0.012, 0), c + Vector3(cos(a0) * r1, 0, sin(a0) * r1 * 0.78) + Vector3(0, 0.012, 0))
		# taxi / coach shelter by the lobby side of the court
		var sh := Vector3(gx + 18.0, ground_y(gx + 18.0, -738.0), -738.0)
		kit.box(Looks.get_mat("steel_white"), sh + Vector3(0, 3.4, 0), Vector3(10.0, 0.25, 3.6))
		kit.box(Looks.get_mat("light_strip"), sh + Vector3(0, 3.26, 0), Vector3(9.4, 0.04, 0.3))
		for sx: float in [-4.6, 4.6]:
			kit.cyl(Looks.get_mat("steel_dark"), sh + Vector3(sx, 0, -1.5), 0.1, 0.1, 3.3, 8)
			kit.col_box(Vector3(0.25, 3.3, 0.25), sh + Vector3(sx, 1.65, -1.5))
		kit.box(Looks.get_mat("glass_dark"), sh + Vector3(0, 1.3, -1.7), Vector3(9.0, 2.2, 0.06))
		benches.append(Kit.xf(sh + Vector3(-2.0, 0, -1.2), PI))
		benches.append(Kit.xf(sh + Vector3(2.0, 0, -1.2), PI))
		var sign := Label3D.new()
		sign.text = "TAXI"
		sign.font_size = 64
		sign.pixel_size = 0.008
		sign.modulate = Color(0.95, 0.9, 0.55)
		sign.position = sh + Vector3(0, 3.0, 1.82)
		sign.visibility_range_end = 120.0
		kit.body.get_parent().add_child(sign)
		# flags along the court mouth
		var fk := ["flag_red", "flag_blue", "flag_gold", "flag_blue", "flag_red"]
		for i in 5:
			var fp := Vector3(gx - 14.0 + i * 7.0, 0, kerb_z + 1.4)
			if _clear(fp):
				(flags[fk[i]] as Array).append(Kit.xf(Vector3(fp.x, ground_y(fp.x, fp.z), fp.z), 0.0))
	# kerb line: bollards and lamps along the whole frontage
	var x := m.x - 205.0
	while x < m.x + 170.0:
		var bp := Vector3(x, 0, kerb_z + 0.6)
		if _clear(bp):
			bollards.append(Vector3(bp.x, ground_y(bp.x, bp.z), bp.z))
		if int(x) % 18 == 0:
			var lp := Vector3(x, 0, kerb_z + 2.4)
			if _clear(lp):
				lamps.append(Kit.xf(Vector3(lp.x, ground_y(lp.x, lp.z), lp.z), PI))
		x += 3.0
	# palms in planters along the tower fronts (east legs face the avenue)
	# and down the west flank of tower 1 where the Helix walk arrives
	for dx: float in [-98.0, 0.0, 98.0]:
		for k in 3:
			var tp := Vector3(m.x + dx - 13.0 + k * 13.0, 0, -759.5)
			if _clear(tp):
				_planter_palm(kit, palms, Vector3(tp.x, ground_y(tp.x, tp.z), tp.z), Vector2(3.4, 1.8), rng)
				n += 1
	for k in 5:
		var wp := Vector3(m.x - 98.0 - 23.5, 0, -746.0 + k * 10.0)
		if _clear(wp):
			_planter_palm(kit, palms, Vector3(wp.x, ground_y(wp.x, wp.z), wp.z), Vector2(2.2, 3.0), rng)
			benches.append(Kit.xf(Vector3(wp.x - 2.2, ground_y(wp.x, wp.z), wp.z + 3.0), PI * 0.5))
			n += 1
	# approach from the Helix landing to tower 1: planters with palms,
	# benches and a cafe kiosk-side terrace
	for i in 6:
		var p2 := Vector3(m.x - 150.0 - i * 9.0, 0, -758.0)
		if _clear(p2):
			_planter_palm(kit, palms, Vector3(p2.x, ground_y(p2.x, p2.z), p2.z), Vector2(3.0, 2.0), rng)
			benches.append(Kit.xf(Vector3(p2.x, ground_y(p2.x, p2.z), p2.z + 2.0), 0.0))
			n += 1
	for i in 4:
		var up := Vector3(m.x - 158.0 - i * 6.5, 0, -742.0 + (i % 2) * 4.0)
		if _clear(up):
			(umbrellas[["fabric_cream", "fabric_teal"][i % 2]] as Array).append(Kit.xf(Vector3(up.x, ground_y(up.x, up.z), up.z), rng.randf_range(0, TAU)))
	return n

## NS Square: masts at the corners, a cafe terrace and kiosks at the bay end,
## palms and benches along both waterside edges.
static func _ns_square(kit: Kit, rng: RandomNumberGenerator, palms: Array, benches: Array, umbrellas: Dictionary, kiosks: Dictionary, masts: Array) -> int:
	var r: Rect2 = DowntownPlan.ISLANDS["ns_square_float"]
	var n := 0
	var y := ground_y(r.get_center().x, r.get_center().y)
	for cx: float in [r.position.x + 14.0, r.end.x - 5.0]:
		for cz: float in [r.position.y + 5.0, r.end.y - 5.0]:
			masts.append(Kit.xf(Vector3(cx, ground_y(cx, cz, y), cz), PI * 0.5 if cx > r.get_center().x else -PI * 0.5))
			kit.col_box(Vector3(1.4, 26.0, 1.4), Vector3(cx, y + 13.0, cz))
	# cafe terrace + kiosks at the bay end (x > centre + 28 m)
	var fabrics := ["fabric_cream", "fabric_terracotta", "fabric_teal"]
	for i in 3:
		for j in 4:
			var p := Vector3(r.end.x - 22.0 + i * 6.0 + rng.randf_range(-0.6, 0.6), 0, r.position.y + 22.0 + j * 9.5 + rng.randf_range(-0.8, 0.8))
			if _clear(p):
				(umbrellas[fabrics[(i + j) % 3]] as Array).append(Kit.xf(Vector3(p.x, ground_y(p.x, p.z, y), p.z), rng.randf_range(0, TAU)))
				n += 1
	for k in 2:
		var kp := Vector3(r.end.x - 9.0, 0, r.position.y + 16.0 + k * 46.0)
		kiosks[["kiosk_green", "kiosk_red"][k]].append(Kit.xf(Vector3(kp.x, ground_y(kp.x, kp.z, y), kp.z), -PI * 0.5))
		kit.col_box(Vector3(2.4, 2.6, 3.4), Vector3(kp.x, y + 1.3, kp.z))
	# waterside edges: palms in planters and benches facing the water
	for edge_z: float in [r.position.y + 4.5, r.end.y - 4.5]:
		var facing := PI if edge_z < r.get_center().y else 0.0
		var xx := r.position.x + 30.0
		while xx < r.end.x - 26.0:
			var pp := Vector3(xx, 0, edge_z)
			if _clear(pp):
				_planter_palm(kit, palms, Vector3(pp.x, ground_y(pp.x, pp.z, y), pp.z), Vector2(2.4, 2.4), rng)
				benches.append(Kit.xf(Vector3(xx + 5.0, ground_y(xx + 5.0, edge_z, y), edge_z), facing))
				n += 1
			xx += 10.0
	return n

## Merlion Park terrace (Fullerton peninsula).
static func _merlion(kit: Kit, rng: RandomNumberGenerator, palms: Array, benches: Array, umbrellas: Dictionary, kiosks: Dictionary) -> int:
	var n := 0
	# palms down the bay-side edge of the terrace
	for i in 5:
		var p := Vector3(-446.0, 0, -404.0 + i * 11.0)
		if _clear(p):
			var c := Vector3(p.x, ground_y(p.x, p.z), p.z)
			_planter_palm(kit, palms, c, Vector2(2.2, 2.2), rng)
			benches.append(Kit.xf(c + Vector3(0, 0, 3.0), -PI * 0.5))
			n += 1
	# gelato / drinks cart under umbrellas in front of the pavilions
	var kp := Vector3(-452.0, 0, -393.0)
	kp.y = ground_y(kp.x, kp.z)
	kiosks["kiosk_red"].append(Kit.xf(kp, 0.0))
	kit.col_box(Vector3(3.4, 2.6, 2.4), kp + Vector3(0, 1.3, 0))
	for i in 3:
		var up := kp + Vector3(-5.0 + i * 3.6, 0, -5.5 + (i % 2) * 1.5)
		if _clear(up):
			(umbrellas[["fabric_teal", "fabric_cream", "fabric_terracotta"][i]] as Array).append(Kit.xf(up, rng.randf_range(0, TAU)))
	# wayfinding board
	var bp := Vector3(-466.0, 0, -362.0)
	bp.y = ground_y(bp.x, bp.z)
	kit.box(Looks.get_mat("signage"), bp + Vector3(0, 1.2, 0), Vector3(1.8, 2.4, 0.25))
	kit.col_box(Vector3(1.8, 2.4, 0.3), bp + Vector3(0, 1.2, 0))
	var lbl := Label3D.new()
	lbl.text = "MERLION PARK\nWATERFRONT"
	lbl.font_size = 48
	lbl.pixel_size = load("res://src/world/downtown/block_kits/frontage_kit.gd").fit_pixel("MERLION PARK", 48, 0.008, 1.5)
	lbl.modulate = Color(0.93, 0.91, 0.85)
	lbl.position = bp + Vector3(0, 1.9, 0.14)
	lbl.visibility_range_end = 90.0
	kit.body.get_parent().add_child(lbl)
	return n

## Esplanade waterfront between the rain trees.
static func _esplanade(kit: Kit, rng: RandomNumberGenerator, palms: Array, benches: Array) -> int:
	var n := 0
	# One flat paving course over the seam between the Esplanade site slab
	# (top 0.34) and the waterfront promenade: their joint (a sloped edge
	# strip side-mapped by the paving shader) read as warped, twisted setts.
	var site := DowntownPlan.block_rect("esplanade_site")
	var sx := site.end.x
	var z0 := site.position.y + 1.0
	var z1 := site.end.y - 1.0
	kit.box(Looks.get_mat("granite_paving"), Vector3(sx + 0.5, 0.30, (z0 + z1) * 0.5), Vector3(7.0, 0.12, z1 - z0))
	var z := -430.0
	while z > -650.0:
		var p := Vector3(-643.6, 0, z)
		if _clear(p):
			var c := Vector3(p.x, ground_y(p.x, p.z), p.z)
			_planter_palm(kit, palms, c, Vector2(1.8, 3.2), rng)
			benches.append(Kit.xf(c + Vector3(0.0, 0, 4.2), PI * 0.5))
			n += 1
		z -= 24.0
	return n
