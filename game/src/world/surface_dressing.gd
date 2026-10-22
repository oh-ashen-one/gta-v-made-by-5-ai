class_name SurfaceDressing
extends RefCounted
## Wave B "materials": lived-in surface dressing applied after the district is
## built. Everything here is batched (one MultiMesh or one ArrayMesh per prop
## family), so the whole pass adds roughly a dozen draws.
##
## - grime multiply pass on imported shophouse / HDB modules and facade sheets
## - wall clutter: AC condensers on brackets, drain pipes, sagging cable runs
## - rooftop plant on generic roofs: condensers, tanks, vent and lift housings,
##   parapet lips and a weathered roof membrane
##
## Deterministic (seeded); `--clean-surfaces` skips it for A/B captures.

const SEED := 20261022

static var stats := {}

## Roof finishes seen from the air: bitumen, grey screed, green and terracotta
## waterproof coatings, silver reflective paint (all weathered by the shader).
const ROOF_FINISHES := [
	Color(0.30, 0.30, 0.30), Color(0.46, 0.45, 0.42), Color(0.52, 0.51, 0.47),
	Color(0.36, 0.44, 0.38), Color(0.55, 0.36, 0.28), Color(0.64, 0.65, 0.64),
	Color(0.40, 0.39, 0.36), Color(0.33, 0.37, 0.40),
]

