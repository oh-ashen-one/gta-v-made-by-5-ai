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
var _hostiles: Array[NPC] = []
var _objective := ""

func setup(w: WorldBuilder, p: Player, t: TrafficManager) -> void:
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
	for i in 3:
		var h := NPC.new()
		h.is_hostile = true
		h.health = 70.0
		add_child(h)
		var ang := TAU * i / 3.0
		h.global_position = base + Vector3(cos(ang) * 9.0, 0.4, sin(ang) * 9.0)
		h.state = NPC.State.WALK
		_hostiles.append(h)

func _process(_delta: float) -> void:
	if Game.simulation_paused:
		return
	var actor: Node3D = _actor()
	match stage:
		Stage.TO_PACKAGE:
			pass
		Stage.TO_CAR:
			if Game.mode == Game.MODE_CAR and not car_taken:
				car_taken = true
				Game.add_heat(14.0)
				_set_stage(Stage.TO_AIRFIELD)
		Stage.TO_AIRFIELD:
			if actor.global_position.distance_to(world.locations["helipad_primary"]) < 60.0:
				_set_stage(Stage.TO_HELI)
		Stage.TO_HELI:
			if Game.mode == Game.MODE_HELI:
				Game.mark_safe_position(world.locations["helipad_primary"], 0.0)
				Game.checkpoint_index = 2
				Events.checkpoint_reached.emit(2)
				_set_stage(Stage.FLY)
		Stage.FLY:
			if Game.mode == Game.MODE_HELI:
				var heli := player.current_vehicle
				if heli and heli.is_landed() and heli.global_position.distance_to(world.locations["helipad_secondary"]) < 30.0:
					landed = true
					_set_stage(Stage.LAND)
		Stage.LAND:
			if Game.mode == Game.MODE_FOOT and actor.global_position.distance_to(world.locations["helipad_secondary"]) < 40.0:
				_set_stage(Stage.DELIVER)
		Stage.DELIVER:
			if delivery_node and player.global_position.distance_to(delivery_node.global_position) < 3.5:
				_set_stage(Stage.DONE)

func _set_stage(new_stage: int) -> void:
	stage = new_stage
	Game.mission_stage = stage
	Game.in_mission = true
	match stage:
		Stage.TO_PACKAGE:
			_objective = "Harbour Relay — collect the package at the hawker centre."
			Events.objective_marker_changed.emit(world.locations["package"])
		Stage.PACKAGE:
			_objective = "Package secured. Take a car — the marked one is by the market."
			Events.objective_marker_changed.emit(world.locations["marked_car"])
		Stage.TO_CAR:
			_objective = "Take a car. Police will notice a stolen vehicle."
			Events.objective_marker_changed.emit(world.locations["marked_car"])
		Stage.TO_AIRFIELD:
			_objective = "Drive to the aviation compound, north-east of the district."
			Events.objective_marker_changed.emit(world.locations["helipad_primary"])
		Stage.TO_HELI:
			_objective = "Board the helicopter on the pad."
			Events.objective_marker_changed.emit(world.locations["helipad_primary"])
		Stage.FLY:
			_objective = "Fly to the waterfront landing pad and set down."
			Events.objective_marker_changed.emit(world.locations["helipad_secondary"])
		Stage.LAND:
			_objective = "Exit the helicopter and continue on foot."
			Events.objective_marker_changed.emit(world.locations["helipad_secondary"])
		Stage.DELIVER:
			_objective = "Deliver the package at the waterfront drop point."
			Events.objective_marker_changed.emit(world.locations["delivery"])
		Stage.DONE:
			_objective = "Harbour Relay complete. Free roam continues."
			Events.objective_marker_changed.emit(Vector3.ZERO)
			Events.mission_finished.emit(true)
			Game.save_game()
	Events.objective_changed.emit(_objective)
	Events.mission_stage_changed.emit(stage)

## Restore a saved stage without replaying its side effects.
func restore_stage(stage_index: int) -> void:
	stage = clampi(stage_index, 0, Stage.DONE)
	Game.mission_stage = stage
	Events.objective_changed.emit(_objective)
	Events.mission_stage_changed.emit(stage)

func package_collected() -> void:
	if stage == Stage.TO_PACKAGE:
		_set_stage(Stage.PACKAGE)
		_set_stage(Stage.TO_CAR)
		Game.mark_safe_position(player.global_position, player.rotation.y)
		Game.checkpoint_index = 1
		Events.checkpoint_reached.emit(1)
		Events.toast("Checkpoint saved.", "info")

func delivery_completed() -> void:
	if stage == Stage.DELIVER:
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
	package_taken = false
	car_taken = false
	landed = false
	_set_stage(Stage.TO_PACKAGE)
	Events.notify.emit("Mission restarted.", "info")

func fail(reason: String) -> void:
	Events.toast(reason, "bad")
	Events.mission_finished.emit(false)
