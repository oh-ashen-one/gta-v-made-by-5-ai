extends RefCounted
## downtown-map: playable edges, helipads and background-city fix-ups
## (DOWNTOWN_PLAN section 10).
##
## - Each PLAYABLE edge is a physical barrier (2.4 m+, collision): construction
##   hoarding at x = -900 (Stamford Rd / Bras Basah) and x = 760 (Tanjong
##   Pagar), the existing boundary railing extended along z = 375 with a weir
##   rail over the river, and the Gardens fence / Marina Channel rail at
##   z = -1060.
## - The four new helipads (NS Square, the Lawn, Esplanade Park, Gardens East).
## - Background city: procedural towers that would stand on a road, a walk,
##   the river or the channel are removed before the city is built; the ones
##   left on downtown plots become stand-in buildings with box collision (no
##   walk-through ghosts). The background carpet, promenade trees and the
##   legacy flank seawalls are cut back out of the playable downtown.

const Roads := preload("res://src/world/downtown/roads.gd")
const Bridges := preload("res://src/world/downtown/bridges.gd")
const Shoreline := preload("res://src/world/downtown/shoreline.gd")
const HERITAGE := Rect2(-336.0, -349.0, 672.0, 724.0)
const CARPET_SHADER := "city_carpet.gdshader"

static func _on_walk(x: float, z: float, margin: float) -> bool:
	var p := Vector2(x, z)
	for key: String in DowntownPlan.PROMENADES:
		var w: Dictionary = DowntownPlan.PROMENADES[key]
		var pts: Array = w["pts"]
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			if Roads._dist_seg(p, Vector2(a.x, a.z), Vector2(b.x, b.z)) < float(w["width"]) * 0.5 + margin:
				return true
	return false

## True when a background tower footprint (centre, radius) may stay.
static func tower_ok(x: float, z: float, r: float) -> bool:
	var inside := DowntownPlan.PLAYABLE.grow(r + 4.0).has_point(Vector2(x, z))
	for wr: Rect2 in Shoreline.water_rects():
		if wr.grow(r + 3.0).has_point(Vector2(x, z)):
			return false
	if not inside:
		return true
	if HERITAGE.grow(r).has_point(Vector2(x, z)):
		return false
	if ResourceLoader.exists("res://src/world/downtown/blocks.gd"):
		return false   # the blocks piece builds every downtown plot
	# landmark sites stay clear of generic towers (Gardens, MBS, Flyer, Esplanade, Fullerton)
	for key: String in DowntownPlan.BLOCKS:
		if DowntownPlan.BLOCKS[key]["kind"] == "landmark_site" and (DowntownPlan.BLOCKS[key]["rect"] as Rect2).grow(r).has_point(Vector2(x, z)):
			return false
	if Roads.on_road(x, z, "", Roads.FOOTWAY + 1.0 + r) or Roads.on_legacy_road(x, z, 4.0 + r):
		return false
	if _on_walk(x, z, r + 1.0) or Bridges.height_at(x, z) > 0.0:
		return false
	for key2: String in DowntownPlan.ISLANDS:
		if (DowntownPlan.ISLANDS[key2] as Rect2).grow(r).has_point(Vector2(x, z)):
			return false
	for key3: String in DowntownPlan.HELIPADS:
		var pad: Dictionary = DowntownPlan.HELIPADS[key3]
		var c: Vector3 = pad["pos"]
		if Vector2(x - c.x, z - c.z).length() < float(pad["radius"]) + r + 14.0:
			return false
	# keep the parks and plazas open
	for key4: String in DowntownPlan.BLOCKS:
		var blk: Dictionary = DowntownPlan.BLOCKS[key4]
		if String(blk["kind"]) in ["park", "plaza", "civic"] and (blk["rect"] as Rect2).grow(r).has_point(Vector2(x, z)):
			return false
	return true

static func skyline_clear(m, city: SkylineCity) -> void:
	var removed := 0
	for kind in city._groups.size():
		var list: Array = city._groups[kind]
		var keep: Array = []
		for item: Array in list:
			var xf: Transform3D = item[0]
			var w := xf.basis.x.length()
			var d := xf.basis.z.length()
			var r := maxf(w, d) * 0.72
			if tower_ok(xf.origin.x, xf.origin.z, r):
				keep.append(item)
				if DowntownPlan.PLAYABLE.has_point(Vector2(xf.origin.x, xf.origin.z)):
					m.kept_towers.append(xf)
			else:
				removed += 1
		city._groups[kind] = keep
	# removed towers never reach city.build (no mesh, no ground shadow)
	city.placed -= removed
	# nothing more (horizon towers, low-rise carpet blocks) inside the playable
	# downtown, the river or the channel
	city.clear_zone(DowntownPlan.PLAYABLE.grow(20.0), 0.0)
	for wr: Rect2 in Shoreline.water_rects():
		city.clear_zone(wr.grow(8.0), 0.0)
	m.stats["towers_removed"] = removed
	m.stats["towers_kept_downtown"] = m.kept_towers.size()
	m.stats["beyond_core_towers"] = _beyond_core_skyline(city)
	m.stats["behind_mbs_tall"] = m_tall_behind_mbs

