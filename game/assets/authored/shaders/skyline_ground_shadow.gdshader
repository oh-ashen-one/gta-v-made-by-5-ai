// Ground cast shadows for the procedural background city (skyline round 3).
// The background towers are MultiMesh instances with cast_shadow off (and the
// sun's shadow map ends at 260 m), so the CBD across the bay stood on an
// evenly lit plaza with no cast shadows (critic A2). SkylineCity builds the
// shadow polygons on the CPU (footprint swept along the sun direction); this
// shader only darkens what is under them, hazing with the facade shader's
// aerial perspective so far shadows fade with their towers.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 shadow_col : source_color = vec3(0.10, 0.12, 0.17);
uniform float strength = 0.74;
// Match skyline_facade.gdshader.
uniform float haze_start = 200.0;
uniform float haze_density = 0.0018;
uniform float haze_max = 0.7;

void fragment() {
	float d = length(VERTEX);
	float hz = (1.0 - exp(-max(d - haze_start, 0.0) * haze_density)) * haze_max;
	ALBEDO = shadow_col;
	ALPHA = strength * (1.0 - hz);
	FOG = vec4(0.0);
}
