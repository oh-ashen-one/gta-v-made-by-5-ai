class_name FootLockModifier
extends SkeletonModifier3D
## Planted-foot locking with analytic two-bone leg IK (locomotion-Q).
## Runs after the authored clip and the procedural motion layer. Whenever the
## animated ankle is down at stance height, its world X/Z position is pinned
## where it touched down and the thigh/shin are re-solved so the shoe stays on
## the paving while the body moves over it (turning, accelerating, blending
## between gaits, aim-strafing). The authored foot height and roll are kept.
## When the clip lifts the foot, or the pinned point drifts too far from the
## animated one, the lock blends out over a few frames. Player only.

var lock_allowed := true          # owner clears it in the air, while skidding, seated...
var ground_ref: Node3D            # CharacterVisual: its origin is the sole plane
var stance_height := 0.13         # ankle height above the sole with a flat foot
var plant_margin := 0.028
var release_dist := 0.30          # m; beyond this the leg re-plants instead of stretching
var blend_out := 0.09             # s
var _legs: Array[Dictionary] = []
var debug_locked := [false, false]

func _cache() -> void:
	_legs.clear()
	var sk := get_skeleton()
	if sk == null:
		return
	for side in ["l", "r"]:
		var leg := {"thigh": sk.find_bone("thigh." + side), "shin": sk.find_bone("shin." + side),
			"foot": sk.find_bone("foot." + side), "locked": false, "lock": Vector3.ZERO, "w": 0.0, "cool": 0.0}
		if int(leg["thigh"]) >= 0 and int(leg["shin"]) >= 0 and int(leg["foot"]) >= 0:
			_legs.append(leg)

func reset_locks() -> void:
	for leg in _legs:
		leg["locked"] = false
		leg["w"] = 0.0

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or ground_ref == null:
		return
	# Paused pose review / photo stills: the authored pose, nothing pinned.
	if Game.simulation_paused:
		reset_locks()
		return
	if _legs.is_empty():
		_cache()
		if _legs.is_empty():
			return
	var sk_xf := sk.global_transform
	var sk_inv := sk_xf.affine_inverse()
	var ref_inv := ground_ref.global_transform.affine_inverse()
	var i := 0
	for leg in _legs:
		var foot_pose := sk.get_bone_global_pose(leg["foot"])
		var ankle_w := sk_xf * foot_pose.origin
		var h := (ref_inv * ankle_w).y
		leg["cool"] = maxf(0.0, float(leg["cool"]) - delta)
		var down := lock_allowed and h < stance_height + plant_margin
		if down and not leg["locked"] and float(leg["cool"]) <= 0.0:
			# Touch-down: pin where the animated foot is now (or where the
			# still-blending previous pin shows it, so nothing pops).
			var shown: Vector3 = ankle_w.lerp(Vector3(leg["lock"].x, ankle_w.y, leg["lock"].z), _ease(leg["w"]))
			leg["lock"] = shown
			leg["locked"] = true
			leg["w"] = 1.0
		elif leg["locked"]:
			var drift := Vector2(ankle_w.x - leg["lock"].x, ankle_w.z - leg["lock"].z).length()
			if not down:
				leg["locked"] = false
			elif drift > release_dist:
				leg["locked"] = false
				leg["cool"] = blend_out * 1.4
		if not leg["locked"]:
			leg["w"] = move_toward(float(leg["w"]), 0.0, delta / blend_out)
		debug_locked[i] = leg["locked"]
		i += 1
		var w: float = _ease(leg["w"])
		if w <= 0.001:
			continue
		var pinned := Vector3(leg["lock"].x, ankle_w.y, leg["lock"].z)
		_solve(sk, leg, sk_inv * ankle_w.lerp(pinned, w))

static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

## Analytic two-bone IK in skeleton space; the knee keeps its animated bend
## plane, the foot keeps its animated orientation.
func _solve(sk: Skeleton3D, leg: Dictionary, target: Vector3) -> void:
	var thigh_id: int = leg["thigh"]
	var shin_id: int = leg["shin"]
	var foot_id: int = leg["foot"]
	var hip_t := sk.get_bone_global_pose(thigh_id)
	var knee_t := sk.get_bone_global_pose(shin_id)
	var foot_t := sk.get_bone_global_pose(foot_id)
	var hip := hip_t.origin
	var knee := knee_t.origin
	var ankle := foot_t.origin
	var a := hip.distance_to(knee)
	var b := knee.distance_to(ankle)
	if a < 0.01 or b < 0.01:
		return
	var to_t := target - hip
	if to_t.length() < 0.01:
		return
	var d := clampf(to_t.length(), absf(a - b) + 0.002, a + b - 0.002)
	var dir := to_t.normalized()
	var cur := (ankle - hip).normalized()
	var pole := (knee - hip) - cur * (knee - hip).dot(cur)
	pole = pole - dir * pole.dot(dir)
	if pole.length() < 0.0005:
		return
	pole = pole.normalized()
	var along := (a * a - b * b + d * d) / (2.0 * d)
	var bend := sqrt(maxf(0.0, a * a - along * along))
	var new_knee := hip + dir * along + pole * bend
	var new_ankle := hip + dir * d
	var r1 := Quaternion((knee - hip).normalized(), (new_knee - hip).normalized())
	hip_t.basis = Basis(r1) * hip_t.basis
	sk.set_bone_global_pose(thigh_id, hip_t)
	var knee_now := sk.get_bone_global_pose(shin_id)
	var ankle_now := sk.get_bone_global_pose(foot_id).origin
	var v_from := ankle_now - knee_now.origin
	var v_to := new_ankle - knee_now.origin
	if v_from.length() > 0.001 and v_to.length() > 0.001:
		knee_now.basis = Basis(Quaternion(v_from.normalized(), v_to.normalized())) * knee_now.basis
		sk.set_bone_global_pose(shin_id, knee_now)
	var foot_now := sk.get_bone_global_pose(foot_id)
	foot_now.basis = foot_t.basis
	sk.set_bone_global_pose(foot_id, foot_now)
