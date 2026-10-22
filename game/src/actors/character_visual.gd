class_name CharacterVisual
extends Node3D
## Textured provider humanoid with Blender-authored skeletal animation.
## Presentation only: the owning Player/NPC remains the authority for physics,
## health, facing, weapon damage and vehicle transitions.

const PROVIDER_DIR := "res://assets/providers/"
const LOOP_CLIPS := ["idle", "walk", "run", "aim", "aim_walk", "aim_run", "jump", "seated", "drive"]
const WARDROBE := [
	Color(1.0, 1.0, 1.0), Color(1.20, 1.34, 1.12),
	Color(1.26, 1.10, 1.02), Color(0.94, 1.14, 1.36),
	Color(1.38, 1.30, 1.10), Color(1.20, 0.96, 1.06),
]

var model: Node3D
var skeleton: Skeleton3D
var animator: AnimationPlayer
var weapon_socket: BoneAttachment3D
var asset_role := "player"
var loaded := false
var ignore_simulation_pause := false # Explicitly enabled only by pose-review fixtures.
var _manual_pause := false
var _clips: Dictionary = {}
var _current := ""
var _one_shot := false
var _dead := false
var _last_speed := 0.0
var _last_aim := false
var _last_grounded := true
var _last_reload := false
var _weapon_node: Node3D
var _aim_pitch := 0.0
var _weapon_kind := "pistol"
var _phase_offset := 0.0
var _seated := false
var _driving_pose := false

static func available(role: String = "player") -> bool:
	return ResourceLoader.exists(PROVIDER_DIR + role + "_rigged.glb")

const NPC_DRAW_RANGE := 150.0

