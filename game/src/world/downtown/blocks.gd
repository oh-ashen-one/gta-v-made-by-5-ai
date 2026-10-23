extends RefCounted
## downtown-blocks piece (wave M, loop/DOWNTOWN_PLAN.md section 8). Original work.
##
## Builds every DowntownPlan.BLOCKS plot that is not a landmark site or a
## park: the Raffles Place / Cecil Street CBD towers and the Raffles Place
## plaza, the Boat Quay shophouse row on the river, the Shenton Way strip,
## the Marina Bay Financial Centre and Marina South towers, the civic north
## bank, Marina Centre malls and hotels and the Bayfront expo halls.
##
## Every building is a full collidable shell (one shared facade shader with
## interior-mapped glazing, see dt_facade.gdshader) with real street
## frontage: lobbies and shopfronts in the ground band, covered linkways and
## canopies, porte-cocheres with name monoliths, shop signs, bus stops,
## planters and trees. Neighbouring buildings never share a silhouette and
## cladding. Shells are one mesh per block; frontage detail is one batched
## mesh per block (visibility range 260 m); collision is one StaticBody3D
## with box shapes inside the plan's 600-box budget.

const MeshKit := preload("res://src/world/downtown/block_kits/mesh_kit.gd")
const Batch := preload("res://src/world/downtown/block_kits/batch.gd")
const BuildingKit := preload("res://src/world/downtown/block_kits/building_kit.gd")
const FrontageKit := preload("res://src/world/downtown/block_kits/frontage_kit.gd")
const BoatQuayKit := preload("res://src/world/downtown/block_kits/boat_quay_kit.gd")
const BlockLooks := preload("res://src/world/downtown/block_looks.gd")

const GY := 0.16                 # building ground floor (district platform height)
const SKIP_KINDS := ["landmark_site", "park"]
const LEGACY_FLYER := Vector3(210.0, 0.0, -700.0)

const TOWER_NAMES := ["CHULIA EXCHANGE", "ONE CECIL PLACE", "STRAITS TRADING TOWER", "RAFFLES QUAY CENTRE", "LION CITY BANK",
	"MARINA ONE CENTRAL", "OCEAN FINANCIAL HOUSE", "TELOK AYER TOWER", "COLLYER POINT", "BAYFRONT LINK", "SHENTON HOUSE",
	"ANSON CENTRE", "ROBINSON 77", "CAPITAL SQUARE", "HARBOUR VIEW TOWER", "MAXWELL CHAMBERS", "PRINCE EDWARD PLACE",
	"KEPPEL BAY TOWER", "ESPLANADE COURT", "MARINA SQUARE", "BAYSHORE HOTEL", "PROMENADE SUITES"]
const SHOP_NAMES := ["KOPI & TOAST", "STRAITS PHARMACY", "BAYSIDE BAKERY", "7-DAY MART", "LAKSA HOUSE", "MONEY CHANGER",
	"CITY OPTICAL", "NOODLE BAR", "BOOKS KINOKUNI", "DIM SUM HOUSE", "FLOWER STALL", "SUSHI EXPRESS", "BANK ATM", "GYM 24/7",
	"BUBBLE TEA", "TAILOR & CO", "CHICKEN RICE", "PHONE REPAIR", "WINE CELLAR", "SALAD STOP"]
const BUS_STOPS := ["Raffles Pl Stn Exit A", "Opp One Cecil", "Shenton Way Ter", "Marina Blvd / MBFC", "Bef Anson Rd", "Marina Sq"]

var looks: BlockLooks
var root: Node3D
var labels: Node3D
var stats := {"buildings": 0, "blocks": 0, "towers": 0, "boxes": 0, "linkway_m": 0.0, "entrances": 0, "signs": 0, "bus_stops": 0,
	"trees": 0, "sequence": [], "footprint_violations": 0, "built_rects": [], "legacy_removed": 0}
var _tree_xf: Array = []
var _prev_style := -1
var _prev_cid := -1
var _prev2_style := -1
var _name_i := 0
var _shop_i := 0
var _bus_i := 0
var _boxes: Array = []

# ------------------------------------------------------------ plan queries
static func is_mine(block_name: String) -> bool:
	var b: Dictionary = DowntownPlan.BLOCKS[block_name]
	return not b.has("owner") and not (String(b["kind"]) in SKIP_KINDS)

