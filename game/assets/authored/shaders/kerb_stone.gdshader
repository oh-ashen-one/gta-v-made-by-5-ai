shader_type spatial;
// Precast concrete kerb units (nearfield, opus55 wave D). Mapped by the swept
// kerb mesh built in src/world/nearfield.gd:
//   UV.x  = metres along the kerb run
//   UV.y  = metres around the profile (0 at the road-side foot)
//   UV2.x = arris weight (1 on the rounded top edge, 0 on flat faces)
//   UV2.y = face: 0 road-side face, 1 top, 2 back/bed
//   COLOR.r = painted (black/white reflective bands), COLOR.g = band phase
// Unit joints every 0.915 m, per-unit tone, chipped and lighter arris,
// tyre scuffs and road grime at the foot, algae at the gutter line, paint
// that wears through to concrete on the arris.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://assets/authored/shaders/weathering.gdshaderinc"

uniform sampler2D grain_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.66, 0.65, 0.62);
uniform float unit_len = 0.915;
uniform float band_len = 0.915;
uniform float wear = 1.0;
// Grain source normalisation: authored concrete (grey 0.72) or the provider
// weathered concrete (warm, mean 0.59/0.564/0.516). grain_colour keeps part
// of the map's own hue (algae, rust and tannin stains) on top of the tint.
uniform vec3 grain_mean = vec3(0.72);
uniform float grain_scale = 0.55;
uniform float grain_colour = 0.0;

float vn(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(w_hash12(i), w_hash12(i + vec2(1, 0)), u.x), mix(w_hash12(i + vec2(0, 1)), w_hash12(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float along = UV.x;
	float prof = UV.y;
	float arris = UV2.x;
	float face = UV2.y;
	float painted = COLOR.r;
	float fw = max(fwidth(along), 1e-4);
	float unit = floor(along / unit_len);
	float u = fract(along / unit_len);
	float jd = min(u, 1.0 - u) * unit_len;
	// concrete grain (authored 4 m tile, sampled at kerb scale)
	vec3 gt = texture(grain_tex, vec2(along, prof) * grain_scale + vec2(unit * 0.29, unit * 0.37)).rgb / grain_mean;
	float g = dot(gt, vec3(0.333));
	float h = w_hash12(vec2(unit, 3.1));
	float tone = g * (0.90 + 0.18 * h);
	vec3 ghue = mix(vec3(1.0), gt / max(g, 1e-3), grain_colour);
	vec4 m1 = w_mask(vec2(along / 5.3, prof * 0.7 + h));
	vec4 m2 = w_mask(vec2(along / 1.1 + 0.3, prof * 3.0));
	// unit joints: a dark mortar line with a soft footprint-aware edge
	float joint = 1.0 - smoothstep(0.004, 0.004 + fw * 1.2, jd);
	// arris: chips and scuffs expose lighter aggregate
	float chip_n = vn(vec2(along * 9.0, prof * 9.0 + unit));
	float chips = arris * smoothstep(0.55, 0.75, chip_n * 0.7 + m2.r * 0.5) * wear;
	// near-joint corner spalls
	chips = max(chips, arris * (1.0 - smoothstep(0.0, 0.05, jd)) * step(0.55, h));
	vec3 col = tint * tone * ghue;
	col *= mix(1.0, 1.16, chips);
	// grime: road-side foot (spray, silt), tyre scuffs, algae at the gutter
	float foot = (1.0 - smoothstep(0.0, 0.10, prof)) * step(face, 0.5);
	col *= 1.0 - 0.32 * foot * (0.6 + 0.4 * m1.g) * wear;
	float scuff = step(face, 0.5) * smoothstep(0.6, 0.75, w_mask(vec2(along / 3.7, 0.21)).g)
		* (1.0 - smoothstep(0.05, 0.16, abs(prof - 0.09))) * (0.5 + 0.5 * vn(vec2(along * 6.0, prof * 30.0)));
	col *= 1.0 - 0.55 * scuff * wear;
	float algae = foot * smoothstep(0.5, 0.75, m1.b + m1.r * 0.3);
	col = mix(col, col * vec3(0.72, 0.80, 0.62), algae * 0.6 * wear);
	// top: foot-traffic dirt, darker toward the back where silt collects
	float top = step(0.5, face) * step(face, 1.5);
	col *= 1.0 - 0.10 * top * smoothstep(0.45, 0.8, m1.r) * wear;
	// rain-darkened streaks down the face
	float streak = step(face, 0.5) * smoothstep(0.62, 0.8, vn(vec2(along * 3.0, 0.5))) * smoothstep(0.02, 0.2, prof);
	col *= 1.0 - 0.10 * streak * wear;
	float rough = 0.88 - 0.06 * scuff;
	// painted reflective bands (islands, bus stops, junction noses)
	if (painted > 0.5) {
		// anti-aliased black/white bands (square wave from a sine)
		float sw = sin(PI * (along / band_len + COLOR.g * 2.0));
		float band = smoothstep(-1.0, 1.0, sw / max(fw * PI / band_len * 1.6, 1e-4));
		vec3 pc = mix(vec3(0.045, 0.045, 0.05), vec3(0.80, 0.80, 0.77), band);
		// paint wear: through to concrete on chips, thinned on the foot
		float worn = clamp(chips * 1.2 + smoothstep(0.6, 0.85, m2.g * 0.6 + chip_n * 0.5) * 0.5 * arris, 0.0, 1.0);
		vec3 paint = pc * (0.92 + 0.08 * g);
		paint *= 1.0 - 0.30 * foot * (0.6 + 0.4 * m1.g);
		paint *= 1.0 - 0.40 * scuff;
		col = mix(paint, col, worn);
		rough = mix(0.55, rough, worn);
		joint *= 0.5;
	}
	col *= 1.0 - 0.55 * joint;
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(rough + 0.08 * joint, 0.3, 1.0);
	SPECULAR = 0.45;
	NORMAL_MAP = texture(grain_nrm, vec2(along, prof) * grain_scale + vec2(unit * 0.29, unit * 0.37)).rgb;
	NORMAL_MAP_DEPTH = 0.8 + 0.8 * chips;
	// ambient occlusion in the joint and at the foot
	AO = 1.0 - 0.5 * joint - 0.25 * foot;
	AO_LIGHT_AFFECT = 0.3;
}
