class_name CharacterLook
extends RefCounted
## Characters piece (wave D): close-range fidelity and crowd variety for the
## provider humanoid (player + civilian rigs).
##
## The provider body is a voxel remesh with an auto-UV atlas of hundreds of
## tiny islands whose baked colours disagree. At load time this rebuilds the
## skinned mesh once per rig:
##   * every vertex is classified into a body region (skin, face, hair,
##     overshirt, tee, trousers, shoe, sole) from mip-0 atlas samples, the
##     provider surface and its rest position;
##   * the body is a triangle soup (corners not shared), so copies are
##     tolerance-welded, and normals, garment weights and skin weights are
##     smoothed SPATIALLY (radius kernels), not over the broken topology;
##   * region weights are diffused across the mesh (CUSTOM2) and the shader
##     picks the dominant one per FRAGMENT, so every garment border is a
##     smooth curve, never a stair of whole triangles; hair follows the
##     atlas's own painted hairline and nape taper;
##   * the rest position (CUSTOM1) and rest normal (CUSTOM3) drive UV-free
##     triplanar fabric scans (flannel, denim, batik, jersey), folds, seams,
##     skin pores and hair strands; hair shells break up the silhouette;
##   * player only: the mitten finger block is folded onto the knuckle line
##     and CharacterHands draws jointed fingers;
##   * all surfaces merge into one draw call with generated LODs.
## Outfits, skin tone, hair colour and body build are per-instance shader
## parameters on one shared material, so a crowd of 140 stays one material.

const SHELLS := 4
## Wrist-to-knuckle distance (m) along the provider hand bone.
const KNUCKLE_Y := 0.082
const THUMB_Z := 0.042
const WELD_TOL := 0.0016
const NORMAL_RADIUS := 0.014
const WEIGHT_RADIUS := 0.02
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
stencil_mode write, compare_always, 8; // street weathering volumes skip people

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
// Woven fabric detail (Higgsfield set, private build), mapped triplanar in
// rest space so the pattern sticks to the body through every pose.
uniform sampler2D flannel_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D denim_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D batik_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D jersey_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_fabrics = false;
uniform vec3 src_skin = vec3(0.5, 0.3, 0.2);
uniform float src_hair_lum = 0.02;
uniform vec3 head_centre = vec3(0.0, 1.62, 0.0);
uniform vec3 nose_tip = vec3(-0.016, 1.575, -0.089);
uniform float placket_x = 0.004;
uniform float shell_step = 0.0022;
uniform float near_fade = 0.6;
uniform int debug_mode = 0; // QA only: 1 flat grey albedo, 2 region colours, 4 normals

// Per-instance wardrobe (linear colours). w channels carry extra parameters.
instance uniform vec4 shirt_col = vec4(0.07, 0.065, 0.035, 0.0); // w: pattern id
instance uniform vec4 shirt_col2 = vec4(0.2, 0.2, 0.2, 9.0);   // w: pattern scale
instance uniform vec4 tee_col = vec4(0.33, 0.33, 0.31, 0.0);    // w: 1 = no overshirt (plain tee)
instance uniform vec4 pants_col = vec4(0.010, 0.016, 0.040, 0.0); // w: 1 = shorts, 2 = authored denim
instance uniform vec4 shoe_col = vec4(0.030, 0.014, 0.007, 0.25); // w: sole value
instance uniform vec4 skin_col = vec4(-1.0, 0.0, 0.0, 0.0);      // x<0: authored tone; w: girth
instance uniform vec4 hair_col = vec4(0.004, 0.003, 0.0025, 0.0); // w: grey amount (+2 = clipper cut)
instance uniform vec4 face_col = vec4(0.0, 0.5, 0.5, 0.0);       // x: stubble, y: creases, z: flush, w: pockets
// Wave R: per-person head build (-1..1): x jaw + cheek fullness, y nose
// size, z brow ridge / forehead; w hair volume (0 = authored, else 0.4..2).
instance uniform vec4 head_shape = vec4(0.0, 0.0, 0.0, 0.0);

varying flat int v_kind;
varying vec3 v_rest;
varying vec4 v_data;
varying vec4 v_rw;
varying vec3 v_rn;
// Wave R: how far the skinned normal has turned from the rest normal (0 at
// rest): bent shoulders, hips and knees bunch their cloth into deeper folds.
varying float v_bend;
// Fragment -> light(): wrap (skin translucency), gloss and specular level.
varying float l_wrap;
varying float l_rough;
varying float l_spec;

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
float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}
// Anti-aliased thin line at |d| < w (d in metres).
float line_aa(float d, float w) {
	float fw = max(fwidth(d), 0.00001);
	return 1.0 - smoothstep(w - fw, w + fw, abs(d));
}
float tband(float t, float period, float off, float w) {
	float d = abs(fract(t / period - off + 0.5) - 0.5) * period;
	float fw = max(fwidth(t), 0.00001);
	return 1.0 - smoothstep(w * 0.5 - fw, w * 0.5 + fw, d);
}
// Triplanar fabric sample in rest space; tile in metres, hs stretches the
// horizontal axis (the flannel period crop is 1.72x wide).
vec3 tri(sampler2D t, vec3 p, vec3 w, float tile, float hs) {
	vec3 a = texture(t, vec2(p.z * hs, -p.y) / tile).rgb;
	vec3 b = texture(t, vec2(p.x * hs, p.z) / tile).rgb;
	vec3 c = texture(t, vec2(p.x * hs, -p.y) / tile).rgb;
	return a * w.x + b * w.y + c * w.z;
}

