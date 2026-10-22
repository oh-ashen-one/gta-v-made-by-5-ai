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
		ALBEDO = t.rgb * 0.94;
		ROUGHNESS = 0.32;
		SPECULAR = 0.55;
		EMISSION = t.rgb * 0.05;
	} else {
		ALBEDO = vec3(0.56, 0.57, 0.57);
		METALLIC = 0.7;
		ROUGHNESS = 0.48;
	}
}
