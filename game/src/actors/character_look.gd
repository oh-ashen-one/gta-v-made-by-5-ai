class_name CharacterLook
extends RefCounted
## Characters piece (wave D): close-range fidelity and crowd variety for the
## provider humanoid (player + civilian rigs).
##
## The provider atlas packs hundreds of tiny per-triangle UV islands whose
## baked colours disagree, so mip-filtered sampling paints the shirt and the
## trousers with a triangle mosaic that reads as stair-stepped shadow blotches
## at close range. At load time this rebuilds the skinned mesh once per rig:
##   * every vertex is classified into a body region (skin, face, hair,
##     overshirt, tee, trousers, shoe, sole) from mip-0 samples of the atlas
##     plus its rest height;
##   * the baked albedo is resampled at mip 0, welded across UV seams and
##     smoothed inside each region, leaving only its low-frequency fold / AO
##     shading (COLOR + CUSTOM0.z);
##   * the rest position goes to CUSTOM1 so the shader can draw stable,
##     UV-free cloth weave, folds, skin pores and hair strands;
##   * the hair gets three skinned shells (CUSTOM0.y) whose strand-clump
##     dither gives a broken, soft silhouette instead of a solid helmet;
##   * all surfaces merge into one draw call with generated LODs.
## Outfits, skin tone, hair colour and body build are per-instance shader
## parameters on one shared material, so a crowd of 140 stays one material.

const SHELLS := 4
## Wrist-to-knuckle length (m) on the provider hand.
const GRIP_PALM := 0.085
const R_SKIN := 0
const R_SHIRT := 1
const R_HAIR := 2
const R_TEE := 3
const R_PANTS := 4
const R_SHOE := 5
const R_SOLE := 6
const R_FACE := 7

static var _cache := {}
static var enabled := OS.get_environment("ORCHARD_LEGACY_CHARACTERS") == ""

const SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, sss_mode_skin;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 src_skin = vec3(0.5, 0.3, 0.2);
uniform vec3 head_centre = vec3(0.0, 1.62, 0.0);
uniform vec3 nose_tip = vec3(-0.016, 1.575, -0.089);
uniform float placket_x = 0.004;
uniform float shell_step = 0.0034;
uniform float near_fade = 0.6;
uniform vec3 grip_centre = vec3(0.0, -10.0, 0.0);
uniform float grip_len = 0.075;
uniform float grip_max = 2.0;
uniform int debug_mode = 0; // QA only: 1 flat grey albedo, 2 region colours

// Per-instance wardrobe (linear colours). w channels carry extra parameters.
instance uniform vec4 shirt_col = vec4(0.07, 0.065, 0.035, 0.0); // w: pattern id
instance uniform vec4 shirt_col2 = vec4(0.2, 0.2, 0.2, 9.0);   // w: pattern scale
instance uniform vec4 tee_col = vec4(0.33, 0.33, 0.31, 0.0);    // w: 1 = no overshirt (plain tee)
instance uniform vec4 pants_col = vec4(0.010, 0.016, 0.040, 0.0); // w: 1 = shorts
instance uniform vec4 shoe_col = vec4(0.030, 0.014, 0.007, 0.25); // w: sole value
instance uniform vec4 skin_col = vec4(-1.0, 0.0, 0.0, 0.0);      // x<0: authored tone; w: girth
instance uniform vec4 hair_col = vec4(0.004, 0.003, 0.0025, 0.0); // w: grey amount
instance uniform vec4 face_col = vec4(0.0, 0.5, 0.5, 0.0);       // x: stubble, y: creases, z: flush, w: pockets
// Procedural right-hand grip: x = curl amount; hand_* = hand bone rest->pose rotation columns.
instance uniform vec4 grip = vec4(0.0);
instance uniform vec4 hand_x = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 hand_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 hand_z = vec4(0.0, 0.0, 1.0, 0.0);

varying flat int v_region;
varying vec3 v_rest;
varying vec4 v_data;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1,0,0)), f.x), mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x), mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.37 + 3.3) * 0.15;
}
// Anti-aliased thin line at |d| < w (d in metres).
float line_aa(float d, float w) {
	float fw = max(fwidth(d), 0.00001);
	return 1.0 - smoothstep(w - fw, w + fw, abs(d));
}
// Periodic band of width w (metres) centred at offset*period.
float tband(float t, float period, float off, float w) {
	float d = abs(fract(t / period - off + 0.5) - 0.5) * period;
	float fw = max(fwidth(t), 0.00001);
	return 1.0 - smoothstep(w * 0.5 - fw, w * 0.5 + fw, d);
}
// Woven tartan / flannel check (q in metres). Single-band areas alternate
// warp and weft colour along the twill diagonal at close range.
vec3 tartan(vec2 q, vec3 base, vec3 accent, float scale, float fine_k) {
	float P = 0.105 * scale;
	float a1 = tband(q.x, P, 0.0, 0.036 * scale);
	float b1 = tband(q.y, P, 0.0, 0.036 * scale);
	float a2 = tband(q.x, P, 0.5, 0.011 * scale);
	float b2 = tband(q.y, P, 0.5, 0.011 * scale);
	float a3 = tband(q.x, P, 0.25, 0.0035);
	float b3 = tband(q.y, P, 0.25, 0.0035);
	float tw = step(0.5, fract((q.x + q.y) / 0.0026));
	float half_tone = mix(0.5, tw, fine_k);
	vec3 dark = base * vec3(0.30, 0.32, 0.36);
	vec3 warp = mix(base, dark, a1);
	vec3 weft = mix(base, dark, b1);
	warp = mix(warp, accent, a2);
	weft = mix(weft, accent, b2);
	vec3 light = mix(base, vec3(0.55, 0.52, 0.42), 0.5);
	warp = mix(warp, light, a3 * 0.8);
	weft = mix(weft, light, b3 * 0.8);
	return mix(warp, weft, half_tone);
}

void vertex() {
	v_region = int(CUSTOM0.x + 0.5);
	v_rest = CUSTOM1.xyz;
	v_data = CUSTOM0;
	// Body build: belly/chest girth pushes the torso out along its normal.
	vec3 r = CUSTOM1.xyz;
	float band = smoothstep(0.84, 1.02, r.y) * (1.0 - smoothstep(1.20, 1.44, r.y));
	float core = 1.0 - smoothstep(0.15, 0.25, abs(r.x));
	float front = mix(0.55, 1.0, smoothstep(-0.02, 0.10, -r.z));
	VERTEX += NORMAL * skin_col.w * 0.055 * band * core * front;
	if (CUSTOM0.y > 0.5) {
		VERTEX += NORMAL * CUSTOM0.y * shell_step;
	}
	// Fingers wrap the weapon grip: each finger vertex rotates about the
	// knuckle line by an angle growing with its distance past the knuckles
	// (a bend deformer in rest space, carried into pose by the hand rotation).
	if (CUSTOM1.w > 0.5 && grip.x > 0.001) {
		float t = grip_centre.y - r.y;
		float phi = -grip_centre.z * clamp(t / grip_len, 0.0, 1.0) * grip_max * grip.x;
		float cs = cos(phi);
		float sn = sin(phi);
		vec2 o = r.xy - grip_centre.xy;
		vec2 o2 = vec2(cs * o.x - sn * o.y, sn * o.x + cs * o.y);
		mat3 R = mat3(hand_x.xyz, hand_y.xyz, hand_z.xyz);
		VERTEX += R * vec3(o2 - o, 0.0);
		mat3 Rz = mat3(vec3(cs, sn, 0.0), vec3(-sn, cs, 0.0), vec3(0.0, 0.0, 1.0));
		NORMAL = normalize(R * (Rz * (transpose(R) * NORMAL)));
	}
}

