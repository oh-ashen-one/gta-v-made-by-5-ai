extends RefCounted
## Marina Bay Sands at true scale (wave M, downtown-landmarks).
##
## Replaces the wave-A GLB (straight slabs, flat plank SkyPark) with:
##  - three 55-storey hotel towers, each a straight bay-side (west) leg and a
##    curved east leg that leans in and merges with it around level 23, with
##    an open lobby atrium between the legs;
##  - the SkyPark: a 309 m boat-hull deck on the tower tops with a 67 m
##    cantilever pointing NORTH (game -x, plan decision D2), infinity pool on
##    the bay side, planting beds, palms, pavilions and glass parapets;
##  - the Shoppes podium on the bay side: double-height glazed frontage with
##    shopfronts behind it, colonnade, deep canopy and a wave roof;
##  - the Event Plaza: raised granite terrace, broad steps down to a tree-lined
##    waterfront promenade with lamps, benches and a seawall railing.
## Frame: game -x = north, +z = toward the bay (west). All geometry original.

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")

const TOWER_DX := [-98.0, 0.0, 98.0]
const TOWER_HALF_W := 17.5
const TOWER_H := 191.0
const JOIN_Y := 80.0
const WEST_Z := [2.0, 16.0]          # bay-side leg, relative to MBS z
const DECK_Y := 200.0
const HULL_X := [-185.0, 124.0]      # cantilever tip (north) .. south end
const HULL_W := 38.0
const TERRACE_Y := 1.5
const PODIUM_X := [-182.0, 158.0]
const FACADE_Z := 41.0               # Shoppes glass line (relative)
const PODIUM_BACK_Z := 16.0

var m: Vector3
var stats := {}

func build(world: WorldBuilder, root: Node3D) -> Dictionary:
	m = DowntownPlan.ANCHORS["marina_bay_sands"]["pos"]
	var holder := Node3D.new()
	holder.name = "marina_bay_sands"
	root.add_child(holder)
	var kit := Kit.new(holder, "MBSCollision")
	_towers(kit)
	kit.commit(holder, "MBSTowers", true)
	_skypark(kit, holder)
	kit.commit(holder, "MBSSkyPark", true)
	_podium(kit, holder)
	kit.commit(holder, "MBSShoppes", true)
	var detail := Kit.new(holder, "MBSPlazaCollision")
	_event_plaza(detail, holder, world)
	detail.commit(holder, "MBSEventPlaza", false, 0.0)
	stats = {"shapes": kit.shapes + detail.shapes, "tris": kit.tris + detail.tris}
	return stats

# ------------------------------------------------------------------ towers
func _east_outer(y: float) -> float:
	return -12.0 - 33.0 * pow(1.0 - clampf(y / TOWER_H, 0.0, 1.0), 2.2)

func _east_inner(y: float) -> float:
	var t := smoothstep(0.0, JOIN_Y, y)
	return maxf(lerpf(-29.0, WEST_Z[0], t), _east_outer(y) + 10.0)

func _ring(x0: float, x1: float, z0: float, z1: float, y: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0)])

