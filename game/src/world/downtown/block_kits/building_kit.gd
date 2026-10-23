extends RefCounted
## Building designs for the downtown blocks piece (original work).
##
## Towers come in eight silhouettes (setbacks, slanted crowns, octagonal
## steps, rounded towers with spires, twin blades, notched plans, sliced
## ovals, clipped corners). Each design writes its shell into the block's
## MeshKit (shared facade shader) and its crown hardware / roof plant into
## the block's detail Batch. Neighbouring buildings never repeat the same
## (style, cladding) pair (see blocks.gd).

const MeshKit := preload("res://src/world/downtown/block_kits/mesh_kit.gd")
const Batch := preload("res://src/world/downtown/block_kits/batch.gd")

const STYLE_NAMES := ["setback", "slant", "octagon", "rounded_spire", "twin_blade", "notched", "oval_slice", "clipped_step"]

static func info(cid: int, rng: RandomNumberGenerator, H: float, lobby: float, ground_y: float) -> Dictionary:
	return {"cid": cid, "tint": rng.randf(), "fl": rng.randf(), "seed": rng.randf(), "H": H, "lobby": lobby, "ground_y": ground_y}

## A tower or mid-rise shell. Returns {"top": y, "style": s, "cid": cid}.
static func tower(k: MeshKit, det: Batch, rng: RandomNumberGenerator, c: Vector2, w: float, d: float, h: float, style: int, cid: int,
		cid2: int, ground_y: float, base_y: float, lobby: float) -> Dictionary:
	var H := h
	var inf := info(cid, rng, H, lobby, ground_y)
	var m := minf(w, d)
	var top_y := ground_y + h
	var span := top_y - base_y
	var long_x := w >= d
	var crown_poly := PackedVector2Array()
	var crown_y := top_y
	match style:
		0: # setback slab
			var p0 := MeshKit.chamfer(c.x, c.y, w, d, 2.5)
			k.prism(p0, base_y, base_y + span * 0.62, inf)
			var p1 := MeshKit.scaled(p0, Vector2(0.86, 0.86), c)
			k.prism(p1, base_y + span * 0.62, base_y + span * 0.85, inf)
			crown_poly = MeshKit.scaled(p0, Vector2(0.70, 0.70), c)
			k.prism(crown_poly, base_y + span * 0.85, top_y, inf)
		1: # slanted crown
			var p := MeshKit.chamfer(c.x, c.y, w, d, 1.5)
			var rise := clampf(span * 0.16, 8.0, 34.0)
			var sl := Vector2(rise / w, 0.0) if long_x else Vector2(0.0, rise / d)
			if rng.randf() < 0.5:
				sl = -sl
			crown_y = k.prism(p, base_y, top_y - rise * 0.5, inf, sl)
			top_y = crown_y
		2: # octagonal setbacks with a pointed crown
			var p := MeshKit.chamfer(c.x, c.y, w, d, m * 0.29)
			k.prism(p, base_y, base_y + span * 0.70, inf)
			k.prism(MeshKit.scaled(p, Vector2(0.88, 0.88), c), base_y + span * 0.70, base_y + span * 0.88, inf)
			crown_poly = MeshKit.scaled(p, Vector2(0.72, 0.72), c)
			k.prism(crown_poly, base_y + span * 0.88, base_y + span * 0.96, inf)
			var cap := MeshKit.scaled(p, Vector2(0.42, 0.42), c)
			var inf2 := inf.duplicate(); inf2["cid"] = 2
			k.prism(cap, base_y + span * 0.96, top_y, inf2)
			det.column("metal_light", 0.45, span * 0.10, Vector3(c.x, top_y, c.y), 6)
			top_y += span * 0.10
		3: # rounded tower, crown ring and spire
			var p := MeshKit.rounded(c.x, c.y, w, d, m * 0.28, 4)
			k.prism(p, base_y, base_y + span * 0.92, inf)
			crown_poly = MeshKit.scaled(p, Vector2(0.82, 0.82), c)
			var inf2 := inf.duplicate(); inf2["cid"] = 2
			k.prism(crown_poly, base_y + span * 0.92, top_y, inf2)
			det.column("metal_light", 0.35, span * 0.12, Vector3(c.x, top_y, c.y), 6)
			det.column("metal_light", 0.9, 2.0, Vector3(c.x, top_y, c.y), 8)
			top_y += span * 0.12
		4: # twin blades of different height and cladding
			var a_w := (w * 0.56) if long_x else w
			var a_d := d if long_x else d * 0.56
			var off := Vector2(w * 0.22, 3.0) if long_x else Vector2(3.0, d * 0.22)
			var pa := MeshKit.chamfer(c.x - off.x, c.y - off.y, a_w, a_d, 1.2)
			k.prism(pa, base_y, top_y, inf)
			var inf2 := info(cid2, rng, H * 0.78, lobby, ground_y)
			var pb := MeshKit.chamfer(c.x + off.x, c.y + off.y, a_w * 0.95, a_d * 0.95, 1.2)
			k.prism(pb, base_y, ground_y + h * 0.78, inf2)
			crown_poly = MeshKit.scaled(pa, Vector2(0.6, 0.6), c - off)
		5: # notched cross plan, stepped crown
			var p := MeshKit.notched(c.x, c.y, w, d, m * 0.17)
			k.prism(p, base_y, base_y + span * 0.80, inf)
			k.prism(MeshKit.scaled(p, Vector2(0.86, 0.86), c), base_y + span * 0.80, base_y + span * 0.93, inf)
			crown_poly = MeshKit.scaled(MeshKit.rect(c.x, c.y, w, d), Vector2(0.5, 0.5), c)
			var inf2 := inf.duplicate(); inf2["cid"] = 4
			k.prism(crown_poly, base_y + span * 0.93, top_y, inf2)
		6: # oval, sliced top
			var p := MeshKit.oval(c.x, c.y, w, d, 22)
			var rise := clampf(span * 0.12, 6.0, 26.0)
			var sl := Vector2(rise / w, rise / d * 0.3) * (1.0 if rng.randf() < 0.5 else -1.0)
			crown_y = k.prism(p, base_y, top_y - rise * 0.5, inf, sl)
			top_y = crown_y
		_: # clipped corner, steps, slanted cap
			var corner := rng.randi() % 4
			var p := MeshKit.clipped(c.x, c.y, w, d, m * 0.38, corner)
			k.prism(p, base_y, base_y + span * 0.55, inf)
			var p2 := MeshKit.scaled(p, Vector2(0.88, 0.88), c)
			k.prism(p2, base_y + span * 0.55, base_y + span * 0.82, inf)
			var p3 := MeshKit.scaled(p, Vector2(0.74, 0.74), c)
			var rise := clampf(span * 0.10, 5.0, 20.0)
			var sl := Vector2(rise / w, 0.0) if long_x else Vector2(0.0, rise / d)
			top_y = k.prism(p3, base_y + span * 0.82, top_y - rise * 0.5, inf, sl)
	# roof plant / water tanks / gondola track on flat crowns
	if crown_poly.size() > 0 and style != 1 and style != 6:
		var b := MeshKit.bounds(crown_poly)
		var ry := crown_y if style != 2 and style != 3 else -1.0
		if ry > 0.0:
			var pw := b.size.x * rng.randf_range(0.35, 0.55)
			var pd := b.size.y * rng.randf_range(0.35, 0.55)
			det.box_at("metal_dark", Vector3(pw, 3.2, pd), Vector3(b.get_center().x + rng.randf_range(-2, 2), ry + 1.6, b.get_center().y + rng.randf_range(-2, 2)))
			det.box_at("metal_light", Vector3(pw + 0.4, 0.25, pd + 0.4), Vector3(b.get_center().x, ry + 3.3, b.get_center().y))
			for i in rng.randi_range(2, 4):
				det.column("metal_light", rng.randf_range(0.9, 1.6), rng.randf_range(1.5, 2.6), Vector3(b.position.x + rng.randf_range(2, b.size.x - 2), ry, b.position.y + rng.randf_range(2, b.size.y - 2)), 10)
			# parapet rim
			det.box_at("metal_light", Vector3(b.size.x, 0.9, 0.3), Vector3(b.get_center().x, ry + 0.45, b.position.y + 0.15))
			det.box_at("metal_light", Vector3(b.size.x, 0.9, 0.3), Vector3(b.get_center().x, ry + 0.45, b.end.y - 0.15))
			if rng.randf() < 0.5 and h > 120.0:
				det.column("metal_light", 0.18, rng.randf_range(10.0, 22.0), Vector3(b.get_center().x + b.size.x * 0.3, ry + 3.2, b.get_center().y), 4)
	return {"top": top_y, "style": style, "cid": cid}

