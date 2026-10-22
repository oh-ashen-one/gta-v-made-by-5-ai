class_name Player
extends CharacterBody3D
## Third-person player: locomotion, camera, aiming, firearms, interaction.
## One authoritative player state (PLAYER-03): the player node owns foot control;
## while driving or flying it is hidden and the vehicle owns control.

signal crosshair_hit(point: Vector3, hit_something: bool)

# Locomotion piece: GTA-style on-foot speeds, each matching an authored gait
# (CharacterVisual WALK/RUN/SPRINT_CLIP_SPEED): default movement is the run
# (jog), holding Walk (Left Alt) or a light stick tilt walks, Sprint sprints.
const WALK_SPEED := 1.5
const RUN_SPEED := 3.6
const SPRINT_SPEED := 6.8
const JUMP_WINDUP := 0.12      # standing-jump anticipation before take-off
const STOP_DECEL := 16.0       # m/s^2 braking when the stick is released from a run
const ACCEL := 14.0
const FRICTION := 12.0
# 5.0 m/s against 24 m/s^2 gravity: ~0.52 m rise, ~0.42 s airtime (a human
# hop, not the old 1.08 m / 0.60 s superhuman float).
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.0022
const AIM_DISTANCE := 1.6  # combat piece: over-the-shoulder aim (wave Q: hero, arms and gun in frame)
const HIP_DISTANCE := 3.2
const INTERACT_RANGE := 5.0
const PICKUP_RANGE := 7.5

var camera: Camera3D
var arm: SpringArm3D
var yaw := 0.0
var pitch := -0.12
var aiming := false
var alive := true
var busy := false                     # transition guard (PLAYER-03)
var current_vehicle: Node = null
var in_mission_actor := true
var _fire_cooldown := 0.0
var _reload_timer := 0.0
var _reloading := false
var _walk_phase := 0.0
var _damage_flash := 0.0
var _muzzle_flash: MeshInstance3D
var _weapon_mesh: MeshInstance3D
var _weapon_model: Node3D = null
var _body_root: Node3D
var _visual: CharacterVisual
var _press_armed: Dictionary = {}
var _press_queue: Dictionary = {}
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _head: Node3D
var _last_fire_time := 0.0
var _last_stride_phase := 0
var _rng := RandomNumberGenerator.new()
# On-foot feel (wave C): heading + scalar speed give arcs, momentum and
# visible lean instead of instant vector snaps; the camera trails on a spring.
const ACCEL_WALK := 11.0       # m/s^2 from standstill to jog
const ACCEL_SPRINT := 6.5      # m/s^2 jog to sprint
const DECEL := 10.5            # m/s^2 releasing the stick
const PIVOT_DECEL := 20.0      # m/s^2 braking into a sharp reversal
const ARM_BASE := Vector3(0.85, 1.50, 0.0)
var _heading := 0.0
var _speed := 0.0
var _prev_speed := 0.0
var _heading_rate := 0.0
var _lean_pitch := 0.0
var _lean_pitch_vel := 0.0
var _lean_roll := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _land_dip := 0.0
var _land_dip_vel := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _cam_follow := Vector3.ZERO
var _cam_ready := false
var _contact_shadow: Decal
var _sprint_cam := 0.0
var _jump_windup := -1.0
var _walk_toggle := false
var _stop_armed := false
var _airborne_time := 0.0
var _land_running := false

