class_name BayWater
extends Node3D
## The bay (water piece, Opus 5.5 loop wave A).
##
## Replaces the flat translucent plane that read as paving with:
## - an animated opaque water surface (assets/authored/shaders/bay_water.gdshader)
##   lit by a planar reflection: a half-resolution mirrored camera renders the
##   skyline, sky and boats into reflection_tex every frame;
## - granite seawalls with a wet band and algae line at the waterline, a stone
##   Merlion pier base and a floating pontoon with moored bumboats;
## - procedural bumboats and river cruisers on loops across the bay, drawn as
##   one MultiMesh per hull type, with Kelvin-wedge wakes in the water shader;
## - a translucent falling-water Merlion jet with splash spray, replacing the
##   opaque white strut that shipped inside merlion_landmark.glb.
## Everything is procedural and original (see docs/ASSET_RIGHTS.md).

const LEVEL := -0.9
## Render layer 20: the water itself (never drawn into its own reflection).
const WATER_LAYER := 1 << 19
## Render layer 19: geometry that dips below the waterline; the mirrored
## camera sits under the water, so it must not see these from beneath.
const SUBMERGED_LAYER := 1 << 18
const NEAR_SHORE_Z := -350.7
const FAR_SHORE_Z := -615.0
const BOAT_SHADER := "res://assets/authored/shaders/bay_boat.gdshader"
const WATER_SHADER := "res://assets/authored/shaders/bay_water.gdshader"
const JET_SHADER := "res://assets/authored/shaders/water_jet.gdshader"

var water: MeshInstance3D
var water_material: ShaderMaterial
var jet: MeshInstance3D
var reflection_viewport: SubViewport
var reflection_camera: Camera3D
var boat_count := 0
var moving_boats := 0
var legacy_spray_hidden := 0
var reflection_active := false

var _builder: Node
var _boats: Array[Dictionary] = []
var _multimeshes := {}
var _time := 0.0
var _source_env: Environment
var _reflection_env: Environment
var _jet_impact := Vector3.ZERO
var _pier_rect := Vector4.ZERO
var _pontoon_rect := Vector4(-44.0, -357.2, -22.0, -351.8)

static func build(builder: Node, root: Node3D, merlion: Node3D, merlion_pos: Vector3) -> BayWater:
	var bay := BayWater.new()
	bay.name = "Bay"
	bay._builder = builder
	root.add_child(bay)
	bay._build(merlion, merlion_pos)
	return bay

func _build(merlion: Node3D, merlion_pos: Vector3) -> void:
	process_priority = 1000
	_build_water()
	_build_edges(merlion_pos)
	_build_merlion_jet(merlion, merlion_pos)
	_build_boats()
	water_material.set_shader_parameter("pier_rect", _pier_rect)
	water_material.set_shader_parameter("pontoon_rect", _pontoon_rect)
	water_material.set_shader_parameter("jet_impact", _jet_impact)
	_update_boats(0.0)
	if DisplayServer.get_name() != "headless":
		_build_reflection()
	# The district is batched after this runs; classify submerged geometry
	# once the whole world exists.
	_classify_submerged.call_deferred()

# ------------------------------------------------------------------ water
func _build_water() -> void:
	water = MeshInstance3D.new()
	water.name = "BayWaterSurface"
	var pm := PlaneMesh.new()
	# One sea plane under the whole map, out to the haze on every horizon
	# (Singapore is an island). Land slabs sit on top of it and hide it.
	pm.size = Vector2(16000.0, 16000.0)
	water.mesh = pm
	water_material = ShaderMaterial.new()
	water_material.shader = load(WATER_SHADER)
	water_material.set_shader_parameter("water_level", LEVEL)
	water_material.set_shader_parameter("near_shore_z", NEAR_SHORE_Z)
	water_material.set_shader_parameter("far_shore_z", FAR_SHORE_Z)
	# Glint cap (wave-5 critic: a blown white disc beside the helicopter).
	water_material.set_shader_parameter("spec_cap", 0.32)
	water.material_override = water_material
	water.position = Vector3(0.0, LEVEL, 0.0)
	water.layers = WATER_LAYER
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.set_meta("bay_water", true)
	add_child(water)

# ------------------------------------------------------------- shoreline
func _edge_box(size: Vector3, pos: Vector3, color: Color, rough: float, kind: String = "concrete") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := Palette.mat_textured(color, kind, Vector3.ONE, rough) if kind != "" else Palette.mat(color, rough)
	mi.material_override = m
	mi.position = pos
	mi.layers = SUBMERGED_LAYER
	# meta keeps these out of the static batcher (they need their own layer)
	mi.set_meta("bay_edge", true)
	add_child(mi)
	return mi

