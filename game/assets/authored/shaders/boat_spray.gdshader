shader_type spatial;
// Boat wash geometry (water piece round 4): raised bow spray sheets peeling
// off both shoulders of the hull and a churned white mound behind the
// transom. The critic read the old wakes as "a flat white halo" and "a flat
// decal"; these stand up out of the water. Foam structure is sampled in world
// space, so it stays with the water while the boat drives through it, and it
// tears into lacy holes and loose clumps toward the free edges.
// kind 0: bow sheet (UV.x along, 0 = stem; UV.y across, 0 = hull)
// kind 1: stern churn (UV.x 0 = transom .. 1 = tail; UV.y 0 centre .. 1 edge)
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform float kind = 0.0;
uniform vec3 foam_tint : source_color = vec3(0.93, 0.95, 0.95);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// F2 - F1 of a jittered grid: ~0 on cell borders (bubble walls)
float cell_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash12(i + g), hash12(i + g + 17.3));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

varying vec3 wpos;
varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
	vec3 w0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (kind > 0.5) {
		// churned water heaves: lumps that boil up and collapse in place
		float h = vnoise(w0.xz * 0.9 + vec2(TIME * 1.3, -TIME * 0.6)) * 0.7 + vnoise(w0.xz * 2.6 - vec2(TIME * 2.0, 0.0)) * 0.5;
		VERTEX.y *= 0.25 + 1.3 * h;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = clamp(custom.r, 0.0, 1.4);
	float seed = custom.g * 37.0;
	vec2 uv = UV;
	float t = TIME;
	// world-space foam structure, slowly tumbling
	vec2 q = wpos.xz + vec2(seed, -seed);
	float n1 = vnoise(q * 1.6 + vec2(t * 1.3, -t * 0.7) + wpos.y * 2.0);
	float n2 = vnoise(q * 4.3 - vec2(t * 2.1, t * 0.9) + wpos.y * 5.0);
	float lace = cell_edge(q * 2.2 + vec2(0.0, wpos.y * 3.0) + vec2(t * 0.6, 0.0));
	float n = n1 * 0.55 + n2 * 0.45;
	float cover;
	float streaks = 1.0;
	if (kind < 0.5) {
		// dense white root along the hull, a torn curtain of water ropes
		// above it, thinning toward the free edge and the aft end
		float across = uv.y;
		cover = (1.0 - across * 1.15) * smoothstep(0.0, 0.08, uv.x) * (1.0 - 0.6 * smoothstep(0.6, 1.0, uv.x));
		float ropes = vnoise(vec2(uv.x * 34.0 + seed, uv.y * 2.2 - t * 4.5 * s));
		float fine = vnoise(vec2(uv.x * 85.0 - seed, uv.y * 5.0 - t * 7.0 * s));
		streaks = smoothstep(0.50, 0.66, ropes * 0.65 + fine * 0.45 + (1.0 - across) * 0.18 - uv.x * 0.12);
		cover *= mix(streaks, 1.0, smoothstep(0.15, 0.0, across) * 0.85);
	} else {
		float along = uv.x;
		float side = uv.y;
		cover = (1.05 - along * 1.35) * (1.0 - smoothstep(0.40, 1.0, side) * 0.9);
	}
	cover *= clamp(0.35 + s, 0.0, 1.2);
	// holes open as cover drops: web of bubble walls, then loose clumps
	float web = smoothstep(cover * 0.42 + 0.02, cover * 0.42 - 0.06, lace);
	float body = smoothstep(0.62 - cover * 0.5, 0.80 - cover * 0.5, n + cover * 0.35);
	float a = clamp(max(body, web * 0.85) * smoothstep(0.02, 0.18, cover), 0.0, 1.0);
	if (kind < 0.5) {
		a = min(a, mix(streaks, 1.0, smoothstep(0.15, 0.0, uv.y) * 0.85)) * 0.95;
	}
	if (a < 0.03) {
		discard;
	}
	// aerated water is not paper white: faint aqua where thin, shading in folds
	vec3 col = mix(foam_tint * vec3(0.70, 0.86, 0.88), foam_tint, smoothstep(0.2, 0.9, a));
	col *= 0.86 + 0.14 * n2;
	ALBEDO = col;
	ALPHA = a;
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
	BACKLIGHT = vec3(0.35, 0.42, 0.42);
}
