shader_type spatial;
// Falling water jet (Merlion spout). UV.y runs from the mouth (0) to the
// splash (1); UV.x wraps around the stream. Streaks scroll along the flow,
// the core stays glassy and see-through, the rim and the lower, aerated end
// turn white and break up into separate ropes before reaching the bay.
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 water_tint : source_color = vec3(0.78, 0.88, 0.90);
uniform vec3 foam_tint : source_color = vec3(0.90, 0.93, 0.94);
uniform float flow_speed = 1.6;
uniform float opacity = 0.85;

varying float v_along;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_along = UV.y;
	// slight wobble that grows downstream, as a real spout flutters
	float w = sin(TIME * 7.0 + UV.y * 23.0) * 0.06 + sin(TIME * 11.0 + UV.y * 41.0 + UV.x * 6.283) * 0.04;
	VERTEX += NORMAL * w * UV.y * 1.6;
}

void fragment() {
	float along = v_along;
	float around = UV.x;
	float flow = along * 9.0 - TIME * flow_speed;
	// lengthwise streaks: stretched noise in (around, flow)
	float s1 = vnoise(vec2(around * 26.0, flow * 1.2));
	float s2 = vnoise(vec2(around * 61.0 + 3.0, flow * 2.7));
	float streak = s1 * 0.65 + s2 * 0.35;
	// break into ropes and droplets toward the end
	float rope = smoothstep(0.30 + along * 0.32, 0.62 + along * 0.18, streak);
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	float aerated = smoothstep(0.15, 0.95, along);
	float a = mix(0.62 + rim * 0.35, 0.35 + rope * 0.65, aerated * 0.8);
	a *= smoothstep(0.0, 0.03, along) * (1.0 - smoothstep(0.93, 1.0, along));
	a = clamp(a * opacity, 0.0, 1.0);
	// refraction of whatever is behind the glassy core
	vec2 off = (NORMAL.xy) * 0.012 * (1.0 - aerated);
	vec3 behind = textureLod(screen_tex, SCREEN_UV + off, 1.0).rgb;
	float foamy = clamp(0.30 + rim * 0.5 + aerated * 0.7 + streak * 0.3, 0.0, 1.0);
	ALBEDO = foam_tint * foamy + water_tint * 0.12 * (1.0 - foamy);
	EMISSION = behind * water_tint * (1.0 - foamy) * 0.9;
	ROUGHNESS = 0.18 + aerated * 0.5;
	SPECULAR = 0.5;
	ALPHA = a;
}
