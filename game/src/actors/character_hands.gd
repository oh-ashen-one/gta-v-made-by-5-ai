class_name CharacterHands
extends Node3D
## Characters piece (wave Q2): real hands for the player.
##
## The provider body has mitten hands (one finger block). CharacterLook folds
## that block flat onto the knuckle line; this node draws jointed fingers and
## a thumb (tapered capsules, nails, knuckle creases) on BoneAttachment3Ds of
## hand.r / hand.l, in two poses: a fist closed round the pistol grip and a
## relaxed curl. The pistol sits inside the gun hand's finger loop.
##
## Wave R: no IK of its own. The combat aim layer (AimIkLayer) places both
## arms; this node only publishes where the gun sits in each hand
## (grip_frames(), read by the layer through CharacterVisual.grip_frames) and
## wraps the fingers round the real pistol grip, measured from the held
## weapon's mesh: gun hand palm on the frame's near side, three fingers
## closed round the front strap, index on the trigger, thumb along the far
## side; the support hand over them, thumb forward under the slide.
## Hand-bone frame on this rig: +Y wrist -> knuckles, +X palm normal on
## hand.r (-X on hand.l), +Z thumb side. hand.r is the gun hand.

## Hand-bone-local frame (both hands): +Y wrist -> knuckles, +Z thumb side,
## palm normal = +X on hand.r and -X on hand.l.
const KNUCKLE_Y := 0.082
# [name, knuckle z, knuckle y, segment lengths, base radius, grip curl (MCP, PIP, DIP) deg, relaxed curl]
const FINGERS := [
	["index", 0.026, 0.080, [0.040, 0.024, 0.019], 0.0102, [62.0, 78.0, 30.0], [10.0, 20.0, 10.0]],
	["middle", 0.008, 0.083, [0.043, 0.027, 0.020], 0.0105, [86.0, 92.0, 22.0], [14.0, 24.0, 12.0]],
	["ring", -0.009, 0.080, [0.040, 0.025, 0.019], 0.0098, [90.0, 92.0, 22.0], [18.0, 28.0, 14.0]],
	["pinky", -0.025, 0.073, [0.032, 0.019, 0.017], 0.0088, [94.0, 90.0, 24.0], [22.0, 32.0, 16.0]],
]
## Knuckles sit this far toward the palm from the bone axis.
const KNUCKLE_X := 0.020
## Pistol pose inside the gun hand's fist (bone-local), see attach_weapon().
const SUPPORT_CURL := [70.0, 80.0, 35.0]

var skin_linear := Color(0.55, 0.33, 0.22)
var holding := false
var aiming := false
var weapon_kind := "pistol"
var aim_pitch := 0.0
var actor: Node3D
var weapon: Node3D
## 0..1 weight of the combat aim layer (support hand on the gun above 0.5).
var ik_weight := 0.0

var _meshes := {}   # "r_grip", "r_relax", "l_grip", "l_relax" -> MeshInstance3D
var _ids := {}
var _material: ShaderMaterial

