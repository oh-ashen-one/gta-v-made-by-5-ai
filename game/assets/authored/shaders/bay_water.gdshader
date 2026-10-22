shader_type spatial;
// Marina-bay water (water piece, Opus 5.5 loop, wave A).
// Opaque so it stays cheap and sorts with the city. Everything that makes it
// read as water is here: a deep-water swell spectrum for animated normals,
// a planar reflection (BayWater renders a mirrored camera into
// reflection_tex), Schlick fresnel between the reflection and a murky
// teal-green body colour, shoreline lapping foam, Kelvin-wedge boat wakes and
// a capped sun glint so no light can blow a white disc into the frame.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D reflection_tex : filter_linear, repeat_disable;
uniform float reflection_ready = 0.0;
uniform float reflection_gain = 0.85;
uniform vec3 deep_color : source_color = vec3(0.040, 0.215, 0.215);
uniform vec3 shallow_color : source_color = vec3(0.075, 0.300, 0.270);
uniform vec3 sky_horizon : source_color = vec3(0.78, 0.76, 0.72);
uniform vec3 sky_zenith : source_color = vec3(0.32, 0.47, 0.68);
uniform vec3 foam_color : source_color = vec3(0.86, 0.88, 0.86);
uniform float water_level = -0.9;
uniform float near_shore_z = -350.7;
uniform float far_shore_z = -615.0;
// xmin, zmin, xmax, zmax of the Merlion pier base and the boat pontoon
uniform vec4 pier_rect = vec4(38.0, -354.0, 52.0, -340.0);
uniform vec4 pontoon_rect = vec4(12.0, -357.0, 34.0, -352.0);
uniform vec3 jet_impact = vec3(45.0, -0.9, -359.0);
uniform vec4 boats[20];      // x, z, heading (rad, +x = 0), speed m/s
uniform vec4 boat_size[20];  // half length, half beam, 0, 0
uniform int boat_count = 0;
uniform float distortion = 0.032;
uniform float spec_cap = 0.32;
uniform float glint_roughness = 0.16;
uniform vec2 wind_dir = vec2(0.80, -0.60);

varying vec3 world_pos;

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

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Sum of deep-water sine waves; returns the height gradient. Each wave fades
// out once a pixel covers half its wavelength (no shimmering moire far away).
vec2 swell_gradient(vec2 p, float t, float foot, float choppy) {
	vec2 g = vec2(0.0);
	float lambda = 13.0;
	float amp = 0.16;
	float spread = 0.0;
	for (int i = 0; i < 11; i++) {
		float fi = float(i);
		spread = (hash12(vec2(fi, 7.0)) - 0.5) * 1.9;
		vec2 d = normalize(rot(wind_dir, spread));
		float k = 6.2831853 / lambda;
		float w = sqrt(9.81 * k);
		float ph = k * dot(d, p) - w * t + fi * 1.7;
		float fade = clamp(1.0 - foot / (lambda * 0.35), 0.0, 1.0);
		g += d * (amp * k * cos(ph)) * fade * (i > 5 ? choppy : 1.0);
		lambda *= 0.68;
		amp *= 0.66;
	}
	return g;
}

float rect_distance(vec2 p, vec4 r) {
	vec2 c = (r.xy + r.zw) * 0.5;
	vec2 h = (r.zw - r.xy) * 0.5;
	vec2 q = abs(p - c) - h;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
}

