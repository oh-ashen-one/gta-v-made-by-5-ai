extends Node
## Player firearm feel (combat piece): recoil and aim presentation layered on
## top of Player without touching its locomotion.
## - camera kick: the view jumps up (and a hair sideways) on each shot and
##   recovers on a critically damped spring in ~0.18 s; a tiny positional
##   shake sells the report;
## - weapon kick: the pistol flips muzzle-up about the grip and slides back,
##   recovering in ~0.12 s; the arms ride the kick (skeleton layer);
## - aim presentation: a tighter over-the-shoulder framing and narrower FOV
##   while aiming;
## - hip fire raises the gun (Player reads `hold`) so shots never leave a
##   hanging pistol;
## - reload handling sound.
## Shots still resolve along the un-kicked camera ray (Player._fire runs in
## _process before this node applies the kick), so the reticle stays honest.

const AIM_FOV := 55.0
## Aim framing on the spring arm (base 0.85 m right of the body): toward the
## spine and a little lower, so the hero stands on the left third, head to
## waist, with both arms and the pistol reaching into the frame.
const AIM_ARM_OFFSET := Vector3(0.12, 0.16, 0.0)  # integ-Q: higher, looking down over the shoulder onto the extended arms and pistol
var arm_offset := Vector3.ZERO
var player: Node3D
var hold := 0.0                 # seconds the gun stays raised after a shot
var cam_kick := 0.0             # radians, + = view up
var cam_kick_v := 0.0
var cam_yaw_kick := 0.0
var cam_yaw_v := 0.0
var gun_kick := 0.0             # 0..~1.5
var gun_kick_v := 0.0
var shake := 0.0
var aim_blend := 0.0
var last_shot_time := -10.0
var _rng := RandomNumberGenerator.new()
var _was_reloading := false
var _arm_mod: Node = null

func _ready() -> void:
	_rng.seed = 9061
	player = get_parent() as Node3D
	process_priority = 20

## Called by CombatFx when the player fires.
func on_shot(weapon: String) -> void:
	hold = 1.1
	last_shot_time = Time.get_ticks_msec() / 1000.0
	var pistol := weapon == "pistol"
	cam_kick_v += 0.62 if pistol else 0.30
	cam_yaw_v += _rng.randf_range(-0.12, 0.12) if pistol else _rng.randf_range(-0.09, 0.09)
	gun_kick_v += 26.0 if pistol else 16.0
	shake = 1.0 if pistol else 0.7
	_ensure_arm_mod()

func _ensure_arm_mod() -> void:
	if _arm_mod != null and is_instance_valid(_arm_mod):
		return
	var visual: Node = player.get("_visual")
	if visual == null or not visual.get("loaded"):
		return
	var sk: Skeleton3D = visual.get("skeleton")
	if sk == null:
		return
	_arm_mod = ArmKick.new()
	_arm_mod.name = "RecoilLayer"
	sk.add_child(_arm_mod)

func _process(delta: float) -> void:
	if player == null or delta <= 0.0:
		return
	hold = maxf(0.0, hold - delta)
	# Springs: camera (omega 26, critically damped), gun (omega 38).
	# Semi-implicit substeps keep the stiff springs stable at any frame rate.
	var steps := clampi(int(ceil(minf(delta, 0.1) / 0.004)), 1, 25)
	var dt := minf(delta, 0.1) / steps
	for i in steps:
		cam_kick_v += (-cam_kick * 676.0 - cam_kick_v * 52.0) * dt
		cam_kick += cam_kick_v * dt
		cam_yaw_v += (-cam_yaw_kick * 676.0 - cam_yaw_v * 52.0) * dt
		cam_yaw_kick += cam_yaw_v * dt
		gun_kick_v += (-gun_kick * 1444.0 - gun_kick_v * 76.0) * dt
		gun_kick += gun_kick_v * dt
	if not (is_finite(cam_kick) and is_finite(gun_kick) and is_finite(cam_yaw_kick)):
		cam_kick = 0.0; cam_kick_v = 0.0; cam_yaw_kick = 0.0; cam_yaw_v = 0.0; gun_kick = 0.0; gun_kick_v = 0.0
	shake = maxf(0.0, shake - delta * 9.0)
	var aiming: bool = bool(player.get("aiming")) and player.get("current_vehicle") == null
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta * (6.0 if aiming else 4.0))
	_apply_camera()
	_apply_weapon()
	if _arm_mod != null and is_instance_valid(_arm_mod):
		_arm_mod.set("kick", gun_kick)
	var reloading := bool(player.get("_reloading"))
	if reloading and not _was_reloading:
		Sfx.play_at("reload_mag", player.global_position + Vector3.UP * 1.1, -10.0)
	_was_reloading = reloading

