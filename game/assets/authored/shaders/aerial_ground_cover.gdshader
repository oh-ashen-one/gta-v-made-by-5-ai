// Planted ground cover for open block-interior patches (aerial piece, Opus 5.5
// wave R; see src/world/aerial_fill.gd). World-space and original: a mown
// lawn with tonal mottling, darker shrub beds and leaf litter under the trees,
// worn earth desire paths and a granite edging strip where the bed meets the
// paving. Reads as planted landscape from a helicopter and as a lawn on foot.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

varying vec3 wpos;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.3) * 0.28 + vnoise(p * 4.1 - 2.1) * 0.14 + vnoise(p * 8.3 + 1.7) * 0.08; }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = wpos.xz;
	float fw = length(fwidth(q));
	float big = fbm(q * 0.035);
	float mid = fbm(q * 0.16 + 11.0);
	float fine = mix(vnoise(q * 1.7) * 0.6 + vnoise(q * 5.3) * 0.4, 0.5, clamp(fw * 0.6, 0.0, 1.0));
	// Lawn: humid tropical carpet grass, yellower where it is thin.
	vec3 lawn = mix(lin(vec3(0.27, 0.40, 0.15)), lin(vec3(0.42, 0.47, 0.20)), smoothstep(0.35, 0.75, big));
	lawn *= 0.82 + 0.3 * mid;
	lawn *= 0.9 + 0.2 * fine;
	// Shrub beds: dense dark planting in organic blobs.
	float bed = smoothstep(0.56, 0.62, fbm(q * 0.07 + 31.0));
	vec3 shrubs = mix(lin(vec3(0.10, 0.20, 0.08)), lin(vec3(0.18, 0.28, 0.10)), fine) * (0.8 + 0.4 * mid);
	// Leaf-litter / mulch rings.
	float litter = smoothstep(0.66, 0.74, fbm(q * 0.11 - 5.0)) * (1.0 - bed);
	vec3 mulch = lin(vec3(0.33, 0.25, 0.17)) * (0.8 + 0.3 * fine);
	// Worn desire paths: thin meandering bands.
	float path_n = abs(fbm(q * 0.045 + 3.3) - 0.5);
	float path = (1.0 - smoothstep(0.012, 0.022 + fw * 0.01, path_n)) * (1.0 - bed) * 0.75;
	vec3 earth = lin(vec3(0.46, 0.38, 0.28));
	vec3 c = lawn;
	c = mix(c, mulch, litter * 0.7);
	c = mix(c, earth, path);
	c = mix(c, shrubs, bed);
	ALBEDO = c;
	ROUGHNESS = mix(0.93, 0.85, bed);
	SPECULAR = 0.28;
	METALLIC = 0.0;
	// Small-scale relief so grazing sun picks out the texture.
	vec3 nrm = normalize(vec3((vnoise(q * 3.1) - 0.5) * 0.35 + (bed - 0.5) * 0.0, 1.0, (vnoise(q * 3.1 + 9.0) - 0.5) * 0.35));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	AO = mix(1.0, 0.75, bed);
	AO_LIGHT_AFFECT = 0.2;
}