func _ready() -> void:
	_rng.seed = 771
	add_to_group("player")
	add_to_group("actors")
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_max_angle = deg_to_rad(52.0)
	_build_body()
	_build_camera()
	_ensure_walk_action()
	CombatFx.attach_player(self) # combat piece: FX, recoil/aim layer, hit markers
	Events.health_changed.connect(_on_health_changed)
	Events.state_restored.connect(_on_state_restored)
	Events.health_changed.emit(Game.health, Game.MAX_HEALTH)

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.75
	shape.shape = cap
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)

	_body_root = Node3D.new()
	_body_root.position.y = 0.025 # align visible soles with capsule bottom
	add_child(_body_root)

	var skin := Palette.mat(Palette.SKIN, 0.8)
	var shirt := Palette.mat(Color(0.16, 0.30, 0.42), 0.85)
	var pants := Palette.mat(Color(0.18, 0.19, 0.22), 0.9)
	var shoe := Palette.mat(Color(0.10, 0.10, 0.11), 0.7)

	var torso := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.62, 0.78, 0.34)
	torso.mesh = tb
	torso.material_override = shirt
	torso.position = Vector3(0.0, 1.22, 0.0)
	_body_root.add_child(torso)

	_head = Node3D.new()
	_head.position = Vector3(0.0, 1.72, 0.0)
	_body_root.add_child(_head)
	var head_mesh := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.26, 0.30, 0.26)
	head_mesh.mesh = hb
	head_mesh.material_override = skin
	_head.add_child(head_mesh)
	var hair := MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.28, 0.09, 0.28)
	hair.mesh = hbm
	hair.material_override = Palette.mat(Color(0.10, 0.08, 0.07), 0.9)
	hair.position = Vector3(0.0, 0.16, 0.0)
	_head.add_child(hair)

	_leg_l = _limb(Vector3(0.17, 0.86, 0.0), Vector3(0.22, 0.86, 0.24), pants, shoe)
	_leg_r = _limb(Vector3(-0.17, 0.86, 0.0), Vector3(0.22, 0.86, 0.24), pants, shoe)
	_arm_l = _limb(Vector3(0.38, 1.42, 0.0), Vector3(0.17, 0.66, 0.19), shirt, skin)
	_arm_r = _limb(Vector3(-0.38, 1.42, 0.0), Vector3(0.17, 0.66, 0.19), shirt, skin)

	# held weapon (a real mesh, swapped per weapon id)
	_weapon_mesh = MeshInstance3D.new()
	_weapon_mesh.position = Vector3(-0.30, 1.18, -0.28)
	_body_root.add_child(_weapon_mesh)
	_update_weapon_mesh()

	_muzzle_flash = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.22
	_muzzle_flash.mesh = sm
	_muzzle_flash.material_override = Palette.emissive(Color(1.0, 0.85, 0.5), 6.0)
	_muzzle_flash.visible = false
	_body_root.add_child(_muzzle_flash)

	_contact_shadow = _make_contact_shadow()
	add_child(_contact_shadow)

	_visual = CharacterVisual.new()
	_body_root.add_child(_visual)
	if _visual.configure("player"):
		for child in _body_root.get_children():
			if child is Node3D and child != _visual and child != _muzzle_flash:
				child.visible = false
		_update_weapon_mesh()

## Soft ambient-occlusion blob under the feet so the figure sits on the
## pavement in shade, where the sun shadow cannot ground it.
func _make_contact_shadow() -> Decal:
	var decal := Decal.new()
	decal.name = "ContactShadow"
	decal.size = Vector3(1.15, 0.7, 1.15)
	decal.position = Vector3(0.0, 0.05, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.78))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	grad.add_point(0.45, Color(0.0, 0.0, 0.0, 0.42))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	decal.texture_albedo = tex
	decal.modulate = Color(1, 1, 1, 0.62)
	decal.upper_fade = 0.25
	decal.lower_fade = 0.6
	decal.cull_mask = 1
	return decal

