// Tower cranes on the skyline (skyline round 4, Opus 5.5): plain painted steel
// hazed with the same aerial perspective as the towers around them.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 paint : source_color = vec3(0.80, 0.60, 0.20);
uniform vec3 haze_col : source_color = vec3(0.60, 0.67, 0.77);
uniform vec3 haze_sun_col : source_color = vec3(0.98, 0.86, 0.70);
uniform vec3 horizon_col : source_color = vec3(0.80, 0.83, 0.87);
uniform vec3 sun_dir = vec3(0.85, 0.28, 0.45);
uniform float haze_start = 150.0;
uniform float haze_density = 0.0022;
uniform float haze_max = 0.82;
uniform float horizon_start = 1700.0;
uniform float horizon_end = 3600.0;
uniform float far_full = 0.55;
uniform vec3 fog_col : source_color = vec3(0.70, 0.77, 0.86);
uniform float fog_density_ref = 0.00046;
uniform float fog_scale = 1.0;

varying vec3 wpos;
#include "res://assets/authored/shaders/skyline_haze.gdshaderinc"

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = paint;
	ROUGHNESS = 0.65;
	FOG = skyline_haze_clip(wpos, CAMERA_POSITION_WORLD, far_full, -VERTEX.z, INV_PROJECTION_MATRIX);
}
