class_name NPC
extends CharacterBody3D
## Civilian and police characters. Purposeful ambient life (NPC-01), visible
## reactions (NPC-02) and readable combatants (NPC-03) with real damage state
## (COMBAT-03).

enum State { WALK, IDLE, FLEE, DEAD, PURSUE }

const WALK_SPEED := 1.5
const FLEE_SPEED := 4.6
const PURSUE_SPEED := 3.4

var state: int = State.WALK
var health := 100.0
var is_police := false
var is_hostile := false
var lane: Array = []
var lane_index := 0
var lane_dir := 1
var idle_time := 0.0
var panic_time := 0.0
var fire_timer := 0.0
var body_root: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _torso: MeshInstance3D
var _shirt_color := Color(0.7, 0.7, 0.7)
var _spawn_position := Vector3.ZERO
var _home_lane := 0

func _ready() -> void:
	add_to_group("npcs")
	add_to_group("actors")
	collision_layer = 4
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(60.0)
	_build()
	_spawn_position = global_position
	Events.shot_fired.connect(_on_shot_fired)
	Events.hit_landed.connect(_on_hit_landed)

func _build() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.72
	shape.shape = cap
	shape.position = Vector3(0.0, 0.88, 0.0)
	add_child(shape)

	body_root = Node3D.new()
	add_child(body_root)
	var skin := Palette.mat(Palette.SKIN.lerp(Color(0.55, 0.40, 0.30), randf() * 0.6), 0.8)
	_shirt_color = Palette.FRONTAGES[randi() % Palette.FRONTAGES.size()] if not is_police else Color(0.16, 0.20, 0.32)
	var shirt := Palette.mat(_shirt_color, 0.88)
	var pants := Palette.mat(Color(0.16, 0.17, 0.20).lerp(Color(0.35, 0.30, 0.26), randf()), 0.9)

	_torso = MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.52, 0.74, 0.28)
	_torso.mesh = tb
	_torso.material_override = shirt
	_torso.position = Vector3(0.0, 1.16, 0.0)
	body_root.add_child(_torso)

	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.24, 0.28, 0.24)
	head.mesh = hb
	head.material_override = skin
	head.position = Vector3(0.0, 1.66, 0.0)
	body_root.add_child(head)
	if is_police:
		var cap_mesh := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.26, 0.09, 0.26)
		cap_mesh.mesh = cm
		cap_mesh.material_override = Palette.mat(Color(0.10, 0.12, 0.20), 0.85)
		cap_mesh.position = Vector3(0.0, 1.82, 0.0)
		body_root.add_child(cap_mesh)

	_leg_l = _limb(Vector3(0.13, 0.80, 0.0), Vector3(0.18, 0.80, 0.20), pants)
	_leg_r = _limb(Vector3(-0.13, 0.80, 0.0), Vector3(0.18, 0.80, 0.20), pants)
	_arm_l = _limb(Vector3(0.31, 1.34, 0.0), Vector3(0.14, 0.60, 0.16), shirt)
	_arm_r = _limb(Vector3(-0.31, 1.34, 0.0), Vector3(0.14, 0.60, 0.16), shirt)
	if is_hostile or is_police:
		var gun := MeshInstance3D.new()
		var gb := BoxMesh.new()
		gb.size = Vector3(0.08, 0.11, 0.4)
		gun.mesh = gb
		gun.material_override = Palette.mat(Color(0.09, 0.09, 0.10), 0.35, 0.85)
		gun.position = Vector3(-0.30, 1.12, -0.24)
		body_root.add_child(gun)

