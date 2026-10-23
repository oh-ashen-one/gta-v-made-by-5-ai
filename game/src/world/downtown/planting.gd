extends RefCounted
## downtown-polish (wave S): layered roadside planting for the downtown roads.
## Original work; reuses the project's own assets only (rain_tree.glb,
## palm.glb, the nearfield photographic plant cards / procedural shrub
## clumps).
##
## Critic gap (downtown-map M2, standing): "behind the roadside barriers the
## frame must show a varied, layered landscape ... at least 3 visibly
## different species or sizes, with no identical tree mesh repeated at uniform
## spacing". Singapore's arterials are planted in layers: a kerbside strip of
## ground cover (mondo grass, spider lily) with flowering shrub clumps (ixora,
## croton) and bird's-nest ferns, palms (royal / foxtail) in the tree pits
## between the big rain-tree canopies, and planted medians. This builds:
##   - a 0.75 m kerbside planting strip on every downtown footway (broken at
##     junction mouths, bus stops and bridge decks), mixed clumps with jitter,
##     scale and species variation;
##   - palms interleaved with the rain trees in the footway tree pits (the
##     tree-pit species is chosen per pit, never a uniform alternation);
##   - median beds (Bayfront Avenue, Bayfront Avenue North) under-planted with
##     shrubs and palms between the existing rain trees;
##   - the open forecourt ground of every downtown block plot (see
##     forecourt_beds(), called by blocks.gd) as lawn beds edged with shrubs.
## Everything is MultiMesh per 400 m cell with a visibility range (shrubs
## 200 m via NearField.emit_shrubs, palms 520 m), no new collision except a
## slim palm trunk.

const Roads := preload("res://src/world/downtown/roads.gd")
const Bridges := preload("res://src/world/downtown/bridges.gd")
const Realm := preload("res://src/world/downtown/landmarks/realm.gd")
const CELL := 400.0
const STRIP_IN := 0.22      # strip starts this far behind the kerb face
const STRIP_W := 0.75
const SHRUB_KINDS := ["mondo", "ixora", "croton", "fern"]

static var shrubs := {}      # kind -> Array of [Transform3D, Color]
static var palms: Array = []  # Transform3D
static var stats := {}

static func reset() -> void:
	shrubs = {}
	palms = []
	stats = {"strip_clumps": 0, "palms": 0, "median_clumps": 0, "forecourt_beds": 0, "species": 0}

static func off() -> bool:
	return "--planting-off" in OS.get_cmdline_user_args()

## Rotated / scaled clump transform (bottom on y).
static func _clump(kind: String, p: Vector3, s: float, rng: RandomNumberGenerator, ys: float = 1.0) -> void:
	if not shrubs.has(kind):
		shrubs[kind] = []
	var b := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(s * rng.randf_range(0.85, 1.2), s * ys * rng.randf_range(0.8, 1.15), s * rng.randf_range(0.85, 1.2)))
	var tint := Color(rng.randf_range(0.88, 1.08), rng.randf_range(0.9, 1.08), rng.randf_range(0.86, 1.04), 1.0)
	(shrubs[kind] as Array).append([Transform3D(b, p), tint])

## A palm in a tree pit (or median); slim trunk collision only.
static func palm(m, p: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.85, 1.25)
	palms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(s, s * rng.randf_range(0.92, 1.15), s)), p))
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.22 * s
	cyl.height = 3.0
	shape.shape = cyl
	shape.position = p + Vector3(0, 1.5, 0)
	m.body.add_child(shape)
	m.shapes += 1
	stats["palms"] = int(stats.get("palms", 0)) + 1

## Tree-pit species: palms where the pit's hash says so (about 40 %), and
## never more than two pits of the same species in a row along one kerb.
static func pit_is_palm(key: String, i: int, side: float, last: Array) -> bool:
	var h := absi(hash("%s|%d|%d" % [key, i, int(side)])) % 100
	var want := h < 40
	if last.size() >= 2 and last[last.size() - 1] == want and last[last.size() - 2] == want:
		want = not want
	last.append(want)
	return want

