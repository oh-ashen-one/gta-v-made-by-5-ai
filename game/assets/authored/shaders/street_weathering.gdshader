shader_type spatial;
// Screen-space weathering volume (Orchard Reach, lighting piece round 3).
// Drawn as an axis-aligned box over one street block. It reconstructs the
// world position of whatever opaque surface is behind each pixel and
// multiplies in age: tyre tracks, patch repairs, cracks and gutter grime on
// asphalt; kerb-side grime, stains, cement patches and cracks on pavers; a
// dirt band and rain streaks at the base of every wall and column. Original,
// procedural; no textures.
render_mode unshaded, blend_mul, cull_front, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 box_min = vec3(-80.0, -0.5, -80.0);
uniform vec3 box_max = vec3(80.0, 12.0, 80.0);
uniform float strength = 1.0;
uniform float fade_start = 70.0;
uniform float fade_end = 170.0;
uniform float asphalt_k = 0.0;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
vec2 h22(vec2 p) {
	float n = h21(p);
	return vec2(n, h21(p + n + 17.17));
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}
// Distance to the nearest Voronoi cell edge (crack network).
float vor_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = h22(i + g);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

// Road lines: carriageways centred every 160 m on x and z, half width 8 m.
float road_lateral(float c) {
	return c - round(c / 160.0) * 160.0;
}

vec3 asphalt_wear(vec2 p, float lat, float along, float aa) {
	vec3 m = vec3(1.0);
	float a = abs(lat);
	// large tonal blotching: sun-bleached and oil-darkened areas
	float big = fbm(p * 0.045);
	m *= mix(0.80, 1.03, smoothstep(0.25, 0.75, big));
	// aggregate grain and mid-scale mottling
	float gr = mix(0.5, vnoise(p * 7.0), 1.0 - smoothstep(0.05, 0.2, aa));
	m *= mix(0.86, 1.03, gr) * mix(0.84, 1.0, fbm(p * 0.9 + 4.0));
	// tyre tracks: two polished-dark wheel paths in each 4 m lane
	float lane_c = (floor(a / 4.0) + 0.5) * 4.0;
	float wheel = abs(abs(a - lane_c) - 0.85);
	float track = 1.0 - smoothstep(0.18, 0.42, wheel);
	float track_var = 0.55 + 0.45 * vnoise(vec2(along * 0.08, lat));
	m *= 1.0 - 0.20 * track * track_var;
	// oil drip line down each lane centre
	float drip = 1.0 - smoothstep(0.15, 0.55, abs(a - lane_c));
	float spots = smoothstep(0.55, 0.85, fbm(vec2(along * 0.6, lat * 3.0)));
	m *= 1.0 - 0.28 * drip * spots;
	// gutter grime and silt against the kerb
	float gutter = smoothstep(7.0, 7.95, a);
	m *= mix(1.0, 0.62 + 0.18 * vnoise(p * 0.7), gutter);
	// patch repairs with a sealed seam (round 4: edges wander and tones
	// vary, so they no longer read as evenly spaced dark rectangles)
	vec2 cell = vec2(floor(lat / 3.2), floor(along / 7.5));
	float r = h21(cell + 3.1);
	if (r < 0.14) {
		vec2 lp = vec2(fract(lat / 3.2) * 3.2, fract(along / 7.5) * 7.5);
		lp += (vec2(vnoise(p * 1.7), vnoise(p * 1.7 + 5.0)) - 0.5) * 0.35;
		vec2 sz = vec2(1.0 + 1.8 * h21(cell + 7.7), 1.6 + 4.6 * h21(cell + 1.3));
		vec2 o = vec2(0.1 + (3.0 - sz.x) * h21(cell + 4.4), 0.2 + (7.2 - sz.y) * h21(cell + 9.9));
		vec2 q = lp - o;
		float inside = step(0.0, q.x) * step(q.x, sz.x) * step(0.0, q.y) * step(q.y, sz.y);
		float edge = min(min(q.x, sz.x - q.x), min(q.y, sz.y - q.y));
		float seam = inside * (1.0 - smoothstep(0.0, 0.06 + aa, edge));
		float tone = mix(0.84, 1.06, h21(cell + 2.2)) * mix(0.94, 1.0, vnoise(p * 2.3));
		m *= mix(vec3(1.0), vec3(tone, tone, tone * 1.02), inside);
		m *= 1.0 - 0.20 * seam;
	}
	// crack network, only in aged zones
	vec2 warp = vec2(fbm(p * 1.3), fbm(p * 1.3 + 7.1)) * 0.8;
	float ce = vor_edge(p * 0.4 + warp);
	float crack = 1.0 - smoothstep(0.0, 0.03 + aa, ce);
	float aged = smoothstep(0.58, 0.72, fbm(p * 0.09 + 3.0));
	m *= 1.0 - 0.38 * crack * aged;
	// oil and coolant stains: soft irregular blobs, densest in the kerb
	// parking lane and at the lane centres where cars idle
	float st_n = fbm(p * 0.55 + 13.0);
	float stain = smoothstep(0.66, 0.76, st_n) * (0.6 + 0.4 * vnoise(p * 3.1));
	float park_lane = smoothstep(5.4, 6.2, a) * (1.0 - smoothstep(7.4, 7.9, a));
	m *= 1.0 - (0.22 + 0.18 * park_lane) * stain;
	// tar-sealed cracks: glossy black snakes in long-patched zones
	vec2 tw = vec2(fbm(p * 0.6 + 2.0), fbm(p * 0.6 + 9.0)) * 1.6;
	float te = vor_edge(p * 0.16 + tw);
	float tar = 1.0 - smoothstep(0.003, 0.008 + aa * 0.16, te);
	m *= 1.0 - 0.32 * tar * smoothstep(0.55, 0.65, fbm(p * 0.05 + 40.0));
	// worn and broken road paint: grime breaks the lines up in patches
	float paint_wear = smoothstep(0.45, 0.7, fbm(vec2(along * 0.35, lat * 1.5) + 21.0));
	m *= mix(vec3(1.0), vec3(0.78, 0.76, 0.80), paint_wear * smoothstep(6.6, 7.2, a));
	// longitudinal joint crack near the lane boundary
	float joint = 1.0 - smoothstep(0.0, 0.03 + aa, abs(a - 4.0 - 0.15 * sin(along * 0.31)));
	m *= 1.0 - 0.35 * joint * smoothstep(0.4, 0.7, vnoise(vec2(along * 0.05, 2.0)));
	return m;
}

