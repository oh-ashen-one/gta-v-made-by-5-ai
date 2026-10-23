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
// Integrator (wave S): a decal, not a floating sheet. The overlay sits at
// y 0.27; it only darkens where the opaque scene surface under the pixel is
// ground near that height (roads 0.06, land 0.16, walks/decks 0.3-0.36). Over
// the bay/river (water -0.9, seabed lower) and through gaps it drew flat dark
// planes that made the MBFC/Marina South podiums read as floating slabs
// (critic downtown-polish-S1: photo_29, dtx_heli_bayfront).
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float ground_tol = 0.5;

varying float sheet_y;

void vertex() {
	sheet_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float d = length(VERTEX);
	float hz = (1.0 - exp(-max(d - haze_start, 0.0) * haze_density)) * haze_max;
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float scene_y = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).y;
	float on_ground = 1.0 - smoothstep(ground_tol, ground_tol + 0.3, abs(scene_y - sheet_y));
	ALBEDO = shadow_col;
	ALPHA = strength * (1.0 - hz) * smoothstep(near_start, near_end, d) * on_ground;
}