static func _strip_ok(p: Vector3, key: String) -> bool:
	if Roads.on_legacy_road(p.x, p.z, 4.0) or Roads.in_water(p.x, p.z) or Bridges.on_deck(p.x, p.z, 2.0) or Bridges.height_at(p.x, p.z) > 0.02:
		return false
	if Roads.on_road(p.x, p.z, key, 4.0):
		return false
	for hk: String in DowntownPlan.HELIPADS:
		var hp: Vector3 = DowntownPlan.HELIPADS[hk]["pos"]
		if Vector2(hp.x - p.x, hp.z - p.z).length() < float(DowntownPlan.HELIPADS[hk]["radius"]) + 8.0:
			return false
	return true

## Kerbside strip along every downtown road footway.
static func kerb_strips(m) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51023
	var shelters := _shelter_spots()
	for key: String in DowntownPlan.ROADS:
		var road: Dictionary = DowntownPlan.ROADS[key]
		var hw := Roads.half_width(key)
		var arterial := String(road["kind"]) == "arterial"
		for side: float in [-1.0, 1.0]:
			var run_kind: String = SHRUB_KINDS[rng.randi() % SHRUB_KINDS.size()]
			var run_left := 0
			for s: Array in Roads.samples(road["pts"], 1.15):
				var c: Vector3 = s[0]
				var f: Vector3 = s[1]
				var l := Roads.left_of(f)
				var off := hw + STRIP_IN + rng.randf_range(0.05, STRIP_W - 0.1)
				var p := c + l * side * off
				if not _strip_ok(p, key):
					continue
				var near_shelter := false
				for q: Vector3 in shelters:
					if Vector2(q.x - p.x, q.z - p.z).length() < 6.5:
						near_shelter = true
						break
				if near_shelter:
					continue
				# continuous ground cover, with drifts of a feature species
				_clump("mondo", Vector3(p.x, Roads.FOOT_TOP - 0.02, p.z), rng.randf_range(0.6, 0.85), rng, 0.55)
				stats["strip_clumps"] = int(stats.get("strip_clumps", 0)) + 1
				if run_left <= 0:
					run_kind = SHRUB_KINDS[1 + rng.randi() % 3]
					run_left = rng.randi_range(3, 9)
				run_left -= 1
				if rng.randf() < (0.62 if arterial else 0.45):
					var sz := rng.randf_range(0.7, 1.15) if run_kind != "fern" else rng.randf_range(0.85, 1.3)
					var q2 := c + l * side * (hw + STRIP_IN + rng.randf_range(0.2, STRIP_W - 0.2)) + f * rng.randf_range(-0.4, 0.4)
					_clump(run_kind, Vector3(q2.x, Roads.FOOT_TOP - 0.02, q2.z), sz, rng)
					stats["strip_clumps"] = int(stats.get("strip_clumps", 0)) + 1

## Plan S-1 corner plaza (Raffles Avenue / Bayfront Avenue North): a low
## garden on the strip the Marina Centre plot gave up, kept below eye level
## within 14 m of the kerb return so the turn keeps its sightline.
const CORNER_GARDENS := [Rect2(-776.0, -764.0, 10.0, 91.0)]
## Raffles Avenue frontage gardens on the landmark decks (y = deck top): the
## Esplanade's west plaza (clear of the domes' foyer rings from x -749) and
## the Flyer site's Raffles Avenue edge. Both read as bare paving from the
## drive before.
const DECK_GARDENS := [[Rect2(-771.0, -618.0, 15.0, 232.0), 0.36], [Rect2(-772.0, -985.0, 9.0, 172.0), 0.36]]
## Groves on the open parts of the Flyer site (the terminal, boarding deck and
## entrance plaza stay clear: they lie within ~75 m of the wheel at
## (-650, -880)); the site read as one bare paved field from the air.
const DECK_GROVES := [[Rect2(-578.0, -988.0, 72.0, 180.0), 0.36], [Rect2(-758.0, -988.0, 60.0, 34.0), 0.36]]
static func groves(m) -> void:
	if not ResourceLoader.exists("res://src/world/downtown/landmarks.gd"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 9133
	for e: Array in DECK_GROVES:
		var r: Rect2 = e[0]
		var y: float = float(e[1]) + 0.02
		m.quad_up("turf", Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y))
		m.box("granite_coping", Vector3(r.get_center().x, y - 0.06, r.get_center().y), Vector3(r.size.x + 0.4, 0.12, r.size.y + 0.4))
		# loose clusters of rain trees and palms over shrub drifts
		var n := int(r.get_area() / 260.0)
		for i in n:
			var c := Vector3(rng.randf_range(r.position.x + 4.0, r.end.x - 4.0), y, rng.randf_range(r.position.y + 4.0, r.end.y - 4.0))
			if rng.randf() < 0.35:
				palm(m, c, rng)
			else:
				m.tree(c, rng.randf_range(0.8, 1.3), rng)
			for k in 5:
				var q := c + Vector3(rng.randf_range(-3.5, 3.5), 0.0, rng.randf_range(-3.5, 3.5))
				if r.grow(-0.8).has_point(Vector2(q.x, q.z)):
					_clump(["ixora", "croton", "fern", "mondo"][rng.randi() % 4], q, rng.randf_range(0.8, 1.3), rng)
