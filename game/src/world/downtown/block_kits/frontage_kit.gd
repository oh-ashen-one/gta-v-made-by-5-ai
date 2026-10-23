extends RefCounted
## Street frontage for the downtown blocks (original work): Singapore
## covered linkways, porte-cocheres, building name monoliths, shop signs,
## bus stops, planters, bollards and forecourt trees. Everything goes into
## the block's detail Batch (merged per material) except text, which is a
## short-range Label3D.

const Batch := preload("res://src/world/downtown/block_kits/batch.gd")

static func _label(parent: Node3D, text: String, pos: Vector3, facing: Vector2, size_px: int, pixel: float, col: Color, emissive := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.pixel_size = pixel
	l.modulate = col
	l.outline_size = 0
	l.double_sided = false
	l.shaded = not emissive
	l.position = pos
	# Label3D faces +z by default; turn it to face along `facing`.
	l.rotation.y = atan2(facing.x, facing.y)
	l.visibility_range_end = 170.0
	l.visibility_range_end_margin = 30.0
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.set_meta("downtown_blocks", true)
	parent.add_child(l)
	return l

## downtown-fill (wave T): rendered width of a label in font pixels, and the
## largest pixel size (<= want) that keeps it inside `room` metres.
static func text_width(text: String, size_px: int) -> float:
	var font: Font = ThemeDB.fallback_font
	var w := 0.0
	for line in text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x if font != null else size_px * 0.62 * line.length())
	return w

static func fit_pixel(text: String, size_px: int, want: float, room: float) -> float:
	return minf(want, room / maxf(text_width(text, size_px), 1.0))

## Covered walkway along segment a->b. out = unit normal toward the road.
## attached: canopy cantilevers from a facade (columns only on the kerb
## side); free: a stand-alone linkway with columns on both sides.
static func linkway(det: Batch, a: Vector2, b: Vector2, out: Vector2, gy: float, attached: bool, depth: float = 3.2, h: float = 3.7) -> void:
	var dir := (b - a)
	var L := dir.length()
	if L < 2.0:
		return
	dir /= L
	var yaw := atan2(-dir.y, dir.x)
	var mid := (a + b) * 0.5 + out * depth * 0.5
	var basis := Basis(Vector3.UP, yaw)
	# roof deck, fascia, gutter, soffit light strip
	det.box("metal_white", Vector3(L, 0.16, depth + 0.3), Transform3D(basis, Vector3(mid.x, gy + h + 0.08, mid.y)))
	var fas := (a + b) * 0.5 + out * (depth + 0.15)
	det.box("metal_dark", Vector3(L, 0.42, 0.12), Transform3D(basis, Vector3(fas.x, gy + h - 0.05, fas.y)))
	var strip := (a + b) * 0.5 + out * (depth * 0.55)
	det.box("light_strip", Vector3(L - 0.4, 0.04, 0.16), Transform3D(basis, Vector3(strip.x, gy + h - 0.03, strip.y)))
	var n := int(L / 7.5)
	for i in n + 1:
		var q := a + dir * (0.5 + (L - 1.0) * float(i) / float(maxi(1, n))) + out * (depth - 0.2)
		det.column("metal_dark", 0.12, h, Vector3(q.x, gy, q.y), 8)
		if not attached:
			var q2 := a + dir * (0.5 + (L - 1.0) * float(i) / float(maxi(1, n))) + out * 0.2
			det.column("metal_dark", 0.12, h, Vector3(q2.x, gy, q2.y), 8)

## Porte-cochere + name monolith at a tower entrance. c = facade point,
## out = outward normal. Returns nothing; adds a Label3D for the name.
static func entrance(det: Batch, labels: Node3D, c: Vector2, out: Vector2, gy: float, title: String, rng: RandomNumberGenerator) -> void:
	var along := Vector2(-out.y, out.x)
	var yaw := atan2(-along.y, along.x)
	var basis := Basis(Vector3.UP, yaw)
	var w := rng.randf_range(12.0, 18.0)
	var depth := rng.randf_range(7.0, 10.0)
	var hh := rng.randf_range(5.2, 6.4)
	var cc := c + out * depth * 0.5
	det.box("metal_light", Vector3(w, 0.5, depth), Transform3D(basis, Vector3(cc.x, gy + hh, cc.y)))
	det.box("light_strip", Vector3(w - 1.0, 0.05, depth - 1.5), Transform3D(basis, Vector3(cc.x, gy + hh - 0.27, cc.y)))
	for s in [-1.0, 1.0]:
		var q: Vector2 = c + out * (depth - 0.8) + along * s * (w * 0.5 - 0.8)
		det.column("metal_light", 0.28, hh, Vector3(q.x, gy, q.y), 10)
	# revolving door drum and glass lobby doors
	det.column("metal_dark", 1.5, 2.9, Vector3(c.x + out.x * 1.4, gy, c.y + out.y * 1.4), 14)
	det.box("metal_dark", Vector3(3.1, 0.25, 3.1), Transform3D(basis, Vector3(c.x + out.x * 1.4, gy + 3.0, c.y + out.y * 1.4)))
	# drop-off kerb island and bollards
	for i in 6:
		var bq := c + out * (depth + 1.2) + along * (-w * 0.5 + w * float(i) / 5.0)
		det.column("metal_dark", 0.11, 0.9, Vector3(bq.x, gy, bq.y), 8)
	# name monolith beside the drop-off
	var m := c + out * (depth + 3.0) + along * (w * 0.5 + 3.0)
	det.box("granite", Vector3(4.6, 1.5, 0.7), Transform3D(basis, Vector3(m.x, gy + 0.75, m.y)))
	_label(labels, title, Vector3(m.x + out.x * 0.37, gy + 0.85, m.y + out.y * 0.37), out, 64, fit_pixel(title, 64, 0.0105, 4.1), Color(0.93, 0.86, 0.66))
	# name on the canopy fascia too (readable from the road)
	var f := c + out * (depth + 0.02)
	_label(labels, title, Vector3(f.x, gy + hh + 0.02, f.y), out, 72, fit_pixel(title, 72, 0.012, w - 1.2), Color(0.95, 0.95, 0.93), true)

