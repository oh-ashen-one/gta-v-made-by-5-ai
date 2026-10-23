extends RefCounted
## downtown-fill (wave T): aerial land density between the water and the
## skyline, plus capture views (fill_capture.gd).
##
## Critic gap (wave S): "from ~110 m the land between the water and the
## skyline reads as a scale model - flat evenly coloured lawn, sparse identical
## lollipop trees". After every downtown piece has built, this:
##   - rasterises every downtown lawn surface (the shared DowntownLawn
##     material, from map / landmarks / blocks) onto a 2 m grid;
##   - rasterises every collision volume that stands on the ground (buildings,
##     supertrees, domes, existing tree trunks) as keep-out;
##   - plants a park canopy on the lawns: groves of mixed species (rain tree,
##     angsana, tembusu, flowering flame tree) and shrub masses along the grove
##     edges, separated by glades no wider than ~40 m, from a world-space
##     density field so it never reads as a regular orchard;
##   - stays clear of helipads, paths' edges (lawn margins) and the keep-out.
## `--fill-off` skips all of it (A/B against wave S).

const Canopy := preload("res://src/world/downtown/canopy.gd")
const Roofs := preload("res://src/world/downtown/roofs.gd")
const Plazas := preload("res://src/world/downtown/plazas.gd")
const G := 2.0
const ORIGIN := Vector2(-920.0, -1080.0)
const W := 860   # cells along x (1720 m)
const H := 740   # cells along z (1480 m)

static func finish(world: WorldBuilder, root: Node3D) -> Dictionary:
	var stats := {}
	var t0 := Time.get_ticks_msec()
	if not DowntownLawn.off():
		var holder := Node3D.new()
		holder.name = "DowntownFill"
		root.add_child(holder)
		var keep := _keepout(world)
		Plazas.set_slabs(_slabs)
		stats["plazas"] = Plazas.build(world, holder)
		stats["park_panels"] = _park_panels(holder, keep)
		var lawn := _lawn_raster(world)
		stats["lawn_cells"] = lawn[1]
		stats["canopy"] = _plant(holder, lawn[0], lawn[2], keep)
		stats["lawn_blocks"] = stats["canopy"].get("lawn_blocks", 0)
		stats["empty_lawn_blocks"] = stats["canopy"].get("empty_lawn_blocks", -1)
		stats["roofs"] = Roofs.build(world, holder)
	stats["ms"] = Time.get_ticks_msec() - t0
	print("[downtown-fill] %s" % JSON.stringify(stats))
	if "--fill-photos" in OS.get_cmdline_user_args():
		var cap: Node = load("res://src/world/downtown/fill_capture.gd").new()
		cap.name = "FillCapture"
		world.add_child(cap)
	return stats

static func _idx(x: float, z: float) -> int:
	var cx := int(floor((x - ORIGIN.x) / G))
	var cz := int(floor((z - ORIGIN.y) / G))
	if cx < 0 or cz < 0 or cx >= W or cz >= H:
		return -1
	return cz * W + cx

## Lawn raster: 1 where an upward lawn triangle covers the cell centre; the
## height of the lawn is kept per cell.
static func _lawn_raster(world: WorldBuilder) -> Array:
	var grid := PackedByteArray()
	grid.resize(W * H)
	var hgt := PackedFloat32Array()
	hgt.resize(W * H)
	var lawn := DowntownLawn.material()
	var count := 0
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mesh: Mesh = null
		var xfs: Array[Transform3D] = []
		var override: Material = null
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
			override = (node as MeshInstance3D).material_override
			xfs.append((node as Node3D).global_transform)
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var mm := (node as MultiMeshInstance3D).multimesh
			if mm.transform_format != MultiMesh.TRANSFORM_3D or mm.instance_count > 64:
				continue
			mesh = mm.mesh
			override = (node as MultiMeshInstance3D).material_override
			for i in mm.instance_count:
				xfs.append((node as Node3D).global_transform * mm.get_instance_transform(i))
		if mesh == null or not mesh is ArrayMesh:
			continue
		for s in mesh.get_surface_count():
			var m: Material = override if override != null else mesh.surface_get_material(s)
			if m != lawn:
				continue
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var ntri := (idx.size() if idx.size() > 0 else verts.size()) / 3
			for xf in xfs:
				for t in ntri:
					var a := xf * verts[idx[t * 3] if idx.size() > 0 else t * 3]
					var b := xf * verts[idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1]
					var c := xf * verts[idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2]
					var n := (b - a).cross(c - a)
					if n.length() < 0.01 or absf(n.normalized().y) < 0.9:
						continue
					count += _raster_tri(grid, hgt, a, b, c)
	return [grid, count, hgt]

