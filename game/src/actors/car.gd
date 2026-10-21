class_name Car
extends CharacterBody3D
## Arcade vehicle with a real cabin, wheels, lights, damage and left-hand-road
## AI. Physics is a deliberately simple kinematic model (reliable at district
## speeds, no physics-engine tuning rabbit hole): throttle, steering, drag,
## kerb-friendly ride height, and visible collision response.

signal damaged(amount: float)

const MAX_SPEED := 27.0
const REVERSE_SPEED := 9.0
const ACCEL := 11.0
const BRAKE := 22.0
const DRAG := 0.55
const STEER_RATE := 2.6
const TURN_SPEED := 1.9

var kind := "sedan"                     # sedan | coupe | van | police
var max_speed := MAX_SPEED
var accel := ACCEL
var health := 100.0
var disabled := false
var driver_is_player := false
var has_ai := false
var ai_target := Vector3.ZERO
var ai_lookahead := 14.0
var ai_speed_limit := INF
var occupied_by_npc := false
var _forward := 0.0
var _steer := 0.0
var _wheels: Array[Node3D] = []
var _camera: Camera3D
var _arm: SpringArm3D
var _body_mesh: MeshInstance3D
var _driver: Node = null
var _provider_root: Node3D = null
var _impact_cooldown := 0.0
var driver_player: Node = null
var _provider_wheels: Array[Node3D] = []
var _procedural_visuals: Array[Node3D] = []

func _ready() -> void:
	add_to_group("vehicles")
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	# Road vehicles stand on world geometry, never on their own passenger
	# or a pedestrian as a moving platform.
	platform_floor_layers = 1
	platform_wall_layers = 0
	floor_max_angle = deg_to_rad(45.0)
	_build()

func _build() -> void:
	var dims := Vector3(1.85, 1.45, 4.5)
	match kind:
		"coupe": dims = Vector3(1.95, 1.25, 4.2)
		"van": dims = Vector3(2.05, 2.1, 5.2)
		"police": dims = Vector3(1.9, 1.5, 4.6)
	var body_mat := Palette.mat(_body_color(), 0.35, 0.55)
	_body_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = dims
	_body_mesh.mesh = bm
	_body_mesh.material_override = body_mat
	_body_mesh.position = Vector3(0.0, dims.y * 0.5, 0.0)
	add_child(_body_mesh)

	# cabin: right-hand drive (ART-06 / CAR-01) with seats, dash, windows
	var cabin := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(dims.x * 0.9, 0.78, dims.z * 0.42)
	cabin.mesh = cb
	cabin.material_override = Palette.mat(Color(0.10, 0.11, 0.13), 0.2, 0.3)
	cabin.position = Vector3(0.0, dims.y + 0.28, -0.15)
	add_child(cabin)
	var glass := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(dims.x * 0.92, 0.5, dims.z * 0.44)
	glass.mesh = gb
	glass.material_override = Palette.glass()
	glass.position = cabin.position + Vector3(0.0, 0.12, 0.0)
	add_child(glass)
	# dashboard + right-hand steering wheel (right = +X side when facing -Z)
	var dash := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(dims.x * 0.8, 0.16, 0.3)
	dash.mesh = db
	dash.material_override = Palette.mat(Color(0.13, 0.13, 0.15), 0.7)
	dash.position = cabin.position + Vector3(0.0, 0.05, 0.42)
	add_child(dash)
	var steering_wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.22
	tm.rings = 16
	tm.ring_segments = 6
	steering_wheel.mesh = tm
	steering_wheel.material_override = Palette.mat(Color(0.08, 0.08, 0.09), 0.6)
	steering_wheel.position = cabin.position + Vector3(dims.x * 0.32, 0.12, 0.38)
	steering_wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	add_child(steering_wheel)
	_wheels.append(steering_wheel)
	for sx in [-1.0, 1.0]:
		var seat := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.5, 0.5, 0.5)
		seat.mesh = sb
		seat.material_override = Palette.mat(Color(0.16, 0.16, 0.18), 0.85)
		seat.position = cabin.position + Vector3(dims.x * 0.32 * sx, -0.1, 0.05)
		add_child(seat)

	# wheels
	var wheel_size := 0.66 if kind != "van" else 0.74
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = wheel_size * 0.5
			cm.bottom_radius = wheel_size * 0.5
			cm.height = 0.26
			cm.radial_segments = 14
			w.mesh = cm
			w.material_override = Palette.mat(Color(0.07, 0.07, 0.08), 0.9)
			w.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			w.position = Vector3(dims.x * 0.5 * sx, wheel_size * 0.5, dims.z * 0.33 * sz)
			add_child(w)
			_wheels.append(w)

	# lights
	for sx in [-1.0, 1.0]:
		var head_light := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.34, 0.16, 0.1)
		head_light.mesh = hb
		head_light.material_override = Palette.emissive(Color(1.0, 0.95, 0.82), 2.2)
		head_light.position = Vector3(dims.x * 0.32 * sx, dims.y * 0.62, dims.z * 0.5)
		add_child(head_light)
		var tail_light := MeshInstance3D.new()
		var tb2 := BoxMesh.new()
		tb2.size = Vector3(0.3, 0.14, 0.1)
		tail_light.mesh = tb2
		tail_light.material_override = Palette.emissive(Color(0.85, 0.12, 0.08), 1.8)
		tail_light.position = Vector3(dims.x * 0.32 * sx, dims.y * 0.62, -dims.z * 0.5)
		add_child(tail_light)
	if kind == "police":
		var lightbar := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(1.2, 0.14, 0.3)
		lightbar.mesh = bb
		lightbar.material_override = Palette.emissive(Color(0.2, 0.35, 1.0), 2.0)
		lightbar.position = Vector3(0.0, dims.y + 0.75, -0.1)
		add_child(lightbar)

	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(dims.x, dims.y, dims.z)
	shape.shape = bs
	shape.position = Vector3(0.0, dims.y * 0.5, 0.0)
	add_child(shape)

	for child in get_children():
		if child is MeshInstance3D:
			_procedural_visuals.append(child)
	# Provider vehicle art when available; the procedural build is the fallback.
	_try_provider_asset(dims)

	_arm = SpringArm3D.new()
	_arm.spring_length = 5.4
	_arm.collision_mask = 1
	_arm.position = Vector3(0.0, dims.y + 0.5, 0.0)
	_arm.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	add_child(_arm)
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_arm.add_child(_camera)