static func my_blocks() -> Array:
	var out := []
	var names := DowntownPlan.BLOCKS.keys()
	names.sort()
	for n in names:
		if is_mine(n):
			out.append(n)
	return out

## Outward normals of the rect sides that face a road (plan roads plus the
## legacy district grid lines), nearest first.
static func road_sides(r: Rect2) -> Array:
	var sides := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
	var out := []
	var dists := []
	for s in sides:
		var best := INF
		for t in [0.2, 0.5, 0.8]:
			var p: Vector2
			if s.x != 0.0:
				p = Vector2(r.position.x if s.x < 0.0 else r.end.x, r.position.y + r.size.y * t)
			else:
				p = Vector2(r.position.x + r.size.x * t, r.position.y if s.y < 0.0 else r.end.y)
			p += s * 6.0
			best = minf(best, _road_dist(p))
		if best < 14.0:
			out.append(s)
			dists.append(best)
	# nearest first
	for i in out.size():
		for j in range(i + 1, out.size()):
			if float(dists[j]) < float(dists[i]):
				var a = out[i]; out[i] = out[j]; out[j] = a
				var d = dists[i]; dists[i] = dists[j]; dists[j] = d
	return out

static func _road_dist(p: Vector2) -> float:
	var best := INF
	for key in DowntownPlan.ROADS:
		var pts: Array = DowntownPlan.ROADS[key]["pts"]
		var hw := float(DowntownPlan.ROADS[key]["width"]) * 0.5
		for i in pts.size() - 1:
			var a := Vector2((pts[i] as Vector3).x, (pts[i] as Vector3).z)
			var b := Vector2((pts[i + 1] as Vector3).x, (pts[i + 1] as Vector3).z)
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) - hw)
	for x in DowntownPlan.LEGACY["x_lines"]:
		if p.y > -380.0 and p.y < 380.0:
			best = minf(best, absf(p.x - float(x)) - 8.0)
	for z in DowntownPlan.LEGACY["z_lines"]:
		if p.x > -380.0 and p.x < 380.0:
			best = minf(best, absf(p.y - float(z)) - 8.0)
	return best

# ------------------------------------------------------------ hooks
func skyline_clear(_world: WorldBuilder, city: SkylineCity) -> void:
	for n in my_blocks():
		city.clear_zone((DowntownPlan.BLOCKS[n]["rect"] as Rect2).grow(10.0), 0.0)