func _build_edges(merlion_pos: Vector3) -> void:
	var granite := Color(0.43, 0.42, 0.40)
	var wet := Color(0.19, 0.19, 0.18)
	var algae := Color(0.12, 0.15, 0.10)
	# Near seawall: dressed granite face down into the water, a pale coping
	# lip at deck level, a dark wet band and a thin algae line at the waterline.
	_edge_box(Vector3(1500.0, 3.4, 0.9), Vector3(0.0, -1.38, -350.25), granite, 0.9)
	_edge_box(Vector3(700.0, 0.16, 1.2), Vector3(0.0, 0.36, -349.9), Color(0.70, 0.68, 0.64), 0.85)
	_edge_box(Vector3(1500.0, 0.75, 0.06), Vector3(0.0, LEVEL + 0.42, -350.73), wet, 0.35, "")
	_edge_box(Vector3(1500.0, 0.16, 0.08), Vector3(0.0, LEVEL + 0.06, -350.74), algae, 0.6, "")
	# Far shore: the existing concrete edge gets the same wet band.
	_edge_box(Vector3(1700.0, 0.8, 0.06), Vector3(0.0, LEVEL + 0.40, FAR_SHORE_Z + 0.03), wet, 0.35, "")
	_edge_box(Vector3(1700.0, 0.16, 0.08), Vector3(0.0, LEVEL + 0.05, FAR_SHORE_Z + 0.04), algae, 0.6, "")
	# Merlion pier: a stone base under the existing deck so it no longer floats.
	var pier := Vector3(merlion_pos.x, 0.0, merlion_pos.z - 2.0)
	_edge_box(Vector3(14.2, 3.2, 14.2), pier + Vector3(0.0, -1.62, 0.0), granite, 0.9)
	_edge_box(Vector3(14.32, 0.75, 14.32), pier + Vector3(0.0, LEVEL + 0.42, 0.0), wet, 0.35, "")
	_pier_rect = Vector4(pier.x - 7.1, pier.z - 7.1, pier.x + 7.1, pier.z + 7.1)
	# Floating pontoon west of the pier: composite deck on dark floats,
	# mooring bollards, two bumboats tied up alongside (see _build_boats).
	var pc := Vector3((_pontoon_rect.x + _pontoon_rect.z) * 0.5, LEVEL, (_pontoon_rect.y + _pontoon_rect.w) * 0.5)
	var pw := _pontoon_rect.z - _pontoon_rect.x
	var pd := _pontoon_rect.w - _pontoon_rect.y
	var deck := _edge_box(Vector3(pw, 0.22, pd), pc + Vector3(0.0, 0.52, 0.0), Color(0.46, 0.38, 0.30), 0.85, "pavers")
	deck.layers = 1
	_edge_box(Vector3(pw - 0.4, 0.6, pd - 0.5), pc + Vector3(0.0, 0.16, 0.0), Color(0.10, 0.11, 0.12), 0.5, "")
	for i: int in 5:
		var bx := _pontoon_rect.x + 1.0 + i * (pw - 2.0) / 4.0
		var bol := _edge_box(Vector3(0.32, 0.45, 0.32), Vector3(bx, LEVEL + 0.85, _pontoon_rect.y + 0.35), Color(0.20, 0.21, 0.22), 0.5, "")
		bol.layers = 1
	if _builder != null and _builder.has_method("_collision_box"):
		_builder._collision_box(Vector3(pw, 0.3, pd), pc + Vector3(0.0, 0.5, 0.0))
	# The avenues run 30 m past the seawall as slabs over the water; give them
	# pile bents and a deck fascia so they read as jetties, not floating roads.
	var pile_mesh := CylinderMesh.new()
	pile_mesh.top_radius = 0.42
	pile_mesh.bottom_radius = 0.48
	pile_mesh.height = 3.4
	pile_mesh.radial_segments = 10
	pile_mesh.rings = 1
	pile_mesh.material = Palette.mat_textured(Color(0.40, 0.39, 0.37), "concrete", Vector3.ONE, 0.9)
	var piles: Array[Transform3D] = []
	for x in [-320.0, -160.0, 0.0, 160.0, 320.0]:
		for z in [-357.0, -365.0, -373.0, -379.0]:
			for side in [-1.0, 1.0]:
				piles.append(Transform3D(Basis.IDENTITY, Vector3(x + side * 6.5, -1.7, z)))
		_edge_box(Vector3(16.6, 0.55, 29.6), Vector3(x, -0.26, -365.4), Color(0.30, 0.30, 0.29), 0.9)
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.mesh = pile_mesh
	pmm.instance_count = piles.size()
	for i in piles.size():
		pmm.set_instance_transform(i, piles[i])
	var pmi := MultiMeshInstance3D.new()
	pmi.name = "JettyPiles"
	pmi.multimesh = pmm
	pmi.layers = SUBMERGED_LAYER
	add_child(pmi)

