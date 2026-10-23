class_name PeoplePose
extends SkeletonModifier3D
## Pose layer for people holding something, elders' stoop and a child's head.
## Runs after the AnimationPlayer each frame on this figure's skeleton.
var pose := ""
var processed := 0
var stoop := 0.0
var head_scale := 1.0
var _ids := {}
var _far := false
var _far_check := 0

## Upper-arm lift and elbow flex (radians about character +X) for each pose.
const ARM := {"phone": Vector2(0.3, 1.27), "cup": Vector2(0.2, 1.2), "umbrella": Vector2(0.05, 1.32)}

func _id(sk: Skeleton3D, bone: String) -> int:
	if not _ids.has(bone):
		_ids[bone] = sk.find_bone(bone)
	return _ids[bone]

## Hand rest transform after the pose's arm lift and elbow flex, built from
## rest globals (character space), so props can be authored for the pose.
static func posed_hand_rest(sk: Skeleton3D, hand: String) -> Transform3D:
	var hid := sk.find_bone(hand)
	var fid := sk.get_bone_parent(hid)
	var uid := sk.get_bone_parent(fid)
	var a := ARM["phone"]
	var meta := sk.get_parent()
	while meta != null and not meta.has_meta("people"):
		meta = meta.get_parent()
	if meta != null:
		var p: Dictionary = meta.get_meta("people")
		a = ARM.get(String(p.get("prop", "phone")), a)
	var ug := sk.get_bone_global_rest(uid)
	var fg := sk.get_bone_global_rest(fid)
	var hg := sk.get_bone_global_rest(hid)
	var r1 := Basis(Vector3.RIGHT, a.x)
	var r2 := Basis(Vector3.RIGHT, a.x + a.y)
	var elbow := ug.origin + r1 * (fg.origin - ug.origin)
	var wrist := elbow + r2 * (hg.origin - fg.origin)
	return Transform3D(r2 * hg.basis, wrist)

func _process_modification_with_delta(_delta: float) -> void:
	processed += 1
	var sk := get_skeleton()
	if sk == null:
		return
	# Perf: beyond 60 m (where the props are no longer drawn) the pose is
	# not worth a GDScript pass every frame; re-checked every 16 frames.
	_far_check -= 1
	if _far_check <= 0:
		_far_check = 16
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		_far = cam != null and cam.global_position.distance_squared_to(sk.global_position) > 3600.0
	if _far:
		return
	if stoop > 0.0:
		_rot(sk, _id(sk, "spine"), -stoop * 0.35)
		_rot(sk, _id(sk, "chest"), -stoop * 0.65)
		_rot(sk, _id(sk, "neck"), stoop * 0.55)
	if head_scale != 1.0:
		var h := _id(sk, "head")
		if h >= 0:
			sk.set_bone_pose_scale(h, Vector3.ONE * head_scale)
	if ARM.has(pose):
		var a: Vector2 = ARM[pose]
		var u := _id(sk, "upper_arm.l")
		var f := _id(sk, "forearm.l")
		var hd := _id(sk, "hand.l")
		if u >= 0 and f >= 0 and hd >= 0:
			sk.set_bone_pose_rotation(u, sk.get_bone_rest(u).basis.get_rotation_quaternion())
			sk.set_bone_pose_rotation(f, sk.get_bone_rest(f).basis.get_rotation_quaternion())
			sk.set_bone_pose_rotation(hd, sk.get_bone_rest(hd).basis.get_rotation_quaternion())
			var fi := _id(sk, "fingers.l")
			if fi >= 0:
				sk.set_bone_pose_rotation(fi, sk.get_bone_rest(fi).basis.get_rotation_quaternion())
			_rot(sk, u, a.x)
			_rot(sk, f, a.y)
		if pose == "phone":
			_rot(sk, _id(sk, "neck"), -0.22)
			_rot(sk, _id(sk, "head"), -0.2)

## Rotate bone `id` about character +X (skeleton space is character space)
## by `angle` at its own origin.
func _rot(sk: Skeleton3D, id: int, angle: float) -> void:
	if id < 0:
		return
	var parent := sk.get_bone_parent(id)
	var pg := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var local_axis := (pg.inverse() * Vector3.RIGHT).normalized()
	sk.set_bone_pose_rotation(id, (Quaternion(local_axis, angle) * sk.get_bone_pose_rotation(id)).normalized())
