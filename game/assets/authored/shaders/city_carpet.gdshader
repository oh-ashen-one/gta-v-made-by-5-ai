// City carpet (skyline round 4, Opus 5.5). Procedural urban ground for the far
// shore and the hinterland behind it: street grid, kerbs, plots with varied
// roofs / courtyards / car parks, parks and street-tree canopy. Round 3's far
// shore was a plain soil-textured slab that read as brown dirt, and the land
// ended in a hard edge with open sea behind the CBD (critic A3). The low-rise
// MultiMesh blocks of SkylineHorizon stand on this; between them the ground
// itself still reads as dense city at 1-4 km. Detail filters to its mean with
// distance (fwidth) so the grazing far ground does not shimmer.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 haze_col : source_color = vec3(0.60, 0.67, 0.77);
uniform vec3 haze_sun_col : source_color = vec3(0.98, 0.86, 0.70);
uniform vec3 horizon_col : source_color = vec3(0.80, 0.83, 0.87);
uniform vec3 sun_dir = vec3(0.85, 0.28, 0.45);
uniform float haze_start = 150.0;
uniform float haze_density = 0.0022;
uniform float haze_max = 0.82;
uniform float horizon_start = 1500.0;
uniform float horizon_end = 2600.0;
uniform float far_full = 1.0;
uniform vec3 fog_col : source_color = vec3(0.70, 0.77, 0.86);
uniform float fog_density_ref = 0.00046;
uniform float fog_scale = 1.0;
uniform float block_m = 110.0;
uniform float street_m = 13.0;
// 0 = full city fabric, 1 = waterfront parkland (lawns, paths, tree canopy).
uniform float park_bias = 0.0;

