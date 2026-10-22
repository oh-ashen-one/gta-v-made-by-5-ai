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
var _blocker_timer := 0.0
var _blocked_cached := false
## Baked-tyre centres measured from each provider body in Car space
## (tools/wheel_probe.gd, wave 5): front/rear z, outer face x, tyre radius.
const WHEEL_FIT := {
	"sedan": {"zf": -1.36, "zr": 1.19, "x": 0.885, "r": 0.355, "xl": 0.885},
	"police": {"zf": -1.36, "zr": 1.19, "x": 0.885, "r": 0.355, "xl": 0.885},
	"coupe": {"zf": -1.21, "zr": 1.21, "x": 0.925, "r": 0.355, "xl": 0.925},
	"van": {"zf": -1.38, "zr": 1.37, "x": 0.97, "r": 0.39, "xl": 0.74},
}
var _articulated: Array[Dictionary] = []
## AI stuck recovery: a car that wants to move but has not covered half a metre
## in two seconds backs out, turning, for 1.6 s (TRAFFIC recovery, wave 5).
var _stuck_check_pos := Vector3.ZERO
var _stuck_check_time := 0.0
var _reverse_time := 0.0
var _ai_steer_visual := 0.0
static var _wheel_meshes: Array[Mesh] = []
## Seated driver silhouette (ART-06 occupants, wave 5): moving and occupied cars
## were visibly driverless because the driver NPC/player is hidden while seated.
## Right-hand drive: the driver sits on +X when the car faces -Z.
const DRIVER_SEAT := {"sedan": Vector3(0.38, 0.0, 0.12), "police": Vector3(0.38, 0.0, 0.12), "coupe": Vector3(0.40, -0.08, 0.18), "van": Vector3(0.42, 0.42, -0.55)}
static var _driver_parts: Array = []
var _driver_bust: Node3D = null
## Simulation LOD (wave 5): AI traffic beyond SIM_NEAR of the player integrates
## along its lane every SIM_FAR_TICKS ticks without a collision solve (measured
## ~130 us per AI car per tick headless). Settled parked cars stop ticking until
## someone takes them.
const SIM_NEAR := 110.0
const SIM_FAR_TICKS := 3
var _sim_accum := 0.0
var _sim_slot := 0

