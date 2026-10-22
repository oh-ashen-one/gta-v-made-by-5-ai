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
var character_visual: CharacterVisual
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _torso: MeshInstance3D
var _shirt_color := Color(0.7, 0.7, 0.7)
var _spawn_position := Vector3.ZERO
var _home_lane := 0
## Simulation level of detail (wave 5). Headless attribution measured the 185
## ambient NPCs at ~6 ms of an ~11 ms physics tick. Settled idle actors skip the
## collision solve; calm walkers beyond SIM_NEAR of the player advance along
## their lane every SIM_FAR_TICKS ticks by direct integration. Anyone panicking,
## pursuing, hostile, police or near the player keeps per-tick move_and_slide.
const SIM_NEAR := 70.0
const SIM_FAR_TICKS := 4
var _sim_accum := 0.0
var _sim_slot := 0

func _ready() -> void:
	add_to_group("npcs")
	add_to_group("actors")
	collision_layer = 4
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(60.0)
	_build()
	_spawn_position = global_position
	_sim_slot = int(get_instance_id() % SIM_FAR_TICKS)
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
	body_root.position.y = 0.02 # capsule lower extent
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

	character_visual = CharacterVisual.new()
	body_root.add_child(character_visual)
	var role := "officer" if is_police else "civilian"
	if character_visual.configure(role, get_instance_id() % 24):
		for child in body_root.get_children():
			if child is Node3D and child != character_visual:
				child.visible = false
		if is_hostile or is_police:
			var gun := AssetLibrary.instantiate("pistol_held.glb", body_root)
			if gun != null:
				character_visual.attach_weapon(gun,"pistol")

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

func become_displaced_pedestrian(pos: Vector3, threat: Vector3 = Vector3.INF) -> void:
	global_position = pos
	collision_layer = 4
	collision_mask = 1 | 4
	set_physics_process(true)
	set_process(true)
	state = State.FLEE
	panic_time = 6.0
	health = maxf(health, 60.0)
	visible = true
	# Run away from the vehicle that was taken, not in a random direction.
	var away := (global_position - threat) if threat != Vector3.INF else Vector3.ZERO
	away.y = 0.0
	if away.length() < 0.2:
		away = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
	_flee_dir = away.normalized()
	lane = []

func _physics_process(delta: float) -> void:
	if Game.simulation_paused:
		return
	# Render LOD on a fixed per-NPC phase (critic pass 2: the old gate reused
	# the far-walk slot, which advances every tick, so most NPCs never checked).
	if (Engine.get_physics_frames() + get_instance_id()) % 8 == 0 and character_visual != null and character_visual.loaded:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var limit := CharacterVisual.NPC_DRAW_RANGE + 10.0
			character_visual.set_lod_far(state != State.DEAD and global_position.distance_squared_to(cam.global_position) > limit * limit)
	if state == State.DEAD:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 24.0 * delta
		move_and_slide()
		return
	if state == State.IDLE and is_on_floor() and not is_hostile and not is_police:
		# Settled: no collision solve while standing or seated.
		velocity = Vector3.ZERO
		idle_time -= delta
		if idle_time <= 0.0:
			# Seated diners keep their seat until something startles them.
			if has_meta("ambient_role"):
				idle_time = 3600.0
			else:
				state = State.WALK
		_animate(delta, 0.0)
		return
	if state == State.WALK and not is_hostile and not is_police and \
			global_position.distance_squared_to(Game.player_position) > SIM_NEAR * SIM_NEAR:
		_sim_accum += delta
		_sim_slot = (_sim_slot + 1) % SIM_FAR_TICKS
		if _sim_slot == 0:
			_walk(_sim_accum)
			_animate(_sim_accum, Vector2(velocity.x, velocity.z).length())
			_sim_accum = 0.0
		global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
		return
	_sim_accum = 0.0
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
	if lane.is_empty() and not is_hostile and not is_police:
		# A displaced driver or other lane-less civilian rejoins the nearest
		# pavement instead of standing frozen in a carriageway (wave 5 soak).
		# Mission guards and officers keep holding their posts as before.
		_adopt_nearest_lane()
	if lane.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var target: Vector3 = lane[lane_index]
	var distance := Vector2(target.x - global_position.x, target.z - global_position.z).length()
	if distance < 0.8:
		lane_index += lane_dir
		if lane_index < 0 or lane_index >= lane.size():
			lane_dir = -lane_dir
			lane_index = clampi(lane_index, 0, lane.size() - 1)
			if randf() < 0.35:
				state = State.IDLE
				idle_time = randf_range(2.0, 7.0)
				return
		target = lane[lane_index]
	_move_towards(target, WALK_SPEED, delta)

