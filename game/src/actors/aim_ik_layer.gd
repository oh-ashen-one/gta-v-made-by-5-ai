class_name AimIkLayer
extends SkeletonModifier3D
## Upper-body aim and reload layer (combat piece, wave Q).
## Runs after the authored clip and the motion layer, before recoil/flinch.
## - Aim: the spine, chest, neck and head turn and pitch onto the barrel
##   line, the gun is placed on the line of the right eye (sights at eye
##   height, ~0.45 m out) and two-bone IK puts the right hand on the grip and
##   the left hand wrapped around it (support grip; SMG: on the foregrip),
##   elbows down and out. The character therefore looks down the sights in
##   every aimed frame, whatever the clip or camera.
## - Reload: a procedural magazine change. The gun comes in to chest height
##   and cants, the empty magazine drops free (a small physical prop), the
##   support hand goes to the belt, brings a fresh magazine to the grip, seats
##   it, racks the slide and returns to the support grip; the head follows the
##   gun throughout.
## The gun itself is placed after all modifiers (skeleton_updated), relative
## to the final hand, so recoil and flinch layers still carry it.

const LAYER_NAME := "AimIkLayer"
const GRIP_POS := Vector3(0.0, 0.055, -0.012)   # CharacterVisual's held-gun offset
const SIGHT_H := 0.09                            # sight line above the grip origin (pistol_held AABB top)
const GUN_SEAT := Vector3(0.0, -0.04, 0.015)     # gun frame: grip seated deeper in the fist, slide just above it
const EYE_OFF := Vector3(0.032, 0.095, 0.088)    # (toward .r side, up, forward) from head bone
const AIM_DROP := 0.15     # integ-Q: grip this far under the sight line below the eye
const AIM_ACROSS := 0.0   # integ-Q: gun across the eye toward the camera (".l") side

var visual: Node3D
var weight := 0.0
var reload_t := -1.0
var reload_len := 1.5
var stats := {"aim_frames": 0, "reload_frames": 0, "mags_dropped": 0, "sight_err": 0.0, "gun_out": 0.0}

var _ids := {}
var _rest := {}
var _F := Vector3.FORWARD
var _U := Vector3.UP
var _R := Vector3.LEFT     # the rig's ".r" side
var _ready_axes := false
var _gun_rel := Basis.IDENTITY     # gun basis relative to the final right hand
var _gun_pos := GRIP_POS
var _gun_driven := false
var _mag_hand: MeshInstance3D
var _mag_show := false
var _mag_dropped := false
var _hand_l_xf := Transform3D.IDENTITY
var _connected := false
var _reset_gun := false

static func ensure(v: Node3D) -> AimIkLayer:
	if v == null:
		return null
	var sk: Skeleton3D = v.get("skeleton")
	if sk == null:
		return null
	var existing := sk.get_node_or_null(LAYER_NAME) as AimIkLayer
	if existing != null:
		return existing
	var layer := AimIkLayer.new()
	layer.name = LAYER_NAME
	layer.visual = v
	sk.add_child(layer)
	var motion := sk.get_node_or_null("MotionLayer")
	if motion != null:
		sk.move_child(layer, motion.get_index() + 1)
	return layer

func _ready() -> void:
	_setup()

func _setup() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in ["pelvis", "spine", "chest", "neck", "head", "clavicle.l", "clavicle.r", "upper_arm.l", "forearm.l", "hand.l",
			"upper_arm.r", "forearm.r", "hand.r", "fingers.l", "fingers.r"]:
		_ids[b] = sk.find_bone(b)
		if _ids[b] >= 0:
			_rest[b] = sk.get_bone_global_rest(_ids[b])
	if int(_ids["upper_arm.r"]) < 0 or int(_ids["head"]) < 0:
		return
	# Character frame in skeleton space from the import hierarchy (actor faces -Z).
	var xf := Transform3D.IDENTITY
	var node: Node = sk
	while node != null and node != visual:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	var inv := xf.basis.orthonormalized().inverse()
	_U = (inv * Vector3.UP).normalized()
	_F = (inv * Vector3.FORWARD).normalized()
	var r: Vector3 = (_rest["upper_arm.r"] as Transform3D).origin - (_rest["upper_arm.l"] as Transform3D).origin
	_R = (r - _U * r.dot(_U)).normalized()
	_mag_hand = _make_mag()
	_mag_hand.top_level = true
	_mag_hand.visible = false
	add_child(_mag_hand)
	if not _connected:
		sk.skeleton_updated.connect(_place_gun)
		_connected = true
	_ready_axes = true