## Integration (wave M): the legacy far-shore tower layers stood where the low
## Bayfront, the Lawn and the Gardens are now, so every view across the bay
## lost its skyline behind MBS. Distant scenery beyond the east playable edge
## (past the Gardens fence, z < -1080) restores that depth: three rows of
## background towers, tallest in the middle row, with the Marina Channel
## corridor kept open. No collision (beyond the walled playable edge, like
## the rest of the background city); the legacy SkyPark wedge caps heights
## straight behind MBS.
static var m_tall_behind_mbs := 0
static func _beyond_core_skyline(city: SkylineCity) -> int:
	m_tall_behind_mbs = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	var before := city.placed
	var rows := [[-1125.0, 44.0, 85.0, 185.0], [-1205.0, 40.0, 120.0, 240.0], [-1295.0, 48.0, 70.0, 160.0]]
	# downtown-polish (wave S): the legacy 70 m SkyPark wedge (WorldBuilder
	# _background_city) was sized for the old far shore 300 m closer; these
	# rows stand 420-590 m behind MBS, where a 190 m tower still sits well
	# under the SkyPark deck in every bay view (the deck at 200 m, 400-500 m
	# from the camera, subtends twice the angle). The wedge is relaxed to
	# 190 m for these rows only and restored afterwards.
	var relaxed: Array[Dictionary] = []
	for c: Dictionary in city._clear:
		if is_equal_approx(float(c["max_h"]), 70.0):
			c["max_h"] = 190.0
			relaxed.append(c)
	for row: Array in rows:
		var x := -1000.0 + rng.randf_range(0.0, float(row[1]))
		while x < 1000.0:
			if x < -480.0 or x > -320.0:
				var z: float = float(row[0]) + rng.randf_range(-18.0, 18.0)
				var h := rng.randf_range(float(row[2]), float(row[3]))
				# directly behind MBS: a dense mid-height cluster, not stubs
				if x > -330.0 and x < 120.0:
					h = maxf(h, rng.randf_range(110.0, 185.0))
				var placed_before := city.placed
				city.add_random(Vector3(x, 0.0, z), h, rng.randf() < 0.2)
				if x > -330.0 and x < 120.0 and h > 100.0 and city.placed > placed_before:
					m_tall_behind_mbs += 1
			x += float(row[1]) * rng.randf_range(0.75, 1.3)
	for c2: Dictionary in relaxed:
		c2["max_h"] = 70.0
	return city.placed - before

static func build(m) -> void:
	_interim_planting(m)
	_edges(m)
	_helipads(m)
	_tower_collision(m)
	_cut_background(m)

static func finish(_m, _w: WorldBuilder) -> void:
	pass

## Interim planting on the park plots and the Gardens site until the blocks /
## landmarks pieces dress them (skipped as soon as those pieces exist).
static func _interim_planting(m) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6611
	var parks: Array = []
	if not ResourceLoader.exists("res://src/world/downtown/blocks.gd"):
		parks.append_array(["esplanade_park", "the_lawn", "civic_padang"])
	if not ResourceLoader.exists("res://src/world/downtown/landmarks.gd"):
		parks.append("gardens_site")
	for key: String in parks:
		var r: Rect2 = DowntownPlan.BLOCKS[key]["rect"]
		var top := 0.12
		if key == "gardens_site":
			# loose groves across the Bay South garden
			for i in 70:
				var c := Vector2(rng.randf_range(r.position.x + 12.0, r.end.x - 12.0), rng.randf_range(r.position.y + 12.0, r.end.y - 12.0))
				if not _pad_clear(c, 26.0):
					continue
				m.tree(Vector3(c.x, top, c.y), rng.randf_range(0.9, 1.5), rng)
			continue
		# perimeter rows, 4 m inside the kerb
		var inner := r.grow(-4.0)
		var corners := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y), inner.position]
		for k in 4:
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[k + 1]
			var n := maxi(1, int(a.distance_to(b) / 19.0))
			for j in n:
				var c2 := a.lerp(b, (j + 0.5) / n)
				if not _pad_clear(c2, 24.0):
					continue
				m.tree(Vector3(c2.x, top, c2.y), rng.randf_range(0.85, 1.2), rng)

static func _pad_clear(c: Vector2, d: float) -> bool:
	for key: String in DowntownPlan.HELIPADS:
		var pos: Vector3 = DowntownPlan.HELIPADS[key]["pos"]
		if Vector2(pos.x, pos.z).distance_to(c) < d:
			return false
	return true