func _limb(hip: Vector3, size: Vector3, cloth: Material, foot: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = hip
	_body_root.add_child(pivot)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = cloth
	mesh.position = Vector3(0.0, -size.y * 0.5, 0.0)
	pivot.add_child(mesh)
	var f := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(size.x + 0.04, 0.12, size.z + 0.06)
	f.mesh = fb
	f.material_override = foot
	f.position = Vector3(0.0, -size.y + 0.05, 0.02)
	pivot.add_child(f)
	return pivot

func _update_weapon_mesh() -> void:
	var file := "smg_clean.glb" if Game.carried_weapon == "smg" else "pistol_clean.glb"
	if _visual != null and _visual.loaded:
		file = "smg_held.glb" if Game.carried_weapon == "smg" else "pistol_held.glb"
	if _weapon_model != null and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
		_weapon_model = null
	if AssetLibrary.has_asset(file):
		_weapon_model = AssetLibrary.instantiate(file, _body_root)
		if _weapon_model != null:
			_weapon_model.position = Vector3(-0.30, 1.18, -0.28)
			if _visual != null and _visual.loaded:
				_visual.attach_weapon(_weapon_model, Game.carried_weapon)
			_weapon_mesh.visible = false
			return
	_weapon_mesh.visible = true
	var bm := BoxMesh.new()
	if Game.carried_weapon == "smg":
		bm.size = Vector3(0.09, 0.13, 0.62)
	else:
		bm.size = Vector3(0.07, 0.11, 0.34)
	_weapon_mesh.mesh = bm
	_weapon_mesh.material_override = Palette.mat(Color(0.10, 0.10, 0.12), 0.35, 0.85)

func _build_camera() -> void:
	arm = SpringArm3D.new()
	arm.spring_length = HIP_DISTANCE
	arm.add_excluded_object(self)
	arm.collision_mask = 1 | 8
	arm.margin = 0.25
	arm.position = ARM_BASE   # over-the-shoulder framing
	arm.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.current = true
	arm.add_child(camera)
	_build_character_lights()

## Third-person character lighting (on-foot piece): a soft camera-side fill
## and a warm back rim that only touch the player's own meshes (render layer
## 11), so the figure keeps readable skin, cloth folds and silhouette in deep
## arcade shade without lifting the world. No shadows, two lights.
func _build_character_lights() -> void:
	var fill := OmniLight3D.new()
	fill.name = "CharacterFill"
	fill.light_cull_mask = CharacterVisual.PLAYER_LIGHT_LAYER
	fill.light_color = Color(1.0, 0.93, 0.84)
	fill.light_energy = 0.32
	fill.light_specular = 0.15
	fill.omni_range = 7.0
	fill.omni_attenuation = 0.6
	fill.position = Vector3(-0.9, 0.7, 0.2)
	fill.shadow_enabled = false
	camera.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "CharacterRim"
	rim.light_cull_mask = CharacterVisual.PLAYER_LIGHT_LAYER
	rim.light_color = Color(1.0, 0.86, 0.68)
	rim.light_energy = 0.38
	rim.light_specular = 0.35
	rim.shadow_enabled = false
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	rim.basis = Basis.looking_at(Vector3(0.45, -0.55, 1.0).normalized(), Vector3.UP)
	camera.add_child(rim)

## Walk input (locomotion piece) is added at runtime so project.godot stays
## untouched: hold Left Alt to walk, Caps Lock toggles walking.
func _ensure_walk_action() -> void:
	if not InputMap.has_action("walk"):
		InputMap.add_action("walk")
		var alt := InputEventKey.new()
		alt.physical_keycode = KEY_ALT
		InputMap.action_add_event("walk", alt)
	if not InputMap.has_action("walk_toggle"):
		InputMap.add_action("walk_toggle")
		var caps := InputEventKey.new()
		caps.physical_keycode = KEY_CAPSLOCK
		InputMap.action_add_event("walk_toggle", caps)

func _unhandled_input(event: InputEvent) -> void:
	if Game.simulation_paused:
		return
	if event.is_action_pressed("walk_toggle"):
		_walk_toggle = not _walk_toggle
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens: float = MOUSE_SENS * float(Game.settings.get("mouse_sensitivity", 1.0))
		yaw -= mm.relative.x * sens
		var dy: float = mm.relative.y * sens
		if bool(Game.settings.get("invert_y", false)):
			dy = -dy
		pitch = clampf(pitch - dy, -1.25, 0.85)
	# Preserve rapid native press/release events even when a slow frame ends
	# after both. Scripted action_press still uses the held-state fallback.
	if not (event is InputEventKey and event.echo):
		for action in ["fire", "reload", "weapon_next", "interact"]:
			if event.is_action_pressed(action):
				_press_queue[action] = true
	# NOTE: fire/reload/weapon/interact are polled in _process so that scripted
	# input (Input.action_press) reaches the same code path as a human press.

func _physics_process(delta: float) -> void:
	if has_meta("_qa_motion_probe"):
		set_meta("_qa_motion_state", {"busy": busy, "vehicle": current_vehicle.name if current_vehicle else "none",
			"paused": Game.simulation_paused, "mode": Game.mode, "forward": Input.get_action_strength("move_forward"),
			"back": Input.get_action_strength("move_back"), "sprint": Input.get_action_strength("sprint"), "before": velocity})
	if Game.simulation_paused:
		velocity = Vector3.ZERO
		return
	if current_vehicle != null and is_instance_valid(current_vehicle):
		# Occupancy has one spatial authority. Keep the hidden foot proxy at
		# the occupied vehicle so witnesses, saves and effects never target
		# an abandoned entry position. It has no collision while seated.
		global_position = current_vehicle.global_position
		Game.player_position = current_vehicle.global_position
		Game.player_rotation = current_vehicle.rotation.y
		collision_layer = 0
		collision_mask = 0
		velocity = Vector3.ZERO
		return
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	if busy:
		velocity = Vector3.ZERO
		return
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_damage_flash = maxf(0.0, _damage_flash - delta)
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_reloading = false
			Game.reload_ammo()
			Events.notify.emit("Reloaded.", "info")
	if aiming:
		arm.spring_length = lerpf(arm.spring_length, AIM_DISTANCE, delta * 10.0)
	else:
		arm.spring_length = lerpf(arm.spring_length, HIP_DISTANCE + 0.35 * _sprint_cam, delta * 4.0)

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	var basis_dir := Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, yaw)
	var sprinting := Input.is_action_pressed("sprint") and not aiming and input_dir.y < 0.0
	var stick := clampf(input_dir.length(), 0.0, 1.0)
	# Gait speeds are quantised (walk / run / sprint) so the authored cycles
	# always play at their own rate; a light stick tilt walks.
	var walking := (Input.is_action_pressed("walk") or _walk_toggle or stick < 0.55) and not sprinting
	var target_speed := SPRINT_SPEED if sprinting else (WALK_SPEED if walking else RUN_SPEED)
	if aiming:
		target_speed = WALK_SPEED if walking else WALK_SPEED * 1.15
	if stick < 0.08:
		target_speed = 0.0

	# Heading + speed locomotion: the body turns at a speed-dependent rate
	# (tight at a walk, wide arcs at a sprint) and a sharp reversal brakes
	# first, so direction changes carry weight instead of snapping.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	_speed = minf(_speed, horizontal.length() + 0.05) # walls and props stop us
	var prev_heading := _heading
	if basis_dir.length() > 0.05:
		var want := atan2(-basis_dir.x, -basis_dir.z)
		if aiming or _speed < 0.25:
			_heading = want if _speed < 0.25 else lerp_angle(_heading, want, clampf(delta * 14.0, 0.0, 1.0))
		else:
			var diff := wrapf(want - _heading, -PI, PI)
			var turn_rate := lerpf(11.0, 4.6, clampf(_speed / SPRINT_SPEED, 0.0, 1.0))
			if absf(diff) > 1.75 and _speed > 2.0:
				target_speed = 0.0
				turn_rate *= 0.35
			_heading += clampf(diff, -turn_rate * delta, turn_rate * delta)
		var rate := ACCEL_WALK if _speed < RUN_SPEED else ACCEL_SPRINT
		if _speed > target_speed:
			rate = PIVOT_DECEL if target_speed <= 0.01 else DECEL
		_speed = move_toward(_speed, target_speed, rate * delta)
		_stop_armed = false
		# Moving off during a standing landing's absorb: step out of it rather
		# than sliding the planted feet.
		if _visual != null and _visual.current_clip() == "land" and not _land_running and _speed > 1.0:
			_visual.cancel_action()
		if _visual != null and _visual.current_clip() == "stop":
			_visual.cancel_action()
	else:
		# Releasing the stick from a run plants a braking step (stop clip)
		# and brakes hard enough that the planted foot does not skate.
		if _speed > 2.8 and _speed < 4.2 and is_on_floor() and not aiming and not _stop_armed and _visual != null and _visual.loaded:
			_stop_armed = _visual.play_action("stop", 0.1)
		_speed = move_toward(_speed, 0.0, (STOP_DECEL if _stop_armed or _speed > 4.2 else DECEL) * delta)
	if delta > 0.0:
		_heading_rate = lerpf(_heading_rate, wrapf(_heading - prev_heading, -PI, PI) / delta, clampf(delta * 10.0, 0.0, 1.0))
	horizontal = Vector3(-sin(_heading), 0.0, -cos(_heading)) * _speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= 24.0 * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	else:
		velocity.y = -0.5
		if _jump_windup >= 0.0:
			# Standing jump: a short crouch (jump_start clip) then take-off.
			_jump_windup -= delta
			if _jump_windup < 0.0:
				velocity.y = _jump_speed()
		elif Input.is_action_just_pressed("jump"):
			if _speed < 1.0 and _visual != null and _visual.loaded and _visual.play_action("jump_start", 0.06):
				_jump_windup = JUMP_WINDUP
			else:
				velocity.y = _jump_speed()
	if has_meta("_qa_motion_probe"):
		get_meta("_qa_motion_state")["requested"] = velocity
	move_and_slide()
	if has_meta("_qa_motion_probe"):
		get_meta("_qa_motion_state")["resolved"] = velocity

	if global_position.y < -8.0 or absf(global_position.x)>400.0 or global_position.z>410.0 or global_position.z < -370.0:
		Events.toast("Beyond the district. Returning to your checkpoint.","warn")
		Game.damage_player(Game.MAX_HEALTH)
		return
	# face the travel heading (or the camera direction when aiming/firing)
	if aiming:
		var aim_dir := -camera.global_transform.basis.z
		rotation.y = lerp_angle(rotation.y, atan2(-aim_dir.x, -aim_dir.z), clampf(delta * 12.0, 0.0, 1.0))
		_heading = rotation.y if _speed < 0.25 else _heading
	elif _speed > 0.05 or basis_dir.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, _heading, clampf(delta * 16.0, 0.0, 1.0))
	else:
		_heading = rotation.y
	arm.rotation.y = yaw - rotation.y
	arm.rotation.x = pitch
	_update_body_motion(delta, sprinting)
	_update_camera_follow(delta, sprinting)
	_animate(delta, horizontal.length(), sprinting)
	var actor := controlled_actor()
	Game.player_position = actor.global_position
	Game.player_rotation = yaw

