shader_type spatial;
// Marina-bay water (water piece, Opus 5.5 loop, wave A).
// Opaque so it stays cheap and sorts with the city. Everything that makes it
// read as water is here: a deep-water swell spectrum for animated normals,
// a planar reflection (BayWater renders a mirrored camera into
// reflection_tex), Schlick fresnel between the reflection and a murky
// teal-green body colour, shoreline lapping foam, Kelvin-wedge boat wakes and
// a capped sun glint so no light can blow a white disc into the frame.
// Round 3: the enclosed bay is glassy; foam only comes from events (hull
// contact, bow spray, a widening turbulent stern trail that breaks into
// patches, diverging 19.5 deg wake arms, quay surges, the Merlion splash).
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D reflection_tex : filter_linear, repeat_disable;
uniform float reflection_ready = 0.0;
uniform float reflection_gain = 0.85;
uniform vec3 deep_color : source_color = vec3(0.026, 0.135, 0.180);
uniform vec3 shallow_color : source_color = vec3(0.055, 0.240, 0.255);
uniform vec3 scatter_color : source_color = vec3(0.060, 0.300, 0.300);
uniform vec3 sky_horizon : source_color = vec3(0.78, 0.76, 0.72);
uniform vec3 sky_zenith : source_color = vec3(0.32, 0.47, 0.68);
uniform vec3 foam_color : source_color = vec3(0.86, 0.88, 0.86);
uniform float water_level = -0.9;
uniform float near_shore_z = -350.7;
uniform float far_shore_z = -615.0;
// xmin, zmin, xmax, zmax of the Merlion pier base and the boat pontoon
uniform vec4 pier_rect = vec4(38.0, -354.0, 52.0, -340.0);
uniform vec4 pontoon_rect = vec4(-44.0, -357.2, -22.0, -351.8);
uniform vec3 jet_impact = vec3(45.0, -0.9, -359.0);
uniform vec4 boats[20];      // x, z, heading (rad, +x = 0), speed m/s
uniform vec4 boat_size[20];  // half length, half beam, 0, 0
uniform int boat_count = 0;
uniform float distortion = 0.020;
uniform float spec_cap = 0.32;
uniform float glint_roughness = 0.16;
uniform vec2 wind_dir = vec2(0.80, -0.60);
uniform float whitecaps = 0.55;  // only beyond the harbour mouth; the dammed bay stays glassy
uniform float sparkle_gain = 0.65;
// Horizon skirt: the sea plane is clipped at the camera far plane, leaving a
// pale band of below-horizon sky with a hard top edge. BayWater keeps a ring
// (same material, skirt = 1) at horizon_radius up to eye height, and the sea
// blends into the identical reflection-only colour before it gets there.
uniform float horizon_radius = 1800.0;
instance uniform float skirt = 0.0;

varying vec3 world_pos;
varying float v_glint_r;
varying float v_foam;
varying float v_sparkle;
varying float v_horizon;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p;
		a *= 0.5;
	}
	return v;
}

// F2 - F1 of a jittered grid: ~0 along cell borders (bubble walls).
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

