extends Node3D
## Public SkyPark lift: a deliberate, labelled in-game level transition.
## Keeps the authored MBS silhouette and opens only a collision-enclosed terrace.
## Helicopter permissions remain the plan's responsibility, after runtime QA.
const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")
const MBS = preload("res://src/world/downtown/landmarks/mbs.gd")
const RANGE := 3.5
const DECK_Y := MBS.DECK_Y
const TERRACE := Rect2(30.0, -4.0, 54.0, 18.0) # relative to (MBS.x, MBS.z + 2)
const PAD_OFFSET := Vector3(55.0, DECK_Y, 7.0) # relative to MBS x/z
const PAD_RADIUS := 5.0
const PAD_EXIT_RADIUS := 2.5
var player: Player
var stations: Dictionary = {}
var _next_use_ms := 0

class LiftStation extends Node3D:
	var access: Node
	var station_id: String
	var prompt_text: String
	func _ready() -> void:
		add_to_group("interactables")
	func can_interact() -> bool:
		return access.can_use_station(station_id)
	func interact(actor: Node) -> void:
		access.use_station(station_id, actor)

static func ground_position() -> Vector3:
	return DowntownPlan.anchor("marina_bay_sands") + Vector3(40.0, MBS.TERRACE_Y + 0.1, 47.0)

static func roof_position() -> Vector3:
	return DowntownPlan.anchor("marina_bay_sands") + Vector3(79.0, DECK_Y + 0.1, 7.0)

static func pad_position() -> Vector3:
	return DowntownPlan.anchor("marina_bay_sands") + PAD_OFFSET

static func on_public_terrace(p: Vector3, margin: float = 0.8) -> bool:
	var m := DowntownPlan.anchor("marina_bay_sands")
	return TERRACE.grow(-margin).has_point(Vector2(p.x - m.x, p.z - m.z - 2.0)) and absf(p.y - DECK_Y) < 2.5