vec3 paver_wear(vec2 p, float kerb_d, float aa) {
	vec3 m = vec3(1.0);
	// tonal wear and soot
	float big = fbm(p * 0.07 + 11.0);
	m *= mix(vec3(0.74, 0.73, 0.71), vec3(1.02), smoothstep(0.22, 0.72, big));
	// kerb-side grime: silt and tyre spray at the platform edge
	float kg = 1.0 - smoothstep(0.0, 2.2, kerb_d);
	m *= mix(1.0, 0.62 + 0.2 * vnoise(p * 1.3), kg);
	// discoloured and replaced paver tiles (0.6 x 0.3 grid)
	vec2 tc = floor(vec2(p.x / 0.6, p.y / 0.3));
	float tr = h21(tc + 0.5);
	if (tr < 0.04) {
		// replaced tiles: a gentle tone shift, not a dark decal
		m *= mix(vec3(0.90, 0.89, 0.87), vec3(1.04, 1.02, 0.98), h21(tc + 9.0));
	}
	// grain, damp patches and mid-scale soiling
	float gr = mix(0.5, vnoise(p * 8.0), 1.0 - smoothstep(0.05, 0.2, aa));
	m *= mix(0.84, 1.03, gr);
	m *= mix(0.80, 1.02, fbm(p * 1.3 + 2.0));
	m *= mix(0.80, 1.0, smoothstep(0.35, 0.62, fbm(p * 0.35 + 21.0)));
	// cement patch repairs with a dark rim
	float pf = fbm(p * 0.22 + 31.0);
	float patch = smoothstep(0.70, 0.71 + aa, pf);
	float rim = smoothstep(0.66, 0.70, pf) * (1.0 - patch);
	m *= mix(vec3(1.0), vec3(0.80, 0.81, 0.82), patch);
	m *= 1.0 - 0.35 * rim;
	// gum spots and drip stains
	vec2 sc = floor(p / 0.9);
	vec2 so = h22(sc);
	float sd = length(fract(p / 0.9) - so);
	float sr = 0.06 + 0.22 * h21(sc + 2.0);
	if (h21(sc + 5.0) < 0.12) {
		m *= mix(0.62, 1.0, smoothstep(sr * 0.6, sr, sd * 0.9));
	}
	// cracks through the bedding
	vec2 warp = vec2(fbm(p * 1.7), fbm(p * 1.7 + 5.3)) * 0.9;
	float ce = vor_edge(p * 0.45 + warp + 5.0);
	float crack = 1.0 - smoothstep(0.0, 0.02 + aa, ce);
	m *= 1.0 - 0.42 * crack * smoothstep(0.60, 0.74, fbm(p * 0.13));
	return m;
}

