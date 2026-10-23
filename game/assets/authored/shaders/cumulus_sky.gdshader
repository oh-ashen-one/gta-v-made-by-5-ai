shader_type sky;
// Volumetric cumulus sky for Orchard Reach (aerial piece, Opus 5.5 wave D).
// Original work, written from scratch: no photographed sky, HDRI or
// third-party code.
//
// The wave-A sky drew clouds as a 2D density field projected onto the dome;
// from the helicopter they read as small, uniform white sprites (critics
// helicopter-C2, lighting-A4, skyline-1). This sky ray-marches a real cloud
// layer instead: a slab of cumulus between ~1.1 and ~2.9 km whose density is
// built from two procedural 3D noise volumes (Perlin fbm and inverted
// cellular "puff" lobes, generated at startup by Lighting). Each sample is lit
// by a short march toward the sun (LIGHT0) with Beer-Lambert extinction, a
// multiple-scattering lift and a two-lobe phase function, plus a height-graded
// sky ambient, so clouds get flat blue-grey bases, bright sun-facing towers
// and silver edges toward the sun. Because the layer is a real slab, clouds
// are huge overhead and stack into banks toward the horizon, then dissolve
// into the humid horizon haze (aerial perspective on the clouds themselves).
//
// Cost: the march runs in the half-resolution pass (and once into the
// radiance cubemap, which stays static because nothing here reads TIME).
render_mode use_half_res_pass;

uniform vec3 zenith_color : source_color = vec3(0.30, 0.44, 0.66);
uniform vec3 mid_color : source_color = vec3(0.52, 0.64, 0.80);
// Humid horizon band: cool pale blue-grey away from the sun (the old beige
// band made every aerial frame milky), warm toward it.
uniform vec3 horizon_cool : source_color = vec3(0.76, 0.81, 0.87);
uniform vec3 horizon_warm : source_color = vec3(1.0, 0.84, 0.66);
uniform vec3 ground_color : source_color = vec3(0.34, 0.33, 0.31);
uniform float sky_energy = 1.0;
uniform float cloud_coverage = 0.6;
uniform float cloud_bottom = 950.0;
uniform float cloud_top = 3300.0;
// World metres per tile of the shape volume (cumulus cells ~0.8-1.6 km).
uniform float shape_scale = 7600.0;
uniform float detail_scale = 1150.0;
uniform float cloud_density = 0.022;
uniform float cloud_sun_scale = 0.62;
uniform float cloud_amb_scale = 1.0;
uniform float cloud_far = 42000.0;
uniform float sun_disc_energy = 40.0;
uniform vec3 fallback_sun = vec3(0.80, 0.34, 0.20);
uniform sampler3D cloud_perlin : filter_linear, repeat_enable;
uniform sampler3D cloud_cells : filter_linear, repeat_enable;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float remap01(float v, float lo, float hi) {
	return clamp((v - lo) / max(hi - lo, 1e-4), 0.0, 1.0);
}

// Low-frequency weather: where cumulus fields and clear gaps sit.
float coverage_at(vec2 xz) {
	float a = texture(cloud_perlin, vec3(xz / 52000.0, 0.31)).r;
	float b = texture(cloud_perlin, vec3(xz / 17000.0 + 0.37, 0.71)).r;
	return clamp(cloud_coverage + (a - 0.5) * 0.9 + (b - 0.5) * 0.35, 0.0, 1.0);
}

// Cumulus body: Perlin-cellular "puff" lobes, a flat base and a rounded,
// coverage-dependent top (big towers where the field is dense).
float puff(vec3 p, bool detail) {
	float h01 = (p.y - cloud_bottom) / (cloud_top - cloud_bottom);
	if (h01 <= 0.0 || h01 >= 1.0) return 0.0;
	float cov = coverage_at(p.xz);
	if (cov < 0.05) return 0.0;
	vec3 q = p / shape_scale;
	float per = texture(cloud_perlin, q * vec3(1.0, 1.6, 1.0)).r;
	float cel = texture(cloud_cells, q * vec3(1.0, 1.6, 1.0) + vec3(0.13, 0.0, 0.41)).r;
	float cel2 = texture(cloud_cells, q * 2.7 + vec3(0.5, 0.2, 0.9)).r;
	float shape = remap01(per, (1.0 - cel) * 0.85, 1.0) * 0.55 + cel * 0.30 + cel2 * 0.15;
	float top = 0.30 + 0.70 * cov;
	float prof = smoothstep(0.0, 0.05, h01) * (1.0 - smoothstep(top * 0.45, top, h01));
	// Rounded tops: lobes narrow with height.
	float d = remap01(shape * prof, 1.0 - cov * 0.92, 1.0);
	if (detail && d > 0.0) {
		float det = texture(cloud_cells, p / detail_scale).r;
		float det2 = texture(cloud_perlin, p / (detail_scale * 0.37)).r;
		float ero = mix(det, det2, 0.35) * mix(0.42, 0.22, h01);
		d = remap01(d, ero, 1.0);
	}
	return d;
}

float hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5);
}