void fragment() {
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

	// ---------------- boats: hull wash, bow wave and Kelvin wedge
	float wake = 0.0;
	float churn = 0.0;
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
		float spd = clamp(b.w / 6.0, 0.0, 1.4);
		// contact ring around the hull (moored boats still lap a little)
		float e = length(vec2(along / (hl + 0.6), lat / (hb + 0.5)));
		float ring = smoothstep(1.45, 1.0, e) * (0.30 + 0.70 * spd);
		ring *= smoothstep(-0.2, 0.6, along / hl + 0.4) + 0.25;
		churn += ring;
		if (spd > 0.02) {
			float behind = -(along + hl * 0.2);
			if (behind > 0.0) {
				float arm = abs(abs(lat) - hb * 0.8 - behind * 0.30);
				float width = 0.55 + behind * 0.06;
				float fade = exp(-behind / (12.0 * spd + 8.0));
				wake += smoothstep(width, 0.0, arm) * fade * min(spd, 1.0) * 0.55;
				float wash = smoothstep(hb * 0.8 + behind * 0.06, 0.0, abs(lat)) * exp(-behind / (8.0 * spd + 3.0));
				churn += wash * min(spd, 1.0) * 1.7;
			}
		}
	}

	// ---------------- jet impact: rings + splash foam
	float dj = length(p - jet_impact.xz);
	float impact = smoothstep(4.2, 0.6, dj);
	float ripples = sin(dj * 3.4 - t * 6.0) * exp(-dj * 0.28) * smoothstep(0.3, 1.2, dj);

	// ---------------- normals
	float rough_water = clamp(churn * 0.8 + impact * 1.2 + wake * 0.5, 0.0, 2.0);
	vec2 g = swell_gradient(p, t, foot, 1.0 + rough_water * 1.6);
	// micro chop from two drifting noise layers (finite difference)
	float nf = 0.55;
	vec2 q1 = p * nf + vec2(t * 0.35, -t * 0.22);
	vec2 q2 = p * nf * 2.3 + vec2(-t * 0.27, t * 0.31);
	float micro_fade = clamp(1.0 - foot * 1.4, 0.0, 1.0);
	float e0 = 0.08;
	float h0 = fbm(q1) + 0.5 * fbm(q2);
	float hx = fbm(q1 + vec2(e0, 0.0)) + 0.5 * fbm(q2 + vec2(e0 * 2.3, 0.0));
	float hz = fbm(q1 + vec2(0.0, e0)) + 0.5 * fbm(q2 + vec2(0.0, e0 * 2.3));
	g += vec2(hx - h0, hz - h0) / e0 * nf * 0.05 * micro_fade * (1.0 + rough_water);
	vec2 rdir = (p - jet_impact.xz) / max(dj, 0.001);
	g += rdir * ripples * 0.12;
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// ---------------- foam
	float lap = 0.55 + 0.45 * sin(t * 1.1 + p.x * 0.09 + p.y * 0.05);
	float foam_n = fbm(p * 0.9 + vec2(t * 0.15, t * 0.07));
	float foam_n2 = fbm(p * 2.7 - vec2(t * 0.2, 0.0));
	float shore_foam = smoothstep(0.9 + 0.8 * lap, 0.0, shore) * smoothstep(0.30, 0.62, foam_n * 0.7 + foam_n2 * 0.5);
	float wake_foam = clamp(wake * 1.4 + churn, 0.0, 1.0) * smoothstep(0.32, 0.70, foam_n2 * 0.65 + foam_n * 0.55);
	float impact_foam = impact * smoothstep(0.25, 0.6, foam_n2 + 0.25 * sin(t * 9.0 + dj * 4.0));
	float foam = clamp(shore_foam * 0.85 + wake_foam + impact_foam, 0.0, 1.0);
	foam *= clamp(1.0 - foot * 0.25, 0.25, 1.0);

	// ---------------- fresnel + reflection
	vec3 V = normalize(VIEW);
	float ndv = clamp(dot(NORMAL, V), 0.0, 1.0);
	float F = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 cam_to = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(cam_to);
	vec3 refl;
	vec3 r_world = reflect(cam_to / dist, n_world);
	vec3 sky = mix(sky_horizon, sky_zenith, pow(clamp(r_world.y, 0.0, 1.0), 0.6));
	if (reflection_ready > 0.5) {
		vec2 ruv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);
		float strength = distortion * clamp(14.0 / (dist * 0.2 + 6.0), 0.3, 1.0);
		ruv += vec2(n_world.x, -n_world.z) * strength;
		ruv = clamp(ruv, vec2(0.002), vec2(0.998));
		refl = texture(reflection_tex, ruv).rgb * reflection_gain;
	} else {
		refl = sky;
	}

	// ---------------- body colour: shallower teal at the walls, deep green-black in the bay
	float depthish = smoothstep(0.0, 26.0, shore);
	vec3 body = mix(shallow_color, deep_color, depthish);
	// light passing through wave crests (subtle teal lift on slopes facing away)
	body += vec3(0.015, 0.060, 0.050) * clamp(dot(n_world.xz, -wind_dir) * 6.0, 0.0, 1.0);

	ALBEDO = mix(body * (1.0 - F), foam_color, foam);
	EMISSION = refl * F * (1.0 - foam);
	SPECULAR = 0.0;
	METALLIC = 0.0;
	ROUGHNESS = mix(glint_roughness, 1.0, foam);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI;
	// Capped GGX glint. ROUGHNESS carries the foam mask (foam is matte).
	float foam = clamp((ROUGHNESS - glint_roughness) / (1.0 - glint_roughness), 0.0, 1.0);
	vec3 H = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, H), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 0.05, 1.0);
	float a = glint_roughness * glint_roughness;
	float a2 = a * a;
	float den = ndh * ndh * (a2 - 1.0) + 1.0;
	float D = a2 / (PI * den * den);
	float vdh = clamp(dot(VIEW, H), 0.0, 1.0);
	float Fs = 0.02 + 0.98 * pow(1.0 - vdh, 5.0);
	float s = D * Fs * ndl * 0.25 / ndv;
	SPECULAR_LIGHT += ATTENUATION * LIGHT_COLOR * min(s, spec_cap) * (1.0 - foam);
}
