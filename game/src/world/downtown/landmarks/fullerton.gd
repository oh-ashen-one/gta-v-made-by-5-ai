extends RefCounted
## The Fullerton Hotel, One Fullerton and the Merlion Park terrace (wave M,
## downtown-landmarks). The Merlion statue itself stays on its pier (plan O-1);
## the geographic park at the river mouth gets its viewing terrace, steps to
## the water and a small cub statue on a plinth, framed by One Fullerton's
## waterfront dining pavilions and the granite neoclassical hotel behind.

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")

const TOP := 0.36

func build(world: WorldBuilder, root: Node3D) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "FullertonWaterfront"
	root.add_child(holder)
	var kit := Kit.new(holder, "FullertonCollision")
	_hotel(kit, holder)
	_one_fullerton(kit, holder, world)
	kit.commit(holder, "FullertonMesh", true)
	return {"shapes": kit.shapes, "tris": kit.tris}

func _hotel(kit: Kit, holder: Node3D) -> void:
	var a: Dictionary = DowntownPlan.ANCHORS["fullerton_hotel"]
	var p: Vector3 = a["pos"]
	var size: Vector3 = a["size"]
	var x0 := p.x - size.x * 0.5
	var x1 := p.x + size.x * 0.5
	var z0 := p.z - size.z * 0.5
	var z1 := p.z + size.z * 0.5
	var stone := Looks.get_mat("fullerton_granite")
	var shadow := Looks.get_mat("fullerton_shadow")
	var glass := Looks.get_mat("window_glass")
	var site := DowntownPlan.block_rect("fullerton_site")
	var sc := site.get_center()
	kit.box(Looks.get_mat("granite_paving"), Vector3(sc.x, TOP * 0.5 - 0.3, sc.y), Vector3(site.size.x, TOP + 0.6, site.size.y))
	kit.col_box(Vector3(site.size.x, 1.0, site.size.y), Vector3(sc.x, TOP - 0.5, sc.y))
	var inset := 3.0
	var body_h := 27.0
	# Main block set back behind the colonnades; rusticated base course.
	kit.box(stone, Vector3(p.x + inset * 0.5, TOP + body_h * 0.5, p.z + inset * 0.5), Vector3(size.x - inset, body_h, size.z - inset))
	kit.box(stone, Vector3(p.x + inset * 0.5, TOP + body_h + 3.0, p.z + inset * 0.5), Vector3(size.x - inset - 4.0, 6.0, size.z - inset - 4.0))
	kit.col_box(Vector3(size.x, body_h + 6.0, size.z), Vector3(p.x, TOP + (body_h + 6.0) * 0.5, p.z))
	# Facade grammar on the two public faces (-z bay/Collyer Quay, -x river).
	var faces := [
		{"o": Vector3(x0, 0, z0), "d": Vector3(1, 0, 0), "n": Vector3(0, 0, -1), "len": size.x},
		{"o": Vector3(x0, 0, z1), "d": Vector3(0, 0, -1), "n": Vector3(-1, 0, 0), "len": size.z},
	]
	for f: Dictionary in faces:
		var o: Vector3 = f["o"]
		var d: Vector3 = f["d"]
		var n: Vector3 = f["n"]
		var flen: float = f["len"]
		var wall := o - n * inset
		# Rustication grooves on the base (0..8 m).
		for k in 8:
			kit.beam(shadow, wall + Vector3(0, TOP + 1.0 + k * 0.95, 0) + n * 0.02, wall + d * flen + Vector3(0, TOP + 1.0 + k * 0.95, 0) + n * 0.02, 0.12, 0.08)
		# Plinth podium the colonnade stands on.
		kit.box(stone, o + d * flen * 0.5 - n * inset * 0.5 + Vector3(0, TOP + 4.0, 0), (d * flen + n * inset).abs() + Vector3(0, 8.0, 0) + (d.abs() * 0.0))
		var ncol := int(flen / 4.8)
		for k in ncol + 1:
			var cpos := o + d * (k * flen / ncol) - n * 1.0
			kit.cyl(stone, cpos + Vector3(0, TOP + 8.0, 0), 0.85, 0.72, 15.5, 12, false)
			kit.box(stone, cpos + Vector3(0, TOP + 8.25, 0), Vector3(2.0, 0.5, 2.0))
			kit.box(stone, cpos + Vector3(0, TOP + 23.7, 0), Vector3(2.1, 0.5, 2.1))
		# Entablature and cornice over the colonnade.
		kit.box(stone, o + d * flen * 0.5 - n * (inset * 0.5 - 0.4) + Vector3(0, TOP + 25.0, 0), (d * (flen + 2.0) + n * (inset + 1.2)).abs() + Vector3(0, 2.4, 0))
		kit.box(Looks.get_mat("granite_light"), o + d * flen * 0.5 - n * (inset * 0.5 - 0.9) + Vector3(0, TOP + 26.5, 0), (d * (flen + 3.0) + n * (inset + 2.2)).abs() + Vector3(0, 0.6, 0))
		# Windows: arched base openings, three tall rows behind the columns, attic row.
		var nwin := int(flen / 4.8)
		for k in nwin:
			var wc := wall + d * ((k + 0.5) * flen / nwin) + n * 0.06
			kit.box(glass, wc + Vector3(0, TOP + 3.6, 0), (d * 2.0).abs() + n.abs() * 0.12 + Vector3(0, 4.2, 0))
			kit.box(shadow, wc + Vector3(0, TOP + 5.9, 0), (d * 2.4).abs() + n.abs() * 0.14 + Vector3(0, 0.5, 0))
			for row: float in [11.0, 15.5, 20.0]:
				kit.box(glass, wc + Vector3(0, TOP + row, 0), (d * 1.6).abs() + n.abs() * 0.12 + Vector3(0, 2.6, 0))
				kit.box(Looks.get_mat("granite_light"), wc + Vector3(0, TOP + row - 1.45, 0) + n * 0.1, (d * 2.0).abs() + n.abs() * 0.25 + Vector3(0, 0.2, 0))
			kit.box(glass, wc + Vector3(0, TOP + body_h + 2.4, 0) + n * (-2.0 + 0.0), (d * 1.4).abs() + n.abs() * 0.12 + Vector3(0, 1.6, 0))
	# Main entrance portico and lantern pavilion on the bay front.
	var ent := Vector3(p.x, TOP, z0 - 0.5)
	kit.box(stone, ent + Vector3(0, 9.0, -1.5), Vector3(16.0, 18.0, 3.0))
	kit.box(glass, ent + Vector3(0, 3.0, -3.05), Vector3(6.0, 5.0, 0.1))
	kit.box(Looks.get_mat("granite_light"), ent + Vector3(0, 18.6, -1.5), Vector3(18.0, 1.2, 4.0))
	var lantern := Vector3(p.x, TOP + body_h + 6.0, z0 + 10.0)
	kit.box(stone, lantern + Vector3(0, 2.5, 0), Vector3(10.0, 5.0, 10.0))
	kit.cyl(Looks.get_mat("glass_clear"), lantern + Vector3(0, 5.0, 0), 3.2, 3.2, 3.4, 12, false)
	kit.cyl(Looks.get_mat("steel_bronze"), lantern + Vector3(0, 8.4, 0), 3.8, 0.4, 2.6, 12, true)
	kit.cyl(Looks.get_mat("steel_dark"), lantern + Vector3(0, 11.0, 0), 0.08, 0.06, 9.0, 6, true)
	var sign := Label3D.new()
	sign.text = "THE FULLERTON"
	sign.font_size = 96
	sign.pixel_size = 0.016
	sign.modulate = Color(0.24, 0.22, 0.19)
	sign.outline_size = 0
	sign.position = ent + Vector3(0, 16.2, -3.08)
	sign.rotation.y = PI
	holder.add_child(sign)
	# Forecourt lamps and bollards along Collyer Quay and the river.
	var lamps := []
	var bollards := []
	for k in 6:
		lamps.append(Kit.xf(Vector3(x0 + 6.0 + k * 13.5, TOP, site.position.y + 3.0), 0.0))
	for k in 12:
		bollards.append(Vector3(x0 + 4.0 + k * 6.5, TOP, z0 - 4.0))
	Realm.lamps(holder, "FullertonLamps", lamps)
	Realm.bollards(holder, "FullertonBollards", bollards)