static func dress(world_root: Node3D) -> Dictionary:
	stats = {"shophouses": 0, "hdb": 0, "infill": 0, "condensers": 0, "pipes": 0, "cables": 0, "roof_props": 0, "overlays": 0}
	if "--clean-surfaces" in OS.get_cmdline_user_args():
		return stats
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var shophouses: Array[Dictionary] = []
	var hdbs: Array[Dictionary] = []
	var infill: Array[Dictionary] = []
	var stack: Array[Node] = [world_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var path := String(node.scene_file_path)
		if node != world_root and node is Node3D and path != "":
			if path.contains("shophouse_clean"):
				shophouses.append(_module_info(node as Node3D, world_root))
				_overlay(node, true)
				continue
			if path.contains("hdb_slab_clean"):
				hdbs.append(_module_info(node as Node3D, world_root))
				_overlay(node)
				continue
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			# Wave A integration: RoofKit tints infill facades and owns their roofs
			# (deck, parapet, plant); here they only get wall clutter.
			if mi.mesh is BoxMesh and RoofKit._facade_variants.values().has(mi.material_override):
				infill.append({"size": (mi.mesh as BoxMesh).size, "xform": _rel_xform(mi, world_root), "roofkit": true})
				continue
			if mi.mesh is BoxMesh and Palette._facade_cache.values().has(mi.material_override):
				var ixf := _rel_xform(mi, world_root)
				infill.append({"size": (mi.mesh as BoxMesh).size, "xform": ixf})
				# Repaint: pick a tint variant per building (deterministic by position).
				var kind := ""
				for k in Palette._facade_cache:
					if Palette._facade_cache[k] == mi.material_override:
						kind = k
				if kind != "" and kind != "office" and kind != "glass":
					mi.material_override = Palette.facade_variant(kind, int(absf(ixf.origin.x) * 0.37 + absf(ixf.origin.z) * 0.71))
	_fix_roof_caps(world_root, infill)
	_shop_floor(world_root)
	stats["shophouses"] = shophouses.size()
	stats["hdb"] = hdbs.size()
	stats["infill"] = infill.size()

	var condensers: Array[Transform3D] = []
	var pipes: Array[Transform3D] = []
	var rust_pipes: Array[Transform3D] = []
	var roof_boxes: Array[Transform3D] = []
	var membranes: Array[Transform3D] = []
	var membrane_cols: Array[Color] = []
	var tanks: Array[Transform3D] = []
	var cables := PackedVector3Array()
	var cable_idx := PackedInt32Array()

	for s in shophouses:
		_dress_shophouse(s, rng, condensers, pipes, rust_pipes, cables, cable_idx)
	# HDB provider slabs carry their own facade; their AABB is far wider than
	# the visible slab, so they only get the grime pass (no placed clutter).
	for b in infill:
		var m0 := membranes.size()
		_dress_infill(b, rng, condensers, rust_pipes, roof_boxes, membranes, tanks)
		if membranes.size() > m0:
			membrane_cols.append(ROOF_FINISHES[rng.randi() % ROOF_FINISHES.size()])

	_add_multimesh(world_root, "WallCondensers", _condenser_mesh(), null, condensers)
	_add_multimesh(world_root, "DrainPipes", _pipe_mesh(), Palette.mat(Color(0.27, 0.29, 0.27), 0.6, 0.2), pipes)
	_add_multimesh(world_root, "RustPipes", _pipe_mesh(), Palette.mat(Color(0.33, 0.22, 0.16), 0.75, 0.35), rust_pipes)
	_add_multimesh(world_root, "RoofPlant", _unit_box(), Palette.weathered_surface(Color(0.50, 0.49, 0.46), "concrete", 0.9, 0.0), roof_boxes)
	# One draw per roof finish (instance colours do not reach this shader path).
	for fi in ROOF_FINISHES.size():
		var group: Array[Transform3D] = []
		for i in membranes.size():
			if membrane_cols[i] == ROOF_FINISHES[fi]:
				group.append(membranes[i])
		_add_multimesh(world_root, "RoofMembrane%d" % fi, _unit_box(), Palette.weathered_surface(ROOF_FINISHES[fi], "concrete", 0.92, 0.0), group)
	_add_multimesh(world_root, "RoofTanks", _tank_mesh(), Palette.mat(Color(0.58, 0.60, 0.60), 0.55, 0.45), tanks)
	if cables.size() > 0:
		var am := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = cables
		arrays[Mesh.ARRAY_INDEX] = cable_idx
		var normals := PackedVector3Array()
		normals.resize(cables.size())
		normals.fill(Vector3.UP)
		arrays[Mesh.ARRAY_NORMAL] = normals
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var cm := Palette.mat(Color(0.05, 0.05, 0.05), 0.7)
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		am.surface_set_material(0, cm)
		var cmi := MeshInstance3D.new()
		cmi.name = "FacadeCables"
		cmi.mesh = am
		cmi.add_to_group("surface_dressing")
		world_root.add_child(cmi)
	stats["condensers"] = condensers.size()
	stats["pipes"] = pipes.size() + rust_pipes.size()
	stats["roof_props"] = roof_boxes.size() + tanks.size() + membranes.size()
	print("[materials] surface dressing ", stats)
	return stats

# ----------------------------------------------------------------- analysis
## The convenience-store kit has no finished floor, so the car-park lot (bay
## lines, cracks) showed inside the shop. Lay a pale vinyl-tile slab in it.
static func _shop_floor(world_root: Node3D) -> void:
	var shop := world_root.find_child("OrchardDailyConvenience", true, false) as Node3D
	if shop == null:
		return
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "ShopVinylFloor"
	var box := BoxMesh.new()
	box.size = Vector3(13.7, 0.06, 9.7)
	floor_mi.mesh = box
	floor_mi.material_override = Palette.mat_textured(Color(0.80, 0.79, 0.74), "pavers", Vector3.ONE, 0.55, 0.0, false)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shop.add_child(floor_mi)
	floor_mi.position = Vector3(0.0, 0.03, 0.0)
	stats["shop_floor"] = 1

static func _rel_xform(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

static func _module_info(module: Node3D, root: Node3D) -> Dictionary:
	var aabb := AABB()
	var first := true
	var st: Array[Node] = [module]
	while not st.is_empty():
		var n: Node = st.pop_back()
		for c in n.get_children():
			st.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var box: AABB = _rel_xform(n as Node3D, root) * (n as MeshInstance3D).mesh.get_aabb()
			if first:
				aabb = box
				first = false
			else:
				aabb = aabb.merge(box)
	var xf := _rel_xform(module, root)
	return {"aabb": aabb, "front": xf.basis.x.normalized(), "side": xf.basis.z.normalized(), "origin": xf.origin}

## The pre-wave-B infill roof deck box was built as `size + (0.7, 0.55, 0.7)`,
## i.e. a full-height shell floating half a storey above the building, which
## hid the facade and read from the air as a blank beige block. Re-shape each
## one into the intended 0.55 m deck slab so walls, parapets and plant show.
static func _fix_roof_caps(world_root: Node3D, infill: Array[Dictionary]) -> void:
	var by_pos := {}
	for child in world_root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			var o := (child as MeshInstance3D).position
			by_pos[Vector3i(roundi(o.x * 10.0), roundi(o.y * 10.0), roundi(o.z * 10.0))] = child
	var fixed := 0
	for b in infill:
		var size: Vector3 = b["size"]
		var c: Vector3 = (b["xform"] as Transform3D).origin
		var cap_pos := Vector3(c.x, c.y - size.y * 0.5 + size.y + 0.2, c.z)
		var key := Vector3i(roundi(cap_pos.x * 10.0), roundi(cap_pos.y * 10.0), roundi(cap_pos.z * 10.0))
		var cap: MeshInstance3D = by_pos.get(key)
		if cap == null:
			continue
		var bm := cap.mesh as BoxMesh
		if absf(bm.size.y - (size.y + 0.55)) > 0.01:
			continue
		var slab := BoxMesh.new()
		slab.size = Vector3(bm.size.x, 0.55, bm.size.z)
		cap.mesh = slab
		fixed += 1
	stats["roof_caps_fixed"] = fixed

static func _overlay(node: Node, light: bool = false) -> void:
	var st: Array[Node] = [node]
	while not st.is_empty():
		var n: Node = st.pop_back()
		for c in n.get_children():
			st.append(c)
		if not n is MeshInstance3D:
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(i)
			if m == null:
				m = mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D and (m as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and m.next_pass == null:
				m.next_pass = Palette.grime_overlay_light() if light else Palette.grime_overlay()
				stats["overlays"] = int(stats["overlays"]) + 1

static func _extent(aabb: AABB, axis: Vector3) -> Vector2:
	# min/max projection of the box onto a horizontal axis
	var lo := INF
	var hi := -INF
	for i in 8:
		var d := aabb.get_endpoint(i).dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)

# ----------------------------------------------------------------- dressing
static func _face_basis(out: Vector3) -> Basis:
	# local +Z points out of the wall, +Y up
	var z := out.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)

static func _dress_shophouse(s: Dictionary, rng: RandomNumberGenerator, condensers: Array[Transform3D], pipes: Array[Transform3D], rust: Array[Transform3D], cables: PackedVector3Array, idx: PackedInt32Array) -> void:
	var aabb: AABB = s["aabb"]
	var front: Vector3 = s["front"]
	var side: Vector3 = s["side"]
	var o: Vector3 = s["origin"]
	var fe := _extent(aabb, front)
	var se := _extent(aabb, side)
	var top := aabb.end.y
	var base := aabb.position.y
	var h := top - base
	var eave := base + h * 0.70
	var front_d := fe.y
	var back_d := fe.x
	var c_side := (se.x + se.y) * 0.5
	var half_w := (se.y - se.x) * 0.5
	var fb := _face_basis(front)
	var bb := _face_basis(-front)
	var o_side := o.dot(side)
	var o_front := o.dot(front)
	var anchor := o - side * o_side - front * o_front   # projection residue (vertical)
	var at := func(f: float, sd: float, y: float) -> Vector3:
		var p: Vector3 = front * f + side * sd
		return Vector3(p.x + anchor.x, y, p.z + anchor.z)
	# Drain pipe down one party-wall line of every unit, eave to ground.
	var px: float = se.x + 0.22
	var plen := eave - base
	pipes.append(Transform3D(Basis.from_scale(Vector3(1.0, plen, 1.0)), at.call(front_d + 0.10, px, base + plen * 0.5)))
	# Rear: a downpipe and a stack of condensers on the service-lane wall.
	rust.append(Transform3D(Basis.from_scale(Vector3(1.2, plen, 1.2)), at.call(back_d - 0.12, c_side + half_w * 0.55, base + plen * 0.5)))
	var rear_count := rng.randi_range(1, 3)
	for k in rear_count:
		var sd := c_side + rng.randf_range(-half_w * 0.7, half_w * 0.7)
		var y := base + rng.randf_range(3.0, eave - 1.2)
		condensers.append(Transform3D(bb.rotated(Vector3.UP, 0.0), at.call(back_d - 0.18, sd, y)))
	# Front: some units carry a condenser on the upper pilaster.
	if rng.randf() < 0.55:
		var sd2: float = se.y - 0.55
		var y2 := base + h * rng.randf_range(0.46, 0.56)
		condensers.append(Transform3D(fb, at.call(front_d + 0.18, sd2, y2)))
	# Sagging service cables along the fascia, unit to unit.
	var runs := [base + h * 0.39, base + h * 0.415, base + h * 0.62]
	for r in runs.size():
		var y0: float = runs[r] + rng.randf_range(-0.05, 0.05)
		var a: Vector3 = at.call(front_d + 0.14 + r * 0.05, se.x + 0.05, y0)
		var b: Vector3 = at.call(front_d + 0.14 + r * 0.05, se.y - 0.05, y0 + rng.randf_range(-0.08, 0.08))
		_cable(cables, idx, a, b, rng.randf_range(0.22, 0.55), 0.022 + r * 0.004)
	stats["cables"] = int(stats["cables"]) + runs.size()

static func _dress_infill(b: Dictionary, rng: RandomNumberGenerator, condensers: Array[Transform3D], rust: Array[Transform3D], roof_boxes: Array[Transform3D], membranes: Array[Transform3D], tanks: Array[Transform3D]) -> void:
	var size: Vector3 = b["size"]
	var xf: Transform3D = b["xform"]
	var c := xf.origin
	var roof_y := c.y + size.y * 0.5 + 0.475     # top of the roof-deck cap
	var hx := size.x * 0.5 + 0.35
	var hz := size.z * 0.5 + 0.35
	if bool(b.get("roofkit", false)):
		_dress_infill_walls(size, c, rng, condensers, rust)
		return
	# Parapet lip (four low walls) so the roof reads as a deck, not a slab.
	var lip := 0.55
	var t := 0.22
	roof_boxes.append(Transform3D(Basis.from_scale(Vector3(hx * 2.0, lip, t)), Vector3(c.x, roof_y + lip * 0.5, c.z - hz + t * 0.5)))
	roof_boxes.append(Transform3D(Basis.from_scale(Vector3(hx * 2.0, lip, t)), Vector3(c.x, roof_y + lip * 0.5, c.z + hz - t * 0.5)))
	roof_boxes.append(Transform3D(Basis.from_scale(Vector3(t, lip, hz * 2.0 - t * 2.0)), Vector3(c.x - hx + t * 0.5, roof_y + lip * 0.5, c.z)))
	roof_boxes.append(Transform3D(Basis.from_scale(Vector3(t, lip, hz * 2.0 - t * 2.0)), Vector3(c.x + hx - t * 0.5, roof_y + lip * 0.5, c.z)))
	# Weathered membrane inside the lip.
	membranes.append(Transform3D(Basis.from_scale(Vector3(hx * 2.0 - t * 2.0, 0.04, hz * 2.0 - t * 2.0)), Vector3(c.x, roof_y + 0.02, c.z)))
	# Rooftop plant: condenser banks, a vent/stair box, sometimes a tank.
	var area := size.x * size.z
	var n_cond := clampi(int(area / 70.0), 1, 8)
	var row_axis := Vector3(1, 0, 0) if size.x >= size.z else Vector3(0, 0, 1)
	var bank_origin := c + Vector3(rng.randf_range(-0.25, 0.25) * size.x, 0.0, rng.randf_range(-0.25, 0.25) * size.z)
	var face_dir := Vector3(0, 0, 1) if row_axis.x != 0.0 else Vector3(1, 0, 0)
	var fb := _face_basis(face_dir)
	for k in n_cond:
		var p := bank_origin + row_axis * (k - n_cond * 0.5) * 1.05
		p.x = clampf(p.x, c.x - size.x * 0.5 + 1.0, c.x + size.x * 0.5 - 1.0)
		p.z = clampf(p.z, c.z - size.z * 0.5 + 1.0, c.z + size.z * 0.5 - 1.0)
		p.y = roof_y + 0.36
		condensers.append(Transform3D(fb, p))
	var vb := Vector3(rng.randf_range(2.2, 3.8), rng.randf_range(1.4, 2.6), rng.randf_range(2.0, 3.2))
	if size.x < 8.0 or size.z < 8.0:
		vb = Vector3(minf(vb.x, size.x * 0.4), vb.y * 0.7, minf(vb.z, size.z * 0.4))
	roof_boxes.append(Transform3D(Basis.from_scale(vb), Vector3(c.x - size.x * 0.28, roof_y + vb.y * 0.5, c.z + size.z * 0.25)))
	if rng.randf() < 0.5:
		tanks.append(Transform3D(Basis.from_scale(Vector3(1.0, 1.1, 1.0)), Vector3(c.x + size.x * 0.3, roof_y + 0.55, c.z - size.z * 0.28)))
	_dress_infill_walls(size, c, rng, condensers, rust)

## Walls: condensers and a rusted downpipe on the two long faces.
static func _dress_infill_walls(size: Vector3, c: Vector3, rng: RandomNumberGenerator, condensers: Array[Transform3D], rust: Array[Transform3D]) -> void:
	var bottom := c.y - size.y * 0.5
	for face: float in [-1.0, 1.0]:
		var out := Vector3(0, 0, face) if size.x >= size.z else Vector3(face, 0, 0)
		var half := (size.x if size.x >= size.z else size.z) * 0.5
		var depth := (size.z if size.x >= size.z else size.x) * 0.5
		var wb := _face_basis(out)
		var count := rng.randi_range(1, 2 + int(size.y / 6.0))
		for k in count:
			var tt := rng.randf_range(-half + 1.2, half - 1.2)
			var y := bottom + rng.randf_range(2.6, maxf(2.8, size.y - 1.2))
			var p := c + out * (depth + 0.17)
			p.y = y
			if size.x >= size.z:
				p.x += tt
			else:
				p.z += tt
			condensers.append(Transform3D(wb, p))
		var pp := c + out * (depth + 0.09)
		var pt := (half - 0.4) * (1.0 if rng.randf() < 0.5 else -1.0)
		if size.x >= size.z:
			pp.x += pt
		else:
			pp.z += pt
		pp.y = bottom + size.y * 0.5
		rust.append(Transform3D(Basis.from_scale(Vector3(1.0, size.y, 1.0)), pp))

# ----------------------------------------------------------------- meshes
static func _add_multimesh(root: Node3D, name: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D], colors: Array[Color] = []) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() == xforms.size()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	mmi.add_to_group("surface_dressing")
	root.add_child(mmi)