func build(world: WorldBuilder, parent: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	looks = BlockLooks.new()
	root = Node3D.new()
	root.name = "DowntownBlocks"
	parent.add_child(root)
	labels = Node3D.new()
	labels.name = "DowntownBlockSigns"
	root.add_child(labels)
	_remove_legacy_towers(parent)
	var landmarks_present := ResourceLoader.exists("res://src/world/downtown/landmarks.gd")
	for n in my_blocks():
		var b: Dictionary = DowntownPlan.BLOCKS[n]
		var r: Rect2 = b["rect"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(n) ^ 0x5eed
		var k := MeshKit.new()
		k.begin()
		var det := Batch.new()
		var kind := String(b["kind"])
		var max_h := float(b["max_h"])
		_plot(det, r, kind)
		match kind:
			"boat_quay_row":
				BoatQuayKit.build(k, det, labels, looks, rng, r, GY, stats)
			"plaza":
				_plaza(det, k, r, rng)
			"civic":
				_civic(n, det, k, r, rng, max_h)
			"podium":
				_expo(det, k, r, rng, max_h, landmarks_present)
			"marina_centre":
				_lots(n, det, k, r, rng, kind, max_h, 95.0)
			"mbfc_tower":
				_lots(n, det, k, r, rng, kind, max_h, 200.0)
			"residential":
				_lots(n, det, k, r, rng, kind, max_h, 62.0)
			"mid_rise":
				_lots(n, det, k, r, rng, kind, max_h, 64.0)
			_:
				_lots(n, det, k, r, rng, kind, max_h, 72.0)
		var shell := k.commit()
		if shell != null:
			var mi := MeshInstance3D.new()
			mi.name = "Shell_" + n
			mi.mesh = shell
			mi.material_override = looks.facade
			mi.set_meta("downtown_blocks", true)
			root.add_child(mi)
		det.commit(root, "Frontage_" + n, looks.mats, 320.0 if kind != "boat_quay_row" else 700.0, kind == "boat_quay_row" or kind == "plaza")
		for fp in k.footprints:
			if not r.grow(0.6).encloses(fp):
				stats["footprint_violations"] += 1
		_boxes.append_array(k.boxes)
		stats["blocks"] += 1
		(stats["built_rects"] as Array).append(r)
	# forecourt / plaza trees (one MultiMesh per tree surface)
	if not _tree_xf.is_empty():
		world._batch_background("res://assets/authored/rain_tree.glb", _tree_xf)
		stats["trees"] = _tree_xf.size()
	_collision()
	root.set_meta("blocks_stats", stats)
	print("[downtown-blocks] built %d blocks, %d buildings (%d towers), %d collision boxes, %d trees, %.0f m linkway in %d ms" % [
		stats["blocks"], stats["buildings"], stats["towers"], stats["boxes"], stats["trees"], stats["linkway_m"], Time.get_ticks_msec() - t0])

func finish(world: WorldBuilder) -> void:
	if "--blocks-photos" in OS.get_cmdline_user_args():
		var cap: Node = load("res://src/world/downtown/blocks_capture.gd").new()
		cap.name = "BlocksCapture"
		world.add_child(cap)

# ------------------------------------------------------------ helpers
## The authored near-shore skyline GLBs (legacy _background_city side row at
## x 440..530) stand inside the Shenton / MBFC blocks this piece now builds.
func _remove_legacy_towers(parent: Node3D) -> void:
	var rects: Array[Rect2] = []
	for n in my_blocks():
		rects.append((DowntownPlan.BLOCKS[n]["rect"] as Rect2).grow(25.0))
	for child in parent.get_children():
		if not child is Node3D:
			continue
		var src := String(child.scene_file_path)
		if not src.contains("/skyline_"):
			continue
		var p := (child as Node3D).position
		for r in rects:
			if r.has_point(Vector2(p.x, p.z)):
				child.queue_free()
				parent.remove_child(child)
				stats["legacy_removed"] += 1
				break

func _collision() -> void:
	var body := StaticBody3D.new()
	body.name = "DowntownBlocksCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for bx in _boxes:
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bx[0]
		shape.shape = bs
		shape.position = bx[1]
		body.add_child(shape)
	stats["boxes"] = _boxes.size()

## Forecourt paving slab across the whole plot (top at GY + 0.04).
func _plot(det: Batch, r: Rect2, kind: String) -> void:
	var key := "paving" if kind != "civic" else "paving_dark"
	det.box_at(key, Vector3(r.size.x, 1.4, r.size.y), Vector3(r.get_center().x, GY + 0.04 - 0.7, r.get_center().y))
	_boxes.append([Vector3(r.size.x, 1.4, r.size.y), Vector3(r.get_center().x, GY + 0.04 - 0.7, r.get_center().y)])
	# granite kerb edge
	for s in [-1.0, 1.0]:
		det.box_at("granite_light", Vector3(r.size.x, 0.22, 0.3), Vector3(r.get_center().x, GY - 0.05, r.get_center().y + s * (r.size.y * 0.5 - 0.15)))
		det.box_at("granite_light", Vector3(0.3, 0.22, r.size.y), Vector3(r.get_center().x + s * (r.size.x * 0.5 - 0.15), GY - 0.05, r.get_center().y))

## Pick a (style, cladding) that differs from the previous building.
func _pick(rng: RandomNumberGenerator, styles: Array, clads: Array) -> Vector2i:
	var s: int = styles[rng.randi() % styles.size()]
	var g := 0
	while (s == _prev_style or s == _prev2_style) and g < 12 and styles.size() > 2:
		s = styles[rng.randi() % styles.size()]
		g += 1
	var c: int = clads[rng.randi() % clads.size()]
	g = 0
	while c == _prev_cid and g < 12 and clads.size() > 1:
		c = clads[rng.randi() % clads.size()]
		g += 1
	_prev2_style = _prev_style
	_prev_style = s
	_prev_cid = c
	return Vector2i(s, c)

## Split a block along its long axis into lots of ~lot_len and build one
## building per lot with frontage on the road sides.
func _lots(block_name: String, det: Batch, k: MeshKit, r: Rect2, rng: RandomNumberGenerator, kind: String, max_h: float, lot_len: float) -> void:
	var long_x := r.size.x >= r.size.y
	var L := r.size.x if long_x else r.size.y
	var n := maxi(1, int(round(L / lot_len)))
	var sides := road_sides(r)
	var podium_block := kind in ["mbfc_tower", "marina_centre"] or (kind == "cbd_tower" and rng.randf() < 0.5) or (kind == "mid_rise" and rng.randf() < 0.35)
	var tallest := rng.randi() % n
	for i in n:
		var lot: Rect2
		if long_x:
			lot = Rect2(r.position.x + L * float(i) / n, r.position.y, L / n, r.size.y)
		else:
			lot = Rect2(r.position.x, r.position.y + L * float(i) / n, r.size.x, L / n)
		# internal lot boundaries get a 4 m service gap / through-block link
		var g := 2.0
		if long_x:
			lot = Rect2(lot.position.x + (g if i > 0 else 0.0), lot.position.y, lot.size.x - (g if i > 0 else 0.0) - (g if i < n - 1 else 0.0), lot.size.y)
		else:
			lot = Rect2(lot.position.x, lot.position.y + (g if i > 0 else 0.0), lot.size.x, lot.size.y - (g if i > 0 else 0.0) - (g if i < n - 1 else 0.0))
		var h := max_h * (rng.randf_range(0.86, 1.0) if i == tallest else rng.randf_range(0.5, 0.82))
		if kind == "mid_rise":
			h = max_h * rng.randf_range(0.55, 1.0)
		elif kind == "residential":
			h = max_h * rng.randf_range(0.72, 1.0)
		_building(block_name, det, k, lot, rng, kind, h, sides, podium_block, i == 0)

func _inset(r: Rect2, sides: Array, road_m: float, other_m: float) -> Rect2:
	var l := other_m; var rr := other_m; var t := other_m; var b := other_m
	for s in sides:
		if s.x < 0.0: l = road_m
		elif s.x > 0.0: rr = road_m
		elif s.y < 0.0: t = road_m
		else: b = road_m
	return Rect2(r.position.x + l, r.position.y + t, r.size.x - l - rr, r.size.y - t - b)

static func _side_seg(r: Rect2, s: Vector2) -> Array:
	if s.x < 0.0: return [Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y)]
	if s.x > 0.0: return [Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y)]
	if s.y < 0.0: return [Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.position.y)]
	return [Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y)]