## Take-off speed: a human hop on open ground; facing a kerb, planter, bench
## or low wall (0.35-1.25 m) the take-off scales up just enough to clear its
## top (a vault), so the lower jump never traps the player.
func _jump_speed() -> float:
	var space := get_world_3d().direct_space_state
	var fwd := -global_transform.basis.z
	if _speed > 0.25:
		fwd = Vector3(-sin(_heading), 0.0, -cos(_heading))
	var top := 0.0
	for reach: float in [0.55, 0.85]:
		var from := global_position + fwd * reach + Vector3.UP * 1.45
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.35)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var hit_pos: Vector3 = hit["position"]
			top = maxf(top, hit_pos.y - global_position.y)
	if top < 0.35 or top > 1.25:
		return JUMP_VELOCITY
	return maxf(JUMP_VELOCITY, sqrt(2.0 * 24.0 * (top + 0.2)))

## Weight cues: forward lean with acceleration and sprint, a damped rock when
## stopping, roll into turns, a knee dip on landing and head look toward the
## camera's view. Whole-body roll pivots on the feet; the spine adds curve.
func _update_body_motion(delta: float, sprinting: bool) -> void:
	if _visual == null or not _visual.loaded or delta <= 0.0:
		return
	var accel := (_speed - _prev_speed) / delta
	_prev_speed = _speed
	# The v2 run/sprint clips carry their own trunk lean; keep a light speed
	# lean plus the acceleration lean here.
	var pitch_target := clampf(_speed / SPRINT_SPEED, 0.0, 1.0) * ((0.04 if sprinting else 0.02) if _visual.gait_v2 else (0.17 if sprinting else 0.08))
	pitch_target += clampf(absf(accel) * 0.014, 0.0, 0.16)
	_lean_pitch_vel += ((pitch_target - _lean_pitch) * 110.0 - _lean_pitch_vel * 13.0) * delta
	_lean_pitch += _lean_pitch_vel * delta
	var roll_target := clampf(_heading_rate * _speed * 0.045, -0.32, 0.32)
	if not is_on_floor():
		roll_target = 0.0
	_lean_roll = lerpf(_lean_roll, roll_target, clampf(delta * 7.0, 0.0, 1.0))
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_land_dip_vel -= clampf(_fall_speed * 0.05, 0.05, 0.6)
		# Weighted landing: a knee-bend absorb clip after a real jump/fall;
		# at running speed the procedural dip carries it into the stride.
		if _fall_speed > 3.0 and _airborne_time > 0.25:
			_land_running = _speed >= 0.8
			if not _land_running:
				_visual.play_action("land", 0.05)
			# integ-P seam (locomotion-P2: feet slid ~3.5 m/s under the planted
			# 'land' crouch): at jog/sprint speed the stride simply continues and
			# the procedural knee dip carries the impact; only a slow landing
			# plays the fast knee-absorb clip.
			elif _speed >= 2.2:
				_speed *= 0.9
				_land_dip_vel -= 0.38
			# Slow running landing: a fast knee-absorb (land clip at 2x, ~0.21 s)
			# that bleeds speed, then the run picks up again.
			elif _visual.play_action("land", 0.04, 2.0):
				_speed *= 0.72
				_land_dip_vel -= 0.25
		_fall_speed = 0.0
	_airborne_time = 0.0 if on_floor else _airborne_time + delta
	_was_on_floor = on_floor
	_land_dip_vel += (-_land_dip * 160.0 - _land_dip_vel * 16.0) * delta
	_land_dip = clampf(_land_dip + _land_dip_vel * delta, -0.16, 0.05)
	_visual.rotation = Vector3(-_lean_pitch * 0.35, 0.0, _lean_roll * 0.55)
	_visual.position.y = _land_dip
	var rel := wrapf(yaw - rotation.y, -PI, PI)
	var look_target := clampf(rel, -1.05, 1.05) if absf(rel) < 2.0 and not aiming else 0.0
	_look_yaw = lerpf(_look_yaw, look_target, clampf(delta * 5.0, 0.0, 1.0))
	_look_pitch = lerpf(_look_pitch, clampf(-pitch * 0.55, -0.35, 0.45), clampf(delta * 5.0, 0.0, 1.0))
	_visual.set_body_motion(_lean_pitch * 0.65, _lean_roll * 0.45, _look_yaw, _look_pitch)

