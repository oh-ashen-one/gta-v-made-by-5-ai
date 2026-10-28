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
uniform vec3 zenith_color : source_color = vec3(0.30, 0.47, 0.76);
uniform vec3 mid_color : source_color = vec3(0.55, 0.63, 0.76);
uniform vec3 horizon_cool : source_color = vec3(0.88, 0.85, 0.80);
uniform vec3 horizon_warm : source_color = vec3(1.0, 0.80, 0.58);
uniform vec3 ground_color : source_color = vec3(0.34, 0.32, 0.29);
uniform float sky_energy = 1.0;
uniform float cloud_coverage = 0.55;
uniform float cloud_scale = 3.2;
uniform float sun_disc_energy = 40.0;
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
		a *= 0.42;
	}
	return n / 0.8526;
}

// Inverted cellular noise: round cauliflower lobes for cumulus tops.
float puff(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float md = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash2(i + g), hash2(i + g + vec2(17.3, 5.9)));
			vec2 r = g + o - f;
			md = min(md, dot(r, r));
		}
	}
	return 1.0 - clamp(sqrt(md), 0.0, 1.0);
}

float density(vec2 p) {
	float c = fbm3(p * 0.80);
	vec2 w = p + vec2(c * 0.6, -c * 0.5);
	float b = puff(w * 1.7) * 0.62 + puff(w * 3.6 + vec2(4.1, 2.3)) * 0.26 + billow(w * 7.5) * 0.12;
	float n = c * 0.66 + b * 0.50;
	// Field mean is ~0.6 (std ~0.1): coverage 0.5 leaves ~40 % of the deck clear.
	// Low-frequency coverage field: big cloud banks and wide clear gaps
	// instead of evenly scattered popcorn (critic A3).
	float cov = cloud_coverage + 0.30 * (vnoise(p * 0.21 + vec2(3.0, 8.0)) - 0.5);
	float lo = 1.17 - cov;
	// Narrow ramp: crisp cumulus outlines with blue gaps, not a milky veil.
	return smoothstep(lo, lo + 0.07, n) * (0.75 + 0.25 * smoothstep(lo + 0.07, lo + 0.25, n));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(fallback_sun);
	vec3 sun_tint = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0, 0.82, 0.62);
	float h = d.y;
	float hp = max(h, 0.0);
	float mu = dot(d, sd);
	float mup = clamp(mu, 0.0, 1.0);

	// The legacy azimuth projection remains unchanged outside the overhead
	// cap. At its pole a nonzero cloud radius sampled an entire noise ring,
	// stretching clouds into spokes. Collapse the field AND radial shadow
	// samples smoothly to one point, and remove the view-azimuth lighting bias.
	vec2 azimuth_ray = d.xz + vec2(1e-5);
	float azimuth_radius = length(azimuth_ray);
	vec2 dh = vec2(0.0);
	if (azimuth_radius > 0.0) {
		dh = normalize(azimuth_ray);
	}
	vec2 sh = normalize(sd.xz + vec2(1e-5));
	float pole_weight = 1.0;
	if (h > 0.0) {
		// Approximately the upper 23.6 degrees of the dome. Using the same
		// epsilon-shifted radius also regularizes the legacy normalize(0) ray.
		pole_weight = smoothstep(0.0, 0.4, azimuth_radius);
	}
	vec2 cloud_dh = dh * pole_weight;
	// Clamped: float error can push the dot past -1, and pow() of a negative
	// base is NaN, which the radiance convolution spreads over the whole map.
	float az = clamp(dot(dh, sh) * 0.5 + 0.5, 0.0, 1.0);
	if (pole_weight < 1.0) {
		az = mix(0.5, az, pole_weight);
	}

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
	// Round 4: a wide warm veil around the low sun (golden-hour haze).
	col += glow_tint * (pow(mup, 4.0) * 0.05 + pow(mup, 10.0) * 0.20 + pow(mup, 80.0) * 0.6 + pow(mup, 1200.0) * 3.0);

	if (h > 0.0) {
		// Cloud deck in a softened perspective: rho = (h + 0.10)^-0.45 still
		// shrinks clouds toward the horizon (2.9x), but a flat-plane
		// projection squashes them into streaks; this keeps distant cumulus
		// about a third as tall as wide, so the horizon band stacks puffs.
		// Round 4: closer to a true cloud-plane projection, so cumulus are
		// big overhead and flatten into stacked banks toward the horizon.
		float r = pow(h + 0.06, -0.62) * 0.68;
		vec2 p = cloud_dh * r * cloud_scale + vec2(7.3, 2.1);
		float D = density(p);
		if (D > 0.002) {
			// Self-shadowing from the cloud's own density field. Density
			// stacked above this point on screen (toward the zenith) means we
			// are looking at the lower body or flat base; density between us
			// and the sun means the far, shaded side. Both darken; the free
			// upper silhouette and the sun-facing edge stay bright.
			float step_v = 0.10;
			float up1 = density(p - cloud_dh * step_v);
			float up2 = density(p - cloud_dh * step_v * 2.6);
			float dn1 = density(p + cloud_dh * step_v * 1.4);
			float sn1 = density(p + sh * 0.10);
			float sn2 = density(p + sh * 0.26);
			float above = up1 * 0.55 + up2 * 0.45;
			float toward_sun = sn1 * 0.5 + sn2 * 0.5;
			// Flat base: the bottom rim (nothing below) of a tall stack.
			float base = clamp((D - dn1) * 1.6, 0.0, 1.0) * above;
			float light = 1.15 - 1.05 * above - 0.45 * toward_sun * (0.4 + 0.6 * az) - 0.55 * base;
			light += 0.25 * (1.0 - toward_sun) * az;
			light = clamp(light, 0.0, 1.15);
			vec3 shade_col = mix(vec3(0.33, 0.38, 0.49), vec3(0.47, 0.44, 0.50), az);
			vec3 lit_col = mix(vec3(1.0, 0.98, 0.95), sun_tint * vec3(1.05, 0.97, 0.88), 0.45) * 1.32;
			vec3 ccol = mix(shade_col, lit_col, light);
			// Silver lining on thin edges close to the sun.
			ccol += glow_tint * pow(mup, 12.0) * (1.0 - D) * 1.6;
			// Far clouds dissolve into the horizon haze (aerial perspective).
			float fade = smoothstep(0.0, 0.10, h);
			ccol = mix(horizon * 1.04, ccol, 0.55 + 0.45 * fade);
			float alpha = D * smoothstep(0.004, 0.035, h);
			col = mix(col, ccol, alpha);
		}
	}

	// Sun disc (HDR: drives the bloom in backlit frames).
	float disc = smoothstep(0.99980, 0.99990, mu);
	col += vec3(1.0, 0.90, 0.72) * disc * sun_disc_energy;

	if (h < 0.0) {
		col = mix(horizon * 0.95, ground_color, smoothstep(0.0, 0.22, -h));
	}
	COLOR = max(col, vec3(0.0)) * sky_energy;
}
