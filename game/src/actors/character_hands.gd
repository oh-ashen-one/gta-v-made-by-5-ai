class_name CharacterHands
extends SkeletonModifier3D
## Characters piece (wave Q2): real hands for the player.
##
## The provider body has mitten hands (one finger block). CharacterLook folds
## that block flat onto the knuckle line; this node draws jointed fingers and
## a thumb (tapered capsules, nails, knuckle creases) on BoneAttachment3Ds of
## hand.r / hand.l, in two poses: a fist closed round the pistol grip and a
## relaxed curl. The pistol sits inside the gun hand's finger loop.
##
## While aiming a pistol it also runs last in the skeleton's modifier stack:
## two-bone IK raises both arms so the pistol sits at eye line, the gun
## hand's wrist turns the slide onto the aim direction, and the support hand
## cups the grip from the other side with its thumb forward along the frame.

## Hand-bone-local frame (both hands): +Y wrist -> knuckles, +Z thumb side,
## palm normal = +X on hand.r and -X on hand.l.
const KNUCKLE_Y := 0.082
# [name, knuckle z, knuckle y, segment lengths, base radius, grip curl (MCP, PIP, DIP) deg, relaxed curl]
const FINGERS := [
	["index", 0.028, 0.080, [0.040, 0.024, 0.019], 0.0102, [62.0, 78.0, 30.0], [18.0, 26.0, 14.0]],
	["middle", 0.009, 0.083, [0.043, 0.027, 0.020], 0.0105, [86.0, 92.0, 22.0], [22.0, 30.0, 16.0]],
	["ring", -0.010, 0.080, [0.040, 0.025, 0.019], 0.0098, [90.0, 92.0, 22.0], [26.0, 34.0, 18.0]],
	["pinky", -0.027, 0.073, [0.032, 0.019, 0.017], 0.0088, [94.0, 90.0, 24.0], [30.0, 38.0, 20.0]],
]
## Knuckles sit this far toward the palm from the bone axis.
const KNUCKLE_X := 0.020
## Pistol pose inside the gun hand's fist (bone-local), see attach_weapon().
const PISTOL_POS := Vector3(0.040, 0.052, 0.030)
const PISTOL_TILT := 0.20 # radians: the grip rakes back like a real frame
## Support palm centre in the gun hand's frame, and the palm centre's offset
## from the support wrist in its own frame.
const SUPPORT_PALM := Vector3(0.040, 0.070, -0.070)
const SUPPORT_CURL := [70.0, 80.0, 35.0]
const SUPPORT_WRIST := Vector3(-0.030, 0.050, 0.0)

var skin_linear := Color(0.55, 0.33, 0.22)
var holding := false
var aiming := false
var weapon_kind := "pistol"
var aim_pitch := 0.0
var actor: Node3D
var weapon: Node3D
## 0..1 blend of the aim IK (eased in and out by the owner's frames).
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

## Places a pistol in the closed gun hand (bone-local transform).
static func weapon_transform(kind: String) -> Transform3D:
	if kind != "pistol":
		return Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.055, -0.012))
	var b := Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.RIGHT, -PISTOL_TILT)
	return Transform3D(b, PISTOL_POS)

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
		var splay: float = (float(f[1]) - 0.010) * 1.6
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
		else [Vector3(s * 0.32, 0.62, 0.60), Vector3(s * 0.38, 0.80, 0.42), Vector3(s * 0.40, 0.85, 0.30)]
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

# --- Aim IK -------------------------------------------------------------------