// Round 4 (critic: "smooth, even white strokes with clean edges"): every
// foam source now produces a coverage value, and coverage is rendered as
// aerated foam: solid where it is thick, a lacy web of bubble walls where it
// thins, loose clumps at the fringe. Two cell scales (1.4 m, 0.45 m) so it
// reads from the helicopter and from the water.
float lace_foam(vec2 p, float cov, float foot, float t) {
	vec2 drift = vec2(t * 0.11, -t * 0.07);
	float e1 = cell_edge(p * 0.72 + drift);
	float e2 = cell_edge(p * 2.2 - drift * 1.7 + 11.0);
	float web1 = smoothstep(cov * 0.42 + 0.02, cov * 0.42 - 0.05, e1);
	float web2 = smoothstep(cov * 0.38 + 0.015, cov * 0.38 - 0.04, e2) * smoothstep(0.08, 0.35, cov);
	float solid = smoothstep(0.72, 1.05, cov) * smoothstep(0.02, 0.10, e2 + 0.06);
	float f = max(max(web1 * 0.92, web2 * 0.8), solid);
	f *= smoothstep(0.02, 0.14, cov);
	// sub-pixel cells: fall back to the mean coverage, never to a clean line
	return mix(f, clamp(cov * 0.55, 0.0, 0.85), smoothstep(0.7, 1.8, foot));
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Wind-sea height field built from rotated, drifting value-noise octaves with
// analytic derivatives (no sine sums: those read as straight periodic streaks
// from the air). Ridged crests give choppy, sharp-topped wavelets; a low
// frequency gust field makes rough and calm patches. Each octave fades once a
// pixel covers ~0.6 of its wavelength; the slope it would have added is
// returned as "lost" so the glint and reflection widen instead of aliasing.
vec3 noised(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	float k4 = a - b - c + d;
	float v = a + (b - a) * u.x + (c - a) * u.y + k4 * u.x * u.y;
	vec2 g = du * (vec2(b - a, c - a) + k4 * u.yx);
	return vec3(v, g);
}

// returns (dh/dx, dh/dz, crest height 0..1, lost slope)
vec4 sea_field(vec2 p, float t, float foot, float choppy, float gust) {
	vec2 g = vec2(0.0);
	float crest = 0.0;
	float crest_w = 0.0;
	float lost = 0.0;
	float lambda = 19.0;
	vec2 wd = normalize(wind_dir);
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float k = 1.0 / lambda;
		// octave orientation: big swell roughly down-wind, chop spreads wide
		float ang = (hash12(vec2(fi, 3.1)) - 0.5) * (0.9 + fi * 0.32) + fi * 2.39996 * step(3.5, fi) * 0.35;
		vec2 dir = rot(wd, ang);
		vec2 side = vec2(-dir.y, dir.x);
		// crests run across the wind: stretch along the crest line
		float stretch = mix(0.42, 0.85, clamp(fi / 7.0, 0.0, 1.0));
		float speed = sqrt(9.81 * lambda / 6.2831853) * 0.55;
		vec2 q = vec2(dot(p, dir) - speed * t, dot(p, side) * stretch) * k;
		q += vec2(fi * 17.3, fi * 9.1);
		// a slower counter-drifting copy keeps the pattern evolving, not sliding
		vec2 q2 = vec2(dot(p, dir) + speed * t * 0.37, dot(p, side) * stretch) * k * 1.13 + vec2(fi * 5.7 + 31.0, 3.0);
		vec3 n1 = noised(q);
		vec3 n2 = noised(q2);
		float v = n1.x * 0.6 + n2.x * 0.4;
		vec2 dq = n1.yz * 0.6 + n2.yz * 0.4 * 1.13;
		// ridge: sharp crests, round troughs
		float s = 2.0 * v - 1.0;
		float ridge = 1.0 - abs(s);
		float hv = mix(v, ridge * ridge, 0.55);
		vec2 dh = mix(dq, -2.0 * ridge * sign(s) * 2.0 * dq, 0.55);
		// back to world xz (dq is per unit q; q = R p * k with stretch)
		vec2 gw = (dir * dh.x + side * dh.y * stretch) * k;
		// Marina Bay is a dammed reservoir: low swell, fine cat's-paw ripples
		// only where gusts touch it; boats and the jet raise 'choppy'.
		float amp = lambda * (i > 2 ? 0.034 * choppy * mix(0.35, 1.25, gust) : 0.026 * mix(0.8, 1.1, gust));
		float fade = clamp(1.6 - foot * k * 2.4, 0.0, 1.0);
		g += gw * amp * fade;
		lost += amp * k * 0.45 * (1.0 - fade);
		if (i < 5) {
			crest += hv * amp * fade;
			crest_w += amp;
		}
		lambda *= 0.56;
	}
	return vec4(g, crest / max(crest_w, 1e-4), lost);
}

float rect_distance(vec2 p, vec4 r) {
	vec2 c = (r.xy + r.zw) * 0.5;
	vec2 h = (r.zw - r.xy) * 0.5;
	vec2 q = abs(p - c) - h;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
}

vec3 horizon_colour(vec2 suv) {
	vec3 refl = sky_horizon;
	if (reflection_ready > 0.5) {
		refl = texture(reflection_tex, clamp(vec2(suv.x, 1.0 - suv.y), vec2(0.002), vec2(0.998))).rgb * reflection_gain;
	}
	return mix(deep_color * 1.8, refl, 0.80);
}