func _one_fullerton(kit: Kit, holder: Node3D, world: WorldBuilder) -> void:
	var pen: Rect2 = DowntownPlan.ISLANDS["fullerton_peninsula"]
	var pz0 := pen.position.y
	var pz1 := pen.end.y
	var px0 := pen.position.x
	var px1 := pen.end.x
	# Peninsula deck (granite) with collision; seawall skirt to the water.
	var pc := pen.get_center()
	kit.box(Looks.get_mat("granite_paving"), Vector3(pc.x, TOP * 0.5 - 0.9, pc.y), Vector3(pen.size.x, TOP + 1.8, pen.size.y))
	kit.col_box(Vector3(pen.size.x, 1.2, pen.size.y), Vector3(pc.x, TOP - 0.6, pc.y))
	# Two low dining pavilions: glass shopfronts, deep flat roofs, warm interiors.
	var white := Looks.get_mat("steel_white")
	for pv: Array in [[-524.0, -504.0], [-500.0, -480.0]]:
		var vx0: float = pv[0]
		var vx1: float = pv[1]
		var vc := Vector3((vx0 + vx1) * 0.5, TOP, -396.0)
		var vs := Vector3(vx1 - vx0, 8.0, 16.0)
		kit.box(Looks.get_mat("interior_warm"), vc + Vector3(0, 3.6, 0), Vector3(vs.x - 2.0, 7.2, vs.z - 2.0))
		kit.box(Looks.get_mat("glass_clear"), vc + Vector3(0, 3.7, 0), Vector3(vs.x - 1.4, 7.4, vs.z - 1.4))
		kit.box(white, vc + Vector3(0, 7.9, 0), Vector3(vs.x + 5.0, 0.7, vs.z + 6.0))
		for cx: float in [vx0 - 1.5, vx1 + 1.5]:
			for cz: float in [-396.0 - 9.5, -396.0 + 9.5]:
				kit.cyl(white, Vector3(cx, TOP, cz), 0.2, 0.2, 7.5, 8, false)
		kit.col_box(Vector3(vs.x - 1.4, 7.4, vs.z - 1.4), vc + Vector3(0, 3.7, 0))
		var sign := Label3D.new()
		sign.text = "ONE FULLERTON"
		sign.font_size = 64
		sign.pixel_size = 0.012
		sign.modulate = Color(0.2, 0.2, 0.2)
		sign.outline_size = 0
		sign.position = vc + Vector3(0, 7.9, -11.05)
		sign.rotation.y = PI
		holder.add_child(sign)
	# Alfresco dining terrace on the bay side: umbrellas and tables.
	var k2 := Kit.new()
	k2.cyl(Looks.get_mat("steel_dark"), Vector3.ZERO, 0.05, 0.05, 2.5, 6, false)
	k2.cyl(Looks.get_mat("render_cream"), Vector3(0, 2.2, 0), 1.6, 0.05, 0.6, 10, true)
	k2.cyl(Looks.get_mat("timber"), Vector3(0, 0.0, 0), 0.5, 0.5, 0.74, 10, true)
	var umbrellas := []
	var ux := px0 + 4.0
	while ux < -481.0:
		umbrellas.append(Kit.xf(Vector3(ux, TOP, pz0 + 4.5), ux))
		ux += 4.2
	Kit.multimesh(holder, "OneFullertonUmbrellas", k2.to_mesh(), umbrellas, false, 300.0)
	# Merlion Park viewing terrace at the peninsula tip.
	var t0 := -476.0
	var deck_y := TOP + 0.9
	var tc := Vector3((t0 + px1) * 0.5, 0, (pz0 + pz1) * 0.5)
	kit.box(Looks.get_mat("granite_light"), Vector3(tc.x, deck_y * 0.5, tc.z), Vector3(px1 - t0, deck_y, pz1 - pz0))
	kit.col_beam(Vector3(t0 - 6.0, TOP, tc.z), Vector3(t0, deck_y, tc.z), pz1 - pz0, 0.5)
	kit.col_box(Vector3(px1 - t0, deck_y, pz1 - pz0), Vector3(tc.x, deck_y * 0.5, tc.z))
	for s in 4:
		kit.box(Looks.get_mat("granite_light"), Vector3(t0 - 1.5 * (s + 0.5), (deck_y - 0.22 * s) * 0.5, tc.z), Vector3(1.5, deck_y - 0.22 * s, pz1 - pz0 - 2.0))
	# Stepped seating down toward the water on the bay edge.
	for s in 3:
		kit.box(Looks.get_mat("granite_light"), Vector3(tc.x, deck_y - 0.3 * (s + 1), pz0 + 1.0 + s * 1.4), Vector3(px1 - t0 - 4.0, 0.3, 1.4))
	# Cub statue on a plinth (the main statue stays on its pier, decision O-1).
	var cub := Vector3(px1 - 9.0, deck_y, pz0 + 9.0)
	kit.cyl(Looks.get_mat("granite_dark"), cub, 1.8, 1.6, 1.4, 12, true)
	var statue := world._authored("merlion_landmark.glb", cub + Vector3(0, 1.4, 0), deg_to_rad(-130.0), Vector3.ONE * 0.28)
	kit.col_box(Vector3(3.4, 4.0, 3.4), cub + Vector3(0, 2.0, 0))
	var lamps := []
	for k in 4:
		lamps.append(Kit.xf(Vector3(t0 + 4.0 + k * 9.0, deck_y, pz1 - 2.0), PI))
	# Planters with palms and lamps along the bay rail, framing the view to MBS.
	var palms := []
	for k in 3:
		var ppos := Vector3(t0 + 6.0 + k * 8.5, deck_y, pz0 + 6.2)
		Realm.planter(kit, ppos, Vector2(5.0, 2.0), 0.5)
		palms.append(Kit.xf(ppos + Vector3(0, 0.5, 0), k * 1.3, Vector3.ONE * (0.9 + 0.1 * k)))
		lamps.append(Kit.xf(Vector3(t0 + 10.5 + k * 8.5, deck_y, pz0 + 6.2), 0.0))
	Kit.multimesh(holder, "MerlionParkPalms", Realm.palm_mesh(), palms, true, 400.0)
	Realm.lamps(holder, "MerlionParkLamps", lamps)
	var benches := []
	for k in 4:
		benches.append(Kit.xf(Vector3(t0 + 5.0 + k * 8.0, deck_y, pz1 - 5.0), PI))
	Realm.benches(holder, "MerlionParkBenches", benches)
	# Waterside railings on the open edges (gap for the seating steps).
	Realm.railing(kit, Vector3(px1 - 0.6, deck_y, pz0 + 6.0), Vector3(px1 - 0.6, deck_y, pz1 - 0.6))
	Realm.railing(kit, Vector3(px0 + 0.6, TOP, pz0 + 0.6), Vector3(t0 - 8.0, TOP, pz0 + 0.6))
	kit.col_box(Vector3(0.2, 1.3, pz1 - pz0 - 6.0), Vector3(px1 - 0.6, deck_y + 0.65, (pz0 + 6.0 + pz1) * 0.5))
	kit.col_box(Vector3(t0 - 8.0 - px0, 1.3, 0.2), Vector3((px0 + t0 - 8.0) * 0.5, TOP + 0.65, pz0 + 0.6))
	var sign2 := Label3D.new()
	sign2.text = "MERLION PARK"
	sign2.font_size = 72
	sign2.pixel_size = 0.012
	sign2.modulate = Color(0.92, 0.9, 0.84)
	sign2.position = Vector3(t0 - 0.2, deck_y + 1.4, pz1 - 3.0)
	sign2.rotation.y = -PI * 0.5
	holder.add_child(sign2)
	kit.box(Looks.get_mat("signage"), Vector3(t0 + 0.1, deck_y + 1.0, pz1 - 3.0), Vector3(0.3, 2.0, 3.4))
