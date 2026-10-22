shader_type spatial;
// Weathered hardwood boardwalk for the bay jetties and pontoon (water piece,
// Opus 5.5 loop, wave A round 3). World-space planks run across `plank_axis`
// with dark gaps, per-plank tone and grain, sun-bleached silver patches,
// darker wet staining toward the deck edges and a steel nosing band. Fine
// detail fades with the pixel footprint so aerial views do not shimmer.
render_mode cull_back;

uniform vec3 wood_a : source_color = vec3(0.50, 0.36, 0.24);
uniform vec3 wood_b : source_color = vec3(0.64, 0.50, 0.36);
uniform vec3 bleached : source_color = vec3(0.66, 0.63, 0.58);
uniform vec3 gap_color : source_color = vec3(0.07, 0.06, 0.05);
uniform float plank_width = 0.24;
uniform float plank_length = 3.6;
// 0 = planks span x (boards stepped along z), 1 = span z
uniform float plank_axis = 0.0;
uniform vec4 deck_rect = vec4(0.0); // xmin, zmin, xmax, zmax for edge staining (0 = off)

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 p = plank_axis < 0.5 ? wpos.xz : wpos.zx; // p.x along the board, p.y across boards
	float foot = max(length(fwidth(p)), 1e-4);
	float row = floor(p.y / plank_width);
	float fy = fract(p.y / plank_width);
	// staggered butt joints
	float off = h11(row) * plank_length;
	float col = floor((p.x + off) / plank_length);
	float fx = fract((p.x + off) / plank_length);
	float id = h21(vec2(row, col));
	vec3 c = mix(wood_a, wood_b, id);
	// grain streaks along the board
	float grain = vn(vec2(p.x * 1.4, p.y * 38.0 + id * 9.0));
	c *= mix(0.86, 1.10, grain);
	// sun-bleached silvering in large patches, plus a few replaced boards
	float bleach = smoothstep(0.42, 0.78, vn(p * 0.22) * 0.7 + vn(p * 0.9) * 0.3);
	c = mix(c, bleached * mix(0.9, 1.05, id), bleach * 0.65);
	c = mix(c, wood_a * 0.75, step(0.93, id));
	// gaps between boards and at butt joints; faded by footprint
	float gap_aa = clamp(1.0 - foot / plank_width * 1.6, 0.0, 1.0);
	float gap = (1.0 - smoothstep(0.0, 0.08, fy) * smoothstep(1.0, 0.92, fy)) * gap_aa;
	float butt = (1.0 - smoothstep(0.0, 0.006, fx) * smoothstep(1.0, 0.994, fx)) * gap_aa;
	float fade_mix = clamp(foot / plank_width * 1.6, 0.0, 1.0);
	c = mix(c, gap_color, max(gap, butt) * 0.85);
	// unresolved gaps still darken the average a little
	c *= mix(1.0, 0.86, fade_mix);
	// wet staining near the water edges of the deck
	if (deck_rect.z > deck_rect.x) {
		vec2 q = wpos.xz;
		float e = min(min(q.x - deck_rect.x, deck_rect.z - q.x), min(q.y - deck_rect.y, deck_rect.w - q.y));
		float wet = smoothstep(1.2, 0.0, e) * (0.6 + 0.4 * vn(q * 1.7));
		c *= mix(1.0, 0.62, wet);
	}
	// side faces: darker end grain / fascia
	float side = 1.0 - smoothstep(0.5, 0.8, wnrm.y);
	c = mix(c, wood_a * 0.55, side);
	ALBEDO = c;
	ROUGHNESS = mix(0.78, 0.92, bleach) - (1.0 - side) * 0.02;
	SPECULAR = 0.35;
	// board edges catch the light: bevel normal across the boards
	float bev = (smoothstep(0.0, 0.14, fy) - smoothstep(0.86, 1.0, fy)) - 0.5;
	vec3 n = wnrm;
	if (wnrm.y > 0.8) {
		vec3 across = plank_axis < 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		n = normalize(wnrm - across * (fy - 0.5) * 0.35 * gap_aa + vec3(0.0, 0.0, 0.0) * bev);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
