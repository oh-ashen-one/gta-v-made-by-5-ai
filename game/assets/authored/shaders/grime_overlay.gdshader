shader_type spatial;
// Multiply-pass grime for imported building modules (wave B "materials").
// Used as next_pass on their materials: darkens the lit result with base
// splash, rain streaks under the eaves, algae mottling and roof lichen.
render_mode blend_mul, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform float ground_y = 0.16;
uniform float strength = 1.0;
uniform float fade_near = 90.0;
uniform float fade_far = 420.0;

varying vec3 v_world;
varying vec3 v_wn;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Pull a few centimetres toward the eye so the pass never z-fights.
	VERTEX -= normalize(VERTEX) * 0.03;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(v_wn);
	float hz = n.x > n.z ? v_world.z : v_world.x;
	vec3 m = vec3(1.0);
	if (n.y > 0.6) {
		vec2 p = v_world.xz;
		float lichen = smoothstep(0.50, 0.80, w_mask(p / 11.0).g * 0.6 + w_mask(p / 41.0 + 0.3).r * 0.6);
		m *= mix(vec3(1.0), vec3(0.62, 0.64, 0.56), lichen * 0.8);
		m *= 0.86 + 0.20 * w_mask(p / 5.0 + 0.7).r;
	} else {
		float y0 = v_world.y - ground_y;
		float band = 1.0 - smoothstep(0.0, 1.3 + 1.2 * w_mask(vec2(hz / 6.0, 0.2)).g, y0);
		m *= mix(vec3(1.0), vec3(0.50, 0.55, 0.45), band * 0.85);
		float s = w_mask(vec2(hz / 4.5, v_world.y / 30.0)).a;
		float region = smoothstep(0.25, 0.62, w_mask(vec2(hz / 23.0, v_world.y / 47.0 + 0.3)).r);
		float streak = smoothstep(0.45, 0.80, s) * region;
		m *= mix(vec3(1.0), vec3(0.52, 0.55, 0.47), streak * 0.9);
		// Soot and damp under eaves and ledges: darker toward the wall top band.
		float eave = smoothstep(0.55, 0.9, w_mask(vec2(hz / 9.0, v_world.y / 3.2)).a) * 0.35;
		m *= mix(vec3(1.0), vec3(0.70, 0.70, 0.64), eave);
		float mott = smoothstep(0.52, 0.85, w_mask(vec2(hz, v_world.y) / 13.0 + 0.4).g);
		m *= mix(vec3(1.0), vec3(0.74, 0.78, 0.68), mott * 0.7);
	}
	float dist = length(VERTEX);
	float k = strength * (1.0 - smoothstep(fade_near, fade_far, dist) * 0.7);
	ALBEDO = mix(vec3(1.0), m, k);
}
