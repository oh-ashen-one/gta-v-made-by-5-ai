shader_type spatial;
// Weathered corrugated-steel cladding and roofing (wave B "materials", r2).
// World-space ribs from a perturbed normal (no textures), sheet laps and
// fixings, rust runs below laps and fixings, dirt and splash at the base.
// Original project code.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.55, 0.57, 0.58);
uniform float rib_m = 0.19;        // rib pitch
uniform float sheet_m = 0.95;      // sheet cover width
uniform float lap_m = 3.2;         // vertical sheet length between laps
uniform float ground_y = 0.0;
uniform float rust = 1.0;

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wn);
	bool wall = abs(n.y) < 0.35;
	// Rib axis: horizontal along the face for walls; along the ridge for roofs.
	vec3 t = wall ? (abs(n.x) > abs(n.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0))
		: normalize(cross(n, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
	float u = dot(v_world, t);
	// Down-the-sheet coordinate: height on walls, along-slope on roofs.
	float v = wall ? v_world.y : dot(v_world, normalize(cross(t, n)));
	float px = max(fwidth(u), 1e-4);
	float ribfade = 1.0 - smoothstep(0.25 * rib_m, 0.7 * rib_m, px);
	float ph = u / rib_m * TAU;
	vec3 nw = normalize(n + t * (cos(ph) * 0.55 * ribfade));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	vec2 p = vec2(u, v);
	vec4 big = w_mask(p / 23.0 + 0.3);
	vec4 med = w_mask(p / 5.0 + 0.7);
	vec3 col = tint * (0.86 + 0.26 * big.r);
	// Per-sheet tone (replaced sheets are fresher).
	float sid = floor(u / sheet_m) + 37.0 * floor(v / lap_m);
	col *= 0.80 + 0.36 * w_hash12(vec2(sid, 3.1));
	// Sheet side-laps read as dark vertical lines even when ribs are sub-pixel.
	float sd = abs(fract(u / sheet_m + 0.5) - 0.5) * sheet_m;
	float seam = 1.0 - smoothstep(0.02, 0.02 + max(px, 0.03), sd);
	col *= 1.0 - 0.35 * seam;
	// Ribs as albedo shading once the normal ribs fall below a pixel.
	col *= 1.0 - 0.10 * (1.0 - ribfade);
	// Laps: dark shadow line where the upper sheet overlaps.
	float lap = 1.0 - smoothstep(0.0, 0.05, fract(v / lap_m) * lap_m);
	col *= 1.0 - 0.45 * lap * (1.0 - smoothstep(0.02, 0.2, fwidth(v)));
	// Rust runs: below laps and fixings, streaked downward.
	float run_src = w_mask(vec2(u / 1.7, 0.37)).a;
	float below = fract(-v / lap_m);   // 0 just under a lap, grows downward
	float runs = smoothstep(0.45, 0.80, run_src) * (1.0 - smoothstep(0.0, 0.55, below)) * rust;
	runs *= 0.6 + 0.4 * w_mask(vec2(u / 0.6, v / 9.0)).a;
	col = mix(col, vec3(0.36, 0.20, 0.11) * (0.8 + 0.4 * med.g), runs * 0.85);
	// Broad oxidised/chalky patches and grime.
	float chalk = smoothstep(0.6, 0.85, big.g) * rust;
	col = mix(col, col * 1.18 + 0.03, chalk * 0.5);
	float grime = smoothstep(0.55, 0.85, med.r * 0.6 + big.b * 0.5);
	col *= 1.0 - 0.25 * grime;
	if (wall) {
		float y0 = v_world.y - ground_y;
		float band = 1.0 - smoothstep(0.0, 0.8 + 0.6 * med.g, y0);
		col = mix(col, col * vec3(0.55, 0.50, 0.42), band * 0.8);
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	METALLIC = mix(0.55, 0.15, max(runs, chalk));
	ROUGHNESS = mix(0.48, 0.85, max(runs, max(chalk, grime * 0.6)));
}
