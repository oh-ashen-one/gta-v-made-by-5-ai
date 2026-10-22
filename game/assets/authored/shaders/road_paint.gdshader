shader_type spatial;
// Road paint (wave B "materials", r2): crisp, well-kept LTA-style markings.
// Wear reads as fading, grain and grime, never as black blotches: the paint
// keeps >85% coverage and only thins to a greyed tone in scuffed areas.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform vec3 paint : source_color = vec3(0.85, 0.83, 0.72);
uniform vec3 under : source_color = vec3(0.16, 0.16, 0.17);
uniform float wear = 1.0;

varying vec3 v_world;
varying vec3 v_local;
uniform float unit_box = 1.0;   // markings are unit boxes scaled per instance

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX;
}

float vn(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(w_hash12(i), w_hash12(i + vec2(1, 0)), u.x), mix(w_hash12(i + vec2(0, 1)), w_hash12(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 p = v_world.xz;
	float px = max(length(fwidth(p)), 1e-4);
	float m1 = w_mask(p / 3.1).g;
	float m2 = w_mask(p / 0.83 + 0.3).r;
	float big = w_mask(p / 41.0 + 0.6).r;
	// Scuffed (thinned) areas: small share, and only partly toward the asphalt.
	float worn = smoothstep(0.60, 0.78, m1 * 0.55 + m2 * 0.45 + (big - 0.5) * 0.3) * wear;
	// Fine grain: asphalt texture showing through a thin coat, footprint-faded.
	float g1 = vn(p * 40.0) - 0.5;
	float g2 = vn(p * 12.0 + 3.0) - 0.5;
	float gw = 1.0 - smoothstep(0.008, 0.024, px);
	float gw2 = 1.0 - smoothstep(0.025, 0.07, px);
	vec3 col = paint * (0.86 + 0.12 * m2);
	col = mix(col, mix(col, under, 0.45), worn * 0.75);
	col *= 1.0 + (0.22 * g1 * gw + 0.16 * g2 * gw2) * wear;
	// Tyre grime across the paint, faint.
	col *= 1.0 - 0.14 * smoothstep(0.55, 0.8, w_mask(p / 7.0 + 0.2).g) * wear;
	col *= COLOR.rgb;   // per-instance colour (yellow boxes); white otherwise
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	// Nearfield (opus55 D): analytic edge coverage. The 12 cm lines were hard
	// geometry edges that stair-stepped into a zipper at 2x MSAA (critic B3).
	// The unit box's top face fades over ~1 px at each edge instead.
	if (unit_box > 0.5) {
		vec2 e = 0.5 - abs(v_local.xz);
		vec2 fl = max(fwidth(v_local.xz), vec2(1e-5));
		vec2 cov = clamp(e / fl * 0.85 + 0.15, 0.0, 1.0);
		ALPHA = cov.x * cov.y * step(0.45, v_local.y);
	}
	ROUGHNESS = mix(0.58, 0.78, worn);
	SPECULAR = 0.5;
}
