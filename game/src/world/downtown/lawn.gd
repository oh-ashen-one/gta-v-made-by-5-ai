class_name DowntownLawn
extends RefCounted
## downtown-fill (wave T): one shared, procedural lawn material for every
## downtown turf surface (map park slabs, shoreline beds, road medians, block
## forecourt beds, the Gardens site). Original work, no texture files.
##
## Critic gap (wave S): "from ~110 m the land between the water and the
## skyline reads as a scale model - flat evenly coloured lawn". Real tropical
## park turf is never one tone: mowing stripes catch the low sun, worn desire
## lines and dry, sun-bleached patches break it up at 10-60 m scale, and
## clover / moss mottling breaks it up at 1-3 m. Everything is world-space so
## adjoining surfaces line up, and the stripes change direction per 90 m
## tile (no parade-ground pattern across the map).
## `--fill-off` restores the old flat tinted soil turf for A/B.

static var _mat: Material = null

const SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec3 lush : source_color = vec3(0.17, 0.29, 0.09);
uniform vec3 deep : source_color = vec3(0.10, 0.19, 0.06);
uniform vec3 dry : source_color = vec3(0.37, 0.37, 0.17);
uniform vec3 worn : source_color = vec3(0.33, 0.28, 0.19);
varying vec3 wp;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int k = 0; k < 4; k++) { s += a * vn(p); p = p * 2.03 + vec2(17.1, 3.7); a *= 0.5; }
	return s;
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	float dist = length(wp - CAMERA_POSITION_WORLD);
	// macro: lush / deep / sun-dried regions (40-120 m)
	float m1 = fbm(p / 70.0);
	float m2 = fbm(p / 23.0 + 7.3);
	vec3 col = mix(deep, lush, smoothstep(0.30, 0.62, m1));
	col = mix(col, dry, smoothstep(0.58, 0.80, m2) * 0.75);
	// worn patches / desire lines
	float w = fbm(p / 9.0 + 31.0);
	col = mix(col, worn, smoothstep(0.70, 0.86, w) * 0.55);
	// mowing stripes: 4.5 m bands, direction per 90 m tile
	vec2 tile = floor(p / 90.0);
	float ang = h2(tile) > 0.5 ? 0.0 : 1.5708;
	ang += (h2(tile + 3.1) - 0.5) * 0.5;
	vec2 dir = vec2(cos(ang), sin(ang));
	float band = sin(dot(p, dir) * 3.14159 / 4.5);
	float stripe = smoothstep(-0.25, 0.25, band) * 2.0 - 1.0;
	float stripe_fade = 1.0 - smoothstep(0.55, 0.85, w);
	col *= 1.0 + 0.11 * stripe * stripe_fade;
	// fine mottling (clover, bare spots); fades with distance (no shimmer)
	float fine = vn(p * 1.7) * 0.6 + vn(p * 5.3) * 0.4;
	float fine_w = 1.0 - smoothstep(30.0, 120.0, dist);
	col *= mix(1.0, 0.82 + 0.36 * fine, fine_w);
	ALBEDO = col;
	ROUGHNESS = 0.93 - 0.06 * stripe * stripe_fade;
	SPECULAR = 0.28;
	// grain normal: blade clumps up close, stripe sheen far
	float e = 0.35;
	float gx = vn((p + vec2(e, 0.0)) * 1.7) - vn((p - vec2(e, 0.0)) * 1.7);
	float gz = vn((p + vec2(0.0, e)) * 1.7) - vn((p - vec2(0.0, e)) * 1.7);
	vec3 n_ws = normalize(vec3(-gx * 0.6 * fine_w - dir.x * 0.05 * stripe, 1.0, -gz * 0.6 * fine_w - dir.y * 0.05 * stripe));
	vec3 gn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	if (gn.y > 0.7) { NORMAL = normalize((VIEW_MATRIX * vec4(n_ws, 0.0)).xyz); }
}
"""

static func off() -> bool:
	return "--fill-off" in OS.get_cmdline_user_args()

## The shared lawn material (null when --fill-off: callers keep their own).
static func material() -> Material:
	if off():
		return null
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		_mat = m
	return _mat

static func or_default(fallback: Material) -> Material:
	var m := material()
	return m if m != null else fallback
