extends RefCounted
## Gardens by the Bay (Bay South) edge (wave M, downtown-landmarks).
##
## The geographic Supertree Grove behind Marina Bay Sands (plan D3): two
## instances of the authored vertical-garden Supertree grove (14 trees, 25-50 m)
## round a planted plaza, an elevated skyway threading the crowns at ~22 m,
## granite paths, flower beds, lamps and benches; and the two conservatories
## (Flower Dome, Cloud Forest) as glazed gridshells with steel arch ribs and
## planted interiors (a vertical-garden mountain in the Cloud Forest).

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")

const TOP := 0.34
const GROVE_TREES := [Vector3(0, 0, 0), Vector3(-15.4, 0, -4.9), Vector3(15.4, 0, -3.5), Vector3(-9.8, 0, 11.9), Vector3(10.5, 0, 12.6), Vector3(-21.7, 0, 7.7), Vector3(21.0, 0, 9.1)]
const COPIES := [[Vector3(-30.0, 0.0, -14.0), 0.0, 1.18], [Vector3(30.0, 0.0, 20.0), 3.14159, 1.05]]

func build(world: WorldBuilder, root: Node3D) -> Dictionary:
	var g: Vector3 = DowntownPlan.anchor("gardens_supertree_grove")
	var site := DowntownPlan.block_rect("gardens_site")
	var holder := Node3D.new()
	holder.name = "GardensByTheBay"
	root.add_child(holder)
	var kit := Kit.new(holder, "GardensCollision")
	var sc := site.get_center()
	kit.box(Looks.get_mat("turf"), Vector3(sc.x, TOP * 0.5 - 0.6, sc.y), Vector3(site.size.x, TOP + 1.2, site.size.y))
	kit.col_box(Vector3(site.size.x, 1.0, site.size.y), Vector3(sc.x, TOP - 0.5, sc.y))
	# Grove plaza: granite ring and radiating paths, flower beds between.
	var paving := Looks.get_mat("granite_paving")
	kit.cyl(paving, Vector3(g.x, TOP - 0.02, g.z), 46.0, 46.0, 0.06, 40, true)
	kit.cyl(Looks.get_mat("planting"), Vector3(g.x, TOP, g.z), 30.0, 30.0, 0.05, 40, true)
	kit.cyl(paving, Vector3(g.x, TOP + 0.01, g.z), 24.0, 24.0, 0.05, 40, true)
	for k in 8:
		var ang := TAU * k / 8.0 + 0.2
		var d := Vector3(cos(ang), 0, sin(ang))
		kit.beam(paving, Vector3(g.x, TOP + 0.04, g.z) + d * 20.0, Vector3(g.x, TOP + 0.04, g.z) + d * 95.0, 4.0, 0.08)
	var trees_world: Array[Vector3] = []
	for cp in COPIES:
		var off: Vector3 = cp[0]
		var yaw: float = cp[1]
		var sc_: float = cp[2]
		world._authored("supertree_grove.glb", g + off, yaw, Vector3.ONE * sc_)
		for t: Vector3 in GROVE_TREES:
			var w := g + off + Basis(Vector3.UP, yaw) * (t * sc_)
			trees_world.append(w)
			kit.col_box(Vector3(6.0, 14.0, 6.0) * sc_, w + Vector3(0, 7.0 * sc_, 0))
			# Planted base ring round each trunk.
			Realm.planter(kit, w, Vector2(9.0, 9.0) * sc_, 0.5)
	# OCBC-style skyway threading the first grove at ~22 m.
	var path_ids := [5, 1, 0, 2, 6, 4, 3]
	var ctrl: Array[Vector3] = []
	var cp0: Array = COPIES[0]
	for id: int in path_ids:
		var t: Vector3 = GROVE_TREES[id]
		ctrl.append(g + (cp0[0] as Vector3) + t * float(cp0[2]) + Vector3(0, 22.0, 0) + Vector3(2.6, 0, 2.2))
	var pts := PackedVector3Array()
	for i in ctrl.size() - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, ctrl.size() - 1)]
		for s in 8:
			var t := s / 8.0
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	pts.append(ctrl[ctrl.size() - 1])
	var deck := Looks.get_mat("timber")
	var under := Looks.get_mat("supertree_steel")
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var side := (b - a).cross(Vector3.UP).normalized() * 1.2
		kit.quad(deck, a + side, b + side, b - side, a - side)
		kit.beam(under, a - Vector3(0, 0.3, 0), b - Vector3(0, 0.3, 0), 1.6, 0.5)
		Realm.railing(kit, a + side, b + side, 1.15)
		Realm.railing(kit, a - side, b - side, 1.15)
	# Flower beds, lamps and benches round the plaza.
	var lamps := []
	var benches := []
	for k in 16:
		var ang := TAU * (k + 0.5) / 16.0
		var d := Vector3(cos(ang), 0, sin(ang))
		lamps.append(Kit.xf(Vector3(g.x, TOP, g.z) + d * 47.5, -ang - PI * 0.5))
		benches.append(Kit.xf(Vector3(g.x, TOP, g.z) + d * 25.2, -ang + PI * 0.5))
		if k % 2 == 0:
			Realm.planter(kit, Vector3(g.x, TOP, g.z) + d * 58.0, Vector2(7.0, 3.0), 0.45)
	Realm.lamps(holder, "GardensLamps", lamps)
	Realm.benches(holder, "GardensBenches", benches)
	for k in 10:
		world._tree(Vector3(site.position.x + 30.0 + k * 34.0, TOP, site.end.y - 12.0), 1.0)
	# Conservatories.
	var fd: Dictionary = DowntownPlan.ANCHORS["flower_dome"]
	var cf: Dictionary = DowntownPlan.ANCHORS["cloud_forest"]
	_conservatory(kit, holder, fd["pos"], fd["size"], 0.85, false)
	_conservatory(kit, holder, cf["pos"], cf["size"], 0.45, true)
	kit.commit(holder, "GardensMesh", true)
	return {"shapes": kit.shapes, "tris": kit.tris, "supertrees": trees_world.size()}

