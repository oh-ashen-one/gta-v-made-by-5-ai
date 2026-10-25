extends Node3D
## Optional city errand; independent of Harbour Relay and its checkpoints.
## Physical E interactions only. Vehicles are transport, never delivery buttons.
signal changed

const Station = preload("res://src/systems/downtown_activities/station.gd")
const Card = preload("res://src/systems/downtown_activities/status_card.gd")
enum Stage { IDLE, OUTBOUND, RECEIPT }
const INTERACTION_RADIUS := 4.5
var stage := Stage.IDLE
var completed_runs := 0
var player: Player
var stations: Dictionary = {}
var _card: CanvasLayer

func setup(_world: WorldBuilder, p: Player) -> void:
	if not stations.is_empty(): return
	player = p
	add_to_group("downtown_activity")
	# Anchor-relative offsets stay on existing promenade paving, away from
	# traffic lanes, helicopter pads, trees and the Shoppes stair risers.
	var heritage := Vector3(-144.0, DowntownPlan.QUAY_TOP, DowntownPlan.LEGACY["promenade_z"])
	var bayfront := DowntownPlan.anchor("mbs_event_plaza") + Vector3(0.0, 0.06, 10.0)
	_add_station("heritage", "HERITAGE WATERFRONT", heritage)
	_add_station("bayfront", "MBS EVENT PLAZA", bayfront)
	_card = Card.new()
	add_child(_card)
	_card.setup(self)
	_refresh()

func _add_station(id: String, title: String, at: Vector3) -> void:
	var station := Station.new()
	station.name = "Courier_" + id
	station.activity = self
	station.station_id = id
	station.title = title
	station.position = at
	stations[id] = station
	add_child(station)

func is_active() -> bool:
	return stage != Stage.IDLE

func target_id() -> String:
	return "bayfront" if stage == Stage.OUTBOUND else "heritage"

func objective_position() -> Vector3:
	if stations.is_empty(): return Vector3.ZERO
	return (stations[target_id()] as Node3D).global_position

func current_objective() -> String:
	match stage:
		Stage.OUTBOUND: return "Deliver the parcel at MBS Event Plaza."
		Stage.RECEIPT: return "Return the receipt to Heritage Waterfront."
	return "Collect a parcel at Heritage Waterfront."

func station_prompt(id: String) -> String:
	if id == "heritage":
		match stage:
			Stage.OUTBOUND: return "[E] Return parcel and cancel courier run"
			Stage.RECEIPT: return "[E] Hand over receipt · finish courier run"
		return "[E] Start Bayfront Courier · MBS Event Plaza"
	return "[E] Deliver parcel · collect return receipt"

func can_use_station(id: String) -> bool:
	if not stations.has(id) or not is_instance_valid(player): return false
	if Game.simulation_paused or Game.mode != Game.MODE_FOOT or player.current_vehicle != null or player.busy: return false
	if Game.health <= 0.0: return false
	if id == "bayfront" and stage != Stage.OUTBOUND: return false
	var station: Node3D = stations[id]
	if player.global_position.distance_to(station.global_position) > INTERACTION_RADIUS: return false
	# A direct call cannot bypass walls, unlike a proximity-only handover.
	return player._interaction_visible(station)

func use_station(id: String, actor: Node) -> bool:
	if actor != player or not can_use_station(id): return false
	if id == "heritage":
		match stage:
			Stage.IDLE:
				stage = Stage.OUTBOUND
				Events.toast("Parcel collected. Take any route to MBS Event Plaza; step out and press E to hand it over.", "good")
			Stage.OUTBOUND:
				stage = Stage.IDLE
				Events.toast("Parcel returned. Courier run cancelled; you can start again here.", "info")
			Stage.RECEIPT:
				completed_runs += 1
				stage = Stage.IDLE
				Events.toast("Bayfront Courier complete · %d run%s. Another parcel is ready here." % [completed_runs, "" if completed_runs == 1 else "s"], "good")
	else:
		stage = Stage.RECEIPT
		Events.toast("MBS handover complete. Return the signed receipt to Heritage Waterfront.", "good")
	_refresh()
	# Parent integrates this snapshot into Game's existing atomic save.
	Game.save_game()
	return true

func serialize_state() -> Dictionary:
	return {"version": 1, "stage": stage, "completed_runs": completed_runs}

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary: return false
	for key in ["version", "stage", "completed_runs"]:
		var value: Variant = data.get(key)
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT: return false
		if not is_finite(float(value)) or float(value) != floorf(float(value)): return false
	return int(data.version) == 1 and int(data.stage) >= Stage.IDLE and int(data.stage) <= Stage.RECEIPT and int(data.completed_runs) >= 0 and int(data.completed_runs) <= 1000000

func restore_state(data: Dictionary) -> bool:
	if not valid_state(data): return false
	stage = int(data.stage)
	completed_runs = int(data.completed_runs)
	_refresh()
	return true

func reset_state() -> void:
	stage = Stage.IDLE
	completed_runs = 0
	_refresh()

func _refresh() -> void:
	for station in stations.values(): station.refresh()
	changed.emit()