static var _unit: BoxMesh = null
static func _unit_box() -> BoxMesh:
	if _unit == null:
		_unit = BoxMesh.new()
		_unit.size = Vector3.ONE
	return _unit

static func _pipe_mesh() -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.055
	m.bottom_radius = 0.055
	m.height = 1.0
	m.radial_segments = 8
	m.rings = 1
	return m

static func _tank_mesh() -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 16
	m.rings = 1
	return m

static var _condenser: ArrayMesh = null
## Split-unit condenser on wall brackets: body, dark fan grille, rusty bracket.
## Local +Z faces out of the wall; the unit's back sits at z = -0.15.
static func _condenser_mesh() -> ArrayMesh:
	if _condenser != null:
		return _condenser
	var am := ArrayMesh.new()
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st_box(body, Vector3(0, 0, 0), Vector3(0.84, 0.58, 0.30))
	# top lid lip
	_st_box(body, Vector3(0, 0.30, 0.0), Vector3(0.88, 0.03, 0.33))
	# Fan guard: horizontal wire bars across the opening, plus a round bezel
	# and hub, so the front reads as a grille rather than a flat black disc.
	for k in 7:
		var gy := -0.18 + 0.06 * k
		var half_w := sqrt(maxf(0.0, 0.215 * 0.215 - gy * gy))
		_st_box(body, Vector3(-0.12, gy, 0.158), Vector3(half_w * 2.0, 0.008, 0.012))
	_st_box(body, Vector3(-0.12, 0.0, 0.158), Vector3(0.008, 0.43, 0.012))
	_st_box(body, Vector3(-0.12, 0.0, 0.162), Vector3(0.07, 0.07, 0.02))
	# Side coil louvres on the right panel.
	for k in 8:
		_st_box(body, Vector3(0.27, -0.19 + 0.052 * k, 0.156), Vector3(0.17, 0.012, 0.012))
	# Feet and a refrigerant pipe stub.
	_st_box(body, Vector3(-0.30, -0.30, 0.0), Vector3(0.08, 0.03, 0.30))
	_st_box(body, Vector3(0.30, -0.30, 0.0), Vector3(0.08, 0.03, 0.30))
	am = body.commit(am)
	am.surface_set_material(0, Palette.mat(Color(0.72, 0.70, 0.64), 0.68, 0.05))
	var grille := SurfaceTool.new()
	grille.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cz := 0.152
	var cx := -0.12
	var r := 0.215
	var seg := 18
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		grille.set_normal(Vector3(0, 0, 1))
		grille.add_vertex(Vector3(cx, 0.0, cz))
		grille.set_normal(Vector3(0, 0, 1))
		grille.add_vertex(Vector3(cx + cos(a1) * r, sin(a1) * r, cz))
		grille.set_normal(Vector3(0, 0, 1))
		grille.add_vertex(Vector3(cx + cos(a0) * r, sin(a0) * r, cz))
	# side louvre panel
	_st_box(grille, Vector3(0.27, -0.02, 0.150), Vector3(0.18, 0.40, 0.006))
	am = grille.commit(am)
	am.surface_set_material(1, Palette.mat(Color(0.20, 0.21, 0.21), 0.75, 0.2))
	var br := SurfaceTool.new()
	br.begin(Mesh.PRIMITIVE_TRIANGLES)
	_st_box(br, Vector3(-0.32, -0.31, -0.02), Vector3(0.05, 0.04, 0.42))
	_st_box(br, Vector3(0.32, -0.31, -0.02), Vector3(0.05, 0.04, 0.42))
	# rust streak drip under the unit, painted on the wall side
	am = br.commit(am)
	am.surface_set_material(2, Palette.mat(Color(0.30, 0.20, 0.15), 0.8, 0.4))
	_condenser = am
	return am

static func _st_box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var ctr := c + n * h
		var uu := u * h
		var vv := v * h
		var p0 := ctr - uu - vv
		var p1 := ctr + uu - vv
		var p2 := ctr + uu + vv
		var p3 := ctr - uu + vv
		# clockwise seen from outside = Godot front face
		for p in [p0, p2, p1, p0, p3, p2]:
			st.set_normal(n)
			st.add_vertex(p)

static func _cable(verts: PackedVector3Array, idx: PackedInt32Array, a: Vector3, b: Vector3, sag: float, radius: float) -> void:
	var segs := 10
	var base := verts.size()
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	for i in segs + 1:
		var t := float(i) / segs
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		# a flat ribbon facing up plus one facing sideways reads as a round cable
		verts.append(p - side * radius)
		verts.append(p + side * radius)
		verts.append(p + Vector3.UP * radius)
		verts.append(p - Vector3.UP * radius)
	for i in segs:
		var k := base + i * 4
		idx.append_array([k, k + 1, k + 5, k, k + 5, k + 4])
		idx.append_array([k + 2, k + 3, k + 7, k + 2, k + 7, k + 6])
