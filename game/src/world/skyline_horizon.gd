class_name SkylineHorizon
extends RefCounted
## Land beyond the bay and a shared aerial perspective (skyline round 4, Opus 5.5).
##
## Critic A3: the CBD stood on a thin flat slab with an abrupt left edge and an
## empty sea band behind it, the far shore read as brown dirt with saplings,
## and the haze was a near-white veil that left the far towers only ~0.05
## darker than the sky, so silhouettes dissolved. This adds:
##  - a procedural city carpet (streets, plots, roofs, parks) over the far
##    shore and a hinterland that runs ~4 km back and wraps both sides of the
##    bay, so the horizon is land and city, not a sea band;
##  - a few thousand low-rise blocks (one MultiMesh) on that carpet, and a
##    third, farther tower layer plus wing estates through SkylineCity, so the
##    city reads in depth layers at ~0.7, ~1.5 and ~3 km;
##  - low wooded ridges at 2.5-4 km as the last silhouette layer;
##  - batched, full-size rain trees along the far-shore promenade;
##  - one place (sync) that takes the live sun direction, sky horizon colour
##    and environment fog and pushes them into every skyline-piece shader.

const CARPET_SHADER := "res://assets/authored/shaders/city_carpet.gdshader"
const HILLS_SHADER := "res://assets/authored/shaders/skyline_hills.gdshader"
const FACADE_SHADER := "res://assets/authored/shaders/skyline_facade.gdshader"
const CRANE_SHADER := "res://assets/authored/shaders/skyline_crane.gdshader"
const SKIRT_SHADER := "res://assets/authored/shaders/skyline_horizon_skirt.gdshader"
const BLOCK_M := 110.0
const STREET_M := 13.0
## Far-shore land (WorldBuilder._perimeter): x -850..850, z -620..-1320.
const SHORE_Z := -628.0
const LAND_FAR_Z := -4300.0
const LAND_HALF_X := 4600.0
const LAND_NEAR_Z := 4400.0

static var _materials: Array[ShaderMaterial] = []
static var _params := {}

var lowrise := 0
var far_towers := 0
var carpet_area := 0.0
var promenade_trees := 0

# ------------------------------------------------------------- atmosphere
## Remember a skyline-piece material so sync() can set its sun / haze inputs.
static func register(mat: ShaderMaterial) -> ShaderMaterial:
	if mat == null:
		return mat
	_materials.append(mat)
	for k in _params:
		mat.set_shader_parameter(k, _params[k])
	return mat

## Read the live sun, sky horizon and environment fog under root and apply
## them to every registered material (and to all registered later).
static func sync(root: Node) -> Dictionary:
	var sun: DirectionalLight3D = null
	var env: Environment = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is WorldEnvironment and env == null:
			env = (n as WorldEnvironment).environment
		elif n is DirectionalLight3D:
			var l := n as DirectionalLight3D
			if l.shadow_enabled and (sun == null or l.light_energy > sun.light_energy):
				sun = l
		if n == root or n.get_parent() == root:
			stack.append_array(n.get_children())
	var p := {}
	if sun != null:
		# Direction toward the sun (the light shines along its local -Z).
		var b := Basis.from_euler(sun.rotation)
		p["sun_dir"] = b.z.normalized()
		p["sun_col"] = sun.light_color
	if env != null:
		if env.fog_enabled:
			p["fog_col"] = env.fog_light_color
			p["fog_density_ref"] = env.fog_density
		if env.sky != null and env.sky.sky_material is ShaderMaterial:
			var sm := env.sky.sky_material as ShaderMaterial
			# "horizon_cool" is the lighting piece's golden_hour_sky (wave A integration).
			for key in ["horizon", "horizon_color", "horizon_col", "sky_horizon", "horizon_cool"]:
				var v: Variant = sm.get_shader_parameter(key)
				if v == null and sm.shader != null:
					v = RenderingServer.shader_get_parameter_default(sm.shader.get_rid(), key)
				if v is Vector3:
					v = Color((v as Vector3).x, (v as Vector3).y, (v as Vector3).z)
				if v is Color:
					# The far land meets a horizon a little paler than the raw sky band.
					p["horizon_col"] = (v as Color).lerp(Color(0.86, 0.84, 0.82), 0.25)
					break
	# Aerial D1: one aerial-perspective setting for every skyline shader.
	p.merge(AerialAtmosphere.HAZE, true)
	_params = p
	for m in _materials:
		if is_instance_valid(m):
			for k in p:
				m.set_shader_parameter(k, p[k])
	return p