func configure(role: String = "player", wardrobe_variant: int = 0) -> bool:
	asset_role = role
	_phase_offset = fmod(float(get_instance_id() % 997) / 997.0 + float(wardrobe_variant) * 0.137, 1.0)
	if not available(role):
		push_warning("Rigged character missing: " + role + "_rigged.glb")
		return false
	var packed := load(PROVIDER_DIR + role + "_rigged.glb") as PackedScene
	if packed == null:
		return false
	model = packed.instantiate() as Node3D
	if model == null:
		return false
	add_child(model)
	skeleton = _find_type(model, "Skeleton3D") as Skeleton3D
	animator = _find_type(model, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or animator == null:
		push_warning("Character import has no skeleton/animation player: " + role)
		model.queue_free()
		return false
	for full_name in animator.get_animation_list():
		var key := String(full_name).get_slice("/", String(full_name).get_slice_count("/") - 1)
		key = key.get_slice("|", key.get_slice_count("|") - 1)
		_clips[key] = String(full_name)
		var clip := animator.get_animation(full_name)
		clip.loop_mode = Animation.LOOP_LINEAR if key in LOOP_CLIPS else Animation.LOOP_NONE
	animator.animation_finished.connect(_on_animation_finished)
	if role == "civilian":
		_apply_wardrobe(model, WARDROBE[posmod(wardrobe_variant, WARDROBE.size())])
		var stature := 0.94 + float(posmod(wardrobe_variant, 7)) * 0.017
		scale = Vector3(stature, stature, stature)
	if role != "player":
		# Ambient figures are not drawn beyond 150 m of the camera (wave 5 perf).
		for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
			(mesh_node as MeshInstance3D).visibility_range_end = NPC_DRAW_RANGE
	weapon_socket = BoneAttachment3D.new()
	weapon_socket.name = "WeaponSocket"
	weapon_socket.bone_name = "hand.r"
	skeleton.add_child(weapon_socket)
	loaded = true
	_play("idle", 0.0)
	return true

func set_motion(speed: float, aiming: bool = false, grounded: bool = true, reloading: bool = false) -> void:
	_last_speed = speed
	_last_aim = aiming
	_last_grounded = grounded
	_last_reload = reloading
	if not loaded or _dead or _one_shot:
		return
	if _seated:
		_play("drive" if _driving_pose else "seated", 0.22)
		return
	var clip := "idle"
	var rate := 1.0
	if not grounded:
		clip = "jump"
	elif reloading:
		clip = "reload"
	elif speed > 2.5:
		clip = "aim_run" if aiming else "run"
		rate = clampf(speed / 4.5, 0.70, 1.55)
	elif speed > 0.18:
		clip = "aim_walk" if aiming else "walk"
		rate = clampf(speed / 1.65, 0.60, 1.55)
	elif aiming:
		clip = "aim"
	_play(clip, 0.16, rate)

func set_seated(seated: bool, driving: bool = false) -> void:
	_seated = seated
	_driving_pose = driving
	set_motion(_last_speed, _last_aim, _last_grounded, _last_reload)

func play_hit() -> void:
	if not loaded or _dead:
		return
	_one_shot = true
	_play("hit", 0.045)

func play_death() -> void:
	if not loaded or _dead:
		return
	_dead = true
	_one_shot = false
	set_lod_far(false)
	_play("fall", 0.08)

func reset_alive() -> void:
	_dead = false
	_one_shot = false
	_seated = false
	_driving_pose = false
	_current = ""
	if loaded:
		_play("idle", 0.0)

func attach_weapon(weapon: Node3D, weapon_kind: String = "pistol") -> void:
	if weapon_socket == null or weapon == null:
		return
	if weapon.get_parent() != null:
		weapon.reparent(weapon_socket, false)
	else:
		weapon_socket.add_child(weapon)
	_weapon_node = weapon
	_weapon_kind = weapon_kind
	if asset_role != "player":
		for mesh_node in weapon.find_children("*", "MeshInstance3D", true, false):
			(mesh_node as MeshInstance3D).visibility_range_end = NPC_DRAW_RANGE
	# *_held.glb derivatives face -Z and place their origin at the grip.
	# At rest the muzzle hangs along the fingers; aiming stabilizes the barrel
	# on the body's forward axis while its grip follows the animated wrist.
	weapon.position = Vector3(0.0, 0.055, -0.012)
	weapon.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	process_priority = 10

func set_aim_pitch(value: float) -> void:
	_aim_pitch = clampf(value, -1.1, 0.85)

func weapon_muzzle_position() -> Vector3:
	if _weapon_node == null or not is_instance_valid(_weapon_node):
		return global_position + Vector3(0.0, 1.3, -0.4)
	var forward_offset := 0.44 if _weapon_kind == "smg" else 0.15
	return _weapon_node.to_global(Vector3(0.0, 0.045, -forward_offset))

func _process(_delta: float) -> void:
	_update_animation_activity()
	if _weapon_node == null or not is_instance_valid(_weapon_node):
		return
	if _last_aim or _last_reload:
		_weapon_node.global_basis = global_transform.basis.orthonormalized() * Basis(Vector3.RIGHT, _aim_pitch)
	else:
		_weapon_node.rotation = Vector3(PI * 0.5, 0.0, 0.0)

func set_paused(paused: bool) -> void:
	_manual_pause = paused
	_update_animation_activity()

## Render LOD (wave 5): beyond the meshes' visibility range the figure is not
## drawn, so its animation need not advance either.
var _lod_far := false
func set_lod_far(far: bool) -> void:
	if far == _lod_far: return
	_lod_far = far
	_update_animation_activity()

func _update_animation_activity() -> void:
	if animator != null:
		var should_run := not (_manual_pause or _lod_far or (Game.simulation_paused and not ignore_simulation_pause))
		if animator.active != should_run:
			animator.active = should_run

func _play(clip: String, crossfade: float, rate: float = 1.0) -> void:
	if not _clips.has(clip):
		clip = "idle"
	if not _clips.has(clip):
		return
	animator.speed_scale = rate
	if _current == clip:
		return
	_current = clip
	animator.play(_clips[clip], crossfade)
	if asset_role != "player" and clip in LOOP_CLIPS:
		animator.seek(_phase_offset * animator.get_animation(_clips[clip]).length, true)

func _on_animation_finished(_animation: StringName) -> void:
	if _dead:
		return
	_one_shot = false
	_current = ""
	set_motion(_last_speed, _last_aim, _last_grounded, _last_reload)

func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_type(child, type_name)
		if found != null:
			return found
	return null

func _apply_wardrobe(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for i in mesh_instance.mesh.get_surface_count():
				var mat := mesh_instance.mesh.surface_get_material(i)
				if mat is StandardMaterial3D and String(mat.resource_name).contains("CharacterClothing"):
					var copy := mat.duplicate() as StandardMaterial3D
					copy.albedo_color = tint
					mesh_instance.set_surface_override_material(i, copy)
	for child in node.get_children():
		_apply_wardrobe(child, tint)
