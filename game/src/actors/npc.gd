class_name NPC
extends CharacterBody3D

## Civilian and police characters. Purposeful ambient life (NPC-01), visible
## reactions (NPC-02) and readable combatants (NPC-03) with real damage state
## (COMBAT-03).

static var _officer_down_toast_ms := 0  # combat piece: debounce for the "Officer down." toast
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
## Street-life M1: camera-side roamers (CrowdDirector) keep the cheap ticked
## walk beyond SIM_NEAR_ROAMER of the player; the crowd concentrates them
## round the camera, and full per-tick move_and_slide for ~150 walkers cost
## ~5 ms of physics per tick (headless perf probe).
const SIM_NEAR_ROAMER := 26.0
var _roamer := -1
func _sim_near_sq() -> float:
	if _roamer < 0:
		_roamer = 1 if has_meta("roamer") else 0
	return SIM_NEAR_ROAMER * SIM_NEAR_ROAMER if _roamer == 1 else SIM_NEAR * SIM_NEAR
## Wave-M integration perf: 240 -> 160 m (a figure past 160 m is a few
## pixels even from the helicopter; the crowd was the largest draw family).
const FAR_DRAW_RANGE := 160.0
const NEAR_HIDE := 2.3
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
	# Street-life M2: who this person is (after the spawner set its metas).
	if not is_police:
		call_deferred("_dress_people")
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
	# Hashed id spreads consecutive spawns across the wardrobe (street-life integration).
	if character_visual.configure(role, posmod(hash(get_instance_id()), 997)):
		for child in body_root.get_children():
			if child is Node3D and child != character_visual:
				child.visible = false
		if is_hostile or is_police:
			var gun := AssetLibrary.instantiate("pistol_held.glb", body_root)
			if gun != null:
				character_visual.attach_weapon(gun,"pistol")
		else:
			# Street life: crowds must read from helicopter and aerial views.
			# Beyond CharacterVisual.NPC_DRAW_RANGE the rig already stops
			# animating (set_lod_far), so a distant figure costs one draw.
			for mesh_node in character_visual.find_children("*", "MeshInstance3D", true, false):
				(mesh_node as MeshInstance3D).visibility_range_end = FAR_DRAW_RANGE
				# M1: a passer-by right at the lens is not drawn (a face filled
				# a corner of the rendered route's car-entered frame).
				(mesh_node as MeshInstance3D).visibility_range_begin = NEAR_HIDE

## Street-life M2: women, elders and children with hair, skirts, props and
## poses (crowd_people.gd); a forced kind comes from meta "people_kind".
func _dress_people() -> void:
	if is_police or is_hostile or character_visual == null or not character_visual.loaded:
		return
	var seed_value := posmod(hash(get_instance_id()), 1 << 30)
	var p: Dictionary
	if has_meta("people_kind"):
		p = CrowdPeople.person(int(get_meta("people_kind")), seed_value)
		if has_meta("people_prop"):
			p["prop"] = String(get_meta("people_prop"))
	else:
		p = CrowdPeople.pick(seed_value)
	CrowdPeople.dress(self, character_visual, p, has_meta("ambient_role"))
	_pace_scale = float(p.get("pace", _pace()))

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
			var d2 := global_position.distance_squared_to(cam.global_position)
			character_visual.set_lod_far(state != State.DEAD and d2 > limit * limit)
			# Wave-M integration perf: mid-range figures animate every 3rd frame.
			character_visual.set_lod_mid(d2 > 35.0 * 35.0 and not is_hostile and not is_police)
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
			global_position.distance_squared_to(Game.player_position) > _sim_near_sq():
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
	# Street-life M2: walking together (couples, a parent with a child).
	if companion != null:
		if _walk_with_companion(delta):
			return
	# Off the pavement outside a crossing (after a dodge or a scramble):
	# straight back to the nearest pavement, never along the traffic lane.
	if not is_hostile and not is_police:
		var back := _pavement_return()
		if back != Vector3.INF:
			_kerb_spot = Vector3.INF
			_move_towards(back, WALK_SPEED * maxf(_pace(), 1.0), delta)
			return
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
			# M2: no pause at a lane end; everyone turning at the same point
			# stood in a single-file line there (rendered M1 route, t=25-31 s).
		target = lane[lane_index]
	target = _personal_target(target)
	if _crossing_hold(target):
		velocity.x = 0.0
		velocity.z = 0.0
		# r1: about half of the people reaching a red crossing turn back along
		# the pavement instead of waiting, so walkers arriving behind them do
		# not pile up into a single-file queue along the kerb.
		if _pace() > 1.0 and lane.size() > 1:
			lane_dir = -lane_dir
			lane_index = clampi(lane_index + lane_dir, 0, lane.size() - 1)
		else:
			_kerb_wait(target, delta)
		return
	_kerb_spot = Vector3.INF
	_move_towards(target, WALK_SPEED * _pace(), delta)