func _ready() -> void:
	_sim_slot = int(get_instance_id() % SIM_FAR_TICKS)
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
		if global_position.distance_squared_to(Game.player_position) > SIM_NEAR * SIM_NEAR:
			# Steering/speed decisions every SIM_FAR_TICKS ticks; motion every tick
			# (cheap direct integration) so distant traffic does not judder.
			_sim_accum += delta
			_sim_slot = (_sim_slot + 1) % SIM_FAR_TICKS
			if _sim_slot == 0:
				_ai_control(_sim_accum)
				_sim_accum = 0.0
			global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
			_spin_wheels(delta)
			return
		_sim_accum = 0.0
		_ai_control(delta)
	else:
		_forward = move_toward(_forward, 0.0, ACCEL * delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if is_zero_approx(_forward) and is_on_floor():
			velocity = Vector3.ZERO
			# Parked and settled: sleep until interact() or a pool wakes it.
			set_physics_process(false)
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

func _update_driver_bust() -> void:
	var seated := driver_is_player or has_ai or occupied_by_npc
	if seated and _driver_bust == null and not disabled:
		if _driver_parts.is_empty():
			var torso := CapsuleMesh.new()
			torso.radius = 0.2
			torso.height = 0.62
			var head := SphereMesh.new()
			head.radius = 0.105
			head.height = 0.23
			_driver_parts = [torso, head, Palette.mat(Color(0.16, 0.18, 0.22), 0.9), Palette.mat(Color(0.52, 0.38, 0.29), 0.7)]
		_driver_bust = Node3D.new()
		_driver_bust.position = DRIVER_SEAT.get(kind, DRIVER_SEAT["sedan"]) + Vector3(0.0, 0.0, 0.0)
		add_child(_driver_bust)
		for part in [[0, 2, Vector3(0.0, 0.86, 0.0)], [1, 3, Vector3(0.0, 1.16, -0.02)]]:
			var mi := MeshInstance3D.new()
			mi.mesh = _driver_parts[part[0]]
			mi.material_override = _driver_parts[part[1]]
			mi.position = part[2]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 90.0
			_driver_bust.add_child(mi)
	if _driver_bust != null:
		_driver_bust.visible = seated

func _spin_wheels(delta: float) -> void:
	var roll := _forward * delta * 2.4
	if Engine.get_physics_frames() % 30 == get_instance_id() % 30:
		_update_driver_bust()
	if _provider_root != null:
		# The provider bodies have their tyres baked into one mesh (their wheel_*
		# nodes are stray strips). Moving cars get articulated overlay wheels at
		# the measured baked-tyre positions instead (tools/wheel_probe.gd).
		if _articulated.is_empty() and (driver_is_player or has_ai):
			_build_articulated_wheels()
		if not _articulated.is_empty():
			var r: float = WHEEL_FIT.get(kind, WHEEL_FIT["sedan"])["r"]
			var steer_visual := clampf(_steer if driver_is_player else _ai_steer_visual, -1.0, 1.0) * 0.32
			for wheel in _articulated:
				wheel["spin"].rotate_x(-_forward * delta / r)
				if wheel["front"]:
					wheel["pivot"].rotation.y = steer_visual
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
	_ai_steer_visual = clampf(angle_difference(rotation.y, desired_yaw) * 2.0, -1.0, 1.0)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(delta * 2.4, 0.0, 1.0))
	var speed_limit := minf(max_speed, ai_speed_limit)
	if dist < 12.0:
		speed_limit = minf(speed_limit, maxf(4.0, dist * 1.1))
	# The perception scan walks every vehicle and pedestrian, so it refreshes at
	# ~8 Hz per car (staggered by instance) rather than on every physics tick.
	_blocker_timer -= delta
	if _blocker_timer <= 0.0:
		_blocker_timer = 0.12 + float(get_instance_id() % 7) * 0.004
		_blocked_cached = blocker_ahead()
	if _blocked_cached:
		speed_limit = 0.0
	if _reverse_time > 0.0:
		_reverse_time -= delta
		_forward = move_toward(_forward, -4.0, BRAKE * delta)
		rotation.y += 0.9 * delta
	else:
		_forward = move_toward(_forward, speed_limit, (BRAKE if speed_limit < _forward else accel) * delta)
		_stuck_check_time += delta
		if _stuck_check_time >= 2.0:
			if speed_limit > 3.0 and global_position.distance_to(_stuck_check_pos) < 0.5:
				_reverse_time = 1.6
			_stuck_check_pos = global_position
			_stuck_check_time = 0.0
	var dir := -global_transform.basis.z
	velocity.x = dir.x * _forward
	velocity.z = dir.z * _forward

func _process(_delta: float) -> void:
	if driver_is_player:
		Sfx.set_engine_pitch(clampf(absf(_forward) / max_speed, 0.0, 1.0))

## True when another vehicle or the player blocks the path ahead (TRAFFIC-02).
func blocker_ahead() -> bool:
	# A lane-width corridor, not a view cone: the old 35-degree cone also caught
	# cars parked at the kerb beside the lane, so traffic queued behind them.
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var left := Vector3.UP.cross(fwd)
	for other in get_tree().get_nodes_in_group("vehicles"):
		if other == self or not (other as Node3D).visible:
			continue
		var d: Vector3 = other.global_position - global_position
		if absf(d.x) > 16.5 or absf(d.z) > 16.5:
			continue
		var ahead := d.dot(fwd)
		if ahead > 0.5 and ahead < 16.0 and absf(d.dot(left)) < 1.9:
			return true
	for actor in get_tree().get_nodes_in_group("actors"):
		if actor == self or not (actor as Node3D).visible:
			continue
		var d2: Vector3 = actor.global_position - global_position
		if absf(d2.x) > 7.5 or absf(d2.z) > 7.5:
			continue
		var ahead2 := d2.dot(fwd)
		if ahead2 > 0.3 and ahead2 < 7.0 and absf(d2.dot(left)) < 1.5:
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
	set_physics_process(true)
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
	_update_driver_bust()
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
	_update_driver_bust()
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
	_update_driver_bust()

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

