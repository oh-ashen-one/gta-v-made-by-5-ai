class_name AerialFill
extends RefCounted
## Aerial ground fill (aerial piece, Opus 5.5 wave R).
##
## Helicopter-P2 judge: "from 100-150 m the city reads as a miniature: bare
## flat ground larger than a city block". The block interiors between the
## authored buildings were hard-standing slabs, which from the air read as one
## tan field. After the whole district is built, this pass rasterises
## everything that stands on the ground (meshes, multimesh instances,
## collision volumes, roads, service lanes, pedestrian lanes, parked cars and
## mission locations) into a 4 m occupancy grid, and fills every left-over
## open patch with landscape the way a real Singapore block is planted:
##  - a planted ground cover (lawn, shrub beds, worn paths; world-space shader);
##  - dense tropical canopy trees (procedural clumped crowns, a few flowering
##    flame/trumpet trees), one MultiMesh draw per part, trunk collision only;
##  - low shrub mounds along the patch edges.
## Everything is generated here (original geometry and shaders, no imported
## assets) and costs a handful of draws.

const CELL := 4.0
const X0 := -376.0
const Z0 := -332.0
const NX := 188
const NZ := 177
const SURFACE_Y := 0.245
const GROUND_SHADER := "res://assets/authored/shaders/aerial_ground_cover.gdshader"
const CANOPY_SHADER := "res://assets/authored/shaders/aerial_canopy.gdshader"
## Occupancy code for small props (ferns, bollards, planters): ground cover
## may run under them, trees may not.
const SOFT := 10
const BLOCK_CENTRES := [-240.0, -80.0, 80.0, 240.0]
const ROAD_LINES := [-320.0, -160.0, 0.0, 160.0, 320.0]

static var stats := {}

var _occ := PackedByteArray()      # 0 free, 1 blocked
var _rng := RandomNumberGenerator.new()

static func build(world: Node, root: Node3D) -> Dictionary:
	var f := AerialFill.new()
	return f._build(world, root)

func _idx(i: int, j: int) -> int:
	return j * NX + i

func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - X0) / CELL)), int(floor((z - Z0) / CELL)))

func _centre(i: int, j: int) -> Vector3:
	var x := X0 + (i + 0.5) * CELL
	var z := Z0 + (j + 0.5) * CELL
	return Vector3(x, _surface_y(x, z), z)

## Block platforms carry their plots at ~0.22 m; the outer verge ring is the
## base ground at 0.
static func _surface_y(x: float, z: float) -> float:
	for cx: float in BLOCK_CENTRES:
		for cz: float in BLOCK_CENTRES:
			if absf(x - cx) < 72.0 and absf(z - cz) < 72.0:
				return SURFACE_Y
	return 0.05

var _reason := 2
var _debug := Lighting._arg("--aerial-fill-debug", "") != ""

func _block_rect(x0: float, z0: float, x1: float, z1: float) -> void:
	var a := _cell_of(x0, z0)
	var b := _cell_of(x1, z1)
	for j in range(maxi(a.y, 0), mini(b.y, NZ - 1) + 1):
		for i in range(maxi(a.x, 0), mini(b.x, NX - 1) + 1):
			var cur := _occ[_idx(i, j)]
			if cur == 0 or (cur == SOFT and _reason != SOFT):
				_occ[_idx(i, j)] = _reason

func _block_aabb(box: AABB, pad: float) -> void:
	if box.size.x > 400.0 or box.size.z > 400.0:
		return
	# Flat ground slabs (pavers, lawns, paint) are what we fill over.
	if box.end.y < 0.42 and box.size.y < 0.35:
		return
	if box.position.y > 30.0:
		return
	if box.size.x * box.size.z < 9.0 and box.end.y < 3.2 and _reason != 5:
		var keep := _reason
		_reason = SOFT
		_block_rect(box.position.x, box.position.z, box.end.x, box.end.z)
		_reason = keep
		return
	_block_rect(box.position.x - pad, box.position.z - pad, box.end.x + pad, box.end.z + pad)