## Podium across a lot: retail / lobby band at the street, stone or metal
## above, landscaped roof deck. Returns the roof height.
static func podium(k: MeshKit, det: Batch, rng: RandomNumberGenerator, r: Rect2, h: float, cid: int, ground_y: float, lobby: float) -> float:
	var inf := info(cid, rng, h, lobby, ground_y)
	var p := MeshKit.chamfer(r.get_center().x, r.get_center().y, r.size.x, r.size.y, 1.0)
	k.prism(p, ground_y - 1.5, ground_y + h, inf)
	# roof garden strips and planters on the podium deck
	var top := ground_y + h
	for i in rng.randi_range(2, 4):
		var gw := r.size.x * rng.randf_range(0.15, 0.3)
		var gd := r.size.y * rng.randf_range(0.15, 0.3)
		var gx := r.position.x + rng.randf_range(gw * 0.5 + 2.0, r.size.x - gw * 0.5 - 2.0)
		var gz := r.position.y + rng.randf_range(gd * 0.5 + 2.0, r.size.y - gd * 0.5 - 2.0)
		det.box_at("planter", Vector3(gw, 0.7, gd), Vector3(gx, top + 0.35, gz))
		det.box_at("shrub", Vector3(gw - 0.6, 0.5, gd - 0.6), Vector3(gx, top + 0.9, gz))
	# glass balustrade rim
	det.box_at("metal_light", Vector3(r.size.x, 1.1, 0.12), Vector3(r.get_center().x, top + 0.55, r.position.y + 0.3))
	det.box_at("metal_light", Vector3(r.size.x, 1.1, 0.12), Vector3(r.get_center().x, top + 0.55, r.end.y - 0.3))
	det.box_at("metal_light", Vector3(0.12, 1.1, r.size.y), Vector3(r.position.x + 0.3, top + 0.55, r.get_center().y))
	det.box_at("metal_light", Vector3(0.12, 1.1, r.size.y), Vector3(r.end.x - 0.3, top + 0.55, r.get_center().y))
	return top

