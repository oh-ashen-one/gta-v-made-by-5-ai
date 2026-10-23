shader_type spatial;
// Median / planter shrub leaves (nearfield, opus55 wave D). Alpha-cut leaf
// cluster cards from shrub_leaves_albedo.png. Vertex colour carries the
// clump occlusion (dark core and underside) times a per-instance tint, so a
// shrub reads as a dense self-shadowed mass; backlight gives the thin-leaf
// translucency toward a low sun; a small sway keeps it alive.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D leaf_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float wind = 1.0;
uniform float alpha_cut = 0.42;

varying float v_occ;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float lift = clamp(VERTEX.y * 1.8, 0.0, 1.0);
	float s = sin(TIME * 1.7 + wp.x * 0.9 + wp.z * 0.7) + 0.5 * sin(TIME * 3.1 + wp.z * 2.3);
	VERTEX.x += s * 0.010 * wind * lift;
	VERTEX.z += s * 0.006 * wind * lift;
	v_occ = COLOR.g;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 base = t.rgb * COLOR.rgb;
	// occlusion: crush the core more than the crown
	float occ = clamp(v_occ, 0.0, 1.0);
	ALBEDO = base * mix(0.55, 1.12, occ);
	AO = mix(0.35, 1.0, occ);
	AO_LIGHT_AFFECT = 0.45;
	ROUGHNESS = 0.52;
	SPECULAR = 0.38;
	BACKLIGHT = t.rgb * vec3(0.55, 0.75, 0.30) * (0.35 + 0.65 * occ);
	NORMAL_MAP = texture(leaf_nrm, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
}