# ------------------------------------------------------------ edges
static func _hoarding(m, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var n := maxi(1, int(ceil(length / 24.0)))
	for i in n:
		var pa := a.lerp(b, float(i) / n)
		var pb := a.lerp(b, float(i + 1) / n)
		if Shoreline.is_water_ext((pa.x + pb.x) * 0.5, (pa.z + pb.z) * 0.5):
			# over water: a steel weir / channel rail on piles
			m.pitched_box_visual("steel_rail", pa + Vector3(0, 1.3, 0), pb + Vector3(0, 1.3, 0), 0.12, 0.12, Vector3.ZERO)
			m.pitched_box_visual("steel_rail", pa + Vector3(0, 0.6, 0), pb + Vector3(0, 0.6, 0), 0.08, 0.08, Vector3.ZERO)
			m.box("concrete_bridge", (pa + pb) * 0.5 + Vector3(0, -1.2, 0), Vector3(0.8, 3.2, 0.8))
		else:
			m.pitched_box_visual("hoarding", pa, pb, 0.18, 2.7, Vector3(0, 1.35, 0))
			m.pitched_box_visual("hoarding_band", pa, pb, 0.2, 0.3, Vector3(0, 2.55, 0))
			m.pitched_box_visual("hoarding_band", pa, pb, 0.2, 0.18, Vector3(0, 0.12, 0))
			m.post(pa, 2.9)
		m.pitched_box(pa, pb, 0.4, 3.0, Vector3(0, 1.5, 0))

static func _edges(m) -> void:
	var r := DowntownPlan.PLAYABLE
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	_hoarding(m, Vector3(x0, 0, z0), Vector3(x0, 0, z1))
	_hoarding(m, Vector3(x1, 0, z0), Vector3(x1, 0, z1))
	_hoarding(m, Vector3(x0, 0, z0), Vector3(x1, 0, z0))
	# z = 375: the existing boundary railing line, extended both ways
	for side: float in [-1.0, 1.0]:
		var x := 367.5 * side + 15.0 * side
		while (side < 0.0 and x > x0) or (side > 0.0 and x < x1):
			var p := Vector3(x, 0.1, z1)
			if Shoreline.is_water_ext(x, z1 - 2.0):
				_hoarding(m, Vector3(x - 7.5, 0, z1), Vector3(x + 7.5, 0, z1))
			else:
				m.world._authored("boundary_railing.glb", p)
				m.col_box(Vector3(15.0, 2.4, 0.25), p + Vector3(0, 1.2, 0))
			x += 15.0 * side
	# site signs on the hoardings at the road ends
	for sign: Array in [[Vector3(x0 + 0.15, 2.0, -360.0), PI * 0.5, "STAMFORD ROAD - ROAD CLOSED"], [Vector3(x0 + 0.15, 2.0, 0.0), PI * 0.5, "BRAS BASAH WORKS - NO ENTRY"],
			[Vector3(x1 - 0.15, 2.0, -480.0), -PI * 0.5, "TANJONG PAGAR SITE WORKS"], [Vector3(x1 - 0.15, 2.0, -160.0), -PI * 0.5, "ROAD CLOSED AHEAD"],
			[Vector3(-10.0, 2.0, z0 + 0.15), 0.0, "GARDENS BY THE BAY - NO PUBLIC ACCESS"]]:
		var lbl := Label3D.new()
		lbl.text = sign[2]
		lbl.font_size = 72
		lbl.pixel_size = 0.014
		lbl.modulate = Color(0.97, 0.95, 0.9)
		lbl.outline_size = 0
		lbl.position = sign[0]
		lbl.rotation.y = sign[1]
		lbl.visibility_range_end = 200.0
		m.root.add_child(lbl)

static func _helipads(m) -> void:
	for key: String in DowntownPlan.HELIPADS:
		var pad: Dictionary = DowntownPlan.HELIPADS[key]
		if pad["status"] != "new":
			continue
		var pos: Vector3 = pad["pos"]
		var base_y := 0.1 if key == "ns_square" else 0.0
		m.world._helipad(Vector3(pos.x, base_y, pos.z), float(pad["radius"]))
		if not m.world.locations.has("helipad_" + key):
			m.world.locations["helipad_" + key] = Vector3(pos.x, base_y + 0.3, pos.z)

# ------------------------------------------------------------ background city
static func _tower_collision(m) -> void:
	for xf: Transform3D in m.kept_towers:
		var size := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length())
		m.col_box(size, xf.origin + Vector3(0, size.y * 0.5, 0), xf.basis.orthonormalized())
	# the authored glass towers of the east flank row (WorldBuilder._background_city)
	var freed := 0
	var collided := 0
	for child in m.world._world_root.get_children():
		if not child is Node3D or not String(child.scene_file_path).get_file().begins_with("skyline_"):
			continue
		var n3 := child as Node3D
		if not DowntownPlan.PLAYABLE.has_point(Vector2(n3.global_position.x, n3.global_position.z)):
			continue
		var aabb := _world_aabb(n3)
		var r := maxf(aabb.size.x, aabb.size.z) * 0.5
		var c := aabb.get_center()
		if not tower_ok(c.x, c.z, r):
			n3.queue_free()
			n3.visible = false
			freed += 1
			continue
		m.col_box(aabb.size, c)
		collided += 1
	m.stats["flank_towers_freed"] = freed
	m.stats["flank_towers_collided"] = collided

