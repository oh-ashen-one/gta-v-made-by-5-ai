extends RefCounted
## downtown-map piece (wave M): the playable ground of central Singapore around
## Marina Bay (loop/DOWNTOWN_PLAN.md, numbers from plan.gd / DowntownPlan).
##
## Builds, in this order: land slabs for every land rect and island with
## seawalls, coping, wet bands and waterfront railings (shoreline.gd); the
## downtown road network with kerbs, raised footways, markings, signals, lamps
## and trees, the downtown lane graph and pedestrian lanes (roads.gd); the
## Esplanade, Bayfront, Jubilee, Cavenagh, Elgin and Coleman bridges with deck
## collision and the Sheares Bridge on the horizon (bridges.gd); playable
## edges, helipads and the background-city fix-ups (bounds.gd).
##
## Geometry is accumulated into one ArrayMesh per material per 400 m cell and
## collision into one StaticBody3D, so the whole piece costs a few dozen draws.

const Shoreline := preload("res://src/world/downtown/shoreline.gd")
const Roads := preload("res://src/world/downtown/roads.gd")
const Bridges := preload("res://src/world/downtown/bridges.gd")
const Bounds := preload("res://src/world/downtown/bounds.gd")
const Planting := preload("res://src/world/downtown/planting.gd")
const CELL := 400.0

var world: WorldBuilder
var root: Node3D
var body: StaticBody3D
var shapes := 0
var stats := {}
var city: SkylineCity
## Background-city towers kept as stand-in buildings on downtown plots
## (they get box collision in bounds.gd).
var kept_towers: Array = []
var _mats := {}
var _st := {}
var _lamps := {"modern": [], "heritage": []}
var _posts: Array[Transform3D] = []
var _trees: Array[Transform3D] = []
## Driving surfaces above ground (ramps, bridge decks): one smooth trimesh, so
## the pitched segment boxes (kept 0.25 m lower against tunnelling) never put
## an internal edge under a tyre (a car stalled mid-deck on the Esplanade).
var _drive_faces := PackedVector3Array()

func replaces() -> PackedStringArray:
	return PackedStringArray(["district_ground", "far_shore_ground", "boundary_rails_x"])

func skyline_clear(w: WorldBuilder, c: SkylineCity) -> void:
	world = w
	city = c
	Bounds.skyline_clear(self, c)