static func _raster_tri(grid: PackedByteArray, hgt: PackedFloat32Array, a: Vector3, b: Vector3, c: Vector3) -> int:
	var minx := minf(a.x, minf(b.x, c.x))
	var maxx := maxf(a.x, maxf(b.x, c.x))
	var minz := minf(a.z, minf(b.z, c.z))
	var maxz := maxf(a.z, maxf(b.z, c.z))
	var n := 0
	var cx0 := int(floor((minx - ORIGIN.x) / G))
	var cx1 := int(floor((maxx - ORIGIN.x) / G))
	var cz0 := int(floor((minz - ORIGIN.y) / G))
	var cz1 := int(floor((maxz - ORIGIN.y) / G))
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var c2 := Vector2(c.x, c.z)
	var den := (b2 - a2).cross(c2 - a2)
	if absf(den) < 0.0001:
		return 0
	for cz in range(maxi(cz0, 0), mini(cz1, H - 1) + 1):
		for cx in range(maxi(cx0, 0), mini(cx1, W - 1) + 1):
			var p := Vector2(ORIGIN.x + (cx + 0.5) * G, ORIGIN.y + (cz + 0.5) * G)
			# barycentric via signed areas (sign-agnostic)
			var w1 := ((b2 - p).cross(c2 - p)) / den
			var w2 := ((c2 - p).cross(a2 - p)) / den
			var w3 := 1.0 - w1 - w2
			if w1 < -0.001 or w2 < -0.001 or w3 < -0.001:
				continue
			var i := cz * W + cx
			if grid[i] == 0:
				n += 1
			grid[i] = 1
			hgt[i] = maxf(hgt[i], a.y * w1 + b.y * w2 + c.y * w3)
	return n

## Keep-out raster from every collision volume standing on the ground
## (buildings, landmark structures, supertrees, existing tree trunks).
static var _slabs: Array = []

static func _keepout(world: WorldBuilder) -> PackedByteArray:
	_slabs = []
	var grid := PackedByteArray()
	grid.resize(W * H)
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not node is CollisionShape3D:
			continue
		var cs := node as CollisionShape3D
		if cs.shape == null or not cs.is_inside_tree():
			continue
		var xf := cs.global_transform
		var aabb := AABB()
		var margin := 3.0
		if cs.shape is BoxShape3D:
			var sz := (cs.shape as BoxShape3D).size
			aabb = xf * AABB(-sz * 0.5, sz)
		elif cs.shape is CylinderShape3D:
			var cy := cs.shape as CylinderShape3D
			aabb = xf * AABB(Vector3(-cy.radius, -cy.height * 0.5, -cy.radius), Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0))
			margin = 5.0   # an existing tree's crown
		elif cs.shape is CapsuleShape3D or cs.shape is SphereShape3D:
			continue
		elif cs.shape is ConcavePolygonShape3D or cs.shape is ConvexPolygonShape3D:
			var faces: PackedVector3Array = (cs.shape as ConcavePolygonShape3D).get_faces() if cs.shape is ConcavePolygonShape3D else (cs.shape as ConvexPolygonShape3D).points
			if faces.is_empty():
				continue
			aabb = AABB(xf * faces[0], Vector3.ZERO)
			for f in faces:
				aabb = aabb.expand(xf * f)
		else:
			continue
		# flat walkable slabs (plazas, decks, terraces) give the plaza props
		# their ground height
		if cs.shape is BoxShape3D and aabb.end.y > -0.5 and aabb.end.y < 2.2 and aabb.size.x >= 8.0 and aabb.size.z >= 8.0 and absf(xf.basis.y.normalized().y) > 0.995:
			_slabs.append(aabb)
		# ground-standing and taller than a kerb / slab; never the drive
		# surface trimesh or a whole-site ground slab
		if aabb.end.y < 0.9 or aabb.position.y > 4.0 or aabb.size.x > 280.0 or aabb.size.z > 280.0:
			continue
		var cx0 := int(floor((aabb.position.x - margin - ORIGIN.x) / G))
		var cx1 := int(floor((aabb.end.x + margin - ORIGIN.x) / G))
		var cz0 := int(floor((aabb.position.z - margin - ORIGIN.y) / G))
		var cz1 := int(floor((aabb.end.z + margin - ORIGIN.y) / G))
		for cz in range(maxi(cz0, 0), mini(cz1, H - 1) + 1):
			for cx in range(maxi(cx0, 0), mini(cx1, W - 1) + 1):
				grid[cz * W + cx] = 1
	return grid