## Anything in the district whose bounds dip under the waterline and stays
## low (ground slabs, quay edges) is hidden from the mirrored camera only.
func _classify_submerged() -> void:
	var root := get_parent()
	if root == null:
		return
	var stack: Array[Node] = [root]
	var hidden := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c != self:
				stack.append(c)
		if n is GeometryInstance3D and n is VisualInstance3D:
			var gi := n as GeometryInstance3D
			var aabb: AABB = gi.global_transform * gi.get_aabb()
			if aabb.position.y < LEVEL - 0.3 and aabb.end.y < 1.2:
				gi.layers = SUBMERGED_LAYER
				hidden += 1
	print("[bay] submerged geometry hidden from reflection: ", hidden)

# ------------------------------------------------------------ Merlion jet
func _build_merlion_jet(merlion: Node3D, merlion_pos: Vector3) -> void:
	if merlion != null:
		var stack: Array[Node] = [merlion]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is MeshInstance3D and (String(n.name).contains("water_spray") or String(n.name).contains("water_jet")):
				(n as MeshInstance3D).visible = false
				legacy_spray_hidden += 1
	# Parabola of the original authored spout (mouth at local (0, 9.8, -2.1)),
	# extended down to the real waterline.
	var pts: Array[Vector3] = []
	var radii: Array[float] = []
	var steps := 44
	var u_end := 1.0
	var target := LEVEL - merlion_pos.y - 0.2
	# solve 9.8 + 2.2u - 11.4u^2 = target
	u_end = (2.2 + sqrt(2.2 * 2.2 + 4.0 * 11.4 * (9.8 - target))) / (2.0 * 11.4)
	for k in steps + 1:
		var u := u_end * float(k) / float(steps)
		var y := 9.8 + 2.2 * u - 11.4 * u * u
		var z := -(2.1 + u * 11.5)
		pts.append(merlion_pos + Vector3(0.0, y, z))
		var f := float(k) / float(steps)
		radii.append(0.20 + 0.55 * f * f + 0.08 * f)
	_jet_impact = Vector3(pts[-1].x, LEVEL, pts[-1].z)
	var core_mat := ShaderMaterial.new()
	core_mat.shader = load(JET_SHADER)
	jet = MeshInstance3D.new()
	jet.name = "MerlionJet"
	jet.mesh = _tube(pts, radii, 14)
	jet.material_override = core_mat
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(jet)
	# a looser, fainter sheath of spray around the core
	var sheath_radii: Array[float] = []
	for r in radii:
		sheath_radii.append(r * 1.9 + 0.05)
	var sheath_mat := ShaderMaterial.new()
	sheath_mat.shader = core_mat.shader
	sheath_mat.set_shader_parameter("opacity", 0.30)
	sheath_mat.set_shader_parameter("flow_speed", 2.3)
	var sheath := MeshInstance3D.new()
	sheath.name = "MerlionJetSpray"
	sheath.mesh = _tube(pts, sheath_radii, 12)
	sheath.material_override = sheath_mat
	sheath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheath)
	_splash(_jet_impact)
	_jet_droplets(pts)

## Droplets peeling off the falling stream, thrown along its direction.
func _jet_droplets(pts: Array[Vector3]) -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.roughness = 0.4
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	quad.material = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.95, 0.97, 0.98, 0.0))
	ramp.set_color(1, Color(0.95, 0.97, 0.98, 0.0))
	ramp.add_point(0.1, Color(0.95, 0.97, 0.98, 0.85))
	ramp.add_point(0.7, Color(0.95, 0.97, 0.98, 0.55))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	for f in [0.35, 0.55, 0.75]:
		var i := int(f * float(pts.size() - 1))
		var dir: Vector3 = (pts[i + 1] - pts[i]).normalized()
		var p := GPUParticles3D.new()
		p.name = "MerlionDroplets"
		p.amount = 70
		p.lifetime = 0.9
		p.preprocess = 1.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.35 + f * 0.4
		pm.direction = dir
		pm.spread = 14.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 6.0
		pm.gravity = Vector3(0.0, -9.8, 0.0)
		pm.scale_min = 0.6
		pm.scale_max = 1.6
		pm.color_ramp = ramp_tex
		p.process_material = pm
		p.draw_pass_1 = quad
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-6, -12, -6), Vector3(12, 16, 12))
		p.position = pts[i]
		add_child(p)