static func _make_mag() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.024, 0.105, 0.034)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.07, 0.075)
	mat.metallic = 0.75
	mat.roughness = 0.38
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Brass of the top round.
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.012, 0.012, 0.028)
	top.mesh = tb
	var bm2 := StandardMaterial3D.new()
	bm2.albedo_color = Color(0.78, 0.58, 0.25)
	bm2.metallic = 0.9
	bm2.roughness = 0.3
	top.material_override = bm2
	top.position = Vector3(0.0, 0.056, 0.0)
	mi.add_child(top)
	return mi

func _process_modification_with_delta(delta: float) -> void:
	if not _ready_axes:
		_setup()
		if not _ready_axes:
			return
	var v := visual
	if v == null or not is_instance_valid(v):
		return
	var gun: Node3D = v.get("_weapon_node")
	var has_gun := gun != null and is_instance_valid(gun) and gun.is_visible_in_tree()
	var alive := not bool(v.get("_dead")) and not bool(v.get("_seated"))
	var aim := has_gun and alive and bool(v.get("_last_aim"))
	var reloading := has_gun and alive and bool(v.get("_last_reload"))
	var kind := String(v.get("_weapon_kind"))
	if reloading:
		if reload_t < 0.0:
			reload_t = 0.0
			reload_len = 2.1 if kind == "smg" else 1.5
			_mag_dropped = false
		reload_t += delta
	else:
		reload_t = -1.0
		_mag_show = false
	var want := 1.0 if (aim or reloading) else 0.0
	weight = move_toward(weight, want, delta * (8.0 if want > weight else 5.0))
	if weight <= 0.001:
		if _gun_driven:
			_gun_driven = false
			_reset_gun = true
		_mag_show = false
		return
	var sk := get_skeleton()
	var w := smoothstep(0.0, 1.0, weight)
	var inv_b := sk.global_basis.orthonormalized().inverse()
	var pitch := float(v.get("_aim_pitch"))
	var vis_b: Basis = v.global_basis.orthonormalized()
	var D := (inv_b * (vis_b * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD)).normalized()
	var flat := D - _U * D.dot(_U)
	if flat.length() < 0.05:
		flat = _F
	flat = flat.normalized()
	var L := -_R
	var yaw := _F.signed_angle_to(flat, _U)
	var side := flat.cross(_U).normalized()
	var theta := flat.signed_angle_to(D, side)
	var rf := 0.0   # reload progress 0..1 (or -1)
	if reloading:
		rf = clampf(reload_t / reload_len, 0.0, 1.0)
		stats["reload_frames"] += 1
	else:
		stats["aim_frames"] += 1
	# During a reload the torso stays on the aim yaw but the eyes drop to the gun.
	var torso_pitch := theta if not reloading else theta * 0.3
	_orient("spine", _rot(yaw * 0.55, torso_pitch * 0.25, side), w)
	_orient("chest", _rot(yaw, torso_pitch * 0.5, side), w)
	_orient("neck", _rot(yaw, torso_pitch * 0.75, side), w)
	# Head pitched ~8 deg down onto the sights, which sit just under the eye line.
	var head_pitch := theta - 0.15
	var head_yaw := yaw
	if reloading:
		# Eyes on the magazine well: ~35 deg down and a little toward the gun.
		var kh := _bump(rf, 0.04, 0.14, 0.84, 0.97)
		head_pitch = lerpf(theta, -0.62, kh)

	# Head cants a touch toward the gun side, as people do over pistol sights.
	var head_rot := Quaternion(D if not reloading else flat, -0.07) * _rot(head_yaw, head_pitch, side)
	_orient("head", head_rot, w)
	# Eye (right eye, the sighting eye) after the head pose.
	var hg := sk.get_bone_global_pose(_ids["head"])
	var eye := hg.origin + (head_rot * (_R * EYE_OFF.x + _U * EYE_OFF.y + _F * EYE_OFF.z))
	var ua := (_U - D * _U.dot(D)).normalized()
	# Desired gun frame (skeleton space): origin = grip, -Z = barrel, +Y = top.
	var s_r: Vector3 = sk.get_bone_global_pose(_ids["upper_arm.r"]).origin
	var reach := _arm_len("r") * 0.985
	var og := Vector3.ZERO
	# Gun ~0.5 m out, 7 cm right of the sighting eye and ~8 cm under it
	# (head canted onto the sights, GTA-style): the barrel line still runs
	# past the eye, and from the over-the-shoulder camera the pistol and
	# right hand clear the head instead of hiding in front of the face.
	var lat := (_R - D * _R.dot(D)).normalized()
	var t := 0.62
	while t > 0.24:
		# integ-Q: the rig's ".r" side is screen-left from the right-shoulder
		# camera, so a gun pushed toward ".r" sat exactly behind the head
		# (cam-frame probe: head x/z -0.52, gun -0.52) and the raised arm read
		# as a phone held to the ear. The gun now sits just across the
		# centreline toward the camera side and a little under the chin, so
		# from the OTS camera it shows beside the head, arms reaching to it.
		og = eye + D * t - ua * (SIGHT_H + AIM_DROP) - lat * AIM_ACROSS
		var gb0 := _gun_basis(D, ua)
		var wr := og - _hand_from_gun(gb0) * GRIP_POS - gb0 * GUN_SEAT
		if wr.distance_to(s_r) <= reach:
			break
		t -= 0.025
	stats["gun_out"] = t
	var gb := _gun_basis(D, ua)
	if reloading:
		var hold_o := eye + flat * 0.22 - _U * 0.36 + L * 0.07
		var bar := (flat * 0.80 + _U * 0.40 + L * 0.42).normalized()
		var up2 := _U - bar * _U.dot(bar)
		up2 = (up2.normalized() * 0.75 + _R * 0.66)
		up2 = (up2 - bar * up2.dot(bar)).normalized()
		var hold_b := Basis.looking_at(bar, up2)
		var k := _bump(rf, 0.0, 0.13, 0.86, 1.0)
		og = og.lerp(hold_o, k)
		gb = Basis(gb.get_rotation_quaternion().slerp(hold_b.get_rotation_quaternion(), k))
	var hr := _hand_from_gun(gb)
	var wr_t := og - hr * GRIP_POS - gb * GUN_SEAT
	_two_bone("r", wr_t, -_U + _R * 0.75 - flat * 0.15, hr, w)
	# Support hand.
	var hl := hr
	var wl_t: Vector3
	if kind == "smg":
		wl_t = og - gb.z * 0.20 - gb.y * 0.035 + L * 0.015
		hl = _hand_from_gun(gb)
	else:
		wl_t = wr_t - D * 0.03 + L * 0.052 - ua * 0.012
	if reloading:
		var r_res := _reload_left(rf, og, gb, flat, L)
		var kr := _bump(rf, 0.10, 0.16, 0.86, 0.94)
		wl_t = wl_t.lerp(r_res[0], kr)
		hl = Basis(hl.get_rotation_quaternion().slerp((r_res[1] as Basis).get_rotation_quaternion(), kr))
		if not _mag_dropped and rf > 0.16:
			_mag_dropped = true
			_drop_mag(sk.global_transform * og, sk.global_basis.orthonormalized() * gb)
		_mag_show = rf > 0.34 and rf < 0.66
	_two_bone("l", wl_t, -_U + L * 0.75 - flat * 0.15, hl, w)
	_gun_rel = Basis(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)).get_rotation_quaternion().slerp((hr.inverse() * gb).get_rotation_quaternion(), w))
	_gun_pos = GRIP_POS + (hr.inverse() * (gb * GUN_SEAT)) * w
	_gun_driven = true
	if aim and w > 0.95 and not reloading:
		# QA: angle between the barrel and the eye-to-sight line.
		var sight := og + ua * SIGHT_H
		stats["sight_err"] = rad_to_deg((sight - eye).normalized().angle_to(D))

