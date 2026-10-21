class_name CharacterVisual
extends Node3D
## Textured provider humanoid with Blender-authored skeletal animation.
## Presentation only: the owning Player/NPC remains the authority for physics,
## health, facing, weapon damage and vehicle transitions.

const PROVIDER_DIR := "res://assets/providers/"
const LOOP_CLIPS := ["idle", "walk", "run", "aim", "aim_walk", "aim_run", "jump"]
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
var _clips: Dictionary = {}
var _current := ""
var _one_shot := false
var _dead := false
var _last_speed := 0.0
var _last_aim := false
var _last_grounded := true
var _last_reload := false

static func available(role: String = "player") -> bool:
	return ResourceLoader.exists(PROVIDER_DIR + role + "_rigged.glb")

func configure(role: String = "player", wardrobe_variant: int = 0) -> bool:
	asset_role = role
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
	_play("fall", 0.08)

func reset_alive() -> void:
	_dead = false
	_one_shot = false
	_current = ""
	if loaded:
		_play("idle", 0.0)

func attach_weapon(weapon: Node3D) -> void:
	if weapon_socket == null or weapon == null:
		return
	if weapon.get_parent() != null:
		weapon.reparent(weapon_socket, false)
	else:
		weapon_socket.add_child(weapon)
	# Bone local Y follows the fingers. Provider guns face Godot -Z.
	weapon.position = Vector3(0.0, 0.085, -0.018)
	weapon.rotation = Vector3(PI * 0.5, 0.0, 0.0)

func set_paused(paused: bool) -> void:
	if animator != null:
		animator.active = not paused

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