// Screen-derivative bump: perturbs the view-space normal by a height field
// (metres) without tangents, so the chaotic atlas UVs never matter.
vec3 bump(vec3 n, vec3 pos, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 g = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * n - g);
}

void fragment() {
	// Never show the inside of a head when the camera passes through someone.
	float d = length(VERTEX);
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (d < near_fade && ign > smoothstep(near_fade * 0.4, near_fade, d)) {
		discard;
	}
	int reg = v_region;
	vec3 p = v_rest;
	float shell = v_data.y;
	float shade = clamp(v_data.z, 0.7, 1.25);
	float e = v_data.w; // distance (m) to the nearest garment / region border
	float px = length(fwidth(p));
	float fine_k = 1.0 - smoothstep(0.0012, 0.004, px);
	float mid_k = 1.0 - smoothstep(0.004, 0.014, px);
	vec3 skin_tone = skin_col.x < 0.0 ? src_skin : skin_col.rgb;
	float az = atan(p.x, p.z);
	float u = az * 0.17;
	// Rest-space facet normal -> triplanar weights for UV-free cloth patterns.
	vec3 nr = normalize(cross(dFdx(p), dFdy(p)));
	vec3 tw3 = pow(abs(nr), vec3(4.0));
	tw3 /= max(tw3.x + tw3.y + tw3.z, 0.0001);
	vec3 col = vec3(0.5);
	float rough = 0.85;
	float spec = 0.3;
	float h = 0.0;
	float sss = 0.0;
	float rim = 0.0;
	float ao = 1.0;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	float nmap_depth = 0.0;
	if (reg == 4 && pants_col.w > 0.5 && p.y < 0.50) {
		reg = 0; // shorts: bare lower legs
	}
	bool tee_only = false;
	if (reg == 1 && tee_col.w > 0.5) {
		reg = 3; // plain tee, no overshirt
		tee_only = true;
	}
	vec3 rel = p - nose_tip;
	if (reg == 0) {
		// Arms, hands, neck: uneven tone, fine grain, knuckle/elbow redness.
		float tone = fbm(p * 14.0);
		col = skin_tone * (0.9 + 0.18 * tone);
		col *= mix(vec3(1.0), vec3(1.08, 0.93, 0.90), smoothstep(0.55, 0.85, vnoise(p * 26.0)) * 0.7);
		col *= 0.95 + 0.1 * vnoise(p * 140.0);
		rough = 0.48 + 0.25 * vnoise(p * 160.0);
		spec = 0.36;
		sss = 0.2;
		h = (vnoise(p * 520.0) - 0.5) * 0.00022 * fine_k + (vnoise(p * 140.0) - 0.5) * 0.0003 * mid_k;
		rim = 0.1;
	} else if (reg == 7) {
		// The provider face texture is split into many auto-UV islands whose
		// tones disagree (blotchy cheeks). Skin is procedural; the texture is
		// used only for the features: eyes + brows, lips, and dark details
		// (nostrils, lash line) inside the face box.
		vec3 tex = texture(albedo_tex, UV).rgb;
		vec3 ratio = skin_tone / max(src_skin, vec3(0.002));
		float tl = dot(tex, vec3(0.2126, 0.7152, 0.0722));
		float sl = dot(src_skin, vec3(0.2126, 0.7152, 0.0722));
		float feature = (1.0 - smoothstep(0.05, 0.06, abs(rel.x))) * step(-0.045, rel.y) * step(rel.y, 0.078) * step(rel.z, 0.035);
		float eyes = (1.0 - smoothstep(0.05, 0.06, abs(rel.x))) * smoothstep(0.028, 0.036, rel.y) * (1.0 - smoothstep(0.046, 0.054, rel.y)) * step(rel.z, 0.03);
		float mouth = (1.0 - smoothstep(0.024, 0.032, abs(rel.x))) * (1.0 - smoothstep(0.007, 0.012, abs(rel.y + 0.029)));
		float dark_feat = feature * (1.0 - smoothstep(0.45, 0.8, tl / max(sl, 0.001))) * (1.0 - smoothstep(0.072, 0.078, rel.y));
		float use_tex = clamp(max(max(eyes, mouth * 0.8), dark_feat), 0.0, 1.0);
		vec3 base = skin_tone * mix(1.0, clamp(shade, 0.85, 1.15), 0.5);
		col = mix(base, tex * ratio * 0.95, use_tex);
		col = mix(col, col * vec3(0.95, 0.74, 0.72), mouth * 0.5);
		float sk = smoothstep(0.02, 0.07, dot(tex, vec3(0.33)));
		// Uneven tone: flushed cheeks / nose / ears, cooler under-eyes.
		float tone = fbm(p * 40.0);
		col *= 0.92 + 0.14 * tone;
		float cheek = (1.0 - smoothstep(0.015, 0.035, length(vec2(abs(rel.x) - 0.045, rel.y - 0.01)))) + (1.0 - smoothstep(0.004, 0.016, length(rel.xy)));
		col *= mix(vec3(1.0), vec3(1.08, 0.92, 0.90), clamp(cheek, 0.0, 1.0) * face_col.z);
		float under_eye = (1.0 - smoothstep(0.006, 0.012, abs(rel.y - 0.036))) * smoothstep(0.012, 0.02, abs(rel.x)) * (1.0 - smoothstep(0.045, 0.055, abs(rel.x)));
		col *= mix(vec3(1.0), vec3(0.86, 0.84, 0.88), under_eye * 0.8);
		// Stubble: jaw, chin and upper lip (lips themselves excluded).
		float jy = -0.008 - 0.2 * abs(rel.x);
		float jaw = (1.0 - smoothstep(jy - 0.014, jy + 0.004, rel.y)) * smoothstep(-0.1, -0.086, rel.y) * (1.0 - smoothstep(0.065, 0.085, abs(rel.x)));
		float lips = (1.0 - smoothstep(0.022, 0.03, abs(rel.x))) * (1.0 - smoothstep(0.006, 0.01, abs(rel.y + 0.029)));
		float stub_mask = jaw * (1.0 - lips) * face_col.x;
		float dots = smoothstep(0.45, 0.75, hash13(floor(p * 1400.0)));
		float stub = stub_mask * mix(0.55, 0.25 + 0.75 * dots, fine_k);
		col = mix(col, col * vec3(0.30, 0.30, 0.34), stub * 0.85);
		h += stub * (dots - 0.5) * 0.00025 * fine_k;
		// Expression creases: nasolabial folds and forehead lines.
		vec2 a = vec2(0.022, -0.004);
		vec2 b = vec2(0.033, -0.036);
		vec2 q = vec2(abs(rel.x), rel.y);
		float tseg = clamp(dot(q - a, b - a) / dot(b - a, b - a), 0.0, 1.0);
		float dl = length(q - (a + (b - a) * tseg));
		float crease = (1.0 - smoothstep(0.0012, 0.0045, dl)) * face_col.y;
		float fh = (1.0 - smoothstep(0.03, 0.05, abs(rel.x))) * step(0.085, rel.y) * step(rel.y, 0.125);
		float flines = fh * line_aa(fract((rel.y - 0.085) / 0.012) - 0.5, 0.08) * face_col.y * 0.5;
		ao *= 1.0 - 0.35 * crease - 0.2 * flines;
		col *= 1.0 - 0.18 * crease - 0.1 * flines;
		rough = mix(0.6, 0.38 + 0.25 * vnoise(p * 180.0), sk);
		rough = mix(rough, 0.32, (1.0 - smoothstep(0.0, 0.03, length(rel.xy))) * 0.6); // oily nose
		spec = 0.4;
		sss = 0.38 * sk;
		nmap = texture(normal_tex, UV).rgb;
		nmap_depth = 0.75;
		h = (vnoise(p * 900.0) - 0.5) * 0.00016 * fine_k + (vnoise(p * 300.0) - 0.5) * 0.0002 * mid_k - crease * 0.0009 - flines * 0.0003;
		rim = 0.08;
	} else if (reg == 2) {
		vec3 q = p - head_centre;
		float qa = atan(q.x, q.z);
		float pol = acos(clamp(q.y / max(length(q), 0.001), -1.0, 1.0));
		float warp = vnoise(vec3(qa * 3.0, pol * 4.0, 1.7)) * 1.6;
		float clump = vnoise(vec3(qa * 18.0 + warp, pol * 2.4, 3.1));
		float strand = vnoise(vec3(qa * 170.0 + warp * 9.0, pol * 6.0, 9.7));
		float strand2 = vnoise(vec3(qa * 420.0 + warp * 20.0, pol * 9.0, 2.3));
		float m = strand * 0.45 + strand2 * 0.2 + clump * 0.35;
		float edge = smoothstep(0.0, 0.03, e); // 0 at the hairline
		if (shell > 0.5) {
			float cut = 0.26 + 0.14 * shell + (ign - 0.5) * 0.16 + (1.0 - edge) * 0.4;
			if (m < cut) {
				discard;
			}
		}
		float buzz = step(1.5, hair_col.w);
		float grey = hair_col.w - 2.0 * buzz;
		if (buzz > 0.5 && shell > 0.5) {
			discard;
		}
		vec3 hc = mix(hair_col.rgb, vec3(0.32, 0.31, 0.30), grey * smoothstep(0.25, 0.75, vnoise(vec3(qa * 60.0, pol * 3.0, 5.0)) + grey * 0.35));
		hc *= mix(vec3(1.0), vec3(1.5, 1.25, 1.0), smoothstep(0.6, 0.9, clump) * 0.6); // warm sun-bleached clumps
		col = hc * (0.4 + 0.8 * strand) * (0.7 + 0.5 * clump) * (0.8 + 0.3 * strand2) * mix(0.75, 1.15, shell / 4.0);
		if (buzz > 0.5) {
			// Clipper cut: scalp tone under dense short stubble.
			float sd = smoothstep(0.35, 0.7, hash13(floor(p * 1300.0)));
			col = mix(skin_tone * 0.7, hair_col.rgb, mix(0.55, 0.3 + 0.6 * sd, fine_k) * smoothstep(0.0, 0.02, e));
		} else if (shell < 0.5) {
			// Scalp shows through a thinning hairline instead of a hard shell edge.
			col = mix(skin_tone * 0.55, col, mix(0.25, 1.0, edge));
		}
		rough = 0.34 + 0.3 * (1.0 - strand);
		spec = 0.5;
		h = (strand * 0.5 + strand2 * 0.2 + clump * 0.3) * 0.0018 * mid_k;
		rim = 0.25;
		ao = mix(0.7, 1.0, shell / 4.0);
	} else if (reg == 1 || reg == 3) {
		int pat = int(shirt_col.w + 0.5);
		float s = shirt_col2.w;
		vec3 base = reg == 1 ? shirt_col.rgb : tee_col.rgb;
		col = base;
		vec2 qf = vec2(p.x, p.y);
		vec2 qs = vec2(p.z, p.y);
		vec2 qt = vec2(p.x, p.z);
		if (reg == 1 || tee_only) {
			if (pat == 5) {
				col = tartan(qf, base, shirt_col2.rgb, s, fine_k) * tw3.z + tartan(qs, base, shirt_col2.rgb, s, fine_k) * tw3.x + tartan(qt, base, shirt_col2.rgb, s, fine_k) * tw3.y;
			} else if (pat == 1) {
				float fu = fract(u * s);
				float st = smoothstep(0.55, 0.6, fu) - smoothstep(0.85, 0.9, fu);
				col = mix(col, shirt_col2.rgb, mix(0.3, st, mid_k));
			} else if (pat == 2) {
				float ga = tband(p.x * tw3.z + p.z * tw3.x, 1.0 / s, 0.0, 0.5 / s);
				float gb = tband(p.y, 1.0 / s, 0.0, 0.5 / s);
				col = mix(col, shirt_col2.rgb, (ga * 0.5 + gb * 0.5));
			} else if (pat == 3) {
				vec3 bp = vec3(u * s, p.y * s, 0.0);
				float f = vnoise(bp * 1.0) * 0.65 + vnoise(bp * 2.7) * 0.35;
				float petal = smoothstep(0.58, 0.62, f) - smoothstep(0.72, 0.76, f) * 0.6;
				float dots = smoothstep(0.80, 0.84, vnoise(bp * 6.0));
				col = mix(col, shirt_col2.rgb, clamp(petal + dots * 0.7, 0.0, 1.0));
			} else if (pat == 4) {
				col = mix(col, shirt_col2.rgb, smoothstep(1.43, 1.46, p.y));
			}
		}
		// Brushed-cotton fuzz.
		col *= 0.94 + 0.12 * vnoise(p * 260.0) * mid_k + 0.06 * (vnoise(p * 40.0) - 0.5);
		float nz = vnoise(p * 9.0);
		// Load folds (metres of displacement): waist bunching, lower-torso
		// drape, armpit drag lines, short-sleeve creases, collar roll.
		float waist = (1.0 - smoothstep(0.0, 0.12, abs(p.y - 1.0))) * (1.0 - smoothstep(0.17, 0.26, abs(p.x)));
		float drape = smoothstep(1.24, 0.96, p.y) * (1.0 - smoothstep(0.17, 0.26, abs(p.x)));
		float sleeve = smoothstep(0.17, 0.22, abs(p.x)) * smoothstep(1.14, 1.22, p.y);
		vec2 ap = vec2(abs(p.x) - 0.17, p.y - 1.30);
		float ar = length(ap);
		float ang = atan(ap.y, ap.x);
		float armpit = smoothstep(0.015, 0.04, ar) * (1.0 - smoothstep(0.10, 0.17, ar)) * step(abs(p.x), 0.19);
		float f1 = sin(p.y * 110.0 + nz * 6.0 + az * 3.0) * waist;
		float f2 = sin(u * 70.0 + nz * 5.0 + p.y * 9.0) * drape;
		float f3 = sin(p.y * 85.0 - abs(p.x) * 40.0 + nz * 4.0) * sleeve;
		float f4 = sin(ang * 11.0 + nz * 3.0) * armpit;
		float f5 = sin(e * 260.0 + nz * 3.0) * (1.0 - smoothstep(0.0, 0.035, e)) * step(1.38, p.y);
		float amp = reg == 1 ? 1.0 : 0.7;
		float folds = (f1 * 0.0034 + f2 * 0.0026 + f3 * 0.0024 + f4 * 0.0026 + f5 * 0.0012) * amp * mid_k;
		float cavity = clamp(-(f1 * waist + f2 * drape * 0.8 + f3 * sleeve + f4 * armpit), 0.0, 1.0);
		ao *= 1.0 - 0.32 * cavity * amp;
		float weave = (vnoise(p * 360.0) - 0.5) * 0.00018 * fine_k;
		h = folds + weave;
		// Construction: hems with a stitch line along every garment border.
		float hem = 1.0 - smoothstep(0.016, 0.021, e);
		float dash = step(0.38, fract((p.x + p.y * 1.3 + p.z) / 0.0042));
		float stitch = line_aa(e - 0.011, 0.0006) * dash * fine_k;
		h += hem * 0.0007 + (1.0 - smoothstep(0.0, 0.004, e)) * 0.0008;
		ao *= 1.0 - 0.12 * hem;
		vec3 thread = mix(col, col * 1.7 + vec3(0.015), 0.6);
		if (reg == 1) {
			float front = smoothstep(0.35, 0.65, tw3.z) * step(p.z, -0.02);
			float back = smoothstep(0.35, 0.65, tw3.z) * step(0.03, p.z);
			float xp = p.x - placket_x;
			// Button placket: two stitch lines, raised band, buttons.
			float plk = front * (1.0 - smoothstep(0.016, 0.019, abs(xp))) * step(p.y, 1.44) * step(0.9, p.y);
			float plk_st = front * step(p.y, 1.44) * (line_aa(abs(xp) - 0.0155, 0.0005) + line_aa(xp + 0.002, 0.0005)) * step(0.35, fract(p.y / 0.004)) * mid_k;
			h += plk * 0.0006 + line_aa(xp + 0.003, 0.0012) * front * step(p.y, 1.44) * 0.0009;
			ao *= 1.0 - 0.3 * line_aa(xp + 0.004, 0.0012) * front * step(p.y, 1.44);
			float yb = 1.0 + clamp(round((p.y - 1.0) / 0.075), 0.0, 5.0) * 0.075;
			float bd = length(vec2(xp + 0.0005, p.y - yb));
			float btn = front * step(0.92, p.y) * (1.0 - smoothstep(0.0048, 0.0058, bd));
			// Chest pockets with flap, stitching and a flap button.
			float pk = 0.0;
			float pk_st = 0.0;
			float flap_sh = 0.0;
			if (face_col.w > 0.5) {
				for (int side = -1; side <= 1; side += 2) {
					float dx = xp - float(side) * 0.088;
					float inside = step(abs(dx), 0.05) * step(1.235, p.y) * step(p.y, 1.36);
					float de = min(0.05 - abs(dx), min(p.y - 1.235, 1.36 - p.y));
					pk += inside;
					pk_st += inside * line_aa(de - 0.004, 0.0005);
					float flap = step(abs(dx), 0.053) * step(1.322, p.y) * step(p.y, 1.37);
					float fde = min(0.053 - abs(dx), min(p.y - 1.322, 1.37 - p.y));
					pk_st += flap * line_aa(fde - 0.0035, 0.0005);
					flap_sh += step(abs(dx), 0.053) * (1.0 - smoothstep(0.0, 0.007, 1.322 - p.y)) * step(p.y, 1.322);
					h += flap * 0.0011 + inside * 0.0005;
					float pbd = length(vec2(dx, p.y - 1.331));
					btn = max(btn, (1.0 - smoothstep(0.0042, 0.0052, pbd)));
				}
				pk *= front;
				pk_st *= front * mid_k;
				flap_sh *= front;
			}
			ao *= 1.0 - 0.45 * flap_sh;
			col *= 1.0 - 0.25 * flap_sh;
			// Armhole, side and back-yoke seams.
			float arm_seam = line_aa(abs(p.x) - 0.188, 0.0009) * step(1.2, p.y);
			float side_seam = line_aa(p.z - 0.025, 0.0009) * smoothstep(0.5, 0.8, tw3.x) * step(abs(p.x), 0.18);
			float yoke = line_aa(p.y - 1.395, 0.0009) * back;
			float seams = clamp(arm_seam + side_seam + yoke, 0.0, 1.0);
			ao *= 1.0 - 0.35 * seams;
			h -= seams * 0.0006;
			stitch = clamp(stitch + (plk_st + pk_st) + seams * dash * 0.0, 0.0, 1.0);
			col = mix(col, thread, stitch * 0.8);
			// Buttons: dark horn discs with two thread holes, slight dome.
			vec3 bcol = vec3(0.13, 0.09, 0.055);
			float holes = (1.0 - smoothstep(0.0006, 0.0011, length(vec2(abs(xp + 0.0005) - 0.0016, p.y - yb)))) * front;
			col = mix(col, bcol, btn);
			col = mix(col, bcol * 0.3, holes * btn);
			h += btn * 0.0012 * (1.0 - bd / 0.006);
			rough = mix(rough, 0.35, btn);
		} else {
			col = mix(col, thread, stitch * 0.6);
		}
		col = min(col * mix(1.0, shade, 0.25), vec3(0.6));
		rough = reg == 1 ? 0.88 + 0.08 * vnoise(p * 90.0) : 0.9;
		spec = 0.24;
		rim = 0.12;
	} else if (reg == 4) {
		col = pants_col.rgb * mix(1.0, shade, 0.25);
		// Denim twill on the leg's own planes and soft wear on thighs/knees.
		float tw = sin(((p.x * tw3.z + p.z * tw3.x) + p.y) * 1900.0) * 0.5 + 0.5;
		col *= mix(1.0, 0.86 + 0.24 * tw, fine_k);
		col *= 0.93 + 0.14 * vnoise(vec3(p.x * 300.0, p.y * 30.0, p.z * 300.0)) * mid_k; // slub yarn streaks
		float wear = smoothstep(0.45, 0.85, vnoise(vec3(p.x * 30.0, p.y * 5.0, p.z * 30.0))) * (smoothstep(0.35, 0.55, p.y) - smoothstep(0.62, 0.8, p.y) * 0.5);
		col = mix(col, col * 1.5 + vec3(0.012), wear * 0.4);
		float nz = vnoise(p * 9.0);
		float knee = 1.0 - smoothstep(0.0, 0.1, abs(p.y - 0.50));
		float ankle = 1.0 - smoothstep(0.0, 0.1, abs(p.y - 0.20));
		float crotch = 1.0 - smoothstep(0.0, 0.08, abs(p.y - 0.80));
		float fl = sin(p.y * 95.0 + nz * 6.0 + az * 2.0);
		h = fl * (knee * 0.0028 + ankle * 0.0032 + crotch * 0.002) * mid_k;
		ao *= 1.0 - 0.3 * clamp(-fl, 0.0, 1.0) * (knee + ankle + crotch);
		h += (tw - 0.5) * 0.00007 * fine_k;
		float hem = 1.0 - smoothstep(0.016, 0.02, e);
		float dash = step(0.38, fract((p.x + p.y * 1.3 + p.z) / 0.0045));
		col = mix(col, vec3(0.62, 0.45, 0.22), line_aa(e - 0.01, 0.0006) * dash * fine_k * 0.8); // orange denim thread
		h += hem * 0.0008;
		rough = 0.82;
		spec = 0.25;
		rim = 0.2;
	} else if (reg == 5) {
		col = shoe_col.rgb * (0.94 + 0.12 * vnoise(p * 120.0));
		rough = 0.55 + 0.25 * vnoise(p * 60.0);
		spec = 0.4;
		h = (vnoise(p * 500.0) - 0.5) * 0.0001 * fine_k;
	} else {
		col = vec3(shoe_col.w) * (0.9 + 0.1 * vnoise(p * 200.0));
		rough = 0.9;
		spec = 0.25;
	}
	if (debug_mode == 1) {
		col = vec3(0.4);
		h = 0.0;
	} else if (debug_mode == 2) {
		col = vec3(float(reg & 1), float((reg >> 1) & 1), float((reg >> 2) & 1)) * 0.6 + 0.1;
	}
	NORMAL = bump(NORMAL, VERTEX, h);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = spec;
	METALLIC = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.45;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = nmap_depth;
	SSS_STRENGTH = sss;
	RIM = rim;
	RIM_TINT = 0.75;
}
"""

static var _shader: Shader

static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader

## Rebuilds the rig's skinned mesh with the region/rest/shell data (cached per
## source mesh) and binds the shared material. Returns the MeshInstance3D, or
## null when the rig cannot be processed (the caller keeps the old look).
static func apply(model: Node) -> MeshInstance3D:
	# Headless runs draw nothing, and the dummy renderer re-parses this shader
	# for every instance that binds it (~0.3 s each, ~60 s for the crowd), so
	# they keep the legacy materials; the regression builds the mesh directly.
	if not enabled or _headless:
		return null
	return _apply(model)

## Builds (or reuses) the look data for a rig's provider mesh without binding
## it to an instance (regression use; works headless).
static func build_for_rig(role: String) -> Dictionary:
	var path := CharacterVisual.asset_path(role)
	var packed := load(path) as PackedScene
	if packed == null:
		return {}
	var model := packed.instantiate()
	var entry := {}
	var target: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() >= 2:
			target = mi
			break
	if target != null:
		var key := _key(target.mesh as ArrayMesh)
		if not _cache.has(key):
			_cache[key] = _build(target.mesh as ArrayMesh, _wrist(model))
		entry = _cache[key]
	model.free()
	return entry

static func _key(src: ArrayMesh) -> String:
	return src.resource_path if src.resource_path != "" else str(src.get_instance_id())

static func _wrist(model: Node) -> Vector3:
	var skel := model.find_children("*", "Skeleton3D", true, false)
	if not skel.is_empty():
		var sk := skel[0] as Skeleton3D
		var hid := sk.find_bone("hand.r")
		if hid >= 0:
			return sk.get_bone_global_rest(hid).origin
	return Vector3.INF

static func _apply(model: Node) -> MeshInstance3D:
	var target: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() >= 2:
			target = mi
			break
	if target == null:
		return null
	var src := target.mesh as ArrayMesh
	# Right wrist (skeleton rest = mesh bind space for these rigs): the finger
	# vertices below its knuckle line get the procedural weapon grip.
	var wrist := _wrist(model)
	var key := _key(src)
	if not _cache.has(key):
		var t0 := Time.get_ticks_msec()
		_cache[key] = _build(src, wrist)
		print("[character-look] built ", key.get_file(), " in ", Time.get_ticks_msec() - t0, " ms")
	var entry: Dictionary = _cache[key]
	if entry.is_empty():
		return null
	target.mesh = entry["mesh"]
	for i in target.get_surface_override_material_count():
		target.set_surface_override_material(i, null)
	target.material_override = null
	return target

static func _surface_kind(mat: Material) -> int:
	var n := String(mat.resource_name) if mat != null else ""
	if n.contains("Sole"):
		return 3
	if n.contains("Textile"):
		return 2
	if n.contains("Clothing"):
		return 1
	return 0

static func _build(src: ArrayMesh, wrist: Vector3 = Vector3.INF) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tangs := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var kinds := PackedByteArray()
	var bpv := -1
	var albedo: Texture2D = null
	var normal: Texture2D = null
	for s in src.get_surface_count():
		var a := src.surface_get_arrays(s)
		var mat := src.surface_get_material(s)
		var kind := _surface_kind(mat)
		var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n := sv.size()
		var sb = a[Mesh.ARRAY_BONES]
		var sw = a[Mesh.ARRAY_WEIGHTS]
		if sb == null or sw == null or a[Mesh.ARRAY_NORMAL] == null or a[Mesh.ARRAY_TEX_UV] == null:
			return {}
		var this_bpv: int = (sb as PackedInt32Array).size() / n
		if bpv < 0:
			bpv = this_bpv
		elif bpv != this_bpv:
			return {}
		if kind <= 1 and albedo == null and mat is StandardMaterial3D:
			albedo = (mat as StandardMaterial3D).albedo_texture
			normal = (mat as StandardMaterial3D).normal_texture
		var base := verts.size()
		verts.append_array(sv)
		norms.append_array(a[Mesh.ARRAY_NORMAL])
		if a[Mesh.ARRAY_TANGENT] != null and (a[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() == n * 4:
			tangs.append_array(a[Mesh.ARRAY_TANGENT])
		else:
			for i in n:
				tangs.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		uvs.append_array(a[Mesh.ARRAY_TEX_UV])
		bones.append_array(sb)
		weights.append_array(sw)
		var kk := PackedByteArray()
		kk.resize(n)
		kk.fill(kind)
		kinds.append_array(kk)
		var si = a[Mesh.ARRAY_INDEX]
		if si == null:
			for i in n:
				indices.append(base + i)
		else:
			for i in (si as PackedInt32Array):
				indices.append(base + i)
	if albedo == null:
		return {}
	var img := albedo.get_image()
	if img == null:
		return {}
	img = img.duplicate() as Image
	if img.is_compressed():
		if img.decompress() != OK:
			return {}
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGB8)
	var iw := img.get_width()
	var ih := img.get_height()
	var data := img.get_data()
	var nv := verts.size()
	# Weld vertices split at UV seams.
	var weld := PackedInt32Array()
	weld.resize(nv)
	var lookup := {}
	var wn := 0
	for i in nv:
		var v := verts[i]
		var k := Vector3i(roundi(v.x * 4000.0), roundi(v.y * 4000.0), roundi(v.z * 4000.0))
		var w = lookup.get(k)
		if w == null:
			lookup[k] = wn
			weld[i] = wn
			wn += 1
		else:
			weld[i] = w
	# The provider splits vertices at every auto-UV island with its own
	# normal, which shades skin and cloth as a faceted triangle mosaic.
	# Average the normals of each welded position (smooth shading).
	var wnorm := PackedVector3Array()
	wnorm.resize(wn)
	for i in nv:
		wnorm[weld[i]] += norms[i]
	for i in nv:
		var nn := wnorm[weld[i]]
		if nn.length_squared() > 0.000001:
			norms[i] = nn.normalized()
	var wpos := PackedVector3Array()
	wpos.resize(wn)
	var wkind := PackedByteArray()
	wkind.resize(wn)
	for i in nv:
		wpos[weld[i]] = verts[i]
		wkind[weld[i]] = kinds[i]
	# Mip-0 samples pulled toward each triangle's UV centroid (inside its island).
	var acc := PackedFloat32Array()
	acc.resize(wn * 3)
	var cnt := PackedFloat32Array()
	cnt.resize(wn)
	var nt := indices.size() / 3
	for t in nt:
		var ia := indices[t * 3]
		var ib := indices[t * 3 + 1]
		var ic := indices[t * 3 + 2]
		if kinds[ia] >= 2:
			continue
		var uc := (uvs[ia] + uvs[ib] + uvs[ic]) / 3.0
		for corner in [ia, ib, ic]:
			var uv: Vector2 = uvs[corner].lerp(uc, 0.45)
			var x := clampi(int(fposmod(uv.x, 1.0) * iw), 0, iw - 1)
			var y := clampi(int(fposmod(uv.y, 1.0) * ih), 0, ih - 1)
			var o := (y * iw + x) * 3
			var wv: int = weld[corner]
			acc[wv * 3] += data[o]
			acc[wv * 3 + 1] += data[o + 1]
			acc[wv * 3 + 2] += data[o + 2]
			cnt[wv] += 1.0
	var col := PackedFloat32Array()
	col.resize(wn * 3)
	var region := PackedByteArray()
	region.resize(wn)
	var head_sum := Vector3.ZERO
	var head_n := 0.0
	for w in wn:
		var c := Color(0.2, 0.2, 0.2)
		if cnt[w] > 0.0:
			c = Color(acc[w * 3] / cnt[w] / 255.0, acc[w * 3 + 1] / cnt[w] / 255.0, acc[w * 3 + 2] / cnt[w] / 255.0)
		col[w * 3] = c.r
		col[w * 3 + 1] = c.g
		col[w * 3 + 2] = c.b
	# Neck axis from the skin ring under the jaw: the provider puts the neck on
	# the overshirt surface, and its dark atlas texels must stay skin.
	var neck_sum := Vector2.ZERO
	var neck_n := 0.0
	for w in wn:
		var v := wpos[w]
		if v.y > 1.45 and v.y < 1.50 and absf(v.x) < 0.12 and _skinlike(Color(col[w * 3], col[w * 3 + 1], col[w * 3 + 2])):
			neck_sum += Vector2(v.x, v.z)
			neck_n += 1.0
	var neck_c := neck_sum / maxf(neck_n, 1.0)
	var neck_r := 0.0
	for w in wn:
		var v := wpos[w]
		if v.y > 1.45 and v.y < 1.50 and absf(v.x) < 0.12 and _skinlike(Color(col[w * 3], col[w * 3 + 1], col[w * 3 + 2])):
			neck_r += Vector2(v.x, v.z).distance_to(neck_c)
	neck_r = neck_r / maxf(neck_n, 1.0) + 0.004
	print("[character-look] neck centre ", neck_c, " radius ", neck_r)
	for w in wn:
		region[w] = _classify(Color(col[w * 3], col[w * 3 + 1], col[w * 3 + 2]), wpos[w], wkind[w], neck_c, neck_r)
	_majority(region, indices, weld, wn)
	_majority(region, indices, weld, wn)
	_majority(region, indices, weld, wn)
	# Hair/head centre for the strand flow.
	for w in wn:
		if region[w] == R_HAIR:
			head_sum += wpos[w]
			head_n += 1.0
	var head_centre := Vector3(0.0, 1.62, 0.0)
	if head_n > 0.0:
		head_centre = head_sum / head_n
		head_centre.y -= 0.06
	# Nose tip (most forward face vertex at nose height): anchor for stubble,
	# creases and the facial-feature box in the shader.
	var nose_tip := Vector3(-0.016, 1.575, -0.089)
	var best_z := 1.0
	for w in wn:
		var v := wpos[w]
		if (region[w] == R_FACE or region[w] == R_SKIN) and v.y > 1.54 and v.y < 1.60 and absf(v.x) < 0.07 and v.z < best_z:
			best_z = v.z
			nose_tip = v
	# Smooth the baked colour inside each region (removes the island mosaic).
	for it in 3:
		var nacc := PackedFloat32Array()
		nacc.resize(wn * 3)
		var ncnt := PackedFloat32Array()
		ncnt.resize(wn)
		for w in wn:
			nacc[w * 3] = col[w * 3] * 2.0
			nacc[w * 3 + 1] = col[w * 3 + 1] * 2.0
			nacc[w * 3 + 2] = col[w * 3 + 2] * 2.0
			ncnt[w] = 2.0
		for t in nt:
			var wa := weld[indices[t * 3]]
			var wb := weld[indices[t * 3 + 1]]
			var wc := weld[indices[t * 3 + 2]]
			for pair in [[wa, wb], [wb, wc], [wc, wa]]:
				var x: int = pair[0]
				var y: int = pair[1]
				if region[x] != region[y]:
					continue
				nacc[x * 3] += col[y * 3]; nacc[x * 3 + 1] += col[y * 3 + 1]; nacc[x * 3 + 2] += col[y * 3 + 2]
				nacc[y * 3] += col[x * 3]; nacc[y * 3 + 1] += col[x * 3 + 1]; nacc[y * 3 + 2] += col[x * 3 + 2]
				ncnt[x] += 1.0
				ncnt[y] += 1.0
		for w in wn:
			col[w * 3] = nacc[w * 3] / ncnt[w]
			col[w * 3 + 1] = nacc[w * 3 + 1] / ncnt[w]
			col[w * 3 + 2] = nacc[w * 3 + 2] / ncnt[w]
	# Unique welded edges, built once for the smoothing and distance passes.
	var edge_set := {}
	var ea := PackedInt32Array()
	var eb := PackedInt32Array()
	for t in nt:
		var tri := [weld[indices[t * 3]], weld[indices[t * 3 + 1]], weld[indices[t * 3 + 2]]]
		for k in 3:
			var x: int = tri[k]
			var y: int = tri[(k + 1) % 3]
			if x == y:
				continue
			var key := mini(x, y) * 1000003 + maxi(x, y)
			if not edge_set.has(key):
				edge_set[key] = true
				ea.append(x)
				eb.append(y)
	var ne := ea.size()
	# The provider surface carries voxel-remesh stair-steps that every light
	# turned into rectangular blotches on skin and cloth. Laplacian-smooth the
	# welded normals within each region: strongly on skin (8 passes), lightly
	# on cloth (2 passes, keeps the real folds). Positions stay authored
	# (smoothing them broke the shared civilian rig's LOD/skinning).
	for it in 8:
		var nacc := PackedVector3Array()
		nacc.resize(wn)
		for w in wn:
			nacc[w] = wnorm[w] * 2.0
		for k in ne:
			var x := ea[k]
			var y := eb[k]
			if region[x] != region[y]:
				continue
			if it >= 2 and region[x] != R_SKIN and region[x] != R_FACE:
				continue
			nacc[x] += wnorm[y]
			nacc[y] += wnorm[x]
		for w in wn:
			if nacc[w].length_squared() > 0.0000001:
				wnorm[w] = nacc[w].normalized()
	for i in nv:
		norms[i] = wnorm[weld[i]]
	# Distance (m) from every vertex to the nearest region border: drives hems,
	# stitch lines, collar roll and the soft hairline in the shader.
	var edist := PackedFloat32Array()
	edist.resize(wn)
	edist.fill(0.08)
	for k in ne:
		if region[ea[k]] != region[eb[k]]:
			edist[ea[k]] = 0.0
			edist[eb[k]] = 0.0
	var elen := PackedFloat32Array()
	elen.resize(ne)
	for k in ne:
		elen[k] = wpos[ea[k]].distance_to(wpos[eb[k]])
	for it in 12:
		var changed := false
		for k in ne:
			var x := ea[k]
			var y := eb[k]
			var dd := elen[k]
			if edist[x] + dd < edist[y]:
				edist[y] = edist[x] + dd
				changed = true
			elif edist[y] + dd < edist[x]:
				edist[x] = edist[y] + dd
				changed = true
		if not changed:
			break
	# Region mean luminance -> per-vertex shading factor (baked folds / AO).
	var lsum := PackedFloat32Array()
	lsum.resize(8)
	var lcnt := PackedFloat32Array()
	lcnt.resize(8)
	var skin_sum := Vector3.ZERO
	var skin_n := 0.0
	var lum := PackedFloat32Array()
	lum.resize(wn)
	for w in wn:
		var l := col[w * 3] * 0.2126 + col[w * 3 + 1] * 0.7152 + col[w * 3 + 2] * 0.0722
		lum[w] = l
		lsum[region[w]] += l
		lcnt[region[w]] += 1.0
		if region[w] == R_FACE:
			var lin := Color(col[w * 3], col[w * 3 + 1], col[w * 3 + 2]).srgb_to_linear()
			if lin.r > lin.b * 1.2:
				skin_sum += Vector3(lin.r, lin.g, lin.b)
				skin_n += 1.0
	var src_skin := Vector3(0.55, 0.30, 0.19)
	if skin_n > 0.0:
		src_skin = skin_sum / skin_n
	# Output arrays (per original vertex) plus the hair shells.
	var grip_verts := 0
	var knuckle_x := 0.0
	var knuckle_n := 0.0
	var grip_centre := Vector3(0.0, -10.0, 0.0)
	var colors := PackedColorArray()
	colors.resize(nv)
	var c0 := PackedFloat32Array()
	c0.resize(nv * 4)
	var c1 := PackedFloat32Array()
	c1.resize(nv * 4)
	for i in nv:
		var w := weld[i]
		var r := int(region[w])
		if kinds[i] == 2:
			r = R_SHOE
		elif kinds[i] == 3:
			r = R_SOLE
		var mean := lsum[r] / maxf(lcnt[r], 1.0) if r < 8 else 1.0
		var shade := clampf(lum[w] / maxf(mean, 0.01), 0.55, 1.35) if r != R_SHOE and r != R_SOLE else 1.0
		colors[i] = Color(col[w * 3], col[w * 3 + 1], col[w * 3 + 2]).srgb_to_linear()
		c0[i * 4] = float(r)
		c0[i * 4 + 1] = 0.0
		c0[i * 4 + 2] = shade
		c0[i * 4 + 3] = edist[w]
		var v := verts[i]
		c1[i * 4] = v.x
		c1[i * 4 + 1] = v.y
		c1[i * 4 + 2] = v.z
		c1[i * 4 + 3] = 0.0
		if wrist != Vector3.INF and r == R_SKIN and v.x * signf(wrist.x) > 0.19 and v.y < wrist.y - GRIP_PALM and v.y > wrist.y - 0.26:
			c1[i * 4 + 3] = 1.0
			grip_verts += 1
			if v.y > wrist.y - GRIP_PALM - 0.015:
				knuckle_x += v.x
				knuckle_n += 1.0
	if knuckle_n > 0.0:
		grip_centre = Vector3(knuckle_x / knuckle_n - signf(wrist.x) * 0.016, wrist.y - GRIP_PALM, signf(wrist.x))
		print("[character-look] wrist ", wrist, " grip centre ", grip_centre, " knuckle verts ", knuckle_n)
	var hair_tris := PackedInt32Array()
	for t in nt:
		var ia := indices[t * 3]
		var ib := indices[t * 3 + 1]
		var ic := indices[t * 3 + 2]
		if int(c0[ia * 4]) == R_HAIR and int(c0[ib * 4]) == R_HAIR and int(c0[ic * 4]) == R_HAIR:
			hair_tris.append_array(PackedInt32Array([ia, ib, ic]))
	if hair_tris.size() > 0:
		var used := {}
		for i in hair_tris:
			used[i] = true
		var hair_verts: Array = used.keys()
		for s in range(1, SHELLS + 1):
			var remap := {}
			for i in hair_verts:
				remap[i] = verts.size()
				verts.append(verts[i])
				norms.append(norms[i])
				tangs.append_array(tangs.slice(i * 4, i * 4 + 4))
				uvs.append(uvs[i])
				bones.append_array(bones.slice(i * bpv, i * bpv + bpv))
				weights.append_array(weights.slice(i * bpv, i * bpv + bpv))
				colors.append(colors[i])
				c0.append_array(PackedFloat32Array([float(R_HAIR), float(s), c0[i * 4 + 2], c0[i * 4 + 3]]))
				c1.append_array(c1.slice(i * 4, i * 4 + 4))
			for i in hair_tris:
				indices.append(remap[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tangs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	if bpv == 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var material := ShaderMaterial.new()
	material.shader = shader()
	material.set_shader_parameter("albedo_tex", albedo)
	if normal != null:
		material.set_shader_parameter("normal_tex", normal)
	material.set_shader_parameter("src_skin", src_skin)
	material.set_shader_parameter("head_centre", head_centre)
	material.set_shader_parameter("nose_tip", nose_tip)
	material.set_shader_parameter("grip_centre", grip_centre)
	var dbg := OS.get_environment("ORCHARD_LOOK_DEBUG")
	if dbg != "":
		material.set_shader_parameter("debug_mode", int(dbg))
	var out: ArrayMesh = null
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, material, "Character", flags)
	im.generate_lods(25.0, 60.0, [])
	out = im.get_mesh()
	if out == null or out.get_surface_count() != 1:
		out = ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(0, material)
	var counts := PackedInt32Array()
	counts.resize(8)
	for w in wn:
		counts[region[w]] += 1
	return {"mesh": out, "material": material, "regions": counts, "shell_tris": hair_tris.size() / 3 * SHELLS, "src_skin": src_skin, "grip_verts": grip_verts, "grip_centre": grip_centre}

static func _skinlike(c: Color) -> bool:
	var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var sat := (mx - mn) / maxf(mx, 0.001)
	return c.r > c.g * 1.06 and c.r - c.b > 0.08 and l > 0.12 and sat > 0.14

## Region from the surface the provider authored (overshirt / shoe / sole),
## the atlas colour only for skin vs cloth, and the rest-pose geometry for
## the rest (the auto-UV atlas bleeds colours across islands).
static func _classify(c: Color, p: Vector3, kind: int, neck_c: Vector2 = Vector2(0.0, 0.03), neck_r: float = 0.0) -> int:
	if kind == 2:
		return R_SHOE
	if kind == 3:
		return R_SOLE
	var skin := _skinlike(c)
	if kind == 1:
		if skin and absf(p.x) > 0.2 and p.y < 1.25:
			return R_SKIN
		if p.y > 1.36 and Vector2(p.x, p.z).distance_to(neck_c) < neck_r and (skin or p.y > 1.44):
			return R_SKIN
		return R_SKIN if skin and p.y > 1.47 else R_SHIRT
	if p.y > 1.5:
		if skin:
			return R_FACE
		# Hair: above the front hairline or anywhere behind the face plane.
		if p.y > 1.665 or (p.z > -0.035 and p.y > 1.585) or (p.y > 1.585 and absf(p.x + 0.016) > 0.062):
			return R_HAIR
		return R_FACE
	if skin:
		return R_SKIN
	if absf(p.x) > 0.215 and p.y > 0.95 and p.y < 1.35:
		return R_SKIN # bare arms and hands (sleeves live on the overshirt surface)
	if p.y > 1.30:
		return R_SKIN # neck: the collar is authored on the overshirt surface
	if p.y > 0.95:
		return R_SHIRT
	return R_PANTS

## One majority pass: an isolated vertex takes its neighbours' region.
static func _majority(region: PackedByteArray, indices: PackedInt32Array, weld: PackedInt32Array, wn: int) -> void:
	var votes := PackedInt32Array()
	votes.resize(wn * 8)
	var nt := indices.size() / 3
	for t in nt:
		var wa := weld[indices[t * 3]]
		var wb := weld[indices[t * 3 + 1]]
		var wc := weld[indices[t * 3 + 2]]
		votes[wa * 8 + region[wb]] += 1; votes[wa * 8 + region[wc]] += 1
		votes[wb * 8 + region[wa]] += 1; votes[wb * 8 + region[wc]] += 1
		votes[wc * 8 + region[wa]] += 1; votes[wc * 8 + region[wb]] += 1
	var out := region.duplicate()
	for w in wn:
		var own := votes[w * 8 + region[w]]
		var best := int(region[w])
		var best_n := own
		var total := 0
		for r in 8:
			var n := votes[w * 8 + r]
			total += n
			if n > best_n:
				best_n = n
				best = r
		if total > 0 and own * 3 < total and best != R_SHOE and best != R_SOLE:
			out[w] = best
	for w in wn:
		region[w] = out[w]

# --- Wardrobe ---------------------------------------------------------------
# sRGB authoring values; converted to linear for the instance parameters.
const SHIRTS := [
	Color(0.10, 0.14, 0.27), Color(0.80, 0.80, 0.78), Color(0.55, 0.68, 0.84), Color(0.45, 0.10, 0.13),
	Color(0.80, 0.62, 0.20), Color(0.08, 0.40, 0.42), Color(0.88, 0.56, 0.62), Color(0.07, 0.07, 0.08),
	Color(0.72, 0.13, 0.11), Color(0.52, 0.52, 0.53), Color(0.16, 0.30, 0.20), Color(0.62, 0.56, 0.78),
	Color(0.80, 0.40, 0.14), Color(0.84, 0.79, 0.66), Color(0.26, 0.36, 0.54), Color(0.84, 0.70, 0.27),
]
const PANTS := [
	Color(0.11, 0.15, 0.26), Color(0.06, 0.06, 0.07), Color(0.62, 0.54, 0.40), Color(0.20, 0.20, 0.22),
	Color(0.36, 0.46, 0.60), Color(0.76, 0.70, 0.57), Color(0.09, 0.10, 0.20), Color(0.40, 0.30, 0.22),
]
const TEES := [Color(0.92, 0.92, 0.90), Color(0.08, 0.08, 0.09), Color(0.55, 0.55, 0.56), Color(0.85, 0.80, 0.70)]
const SKINS := [
	Color(0.90, 0.74, 0.62), Color(0.84, 0.64, 0.50), Color(0.74, 0.54, 0.40), Color(0.64, 0.44, 0.31),
	Color(0.54, 0.36, 0.25), Color(0.43, 0.28, 0.19), Color(0.33, 0.21, 0.14),
]
const HAIRS := [Color(0.05, 0.045, 0.04), Color(0.10, 0.07, 0.05), Color(0.20, 0.13, 0.08), Color(0.03, 0.03, 0.03), Color(0.30, 0.13, 0.07)]
const SHOES := [Color(0.88, 0.88, 0.86), Color(0.07, 0.07, 0.08), Color(0.30, 0.18, 0.10), Color(0.45, 0.45, 0.47), Color(0.12, 0.16, 0.30), Color(0.70, 0.14, 0.12)]

static func _lin(c: Color) -> Color:
	return c.srgb_to_linear()

static func _v4(c: Color, w: float) -> Vector4:
	var l := c.srgb_to_linear()
	return Vector4(l.r, l.g, l.b, w)

## Player: olive brushed-flannel check overshirt (dark bands, rust and
## cream over-check, chest pockets), dark indigo jeans, brown leather shoes,
## a warm tan (not orange) skin tone, short black hair and two-day stubble.
static func player_outfit() -> Dictionary:
	return {
		"shirt_col": _v4(Color(0.36, 0.37, 0.26), 5.0),
		"shirt_col2": _v4(Color(0.40, 0.15, 0.09), 1.0),
		"tee_col": _v4(Color(0.66, 0.66, 0.64), 0.0),
		"pants_col": _v4(Color(0.11, 0.14, 0.24), 0.0),
		"shoe_col": _v4(Color(0.26, 0.16, 0.09), 0.16),
		"skin_col": Vector4(_lin(Color(0.74, 0.56, 0.45)).r, _lin(Color(0.74, 0.56, 0.45)).g, _lin(Color(0.74, 0.56, 0.45)).b, 0.0),
		"hair_col": _v4(Color(0.05, 0.045, 0.04), 0.0),
		"face_col": Vector4(0.85, 0.8, 0.6, 1.0),
	}

## Deterministic civilian outfit and build for a seed. Never the player's
## olive check overshirt with dark jeans.
static func civilian_outfit(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 2654435761 + 1013904223)
	var shirt: Color = SHIRTS[rng.randi() % SHIRTS.size()]
	var shirt2: Color = SHIRTS[rng.randi() % SHIRTS.size()]
	if shirt2.is_equal_approx(shirt):
		shirt2 = Color(0.95, 0.95, 0.93) if shirt.get_luminance() < 0.5 else Color(0.08, 0.10, 0.18)
	var roll := rng.randf()
	var pattern := 0
	if roll < 0.14: pattern = 1
	elif roll < 0.26: pattern = 2
	elif roll < 0.40: pattern = 3
	elif roll < 0.52: pattern = 4
	elif roll < 0.66: pattern = 5
	var scale: float = [0.0, rng.randf_range(9.0, 16.0), rng.randf_range(6.0, 11.0), rng.randf_range(5.0, 8.0), 0.0, rng.randf_range(0.7, 1.3)][pattern]
	var tee_only := 1.0 if rng.randf() < 0.32 else 0.0
	var tee: Color = TEES[rng.randi() % TEES.size()]
	if tee_only > 0.5:
		tee = shirt
	var pants: Color = PANTS[rng.randi() % PANTS.size()]
	var shorts := 1.0 if rng.randf() < 0.16 else 0.0
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var elder := rng.randf() < 0.18
	var hair: Color = HAIRS[rng.randi() % HAIRS.size()]
	var shoe: Color = SHOES[rng.randi() % SHOES.size()]
	var girth := rng.randf_range(-0.25, 0.35)
	if rng.randf() < 0.22:
		girth = rng.randf_range(0.55, 1.0)
	var stubble := rng.randf_range(0.5, 1.0) if rng.randf() < 0.35 else 0.0
	return {
		"shirt_col": _v4(shirt, float(pattern)),
		"shirt_col2": _v4(shirt2, scale),
		"tee_col": _v4(tee, tee_only),
		"pants_col": _v4(pants, shorts),
		"shoe_col": _v4(shoe, 0.75 if shoe.get_luminance() > 0.5 or rng.randf() < 0.5 else 0.12),
		"skin_col": Vector4(_lin(skin).r, _lin(skin).g, _lin(skin).b, girth),
		"hair_col": _v4(hair, (rng.randf_range(0.55, 1.0) if elder else 0.0) + (2.0 if rng.randf() < 0.2 else 0.0)),
		"face_col": Vector4(stubble, rng.randf_range(0.3, 1.0) if elder else rng.randf_range(0.1, 0.5), rng.randf_range(0.3, 0.9), 1.0 if rng.randf() < 0.5 else 0.0),
		"height": rng.randf_range(0.93, 1.06) * (0.97 if elder else 1.0),
	}

## The headless (dummy) renderer re-parses the shader on every per-instance
## parameter write (~45 ms each), so headless runs keep the outfit data on the
## CharacterVisual only; nothing is drawn there anyway.
static var _headless := DisplayServer.get_name() == "headless"

static func set_outfit(mi: MeshInstance3D, outfit: Dictionary) -> void:
	if _headless:
		return
	for key in ["shirt_col", "shirt_col2", "tee_col", "pants_col", "shoe_col", "skin_col", "hair_col", "face_col"]:
		if outfit.has(key):
			mi.set_instance_shader_parameter(key, outfit[key])

## Per-frame grip update (player): curl amount and the hand bone's
## rest->pose rotation in skeleton (= mesh) space.
static func set_grip(mi: MeshInstance3D, skeleton: Skeleton3D, bone: int, amount: float) -> void:
	if _headless or mi == null or skeleton == null or bone < 0:
		return
	var b := skeleton.get_bone_global_pose(bone).basis * skeleton.get_bone_global_rest(bone).basis.inverse()
	mi.set_instance_shader_parameter("grip", Vector4(amount, 0.0, 0.0, 0.0))
	mi.set_instance_shader_parameter("hand_x", Vector4(b.x.x, b.x.y, b.x.z, 0.0))
	mi.set_instance_shader_parameter("hand_y", Vector4(b.y.x, b.y.y, b.y.z, 0.0))
	mi.set_instance_shader_parameter("hand_z", Vector4(b.z.x, b.z.y, b.z.z, 0.0))

## A short signature of an outfit, used by the regression to count distinct looks.
static func outfit_signature(outfit: Dictionary) -> String:
	var parts := []
	for key in ["shirt_col", "tee_col", "pants_col", "skin_col"]:
		var v: Vector4 = outfit[key]
		parts.append("%d,%d,%d,%d" % [int(v.x * 20), int(v.y * 20), int(v.z * 20), int(v.w)])
	return "|".join(parts)