func build(w: WorldBuilder, r: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	world = w
	root = r
	body = StaticBody3D.new()
	body.name = "DowntownMapStatic"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	Planting.reset()
	Shoreline.build(self)
	Roads.build(self)
	if not Planting.off():
		Planting.kerb_strips(self)
		Planting.corner_gardens(self)
	Bridges.build(self)
	Bounds.build(self)
	_flush()
	stats["build_ms"] = Time.get_ticks_msec() - t0
	stats["shapes"] = shapes
	world.set_meta("downtown_map_stats", stats)
	print("[downtown-map] built in %d ms: %d collision shapes, %d mesh draws, %d lamps, %d trees" % [stats["build_ms"], shapes, stats.get("draws", 0), stats.get("lamps", 0), _trees.size()])

func build_lanes(w: WorldBuilder) -> void:
	Roads.build_lanes(self, w)

func finish(w: WorldBuilder) -> void:
	Bounds.finish(self, w)
	# downtown-polish: layered planting collected by map (kerb strips, tree
	# pits, medians) and blocks (forecourt beds) is emitted once here.
	Planting.flush(root)
	stats["planting"] = Planting.stats.duplicate()
	w.set_meta("downtown_map_stats", stats)

# ------------------------------------------------------------ materials
func mat(key: String) -> Material:
	if key.ends_with("_soffit"):
		key = key.trim_suffix("_soffit")
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"asphalt": m = Palette.weathered_surface(Palette.ASPHALT, "asphalt", 0.9, 0.0, true)
		"ground": m = Palette.mat_textured(Color(0.44, 0.44, 0.43), "concrete", Vector3(70.0, 1.0, 70.0), 0.95)   # = legacy district slab
		"pavers": m = Palette.mat_textured(Color(0.52, 0.54, 0.57), "pavers", Vector3.ONE, 0.9)
		"pavers_warm": m = Palette.mat_textured(Color(0.62, 0.60, 0.58), "pavers", Vector3.ONE, 0.88)
		"pavers_bridge": m = Palette.mat_textured(Color(0.60, 0.58, 0.55), "pavers", Vector3.ONE, 0.9)
		"plaza": m = Palette.mat_textured(Color(0.50, 0.52, 0.55), "pavers", Vector3.ONE, 0.9)
		"plot": m = Palette.mat_textured(Color(0.60, 0.62, 0.64), "pavers", Vector3.ONE, 0.9, 0.0, false)   # cool granite setts (weathered tint read as dirt from the air)
		"turf": m = Palette.mat_textured(Color(0.24, 0.33, 0.16), "soil", Vector3.ONE, 0.95)
		"kerb": m = Palette.mat_textured(Color(0.72, 0.70, 0.65), "concrete", Vector3.ONE, 0.88)
		"granite": m = Palette.mat_textured(Color(0.43, 0.42, 0.40), "concrete", Vector3.ONE, 0.9)
		"granite_coping": m = Palette.mat_textured(Color(0.52, 0.51, 0.48), "concrete", Vector3.ONE, 0.85)
		"granite_light": m = Palette.mat_textured(Color(0.74, 0.72, 0.66), "concrete", Vector3.ONE, 0.86)
		"concrete_bridge": m = Palette.mat_textured(Color(0.60, 0.60, 0.58), "concrete", Vector3.ONE, 0.9)
		"cream_render": m = Palette.mat_textured(Color(0.86, 0.81, 0.70), "plaster", Vector3.ONE, 0.85)
		"wet": m = Palette.mat(Color(0.19, 0.19, 0.18), 0.35)
		"algae": m = Palette.mat(Color(0.12, 0.15, 0.10), 0.6)
		"steel_white": m = Palette.mat(Color(0.88, 0.88, 0.86), 0.4, 0.5)
		"steel_rail": m = Palette.mat(Color(0.33, 0.35, 0.36), 0.45, 0.7)
		"lamp_pole": m = Palette.mat(Color(0.20, 0.22, 0.23), 0.5, 0.6)
		"lamp_head": m = Palette.emissive(Color(1.0, 0.86, 0.62), 1.6)
		"hoarding": m = Palette.mat_textured(Color(0.17, 0.36, 0.27), "concrete", Vector3.ONE, 0.8)
		"hoarding_band": m = Palette.mat(Color(0.92, 0.92, 0.88), 0.7)
		"paint_white": m = Palette.road_paint(Color(0.90, 0.90, 0.86))
		"paint_yellow": m = Palette.road_paint(Color(0.92, 0.72, 0.16))
		"glass_rail":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.55, 0.70, 0.72, 0.35)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.roughness = 0.1
			g.metallic = 0.2
			m = g
		_: m = Palette.mat(Color(0.5, 0.5, 0.5), 0.9)
	_mats[key] = m
	return m

const NO_SHADOW := ["asphalt", "ground", "pavers", "pavers_warm", "pavers_bridge", "plaza", "plot", "turf", "paint_white", "paint_yellow", "wet", "algae", "kerb", "granite_coping"]

# ------------------------------------------------------------ geometry
func _surf(key: String, p: Vector3) -> SurfaceTool:
	var cell := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var k := "%s|%d|%d" % [key, cell.x, cell.y]
	if not _st.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[k] = {"st": st, "key": key, "n": 0}
	_st[k]["n"] += 1
	return _st[k]["st"]

## Triangle with an explicit outward normal (winding fixed for Godot's
## clockwise front faces).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (c - a).cross(b - a).dot(n) < 0.0:
		var tmp := b
		b = c
		c = tmp
	st.set_normal(n)
	st.set_uv(Vector2(a.x, a.z)); st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z)); st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z)); st.add_vertex(c)

func quad_dir(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var st := _surf(key, (a + c) * 0.5)
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)

