class_name LandmarkLooks
extends RefCounted
## Runtime material upgrades for the authored landmark GLBs (wave A, Opus 5.5).
##
## glTF carries only flat PBR values, so a few named landmark materials are
## swapped for procedural shaders after instancing: the Marina Bay Sands
## curtain wall gets floor bands, mullions and per-panel variation; the
## Supertree trunks and canopy beds get a planted vertical-garden surface; the
## Supertree canopy funnel shell is made double-sided. Matching is by the
## Blender material name, so a rebuilt GLB keeps working without code changes.

const FACADE_SHADER := "res://assets/authored/shaders/skyline_facade.gdshader"
const GARDEN_SHADER := "res://assets/authored/shaders/vertical_garden.gdshader"

static var _cache := {}

static func apply(root: Node) -> int:
	if root == null:
		return 0
	var swapped := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is MeshInstance3D:
			continue
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source: Material = mi.mesh.surface_get_material(i)
			if source == null:
				continue
			var replacement := material_for(String(source.resource_name), source)
			if replacement != null:
				mi.set_surface_override_material(i, replacement)
				swapped += 1
	return swapped

static func material_for(material_name: String, source: Material = null) -> Material:
	if _cache.has(material_name):
		return _cache[material_name]
	var result: Material = null
	match material_name:
		"mbs_curtain_glass":
			var m := ShaderMaterial.new()
			m.shader = load(FACADE_SHADER)
			m.set_shader_parameter("style", 0.0)
			m.set_shader_parameter("palette", 0.5)
			m.set_shader_parameter("floor_scale", 0.45)
			m.set_shader_parameter("mullion_m", 1.9)
			m.set_shader_parameter("band_frac", 0.17)
			m.set_shader_parameter("lit_chance", 0.018)
			m.set_shader_parameter("glass_b", Color(0.42, 0.52, 0.58))
			m.set_shader_parameter("frame_col", Color(0.76, 0.75, 0.71))
			result = m
		"near_shore_tower_0", "near_shore_tower_1":
			var t := ShaderMaterial.new()
			t.shader = load(FACADE_SHADER)
			t.set_shader_parameter("style", 0.0)
			t.set_shader_parameter("palette", 0.2 if material_name.ends_with("0") else 0.7)
			t.set_shader_parameter("floor_scale", 0.6)
			t.set_shader_parameter("seed", 0.37 if material_name.ends_with("0") else 0.81)
			t.set_shader_parameter("lit_chance", 0.03)
			result = t
		"st_vertical_garden":
			var g := ShaderMaterial.new()
			g.shader = load(GARDEN_SHADER)
			result = g
		"st_canopy_planting":
			var p := ShaderMaterial.new()
			p.shader = load(GARDEN_SHADER)
			p.set_shader_parameter("bloom_amount", 0.32)
			p.set_shader_parameter("green_a", Color(0.14, 0.26, 0.11))
			result = p
		"st_canopy_shell":
			if source is StandardMaterial3D:
				var s := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
				s.cull_mode = BaseMaterial3D.CULL_DISABLED
				result = s
	_cache[material_name] = result
	return result