void fragment() {
	if (skirt > 0.5) {
		v_foam = 0.0;
		v_glint_r = 0.3;
		v_sparkle = 0.0;
		v_horizon = 1.0;
		ALBEDO = vec3(0.0);
		EMISSION = horizon_colour(SCREEN_UV);
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
	} else {
	vec2 p = world_pos.xz;
	float t = TIME;
	float foot = max(length(fwidth(p)), 0.0005);

	// ---------------- shoreline distance (seawalls, pier, pontoon)
	// The surface is one sea plane under the whole map; quay lines only exist
	// where the district (|x| < 750) and the far shore (|x| < 850) are.
	float d_near = max(abs(near_shore_z - p.y), abs(p.x) - 750.0);
	float d_far = max(abs(p.y - far_shore_z), abs(p.x) - 850.0);
	float d_pier = rect_distance(p, pier_rect);
	float d_pont = rect_distance(p, pontoon_rect);
	float shore = min(min(d_near, d_far), min(d_pier, d_pont));

	// event-driven foam breakup noise (shared by wakes, quay wash, jet)
	float foam_n = fbm(p * 0.9 + vec2(t * 0.15, t * 0.07));
	float foam_n2 = fbm(p * 2.7 - vec2(t * 0.2, 0.0));
	float foam_fine = vnoise(p * 6.5 + vec2(t * 0.9, -t * 0.4));
	float wake_break = foam_n2 * 0.55 + foam_n * 0.35 + foam_fine * 0.35;

	// ---------------- boats: hull contact, bow spray, turbulent stern trail
	// and a Kelvin wedge (19.5 deg arms) of displacement waves
	float wake = 0.0;
	float churn = 0.0;
	float trail_foam = 0.0;
	vec2 wake_g = vec2(0.0);
	for (int i = 0; i < 20; i++) {
		if (i >= boat_count) break;
		vec4 b = boats[i];
		vec2 fwd = vec2(cos(b.z), sin(b.z));
		vec2 right = vec2(-fwd.y, fwd.x);
		vec2 rel = p - b.xy;
		float along = dot(rel, fwd);
		float lat = dot(rel, right);
		float hl = boat_size[i].x;
		float hb = boat_size[i].y;
		float L = 2.0 * hl;
		float spd = clamp(b.w / 6.0, 0.0, 1.4);
		if (abs(along) > L * 11.0 + 20.0 || abs(lat) > L * 4.5 + 12.0) continue;
		// moored hulls lap a little; boats under way get no halo ahead of the
		// stem, only a torn contact band along both sides from the shoulder aft
		float e = length(vec2(along / (hl + 0.7), lat / (hb + 0.6)));
		if (spd <= 0.02) {
			float lap = smoothstep(1.35, 1.0, e) * 0.32;
			trail_foam += lap;
			churn += lap;
			continue;
		}
		float s1 = min(spd, 1.0);
		float alat = abs(lat);
		float hw_here = hb * clamp((hl - along) / (hl * 0.9), 0.08, 1.0);
		float contact = smoothstep(hw_here + 0.8 + hb * 0.6, hw_here, alat) * smoothstep(hl * 0.95, hl * 0.5, along) * smoothstep(-hl * 1.15, -hl * 0.7, along);
		trail_foam += contact * (0.30 + 0.80 * s1);
		churn += contact * s1;
		// bow wave crest peeling off both shoulders onto the water
		float bow_t = clamp((along - hl * 0.1) / (hl * 0.95), 0.0, 1.0);
		float bow_side = abs(alat - hb * (1.15 + (1.0 - bow_t) * 0.55));
		float bow = smoothstep(0.9 + hb * 0.5, 0.0, bow_side) * smoothstep(-hl * 0.2, hl * 0.4, along) * smoothstep(hl * 1.1, hl * 0.8, along);
		trail_foam += bow * s1 * 0.95;
		float behind = -(along + hl * 0.85);
		if (behind > -hl * 0.4) {
			float b2 = max(behind, 0.0);
			float age = b2 / (L * 7.0);
			// the trail meanders and fans out; its edge is torn, not ruled
			float mw = (vnoise(vec2(b2 * 0.06 + float(i) * 7.1, t * 0.05)) - 0.5) * (hb * 0.9 + b2 * 0.16);
			float lat_m = lat - mw;
			float hw = hb * 1.2 + b2 * 0.24;
			float edge_n = (foam_n - 0.5) * hw * 1.1 + (foam_n2 - 0.5) * hw * 0.5;
			float core = smoothstep(hw + edge_n, hw * 0.12, abs(lat_m));
			float tf = smoothstep(-hl * 0.4, 0.4, behind) * smoothstep(L * 8.0, L * 2.5, b2);
			// torn blotches at 2-8 m scale so the fan is broken up even from
			// the helicopter; they get sparser as the foam ages
			float brk = vnoise(p * 0.13 + float(i) * 5.1) * 0.55 + vnoise(p * 0.42 - float(i) * 2.3) * 0.35 + foam_n * 0.35;
			float patch = smoothstep(0.30 + age * 0.40, 0.60 + age * 0.40, brk);
			// solid churn at the transom decaying over ~2 lengths into lace
			float near_stern = exp(-b2 / (L * 0.8));
			trail_foam += core * tf * s1 * (1.30 * near_stern * mix(patch, 1.0, near_stern) + 0.95 * patch * exp(-b2 / (L * 4.2)));
			churn += core * tf * s1 * 0.8 * exp(-b2 / (L * 3.0));
			// Kelvin arms: diverging crests on both sides
			float arm_d = abs(lat) - (hb * 0.9 + b2 * 0.354);
			float af = exp(-b2 / (L * 2.6)) * smoothstep(L * 6.5, L * 2.5, b2) * smoothstep(-hl * 0.4, hl * 0.4, behind) * s1;
			float arm_w = 0.9 + b2 * 0.07;
			float arm = smoothstep(arm_w, 0.0, abs(arm_d + 0.3));
			wake += arm * af;
			float patch2 = smoothstep(0.32 + age * 0.4, 0.62 + age * 0.4, brk * 0.7 + foam_n2 * 0.45);
			trail_foam += arm * af * 1.0 * patch2;
			// displacement waves: the arm crest plus echoes inside the wedge,
			// and transverse waves across it
			float inside = smoothstep(1.5, -1.0, arm_d);
			float wv = cos(arm_d * 1.6) * exp(-abs(arm_d) * 0.22) * inside;
			wake_g += right * sign(lat) * wv * af * 0.38;
			float trans = cos(b2 * 6.2831853 / max(L * 0.9, 2.0)) * smoothstep(0.0, -2.0, arm_d) * af;
			wake_g += -fwd * trans * 0.12;
		}
	}

	// ---------------- jet impact: rings + splash foam
	float dj = length(p - jet_impact.xz);
	float impact = smoothstep(4.2, 0.6, dj);
	float ripples = sin(dj * 3.4 - t * 6.0) * exp(-dj * 0.28) * smoothstep(0.3, 1.2, dj);

	// ---------------- normals
	// isotropic footprint (geometric mean of the two screen axes) so grazing
	// views keep their near wavelets instead of fading to a smooth smear
	float foot_iso = sqrt(max(length(dFdx(p)) * length(dFdy(p)), 1e-8));
	float rough_water = clamp(churn * 0.9 + impact * 1.4 + wake * 0.6 + trail_foam * 0.5, 0.0, 2.5);
	float gust = smoothstep(0.30, 0.72, fbm(p * 0.0105 + vec2(t * 0.012, -t * 0.007)));
	vec4 sea = sea_field(p, t, foot_iso, 1.0 + rough_water * 1.4, gust);
	vec2 g = sea.xy + wake_g;
	float crest = sea.z;
	float lost = sea.w;
	vec2 rdir = (p - jet_impact.xz) / max(dj, 0.001);
	g += rdir * ripples * 0.12;
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// ---------------- foam
	// Quay contact: a continuous thin wet/lapping line, plus surges that run
	// along the wall at different reaches (wave-driven, never a fixed band).
	float surge_ph = t * 0.85 + fbm(p * 0.035) * 9.0 + p.x * 0.045 + p.y * 0.03;
	float surge = pow(0.5 + 0.5 * sin(surge_ph), 2.0);
	float reach = 0.6 + foot * 1.5 + 3.6 * surge * (0.35 + 0.9 * fbm(p * 0.11 + vec2(t * 0.04, -t * 0.03)));
	// the wall line is broken: long stretches of thin wet lace, gaps, and
	// surges that throw torn foam several metres off the stone
	float along_wall = fbm(p * 0.07 + vec2(t * 0.03, 0.0));
	float wet_line = smoothstep(0.9 + foot * 1.8, 0.05, shore) * mix(0.15, 1.0, smoothstep(0.30, 0.68, along_wall));
	float shore_cov = wet_line * 0.85 + smoothstep(reach + foot, 0.0, shore) * smoothstep(0.30, 0.62, foam_n * 0.7 + foam_n2 * 0.5 + surge * 0.15) * 1.1;
	shore_cov += smoothstep(6.0 + foot * 1.5, 0.5, shore) * smoothstep(0.55, 0.80, foam_n2 * 0.6 + foam_n * 0.6) * 0.45 * (0.4 + surge);
	float wake_cov = clamp(trail_foam, 0.0, 1.4);
	float foam_cov = max(shore_cov, wake_cov) + 0.5 * min(shore_cov, wake_cov);
	float wake_foam = foam_cov > 0.01 ? lace_foam(p, foam_cov, foot, t) : 0.0;
	float shore_foam = 0.0;
	float impact_foam = impact * smoothstep(0.25, 0.6, foam_n2 + 0.25 * sin(t * 9.0 + dj * 4.0));
	// aerated boil around the plunge point, then foam rings pushed outward
	// that break up and thin as they spread
	float boil = smoothstep(7.5, 2.0, dj) * smoothstep(0.40, 0.68, foam_n2 * 0.7 + foam_fine * 0.5 + 0.1 * sin(t * 4.0 - dj));
	float ring_ph = fract((dj - t * 1.6) / 2.8);
	float rings = smoothstep(0.22, 0.0, abs(ring_ph - 0.5)) * exp(-dj * 0.16) * smoothstep(2.0, 4.0, dj)
		* smoothstep(0.32, 0.62, wake_break);
	impact_foam = clamp(impact_foam + boil * 0.85 + rings * 0.7, 0.0, 1.0);
	// scattered whitecaps on the sharpest crests of gusty patches, streaked
	// down-wind; open water outside the bay gets more of them
	vec2 wd = normalize(wind_dir);
	vec2 sp = vec2(dot(p, wd), dot(p, vec2(-wd.y, wd.x)));
	float streak = fbm(sp * vec2(0.55, 1.15) + vec2(-t * 0.6, 0.0));
	float open_sea = smoothstep(320.0, 700.0, shore);
	float cap_amt = whitecaps * mix(0.35, 1.0, gust) * open_sea;
	float wc_in = crest + (streak - 0.5) * 0.30 + (foam_fine - 0.5) * 0.08;
	float wc_t = 0.678 - cap_amt * 0.07;
	// bright core with a lacy, translucent rim
	float wcap = smoothstep(wc_t, wc_t + 0.05, wc_in) * 0.75 + smoothstep(wc_t + 0.03, wc_t + 0.09, wc_in) * 0.25;
	wcap *= smoothstep(0.34, 0.60, foam_n2 * 0.6 + streak * 0.35 + foam_fine * 0.3) * clamp(0.5 + cap_amt * 1.4, 0.0, 1.0) * open_sea;
	// older, thinned foam drifting down-wind from spent whitecaps
	float resid_n = fbm(sp * vec2(0.42, 0.85) * 0.6 + vec2(-t * 0.35, 3.0)) * 0.7 + foam_n2 * 0.3 + foam_fine * 0.15;
	float lace = smoothstep(0.45, 0.75, foam_fine * 0.6 + foam_n2 * 0.6);
	float residue = smoothstep(0.58, 0.74, resid_n) * lace * clamp(cap_amt * 2.2, 0.0, 1.0);
	float foam = clamp(shore_foam * 0.9 + wake_foam + impact_foam + wcap, 0.0, 1.0);
	foam *= clamp(1.0 - foot * 0.22, 0.3, 1.0);

	// ---------------- fresnel + reflection
	vec3 cam_to = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(cam_to);
	vec3 vdir = cam_to / dist;
	float ndv = clamp(dot(n_world, -vdir), 0.0, 1.0);
	float F = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	// unresolved roughness beyond the faded octaves dims the mirror a little
	F *= 1.0 - clamp(lost * 1.4, 0.0, 0.35);
	F *= mix(0.55, 1.0, smoothstep(4.0, 40.0, dist));
	vec3 refl;
	vec3 r_world = reflect(vdir, n_world);
	vec3 sky = mix(sky_horizon, sky_zenith, pow(clamp(r_world.y, 0.0, 1.0), 0.6));
	if (reflection_ready > 0.5) {
		vec2 ruv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
		// Slopes along the view direction tilt the reflected ray up/down
		// (vertical streaks); sideways slopes barely move it. Screen-space
		// offset is ~independent of distance, as with real chop.
		vec2 fwd = normalize(vdir.xz + vec2(1e-5));
		vec2 rgt = vec2(-fwd.y, fwd.x);
		vec2 sl = vec2(dot(g, rgt), dot(g, fwd));
		float k_d = distortion * 6.0;
		vec2 off = vec2(sl.x * 0.22, sl.y) * k_d;
		float spread = clamp(lost * 0.05 + 0.004, 0.0, 0.03);
		vec2 base = ruv + off;
		vec3 r0 = texture(reflection_tex, clamp(base, vec2(0.002), vec2(0.998))).rgb;
		vec3 r1 = texture(reflection_tex, clamp(base + vec2(0.0, spread), vec2(0.002), vec2(0.998))).rgb;
		vec3 r2 = texture(reflection_tex, clamp(base - vec2(0.0, spread * 1.6), vec2(0.002), vec2(0.998))).rgb;
		refl = (r0 * 0.5 + r1 * 0.25 + r2 * 0.25) * reflection_gain;
		// the mirror pass can miss things (culled undersides); never let a
		// reflection go blacker than a dim sky
		refl = max(refl, sky * 0.22);
	} else {
		refl = sky;
	}

	// ---------------- body colour: blue-teal deep water, lighter at the walls
	float depthish = smoothstep(0.0, 30.0, shore);
	vec3 body = mix(shallow_color, deep_color, depthish);
	// light scattered through thin crests: teal on wave tops, dark troughs
	float sss = clamp((crest - 0.30) * 2.2, 0.0, 1.0);
	body = mix(body * 0.74, body + scatter_color * 1.0, sss);
	// wave backs facing a low camera glow teal (light through the crest)
	float thru = clamp(dot(n_world.xz, -vdir.xz) * 5.0, 0.0, 1.0) * (1.0 - clamp(-vdir.y * 2.0, 0.0, 1.0));
	body += scatter_color * thru * 0.5 * (0.4 + sss);
	body *= mix(0.92, 1.08, gust);
	// thin lacy foam residue: a pale aqua lift, not grey scum
	body += vec3(0.11, 0.19, 0.19) * residue;

	v_foam = foam;
	v_glint_r = clamp(glint_roughness * 0.6 + lost * 0.9, 0.08, 0.45);
	v_sparkle = (1.0 - clamp(lost * 2.5, 0.0, 1.0)) * (1.0 - foam);
	float hz = smoothstep(horizon_radius * 0.55, horizon_radius * 0.98, length(cam_to.xz));
	v_horizon = hz;
	ALBEDO = mix(body * (1.0 - F), foam_color, foam) * (1.0 - hz);
	EMISSION = mix(refl * F * (1.0 - foam), horizon_colour(SCREEN_UV), hz);
	SPECULAR = 0.0;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.2, 1.0, foam);
	}
}

