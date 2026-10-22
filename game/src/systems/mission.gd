class_name Mission
extends Node
## "Harbour Relay" — the authored mission that proves the systems integrate
## (MISSION-01). Objectives use real prerequisites and real game systems; no
## teleport, no private fake duplicates of gameplay systems.

enum Stage { TO_PACKAGE, PACKAGE, TO_CAR, TO_AIRFIELD, TO_HELI, FLY, LAND, DELIVER, DONE }

var stage: int = Stage.TO_PACKAGE
var world: WorldBuilder
var player: Player
var traffic: TrafficManager
var package_node: Node3D
var delivery_node: Node3D
var package_taken := false
var car_taken := false
var landed := false
var car_driven_distance := 0.0
var flight_distance := 0.0
var _last_actor_position := Vector3.ZERO
var _last_actor: Node3D = null
var _hostiles: Array[NPC] = []
var _objective := ""

func setup(w: WorldBuilder, p: Player, t: TrafficManager) -> void:
	add_to_group("mission")
	world = w
	player = p
	traffic = t
	_spawn_package()
	_spawn_delivery()
	_spawn_hostiles()
	_set_stage(Stage.TO_PACKAGE)

func _spawn_package() -> void:
	package_node = Node3D.new()
	package_node.name = "MissionPackage"
	package_node.position = world.locations["package"]
	package_node.set_script(load("res://src/systems/package_pickup.gd"))
	add_child(package_node)
	package_node.set("mission", self)

func _spawn_delivery() -> void:
	delivery_node = Node3D.new()
	delivery_node.name = "DeliveryPoint"
	delivery_node.position = world.locations["delivery"]
	delivery_node.set_script(load("res://src/systems/delivery_point.gd"))
	add_child(delivery_node)
	delivery_node.set("mission", self)

func _spawn_hostiles() -> void:
	var base: Vector3 = world.locations["package"]
	# the guards hold the stall line: they stand in front of the counters but
	# never in the centre aisle, so the player can walk in and take the package
	var posts := [Vector3(-16.0, 0.0, -9.0), Vector3(16.0, 0.0, -9.0), Vector3(6.0, 0.0, -12.0)]
	for i in posts.size():
		var h := NPC.new()
		h.is_hostile = true
		h.health = 70.0
		add_child(h)
		h.global_position = base + posts[i]
		h.state = NPC.State.WALK
		_hostiles.append(h)

## Objective progression runs on the physics tick, not the render tick. It was
## in _process, which meant a stage change could be delayed by a slow frame; the
## wave-3 district is heavy enough that this became observable, and gameplay
## state should never depend on render rate.
func _physics_process(_delta: float) -> void:
	if Game.simulation_paused:
		return
	var actor: Node3D = _actor()
	if actor == null:
		return
	# Only continuous movement of the controlled vehicle counts. A respawn or
	# a fixture teleport cannot accidentally fulfil a driving/flight leg.
	var travelled := 0.0
	if actor == _last_actor:
		var step := actor.global_position.distance_to(_last_actor_position)
		if step < 12.0:
			travelled = step
	_last_actor = actor
	_last_actor_position = actor.global_position
	match stage:
		Stage.TO_PACKAGE:
			pass
		Stage.TO_CAR:
			if Game.mode == Game.MODE_CAR and not car_taken:
				car_taken = true
				Game.add_heat(14.0)
				_set_stage(Stage.TO_AIRFIELD)
		Stage.TO_AIRFIELD:
			if Game.mode == Game.MODE_CAR and actor is Car:
				car_driven_distance += travelled
				if car_driven_distance >= 80.0 and actor.global_position.distance_to(world.locations["helipad_primary"]) < 60.0:
					Game.mark_safe_position(world.locations["helipad_primary"] + Vector3(3.6, 0.6, 0.0), 0.0)
					Game.checkpoint_index = 2
					Events.checkpoint_reached.emit(2)
					_set_stage(Stage.TO_HELI)
		Stage.TO_HELI:
			if Game.mode == Game.MODE_HELI:
				flight_distance = 0.0
				_set_stage(Stage.FLY)
		Stage.FLY:
			if Game.mode == Game.MODE_HELI:
				flight_distance += travelled
				var heli := player.current_vehicle
				if heli and flight_distance >= 80.0 and heli.is_landed() and heli.global_position.distance_to(world.locations["helipad_secondary"]) < 30.0:
					landed = true
					Game.checkpoint_index = 3
					Game.mark_safe_position(world.locations["helipad_secondary"] + Vector3(3.6, 0.6, 0.0), 0.0)
					Events.checkpoint_reached.emit(3)
					_set_stage(Stage.LAND)
		Stage.LAND:
			if Game.mode == Game.MODE_FOOT and actor.global_position.distance_to(world.locations["helipad_secondary"]) < 40.0:
				_set_stage(Stage.DELIVER)
		Stage.DELIVER:
			pass # Delivery is an explicit on-foot interaction, never proximity alone.

