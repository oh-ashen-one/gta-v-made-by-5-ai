extends Node
## Authoritative global state for the session (END_GOAL SYSTEM-01).
## Owns: control mode, health, wanted level, ammo, mission stage, save/load.
## Nodes report into this object; they do not keep competing copies of the truth.

const MODE_FOOT := 0
const MODE_CAR := 1
const MODE_HELI := 2

const MAX_HEALTH := 100.0
const SAVE_PATH := "user://orchard_reach_save.json"
const SAVE_VERSION := 1

var mode: int = MODE_FOOT
var health: float = MAX_HEALTH
var wanted_level: int = 0
var wanted_heat: float = 0.0
var mission_stage: int = 0
var checkpoint_index: int = 0
var seed_value: int = 20261021
var elapsed_seconds: float = 0.0
var player_position: Vector3 = Vector3.ZERO
var player_rotation: float = 0.0
var carried_weapon: String = "pistol"
var ammo := {
	"pistol": {"mag": 12, "reserve": 96},
	"smg": {"mag": 30, "reserve": 180},
}
var last_safe_position: Vector3 = Vector3.ZERO
var last_safe_rotation: float = 0.0
var simulation_paused: bool = false
var in_mission: bool = false
var search_timer: float = 0.0          # seconds of active search left (LAW-04)
var player_seen: bool = false          # police currently have eyes on the player
var last_seen_position: Vector3 = Vector3.ZERO
var settings := {
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"reduced_shake": false,
	"hud_visible": true,
}

func _ready() -> void:
	_setup_input_map()
	Events.mode_changed.connect(_on_mode_changed)
	Events.health_changed.connect(_on_health_changed)
	Events.wanted_changed.connect(_on_wanted_changed)

func _process(delta: float) -> void:
	if not simulation_paused:
		elapsed_seconds += delta
	# Pursuit decay only happens while nobody is looking (LAW-04: fair escape).
	if wanted_level > 0 and not player_seen:
		search_timer = maxf(0.0, search_timer - delta)
		decay_heat(delta * 1.4)
		if wanted_level == 0:
			Events.notify.emit("You lost the search.", "good")

# ---------------------------------------------------------------- input setup
func _setup_input_map() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("jump", [KEY_SPACE])
	_add_action("fire", [MOUSE_BUTTON_LEFT])
	_add_action("aim", [MOUSE_BUTTON_RIGHT])
	_add_action("reload", [KEY_R])
	_add_action("interact", [KEY_E])
	_add_action("weapon_next", [KEY_Q])
	_add_action("pause", [KEY_ESCAPE])
	_add_action("camera_swap", [KEY_C])
	_add_action("debug_panel", [KEY_F1])

func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

# ------------------------------------------------------------------- helpers
func set_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	Events.mode_changed.emit(mode)

func health_ratio() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)