## Swap in the generated sedan for the civilian and response variants.
func _try_provider_asset(dims: Vector3) -> void:
	var asset_file := ""
	match kind:
		"sedan":
			asset_file = "sedan_clean.glb"
		"coupe":
			asset_file = "coupe_clean.glb"
		"van":
			asset_file = "van_clean.glb"
		"police":
			asset_file = "sedan_clean.glb"
	if asset_file == "" or not AssetLibrary.has_asset(asset_file):
		return
	var root := AssetLibrary.instantiate(asset_file, self)
	if root == null:
		return
	_provider_root = root
	# The cleaned export already faces -Z (engine forward) after the Blender
	# assembly rotation, so no extra rotation is applied here.
	root.position = Vector3.ZERO
	# Wave-one normalization assumed every provider car used the sedan axis.
	# These two exports have their length on X; fit the visible body to the
	# same real-world bounds as the collider after rotating it to -Z.
	if kind == "coupe":
		root.rotation.y = PI * 0.5
		root.scale = Vector3(dims.z / 9.13, dims.y / 2.61, dims.x / 4.30)
	elif kind == "van":
		root.rotation.y = PI * 0.5
		root.scale = Vector3(dims.z / 9.73, dims.y / 5.42, dims.x / 5.20)
	if kind == "police":
		AssetLibrary.tint(root, Color(0.85, 0.88, 0.95))
	for part in _procedural_visuals:
		part.visible = false
	for wheel_name in ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]:
		var node := AssetLibrary.find_named(root, wheel_name)
		if node is Node3D:
			_provider_wheels.append(node)

func _body_color() -> Color:
	match kind:
		"coupe": return Color(0.62, 0.14, 0.16)
		"van": return Color(0.85, 0.85, 0.83)
		"police": return Color(0.88, 0.90, 0.93)
		_: return Color(0.30, 0.36, 0.42)

