// Distant wooded ridges (skyline round 4, Opus 5.5). Low rainforest hills
// behind the hinterland give the horizon a land silhouette instead of an empty
// sea band behind the CBD (critic A3). Canopy texture from layered noise,
// darker in the valleys and on the shaded flanks, hazed with the shared
// aerial perspective so they sit as the farthest depth layer.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 haze_col : source_color = vec3(0.60, 0.67, 0.77);
uniform vec3 haze_sun_col : source_color = vec3(0.98, 0.86, 0.70);
uniform vec3 horizon_col : source_color = vec3(0.80, 0.83, 0.87);
uniform vec3 sun_dir = vec3(0.85, 0.28, 0.45);
uniform float haze_start = 150.0;
uniform float haze_density = 0.0022;
uniform float haze_max = 0.82;
uniform float horizon_start = 2600.0;
uniform float horizon_end = 5200.0;
uniform float far_full = 0.7;
uniform vec3 fog_col : source_color = vec3(0.70, 0.77, 0.86);
uniform float fog_density_ref = 0.00046;
uniform float fog_scale = 1.0;

varying vec3 wpos;
varying vec3 wnorm;
#include "res://assets/authored/shaders/skyline_haze.gdshaderinc"

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	float n = vnoise(p * 0.02) * 0.5 + vnoise(p * 0.07) * 0.3 + vnoise(p * 0.25) * 0.2;
	vec3 c = lin(mix(vec3(0.10, 0.19, 0.09), vec3(0.20, 0.30, 0.13), n));
	// Paler crowns on the ridge tops, darker gullies.
	c *= mix(0.75, 1.15, smoothstep(5.0, 70.0, wpos.y));
	// Scattered pale patches: quarries, clearings, a few low buildings.
	c = mix(c, lin(vec3(0.58, 0.55, 0.48)), step(0.86, vnoise(p * 0.013 + 4.0)) * 0.5);
	vec3 sdn = normalize(sun_dir);
	c *= mix(0.7, 1.05, smoothstep(-0.2, 0.5, dot(normalize(wnorm), sdn)));
	ALBEDO = c;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	FOG = skyline_haze_clip(wpos, CAMERA_POSITION_WORLD, far_full, -VERTEX.z, INV_PROJECTION_MATRIX);
}
