// Horizon skirt (skyline round 4, Opus 5.5). An open cylinder that follows the
// camera at ~96% of its far distance and reaches up to eye level, so the
// strip between the last visible land and the true horizon is hazy far land
// (the same colour the land fades into) instead of the sky shader's
// below-horizon band, which read as a flat grey sea strip behind the CBD
// (critic A3: "hard, flat sea-to-sky horizon line"). Land, towers and hills
// all fade to horizon_col before they reach it (skyline_haze.gdshaderinc).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled, world_vertex_coords;

uniform vec3 horizon_col : source_color = vec3(0.80, 0.83, 0.87);
uniform vec3 haze_col : source_color = vec3(0.60, 0.67, 0.77);
uniform float clip_frac = 0.955;

float cam_far(mat4 inv_proj) {
	vec4 a = inv_proj * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 b = inv_proj * vec4(0.0, 0.0, 1.0, 1.0);
	float za = abs(a.w) > 1e-6 ? abs(a.z / a.w) : 1e9;
	float zb = abs(b.w) > 1e-6 ? abs(b.z / b.w) : 1e9;
	return min(max(za, zb), 1e6);
}

varying float vy;

void vertex() {
	float r = cam_far(INV_PROJECTION_MATRIX) * clip_frac;
	vec3 c = CAMERA_POSITION_WORLD;
	// Unit cylinder: VERTEX.xz on the unit circle, VERTEX.y in 0..1.
	vy = VERTEX.y;
	VERTEX = vec3(c.x + VERTEX.x * r, mix(-40.0, max(c.y, 2.0), VERTEX.y), c.z + VERTEX.z * r);
}

void fragment() {
	// A touch of the cool haze at the foot so it meets the faded land.
	ALBEDO = mix(mix(haze_col, horizon_col, 0.75), horizon_col, smoothstep(0.6, 1.0, vy));
}