func setup(world: WorldBuilder, p: Player) -> void:
	if not stations.is_empty(): return
	player = p
	name = "SkyParkAccess"
	add_to_group("skypark_access")
	var m := DowntownPlan.anchor("marina_bay_sands")
	var kit := Kit.new(self, "SkyParkPublicCollision")
	# 2.4 m laminated glass wind screens: actual rails at the visible boundaries,
	# inside the existing solid deck. This prevents jumping onto pool/scenery.
	var x0 := m.x + TERRACE.position.x
	var x1 := m.x + TERRACE.end.x
	var z0 := m.z + 2.0 + TERRACE.position.y
	var z1 := m.z + 2.0 + TERRACE.end.y
	var corners := [Vector3(x0, DECK_Y, z0), Vector3(x1, DECK_Y, z0), Vector3(x1, DECK_Y, z1), Vector3(x0, DECK_Y, z1)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		Realm.glass_rail(kit, a, b, 2.4)
		kit.col_beam(a + Vector3.UP * 2.4, b + Vector3.UP * 2.4, 0.16, 2.4)
	_add_station(kit, "ground", ground_position() - Vector3(0, 0.1, 2), "SKYPARK PUBLIC LIFT\n[E] Observation terrace", "[E] Take public lift to SkyPark")
	_add_station(kit, "roof", roof_position() - Vector3(0, 0.1, 2), "PUBLIC LIFT\n[E] Shoppes / Event Plaza", "[E] Return to Shoppes / Event Plaza")
	# Existing landmark benches give the western viewing edge a public use,
	# well outside the measured rotor/exit area and the lift-to-pad path.
	var benches := []
	for dx: float in [36.0, 43.0]:
		var bench_at := m + Vector3(dx, DECK_Y, 12.0)
		benches.append(Kit.xf(bench_at))
		kit.col_box(Vector3(2.0, 0.5, 0.5), bench_at + Vector3.UP * 0.25)
	Realm.benches(self, "SkyParkViewingBenches", benches)
	_pad_marking(kit)
	kit.commit(self, "SkyParkLiftAndRails", false, 450.0)
	world.locations["skypark_public_lift"] = ground_position()
	world.locations["skypark_public_terrace"] = roof_position()
	world.locations["helipad_skypark"] = pad_position()
	set_meta("collision_shapes", kit.shapes)

func _add_station(kit: Kit, id: String, at: Vector3, title: String, prompt: String) -> void:
	var station := LiftStation.new()
	station.name = "SkyParkLift_" + id
	station.access = self
	station.station_id = id
	station.prompt_text = prompt
	station.position = at
	add_child(station)
	stations[id] = station
	# Compact paired lift doors and frame, using the landmark's existing palette.
	# Interaction target stands in front; the door collision never masks its LOS.
	var back := at + Vector3(0, 0, -0.65)
	kit.box(Looks.get_mat("steel_dark"), back + Vector3(0, 1.5, -0.8), Vector3(3.5, 3.0, 1.95))
	kit.col_box(Vector3(3.5, 3.0, 1.95), back + Vector3(0, 1.5, -0.8))
	kit.box(Looks.get_mat("steel_white"), back + Vector3(0, 3.05, -0.8), Vector3(3.8, 0.1, 2.15))
	for dx: float in [-0.77, 0.77]:
		kit.box(Looks.get_mat("steel_satin"), back + Vector3(dx, 1.35, 0.2), Vector3(1.45, 2.6, 0.04))
	kit.box(Looks.get_mat("signage"), back + Vector3(0, 3.15, 0), Vector3(4.6, 0.85, 0.4))
	var label := Label3D.new()
	label.text = title
	label.font_size = 48
	label.pixel_size = 0.003
	label.outline_size = 0
	label.modulate = Color(0.92, 0.9, 0.84)
	label.position = back + Vector3(0, 3.15, 0.22)
	label.visibility_range_end = 150.0
	add_child(label)

func can_use_station(id: String) -> bool:
	if not stations.has(id) or not is_instance_valid(player): return false
	if Game.simulation_paused or Game.mode != Game.MODE_FOOT or player.current_vehicle != null or player.busy: return false
	if Game.health <= 0.0 or not player.alive or Time.get_ticks_msec() < _next_use_ms: return false
	var station: Node3D = stations[id]
	if player.global_position.distance_to(station.global_position) > RANGE: return false
	return player._interaction_visible(station)

func use_station(id: String, actor: Node) -> bool:
	if actor != player or not can_use_station(id): return false
	var destination := roof_position() if id == "ground" else ground_position()
	if not destination_clear(destination):
		Events.toast("Lift arrival is obstructed. Please try again when the doorway is clear.", "warn")
		return false
	_next_use_ms = Time.get_ticks_msec() + 900
	# Do not respawn: respawn_at changes life/vehicle/mode and announces a
	# checkpoint. This transit changes position and motion only.
	player.global_position = destination
	player.velocity = Vector3.ZERO
	player._speed = 0.0
	player._prev_speed = 0.0
	player._fall_speed = 0.0
	player._airborne_time = 0.0
	player._jump_windup = -1.0
	player._cam_ready = false
	player.yaw = PI
	player.rotation.y = PI
	player._heading = PI
	Game.player_position = destination
	Game.player_rotation = PI
	# Ground is always a recoverable death/vehicle checkpoint with an escape route.
	Game.mark_safe_position(ground_position(), PI)
	Game.save_game()
	Events.toast("SkyPark observation terrace · public lift returns to Event Plaza." if id == "ground" else "Shoppes / Event Plaza · public lift arrival.", "info")
	return true

func destination_clear(at: Vector3) -> bool:
	if not is_inside_tree() or not is_instance_valid(player): return false
	var space := get_world_3d().direct_space_state
	for offset: Vector3 in [Vector3.ZERO, Vector3(0.45, 0, 0), Vector3(-0.45, 0, 0), Vector3(0, 0, 0.45), Vector3(0, 0, -0.45)]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + offset + Vector3.UP, at + offset - Vector3.UP * 0.5, 1))
		if hit.is_empty() or absf(hit.position.y - (at.y - 0.1)) > 0.12: return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 1.85
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 1.0, 0))
	query.collision_mask = Player.COLLIDE_MASK | 2
	query.exclude = [player.get_rid()]
	return space.intersect_shape(query, 1).is_empty()

func _pad_marking(kit: Kit) -> void:
	# Paint only; the authored deck remains the landing surface. The 5 m
	# marking is deliberately smaller than the 6 m tested aircraft clearance.
	var center := pad_position() + Vector3.UP * 0.015
	var paint := Looks.get_mat("steel_white")
	for i in 48:
		var a := TAU * i / 48.0
		var b := TAU * (i + 1) / 48.0
		kit.beam(paint, center + Vector3(cos(a), 0, sin(a)) * PAD_RADIUS, center + Vector3(cos(b), 0, sin(b)) * PAD_RADIUS, 0.16, 0.015)
	for dx: float in [-1.0, 1.0]:
		kit.box(paint, center + Vector3(dx, 0, 0), Vector3(0.3, 0.015, 3.0))
	kit.box(paint, center, Vector3(2.0, 0.015, 0.3))