func _set_stage(new_stage: int, side_effects: bool = true) -> void:
	stage = new_stage
	Game.mission_stage = stage
	Game.in_mission = stage != Stage.DONE
	match stage:
		Stage.TO_PACKAGE:
			_objective = "Harbour Relay — collect the package at the hawker centre."
			_mark_objective(world.locations["package"])
		Stage.PACKAGE:
			_objective = "Package secured. Find a car near the market."
			_mark_objective(world.locations["marked_car"])
		Stage.TO_CAR:
			_objective = "Take the marked car, or another usable car. Police will notice."
			_mark_objective(_nearest_usable_car_position())
		Stage.TO_AIRFIELD:
			_objective = "Drive to the aviation compound, north-east of the district."
			_mark_objective(world.locations["helipad_primary"])
		Stage.TO_HELI:
			_objective = "Board the helicopter on the pad."
			_mark_objective(world.locations["helipad_primary"])
		Stage.FLY:
			_objective = "Fly to the waterfront landing pad and set down."
			_mark_objective(world.locations["helipad_secondary"])
		Stage.LAND:
			_objective = "Exit the helicopter and continue on foot."
			_mark_objective(world.locations["helipad_secondary"])
		Stage.DELIVER:
			_objective = "Deliver the package at the waterfront drop point."
			_mark_objective(world.locations["delivery"])
		Stage.DONE:
			_objective = "Harbour Relay complete. Free roam continues."
			_mark_objective(Vector3.ZERO)
			if side_effects:
				Events.mission_finished.emit(true)
				Game.save_game()
	Events.objective_changed.emit(_objective)
	Events.mission_stage_changed.emit(stage)

func _mark_objective(position: Vector3) -> void:
	# Persist before emitting so HUD creation after Mission.setup still sees
	# the initial package marker rather than a lost startup signal at (0,0,0).
	set_meta("marker", position)
	Events.objective_marker_changed.emit(position)

func _nearest_usable_car_position() -> Vector3:
	var nearest := INF
	var position: Vector3 = world.locations["marked_car"]
	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		if not vehicle is Car or vehicle.disabled or vehicle.driver_is_player or vehicle.has_ai: continue
		if vehicle.get_meta("courtyard_only", false): continue
		var distance: float = player.global_position.distance_to(vehicle.global_position)
		if distance < nearest:
			nearest = distance
			position = vehicle.global_position
	return position

