extends RefCounted
## downtown-fill (wave T): roof plant and roof finishes for the downtown
## podiums and mid-rise roofs (8-95 m), which fill most of a 110 m helicopter
## view. Critic gap (wave S): "towers as boxes ... distinct rooftops and plant".
## Per roof, from a per-building hash: a coloured waterproofing membrane
## (pale grey, cool white, terracotta, green coating, dark bitumen), then a mix
## of condenser grids, cooling-tower clusters, a lift/stair penthouse, water
## tanks, solar arrays, duct runs, skylights and roof-garden beds with shrub
## mounds. Everything stays inside the central 68 % of the roof box, so round
## and chamfered roofs never show an overhang. MultiMesh per prop per 400 m
## cell; no collision. Original procedural work.

const Canopy := preload("res://src/world/downtown/canopy.gd")
const INSET := 0.68

static var _m := {}

static func _mat(key: String) -> Material:
	if _m.has(key):
		return _m[key]
	var m: Material
	match key:
		"membrane_grey": m = Palette.mat_textured(Color(0.62, 0.62, 0.60), "concrete", Vector3.ONE, 0.9)
		"membrane_white": m = Palette.mat_textured(Color(0.80, 0.80, 0.77), "concrete", Vector3.ONE, 0.85)
		"membrane_terracotta": m = Palette.mat_textured(Color(0.50, 0.30, 0.22), "concrete", Vector3.ONE, 0.9)
		"membrane_green": m = Palette.mat_textured(Color(0.30, 0.40, 0.33), "concrete", Vector3.ONE, 0.88)
		"membrane_dark": m = Palette.mat_textured(Color(0.22, 0.22, 0.23), "concrete", Vector3.ONE, 0.92)
		"plant": m = Palette.mat(Color(0.70, 0.71, 0.70), 0.5, 0.4)
		"plant_dark": m = Palette.mat(Color(0.30, 0.32, 0.33), 0.6, 0.3)
		"tower_green": m = Palette.mat(Color(0.36, 0.45, 0.42), 0.6, 0.2)
		"tank": m = Palette.mat(Color(0.82, 0.84, 0.85), 0.45, 0.2)
		"solar":
			var s := StandardMaterial3D.new()
			s.albedo_color = Color(0.07, 0.10, 0.18)
			s.roughness = 0.18
			s.metallic = 0.4
			m = s
		"skylight":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.40, 0.55, 0.62)
			g.roughness = 0.08
			g.metallic = 0.5
			m = g
		"penthouse": m = Palette.mat_textured(Color(0.74, 0.72, 0.67), "plaster", Vector3.ONE, 0.88)
		_: m = Palette.mat(Color(0.5, 0.5, 0.5), 0.8)
	_m[key] = m
	return m

static func _box_mesh() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return b

static func _cyl_mesh() -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.5
	c.bottom_radius = 0.5
	c.height = 1.0
	c.radial_segments = 12
	c.rings = 1
	return c

## Ground-standing building boxes from the blocks collision body.
static func _boxes(world: WorldBuilder) -> Array:
	var out: Array = []
	var body := world.find_child("DowntownBlocksCollision", true, false)
	if body == null:
		return out
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var cs := c as CollisionShape3D
			var sz := (cs.shape as BoxShape3D).size
			var p := cs.global_position
			out.append(AABB(p - sz * 0.5, sz))
	return out