func _towers(kit: Kit) -> void:
	var glass := Looks.get_mat("tower_glass")
	var roof := Looks.get_mat("concrete_fair")
	var leg_ys := [0.0, 5.0, 11.0, 18.0, 26.0, 35.0, 45.0, 56.0, 68.0, JOIN_Y]
	var up_ys := [JOIN_Y, 92.0, 105.0, 120.0, 136.0, 152.0, 168.0, 180.0, TOWER_H]
	for dx: float in TOWER_DX:
		var x0 := m.x + dx - TOWER_HALF_W
		var x1 := m.x + dx + TOWER_HALF_W
		var west := []
		var east := []
		for y: float in leg_ys:
			west.append(_ring(x0, x1, m.z + WEST_Z[0], m.z + WEST_Z[1], y))
			east.append(_ring(x0, x1, m.z + _east_outer(y), m.z + _east_inner(y), y))
		kit.loft(glass, west)
		kit.loft(glass, east)
		var upper := []
		for y: float in up_ys:
			upper.append(_ring(x0, x1, m.z + _east_outer(y), m.z + WEST_Z[1], y))
		kit.loft(glass, upper)
		kit.cap(roof, upper[upper.size() - 1])
		# Atrium soffit where the legs merge (seen from below the split).
		var j: PackedVector3Array = _ring(x0, x1, m.z + _east_inner(JOIN_Y - 0.01), m.z + WEST_Z[0], JOIN_Y)
		kit.quad(roof, j[3], j[2], j[1], j[0])
		# Lobby: dark glazed base between the legs and a porte-cochere canopy.
		kit.box(Looks.get_mat("glass_dark"), Vector3(m.x + dx, 6.0, m.z - 13.0), Vector3(TOWER_HALF_W * 2.0 - 1.0, 12.0, 26.0))
		kit.box(Looks.get_mat("steel_white"), Vector3(m.x + dx, 12.4, m.z - 13.0), Vector3(TOWER_HALF_W * 2.0 + 4.0, 0.8, 30.0))
		# Collision: west leg, east leg in three leaning steps, merged shaft.
		kit.col_box(Vector3(TOWER_HALF_W * 2.0, JOIN_Y, WEST_Z[1] - WEST_Z[0]), Vector3(m.x + dx, JOIN_Y * 0.5, m.z + (WEST_Z[0] + WEST_Z[1]) * 0.5))
		for k in 3:
			var ya := JOIN_Y * k / 3.0
			var yb := JOIN_Y * (k + 1) / 3.0
			var zo := _east_outer((ya + yb) * 0.5)
			var zi := _east_inner((ya + yb) * 0.5)
			kit.col_box(Vector3(TOWER_HALF_W * 2.0, yb - ya, zi - zo), Vector3(m.x + dx, (ya + yb) * 0.5, m.z + (zo + zi) * 0.5))
		var zt := _east_outer((JOIN_Y + TOWER_H) * 0.5)
		kit.col_box(Vector3(TOWER_HALF_W * 2.0, TOWER_H - JOIN_Y, WEST_Z[1] - zt), Vector3(m.x + dx, (JOIN_Y + TOWER_H) * 0.5, m.z + (zt + WEST_Z[1]) * 0.5))

# ------------------------------------------------------------------ SkyPark
func _hull_w(s: float) -> float:
	var bow := 1.0 - pow(1.0 - clampf(s / 0.24, 0.0, 1.0), 2.4)
	var w := lerpf(3.0, HULL_W, bow)
	if s > 0.9:
		w = lerpf(w, 24.0, pow((s - 0.9) / 0.1, 1.6))
	return w

func _hull_bottom(x_rel: float) -> float:
	var tower_n: float = TOWER_DX[0] - TOWER_HALF_W
	if x_rel < tower_n:
		var u: float = (tower_n - x_rel) / (tower_n - HULL_X[0])
		return lerpf(191.0, 197.8, pow(u, 1.25))
	var tower_s: float = TOWER_DX[2] + TOWER_HALF_W
	if x_rel > tower_s:
		var v: float = (x_rel - tower_s) / (HULL_X[1] - tower_s)
		return lerpf(191.0, 196.2, pow(v, 1.5))
	return 191.0