## One shared tyre + rim mesh (two surfaces), built once for every car.
static func _articulated_wheel_mesh() -> Mesh:
	if not _wheel_meshes.is_empty():
		return _wheel_meshes[0]
	var rubber := Palette.mat(Color(0.045, 0.045, 0.05), 0.92)
	var alloy := Palette.mat(Color(0.70, 0.71, 0.73), 0.32, 0.85)
	# Procedural winding is not hand-checked per face; draw both sides.
	rubber.cull_mode = BaseMaterial3D.CULL_DISABLED
	alloy.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	# Tyre: unit radius, 0.25 wide along X, with a rounded shoulder.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 28
	var profile: Array[Vector2] = [Vector2(-0.5, 0.80), Vector2(-0.5, 0.94), Vector2(-0.42, 1.0), Vector2(0.42, 1.0), Vector2(0.5, 0.94), Vector2(0.5, 0.80)]
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for k in profile.size() - 1:
			var p0: Vector2 = profile[k]
			var p1: Vector2 = profile[k + 1]
			var v00 := Vector3(p0.x * 0.25, cos(a0) * p0.y, sin(a0) * p0.y)
			var v01 := Vector3(p0.x * 0.25, cos(a1) * p0.y, sin(a1) * p0.y)
			var v10 := Vector3(p1.x * 0.25, cos(a0) * p1.y, sin(a0) * p1.y)
			var v11 := Vector3(p1.x * 0.25, cos(a1) * p1.y, sin(a1) * p1.y)
			for v in [v00, v10, v11, v00, v11, v01]:
				st.add_vertex(v)
	st.generate_normals()
	st.set_material(rubber)
	var mesh := st.commit()
	# Rim: recessed alloy dish with five spokes on both faces.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: float in [-1.0, 1.0]:
		var x := face * 0.105
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			# outer lip ring
			var o0 := Vector3(x, cos(a0) * 0.80, sin(a0) * 0.80)
			var o1 := Vector3(x, cos(a1) * 0.80, sin(a1) * 0.80)
			var i0 := Vector3(x, cos(a0) * 0.70, sin(a0) * 0.70)
			var i1 := Vector3(x, cos(a1) * 0.70, sin(a1) * 0.70)
			for v in ([o0, i0, i1, o0, i1, o1] if face > 0 else [o0, i1, i0, o0, o1, i1]):
				st.add_vertex(v)
			# dark recessed dish behind the spokes
			var d := Vector3(x - face * 0.04, 0.0, 0.0)
			var d0 := Vector3(x - face * 0.04, cos(a0) * 0.70, sin(a0) * 0.70)
			var d1 := Vector3(x - face * 0.04, cos(a1) * 0.70, sin(a1) * 0.70)
			for v in ([d, d0, d1] if face > 0 else [d, d1, d0]):
				st.add_vertex(v)
		for sp in 5:
			var a := TAU * sp / 5.0
			var axis := Vector3(0.0, cos(a), sin(a))
			var side := Vector3(0.0, -sin(a), cos(a)) * 0.075
			var root := Vector3(x, 0.0, 0.0) + axis * 0.16
			var tip := Vector3(x, 0.0, 0.0) + axis * 0.72
			var q := [root - side, tip - side * 0.6, tip + side * 0.6, root + side]
			for v in ([q[0], q[1], q[2], q[0], q[2], q[3]] if face > 0 else [q[0], q[2], q[1], q[0], q[3], q[2]]):
				st.add_vertex(v)
		# hub cap
		for i in 12:
			var a0 := TAU * i / 12.0
			var a1 := TAU * (i + 1) / 12.0
			var c := Vector3(x + face * 0.01, 0.0, 0.0)
			var h0 := c + Vector3(0.0, cos(a0) * 0.18, sin(a0) * 0.18)
			var h1 := c + Vector3(0.0, cos(a1) * 0.18, sin(a1) * 0.18)
			for v in ([c, h0, h1] if face > 0 else [c, h1, h0]):
				st.add_vertex(v)
	st.generate_normals()
	st.set_material(alloy)
	st.commit(mesh)
	_wheel_meshes.append(mesh)
	return mesh

func _build_articulated_wheels() -> void:
	var fit: Dictionary = WHEEL_FIT.get(kind, WHEEL_FIT["sedan"])
	var r: float = fit["r"]
	var mesh := _articulated_wheel_mesh()
	for front: bool in [true, false]:
		for side: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			var outer: float = fit["x"] if side > 0.0 else fit["xl"]
			# Outer face sits just proud of the baked tyre so it covers it.
			pivot.position = Vector3(side * (outer - 0.11), r, fit["zf"] if front else fit["zr"])
			add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			var wheel := MeshInstance3D.new()
			wheel.mesh = mesh
			wheel.scale = Vector3(1.0, r, r)
			wheel.visibility_range_end = 140.0
			spin.add_child(wheel)
			_articulated.append({"pivot": pivot, "spin": spin, "front": front})
