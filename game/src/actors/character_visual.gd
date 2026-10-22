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

# On-foot piece: ground speed each locomotion clip covers at rate 1.0, measured
# from the provider clips' mid-stance foot-bone travel (walk 1.41 m/s, run
# 4.28 m/s; whole-stance run average 3.7 m/s) and checked in rendered footage.
# Playback rate = ground speed / clip speed keeps planted feet from sliding.
const WALK_CLIP_SPEED := 1.45
const RUN_CLIP_SPEED := 4.0
const RUN_THRESHOLD := 2.1
const LOCOMOTION := ["walk", "run", "aim_walk", "aim_run"]
var motion: CharacterMotionModifier
var stride_amp := 1.0
var walk_arm := 0.0
# Contact shadows (on-foot round C2): one soft dark decal under each foot plus
# a wider pelvis blob, so the shoes read as touching the paving in close shots.
var contact_shadows: Array[Decal] = []
var _foot_ids := PackedInt32Array()
## Characters piece: the rebuilt skinned mesh and its wardrobe (empty when the
## rig could not be processed and the legacy materials are in use).
var look_mesh: MeshInstance3D
var outfit: Dictionary = {}

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
	_upgrade_materials(model)
	# Characters piece: region-aware rebuilt mesh + shared wardrobe shader for
	# the player and civilian rigs (officers keep their authored uniform).
	look_mesh = CharacterLook.apply(model) if role != "officer" else null
	if look_mesh != null:
		if role == "player":
			outfit = CharacterLook.player_outfit()
		else:
			outfit = CharacterLook.civilian_outfit(get_instance_id() + wardrobe_variant * 7919)
			var stature: float = outfit["height"]
			scale = Vector3(stature, stature, stature)
		CharacterLook.set_outfit(look_mesh, outfit)
	elif role == "civilian":
		_apply_wardrobe(model, WARDROBE[posmod(wardrobe_variant, WARDROBE.size())])
		var stature := 0.94 + float(posmod(wardrobe_variant, 7)) * 0.017
		scale = Vector3(stature, stature, stature)
	if role != "player":
		# Ambient figures are not drawn beyond 150 m of the camera (wave 5 perf).
		for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
			(mesh_node as MeshInstance3D).visibility_range_end = NPC_DRAW_RANGE
	if role == "player":
		_player_look(model)
		motion = CharacterMotionModifier.new()
		motion.name = "MotionLayer"
		skeleton.add_child(motion)
		_set_motion_frame()
		_build_contact_shadows()
	weapon_socket = BoneAttachment3D.new()
	weapon_socket.name = "WeaponSocket"
	weapon_socket.bone_name = "hand.r"
	skeleton.add_child(weapon_socket)
	loaded = true
	_play("idle", 0.0)
	if motion != null:
		animator.seek(0.0, true)
		motion.capture_reference()
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
	var crossfade := 0.28
	var amp := 1.0
	if not grounded:
		clip = "jump"
		crossfade = 0.12
	elif reloading:
		clip = "reload"
		crossfade = 0.16
	elif speed > RUN_THRESHOLD:
		clip = "aim_run" if aiming else "run"
		# Fast running lengthens the stride (procedural layer, player only)
		# before it raises cadence, as real sprinting does.
		if motion != null:
			amp = clampf(1.0 + (speed - 3.6) / 3.2 * 0.25, 1.0, 1.25)
		rate = clampf(speed / (RUN_CLIP_SPEED * amp), 0.72, 2.0)
	elif speed > 0.18:
		clip = "aim_walk" if aiming else "walk"
		rate = clampf(speed / WALK_CLIP_SPEED, 0.45, 1.8)
	elif aiming:
		clip = "aim"
		crossfade = 0.18
	stride_amp = amp
	walk_arm = 1.0 if clip == "walk" else 0.0
	if motion != null:
		motion.stride_amp = lerpf(motion.stride_amp, amp, 0.2)
		motion.arm_swing = lerpf(motion.arm_swing, walk_arm, 0.15)
		motion.breath = lerpf(motion.breath, 1.0 if clip in ["idle", "aim"] else 0.0, 0.05)
	_play(clip, crossfade, rate)