## The Flyer forecourt (one 280 x 200 m granite slab) becomes a park of lawn
## panels between paved walks; the canopy pass then plants it. Panels only go
## where nothing stands (keep-out raster) and clear of the Flyer terminal.
static func _park_panels(holder: Node3D, keep: PackedByteArray) -> int:
	var site := DowntownPlan.block_rect("flyer_site")
	var flyer: Vector3 = DowntownPlan.anchor("singapore_flyer")
	var kit := preload("res://src/world/downtown/landmarks/kit.gd").new()
	var lawn := DowntownLawn.material()
	var edge := preload("res://src/world/downtown/landmarks/looks.gd").get_mat("granite_light")
	var n := 0
	const P := 24.0
	const WALK := 5.0
	var y := Plazas.ground_y(site.get_center().x, site.get_center().y, 0.34)
	var x := site.position.x + 8.0
	while x + P - WALK <= site.end.x - 8.0:
		var z := site.position.y + 8.0
		while z + P - WALK <= site.end.y - 8.0:
			var r := Rect2(x, z, P - WALK, P - WALK)
			var ok := Vector2(r.get_center().x - flyer.x, r.get_center().y - flyer.z).length() > 70.0
			var cz := r.position.y
			while ok and cz <= r.end.y:
				var cx := r.position.x
				while cx <= r.end.x:
					var i := _idx(cx, cz)
					if i < 0 or keep[i] == 1:
						ok = false
						break
					cx += G
				cz += G
			if ok:
				var c := r.get_center()
				kit.box(edge, Vector3(c.x, y + 0.05, c.y), Vector3(r.size.x + 0.5, 0.1, r.size.y + 0.5))
				kit.quad(lawn, Vector3(r.position.x, y + 0.11, r.end.y), Vector3(r.end.x, y + 0.11, r.end.y), Vector3(r.end.x, y + 0.11, r.position.y), Vector3(r.position.x, y + 0.11, r.position.y))
				n += 1
			z += P
		x += P
	if n > 0:
		kit.commit(holder, "DowntownFlyerPark", false, 0.0)
	return n

static func _lawn_at(lawn: PackedByteArray, x: float, z: float) -> bool:
	var i := _idx(x, z)
	return i >= 0 and lawn[i] == 1

static func _noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = 6071
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0 / 55.0
	n.fractal_octaves = 3
	return n

