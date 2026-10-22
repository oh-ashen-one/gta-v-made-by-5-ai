shader_type spatial;
// Bay boats (procedural meshes from boat_meshes.gd). Vertex colour alpha picks
// the surface: 1 paint, 0.8 varnished wood, 0.68 polished steel, 0.5 glass,
// 0.2 hull tint, 0 canopy tint. INSTANCE_CUSTOM.rgb is the canopy colour,
// .a the hull palette. Round 4: gel-coat hulls are glossy with a clear coat
// (critic: GTA's hero boat has "a glossy two-tone hull with real specular
// highlights"), rails and frames are polished steel, glass is dark and wet.
render_mode cull_back;

varying vec4 custom;
varying vec3 obj_pos;

void vertex() {
	custom = INSTANCE_CUSTOM;
	obj_pos = VERTEX;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float k = COLOR.a;
	float rough = 0.42;
	float metal = 0.0;
	float coat = 0.0;
	if (k < 0.1) {
		c = custom.rgb * custom.rgb; // canopy tint (sRGB -> approx linear)
		rough = 0.7;
	} else if (k < 0.35) {
		int idx = int(custom.a * 4.0);
		vec3 hulls[4] = vec3[4](vec3(0.42, 0.03, 0.02), vec3(0.02, 0.05, 0.20), vec3(0.03, 0.16, 0.08), vec3(0.55, 0.30, 0.02));
		c = hulls[clamp(idx, 0, 3)];
		rough = 0.16;
		coat = 1.0;
	} else if (k < 0.6) {
		rough = 0.05;
		metal = 0.3;
		coat = 0.5;
	} else if (k < 0.75) {
		rough = 0.18;
		metal = 1.0;
	} else if (k < 0.9) {
		rough = 0.38;
		coat = 0.6;
	} else {
		rough = 0.30;
		coat = 0.5;
	}
	// waterline grime and faint streaks so hulls are not showroom-clean
	float grime = smoothstep(0.35, 0.0, obj_pos.y) * smoothstep(-0.2, 0.05, obj_pos.y) * 0.25;
	float streak = hash12(vec2(floor(obj_pos.x * 7.0), 3.0)) * smoothstep(0.9, 0.2, obj_pos.y) * 0.08;
	if ((k > 0.1 && k < 0.35) || k > 0.9) {
		c *= 1.0 - grime - streak;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.08;
}
