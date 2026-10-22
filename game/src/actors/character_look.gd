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

const SHELLS := 3
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
uniform float shell_step = 0.0042;
uniform float near_fade = 0.6;

// Per-instance wardrobe (linear colours). w channels carry extra parameters.
instance uniform vec4 shirt_col = vec4(0.07, 0.065, 0.035, 0.0); // w: pattern id
instance uniform vec4 shirt_col2 = vec4(0.2, 0.2, 0.2, 9.0);   // w: pattern scale
instance uniform vec4 tee_col = vec4(0.33, 0.33, 0.31, 0.0);    // w: 1 = no overshirt (plain tee)
instance uniform vec4 pants_col = vec4(0.010, 0.016, 0.040, 0.0); // w: 1 = shorts
instance uniform vec4 shoe_col = vec4(0.030, 0.014, 0.007, 0.25); // w: sole value
instance uniform vec4 skin_col = vec4(-1.0, 0.0, 0.0, 0.0);      // x<0: authored tone; w: girth
instance uniform vec4 hair_col = vec4(0.004, 0.003, 0.0025, 0.0); // w: grey amount

varying flat int v_region;
varying vec3 v_rest;
varying vec4 v_data;
varying vec3 v_bake;

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

void vertex() {
	v_region = int(CUSTOM0.x + 0.5);
	v_rest = CUSTOM1.xyz;
	v_data = CUSTOM0;
	v_bake = COLOR.rgb;
	// Body build: belly/chest girth pushes the torso out along its normal.
	vec3 r = CUSTOM1.xyz;
	float band = smoothstep(0.84, 1.02, r.y) * (1.0 - smoothstep(1.20, 1.44, r.y));
	float core = 1.0 - smoothstep(0.15, 0.25, abs(r.x));
	float front = mix(0.55, 1.0, smoothstep(-0.02, 0.10, -r.z));
	VERTEX += NORMAL * skin_col.w * 0.055 * band * core * front;
	if (CUSTOM0.y > 0.5) {
		VERTEX += NORMAL * CUSTOM0.y * shell_step;
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
	float shade = clamp(v_data.z, 0.55, 1.35);
	// Fine detail fades out once a texel-scale feature is smaller than a pixel.
	float px = length(fwidth(p));
	float fine_k = 1.0 - smoothstep(0.0012, 0.004, px);
	float mid_k = 1.0 - smoothstep(0.004, 0.014, px);
	vec3 skin_tone = skin_col.x < 0.0 ? src_skin : skin_col.rgb;
	float az = atan(p.x, p.z);
	float u = az * 0.17; // ~arc length around the body (m)
	vec3 col = vec3(0.5);
	float rough = 0.85;
	float spec = 0.3;
	float h = 0.0;
	float sss = 0.0;
	float rim = 0.0;
	float ao = mix(1.0, shade, 0.45);
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	float nmap_depth = 0.0;
	if (reg == 4 && pants_col.w > 0.5 && p.y < 0.50) {
		reg = 0; // shorts: bare lower legs
	}
	if (reg == 1 && tee_col.w > 0.5) {
		reg = 3; // plain tee, no overshirt
	}
	if (reg == 0) {
		float blotch = fbm(p * 38.0);
		col = skin_tone * (0.9 + 0.2 * blotch) * mix(1.0, shade, 0.5);
		col *= mix(vec3(1.0), vec3(1.06, 0.95, 0.93), smoothstep(0.55, 0.8, vnoise(p * 21.0)));
		rough = 0.5 + 0.22 * vnoise(p * 160.0);
		spec = 0.42;
		sss = 0.5;
		h = (vnoise(p * 700.0) - 0.5) * 0.00018 * fine_k;
		rim = 0.12;
	} else if (reg == 7) {
		vec3 tex = texture(albedo_tex, UV).rgb;
		col = tex * (skin_tone / max(src_skin, vec3(0.002)));
		float sk = smoothstep(0.02, 0.07, dot(tex, vec3(0.33)));
		col *= 0.94 + 0.12 * fbm(p * 60.0);
		rough = mix(0.62, 0.42 + 0.2 * vnoise(p * 180.0), sk);
		spec = 0.45;
		sss = 0.55 * sk;
		nmap = texture(normal_tex, UV).rgb;
		nmap_depth = 0.65;
		h = (vnoise(p * 900.0) - 0.5) * 0.00012 * fine_k;
		rim = 0.1;
	} else if (reg == 2) {
		vec3 q = p - head_centre;
		float qa = atan(q.x, q.z);
		float pol = acos(clamp(q.y / max(length(q), 0.001), -1.0, 1.0));
		float warp = vnoise(vec3(qa * 3.0, pol * 4.0, 1.7)) * 1.6;
		float clump = vnoise(vec3(qa * 16.0 + warp, pol * 2.2, 3.1));
		float strand = vnoise(vec3(qa * 140.0 + warp * 9.0, pol * 5.0, 9.7));
		float m = strand * 0.55 + clump * 0.45;
		if (shell > 0.5) {
			float cut = 0.30 + 0.16 * shell + (ign - 0.5) * 0.18;
			if (m < cut) {
				discard;
			}
		}
		vec3 hc = mix(hair_col.rgb, vec3(0.32, 0.31, 0.30), hair_col.w * smoothstep(0.25, 0.75, vnoise(vec3(qa * 60.0, pol * 3.0, 5.0)) + hair_col.w * 0.35));
		col = hc * (0.45 + 0.75 * strand) * (0.75 + 0.5 * clump) * mix(0.7, 1.15, shell / 3.0);
		rough = 0.36 + 0.3 * (1.0 - strand);
		spec = 0.55;
		h = (strand * 0.65 + clump * 0.35) * 0.0016 * mid_k;
		rim = 0.25;
		ao = mix(0.75, 1.0, shell / 3.0);
	} else if (reg == 1) {
		col = shirt_col.rgb;
		int pat = int(shirt_col.w + 0.5);
		float s = shirt_col2.w;
		if (pat == 1) { // stripes
			float fu = fract(u * s);
			float st = smoothstep(0.55, 0.6, fu) - smoothstep(0.85, 0.9, fu);
			col = mix(col, shirt_col2.rgb, mix(0.3, st, mid_k));
		} else if (pat == 2) { // check / gingham
			float a = step(0.5, fract(u * s));
			float b = step(0.5, fract(p.y * s));
			col = mix(col, shirt_col2.rgb, (a * 0.5 + b * 0.5) * mix(0.5, 1.0, mid_k));
		} else if (pat == 3) { // batik / floral print
			vec3 bp = vec3(u * s, p.y * s, 0.0);
			float f = vnoise(bp * 1.0) * 0.65 + vnoise(bp * 2.7) * 0.35;
			float petal = smoothstep(0.58, 0.62, f) - smoothstep(0.72, 0.76, f) * 0.6;
			float dots = smoothstep(0.80, 0.84, vnoise(bp * 6.0));
			col = mix(col, shirt_col2.rgb, clamp(petal + dots * 0.7, 0.0, 1.0));
		} else if (pat == 4) { // polo with contrast trim near the collar
			col = mix(col, shirt_col2.rgb, smoothstep(1.43, 1.46, p.y));
		}
		// Drape and bunching folds (metres): waist bunching, lower-torso
		// drape, and creases across the short sleeves.
		float nz = vnoise(p * 9.0);
		float waist = (1.0 - smoothstep(0.0, 0.11, abs(p.y - 0.98))) * (1.0 - smoothstep(0.17, 0.26, abs(p.x)));
		float drape = smoothstep(1.24, 0.98, p.y) * (1.0 - smoothstep(0.17, 0.26, abs(p.x)));
		float sleeve = smoothstep(0.17, 0.23, abs(p.x)) * smoothstep(1.16, 1.24, p.y);
		float f1 = sin(p.y * 105.0 + nz * 6.0 + az * 3.0) * waist;
		float f2 = sin(u * 75.0 + nz * 5.0 + p.y * 9.0) * drape;
		float f3 = sin(p.y * 80.0 - abs(p.x) * 40.0 + nz * 4.0) * sleeve;
		float folds = (f1 * 0.0026 + f2 * 0.0022 + f3 * 0.0018) * mid_k;
		float weave = (sin(u * 2400.0) * sin(p.y * 2400.0)) * 0.00004 * fine_k + (vnoise(p * 320.0) - 0.5) * 0.00016 * fine_k;
		h = folds + weave;
		col *= mix(1.0, shade, 0.65) * (0.97 + 0.06 * vnoise(p * 50.0));
		rough = 0.86 + 0.08 * vnoise(p * 90.0);
		spec = 0.26;
		rim = 0.3;
	} else if (reg == 3) {
		col = tee_col.rgb * mix(1.0, shade, 0.6) * (0.97 + 0.06 * vnoise(p * 60.0));
		float nz = vnoise(p * 10.0);
		float body = 1.0 - smoothstep(0.17, 0.26, abs(p.x));
		h = sin(u * 60.0 + nz * 5.0 + p.y * 12.0) * 0.0014 * smoothstep(1.3, 1.0, p.y) * body * mid_k;
		h += (vnoise(p * 380.0) - 0.5) * 0.00014 * fine_k;
		rough = 0.88;
		spec = 0.24;
		rim = 0.3;
	} else if (reg == 4) {
		col = pants_col.rgb * mix(1.0, shade, 0.6);
		// Denim / chino twill and soft wear on the thighs and knees.
		float tw = sin((u + p.y) * 1900.0) * 0.5 + 0.5;
		col *= mix(1.0, 0.88 + 0.2 * tw, fine_k);
		float wear = smoothstep(0.45, 0.85, vnoise(vec3(u * 12.0, p.y * 5.0, 2.0))) * (smoothstep(0.35, 0.55, p.y) - smoothstep(0.62, 0.8, p.y) * 0.5);
		col = mix(col, col * 1.45 + vec3(0.01), wear * 0.35);
		float nz = vnoise(p * 9.0);
		float knee = 1.0 - smoothstep(0.0, 0.1, abs(p.y - 0.50));
		float ankle = 1.0 - smoothstep(0.0, 0.1, abs(p.y - 0.20));
		float crotch = 1.0 - smoothstep(0.0, 0.08, abs(p.y - 0.80));
		h = sin(p.y * 95.0 + nz * 6.0 + az * 2.0) * (knee * 0.0022 + ankle * 0.0026 + crotch * 0.0016) * mid_k;
		h += (tw - 0.5) * 0.00006 * fine_k;
		rough = 0.84;
		spec = 0.25;
		rim = 0.2;
	} else if (reg == 5) {
		col = shoe_col.rgb * mix(1.0, shade, 0.4) * (0.94 + 0.12 * vnoise(p * 120.0));
		rough = 0.55 + 0.25 * vnoise(p * 60.0);
		spec = 0.4;
		h = (vnoise(p * 500.0) - 0.5) * 0.0001 * fine_k;
	} else {
		col = vec3(shoe_col.w) * (0.9 + 0.1 * vnoise(p * 200.0));
		rough = 0.9;
		spec = 0.25;
	}
	NORMAL = bump(NORMAL, VERTEX, h);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = spec;
	METALLIC = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
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
	if not enabled:
		return null
	var target: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() >= 2:
			target = mi
			break
	if target == null:
		return null
	var src := target.mesh as ArrayMesh
	var key := src.resource_path if src.resource_path != "" else str(src.get_instance_id())
	if not _cache.has(key):
		var t0 := Time.get_ticks_msec()
		_cache[key] = _build(src)
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

static func _build(src: ArrayMesh) -> Dictionary:
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
		region[w] = _classify(c, wpos[w], wkind[w])
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
		if region[w] == R_SKIN or region[w] == R_FACE:
			var lin := Color(col[w * 3], col[w * 3 + 1], col[w * 3 + 2]).srgb_to_linear()
			if lin.r > lin.b * 1.2:
				skin_sum += Vector3(lin.r, lin.g, lin.b)
				skin_n += 1.0
	var src_skin := Vector3(0.55, 0.30, 0.19)
	if skin_n > 0.0:
		src_skin = skin_sum / skin_n
	# Output arrays (per original vertex) plus the hair shells.
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
		c0[i * 4 + 3] = 0.0
		var v := verts[i]
		c1[i * 4] = v.x
		c1[i * 4 + 1] = v.y
		c1[i * 4 + 2] = v.z
		c1[i * 4 + 3] = 0.0
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
				c0.append_array(PackedFloat32Array([float(R_HAIR), float(s), c0[i * 4 + 2], 0.0]))
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
	return {"mesh": out, "material": material, "regions": counts, "shell_tris": hair_tris.size() / 3 * SHELLS, "src_skin": src_skin}

static func _classify(c: Color, p: Vector3, kind: int) -> int:
	if kind == 2:
		return R_SHOE
	if kind == 3:
		return R_SOLE
	var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var sat := (mx - mn) / maxf(mx, 0.001)
	var skinlike := c.r > c.g * 1.06 and c.g >= c.b * 0.92 and c.r - c.b > 0.10 and l > 0.16 and sat > 0.16
	if p.y > 1.50:
		if skinlike:
			return R_FACE
		if l < 0.17 and (p.y > 1.60 or p.z > 0.02):
			return R_HAIR
		return R_FACE
	if skinlike:
		return R_SKIN
	if p.y > 0.95:
		if l < 0.13 or (l < 0.28 and sat > 0.18):
			return R_SHIRT
		return R_TEE
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
	Color(0.10, 0.14, 0.27), Color(0.88, 0.88, 0.86), Color(0.55, 0.68, 0.84), Color(0.45, 0.10, 0.13),
	Color(0.80, 0.62, 0.20), Color(0.08, 0.40, 0.42), Color(0.88, 0.56, 0.62), Color(0.07, 0.07, 0.08),
	Color(0.72, 0.13, 0.11), Color(0.52, 0.52, 0.53), Color(0.16, 0.30, 0.20), Color(0.62, 0.56, 0.78),
	Color(0.90, 0.47, 0.16), Color(0.90, 0.84, 0.70), Color(0.26, 0.36, 0.54), Color(0.95, 0.80, 0.30),
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

## Player: olive-khaki twill overshirt over a light grey tee, dark indigo
## jeans, brown leather shoes, authored skin and black hair.
static func player_outfit() -> Dictionary:
	return {
		"shirt_col": _v4(Color(0.36, 0.33, 0.22), 0.0),
		"shirt_col2": _v4(Color(0.2, 0.2, 0.2), 9.0),
		"tee_col": _v4(Color(0.66, 0.66, 0.64), 0.0),
		"pants_col": _v4(Color(0.12, 0.15, 0.24), 0.0),
		"shoe_col": _v4(Color(0.26, 0.16, 0.09), 0.16),
		"skin_col": Vector4(-1.0, 0.0, 0.0, 0.0),
		"hair_col": _v4(Color(0.045, 0.04, 0.035), 0.0),
	}

## Deterministic civilian outfit and build for a seed. Never the player's
## olive-khaki overshirt with dark jeans.
static func civilian_outfit(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 2654435761 + 1013904223)
	var shirt: Color = SHIRTS[rng.randi() % SHIRTS.size()]
	var shirt2: Color = SHIRTS[rng.randi() % SHIRTS.size()]
	if shirt2.is_equal_approx(shirt):
		shirt2 = Color(0.95, 0.95, 0.93) if shirt.get_luminance() < 0.5 else Color(0.08, 0.10, 0.18)
	var roll := rng.randf()
	var pattern := 0
	if roll < 0.18: pattern = 1
	elif roll < 0.32: pattern = 2
	elif roll < 0.46: pattern = 3
	elif roll < 0.58: pattern = 4
	var scale: float = [0.0, rng.randf_range(9.0, 16.0), rng.randf_range(6.0, 11.0), rng.randf_range(5.0, 8.0), 0.0][pattern]
	var tee_only := 1.0 if rng.randf() < 0.32 else 0.0
	var tee: Color = TEES[rng.randi() % TEES.size()]
	if tee_only > 0.5:
		tee = shirt
	var pants: Color = PANTS[rng.randi() % PANTS.size()]
	var shorts := 1.0 if rng.randf() < 0.28 else 0.0
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var elder := rng.randf() < 0.18
	var hair: Color = HAIRS[rng.randi() % HAIRS.size()]
	var shoe: Color = SHOES[rng.randi() % SHOES.size()]
	var girth := rng.randf_range(-0.25, 0.35)
	if rng.randf() < 0.22:
		girth = rng.randf_range(0.55, 1.0)
	return {
		"shirt_col": _v4(shirt, float(pattern)),
		"shirt_col2": _v4(shirt2, scale),
		"tee_col": _v4(tee, tee_only),
		"pants_col": _v4(pants, shorts),
		"shoe_col": _v4(shoe, 0.75 if shoe.get_luminance() > 0.5 or rng.randf() < 0.5 else 0.12),
		"skin_col": Vector4(_lin(skin).r, _lin(skin).g, _lin(skin).b, girth),
		"hair_col": _v4(hair, rng.randf_range(0.55, 1.0) if elder else 0.0),
		"height": rng.randf_range(0.93, 1.06) * (0.97 if elder else 1.0),
	}

## The headless (dummy) renderer re-parses the shader on every per-instance
## parameter write (~45 ms each), so headless runs keep the outfit data on the
## CharacterVisual only; nothing is drawn there anyway.
static var _headless := DisplayServer.get_name() == "headless"

static func set_outfit(mi: MeshInstance3D, outfit: Dictionary) -> void:
	if _headless:
		return
	for key in ["shirt_col", "shirt_col2", "tee_col", "pants_col", "shoe_col", "skin_col", "hair_col"]:
		if outfit.has(key):
			mi.set_instance_shader_parameter(key, outfit[key])

## A short signature of an outfit, used by the regression to count distinct looks.
static func outfit_signature(outfit: Dictionary) -> String:
	var parts := []
	for key in ["shirt_col", "tee_col", "pants_col", "skin_col"]:
		var v: Vector4 = outfit[key]
		parts.append("%d,%d,%d,%d" % [int(v.x * 20), int(v.y * 20), int(v.z * 20), int(v.w)])
	return "|".join(parts)
