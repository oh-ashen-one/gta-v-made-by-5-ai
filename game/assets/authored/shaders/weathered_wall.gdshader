shader_type spatial;
// Weathered concrete / render (wave B "materials"): base splash grime, rain
// streaks, algae mottling, optional peeling paint and stained roof decks.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.55, 0.54, 0.51);
uniform float tile_m = 4.0;
uniform float base_rough = 0.9;
uniform float metal = 0.0;
uniform float ground_y = 0.16;
uniform float peel = 0.0;
uniform float streaks = 1.0;
uniform float wear = 1.0;
uniform float slabs = 1.0;     // 6 m cast-slab joints on horizontal tops (concrete only)

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(v_wn);
	bool top = n.y > 0.5;
	// Wall tangent coordinate: continuous around box corners.
	float hz = n.x > n.z ? v_world.z : v_world.x;
	vec2 p = top ? v_world.xz : vec2(hz, v_world.y);
	vec3 base = texture(albedo_tex, p / tile_m).rgb;
	vec3 col = tint * base / 0.8;
	float rough = base_rough;
	vec4 big = w_mask(p / 29.0 + 0.17);
	vec4 med = w_mask(w_rot(p, 0.4) / 7.0);
	col *= 0.84 + 0.30 * big.r;
	if (top) {
		// Large-scale tone so wide aprons and roofs never read as one flat colour.
		vec4 huge = w_mask(p / 113.0 + 0.41);
		col *= 0.80 + 0.40 * huge.r;
		// Cast slabs on a 6 m grid: per-slab tone and sealed joints.
		vec2 slab = floor(p / 6.0);
		col *= 1.0 + slabs * (0.16 * w_hash12(slab + 3.3) - 0.08);
		vec2 jd = abs(fract(p / 6.0 + 0.5) - 0.5) * 6.0;
		float jdist = min(jd.x, jd.y);
		float fw = max(fwidth(jdist), 1e-4);
		float joint = (1.0 - smoothstep(0.03, 0.03 + fw, jdist)) * clamp(0.08 / fw, 0.0, 1.0) * slabs;
		col *= 1.0 - 0.45 * joint;
		// Rust / oil stains and tyre scuffs.
		float stain = smoothstep(0.66, 0.82, w_mask(p / 17.0 + 0.77).r) * wear;
		col = mix(col, col * vec3(0.62, 0.55, 0.48), stain * 0.7);
		// Roof decks and slab tops: ponding rings, lichen and soot.
		float pond = smoothstep(0.62, 0.80, big.r) * wear;
		col = mix(col, col * vec3(0.58, 0.60, 0.52), pond * 0.8);
		float lichen = smoothstep(0.58, 0.80, med.g * 0.7 + big.g * 0.5) * wear;
		col = mix(col, col * vec3(0.62, 0.64, 0.54), lichen * 0.6);
		rough -= 0.12 * pond;
	} else {
		float y0 = v_world.y - ground_y;
		// Splashback and algae at the wall base.
		float band = 1.0 - smoothstep(0.0, 0.9 + 0.8 * med.g, y0);
		col = mix(col, col * vec3(0.52, 0.56, 0.46), band * 0.8 * wear);
		// Rain streaks: long vertical runs, stronger in damp regions.
		float s = w_mask(vec2(hz / 7.0, v_world.y / 55.0)).a;
		float region = smoothstep(0.30, 0.70, w_mask(vec2(hz / 37.0, v_world.y / 71.0 + 0.3)).r);
		float streak = smoothstep(0.50, 0.80, s) * region * streaks * wear;
		col = mix(col, col * vec3(0.60, 0.62, 0.55), streak * 0.75);
		// Algae mottling, darker green-grey.
		float mott = smoothstep(0.55, 0.85, big.g * 0.6 + med.r * 0.5) * wear;
		col = mix(col, col * vec3(0.70, 0.75, 0.64), mott * 0.6);
		// Peeling paint: lighter exposed cement with a dark lifted rim.
		if (peel > 0.0) {
			float pm = w_mask(p / 3.1 + 0.5).g * 0.75 + big.r * 0.4;
			float flake = smoothstep(0.735, 0.745, pm) * peel;
			float rim = (smoothstep(0.70, 0.735, pm) - smoothstep(0.735, 0.75, pm)) * peel;
			col = mix(col, vec3(0.60, 0.58, 0.53) * (0.85 + 0.2 * med.g), flake);
			col *= 1.0 - 0.35 * rim;
		}
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	METALLIC = metal;
	NORMAL_MAP = texture(normal_tex, p / tile_m).rgb;
	NORMAL_MAP_DEPTH = 0.3;
}
