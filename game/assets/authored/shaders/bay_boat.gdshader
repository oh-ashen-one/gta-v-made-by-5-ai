shader_type spatial;
// Bay boats (procedural meshes from boat_meshes.gd). Vertex colour alpha picks
// the surface: 1 paint, 0.8 varnished wood, 0.5 glass, 0.2 hull tint,
// 0 canopy tint. INSTANCE_CUSTOM.rgb is the canopy colour, .a the hull palette.
render_mode cull_back;

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float k = COLOR.a;
	float rough = 0.55;
	float metal = 0.0;
	if (k < 0.1) {
		c = custom.rgb * custom.rgb; // canopy tint (sRGB -> approx linear)
		rough = 0.7;
	} else if (k < 0.35) {
		int idx = int(custom.a * 4.0);
		vec3 hulls[4] = vec3[4](vec3(0.32, 0.035, 0.025), vec3(0.025, 0.05, 0.16), vec3(0.03, 0.12, 0.06), vec3(0.40, 0.22, 0.03));
		c = hulls[clamp(idx, 0, 3)];
		rough = 0.35;
	} else if (k < 0.65) {
		rough = 0.06;
		metal = 0.25;
	} else if (k < 0.9) {
		rough = 0.42;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
}
