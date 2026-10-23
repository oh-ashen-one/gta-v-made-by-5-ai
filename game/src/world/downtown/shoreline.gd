extends RefCounted
## downtown-map: ground, bay outline, seawalls, waterfront rails, plots and
## parks (DOWNTOWN_PLAN sections 4 and 8).
##
## Land = the map outline minus the WATER rects plus the ISLANDS. The outline
## is cut into a grid on every rect edge and merged back into strips, so every
## land rect gets one collision slab (top at 0, like the old district slab)
## and there are no cracks between the heritage district and the new land.
## Every land/water boundary inside the playable area gets a granite seawall
## face, a coping, a wet band, an algae line and a railing with collision.

## Built land extends past PLAYABLE under the background city carpet so the
## river and the Marina Channel stay open water out to the old map edge.
const OUTER := Rect2(-1000.0, -1320.0, 1900.0, 2120.0)
const RIVER_EXT := Rect2(-590.0, -349.0, 60.0, 1149.0)
const CHANNEL_EXT := Rect2(-470.0, -1320.0, 140.0, 660.0)
## The legacy near seawall (bay.gd) keeps x -350..350 at z -349.9.
const LEGACY_NEAR := Vector2(-350.0, 350.0)
const COPING_TOP := 0.44

static func water_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for key: String in DowntownPlan.WATER:
		var r: Rect2 = DowntownPlan.WATER[key]
		if key == "singapore_river": r = RIVER_EXT
		elif key == "east_channel": r = CHANNEL_EXT
		out.append(r)
	return out

