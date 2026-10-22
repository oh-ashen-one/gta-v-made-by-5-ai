class_name Ragdoll
extends RefCounted
## Death ragdoll (combat piece, wave Q). On a lethal hit the rigged figure
## hands its skeleton to a physical skeleton built on the fly: 13 capsule
## bodies (pelvis, spine, chest, head, arms, legs) joined with cone joints
## at the spine, neck, shoulders and hips and limited hinges at the elbows
## and knees; a guard clamps runaway speeds and catches a blown-up solve. It starts from the pose of the moment (authored fall clip plus
## flinch), takes the round's push at the chest, then collapses, rolls and
## settles on the ground under gravity, conforming to kerbs and steps,
## instead of freezing in the clip's end pose. The held gun drops free.
## Bodies live on their own collision layer (they collide with the world and
## vehicles; nothing collides with them), so corpses never block the player,
## cars or bullets.

const LAYER := 1 << 9          # ragdoll bodies (layer 10)
const MASK := 1 | 8            # world and vehicles (bodies never end up inside a parked car)
## bone -> [child bone for the capsule axis (or "" = fixed length), radius,
##          mass kg, joint, swing/upper deg, twist/-lower deg]. Hinge axis is
## the character's left; + flexes the knee and the elbow (checked headless:
## the reverse elbow range made bodies launch from the aim pose).
const BODIES := {
	"pelvis": ["", 0.11, 11.0, "none", 0.0, 0.0],
	"spine": ["chest", 0.12, 7.0, "cone", 22.0, 12.0],
	"chest": ["neck", 0.15, 13.0, "cone", 22.0, 12.0],
	"head": ["", 0.105, 5.0, "cone", 38.0, 30.0],
	"upper_arm.l": ["forearm.l", 0.055, 2.4, "cone", 75.0, 35.0],
	"upper_arm.r": ["forearm.r", 0.055, 2.4, "cone", 75.0, 35.0],
	"forearm.l": ["hand.l", 0.04, 1.6, "hinge", 120.0, 2.0],
	"forearm.r": ["hand.r", 0.04, 1.6, "hinge", 120.0, 2.0],
	"thigh.l": ["shin.l", 0.07, 8.5, "cone", 50.0, 18.0],
	"thigh.r": ["shin.r", 0.07, 8.5, "cone", 50.0, 18.0],
	"shin.l": ["foot.l", 0.06, 4.0, "hinge", 45.0, 2.0],
	"shin.r": ["foot.r", 0.06, 4.0, "hinge", 45.0, 2.0],
}
static var active_count := 0
static var started := 0
static var blowups := 0
static var last_blowup := ""

## Start the ragdoll on `visual` (a loaded CharacterVisual). `push` is the
## horizontal direction the killing round travelled; `strength` ~0.5..1.5.
static func start(visual: Node3D, push: Vector3, strength: float = 1.0) -> bool:
	if visual == null or not is_instance_valid(visual) or not visual.is_inside_tree():
		return false
	var sk: Skeleton3D = visual.get("skeleton")
	if sk == null or sk.get_node_or_null("Ragdoll") != null:
		return false
	# Physics bodies cannot carry scale: civilians' stature scale (0.94-1.05)
	# made the joint solve blow up, so the body returns to unit scale here.
	visual.scale = Vector3.ONE
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	sk.add_child(sim)
	var bodies := {}
	var side := _char_left(sk, visual)
	for bone in BODIES:
		var id := sk.find_bone(bone)
		if id < 0:
			continue
		var spec: Array = BODIES[bone]
		var pb := _make_body(sk, id, spec, side)
		sim.add_child(pb)
		bodies[bone] = pb
	_drop_weapon(visual)
	started += 1
	active_count += 1
	_begin.call_deferred(sim, bodies, push, strength)
	return true

static func _char_left(sk: Skeleton3D, visual: Node3D) -> Vector3:
	var l := sk.find_bone("upper_arm.l")
	var r := sk.find_bone("upper_arm.r")
	if l < 0 or r < 0:
		return Vector3.RIGHT
	return (sk.get_bone_global_rest(l).origin - sk.get_bone_global_rest(r).origin).normalized()

