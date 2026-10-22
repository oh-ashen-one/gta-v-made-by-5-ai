extends SkeletonModifier3D
## Procedural hit reaction layered after the authored clips (combat piece).
## A struck figure's torso snaps back and twists away from the round, the
## head whips, the arms jerk out and the knees give, on a damped spring that
## settles in ~0.4 s, so every hit reads even mid-clip. A lethal hit drives a
## larger, slower twist that carries into the authored fall.

var _ids := {}
var _dir := Vector3.ZERO        # push direction, skeleton space, horizontal
var _x := 0.0                   # spring displacement (0..~1)
var _v := 0.0
var _twist := 0.0
var _lethal := 0.0
var _side := 1.0
var _up := Vector3.UP
var _fwd := Vector3.FORWARD

func _ready() -> void:
	_cache()

func _cache() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for bone in ["pelvis", "spine", "chest", "neck", "head", "upper_arm.l", "upper_arm.r", "forearm.l", "forearm.r", "thigh.l", "thigh.r", "shin.l", "shin.r"]:
		_ids[bone] = sk.find_bone(bone)
	# Skeleton-space up/forward from the import hierarchy (actor faces -Z).
	var xf := Transform3D.IDENTITY
	var node: Node = sk
	var visual := sk.get_parent()
	while visual != null and not (visual is CharacterVisual):
		visual = visual.get_parent()
	while node != null and node != visual:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	var inv := xf.basis.orthonormalized().inverse()
	_up = (inv * Vector3.UP).normalized()
	_fwd = (inv * Vector3.FORWARD).normalized()

## `world_dir`: horizontal direction the round travelled (attacker -> victim).
func kick(world_dir: Vector3, strength: float, lethal: bool, side: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		_cache()
	var local := (sk.global_basis.orthonormalized().inverse() * world_dir)
	local -= _up * local.dot(_up)
	if local.length() < 0.01:
		local = -_fwd
	_dir = local.normalized()
	_v += 12.0 * strength * (1.4 if lethal else 1.0)
	_side = signf(side) if absf(side) > 0.05 else 1.0
	_twist = clampf(_twist + 0.45 * strength * _side, -0.9, 0.9)
	if lethal:
		_lethal = 1.0

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		_cache()
	# Damped spring (about 0.4 s to settle).
	var steps := clampi(int(ceil(minf(delta, 0.1) / 0.005)), 1, 20)
	var h := minf(delta, 0.1) / steps
	for i in steps:
		_v += (-_x * 120.0 - _v * 13.0) * h
		_x += _v * h
	if not is_finite(_x):
		_x = 0.0
		_v = 0.0
	_twist = lerpf(_twist, 0.0, clampf(delta * (2.0 if _lethal > 0.0 else 6.0), 0.0, 1.0))
	_lethal = maxf(0.0, _lethal - delta * 0.9)
	var amt := clampf(_x, -0.6, 1.4)
	if absf(amt) < 0.002 and absf(_twist) < 0.002:
		return
	var axis := _up.cross(_dir).normalized()   # rotates the top of a bone toward _dir
	_rot("spine", axis, amt * 0.22)
	_rot("chest", axis, amt * 0.30)
	_rot("neck", axis, amt * 0.22)
	_rot("head", axis, amt * 0.35)
	_rot("spine", _up, _twist * 0.35)
	_rot("chest", _up, _twist * 0.45)
	_rot("head", _up, -_twist * 0.3)
	# Arms fling outward and up a little, elbows open.
	var side_axis := _fwd
	_rot("upper_arm.l", side_axis, -amt * 0.35)
	_rot("upper_arm.r", side_axis, amt * 0.35)
	_rot("forearm.l", axis, amt * 0.25)
	_rot("forearm.r", axis, amt * 0.25)
	# Knees give: thighs swing forward, shins fold.
	var left := _fwd.cross(_up).normalized()
	_rot("thigh.l", left, -amt * 0.12)
	_rot("thigh.r", left, -amt * 0.12)
	_rot("shin.l", left, amt * 0.22)
	_rot("shin.r", left, amt * 0.22)

func _rot(bone: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.00005:
		return
	var id: int = _ids.get(bone, -1)
	if id < 0:
		return
	var sk := get_skeleton()
	var parent := sk.get_bone_parent(id)
	var parent_global := Basis.IDENTITY
	if parent >= 0:
		parent_global = sk.get_bone_global_pose(parent).basis.orthonormalized()
	var local_axis := (parent_global.inverse() * axis).normalized()
	sk.set_bone_pose_rotation(id, (Quaternion(local_axis, angle) * sk.get_bone_pose_rotation(id)).normalized())