static func params() -> Dictionary:
	return _params

# ------------------------------------------------------------- population
## Third (farthest) tower layer and the wing estates, added to the shared
## SkylineCity before it builds (so they share its six draw calls).
func populate(city: SkylineCity) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var before := city.placed
	# Layer 3: a broad, lower city 1.4-2.2 km behind the bay with a second,
	# smaller cluster of towers right of centre (a district centre).
	var z := -1390.0
	while z > -2250.0:
		var x := -1700.0 + rng.randf_range(0.0, 60.0)
		while x < 1700.0:
			var cluster := exp(-pow((x - 650.0) / 300.0, 2.0)) * exp(-pow((z + 1650.0) / 220.0, 2.0))
			var h := rng.randf_range(35.0, 95.0) + cluster * rng.randf_range(60.0, 140.0)
			if rng.randf() < 0.82:
				city.add_random(Vector3(x + rng.randf_range(-12, 12), 0.0, z + rng.randf_range(-15, 15)), h, rng.randf() < 0.5 and cluster < 0.3)
			x += rng.randf_range(62.0, 104.0)
		z -= rng.randf_range(80.0, 120.0)
	# Wing estates either side of the bay, behind the shoreline promenade:
	# HDB-style slabs and mid-rise offices so the left edge of the aerial
	# views is city, not the end of a slab.
	for side in [-1.0, 1.0]:
		var zz := -700.0
		while zz > -1400.0:
			var xx := 900.0 + rng.randf_range(0.0, 40.0)
			while xx < 2100.0:
				var res := rng.randf() < 0.55
				city.add_random(Vector3(side * xx, 0.0, zz + rng.randf_range(-14, 14)), rng.randf_range(36.0, 82.0) + (60.0 if not res and rng.randf() < 0.3 else 0.0), res)
				xx += rng.randf_range(70.0, 120.0)
			zz -= rng.randf_range(70.0, 110.0)
	# HDB new towns ringing the district to the west, east and south at
	# 0.9-2 km: clusters of 12-30 storey slabs (point blocks mixed in).
	for t in 9:
		var ang := -PI * 0.15 + float(t) / 8.0 * PI * 1.3 + rng.randf_range(-0.12, 0.12)
		var rad := rng.randf_range(1050.0, 1750.0)
		var centre := Vector2(sin(ang) * rad, cos(ang) * rad * 0.9 + 250.0)
		for k in rng.randi_range(9, 16):
			var off := Vector2(rng.randf_range(-190.0, 190.0), rng.randf_range(-150.0, 150.0))
			var pos := Vector3(centre.x + off.x, 0.0, centre.y + off.y)
			if not _is_city_land(pos.x, pos.z, 30.0):
				continue
			city.add_random(pos, rng.randf_range(36.0, 95.0), rng.randf() < 0.8)
	far_towers = city.placed - before

# ------------------------------------------------------------------ build
func build(parent: Node3D, city: SkylineCity) -> void:
	_carpet(parent)
	_lowrise(parent, city)
	_hills(parent)
	_skirt(parent)
	_cranes(parent, city)