## The camera trails the body on a critically damped spring (no rigid lock),
## widens slightly at a sprint and snaps after teleports.
func _update_camera_follow(delta: float, sprinting: bool) -> void:
	if not _cam_ready or _cam_follow.distance_to(global_position) > 3.0:
		_cam_follow = global_position
		_cam_ready = true
	var k := 1.0 - exp(-delta * 9.0)
	_cam_follow.x = lerpf(_cam_follow.x, global_position.x, k)
	_cam_follow.z = lerpf(_cam_follow.z, global_position.z, k)
	_cam_follow.y = lerpf(_cam_follow.y, global_position.y, 1.0 - exp(-delta * 6.0))
	var lag := _cam_follow - global_position
	if lag.length() > 0.7:
		lag = lag.normalized() * 0.7
		_cam_follow = global_position + lag
	var pc := get_node_or_null("PlayerCombat")
	var aim_off: Vector3 = pc.get("arm_offset") if pc != null else Vector3.ZERO
	arm.position = ARM_BASE + aim_off + global_transform.basis.inverse() * lag
	var sprint_amount := clampf((_speed - RUN_SPEED) / (SPRINT_SPEED - RUN_SPEED), 0.0, 1.0) if sprinting else 0.0
	camera.fov = lerpf(camera.fov, 58.0 + 5.0 * sprint_amount, clampf(delta * 3.0, 0.0, 1.0))
	_sprint_cam = sprint_amount