static func corner_gardens(m) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417
	var gardens: Array = []
	for r0: Rect2 in CORNER_GARDENS:
		gardens.append([r0, 0.12, false])
	if ResourceLoader.exists("res://src/world/downtown/landmarks.gd"):
		for e: Array in DECK_GARDENS:
			gardens.append([e[0], float(e[1]) + 0.02, true])
	for g: Array in gardens:
		var r: Rect2 = g[0]
		var y: float = g[1]
		var deck: bool = g[2]
		m.quad_up("turf", Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y))
		m.box("granite_coping", Vector3(r.get_center().x, y - 0.06, r.get_center().y), Vector3(r.size.x + 0.4, 0.12, r.size.y + 0.4))
		var z := r.position.y + 1.0
		while z < r.end.y - 1.0:
			for k in 3:
				var p := Vector3(rng.randf_range(r.position.x + 0.8, r.end.x - 0.8), y, z + rng.randf_range(-0.6, 0.6))
				var near_corner := z < r.position.y + 14.0
				var kind: String = ["mondo", "ixora", "croton", "fern"][rng.randi() % (2 if near_corner else 4)]
				_clump(kind, p, rng.randf_range(0.8, 1.25), rng)
			z += 1.3
		var t := r.position.y + (6.0 if deck else 20.0)
		while t < r.end.y - 6.0:
			var q := Vector3(r.get_center().x + rng.randf_range(-1.5, 1.5) * (2.0 if deck and r.size.x > 12.0 else 1.0), y, t)
			if rng.randf() < 0.45:
				palm(m, q, rng)
				if deck and r.size.x > 12.0:
					palm(m, q + Vector3(rng.randf_range(2.5, 4.0) * (1.0 if q.x < r.get_center().x else -1.0), 0.0, rng.randf_range(-2.0, 2.0)), rng)
			else:
				m.tree(q, rng.randf_range(0.75, 1.1), rng)
			t += rng.randf_range(10.0, 16.0)

static func _shelter_spots() -> Array:
	var out: Array = []
	for key: String in ["bayfront_avenue", "bayfront_avenue_north", "esplanade_drive", "collyer_quay", "marina_way", "anson_road"]:
		var pts: Array = DowntownPlan.ROADS[key]["pts"]
		var hw := Roads.half_width(key)
		var n2 := 0
		for s: Array in Roads.samples(pts, 90.0):
			var q: Vector3 = s[0]
			n2 += 1
			if n2 % 2 == 0:
				continue
			out.append(Vector3(q.x, 0.0, q.z - hw - Roads.FOOTWAY * 0.5 - 0.2))
	return out

## Median under-planting: shrubs along the median bed, palms between the rain
## trees (the median trees are placed every 27 m by roads._median).
static func median(m, key: String, pts: Array, width: float, rng: RandomNumberGenerator) -> void:
	var skip := func(p: Vector3) -> bool:
		return Roads.on_road(p.x, p.z, key, 6.0) or Roads.in_water(p.x, p.z) or Bridges.on_deck(p.x, p.z, 4.0) or Bridges.height_at(p.x, p.z) > 0.05
	var k := 0
	for s: Array in Roads.samples(pts, 1.6):
		var p: Vector3 = s[0]
		var f: Vector3 = s[1]
		var l := Roads.left_of(f)
		k += 1
		if skip.call(p):
			continue
		for sd: float in [-1.0, 1.0]:
			if rng.randf() < 0.75:
				var q := p + l * sd * rng.randf_range(0.15, width * 0.5 - 0.55)
				var kind: String = ["ixora", "croton", "mondo", "fern", "ixora"][rng.randi() % 5]
				_clump(kind, Vector3(q.x, 0.28, q.z), rng.randf_range(0.75, 1.2), rng)
				stats["median_clumps"] = int(stats.get("median_clumps", 0)) + 1
		# a palm halfway between the 27 m rain trees, skipping some
		if k % 17 == 8 and rng.randf() < 0.8:
			palm(m, Vector3(p.x, 0.3, p.z), rng)

