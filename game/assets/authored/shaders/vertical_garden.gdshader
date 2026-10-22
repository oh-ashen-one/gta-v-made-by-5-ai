// Planted surface for the Supertree trunks and canopy beds (wave A, Opus 5.5):
// ferns and creepers in mixed greens, broken by bromeliad and orchid clumps in
// purple, magenta and yellow-green. World-space noise, no UVs needed.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 green_a : source_color = vec3(0.16, 0.30, 0.12);
uniform vec3 green_b : source_color = vec3(0.30, 0.42, 0.16);
uniform vec3 bloom_a : source_color = vec3(0.45, 0.20, 0.42);
uniform vec3 bloom_b : source_color = vec3(0.62, 0.55, 0.20);
uniform float bloom_amount = 0.22;

varying vec3 wpos;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = vnoise3(wpos * 0.9);
	float n2 = vnoise3(wpos * 2.7 + 5.0);
	float n3 = vnoise3(wpos * 0.35 + 11.0);
	vec3 c = mix(green_a, green_b, n1 * 0.7 + n2 * 0.3);
	float bloom = smoothstep(1.0 - bloom_amount, 1.0 - bloom_amount * 0.4, n3 * 0.6 + n2 * 0.4);
	c = mix(c, mix(bloom_a, bloom_b, step(0.55, n1)), bloom);
	// Leaf-scale shading so it reads as foliage texture, not paint.
	c *= 0.72 + 0.45 * n2;
	ALBEDO = c;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	// Fake leaf-clump relief.
	NORMAL_MAP = normalize(vec3(n2 - 0.5, n1 - 0.5, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.8;
}