func _animate(delta: float, speed: float, sprinting: bool) -> void:
	if _visual != null and _visual.loaded:
		_visual.set_air_velocity(velocity.y if not is_on_floor() else 99.0, JUMP_VELOCITY)
		_visual.set_travel_direction(wrapf(_heading - rotation.y, -PI, PI))
		_visual.set_motion(speed, aiming, is_on_floor(), _reloading)
		_visual.set_aim_pitch(pitch)
		# Footsteps on the authored heel strikes (cycle phase 0 and 0.5).
		var gait := _visual.gait_phase()
		var contact := int(gait * 2.0) if gait >= 0.0 else _last_stride_phase
		if contact != _last_stride_phase and speed > .5 and is_on_floor():
			_last_stride_phase = contact
			Sfx.play_at("footstep", global_position, -18.0, _rng.randf_range(.9, 1.1))
		return
	var stride: float = clampf(speed / 5.0, 0.0, 1.6)
	_walk_phase += delta * (6.0 + speed * 1.4)
	var swing: float = sin(_walk_phase) * stride * 0.7
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	var arm_swing := swing * 0.6
	if aiming:
		_arm_r.rotation.x = -1.35
		_arm_l.rotation.x = -1.25
		_arm_l.rotation.z = 0.25
	else:
		_arm_l.rotation.x = -arm_swing
		_arm_r.rotation.x = arm_swing
		_arm_l.rotation.z = 0.0
	_head.rotation.x = clampf(-pitch * 0.6, -0.5, 0.5)
	if _reloading:
		_arm_r.rotation.x = -0.9 + sin(_walk_phase * 2.0) * 0.4
	_body_root.position.y = absf(sin(_walk_phase)) * 0.04 * stride
	# footstep audio on each stride contact
	var stride_phase := int(_walk_phase / PI)
	if stride_phase != _last_stride_phase:
		_last_stride_phase = stride_phase
		if stride > 0.25:
			Sfx.play_at("footstep", global_position, -18.0, _rng.randf_range(0.9, 1.15))