## Upward-facing quad (roads, decks, paving).
func quad_up(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(d - a)
	if n.y < 0.0:
		n = -n
	quad_dir(key, a, b, c, d, n.normalized() if n.length() > 0.0001 else Vector3.UP)

## Vertical-ish quad whose outward normal points to `side` of the a->b line
## (+1 = left of travel, -1 = right).
func quad_side(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, side: float) -> void:
	var f := b - a
	f.y = 0.0
	var left := Vector3(f.z, 0.0, -f.x).normalized()
	quad_dir(key, a, b, c, d, left * side)

func box_basis(key: String, center: Vector3, size: Vector3, basis: Basis) -> void:
	var h := size * 0.5
	var ax := basis.x.normalized()
	var ay := basis.y.normalized()
	var az := basis.z.normalized()
	var corner := func(sx: float, sy: float, sz: float) -> Vector3:
		return center + ax * (h.x * sx) + ay * (h.y * sy) + az * (h.z * sz)
	var faces := [
		[ay, [-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]],
		[-ay, [-1, -1, -1], [-1, -1, 1], [1, -1, 1], [1, -1, -1]],
		[ax, [1, -1, -1], [1, -1, 1], [1, 1, 1], [1, 1, -1]],
		[-ax, [-1, -1, -1], [-1, 1, -1], [-1, 1, 1], [-1, -1, 1]],
		[az, [-1, -1, 1], [-1, 1, 1], [1, 1, 1], [1, -1, 1]],
		[-az, [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1]],
	]
	for f in faces:
		var pts: Array[Vector3] = []
		for k in range(1, 5):
			var s: Array = f[k]
			pts.append(corner.call(float(s[0]), float(s[1]), float(s[2])))
		quad_dir(key, pts[0], pts[1], pts[2], pts[3], f[0])

func box(key: String, center: Vector3, size: Vector3) -> void:
	box_basis(key, center, size, Basis.IDENTITY)

## Basis for a box running from a to b (x across, y up, z along a->b).
static func seg_basis(a: Vector3, b: Vector3) -> Basis:
	var along := b - a
	if along.length() < 0.001:
		return Basis.IDENTITY
	along = along.normalized()
	var across := Vector3.UP.cross(along).normalized()
	var up := along.cross(across).normalized()
	return Basis(across, up, along)

func pitched_box_visual(key: String, a: Vector3, b: Vector3, width: float, height: float, offset: Vector3) -> void:
	var basis := seg_basis(a, b)
	box_basis(key, (a + b) * 0.5 + offset, Vector3(width, height, a.distance_to(b) + 0.05), basis)

## Collision box from a to b (top surface on the a-b line + offset).
func pitched_box(a: Vector3, b: Vector3, width: float, height: float, offset: Vector3, _thin: bool = false) -> void:
	var basis := seg_basis(a, b)
	col_box(Vector3(width, height, a.distance_to(b) + 0.3), (a + b) * 0.5 + offset, basis)

func drive_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_drive_faces.append_array([a, b, c, a, c, d])

func col_box(size: Vector3, center: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.transform = Transform3D(basis.orthonormalized(), center)
	body.add_child(shape)
	shapes += 1

# ------------------------------------------------------------ props
func lamp(pos: Vector3, style: String = "modern") -> void:
	(_lamps[style] as Array).append(pos)

func post(pos: Vector3, h: float) -> void:
	_posts.append(Transform3D(Basis.from_scale(Vector3(0.07, h, 0.07)), pos + Vector3(0, h * 0.5, 0)))

func tree(pos: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(s * rng.randf_range(0.9, 1.1), s * rng.randf_range(0.9, 1.1), s * rng.randf_range(0.9, 1.1)))
	_trees.append(Transform3D(b, pos))
	# trunk collision only (leaf envelopes never become invisible walls)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.45 * s
	cyl.height = 4.8 * s
	shape.shape = cyl
	shape.position = pos + Vector3(0, 2.4 * s, 0)
	body.add_child(shape)
	shapes += 1

func label_name(p: Dictionary) -> void:
	var name_text := String(p["name"]).replace("_", " ").capitalize()
	var lbl := Label3D.new()
	lbl.text = name_text.to_upper()
	lbl.font_size = 64
	lbl.pixel_size = 0.012
	lbl.modulate = Color(0.95, 0.93, 0.86)
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0.1, 0.1, 0.1, 0.8)
	var q := Bridges.deck_point(p, -float(p["span"]) + 3.0, float(p["w"]) + 0.08, 0.0)
	lbl.position = Vector3(q.x, Bridges.profile_h(p, -float(p["span"]) + 3.0) - 0.45, q.z)
	var d: Vector3 = p["d"]
	lbl.rotation.y = atan2(d.x, d.z) - PI * 0.5
	lbl.visibility_range_end = 220.0
	root.add_child(lbl)

func _unit_mesh(kind: String) -> Mesh:
	match kind:
		"pole":
			var c := CylinderMesh.new()
			c.top_radius = 0.07
			c.bottom_radius = 0.11
			c.height = 1.0
			c.radial_segments = 8
			c.rings = 1
			return c
		"head":
			var b := BoxMesh.new()
			b.size = Vector3(0.36, 0.16, 1.3)
			return b
		"globe":
			var s := SphereMesh.new()
			s.radius = 0.28
			s.height = 0.56
			s.radial_segments = 10
			s.rings = 6
			return s
	var u := BoxMesh.new()
	u.size = Vector3.ONE
	return u

func _mm(mesh: Mesh, xforms: Array, material: Material, shadow: bool, vis_end: float, node_name: String) -> void:
	if xforms.is_empty():
		return
	var by_cell := {}
	for xf: Transform3D in xforms:
		var cell := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
		if not by_cell.has(cell):
			by_cell[cell] = []
		by_cell[cell].append(xf)
	for cell in by_cell:
		var list: Array = by_cell[cell]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = node_name
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_end > 0.0:
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = 30.0
		mmi.set_meta("downtown_map", true)
		if "--sightline-probe" in OS.get_cmdline_user_args():
			mmi.set_meta("probe_xforms", list.duplicate())
		root.add_child(mmi)
		stats["draws"] = int(stats.get("draws", 0)) + 1

func _flush() -> void:
	if not _drive_faces.is_empty():
		var tri := ConcavePolygonShape3D.new()
		tri.backface_collision = true
		tri.set_faces(_drive_faces)
		var cs := CollisionShape3D.new()
		cs.name = "DowntownDriveSurface"
		cs.shape = tri
		body.add_child(cs)
		shapes += 1
	for k in _st:
		var e: Dictionary = _st[k]
		var st: SurfaceTool = e["st"]
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "DowntownMap_" + String(e["key"])
		mi.mesh = mesh
		mi.material_override = mat(e["key"])
		var base_key := String(e["key"]).trim_suffix("_soffit")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if base_key in NO_SHADOW else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if base_key in ["steel_rail", "glass_rail", "hoarding_band"]:
			mi.visibility_range_end = float(DowntownPlan.PERF["vis_detail_end"]) + 150.0
			mi.visibility_range_end_margin = 30.0
		mi.set_meta("downtown_map", true)
		root.add_child(mi)
		stats["draws"] = int(stats.get("draws", 0)) + 1
	_st.clear()
	# lamps: pole + arm head (modern) or pole + lantern globe (heritage)
	var poles: Array = []
	var heads: Array = []
	var globes: Array = []
	for pos: Vector3 in _lamps["modern"]:
		poles.append(Transform3D(Basis.from_scale(Vector3(1, 8.5, 1)), pos + Vector3(0, 4.25, 0)))
		heads.append(Transform3D(Basis.IDENTITY, pos + Vector3(0, 8.45, 0)))
	for pos: Vector3 in _lamps["heritage"]:
		poles.append(Transform3D(Basis.from_scale(Vector3(1.1, 4.6, 1.1)), pos + Vector3(0, 2.3, 0)))
		globes.append(Transform3D(Basis.IDENTITY, pos + Vector3(0, 4.85, 0)))
	stats["lamps"] = poles.size()
	_mm(_unit_mesh("pole"), poles, mat("lamp_pole"), false, 600.0, "DowntownLampPoles")
	_mm(_unit_mesh("head"), heads, mat("lamp_head"), false, 600.0, "DowntownLampHeads")
	_mm(_unit_mesh("globe"), globes, mat("lamp_head"), false, 600.0, "DowntownLampGlobes")
	_mm(_unit_mesh("box"), _posts, mat("steel_rail"), false, 300.0, "DowntownRailPosts")
	_batch_trees()
	stats["trees"] = _trees.size()

## Rain trees (the existing project GLB, ~32k tris each) batched per 400 m
## cell with a visibility range, so only nearby groves are drawn.
func _batch_trees() -> void:
	if _trees.is_empty():
		return
	var packed: PackedScene = load("res://assets/authored/rain_tree.glb")
	var source: Node = packed.instantiate()
	var parts: Array[Dictionary] = []
	world._background_mesh_parts(source, Transform3D.IDENTITY, parts)
	var by_cell := {}
	for xf: Transform3D in _trees:
		var cell := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
		if not by_cell.has(cell):
			by_cell[cell] = []
		by_cell[cell].append(xf)
	for cell in by_cell:
		var list: Array = by_cell[cell]
		for part in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part["mesh"]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, (list[i] as Transform3D) * (part["transform"] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "DowntownTrees"
			mmi.multimesh = mm
			mmi.material_override = part["override"]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 650.0
			mmi.visibility_range_end_margin = 60.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.set_meta("downtown_map", true)
			root.add_child(mmi)
			stats["draws"] = int(stats.get("draws", 0)) + 1
	source.free()