static func _plant(holder: Node3D, lawn: PackedByteArray, hgt: PackedFloat32Array, keep: PackedByteArray) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var dens := _noise()
	var spn := FastNoiseLite.new()
	spn.seed = 811
	spn.frequency = 1.0 / 38.0
	var items: Array = []
	var taken := {}
	var counts := {}
	const STEP := 6.0
	var nx := int(W * G / STEP)
	var nz := int(H * G / STEP)
	for gz in nz:
		for gx in nx:
			var x := ORIGIN.x + (gx + rng.randf_range(0.1, 0.9)) * STEP
			var z := ORIGIN.y + (gz + rng.randf_range(0.1, 0.9)) * STEP
			var i := _idx(x, z)
			if i < 0 or lawn[i] == 0 or keep[i] == 1:
				continue
			# deep in the lawn: no crown over a path, kerb or seawall
			var deep := 0
			for o: Vector2 in [Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5), Vector2(3.5, 3.5), Vector2(-3.5, -3.5)]:
				if _lawn_at(lawn, x + o.x, z + o.y):
					var j := _idx(x + o.x, z + o.y)
					if keep[j] == 0:
						deep += 1
			if deep < 6:
				# lawn margin: shrub masses only, sparsely
				if deep >= 3 and rng.randf() < 0.22:
					_add(items, counts, "shrub", Vector3(x, hgt[i], z), rng, 0.7, 1.2)
				continue
			var hp := false
			# the Supertree plazas stay open (the grove reads above the canopy)
			var g: Vector3 = DowntownPlan.anchor("gardens_supertree_grove")
			for gc: Vector3 in [g + Vector3(-54.0, 0, -14.0), g + Vector3(48.0, 0, 17.0), g]:
				if Vector2(gc.x - x, gc.z - z).length() < 40.0:
					hp = true
			for hk: String in DowntownPlan.HELIPADS:
				var pad: Vector3 = DowntownPlan.HELIPADS[hk]["pos"]
				if Vector2(pad.x - x, pad.z - z).length() < float(DowntownPlan.HELIPADS[hk]["radius"]) + 14.0:
					hp = true
					break
			if hp:
				continue
			var d := dens.get_noise_2d(x, z) * 0.5 + 0.5
			# glade cap: within any 40 m the field always rises above the grove
			# threshold somewhere, so no open lawn reads larger than a block
			var p := 0.0
			if d > 0.52:
				p = 0.92
			elif d > 0.44:
				p = 0.55
			elif d > 0.36:
				p = 0.18
			else:
				p = 0.06
			if rng.randf() > p:
				continue
			var key := Vector2i(int(x / 4.5), int(z / 4.5))
			if taken.has(key):
				continue
			taken[key] = true
			var s := spn.get_noise_2d(x, z) * 0.5 + 0.5
			var roll := rng.randf()
			var sp := "rain"
			if s < 0.32:
				sp = "angsana" if roll < 0.7 else "rain"
			elif s < 0.5:
				sp = "rain" if roll < 0.6 else "flame"
			elif s < 0.68:
				sp = "tembusu" if roll < 0.55 else "angsana"
			else:
				sp = "flame" if roll < 0.35 else "rain"
			if d < 0.44 and roll < 0.25:
				sp = "shrub"
			var sc := rng.randf_range(0.75, 1.2) if sp != "rain" else rng.randf_range(0.7, 1.05)
			_add(items, counts, sp, Vector3(x, hgt[i], z), rng, sc, sc)
			if d > 0.44 and d < 0.56 and rng.randf() < 0.35:
				# understorey shrubs on the grove edge
				_add(items, counts, "shrub", Vector3(x + rng.randf_range(-4, 4), hgt[i], z + rng.randf_range(-4, 4)), rng, 0.8, 1.3)
	# glade check: every 48 m cell that is (almost) all open lawn has trees
	var trees_in := {}
	for it in items:
		if it[0] == "shrub":
			continue
		var o: Vector3 = (it[1] as Transform3D).origin
		var ck := Vector2i(floori(o.x / 48.0), floori(o.z / 48.0))
		trees_in[ck] = int(trees_in.get(ck, 0)) + 1
	var lawn_blocks := 0
	var empty := 0
	var cx0 := floori(ORIGIN.x / 48.0)
	var cz0 := floori(ORIGIN.y / 48.0)
	for bz in range(cz0, cz0 + int(H * G / 48.0) + 1):
		for bx in range(cx0, cx0 + int(W * G / 48.0) + 1):
			var open_cells := 0
			var total := 0
			for sz in 24:
				for sx in 24:
					total += 1
					var j := _idx(bx * 48.0 + sx * 2.0 + 1.0, bz * 48.0 + sz * 2.0 + 1.0)
					if j >= 0 and lawn[j] == 1 and keep[j] == 0:
						open_cells += 1
			if open_cells >= total * 0.9:
				lawn_blocks += 1
				if int(trees_in.get(Vector2i(bx, bz), 0)) == 0:
					empty += 1
	counts["lawn_blocks"] = lawn_blocks
	counts["empty_lawn_blocks"] = empty
	counts["draws"] = Canopy.emit(holder, items, "DowntownCanopy")
	counts["total"] = items.size()
	return counts

static func _add(items: Array, counts: Dictionary, sp: String, p: Vector3, rng: RandomNumberGenerator, s0: float, s1: float) -> void:
	var s := rng.randf_range(s0, s1)
	var b := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(s * rng.randf_range(0.9, 1.1), s * rng.randf_range(0.85, 1.15), s * rng.randf_range(0.9, 1.1)))
	var tint := Color(rng.randf_range(0.82, 1.18), rng.randf_range(0.86, 1.14), rng.randf_range(0.8, 1.12), 0.0)
	if sp == "flame":
		tint.a = rng.randf_range(0.5, 1.0)
	elif sp in ["angsana", "rain"] and rng.randf() < 0.08:
		tint = Color(tint.r * 1.25, tint.g * 1.1, tint.b * 0.7, 0.0)   # a yellowing crown
	items.append([sp, Transform3D(b, p - Vector3(0, 0.05, 0)), tint])
	counts[sp] = int(counts.get(sp, 0)) + 1