## Lean and head-look inputs for the procedural layer (player only).
func set_body_motion(lean_pitch: float, lean_roll: float, look_yaw: float, look_pitch: float) -> void:
	if motion == null:
		return
	motion.lean_pitch = lean_pitch
	motion.lean_roll = lean_roll
	motion.look_yaw = look_yaw
	motion.look_pitch = look_pitch

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
	_update_contact_shadows()
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
	# Walk <-> run (and aim variants) keep the gait phase so the feet never
	# jump to a different step during the blend.
	var phase := -1.0
	if _current in LOCOMOTION and clip in LOCOMOTION and animator.current_animation != "":
		var cur_len := animator.current_animation_length
		if cur_len > 0.0:
			phase = fmod(animator.current_animation_position, cur_len) / cur_len
	_current = clip
	animator.play(_clips[clip], crossfade)
	if phase >= 0.0:
		animator.seek(phase * animator.get_animation(_clips[clip]).length, false)
	elif asset_role != "player" and clip in LOOP_CLIPS:
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


## Render layer 11 carries the player's own fill/rim lights (Player camera).
const PLAYER_LIGHT_LAYER := 1 << 10
## The player's meshes also sit on render layer 11 so his own fill/rim lights
## (on the Player camera) touch only him.
## The provider rig is shared with the black-shirted crowd, so the
## protagonist's overshirt is re-dyed a washed olive-khaki in a shader: only the
## near-black overshirt texels are recoloured, with their luminance compressed
## (not multiplied) so baked fold shading survives without blowing out, and the
## grey tee underneath keeps its texture. Cloth folds now read at close range.
const PLAYER_CLOTH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, sss_mode_skin;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 dye : source_color = vec3(0.29, 0.26, 0.19);
uniform float normal_strength = 1.6;
uniform float force_dye = 0.0;
// Skin/details surface variant: it also carries the overshirt's hem and cuff
// texels, so dark texels are dyed only between waist and shoulder height
// (hair and shoes stay as authored) and the rest is shaded as skin.
uniform bool skin_surface = false;
varying float body_y;
void vertex() {
	body_y = VERTEX.y;
}
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float sat = (max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b))) / max(max(c.r, max(c.g, c.b)), 0.0001);
	// Near-black overshirt texels, plus its brownish hem/cuff texels; the
	// neutral grey tee stays as authored.
	float dark = max(1.0 - smoothstep(0.08, 0.16, l), (1.0 - smoothstep(0.22, 0.34, l)) * smoothstep(0.10, 0.25, sat));
	float shade = clamp(pow(max(l, 0.0005) / 0.016, 0.3), 0.72, 1.3);
	if (skin_surface) {
		dark *= step(0.82, body_y) * (1.0 - step(1.47, body_y)) * (1.0 - smoothstep(0.035, 0.07, l));
	}
	ALBEDO = mix(c, dye * shade, max(dark, force_dye));
	vec4 orm = texture(orm_tex, UV);
	ROUGHNESS = clamp(orm.g, 0.6, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.3;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.25;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	RIM = skin_surface ? 0.22 : 0.45;
	RIM_TINT = skin_surface ? 0.55 : 0.8;
	if (skin_surface) {
		ROUGHNESS = clamp(orm.g * 0.82, 0.3, 1.0);
		SPECULAR = 0.42;
		AO = 1.0; // the authored skin material had no occlusion term
		SSS_STRENGTH = 0.32 * (1.0 - dark);
	}
}
"""

func _player_look(node: Node) -> void:
	var shader := Shader.new()
	shader.code = PLAYER_CLOTH_SHADER
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		mi.layers = 1 | PLAYER_LIGHT_LAYER
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if look_mesh != null or mat == null or mat.albedo_texture == null:
				continue
			var is_skin := String(mat.resource_name).contains("Skin")
			if not (is_skin or String(mat.resource_name).contains("CharacterClothing")):
				continue
			var cloth := ShaderMaterial.new()
			cloth.shader = shader
			cloth.set_shader_parameter("skin_surface", is_skin)
			if is_skin:
				cloth.set_shader_parameter("normal_strength", 1.15)
			cloth.set_shader_parameter("albedo_tex", mat.albedo_texture)
			if mat.normal_texture != null:
				cloth.set_shader_parameter("normal_tex", mat.normal_texture)
			if mat.roughness_texture != null:
				cloth.set_shader_parameter("orm_tex", mat.roughness_texture)
			mi.set_surface_override_material(i, cloth)

## Skeleton-space facing and left axes from the imported hierarchy, so the
## procedural layer leans the right way whatever the glTF root rotation is.
func _set_motion_frame() -> void:
	var xf := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != null and node != self:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	var inv := xf.basis.orthonormalized().inverse()
	# The owning actor faces -Z.
	motion.forward_axis = (inv * Vector3.FORWARD).normalized()
	motion.left_axis = (inv * Vector3.LEFT).normalized()

## Character shading (on-foot piece). The provider export marks skin and
## cloth fully metallic and leaves them without any sheen, which renders the
## figure as a dull, dark plastic in shade. Real dielectric response, skin
## subsurface scattering and a soft cloth rim make the figure read as a person
## at close third-person range. Shared imported materials are upgraded once.
static func _upgrade_materials(root: Node) -> void:
	for mesh_node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mesh_node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null or mat.has_meta("orchard_upgraded"):
				continue
			mat.set_meta("orchard_upgraded", true)
			var mat_name := String(mat.resource_name)
			if mat_name.contains("Skin"):
				mat.metallic = 0.0
				mat.metallic_specular = 0.42
				mat.roughness = 0.82
				mat.subsurf_scatter_enabled = true
				mat.subsurf_scatter_strength = 0.32
				mat.subsurf_scatter_skin_mode = true
				mat.rim_enabled = true
				mat.rim = 0.22
				mat.rim_tint = 0.55
				mat.normal_scale = 1.15
			elif mat_name.contains("Clothing"):
				mat.metallic = 0.0
				mat.metallic_specular = 0.28
				mat.rim_enabled = true
				mat.rim = 0.55
				mat.rim_tint = 0.85
				mat.normal_scale = 1.55
			elif mat_name.contains("Textile"):
				mat.metallic_specular = 0.25
				mat.rim_enabled = true
				mat.rim = 0.5
				mat.rim_tint = 0.8


static var _contact_tex: Texture2D
static func _contact_texture() -> Texture2D:
	if _contact_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.92), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_contact_tex = t
	return _contact_tex

func _build_contact_shadows() -> void:
	_foot_ids.clear()
	for bone in ["foot.l", "foot.r"]:
		var id := skeleton.find_bone(bone)
		if id < 0:
			id = skeleton.find_bone(bone.replace("foot", "toe"))
		_foot_ids.append(id)
	var sizes := [Vector3(0.34, 0.7, 0.46), Vector3(0.34, 0.7, 0.46), Vector3(0.85, 0.7, 0.68)]
	for i in 3:
		var d := Decal.new()
		d.name = "ContactShadow%d" % i
		d.texture_albedo = _contact_texture()
		d.size = sizes[i]
		d.modulate = Color(1, 1, 1, 0.85 if i < 2 else 0.5)
		d.albedo_mix = 1.0
		d.upper_fade = 0.25
		d.lower_fade = 0.6
		d.top_level = true
		add_child(d)
		contact_shadows.append(d)
	_update_contact_shadows()

func _update_contact_shadows() -> void:
	if contact_shadows.is_empty() or skeleton == null:
		return
	var visible_now := is_visible_in_tree() and not _seated
	# Ankle bones sit ~0.09 m above the sole; the lower ankle marks the ground
	# (works whatever height the visual root sits at, and on stairs/kerbs).
	var feet: Array[Vector3] = []
	for id in _foot_ids:
		feet.append(skeleton.global_transform * skeleton.get_bone_global_pose(id).origin if id >= 0 else global_position)
	var ground := minf(feet[0].y, feet[1].y) - 0.09
	var yaw := global_basis.get_euler().y
	for i in contact_shadows.size():
		var d := contact_shadows[i]
		d.visible = visible_now
		if not visible_now:
			continue
		var p := global_position
		var lift := 0.0
		if i < 2:
			p = feet[i]
			lift = maxf(p.y - ground - 0.12, 0.0)
		# A raised foot casts a fainter, softer contact shadow.
		var k := clampf(1.0 - lift / 0.25, 0.0, 1.0)
		d.modulate.a = (0.85 if i < 2 else 0.5) * (0.25 + 0.75 * k)
		d.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, ground + 0.05, p.z))
