class_name CharacterMotionModifier
extends SkeletonModifier3D
## Procedural layer applied after the authored clip each frame (on-foot piece).
## - stride: scales hip/knee/arm swing so long strides match fast ground speed
##   (the run clip natively covers ~2.9 m/s; sprint needs ~1.45x the stride
##   so the playback rate, not foot sliding, carries the remaining speed);
## - lean: spine/chest pitch (acceleration, sprint) and roll (turns);
## - head look: neck + head turn toward the camera's view direction;
## - breathing: a slow chest/shoulder rise at rest.
## All inputs are smoothed by the owner; this node only applies them.

var stride_amp := 1.0          # 1.0 = authored clip
var lean_pitch := 0.0          # radians, + = forward
var lean_roll := 0.0           # radians, + = toward the character's left
var look_yaw := 0.0            # radians relative to the body, + = left
var look_pitch := 0.0          # radians, + = down
var breath := 0.0              # 0..1 weight of idle breathing
var _t := 0.0
var _ids := {}
# Character frame in skeleton space (set by CharacterVisual from the import
# hierarchy): forward = facing direction, left = the character's left.
var forward_axis := Vector3.FORWARD
var left_axis := Vector3.LEFT
# Idle-clip rotations used as the neutral pose for stride amplification (the
# bind pose is an A-pose, so amplifying from it would fold the arms inward).
var reference := {}

func capture_reference() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		_cache()
	for bone in _ids:
		var id: int = _ids[bone]
		if id >= 0:
			reference[bone] = sk.get_bone_pose_rotation(id)

func _ready() -> void:
	_cache()

func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_ids.clear()
	_cache()

func _cache() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for bone in ["pelvis", "spine", "chest", "neck", "head", "thigh.l", "thigh.r", "shin.l", "shin.r",
			"upper_arm.l", "upper_arm.r", "forearm.l", "forearm.r", "clavicle.l", "clavicle.r"]:
		_ids[bone] = sk.find_bone(bone)

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		_cache()
	_t += delta
	if absf(stride_amp - 1.0) > 0.01:
		_amplify("thigh.l", stride_amp)
		_amplify("thigh.r", stride_amp)
		_amplify("shin.l", 1.0 + (stride_amp - 1.0) * 0.55)
		_amplify("shin.r", 1.0 + (stride_amp - 1.0) * 0.55)
		_amplify("upper_arm.l", 1.0 + (stride_amp - 1.0) * 0.8)
		_amplify("upper_arm.r", 1.0 + (stride_amp - 1.0) * 0.8)
		_amplify("forearm.l", 1.0 + (stride_amp - 1.0) * 0.5)
		_amplify("forearm.r", 1.0 + (stride_amp - 1.0) * 0.5)
	# Lean: split pitch and roll over spine and chest so the back curves
	# instead of hinging at one joint. Bone-local axes are unknown for this
	# provider rig, so rotations are composed in model space.
	var breathe := sin(_t * TAU / 4.2) * breath
	# Rotating about the character's left axis tilts the top forward/down;
	# about its back axis tilts it toward the left.
	var pitch_axis := left_axis
	var roll_axis := -forward_axis
	_rotate_model_space("spine", pitch_axis, lean_pitch * 0.55)
	_rotate_model_space("chest", pitch_axis, lean_pitch * 0.45 - breathe * 0.018)
	_rotate_model_space("spine", roll_axis, lean_roll * 0.5)
	_rotate_model_space("chest", roll_axis, lean_roll * 0.5)
	_rotate_model_space("clavicle.l", forward_axis, breathe * 0.02)
	_rotate_model_space("clavicle.r", forward_axis, -breathe * 0.02)
	# Relaxed stance at rest: arms hang slightly away from the body with soft
	# elbows, and the weight drifts between the legs every few seconds, so the
	# idle figure is a person standing rather than a mannequin.
	if breath > 0.01:
		var sway := sin(_t * TAU / 6.5) * breath
		_rotate_model_space("upper_arm.l", forward_axis, -0.075 * breath)
		_rotate_model_space("upper_arm.r", forward_axis, 0.075 * breath)
		_rotate_model_space("forearm.l", left_axis, -(0.20 + breathe * 0.02) * breath)
		_rotate_model_space("forearm.r", left_axis, -(0.20 + breathe * 0.02) * breath)
		_rotate_model_space("pelvis", roll_axis, sway * 0.03)
		_rotate_model_space("chest", roll_axis, -sway * 0.035)
	# Head look (40 % neck, 60 % head), counter-rotating the chest lean so
	# the eyes stay level while running.
	_rotate_model_space("neck", Vector3.UP, look_yaw * 0.4)
	_rotate_model_space("head", Vector3.UP, look_yaw * 0.6)
	_rotate_model_space("neck", pitch_axis, look_pitch * 0.4 - lean_pitch * 0.45)
	_rotate_model_space("head", pitch_axis, look_pitch * 0.6 - lean_pitch * 0.4)

## Scale the clip's rotation away from the bind pose by `amount`.
func _amplify(bone: String, amount: float) -> void:
	var id: int = _ids.get(bone, -1)
	if id < 0:
		return
	var sk := get_skeleton()
	var rest: Quaternion = reference.get(bone, sk.get_bone_rest(id).basis.get_rotation_quaternion())
	var pose := sk.get_bone_pose_rotation(id)
	var d := rest.inverse() * pose
	if d.w < 0.0:
		d = -d
	var angle := d.get_angle()
	if angle < 0.0001:
		return
	var scaled := Quaternion(d.get_axis().normalized(), clampf(angle * amount, -2.6, 2.6))
	sk.set_bone_pose_rotation(id, rest * scaled)

## Rotate a bone by `angle` about a model-space axis, keeping children attached.
func _rotate_model_space(bone: String, axis: Vector3, angle: float) -> void:
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
	var pose := sk.get_bone_pose_rotation(id)
	sk.set_bone_pose_rotation(id, (Quaternion(local_axis, angle) * pose).normalized())
