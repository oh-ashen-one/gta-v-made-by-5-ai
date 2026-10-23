shader_type spatial;
// Weathered footway paving (wave B "materials"): tonal grime, damp algae
// patches, dark joints, gum spots and kerb-side dirt. World-space.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"
#include "res://assets/authored/shaders/leaf_litter.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.62, 0.60, 0.56);
uniform float tile_m = 3.0;
uniform float base_rough = 0.9;
uniform float grid_period = 160.0;
uniform float road_half = 8.0;
uniform float wear = 1.0;
// nearfield R: value lift toward the LOOK_DEV pale-concrete footway (the
// stacked grime/damp/zone factors left pavements near-black in shade).
uniform float lift = 1.0;
uniform float sat = 1.0;   // < 1 pulls the warm tint toward neutral concrete grey
uniform float fittings = 0.0;   // nearfield R: inspection covers + tactile strips in the footway band
uniform float litter = 0.0;     // nearfield R: fallen leaf density (0 = off)

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool top = abs(v_wn.y) > 0.5;
	vec2 p = top ? v_world.xz : vec2(v_world.x + v_world.z, v_world.y);
	vec3 base = texture(albedo_tex, p / tile_m).rgb;
	float lum = dot(base, vec3(0.333));
	// Pull individual stones toward the sheet mean: weathering evens them out.
	vec3 mean = textureLod(albedo_tex, p / tile_m, 9.0).rgb;
	base = mix(base, mean, 0.50);
	vec4 big = w_mask(p / 61.0);
	vec4 med = w_mask(w_rot(p, 0.9) / 13.0 + 0.4);
	vec4 sml = w_mask(p / 3.7 + 0.2);
	vec3 col = tint * base;
	float rough = base_rough * texture(rough_tex, p / tile_m).r / 0.85;
	// Broad tonal breakup kills the repeat of the paver sheet; the widest
	// octave keeps whole plazas from reading as one colour from the air.
	col *= 0.80 + 0.36 * big.r;
	col *= 0.74 + 0.46 * w_mask(p / 157.0 + 0.27).g;
	// Big dirty / damp zones that survive mip filtering at grazing angles.
	float zone = smoothstep(0.52, 0.74, w_mask(p / 47.0 + 0.53).r);
	col = mix(col, col * vec3(0.70, 0.70, 0.62), zone * 0.8 * wear);
	// Individual slabs: some replaced (cleaner), some sunk and darker.
	float srow = floor(p.y / tile_m * 8.0);
	vec2 sid = vec2(floor((p.x / tile_m * 1024.0 + mod(srow, 2.0) * 128.0) / 256.0), srow);
	float sh = w_hash12(sid + 7.7);
	col *= 0.82 + 0.34 * sh;
	// nearfield R2: unit-by-unit character. Slab-local coords (0..1).
	vec2 su = vec2(fract((p.x / tile_m * 1024.0 + mod(srow, 2.0) * 128.0) / 256.0), fract(p.y / tile_m * 8.0));
	float sh2 = w_hash12(sid + 21.3);
	float sh3 = w_hash12(sid + 37.9);
	// warm/cool batch cast
	col *= mix(vec3(1.04, 1.0, 0.94), vec3(0.96, 0.99, 1.03), sh2);
	// stained slabs: spreading dark blot from one corner
	float sstain = step(0.86, sh3) * (1.0 - smoothstep(0.2, 0.9, length((su - vec2(sh2, sh)) * vec2(2.0, 1.0))));
	col = mix(col, col * vec3(0.58, 0.55, 0.48), sstain * wear);
	// sunken / rocking slabs: darker, dirty, with a shadowed high edge
	float sunk = step(sh3, 0.10) * wear;
	float sedge = sunk * (1.0 - smoothstep(0.0, 0.12, sh2 < 0.5 ? su.y : 1.0 - su.y));
	col *= 1.0 - 0.18 * sunk - 0.35 * sedge;
	// cracked slabs: one jagged crack across the unit
	float crk_on = step(0.10, sh3) * step(sh3, 0.17);
	float cxs = su.x * 11.0;
	float cj = mix(w_hash12(vec2(floor(cxs), sh * 97.0)), w_hash12(vec2(floor(cxs) + 1.0, sh * 97.0)), fract(cxs)) - 0.5;
	float cy = su.y - (0.3 + 0.4 * sh2) - (su.x - 0.5) * (sh - 0.5) * 1.2 - 0.07 * cj;
	float crk = crk_on * (1.0 - smoothstep(0.012, 0.04, abs(cy)));
	col *= 1.0 - 0.55 * crk * wear;
	// chipped arrises: dark at slab corners
	vec2 sc = min(su, 1.0 - su) * vec2(4.0, 2.0);
	col *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.10, min(sc.x, sc.y))) * step(0.5, sh2 + 0.3 * sh3);
	col *= 0.90 + 0.20 * med.g;
	// Traffic-worn grime blotches (warm grey-brown).
	float grime = smoothstep(0.50, 0.78, med.g * 0.65 + big.g * 0.55) * wear;
	col = mix(col, col * vec3(0.64, 0.61, 0.54), grime * 0.9);
	// Damp algae patches: humid tropical staining, slightly glossier.
	float damp = smoothstep(0.60, 0.84, big.r * 0.7 + sml.g * 0.45) * wear;
	col = mix(col, col * vec3(0.50, 0.58, 0.46), damp * 0.85);
	rough -= 0.18 * damp;
	// Joints hold dirt and moss.
	float joint = 1.0 - smoothstep(0.20, 0.42, lum);
	col = mix(col, col * vec3(0.55, 0.58, 0.48), joint * 0.45 * (0.5 + 0.5 * med.r));
	// Gum spots and drip stains.
	vec2 gc = floor(p * 1.6);
	float gh = w_hash12(gc + 5.1);
	vec2 gp = fract(p * 1.6) - vec2(w_hash12(gc + 1.7), w_hash12(gc + 9.3)) * 0.6 - 0.2;
	float gum = step(gh, 0.05 * wear) * (1.0 - smoothstep(0.035, 0.07 + 0.05 * gh * 20.0 * 0.05, length(gp)));
	col *= 1.0 - 0.45 * gum;
	// Larger dark stains (spilt drinks, hawker run-off).
	float stain = smoothstep(0.70, 0.86, w_mask(p / 7.3 + 0.61).r) * smoothstep(0.45, 0.6, med.r) * wear;
	col *= 1.0 - 0.32 * stain;
	rough -= 0.12 * stain;
	// Kerb-side dirt and leaf litter where footway meets the carriageway.
	float d = mod(v_world.x + grid_period * 0.5, grid_period) - grid_period * 0.5;
	float e = mod(v_world.z + grid_period * 0.5, grid_period) - grid_period * 0.5;
	float kd = min(abs(d), abs(e));
	float kerb = smoothstep(road_half + 2.6, road_half + 0.3, kd) * step(road_half + 0.25, kd) * wear;
	col = mix(col, col * vec3(0.66, 0.64, 0.56), kerb * (0.55 + 0.45 * sml.r));
	// Hairline cracking in a few areas.
	float cr = w_mask(p / 9.0 + 0.33).b * smoothstep(0.55, 0.75, big.g) * wear;
	col *= 1.0 - 0.4 * cr;
	// nearfield R: footway fittings in the band behind the kerb. Cast-iron
	// inspection covers (frame + raised diamond tread) every few slabs, and
	// yellow blister tactile strips at the block corners where people cross.
	float metal_k = 0.0;
	if (top && fittings > 0.5) {
		bool on_x = abs(d) < abs(e);
		float along_f = on_x ? v_world.z : v_world.x;
		float side_f = on_x ? sign(d) : sign(e);
		float other = on_x ? abs(e) : abs(d);
		float band = step(road_half + 0.3, kd) * step(kd, road_half + 2.6);
		float cid = floor(along_f / 8.5);
		float ch = w_hash12(vec2(cid, side_f * 7.0 + 3.0));
		vec2 cq = vec2(along_f - (cid * 8.5 + 1.5 + ch * 5.5), kd - (road_half + 1.3 + ch * 0.9));
		float cov = band * step(0.45, ch) * step(abs(cq.x), 0.32) * step(abs(cq.y), 0.32) * step(road_half + 6.0, other);
		float frame_ring = cov * (1.0 - step(abs(cq.x), 0.27) * step(abs(cq.y), 0.27));
		vec2 dq = fract(w_rot(cq, 0.785) * 18.0) - 0.5;
		float tread = step(abs(dq.x) + abs(dq.y), 0.32);
		vec3 iron = vec3(0.16, 0.155, 0.15) * (0.85 + 0.3 * tread) * (0.9 + 0.2 * med.g);
		col = mix(col, mix(iron, vec3(0.30, 0.29, 0.27), frame_ring), cov);
		rough = mix(rough, 0.55 + 0.2 * tread, cov);
		metal_k = cov * 0.6;
		// tactile strip: 0.6 m deep across the crossing approach at each corner
		float corner = step(road_half + 0.35, other) * step(other, road_half + 0.95) * band * step(kd, road_half + 2.3);
		vec2 bq = fract(vec2(along_f, kd) / 0.075) - 0.5;
		float blister = 1.0 - smoothstep(0.18, 0.26, length(bq));
		vec3 tactile = vec3(0.78, 0.60, 0.10) * (0.82 + 0.25 * blister) * (0.85 + 0.15 * med.r);
		col = mix(col, tactile, corner);
		rough = mix(rough, 0.7, corner);
	}
	if (top && litter > 0.0) {
		float lpx = max(length(fwidth(v_world.xz)), 1e-4);
		// denser in drifts and along the kerb band, under the avenue trees
		float drift = smoothstep(0.45, 0.75, w_mask(v_world.xz / 9.0 + 0.41).g);
		vec4 lf = leaf_litter(v_world.xz, litter * (0.35 + 0.9 * drift + 0.6 * kerb), lpx);
		col = mix(col, lf.rgb / max(lift, 1e-3), lf.a * (1.0 - metal_k));
		rough = mix(rough, 0.8, lf.a);
	}
	if (!top) {
		// Platform edge faces: splashback grime.
		col *= vec3(0.70, 0.72, 0.64);
	}
	col = mix(vec3(dot(col, vec3(0.333))), col, sat);
	ALBEDO = clamp(col * lift, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.35, 1.0);
	// nearfield R2: each slab sits at its own slight tilt, so the raking sun
	// picks units out one by one (uneven, height-varied paving).
	vec3 nm = texture(normal_tex, p / tile_m).rgb * 2.0 - 1.0;
	nm.xy += (vec2(sh2, sh3) - 0.5) * 0.40 + vec2(0.0, sunk * 0.5);
	NORMAL_MAP = normalize(nm) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.32;
	METALLIC = metal_k;
}
