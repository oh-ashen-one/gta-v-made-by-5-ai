shader_type spatial;
// Worn arterial asphalt (wave B "materials"). World-space; knows the district
// road grid so tyre tracks, oil lines, gutter grime, patches and manholes sit
// in real lane positions (left-hand traffic, two lanes each way).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.255, 0.255, 0.265);
uniform float road_grid = 1.0;      // 1 = district carriageway grid, 0 = lot / yard
uniform float grid_period = 160.0;
uniform float road_half = 8.0;
uniform float tile_m = 4.0;
uniform float wear = 1.0;
uniform sampler2D agg_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D agg_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grain_k = 0.42;
// nearfield R: photographic carriageway map (provider road_asphalt, ~7 m tile,
// wheel-track bands along V) laid in the lane frame so its bands follow the
// lanes; two offset samples and macro noise hide the repeat. photo_k = 0
// (no provider file) keeps the procedural surface only.
uniform sampler2D photo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D photo_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float photo_k = 0.0;
uniform float photo_tile = 7.0;
uniform vec3 photo_mean = vec3(0.318, 0.315, 0.31);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float rect_mask(vec2 lc, vec2 lo, vec2 hi, float soft) {
	vec2 a = smoothstep(lo - soft, lo + soft, lc) * (1.0 - smoothstep(hi - soft, hi + soft, lc));
	return a.x * a.y;
}

// Smooth value noise (band-limited enough to fade cleanly by pixel footprint).
float vnoise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = w_hash12(i);
	float b = w_hash12(i + vec2(1.0, 0.0));
	float c = w_hash12(i + vec2(0.0, 1.0));
	float d = w_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Octave weight: fades a feature of `cell` metres once a pixel covers it.
float oct_w(float cell, float px) {
	return 1.0 - smoothstep(0.30 * cell, 0.85 * cell, px);
}