## Smooth 0->1->0 window: rises over [a,b], holds, falls over [c,d].
static func _bump(x: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x))

func _rot(yaw: float, pitch: float, side: Vector3) -> Quaternion:
	return Quaternion(side, pitch) * Quaternion(_U, yaw)

func _gun_basis(barrel: Vector3, up: Vector3) -> Basis:
	return Basis.looking_at(barrel, up)

## Right-hand bone basis that holds a gun with basis `gb` (from the authored
## aim clip: fingers down-forward round the grip, thumb along the slide).
func _hand_from_gun(gb: Basis) -> Basis:
	var fwd := -gb.z
	var up := gb.y
	var z := (fwd * 0.84 + up * 0.55).normalized()
	var y := (fwd * 0.55 - up * 0.84).normalized()
	return Basis(y.cross(z), y, z).orthonormalized()

## Left-hand reload path: [wrist target, hand basis].
func _reload_left(rf: float, og: Vector3, gb: Basis, flat: Vector3, L: Vector3) -> Array:
	var sk := get_skeleton()
	var pelvis: Vector3 = sk.get_bone_global_pose(_ids["pelvis"]).origin
	var grip_bottom := og - gb.y * 0.12 + gb.z * 0.01
	var belt := pelvis + L * 0.15 + flat * 0.06 + _U * 0.02
	var slide_front := og + gb.y * 0.075 - gb.z * 0.05
	var slide_back := og + gb.y * 0.075 + gb.z * 0.06
	var hand_down := Basis((-_U).cross(flat).normalized(), -_U, flat).orthonormalized()
	var push_b := _hand_from_gun(Basis.looking_at(-gb.y, gb.z))
	var over_b := Basis.looking_at(-gb.z, gb.y)
	over_b = Basis(over_b.x, (-gb.y * 0.4 + _R * 0.9).normalized(), over_b.z).orthonormalized()
	var keys := [
		[0.16, grip_bottom - gb.y * 0.05, hand_down],
		[0.30, belt, hand_down],
		[0.40, belt, hand_down],
		[0.56, grip_bottom - gb.y * 0.06, push_b],
		[0.64, grip_bottom + gb.y * 0.02, push_b],
		[0.72, slide_front, over_b],
		[0.82, slide_back, over_b],
		[0.90, slide_back + gb.y * 0.03, over_b],
	]
	if rf <= float(keys[0][0]):
		return [keys[0][1], keys[0][2]]
	for i in range(1, keys.size()):
		if rf <= float(keys[i][0]):
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var k := smoothstep(float(a[0]), float(b[0]), rf)
			var bq := (a[2] as Basis).get_rotation_quaternion().slerp((b[2] as Basis).get_rotation_quaternion(), k)
			return [(a[1] as Vector3).lerp(b[1], k), Basis(bq)]
	var last: Array = keys[keys.size() - 1]
	return [last[1], last[2]]

