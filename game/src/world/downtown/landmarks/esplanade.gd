extends RefCounted
## Esplanade - Theatres on the Bay (wave M, downtown-landmarks).
##
## Two rounded, elongated domes (concert hall and theatre) clad in a dark
## glazed shell under ~2,600 triangular aluminium sunshade hoods (MultiMesh,
## each oriented to the dome normal, hood tilted up the meridian). A glazed
## link block joins them; a colonnaded canopy runs along the bay frontage; an
## outdoor theatre (stage canopy + stepped seating) faces the water.

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")

const TOP := 0.36
const SPIKE_SPACING := 2.7

var _spikes: Array = []

func _dome_p(c: Vector3, a: float, b: float, h: float, th: float, ph: float) -> Vector3:
	var e := 0.62
	var cp := pow(maxf(cos(ph), 0.0), e)
	return c + Vector3(a * cos(th) * cp, h * sin(ph), b * sin(th) * cp)

func _dome(kit: Kit, c: Vector3, a: float, b: float, h: float) -> void:
	var glass := Looks.get_mat("glass_dark")
	var frame := Looks.get_mat("dome_frame")
	var nth := 48
	var nph := 16
	var ph_max := deg_to_rad(84.0)
	var rings := []
	for k in nph + 1:
		var ph := ph_max * k / nph
		var ring := PackedVector3Array()
		for j in nth:
			ring.append(_dome_p(c, a, b, h, -TAU * j / nth, ph))
		rings.append(ring)
	kit.loft(glass, rings, true, true)
	kit.cap(glass, rings[rings.size() - 1])
	# Space-frame ribs (meridians) under the hoods.
	for j in range(0, nth, 2):
		var line := PackedVector3Array()
		for k in nph + 1:
			line.append(_dome_p(c, a * 1.004, b * 1.004, h * 1.004, -TAU * j / nth, ph_max * k / nph))
		kit.tube(frame, line, 0.12, 4)
	# Sunshade hoods on a staggered triangular grid of the dome surface.
	var meridian := (PI * 0.5) * (a + b + 2.0 * h) * 0.25
	var nrows := int(meridian / SPIKE_SPACING)
	for r in range(1, nrows):
		var ph := deg_to_rad(86.0) * r / nrows
		var cp := pow(maxf(cos(ph), 0.0), 0.62)
		var circ := TAU * sqrt((a * a + b * b) * 0.5) * cp
		var n := maxi(6, int(circ / SPIKE_SPACING))
		var off := 0.5 * float(r % 2)
		for j in n:
			var th := TAU * (j + off) / n
			var p := _dome_p(c, a, b, h, th, ph)
			if p.y < c.y + 2.6:
				continue
			var d_th := _dome_p(c, a, b, h, th + 0.01, ph) - p
			var d_ph := _dome_p(c, a, b, h, th, ph + 0.01) - p
			var nrm := d_ph.cross(d_th).normalized()
			if nrm.dot(p - c - Vector3(0, h * 0.3, 0)) < 0.0:
				nrm = -nrm
			var s := clampf(circ / n / SPIKE_SPACING, 0.8, 1.25)
			_spikes.append(Transform3D(Kit.basis_up(nrm, d_ph).scaled(Vector3(s, 1.0, s)), p))

func _spike_mesh() -> ArrayMesh:
	var k := Kit.new()
	var al := Looks.get_mat("aluminium_shade")
	var a := Vector3(-1.25, 0.0, -0.85)
	var b := Vector3(1.25, 0.0, -0.85)
	var c := Vector3(0.0, 0.0, 1.35)
	var apex := Vector3(0.0, 1.35, 0.55)
	k.tri(al, a, b, apex)
	k.tri(al, b, c, apex)
	k.tri(al, c, a, apex)
	var mesh := k.to_mesh()
	var dbl := (al as StandardMaterial3D).duplicate() as StandardMaterial3D
	dbl.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, dbl)
	return mesh