## Step out of the way of a slow vehicle: a short, quiet flee for civilians.
func scramble_from(from_position: Vector3) -> void:
	if state == State.DEAD or is_hostile or is_police or state == State.FLEE:
		return
	var away := global_position - from_position
	away.y = 0.0
	if away.length() < 0.2:
		away = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
	_flee_dir = away.normalized()
	state = State.FLEE
	panic_time = 2.5

func _adopt_nearest_lane() -> void:
	var traffic := get_tree().get_first_node_in_group("traffic_manager")
	if traffic == null: return
	var best_lane: Array = []
	var best_index := 0
	var best := INF
	for candidate in traffic.get("_ped_lanes"):
		var points: Array = candidate
		for i in points.size():
			var d := global_position.distance_squared_to(points[i])
			if d < best:
				best = d
				best_lane = points
				best_index = i
	if best_lane.size() >= 2:
		lane = best_lane
		lane_index = best_index
		lane_dir = 1 if best_index < best_lane.size() - 1 else -1

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
	var target_position: Vector3 = player.global_position
	if player.has_method("controlled_actor"):
		target_position = player.controlled_actor().global_position
	var to_player: Vector3 = target_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > 42.0:
		state = State.WALK
		return
	if is_police and Game.wanted_level > 0:
		if dist > 9.0:
			_move_towards(target_position, PURSUE_SPEED, delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			fire_timer -= delta
			if fire_timer <= 0.0:
				fire_timer = 2.0
				_shoot_at(player)
	elif is_hostile:
		if dist > 7.0:
			_move_towards(target_position, PURSUE_SPEED, delta)
		else:
			fire_timer -= delta
			if fire_timer <= 0.0:
				fire_timer = 1.4
				_shoot_at(player)

func _shoot_at(player: Node) -> void:
	var target: Node3D = player.controlled_actor() if player.has_method("controlled_actor") else player
	if target == null:
		return
	var origin := global_position + Vector3(0.0, 1.3, 0.0)
	var aim_height := 1.1 if target == player else 1.0
	var dir: Vector3 = (target.global_position + Vector3(0.0, aim_height, 0.0) - origin).normalized()
	Events.shot_fired.emit(origin, dir, "npc_pistol")
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0)
	# Cars and aircraft are cover for their occupants. The ray stops on the
	# bodywork and damages it; it cannot hit a hidden player at the entry spot.
	params.collision_mask = 1 | 2 | 8
	var excluded: Array[RID] = [get_rid()]
	if target != player:
		excluded.append(player.get_rid())
	params.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty():
		var collider = hit["collider"]
		if collider and collider.has_method("take_damage"):
			collider.take_damage(5.5, global_position, false)
			Events.hit_landed.emit(collider, 5.5, hit["position"], false)

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
	if character_visual != null and character_visual.loaded:
		character_visual.set_motion(speed, (is_police or is_hostile) and state == State.PURSUE, is_on_floor())
		return
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
	if character_visual != null and character_visual.loaded and health > 0:
		character_visual.play_hit()
	if by_player:
		Game.add_heat(4.0 if not is_police else 8.0)
	_panic(from_position)
	if health <= 0.0:
		_die(by_player)

func _panic(from_position: Vector3) -> void:
	if state == State.DEAD:
		return
	if character_visual != null and character_visual.loaded:
		character_visual.set_seated(false)
		character_visual.position.y=0.0
	var away := global_position - from_position
	away.y = 0.0
	if away.length() < 0.2:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	_flee_dir = away.normalized()
	if is_hostile or is_police:
		state = State.PURSUE
	elif not is_police and not is_hostile:
		# Announce only the change into fleeing, not every repeat (critic pass 3).
		var was_fleeing := state == State.FLEE
		state = State.FLEE
		panic_time = randf_range(6.0, 12.0)
		if not was_fleeing:
			Events.toast("Civilian fleeing!", "info")

func _die(by_player: bool) -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	if character_visual != null and character_visual.loaded:
		character_visual.position.y=0.0
		character_visual.play_death()
	else:
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
	if _weapon_id != "npc_pistol":
		_panic(origin)

func _on_hit_landed(_target: Node, _dmg: float, _point: Vector3, _by_player: bool) -> void:
	pass