func _building(block_name: String, det: Batch, k: MeshKit, lot: Rect2, rng: RandomNumberGenerator, kind: String, h: float, sides: Array, podium: bool, first: bool) -> void:
	var lot_sides := []
	for s in sides:
		lot_sides.append(s)
	var styles := [0, 1, 2, 3, 4, 5, 6, 7]
	var clads := [0, 1, 2, 3, 7, 4, 5]
	match kind:
		"mbfc_tower":
			clads = [5, 0, 2, 3]
			styles = [1, 3, 6, 0, 7]
		"residential":
			clads = [6]
			styles = [0, 3, 5, 6]
		"marina_centre":
			clads = [4, 2, 0, 1, 7]
			styles = [0, 3, 5, 7, 1]
		"mid_rise":
			clads = [1, 4, 2, 7, 3, 0]
			styles = [0, 1, 5, 7, 4]
	var pick := _pick(rng, styles, clads)
	var cid2: int = clads[(clads.find(pick.y) + 1) % clads.size()]
	if cid2 == pick.y:
		cid2 = [2, 0, 1, 7][rng.randi() % 4]
	var base_y := GY
	var lobby := 7.5
	var foot: Rect2
	var podium_top := GY
	if podium:
		var pr := _inset(lot, lot_sides, 3.5, 1.5)
		var ph := rng.randf_range(12.0, 22.0) if kind != "marina_centre" else rng.randf_range(22.0, 30.0)
		var pc: int = [1, 7, 2, 4][rng.randi() % 4]
		if pc == pick.y:
			pc = 1 if pick.y != 1 else 7
		podium_top = BuildingKit.podium(k, det, rng, pr, ph, pc, GY, 6.2)
		base_y = podium_top
		foot = _inset(pr, lot_sides, 4.0, 3.0)
		# canopies along the podium's road faces + shop signs above them
		for s in lot_sides:
			var seg := _side_seg(pr, s)
			FrontageKit.linkway(det, seg[0], seg[1], s, GY, true, 3.0, 4.2)
			stats["linkway_m"] += (seg[0] as Vector2).distance_to(seg[1])
			_shop_i = FrontageKit.shop_signs(det, labels, seg[0], seg[1], s, GY, 5.2, SHOP_NAMES, rng, _shop_i)
			stats["signs"] = _shop_i
	else:
		foot = _inset(lot, lot_sides, 10.0, 4.0)
		# free-standing covered linkway along every road edge of the lot
		for s in lot_sides:
			var seg2 := _side_seg(_inset(lot, lot_sides, 0.8, 0.0), s)
			var a: Vector2 = seg2[0]
			var b: Vector2 = seg2[1]
			# leave a gap mid-way for the forecourt entrance
			var mid := (a + b) * 0.5
			var dirv := (b - a).normalized()
			FrontageKit.linkway(det, a, mid - dirv * 9.0, -s, GY, false, 3.2, 3.6)
			FrontageKit.linkway(det, mid + dirv * 9.0, b, -s, GY, false, 3.2, 3.6)
			stats["linkway_m"] += a.distance_to(b) - 18.0
			# planters with trees between linkway and building
			var L := a.distance_to(b)
			var nt := int(L / 14.0)
			for t in nt:
				var q: Vector2 = a + dirv * (L * (float(t) + 0.5) / float(nt)) - s * 6.4
				if q.distance_to(mid - s * 6.4) < 10.0:
					continue
				_tree_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.75, 0.95)), FrontageKit.planter_tree(det, q, GY)))
	# tower footprint: real CBD towers are ~32-58 m across
	var max_dim := 56.0 if kind != "residential" else 34.0
	var w := minf(foot.size.x, max_dim)
	var d := minf(foot.size.y, max_dim)
	if kind == "residential":
		w = minf(foot.size.x, 30.0); d = minf(foot.size.y, 30.0)
	var c := foot.get_center()
	# pull the tower toward the main road so the forecourt is not dead space
	if not lot_sides.is_empty() and not podium:
		var s0: Vector2 = lot_sides[0]
		c += s0 * maxf(0.0, ((foot.size.x - w) if s0.x != 0.0 else (foot.size.y - d)) * 0.5 - 2.0)
	if w < 12.0 or d < 12.0:
		return
	# Residential: two slender towers when the lot allows
	var shells := [[c, w, d, h]]
	if kind == "residential" and foot.size.x > 70.0:
		shells = [[c - Vector2(foot.size.x * 0.25, 0), w, d, h], [c + Vector2(foot.size.x * 0.25, 0), w, d, h * 0.86]]
	elif kind == "residential" and foot.size.y > 70.0:
		shells = [[c - Vector2(0, foot.size.y * 0.25), w, d, h], [c + Vector2(0, foot.size.y * 0.25), w, d, h * 0.86]]
	var si := 0
	for sh in shells:
		# a second tower on the same lot is a different model (silhouette)
		var st: int = pick.x if si == 0 else int(styles[(styles.find(pick.x) + 1) % styles.size()])
		var res := BuildingKit.tower(k, det, rng, sh[0], sh[1], sh[2], sh[3], st, pick.y, cid2, GY, base_y, lobby)
		si += 1
		if si > 1:
			_prev2_style = _prev_style
			_prev_style = st
		stats["buildings"] += 1
		if float(sh[3]) > 100.0:
			stats["towers"] += 1
		(stats["sequence"] as Array).append({"block": block_name, "style": int(res["style"]), "cid": int(res["cid"]), "h": float(sh[3])})
	# main entrance on the nearest road side
	if not lot_sides.is_empty():
		var s1: Vector2 = lot_sides[0]
		var face := c + s1 * ((w if s1.x != 0.0 else d) * 0.5)
		if podium:
			var pr2 := _inset(lot, lot_sides, 3.5, 1.5)
			face = pr2.get_center() + s1 * ((pr2.size.x if s1.x != 0.0 else pr2.size.y) * 0.5)
		FrontageKit.entrance(det, labels, face, s1, GY, TOWER_NAMES[_name_i % TOWER_NAMES.size()], rng)
		_name_i += 1
		stats["entrances"] += 1
		# a bus stop on the kerb of every third building's main road
		if _bus_i < 18 and (stats["entrances"] % 3 == 1):
			var along := Vector2(-s1.y, s1.x)
			var edge := (lot.get_center() + s1 * ((lot.size.x if s1.x != 0.0 else lot.size.y) * 0.5 + 1.8)) + along * 18.0
			FrontageKit.bus_stop(det, labels, edge, s1, GY, BUS_STOPS[_bus_i % BUS_STOPS.size()])
			_bus_i += 1
			stats["bus_stops"] = _bus_i