static func is_water_ext(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for key: String in DowntownPlan.ISLANDS:
		if (DowntownPlan.ISLANDS[key] as Rect2).has_point(p):
			return false
	for r: Rect2 in water_rects():
		if r.has_point(p):
			return true
	return not OUTER.has_point(p)

static func _edges() -> Array:
	var xs := {OUTER.position.x: true, OUTER.end.x: true, LEGACY_NEAR.x: true, LEGACY_NEAR.y: true}
	var zs := {OUTER.position.y: true, OUTER.end.y: true}
	var rects: Array[Rect2] = water_rects()
	for key: String in DowntownPlan.ISLANDS:
		rects.append(DowntownPlan.ISLANDS[key])
	for r: Rect2 in rects:
		for x: float in [r.position.x, r.end.x]:
			if x > OUTER.position.x and x < OUTER.end.x: xs[x] = true
		for z: float in [r.position.y, r.end.y]:
			if z > OUTER.position.y and z < OUTER.end.y: zs[z] = true
	var xa: Array = xs.keys()
	var za: Array = zs.keys()
	xa.sort()
	za.sort()
	return [xa, za]

## Land rects (merged grid cells).
static func land_rects() -> Array[Rect2]:
	var e := _edges()
	var xs: Array = e[0]
	var zs: Array = e[1]
	var rows: Array = []
	for j in zs.size() - 1:
		var runs: Array = []
		var start := -1
		for i in xs.size():
			var land := false
			if i < xs.size() - 1:
				land = not is_water_ext((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)
			if land and start < 0:
				start = i
			elif not land and start >= 0:
				runs.append(Vector2(xs[start], xs[i]))
				start = -1
		rows.append(runs)
	var out: Array[Rect2] = []
	var open := {}   # run -> z start
	for j in rows.size():
		var runs2: Array = rows[j]
		var next_open := {}
		for run: Vector2 in runs2:
			next_open[run] = open.get(run, zs[j])
		for run: Vector2 in open:
			if not next_open.has(run):
				out.append(Rect2(run.x, open[run], run.y - run.x, zs[j] - open[run]))
		open = next_open
	for run: Vector2 in open:
		out.append(Rect2(run.x, open[run], run.y - run.x, zs[zs.size() - 1] - open[run]))
	return out

## Shore segments: [a, b, outward] where outward points into the water.
static func shore_segments() -> Array:
	var e := _edges()
	var xs: Array = e[0]
	var zs: Array = e[1]
	var segs: Array = []
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			var cx: float = (xs[i] + xs[i + 1]) * 0.5
			var cz: float = (zs[j] + zs[j + 1]) * 0.5
			if is_water_ext(cx, cz):
				continue
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			var z0: float = zs[j]
			var z1: float = zs[j + 1]
			if is_water_ext(cx, z0 - 0.5) and OUTER.has_point(Vector2(cx, z0 - 0.5)): segs.append([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(0, 0, -1)])
			if is_water_ext(cx, z1 + 0.5) and OUTER.has_point(Vector2(cx, z1 + 0.5)): segs.append([Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(0, 0, 1)])
			if is_water_ext(x0 - 0.5, cz) and OUTER.has_point(Vector2(x0 - 0.5, cz)): segs.append([Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(-1, 0, 0)])
			if is_water_ext(x1 + 0.5, cz) and OUTER.has_point(Vector2(x1 + 0.5, cz)): segs.append([Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(1, 0, 0)])
	return segs

static func build(m) -> void:
	var lands := land_rects()
	m.stats["land_rects"] = lands.size()
	for r: Rect2 in lands:
		var a := Vector3(r.position.x, 0.0, r.position.y)
		var b := Vector3(r.end.x, 0.0, r.position.y)
		var c := Vector3(r.end.x, 0.0, r.end.y)
		var d := Vector3(r.position.x, 0.0, r.end.y)
		m.quad_up("ground", a, b, c, d)
		m.col_box(Vector3(r.size.x, 4.0, r.size.y), Vector3(r.get_center().x, -2.0, r.get_center().y))
	_seawalls(m)
	_plots(m)
	_ns_square(m)
	_adjust_bay(m)

static func _seawalls(m) -> void:
	var playable := DowntownPlan.PLAYABLE.grow(60.0)
	var count := 0
	for s: Array in shore_segments():
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var out: Vector3 = s[2]
		# the legacy near seawall and the Merlion pier are bay.gd's
		if out.z < 0.0 and is_equal_approx(a.z, -349.0) and minf(a.x, b.x) >= LEGACY_NEAR.x - 0.1 and maxf(a.x, b.x) <= LEGACY_NEAR.y + 0.1:
			continue
		var mid := (a + b) * 0.5
		if (DowntownPlan.ISLANDS["merlion_pier"] as Rect2).grow(0.5).has_point(Vector2(mid.x, mid.z)):
			continue
		var length := a.distance_to(b)
		var along := (b - a).normalized()
		var face_size := Vector3(length, 3.5, 0.9) if absf(out.z) > 0.5 else Vector3(0.9, 3.5, length)
		var face_c := mid + out * 0.45 + Vector3(0, -1.45, 0)
		m.box("granite", face_c, face_size)
		var cop_size := Vector3(length, 0.16, 1.2) if absf(out.z) > 0.5 else Vector3(1.2, 0.16, length)
		m.box("granite_coping", mid + out * 0.3 + Vector3(0, COPING_TOP - 0.08, 0), cop_size)
		var wet_size := Vector3(length, 0.75, 0.06) if absf(out.z) > 0.5 else Vector3(0.06, 0.75, length)
		m.box("wet", mid + out * 0.93 + Vector3(0, DowntownPlan.WATER_LEVEL + 0.42, 0), wet_size)
		var alg_size := Vector3(length, 0.16, 0.08) if absf(out.z) > 0.5 else Vector3(0.08, 0.16, length)
		m.box("algae", mid + out * 0.94 + Vector3(0, DowntownPlan.WATER_LEVEL + 0.06, 0), alg_size)
		count += 1
		if not playable.has_point(Vector2(mid.x, mid.z)):
			continue
		# railing in runs, broken where a bridge lands or a pad meets the edge
		var run_start := -1.0
		var t := 0.0
		var step := 2.5
		while t <= length + 0.01:
			var p := a + along * t + out * 0.1
			var open := _rail_gap(p)
			if not open and run_start < 0.0:
				run_start = t
			if (open or t + step > length + 0.01) and run_start >= 0.0:
				var t_end := t if open else minf(t, length)
				if t_end - run_start > 1.0:
					var ra := a + along * run_start + out * 0.15 + Vector3(0, COPING_TOP, 0)
					var rb := a + along * t_end + out * 0.15 + Vector3(0, COPING_TOP, 0)
					m.pitched_box_visual("steel_rail", ra, rb, 0.07, 0.07, Vector3(0, 1.1, 0))
					m.pitched_box_visual("steel_rail", ra, rb, 0.04, 0.04, Vector3(0, 0.55, 0))
					m.pitched_box(ra, rb, 0.3, 1.3, Vector3(0, 0.65, 0))
				run_start = -1.0
			if not open:
				m.post(a + along * t + out * 0.15 + Vector3(0, COPING_TOP, 0), 1.12)
			t += step
	m.stats["seawall_segments"] = count

static func _rail_gap(p: Vector3) -> bool:
	var Bridges := preload("res://src/world/downtown/bridges.gd")
	if Bridges.on_deck(p.x, p.z, 0.4):
		return true
	var helix: Dictionary = DowntownPlan.BRIDGES["helix_bridge"]
	for end: Vector3 in [helix["from"], helix["to"]]:
		if Vector2(p.x - end.x, p.z - end.z).length() < 8.0:
			return true
	return false

## Plot pads: every BLOCKS rect is a raised paved pad (parks are turf), so
## the downtown reads as made city ground before the blocks/landmarks pieces
## stand their buildings on it.
static func _plots(m) -> void:
	for key: String in DowntownPlan.BLOCKS:
		var blk: Dictionary = DowntownPlan.BLOCKS[key]
		var r: Rect2 = blk["rect"]
		var kind := String(blk["kind"])
		var top := 0.16
		var key_mat := "plot"
		if kind == "park" or key in ["gardens_site", "civic_padang"]:
			key_mat = "turf"
			top = 0.2
		elif kind == "plaza":
			key_mat = "plaza"
		var c := r.get_center()
		m.box(key_mat, Vector3(c.x, top * 0.5, c.y), Vector3(r.size.x, top, r.size.y))
		# kerb-stone border
		for side: float in [-1.0, 1.0]:
			m.box("kerb", Vector3(c.x, top * 0.5 + 0.01, c.y + side * (r.size.y * 0.5 - 0.15)), Vector3(r.size.x, top + 0.02, 0.3))
			m.box("kerb", Vector3(c.x + side * (r.size.x * 0.5 - 0.15), top * 0.5 + 0.01, c.y), Vector3(0.3, top + 0.02, r.size.y))
		m.col_box(Vector3(r.size.x, top, r.size.y), Vector3(c.x, top * 0.5, c.y))
		if key_mat == "plot" and not ResourceLoader.exists("res://src/world/downtown/blocks.gd"):
			_landscape_plot(m, key, r, top)
		if key == "civic_padang":
			# the Padang: a cricket green inside a paved rim with a pavilion terrace
			m.box("pavers_warm", Vector3(c.x, 0.21, c.y - r.size.y * 0.5 + 9.0), Vector3(r.size.x - 4.0, 0.04, 14.0))

## NS Square (the former Float@Marina Bay): a paved 120 x 83 m deck at +0.3
## with a stepped grandstand on the land side, doubling as a helipad.
static func _ns_square(m) -> void:
	var r: Rect2 = DowntownPlan.ISLANDS["ns_square_float"]
	var c := r.get_center()
	m.box("plaza", Vector3(c.x + 6.0, 0.15, c.y), Vector3(r.size.x - 12.0, 0.3, r.size.y))
	m.col_box(Vector3(r.size.x - 12.0, 0.3, r.size.y), Vector3(c.x + 6.0, 0.15, c.y))
	for i in 6:
		var h := 0.3 + 0.45 * (i + 1)
		var x := r.position.x + 12.0 - (i + 0.5) * 2.0
		m.box("concrete_bridge", Vector3(x, h * 0.5, c.y), Vector3(2.0, h, r.size.y - 10.0))
		m.col_box(Vector3(2.0, h, r.size.y - 10.0), Vector3(x, h * 0.5, c.y))

## The legacy bay seawalls spanned the whole old map (x -750..750 near shore,
## a far edge at z -615). Downtown geography puts the river mouth, the Esplanade
## and the Marina South shore on those lines, so the legacy near face is cut
## back to its own promenade and the far wet bands are retired (this piece
## builds every other shoreline). The water shader's lapping-foam lines follow.
static func _adjust_bay(m) -> void:
	var bay: BayWater = m.world.bay
	if bay == null:
		return
	for child in bay.get_children():
		if not child is MeshInstance3D or not child.has_meta("bay_edge"):
			continue
		var mi := child as MeshInstance3D
		var bm := mi.mesh as BoxMesh
		if bm == null:
			continue
		if bm.size.x >= 1400.0 and absf(mi.position.z - (-350.4)) < 1.0:
			var nb := bm.duplicate() as BoxMesh
			nb.size.x = LEGACY_NEAR.y - LEGACY_NEAR.x
			mi.mesh = nb
			mi.position.x = (LEGACY_NEAR.x + LEGACY_NEAR.y) * 0.5
		elif bm.size.x >= 1600.0 and mi.position.z < -600.0:
			mi.visible = false
	if bay.water_material != null:
		bay.water_material.set_shader_parameter("far_shore_z", float(DowntownPlan.LEGACY["far_seawall_z"]) - 0.9)
		bay.water_material.set_shader_parameter("near_shore_span", Vector2(LEGACY_NEAR.x - 90.0, LEGACY_NEAR.y))
		bay.water_material.set_shader_parameter("far_shore_span", Vector2(-330.0, 350.0))

## Interim landscaping on the paved plot pads (until the blocks piece builds
## them): a grid of kerbed turf beds with shade trees, so an empty plot reads as
## a planted city plaza from the street and the air, not bare hard-standing.
static func _landscape_plot(m, key: String, r: Rect2, top: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var Bounds := preload("res://src/world/downtown/bounds.gd")
	var step := 26.0
	var bed := 9.0
	var nx := maxi(1, int((r.size.x - 8.0) / step))
	var nz := maxi(1, int((r.size.y - 8.0) / step))
	var ox := r.position.x + (r.size.x - (nx - 1) * step) * 0.5
	var oz := r.position.y + (r.size.y - (nz - 1) * step) * 0.5
	var k := 0
	for i in nx:
		for j in nz:
			var c := Vector2(ox + i * step, oz + j * step)
			# keep clear of the stand-in towers kept on this plot
			var blocked := false
			for xf: Transform3D in m.kept_towers:
				var rad := maxf(xf.basis.x.length(), xf.basis.z.length()) * 0.75 + bed
				if Vector2(xf.origin.x, xf.origin.z).distance_to(c) < rad:
					blocked = true
					break
			if blocked or not Bounds._pad_clear(c, 30.0):
				continue
			m.box("kerb", Vector3(c.x, top + 0.12, c.y), Vector3(bed + 0.5, 0.24, bed + 0.5))
			m.box("turf", Vector3(c.x, top + 0.14, c.y), Vector3(bed - 0.3, 0.26, bed - 0.3))
			k += 1
			if k % 4 == 0:
				m.tree(Vector3(c.x, top + 0.27, c.y), rng.randf_range(0.8, 1.2), rng)