const SKIN_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, sss_mode_skin;
stencil_mode write, compare_always, 8; // street weathering volumes skip people
uniform vec3 skin = vec3(0.4, 0.2, 0.13); // linear
varying vec3 v_local;
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
vec3 bump(vec3 n, vec3 pos, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 g = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * n - g);
}
void vertex() {
	v_local = VERTEX;
}
void fragment() {
	// COLOR: r nail, g knuckle crease, b joint ring, a dorsal (back of hand) side.
	float nail = COLOR.r;
	float crease = COLOR.g;
	float dorsal = COLOR.a;
	vec3 p = v_local;
	vec3 col = skin * (0.94 + 0.1 * vnoise(p * 180.0));
	col *= mix(vec3(1.08, 1.0, 0.97), vec3(1.0), dorsal); // paler palms
	col *= mix(vec3(1.0), vec3(1.06, 0.93, 0.9), COLOR.b * 0.6 * dorsal); // knuckle flush
	float wr = smoothstep(0.35, 0.75, vnoise(vec3(p.x * 2600.0, p.y * 300.0, p.z * 2600.0)));
	float lines = crease * wr;
	col *= 1.0 - 0.28 * lines;
	vec3 nail_col = mix(skin * 1.25 + vec3(0.07, 0.05, 0.05), vec3(0.86, 0.74, 0.70), 0.35);
	float lunula = smoothstep(0.55, 0.75, COLOR.r) * 0.0;
	col = mix(col, nail_col, smoothstep(0.35, 0.6, nail));
	float h = (vnoise(p * 900.0) - 0.5) * 0.00008 - lines * 0.00025 + smoothstep(0.35, 0.6, nail) * 0.0003;
	NORMAL = bump(NORMAL, VERTEX, h);
	ALBEDO = col;
	ROUGHNESS = mix(0.52 + 0.12 * vnoise(p * 400.0), 0.28, smoothstep(0.35, 0.6, nail));
	SPECULAR = 0.38;
	SSS_STRENGTH = 0.32 * (1.0 - smoothstep(0.35, 0.6, nail));
	RIM = 0.12;
	RIM_TINT = 0.7;
}
"""

func setup(skel: Skeleton3D, skin: Color) -> void:
	skin_linear = skin
	_material = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKIN_SHADER
	_material.shader = sh
	var lin := skin.srgb_to_linear()
	_material.set_shader_parameter("skin", Vector3(lin.r, lin.g, lin.b))
	for side in [["r", "hand.r", 1.0], ["l", "hand.l", -1.0]]:
		if skel.find_bone(side[1]) < 0:
			continue
		var att := BoneAttachment3D.new()
		att.name = "Fingers_" + side[0]
		att.bone_name = side[1]
		skel.add_child(att)
		for pose in ["grip", "relax"]:
			var mi := MeshInstance3D.new()
			mi.mesh = build_hand(side[2], pose == "grip")
			mi.material_override = _material
			mi.layers = 1 | (1 << 10)
			mi.visible = pose == "relax"
			att.add_child(mi)
			_meshes[side[0] + "_" + pose] = mi

## Skin tone from the shader-linear outfit colour (sRGB albedo for the uniform).
func set_skin(linear: Color) -> void:
	if _material != null:
		_material.set_shader_parameter("skin", Vector3(linear.r, linear.g, linear.b))

## Gun hand closes round the weapon; the support hand closes only while aiming.
func update_pose() -> void:
	var r_grip := holding
	var l_grip := holding and aiming and weapon_kind == "pistol" and ik_weight > 0.5
	if _meshes.has("r_grip"):
		_meshes["r_grip"].visible = r_grip
		_meshes["r_relax"].visible = not r_grip
	if _meshes.has("l_grip"):
		_meshes["l_grip"].visible = l_grip
		_meshes["l_relax"].visible = not l_grip

## The held pistol's pose in the gun hand (bone-local), same seat the aim
## layer uses, so the fingers stay closed on it aimed or not.
static func weapon_transform(kind: String) -> Transform3D:
	if kind != "pistol":
		return Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.055, -0.012))
	return grip_frames()["pistol_r"]

# --- Mesh generation ----------------------------------------------------------

static func build_hand(s: float, grip: bool) -> ArrayMesh:
	var st := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	var axis := Vector3(0.0, 0.0, -s) # flexion axis: curls +Y toward the palm (+sX)
	for f in FINGERS:
		var curl: Array = f[5] if grip else f[6]
		if grip and s < 0.0:
			curl = SUPPORT_CURL # the support hand wraps round the gun hand
		var lens: Array = f[3]
		var r0: float = f[4]
		var pos := Vector3(s * KNUCKLE_X, f[2], f[1])
		var dir := Vector3.UP
		# Slight fan: the outer fingers splay away from the middle one.
		var splay: float = (float(f[1]) - 0.008) * (1.6 if grip else 0.45)
		dir = dir.rotated(Vector3.RIGHT, splay)
		var ang := 0.0
		for k in 3:
			ang = deg_to_rad(curl[k])
			dir = dir.rotated(axis, ang).normalized()
			var end: Vector3 = pos + dir * float(lens[k])
			var ra := r0 * (1.0 - 0.09 * k)
			var rb := r0 * (0.91 - 0.09 * k) * (0.92 if k == 2 else 1.0)
			_capsule(st, pos, end, ra, rb, dir.cross(axis).normalized(), k == 2, k > 0)
			pos = end
	# Thumb: metacarpal from the heel of the palm, then two phalanges. In the
	# grip it lies along the far side of the frame pointing forward.
	var tb := Vector3(s * 0.016, 0.018, 0.030)
	var t_dirs := [Vector3(s * 0.35, 0.62, 0.55), Vector3(s * 0.62, 0.70, 0.10), Vector3(s * 0.55, 0.78, -0.20)] if grip \
		else [Vector3(s * 0.22, 0.78, 0.42), Vector3(s * 0.18, 0.92, 0.22), Vector3(s * 0.14, 0.96, 0.12)]
	if grip and s < 0.0:
		# Support thumb lies forward along the frame, over the gun thumb.
		t_dirs = [Vector3(s * 0.30, 0.45, 0.85), Vector3(s * 0.25, 0.20, 1.0), Vector3(s * 0.20, 0.05, 1.0)]
	var t_lens := [0.030, 0.029, 0.024]
	var t_r := [0.0125, 0.0108, 0.0098]
	var tp := tb
	for k in 3:
		var d: Vector3 = (t_dirs[k] as Vector3).normalized()
		var e: Vector3 = tp + d * float(t_lens[k])
		# Thumb nail faces away from the palm and the fingers.
		var dorsal := d.cross(Vector3(0.0, 0.0, 1.0)).normalized() * -s
		if dorsal.length_squared() < 0.01:
			dorsal = Vector3(-s, 0.0, 0.0)
		_capsule(st, tp, e, t_r[k], t_r[k] * 0.9, dorsal, k == 2, k > 0)
		tp = e
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = st["v"]
	arrays[Mesh.ARRAY_NORMAL] = st["n"]
	arrays[Mesh.ARRAY_COLOR] = st["c"]
	arrays[Mesh.ARRAY_INDEX] = st["i"]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## Tapered capsule from a to b (radii ra -> rb), slightly flattened across the
## palm. `dorsal` points to the back of the finger (nail side).
static func _capsule(st: Dictionary, a: Vector3, b: Vector3, ra: float, rb: float, dorsal: Vector3, nail: bool, joint: bool) -> void:
	const RAD := 14
	const LEN := 6
	const CAP := 4
	var ax := (b - a).normalized()
	var u := (dorsal - ax * dorsal.dot(ax)).normalized()
	var w := ax.cross(u).normalized()
	var flat := 0.86 # finger depth (dorsal-palmar) vs width
	var v: PackedVector3Array = st["v"]
	var n: PackedVector3Array = st["n"]
	var c: PackedColorArray = st["c"]
	var idx: PackedInt32Array = st["i"]
	var base := v.size()
	var rows := []
	# Rows: start cap (hemisphere), body, end cap.
	for k in range(CAP, 0, -1):
		var phi := float(k) / CAP * PI * 0.5
		rows.append([-sin(phi), cos(phi), 0.0])
	for k in LEN + 1:
		rows.append([0.0, 1.0, float(k) / LEN])
	for k in range(1, CAP + 1):
		var phi := float(k) / CAP * PI * 0.5
		rows.append([sin(phi), cos(phi), 1.0])
	var length := a.distance_to(b)
	for row in rows:
		var t: float = row[2]
		var r := lerpf(ra, rb, t)
		var centre := a + ax * (length * t + float(row[0]) * r)
		var ring_r := r * float(row[1])
		for j in RAD:
			var th := float(j) / RAD * TAU
			var dv := u * cos(th) * flat + w * sin(th)
			var p := centre + dv * ring_r
			var nn := (u * cos(th) / flat + w * sin(th)) * float(row[1]) + ax * float(row[0])
			v.append(p)
			n.append(nn.normalized())
			var dors := clampf(cos(th), 0.0, 1.0)
			var along := clampf((length * t + float(row[0]) * r) / maxf(length, 0.001), 0.0, 1.0)
			var nail_k := 0.0
			if nail:
				nail_k = smoothstep(0.62, 0.86, cos(th)) * smoothstep(0.32, 0.5, along) * (1.0 - smoothstep(0.96, 1.08, along))
			# Creases sit near each joint on the palm and back; the knuckle ring shows on the back.
			var crease := 0.0
			if joint:
				crease = 1.0 - smoothstep(0.0, 0.22, along)
			var ring := 1.0 - smoothstep(0.0, 0.18, along) if joint else 0.0
			c.append(Color(nail_k, crease, ring, dors))
	var nrows := rows.size()
	for k in nrows - 1:
		for j in RAD:
			var a0 := base + k * RAD + j
			var a1 := base + k * RAD + (j + 1) % RAD
			var b0 := a0 + RAD
			var b1 := a1 + RAD
			idx.append_array(PackedInt32Array([a0, b0, a1, a1, b0, b1]))
	st["v"] = v
	st["n"] = n
	st["c"] = c
	st["i"] = idx

# --- Grip fitted to the held pistol -------------------------------------------

## Hand poses on the gun, in the GUN frame (X right, Y up, -Z barrel, origin
## at the grip): the gun hand's palm lies on the frame's -X side with its
## metacarpals raked 25 degrees down from the bore; the support palm fills
## the +X side, angled steeper, under it.
const GUN_TILT := 0.44
static func hand_in_gun(side_r: bool) -> Transform3D:
	if side_r:
		var t := GUN_TILT
		var y := Vector3(0.0, -sin(t), -cos(t))
		var x := Vector3(1.0, 0.0, 0.0)
		return Transform3D(Basis(x, y, x.cross(y)), Vector3(-0.047, 0.026, 0.066))
	var y2 := Vector3(0.0, -0.62, -0.78).normalized()
	var x2 := Vector3(1.0, 0.0, 0.0)
	return Transform3D(Basis(x2, y2, x2.cross(y2)), Vector3(0.056, -0.004, 0.070))

## Gun pose in each hand's bone space, for AimIkLayer (see its _grip_frame).
static func grip_frames() -> Dictionary:
	return {"pistol_r": hand_in_gun(true).affine_inverse(), "pistol_l": hand_in_gun(false).affine_inverse()}

## Grip cross-section of the held gun: for 6 heights between the bottom of
## the grip and the trigger guard, [y, x half width, z front, z back].
static func grip_profile(weapon: Node3D) -> Array:
	var pts := PackedVector3Array()
	for node in weapon.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != weapon:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for s in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(s)
			for v in (a[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(xf * v)
	var lo := 1e9
	for p in pts:
		lo = minf(lo, p.y)
	var out := []
	if pts.is_empty():
		for k in 6:
			out.append([-0.035 + k * 0.012, 0.015, -0.022, 0.028])
		return out
	# Rear 55 % of the gun only (the trigger guard and barrel sit forward).
	var zmin := 1e9
	var zmax := -1e9
	for p in pts:
		zmin = minf(zmin, p.z)
		zmax = maxf(zmax, p.z)
	var zcut := zmax - (zmax - zmin) * 0.36
	for k in 6:
		var y := lo + 0.008 + k * 0.012
		var hx := 0.0
		var zf := 1e9
		var zb := -1e9
		for p in pts:
			if absf(p.y - y) < 0.006 and p.z > zcut:
				hx = maxf(hx, absf(p.x))
				zf = minf(zf, p.z)
				zb = maxf(zb, p.z)
		if zf > zb:
			zf = -0.02
			zb = 0.028
			hx = 0.015
		out.append([y, clampf(hx, 0.009, 0.022), zf, zb])
	return out

static func _profile_at(profile: Array, y: float) -> Array:
	var best: Array = profile[0]
	for row in profile:
		if absf(float(row[0]) - y) < absf(float(best[0]) - y):
			best = row
	return best

## One finger wrapped round an ellipse (x half A, z half B, centre cx/cz) at
## height y, starting from the knuckle, in the gun frame. dir: +1 wraps from
## the -X side round the front to +X, -1 the other way.
static func _wrap_finger(st: Dictionary, to_hand: Transform3D, knuckle: Vector3, y: float, ax: float, bz: float, cz: float, lens: Array, r0: float, dir: float) -> void:
	var ang := atan2((knuckle.z - cz) / bz, knuckle.x / ax)
	var pts := [knuckle]
	var prev: Vector3 = knuckle
	for k in lens.size():
		var target_len: float = lens[k]
		var p := prev
		var guard := 0
		while prev.distance_to(p) < target_len and guard < 400:
			ang += dir * 0.01
			p = Vector3(ax * cos(ang), y, cz + bz * sin(ang))
			guard += 1
		pts.append(p)
		prev = p
	for k in lens.size():
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var mid := (a + b) * 0.5
		var outward := Vector3(mid.x / (ax * ax), 0.0, (mid.z - cz) / (bz * bz)).normalized()
		var ra := r0 * (1.0 - 0.09 * k)
		var rb := r0 * (0.91 - 0.09 * k) * (0.92 if k == lens.size() - 1 else 1.0)
		_capsule(st, to_hand * a, to_hand * b, ra, rb, to_hand.basis * outward, k == lens.size() - 1, k > 0)

## Polyline finger/thumb through gun-frame points (dorsal side `out`).
static func _path_finger(st: Dictionary, to_hand: Transform3D, pts: Array, r0: float, out: Vector3) -> void:
	for k in pts.size() - 1:
		var ra := r0 * (1.0 - 0.08 * k)
		var rb := r0 * (0.92 - 0.08 * k)
		_capsule(st, to_hand * (pts[k] as Vector3), to_hand * (pts[k + 1] as Vector3), ra, rb, to_hand.basis * out, k == pts.size() - 2, k > 0)

## Gun hand (side_r) or support hand closed on the pistol grip `profile`
## (grip_profile()), in that hand's bone space.
static func build_grip(side_r: bool, profile: Array) -> ArrayMesh:
	var st := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	var hg := hand_in_gun(side_r)
	var to_hand := hg.affine_inverse()
	var s := 1.0 if side_r else -1.0
	var top: Array = profile[profile.size() - 1]
	for fi in FINGERS.size():
		var f: Array = FINGERS[fi]
		var knuckle := hg * Vector3(s * KNUCKLE_X * 0.8, float(f[2]), float(f[1]))
		var lens: Array = f[3]
		var r0: float = f[4]
		if side_r and fi == 0:
			# Index: along the frame into the trigger guard, tip on the trigger.
			var ty := float(top[0]) + 0.004
			var zf := float(top[2])
			_path_finger(st, to_hand, [knuckle, Vector3(-float(top[1]) - 0.006, ty + 0.004, zf - 0.016),
				Vector3(-0.006, ty + 0.002, zf - 0.034), Vector3(0.002, ty - 0.012, zf - 0.036)], r0, Vector3(-1.0, 0.3, 0.0))
			continue
		var row := _profile_at(profile, knuckle.y)
		var y := clampf(knuckle.y, float(profile[0][0]), float(top[0]))
		var hx: float = row[1]
		var zf2: float = row[2]
		var zb: float = row[3]
		var cz := (zf2 + zb) * 0.5
		var bz := (zb - zf2) * 0.5
		var pad := r0 * 0.95 + (0.0 if side_r else 0.021)
		_wrap_finger(st, to_hand, knuckle, y, hx + pad, bz + pad, cz, lens, r0 * (1.0 if side_r else 1.04), s)
	# Thumb.
	var tb := hg * Vector3(s * 0.016, 0.018, 0.030)
	var hx_top := float(top[1])
	if side_r:
		# Over the web behind the back strap, then forward along the far side.
		var ty := float(top[0]) + 0.012
		_path_finger(st, to_hand, [tb, Vector3(-0.004, ty + 0.010, float(top[3]) + 0.018), Vector3(hx_top + 0.012, ty + 0.002, float(top[3]) - 0.006),
			Vector3(hx_top + 0.012, ty, float(top[2]) + 0.004)], 0.0115, Vector3(1.0, 0.4, 0.0))
	else:
		var ty2 := float(top[0]) - 0.006
		_path_finger(st, to_hand, [tb, Vector3(hx_top + 0.026, ty2 - 0.002, float(top[3]) - 0.012), Vector3(hx_top + 0.024, ty2, float(top[2]) + 0.004),
			Vector3(hx_top + 0.021, ty2 + 0.002, float(top[2]) - 0.020)], 0.0118, Vector3(1.0, 0.3, 0.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = st["v"]
	arrays[Mesh.ARRAY_NORMAL] = st["n"]
	arrays[Mesh.ARRAY_COLOR] = st["c"]
	arrays[Mesh.ARRAY_INDEX] = st["i"]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## Re-fits both grip meshes to a newly held pistol.
func fit_weapon(weapon: Node3D, kind: String) -> void:
	if kind != "pistol" or weapon == null:
		return
	var prof := grip_profile(weapon)
	for side in ["r", "l"]:
		if _meshes.has(side + "_grip"):
			(_meshes[side + "_grip"] as MeshInstance3D).mesh = build_grip(side == "r", prof)