func _tube(pts: Array[Vector3], radii: Array[float], sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in pts.size():
		var tangent: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := tangent.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(tangent).normalized()
		var ring: Array = []
		for s in sides + 1:
			var a := TAU * float(s) / float(sides)
			var n := side * cos(a) + up * sin(a)
			ring.append([pts[i] + n * radii[i], n, Vector2(float(s) / float(sides), float(i) / float(pts.size() - 1))])
		rings.append(ring)
	for i in pts.size() - 1:
		for s in sides:
			var a: Array = rings[i][s]
			var b: Array = rings[i][s + 1]
			var c: Array = rings[i + 1][s + 1]
			var d: Array = rings[i + 1][s]
			for v in [a, b, c, a, c, d]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
	return st.commit()

func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex

func _splash(at: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.roughness = 0.9
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	quad.material = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.92, 0.95, 0.96, 0.0))
	ramp.set_color(1, Color(0.92, 0.95, 0.96, 0.0))
	ramp.add_point(0.12, Color(0.94, 0.96, 0.97, 0.55))
	ramp.add_point(0.6, Color(0.90, 0.93, 0.95, 0.25))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	# droplets thrown up where the jet hits
	var spray := GPUParticles3D.new()
	spray.name = "MerlionSplash"
	spray.amount = 320
	spray.lifetime = 1.3
	spray.preprocess = 2.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3(0.0, 1.0, -0.35)
	pm.spread = 34.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.35
	pm.scale_max = 0.9
	pm.color_ramp = ramp_tex
	spray.process_material = pm
	spray.draw_pass_1 = quad
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spray.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 10, 16))
	spray.position = at + Vector3(0.0, 0.2, 0.0)
	add_child(spray)
	# slow mist rising off the impact
	var mist := GPUParticles3D.new()
	mist.name = "MerlionMist"
	mist.amount = 36
	mist.lifetime = 3.2
	mist.preprocess = 4.0
	var mm := ParticleProcessMaterial.new()
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mm.emission_sphere_radius = 1.6
	mm.direction = Vector3(0.0, 1.0, 0.0)
	mm.spread = 25.0
	mm.initial_velocity_min = 0.3
	mm.initial_velocity_max = 0.9
	mm.gravity = Vector3(0.4, 0.15, 0.0)
	mm.scale_min = 2.2
	mm.scale_max = 4.0
	var mist_ramp := Gradient.new()
	mist_ramp.set_color(0, Color(0.95, 0.96, 0.97, 0.0))
	mist_ramp.set_color(1, Color(0.95, 0.96, 0.97, 0.0))
	mist_ramp.add_point(0.25, Color(0.95, 0.96, 0.97, 0.10))
	var mist_tex := GradientTexture1D.new()
	mist_tex.gradient = mist_ramp
	mm.color_ramp = mist_tex
	mist.process_material = mm
	mist.draw_pass_1 = quad
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mist.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 14, 20))
	mist.position = at + Vector3(0.0, 0.4, 0.0)
	add_child(mist)