void fragment() {
	vec2 p = v_world.xz;
	// Metres per pixel, for footprint-aware aggregate detail.
	float px = max(length(fwidth(p)), 1e-4);
	float dist = length(VERTEX);
	// Nearfield (opus55 wave D): graded stone aggregate in bitumen from a 2 m
	// authored tile, sampled twice (rotated, 2 m and 3.3 m) so it never tiles.
	// Mip filtering averages the grain away with distance, so the road far off
	// is one calm tone instead of the old blotchy camouflage mottle.
	float g1 = texture(agg_tex, p / 2.0).g;
	float g2 = texture(agg_tex, w_rot(p, 0.73) / 3.3 + 0.37).g;
	float grain = (mix(g1, g2, 0.42) - 0.5) * 2.0;
	vec4 big = w_mask(p / 97.0);
	vec4 med = w_mask(w_rot(p, 1.1) / 23.0 + 0.21);
	vec4 sml = w_mask(p / 6.3 + 0.5);
	// Coherent, low-amplitude large-scale variation only (no mottle).
	float tone = (0.95 + 0.10 * big.r) * (0.97 + 0.06 * med.g);
	// Sun-bleached, oxidised areas read slightly lighter and greyer.
	tone *= 1.0 + 0.08 * smoothstep(0.55, 0.8, big.g);
	tone *= 1.0 + grain_k * grain;
	float rough = 0.90;
	vec3 hue = vec3(1.0);

	// Road frame: lateral offset from the carriageway centreline.
	float d = mod(p.x + grid_period * 0.5, grid_period) - grid_period * 0.5;
	float e = mod(p.y + grid_period * 0.5, grid_period) - grid_period * 0.5;
	float on_z = step(abs(d), road_half + 0.4) * step(road_half + 0.4, abs(e));
	float on_x = step(abs(e), road_half + 0.4) * step(road_half + 0.4, abs(d));
	float lane = road_grid * max(on_z, on_x);
	float junction = road_grid * step(abs(d), road_half + 0.4) * step(abs(e), road_half + 0.4);
	float lat = on_z > 0.5 ? d : e;
	float along = on_z > 0.5 ? p.y : p.x;
	float al = abs(lat);
	vec2 rf = lane > 0.5 ? vec2(lat, along) : p;   // patch frame

	// Photographic surface detail: luminance ratio against the map mean, so
	// the tint and the lane-aware wear below keep the LOOK_DEV value. The
	// detail swing stays bounded (driving-q: no salt-and-pepper frosting).
	vec2 pq = rf / photo_tile;
	float ph1 = dot(texture(photo_tex, pq + vec2(0.0, floor(along / 61.0) * 0.37)).rgb, vec3(0.333));
	float ph2 = dot(texture(photo_tex, w_rot(p, 0.61) / (photo_tile * 1.61) + 0.29).rgb, vec3(0.333));
	float pmix = smoothstep(0.35, 0.65, w_mask(p / 23.0 + 0.17).g);
	float pl = mix(ph1, ph2, pmix * 0.6) / dot(photo_mean, vec3(0.333));
	tone *= mix(1.0, clamp(pow(pl, 0.85), 0.72, 1.38), photo_k);

	// Tyre tracks: polished, darker, smoother rubber lines in every lane.
	float tvar = 0.70 + 0.30 * w_mask(vec2(along / 41.0, lat / 13.0 + 0.3)).g;
	float tracks = 0.0;
	tracks += w_gauss(al - 1.15, 0.34);
	tracks += w_gauss(al - 2.85, 0.34);
	tracks += w_gauss(al - 5.15, 0.34);
	tracks += w_gauss(al - 6.85, 0.34);
	tracks = clamp(tracks, 0.0, 1.0) * tvar * lane * wear;
	tone *= 1.0 - 0.20 * tracks;
	rough = mix(rough, 0.76, tracks * 0.8);
	// Between the tracks the surface is dustier and lighter.
	float between = lane * (w_gauss(al - 2.0, 0.55) + w_gauss(al - 6.0, 0.55));
	tone *= 1.0 + 0.06 * between * (1.0 - tracks);

	// Oil drip line in each lane centre: blotchy dark, a little glossy.
	float oil = lane * (w_gauss(al - 2.0, 0.42) + w_gauss(al - 6.0, 0.42));
	oil *= smoothstep(0.50, 0.72, sml.r) * (0.6 + 0.4 * med.r);
	// Generic lots: scattered oil stains where cars park.
	float lot_oil = (1.0 - lane) * (1.0 - junction) * smoothstep(0.62, 0.80, w_mask(p / 9.0 + 0.13).r) * smoothstep(0.4, 0.7, sml.g);
	oil = clamp(oil + lot_oil, 0.0, 1.0) * wear;
	tone *= 1.0 - 0.22 * oil;
	rough -= 0.10 * oil;
	hue = mix(hue, vec3(0.92, 0.93, 1.02), oil * 0.5);

	// Gutter: dust band then a dark damp algae edge against the kerb.
	float gutter = lane * smoothstep(6.6, 7.9, al);
	tone = mix(tone, tone * 1.10 + 0.02, gutter * 0.45 * (0.6 + 0.4 * med.g));
	float wet = lane * smoothstep(7.55, 8.05, al) * (0.55 + 0.45 * big.g);
	tone *= 1.0 - 0.38 * wet;
	hue = mix(hue, vec3(0.90, 0.98, 0.86), wet * 0.6);
	rough -= 0.06 * wet;

	// Junction box: heavier general wear, braking polish.
	tone *= 1.0 - 0.10 * junction * smoothstep(0.35, 0.7, med.g);
	rough = mix(rough, 0.62, junction * 0.35 * med.r);

	// Patches: irregular hand-laid reinstatements. Noise-warped rounded
	// outline, soft blended edge, darker fresher binder, no painted seam.
	vec2 cell_size = lane > 0.5 ? vec2(4.0, 9.0) : vec2(5.0, 6.5);
	vec2 cid = floor(rf / cell_size);
	vec2 lc = fract(rf / cell_size) * cell_size;
	float h0 = w_hash12(cid + 17.0);
	float h1 = w_hash12(cid + 41.3);
	float h2 = w_hash12(cid + 73.9);
	vec2 pc = cell_size * vec2(0.35 + 0.3 * h1, 0.3 + 0.4 * h2);
	vec2 pr = vec2(0.6 + 0.9 * h2, 0.9 + 2.2 * h1);
	vec2 warp = vec2(vnoise(rf * 0.9 + h0 * 31.0), vnoise(rf * 0.9 + h1 * 17.0 + 4.0)) - 0.5;
	vec2 q = (lc - pc + warp * 0.9) / pr;
	float blob = length(q * q * q * q) * 0.5 + length(q) * 0.5;   // squircle-ish
	blob += (vnoise(rf * 3.1 + h2 * 9.0) - 0.5) * 0.35;
	float patch_on = step(h0, 0.22 * wear);
	float inside = (1.0 - smoothstep(0.82, 1.0, blob)) * patch_on;
	float fresh = 0.74 + 0.10 * h2;
	tone = mix(tone, tone * fresh, inside);
	rough = mix(rough, 0.82, inside * 0.6);

	// Utility trench reinstatement strip across the carriageway.
	float tc = floor(along / 37.0);
	float th = w_hash12(vec2(tc, 5.0) + floor(lat / 40.0));
	float tpos = 6.0 + w_hash12(vec2(tc, 9.0)) * 25.0;
	float tl = abs(mod(along, 37.0) - tpos + (vnoise(vec2(lat * 0.8, tc)) - 0.5) * 0.35);
	float trench = lane * step(th, 0.22 * wear) * (1.0 - smoothstep(0.36, 0.50, tl)) * step(al, road_half - 0.2);
	tone = mix(tone, tone * 0.80, trench);

	// Manhole / utility covers in lane centres.
	float mc = floor(along / 29.0);
	float mh = w_hash12(vec2(mc, floor(lat / 4.0)) + 3.7);
	float mpos = 8.0 + w_hash12(vec2(mc, 2.0)) * 13.0;
	vec2 mq = vec2(al - (mh < 0.11 ? 2.0 : 6.0), mod(along, 29.0) - mpos);
	float mr = length(mq);
	float cover = lane * step(mh, 0.22) * (1.0 - smoothstep(0.34, 0.36, mr));
	float cover_ring = lane * step(mh, 0.22) * w_gauss(mr - 0.37, 0.025);
	float grate = 0.85 + 0.15 * step(0.5, fract((mq.x + mq.y) * 9.0));
	tone = mix(tone, 0.42 * grate * (0.8 + 0.3 * sml.g), cover);
	rough = mix(rough, 0.62, cover);
	tone *= 1.0 - 0.6 * cover_ring;

	// Kerbside slot gratings every ~15 m between the double yellow lines and
	// the kerb face: concrete surround, cast-iron bars.
	float ga = mod(along + 3.0 * step(0.0, lat), 15.0) - 7.5;
	vec2 gq = vec2(al - 7.86, ga);
	float gsur = lane * (1.0 - smoothstep(0.125, 0.14, abs(gq.x))) * (1.0 - smoothstep(0.56, 0.60, abs(gq.y)));
	float gin = lane * (1.0 - smoothstep(0.085, 0.10, abs(gq.x))) * (1.0 - smoothstep(0.46, 0.48, abs(gq.y)));
	float bars = 0.35 + 0.65 * smoothstep(0.35, 0.6, abs(fract(gq.y / 0.07) - 0.5) * 2.0);
	tone = mix(tone, 1.7 * (0.85 + 0.3 * sml.g), (gsur - gin) * 0.85);
	tone = mix(tone, 0.16 * bars, gin);
	rough = mix(rough, 0.55, gin);

	// Cracks: regional alligator cracking plus longitudinal joint cracks.
	float region = smoothstep(0.48, 0.70, big.g * 0.7 + med.r * 0.5);
	float cr = w_mask(p / 14.0).b * region;
	cr = max(cr, w_mask(w_rot(p, 0.6) / 31.0 + 0.7).b * smoothstep(0.55, 0.75, big.r) * 0.8);
	float jl = abs(al - 4.0 + (med.r - 0.5) * 0.35);
	float joint = lane * (1.0 - smoothstep(0.012, 0.05, jl)) * step(0.48, w_mask(vec2(along / 53.0, 0.31)).g);
	float jl0 = abs(al + (med.b - 0.5) * 0.3);
	joint += lane * (1.0 - smoothstep(0.01, 0.045, jl0)) * step(0.55, w_mask(vec2(along / 47.0, 0.71)).g);
	cr = clamp(cr * wear + joint * wear, 0.0, 1.0) * (1.0 - cover);
	cr *= 1.0 - smoothstep(60.0, 160.0, dist) * 0.6;
	tone *= 1.0 - 0.62 * cr;
	rough += 0.08 * cr;
	// Weeds/grime seeping from cracks near the gutter (tropical).
	hue = mix(hue, vec3(0.86, 0.96, 0.80), cr * gutter * 0.6);

	ALBEDO = clamp(tint * tone * hue, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	// Fine aggregate relief only; the old 4 m normal tile carried broad
	// undulations that rippled the sky reflection ("navy and wavy" shade).
	vec3 n1 = texture(agg_nrm, p / 2.0).rgb;
	vec3 n2 = texture(agg_nrm, w_rot(p, 0.73) / 3.3 + 0.37).rgb;
	vec3 n3 = texture(photo_nrm, pq + vec2(0.0, floor(along / 61.0) * 0.37)).rgb;
	NORMAL_MAP = normalize(mix(mix(n1, n2, 0.42), n3, 0.5 * photo_k) * 2.0 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.9, 0.3, max(inside, cover)) * (1.0 - smoothstep(25.0, 90.0, dist) * 0.7);
	SPECULAR = 0.32;
}