## Low colonial civic block: white plaster, colonnade, cornice, optional dome.
static func colonial(k: MeshKit, det: Batch, rng: RandomNumberGenerator, r: Rect2, h: float, front: Vector2, ground_y: float, dome: bool) -> void:
	var inf := info(8, rng, h, 4.6, ground_y)
	var p := MeshKit.rect(r.get_center().x, r.get_center().y, r.size.x, r.size.y)
	k.prism(p, ground_y - 1.0, ground_y + h, inf)
	# attic storey set back
	var inf2 := info(8, rng, h + 4.0, 0.0, ground_y)
	k.prism(MeshKit.scaled(p, Vector2(0.9, 0.86), r.get_center()), ground_y + h, ground_y + h + 3.2, inf2)
	# cornice lines all round
	for yy in [ground_y + 4.6, ground_y + h - 0.4]:
		det.box_at("plaster_white", Vector3(r.size.x + 0.8, 0.45, 0.6), Vector3(r.get_center().x, yy, r.position.y))
		det.box_at("plaster_white", Vector3(r.size.x + 0.8, 0.45, 0.6), Vector3(r.get_center().x, yy, r.end.y))
		det.box_at("plaster_white", Vector3(0.6, 0.45, r.size.y + 0.8), Vector3(r.position.x, yy, r.get_center().y))
		det.box_at("plaster_white", Vector3(0.6, 0.45, r.size.y + 0.8), Vector3(r.end.x, yy, r.get_center().y))
	# colonnade on the front: giant-order columns + entablature + steps
	var along := Vector2(-front.y, front.x)
	var long_len := r.size.y if absf(front.x) > 0.5 else r.size.x
	var face_c := r.get_center() + front * ((r.size.x if absf(front.x) > 0.5 else r.size.y) * 0.5)
	var col_h := minf(h - 1.0, 13.0)
	var span := long_len * 0.62
	var n_cols := int(span / 4.2)
	for i in n_cols + 1:
		var q := face_c + along * (-span * 0.5 + span * float(i) / float(n_cols)) + front * 3.2
		det.column("plaster_white", 0.55, col_h, Vector3(q.x, ground_y + 0.6, q.y), 12)
	var ent_c := face_c + front * 3.2
	var ent_size := Vector3(span + 1.6, 1.6, 7.0) if absf(front.y) > 0.5 else Vector3(7.0, 1.6, span + 1.6)
	det.box_at("plaster_white", ent_size, Vector3(ent_c.x - front.x * 1.6, ground_y + 0.6 + col_h + 0.8, ent_c.y - front.y * 1.6))
	# pediment-ish attic block over the portico
	var ped := Vector3(span * 0.5, 3.0, 2.0) if absf(front.y) > 0.5 else Vector3(2.0, 3.0, span * 0.5)
	det.box_at("plaster_white", ped, Vector3(ent_c.x, ground_y + col_h + 3.4, ent_c.y))
	for s in 3:
		var stp := Vector3(span + 4.0, 0.2, 1.4) if absf(front.y) > 0.5 else Vector3(1.4, 0.2, span + 4.0)
		var sp := ent_c + front * (2.8 - float(s) * 0.0) + front * float(2 - s) * 1.2
		det.box_at("granite_light", stp, Vector3(sp.x, ground_y + 0.1 + 0.2 * float(s), sp.y))
	if dome:
		var dc := r.get_center()
		var dy := ground_y + h + 3.2
		var rad := minf(r.size.x, r.size.y) * 0.22
		var infd := info(4, rng, h + 30.0, 0.0, ground_y)
		k.prism(MeshKit.oval(dc.x, dc.y, rad * 2.1, rad * 2.1, 24), dy, dy + 5.0, info(8, rng, h + 30.0, 0.0, ground_y))
		var steps := 6
		for i in steps:
			var a0 := float(i) / float(steps) * PI * 0.5
			var a1 := float(i + 1) / float(steps) * PI * 0.5
			var rr := cos(a0) * rad
			k.prism(MeshKit.oval(dc.x, dc.y, rr * 2.0, rr * 2.0, 24), dy + 5.0 + sin(a0) * rad * 0.8, dy + 5.0 + sin(a1) * rad * 0.8, infd, Vector2.ZERO, true, false, false)
		det.column("bronze", 0.6, 5.0, Vector3(dc.x, dy + 5.0 + rad * 0.8, dc.y), 8)
