shader_type spatial;
// Five-foot-way floor (wave B "materials", r2): original procedural encaustic
// cement tiles in a heritage-shophouse palette. Each shop frontage gets its
// own motif and colourway with a plain border course; wear polishes and fades
// the walking line, grime collects in grout and against the shop wall.
// Pattern fades to its mean colour by pixel footprint so it never shimmers.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform float tile_m = 0.20;   // nearfield R2: 20 cm encaustic (was 25 cm, read oversized)
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
		if (length(q) < 0.12) region = 3.0;
		if (length(a - 1.0) < 0.50) region = 2.0;
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
	// nearfield R2: decades-old cement tiles: pigments chalked and dusty.
	vec3 cream = vec3(0.60, 0.57, 0.50);
	vec3 terra = vec3(0.50, 0.30, 0.22);
	vec3 teal = vec3(0.24, 0.37, 0.35);
	vec3 ochre = vec3(0.62, 0.50, 0.30);
	vec3 navy = vec3(0.22, 0.25, 0.32);
	vec3 c1 = h2 < 0.5 ? terra : teal;
	vec3 c2 = h2 < 0.25 ? teal : (h2 < 0.75 ? ochre : terra);
	vec3 c3 = h2 < 0.5 ? navy : terra * 0.8;

	vec2 tid = floor(p / tile_m);
	vec2 q = (fract(p / tile_m) - 0.5) * 2.0;
	// a few tiles are later replacements in a different motif (repairs)
	float swap = step(0.93, w_hash12(tid + 23.0));
	float reg = motif(q, fract(h + swap * 0.37));
	vec3 col = reg < 0.5 ? cream : (reg < 1.5 ? c1 : (reg < 2.5 ? c2 : c3));
	// Mean colour for distance (approximate region coverage).
	vec3 mean_col = cream * 0.5 + c1 * 0.22 + c2 * 0.18 + c3 * 0.10;
	float detail = 1.0 - smoothstep(0.02, 0.06, px);
	col = mix(mean_col, col, detail);
	// Panels: a plain border course every 6 tiles frames each carpet of
	// pattern, so the floor keeps structure at distance.
	vec2 pm = mod(tid, 6.0);
	float border = (pm.x < 0.5 || pm.y < 0.5) ? 1.0 : 0.0;
	col = mix(col, (h2 < 0.5 ? terra * 0.85 : navy * 1.1), border);
	// Grout lines, anti-aliased so the grid survives into the distance.
	vec2 g = abs(fract(p / tile_m) - 0.5) * tile_m;
	float gd = tile_m * 0.5 - max(g.x, g.y);
	float fw = max(fwidth(gd), 1e-4);
	float grout = (1.0 - smoothstep(0.003, 0.003 + fw, gd)) * clamp(0.008 / fw, 0.0, 1.0);
	col = mix(col, vec3(0.26, 0.24, 0.21), grout * 0.75);
	// Per-tile tone, a few replaced plain tiles and cracked ones.
	float th = w_hash12(tid + 3.7);
	// nearfield R2: every tile is its own batch: tone, fade and a slight
	// warm/cool cast differ unit to unit; chipped corners show grey cement;
	// some are cracked across, and a few are plain cement patches.
	col *= 0.80 + 0.30 * th;
	col = mix(col, vec3(dot(col, vec3(0.333))), 0.15 + 0.35 * w_hash12(tid + 8.8));
	col *= mix(vec3(1.03, 1.0, 0.95), vec3(0.97, 1.0, 1.03), w_hash12(tid + 12.4));
	vec2 qa = abs(q);
	float chip_c = step(0.80, w_hash12(tid + 31.0)) * step(1.72 - 0.12 * w_hash12(tid + 33.0), qa.x + qa.y);
	col = mix(col, vec3(0.42, 0.40, 0.37), chip_c * detail);
	float tcrack_on = step(0.88, w_hash12(tid + 44.0));
	vec2 qr = w_rot(q, w_hash12(tid + 45.0) * 3.14);
	float tcrack = tcrack_on * (1.0 - smoothstep(0.015, 0.05, abs(qr.y + 0.15 * sin(qr.x * 5.0 + th * 9.0)))) * detail;
	col *= 1.0 - 0.6 * tcrack;
	float plain = step(0.955, w_hash12(tid + 51.0));
	col = mix(col, vec3(0.50, 0.49, 0.46) * (0.9 + 0.2 * th), plain * 0.9);
	// grime packs into each tile's edges (worn arris, dirty grout margin)
	float edge = smoothstep(0.72, 1.0, max(qa.x, qa.y));
	col *= 1.0 - 0.22 * edge;
	// Wear: faded, dusty, scuffed; grime in big blotches.
	vec4 big = w_mask(p / 7.0 + 0.4);
	vec4 med = w_mask(p / 1.3 + 0.2);
	float fade = smoothstep(0.35, 0.75, big.g * 0.7 + med.r * 0.4);
	col = mix(col, mix(col, vec3(0.50, 0.47, 0.42), 0.4), fade * 0.35);
	float grime = smoothstep(0.45, 0.85, big.r * 0.6 + med.g * 0.5);
	col = mix(col, col * vec3(0.62, 0.58, 0.50), grime * 0.75);
	// walking line: the pattern is scuffed pale where feet go; the margins
	// collect a dark build-up. Stains and drips from the shops.
	vec4 wide = w_mask(p / 23.0 + 0.11);
	col = mix(col, vec3(0.56, 0.53, 0.48), smoothstep(0.55, 0.80, wide.g) * 0.35);
	float stain = smoothstep(0.66, 0.84, w_mask(p / 2.3 + 0.77).r) * smoothstep(0.4, 0.6, wide.r);
	col *= 1.0 - 0.38 * stain;
	float crack = w_mask(p / 3.0 + 0.6).b * smoothstep(0.5, 0.8, big.b);
	col *= 1.0 - 0.5 * crack;
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = mix(0.55, 0.85, max(grime, grout * 0.5)) - 0.15 * stain;
	SPECULAR = 0.45;
}