static func build(world: WorldBuilder, holder: Node3D) -> Dictionary:
	var boxes := _boxes(world)
	var groups := {}   # "mesh|mat" -> Array[Transform3D]
	var shrubs: Array = []
	var rng := RandomNumberGenerator.new()
	var roofs := 0
	for bx: AABB in boxes:
		var top := bx.end.y
		if top < 7.0 or top > 95.0 or bx.position.y > 6.0 or bx.size.x < 9.0 or bx.size.z < 9.0:
			continue
		var c := bx.get_center()
		# skip roofs whose middle is under a taller block (tower over podium)
		var covered := false
		for o: AABB in boxes:
			if o != bx and o.end.y > top + 2.0 and o.has_point(Vector3(c.x, top + 1.0, c.z)):
				covered = true
				break
		roofs += 1
		rng.seed = hash(Vector2i(int(c.x), int(c.z)))
		var ex := bx.size.x * INSET
		var ez := bx.size.z * INSET
		var y := top
		var memb: String = ["membrane_grey", "membrane_white", "membrane_terracotta", "membrane_green", "membrane_dark", "membrane_grey"][rng.randi() % 6]
		if not covered:
			_add(groups, "box", memb, Transform3D(Basis.from_scale(Vector3(ex, 0.12, ez)), Vector3(c.x, y + 0.06, c.z)))
		var others := func(p: Vector3) -> bool:
			for o: AABB in boxes:
				if o != bx and o.end.y > top + 1.0 and o.grow(1.0).has_point(Vector3(p.x, top + 0.5, p.z)):
					return true
			return false
		# lift / stair penthouse
		var ph := Vector3(c.x + rng.randf_range(-0.25, 0.25) * ex, y, c.z + rng.randf_range(-0.25, 0.25) * ez)
		var phs := Vector3(rng.randf_range(5.0, 8.0), rng.randf_range(3.0, 4.2), rng.randf_range(4.0, 6.0))
		if not others.call(ph):
			_add(groups, "box", "penthouse", Transform3D(Basis.from_scale(phs), ph + Vector3(0, phs.y * 0.5, 0)))
			_add(groups, "box", "plant_dark", Transform3D(Basis.from_scale(Vector3(phs.x + 0.4, 0.3, phs.z + 0.4)), ph + Vector3(0, phs.y + 0.15, 0)))
		# condenser grid
		var rows := rng.randi_range(2, 4)
		var cols := clampi(int(ex / 2.4) - 2, 2, 9)
		var gx0 := c.x - ex * 0.5 + 2.0 + rng.randf_range(0.0, 3.0)
		var gz0 := c.z + (rng.randf_range(0.05, 0.35) if rng.randf() < 0.5 else -rng.randf_range(0.35, 0.45)) * ez
		for r in rows:
			for k in cols:
				var p := Vector3(gx0 + k * 2.1, y, gz0 + r * 1.8)
				if absf(p.x - c.x) > ex * 0.5 - 0.8 or absf(p.z - c.z) > ez * 0.5 - 0.8 or others.call(p):
					continue
				_add(groups, "box", "plant", Transform3D(Basis.from_scale(Vector3(1.3, 1.1, 1.0)), p + Vector3(0, 0.55, 0)))
				_add(groups, "cyl", "plant_dark", Transform3D(Basis.from_scale(Vector3(0.8, 0.06, 0.8)), p + Vector3(0, 1.13, 0)))
		# cooling towers / tanks
		if rng.randf() < 0.65:
			var n := rng.randi_range(2, 4)
			var tp := Vector3(c.x + rng.randf_range(-0.3, 0.3) * ex, y, c.z + rng.randf_range(-0.3, 0.3) * ez)
			var tank := rng.randf() < 0.4
			for i in n:
				var p2 := tp + Vector3(i * (4.6 if not tank else 3.4), 0, 0)
				if absf(p2.x - c.x) > ex * 0.5 - 2.0 or others.call(p2):
					continue
				var rad := rng.randf_range(1.6, 2.4) if not tank else rng.randf_range(1.2, 1.6)
				var hh := rng.randf_range(2.8, 3.8) if not tank else rng.randf_range(2.2, 3.2)
				_add(groups, "cyl", "tower_green" if not tank else "tank", Transform3D(Basis.from_scale(Vector3(rad * 2.0, hh, rad * 2.0)), p2 + Vector3(0, hh * 0.5, 0)))
				if not tank:
					_add(groups, "cyl", "plant_dark", Transform3D(Basis.from_scale(Vector3(rad * 1.5, 0.5, rad * 1.5)), p2 + Vector3(0, hh + 0.25, 0)))
		# solar array or roof garden on the remaining side
		var side_z := c.z - ez * 0.25
		if rng.randf() < 0.5:
			var nx := clampi(int(ex / 2.4) - 1, 2, 12)
			var nz := clampi(int(ez * 0.35 / 1.9), 1, 6)
			for i in nx:
				for j in nz:
					var p3 := Vector3(c.x - ex * 0.5 + 1.6 + i * 2.3, y, side_z - ez * 0.12 + j * 1.9)
					if absf(p3.x - c.x) > ex * 0.5 - 1.0 or absf(p3.z - c.z) > ez * 0.5 - 1.0 or others.call(p3):
						continue
					_add(groups, "box", "solar", Transform3D(Basis(Vector3.RIGHT, -0.26).scaled(Vector3(2.0, 0.06, 1.6)), p3 + Vector3(0, 0.55, 0)))
		else:
			var gw := ex * rng.randf_range(0.35, 0.6)
			var gd := ez * rng.randf_range(0.2, 0.32)
			var gp := Vector3(c.x + rng.randf_range(-0.15, 0.15) * ex, y, side_z)
			if not others.call(gp):
				_add(groups, "box", "garden", Transform3D(Basis.from_scale(Vector3(gw, 0.5, gd)), gp + Vector3(0, 0.25, 0)))
				for i in int(gw * gd / 14.0):
					var sp := gp + Vector3(rng.randf_range(-0.45, 0.45) * gw, 0.5, rng.randf_range(-0.42, 0.42) * gd)
					var s := rng.randf_range(0.35, 0.7)
					shrubs.append(["shrub", Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(s, s, s)), sp),
						Color(rng.randf_range(0.85, 1.15), rng.randf_range(0.9, 1.15), rng.randf_range(0.85, 1.1), 0.0)])
		# duct runs and skylights
		for i in rng.randi_range(1, 3):
			var dp := Vector3(c.x + rng.randf_range(-0.35, 0.35) * ex, y, c.z + rng.randf_range(-0.35, 0.35) * ez)
			if others.call(dp):
				continue
			if rng.randf() < 0.5:
				_add(groups, "box", "plant", Transform3D(Basis.from_scale(Vector3(ex * rng.randf_range(0.2, 0.45), 0.6, 0.7)), dp + Vector3(0, 0.5, 0)))
			else:
				_add(groups, "box", "skylight", Transform3D(Basis.from_scale(Vector3(rng.randf_range(3.0, 6.0), 0.5, rng.randf_range(2.0, 4.0))), dp + Vector3(0, 0.3, 0)))
	var draws := 0
	var meshes := {"box": _box_mesh(), "cyl": _cyl_mesh()}
	for key: String in groups:
		var parts := key.split("|")
		var mesh_key := parts[0]
		var mat_key := parts[1]
		var by_cell := {}
		for xf: Transform3D in groups[key]:
			var cell := Vector2i(floori(xf.origin.x / 400.0), floori(xf.origin.z / 400.0))
			if not by_cell.has(cell):
				by_cell[cell] = []
			by_cell[cell].append(xf)
		for cell in by_cell:
			var list: Array = by_cell[cell]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[mesh_key]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "DowntownRoof_" + mat_key
			mmi.multimesh = mm
			mmi.material_override = DowntownLawn.or_default(_mat("membrane_green")) if mat_key == "garden" else _mat(mat_key)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mat_key.begins_with("membrane") or mat_key == "solar" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.visibility_range_end = 1100.0
			mmi.visibility_range_end_margin = 60.0
			mmi.set_meta("downtown_fill", true)
			holder.add_child(mmi)
			draws += 1
	if not shrubs.is_empty():
		draws += Canopy.emit(holder, shrubs, "DowntownRoofGardens", 900.0)
	return {"roofs": roofs, "draws": draws, "boxes": boxes.size()}

static func _add(groups: Dictionary, mesh: String, mat: String, xf: Transform3D) -> void:
	var key := "%s|%s" % [mesh, mat]
	if not groups.has(key):
		groups[key] = []
	groups[key].append(xf)