func build(world: WorldBuilder, root: Node3D) -> Dictionary:
	var site := DowntownPlan.block_rect("esplanade_site")
	var hall: Dictionary = DowntownPlan.ANCHORS["esplanade_concert_hall"]
	var theatre: Dictionary = DowntownPlan.ANCHORS["esplanade_theatre"]
	var holder := Node3D.new()
	holder.name = "Esplanade"
	root.add_child(holder)
	var kit := Kit.new(holder, "EsplanadeCollision")
	var paving := Looks.get_mat("granite_paving")
	var sc := site.get_center()
	kit.box(paving, Vector3(sc.x, TOP * 0.5 - 0.6, sc.y), Vector3(site.size.x, TOP + 1.2, site.size.y))
	kit.col_box(Vector3(site.size.x, 1.0, site.size.y), Vector3(sc.x, TOP - 0.5, sc.y))
	var domes := [hall, theatre]
	for d: Dictionary in domes:
		var p: Vector3 = d["pos"]
		var size: Vector3 = d["size"]
		var c := Vector3(p.x, TOP, p.z)
		var a := size.x * 0.5
		var b := size.z * 0.5
		var h := size.y
		# Foyer plinth ring: glazed, with a stone base course.
		var base_rings := []
		for yy: float in [TOP, TOP + 4.5]:
			var ring := PackedVector3Array()
			for j in 48:
				var th := -TAU * j / 48.0
				ring.append(Vector3(c.x + (a + 1.6) * cos(th), yy, c.z + (b + 1.6) * sin(th)))
			base_rings.append(ring)
		kit.loft(Looks.get_mat("glass_green"), base_rings, true, false)
		kit.cap(Looks.get_mat("concrete_fair"), base_rings[1])
		_dome(kit, c + Vector3(0, 4.5, 0), a, b, h - 4.5)
		kit.col_box(Vector3(a * 1.8, h * 0.55, b * 1.8), Vector3(c.x, TOP + h * 0.275, c.z))
		kit.col_box(Vector3(a * 1.2, h * 0.4, b * 1.2), Vector3(c.x, TOP + h * 0.75, c.z))
	# Link block between the domes: cream render, glazed ground floor.
	var hp: Vector3 = hall["pos"]
	var tp: Vector3 = theatre["pos"]
	var lz0 := tp.z + float(theatre["size"].z) * 0.5 - 4.0
	var lz1 := hp.z - float(hall["size"].z) * 0.5 + 4.0
	var lx0 := hp.x - 30.0
	var lx1 := hp.x + 26.0
	var lc := Vector3((lx0 + lx1) * 0.5, 0, (lz0 + lz1) * 0.5)
	kit.box(Looks.get_mat("render_cream"), lc + Vector3(0, TOP + 7.0, 0), Vector3(lx1 - lx0, 10.0, lz1 - lz0))
	kit.box(Looks.get_mat("glass_dark"), lc + Vector3(0, TOP + 1.0, 0), Vector3(lx1 - lx0 + 0.2, 2.0, lz1 - lz0 + 0.2))
	kit.col_box(Vector3(lx1 - lx0, 12.0, lz1 - lz0), lc + Vector3(0, TOP + 6.0, 0))
	# Bay-facing facade of the link: glazed band and aluminium sunshade louvres.
	var fx := lx1 + 0.05
	kit.box(Looks.get_mat("glass_green"), Vector3(fx, TOP + 6.2, lc.z), Vector3(0.1, 3.4, lz1 - lz0 - 2.0))
	for k in 9:
		kit.box(Looks.get_mat("aluminium_shade"), Vector3(fx + 0.5, TOP + 3.6 + k * 0.62, lc.z), Vector3(1.0, 0.08, lz1 - lz0 - 1.0))
	var fz := lz0 + 1.5
	while fz < lz1 - 1.0:
		kit.box(Looks.get_mat("steel_satin"), Vector3(fx + 0.3, TOP + 6.0, fz), Vector3(0.6, 9.0, 0.18))
		fz += 3.0
	# Bay frontage canopy walk: slim columns, thin roof, lit soffit.
	var cx := site.end.x - 3.0
	var cz0 := site.position.y + 8.0
	var cz1 := site.end.y - 8.0
	var white := Looks.get_mat("steel_white")
	var z := cz0
	while z <= cz1:
		kit.cyl(white, Vector3(cx, TOP, z), 0.18, 0.15, 5.2, 8, false)
		z += 7.5
	kit.box(white, Vector3(cx - 2.5, TOP + 5.4, (cz0 + cz1) * 0.5), Vector3(7.0, 0.35, cz1 - cz0 + 2.0))
	kit.box(Looks.get_mat("light_strip"), Vector3(cx - 2.5, TOP + 5.2, (cz0 + cz1) * 0.5), Vector3(0.4, 0.05, cz1 - cz0))
	# Outdoor theatre: stage with a sail canopy at the water, stepped seats.
	var stage := Vector3(site.end.x - 9.0, TOP, tp.z - 14.0)
	kit.box(Looks.get_mat("timber"), stage + Vector3(0, 0.6, 0), Vector3(10.0, 1.2, 24.0))
	kit.col_box(Vector3(10.0, 1.2, 24.0), stage + Vector3(0, 0.6, 0))
	var sail := []
	for k in 9:
		var u := float(k) / 8.0
		var zz := stage.z - 13.0 + 26.0 * u
		sail.append(PackedVector3Array([Vector3(stage.x - 6.0, TOP + 9.0 + 2.0 * sin(PI * u), zz), Vector3(stage.x + 5.0, TOP + 7.0 + 1.0 * sin(PI * u), zz)]))
	kit.loft(Looks.get_mat("steel_white"), sail, false, true)
	var sail_rev := []
	for r: PackedVector3Array in sail:
		sail_rev.append(PackedVector3Array([r[1], r[0]]))
	kit.loft(Looks.get_mat("hull_panel"), sail_rev, false, true)
	for zz: float in [stage.z - 12.0, stage.z + 12.0]:
		kit.beam(white, Vector3(stage.x - 5.5, TOP + 1.2, zz), Vector3(stage.x - 5.5, TOP + 9.2, zz), 0.4, 0.4)
	for r in 6:
		var sx := stage.x - 9.0 - r * 1.6
		kit.box(Looks.get_mat("granite_light"), Vector3(sx, TOP + 0.22 * (r + 1) * 0.5, stage.z), Vector3(1.6, 0.22 * (r + 1), 30.0 + r * 3.0))
		kit.col_box(Vector3(1.6, 0.22 * (r + 1), 30.0 + r * 3.0), Vector3(sx, TOP + 0.22 * (r + 1) * 0.5, stage.z))
	# Trees, lamps and benches along the frontage.
	var lamps := []
	var benches := []
	var zt := site.position.y + 14.0
	var i := 0
	while zt < site.end.y - 6.0:
		if absf(zt - stage.z) > 22.0:
			world._tree(Vector3(site.end.x - 8.5, TOP, zt), 0.9 + 0.08 * float(i % 3))
			benches.append(Kit.xf(Vector3(site.end.x - 6.5, TOP, zt + 6.0), -PI * 0.5))
		lamps.append(Kit.xf(Vector3(site.end.x - 1.2, TOP, zt + 12.0), PI * 0.5))
		zt += 24.0
		i += 1
	Realm.lamps(holder, "EsplanadeLamps", lamps)
	Realm.benches(holder, "EsplanadeBenches", benches)
	var sign := Label3D.new()
	sign.text = "ESPLANADE\nTHEATRES ON THE BAY"
	sign.font_size = 96
	sign.pixel_size = 0.014
	sign.modulate = Color(0.92, 0.9, 0.84)
	sign.position = Vector3(lx1 + 0.4, TOP + 9.0, lc.z)
	sign.rotation.y = PI * 0.5
	holder.add_child(sign)
	kit.commit(holder, "EsplanadeMesh", true)
	Kit.multimesh(holder, "EsplanadeSunshades", _spike_mesh(), _spikes, true, 0.0)
	return {"shapes": kit.shapes, "tris": kit.tris, "sunshades": _spikes.size()}