func _shell_p(c: Vector3, a: float, b: float, h: float, e: float, th: float, ph: float) -> Vector3:
	var cp := pow(maxf(cos(ph), 0.0), e)
	return c + Vector3(a * cos(th) * cp, h * sin(ph), b * sin(th) * cp)

func _conservatory(kit: Kit, holder: Node3D, pos: Vector3, size: Vector3, e: float, mountain: bool) -> void:
	var c := Vector3(pos.x, TOP, pos.z)
	var a := size.x * 0.5
	var b := size.z * 0.5
	var h := size.y
	var glass := Looks.get_mat("glass_canopy")
	var frame := Looks.get_mat("steel_white")
	var nth := 40
	var nph := 12
	var ph_max := deg_to_rad(88.0)
	var rings := []
	for k in nph + 1:
		var ring := PackedVector3Array()
		for j in nth:
			ring.append(_shell_p(c, a, b, h, e, -TAU * j / nth, ph_max * k / nph))
		rings.append(ring)
	kit.loft(glass, rings, true, true)
	kit.cap(glass, rings[rings.size() - 1])
	# Gridshell: meridians and parallels.
	for j in nth:
		var line := PackedVector3Array()
		for k in nph + 1:
			line.append(_shell_p(c, a + 0.15, b + 0.15, h + 0.15, e, -TAU * j / nth, ph_max * k / nph))
		kit.tube(frame, line, 0.14, 4)
	for k in range(1, nph, 2):
		var line2 := PackedVector3Array()
		for j in nth + 1:
			line2.append(_shell_p(c, a + 0.15, b + 0.15, h + 0.15, e, -TAU * j / nth, ph_max * k / nph))
		kit.tube(frame, line2, 0.11, 4)
	# External arch ribs across the short span.
	var ribs := 7
	for r in ribs:
		var xr := lerpf(-a * 0.75, a * 0.75, float(r) / (ribs - 1))
		var cx := xr / a
		var arc := PackedVector3Array()
		for k in 13:
			var ang := PI * k / 12.0
			var zz := -cos(ang) * b * sqrt(maxf(1.0 - cx * cx, 0.05)) * 1.08
			var yy := sin(ang) * (h * pow(maxf(1.0 - cx * cx, 0.0), 0.5) + 2.5)
			arc.append(c + Vector3(xr, yy, zz))
		kit.tube(Looks.get_mat("dome_frame"), arc, 0.7, 6)
	# Base plinth and entrances (closed glazed doors).
	var base := []
	for yy: float in [TOP - 0.2, TOP + 2.5]:
		var ring := PackedVector3Array()
		for j in nth:
			var th := -TAU * j / nth
			ring.append(Vector3(c.x + (a + 0.8) * cos(th), yy, c.z + (b + 0.8) * sin(th)))
		base.append(ring)
	kit.loft(Looks.get_mat("concrete_fair"), base, true, false)
	# Interior planting.
	if mountain:
		var m_rings := []
		for lvl in 7:
			var t := lvl / 6.0
			var rr := lerpf(b * 0.55, 5.0, t)
			var ring := PackedVector3Array()
			for j in 16:
				var th := -TAU * j / 16.0
				ring.append(c + Vector3(cos(th) * rr * 1.1, t * h * 0.78, sin(th) * rr))
			m_rings.append(ring)
		kit.loft(Looks.get_mat("vertical_garden"), m_rings, true, true)
		kit.cap(Looks.get_mat("planting"), m_rings[m_rings.size() - 1])
	else:
		for k in 5:
			var mc := c + Vector3(lerpf(-a * 0.6, a * 0.6, k / 4.0), 0.0, 6.0 * sin(k * 1.9))
			kit.box(Looks.get_mat("planting"), mc + Vector3(0, 1.2, 0), Vector3(18.0, 2.4, b * 0.9))
	var palms := []
	for k in 10:
		var ang := TAU * k / 10.0
		palms.append(Kit.xf(c + Vector3(cos(ang) * a * 0.55, 0.0, sin(ang) * b * 0.5), ang, Vector3.ONE * 1.4))
	Kit.multimesh(holder, "ConservatoryPalms", Realm.palm_mesh(), palms, false, 900.0)
	kit.col_box(Vector3(a * 1.8, h * 0.6, b * 1.8), c + Vector3(0, h * 0.3, 0))
	kit.col_box(Vector3(a * 1.1, h * 0.38, b * 1.1), c + Vector3(0, h * 0.78, 0))
	var sign := Label3D.new()
	sign.text = "CLOUD FOREST" if mountain else "FLOWER DOME"
	sign.font_size = 96
	sign.pixel_size = 0.014
	sign.modulate = Color(0.92, 0.9, 0.84)
	sign.position = c + Vector3(-(a + 1.5), 3.6, 0)
	sign.rotation.y = -PI * 0.5
	holder.add_child(sign)
