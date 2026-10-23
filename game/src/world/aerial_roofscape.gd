class_name AerialRoofscape
extends RefCounted
## Shophouse roofscape variety (aerial piece, Opus 5.5 wave R).
##
## Helicopter-P2 judge: "runs of identical adjacent buildings, blank roofs".
## Every heritage row is the same provider module repeated, so from 100 m the
## roofs read as one stamped tile. Real shophouse terraces have been altered
## unit by unit over decades: rear attic and service-wing extensions with flat
## roofs, whole units rebuilt with a roof terrace, water tanks and solar on
## the slopes. Each unit (from Lighting.bays, recorded by the row builder)
## gets one alteration chosen by a seeded hash, with a rule that no more than
## three neighbours in a row share the same treatment. Flat roofs go through
## RoofKit (membranes, parapets, condensers, tanks, planters), so it costs a
## handful of MultiMesh draws. Additions sit at roof level (>= 9 m) and are set
## back from the street front, so the five-foot ways are untouched.

const OPENING_ROW_X := -180.0

static var stats := {}
const ROOF_TEX := "res://assets/providers/higgsfield/rooftop_flat_albedo.png"
static var roof_textured := false

## Gives the RoofKit deck material the generated `rooftop_flat` sheet when the
## private library is linked in (it is git-ignored); the procedural deck
## stays as the fallback.
static func apply_roof_texture(mat: ShaderMaterial) -> void:
	if not ResourceLoader.exists(ROOF_TEX):
		return
	var tex := load(ROOF_TEX) as Texture2D
	if tex == null:
		return
	mat.set_shader_parameter("roof_tex", tex)
	mat.set_shader_parameter("roof_tex_amount", 0.85)
	roof_textured = true

static func build(world: Node, root: Node3D) -> Dictionary:
	var lighting = world.get("_lighting")
	if lighting == null:
		return {}
	var bays: Array = lighting.bays
	var kit := RoofKit.new(8807)
	var rng := RandomNumberGenerator.new()
	var counts := [0, 0, 0, 0]
	var prev := -1
	var run := 0
	var max_run := 0
	var tank_mat := Palette.mat(Color(0.62, 0.62, 0.60), 0.6, 0.35)
	var solar_mat := Palette.mat(Color(0.08, 0.10, 0.16), 0.25, 0.6)
	for bay in bays:
		var pos: Vector3 = bay["pos"]
		var front: Vector3 = bay["front"]
		var dir: Vector3 = bay["dir"]
		rng.seed = int(absf(pos.x) * 13.0 + absf(pos.z) * 71.0) + 5
		# 0 untouched, 1 rear attic, 2 rebuilt with roof terrace, 3 tanks + solar
		var weights := [0.34, 0.30, 0.18, 0.18]
		if absf(pos.x - OPENING_ROW_X) < 6.0 or absf(pos.x - (OPENING_ROW_X + 10.0)) < 6.0:
			weights = [0.55, 0.30, 0.0, 0.15]   # the street-photo heritage row keeps its fronts
		var pick := _weighted(rng.randf(), weights)
		if pick == prev and run >= 2:
			pick = (pick + 1 + rng.randi_range(0, 1)) % 4
			if weights[pick] <= 0.0 or pick == prev:
				pick = 0 if prev != 0 else 3
		run = run + 1 if pick == prev else 0
		max_run = maxi(max_run, run + 1)
		prev = pick
		counts[pick] += 1
		var along_x := absf(dir.x) > 0.5
		match pick:
			1:
				var depth := rng.randf_range(4.2, 5.8)
				var h := rng.randf_range(3.4, 4.8)
				var c := pos - front * (5.0 - depth * 0.5) + Vector3(0.0, 9.0, 0.0)
				_annex(root, kit, Vector3(9.8, h, depth), c, along_x, "shopback")
			2:
				var h2 := rng.randf_range(4.4, 5.8)
				var c2 := pos - front * 1.6 + Vector3(0.0, 8.2, 0.0)
				_annex(root, kit, Vector3(10.0, h2, 7.2), c2, along_x, "shopback" if rng.randf() < 0.6 else "hdb")
			3:
				var base := pos - front * 3.0 + Vector3(0.0, 10.4, 0.0)
				for k in rng.randi_range(1, 2):
					var tp := base + dir * (-2.5 + k * 3.2)
					_mesh(root, _cyl(1.1, 1.6), Transform3D(Basis.IDENTITY, tp + Vector3(0, 1.0, 0)), tank_mat)
					_mesh(root, _box(), Transform3D(Basis.from_scale(Vector3(1.6, 0.25, 1.6)), tp + Vector3(0, 0.1, 0)), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))
				var sp := pos + front * 1.4 + Vector3(0.0, 11.0, 0.0)
				var panel := Basis.from_scale(Vector3(7.0, 0.08, 3.2) if along_x else Vector3(3.2, 0.08, 7.0))
				_mesh(root, _box(), Transform3D(panel, sp), solar_mat)
	kit.build(root)
	# The background city is built by now: hand its curtain walls the
	# generated glass sheet too (kept here so world_builder needs no new hook).
	var glass := AerialAtmosphere.apply_glass_library()
	stats = {"glass_materials": glass, "units": bays.size(), "untouched": counts[0], "attic": counts[1], "rebuilt": counts[2], "tanks_solar": counts[3], "roofs": kit.roofs, "max_run": max_run}
	print("[world] aerial roofscape: ", stats)
	return stats

static func _weighted(r: float, w: Array) -> int:
	var acc := 0.0
	for k in w.size():
		acc += float(w[k])
		if r < acc:
			return k
	return w.size() - 1

static func _annex(root: Node3D, kit: RoofKit, size_local: Vector3, centre: Vector3, along_x: bool, kind: String) -> void:
	var size := size_local if along_x else Vector3(size_local.z, size_local.y, size_local.x)
	_mesh(root, _box(), Transform3D(Basis.from_scale(size), centre + Vector3(0.0, size.y * 0.5, 0.0)), RoofKit.facade_variant(kind, centre))
	kit.add_flat_roof(size, centre, kind)

static func _mesh(root: Node3D, mesh: Mesh, xf: Transform3D, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.material_override = mat
	root.add_child(mi)

static var _box_cache: BoxMesh
static func _box() -> BoxMesh:
	if _box_cache == null:
		_box_cache = BoxMesh.new()
		_box_cache.size = Vector3.ONE
	return _box_cache

static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	return c