float ggx(float ndh, float r) {
	float a = r * r;
	float a2 = a * a;
	float den = ndh * ndh * (a2 - 1.0) + 1.0;
	return a2 / (PI * den * den);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// Water scatters skylight under a tower's shadow: only half the sun
	// shadow reaches the body colour (no hard near-black polygons).
	float diff_att = LIGHT_IS_DIRECTIONAL ? mix(0.5, 1.0, ATTENUATION) : ATTENUATION;
	DIFFUSE_LIGHT += ndl * diff_att * LIGHT_COLOR / PI;
	vec3 H = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, H), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 0.05, 1.0);
	float vdh = clamp(dot(VIEW, H), 0.0, 1.0);
	float Fs = 0.02 + 0.98 * pow(1.0 - vdh, 5.0);
	float k = Fs * ndl * 0.25 / ndv;
	// broad glitter path, widened by unresolved chop; capped so it can never
	// blow into a white disc
	float broad = min(ggx(ndh, v_glint_r) * k, spec_cap);
	// tiny sun sparkles on resolved wavelet facets
	float spark = min(ggx(ndh, 0.045) * k, 6.0) * v_sparkle * sparkle_gain;
	SPECULAR_LIGHT += ATTENUATION * LIGHT_COLOR * (broad + spark) * (1.0 - v_foam) * (1.0 - v_horizon);
}