func damage_player(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	Events.health_changed.emit(health, MAX_HEALTH)
	if health <= 0.0:
		Events.notify.emit("You are down. Respawning at the last checkpoint.", "bad")
		respawn()

func respawn() -> void:
	health = MAX_HEALTH
	Events.health_changed.emit(health, MAX_HEALTH)
	wanted_heat = 0.0
	set_wanted(0)
	var body := get_tree().get_first_node_in_group("player")
	if body and body.has_method("respawn_at"):
		body.respawn_at(last_safe_position, last_safe_rotation)

func set_wanted(level: int) -> void:
	if wanted_level == level:
		return
	wanted_level = clampi(level, 0, 3)
	Events.wanted_changed.emit(wanted_level)

func add_heat(amount: float) -> void:
	wanted_heat = maxf(0.0, wanted_heat + amount)
	# Three escalation tiers, thresholds calibrated in the wave-1 contract.
	var target := 0
	if wanted_heat >= 100.0:
		target = 3
	elif wanted_heat >= 45.0:
		target = 2
	elif wanted_heat >= 12.0:
		target = 1
	set_wanted(target)

func decay_heat(delta: float) -> void:
	if wanted_level == 0:
		wanted_heat = maxf(0.0, wanted_heat - delta * 4.0)
		return
	if wanted_heat > 0.0:
		wanted_heat = maxf(0.0, wanted_heat - delta * 3.0)
		var still := 0
		if wanted_heat >= 100.0:
			still = 3
		elif wanted_heat >= 45.0:
			still = 2
		elif wanted_heat >= 12.0:
			still = 1
		if still < wanted_level:
			set_wanted(still)

func current_mag() -> int:
	return int(ammo[carried_weapon]["mag"])

func current_reserve() -> int:
	return int(ammo[carried_weapon]["reserve"])

func consume_ammo() -> bool:
	var slot: Dictionary = ammo[carried_weapon]
	if int(slot["mag"]) <= 0:
		return false
	slot["mag"] = int(slot["mag"]) - 1
	Events.ammo_changed.emit(int(slot["mag"]), int(slot["reserve"]))
	return true

func reload_ammo() -> void:
	var slot: Dictionary = ammo[carried_weapon]
	var need: int = _mag_size(carried_weapon) - int(slot["mag"])
	if need <= 0 or int(slot["reserve"]) <= 0:
		return
	var moved: int = mini(need, int(slot["reserve"]))
	slot["mag"] = int(slot["mag"]) + moved
	slot["reserve"] = int(slot["reserve"]) - moved
	Events.ammo_changed.emit(int(slot["mag"]), int(slot["reserve"]))

func _mag_size(weapon_id: String) -> int:
	return 12 if weapon_id == "pistol" else 30

func switch_weapon(weapon_id: String) -> void:
	if weapon_id == carried_weapon:
		return
	carried_weapon = weapon_id
	Events.ammo_changed.emit(current_mag(), current_reserve())

func mark_safe_position(pos: Vector3, rot: float) -> void:
	last_safe_position = pos
	last_safe_rotation = rot

# ------------------------------------------------------------------ save/load
func save_game() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"health": health,
		"wanted_level": wanted_level,
		"mission_stage": mission_stage,
		"checkpoint_index": checkpoint_index,
		"seed": seed_value,
		"elapsed": elapsed_seconds,
		"player_position": [player_position.x, player_position.y, player_position.z],
		"player_rotation": player_rotation,
		"ammo": ammo,
		"carried_weapon": carried_weapon,
		"wanted_heat": wanted_heat,
		"last_safe_position": [last_safe_position.x, last_safe_position.y, last_safe_position.z],
		"last_safe_rotation": last_safe_rotation,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	if int(parsed.get("version", 0)) != SAVE_VERSION:
		return false
	health = float(parsed.get("health", MAX_HEALTH))
	wanted_level = int(parsed.get("wanted_level", 0))
	mission_stage = int(parsed.get("mission_stage", 0))
	checkpoint_index = int(parsed.get("checkpoint_index", 0))
	seed_value = int(parsed.get("seed", seed_value))
	elapsed_seconds = float(parsed.get("elapsed", 0.0))
	var p: Array = parsed.get("player_position", [0, 0, 0])
	player_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	player_rotation = float(parsed.get("player_rotation", 0.0))
	carried_weapon = String(parsed.get("carried_weapon", "pistol"))
	wanted_heat = float(parsed.get("wanted_heat", 0.0))
	var safe: Array = parsed.get("last_safe_position", [0, 0, 0])
	last_safe_position = Vector3(float(safe[0]), float(safe[1]), float(safe[2]))
	last_safe_rotation = float(parsed.get("last_safe_rotation", 0.0))
	var saved_ammo = parsed.get("ammo", {})
	if typeof(saved_ammo) == TYPE_DICTIONARY:
		for key in saved_ammo.keys():
			if ammo.has(key) and typeof(saved_ammo[key]) == TYPE_DICTIONARY:
				ammo[key]["mag"] = int(saved_ammo[key].get("mag", ammo[key]["mag"]))
				ammo[key]["reserve"] = int(saved_ammo[key].get("reserve", ammo[key]["reserve"]))
	Events.health_changed.emit(health, MAX_HEALTH)
	Events.wanted_changed.emit(wanted_level)
	Events.ammo_changed.emit(current_mag(), current_reserve())
	# Apply the restored state to the world: a save that stores values nobody
	# reads is not a save (B7).
	var body := get_tree().get_first_node_in_group("player")
	if body and body.has_method("respawn_at"):
		body.respawn_at(player_position, player_rotation)
	mark_safe_position(player_position, player_rotation)
	var mission := get_tree().get_first_node_in_group("mission")
	if mission and mission.has_method("restore_stage"):
		mission.restore_stage(mission_stage)
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# --------------------------------------------------------------------- slots
func _on_mode_changed(_m: int) -> void:
	pass

func _on_health_changed(v: float, m: float) -> void:
	health = v

func _on_wanted_changed(l: int) -> void:
	wanted_level = l