func _skypark(kit: Kit, holder: Node3D) -> void:
	var hull := Looks.get_mat("hull_panel")
	var deck := Looks.get_mat("deck_stone")
	var zc := m.z + 2.0
	var rings := []
	var n := 44
	for i in n + 1:
		var s := float(i) / n
		var xr: float = lerpf(HULL_X[0], HULL_X[1], s)
		var x := m.x + xr
		var w := _hull_w(s)
		var yb := _hull_bottom(xr)
		var top_edge := DECK_Y - 1.6
		rings.append(PackedVector3Array([
			Vector3(x, DECK_Y, zc + w * 0.5),
			Vector3(x, top_edge, zc + w * 0.5),
			Vector3(x, yb + 1.2, zc + w * 0.36),
			Vector3(x, yb, zc),
			Vector3(x, yb + 1.2, zc - w * 0.36),
			Vector3(x, top_edge, zc - w * 0.5),
			Vector3(x, DECK_Y, zc - w * 0.5),
		]))
	kit.loft(hull, rings, false, true)
	# Panel joints: a darker reveal line along the hull.
	var reveal := Looks.get_mat("steel_dark")
	for i in n:
		var a: PackedVector3Array = rings[i]
		var b: PackedVector3Array = rings[i + 1]
		kit.quad(deck, a[6], a[0], b[0], b[6])
		for side in [1, 5]:
			kit.beam(reveal, a[side] - Vector3(0, 0.05, 0), b[side] - Vector3(0, 0.05, 0), 0.12, 0.12)
		Realm.glass_rail(kit, a[0], b[0], 1.3)
		Realm.glass_rail(kit, b[6], a[6], 1.3)
	var stern: PackedVector3Array = rings[n]
	kit.cap(hull, stern)
	var bow: PackedVector3Array = rings[0]
	var bow_rev := PackedVector3Array()
	for i in range(bow.size() - 1, -1, -1):
		bow_rev.append(bow[i])
	kit.cap(hull, bow_rev)
	# Infinity pool along the bay edge of the deck, over the north and centre towers.
	var pool_x0 := m.x - 150.0
	var pool_x1 := m.x + 20.0
	var pool_z1 := zc + HULL_W * 0.5 - 1.6
	var pool_z0 := pool_z1 - 9.0
	kit.box(Looks.get_mat("granite_light"), Vector3((pool_x0 + pool_x1) * 0.5, DECK_Y + 0.12, (pool_z0 + pool_z1) * 0.5), Vector3(pool_x1 - pool_x0 + 1.2, 0.24, pool_z1 - pool_z0 + 1.2))
	kit.box(Looks.get_mat("pool_water"), Vector3((pool_x0 + pool_x1) * 0.5, DECK_Y + 0.26, (pool_z0 + pool_z1) * 0.5), Vector3(pool_x1 - pool_x0, 0.06, pool_z1 - pool_z0))
	# Sun-lounger rows beside the pool.
	var lounger := Looks.get_mat("steel_white")
	var xl := pool_x0 + 2.0
	while xl < pool_x1 - 2.0:
		kit.box(lounger, Vector3(xl, DECK_Y + 0.3, pool_z0 - 2.0), Vector3(0.8, 0.3, 2.0))
		xl += 2.6
	# Planting beds, palms and garden pavilions down the landward half.
	var palm_x := []
	var bed_x := m.x - 140.0
	while bed_x < m.x + 110.0:
		Realm.planter(kit, Vector3(bed_x, DECK_Y, zc - 9.0), Vector2(14.0, 4.0), 0.7, false)
		palm_x.append(Kit.xf(Vector3(bed_x - 4.0, DECK_Y + 0.7, zc - 9.0), bed_x * 0.13, Vector3.ONE * 0.95))
		palm_x.append(Kit.xf(Vector3(bed_x + 4.0, DECK_Y + 0.7, zc - 9.0), bed_x * 0.29, Vector3.ONE * 0.85))
		bed_x += 22.0
	for dx: float in TOWER_DX:
		var px := m.x + dx
		kit.box(Looks.get_mat("glass_dark"), Vector3(px, DECK_Y + 2.0, zc - 2.0), Vector3(24.0, 4.0, 8.0))
		kit.box(Looks.get_mat("steel_white"), Vector3(px, DECK_Y + 4.2, zc - 2.0), Vector3(27.0, 0.4, 10.5))
	Realm.glb_multimesh(holder, "MBSSkyParkPalms", "palm.glb", palm_x, false, 1400.0)
	# Landable deck for the helicopter (pad itself stays reserved; plan section 10).
	var hx: float = m.x + (HULL_X[0] + HULL_X[1]) * 0.5
	kit.col_box(Vector3(HULL_X[1] - HULL_X[0] - 20.0, 8.0, 30.0), Vector3(hx + 10.0, DECK_Y - 4.0, zc))