## Tower cranes over the CBD and the far district (a city still being built,
## as in every real skyline): mast, jib, counter-jib with ballast and cab.
var cranes := 0
func _cranes(parent: Node3D, city: SkylineCity) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := sqrt(2.0)
	# Unit crane, 1.0 = mast height; jib along +x.
	SkylineCity._add_prism(st, 4, k, k, 0.0, 1.0, PI * 0.25, 0.011, 0.011)
	SkylineCity._add_prism(st, 4, k, k, 0.985, 1.0, PI * 0.25, 0.20, 0.008, Vector3(0.17, 0.0, 0.0))
	SkylineCity._add_prism(st, 4, k, k, 0.975, 1.0, PI * 0.25, 0.07, 0.009, Vector3(-0.08, 0.0, 0.0))
	SkylineCity._add_prism(st, 4, k, k, 0.955, 0.985, PI * 0.25, 0.025, 0.014, Vector3(-0.13, 0.0, 0.0))
	SkylineCity._add_prism(st, 4, k, k, 0.955, 0.982, PI * 0.25, 0.015, 0.014, Vector3(0.018, 0.0, 0.0))
	SkylineCity._add_prism(st, 4, k, k, 1.0, 1.07, PI * 0.25, 0.008, 0.008)
	var mesh := st.commit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6061
	var spots: Array[Vector3] = []
	for c in [Vector2(-470.0, -900.0), Vector2(-560.0, -1010.0), Vector2(420.0, -880.0), Vector2(540.0, -960.0), Vector2(-250.0, -1180.0), Vector2(650.0, -1650.0), Vector2(-900.0, -1500.0), Vector2(1200.0, -900.0), Vector2(-1300.0, 600.0)]:
		var p := Vector3(c.x + rng.randf_range(-25.0, 25.0), 0.0, c.y + rng.randf_range(-25.0, 25.0))
		if city._allowed_height(p.x, p.z, 8.0) < 150.0:
			continue
		spots.append(p)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var h := rng.randf_range(150.0, 230.0)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(h, h, h)), spots[i]))
	var mat := ShaderMaterial.new()
	mat.shader = load(CRANE_SHADER)
	register(mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SkylineCranes"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	cranes = spots.size()

func _skirt(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 96
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p00 := Vector3(cos(a0), 0.0, sin(a0))
		var p10 := Vector3(cos(a1), 0.0, sin(a1))
		var p01 := Vector3(cos(a0), 1.0, sin(a0))
		var p11 := Vector3(cos(a1), 1.0, sin(a1))
		for v in [p00, p01, p11, p00, p11, p10]:
			st.set_normal(-Vector3(v.x, 0.0, v.z))
			st.add_vertex(v)
	var mat := ShaderMaterial.new()
	mat.shader = load(SKIRT_SHADER)
	register(mat)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "SkylineHorizonSkirt"
	mi.mesh = mesh
	# The shader moves it to the camera; never frustum-cull it.
	mi.custom_aabb = AABB(Vector3(-1.0e5, -1.0e3, -1.0e5), Vector3(2.0e5, 2.0e3, 2.0e5))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mi)

func _carpet(parent: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(CARPET_SHADER)
	mat.set_shader_parameter("block_m", BLOCK_M)
	mat.set_shader_parameter("street_m", STREET_M)
	register(mat)
	var park := ShaderMaterial.new()
	park.shader = mat.shader
	park.set_shader_parameter("block_m", BLOCK_M)
	park.set_shader_parameter("street_m", STREET_M)
	park.set_shader_parameter("park_bias", 1.0)
	register(park)
	# Far shore behind the landmark plaza (sits just above the old soil slab),
	# the hinterland behind it and both wings. Rects: x0, z0 (far), x1, z1 (near).
	# The playable district stands on WorldBuilder's ground box (x +-750,
	# z -350..750) and the bay water covers x +-800, z -328..-1028; everything
	# else out to ~4.5 km becomes city, so no view sees an empty void or a sea
	# band at the horizon.
	var pieces := [
		[Rect2(-850.0, -1320.0, 1700.0, 470.0), 0.26, mat],      # far shore, behind the plaza / parkland
		[Rect2(-850.0, -850.0, 1700.0, 147.0), 0.26, park],      # waterfront parkland behind the plaza
		[Rect2(-850.0, -703.0, 1700.0, 45.0), 0.33, park],       # lawns and canopy on the back of the promenade
		[Rect2(-850.0, LAND_FAR_Z, 1700.0, -1320.0 - LAND_FAR_Z), 0.05, mat],
		[Rect2(-LAND_HALF_X, LAND_FAR_Z, LAND_HALF_X - 850.0, SHORE_Z - 12.0 - LAND_FAR_Z), 0.05, mat],
		[Rect2(850.0, LAND_FAR_Z, LAND_HALF_X - 850.0, SHORE_Z - 12.0 - LAND_FAR_Z), 0.05, mat],
		[Rect2(-LAND_HALF_X, SHORE_Z - 12.0, LAND_HALF_X - 800.0, -328.0 - SHORE_Z + 12.0), 0.05, mat],
		[Rect2(800.0, SHORE_Z - 12.0, LAND_HALF_X - 800.0, -328.0 - SHORE_Z + 12.0), 0.05, mat],
		[Rect2(-LAND_HALF_X, -328.0, LAND_HALF_X - 750.0, LAND_NEAR_Z + 328.0), 0.05, mat],
		[Rect2(750.0, -328.0, LAND_HALF_X - 750.0, LAND_NEAR_Z + 328.0), 0.05, mat],
		[Rect2(-750.0, 750.0, 1500.0, LAND_NEAR_Z - 750.0), 0.05, mat],
		# Outside the district railings (x +-375, z 375) but still on the
		# ground box: was bare concrete between the flank towers.
		[Rect2(-750.0, -300.0, 352.0, 1050.0), 0.04, mat],
		[Rect2(398.0, -300.0, 352.0, 1050.0), 0.04, mat],
		[Rect2(-398.0, 398.0, 796.0, 352.0), 0.04, mat],
	]
	for piece in pieces:
		var r: Rect2 = piece[0]
		var mi := MeshInstance3D.new()
		mi.name = "SkylineCarpet"
		var pm := PlaneMesh.new()
		pm.size = r.size
		# A few subdivisions keep per-vertex depth sane on km-long planes.
		pm.subdivide_width = int(r.size.x / 400.0)
		pm.subdivide_depth = int(r.size.y / 400.0)
		mi.mesh = pm
		mi.material_override = piece[2]
		mi.position = Vector3(r.position.x + r.size.x * 0.5, float(piece[1]), r.position.y + r.size.y * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		carpet_area += r.size.x * r.size.y
	# Seawalls along the bay's east and west sides, where the bay water now
	# meets the new wing land.
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.62, 0.60, 0.56)
	wall_mat.roughness = 0.9
	for side in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		w.name = "SkylineSeawall"
		var bm := BoxMesh.new()
		bm.size = Vector3(8.0, 2.4, -328.0 - SHORE_Z + 12.0)
		w.mesh = bm
		w.material_override = wall_mat
		w.position = Vector3(side * 804.0, -0.9, (-328.0 + SHORE_Z - 12.0) * 0.5)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(w)

## Low-rise blocks on the carpet's block grid: shophouse rows, walk-ups,
## warehouses and podium blocks, 2-12 storeys, never in a street.
func _lowrise(parent: Node3D, city: SkylineCity) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var bx0 := int(floor(-2900.0 / BLOCK_M))
	var bx1 := int(ceil(2900.0 / BLOCK_M))
	var bz0 := int(floor(-2900.0 / BLOCK_M))
	var bz1 := int(ceil(2700.0 / BLOCK_M))
	for bx in range(bx0, bx1):
		for bz in range(bz0, bz1):
			var ox := bx * BLOCK_M
			var oz := bz * BLOCK_M
			var cx := ox + BLOCK_M * 0.5
			var cz := oz + BLOCK_M * 0.5
			if not _is_city_land(cx, cz, BLOCK_M * 0.5):
				continue
			if rng.randf() < 0.12:
				continue  # a park block
			var dist := Vector2(cx, cz + 300.0).length()
			if dist > 3000.0:
				continue
			var lots := rng.randi_range(3, 6)
			for i in lots:
				var w := rng.randf_range(16.0, 40.0)
				var d := rng.randf_range(14.0, 36.0)
				var px := ox + STREET_M + 3.0 + w * 0.5 + rng.randf_range(0.0, maxf(BLOCK_M - STREET_M - 6.0 - w, 0.0))
				var pz := oz + STREET_M + 3.0 + d * 0.5 + rng.randf_range(0.0, maxf(BLOCK_M - STREET_M - 6.0 - d, 0.0))
				var h := rng.randf_range(7.0, 18.0)
				if rng.randf() < 0.25:
					h += rng.randf_range(8.0, 22.0)
				if dist > 2600.0 and rng.randf() < 0.4:
					continue
				var cap := city._allowed_height(px, pz, maxf(w, d))
				if cap < h + 2.0:
					continue
				var b := Basis.from_scale(Vector3(w, h, d))
				xforms.append(Transform3D(b, Vector3(px, 0.0, pz)))
				var m: int = [5, 5, 3, 0, 5, 1, 6, 2, 5][rng.randi() % 9]
				customs.append(Color((float(m) + 0.5) / 8.0, rng.randf(), rng.randf_range(0.4, 0.75), rng.randf()))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = SkylineCity._box_mesh(0.0, 1.0, 0.5, 0.5)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
	var mat := ShaderMaterial.new()
	mat.shader = load(FACADE_SHADER)
	mat.set_shader_parameter("use_instance_custom", true)
	mat.set_shader_parameter("roof_variety", 1.0)
	mat.set_shader_parameter("form_contrast", 1.0)
	register(mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SkylineLowrise"
	mmi.multimesh = mm
	mmi.material_override = mat
	# Aerial D1: real shadows inside the long aerial shadow range.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mmi)
	lowrise = xforms.size()

## Background city land: outside the playable district box and the bay
## water, and off the far-shore landmark plaza. margin widens the keep-outs.
static func _is_city_land(x: float, z: float, margin: float) -> bool:
	if absf(x) < 398.0 + margin and z > -350.0 - margin and z < 398.0 + margin:
		return false  # playable district (railings at x +-375, z 375)
	if absf(x) < 750.0 + margin and z > -350.0 - margin and z < -300.0 + margin:
		return false  # waterfront edge of the ground box
	if absf(x) < 800.0 + margin and z > SHORE_Z - margin and z < -328.0 + margin:
		return false  # bay water
	if absf(x) < 850.0 and z > -860.0 and z <= SHORE_Z - margin:
		return false  # landmark plaza / waterfront parkland
	return true

## Low wooded ridges 2.6-4 km out: one strip mesh with a noisy crest line.
func _hills(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise := FastNoiseLite.new()
	noise.seed = 1219
	noise.frequency = 0.0011
	noise.fractal_octaves = 4
	var nx := 120
	var rows := [[-2700.0, 0.0], [-2950.0, 0.55], [-3200.0, 1.0], [-3450.0, 0.8], [-3800.0, 0.5], [-4250.0, 0.2]]
	var grid: Array = []
	for r in rows.size():
		var line: Array[Vector3] = []
		for i in nx + 1:
			var x := -LAND_HALF_X + (2.0 * LAND_HALF_X) * float(i) / float(nx)
			var zr: float = rows[r][0] + noise.get_noise_2d(x, 77.0) * 160.0
			var n := noise.get_noise_2d(x, zr) * 0.5 + 0.5
			var hgt: float = rows[r][1] * (40.0 + 150.0 * n * n)
			line.append(Vector3(x, hgt - 2.0, zr))
		grid.append(line)
	for r in rows.size() - 1:
		for i in nx:
			var a: Vector3 = grid[r][i]
			var b: Vector3 = grid[r][i + 1]
			var c: Vector3 = grid[r + 1][i + 1]
			var d: Vector3 = grid[r + 1][i]
			# Front faces toward the bay (+z): emit clockwise from the camera.
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
			st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = load(HILLS_SHADER)
	register(mat)
	var mi := MeshInstance3D.new()
	mi.name = "SkylineHills"
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## Promenade trees on the far shore: the rain-tree GLB batched as MultiMesh
## parts at full size (the old per-node trees at 0.8-1.3 x read as saplings
## from the aerial views). Returns transforms for WorldBuilder._batch_background.
func promenade_tree_transforms(clear: Callable) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3307
	var out: Array = []
	# Clumps and gaps rather than an even avenue: a slow noise thins the rows,
	# trees lean in size from young to mature, and the back rows stagger.
	var thin := FastNoiseLite.new()
	thin.seed = 88
	thin.frequency = 0.012
	for row in [[-646.0, 20.0, 0.30], [-680.0, 16.0, 0.0], [-697.0, 18.0, 0.1], [-720.0, 22.0, -0.1]]:
		var x := -840.0 + rng.randf_range(0.0, 10.0)
		while x < 840.0:
			var p := Vector3(x, 0.35, float(row[0]) + rng.randf_range(-5.0, 5.0))
			if clear.call(p) and thin.get_noise_2d(x, float(row[0])) > float(row[2]) - 0.25:
				var s := rng.randf_range(1.0, 2.5) * (1.0 if rng.randf() < 0.8 else 0.6)
				var b := Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(s * rng.randf_range(0.9, 1.15), s * rng.randf_range(0.85, 1.1), s * rng.randf_range(0.9, 1.15)))
				out.append(Transform3D(b, p))
			x += float(row[1]) * rng.randf_range(0.6, 1.5)
	promenade_trees = out.size()
	return out