func _block_vertices(mi: MeshInstance3D) -> void:
	var gt := mi.global_transform
	# Low plinths / landscaping baked into imported models do not count.
	var floor_y := gt.origin.y + 1.2
	for surf in mi.mesh.get_surface_count():
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]
		var stride := maxi(1, verts.size() / 1500)
		var k := 0
		while k < verts.size():
			var w := gt * verts[k]
			k += stride
			if w.y < floor_y or w.y > 30.0:
				continue
			var c := _cell_of(w.x, w.z)
			if c.x >= 0 and c.y >= 0 and c.x < NX and c.y < NZ:
				var cur := _occ[_idx(c.x, c.y)]
				if cur == 0 or cur == SOFT:
					_occ[_idx(c.x, c.y)] = _reason

func _block_disc(p: Vector3, r: float) -> void:
	_block_rect(p.x - r, p.z - r, p.x + r, p.z + r)

func _block_segment(a: Vector3, b: Vector3, r: float) -> void:
	var n := int(ceil(a.distance_to(b) / (CELL * 0.5))) + 1
	for k in n + 1:
		var p := a.lerp(b, float(k) / float(maxi(n, 1)))
		_block_disc(p, r)

func _build(world: Node, root: Node3D) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	_rng.seed = 77031
	_occ.resize(NX * NZ)
	_occ.fill(1)
	# Candidates: the walkable district inside the boundary railings (the
	# block platforms and the outer verge ring). Cross service lanes stay open.
	for j in NZ:
		for i in NX:
			var c := _centre(i, j)
			if absf(c.x) > 371.0 or c.z < -326.0 or c.z > 371.0:
				continue
			var lane := false
			for cx: float in BLOCK_CENTRES:
				for cz: float in BLOCK_CENTRES:
					if absf(c.x - cx) < 72.0 and absf(c.z - cz) < 72.0 and (absf(c.x - cx) < 5.5 or absf(c.z - cz) < 5.5):
						lane = true
			if not lane:
				_occ[_idx(i, j)] = 0
	# Road corridors (carriageway + kerb + verge trees).
	for r: float in ROAD_LINES:
		_block_rect(r - 12.5, -400.0, r + 12.5, 400.0)
		_block_rect(-400.0, r - 12.5, 400.0, r + 12.5)
	# Everything that stands on the ground.
	_reason = 3
	var stack: Array[Node] = [root]
	var meshes := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			_reason = 3
			var mi := node as MeshInstance3D
			if mi.mesh != null and mi.is_inside_tree():
				var gb := mi.global_transform * mi.get_aabb()
				if gb.size.x * gb.size.z > 400.0 and gb.size.x < 400.0 and gb.size.z < 400.0 and mi.mesh is ArrayMesh:
					# Big imported models (HDB slabs, pavilions, landmarks) have
					# loose bounds: rasterise a sample of their real vertices.
					_block_vertices(mi)
				else:
					_block_aabb(gb, 0.8)
				meshes += 1
		elif node is MultiMeshInstance3D:
			var mmi := node as MultiMeshInstance3D
			var mm := mmi.multimesh
			_reason = 4
			if mm != null and mm.mesh != null and mmi.is_inside_tree() and mm.transform_format == MultiMesh.TRANSFORM_3D:
				var local := mm.mesh.get_aabb()
				var gt := mmi.global_transform
				for k in mm.instance_count:
					_block_aabb(gt * mm.get_instance_transform(k) * local, 0.8)
		elif node is CollisionShape3D:
			_reason = 5
			var cs := node as CollisionShape3D
			if cs.shape == null or not cs.is_inside_tree():
				continue
			var ext := Vector3.ZERO
			if cs.shape is BoxShape3D:
				ext = (cs.shape as BoxShape3D).size
			elif cs.shape is CylinderShape3D:
				var cy := cs.shape as CylinderShape3D
				ext = Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0)
			else:
				continue
			_block_aabb(cs.global_transform * AABB(-ext * 0.5, ext), 0.8)
	# Gameplay: mission locations, parked cars, pedestrian and traffic lanes.
	_reason = 6
	var locations: Dictionary = world.get("locations")
	for key in locations:
		var v = locations[key]
		if v is Vector3:
			var r := 12.0
			if String(key) in ["supertree_grove"]:
				r = 30.0
			elif String(key).begins_with("helipad"):
				r = 26.0
			_block_disc(v, r)
	_reason = 7
	for spot in world.get("parked_spots"):
		_block_disc(spot["pos"], 6.0)
	_reason = 8
	for lane in world.get("ped_lanes"):
		for k in range(lane.size() - 1):
			_block_segment(lane[k], lane[k + 1], 2.5)
	_reason = 9
	for node_pos in world.get("traffic_nodes"):
		_block_disc(node_pos, 6.0)
	_debug_dump()
	var free := 0
	for v in _occ:
		if v == 0 or v == SOFT:
			free += 1
	var ground := _ground_cover(root)
	var trees := _trees(root)
	stats = {"ms": Time.get_ticks_msec() - t0, "cells": free, "area_m2": free * CELL * CELL, "trees": trees["trees"], "flowering": trees["flowering"], "shrubs": trees["shrubs"], "ground_quads": ground, "scanned_meshes": meshes}
	print("[world] aerial fill: ", stats)
	return stats