void vertex() {
	v_kind = int(CUSTOM0.x + 0.5);
	v_rest = CUSTOM1.xyz;
	v_data = CUSTOM0;
	v_rw = CUSTOM2;
	v_rn = CUSTOM3.xyz;
	v_bend = clamp(1.0 - dot(normalize(NORMAL), normalize(CUSTOM3.xyz + vec3(0.0, 0.0, 0.00001))), 0.0, 1.0);
	// Body build: belly/chest girth pushes the torso out along its normal.
	vec3 r = CUSTOM1.xyz;
	float band = smoothstep(0.84, 1.02, r.y) * (1.0 - smoothstep(1.20, 1.44, r.y));
	float core = 1.0 - smoothstep(0.15, 0.25, abs(r.x));
	float front = mix(0.55, 1.0, smoothstep(-0.02, 0.10, -r.z));
	VERTEX += NORMAL * skin_col.w * 0.055 * band * core * front;
	// Head build: the skinned head moves rigidly, so a push along the
	// skinned normal masked in rest space reshapes it per person (one mesh,
	// many faces): jaw and cheeks, nose, brow ridge, hair mass.
	vec3 rl = r - nose_tip;
	float headk = smoothstep(1.44, 1.48, r.y);
	float facing = 1.0 - smoothstep(0.03, 0.09, rl.z);
	float ax = abs(rl.x);
	float jaw = smoothstep(-0.115, -0.085, rl.y) * (1.0 - smoothstep(-0.035, -0.005, rl.y)) * smoothstep(0.015, 0.05, ax) * (1.0 - smoothstep(0.06, 0.11, rl.z));
	float cheek = 1.0 - smoothstep(0.012, 0.034, length(vec2(ax - 0.044, rl.y + 0.004)));
	float nose = (1.0 - smoothstep(0.006, 0.026, length(vec2(rl.x, rl.y + 0.008)))) * facing;
	float brow = (1.0 - smoothstep(0.006, 0.016, abs(rl.y - 0.056))) * (1.0 - smoothstep(0.045, 0.068, ax)) * facing;
	float hv = head_shape.w > 0.0 ? head_shape.w : 1.0;
	float hairm = smoothstep(0.4, 0.8, CUSTOM2.z) * smoothstep(1.56, 1.62, r.y);
	VERTEX += NORMAL * headk * (head_shape.x * (0.0085 * jaw + 0.0045 * cheek * facing) + head_shape.y * 0.0042 * nose
		+ head_shape.z * 0.0032 * brow + (hv - 1.0) * 0.006 * hairm);
	if (CUSTOM0.y > 0.5) {
		VERTEX += NORMAL * CUSTOM0.y * shell_step * hv;
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
	vec3 p = v_rest;
	float shell = v_data.y;
	float shade = clamp(v_data.z, 0.7, 1.25);
	float px = length(fwidth(p));
	float fine_k = 1.0 - smoothstep(0.0012, 0.004, px);
	float mid_k = 1.0 - smoothstep(0.004, 0.014, px);
	vec3 skin_tone = skin_col.x < 0.0 ? src_skin : skin_col.rgb;
	float az = atan(p.x, p.z);
	float u = az * 0.17;
	vec3 rn = normalize(v_rn + vec3(0.0, 0.0, 0.00001));
	vec3 tw3 = pow(abs(rn), vec3(4.0));
	tw3 /= max(tw3.x + tw3.y + tw3.z, 0.0001);
	// Region per FRAGMENT: the dominant of the smoothly interpolated
	// (pre-diffused) garment weights, so every border is a smooth curve
	// through the triangles instead of a stair of whole triangles.
	int reg = v_kind;
	float e = v_data.w;
	if (reg < 5) {
		float ws[5] = float[](v_rw.x, v_rw.y, v_rw.z, v_rw.w, max(1.0 - v_rw.x - v_rw.y - v_rw.z - v_rw.w, 0.0));
		int ra = 0;
		float wa = -1.0;
		float wb = -1.0;
		for (int i = 0; i < 5; i++) {
			if (ws[i] > wa) {
				wb = wa;
				wa = ws[i];
				ra = i;
			} else if (ws[i] > wb) {
				wb = ws[i];
			}
		}
		int map5[5] = int[](0, 1, 2, 4, 3);
		reg = map5[ra];
		float m = wa - wb;
		e = m < 0.98 ? m * 0.03 : max(v_data.w, 0.03);
	}
	// Authored atlas at a low mip only (island colours bleed in the mip chain).
	vec2 tsz = vec2(textureSize(albedo_tex, 0));
	vec2 duv = max(abs(dFdx(UV)), abs(dFdy(UV))) * tsz;
	float lod = clamp(log2(max(max(duv.x, duv.y), 1.0)), 0.0, 1.5);
	vec3 tex = textureLod(albedo_tex, UV, lod).rgb;
	float tl = lum(tex);
	float sl = lum(src_skin);
	vec3 rel = p - nose_tip;
	// Head: hair follows the authored atlas (its painted hairline, sideburns
	// and the nape taper), never a geometric cap.
	float hairness = 0.0;
	if ((reg == 0 || reg == 2) && p.y > 1.46) {
		float dark = 1.0 - smoothstep(0.22 * sl, 0.5 * sl, tl);
		float facebox = (1.0 - smoothstep(0.052, 0.062, abs(rel.x))) * (1.0 - smoothstep(0.072, 0.082, rel.y)) * (1.0 - smoothstep(0.04, 0.05, rel.z));
		hairness = dark * (1.0 - facebox) * smoothstep(1.46, 1.50, p.y);
		hairness = max(hairness, smoothstep(1.695, 1.72, p.y));
		if (p.z - head_centre.z > 0.02) {
			// Back of the head: no stray skin islands inside the hair mass.
			hairness = max(hairness, smoothstep(1.60, 1.63, p.y));
		}
		// No long sideburn spikes down the cheek in front of the ear.
		hairness *= 1.0 - (1.0 - smoothstep(1.585, 1.615, p.y)) * (1.0 - smoothstep(0.085, 0.10, rel.z));
		// Wave R: dark atlas texels on the front and sides of the neck are the
		// collar's shadow, not hair (they cut a black notch above the collar).
		hairness *= mix(smoothstep(1.515, 1.55, p.y), 1.0, smoothstep(0.01, 0.05, p.z - head_centre.z));
		hairness = clamp(hairness + (vnoise(p * 260.0) - 0.5) * 0.25, 0.0, 1.0);
		reg = hairness > 0.5 ? 2 : 0;
	} else if (reg == 2) {
		reg = 0;
	}
	if (shell > 0.5 && reg != 2) {
		discard;
	}
	vec3 col = vec3(0.5);
	float rough = 0.85;
	float spec = 0.3;
	float h = 0.0;
	float sss = 0.0;
	float rim = 0.0;
	float ao = 1.0;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	float nmap_depth = 0.0;
	if (reg == 4 && abs(pants_col.w - 1.0) < 0.5 && p.y < 0.50) {
		reg = 0; // shorts: bare lower legs
	}
	bool tee_only = false;
	if (reg == 1 && tee_col.w > 0.5) {
		reg = 3; // plain tee, no overshirt
		tee_only = true;
	}
	if (reg == 0) {
		// Skin (body and face share one tone model; the face features fade in
		// above the jaw so there is no seam at the neck).
		float face_k = smoothstep(1.47, 1.52, p.y);
		float tone = fbm(p * 14.0);
		col = skin_tone * (0.95 + 0.08 * tone);
		col *= mix(vec3(1.0), vec3(1.04, 0.97, 0.95), smoothstep(0.55, 0.85, vnoise(p * 26.0)) * 0.5);
		col *= 0.96 + 0.08 * vnoise(p * 140.0);
		// Wave R: uneven living skin, not one waxy tone: mottled redness,
		// freckle-scale pigment and a broken-up sheen.
		float blot = fbm(p * 55.0);
		col *= mix(vec3(1.0), vec3(1.07, 0.93, 0.92), smoothstep(0.5, 0.78, blot) * 0.7);
		col *= 1.0 - 0.07 * smoothstep(0.62, 0.8, vnoise(p * 320.0)) * mid_k;
		rough = 0.46 + 0.26 * fbm(p * 120.0);
		spec = 0.33;
		sss = 0.2;
		h = (vnoise(p * 520.0) - 0.5) * 0.0002 * fine_k + (vnoise(p * 140.0) - 0.5) * 0.00025 * mid_k;
		rim = 0.12;
		if (face_k > 0.0) {
			vec3 ratio = skin_tone / max(src_skin, vec3(0.002));
			float feature = (1.0 - smoothstep(0.05, 0.06, abs(rel.x))) * step(-0.045, rel.y) * step(rel.y, 0.078) * step(rel.z, 0.035);
			float eyes = (1.0 - smoothstep(0.05, 0.06, abs(rel.x))) * smoothstep(0.028, 0.036, rel.y) * (1.0 - smoothstep(0.046, 0.054, rel.y)) * step(rel.z, 0.03);
			float mouth = (1.0 - smoothstep(0.024, 0.032, abs(rel.x))) * (1.0 - smoothstep(0.007, 0.012, abs(rel.y + 0.029)));
			float dark_feat = feature * (1.0 - smoothstep(0.45, 0.8, tl / max(sl, 0.001))) * (1.0 - smoothstep(0.072, 0.078, rel.y));
			// The authored face paint carries its modelled shading (sockets,
			// cheekbones, lips): blend it over the procedural tone, features fully.
			float face_box = (1.0 - smoothstep(0.06, 0.085, abs(rel.x))) * smoothstep(-0.11, -0.09, rel.y) * (1.0 - smoothstep(0.1, 0.12, rel.y)) * (1.0 - smoothstep(0.05, 0.08, rel.z));
			float use_tex = clamp(max(max(max(eyes * 0.9, mouth * 0.75), dark_feat), face_box * 0.55), 0.0, 1.0) * face_k * (1.0 - hairness);
			col = mix(col, tex * ratio * 0.95, use_tex);
			col = mix(col, col * vec3(0.93, 0.74, 0.72), mouth * 0.45 * face_k);
			float fk = face_k * (1.0 - hairness);
			float cheek = (1.0 - smoothstep(0.015, 0.035, length(vec2(abs(rel.x) - 0.045, rel.y - 0.01)))) + (1.0 - smoothstep(0.004, 0.016, length(rel.xy)));
			col *= mix(vec3(1.0), vec3(1.07, 0.93, 0.91), clamp(cheek, 0.0, 1.0) * face_col.z * fk);
			float under_eye = (1.0 - smoothstep(0.006, 0.012, abs(rel.y - 0.036))) * smoothstep(0.012, 0.02, abs(rel.x)) * (1.0 - smoothstep(0.045, 0.055, abs(rel.x)));
			col *= mix(vec3(1.0), vec3(0.86, 0.84, 0.88), under_eye * 0.7 * fk);
			// Eye sockets and upper lids: a soft occlusion band reads as a brow ridge.
			float socket = (1.0 - smoothstep(0.008, 0.016, abs(rel.y - 0.047))) * smoothstep(0.008, 0.016, abs(rel.x)) * (1.0 - smoothstep(0.05, 0.06, abs(rel.x)));
			ao *= 1.0 - 0.3 * socket * fk;
			// Stubble: jaw, chin and upper lip (lips themselves excluded).
			float jy = -0.008 - 0.2 * abs(rel.x);
			float jaw = (1.0 - smoothstep(jy - 0.014, jy + 0.004, rel.y)) * smoothstep(-0.1, -0.086, rel.y) * (1.0 - smoothstep(0.065, 0.085, abs(rel.x)));
			float lips = (1.0 - smoothstep(0.022, 0.03, abs(rel.x))) * (1.0 - smoothstep(0.006, 0.01, abs(rel.y + 0.029)));
			float stub_mask = jaw * (1.0 - lips) * face_col.x * fk;
			float dots = smoothstep(0.45, 0.75, hash13(floor(p * 1400.0)));
			float stub = stub_mask * mix(0.5, 0.25 + 0.75 * dots, fine_k);
			col = mix(col, col * vec3(0.34, 0.33, 0.36), stub * 0.8);
			// Expression creases: nasolabial folds and forehead lines.
			vec2 a = vec2(0.022, -0.004);
			vec2 b = vec2(0.033, -0.036);
			vec2 q = vec2(abs(rel.x), rel.y);
			float tseg = clamp(dot(q - a, b - a) / dot(b - a, b - a), 0.0, 1.0);
			float dl = length(q - (a + (b - a) * tseg));
			float crease = (1.0 - smoothstep(0.0012, 0.0045, dl)) * face_col.y * fk;
			float fh = (1.0 - smoothstep(0.03, 0.05, abs(rel.x))) * step(0.085, rel.y) * step(rel.y, 0.125);
			float flines = fh * line_aa(fract((rel.y - 0.085) / 0.012) - 0.5, 0.08) * face_col.y * 0.5 * fk;
			ao *= 1.0 - 0.35 * crease - 0.2 * flines;
			col *= 1.0 - 0.18 * crease - 0.1 * flines;
			float sk = smoothstep(0.02, 0.07, dot(tex, vec3(0.33)));
			rough = mix(rough, mix(0.6, 0.38 + 0.22 * vnoise(p * 180.0), sk), face_k);
			rough = mix(rough, 0.32, (1.0 - smoothstep(0.0, 0.03, length(rel.xy))) * 0.6 * fk); // oily nose
			spec = mix(spec, 0.42, face_k);
			sss = mix(sss, 0.38 * sk, face_k);
			nmap = texture(normal_tex, UV).rgb;
			nmap_depth = 0.45 * smoothstep(1.53, 1.57, p.y) * (1.0 - hairness);
			h += stub * (dots - 0.5) * 0.00025 * fine_k + (vnoise(p * 900.0) - 0.5) * 0.00012 * fine_k * face_k - crease * 0.0009 - flines * 0.0003;
		}
	} else if (reg == 2) {
		vec3 q = p - head_centre;
		float qa = atan(q.x, q.z);
		float pol = acos(clamp(q.y / max(length(q), 0.001), -1.0, 1.0));
		float warp = vnoise(vec3(qa * 3.0, pol * 4.0, 1.7)) * 1.6;
		float clump = vnoise(vec3(qa * 18.0 + warp, pol * 2.4, 3.1));
		float strand = vnoise(vec3(qa * 170.0 + warp * 9.0, pol * 6.0, 9.7));
		float strand2 = vnoise(vec3(qa * 420.0 + warp * 20.0, pol * 9.0, 2.3));
		float m = strand * 0.45 + strand2 * 0.2 + clump * 0.35;
		float edge = smoothstep(0.5, 0.95, hairness);
		if (shell > 0.5) {
			float cut = 0.3 + 0.13 * shell + (ign - 0.5) * 0.16 + (1.0 - edge) * 0.5;
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
		// The authored strand shading survives as a luminance ratio.
		float authored = clamp(tl / max(src_hair_lum, 0.0005), 0.6, 1.7);
		hc *= mix(vec3(1.0), vec3(1.45, 1.22, 1.0), smoothstep(0.6, 0.9, clump) * 0.5); // warm sun-bleached clumps
		col = hc * mix(1.0, authored, 0.6) * (0.55 + 0.6 * strand) * (0.8 + 0.35 * clump) * (0.85 + 0.25 * strand2) * mix(0.8, 1.12, shell / 4.0);
		if (buzz > 0.5) {
			// Clipper cut: scalp tone under dense short stubble.
			float sd = smoothstep(0.35, 0.7, hash13(floor(p * 1300.0)));
			col = mix(skin_tone * 0.7, hair_col.rgb, mix(0.55, 0.3 + 0.6 * sd, fine_k) * edge);
		} else if (shell < 0.5) {
			// Short fade into the skin at the hairline and the nape.
			col = mix(mix(skin_tone * 0.6, hair_col.rgb, 0.55), col, edge);
		}
		rough = 0.36 + 0.28 * (1.0 - strand);
		spec = 0.5;
		h = (strand * 0.5 + strand2 * 0.2 + clump * 0.3) * 0.0014 * mid_k;
		rim = 0.3;
		ao = mix(0.75, 1.0, shell / 4.0);
	} else if (reg == 1 || reg == 3) {
		int pat = int(shirt_col.w + 0.5);
		float s = shirt_col2.w;
		vec3 base = reg == 1 ? shirt_col.rgb : tee_col.rgb;
		col = base;
		float fab_h = 0.0;
		if (reg == 1 || tee_only) {
			if (has_fabrics && (pat == 5 || pat == 7)) {
				vec3 fl = tri(flannel_tex, p, tw3, 0.30, 1.72);
				if (pat == 7) {
					col = fl * 0.95;
				} else {
					// Recoloured flannel: dark/light bands take the wardrobe pair,
					// the authored red over-check stays as an accent.
					float l = lum(fl) / 0.126;
					float red = smoothstep(0.03, 0.09, fl.r - fl.g);
					col = mix(base * 0.55, shirt_col2.rgb, smoothstep(0.9, 1.9, l)) * clamp(l, 0.55, 1.5);
					col = mix(col, vec3(0.32, 0.05, 0.03), red * 0.7);
				}
				fab_h = lum(fl) / 0.126;
			} else if (has_fabrics && pat == 3) {
				vec3 bt = tri(batik_tex, p, tw3, 0.34, 1.0);
				col = bt * mix(vec3(1.0), base / max(lum(base), 0.02) * 0.2, 0.35);
				fab_h = lum(bt) / 0.148;
			} else if (pat == 1) {
				float fu = fract(u * s);
				float st = smoothstep(0.55, 0.6, fu) - smoothstep(0.85, 0.9, fu);
				col = mix(col, shirt_col2.rgb, mix(0.3, st, mid_k));
			} else if (pat == 2) {
				float ga = tband(p.x * tw3.z + p.z * tw3.x, 1.0 / s, 0.0, 0.5 / s);
				float gb = tband(p.y, 1.0 / s, 0.0, 0.5 / s);
				col = mix(col, shirt_col2.rgb, (ga * 0.5 + gb * 0.5));
			} else if (pat == 4) {
				col = mix(col, shirt_col2.rgb, smoothstep(1.43, 1.46, p.y));
			}
		}
		if (has_fabrics && fab_h == 0.0) {
			// Plain cotton: knit detail from the neutral jersey map.
			float jn = lum(tri(jersey_tex, p, tw3, 0.16, 1.0)) / 0.618;
			col *= mix(1.0, jn, 0.55);
			fab_h = jn;
		}
		col *= 0.97 + 0.06 * (vnoise(p * 40.0) - 0.5);
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
		float bendk = smoothstep(0.02, 0.35, v_bend);
		// Pose: a raised or swung arm drags deeper creases from the armpit
		// and across the sleeve; a twisted torso folds at the waist.
		float pose_amp = 1.0 + 1.6 * bendk;
		f3 *= pose_amp;
		f4 *= pose_amp;
		float folds = (f1 * 0.0034 + f2 * 0.0026 + f3 * 0.0024 + f4 * 0.0026 + f5 * 0.0012) * amp * mid_k;
		float cavity = clamp(-(f1 * waist + f2 * drape * 0.8 + f3 * sleeve + f4 * armpit), 0.0, 1.0);
		float ridge = clamp(f1 * waist + f2 * drape * 0.8 + f3 * sleeve + f4 * armpit, 0.0, 1.0);
		ao *= 1.0 - 0.32 * cavity * amp;
		// Folds must read in direct sun too (AO only darkens ambient light).
		col *= (1.0 - 0.26 * cavity * amp) * (1.0 + 0.08 * ridge * amp);
		h = folds + (fab_h - 1.0) * 0.00022 * fine_k;
		// Construction: hems with a stitch line along every garment border.
		float hem = 1.0 - smoothstep(0.016, 0.021, e);
		float dash = step(0.38, fract((p.x + p.y * 1.3 + p.z) / 0.0042));
		float stitch = line_aa(e - 0.011, 0.0006) * dash * fine_k;
		h += hem * 0.0007 + (1.0 - smoothstep(0.0, 0.004, e)) * 0.0008;
		ao *= 1.0 - 0.12 * hem;
		vec3 thread = mix(col, col * 1.6 + vec3(0.015), 0.6);
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
			float pk_st = 0.0;
			float flap_sh = 0.0;
			if (face_col.w > 0.5) {
				for (int side = -1; side <= 1; side += 2) {
					float dx = xp - float(side) * 0.088;
					float inside = step(abs(dx), 0.05) * step(1.235, p.y) * step(p.y, 1.36);
					float de = min(0.05 - abs(dx), min(p.y - 1.235, 1.36 - p.y));
					pk_st += inside * line_aa(de - 0.004, 0.0005);
					float flap = step(abs(dx), 0.053) * step(1.322, p.y) * step(p.y, 1.37);
					float fde = min(0.053 - abs(dx), min(p.y - 1.322, 1.37 - p.y));
					pk_st += flap * line_aa(fde - 0.0035, 0.0005);
					flap_sh += step(abs(dx), 0.053) * (1.0 - smoothstep(0.0, 0.007, 1.322 - p.y)) * step(p.y, 1.322);
					h += flap * 0.0011 + inside * 0.0005;
					float pbd = length(vec2(dx, p.y - 1.331));
					btn = max(btn, (1.0 - smoothstep(0.0042, 0.0052, pbd)) * front);
				}
				pk_st *= front * mid_k;
				flap_sh *= front;
			}
			ao *= 1.0 - 0.45 * flap_sh;
			col *= 1.0 - 0.25 * flap_sh;
			float arm_seam = line_aa(abs(p.x) - 0.188, 0.0009) * step(1.2, p.y);
			float side_seam = line_aa(p.z - 0.025, 0.0009) * smoothstep(0.5, 0.8, tw3.x) * step(abs(p.x), 0.18);
			float yoke = line_aa(p.y - 1.395, 0.0009) * back;
			float seams = clamp(arm_seam + side_seam + yoke, 0.0, 1.0);
			ao *= 1.0 - 0.35 * seams;
			h -= seams * 0.0006;
			stitch = clamp(stitch + (plk_st + pk_st), 0.0, 1.0);
			col = mix(col, thread, stitch * 0.8);
			vec3 bcol = vec3(0.13, 0.09, 0.055);
			float holes = (1.0 - smoothstep(0.0006, 0.0011, length(vec2(abs(xp + 0.0005) - 0.0016, p.y - yb)))) * front;
			col = mix(col, bcol, btn);
			col = mix(col, bcol * 0.3, holes * btn);
			h += btn * 0.0012 * (1.0 - bd / 0.006);
			rough = mix(rough, 0.35, btn);
		} else {
			col = mix(col, thread, stitch * 0.6);
		}
		col = min(col * mix(1.0, shade, 0.2), vec3(0.6));
		rough = reg == 1 ? 0.86 + 0.08 * vnoise(p * 90.0) : 0.9;
		spec = 0.26;
		rim = 0.16;
	} else if (reg == 4) {
		float dl = 1.0;
		if (has_fabrics) {
			vec3 dn = tri(denim_tex, p, tw3, 0.2, 1.0);
			dl = lum(dn) / 0.133;
			if (pants_col.w > 1.5) {
				col = dn * 0.95;
			} else {
				col = pants_col.rgb * clamp(mix(1.0, dl, 0.75), 0.55, 1.5);
			}
		} else {
			col = pants_col.rgb;
			float tw = sin(((p.x * tw3.z + p.z * tw3.x) + p.y) * 1900.0) * 0.5 + 0.5;
			col *= mix(1.0, 0.86 + 0.24 * tw, fine_k);
		}
		col *= mix(1.0, shade, 0.2);
		float wear = smoothstep(0.45, 0.85, vnoise(vec3(p.x * 30.0, p.y * 5.0, p.z * 30.0))) * (smoothstep(0.35, 0.55, p.y) - smoothstep(0.62, 0.8, p.y) * 0.5);
		col = mix(col, col * 1.45 + vec3(0.01), wear * 0.35);
		float nz = vnoise(p * 9.0);
		float knee = 1.0 - smoothstep(0.0, 0.1, abs(p.y - 0.50));
		float ankle = 1.0 - smoothstep(0.0, 0.1, abs(p.y - 0.20));
		float crotch = 1.0 - smoothstep(0.0, 0.08, abs(p.y - 0.80));
		float fl = sin(p.y * 95.0 + nz * 6.0 + az * 2.0);
		// Hip whiskers: diagonal creases fanning from the crotch over the thighs.
		float lat = abs(p.x) - 0.02;
		float whisk_k = (1.0 - smoothstep(0.0, 0.07, abs(p.y - 0.84))) * smoothstep(0.0, 0.03, lat) * (1.0 - smoothstep(0.08, 0.14, lat)) * smoothstep(0.3, 0.7, tw3.z);
		float whisk = sin((p.y + lat * 0.9) * 140.0 + nz * 3.0) * whisk_k;
		float bendk = smoothstep(0.02, 0.4, v_bend);
		float kpose = knee * (0.8 + 1.8 * bendk) + ankle + crotch * (0.8 + 1.2 * bendk);
		h = (fl * (knee * 0.0028 * (0.8 + 1.8 * bendk) + ankle * 0.0032 + crotch * 0.002 * (0.8 + 1.2 * bendk)) + whisk * 0.0016) * mid_k;
		float pcav = clamp(-fl, 0.0, 1.0) * kpose + clamp(-whisk, 0.0, 1.0) * 0.8;
		ao *= 1.0 - 0.3 * clamp(pcav, 0.0, 1.0);
		col *= (1.0 - 0.24 * clamp(pcav, 0.0, 1.2)) * (1.0 + 0.10 * clamp(fl, 0.0, 1.0) * kpose + 0.12 * clamp(whisk, 0.0, 1.0));
		h += (dl - 1.0) * 0.00018 * fine_k;
		float hem = 1.0 - smoothstep(0.016, 0.02, e);
		float dash = step(0.38, fract((p.x + p.y * 1.3 + p.z) / 0.0045));
		col = mix(col, vec3(0.62, 0.45, 0.22), line_aa(e - 0.01, 0.0006) * dash * fine_k * 0.8); // orange denim thread
		h += hem * 0.0008;
		rough = 0.84;
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
	if (debug_mode == 4) {
		EMISSION = NORMAL * 0.5 + 0.5;
		col = vec3(0.0);
	}
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
	l_wrap = reg == 0 ? 0.45 : (reg == 2 ? 0.25 : 0.3);
	l_rough = clamp(rough, 0.05, 1.0);
	l_spec = spec;
}

// Own light model: wrapped Lambert (soft terminator, skin and cloth read
// as soft materials) and a normalised Blinn-Phong lobe.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + l_wrap) / ((1.0 + l_wrap) * (1.0 + l_wrap)), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * d / PI;
	vec3 hv = normalize(VIEW + LIGHT);
	float a = max(l_rough * l_rough, 0.003);
	float shin = 2.0 / (a * a) - 2.0;
	float nh = max(dot(NORMAL, hv), 0.0);
	float spec = pow(nh, shin) * (shin + 8.0) / (8.0 * PI) * clamp(ndl, 0.0, 1.0);
	float fres = l_spec * 0.08 + (1.0 - l_spec * 0.08) * pow(1.0 - max(dot(VIEW, hv), 0.0), 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * spec * fres;
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
static func apply(model: Node, role: String = "civilian") -> MeshInstance3D:
	# Headless runs draw nothing, and the dummy renderer re-parses this shader
	# for every instance that binds it (~0.3 s each, ~60 s for the crowd), so
	# they keep the legacy materials; the regression builds the mesh directly.
	if not enabled or _headless:
		return null
	return _apply(model, role)

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
			_cache[key] = _build(target.mesh as ArrayMesh, _rig(model, role))
		entry = _cache[key]
	model.free()
	return entry

static func _key(src: ArrayMesh) -> String:
	return src.resource_path if src.resource_path != "" else str(src.get_instance_id())

## Hand bone rests (skeleton rest = mesh bind space for these rigs). Only the
## player gets the folded mitten + procedural fingers (one extra draw each).
static func _rig(model: Node, role: String) -> Dictionary:
	var out := {}
	var skel := model.find_children("*", "Skeleton3D", true, false)
	if skel.is_empty():
		return out
	var sk := skel[0] as Skeleton3D
	# Skin bind indices of the upper arms (sleeves are re-weighted onto them).
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var skin := (mi as MeshInstance3D).skin
		if skin == null:
			continue
		var names := PackedStringArray()
		for i in skin.get_bind_count():
			var bn := String(skin.get_bind_name(i))
			if bn == "" and skin.get_bind_bone(i) >= 0:
				bn = sk.get_bone_name(skin.get_bind_bone(i))
			names.append(bn)
			if bn == "upper_arm.r":
				out["bind_ua_r"] = i
			elif bn == "upper_arm.l":
				out["bind_ua_l"] = i
		out["bind_names"] = names
		break
	if not out.has("bind_names"):
		var names2 := PackedStringArray()
		for i in sk.get_bone_count():
			names2.append(sk.get_bone_name(i))
		out["bind_names"] = names2
	if not out.has("bind_ua_r"):
		# No Skin resource: binds follow the skeleton order.
		out["bind_ua_r"] = sk.find_bone("upper_arm.r")
		out["bind_ua_l"] = sk.find_bone("upper_arm.l")
	out["ua_r_x"] = sk.get_bone_global_rest(sk.find_bone("upper_arm.r")).origin.x if sk.find_bone("upper_arm.r") >= 0 else -0.2
	if role != "player":
		return out
	for b in [["hand.r", "hand_r"], ["hand.l", "hand_l"]]:
		var hid := sk.find_bone(b[0])
		if hid >= 0:
			out[b[1]] = sk.get_bone_global_rest(hid)
	return out

static func _apply(model: Node, role: String) -> MeshInstance3D:
	var target: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() >= 2:
			target = mi
			break
	if target == null:
		return null
	var src := target.mesh as ArrayMesh
	var key := _key(src)
	if not _cache.has(key):
		var t0 := Time.get_ticks_msec()
		var baked := _load_baked(src, CharacterVisual.asset_path(role))
		if not baked.is_empty():
			_cache[key] = baked
			print("[character-look] loaded bake for ", key.get_file(), " in ", Time.get_ticks_msec() - t0, " ms")
		else:
			push_warning("character-look: no offline bake for " + CharacterVisual.asset_path(role) + " (run tools/bake_character_look.tscn); building at runtime")
			_cache[key] = _build(src, _rig(model, role))
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

static func _build(src: ArrayMesh, rig: Dictionary = {}) -> Dictionary:
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
	# Weld vertices split at UV seams (and across surfaces, so smoothing never
	# opens a crack between the shirt and the skin).
	var weld := PackedInt32Array()
	weld.resize(nv)
	# Tolerance weld (WELD_TOL): the decimated civilian rig is a triangle soup
	# whose shared corners differ by up to ~1 mm, so an exact weld left every
	# triangle on its own (shard-like regions and normals).
	var lookup := {}
	var reps := PackedVector3Array()
	var wn := 0
	var inv_cell := 1.0 / WELD_TOL
	for i in nv:
		var v := verts[i]
		var c := Vector3i(floori(v.x * inv_cell), floori(v.y * inv_cell), floori(v.z * inv_cell))
		var found := -1
		for dx in 3:
			for dy in 3:
				for dz in 3:
					var lst = lookup.get(c + Vector3i(dx - 1, dy - 1, dz - 1))
					if lst != null:
						for o in lst:
							if reps[o].distance_squared_to(v) <= WELD_TOL * WELD_TOL:
								found = o
								break
					if found >= 0:
						break
				if found >= 0:
					break
			if found >= 0:
				break
		if found < 0:
			found = wn
			reps.append(v)
			if not lookup.has(c):
				lookup[c] = PackedInt32Array()
			var arr: PackedInt32Array = lookup[c]
			arr.append(wn)
			lookup[c] = arr
			wn += 1
		weld[i] = found
	# The provider split vertices at every UV island and skinned each copy on
	# its own, so copies at one position carry different bone weights: in any
	# pose neighbouring triangles drift apart and shade as hard-edged facets
	# (with or without textures, shadows or AO). Every copy now shares the
	# summed, renormalised weights of its welded position.
	var wb_acc: Array = []
	wb_acc.resize(wn)
	for i in nv:
		var w: int = weld[i]
		var dct: Dictionary = wb_acc[w] if wb_acc[w] != null else {}
		for k in bpv:
			var wt := weights[i * bpv + k]
			if wt > 0.0:
				var b := bones[i * bpv + k]
				dct[b] = float(dct.get(b, 0.0)) + wt
		wb_acc[w] = dct
	var merged_b := PackedInt32Array()
	merged_b.resize(wn * bpv)
	var merged_w := PackedFloat32Array()
	merged_w.resize(wn * bpv)
	for w in wn:
		var dct: Dictionary = wb_acc[w] if wb_acc[w] != null else {}
		var pairs := []
		for b in dct:
			pairs.append([float(dct[b]), int(b)])
		pairs.sort_custom(func(x, y): return x[0] > y[0])
		var tot := 0.0
		for k in mini(bpv, pairs.size()):
			tot += pairs[k][0]
		for k in bpv:
			if k < pairs.size() and tot > 0.0:
				merged_b[w * bpv + k] = pairs[k][1]
				merged_w[w * bpv + k] = pairs[k][0] / tot
	for i in nv:
		var w: int = weld[i]
		for k in bpv:
			bones[i * bpv + k] = merged_b[w * bpv + k]
			weights[i * bpv + k] = merged_w[w * bpv + k]
	var wpos := PackedVector3Array()
	wpos.resize(wn)
	var wkind := PackedByteArray()
	wkind.resize(wn)
	for i in nv:
		wpos[weld[i]] = reps[weld[i]]
		wkind[weld[i]] = maxi(wkind[weld[i]], kinds[i])
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
	var region := PackedByteArray()
	region.resize(wn)
	for w in wn:
		region[w] = _classify(Color(col[w * 3], col[w * 3 + 1], col[w * 3 + 2]), wpos[w], wkind[w], neck_c, neck_r)
	_majority(region, indices, weld, wn)
	_majority(region, indices, weld, wn)
	_majority(region, indices, weld, wn)
	var dressed := _dress_hidden_skin(region, wpos, wkind, merged_b, bpv, rig, neck_c, neck_r)
	# Unique welded edges.
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
	for i in nv:
		var w: int = weld[i]
		for k in bpv:
			bones[i * bpv + k] = merged_b[w * bpv + k]
			weights[i * bpv + k] = merged_w[w * bpv + k]
	# Sleeves ride the arm: the provider weighted the short sleeves to the
	# chest, so a raised arm (aim) slid out of its sleeve and the skin under it
	# poked through. In the sleeve zone every overshirt vertex now takes the
	# bone weights of the nearest body (arm) vertex under it, blended in from
	# the shoulder seam, so sleeve and arm deform as one.
	var bgrid := _spatial_grid(wpos, 0.04)
	for i in nv:
		if wkind[weld[i]] != 1:
			continue
		var v := verts[i]
		var t := smoothstep(0.150, 0.200, absf(v.x)) * smoothstep(1.02, 1.10, v.y) * (1.0 - smoothstep(1.40, 1.46, v.y))
		if t <= 0.0:
			continue
		var best := -1
		var best_d := 0.05
		for o in _neighbours(bgrid, wpos, v, 0.04, 0.04):
			if wkind[o] != 0:
				continue
			var dd := wpos[o].distance_to(v)
			if dd < best_d:
				best_d = dd
				best = o
		if best < 0:
			continue
		var wsum := {}
		for k in bpv:
			var wt := weights[i * bpv + k]
			if wt > 0.0:
				wsum[bones[i * bpv + k]] = float(wsum.get(bones[i * bpv + k], 0.0)) + wt * (1.0 - t)
			var wb2 := merged_w[best * bpv + k]
			if wb2 > 0.0:
				wsum[merged_b[best * bpv + k]] = float(wsum.get(merged_b[best * bpv + k], 0.0)) + wb2 * t
		var pairs := []
		for bb in wsum:
			pairs.append([float(wsum[bb]), int(bb)])
		pairs.sort_custom(func(x, y): return x[0] > y[0])
		var tot := 0.0
		for k in mini(bpv, pairs.size()):
			tot += pairs[k][0]
		for k in bpv:
			bones[i * bpv + k] = pairs[k][1] if k < pairs.size() else 0
			weights[i * bpv + k] = pairs[k][0] / tot if k < pairs.size() else 0.0
	# Player only: the provider hand is a mitten. Its finger block is folded
	# flat onto the knuckle line, and CharacterHands draws real jointed fingers.
	var folded := 0
	for side in [["hand_r", 1.0], ["hand_l", -1.0]]:
		if not rig.has(side[0]):
			continue
		var rest: Transform3D = rig[side[0]]
		var inv := rest.affine_inverse()
		for w in wn:
			if region[w] != R_SKIN:
				continue
			var q := inv * wpos[w]
			if q.y > KNUCKLE_Y - 0.004 and q.y < 0.24 and absf(q.x) < 0.075 and absf(q.z) < 0.09:
				q.y = KNUCKLE_Y - 0.004 + (q.y - KNUCKLE_Y + 0.004) * 0.06
				q.x *= 0.85
				wpos[w] = rest * q
				folded += 1
			elif q.z > THUMB_Z and q.y > -0.01 and q.y < KNUCKLE_Y and absf(q.x) < 0.075 and q.z < 0.13:
				# The mitten thumb folds into the palm edge (a jointed one replaces it).
				q.z = THUMB_Z + (q.z - THUMB_Z) * 0.15
				wpos[w] = rest * q
				folded += 1
	# Smooth vertex normals from the smoothed surface (area weighted). The
	# provider's winding is not consistent (decimated civilian rig), so each
	# face normal is oriented by the authored vertex normals it replaces.
	var anorm := PackedVector3Array()
	anorm.resize(wn)
	for i in nv:
		anorm[weld[i]] += norms[i]
	var wnorm := PackedVector3Array()
	wnorm.resize(wn)
	for t in nt:
		var ia := indices[t * 3]
		var ib := indices[t * 3 + 1]
		var ic := indices[t * 3 + 2]
		var wa := weld[ia]
		var wb := weld[ib]
		var wc := weld[ic]
		var fnrm := (wpos[wb] - wpos[wa]).cross(wpos[wc] - wpos[wa])
		if fnrm.dot(norms[ia] + norms[ib] + norms[ic]) < 0.0:
			fnrm = -fnrm
		wnorm[wa] += fnrm
		wnorm[wb] += fnrm
		wnorm[wc] += fnrm
	for w in wn:
		if wnorm[w].length_squared() > 1e-14:
			wnorm[w] = wnorm[w].normalized()
		elif anorm[w].length_squared() > 1e-10:
			wnorm[w] = anorm[w].normalized()
		else:
			wnorm[w] = Vector3.UP
	# The provider body is a triangle soup: neighbouring triangles do not
	# share corners (gaps of a few millimetres), so topology-based smoothing
	# left every triangle with its own flat normal: the faceted, posterised
	# skin and cloth. Normals are smoothed SPATIALLY instead: every vertex
	# takes the kernel-weighted area normals of all vertices within
	# NORMAL_RADIUS that face the same way (thin parts keep two sides).
	var sgrid := _spatial_grid(wpos, NORMAL_RADIUS)
	var raw := wnorm.duplicate()
	var area := PackedVector3Array()
	area.resize(wn)
	for t in nt:
		var ia := indices[t * 3]
		var ib := indices[t * 3 + 1]
		var ic := indices[t * 3 + 2]
		var fnrm := (wpos[weld[ib]] - wpos[weld[ia]]).cross(wpos[weld[ic]] - wpos[weld[ia]])
		if fnrm.dot(norms[ia] + norms[ib] + norms[ic]) < 0.0:
			fnrm = -fnrm
		area[weld[ia]] += fnrm
		area[weld[ib]] += fnrm
		area[weld[ic]] += fnrm
	for w in wn:
		if wkind[w] >= 2:
			continue
		var p := wpos[w]
		var own := raw[w]
		var radius := NORMAL_RADIUS * (0.6 if region[w] == R_FACE else 1.0)
		var acc_n := Vector3.ZERO
		for o in _neighbours(sgrid, wpos, p, radius, NORMAL_RADIUS):
			if wkind[o] >= 2:
				continue
			var a_n: Vector3 = area[o]
			if a_n.normalized().dot(own) < 0.25:
				continue
			var dd := wpos[o].distance_to(p) / radius
			acc_n += a_n * (1.0 - dd * dd)
		if acc_n.length_squared() > 1e-16:
			wnorm[w] = acc_n.normalized()
	# Shoes and soles keep their authored (crisp) normals.
	for i in nv:
		verts[i] = wpos[weld[i]]
		if kinds[i] < 2:
			norms[i] = wnorm[weld[i]]
	# Tangents re-orthogonalised against the new normals (Godot packs normal
	# and tangent together; a skewed provider tangent corrupts the pair).
	for i in nv:
		var nn := norms[i]
		var tg := Vector3(tangs[i * 4], tangs[i * 4 + 1], tangs[i * 4 + 2])
		tg = tg - nn * nn.dot(tg)
		if tg.length_squared() < 1e-8:
			tg = nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT)
		tg = tg.normalized()
		tangs[i * 4] = tg.x
		tangs[i * 4 + 1] = tg.y
		tangs[i * 4 + 2] = tg.z
		tangs[i * 4 + 3] = 1.0 if tangs[i * 4 + 3] >= 0.0 else -1.0
	# Garment weights (skin, shirt, hair, trousers, tee) diffused across the
	# mesh: the fragment shader takes the dominant one, so region borders are
	# smooth iso-curves rather than whole-triangle stairs.
	var rw := PackedFloat32Array()
	rw.resize(wn * 5)
	const CH := [0, 1, 2, 4, 3, 9, 9, 0] # region -> channel (face -> skin)
	for w in wn:
		var ch: int = CH[region[w]]
		if ch < 5:
			rw[w * 5 + ch] = 1.0
	# Spatial (not topological: the body is a triangle soup) kernel average
	# within WEIGHT_RADIUS among same-facing vertices.
	var rgrid := _spatial_grid(wpos, WEIGHT_RADIUS)
	var rw2 := rw.duplicate()
	for w in wn:
		if wkind[w] >= 2:
			continue
		var p := wpos[w]
		var acc5 := [0.0, 0.0, 0.0, 0.0, 0.0]
		var ksum := 0.0
		for o in _neighbours(rgrid, wpos, p, WEIGHT_RADIUS, WEIGHT_RADIUS):
			if wkind[o] >= 2 or wnorm[o].dot(wnorm[w]) < 0.2:
				continue
			var dd := wpos[o].distance_to(p) / WEIGHT_RADIUS
			var kk := 1.0 - dd * dd
			for c in 5:
				acc5[c] += rw[o * 5 + c] * kk
			ksum += kk
		if ksum > 0.0:
			for c in 5:
				rw2[w * 5 + c] = acc5[c] / ksum
	rw = rw2
	# Hair/head centre for the strand flow.
	var head_sum := Vector3.ZERO
	var head_n := 0.0
	for w in wn:
		if region[w] == R_HAIR:
			head_sum += wpos[w]
			head_n += 1.0
	var head_centre := Vector3(0.0, 1.62, 0.0)
	if head_n > 0.0:
		head_centre = head_sum / head_n
		head_centre.y -= 0.06
	# Nose tip (most forward face vertex at nose height).
	var nose_tip := Vector3(-0.016, 1.575, -0.089)
	var best_z := 1.0
	for w in wn:
		var v := wpos[w]
		if (region[w] == R_FACE or region[w] == R_SKIN) and v.y > 1.54 and v.y < 1.60 and absf(v.x) < 0.07 and v.z < best_z:
			best_z = v.z
			nose_tip = v
	# Smooth the baked colour inside each region (low-frequency fold shading).
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
		for k in ne:
			var x := ea[k]
			var y := eb[k]
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
	# Distance (m) from every vertex to the nearest region border (hems).
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
	var hair_l := 0.0
	var hair_ln := 0.0
	var lum := PackedFloat32Array()
	lum.resize(wn)
	for w in wn:
		var l := col[w * 3] * 0.2126 + col[w * 3 + 1] * 0.7152 + col[w * 3 + 2] * 0.0722
		lum[w] = l
		lsum[region[w]] += l
		lcnt[region[w]] += 1.0
		var lin := Color(col[w * 3], col[w * 3 + 1], col[w * 3 + 2]).srgb_to_linear()
		if region[w] == R_FACE and lin.r > lin.b * 1.2:
			skin_sum += Vector3(lin.r, lin.g, lin.b)
			skin_n += 1.0
		elif region[w] == R_HAIR:
			hair_l += lin.get_luminance()
			hair_ln += 1.0
	var src_skin := Vector3(0.55, 0.30, 0.19)
	if skin_n > 0.0:
		src_skin = skin_sum / skin_n
	var src_hair_lum := hair_l / maxf(hair_ln, 1.0)
	var colors := PackedColorArray()
	colors.resize(nv)
	var c0 := PackedFloat32Array()
	c0.resize(nv * 4)
	var c1 := PackedFloat32Array()
	c1.resize(nv * 4)
	var c2 := PackedFloat32Array()
	c2.resize(nv * 4)
	var c3 := PackedFloat32Array()
	c3.resize(nv * 4)
	for i in nv:
		var w := weld[i]
		var r := int(region[w])
		if kinds[i] == 2:
			r = R_SHOE
		elif kinds[i] == 3:
			r = R_SOLE
		var mean := lsum[r] / maxf(lcnt[r], 1.0)
		var shade := clampf(lum[w] / maxf(mean, 0.01), 0.55, 1.35) if r != R_SHOE and r != R_SOLE else 1.0
		colors[i] = Color(col[w * 3], col[w * 3 + 1], col[w * 3 + 2]).srgb_to_linear()
		c0[i * 4] = float(r) if r == R_SHOE or r == R_SOLE else 0.0
		c0[i * 4 + 1] = 0.0
		c0[i * 4 + 2] = shade
		c0[i * 4 + 3] = edist[w]
		var v := verts[i]
		c1[i * 4] = v.x
		c1[i * 4 + 1] = v.y
		c1[i * 4 + 2] = v.z
		c2[i * 4] = rw[w * 5]
		c2[i * 4 + 1] = rw[w * 5 + 1]
		c2[i * 4 + 2] = rw[w * 5 + 2]
		c2[i * 4 + 3] = rw[w * 5 + 3]
		var nn := wnorm[w]
		c3[i * 4] = nn.x
		c3[i * 4 + 1] = nn.y
		c3[i * 4 + 2] = nn.z
	# Hair shells: every triangle touching the hair mass (the fragment shader
	# decides strand by strand where hair really is).
	var hair_tris := PackedInt32Array()
	for t in nt:
		var ia := indices[t * 3]
		var ib := indices[t * 3 + 1]
		var ic := indices[t * 3 + 2]
		if kinds[ia] >= 2:
			continue
		var hw := rw[weld[ia] * 5 + 2] + rw[weld[ib] * 5 + 2] + rw[weld[ic] * 5 + 2]
		if hw > 0.6:
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
				c0.append_array(PackedFloat32Array([0.0, float(s), c0[i * 4 + 2], c0[i * 4 + 3]]))
				c1.append_array(c1.slice(i * 4, i * 4 + 4))
				c2.append_array(c2.slice(i * 4, i * 4 + 4))
				c3.append_array(c3.slice(i * 4, i * 4 + 4))
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
	arrays[Mesh.ARRAY_CUSTOM2] = c2
	arrays[Mesh.ARRAY_CUSTOM3] = c3
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
	if bpv == 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var params := {"src_skin": src_skin, "src_hair_lum": src_hair_lum, "head_centre": head_centre, "nose_tip": nose_tip}
	var material := _make_material(albedo, normal, params)
	var fab := _fabrics()
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
	return {"mesh": out, "material": material, "regions": counts, "shell_tris": hair_tris.size() / 3 * SHELLS, "src_skin": src_skin, "grip_verts": folded, "fabrics": fab.size() == 4, "params": params, "dressed": dressed}

## The shared character material for one provider atlas (also rebuilt for a
## baked mesh, which is stored without it).
static func _make_material(albedo: Texture2D, normal: Texture2D, params: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader()
	material.set_shader_parameter("albedo_tex", albedo)
	if normal != null:
		material.set_shader_parameter("normal_tex", normal)
	var fab := _fabrics()
	if fab.size() == 4:
		material.set_shader_parameter("flannel_tex", fab[0])
		material.set_shader_parameter("denim_tex", fab[1])
		material.set_shader_parameter("batik_tex", fab[2])
		material.set_shader_parameter("jersey_tex", fab[3])
		material.set_shader_parameter("has_fabrics", true)
	for k in params:
		material.set_shader_parameter(k, params[k])
	var dbg := OS.get_environment("ORCHARD_LOOK_DEBUG")
	if dbg != "":
		material.set_shader_parameter("debug_mode", int(dbg))
	return material

# --- Offline bake ---------------------------------------------------------------
# The rebuild above takes tens of seconds of GDScript per rig, so it runs
# OFFLINE (res://tools/bake_character_look.tscn, headless) and the result is
# stored next to the provider rigs under a new filename. The game only loads
# it; a missing or stale bake falls back to the runtime build with a warning.
## Bump whenever _build/_classify/_rig change what they produce.
const BAKE_VERSION := "r1e"
const BAKE_DIR := "res://assets/providers/baked_characters/"

static func baked_path(src_path: String) -> String:
	return BAKE_DIR + src_path.get_file().get_basename() + "_look_" + BAKE_VERSION + ".res"

static func _src_stamp(src_path: String) -> int:
	var f := FileAccess.open(src_path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n

## Bakes one role's look mesh (tool use). Returns the saved path or "".
static func bake(role: String) -> String:
	var path := CharacterVisual.asset_path(role)
	var entry := build_for_rig(role)
	if entry.is_empty():
		return ""
	var mesh: ArrayMesh = entry["mesh"]
	var mat := mesh.surface_get_material(0)
	mesh.surface_set_material(0, null)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKE_DIR))
	var out := baked_path(path)
	var err := ResourceSaver.save(mesh, out, ResourceSaver.FLAG_COMPRESS)
	mesh.surface_set_material(0, mat)
	if err != OK:
		return ""
	var info := {"source": path, "source_bytes": _src_stamp(path), "version": BAKE_VERSION, "role": role,
		"regions": Array(entry["regions"]), "shell_tris": entry["shell_tris"], "grip_verts": entry["grip_verts"],
		"fabrics": entry["fabrics"], "params": {}}
	var params: Dictionary = entry["params"]
	for k in params:
		var v: Vector3 = params[k] if params[k] is Vector3 else Vector3(float(params[k]), 0.0, 0.0)
		info["params"][k] = [v.x, v.y, v.z, 1.0 if params[k] is Vector3 else 0.0]
	var f := FileAccess.open(out.get_basename() + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "  "))
	f.close()
	return out

## Loads a baked look mesh for `src` (from `src_path`) and binds a fresh
## material; {} when there is no valid bake.
static func _load_baked(src: ArrayMesh, src_path: String) -> Dictionary:
	var out := baked_path(src_path)
	var jpath := out.get_basename() + ".json"
	if not ResourceLoader.exists(out) or not FileAccess.file_exists(jpath):
		return {}
	var info = JSON.parse_string(FileAccess.get_file_as_string(jpath))
	if not (info is Dictionary) or String(info.get("version", "")) != BAKE_VERSION or int(info.get("source_bytes", -2)) != _src_stamp(src_path):
		push_warning("character-look: stale bake " + out)
		return {}
	var mesh := load(out) as ArrayMesh
	if mesh == null or mesh.get_surface_count() != 1:
		return {}
	var albedo: Texture2D = null
	var normal: Texture2D = null
	for s in src.get_surface_count():
		var m := src.surface_get_material(s)
		if _surface_kind(m) <= 1 and m is StandardMaterial3D and (m as StandardMaterial3D).albedo_texture != null:
			albedo = (m as StandardMaterial3D).albedo_texture
			normal = (m as StandardMaterial3D).normal_texture
			break
	var params := {}
	for k in info["params"]:
		var a: Array = info["params"][k]
		params[k] = Vector3(a[0], a[1], a[2]) if float(a[3]) > 0.5 else float(a[0])
	var material := _make_material(albedo, normal, params)
	mesh.surface_set_material(0, material)
	var regions := PackedInt32Array(info["regions"])
	return {"mesh": mesh, "material": material, "regions": regions, "shell_tris": int(info["shell_tris"]),
		"grip_verts": int(info["grip_verts"]), "fabrics": bool(info["fabrics"]), "params": params, "baked": true}

const FABRIC_DIR := "res://assets/providers/higgsfield/"
static var _fabric_cache: Array = []
static func _fabrics() -> Array:
	if _fabric_cache.is_empty():
		for f in ["fabric_flannel_plaid_albedo.png", "fabric_denim_albedo.png", "fabric_batik_single_albedo.png", "fabric_cotton_jersey_neutral.png"]:
			if not ResourceLoader.exists(FABRIC_DIR + f):
				_fabric_cache = [null]
				return []
			_fabric_cache.append(load(FABRIC_DIR + f))
	return [] if _fabric_cache.size() != 4 else _fabric_cache

static func _spatial_grid(pos: PackedVector3Array, cell: float) -> Dictionary:
	var g := {}
	for i in pos.size():
		var c := Vector3i(floori(pos[i].x / cell), floori(pos[i].y / cell), floori(pos[i].z / cell))
		if not g.has(c):
			g[c] = PackedInt32Array()
		var arr: PackedInt32Array = g[c]
		arr.append(i)
		g[c] = arr
	return g

## Indices of points within `radius` of p (grid built with cell >= radius).
static func _neighbours(g: Dictionary, pos: PackedVector3Array, p: Vector3, radius: float, cell: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
	var r2 := radius * radius
	for dx in 3:
		for dy in 3:
			for dz in 3:
				var lst = g.get(c + Vector3i(dx - 1, dy - 1, dz - 1))
				if lst == null:
					continue
				for o in lst:
					if pos[o].distance_squared_to(p) <= r2:
						out.append(o)
	return out

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
		if skin and absf(p.x) > 0.2 and p.y < 1.19:
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
	if absf(p.x) > 0.19 and p.y >= 1.19 and p.y < 1.42:
		return R_SHIRT # the body's upper arm runs just under the sleeve: dress it
	if absf(p.x) > 0.215 and p.y > 0.95 and p.y < 1.19:
		return R_SKIN # bare forearms (sleeves live on the overshirt surface)
	if absf(p.x) > 0.205 and p.y > 0.6 and p.y <= 0.95:
		return R_SKIN # hands hang outside the thighs in the rest pose
	if p.y > 1.30:
		return R_SKIN # neck: the collar is authored on the overshirt surface
	if p.y > 0.95:
		return R_SHIRT
	return R_PANTS

## Body skin that belongs under the clothes is dressed, so a pose that pushes
## it through a garment shows cloth, not a skin shard: the thigh and hip
## (dominant leg/pelvis bone) become trousers, the waist and torso (spine /
## chest away from the neck opening) shirt, and body skin within 2 cm of
## the overshirt surface (upper arm under the sleeve, armpit, waistband)
## shirt. Returns how many vertices were dressed.
static func _dress_hidden_skin(region: PackedByteArray, wpos: PackedVector3Array, wkind: PackedByteArray, mb: PackedInt32Array, bpv: int, rig: Dictionary, neck_c: Vector2, neck_r: float) -> int:
	var names: PackedStringArray = rig.get("bind_names", PackedStringArray())
	var wn := wpos.size()
	var shirt_pts := PackedVector3Array()
	for w in wn:
		if wkind[w] == 1 and region[w] == R_SHIRT:
			shirt_pts.append(wpos[w])
	var sg := _spatial_grid(shirt_pts, 0.02)
	var n := 0
	for w in wn:
		if wkind[w] != 0 or region[w] != R_SKIN:
			continue
		var p := wpos[w]
		var dom := ""
		var bi := mb[w * bpv]
		if bi >= 0 and bi < names.size():
			dom = names[bi]
		var at_neck := p.y > 1.34 and Vector2(p.x, p.z).distance_to(neck_c) < neck_r + 0.035
		if p.y > 1.44 or at_neck:
			continue
		var to := -1
		if dom.begins_with("thigh") or dom.begins_with("shin") or dom == "pelvis":
			to = R_PANTS if p.y < 0.99 else R_SHIRT
		elif dom.begins_with("spine") or dom == "chest" or dom.begins_with("clavicle"):
			to = R_SHIRT if p.y > 0.95 else R_PANTS
		elif dom.begins_with("upper_arm") and p.y > 1.16:
			to = R_SHIRT
		elif not _neighbours(sg, shirt_pts, p, 0.02, 0.02).is_empty():
			to = R_SHIRT
		if to >= 0:
			region[w] = to
			n += 1
	return n

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
const SKIN_WEIGHTS := [0.24, 0.30, 0.18, 0.12, 0.08, 0.05, 0.03]
const HAIRS := [Color(0.05, 0.045, 0.04), Color(0.10, 0.07, 0.05), Color(0.20, 0.13, 0.08), Color(0.03, 0.03, 0.03), Color(0.30, 0.13, 0.07)]
const SHOES := [Color(0.88, 0.88, 0.86), Color(0.07, 0.07, 0.08), Color(0.30, 0.18, 0.10), Color(0.45, 0.45, 0.47), Color(0.12, 0.16, 0.30), Color(0.70, 0.14, 0.12)]

static func _lin(c: Color) -> Color:
	return c.srgb_to_linear()

static func _v4(c: Color, w: float) -> Vector4:
	var l := c.srgb_to_linear()
	return Vector4(l.r, l.g, l.b, w)

## Player: woven navy/green flannel overshirt (the authored fabric scan,
## chest pockets), faded mid-blue denim, brown leather shoes, a warm tan skin
## tone, short dark-brown hair and two-day stubble.
static func player_outfit() -> Dictionary:
	var skin := _lin(Color(0.76, 0.58, 0.46))
	return {
		"shirt_col": _v4(Color(0.20, 0.27, 0.24), 7.0),
		"shirt_col2": _v4(Color(0.40, 0.15, 0.09), 1.0),
		"tee_col": _v4(Color(0.62, 0.62, 0.60), 0.0),
		"pants_col": _v4(Color(0.27, 0.36, 0.50), 2.0),
		"shoe_col": _v4(Color(0.26, 0.16, 0.09), 0.16),
		"skin_col": Vector4(skin.r, skin.g, skin.b, 0.0),
		"hair_col": _v4(Color(0.12, 0.09, 0.07), 0.0),
		"face_col": Vector4(0.85, 0.8, 0.6, 1.0),
		"head_shape": Vector4(0.35, 0.15, 0.8, 1.0),
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
	if roll < 0.10: pattern = 1
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
	# Singapore's street mix: mostly light-to-medium (Chinese majority),
	# then tan/brown (Malay), then deep brown (Indian) complexions.
	var sr := rng.randf()
	var si := 0
	var acc := 0.0
	for k in SKIN_WEIGHTS.size():
		acc += SKIN_WEIGHTS[k]
		if sr <= acc:
			si = k
			break
	var skin: Color = SKINS[si]
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
		"head_shape": Vector4(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-0.8, 1.0), rng.randf_range(0.5, 1.9)),
	}

## The headless (dummy) renderer re-parses the shader on every per-instance
## parameter write (~45 ms each), so headless runs keep the outfit data on the
## CharacterVisual only; nothing is drawn there anyway.
static var _headless := DisplayServer.get_name() == "headless"

static func set_outfit(mi: MeshInstance3D, outfit: Dictionary) -> void:
	if _headless:
		return
	for key in ["shirt_col", "shirt_col2", "tee_col", "pants_col", "shoe_col", "skin_col", "hair_col", "face_col", "head_shape"]:
		if outfit.has(key):
			mi.set_instance_shader_parameter(key, outfit[key])

## A short signature of an outfit, used by the regression to count distinct looks.
static func outfit_signature(outfit: Dictionary) -> String:
	var parts := []
	for key in ["shirt_col", "tee_col", "pants_col", "skin_col"]:
		var v: Vector4 = outfit[key]
		parts.append("%d,%d,%d,%d" % [int(v.x * 20), int(v.y * 20), int(v.z * 20), int(v.w)])
	return "|".join(parts)