## Saves restore the matching pickup/flag/objective state. Since vehicles are
## not serialized, a mid-drive/mid-flight save returns to its honest checkpoint.
func restore_stage(stage_index: int) -> void:
	var restored := clampi(stage_index, 0, Stage.DONE)
	if restored == Stage.PACKAGE or restored == Stage.TO_AIRFIELD:
		restored = Stage.TO_CAR
	elif restored == Stage.FLY:
		restored = Stage.TO_HELI
	elif restored == Stage.LAND:
		restored = Stage.DELIVER
	package_taken = restored >= Stage.TO_CAR
	car_taken = restored >= Stage.TO_HELI
	landed = restored >= Stage.DELIVER
	car_driven_distance = 0.0
	flight_distance = 0.0
	_last_actor = null
	if package_node:
		package_node.set("_taken", package_taken)
		package_node.visible = not package_taken
	if restored == Stage.TO_HELI:
		_reset_helicopter()
	_set_stage(restored, false)

## Death never substitutes walking for the car leg. The reached checkpoint
## is retained, while the unfinished transport leg must be played again.
func on_player_respawn() -> void:
	if stage == Stage.DONE:
		return
	if Game.checkpoint_index >= 3:
		restore_stage(Stage.DELIVER)
	elif Game.checkpoint_index >= 2:
		_reset_helicopter()
		restore_stage(Stage.TO_HELI)
	elif Game.checkpoint_index >= 1:
		restore_stage(Stage.TO_CAR)
	else:
		restore_stage(Stage.TO_PACKAGE)

func _reset_helicopter() -> void:
	var heli := get_tree().get_first_node_in_group("helicopters") as Helicopter
	if heli:
		heli.force_exit()
		heli.global_position = world.locations["helipad_primary"] + Vector3(0.0, 0.6, 0.0)
		heli.rotation = Vector3.ZERO
		heli.velocity = Vector3.ZERO
		heli.health = 100.0
		heli.disabled = false

func package_collected() -> void:
	if stage == Stage.TO_PACKAGE:
		package_taken = true
		_set_stage(Stage.PACKAGE)
		_set_stage(Stage.TO_CAR)
		Game.mark_safe_position(player.global_position, player.rotation.y)
		Game.checkpoint_index = 1
		Events.checkpoint_reached.emit(1)
		Events.toast("Checkpoint saved.", "info")

func delivery_completed() -> void:
	if stage == Stage.DELIVER and Game.mode == Game.MODE_FOOT and package_taken and landed:
		if player.global_position.distance_to(delivery_node.global_position) <= Player.PICKUP_RANGE:
			_set_stage(Stage.DONE)

## The body the player controls right now (vehicle when driving or flying).
func _actor() -> Node3D:
	if player and player.current_vehicle != null and is_instance_valid(player.current_vehicle):
		return player.current_vehicle as Node3D
	return player

func current_objective() -> String:
	return _objective

## Clean restart (MISSION-04): actors, pickups and stage state reset.
func restart() -> void:
	if package_node and package_node.has_method("reset"):
		package_node.reset()
	for h in _hostiles:
		if is_instance_valid(h):
			h.queue_free()
	_hostiles.clear()
	_spawn_hostiles()
	player.respawn_at(world.locations["player_start"], deg_to_rad(WorldBuilder.PLAYER_START_YAW_DEG))
	player.pitch = WorldBuilder.PLAYER_START_PITCH
	Game.health = Game.MAX_HEALTH
	Events.health_changed.emit(Game.health, Game.MAX_HEALTH)
	Game.wanted_heat = 0.0
	Game.set_wanted(0)
	Game.checkpoint_index = 0
	Game.mark_safe_position(player.global_position, player.yaw)
	Game.ammo = {"pistol": {"mag": 12, "reserve": 96}, "smg": {"mag": 30, "reserve": 180}}
	player.reset_action_state()
	traffic.wanted_reset()
	_reset_helicopter()
	package_taken = false
	car_taken = false
	landed = false
	car_driven_distance = 0.0
	flight_distance = 0.0
	_last_actor = null
	_set_stage(Stage.TO_PACKAGE)
	Events.notify.emit("Mission restarted.", "info")

func fail(reason: String) -> void:
	Events.toast(reason, "bad")
	Events.mission_finished.emit(false)