func _apply_camera() -> void:
	var camera: Camera3D = player.get("camera")
	if camera == null or not camera.current:
		return
	# The camera's rest pose on the spring arm is unrotated with the arm's
	# length along +Z; only that length is taken from the current transform,
	# so the kick and offsets can never accumulate frame to frame.
	var s := shake * shake
	var offset := Vector3(_rng.randf_range(-1, 1) * 0.012 * s, _rng.randf_range(-1, 1) * 0.010 * s, 0.0)
	# Aiming (wave Q): the framing offset lives on the spring arm itself
	# (`arm_offset`, read by Player._update_camera_follow) so the view and the
	# shot ray share one origin; only shake and kick are applied here.
	arm_offset = AIM_ARM_OFFSET * aim_blend
	var length := camera.transform.origin.z
	var b := Basis(Vector3.UP, cam_yaw_kick) * Basis(Vector3.RIGHT, cam_kick)
	camera.transform = Transform3D(b, Vector3(offset.x, offset.y, length))
	if aim_blend > 0.0:
		camera.fov = lerpf(camera.fov, AIM_FOV, aim_blend)

var _gun_offset := Vector3.ZERO
var _gun_node: Node3D = null

func _apply_weapon() -> void:
	var weapon: Node3D = player.get("_weapon_model")
	if weapon == null or not is_instance_valid(weapon):
		return
	if weapon != _gun_node:
		_gun_node = weapon
		_gun_offset = Vector3.ZERO
	# Undo last frame's slide (CharacterVisual sets the grip position once).
	weapon.position -= _gun_offset
	_gun_offset = Vector3.ZERO
	if absf(gun_kick) < 0.001:
		return
	var k := gun_kick
	weapon.global_basis = weapon.global_basis * Basis(Vector3.RIGHT, k * 0.30)
	_gun_offset = weapon.transform.basis.orthonormalized() * Vector3(0.0, 0.0, 0.035 * k)
	weapon.position += _gun_offset

class ArmKick extends SkeletonModifier3D:
	var kick := 0.0
	var _ids := {}
	var _left := Vector3.LEFT
	var _ready_axes := false

	func _setup() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for bone in ["upper_arm.r", "forearm.r", "upper_arm.l", "forearm.l", "chest", "head"]:
			_ids[bone] = sk.find_bone(bone)
		var xf := Transform3D.IDENTITY
		var node: Node = sk
		var visual := sk.get_parent()
		while visual != null and not (visual is CharacterVisual):
			visual = visual.get_parent()
		while node != null and node != visual:
			if node is Node3D:
				xf = (node as Node3D).transform * xf
			node = node.get_parent()
		_left = (xf.basis.orthonormalized().inverse() * Vector3.LEFT).normalized()
		_ready_axes = true

	func _process_modification_with_delta(_delta: float) -> void:
		if not _ready_axes:
			_setup()
		if absf(kick) < 0.002:
			return
		var k := clampf(kick, -0.6, 1.6)
		_rot("upper_arm.r", -k * 0.10)
		_rot("forearm.r", -k * 0.12)
		_rot("upper_arm.l", -k * 0.08)
		_rot("forearm.l", -k * 0.10)
		_rot("chest", -k * 0.035)
		_rot("head", k * 0.03)

	func _rot(bone: String, angle: float) -> void:
		var id: int = _ids.get(bone, -1)
		if id < 0:
			return
		var sk := get_skeleton()
		var parent := sk.get_bone_parent(id)
		var pg := Basis.IDENTITY
		if parent >= 0:
			pg = sk.get_bone_global_pose(parent).basis.orthonormalized()
		var axis := (pg.inverse() * _left).normalized()
		sk.set_bone_pose_rotation(id, (Quaternion(axis, angle) * sk.get_bone_pose_rotation(id)).normalized())
