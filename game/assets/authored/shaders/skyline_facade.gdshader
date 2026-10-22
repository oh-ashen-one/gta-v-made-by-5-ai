// Skyline facade (wave A, Opus 5.5). World-space curtain-wall / punched-window
// facade for landmark towers and the procedural background city. Floor bands,
// mullions, per-panel tint variation and sparse warm interiors come from world
// position, so instances can be scaled freely without UVs. Upward faces get a
// weathered roof deck instead of facade, which is what an aerial camera sees.
// Patterns fade to their mean with distance (fwidth) so far towers do not moire.
//
// Per-instance control (MultiMesh custom data, or the uniforms for single meshes):
//   INSTANCE_CUSTOM.r  style blend: 0 = glass curtain wall, 1 = punched concrete
//   INSTANCE_CUSTOM.g  palette pick 0..1
//   INSTANCE_CUSTOM.b  floor height scale (0.5..1.0 -> 2.8..4.2 m)
//   INSTANCE_CUSTOM.a  random seed
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform bool use_instance_custom = false;
uniform float style = 0.0;
uniform float palette = 0.3;
uniform float floor_scale = 0.8;
uniform float seed = 0.0;
uniform vec3 glass_a : source_color = vec3(0.14, 0.22, 0.31);
uniform vec3 glass_b : source_color = vec3(0.34, 0.42, 0.48);
uniform vec3 glass_c : source_color = vec3(0.13, 0.24, 0.24);
uniform vec3 glass_d : source_color = vec3(0.26, 0.23, 0.20);
uniform vec3 frame_col : source_color = vec3(0.52, 0.53, 0.53);
uniform vec3 wall_a : source_color = vec3(0.64, 0.63, 0.60);
uniform vec3 wall_b : source_color = vec3(0.50, 0.52, 0.54);
uniform vec3 wall_c : source_color = vec3(0.70, 0.66, 0.58);
uniform vec3 roof_col : source_color = vec3(0.32, 0.31, 0.30);
uniform float band_frac = 0.20;
uniform float mullion_m = 2.6;
uniform float lit_chance = 0.035;

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 icustom;

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}
// Box-filtered pulse train: fraction of [0,1) period covered by [0,w), filtered over fw.
float pulse(float x, float w, float fw) {
	float f = fract(x);
	float p = step(f, w);
	return mix(p, w, clamp(fw * 1.6 - 0.2, 0.0, 1.0));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	icustom = use_instance_custom ? INSTANCE_CUSTOM : vec4(style, palette, floor_scale, seed);
}

void fragment() {
	float st = icustom.r;
	float pal = icustom.g;
	float fh = mix(2.8, 4.2, clamp(icustom.b, 0.0, 1.0));
	float sd = icustom.a * 97.0;
	vec3 n = normalize(wnorm);
	if (n.y > 0.6) {
		// Roof deck: weathered membrane with stains, panel seams and a lighter rim.
		vec2 q = wpos.xz;
		float stain = vnoise(q * 0.08 + sd) * 0.6 + vnoise(q * 0.31 - sd) * 0.4;
		float seam = max(pulse(q.x / 3.0, 0.05, fwidth(q.x / 3.0)), pulse(q.y / 3.0, 0.05, fwidth(q.y / 3.0)));
		vec3 c = roof_col * (0.78 + 0.42 * stain);
		c = mix(c, c * 0.72, seam * 0.6);
		c = mix(c, lin(vec3(0.30, 0.34, 0.30)), smoothstep(0.72, 0.9, vnoise(q * 0.05 + 3.0 + sd)) * 0.5);
		ALBEDO = c;
		ROUGHNESS = 0.92;
		METALLIC = 0.0;
	} else {
		float hz = abs(n.x) > abs(n.z) ? wpos.z : wpos.x;
		float fy = wpos.y / fh;
		float fwy = fwidth(fy);
		float fwx = fwidth(hz / mullion_m);
		vec2 cell = vec2(floor(hz / mullion_m), floor(fy));
		float r = hash2(cell + sd);
		float rf = hash2(vec2(floor(fy), sd));
		// Glass curtain wall.
		vec3 g = pal < 0.3 ? glass_a : (pal < 0.55 ? glass_b : (pal < 0.8 ? glass_c : glass_d));
		g *= 0.86 + 0.24 * r + 0.08 * rf;
		float band = pulse(fy, band_frac, fwy);
		float mull = pulse(hz / mullion_m, 0.08, fwx);
		vec3 curtain = mix(g, frame_col, max(band, mull * 0.75));
		// Punched concrete: window openings inside a light wall.
		vec3 wall = (pal < 0.4 ? wall_a : (pal < 0.7 ? wall_b : wall_c)) * (0.86 + 0.2 * vnoise(vec2(hz, wpos.y) * 0.04 + sd));
		float wx = pulse(hz / mullion_m + 0.3, 0.55, fwx);
		float wy = pulse(fy + 0.25, 0.48, fwy);
		vec3 win = lin(vec3(0.16, 0.19, 0.22)) * (0.7 + 0.6 * r);
		vec3 punched = mix(wall, win, wx * wy);
		vec3 c = mix(curtain, punched, st);
		// Sparse warm interiors (late-afternoon lights already on in a few rooms).
		float lit = step(1.0 - lit_chance, r) * (1.0 - band) * (1.0 - clamp(fwy * 2.0, 0.0, 1.0));
		c = mix(c, lin(vec3(0.95, 0.78, 0.52)), lit * mix(0.8, 0.6, st));
		// Grime gathers at the base; whole towers vary in value so the
		// skyline reads as many buildings, not one material.
		c *= 0.9 + 0.1 * smoothstep(0.0, 12.0, wpos.y);
		c *= mix(0.68, 1.08, fract(icustom.a * 7.31));
		ALBEDO = c;
		float glassy = (1.0 - st) * (1.0 - max(band, mull));
		METALLIC = mix(0.05, 0.3, glassy);
		ROUGHNESS = mix(0.8, 0.16 + 0.12 * r, glassy);
		SPECULAR = mix(0.4, 0.7, glassy);
		EMISSION = vec3(1.0, 0.78, 0.5) * lit * 0.25;
	}
}