func _fire() -> void:
	if current_vehicle != null or busy:
		return
	if _reloading:
		return
	if _fire_cooldown > 0.0:
		return
	if Game.current_mag() <= 0:
		Events.notify.emit("Out of ammo. Press R to reload.", "warn")
		Sfx.play_at("dry_fire", global_position + Vector3.UP * 1.2, -8.0)
		_fire_cooldown = 0.35
		return
	Game.consume_ammo()
	_fire_cooldown = 0.16 if Game.carried_weapon == "pistol" else 0.085
	_muzzle_flash.position = _weapon_mesh.position + Vector3(0.0, 0.02, -0.35 if Game.carried_weapon == "smg" else -0.22)
	if _visual != null and _visual.loaded:
		_muzzle_flash.global_position = _visual.weapon_muzzle_position()
	var cam_basis := camera.global_transform.basis
	var origin := camera.global_position
	var dir := -cam_basis.z
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * 120.0)
	params.collision_mask = 1 | 4 | 8
	params.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	var point := origin + dir * 120.0
	# The camera chooses the aim point, but the muzzle must have a clear
	# path to it. This prevents shooting through close walls/vehicle cover.
	if not hit.is_empty():
		point = hit["position"]
	var muzzle := _muzzle_flash.global_position
	var muzzle_params := PhysicsRayQueryParameters3D.create(muzzle, point)
	muzzle_params.collision_mask = 1 | 4 | 8
	muzzle_params.exclude = [get_rid()]
	var muzzle_hit := get_world_3d().direct_space_state.intersect_ray(muzzle_params)
	if not muzzle_hit.is_empty():
		hit = muzzle_hit
	var hit_something := false
	if not hit.is_empty():
		point = hit["position"]
		hit_something = true
	# Combat piece: muzzle flash/light/smoke, tracer, impact, decal, brass and
	# recoil (CombatFx + PlayerCombat). Visuals before damage so a lethal hit
	# still shows its impact on the falling body.
	CombatFx.get_fx(get_tree()).shot(muzzle, (point - muzzle).normalized(), point, hit_something,
		hit.get("normal", -dir), hit.get("collider"), Game.carried_weapon, true)
	var combat := get_node_or_null("PlayerCombat")
	if combat != null:
		combat.on_shot(Game.carried_weapon)
	if hit_something:
		var collider = hit["collider"]
		if collider and collider.has_method("take_damage"):
			var dmg := 34.0 if Game.carried_weapon == "pistol" else 22.0
			collider.take_damage(dmg, global_position, true)
			Events.hit_landed.emit(collider, dmg, point, true)
	Events.shot_fired.emit(origin, dir, Game.carried_weapon)
	Sfx.play_at("gun_pistol" if Game.carried_weapon == "pistol" else "gun_smg", muzzle, -3.0, 1.0)
	crosshair_hit.emit(point, hit_something)
	# make noise: gunfire draws witnesses and police (LAW-02)
	Game.add_heat(2.0)

func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	mesh.mesh = sm
	mesh.material_override = Palette.emissive(Color(0.9, 0.75, 0.5), 2.0)
	mesh.position = point
	get_tree().current_scene.add_child(mesh)
	var t := get_tree().create_timer(0.25)
	t.timeout.connect(func():
		if is_instance_valid(mesh):
			mesh.queue_free())

func _start_reload() -> void:
	if _reloading or current_vehicle != null:
		return
	if Game.current_mag() >= (12 if Game.carried_weapon == "pistol" else 30):
		return
	if Game.current_reserve() <= 0:
		Events.notify.emit("No reserve ammunition.", "warn")
		return
	_reloading = true
	_reload_timer = 1.5 if Game.carried_weapon == "pistol" else 2.1

func _try_interact() -> void:
	if busy:
		return
	if current_vehicle != null:
		if current_vehicle.has_method("exit_vehicle"):
			current_vehicle.exit_vehicle(self)
		return
	var best := _interaction_target()
	if best != null:
		best.interact(self)

func _interaction_target() -> Node3D:
	var best: Node3D = null
	var nearest := INF
	for group in ["vehicles", "interactables"]:
		for candidate in get_tree().get_nodes_in_group(group):
			if not candidate is Node3D or not candidate.visible:
				continue
			if candidate == current_vehicle:
				continue
			if candidate.has_method("is_disabled") and candidate.is_disabled():
				continue
			if candidate.has_method("can_interact") and not candidate.can_interact():
				continue
			var distance: float = global_position.distance_to(candidate.global_position)
			var reach := INTERACT_RANGE if group=="vehicles" else PICKUP_RANGE
			if distance >= nearest or distance >= reach:
				continue
			if not _interaction_visible(candidate):
				continue
			nearest=distance
			best=candidate
	return best

func _interaction_visible(target: Node3D) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(global_position+Vector3(0,1.25,0),target.global_position+Vector3(0,.65,0))
	ray.collision_mask=1|8
	var excluded: Array[RID] = [get_rid()]
	if target is CollisionObject3D:
		excluded.append(target.get_rid())
	ray.exclude=excluded
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _process(_delta: float) -> void:
	if Game.simulation_paused:
		return
	if current_vehicle == null and not busy:
		# Hip fire keeps the gun raised for a moment (combat piece).
		var combat := get_node_or_null("PlayerCombat")
		aiming = Input.is_action_pressed("aim") or (combat != null and float(combat.hold) > 0.0)
	var fire_pressed := _consume_press("fire")
	if fire_pressed or (Game.carried_weapon == "smg" and Input.is_action_pressed("fire")):
		_fire()
	if _consume_press("reload"):
		_start_reload()
	if _consume_press("weapon_next"):
		Game.switch_weapon("smg" if Game.carried_weapon == "pistol" else "pistol")
		_update_weapon_mesh()
	if _consume_press("interact"):
		_try_interact()
	_update_prompt()