## Shop signs along a facade a->b (above the canopy) with lit lettering.
static func shop_signs(det: Batch, labels: Node3D, a: Vector2, b: Vector2, out: Vector2, gy: float, y: float, names: Array, rng: RandomNumberGenerator, start: int) -> int:
	var dir := b - a
	var L := dir.length()
	if L < 10.0:
		return start
	dir /= L
	var yaw := atan2(-dir.y, dir.x)
	var basis := Basis(Vector3.UP, yaw)
	var n := int(L / 13.0)
	var used := start
	for i in n:
		if rng.randf() < 0.45:
			continue
		var t := (float(i) + 0.5) / float(n)
		var q := a + dir * L * t + out * 0.18
		var sw := rng.randf_range(4.0, 7.0)
		# downtown-fill (wave T): the plate always holds its lettering
		var shop_name := String(names[used % names.size()])
		sw = maxf(sw, text_width(shop_name, 56) * 0.0085 + 0.8)
		det.box("sign_dark", Vector3(sw, 0.85, 0.14), Transform3D(basis, Vector3(q.x, gy + y, q.y)))
		_label(labels, shop_name, Vector3(q.x + out.x * 0.09, gy + y, q.y + out.y * 0.09), out, 56, 0.0085,
			[Color(1.0, 0.92, 0.75), Color(0.85, 0.95, 1.0), Color(1.0, 0.55, 0.40), Color(0.75, 1.0, 0.82)][used % 4], true)
		used += 1
	return used

## Bus stop on the footway: roof, rear glass, lit ad panel, bench, pole sign.
static func bus_stop(det: Batch, labels: Node3D, c: Vector2, out: Vector2, gy: float, stop_name: String) -> void:
	var along := Vector2(-out.y, out.x)
	var yaw := atan2(-along.y, along.x)
	var basis := Basis(Vector3.UP, yaw)
	var L := 9.0
	det.box("metal_white", Vector3(L, 0.18, 2.6), Transform3D(basis, Vector3(c.x, gy + 2.75, c.y)))
	det.box("light_cool", Vector3(L - 0.6, 0.04, 0.2), Transform3D(basis, Vector3(c.x, gy + 2.64, c.y)))
	for s in [-1.0, 0.0, 1.0]:
		var q: Vector2 = c - out * 1.1 + along * s * (L * 0.5 - 0.3)
		det.column("metal_dark", 0.09, 2.7, Vector3(q.x, gy, q.y), 8)
	var back := c - out * 1.15
	det.box("shelter_glass", Vector3(L - 2.2, 2.0, 0.06), Transform3D(basis, Vector3(back.x, gy + 1.3, back.y)))
	var ad := c - out * 1.1 + along * (L * 0.5 - 0.6)
	det.box("ad_panel", Vector3(1.3, 1.9, 0.18), Transform3D(basis, Vector3(ad.x, gy + 1.25, ad.y)))
	det.box("metal_dark", Vector3(1.45, 2.05, 0.12), Transform3D(basis, Vector3(ad.x - out.x * 0.05, gy + 1.25, ad.y - out.y * 0.05)))
	var bench := c - out * 0.7
	det.box("metal_light", Vector3(4.0, 0.08, 0.5), Transform3D(basis, Vector3(bench.x, gy + 0.46, bench.y)))
	var pole := c + out * 1.0 + along * (L * 0.5 + 0.8)
	det.column("metal_dark", 0.06, 3.0, Vector3(pole.x, gy, pole.y), 6)
	det.box("bus_sign", Vector3(0.7, 0.9, 0.05), Transform3D(basis, Vector3(pole.x, gy + 2.6, pole.y)))
	_label(labels, stop_name, Vector3(c.x + out.x * 0.0, gy + 2.95, c.y + out.y * 0.0) + Vector3(out.x, 0, out.y) * 1.32, out, 40, 0.008, Color(0.95, 0.95, 0.95), true)

## Planter with a tree slot; returns the tree position for batching.
static func planter_tree(det: Batch, p: Vector2, gy: float) -> Vector3:
	det.box_at("planter", Vector3(2.2, 0.55, 2.2), Vector3(p.x, gy + 0.27, p.y))
	det.box_at("soil", Vector3(1.9, 0.1, 1.9), Vector3(p.x, gy + 0.52, p.y))
	return Vector3(p.x, gy + 0.5, p.y)

static func hedge(det: Batch, a: Vector2, b: Vector2, gy: float) -> void:
	var dir := b - a
	var L := dir.length()
	if L < 1.0:
		return
	var yaw := atan2(-dir.y, dir.x)
	var mid := (a + b) * 0.5
	det.box("planter", Vector3(L, 0.6, 1.3), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, gy + 0.3, mid.y)))
	det.box("shrub", Vector3(L - 0.3, 0.55, 1.0), Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, gy + 0.85, mid.y)))
