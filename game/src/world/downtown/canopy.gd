extends RefCounted
## downtown-fill (wave T): procedural park-canopy trees for the downtown, cheap
## enough to plant thousands (one MultiMesh per species per 400 m cell).
## Original work: generated meshes and a procedural foliage shader, no files.
##
## Each crown is a cluster of jittered, subdivided-icosahedron lobes (umbrella
## rain tree, rounded angsana, tall tembusu, flowering flame tree, palm-like
## fan cluster and low shrub masses). Lobe normals are bent toward the crown's
## outer shell so a crown shades as one canopy with soft clumps; the foliage
## shader breaks the surface into lit leaf clumps and dark gaps, tears the
## silhouette into a ragged leafy edge and lets the sun glow through (backlight).
## Per-instance tint (custom data) keeps neighbours from matching.

const SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec3 leaf : source_color = vec3(0.17, 0.28, 0.09);
uniform vec3 flower : source_color = vec3(0.80, 0.30, 0.12);
uniform vec3 bark : source_color = vec3(0.24, 0.20, 0.16);
uniform float near_fade = 18.0;
varying vec3 wp;
varying vec4 tint;
varying float ao;
varying float is_bark;
float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vn3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = INSTANCE_CUSTOM;
	ao = COLOR.r;
	is_bark = COLOR.b;
}
void fragment() {
	float dist = length(wp - CAMERA_POSITION_WORLD);
	// leaf clumps at two scales (world space, so instances never match)
	float c1 = vn3(wp * 0.95);
	float c2 = vn3(wp * 2.7 + 13.0);
	float clump = c1 * 0.62 + c2 * 0.38;
	// ragged leafy silhouette: holes where the crown is seen edge-on
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float tear = vn3(wp * 3.1 + 5.0);
	if (is_bark < 0.5 && rim > 0.45 && tear < (rim - 0.45) * 1.6 * (1.0 - smoothstep(250.0, 600.0, dist))) { discard; }
	vec3 base = leaf * tint.rgb;
	float lit = 0.55 + 0.75 * smoothstep(0.30, 0.75, clump);
	vec3 col = base * lit * mix(0.45, 1.0, ao);
	// flowering crowns: blossom patches on the upper surface
	float fl = smoothstep(0.58, 0.70, vn3(wp * 0.7 + 3.0)) * tint.a * smoothstep(0.55, 0.9, ao);
	col = mix(col, flower * (0.8 + 0.3 * c2), fl);
	col = mix(col, bark * (0.8 + 0.3 * c2), is_bark);
	ALBEDO = col;
	ROUGHNESS = mix(0.82, 0.95, is_bark);
	SPECULAR = mix(0.32, 0.2, is_bark);
	BACKLIGHT = mix(base * 0.55, vec3(0.0), is_bark);
	// clumpy normal: bumps from the clump field
	float e = 0.25;
	vec3 g = vec3(vn3((wp + vec3(e,0,0)) * 0.95) - vn3((wp - vec3(e,0,0)) * 0.95),
		vn3((wp + vec3(0,e,0)) * 0.95) - vn3((wp - vec3(0,e,0)) * 0.95),
		vn3((wp + vec3(0,0,e)) * 0.95) - vn3((wp - vec3(0,0,e)) * 0.95));
	vec3 gv = (VIEW_MATRIX * vec4(g, 0.0)).xyz;
	NORMAL = normalize(NORMAL - gv * 1.6 * (1.0 - is_bark));
}
"""

## name: [lobes, crown radius, crown half-height, trunk height, lobe radius, shape]
const SPECIES := {
	"rain": {"lobes": 9, "r": 7.0, "hh": 2.2, "trunk": 5.2, "lobe": 3.6, "shape": "umbrella", "leaf": Color(0.16, 0.27, 0.085)},
	"angsana": {"lobes": 7, "r": 4.6, "hh": 3.2, "trunk": 4.0, "lobe": 2.9, "shape": "round", "leaf": Color(0.21, 0.32, 0.10)},
	"tembusu": {"lobes": 6, "r": 3.0, "hh": 5.2, "trunk": 3.4, "lobe": 2.3, "shape": "tall", "leaf": Color(0.12, 0.21, 0.075)},
	"flame": {"lobes": 8, "r": 5.0, "hh": 1.9, "trunk": 3.6, "lobe": 2.7, "shape": "umbrella", "leaf": Color(0.20, 0.30, 0.10)},
	"shrub": {"lobes": 4, "r": 2.4, "hh": 0.9, "trunk": 0.0, "lobe": 1.5, "shape": "mound", "leaf": Color(0.19, 0.29, 0.09)},
}

static var _meshes := {}
static var _mats := {}

static func _ico() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	# one subdivision (80 faces)
	var out: Array = []
	var mid := {}
	var mp := func(a: int, b: int) -> int:
		var k := "%d_%d" % [mini(a, b), maxi(a, b)]
		if mid.has(k):
			return mid[k]
		v.append(((v[a] + v[b]) * 0.5).normalized())
		mid[k] = v.size() - 1
		return v.size() - 1
	for tri in f:
		var a: int = tri[0]
		var b: int = tri[1]
		var c: int = tri[2]
		var ab: int = mp.call(a, b)
		var bc: int = mp.call(b, c)
		var ca: int = mp.call(c, a)
		out.append_array([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]])
	return [v, out]

static func _hash3(p: Vector3, s: int) -> float:
	return fract(sin(p.x * 12.9898 + p.y * 78.233 + p.z * 37.719 + float(s) * 4.1) * 43758.5453)

static func fract(x: float) -> float:
	return x - floorf(x)

## One crown mesh per species (built once, cached). `far` = the LOD drawn
## beyond ~420 m: half the lobes, each grown to keep the crown's volume.
static func mesh(sp: String, far: bool = false) -> ArrayMesh:
	var mkey := sp + ("|far" if far else "")
	if _meshes.has(mkey):
		return _meshes[mkey]
	var d: Dictionary = (SPECIES[sp] as Dictionary).duplicate()
	if far:
		d["lobes"] = maxi(3, int(d["lobes"]) / 2)
		d["lobe"] = float(d["lobe"]) * 1.3
		d["trunk_far"] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sp) & 0x7fffffff
	var ico := _ico()
	var iv: Array[Vector3] = ico[0]
	var ifaces: Array = ico[1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r: float = d["r"]
	var hh: float = d["hh"]
	var trunk: float = d["trunk"]
	var lobe: float = d["lobe"]
	var shape: String = d["shape"]
	var crown_c := Vector3(0, trunk + hh * 0.9, 0)
	var n_lobes: int = d["lobes"]
	for li in n_lobes:
		var c := Vector3.ZERO
		var lr := lobe * rng.randf_range(0.8, 1.15)
		match shape:
			"umbrella":
				var a := TAU * li / float(n_lobes) + rng.randf_range(-0.3, 0.3)
				var rr := r * (0.55 if li % 3 == 0 else 0.82) * rng.randf_range(0.85, 1.05)
				if li == 0:
					rr = 0.0
				c = crown_c + Vector3(cos(a) * rr, rng.randf_range(-0.4, 0.6) * hh + (hh * 0.5 if rr < 0.1 else 0.0), sin(a) * rr)
			"round":
				var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1.0), rng.randf_range(-1, 1)).normalized()
				c = crown_c + Vector3(dir.x * r * 0.62, dir.y * hh * 0.7, dir.z * r * 0.62)
			"tall":
				var t := float(li) / float(maxi(1, n_lobes - 1))
				var a2 := rng.randf_range(-PI, PI)
				c = Vector3(cos(a2) * r * 0.45 * (1.0 - t * 0.6), trunk + t * hh * 2.0, sin(a2) * r * 0.45 * (1.0 - t * 0.6))
				lr *= 1.0 - t * 0.35
			"mound":
				var a3 := TAU * li / float(n_lobes) + rng.randf_range(-0.4, 0.4)
				c = Vector3(cos(a3) * r * 0.55, hh * 0.7, sin(a3) * r * 0.55) if li > 0 else Vector3(0, hh, 0)
		var sy := 0.72 if shape in ["umbrella", "mound"] else 0.95
		for tri in ifaces:
			for k in [0, 2, 1]:
				var vi: int = tri[k]
				var n0 := iv[vi]
				var jit := 1.0 + (_hash3(n0 * 3.0, li) - 0.5) * 0.35
				var p := c + Vector3(n0.x * lr * jit, n0.y * lr * sy * jit, n0.z * lr * jit)
				# bend the lobe normal toward the crown shell normal
				var shell := (p - crown_c)
				shell.y *= 1.6
				var nrm := (n0 * 0.45 + shell.normalized() * 0.55).normalized()
				var low := clampf((p.y - (crown_c.y - hh * 1.2)) / (hh * 2.4), 0.0, 1.0)
				var outer := clampf(shell.length() / maxf(r, hh * 1.6), 0.0, 1.0)
				st.set_color(Color(clampf(0.25 + 0.55 * low + 0.3 * outer * (0.5 + 0.5 * n0.y), 0.0, 1.0), 0.0, 0.0, 1.0))
				st.set_normal(nrm)
				st.add_vertex(p)
	if trunk > 0.0 and not d.has("trunk_far"):
		# tapered hexagonal trunk with two limbs into the crown
		var limbs: Array = [[Vector3.ZERO, Vector3(0, trunk + hh * 0.3, 0), 0.32 * r / 5.0 + 0.12, 0.18]]
		for k in 3:
			var a4 := TAU * k / 3.0 + 0.4
			limbs.append([Vector3(0, trunk * 0.8, 0), Vector3(cos(a4) * r * 0.45, trunk + hh * 0.5, sin(a4) * r * 0.45), 0.16, 0.08])
		for lb in limbs:
			var a0: Vector3 = lb[0]
			var a1: Vector3 = lb[1]
			var r0: float = lb[2]
			var r1: float = lb[3]
			var ax := (a1 - a0).normalized()
			var side := ax.cross(Vector3.FORWARD if absf(ax.z) < 0.9 else Vector3.RIGHT).normalized()
			var side2 := ax.cross(side).normalized()
			for s in 6:
				var t0 := TAU * s / 6.0
				var t1 := TAU * (s + 1) / 6.0
				var d0 := side * cos(t0) + side2 * sin(t0)
				var d1 := side * cos(t1) + side2 * sin(t1)
				var q := [a0 + d0 * r0, a0 + d1 * r0, a1 + d1 * r1, a1 + d0 * r1]
				var ns := [d0, d1, d1, d0]
				for idx in [0, 2, 1, 0, 3, 2]:
					st.set_color(Color(0.5, 0.0, 1.0, 1.0))
					st.set_normal(ns[idx])
					st.add_vertex(q[idx])
	var m := st.commit()
	_meshes[mkey] = m
	return m

static func material(sp: String) -> ShaderMaterial:
	if _mats.has(sp):
		return _mats[sp]
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var d: Dictionary = SPECIES[sp]
	m.set_shader_parameter("leaf", d["leaf"])
	m.set_shader_parameter("flower", Color(0.86, 0.33, 0.13) if sp == "flame" else Color(0.86, 0.45, 0.62))
	_mats[sp] = m
	return m

## items: Array of [species, Transform3D, Color(tint rgb, flower amount)].
static func emit(parent: Node3D, items: Array, node_name: String, vis_end: float = 1500.0) -> int:
	var groups := {}
	for it in items:
		var xf: Transform3D = it[1]
		var key := "%s|%d|%d" % [it[0], floori(xf.origin.x / 400.0), floori(xf.origin.z / 400.0)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(it)
	var draws := 0
	for key: String in groups:
		var list: Array = groups[key]
		var sp: String = key.get_slice("|", 0)
		# near (full crowns) and far (LOD) copies of each 400 m cell
		for far: bool in [false, true]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh(sp, far)
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i][1])
				mm.set_instance_custom_data(i, list[i][2])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = node_name + ("Far" if far else "")
			mmi.multimesh = mm
			mmi.material_override = material(sp)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if sp == "shrub" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if far:
				mmi.visibility_range_begin = 420.0
				mmi.visibility_range_begin_margin = 40.0
				mmi.visibility_range_end = vis_end
				mmi.visibility_range_end_margin = 80.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				mmi.visibility_range_end = minf(460.0, vis_end)
				mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mmi.set_meta("downtown_fill", true)
			parent.add_child(mmi)
			draws += 1
	return draws