## Rising-edge detection on the *held* state of an action.
##
## `Input.is_action_just_pressed()` is tied to the frame in which the press was
## parsed, so a press injected after this node's turn in the frame is invisible
## to it until the next press. A scripted playtest (and a player on a slow
## frame) would then lose the input entirely. Watching the held state and
## firing once per press re-arms on release keeps one code path for humans and
## for scripts, and cannot miss a press that is still held.
func _consume_press(action: String) -> bool:
	if _press_queue.get(action, false):
		_press_queue.erase(action)
		_press_armed[action] = false
		return true
	if not Input.is_action_pressed(action):
		_press_armed[action] = true
		return false
	if _press_armed.get(action, true):
		_press_armed[action] = false
		return true
	return false

func _update_prompt() -> void:
	if current_vehicle != null:
		# an airborne helicopter cannot be left, so no exit prompt in flight
		var airborne: bool = current_vehicle is Helicopter and not current_vehicle.is_landed()
		Events.interaction_prompt.emit("" if airborne else "[E] Exit vehicle")
		return
	var target := _interaction_target()
	var prompt := ""
	if CombatFx.in_combat():
		target = null # combat piece: no interaction prompts mid-firefight
	if target != null:
		if target is Helicopter:
			prompt="[E] Board helicopter"
		elif target is Car:
			prompt="[E] Take %s"%target.kind.capitalize()
		else:
			prompt=String(target.get("prompt_text")) if target.get("prompt_text") else "[E] Interact"
	Events.interaction_prompt.emit(prompt)

func take_damage(amount: float, from_position: Vector3, _by_player: bool = false) -> void:
	if not alive:
		return
	Game.damage_player(amount)
	_damage_flash = 0.3
	# integ-P seam: while aiming (or the gun is still raised from a shot) a hit
	# must not drop the gun arm via the full-body 'hit' clip; the damage flash
	# and camera shake carry the feedback instead.
	var pc := get_node_or_null("PlayerCombat")
	var gun_up := aiming or (pc != null and float(pc.get("hold")) > 0.0)
	if _visual != null and _visual.loaded and Game.health > 0 and not gun_up:
		_visual.play_hit()

func _on_health_changed(value: float, _max_value: float) -> void:
	alive = value > 0.0
	if not alive:
		visible = false

func respawn_at(pos: Vector3, rot: float) -> void:
	var vehicle := current_vehicle
	if vehicle != null and is_instance_valid(vehicle):
		if vehicle.has_method("force_exit"):
			vehicle.force_exit()
	current_vehicle = null
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	global_position = pos
	yaw = rot
	rotation.y = rot
	velocity = Vector3.ZERO
	_speed = 0.0
	_heading = rot
	_cam_ready = false
	visible = true
	alive = true
	if _visual != null and _visual.loaded:
		_visual.reset_alive()
	busy = false
	camera.current = true
	Game.set_mode(Game.MODE_FOOT)
	Events.notify.emit("Restored at checkpoint.", "info")

func die() -> void:
	alive = false
	visible = false
	Game.damage_player(Game.MAX_HEALTH)


## The body the player is actually controlling: the vehicle when driving or
## flying, otherwise the player itself. Every system that needs "where is the
## player" must use this, never the raw node position (B5).
func controlled_actor() -> Node3D:
	if current_vehicle != null and is_instance_valid(current_vehicle):
		return current_vehicle as Node3D
	return self

func reset_action_state() -> void:
	_fire_cooldown=0.0
	_reload_timer=0.0
	_reloading=false
	aiming=false
	busy=false
	_press_queue.clear()
	_press_armed.clear()
	Game.carried_weapon="pistol"
	_update_weapon_mesh()
	if _visual!=null and _visual.loaded: _visual.reset_alive()
	Events.ammo_changed.emit(Game.current_mag(),Game.current_reserve())

func _on_state_restored() -> void:
	_fire_cooldown=0.0
	_reload_timer=0.0
	_reloading=false
	aiming=false
	busy=false
	_press_queue.clear()
	_press_armed.clear()
	_update_weapon_mesh()
	if _visual != null and _visual.loaded: _visual.reset_alive()