vec3 sky_base(vec3 d, vec3 sd, vec3 sun_tint) {
	float h = d.y;
	float hp = max(h, 0.0);
	vec2 dh = normalize(d.xz + vec2(1e-5));
	vec2 sh = normalize(sd.xz + vec2(1e-5));
	float az = clamp(dot(dh, sh) * 0.5 + 0.5, 0.0, 1.0);
	vec3 horizon = mix(horizon_cool, horizon_warm, pow(az, 2.2));
	float t1 = smoothstep(0.0, 0.30, hp);
	t1 = t1 * t1 * (3.0 - 2.0 * t1);
	float t2 = smoothstep(0.22, 0.95, hp);
	vec3 col = mix(horizon, mid_color, t1);
	col = mix(col, zenith_color, t2);
	col *= mix(0.93, 1.0, az);
	float mup = clamp(dot(d, sd), 0.0, 1.0);
	vec3 glow_tint = sun_tint * vec3(1.0, 0.90, 0.74);
	col += glow_tint * (pow(mup, 4.0) * 0.06 + pow(mup, 12.0) * 0.20 + pow(mup, 90.0) * 0.6 + pow(mup, 1200.0) * 3.0);
	if (h < 0.0) {
		col = mix(horizon * 0.96, ground_color, smoothstep(0.0, 0.22, -h));
	}
	return col;
}

// Front-to-back march through the cumulus slab. Returns in-scattered light
// (rgb) and opacity (a).
vec4 march_clouds(vec3 ro, vec3 d, vec3 sd, vec3 sun_col, vec3 haze, int steps, float jitter) {
	if (d.y <= 0.004) return vec4(0.0);
	float t0 = max((cloud_bottom - ro.y) / d.y, 0.0);
	float t1 = (cloud_top - ro.y) / d.y;
	if (t1 <= 0.0) return vec4(0.0);
	t1 = min(t1, cloud_far);
	if (t0 >= t1) return vec4(0.0);
	float seg = t1 - t0;
	float dt = seg / float(steps);
	float t = t0 + dt * jitter;
	float T = 1.0;
	vec3 acc = vec3(0.0);
	float depth_w = 0.0;
	float depth_sum = 0.0;
	float mu = dot(d, sd);
	float phase = (hg(mu, 0.72) * 0.45 + hg(mu, -0.18) * 0.55);
	vec3 amb_lo = vec3(0.36, 0.42, 0.53) * cloud_amb_scale;
	vec3 amb_hi = vec3(0.80, 0.86, 0.97) * cloud_amb_scale;
	for (int i = 0; i < steps; i++) {
		vec3 p = ro + d * t;
		float den = puff(p, true);
		if (den > 0.002) {
			float h01 = clamp((p.y - cloud_bottom) / (cloud_top - cloud_bottom), 0.0, 1.0);
			// Light march toward the sun: optical depth of the cloud above
			// this point. "above" = density stacked between it and the sun.
			float above = 0.0;
			float ls = 55.0;
			vec3 lp = p;
			for (int j = 0; j < 5; j++) {
				lp += sd * ls;
				above += puff(lp, false) * ls;
				ls *= 1.75;
			}
			float od = above * cloud_density;
			float beer = exp(-od);
			// Multiple scattering keeps thick cores from going black.
			float ms = max(beer, exp(-od * 0.22) * 0.55);
			float powder = 1.0 - exp(-den * dt * cloud_density * 2.2);
			vec3 sun_l = sun_col * ms * phase * mix(1.0, powder * 1.6 + 0.35, 0.35);
			vec3 amb = mix(amb_lo, amb_hi, smoothstep(0.0, 0.8, h01));
			vec3 S = (sun_l + amb) * den;
			float ext = den * cloud_density;
			float tr = exp(-ext * dt);
			acc += T * S * (1.0 - tr) / max(ext, 1e-5) * cloud_density;
			depth_sum += t * T * (1.0 - tr);
			depth_w += T * (1.0 - tr);
			T *= tr;
			if (T < 0.02) break;
		}
		t += dt;
	}
	float a = 1.0 - T;
	if (a <= 0.0) return vec4(0.0);
	// Aerial perspective on the clouds: distant banks sink into the haze.
	float dist = depth_w > 0.0 ? depth_sum / depth_w : t0;
	float fade = 1.0 - exp(-dist / 26000.0);
	acc = mix(acc, haze * a, clamp(fade * 1.15, 0.0, 0.92));
	// Low banks melt into the horizon band instead of ending in a hard line.
	float low = smoothstep(0.004, 0.06, d.y);
	return vec4(acc, a) * low;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(fallback_sun);
	vec3 sun_tint = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0, 0.84, 0.66);
	float sun_e = LIGHT0_ENABLED ? LIGHT0_ENERGY : 2.6;
	vec3 sun_col = sun_tint * sun_e * cloud_sun_scale;
	if (AT_HALF_RES_PASS) {
		vec3 haze = sky_base(vec3(d.x, max(d.y, 0.0) * 0.25, d.z), sd, sun_tint);
		vec4 c = march_clouds(POSITION, d, sd, sun_col, haze, 56, hash13(d * 911.0 + 3.1));
		COLOR = c.rgb * sky_energy;
		ALPHA = c.a;
	} else {
		vec3 col = sky_base(d, sd, sun_tint);
		// Sun disc (HDR: drives the bloom in backlit frames); clouds cover it.
		float disc = smoothstep(0.99980, 0.99990, dot(d, sd));
		col += vec3(1.0, 0.91, 0.75) * disc * sun_disc_energy * step(0.0, d.y);
		vec4 c;
		if (AT_CUBEMAP_PASS) {
			vec3 haze = sky_base(vec3(d.x, max(d.y, 0.0) * 0.25, d.z), sd, sun_tint);
			c = march_clouds(POSITION, d, sd, sun_col, haze, 32, 0.5);
		} else {
			c = HALF_RES_COLOR;
			c.rgb /= max(sky_energy, 1e-4);
		}
		col = col * (1.0 - c.a) + c.rgb;
		COLOR = max(col, vec3(0.0)) * sky_energy;
	}
}