static func _world_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var q: Node = stack.pop_back()
		for ch in q.get_children():
			stack.append(ch)
		if q is MeshInstance3D and (q as MeshInstance3D).mesh != null:
			var mi := q as MeshInstance3D
			var a := mi.global_transform * mi.mesh.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
	return out

static func _rect_minus(r: Rect2, cut: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not r.intersects(cut):
		out.append(r)
		return out
	var i := r.intersection(cut)
	if i.position.y > r.position.y: out.append(Rect2(r.position.x, r.position.y, r.size.x, i.position.y - r.position.y))
	if i.end.y < r.end.y: out.append(Rect2(r.position.x, i.end.y, r.size.x, r.end.y - i.end.y))
	if i.position.x > r.position.x: out.append(Rect2(r.position.x, i.position.y, i.position.x - r.position.x, i.size.y))
	if i.end.x < r.end.x: out.append(Rect2(i.end.x, i.position.y, r.end.x - i.end.x, i.size.y))
	return out

static func _cut_background(m) -> void:
	var cutters: Array[Rect2] = [DowntownPlan.PLAYABLE]
	cutters.append_array(Shoreline.water_rects())
	var carpets := 0
	var walls := 0
	for child in m.world._world_root.get_children():
		if not child is MeshInstance3D:
			continue
		var mi := child as MeshInstance3D
		var sm := mi.material_override as ShaderMaterial
		if mi.name.begins_with("SkylineSeawall") or String(mi.name).contains("SkylineSeawall"):
			if absf(mi.position.x) < 900.0:
				mi.visible = false
				walls += 1
			continue
		if sm == null or sm.shader == null or not sm.shader.resource_path.ends_with(CARPET_SHADER):
			continue
		var pm := mi.mesh as PlaneMesh
		if pm == null:
			continue
		var r := Rect2(mi.position.x - pm.size.x * 0.5, mi.position.z - pm.size.y * 0.5, pm.size.x, pm.size.y)
		var hit := false
		for c: Rect2 in cutters:
			if r.intersects(c):
				hit = true
		if not hit:
			continue
		var pieces: Array[Rect2] = [r]
		for c2: Rect2 in cutters:
			var next: Array[Rect2] = []
			for pr: Rect2 in pieces:
				next.append_array(_rect_minus(pr, c2))
			pieces = next
		mi.visible = false
		carpets += 1
		for pr2: Rect2 in pieces:
			if pr2.size.x < 1.0 or pr2.size.y < 1.0:
				continue
			var np := MeshInstance3D.new()
			np.name = "SkylineCarpetCut"
			var plane := PlaneMesh.new()
			plane.size = pr2.size
			plane.subdivide_width = int(pr2.size.x / 400.0)
			plane.subdivide_depth = int(pr2.size.y / 400.0)
			np.mesh = plane
			np.material_override = sm
			np.position = Vector3(pr2.get_center().x, mi.position.y, pr2.get_center().y)
			np.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.world._world_root.add_child(np)
	# promenade rain trees of the old far shore: drop any standing in the
	# channel / lobe or on a downtown road, bridge or walk
	var dropped := 0
	var expect: int = int(m.world.skyline_stats.get("promenade_trees", -1))
	for child2 in m.world._world_root.get_children():
		if not child2 is MultiMeshInstance3D or child2.has_meta("downtown_map"):
			continue
		var mm := (child2 as MultiMeshInstance3D).multimesh
		if mm == null or mm.instance_count != expect or expect <= 0:
			continue
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			var p := xf.origin
			if Shoreline.is_water_ext(p.x, p.z) or Roads.on_road(p.x, p.z, "", 6.0) or Bridges.height_at(p.x, p.z) > 0.0 or _on_walk(p.x, p.z, 1.0):
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), p - Vector3(0, 50, 0)))
				dropped += 1
	m.stats["carpets_cut"] = carpets
	m.stats["flank_walls_hidden"] = walls
	m.stats["promenade_tree_parts_dropped"] = dropped
