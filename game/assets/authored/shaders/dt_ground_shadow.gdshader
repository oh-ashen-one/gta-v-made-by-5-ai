// Downtown tower ground shadows (downtown-polish, wave S, Opus 5.5). Original work.
// The sun's shadow map ends 280 m from the camera, so from the helicopter and
// across the bay the downtown towers stood on evenly lit ground. The CPU
// sweeps each tower footprint along the sun direction (tower_shadows.gd); this
// only darkens what lies under it, starting where the real shadow map ends
// (so near the camera only real shadows draw) and hazing out with distance
// like the skyline's ground shadows.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform vec3 shadow_col : source_color = vec3(0.09, 0.11, 0.16);
uniform float strength = 0.62;
uniform float near_start = 210.0;
uniform float near_end = 300.0;
uniform float haze_start = 450.0;
uniform float haze_density = 0.0016;
uniform float haze_max = 0.75;

void fragment() {
	float d = length(VERTEX);
	float hz = (1.0 - exp(-max(d - haze_start, 0.0) * haze_density)) * haze_max;
	ALBEDO = shadow_col;
	ALPHA = strength * (1.0 - hz) * smoothstep(near_start, near_end, d);
}