func _arm_len(s: String) -> float:
	var u: Transform3D = _rest["upper_arm." + s]
	var f: Transform3D = _rest["forearm." + s]
	var h: Transform3D = _rest["hand." + s]
	return u.origin.distance_to(f.origin) + f.origin.distance_to(h.origin)

## Rotate `bone` so its global basis becomes rot * rest, blended by w.
func _orient(bone: String, rot: Quaternion, w: float) -> void:
	var id: int = _ids.get(bone, -1)
	if id < 0:
		return
	var rest: Transform3D = _rest[bone]
	var want := Basis(rot) * rest.basis.orthonormalized()
	_set_global(id, want, w)

func _set_global(id: int, want: Basis, w: float) -> void:
	var sk := get_skeleton()
	var cur := sk.get_bone_global_pose(id).basis.orthonormalized()
	var q := cur.get_rotation_quaternion().slerp(want.orthonormalized().get_rotation_quaternion(), w)
	var parent := sk.get_bone_parent(id)
	var pg := Basis.IDENTITY
	if parent >= 0:
		pg = sk.get_bone_global_pose(parent).basis.orthonormalized()
	sk.set_bone_pose_rotation(id, (pg.inverse() * Basis(q)).get_rotation_quaternion().normalized())

func _aim_bone(id: int, child: int, target: Vector3, w: float) -> void:
	var sk := get_skeleton()
	var g := sk.get_bone_global_pose(id)
	var cur_dir := sk.get_bone_global_pose(child).origin - g.origin
	var want_dir := target - g.origin
	if cur_dir.length() < 1e-4 or want_dir.length() < 1e-4:
		return
	var q := Quaternion(cur_dir.normalized(), want_dir.normalized())
	_set_global(id, Basis(q) * g.basis.orthonormalized(), w)