## Street-life M2: a stable personal offset across the walk (keep-left of
## the direction of travel), so walkers bound for the same lane points do not
## converge into one file; opposing flows pass side by side.
var _lat_off := INF
func _personal_target(target: Vector3) -> Vector3:
	if lane.size() < 2:
		return target
	if _lat_off == INF:
		_lat_off = lerpf(-0.45, 0.6, float(posmod(hash(get_instance_id() * 104729), 1000)) / 1000.0)
	var prev: Vector3 = lane[clampi(lane_index - lane_dir, 0, lane.size() - 1)]
	var seg: Vector3 = target - prev
	seg.y = 0.0
	if seg.length() < 0.5:
		return target
	return target + Vector3.UP.cross(seg.normalized()) * _lat_off

## Street-life M2: walking with someone (set by CrowdDirector). Returns true
## when this step was handled.
var companion: NPC = null
var companion_side := 0.62
func _walk_with_companion(delta: float) -> bool:
	if not is_instance_valid(companion) or companion.state == State.DEAD or companion.state == State.FLEE \
			or companion.global_position.distance_to(global_position) > 9.0:
		companion = null
		return false
	var lb := companion.global_transform.basis
	var lfwd := Vector3(-lb.z.x, 0.0, -lb.z.z).normalized()
	var lright := Vector3(lb.x.x, 0.0, lb.x.z).normalized()
	var spot := companion.global_position + lright * companion_side - lfwd * 0.12
	var lspeed := Vector2(companion.velocity.x, companion.velocity.z).length()
	if companion.state == State.IDLE or lspeed < 0.15:
		var off := spot - global_position
		off.y = 0.0
		if off.length() > 0.35:
			_move_towards(spot, 1.2, delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			rotation.y = lerp_angle(rotation.y, companion.rotation.y, clampf(delta * 4.0, 0.0, 1.0))
		return true
	var gap := (spot - global_position).dot(lfwd)
	var speed := clampf(lspeed + gap * 0.8, 0.0, lspeed * 1.6 + 0.4)
	_move_towards(spot + lfwd * 1.2, speed, delta)
	return true

## Legacy-grid carriageway test: the nearest pavement point when this person
## stands in a traffic lane outside the junction crossings, else INF.
func _pavement_return() -> Vector3:
	var p := global_position
	if absf(p.x) > 330.0 or absf(p.z) > 330.0:
		return Vector3.INF
	var band := WorldBuilder.ROAD_HALF - 0.2
	for x in WorldBuilder.X_LINES:
		if absf(p.x - x) < band:
			var near_cross := false
			for z in WorldBuilder.Z_LINES:
				if absf(p.z - z) < WorldBuilder.ROAD_HALF + 4.5:
					near_cross = true
			if not near_cross:
				return Vector3(x + signf(p.x - x + 0.001) * (WorldBuilder.ROAD_HALF + 1.6), p.y, p.z)
	for z in WorldBuilder.Z_LINES:
		if absf(p.z - z) < band:
			var near_cross2 := false
			for x in WorldBuilder.X_LINES:
				if absf(p.x - x) < WorldBuilder.ROAD_HALF + 4.5:
					near_cross2 = true
			if not near_cross2:
				return Vector3(p.x, p.y, z + signf(p.z - z + 0.001) * (WorldBuilder.ROAD_HALF + 1.6))
	return Vector3.INF

## Street life r1: each walker keeps a personal pace (0.8-1.2x, stable per
## person), so people seeded near each other drift apart instead of marching
## along the pavement in lockstep columns.
var _pace_scale := 0.0
func _pace() -> float:
	if _pace_scale == 0.0:
		_pace_scale = 0.8 + 0.4 * float(posmod(hash(get_instance_id() * 7919), 1000)) / 1000.0
	return _pace_scale

## Street-life M1: people waiting at a red crossing spread into a loose
## group along and back from the kerb (rendered route: a dozen waiting
## walkers stood in one single-file line along the pavement).
var _kerb_spot := Vector3.INF
func _kerb_wait(target: Vector3, delta: float) -> void:
	var dir := target - global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		return
	dir = dir.normalized()
	if _kerb_spot == Vector3.INF:
		var side := Vector3.UP.cross(dir)
		var h := float(posmod(hash(get_instance_id() * 31 + lane_index), 1000)) / 1000.0
		var spot := global_position + side * lerpf(-1.7, 1.7, h) - dir * fmod(h * 7.0, 1.0) * 1.4
		# Keep the spot on the pavement of the road being walked along.
		var band := WorldBuilder.ROAD_HALF + 0.7
		for x in WorldBuilder.X_LINES:
			if absf(spot.x - x) < band:
				spot.x = x + signf(global_position.x - x) * band
		for z in WorldBuilder.Z_LINES:
			if absf(spot.z - z) < band:
				spot.z = z + signf(global_position.z - z) * band
		_kerb_spot = spot
	var off := _kerb_spot - global_position
	off.y = 0.0
	if off.length() > 0.3:
		_move_towards(_kerb_spot, 0.75, delta)
	else:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 4.0, 0.0, 1.0))