# ------------------------------------------------------------------ boats
func _build_boats() -> void:
	var shader: Shader = load(BOAT_SHADER)
	var bum_mat := ShaderMaterial.new()
	bum_mat.shader = shader
	var types := {
		"bumboat": {"mesh": BoatMeshes.bumboat(), "half": Vector2(5.6, 1.55)},
		"cruiser": {"mesh": BoatMeshes.cruiser(), "half": Vector2(9.2, 2.5)},
		"launch": {"mesh": BoatMeshes.launch(), "half": Vector2(3.6, 1.2)},
	}
	var roof_tints := [Color(0.62, 0.10, 0.08), Color(0.10, 0.22, 0.48), Color(0.80, 0.55, 0.12), Color(0.70, 0.16, 0.10), Color(0.12, 0.38, 0.30), Color(0.85, 0.80, 0.70)]
	# loops: centre x, centre z, radius x, radius z, speed (m/s, sign = direction), boats, type
	var loops := [
		[-110.0, -470.0, 250.0, 70.0, 4.6, 3, "bumboat"],
		[230.0, -455.0, 210.0, 55.0, -5.2, 2, "bumboat"],
		[-430.0, -505.0, 190.0, 60.0, 4.2, 2, "bumboat"],
		[20.0, -540.0, 560.0, 45.0, -6.4, 3, "cruiser"],
		[120.0, -410.0, 140.0, 30.0, 9.0, 1, "launch"],
		[-260.0, -420.0, 120.0, 32.0, -8.0, 1, "launch"],
		[520.0, -520.0, 160.0, 50.0, 5.0, 2, "bumboat"],
		[-60.0, -585.0, 300.0, 16.0, 7.5, 1, "launch"],
	]
	var idx := 0
	for loop in loops:
		for j in int(loop[5]):
			var phase := TAU * float(j) / float(loop[5]) + float(idx) * 0.7
			_boats.append({"type": loop[6], "c": Vector2(loop[0], loop[1]), "r": Vector2(loop[2], loop[3]),
				"speed": float(loop[4]), "phase": phase, "half": types[loop[6]]["half"],
				"tint": roof_tints[idx % roof_tints.size()], "hull": float(idx % 4) / 4.0 + 0.01, "seed": float(idx) * 1.37})
			idx += 1
	moving_boats = _boats.size()
	# two bumboats tied up along the pontoon's bay side
	for k in 2:
		_boats.append({"type": "bumboat", "moored": Vector2(_pontoon_rect.x + 5.8 + k * 11.4, _pontoon_rect.y - 1.9),
			"heading": PI if k == 0 else 0.0, "speed": 0.0, "half": types["bumboat"]["half"],
			"tint": roof_tints[(k + 3) % roof_tints.size()], "hull": float(k * 2) / 4.0 + 0.01, "seed": 9.0 + k})
	boat_count = _boats.size()
	for type_name in types:
		var count := 0
		for b in _boats:
			if b["type"] == type_name:
				count += 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = types[type_name]["mesh"]
		mm.instance_count = count
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Boats_" + type_name
		mmi.multimesh = mm
		mmi.material_override = bum_mat
		mmi.set_meta("bay_boats", true)
		add_child(mmi)
		_multimeshes[type_name] = mm
	var counters := {}
	for b in _boats:
		var t: String = b["type"]
		counters[t] = int(counters.get(t, 0))
		b["slot"] = counters[t]
		counters[t] += 1
		var mm: MultiMesh = _multimeshes[t]
		var tint: Color = b["tint"]
		mm.set_instance_custom_data(b["slot"], Color(tint.r, tint.g, tint.b, b["hull"]))

func boat_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for b in _boats:
		out.append(b.get("pos", Vector3.ZERO))
	return out

func _update_boats(t: float) -> void:
	var packed: Array[Vector4] = []
	var sizes: Array[Vector4] = []
	for b in _boats:
		var p2: Vector2
		var heading: float
		var speed: float = absf(b["speed"])
		if b.has("moored"):
			p2 = b["moored"] + Vector2(sin(t * 0.4 + b["seed"]) * 0.15, cos(t * 0.33 + b["seed"]) * 0.1)
			heading = b["heading"] + sin(t * 0.21 + b["seed"]) * 0.03
		else:
			var c: Vector2 = b["c"]
			var r: Vector2 = b["r"]
			var mean_r := (r.x + r.y) * 0.5
			var ang: float = b["phase"] + t * float(b["speed"]) / mean_r
			p2 = c + Vector2(cos(ang) * r.x, sin(ang) * r.y)
			var tangent := Vector2(-sin(ang) * r.x, cos(ang) * r.y) * signf(b["speed"])
			heading = atan2(tangent.y, tangent.x)
		var s: float = b["seed"]
		var bob := sin(t * 1.3 + s) * 0.06 + sin(t * 2.1 + s * 2.0) * 0.03
		var pitch := sin(t * 1.1 + s * 1.3) * 0.012 - speed * 0.004
		var roll := sin(t * 0.9 + s * 0.7) * 0.025
		var basis := Basis(Vector3.UP, -heading) * Basis(Vector3.FORWARD, pitch) * Basis(Vector3.RIGHT, roll)
		var pos := Vector3(p2.x, LEVEL + bob, p2.y)
		b["pos"] = pos
		var mm: MultiMesh = _multimeshes[b["type"]]
		mm.set_instance_transform(b["slot"], Transform3D(basis, pos))
		var half: Vector2 = b["half"]
		packed.append(Vector4(p2.x, p2.y, heading, speed))
		sizes.append(Vector4(half.x, half.y, 0.0, 0.0))
	while packed.size() < 20:
		packed.append(Vector4.ZERO)
		sizes.append(Vector4.ONE)
	if packed.size() > 20:
		packed.resize(20)
		sizes.resize(20)
	water_material.set_shader_parameter("boats", packed)
	water_material.set_shader_parameter("boat_size", sizes)
	water_material.set_shader_parameter("boat_count", mini(_boats.size(), 20))

