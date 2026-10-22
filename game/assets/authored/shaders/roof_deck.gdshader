// Weathered flat-roof deck (wave A, Opus 5.5). Per-instance colour (MultiMesh
// COLOR) picks the membrane: grey concrete tiles, dark bitumen, green or red
// waterproofing paint, or ribbed metal sheet (COLOR.a < 0.5). World-space
// stains, ponding marks, patch repairs and tile seams break up each parcel so
// an aerial camera reads weathered rooftops, not flat beige boxes. Side faces
// of the deck slab render as a concrete parapet band.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 parapet_col : source_color = vec3(0.62, 0.60, 0.56);

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 tint;

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.1 + 7.3) * 0.3 + vnoise(p * 4.3 - 2.1) * 0.15; }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float pulse(float x, float w, float fw) {
	return mix(step(fract(x), w), w, clamp(fw * 1.6 - 0.2, 0.0, 1.0));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Instance colours arrive as sRGB values; shade in linear.
	tint = vec4(pow(COLOR.rgb, vec3(2.2)), COLOR.a);
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec2 q = wpos.xz;
	if (n.y < 0.5) {
		// Parapet edge: painted concrete with rain streaks.
		float streak = vnoise(vec2((wpos.x + wpos.z) * 1.7, wpos.y * 0.2));
		ALBEDO = parapet_col * (0.82 + 0.22 * streak);
		ROUGHNESS = 0.9;
	} else {
		vec3 base = tint.rgb;
		bool metal_sheet = tint.a < 0.5;
		float stain = fbm(q * 0.11 + tint.r * 31.0);
		float big = fbm(q * 0.035 + tint.g * 7.0);
		float pond = smoothstep(0.58, 0.74, fbm(q * 0.045 + 11.0 + tint.g * 17.0));
		float patch = step(0.80, hash2(floor(q / vec2(5.0, 3.5)) + tint.b * 13.0));
		float dark_patch = step(0.88, hash2(floor(q / vec2(3.0, 6.0)) + 4.0 + tint.b * 7.0));
		vec3 c = base * (0.55 + 0.75 * stain) * (0.8 + 0.4 * big);
		if (metal_sheet) {
			// Ribbed metal sheet: ribs every 0.25 m along x, rust bloom.
			float rib = pulse(q.x / 0.25, 0.3, fwidth(q.x / 0.25));
			c = mix(c, c * 0.7, rib * 0.5);
			c = mix(c, lin(vec3(0.42, 0.24, 0.16)), smoothstep(0.6, 0.85, stain) * 0.6);
			ROUGHNESS = 0.55;
			METALLIC = 0.45;
		} else {
			float tiles = max(pulse(q.x / 1.5, 0.04, fwidth(q.x / 1.5)), pulse(q.y / 1.5, 0.04, fwidth(q.y / 1.5)));
			c = mix(c, c * 0.68, tiles * 0.55);
			c = mix(c, c * 1.35 + vec3(0.01), patch * 0.6);
			c = mix(c, lin(vec3(0.16, 0.16, 0.17)), dark_patch * 0.75);
			ROUGHNESS = 0.93;
			METALLIC = 0.0;
		}
		// Dark ponding / algae marks after rain.
		c = mix(c, c * 0.45 + lin(vec3(0.03, 0.05, 0.03)), pond * 0.75);
		ALBEDO = c;
	}
}