func _limb(hip: Vector3, size: Vector3, cloth: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = hip
	body_root.add_child(pivot)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = cloth
	mesh.position = Vector3(0.0, -size.y * 0.5, 0.0)
	pivot.add_child(mesh)
	return pivot

func assign_lane(lanes: Array, lane_id: int) -> void:
	_home_lane = lane_id
	if lanes.is_empty():
		return
	lane = lanes[lane_id % lanes.size()]
	lane_index = randi() % maxi(1, lane.size())
	lane_dir = 1 if randf() > 0.5 else -1

func become_displaced_pedestrian(pos: Vector3) -> void:
	global_position = pos
	state = State.FLEE
	panic_time = 6.0
	health = maxf(health, 60.0)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 24.0 * delta
		move_and_slide()
		return
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = -0.5
	match state:
		State.WALK:
			_walk(delta)
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			idle_time -= delta
			if idle_time <= 0.0:
				state = State.WALK
		State.FLEE:
			_flee(delta)
		State.PURSUE:
			_pursue(delta)
	move_and_slide()
	_animate(delta, Vector2(velocity.x, velocity.z).length())

func _walk(delta: float) -> void:
	if lane.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	lane_index += lane_dir
	if lane_index < 0 or lane_index >= lane.size():
		lane_dir = -lane_dir
		lane_index = clampi(lane_index, 0, lane.size() - 1)
		if randf() < 0.35:
			state = State.IDLE
			idle_time = randf_range(2.0, 7.0)
			return
	var target: Vector3 = lane[lane_index]
	_move_towards(target, WALK_SPEED, delta)

func _flee(delta: float) -> void:
	panic_time -= delta
	velocity.x = move_toward(velocity.x, _flee_dir.x * FLEE_SPEED, 12.0 * delta)
	velocity.z = move_toward(velocity.z, _flee_dir.z * FLEE_SPEED, 12.0 * delta)
	if panic_time <= 0.0:
		state = State.WALK

var _flee_dir := Vector3.ZERO

func _pursue(delta: float) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		state = State.WALK
		return
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > 42.0:
		state = State.WALK
		return
	if is_police and Game.wanted_level > 0:
		if dist > 9.0:
			_move_towards(player.global_position, PURSUE_SPEED, delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			fire_timer -= delta
			if fire_timer <= 0.0:
				fire_timer = 1.6
				_shoot_at(player)
	elif is_hostile:
		if dist > 7.0:
			_move_towards(player.global_position, PURSUE_SPEED, delta)
		else:
			fire_timer -= delta
			if fire_timer <= 0.0:
				fire_timer = 1.1
				_shoot_at(player)

func _shoot_at(player: Node) -> void:
	var origin := global_position + Vector3(0.0, 1.3, 0.0)
	var dir: Vector3 = (player.global_position + Vector3(0.0, 1.1, 0.0) - origin).normalized()
	Events.shot_fired.emit(origin, dir, "npc_pistol")
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0)
	params.collision_mask = 1 | 2
	params.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty():
		var collider = hit["collider"]
		if collider and collider.has_method("take_damage"):
			collider.take_damage(9.0, global_position, false)
			Events.hit_landed.emit(collider, 9.0, hit["position"], false)

func _move_towards(target: Vector3, speed: float, delta: float) -> void:
	var dir := target - global_position
	dir.y = 0.0
	if dir.length() < 0.4:
		return
	dir = dir.normalized()
	velocity.x = move_toward(velocity.x, dir.x * speed, 10.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 10.0 * delta)
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 6.0, 0.0, 1.0))

func _animate(delta: float, speed: float) -> void:
	var stride: float = clampf(speed / 2.2, 0.0, 1.4)
	_walk_phase += delta * (5.0 + speed * 3.0)
	var swing: float = sin(_walk_phase) * stride * 0.6
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	_arm_l.rotation.x = -swing * 0.7
	_arm_r.rotation.x = swing * 0.7
	if is_police or is_hostile:
		_arm_r.rotation.x = -1.2
	if state == State.FLEE:
		_arm_l.rotation.x = -1.5
		_arm_r.rotation.x = -1.5

var _walk_phase := 0.0

func take_damage(amount: float, from_position: Vector3, by_player: bool = true) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if by_player:
		Game.add_heat(4.0 if not is_police else 8.0)
	_panic(from_position)
	if health <= 0.0:
		_die(by_player)

func _panic(from_position: Vector3) -> void:
	if state == State.DEAD:
		return
	var away := global_position - from_position
	away.y = 0.0
	if away.length() < 0.2:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	_flee_dir = away.normalized()
	if not is_police and not is_hostile:
		state = State.FLEE
		panic_time = randf_range(6.0, 12.0)
		Events.toast("Civilian fleeing!", "info")

func _die(by_player: bool) -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	body_root.rotation_degrees = Vector3(82.0, rotation.y, 0.0)
	body_root.position = Vector3(0.0, 0.35, 0.0)
	collision_layer = 0
	Events.actor_died.emit(self, by_player)
	if is_police:
		Game.add_heat(12.0)
		Events.toast("Officer down.", "bad")

func _on_shot_fired(origin: Vector3, _dir: Vector3, _weapon_id: String) -> void:
	if state == State.DEAD:
		return
	var d := global_position.distance_to(origin)
	if d > 26.0:
		return
	if not is_police and not is_hostile:
		_panic(origin)

func _on_hit_landed(_target: Node, _dmg: float, _point: Vector3, _by_player: bool) -> void:
	pass