# ------------------------------------------------------------------ Shoppes
func _podium(kit: Kit, holder: Node3D) -> void:
	var x0: float = m.x + PODIUM_X[0]
	var x1: float = m.x + PODIUM_X[1]
	var zf := m.z + FACADE_Z
	var zb := m.z + PODIUM_BACK_Z
	var top := 16.0
	var concrete := Looks.get_mat("concrete_fair")
	var white := Looks.get_mat("steel_white")
	var satin := Looks.get_mat("steel_satin")
	var xc := (x0 + x1) * 0.5
	var lx := x1 - x0
	# Shop interior block: warm shopfronts 4 m behind the glass, two mezzanine
	# slab edges with light strips, solid back of house.
	kit.box(concrete, Vector3(xc, (TERRACE_Y + top) * 0.5, (zb + zf - 4.0) * 0.5), Vector3(lx, top - TERRACE_Y, zf - 4.0 - zb))
	kit.quad(Looks.get_mat("interior_warm"), Vector3(x0, TERRACE_Y, zf - 3.95), Vector3(x1, TERRACE_Y, zf - 3.95), Vector3(x1, top, zf - 3.95), Vector3(x0, top, zf - 3.95))
	for ys: float in [6.2, 11.0]:
		kit.box(concrete, Vector3(xc, ys, zf - 2.0), Vector3(lx, 0.5, 4.0))
		kit.box(Looks.get_mat("light_strip"), Vector3(xc, ys - 0.27, zf - 2.0), Vector3(lx, 0.04, 2.6))
		kit.box(Looks.get_mat("glass_clear"), Vector3(xc, ys + 0.6, zf - 3.6), Vector3(lx, 0.7, 0.04))
	kit.box(concrete, Vector3(xc, top - 0.4, zf - 2.0), Vector3(lx, 0.8, 4.0))
	# Shopfront fit-outs behind the glazing: alternating warm/dark bays.
	var sx := x0 + 2.0
	var bay_i := 0
	while sx < x1 - 6.0:
		var w := 9.0 + float(bay_i % 3) * 2.0
		var lit := bay_i % 4 != 2
		kit.box(Looks.get_mat("interior_warm") if lit else Looks.get_mat("glass_dark"), Vector3(sx + w * 0.5, TERRACE_Y + 2.2, zf - 3.7), Vector3(w - 0.8, 4.0, 0.3))
		kit.box(Looks.get_mat("signage"), Vector3(sx + w * 0.5, TERRACE_Y + 4.6, zf - 3.6), Vector3(w - 1.2, 0.7, 0.2))
		sx += w
		bay_i += 1
	# Curtain wall: glass, 3 m mullions, two transoms.
	kit.quad(Looks.get_mat("glass_clear"), Vector3(x1, TERRACE_Y, zf), Vector3(x0, TERRACE_Y, zf), Vector3(x0, top, zf), Vector3(x1, top, zf))
	var mx := x0
	while mx <= x1 + 0.01:
		kit.box(satin, Vector3(mx, (TERRACE_Y + top) * 0.5, zf + 0.12), Vector3(0.16, top - TERRACE_Y, 0.34))
		mx += 3.0
	for ty: float in [TERRACE_Y + 0.15, 5.7, 10.6, top - 0.2]:
		kit.box(satin, Vector3(xc, ty, zf + 0.12), Vector3(lx, 0.16, 0.3))
	# Colonnade and deep cantilevered canopy with a lit soffit.
	var zc := zf + 7.5
	var cx := x0 + 4.0
	while cx < x1:
		kit.cyl(white, Vector3(cx, TERRACE_Y, zc), 0.55, 0.42, top - TERRACE_Y, 10, false)
		cx += 18.0
	kit.box(white, Vector3(xc, top + 0.7, (zb + zf + 9.0) * 0.5), Vector3(lx + 4.0, 1.4, zf + 9.0 - zb))
	kit.box(Looks.get_mat("soffit"), Vector3(xc, top - 0.02, (zb + zf + 9.0) * 0.5), Vector3(lx + 3.6, 0.04, zf + 9.0 - zb - 0.4))
	var sx2 := x0 + 3.0
	while sx2 < x1 - 2.0:
		kit.box(Looks.get_mat("light_strip"), Vector3(sx2, top - 0.06, zf + 4.5), Vector3(0.5, 0.05, 6.0))
		sx2 += 6.0
	kit.box(satin, Vector3(xc, top + 0.7, zf + 9.1), Vector3(lx + 4.0, 1.6, 0.25))
	# Wave roof: a run of curved shells with glazed clerestory ends.
	var shell := white
	var bays := 10
	var span := lx / bays
	for b in bays:
		var bx0 := x0 + b * span
		var rise := 7.5 if b % 2 == 0 else 5.2
		var base := top + 1.4
		var arc := []
		var steps := 9
		for k in steps + 1:
			var u := float(k) / steps
			arc.append(Vector3(bx0 + span * u, base + rise * sin(PI * u), 0.0))
		var ra := PackedVector3Array()
		var rb := PackedVector3Array()
		for p: Vector3 in arc:
			ra.append(Vector3(p.x, p.y, zf + 6.0))
			rb.append(Vector3(p.x, p.y, zb + 1.0))
		# Rings advance -z; list the arc so its outward normal points up.
		var ra_rev := PackedVector3Array()
		var rb_rev := PackedVector3Array()
		for i in range(ra.size() - 1, -1, -1):
			ra_rev.append(ra[i])
			rb_rev.append(rb[i])
		kit.loft(shell, [ra, rb], false, true)
		kit.loft(Looks.get_mat("steel_dark"), [ra_rev, rb_rev], false, true)
		for k in steps:
			kit.tri(Looks.get_mat("glass_dark"), Vector3(arc[k].x, base, zf + 6.0), Vector3(arc[k + 1].x, arc[k + 1].y, zf + 6.0), Vector3(arc[k].x, arc[k].y, zf + 6.0))
			kit.tri(Looks.get_mat("glass_dark"), Vector3(arc[k].x, base, zf + 6.0), Vector3(arc[k + 1].x, base, zf + 6.0), Vector3(arc[k + 1].x, arc[k + 1].y, zf + 6.0))
	# Entrances on the tower axes: recessed portals, revolving doors, signs.
	for dx: float in TOWER_DX:
		var ex := m.x + dx
		kit.box(Looks.get_mat("steel_dark"), Vector3(ex, TERRACE_Y + 2.0, zf + 0.25), Vector3(10.0, 4.0, 0.3))
		kit.box(Looks.get_mat("glass_dark"), Vector3(ex, TERRACE_Y + 1.6, zf + 0.45), Vector3(9.0, 3.2, 0.2))
		for side: float in [-3.0, 0.0, 3.0]:
			kit.cyl(Looks.get_mat("glass_clear"), Vector3(ex + side, TERRACE_Y, zf + 1.4), 1.2, 1.2, 2.8, 10)
			kit.cyl(Looks.get_mat("steel_satin"), Vector3(ex + side, TERRACE_Y + 2.8, zf + 1.4), 1.3, 1.3, 0.3, 10)
		var sign := Label3D.new()
		sign.text = "THE SHOPPES"
		sign.font_size = 120
		sign.pixel_size = 0.012
		sign.modulate = Color(0.86, 0.84, 0.78)
		sign.outline_size = 0
		sign.position = Vector3(ex, top + 0.75, zf + 9.3)
		holder.add_child(sign)
	kit.col_box(Vector3(lx, top - TERRACE_Y, zf - zb), Vector3(xc, (TERRACE_Y + top) * 0.5, (zb + zf) * 0.5))

