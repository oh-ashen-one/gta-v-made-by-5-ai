shader_type spatial;
// Five-foot-way floor (wave B "materials", r2): original procedural encaustic
// cement tiles in a heritage-shophouse palette. Each shop frontage gets its
// own motif and colourway with a plain border course; wear polishes and fades
// the walking line, grime collects in grout and against the shop wall.
// Pattern fades to its mean colour by pixel footprint so it never shimmers.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform float tile_m = 0.20;
uniform float frontage_m = 10.6;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float sdf_circle(vec2 q, vec2 c, float r) { return length(q - c) - r; }

// One motif in tile space q in [-1,1]^2; returns per-region index 0..3.
float motif(vec2 q, float kind) {
	vec2 a = abs(q);
	float region = 0.0;
	if (kind < 0.34) {
		// Quatrefoil flower with a corner rosette (corners meet as a 4th motif).
		float petals = min(min(sdf_circle(q, vec2(0.0, 0.38), 0.34), sdf_circle(q, vec2(0.0, -0.38), 0.34)),
			min(sdf_circle(q, vec2(0.38, 0.0), 0.34), sdf_circle(q, vec2(-0.38, 0.0), 0.34)));
		if (petals < 0.0) region = 1.0;
		if (length(q) < 0.17) region = 3.0;
		if (length(a - 1.0) < 0.42) region = 2.0;
		if (abs(length(a - 1.0) - 0.42) < 0.05) region = 3.0;
	} else if (kind < 0.67) {
		// Eight-point star on a diamond.
		float diamond = a.x + a.y;
		if (diamond < 0.95) region = 2.0;
		vec2 r = vec2(a.x * 0.7071 - a.y * 0.7071, a.x * 0.7071 + a.y * 0.7071);
		float star = min(max(a.x, a.y), max(abs(r.x), abs(r.y)));
		if (star < 0.42) region = 1.0;
		if (length(q) < 0.13) region = 3.0;
		if (max(a.x, a.y) > 0.9) region = 3.0;
	} else {
		// Four-tile medallion: each tile holds a quarter, so the motif spans
		// 40 cm; diagonal leaves out of the corner, a scalloped band.
		vec2 c = a - 1.0;    // distance from the shared corner
		float r = length(c);
		if (r < 0.95) region = 1.0;
		if (r < 0.70) region = 2.0;
		if (r < 0.40) region = 3.0;
		float leaf = abs(c.x - c.y) * 1.4 + abs(r - 1.25) * 1.6;
		if (leaf < 0.35) region = 2.0;
		if (min(a.x, a.y) > 0.88) region = 3.0;
	}
	return region;
}

void fragment() {
	vec2 p = v_world.xz;
	float px = max(length(fwidth(p)), 1e-4);
	// Shop frontage id from whichever horizontal axis the row runs along.
	vec2 shop = floor(p / frontage_m);
	float h = w_hash12(shop + 7.3);
	float h2 = w_hash12(shop + 19.1);
	vec3 cream = vec3(0.66, 0.62, 0.53);
	vec3 terra = vec3(0.60, 0.26, 0.17);
	vec3 teal = vec3(0.16, 0.40, 0.39);
	vec3 ochre = vec3(0.76, 0.56, 0.24);
	vec3 navy = vec3(0.17, 0.22, 0.34);
	vec3 c1 = h2 < 0.5 ? terra : teal;
	vec3 c2 = h2 < 0.25 ? teal : (h2 < 0.75 ? ochre : terra);
	vec3 c3 = h2 < 0.5 ? navy : terra * 0.8;

	vec2 tid = floor(p / tile_m);
	vec2 q = (fract(p / tile_m) - 0.5) * 2.0;
	float reg = motif(q, h);
	vec3 col = reg < 0.5 ? cream : (reg < 1.5 ? c1 : (reg < 2.5 ? c2 : c3));
	// Mean colour for distance (approximate region coverage).
	vec3 mean_col = cream * 0.5 + c1 * 0.22 + c2 * 0.18 + c3 * 0.10;
	float detail = 1.0 - smoothstep(0.012, 0.035, px);
	col = mix(mean_col, col, detail);
	// Grout lines.
	vec2 g = abs(fract(p / tile_m) - 0.5) * tile_m;
	float grout = (1.0 - smoothstep(tile_m * 0.5 - 0.006, tile_m * 0.5 - 0.002, max(g.x, g.y))) ;
	grout = 1.0 - grout;
	col = mix(col, vec3(0.30, 0.28, 0.25), grout * 0.7 * (1.0 - smoothstep(0.004, 0.012, px)));
	// Per-tile tone, a few replaced plain tiles and cracked ones.
	float th = w_hash12(tid + 3.7);
	col *= 0.90 + 0.18 * th;
	float plain = step(0.965, w_hash12(tid + 51.0));
	col = mix(col, vec3(0.55, 0.53, 0.49), plain * 0.85);
	// Wear: faded, dusty, scuffed; grime in big blotches.
	vec4 big = w_mask(p / 7.0 + 0.4);
	vec4 med = w_mask(p / 1.3 + 0.2);
	float fade = smoothstep(0.35, 0.75, big.g * 0.7 + med.r * 0.4);
	col = mix(col, mix(col, vec3(0.50, 0.47, 0.42), 0.5), fade * 0.45);
	float grime = smoothstep(0.55, 0.85, big.r * 0.6 + med.g * 0.5);
	col *= 1.0 - 0.30 * grime;
	float crack = w_mask(p / 3.0 + 0.6).b * smoothstep(0.5, 0.8, big.b);
	col *= 1.0 - 0.5 * crack;
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = mix(0.55, 0.85, max(grime, grout * 0.5));
	SPECULAR = 0.45;
}