func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	if Game.simulation_paused:
		return
	if disabled:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if driver_is_player:
		_player_control(delta)
	elif has_ai:
		_ai_control(delta)
	else:
		_forward = move_toward(_forward, 0.0, ACCEL * delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if is_zero_approx(_forward) and is_on_floor():
			velocity = Vector3.ZERO
			return
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = -0.6
	_step_low_kerb(delta)
	var before := velocity
	move_and_slide()
	_check_impact(before)
	_spin_wheels(delta)

## Kinematic wheel contact: lift over a low kerb only when the complete car
## collision hull fits in the raised position and along its intended motion.
## This same bounded 0.24m step applies to human and AI driving.
func _step_low_kerb(delta: float) -> void:
	if not is_on_floor(): return
	var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if horizontal_motion.length() < 0.01: return
	if not test_move(global_transform, horizontal_motion): return
	var raised := global_transform
	raised.origin.y += 0.24
	if not test_move(global_transform, Vector3.UP * 0.24) and not test_move(raised, horizontal_motion):
		global_position.y += 0.24

func _check_impact(before: Vector3) -> void:
	if get_slide_collision_count() == 0:
		return
	# A parked car absorbs contact without being worn out or announced.
	if not driver_is_player and not has_ai:
		return
	# Damage comes from the closing speed along the contact normal, once per
	# contact: a car scraping a wall must not lose health every frame (B2).
	var worst := 0.0
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()
		if normal.y > 0.65:
			continue # Ground support is not a crash.
		var approach := -before.dot(normal)
		worst = maxf(worst, approach)
	if worst > 0.5:
		# Match the drivetrain to the velocity the collision actually permits.
		# Holding throttle against a wall must not invent a fresh 27 m/s crash.
		_forward = signf(_forward) * minf(absf(_forward), Vector2(velocity.x, velocity.z).length())
	if worst < 6.0 or _impact_cooldown > 0.0:
		return
	_impact_cooldown = 1.2
	var dmg: float = clampf((worst - 6.0) * 0.8, 0.0, 28.0)
	health = maxf(0.0, health - dmg)
	damaged.emit(dmg)
	if health <= 0.0 and not disabled:
		disabled = true
		if driver_is_player:
			Events.notify.emit("Vehicle disabled.", "warn")

func _spin_wheels(delta: float) -> void:
	var roll := _forward * delta * 2.4
	if _provider_root != null:
		# The inherited classifier named displaced body strips as wheel_*.
		# Keep their imported transforms: spinning them creates orbiting shards.
		# Proper wheel partition/pivots/steering remain an explicit ART-06 gap.
		return
	for w in _wheels:
		if w is MeshInstance3D:
			w.rotate_x(roll)

func _player_control(delta: float) -> void:
	var throttle := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var steer_input := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	if throttle > 0.01:
		_forward = minf(_forward + accel * throttle * delta, max_speed)
	elif throttle < -0.01:
		if _forward > 0.2:
			_forward = maxf(_forward - BRAKE * delta, 0.0)
		else:
			_forward = maxf(_forward - accel * 0.7 * delta, -REVERSE_SPEED)
	else:
		_forward = move_toward(_forward, 0.0, (DRAG + absf(_forward) * 0.25) * delta * 6.0)
	_steer = lerpf(_steer, steer_input, clampf(delta * 9.0, 0.0, 1.0))
	var turn := _steer * TURN_SPEED * clampf(absf(_forward) / 8.0, 0.0, 1.0) * signf(_forward if absf(_forward) > 0.05 else 1.0)
	# A node that faces -Z turns left when its yaw increases, so the sign here
	# has to be positive: pressing left has to steer left, not right.
	rotation.y += turn * delta
	var dir := -global_transform.basis.z
	velocity.x = dir.x * _forward
	velocity.z = dir.z * _forward

func _ai_control(delta: float) -> void:
	var to_target := ai_target - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var desired_yaw := atan2(-to_target.x, -to_target.z) if dist > 0.01 else rotation.y
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(delta * 2.4, 0.0, 1.0))
	var speed_limit := minf(max_speed, ai_speed_limit)
	if dist < 12.0:
		speed_limit = minf(speed_limit, maxf(4.0, dist * 1.1))
	if blocker_ahead():
		speed_limit = 0.0
	_forward = move_toward(_forward, speed_limit, (BRAKE if speed_limit < _forward else accel) * delta)
	var dir := -global_transform.basis.z
	velocity.x = dir.x * _forward
	velocity.z = dir.z * _forward

func _process(_delta: float) -> void:
	if driver_is_player:
		Sfx.set_engine_pitch(clampf(absf(_forward) / max_speed, 0.0, 1.0))

## True when another vehicle or the player blocks the path ahead (TRAFFIC-02).
func blocker_ahead() -> bool:
	var fwd := -global_transform.basis.z
	var origin := global_position + Vector3(0.0, 0.8, 0.0)
	for other in get_tree().get_nodes_in_group("vehicles"):
		if other == self:
			continue
		var d: Vector3 = other.global_position - global_position
		var dist := d.length()
		if dist < 0.5 or dist > 16.0:
			continue
		var dir := d.normalized()
		if dir.dot(fwd) > 0.82:
			return true
	for actor in get_tree().get_nodes_in_group("actors"):
		if actor == self:
			continue
		var d2: Vector3 = actor.global_position - global_position
		if d2.length() < 7.0 and d2.normalized().dot(fwd) > 0.85:
			return true
	return false

func speed_kmh() -> float:
	return absf(_forward) * 3.6

func forward_speed() -> float:
	return _forward

