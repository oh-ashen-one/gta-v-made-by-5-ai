shader_type sky;
// Original procedural late-afternoon sky for Orchard Reach (lighting wave A).
// Written from scratch: no photographed sky, HDRI or third-party code.
//
// Reads the sun from LIGHT0 so the sky glow, the sun disc and the cloud
// lighting always agree with the shadow direction. Values are HDR: the band
// around the sun exceeds 1.0 so the tonemapper and glow give a real, restrained
// golden-hour bloom; the zenith stays a deep saturated blue.
uniform vec3 zenith_color : source_color = vec3(0.13, 0.29, 0.60);
uniform vec3 mid_color : source_color = vec3(0.38, 0.56, 0.82);
uniform vec3 horizon_cool : source_color = vec3(0.70, 0.76, 0.84);
uniform vec3 horizon_warm : source_color = vec3(1.00, 0.76, 0.42);
uniform vec3 ground_color : source_color = vec3(0.30, 0.28, 0.25);
uniform float sky_energy = 1.0;
uniform float cloud_coverage = 0.46;
uniform float sun_disc_energy = 26.0;
uniform vec3 fallback_sun = vec3(0.85, 0.28, 0.45);

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

float fbm(vec2 p) {
	float n = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 5; i++) {
		n += vnoise(p) * a;
		p = rot * p * 2.02 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return n;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(fallback_sun);
	vec3 sun_tint = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0, 0.76, 0.52);
	float h = d.y;
	float hp = max(h, 0.0);
	float mu = dot(d, sd);
	float mup = clamp(mu, 0.0, 1.0);

	// Horizon warms toward the sun's azimuth and cools away from it.
	vec2 dh = normalize(d.xz + vec2(1e-5));
	vec2 sh = normalize(sd.xz + vec2(1e-5));
	// Clamped: float error can push the dot past -1, and pow() of a negative
	// base is NaN, which the radiance convolution spreads over the whole map.
	float az = clamp(dot(dh, sh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 horizon = mix(horizon_cool, horizon_warm, pow(az, 2.2));
	// Thin bright band right at the horizon, then a fast climb into saturated
	// blue: a real gradient, not a uniform haze.
	float t1 = 1.0 - exp(-hp * 7.0);
	float t2 = smoothstep(0.12, 0.95, hp);
	vec3 col = mix(horizon, mid_color, t1);
	col = mix(col, zenith_color, t2);
	// Slightly darker, more saturated band opposite the sun (shadow side).
	col *= mix(0.86, 1.0, az);

	// Forward scattering around the low sun.
	vec3 glow_tint = sun_tint * vec3(1.0, 0.84, 0.58);
	col = mix(col, horizon_warm * 1.15, pow(mup, 4.0) * 0.62);
	col += glow_tint * (pow(mup, 5.0) * 0.30 + pow(mup, 48.0) * 0.80 + pow(mup, 700.0) * 2.6);

	if (h > 0.0) {
		// Cumulus deck: planar projection, domain-warped fbm.
		vec2 uv = d.xz / (h + 0.07);
		vec2 p = uv * 0.42 + vec2(7.3, 2.1);
		vec2 q = vec2(fbm(p), fbm(p + vec2(5.2, 1.3)));
		float n = fbm(p + q * 0.9);
		float lo = 1.0 - cloud_coverage;
		float cover = smoothstep(lo - 0.06, lo + 0.16, n);
		// Lighting: is the cloud thinner toward the sun? Then this edge is lit.
		vec2 toward = normalize(sd.xz + vec2(1e-5)) * 0.16;
		float n2 = fbm(p + q * 0.9 + toward);
		float lit = clamp(0.55 + (n - n2) * 4.5, 0.0, 1.0);
		float thick = smoothstep(lo, lo + 0.35, n);
		vec3 base = mix(vec3(0.46, 0.47, 0.56), vec3(0.62, 0.58, 0.62), az);
		vec3 lit_col = sun_tint * vec3(1.25, 1.02, 0.80);
		vec3 ccol = mix(base, lit_col, lit * (1.0 - thick * 0.45));
		// Silver lining: thin cloud edges blaze near the sun.
		ccol += glow_tint * pow(mup, 10.0) * (1.0 - thick) * 2.4;
		// Distant clouds sink into the horizon haze.
		float fade = smoothstep(0.0, 0.20, h);
		ccol = mix(horizon * 1.05, ccol, fade);
		float alpha = cover * smoothstep(0.012, 0.09, h) * 0.95;
		col = mix(col, ccol, alpha);
	}

	// Sun disc (HDR: drives the bloom in backlit frames).
	float disc = smoothstep(0.99986, 0.99994, mu);
	col += vec3(1.0, 0.86, 0.62) * disc * sun_disc_energy;

	if (h < 0.0) {
		col = mix(horizon * 0.92, ground_color, smoothstep(0.0, 0.22, -h));
	}
	COLOR = max(col, vec3(0.0)) * sky_energy;
}