## Street life: wait at the kerb while the road about to be crossed has a
## green (or amber) for its traffic, instead of walking into moving cars.
var _traffic_ref: Node = null
func _crossing_hold(target: Vector3) -> bool:
	if is_hostile or is_police:
		return false
	var dir := target - global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		return false
	dir = dir.normalized()
	var probe := global_position + dir * 0.9
	var band := WorldBuilder.ROAD_HALF + 0.35
	var flow := Vector3.ZERO
	for x in WorldBuilder.X_LINES:
		if absf(probe.x - x) < band and absf(global_position.x - x) >= band:
			flow = Vector3(0, 0, 1)
	for z in WorldBuilder.Z_LINES:
		if absf(probe.z - z) < band and absf(global_position.z - z) >= band:
			flow = Vector3(1, 0, 0)
	if flow == Vector3.ZERO:
		return false
	if _traffic_ref == null or not is_instance_valid(_traffic_ref):
		_traffic_ref = get_tree().get_first_node_in_group("traffic_manager")
	if _traffic_ref == null:
		return false
	# Step off only in the walk phase: that road's traffic is held long enough.
	return not _traffic_ref.ped_may_cross(flow)

## Street life: jump clear of an approaching vehicle, sideways off its path.
func dodge_vehicle(car_pos: Vector3, car_fwd: Vector3) -> void:
	if state == State.DEAD or is_hostile or is_police or state == State.FLEE:
		return
	var side := Vector3.UP.cross(car_fwd).normalized()
	if (global_position - car_pos).dot(side) < 0.0:
		side = -side
	# M2: in the carriageway, always toward the nearer pavement (M1 dodgers
	# ran across into the next live lane and stayed there).
	var kerb := _pavement_return()
	if kerb != Vector3.INF:
		var to_kerb := kerb - global_position
		to_kerb.y = 0.0
		if to_kerb.length() > 0.2:
			side = to_kerb.normalized()
	_flee_dir = (side + car_fwd * 0.15).normalized()
	_flee_speed = 3.6 * clampf(_pace(), 0.7, 1.15)
	state = State.FLEE
	panic_time = 1.3

