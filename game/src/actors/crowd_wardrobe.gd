class_name CrowdWardrobe
extends RefCounted
## Street-life M1: real outfit variety for the civilian crowd.
##
## Every civilian is the same provider rig, and the wave-5 WARDROBE tints are
## near-white multiplies over a brown shirt texture, so a rendered crowd read as
## clones of the player (brown shirt, grey trousers). This recolours the two
## clothing surfaces with a luminance-preserving tint: the fabric's own shading,
## folds and normal map stay, the hue and value come from a street-wear palette
## (tops) and a trouser palette (bottoms). One small ShaderMaterial per surface
## per figure, picked from the figure's wardrobe variant, so every person keeps
## the same outfit for life and neighbours rarely match.

const TOPS: Array[Color] = [
	Color(0.86, 0.86, 0.84), Color(0.62, 0.63, 0.64), Color(0.09, 0.09, 0.1), Color(0.11, 0.15, 0.3),
	Color(0.46, 0.6, 0.8), Color(0.62, 0.13, 0.13), Color(0.36, 0.09, 0.12), Color(0.36, 0.39, 0.21),
	Color(0.78, 0.6, 0.2), Color(0.12, 0.43, 0.43), Color(0.86, 0.62, 0.64), Color(0.74, 0.66, 0.52),
	Color(0.56, 0.5, 0.71), Color(0.2, 0.46, 0.26), Color(0.82, 0.44, 0.16), Color(0.27, 0.37, 0.53),
	Color(0.92, 0.9, 0.82), Color(0.3, 0.3, 0.33),
]
const BOTTOMS: Array[Color] = [
	Color(0.2, 0.28, 0.45), Color(0.08, 0.08, 0.09), Color(0.58, 0.52, 0.38), Color(0.12, 0.14, 0.25),
	Color(0.55, 0.56, 0.57), Color(0.72, 0.68, 0.6), Color(0.3, 0.32, 0.22), Color(0.32, 0.4, 0.58),
	Color(0.24, 0.24, 0.26),
]

const SHADER_CODE := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform vec3 tint : source_color = vec3(0.5);
uniform float base_lum = 0.25;
uniform float keep = 0.1;
uniform float roughness = 0.86;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float shade = clamp(l / max(base_lum, 0.03), 0.35, 1.45);
	ALBEDO = mix(tint * shade, c, keep);
	ROUGHNESS = roughness;
	if (has_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		AO = orm.r;
		ROUGHNESS = clamp(orm.g, 0.6, 1.0);
	}
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
"""

static var _shader: Shader
static var _lum_cache := {}

## Recolour a civilian model's clothing for wardrobe `variant`. Returns the
## number of surfaces recoloured.
static func apply(model: Node, variant: int) -> int:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var h := posmod(hash(variant * 2654435761), 1 << 30)
	var top: Color = TOPS[h % TOPS.size()]
	var bottom: Color = BOTTOMS[(h / TOPS.size()) % BOTTOMS.size()]
	# A per-person value jitter so two people in "navy" are not identical.
	var j := 0.88 + float((h / 977) % 25) / 100.0
	var done := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var mname := String(mat.resource_name)
			var tint: Color
			if mname.contains("CharacterClothing"):
				tint = top
			elif mname.contains("CharcoalTextile"):
				tint = bottom
			else:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = _shader
			var tex := mat.albedo_texture
			if tex == null:
				continue
			sm.set_shader_parameter("albedo_tex", tex)
			sm.set_shader_parameter("base_lum", _mean_lum(tex))
			sm.set_shader_parameter("tint", Color(tint.r * j, tint.g * j, tint.b * j))
			if mat.normal_texture != null:
				sm.set_shader_parameter("normal_tex", mat.normal_texture)
				sm.set_shader_parameter("has_normal", true)
			if mat.roughness_texture != null and mname.contains("CharacterClothing"):
				sm.set_shader_parameter("orm_tex", mat.roughness_texture)
				sm.set_shader_parameter("has_orm", true)
			mi.set_surface_override_material(i, sm)
			done += 1
	return done

## Mean luminance of a texture (once per texture), so the tint keeps the
## fabric's relative shading whatever the source colour was.
static func _mean_lum(tex: Texture2D) -> float:
	var key := tex.get_rid().get_id()
	if _lum_cache.has(key):
		return _lum_cache[key]
	var lum := 0.25
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		if not img.is_compressed():
			img = img.duplicate()
			img.resize(16, 16, Image.INTERPOLATE_BILINEAR)
			var acc := 0.0
			var n := 0
			for y in 16:
				for x in 16:
					var c := img.get_pixel(x, y).srgb_to_linear()
					# Ignore near-black atlas padding.
					var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
					if l > 0.02:
						acc += l
						n += 1
			if n > 0:
				lum = acc / n
	_lum_cache[key] = lum
	return lum