## `--aerial-fill-debug=ABS.png` writes the occupancy grid (QA only):
## green free, grey outside blocks, dark road, blue mesh, cyan multimesh,
## yellow collision, red locations, magenta parked, orange ped lanes.
func _debug_dump() -> void:
	var path := Lighting._arg("--aerial-fill-debug", "")
	if path == "":
		return
	var cols := [Color(0.2, 0.8, 0.2), Color(0.5, 0.5, 0.5), Color(0.15, 0.15, 0.15), Color(0.2, 0.3, 0.9), Color(0.2, 0.9, 0.9), Color(0.9, 0.9, 0.2), Color(0.9, 0.1, 0.1), Color(0.9, 0.2, 0.9), Color(1.0, 0.6, 0.1), Color(0.6, 0.3, 0.1)]
	var img := Image.create(NX, NZ, false, Image.FORMAT_RGB8)
	for j in NZ:
		for i in NX:
			img.set_pixel(i, j, Color(0.6, 0.9, 0.4) if _occ[_idx(i, j)] == SOFT else cols[clampi(_occ[_idx(i, j)], 0, 9)])
	img.save_png(path)

func _free(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < NX and j < NZ and _occ[_idx(i, j)] == 0

func _coverable(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < NX and j < NZ and (_occ[_idx(i, j)] == 0 or _occ[_idx(i, j)] == SOFT)

func _clearance(i: int, j: int, r: int) -> bool:
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			if not _free(i + di, j + dj):
				return false
	return true

# ------------------------------------------------------------ ground cover
func _ground_cover(root: Node3D) -> int:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for j in NZ:
		var i := 0
		while i < NX:
			if not _coverable(i, j):
				i += 1
				continue
			var i_end := i
			var y := _centre(i, j).y
			while i_end + 1 < NX and _coverable(i_end + 1, j) and absf(_centre(i_end + 1, j).y - y) < 0.01:
				i_end += 1
			# One quad per free run (merged along x), slightly inset at patch
			# ends so the edge reads as a kerbed bed rather than a hard seam.
			var x0 := X0 + i * CELL + 0.3
			var x1 := X0 + (i_end + 1) * CELL - 0.3
			var z0 := Z0 + j * CELL
			var z1 := Z0 + (j + 1) * CELL
			if not _coverable(i, j - 1):
				z0 += 0.3
			if not _coverable(i, j + 1):
				z1 -= 0.3
			st.set_normal(Vector3.UP)
			for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
				st.set_uv(Vector2(p.x, p.z))
				st.add_vertex(p)
			quads += 1
			i = i_end + 1
	if quads == 0:
		return 0
	st.index()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "AerialGroundCover"
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load(GROUND_SHADER)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("aerial_fill", true)   # keeps it out of static batching
	root.add_child(mi)
	return quads

# ------------------------------------------------------------ canopy trees
## A clumped tropical crown: several displaced icospheres around a trunk.
static func canopy_mesh(seed_value: int, shrub: bool = false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ico := _icosphere()
	var ico_low := _icosphere(false)
	var crown_y := 0.9 if shrub else rng.randf_range(5.6, 7.0)
	var spread := 1.6 if shrub else rng.randf_range(3.6, 4.6)
	var blobs: Array = []
	if shrub:
		blobs.append([Vector3(0, 0.55, 0), 1.25])
		for k in 3:
			var a := TAU * k / 3.0 + rng.randf()
			blobs.append([Vector3(cos(a) * 0.9, 0.45, sin(a) * 0.9), rng.randf_range(0.7, 0.95)])
	else:
		blobs.append([Vector3(0, crown_y + 0.6, 0), spread * 0.62])
		var n := rng.randi_range(5, 7)
		for k in n:
			var a := TAU * k / n + rng.randf_range(-0.3, 0.3)
			var rr := spread * rng.randf_range(0.5, 0.72)
			blobs.append([Vector3(cos(a) * rr, crown_y + rng.randf_range(-0.7, 0.6), sin(a) * rr), spread * rng.randf_range(0.36, 0.52)])
		# Small outer sprigs break the round silhouette.
		for k in rng.randi_range(4, 6):
			var a3 := rng.randf() * TAU
			var rr3 := spread * rng.randf_range(0.8, 1.0)
			blobs.append([Vector3(cos(a3) * rr3, crown_y + rng.randf_range(-0.9, 0.9), sin(a3) * rr3), spread * rng.randf_range(0.2, 0.3), true])
		for k in 2:
			var a2 := rng.randf() * TAU
			blobs.append([Vector3(cos(a2) * spread * 0.25, crown_y + 1.5, sin(a2) * spread * 0.25), spread * 0.4])
	for b in blobs:
		var c: Vector3 = b[0]
		var r: float = b[1]
		var off := rng.randf() * 100.0
		for tri in (ico_low if b.size() > 2 else ico):
			for v: Vector3 in tri:
				var d := sin(v.x * 5.1 + off) * sin(v.y * 4.3 + off * 0.7) * sin(v.z * 4.7 + off * 1.3) + 0.5 * sin(v.x * 11.3 - off) * sin(v.z * 9.7 + off)
				var rad := r * (1.0 + 0.16 * d)
				var p := c + Vector3(v.x * rad, v.y * rad * 0.78, v.z * rad)
				# Vertex colour: ambient occlusion (dark underside / inner crown).
				var ao := clampf(0.42 + 0.58 * (v.y * 0.5 + 0.5), 0.0, 1.0)
				ao *= clampf(0.65 + 0.35 * (Vector2(p.x, p.z).length() / (spread + 0.01)) + 0.25 * (1.0 if shrub else 0.0), 0.0, 1.0)
				st.set_color(Color(ao, ao, ao, 1.0))
				st.set_normal(v.normalized())
				st.add_vertex(p)
	if not shrub:
		# Trunk + two limbs, coloured as bark through vertex alpha = 0.
		_cyl(st, Vector3.ZERO, Vector3(0, crown_y, 0), 0.32, 0.2)
		_cyl(st, Vector3(0, crown_y * 0.6, 0), Vector3(spread * 0.45, crown_y + 0.3, 0.3), 0.16, 0.08)
		_cyl(st, Vector3(0, crown_y * 0.65, 0), Vector3(-spread * 0.35, crown_y + 0.2, -spread * 0.3), 0.15, 0.08)
	return st.commit()

static func _cyl(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := axis.cross(side).normalized()
	var seg := 6
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var n0 := side * cos(a0) + up * sin(a0)
		var n1 := side * cos(a1) + up * sin(a1)
		var quad := [[a + n0 * r0, n0], [b + n1 * r1, n1], [a + n1 * r0, n1], [a + n0 * r0, n0], [b + n0 * r1, n0], [b + n1 * r1, n1]]
		for q in quad:
			st.set_color(Color(0.6, 0.6, 0.6, 0.0))
			st.set_normal(q[1])
			st.add_vertex(q[0])

static func _icosphere(subdivide: bool = true) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for k in v.size():
		v[k] = (v[k] as Vector3).normalized()
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var tris: Array = []
	for face in f:
		var a: Vector3 = v[face[0]]
		var b: Vector3 = v[face[1]]
		var c: Vector3 = v[face[2]]
		if not subdivide:
			tris.append([a, c, b])
			continue
		var ab := ((a + b) * 0.5).normalized()
		var bc := ((b + c) * 0.5).normalized()
		var ca := ((c + a) * 0.5).normalized()
		# Godot front faces are clockwise seen from outside.
		tris.append([a, ca, ab])
		tris.append([b, ab, bc])
		tris.append([c, bc, ca])
		tris.append([ab, ca, bc])
	return tris

func _trees(root: Node3D) -> Dictionary:
	var variants := 3
	var tree_xf: Array = []
	for k in variants:
		tree_xf.append([])
	var shrub_xf: Array = []
	var placed: Array[Vector3] = []
	var flowering := 0
	var body := StaticBody3D.new()
	body.name = "AerialFillTrunks"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var order: Array[int] = []
	for k in NX * NZ:
		if _occ[k] == 0:
			order.append(k)
	# deterministic shuffle
	for k in range(order.size() - 1, 0, -1):
		var s := _rng.randi_range(0, k)
		var tmp := order[k]
		order[k] = order[s]
		order[s] = tmp
	var grid := {}
	for k in order:
		var i := k % NX
		var j := k / NX
		var big := _clearance(i, j, 2)
		if not big and not _clearance(i, j, 1):
			# Narrow strip: a shrub mound now and then.
			if _rng.randf() < 0.35:
				var sp := _centre(i, j) + Vector3(_rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(-1.2, 1.2))
				shrub_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.2)), sp))
			continue
		var p := _centre(i, j) + Vector3(_rng.randf_range(-1.4, 1.4), 0.0, _rng.randf_range(-1.4, 1.4))
		var scale := _rng.randf_range(0.95, 1.35) if big else _rng.randf_range(0.6, 0.8)
		var min_gap := 7.2 * scale
		var key := Vector2i(int(p.x / 10.0), int(p.z / 10.0))
		var ok := true
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for q: Vector3 in grid.get(key + Vector2i(dx, dz), []):
					if Vector2(q.x - p.x, q.z - p.z).length() < min_gap:
						ok = false
		if not ok:
			if _rng.randf() < 0.18:
				shrub_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.4)), p))
			continue
		if not grid.has(key):
			grid[key] = []
		grid[key].append(p)
		placed.append(p)
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(scale, scale * _rng.randf_range(0.88, 1.12), scale)), p)
		var colour := _rng.randf()
		var flower := colour > 0.955
		if flower:
			flowering += 1
		tree_xf[_rng.randi_range(0, variants - 1)].append([xf, Color(colour, _rng.randf(), 0.0, 0.0)])
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.38 * scale
		cyl.height = 5.0 * scale
		shape.shape = cyl
		shape.position = p + Vector3(0.0, 2.5 * scale, 0.0)
		body.add_child(shape)
	var mat := ShaderMaterial.new()
	mat.shader = load(CANOPY_SHADER)
	for v in variants:
		_emit(root, canopy_mesh(9100 + v * 17), tree_xf[v], mat, true, "AerialFillTrees%d" % v)
	var shrub_items: Array = []
	for xf: Transform3D in shrub_xf:
		shrub_items.append([xf, Color(_rng.randf() * 0.92, _rng.randf(), 1.0, 0.0)])
	_emit(root, canopy_mesh(9301, true), shrub_items, mat, false, "AerialFillShrubs")
	return {"trees": placed.size(), "flowering": flowering, "shrubs": shrub_xf.size()}

## Emits one MultiMesh per ~190 m tile so frustum culling (camera and every
## shadow cascade) skips tiles out of view instead of drawing every tree.
func _emit(root: Node3D, mesh: Mesh, items: Array, mat: Material, shadows: bool, label: String) -> void:
	if items.is_empty():
		return
	var tiles := {}
	for it in items:
		var o: Vector3 = (it[0] as Transform3D).origin
		var key := Vector2i(int(floor((o.x + 380.0) / 190.0)), int(floor((o.z + 340.0) / 190.0)))
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(it)
	for key in tiles:
		var list: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k][0])
			mm.set_instance_custom_data(k, list[k][1])
		var inst := MultiMeshInstance3D.new()
		inst.name = "%s_%d_%d" % [label, key.x, key.y]
		inst.multimesh = mm
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Shrub mounds vanish past 450 m; crowns stay (the aerial views need them).
		if not shadows:
			inst.visibility_range_end = 450.0
			inst.visibility_range_end_margin = 40.0
		root.add_child(inst)
