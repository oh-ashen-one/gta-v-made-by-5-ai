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

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float rect_mask(vec2 lc, vec2 lo, vec2 hi, float soft) {
	vec2 a = smoothstep(lo - soft, lo + soft, lc) * (1.0 - smoothstep(hi - soft, hi + soft, lc));
	return a.x * a.y;
}

void fragment() {
	vec2 p = v_world.xz;
	float dist = length(VERTEX);
	vec3 agg = texture(albedo_tex, p / tile_m).rgb;
	vec3 agg2 = texture(albedo_tex, w_rot(p, 0.73) / (tile_m * 2.7) + 0.37).rgb;
	float a = mix(agg.r, agg2.r, 0.45);
	vec4 big = w_mask(p / 97.0);
	vec4 med = w_mask(w_rot(p, 1.1) / 23.0 + 0.21);
	vec4 sml = w_mask(p / 6.3 + 0.5);
	float tone = a * (0.70 + 0.60 * big.r) * (0.84 + 0.32 * med.g);
	// Sun-bleached, oxidised areas read lighter and greyer.
	tone *= 1.0 + 0.18 * smoothstep(0.55, 0.8, big.g);
	float rough = 0.88;
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

	// Tyre tracks: polished, darker, smoother rubber lines in every lane.
	float tvar = 0.55 + 0.45 * w_mask(vec2(along / 41.0, lat / 13.0 + 0.3)).g;
	float tracks = 0.0;
	tracks += w_gauss(al - 1.15, 0.34);
	tracks += w_gauss(al - 2.85, 0.34);
	tracks += w_gauss(al - 5.15, 0.34);
	tracks += w_gauss(al - 6.85, 0.34);
	tracks = clamp(tracks, 0.0, 1.0) * tvar * lane * wear;
	tone *= 1.0 - 0.40 * tracks;
	rough = mix(rough, 0.52, tracks * 0.85);
	// Between the tracks the surface is dustier and lighter.
	float between = lane * (w_gauss(al - 2.0, 0.55) + w_gauss(al - 6.0, 0.55));
	tone *= 1.0 + 0.14 * between * (1.0 - tracks);

	// Oil drip line in each lane centre: blotchy dark, a little glossy.
	float oil = lane * (w_gauss(al - 2.0, 0.42) + w_gauss(al - 6.0, 0.42));
	oil *= smoothstep(0.50, 0.72, sml.r) * (0.6 + 0.4 * med.r);
	// Generic lots: scattered oil stains where cars park.
	float lot_oil = (1.0 - lane) * (1.0 - junction) * smoothstep(0.62, 0.80, w_mask(p / 9.0 + 0.13).r) * smoothstep(0.4, 0.7, sml.g);
	oil = clamp(oil + lot_oil, 0.0, 1.0) * wear;
	tone *= 1.0 - 0.42 * oil;
	rough -= 0.30 * oil;
	hue = mix(hue, vec3(0.92, 0.93, 1.02), oil * 0.5);

	// Gutter: dust band then a dark damp algae edge against the kerb.
	float gutter = lane * smoothstep(6.6, 7.9, al);
	tone = mix(tone, tone * 1.22 + 0.04, gutter * 0.55 * (0.6 + 0.4 * med.g));
	float wet = lane * smoothstep(7.55, 8.05, al) * (0.55 + 0.45 * big.g);
	tone *= 1.0 - 0.38 * wet;
	hue = mix(hue, vec3(0.90, 0.98, 0.86), wet * 0.6);
	rough -= 0.15 * wet;

	// Junction box: heavier general wear, braking polish.
	tone *= 1.0 - 0.10 * junction * smoothstep(0.35, 0.7, med.g);
	rough = mix(rough, 0.62, junction * 0.35 * med.r);

	// Patches: rectangular reinstatements with a sealed bitumen seam.
	vec2 cell_size = lane > 0.5 ? vec2(4.0, 9.0) : vec2(5.0, 6.5);
	vec2 cid = floor(rf / cell_size);
	vec2 lc = fract(rf / cell_size) * cell_size;
	float h0 = w_hash12(cid + 17.0);
	float h1 = w_hash12(cid + 41.3);
	float h2 = w_hash12(cid + 73.9);
	vec2 lo = vec2(0.25 + h1 * 1.2, 0.4 + h2 * 3.0);
	vec2 hi = lo + vec2(1.4 + h2 * (cell_size.x - 2.0 - lo.x), 1.2 + h1 * (cell_size.y - 1.8 - lo.y));
	hi = min(hi, cell_size - 0.2);
	float patch_on = step(h0, 0.28 * wear);
	float inside = rect_mask(lc, lo, hi, 0.015) * patch_on;
	float ring = (rect_mask(lc, lo - 0.07, hi + 0.07, 0.02) - rect_mask(lc, lo + 0.03, hi - 0.03, 0.02)) * patch_on;
	float fresh = 0.50 + 0.28 * h2;
	tone = mix(tone, (0.50 + 0.40 * agg2.r) * fresh * (0.9 + 0.2 * med.g), inside);
	rough = mix(rough, 0.80, inside);
	tone *= 1.0 - 0.55 * clamp(ring, 0.0, 1.0);
	rough = mix(rough, 0.45, clamp(ring, 0.0, 1.0) * 0.7);

	// Utility trench reinstatement strip across the carriageway.
	float tc = floor(along / 37.0);
	float th = w_hash12(vec2(tc, 5.0) + floor(lat / 40.0));
	float tpos = 6.0 + w_hash12(vec2(tc, 9.0)) * 25.0;
	float tl = abs(mod(along, 37.0) - tpos);
	float trench = lane * step(th, 0.30 * wear) * (1.0 - smoothstep(0.42, 0.47, tl)) * step(al, road_half - 0.2);
	float trench_seam = lane * step(th, 0.30 * wear) * w_gauss(tl - 0.47, 0.035) * step(al, road_half - 0.2);
	tone = mix(tone, (0.50 + 0.40 * agg.r) * 0.72, trench);
	tone *= 1.0 - 0.5 * trench_seam;

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
	rough = mix(rough, 0.45, cover);
	tone *= 1.0 - 0.6 * cover_ring;

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
	NORMAL_MAP = texture(normal_tex, p / tile_m).rgb;
	NORMAL_MAP_DEPTH = mix(0.35, 0.12, max(inside, cover));
	SPECULAR = 0.5;
}
