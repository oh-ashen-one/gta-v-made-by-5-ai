shader_type spatial;
// Weathered footway paving (wave B "materials"): tonal grime, damp algae
// patches, dark joints, gum spots and kerb-side dirt. World-space.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.62, 0.60, 0.56);
uniform float tile_m = 3.0;
uniform float base_rough = 0.9;
uniform float grid_period = 160.0;
uniform float road_half = 8.0;
uniform float wear = 1.0;

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
	base = mix(base, mean, 0.58);
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
	col *= 0.90 + 0.18 * sh;
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
	col = mix(col, col * vec3(0.45, 0.50, 0.40), joint * 0.6 * (0.5 + 0.5 * med.r));
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
	if (!top) {
		// Platform edge faces: splashback grime.
		col *= vec3(0.70, 0.72, 0.64);
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.35, 1.0);
	NORMAL_MAP = texture(normal_tex, p / tile_m).rgb;
	NORMAL_MAP_DEPTH = 0.45;
}