# ------------------------------------------------------------------ Event Plaza
func _event_plaza(kit: Kit, holder: Node3D, world: WorldBuilder) -> void:
	var ep: Dictionary = DowntownPlan.ANCHORS["mbs_event_plaza"]
	var c: Vector3 = ep["pos"]
	var size: Vector3 = ep["size"]
	var x0 := c.x - size.x * 0.5 + 6.0
	var x1 := c.x + size.x * 0.5 - 6.0
	var xc := (x0 + x1) * 0.5
	var lx := x1 - x0
	var zf := m.z + FACADE_Z
	var z_terrace := zf + 13.0          # terrace edge / top step
	var z_steps := z_terrace + 10.0     # foot of the steps
	var z_sea := c.z + size.z * 0.5     # seawall line
	var paving := Looks.get_mat("granite_paving")
	var step_mat := Looks.get_mat("granite_light")
	var prom_top := 0.36
	# Raised terrace in front of the Shoppes.
	kit.box(paving, Vector3(xc, TERRACE_Y * 0.5, (zf - 2.0 + z_terrace) * 0.5), Vector3(lx + 10.0, TERRACE_Y, z_terrace - zf + 2.0))
	kit.col_box(Vector3(lx + 10.0, TERRACE_Y, z_terrace - zf + 2.0), Vector3(xc, TERRACE_Y * 0.5, (zf - 2.0 + z_terrace) * 0.5))
	# Broad amphitheatre steps (visual) over one walkable ramp (collision).
	var nsteps := 8
	var tread := (z_steps - z_terrace) / nsteps
	var rise := (TERRACE_Y - prom_top) / nsteps
	for i in nsteps:
		var ytop := TERRACE_Y - rise * (i + 1)
		var za := z_terrace + tread * i
		kit.box(step_mat, Vector3(xc, ytop * 0.5, za + tread * 0.5), Vector3(lx, ytop, tread))
		kit.box(Looks.get_mat("granite_dark"), Vector3(xc, ytop + 0.005, za + 0.08), Vector3(lx, 0.012, 0.12))
	kit.col_beam(Vector3(xc, TERRACE_Y, z_terrace), Vector3(xc, prom_top, z_steps), lx, 0.6)
	# Waterfront promenade to the seawall.
	kit.box(paving, Vector3(xc, prom_top * 0.5, (z_steps + z_sea) * 0.5), Vector3(lx + 10.0, prom_top, z_sea - z_steps))
	kit.col_box(Vector3(lx + 10.0, 1.0, z_sea - z_steps), Vector3(xc, prom_top - 0.5, (z_steps + z_sea) * 0.5))
	kit.box(Looks.get_mat("granite_light"), Vector3(xc, prom_top + 0.04, z_sea - 0.7), Vector3(lx + 10.0, 0.16, 1.4))
	# Seawall railing with one opening onto the crystal pavilion gangway.
	var gap_x := m.x + 78.0
	Realm.railing(kit, Vector3(x0 - 5.0, prom_top + 0.1, z_sea - 0.9), Vector3(gap_x - 2.2, prom_top + 0.1, z_sea - 0.9), 1.15)
	Realm.railing(kit, Vector3(gap_x + 2.2, prom_top + 0.1, z_sea - 0.9), Vector3(x1 + 5.0, prom_top + 0.1, z_sea - 0.9), 1.15)
	var ra := x0 - 5.0
	var rb := gap_x - 2.2
	kit.col_box(Vector3(rb - ra, 1.3, 0.2), Vector3((ra + rb) * 0.5, prom_top + 0.65, z_sea - 0.9))
	ra = gap_x + 2.2
	rb = x1 + 5.0
	kit.col_box(Vector3(rb - ra, 1.3, 0.2), Vector3((ra + rb) * 0.5, prom_top + 0.65, z_sea - 0.9))
	# Granite tree pits with rain trees, lamps between, benches facing the bay.
	var lamp_x := []
	var bench_x := []
	var x := x0 + 8.0
	var i := 0
	while x < x1 - 4.0:
		var tz := z_steps + 4.5
		kit.box(Looks.get_mat("granite_dark"), Vector3(x, prom_top + 0.06, tz), Vector3(3.2, 0.14, 3.2))
		kit.box(Looks.get_mat("soil_bed"), Vector3(x, prom_top + 0.08, tz), Vector3(2.8, 0.14, 2.8))
		world._tree(Vector3(x, prom_top, tz), 0.95 + 0.1 * float(i % 3))
		lamp_x.append(Kit.xf(Vector3(x + 12.0, prom_top, z_sea - 3.0), PI))
		bench_x.append(Kit.xf(Vector3(x + 6.0, prom_top, z_sea - 4.6), 0.0))
		bench_x.append(Kit.xf(Vector3(x + 18.0, prom_top, z_sea - 4.6), 0.0))
		x += 24.0
		i += 1
	# Terrace: planters and lamps along the step edge, bollards at the stairs.
	var bollards := []
	var px := x0 + 14.0
	while px < x1 - 6.0:
		Realm.planter(kit, Vector3(px, TERRACE_Y, z_terrace - 4.0), Vector2(6.0, 2.2))
		lamp_x.append(Kit.xf(Vector3(px + 15.0, TERRACE_Y, z_terrace - 1.2), PI))
		px += 30.0
	for dx: float in TOWER_DX:
		for k in 5:
			bollards.append(Vector3(m.x + dx - 6.0 + k * 3.0, TERRACE_Y, z_terrace - 0.6))
	Realm.lamps(holder, "MBSPlazaLamps", lamp_x)
	Realm.benches(holder, "MBSPlazaBenches", bench_x)
	Realm.bollards(holder, "MBSPlazaBollards", bollards)
	Realm.flush_ferns(holder, "MBSPlazaFerns")
	# Crystal pavilion on the water off the promenade, reached by a gangway.
	var cp := Vector3(m.x + 78.0, prom_top, z_sea + 16.0)
	var base_r := 13.0
	var top_pts := PackedVector3Array()
	var low := PackedVector3Array()
	for k in 6:
		var ang := TAU * k / 6.0 + 0.3
		low.append(cp + Vector3(cos(ang) * base_r, 0.0, sin(ang) * base_r * 0.8))
		top_pts.append(cp + Vector3(cos(ang + 0.5) * base_r * 0.45 + 3.0, 13.0 - 3.0 * float(k % 2), sin(ang + 0.5) * base_r * 0.35))
	var gl := Looks.get_mat("glass_dark")
	var fr := Looks.get_mat("steel_satin")
	for k in 6:
		var k1 := (k + 1) % 6
		kit.tri(gl, low[k1], low[k], top_pts[k])
		kit.tri(gl, low[k1], top_pts[k], top_pts[k1])
		kit.beam(fr, low[k], top_pts[k], 0.18, 0.18)
		kit.beam(fr, top_pts[k], top_pts[k1], 0.18, 0.18)
		kit.beam(fr, low[k1], top_pts[k], 0.12, 0.12)
	var top_rev := PackedVector3Array()
	for k in range(5, -1, -1):
		top_rev.append(top_pts[k])
	kit.cap(gl, top_rev)
	kit.cyl(Looks.get_mat("concrete_fair"), cp - Vector3(0, 1.4, 0), base_r + 1.0, base_r + 1.0, 1.4, 6, true)
	kit.col_box(Vector3(base_r * 1.6, 12.0, base_r * 1.3), cp + Vector3(0, 6.0, 0))
	var g0 := Vector3(cp.x, prom_top, z_sea - 0.5)
	var g1 := Vector3(cp.x, prom_top, cp.z - base_r * 0.8 + 0.5)
	kit.box(Looks.get_mat("timber"), (g0 + g1) * 0.5 + Vector3(0, 0.1, 0), Vector3(4.0, 0.3, g1.z - g0.z))
	Realm.glass_rail(kit, g0 + Vector3(-2.0, 0.25, 0), g1 + Vector3(-2.0, 0.25, 0), 1.1)
	Realm.glass_rail(kit, g0 + Vector3(2.0, 0.25, 0), g1 + Vector3(2.0, 0.25, 0), 1.1)
	kit.col_box(Vector3(4.0, 0.5, g1.z - g0.z), (g0 + g1) * 0.5)
	# Wayfinding totem by the centre steps.
	var totem := Label3D.new()
	totem.text = "EVENT PLAZA\nBAYFRONT"
	totem.font_size = 64
	totem.pixel_size = 0.01
	totem.position = Vector3(m.x + 44.0, TERRACE_Y + 2.2, z_terrace - 2.0 + 0.32)
	totem.modulate = Color(0.92, 0.9, 0.84)
	holder.add_child(totem)
	kit.box(Looks.get_mat("signage"), Vector3(m.x + 44.0, TERRACE_Y + 1.5, z_terrace - 2.0), Vector3(1.6, 3.0, 0.6))