## Step out of the way of a slow vehicle: a short, quiet flee for civilians.
func scramble_from(from_position: Vector3) -> void:
	if state == State.DEAD or is_hostile or is_police or state == State.FLEE:
		return
	var away := global_position - from_position
	away.y = 0.0
	if away.length() < 0.2:
		away = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
	_flee_dir = away.normalized()
	# M2: a quick step aside at walking pace, not a sprint (M1: packs of
	# people sprinting away from a player who only brushed past them).
	_flee_speed = 1.7
	state = State.FLEE
	panic_time = 1.1

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
	var fs := _flee_speed if _flee_speed > 0.0 else FLEE_SPEED
	velocity.x = move_toward(velocity.x, _flee_dir.x * fs, 12.0 * delta)
	velocity.z = move_toward(velocity.z, _flee_dir.z * fs, 12.0 * delta)
	var fl := Vector3(velocity.x, 0.0, velocity.z)
	if fl.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(-fl.x, -fl.z), clampf(delta * 8.0, 0.0, 1.0))
	if panic_time <= 0.0:
		state = State.WALK
		_flee_speed = 0.0

var _flee_dir := Vector3.ZERO
var _flee_speed := 0.0
## Street-life M2: crowd separation and prop avoidance (CrowdDirector).
var avoid := Vector3.ZERO

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
	# Combat piece: armed NPCs hold and fire from range when they have a clear
	# line (bursts, sidesteps, flinch), and close in otherwise.
	if is_police and Game.wanted_level > 0:
		if dist > NpcCombat.POLICE_RANGE or not NpcCombat.has_line(self, target_position):
			_move_towards(target_position, PURSUE_SPEED, delta)
		else:
			NpcCombat.engage(self, player, target_position, delta)
	elif is_hostile:
		if dist > NpcCombat.HOSTILE_RANGE or not NpcCombat.has_line(self, target_position):
			_move_towards(target_position, PURSUE_SPEED, delta)
		else:
			NpcCombat.engage(self, player, target_position, delta)

func _shoot_at(player: Node, spread: float = 0.0) -> void:
	var target: Node3D = player.controlled_actor() if player.has_method("controlled_actor") else player
	if target == null:
		return
	var origin := global_position + Vector3(0.0, 1.3, 0.0)
	var aim_height := 1.1 if target == player else 1.0
	var dir: Vector3 = (target.global_position + Vector3(0.0, aim_height, 0.0) - origin).normalized()
	if spread > 0.0:
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread)).rotated(dir.cross(Vector3.UP).normalized(), randf_range(-spread, spread) * 0.6).normalized()
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
	var muzzle := character_visual.weapon_muzzle_position() if character_visual != null and character_visual.loaded else origin + dir * 0.45
	CombatFx.get_fx(get_tree()).shot(muzzle, dir, hit["position"] if not hit.is_empty() else origin + dir * 60.0, not hit.is_empty(),
		hit.get("normal", Vector3.ZERO), hit.get("collider"), "npc_pistol", false)
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
	if avoid != Vector3.ZERO and not is_hostile and not is_police:
		dir = (dir + avoid).normalized()
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
	# Combat piece: shove + skeletal flinch, and a short hold on firing.
	CombatFx.get_fx(get_tree()).stagger(self, from_position, amount, health <= 0.0)
	NpcCombat.flinch(self)
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
		# M2: everyone runs their own way at their own speed (M1: a pack of
		# ten identical men sprinting in step), elders can only hurry.
		_flee_dir = _flee_dir.rotated(Vector3.UP, randf_range(-0.75, 0.75))
		_flee_speed = randf_range(3.2, 5.4) * clampf(_pace(), 0.55, 1.1)
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
		# One toast per burst of police deaths (wave Q2: no stacked duplicates).
		var now_ms := Time.get_ticks_msec()
		if now_ms - _officer_down_toast_ms > 6000 or _officer_down_toast_ms == 0:
			_officer_down_toast_ms = now_ms
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
