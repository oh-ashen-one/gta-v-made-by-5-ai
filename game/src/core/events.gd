extends Node
## Global signal bus. One source of truth for cross-system events (END_GOAL SYSTEM-01).

signal shot_fired(origin: Vector3, direction: Vector3, weapon_id: String)
signal hit_landed(target: Node, damage: float, point: Vector3, by_player: bool)
signal actor_died(actor: Node, by_player: bool)
signal wanted_changed(level: int)
signal mode_changed(mode: int)
signal objective_changed(text: String)
signal notify(text: String, kind: String)
signal interaction_prompt(text: String)
signal ammo_changed(mag: int, reserve: int)
signal health_changed(value: float, max_value: float)
signal mission_stage_changed(stage: int)
signal objective_marker_changed(position: Vector3)
signal vehicle_entered(vehicle: Node)
signal vehicle_exited(vehicle: Node)
signal checkpoint_reached(index: int)
signal mission_finished(success: bool)
signal settings_changed(settings: Dictionary)
signal state_restored

func toast(text: String, kind: String = "info") -> void:
	notify.emit(text, kind)