func _cache_ids() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in ["upper_arm.r", "forearm.r", "hand.r", "upper_arm.l", "forearm.l", "hand.l", "head", "chest"]:
		_ids[b] = sk.find_bone(b)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or actor == null or ik_weight <= 0.001 or weapon_kind != "pistol":
		return
	if _ids.is_empty():
		_cache_ids()
	for k in _ids:
		if _ids[k] < 0:
			return
	var sx := sk.global_transform
	var inv := sx.affine_inverse()
	var ab := actor.global_basis.orthonormalized()
	var fwd := -ab.z
	var up := ab.y
	var right := ab.x
	var wb := ab * Basis(Vector3.RIGHT, aim_pitch)
	var wfwd := -wb.z
	var wup := wb.y
	# Eye line: the rear sight sits ~3 cm under the eye, ~0.45 m ahead.
	var head := sx * sk.get_bone_global_pose(_ids["head"]).origin
	var eye := head + up * 0.095 + fwd * 0.075
	var wt := weapon_transform("pistol")
	var grip_world := eye + wfwd * 0.43 - wup * 0.115 + right * 0.0
	# Gun hand: hand basis so the weapon's local basis lands on the aim basis.
	var hand_b := wb * wt.basis.inverse()
	var wrist_world := grip_world - hand_b * wt.origin
	_solve_arm(sk, sx, inv, "r", wrist_world, hand_b, right, up, fwd)
	# Support hand: cups the gun hand from below on the far side of the grip,
	# palm up and inward, fingers wrapping over the gun hand's fingers, thumb
	# forward along the frame.
	var xg := wb.x
	var n_palm := (-xg * 0.72 + wup * 0.69).normalized()
	var xl := -n_palm
	var yl := -xg - xl * (-xg).dot(xl)
	yl = yl.normalized()
	var zl := xl.cross(yl).normalized()
	var l_b := Basis(xl, yl, zl)
	var support_palm := grip_world + hand_b * SUPPORT_PALM
	var wrist_l := support_palm - l_b * SUPPORT_WRIST
	_solve_arm(sk, sx, inv, "l", wrist_l, l_b, right, up, fwd)

## Two-bone IK in skeleton space (shortest-arc swings keep the clip's twist),
## then the hand orientation, blended by ik_weight.
func _solve_arm(sk: Skeleton3D, sx: Transform3D, inv: Transform3D, side: String, wrist_world: Vector3, hand_world: Basis, right: Vector3, up: Vector3, fwd: Vector3) -> void:
	var iu: int = _ids["upper_arm." + side]
	var i_f: int = _ids["forearm." + side]
	var ih: int = _ids["hand." + side]
	var pu := sk.get_bone_global_pose(iu)
	var pf := sk.get_bone_global_pose(i_f)
	var ph := sk.get_bone_global_pose(ih)
	var s := pu.origin
	var e := pf.origin
	var w := ph.origin
	var l1 := s.distance_to(e)
	var l2 := e.distance_to(w)
	var t := inv * wrist_world
	t = w.lerp(t, ik_weight)
	var st := t - s
	var dist := clampf(st.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.995)
	var dir := st.normalized()
	t = s + dir * dist
	# Elbows drop down and out.
	var side_sign := 1.0 if (sx * s - sx * sk.get_bone_global_pose(_ids["chest"]).origin).dot(right) > 0.0 else -1.0
	var pole_world := sx * s + (-up * 0.6 + right * side_sign * 0.45 - fwd * 0.15)
	var pole := inv * pole_world - s
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pd := (pole - dir * pole.dot(dir))
	pd = pd.normalized() if pd.length_squared() > 1e-8 else up
	var e2 := s + dir * a + pd * h
	var q1 := _arc(e - s, e2 - s)
	sk.set_bone_global_pose(iu, Transform3D(Basis(q1) * pu.basis, s))
	pf = sk.get_bone_global_pose(i_f)
	ph = sk.get_bone_global_pose(ih)
	var q2 := _arc(ph.origin - pf.origin, t - pf.origin)
	sk.set_bone_global_pose(i_f, Transform3D(Basis(q2) * pf.basis, pf.origin))
	ph = sk.get_bone_global_pose(ih)
	var hb := (inv.basis * hand_world).orthonormalized()
	var cur := ph.basis.orthonormalized()
	var blended := Basis(cur.get_rotation_quaternion().slerp(hb.get_rotation_quaternion(), ik_weight))
	sk.set_bone_global_pose(ih, Transform3D(blended.scaled(ph.basis.get_scale()), ph.origin))

static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var d := a.dot(b)
	if d > 0.99999:
		return Quaternion.IDENTITY
	var ax := a.cross(b)
	if ax.length_squared() < 1e-10:
		return Quaternion.IDENTITY
	return Quaternion(ax.normalized(), acos(clampf(d, -1.0, 1.0)))
