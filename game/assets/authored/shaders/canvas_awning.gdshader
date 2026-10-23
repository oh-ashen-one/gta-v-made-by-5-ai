shader_type spatial;
// Shopfront canvas awning (nearfield, opus55 wave R). Replaces the flat
// single-colour slab (critic: "a flat mauve awning plane"). Mesh from
// NearField.canvas_awning: UV.x = metres across the shopfront, UV.y = 0 at
// the wall to 1 at the front bar, 1..1.3 down the valance. Two-tone stripes
// (shop colour and cream), canvas weave, sun-bleached crown, rain-dirt
// streaks toward the drip edge, a scalloped valance hem (alpha cut) and a
// little translucency where the low sun comes through the cloth.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Per awning (merged per 160 m cell): COLOR.rgb = stripe colour, COLOR.a = 1
// for a plain single-colour canvas.
uniform vec3 cream : source_color = vec3(0.86, 0.82, 0.72);
uniform float stripe_w = 0.32;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 x) {
	vec2 i = floor(x); vec2 f = fract(x); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	// scalloped hem on the valance
	float hem = 1.27 - 0.045 * abs(sin(u * PI / 0.30));
	ALPHA = v > hem ? 0.0 : 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float fw = max(fwidth(u), 1e-4);
	float sw = sin(PI * u / stripe_w);
	float s = mix(smoothstep(-1.0, 1.0, sw / max(fw * PI / stripe_w * 1.5, 1e-4)), 1.0, COLOR.a);
	vec3 col = mix(cream, pow(COLOR.rgb, vec3(2.2)), s);   // vertex colour is sRGB
	// weave and slight unevenness of the dye
	float weave = 0.94 + 0.06 * vn(vec2(u * 140.0, v * 140.0)) + 0.04 * (vn(vec2(u * 3.0, v * 4.0)) - 0.5);
	col *= weave;
	// sun-bleached crown (top face, toward the wall) and rain-dirt streaks
	float bleach = smoothstep(0.9, 0.2, v) * 0.18;
	col = mix(col, vec3(dot(col, vec3(0.333))) * 1.08, bleach);
	float streak = smoothstep(0.55, 0.85, vn(vec2(u * 6.0, 0.5))) * smoothstep(0.5, 1.2, v);
	col *= 1.0 - 0.22 * streak;
	// darker, damp hem
	col *= 1.0 - 0.15 * smoothstep(1.15, 1.27, v);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	BACKLIGHT = col * 0.35;
}
