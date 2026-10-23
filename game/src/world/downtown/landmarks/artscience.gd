extends RefCounted
## ArtScience Museum (wave M, downtown-landmarks): moved to the Bayfront tip
## promontory (plan D2) and rebuilt as a ~60 m lotus of ten curved, tapering
## shell "fingers" with skylight tips, rising from a bowl that floats on a
## central pedestal over a lily pond, inside a granite promontory walk.

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")

const HEIGHTS := [58.0, 52.0, 44.0, 36.0, 30.0, 27.0, 31.0, 38.0, 47.0, 55.0]
const TOP := 0.36

func build(world: WorldBuilder, root: Node3D) -> Dictionary:
	var a: Dictionary = DowntownPlan.ANCHORS["artscience_museum"]
	var c: Vector3 = a["pos"]
	c.y = TOP
	var yaw := deg_to_rad(float(a["yaw_deg"]))
	var island: Rect2 = DowntownPlan.ISLANDS["artscience_promontory"]
	var holder := Node3D.new()
	holder.name = "artscience_museum"
	root.add_child(holder)
	var kit := Kit.new(holder, "ArtScienceCollision")
	var white := Looks.get_mat("lotus_white")
	var paving := Looks.get_mat("granite_paving")
	var ic := island.get_center()
	# Promontory deck with a granite seawall skirt down to the water.
	kit.box(paving, Vector3(ic.x, TOP * 0.5 - 0.9, ic.y), Vector3(island.size.x, TOP + 1.8, island.size.y))
	kit.col_box(Vector3(island.size.x, 1.2, island.size.y), Vector3(ic.x, TOP - 0.6, ic.y))
	kit.box(Looks.get_mat("granite_light"), Vector3(ic.x, TOP + 0.05, ic.y), Vector3(island.size.x - 1.0, 0.1, island.size.y - 1.0))
	# Lily pond with granite rim; collision rim keeps walkers on the paving.
	var pond_r := 21.0
	kit.cyl(Looks.get_mat("granite_light"), Vector3(c.x, TOP, c.z), pond_r + 0.8, pond_r + 0.8, 0.45, 32, true)
	kit.cyl(Looks.get_mat("pond_water"), Vector3(c.x, TOP + 0.3, c.z), pond_r, pond_r, 0.17, 32, true)
	for k in 8:
		var ang := TAU * k / 8.0
		var p := c + Vector3(cos(ang), 0, sin(ang)) * (pond_r + 0.4)
		kit.col_box(Vector3(17.0, 0.9, 0.8), p + Vector3(0, 0.45, 0), Basis(Vector3.UP, -ang + PI * 0.5))
	var pads := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 9917
	for k in 140:
		var ang := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * (pond_r - 1.2)
		if rr < 9.0:
			continue
		pads.append(Kit.xf(c + Vector3(cos(ang) * rr, 0.49, sin(ang) * rr), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.7, 1.3)))
	var pad_kit := Kit.new()
	pad_kit.cyl(Looks.get_mat("shrub_light"), Vector3.ZERO, 0.55, 0.55, 0.03, 9)
	Kit.multimesh(holder, "ArtScienceLilyPads", pad_kit.to_mesh(), pads, false, 260.0)
	# Pedestal and the bowl the fingers spring from.
	kit.cyl(Looks.get_mat("concrete_fair"), Vector3(c.x, TOP, c.z), 5.0, 7.5, 9.0, 16, false)
	var bowl := []
	for ring_def in [[8.0, 6.5], [10.0, 13.0], [13.0, 17.5], [16.5, 18.5], [19.0, 16.0]]:
		var ring := PackedVector3Array()
		for s in 24:
			var ang := -TAU * s / 24.0
			ring.append(Vector3(c.x + cos(ang) * ring_def[1], ring_def[0], c.z + sin(ang) * ring_def[1]))
		bowl.append(ring)
	kit.loft(white, bowl, true, true)
	kit.cap(Looks.get_mat("glass_dark"), bowl[bowl.size() - 1])
	kit.col_box(Vector3(30.0, 11.0, 30.0), Vector3(c.x, 13.5, c.z), Basis(Vector3.UP, yaw))
	kit.col_box(Vector3(10.0, 8.0, 10.0), Vector3(c.x, 4.4, c.z))
	# Ten fingers: lens-section shells that splay outward and taper upward.
	for i in 10:
		var ang := yaw + TAU * i / 10.0 + 0.12 * sin(i * 1.7)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var tan := Vector3(-dir.z, 0, dir.x)
		var h: float = HEIGHTS[i]
		var rings := []
		var steps := 12
		var tips := PackedVector3Array()
		for s in steps + 1:
			var t := float(s) / steps
			var rad := 9.0 + (h * 0.48) * pow(t, 1.55)
			var y := 12.0 + (h - 12.0) * t
			var width := lerpf(15.5, 4.2, pow(t, 0.9))
			var thick := lerpf(5.5, 1.6, t)
			var lean := (dir * (h * 0.48 * 1.55 * pow(maxf(t, 0.01), 0.55)) + Vector3(0, h - 12.0, 0)).normalized()
			var nrm := (dir - lean * dir.dot(lean)).normalized()
			var centre := c + dir * rad + Vector3(0, y, 0)
			var ring := PackedVector3Array()
			var n := 12
			for k in n:
				var q := TAU * k / n
				# Lens section: sharp side edges, fuller on the outer face.
				var bulge := thick * (0.55 if sin(q) < 0.0 else 0.45)
				ring.append(centre + tan * (cos(q) * width * 0.5) + nrm * (sin(q) * bulge))
			rings.append(ring)
			if s == steps:
				tips = ring
		kit.loft(white, rings, true, true)
		kit.cap(Looks.get_mat("glass_dark"), tips)
		var tip_c := c + dir * (9.0 + h * 0.48) + Vector3(0, h, 0)
		var base_c := c + dir * 10.0 + Vector3(0, 13.0, 0)
		kit.col_beam(base_c, tip_c, 8.0, 4.0)
	# Promenade furniture round the pond: lamps, benches, bollards at the steps.
	var lamps := []
	var benches := []
	for k in 6:
		var ang := TAU * (k + 0.5) / 6.0
		var p := c + Vector3(cos(ang), 0, sin(ang)) * (pond_r + 4.5)
		p.y = TOP
		if island.grow(-1.0).has_point(Vector2(p.x, p.z)):
			lamps.append(Kit.xf(p, -ang + PI * 0.5))
	for k in 8:
		var ang := TAU * k / 8.0
		var p := c + Vector3(cos(ang), 0, sin(ang)) * (pond_r + 2.4)
		p.y = TOP
		if island.grow(-1.0).has_point(Vector2(p.x, p.z)):
			benches.append(Kit.xf(p, -ang - PI * 0.5))
	Realm.lamps(holder, "ArtScienceLamps", lamps)
	Realm.benches(holder, "ArtScienceBenches", benches)
	# Seawall railing round the three water sides of the promontory.
	var x0 := island.position.x + 0.6
	var x1 := island.end.x - 0.6
	var z0 := island.position.y + 2.5
	var z1 := island.end.y - 0.6
	Realm.railing(kit, Vector3(x0, TOP, z0), Vector3(x0, TOP, z1))
	Realm.railing(kit, Vector3(x0, TOP, z1), Vector3(x1, TOP, z1))
	Realm.railing(kit, Vector3(x1, TOP, z1), Vector3(x1, TOP, z0))
	kit.col_box(Vector3(0.2, 1.3, z1 - z0), Vector3(x0, TOP + 0.65, (z0 + z1) * 0.5))
	kit.col_box(Vector3(x1 - x0, 1.3, 0.2), Vector3((x0 + x1) * 0.5, TOP + 0.65, z1))
	kit.col_box(Vector3(0.2, 1.3, z1 - z0), Vector3(x1, TOP + 0.65, (z0 + z1) * 0.5))
	var sign := Label3D.new()
	sign.text = "ARTSCIENCE MUSEUM"
	sign.font_size = 72
	sign.pixel_size = 0.012
	sign.modulate = Color(0.25, 0.25, 0.26)
	sign.outline_size = 0
	sign.position = Vector3(c.x, TOP + 0.9, island.position.y + 1.4)
	sign.rotation.y = PI
	holder.add_child(sign)
	kit.box(Looks.get_mat("granite_light"), Vector3(c.x, TOP + 0.45, island.position.y + 1.2), Vector3(9.0, 0.9, 0.4))
	kit.commit(holder, "ArtScienceMesh", true)
	return {"shapes": kit.shapes, "tris": kit.tris}