vec3 wall_wear(vec3 w, vec3 n, float base_y) {
	vec3 m = vec3(1.0);
	float h = w.y - base_y;
	vec2 tp = vec2(dot(w.xz, vec2(-n.z, n.x)), w.y);
	// rising damp / splash dirt band at the base
	float band_h = 0.55 + 0.45 * vnoise(vec2(tp.x * 0.6, 0.0));
	float band = 1.0 - smoothstep(0.0, band_h, h);
	m *= mix(1.0, 0.55 + 0.12 * vnoise(tp * 3.0), band);
	// soft grime gradient over the lower storey
	m *= mix(0.84, 1.0, smoothstep(0.0, 2.6, h));
	// rain streaks running down from sills and eaves
	float col = vnoise(vec2(tp.x * 2.3, 0.0));
	float streak = smoothstep(0.62, 0.9, col) * (0.6 + 0.4 * vnoise(vec2(tp.x * 2.3, tp.y * 0.35)));
	float upper = smoothstep(1.5, 3.5, h);
	m *= 1.0 - 0.22 * streak * upper;
	// mottled paint wear across the facade
	float wear = fbm(tp * vec2(0.5, 0.7));
	m *= mix(vec3(0.86, 0.85, 0.83), vec3(1.0), smoothstep(0.3, 0.65, wear));
	// peeling paint flecks
	float peel = smoothstep(0.74, 0.76, fbm(tp * 1.6 + 7.0));
	m *= mix(vec3(1.0), vec3(0.78, 0.76, 0.72), peel * upper);
	return m;
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	vec3 w = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	if (any(lessThan(w, box_min)) || any(greaterThan(w, box_max))) {
		discard;
	}
	float dist = length(view.xyz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	if (fade <= 0.001) {
		discard;
	}
	vec3 n = normalize(cross(dFdx(w), dFdy(w)));
	if (n.y < 0.0 && abs(n.y) > 0.7) { n = -n; }
	// anti-alias width for line features, in metres
	float aa = clamp(dist * 0.0018, 0.0, 0.25);
	// Weather only planar surfaces: curved actors (people, cars) keep clean.
	float planar = 1.0 - smoothstep(0.25, 0.7, length(fwidth(n)));
	vec3 m = vec3(1.0);
	if (abs(n.y) > 0.8) {
		float lat_x = road_lateral(w.x);
		float lat_z = road_lateral(w.z);
		if (w.y < 0.115 && (abs(lat_x) < 8.0 || abs(lat_z) < 8.0)) {
			bool along_z = abs(lat_x) < abs(lat_z);
			float lat = along_z ? lat_x : lat_z;
			float along = along_z ? w.z : w.x;
			// Nearfield (opus55 wave D): the carriageway shader owns its own
			// lane-aware wear; multiplying a second wear pass on top produced
			// the blotchy camouflage mottle and, against the MSAA-resolved
			// depth, a dotted zipper along kerbs and double-yellow lines.
			m = mix(vec3(1.0), asphalt_wear(w.xz, lat, along, aa), asphalt_k);
		} else if (w.y < 0.5 || (w.y < 3.0 && min(abs(lat_x), abs(lat_z)) > 8.4)) {
			// pavers, void-deck slabs and forecourts: anything on the
			// carriageway above kerb height (car hoods, roofs) stays clean
			// (critic A3: cracks on a parked sedan's hood)
			float kd = min(abs(lat_x), abs(lat_z)) - 8.3;
			m = paver_wear(w.xz, max(kd, 0.0), aa);
			// kerb stones and median kerbs carry their own wear (nearfield);
			// fade in behind the kerb so there is no seam at the arris
			float med = min(abs(lat_x), abs(lat_z));
			m = mix(vec3(1.0), m, smoothstep(0.05, 0.6, kd) * step(1.2, med));
		} else if (w.y > 3.0) {
			m = mix(vec3(0.9), vec3(1.0), fbm(w.xz * 0.3));
		}
	} else if (abs(n.y) < 0.3) {
		m = wall_wear(w, normalize(vec3(n.x, 0.0, n.z) + vec3(1e-4)), 0.16);
		// kerb faces (road side, under 0.35 m) are dressed by the kerb shader
		float kl = min(abs(road_lateral(w.x)), abs(road_lateral(w.z)));
		if (w.y < 0.35 && (kl > 7.6 && kl < 8.6 || kl < 1.2)) { m = vec3(1.0); }
	}
	m = mix(vec3(1.0), m, fade * strength * planar);
	ALBEDO = m;
}