# ------------------------------------------------------------ special blocks
## Raffles Place: paved plaza ringed by towers, central lawn, rain trees,
## MRT entrance pavilions, benches, a bronze sculpture.
func _plaza(det: Batch, k: MeshKit, r: Rect2, rng: RandomNumberGenerator) -> void:
	var c := r.get_center()
	det.box_at("paving_dark", Vector3(r.size.x - 8.0, 0.06, r.size.y - 8.0), Vector3(c.x, GY + 0.07, c.y))
	# lawn oval approximated by stacked rounded boxes
	det.box_at("planter", Vector3(34.0, 0.45, 62.0), Vector3(c.x, GY + 0.22, c.y + 6.0))
	det.box_at("shrub_light", Vector3(33.0, 0.12, 61.0), Vector3(c.x, GY + 0.48, c.y + 6.0))
	# ring of rain trees in tree grates
	for i in 12:
		var a := TAU * float(i) / 12.0
		var q := c + Vector2(cos(a) * 30.0, sin(a) * 52.0)
		_tree_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.85, 1.05)), FrontageKit.planter_tree(det, q, GY)))
	# MRT entrance pavilions (glass canopy over a stair down, red roundel)
	for s in [-1.0, 1.0]:
		var p := c + Vector2(s * 26.0, -48.0 * s)
		det.box_at("granite", Vector3(9.0, 0.9, 5.0), Vector3(p.x, GY + 0.45, p.y))
		det.box_at("sign_dark", Vector3(6.6, 0.1, 3.6), Vector3(p.x, GY + 0.92, p.y))
		for cx in [-4.3, 4.3]:
			for cz in [-2.3, 2.3]:
				det.column("metal_light", 0.12, 3.6, Vector3(p.x + cx, GY, p.y + cz), 8)
		det.box_at("canopy_glass", Vector3(10.0, 0.12, 6.0), Vector3(p.x, GY + 3.7, p.y))
		det.box_at("metal_light", Vector3(10.2, 0.35, 0.2), Vector3(p.x, GY + 3.6, p.y + 3.0))
		det.box_at("metal_light", Vector3(10.2, 0.35, 0.2), Vector3(p.x, GY + 3.6, p.y - 3.0))
		det.column("metal_dark", 0.08, 3.4, Vector3(p.x + 5.6, GY, p.y), 6)
		det.column("mrt_red", 0.55, 0.12, Vector3(p.x + 5.6, GY + 3.2, p.y), 16)
		FrontageKit._label(labels, "MRT  Raffles Place", Vector3(p.x, GY + 3.6, p.y + 3.12), Vector2(0, 1), 56, 0.009, Color(0.95, 0.95, 0.95), true)
		k.boxes.append([Vector3(9.0, 0.9, 5.0), Vector3(p.x, GY + 0.45, p.y)])
	# benches around the lawn, bollards at the plaza edge
	for i in 10:
		var a2 := TAU * (float(i) + 0.5) / 10.0
		var q2 := c + Vector2(cos(a2) * 21.0, sin(a2) * 38.0) + Vector2(0, 6.0)
		det.box_at("granite_light", Vector3(2.4, 0.45, 0.7), Vector3(q2.x, GY + 0.22, q2.y), -a2)
	for i in 14:
		var bx := r.position.x + 4.0 + (r.size.x - 8.0) * float(i) / 13.0
		det.column("metal_dark", 0.11, 0.9, Vector3(bx, GY, r.position.y + 2.0), 8)
		det.column("metal_dark", 0.11, 0.9, Vector3(bx, GY, r.end.y - 2.0), 8)
	# bronze sculpture on a plinth (abstract, original)
	var sp := c + Vector2(0, -40.0)
	det.box_at("granite", Vector3(5.0, 0.8, 5.0), Vector3(sp.x, GY + 0.4, sp.y))
	det.box("bronze", Vector3(1.2, 6.0, 1.2), Transform3D(Basis(Vector3(0, 0, 1), 0.35).rotated(Vector3.UP, 0.6), Vector3(sp.x, GY + 3.6, sp.y)))
	det.box("bronze", Vector3(1.0, 4.4, 1.0), Transform3D(Basis(Vector3(0, 0, 1), -0.5).rotated(Vector3.UP, 1.9), Vector3(sp.x + 0.8, GY + 2.9, sp.y + 0.4)))
	k.boxes.append([Vector3(5.0, 0.8, 5.0), Vector3(sp.x, GY + 0.4, sp.y)])
	# stall kiosk + covered walkway across the plaza (Singapore linkway)
	FrontageKit.linkway(det, Vector2(r.position.x + 4.0, c.y - 12.0), Vector2(r.end.x - 4.0, c.y - 12.0), Vector2(0, 1), GY, false, 3.4, 3.6)
	stats["linkway_m"] += r.size.x - 8.0