## Forecourt beds on a block plot: lawn with a shrub edge on every open patch
## of the plot (8 m grid) that is clear of buildings (`footprints` grown by
## 4 m), of the road-facing frontage band and of the plot edge. Returns the
## bed rects (the caller draws the turf in its own batch).
static func forecourt_beds(r: Rect2, footprints: Array, road_sides: Array, rng: RandomNumberGenerator) -> Array:
	var beds: Array = []
	var cell := 9.0
	var frontage := 9.0
	var nx := int(r.size.x / cell)
	var nz := int(r.size.y / cell)
	for ix in nx:
		for iz in nz:
			var c := Rect2(r.position.x + ix * cell + (r.size.x - nx * cell) * 0.5, r.position.y + iz * cell + (r.size.y - nz * cell) * 0.5, cell, cell)
			var ok := r.grow(-3.0).encloses(c)
			for s: Vector2 in road_sides:
				var band: Rect2
				if s.x < 0.0: band = Rect2(r.position.x, r.position.y, frontage, r.size.y)
				elif s.x > 0.0: band = Rect2(r.end.x - frontage, r.position.y, frontage, r.size.y)
				elif s.y < 0.0: band = Rect2(r.position.x, r.position.y, r.size.x, frontage)
				else: band = Rect2(r.position.x, r.end.y - frontage, r.size.x, frontage)
				if band.intersects(c):
					ok = false
			if not ok:
				continue
			for fp: Rect2 in footprints:
				if fp.grow(4.0).intersects(c):
					ok = false
					break
			if ok:
				beds.append(c.grow(-0.6))
	stats["forecourt_beds"] = int(stats.get("forecourt_beds", 0)) + beds.size()
	# shrub edging and specimen palms on each bed
	for b: Rect2 in beds:
		var per := int((b.size.x + b.size.y) * 2.0 / 1.4)
		for i in per:
			var t := float(i) / per
			var q: Vector2
			var L := (b.size.x + b.size.y) * 2.0
			var d := t * L
			if d < b.size.x: q = Vector2(b.position.x + d, b.position.y)
			elif d < b.size.x + b.size.y: q = Vector2(b.end.x, b.position.y + d - b.size.x)
			elif d < b.size.x * 2.0 + b.size.y: q = Vector2(b.end.x - (d - b.size.x - b.size.y), b.end.y)
			else: q = Vector2(b.position.x, b.end.y - (d - b.size.x * 2.0 - b.size.y))
			q += (b.get_center() - q).normalized() * 0.5
			var kind: String = ["ixora", "croton", "ixora", "fern"][(i / 4 + int(b.position.x)) % 4]
			_clump(kind, Vector3(q.x, 0.24, q.y), rng.randf_range(0.8, 1.15), rng)
		if rng.randf() < 0.55:
			var pc := b.get_center() + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
			var s := rng.randf_range(0.9, 1.3)
			palms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(s, s, s)), Vector3(pc.x, 0.24, pc.y)))
	return beds

## Emit everything collected (call once after map, landmarks and blocks).
static func flush(root: Node3D) -> void:
	if not shrubs.is_empty():
		NearField.emit_shrubs(root, shrubs)
	var by_cell := {}
	for xf: Transform3D in palms:
		var c := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
		if not by_cell.has(c):
			by_cell[c] = []
		(by_cell[c] as Array).append(xf)
	for c in by_cell:
		Realm.glb_multimesh(root, "DowntownPalms_%d_%d" % [c.x, c.y], "palm.glb", by_cell[c], true, 520.0)
	var n := 0
	for k in shrubs:
		n += 1
	stats["species"] = n + (1 if not palms.is_empty() else 0) + 1   # + rain trees
	stats["shrub_kinds"] = shrubs.keys()
	print("[downtown-planting] %s" % str(stats))
	shrubs = {}
	palms = []