func interact(player: Node) -> void:
	if disabled or driver_is_player:
		return
	if player is Player and (player as Player).busy:
		return
	if occupied_by_npc:
		displace_driver()
	else:
		# taking a vehicle that was moving is still an incident
		Game.add_heat(5.0)
	driver_player = player
	driver_is_player = true
	has_ai = false
	if player is Player:
		(player as Player).busy = true        # guard the transition (PLAYER-03)
	# Disable the passenger immediately, before moving it into the vehicle.
	# Waiting for the next player physics tick lets this body cache the
	# passenger as a floor/platform during the transition.
	if player is CollisionObject3D:
		(player as CollisionObject3D).collision_layer = 0
		(player as CollisionObject3D).collision_mask = 0
	player.current_vehicle = self
	player.visible = false
	player.global_position = global_position
	_arm.rotation.y = 0.0
	_camera.current = true
	Game.set_mode(Game.MODE_CAR)
	Sfx.start_engine()
	player.busy = false            # the transition is complete
	Events.vehicle_entered.emit(self)
	Events.notify.emit("Vehicle entered. [E] to exit.", "info")

func force_exit() -> void:
	Sfx.stop_engine()
	if driver_is_player:
		driver_is_player = false
		_forward = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		if driver_player is Player:
			(driver_player as Player).current_vehicle = null
			(driver_player as Player).busy = false
			(driver_player as Player).visible = true
	driver_player = null

func exit_vehicle(player: Node) -> void:
	if not driver_is_player:
		return
	var exit_pos := _clear_exit_position()
	if exit_pos == Vector3.ZERO:
		Events.notify.emit("No clear space to step out.", "warn")
		return
	driver_is_player = false
	driver_player = null
	_forward = 0.0
	velocity = Vector3.ZERO
	player.global_position = exit_pos
	player.yaw = rotation.y
	player.rotation.y = rotation.y
	player.visible = true
	player.current_vehicle = null
	player.camera.current = true
	player.busy = false
	Game.set_mode(Game.MODE_FOOT)
	Sfx.stop_engine()
	Events.vehicle_exited.emit(self)
	Events.notify.emit("On foot.", "info")

func displace_driver() -> void:
	occupied_by_npc = false
	if _driver and is_instance_valid(_driver):
		if _driver.has_method("become_displaced_pedestrian"):
			_driver.become_displaced_pedestrian(global_position + global_transform.basis.x * 1.8)
		_driver = null
	Game.add_heat(6.0)
	Events.notify.emit("Vehicle taken. Witnesses are looking.", "warn")

func set_ai_driver(driver: Node) -> void:
	_driver = driver
	occupied_by_npc = true

## A clear spot beside the car, or zero when both sides are blocked.
func _clear_exit_position() -> Vector3:
	var right := global_transform.basis.x
	var forward := -global_transform.basis.z
	var offsets: Array[Vector3] = [
		right * 1.9, right * -1.9, forward * 2.9, forward * -2.9,
		right * 2.8 + forward * 1.2, right * -2.8 + forward * 1.2,
	]
	return find_safe_exit(self, offsets)

## A vehicle exit uses the player's actual capsule dimensions, supported by
## a walkable surface. If every candidate is blocked, ownership stays seated.
## This avoids the previous fallback that placed the player inside a wall.
static func find_safe_exit(vehicle: CharacterBody3D, offsets: Array[Vector3]) -> Vector3:
	var space := vehicle.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.75
	for offset in offsets:
		var candidate := vehicle.global_position + offset
		var floor_query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 2.5, candidate - Vector3.UP * 4.0)
		floor_query.collision_mask = 1
		var floor_hit := space.intersect_ray(floor_query)
		if floor_hit.is_empty() or floor_hit["normal"].y < 0.65: continue
		candidate.y = float(floor_hit["position"].y) + 0.08
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP * 0.9)
		query.collision_mask = 1 | 4 | 8
		query.exclude = [vehicle.get_rid()]
		if not space.intersect_shape(query, 1).is_empty(): continue
		var path_query := PhysicsRayQueryParameters3D.create(vehicle.global_position + Vector3.UP * 0.9, candidate + Vector3.UP * 0.9)
		path_query.collision_mask = 1 | 8
		path_query.exclude = [vehicle.get_rid()]
		if space.intersect_ray(path_query).is_empty(): return candidate
	return Vector3.ZERO

func busy() -> bool:
	return driver_is_player

## Vehicle bodywork absorbs incoming fire; occupants are protected until they
## choose to leave. A disabled car still permits a safe exit.
func take_damage(amount: float, _from_position: Vector3, _by_player: bool = false) -> void:
	if disabled:
		return
	var applied := maxf(amount, 0.0) * 0.55
	health = maxf(0.0, health - applied)
	damaged.emit(applied)
	if health <= 0.0:
		disabled = true
		_forward = 0.0
		if driver_is_player:
			Events.notify.emit("Vehicle disabled. [E] to get clear.", "warn")

func is_disabled() -> bool:
	return disabled