static func _make_body(sk: Skeleton3D, id: int, spec: Array, left_axis: Vector3) -> PhysicalBone3D:
	var pb := PhysicalBone3D.new()
	pb.name = "PB_" + sk.get_bone_name(id).replace(".", "_")
	# World-space bodies: the dead actor's root may still be shoved or slide,
	# and a parent transform change must never teleport simulated bodies.
	pb.top_level = true
	pb.bone_name = sk.get_bone_name(id)
	pb.collision_layer = LAYER
	pb.collision_mask = MASK
	pb.mass = float(spec[2])
	pb.friction = 0.9
	pb.bounce = 0.0
	pb.linear_damp = 0.15
	pb.angular_damp = 1.6
	pb.can_sleep = true
	var rest_g := sk.get_bone_global_rest(id)
	var child_name: String = spec[0]
	var axis_local := Vector3(0.0, 0.2 if id == sk.find_bone("pelvis") else 0.22, 0.0)   # bone-local vector to the far end
	if child_name != "":
		var c := sk.find_bone(child_name)
		if c >= 0:
			axis_local = rest_g.affine_inverse() * sk.get_bone_global_rest(c).origin
	var half := maxf(axis_local.length() * 0.5, 0.04)
	var radius := minf(float(spec[1]), half * 0.95)
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(half * 2.0 + radius * 0.6, radius * 2.0 + 0.01)
	var cs := CollisionShape3D.new()
	cs.shape = cap
	# Body frame: origin halfway along the bone, local Y along the bone.
	var y := axis_local.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var body_basis := Basis(x, y, z)
	pb.body_offset = Transform3D(body_basis, axis_local * 0.5)
	pb.add_child(cs)
	# Joint at the bone head (body-local -half along Y).
	var joint: String = spec[3]
	var jb := Basis.IDENTITY
	if joint == "hinge":
		# Hinge axis (joint Z) = the character's left-right axis, in body space.
		var left_bone := rest_g.basis.orthonormalized().inverse() * left_axis
		var left_body := body_basis.inverse() * left_bone
		var hz := left_body.normalized()
		var hy := Vector3.UP - hz * hz.dot(Vector3.UP)
		hy = hy.normalized() if hy.length() > 0.01 else Vector3.FORWARD
		jb = Basis(hy.cross(hz).normalized(), hy, hz)
	pb.joint_offset = Transform3D(jb, Vector3(0.0, -half, 0.0))
	match joint:
		"none":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		"pin":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
			pb.set("joint_constraints/damping", 1.0)
		"cone":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", float(spec[4]))
			pb.set("joint_constraints/twist_span", float(spec[5]))
			pb.set("joint_constraints/softness", 0.9)
			pb.set("joint_constraints/relaxation", 1.0)
		"hinge":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			pb.set("joint_constraints/angular_limit_enabled", true)
			pb.set("joint_constraints/angular_limit_upper", float(spec[4]))
			pb.set("joint_constraints/angular_limit_lower", -float(spec[5]))
			pb.set("joint_constraints/angular_limit_relaxation", 1.0)
	return pb

static func _begin(sim: PhysicalBoneSimulator3D, bodies: Dictionary, push: Vector3, strength: float) -> void:
	if sim == null or not is_instance_valid(sim) or not sim.is_inside_tree():
		return
	await sim.get_tree().process_frame
	if not is_instance_valid(sim):
		return
	sim.physical_bones_start_simulation()
	var p := push
	p.y = 0.0
	p = p.normalized() if p.length() > 0.01 else Vector3.ZERO
	var s := clampf(strength, 0.4, 1.0)   # stronger launches destabilise the joint solve
	# The round's push at the chest and head, knees buckling forward, so the
	# figure folds back and down rather than toppling like a plank.
	for bone in bodies:
		var pb: PhysicalBone3D = bodies[bone]
		if not is_instance_valid(pb):
			continue
		# One shared drift plus a modest extra at the chest and head (large
		# relative velocities between jointed bodies destabilise the solve).
		var v := p * 0.9 * s
		match bone:
			"chest", "head":
				v += p * 0.9 * s
			"spine", "upper_arm.l", "upper_arm.r":
				v += p * 0.5 * s
			"shin.l", "shin.r":
				v -= p * 0.4 * s
		pb.linear_velocity = v
	# Watchdog: a joint fighting its limits must never launch the body.
	var guard := RagdollGuard.new()
	guard.bodies = bodies.values()
	guard.origin = sim.get_skeleton().global_position   # feet / ground level
	sim.add_child(guard)
	# Stop simulating once settled; the bodies stay where they came to rest.
	var tree := sim.get_tree()
	tree.create_timer(9.0, true, true).timeout.connect(func() -> void:
		if is_instance_valid(sim):
			for pb in sim.get_children():
				if pb is PhysicalBone3D:
					(pb as PhysicalBone3D).axis_lock_linear_x = true
					(pb as PhysicalBone3D).axis_lock_linear_y = true
					(pb as PhysicalBone3D).axis_lock_linear_z = true
					(pb as PhysicalBone3D).axis_lock_angular_x = true
					(pb as PhysicalBone3D).axis_lock_angular_y = true
					(pb as PhysicalBone3D).axis_lock_angular_z = true
		active_count = maxi(0, active_count - 1))

