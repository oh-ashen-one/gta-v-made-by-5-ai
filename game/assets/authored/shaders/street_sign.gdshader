shader_type spatial;
// Street sign plates (nearfield, opus55 wave D). One atlas of original
// pictograms (street_signs_albedo.png, 4 x 2 cells); INSTANCE_CUSTOM.x picks
// the cell. Alpha cuts the plate to the sign's shape; the back face is
// galvanised sheet. Faces carry a slight retro-reflective lift.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sign_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

varying vec2 v_cell;
varying float v_front;

void vertex() {
	float c = INSTANCE_CUSTOM.x;
	v_cell = vec2(mod(c, 4.0), floor(c / 4.0 + 0.01));
	v_front = UV2.x;
}

void fragment() {
	vec2 uv = (clamp(UV, vec2(0.004), vec2(0.996)) + v_cell) / vec2(4.0, 2.0);
	vec4 t = texture(sign_tex, uv);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (v_front > 0.5) {
		// nearfield R: road film and sun fade so faces read as outdoor
		// retro-reflective sheeting, not clean decals: dust settles toward
		// the bottom edge, rain streaks run down, reds fade a little.
		vec2 q = UV * vec2(23.0, 7.0) + v_cell * 13.0;
		float n = fract(sin(dot(floor(q), vec2(12.9898, 78.233))) * 43758.5453);
		float dust = smoothstep(0.35, 1.0, UV.y) * 0.10 + n * 0.04;
		vec3 c = t.rgb;
		c.r = mix(c.r, dot(c, vec3(0.333)) + 0.05, 0.12);
		ALBEDO = c * (0.94 - dust);
		ROUGHNESS = 0.32;
		SPECULAR = 0.55;
		EMISSION = t.rgb * 0.05;
	} else {
		// galvanised back: darker zinc with two riveted stiffener rails and
		// mottled spangle, so a sign seen from behind reads as a sign back,
		// not a blank pale placard (critic, route 05)
		float rail = smoothstep(0.0, 0.01, 0.03 - abs(UV.y - 0.30)) + smoothstep(0.0, 0.01, 0.03 - abs(UV.y - 0.70));
		vec2 q = UV * 31.0;
		float spang = fract(sin(dot(floor(q), vec2(12.9898, 78.233))) * 43758.5453);
		ALBEDO = vec3(0.30, 0.31, 0.31) * (0.9 + 0.12 * spang) * (1.0 - 0.35 * rail);
		METALLIC = 0.65;
		ROUGHNESS = 0.55 + 0.1 * rail;
	}
}