## Civic blocks: the Padang green with colonial courts along its far side,
## or a riverside museum with low offices behind.
func _civic(block_name: String, det: Batch, k: MeshKit, r: Rect2, rng: RandomNumberGenerator, max_h: float) -> void:
	if block_name == "civic_padang":
		var strip := 62.0
		var field := Rect2(r.position.x + strip + 8.0, r.position.y + 10.0, r.size.x - strip - 18.0, r.size.y - 20.0)
		det.box_at("turf", Vector3(field.size.x, 0.1, field.size.y), Vector3(field.get_center().x, GY + 0.08, field.get_center().y))
		# white post-and-rail fence round the field
		for s in [-1.0, 1.0]:
			det.box_at("metal_white", Vector3(field.size.x, 0.08, 0.08), Vector3(field.get_center().x, GY + 0.9, field.get_center().y + s * field.size.y * 0.5))
			det.box_at("metal_white", Vector3(0.08, 0.08, field.size.y), Vector3(field.get_center().x + s * field.size.x * 0.5, GY + 0.9, field.get_center().y))
		var h1 := minf(max_h - 8.0, 26.0)
		BuildingKit.colonial(k, det, rng, Rect2(r.position.x + 4.0, r.position.y + 20.0, strip - 8.0, 130.0), h1, Vector2(1, 0), GY, true)
		BuildingKit.colonial(k, det, rng, Rect2(r.position.x + 4.0, r.position.y + 175.0, strip - 8.0, 140.0), h1 - 4.0, Vector2(1, 0), GY, false)
		stats["buildings"] += 2
		for i in 8:
			var q := Vector2(field.position.x - 4.0, field.position.y + field.size.y * (float(i) + 0.5) / 8.0)
			_tree_xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, GY, q.y)))
	else:
		# museum on the river frontage (+x), offices behind
		BuildingKit.colonial(k, det, rng, Rect2(r.end.x - 80.0, r.position.y + 14.0, 66.0, r.size.y - 28.0), minf(max_h - 10.0, 22.0), Vector2(1, 0), GY, false)
		stats["buildings"] += 1
		_lots(block_name, det, k, Rect2(r.position.x, r.position.y, r.size.x - 96.0, r.size.y), rng, "mid_rise", minf(max_h, 32.0), 64.0)