## The held gun falls out of the dead hand and clatters to the ground.
static func _drop_weapon(visual: Node3D) -> void:
	var gun: Node3D = visual.get("_weapon_node")
	if gun == null or not is_instance_valid(gun):
		return
	var xf := gun.global_transform
	visual.set("_weapon_node", null)
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.9
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.04, 0.13, 0.19)
	cs.shape = box
	cs.position = Vector3(0.0, 0.03, -0.06)
	body.add_child(cs)
	var root := visual.get_tree().current_scene if visual.get_tree().current_scene != null else visual.get_tree().root
	root.add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	gun.reparent(body, true)
	visual.set_meta("_ragdoll_gun", gun)
	visual.set_meta("_ragdoll_gun_body", body)
	body.linear_velocity = Vector3(randf_range(-0.6, 0.6), 0.8, randf_range(-0.6, 0.6))
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))

## A pooled actor coming back to life: drop the physical skeleton and put the
## gun back in its hand.
static func clear(visual: Node3D) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var sk: Skeleton3D = visual.get("skeleton")
	if sk != null:
		var sim := sk.get_node_or_null("Ragdoll") as PhysicalBoneSimulator3D
		if sim != null:
			sim.physical_bones_stop_simulation()
			sim.name = "RagdollFreed"
			sim.queue_free()
			active_count = maxi(0, active_count - 1)
	if visual.has_meta("_ragdoll_gun"):
		var gun: Node3D = visual.get_meta("_ragdoll_gun")
		var body: Node = visual.get_meta("_ragdoll_gun_body")
		visual.remove_meta("_ragdoll_gun")
		visual.remove_meta("_ragdoll_gun_body")
		if gun != null and is_instance_valid(gun) and visual.has_method("attach_weapon"):
			visual.call("attach_weapon", gun, "pistol")
		if body != null and is_instance_valid(body):
			body.queue_free()

## Clamps runaway body speeds for the first seconds of a ragdoll.
class RagdollGuard extends Node:
	var bodies: Array = []
	var origin := Vector3.ZERO
	var t := 0.0
	var tripped := false
	func _physics_process(delta: float) -> void:
		t += delta
		if t > 4.0:
			set_physics_process(false)
			return
		# A blown-up solve (body flung or through the floor): kill the motion
		# and let gravity settle it again from where it is.
		for b in bodies:
			var q := b as PhysicalBone3D
			if q == null or not is_instance_valid(q):
				continue
			var off := q.global_position - origin
			var core := q.name in [&"PB_pelvis", &"PB_chest", &"PB_head"]
			if (core and off.y < -0.3) or off.y < -1.0 or Vector2(off.x, off.z).length() > 4.0:
				Ragdoll.last_blowup = "y=%.2f h=%.2f %s" % [off.y, Vector2(off.x, off.z).length(), q.name]
				# Fall back to the authored fall clip's end pose (the pre-wave-Q
				# behaviour) rather than leave a body under the floor.
				tripped = true
				Ragdoll.blowups += 1
				var sim := get_parent() as PhysicalBoneSimulator3D
				if sim != null:
					sim.physical_bones_stop_simulation()
					sim.influence = 0.0
				set_physics_process(false)
				return
		var cap := 7.0 if t > 0.1 else 9.0
		for b in bodies:
			var pb := b as PhysicalBone3D
			if pb == null or not is_instance_valid(pb):
				continue
			if pb.linear_velocity.length() > cap:
				pb.linear_velocity = pb.linear_velocity.normalized() * cap
			if pb.angular_velocity.length() > 18.0:
				pb.angular_velocity = pb.angular_velocity.normalized() * 18.0
