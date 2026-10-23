// Tropical canopy for the procedural fill trees and shrub mounds (aerial
// piece, Opus 5.5 wave R; see src/world/aerial_fill.gd). Original.
// Per instance (MultiMesh custom data): r = colour pick (r > 0.955 flowering:
// flame-of-the-forest orange or trumpet-tree pink), g = tint jitter,
// b = 1 for shrub mounds. Vertex colour = baked crown occlusion; vertex alpha
// 0 = bark. Leaf clumps come from world-space noise in the albedo and the
// normal, with a little back-light so sun-side crowns glow at the rim.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

varying vec3 wpos;
varying vec4 ic;
varying vec4 vcol;
varying vec3 wn;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ic = INSTANCE_CUSTOM;
	vcol = COLOR;
}

void fragment() {
	if (vcol.a < 0.5) {
		float g = vnoise3(wpos * vec3(6.0, 1.2, 6.0));
		ALBEDO = lin(vec3(0.30, 0.26, 0.21)) * (0.7 + 0.5 * g);
		ROUGHNESS = 0.95;
		SPECULAR = 0.2;
	} else {
		float fw = length(fwidth(wpos));
		float clump = vnoise3(wpos * 0.9 + ic.g * 30.0);
		float leaf = mix(vnoise3(wpos * 3.4) * 0.6 + vnoise3(wpos * 7.9) * 0.4, 0.5, clamp(fw * 1.2, 0.0, 1.0));
		// Greens: dark glossy rain-tree, mid tembusu, yellow-green angsana.
		float pick = ic.r;
		vec3 base;
		if (pick < 0.40) base = lin(vec3(0.17, 0.26, 0.11));
		else if (pick < 0.70) base = lin(vec3(0.23, 0.31, 0.13));
		else if (pick < 0.955) base = lin(vec3(0.31, 0.36, 0.15));
		else base = ic.g < 0.5 ? lin(vec3(0.70, 0.32, 0.14)) : lin(vec3(0.74, 0.48, 0.58));
		if (ic.b > 0.5) base = mix(lin(vec3(0.14, 0.25, 0.09)), lin(vec3(0.30, 0.36, 0.12)), ic.g);
		base *= 0.85 + 0.3 * ic.g;
		float holes = smoothstep(0.62, 0.8, vnoise3(wpos * 2.2 + 3.0));
		vec3 c = base * (0.5 + 0.7 * clump) * (0.7 + 0.55 * leaf) * (1.0 - 0.55 * holes);
		// Flowering crowns keep some green showing through.
		if (pick >= 0.955 && ic.b < 0.5) c = mix(c, lin(vec3(0.20, 0.30, 0.11)) * (0.7 + 0.5 * leaf), smoothstep(0.55, 0.75, clump) * 0.6);
		ALBEDO = c;
		AO = vcol.r;
		AO_LIGHT_AFFECT = 0.55;
		ROUGHNESS = 0.78;
		SPECULAR = 0.35;
		BACKLIGHT = base * 0.35;
		// Leaf-clump relief in the normal.
		vec3 d = vec3(vnoise3(wpos * 1.6) - 0.5, vnoise3(wpos * 1.6 + 17.0) - 0.5, vnoise3(wpos * 1.6 - 9.0) - 0.5);
		vec3 d2 = vec3(vnoise3(wpos * 4.5) - 0.5, vnoise3(wpos * 4.5 + 5.0) - 0.5, vnoise3(wpos * 4.5 - 3.0) - 0.5);
		vec3 n = normalize(normalize(wn) + d * 1.3 + d2 * 0.6);
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
	METALLIC = 0.0;
}