# ------------------------------------------------------------- reflection
func _build_reflection() -> void:
	reflection_viewport = SubViewport.new()
	reflection_viewport.name = "BayReflection"
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	reflection_viewport.use_hdr_2d = true
	reflection_viewport.msaa_3d = Viewport.MSAA_DISABLED
	reflection_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	reflection_viewport.positional_shadow_atlas_size = 0
	reflection_viewport.mesh_lod_threshold = 3.0
	reflection_viewport.audio_listener_enable_3d = false
	reflection_viewport.size = Vector2i(640, 360)
	add_child(reflection_viewport)
	reflection_camera = Camera3D.new()
	reflection_camera.name = "BayReflectionCamera"
	reflection_camera.cull_mask = 0xFFFFF & ~(WATER_LAYER | SUBMERGED_LAYER)
	reflection_viewport.add_child(reflection_camera)
	reflection_camera.current = true
	water_material.set_shader_parameter("reflection_tex", reflection_viewport.get_texture())

func _sync_environment() -> void:
	var world := get_world_3d()
	var env: Environment = world.environment if world != null else null
	if env == null or env == _source_env:
		return
	_source_env = env
	_reflection_env = env.duplicate() as Environment
	_reflection_env.ssao_enabled = false
	_reflection_env.ssil_enabled = false
	_reflection_env.sdfgi_enabled = false
	_reflection_env.ssr_enabled = false
	_reflection_env.glow_enabled = false
	_reflection_env.adjustment_enabled = false
	_reflection_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_reflection_env.tonemap_exposure = 1.0
	reflection_camera.environment = _reflection_env

## Cheap visibility gate for the reflection pass: street-level cameras deep in
## the district never see the water past the buildings, and anything whose
## frustum misses the bay rectangle skips it too.
func _bay_in_view(cam: Camera3D) -> bool:
	var p := cam.global_position
	if p.z > -170.0 and p.y < 45.0:
		return false
	var corners: Array[Vector3] = []
	for x in [-900.0, 900.0]:
		for z in [NEAR_SHORE_Z, FAR_SHORE_Z]:
			for y in [LEVEL, LEVEL + 0.2]:
				corners.append(Vector3(x, y, z))
	for plane: Plane in cam.get_frustum():
		var outside := true
		for c in corners:
			if not plane.is_point_over(c):
				outside = false
				break
		if outside:
			return false
	return true

func _process(delta: float) -> void:
	if not get_tree().paused:
		_time += delta
	_update_boats(_time)
	if reflection_camera == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam == reflection_camera:
		water_material.set_shader_parameter("reflection_ready", 0.0)
		return
	_sync_environment()
	var vis := get_viewport().get_visible_rect().size
	var want := Vector2i(maxi(64, int(vis.x * 0.5)), maxi(36, int(vis.y * 0.5)))
	if reflection_viewport.size != want:
		reflection_viewport.size = want
	var t := cam.global_transform
	if t.origin.y < LEVEL + 0.05 or not _bay_in_view(cam):
		# Nothing of the bay on screen: skip the mirrored render entirely.
		reflection_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		water_material.set_shader_parameter("reflection_ready", 0.0)
		reflection_active = false
		return
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	reflection_active = true
	var m := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1))
	var b := t.basis.orthonormalized()
	var nb := Basis(m * b.x, -(m * b.y), m * b.z)
	var o := t.origin
	o.y = 2.0 * LEVEL - o.y
	reflection_camera.global_transform = Transform3D(nb, o)
	reflection_camera.fov = cam.fov
	reflection_camera.near = cam.near
	reflection_camera.far = cam.far
	reflection_camera.keep_aspect = cam.keep_aspect
	reflection_camera.h_offset = cam.h_offset
	reflection_camera.v_offset = -cam.v_offset
	water_material.set_shader_parameter("reflection_ready", 1.0)