varying vec3 wpos;
#include "res://assets/authored/shaders/skyline_haze.gdshaderinc"

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}
// 1 inside [0, w) of each unit period, box-filtered toward w over fw.
float band(float x, float w, float fw) {
	float f = fract(x);
	return mix(step(f, w), w, clamp(fw * 1.5 - 0.15, 0.0, 1.0));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 fw = fwidth(p);
	float fwm = max(fw.x, fw.y);
	// Same block grid as SkylineHorizon's low-rise blocks (street at the low
	// edge of every block), so buildings never stand in a street.
	vec2 q = p;
	vec2 cell = floor(q / block_m);
	vec2 local = q / block_m - cell;
	float h = hash2(cell);
	float h2 = hash2(cell + 17.3);
	// Street mask (two directions) and kerb/pavement strip.
	float sw = street_m / block_m;
	float st = max(band(q.x / block_m, sw, fw.x / block_m), band(q.y / block_m, sw, fw.y / block_m));
	float kw = (street_m + 6.0) / block_m;
	float kerb = max(band(q.x / block_m + 0.5 * (kw - sw), kw, fw.x / block_m), band(q.y / block_m + 0.5 * (kw - sw), kw, fw.y / block_m));
	// Plots: each block splits into 2-4 x 2-3 lots.
	vec2 nlots = vec2(2.0 + floor(h * 3.0), 2.0 + floor(h2 * 2.0));
	vec2 lot = floor(local * nlots);
	float lh = hash2(cell * 3.1 + lot);
	float lh2 = hash2(cell * 1.7 + lot + 5.0);
	vec2 lf = fract(local * nlots);
	// Lot boundaries: service lanes / shadow lines.
	vec2 lfw = fw / block_m * nlots;
	float lane = max(band(lf.x + 0.03, 0.06, lfw.x), band(lf.y + 0.03, 0.06, lfw.y));
	bool park = h < 0.12 + 0.75 * park_bias;
	vec3 roof;
	if (park) {
		float n = vnoise(p * 0.09) * 0.6 + vnoise(p * 0.023) * 0.4;
		vec3 lawn = lin(mix(vec3(0.27, 0.36, 0.18), vec3(0.33, 0.42, 0.22), n));
		float canopy = smoothstep(0.52, 0.66, vnoise(p * 0.07 + 3.0) * 0.7 + vnoise(p * 0.21) * 0.3);
		roof = mix(lawn, lin(vec3(0.11, 0.20, 0.09)) * (0.8 + 0.4 * n), canopy);
		float path = band(dot(p, vec2(0.6, 0.8)) / 47.0, 0.06, fwm / 47.0) * (1.0 - canopy);
		roof = mix(roof, lin(vec3(0.62, 0.59, 0.53)), path * 0.8);
		lane = 0.0;
	} else {
		// Roofs, courtyards and car parks.
		if (lh < 0.28) roof = lin(vec3(0.58, 0.34, 0.25));       // clay tile
		else if (lh < 0.50) roof = lin(vec3(0.56, 0.56, 0.54));  // concrete deck
		else if (lh < 0.66) roof = lin(vec3(0.72, 0.71, 0.68));  // pale membrane
		else if (lh < 0.78) roof = lin(vec3(0.28, 0.30, 0.31));  // dark metal
		else if (lh < 0.88) roof = lin(vec3(0.30, 0.30, 0.31));  // car park asphalt
		else roof = lin(vec3(0.24, 0.33, 0.17));                 // courtyard green
		roof *= 0.82 + 0.3 * lh2;
		// Roof plant and stains on the larger decks.
		float speck = step(0.8, hash2(floor(p / 4.0) + h)) * (1.0 - clamp(fwm / 3.0, 0.0, 1.0));
		roof = mix(roof, roof * 0.6, speck * 0.6);
		// Building shadow on the side away from the sun (sun from +x +z).
		vec2 sd2 = normalize(sun_dir.xz);
		float shade_edge = smoothstep(0.7, 0.98, dot(lf - 0.5, -sd2) * 2.0);
		roof *= 1.0 - 0.45 * shade_edge * (1.0 - clamp(lfw.x * 2.0, 0.0, 1.0));
	}
	vec3 asphalt = lin(vec3(0.21, 0.21, 0.22)) * (0.9 + 0.2 * vnoise(p * 0.05));
	vec3 pave = lin(vec3(0.55, 0.54, 0.51));
	// Street-tree canopy along the kerbs.
	float trees = smoothstep(0.55, 0.72, vnoise(p * 0.16 + 7.0)) * kerb * (1.0 - st * 0.4);
	vec3 c = roof;
	c = mix(c, lin(vec3(0.14, 0.15, 0.15)), lane * 0.55);
	c = mix(c, pave, (kerb - st) * 0.9);
	c = mix(c, asphalt, st);
	// Moving traffic: two lanes each way on every street, cars ~4.5 m long
	// in 9 m slots, ~40% occupied, drifting at 9-15 m/s. Seen from the
	// helicopter it is a field of moving specks along the grid.
	float car_fade = 1.0 - clamp((fwm - 0.6) / 2.4, 0.0, 1.0);
	// Only street pixels near enough to resolve a car pay for the lanes.
	if (car_fade * st > 0.001) for (int axis = 0; axis < 2; axis++) {
		float across = (axis == 0 ? fract(q.y / block_m) : fract(q.x / block_m)) * block_m;
		float along = axis == 0 ? q.x : q.y;
		float row = axis == 0 ? cell.y : cell.x;
		for (int ln = 0; ln < 2; ln++) {
			float l0 = ln == 0 ? 2.6 : 7.6;
			float in_lane = step(l0, across) * step(across, l0 + 2.2);
			float dir = ln == 0 ? 1.0 : -1.0;
			float spd = 9.0 + 6.0 * hash2(vec2(row, float(ln) + float(axis) * 3.0));
			float u = along + dir * TIME * spd;
			float slot = floor(u / 9.0);
			float occ = step(hash2(vec2(slot, row * 7.0 + float(ln) + float(axis) * 13.0)), 0.4);
			float body = step(fract(u / 9.0), 0.5);
			float k = hash2(vec2(slot * 1.7, row + float(ln)));
			vec3 paint = k < 0.35 ? lin(vec3(0.85, 0.85, 0.83)) : (k < 0.6 ? lin(vec3(0.55, 0.57, 0.6)) : (k < 0.82 ? lin(vec3(0.08, 0.09, 0.1)) : (k < 0.92 ? lin(vec3(0.6, 0.1, 0.08)) : lin(vec3(0.15, 0.25, 0.5)))));
			c = mix(c, paint, in_lane * occ * body * st * car_fade);
		}
	}
	c = mix(c, lin(vec3(0.12, 0.22, 0.10)), trees * 0.85);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.3;
	FOG = skyline_haze_clip(wpos, CAMERA_POSITION_WORLD, far_full, -VERTEX.z, INV_PROJECTION_MATRIX);
}
