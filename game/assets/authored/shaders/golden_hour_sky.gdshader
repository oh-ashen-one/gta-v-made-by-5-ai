shader_type sky;
// Original procedural late-afternoon tropical sky for Orchard Reach (lighting
// wave A, round 2). Written from scratch: no photographed sky, HDRI or
// third-party code.
//
// Round 2 (critic A1: "empty, oversaturated cobalt gradient"): a pale humid
// blue that fades into a warm haze near the horizon, under a deck of large
// cumulus. Each cloud is shaded from its own density field: the edge toward
// the sun and the upper (zenith-side) silhouette are lit warm white, the flat
// underside and the thick core fall to a blue-grey base. Everything reads the
// sun from LIGHT0 so the cloud lighting agrees with the shadow direction.
uniform vec3 zenith_color : source_color = vec3(0.36, 0.53, 0.78);
uniform vec3 mid_color : source_color = vec3(0.58, 0.70, 0.86);
uniform vec3 horizon_cool : source_color = vec3(0.84, 0.86, 0.88);
uniform vec3 horizon_warm : source_color = vec3(1.00, 0.88, 0.72);
uniform vec3 ground_color : source_color = vec3(0.34, 0.32, 0.29);
uniform float sky_energy = 1.0;
uniform float cloud_coverage = 0.56;
uniform float cloud_scale = 0.62;
uniform float sun_disc_energy = 22.0;
uniform vec3 fallback_sun = vec3(0.80, 0.40, 0.45);

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Low-frequency coverage: where cloud banks sit.
float fbm3(vec2 p) {
	float n = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		n += vnoise(p) * a;
		p = rot * p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return n / 0.875;
}

// Billowed detail: rounded cauliflower puffs instead of smeared streaks.
float billow(vec2 p) {
	float n = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		float v = vnoise(p);
		n += (1.0 - abs(v * 2.0 - 1.0)) * a;
		p = rot * p * 2.07 + vec2(3.1, 4.7);
		a *= 0.5;
	}
	return n / 0.9375;
}

float density(vec2 p) {
	float c = fbm3(p * 0.42);
	float b = billow(p * 1.15 + vec2(c * 1.4, -c));
	float n = c * 0.62 + b * 0.48;
	float lo = 1.0 - cloud_coverage;
	return smoothstep(lo, lo + 0.22, n);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(fallback_sun);
	vec3 sun_tint = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0, 0.82, 0.62);
	float h = d.y;
	float hp = max(h, 0.0);
	float mu = dot(d, sd);
	float mup = clamp(mu, 0.0, 1.0);

	vec2 dh = normalize(d.xz + vec2(1e-5));
	vec2 sh = normalize(sd.xz + vec2(1e-5));
	// Clamped: float error can push the dot past -1, and pow() of a negative
	// base is NaN, which the radiance convolution spreads over the whole map.
	float az = clamp(dot(dh, sh) * 0.5 + 0.5, 0.0, 1.0);

	// Humid tropical gradient: pale blue overhead, a wide warm haze band low
	// down (warmest toward the sun's azimuth), no saturated cobalt.
	vec3 horizon = mix(horizon_cool, horizon_warm, pow(az, 1.6));
	float t1 = smoothstep(0.0, 0.32, hp);
	t1 = t1 * t1 * (3.0 - 2.0 * t1);
	float t2 = smoothstep(0.25, 0.95, hp);
	vec3 col = mix(horizon, mid_color, t1);
	col = mix(col, zenith_color, t2);
	col *= mix(0.92, 1.0, az);

	// Forward scattering around the sun: a tight halo, not a veil.
	vec3 glow_tint = sun_tint * vec3(1.0, 0.90, 0.72);
	col += glow_tint * (pow(mup, 8.0) * 0.22 + pow(mup, 64.0) * 0.55 + pow(mup, 900.0) * 2.2);

	if (h > 0.0) {
		// Planar cloud deck: perspective shrinks clouds toward the horizon.
		float r = 1.0 / (h + 0.055);
		vec2 uv = d.xz * r;
		vec2 p = uv * cloud_scale + vec2(7.3, 2.1);
		float D = density(p);
		if (D > 0.002) {
			// Screen-up (toward the zenith) and screen-down (outward) samples:
			// density thinning upward = lit cauliflower top; thinning downward
			// = the flat shaded base.
			float step_v = 0.10 + 0.05 * r;
			float d_up = density(p - dh * step_v);
			float d_dn = density(p + dh * step_v);
			// Toward the sun along the deck: thinning = sun-facing edge.
			float d_sun = density(p + sh * 0.22);
			float top = clamp((D - d_up) * 1.6 + 0.35, 0.0, 1.0);
			float base = clamp((D - d_dn) * 1.8, 0.0, 1.0);
			float sunface = clamp((D - d_sun) * 2.2 + 0.25, 0.0, 1.0);
			float core = smoothstep(0.55, 1.0, D) * (1.0 - top);
			float light = clamp(0.30 + 0.42 * top + 0.42 * sunface * (0.55 + 0.45 * az) - 0.38 * base - 0.22 * core, 0.0, 1.15);
			vec3 shade_col = mix(vec3(0.50, 0.55, 0.64), vec3(0.62, 0.60, 0.62), az);
			vec3 lit_col = mix(vec3(1.0, 0.98, 0.95), sun_tint * vec3(1.05, 0.97, 0.88), 0.45) * 1.32;
			vec3 ccol = mix(shade_col, lit_col, light);
			// Silver lining on thin edges close to the sun.
			ccol += glow_tint * pow(mup, 12.0) * (1.0 - D) * 1.6;
			// Far clouds dissolve into the horizon haze (aerial perspective).
			float fade = smoothstep(0.015, 0.16, h);
			ccol = mix(horizon * 1.04, ccol, 0.35 + 0.65 * fade);
			float alpha = D * smoothstep(0.008, 0.05, h);
			col = mix(col, ccol, alpha);
		}
	}

	// Sun disc (HDR: drives the bloom in backlit frames).
	float disc = smoothstep(0.99986, 0.99994, mu);
	col += vec3(1.0, 0.90, 0.72) * disc * sun_disc_energy;

	if (h < 0.0) {
		col = mix(horizon * 0.95, ground_color, smoothstep(0.0, 0.22, -h));
	}
	COLOR = max(col, vec3(0.0)) * sky_energy;
}
