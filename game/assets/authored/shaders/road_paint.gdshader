shader_type spatial;
// Worn road paint (wave B "materials"): scuffed, chipped and dirty markings
// that let the asphalt show through, broken by the same crack network.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform vec3 paint : source_color = vec3(0.85, 0.83, 0.72);
uniform vec3 under : source_color = vec3(0.16, 0.16, 0.17);
uniform float wear = 1.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float m1 = w_mask(p / 3.1).g;
	float m2 = w_mask(p / 0.83 + 0.3).r;
	float big = w_mask(p / 41.0 + 0.6).r;
	float worn = smoothstep(0.50, 0.64, m1 * 0.55 + m2 * 0.45 + (big - 0.5) * 0.45) * wear;
	float speck = step(0.80, w_mask(p * 1.7 + 0.11).g) * wear;
	vec3 col = paint * (0.74 + 0.22 * m2);
	col = mix(col, under * (0.8 + 0.4 * m2), clamp(worn * 0.9 + speck * 0.6, 0.0, 1.0));
	col *= 1.0 - 0.45 * w_mask(p / 14.0).b * smoothstep(0.48, 0.7, big);
	ALBEDO = col;
	ROUGHNESS = mix(0.62, 0.86, worn);
	SPECULAR = 0.5;
}
