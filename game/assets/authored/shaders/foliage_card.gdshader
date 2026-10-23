shader_type spatial;
// Photographic plant cards (nearfield, opus55 wave R). Crossed vertical cards
// cut from the generated foliage atlas (mondo/spider lily, ixora, croton,
// bird's-nest fern). The card meshes carry hemispherical normals from the
// clump base and are emitted double-sided (both windings), so the clump
// shades as one rounded mass instead of flat planes. Vertex alpha = height
// occlusion (dark base, lit crown); vertex RGB is white, so COLOR.rgb is the
// MultiMesh instance tint (hue and value per plant). Translucent backlight toward a low sun.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.45;
uniform float wind = 1.0;

varying float v_occ;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float lift = clamp(VERTEX.y * 1.2, 0.0, 1.0);
	float s = sin(TIME * 1.3 + wp.x * 0.7 + wp.z * 0.5) + 0.4 * sin(TIME * 2.9 + wp.z * 1.9);
	VERTEX.x += s * 0.012 * wind * lift;
	VERTEX.z += s * 0.008 * wind * lift;
	v_occ = COLOR.a;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	float occ = clamp(v_occ, 0.0, 1.0);
	vec3 base = t.rgb * COLOR.rgb;
	// The generated cards are studio-lit and saturated: pull them toward the
	// LOOK_DEV rule (foliage deep and desaturated, never fighting the built
	// form) - 30 % toward luminance, a touch darker and greener.
	float lum = dot(base, vec3(0.30, 0.55, 0.15));
	base = mix(vec3(lum), base, 0.70) * vec3(0.84, 0.90, 0.78);
	ALBEDO = clamp(base * mix(0.62, 1.05, occ), vec3(0.0), vec3(1.0));
	AO = mix(0.45, 1.0, occ);
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = 0.58;
	SPECULAR = 0.32;
	BACKLIGHT = t.rgb * vec3(0.50, 0.70, 0.28) * (0.3 + 0.6 * occ);
}