## Bayfront expo: long low convention halls with a glass front and a deep
## entrance canopy on Bayfront Avenue (-z).
func _expo(det: Batch, k: MeshKit, r: Rect2, rng: RandomNumberGenerator, max_h: float, landmarks_present: bool) -> void:
	var halls := 3
	var hw := (r.size.x - 8.0 * float(halls - 1)) / float(halls)
	for i in halls:
		var hr := Rect2(r.position.x + float(i) * (hw + 8.0), r.position.y + 6.0, hw, r.size.y - 10.0)
		# the legacy Flyer stands here until the landmarks piece moves it
		if not landmarks_present and hr.grow(20.0).has_point(Vector2(LEGACY_FLYER.x, LEGACY_FLYER.z)):
			continue
		var inf := BuildingKit.info(4 if i % 2 == 0 else 2, rng, max_h * 0.8, 9.0, GY)
		k.prism(MeshKit.chamfer(hr.get_center().x, hr.get_center().y, hr.size.x, hr.size.y, 3.0), GY - 1.0, GY + max_h * rng.randf_range(0.6, 0.8), inf)
		var front := Vector2(hr.get_center().x, hr.position.y)
		FrontageKit.linkway(det, Vector2(hr.end.x, hr.position.y), Vector2(hr.position.x, hr.position.y), Vector2(0, -1), GY, true, 5.0, 7.0)
		stats["linkway_m"] += hr.size.x
		FrontageKit.entrance(det, labels, front, Vector2(0, -1), GY, "BAYFRONT EXPO HALL %s" % ["A", "B", "C"][i], rng)
		stats["entrances"] += 1
		stats["buildings"] += 1
