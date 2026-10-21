class_name Player
extends CharacterBody3D
## Third-person player: locomotion, camera, aiming, firearms, interaction.
## One authoritative player state (PLAYER-03): the player node owns foot control;
## while driving or flying it is hidden and the vehicle owns control.

signal crosshair_hit(point: Vector3, hit_something: bool)

const WALK_SPEED := 3.6
const SPRINT_SPEED := 6.8
const ACCEL := 14.0
const FRICTION := 12.0
const JUMP_VELOCITY := 7.2
const MOUSE_SENS := 0.0022
const AIM_DISTANCE := 2.2
const HIP_DISTANCE := 4.6
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
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _head: Node3D
var _last_fire_time := 0.0
var _last_stride_phase := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 771
	add_to_group("player")
	add_to_group("actors")
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_max_angle = deg_to_rad(52.0)
	_build_body()
	_build_camera()
	Events.health_changed.connect(_on_health_changed)
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
	if _weapon_model != null and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
		_weapon_model = null
	if AssetLibrary.has_asset(file):
		_weapon_model = AssetLibrary.instantiate(file, _body_root)
		if _weapon_model != null:
			_weapon_model.position = Vector3(-0.30, 1.18, -0.28)
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
	arm.collision_mask = 1
	arm.margin = 0.25
	arm.position = Vector3(0.85, 1.62, 0.0)   # over-the-shoulder framing
	arm.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.current = true
	arm.add_child(camera)

func _unhandled_input(event: InputEvent) -> void:
	if Game.simulation_paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens: float = MOUSE_SENS * float(Game.settings.get("mouse_sensitivity", 1.0))
		yaw -= mm.relative.x * sens
		var dy: float = mm.relative.y * sens
		if bool(Game.settings.get("invert_y", false)):
			dy = -dy
		pitch = clampf(pitch - dy, -1.25, 0.85)
	# NOTE: fire/reload/weapon/interact are polled in _process so that scripted
	# input (Input.action_press) reaches the same code path as a human press.

func _physics_process(delta: float) -> void:
	if Game.simulation_paused:
		velocity = Vector3.ZERO
		return
	if current_vehicle != null or busy:
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
		arm.spring_length = lerpf(arm.spring_length, HIP_DISTANCE, delta * 8.0)

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	var basis_dir := Vector3(input_dir.x, 0.0, input_dir.y).rotated(Vector3.UP, yaw)
	var sprinting := Input.is_action_pressed("sprint") and not aiming and input_dir.y < 0.0
	var target_speed := SPRINT_SPEED if sprinting else WALK_SPEED
	if aiming:
		target_speed *= 0.55

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if basis_dir.length() > 0.05:
		horizontal = horizontal.lerp(basis_dir.normalized() * target_speed, clampf(ACCEL * delta / maxf(target_speed, 0.001), 0.0, 1.0))
	else:
		horizontal = horizontal.lerp(Vector3.ZERO, clampf(FRICTION * delta, 0.0, 1.0))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = -0.5
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	move_and_slide()

	# face movement direction (or camera direction when aiming/firing)
	var face_dir := Vector3.ZERO
	if aiming:
		face_dir = -camera.global_transform.basis.z
	elif basis_dir.length() > 0.05:
		face_dir = basis_dir
	if face_dir.length() > 0.05:
		var target_yaw := atan2(-face_dir.x, -face_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 12.0, 0.0, 1.0))
	arm.rotation.y = yaw
	arm.rotation.x = pitch
	_animate(delta, horizontal.length(), sprinting)
	var actor := controlled_actor()
	Game.player_position = actor.global_position
	Game.player_rotation = yaw

func _animate(delta: float, speed: float, sprinting: bool) -> void:
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
			Sfx.play("footstep", -18.0, _rng.randf_range(0.9, 1.15))

func _fire() -> void:
	if current_vehicle != null or busy:
		return
	if _reloading:
		return
	if _fire_cooldown > 0.0:
		return
	if Game.current_mag() <= 0:
		Events.notify.emit("Out of ammo. Press R to reload.", "warn")
		_fire_cooldown = 0.35
		return
	Game.consume_ammo()
	_fire_cooldown = 0.16 if Game.carried_weapon == "pistol" else 0.085
	_muzzle_flash.visible = true
	_muzzle_flash.position = _weapon_mesh.position + Vector3(0.0, 0.02, -0.35 if Game.carried_weapon == "smg" else -0.22)
	var cam_basis := camera.global_transform.basis
	var origin := camera.global_position
	var dir := -cam_basis.z
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * 120.0)
	params.collision_mask = 1 | 4 | 8
	params.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	var point := origin + dir * 120.0
	var hit_something := false
	if not hit.is_empty():
		point = hit["position"]
		hit_something = true
		var collider = hit["collider"]
		if collider and collider.has_method("take_damage"):
			var dmg := 34.0 if Game.carried_weapon == "pistol" else 22.0
			collider.take_damage(dmg, global_position, true)
			Events.hit_landed.emit(collider, dmg, point, true)
			hit_something = true
		_spawn_impact(point, -dir)
	Events.shot_fired.emit(origin, dir, Game.carried_weapon)
	Sfx.play("gunshot", -4.0, 1.0 if Game.carried_weapon == "pistol" else 0.88)
	crosshair_hit.emit(point, hit_something)
	# make noise: gunfire draws witnesses and police (LAW-02)
	Game.add_heat(2.0)
	get_tree().create_timer(0.05).timeout.connect(func(): _muzzle_flash.visible = false)

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
	var best: Node = null
	var best_d := INTERACT_RANGE
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v == current_vehicle:
			continue
		var d := global_position.distance_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	if best and best.has_method("interact"):
		best.interact(self)
		return
	# mission interactables
	for obj in get_tree().get_nodes_in_group("interactables"):
		var d2 := global_position.distance_to(obj.global_position)
		# small props are picked up from a slightly wider reach than a vehicle
		if d2 < PICKUP_RANGE and obj.has_method("interact"):
			obj.interact(self)
			return

func _process(_delta: float) -> void:
	if Game.simulation_paused:
		return
	if current_vehicle == null and not busy:
		aiming = Input.is_action_pressed("aim")
	if true:
		if Input.is_action_just_pressed("fire"):
			_fire()
		if Input.is_action_just_pressed("reload"):
			_start_reload()
		if Input.is_action_just_pressed("weapon_next"):
			Game.switch_weapon("smg" if Game.carried_weapon == "pistol" else "pistol")
			_update_weapon_mesh()
		if Input.is_action_just_pressed("interact"):
			_try_interact()
	_update_prompt()

func _update_prompt() -> void:
	if current_vehicle != null:
		Events.interaction_prompt.emit("[E] Exit vehicle")
		return
	var prompt := ""
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.global_position.distance_to(global_position) < INTERACT_RANGE:
			prompt = "[E] Enter vehicle"
			break
	for obj in get_tree().get_nodes_in_group("interactables"):
		if obj.global_position.distance_to(global_position) < INTERACT_RANGE:
			prompt = String(obj.get("prompt_text")) if obj.get("prompt_text") else "[E] Interact"
			break
	Events.interaction_prompt.emit(prompt)

func take_damage(amount: float, from_position: Vector3, _by_player: bool = false) -> void:
	if not alive:
		return
	Game.damage_player(amount)
	_damage_flash = 0.3

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
	global_position = pos
	yaw = rot
	rotation.y = rot
	velocity = Vector3.ZERO
	visible = true
	alive = true
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