func _two_bone(s: String, target: Vector3, pole: Vector3, hand_basis: Basis, w: float) -> void:
	var sk := get_skeleton()
	var u: int = _ids["upper_arm." + s]
	var f: int = _ids["forearm." + s]
	var h: int = _ids["hand." + s]
	if u < 0 or f < 0 or h < 0:
		return
	var su := sk.get_bone_global_pose(u).origin
	var l1 := (_rest["upper_arm." + s] as Transform3D).origin.distance_to((_rest["forearm." + s] as Transform3D).origin)
	var l2 := (_rest["forearm." + s] as Transform3D).origin.distance_to((_rest["hand." + s] as Transform3D).origin)
	var to := target - su
	var d := clampf(to.length(), absf(l1 - l2) + 0.02, (l1 + l2) * 0.995)
	var dir := to.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var hgt := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pp := pole - dir * pole.dot(dir)
	if pp.length() < 1e-3:
		pp = -_U - dir * (-_U).dot(dir)
	var elbow := su + dir * a + pp.normalized() * hgt
	_aim_bone(u, f, elbow, w)
	_aim_bone(f, h, su + dir * d, w)
	_set_global(h, hand_basis, w)

## After every modifier: the gun follows the final right hand (so recoil and
## flinch carry it); the fresh magazine rides in the left palm.
func _place_gun() -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var gun: Node3D = visual.get("_weapon_node")
	var sk := get_skeleton()
	if gun == null or not is_instance_valid(gun) or sk == null:
		return
	if not _gun_driven:
		if _mag_hand != null:
			_mag_hand.visible = false
		if _reset_gun:
			_reset_gun = false
			gun.position = GRIP_POS
			gun.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		return
	var hr := sk.global_transform * sk.get_bone_global_pose(_ids["hand.r"])
	var hb := hr.basis.orthonormalized()
	gun.global_transform = Transform3D(hb * _gun_rel, hr * _gun_pos)
	var hl := sk.global_transform * sk.get_bone_global_pose(_ids["hand.l"])
	_hand_l_xf = hl
	if _mag_hand != null:
		_mag_hand.visible = _mag_show
		if _mag_show:
			var lb := hl.basis.orthonormalized()
			_mag_hand.global_transform = Transform3D(lb, hl * Vector3(0.0, 0.075, 0.03))

func _drop_mag(at: Vector3, gun_basis: Basis) -> void:
	stats["mags_dropped"] += 1
	var tree := get_tree()
	if tree == null:
		return
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.25
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.024, 0.105, 0.034)
	cs.shape = box
	body.add_child(cs)
	var mesh := _make_mag()
	body.add_child(mesh)
	if tree.current_scene != null:
		tree.current_scene.add_child(body)
	else:
		tree.root.add_child(body)
	body.global_transform = Transform3D(gun_basis, at - gun_basis.y * 0.09)
	body.linear_velocity = -gun_basis.y * 1.6 + Vector3.DOWN * 0.5
	body.angular_velocity = gun_basis.z * 6.0
	tree.create_timer(6.0).timeout.connect(body.queue_free)
