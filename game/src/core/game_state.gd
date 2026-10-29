extends Node
## Authoritative global state for the session (END_GOAL SYSTEM-01).
## Owns: control mode, health, wanted level, ammo, mission stage, save/load.
## Nodes report into this object; they do not keep competing copies of the truth.

const MODE_FOOT := 0
const MODE_CAR := 1
const MODE_HELI := 2

const MAX_HEALTH := 100.0
const REGEN_DELAY := 5.0   # seconds out of fire before health comes back
const REGEN_RATE := 9.0     # health per second while regenerating
const SAVE_PATH := "user://orchard_reach_save.json"
## QA runs without --save-path= or a --qa-session <abs dir> save here, never to SAVE_PATH.
const QA_SAVE_PATH := "user://qa_session_save.json"
const SAVE_VERSION := 1
var _save_path: String = SAVE_PATH
# Source geography has its own versioned slot and checked restore service.
# Keeping this separate prevents legacy local XYZ from becoming map positions.
var _source_session: Object
var _source_recovery_hold := false

func source_controls_held() -> bool:
	return health <= 0.0 or _source_recovery_hold

func source_session_owns(service: Object) -> bool:
	return service != null and service == _bound_source_session()

func set_source_recovery_hold(service: Object, held: bool) -> bool:
	if service == null or service != _bound_source_session(): return false
	_source_recovery_hold = held
	return true

func save_slot_path() -> String:
	return _save_path

func _source_player() -> Player:
	var body := get_tree().get_first_node_in_group("player") as Player
	return body if is_instance_valid(body) and body.uses_source_world else null

func install_source_session(service: Object) -> bool:
	var body := _source_player()
	if body == null or not is_instance_valid(service): return false
	for method in ["is_bound_to", "metadata", "save", "load", "has_save", "capture_anchor", "request_recovery", "retry_pending"]:
		if not service.has_method(method): return false
	if not service.is_bound_to(body.source_world_runtime, body): return false
	var info: Variant = service.metadata()
	if not info is Dictionary or not info.get("slot_path") is String or info.slot_path.is_empty(): return false
	if is_instance_valid(_source_session): return _source_session == service
	_source_session = service
	_source_recovery_hold = false
	return true

func uninstall_source_session(expected: Object) -> bool:
	if _source_session != expected: return false
	if is_instance_valid(expected):
		var info: Variant = expected.metadata()
		if info is Dictionary and info.get("transaction_busy",false): return false
	_source_session = null
	_source_recovery_hold = false
	return true

func _bound_source_session() -> Object:
	var body := _source_player()
	if body == null or not is_instance_valid(_source_session) or not _source_session.is_bound_to(body.source_world_runtime, body): return null
	return _source_session

func _source_slot_request(path: String, service: Object) -> bool:
	if path.is_empty(): return true
	var info: Variant = service.metadata()
	if not info is Dictionary or not info.get("slot_path") is String or info.slot_path.is_empty(): return false
	return ProjectSettings.globalize_path(path).simplify_path() == ProjectSettings.globalize_path(info.slot_path).simplify_path()

func recover_disabled_aircraft() -> bool:
	if _source_player() != null:
		var service := _bound_source_session()
		if service == null:
			Events.notify.emit("Recovery is waiting for the source-world checkpoint service.", "warn")
			return false
		return service.request_recovery("disabled_aircraft")
	var body := get_tree().get_first_node_in_group("player")
	if body and body.has_method("respawn_at"):
		body.respawn_at(last_safe_position, last_safe_rotation)
		return true
	return false


var mode: int = MODE_FOOT
var health: float = MAX_HEALTH
var death_count := 0
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
var _since_damage: float = 0.0         # seconds since the last hit taken
var player_seen: bool = false          # police currently have eyes on the player
var last_seen_position: Vector3 = Vector3.ZERO
var settings := {
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"reduced_shake": false,
	"hud_visible": true,
}

func _ready() -> void:
	seed(seed_value)
	var args := OS.get_cmdline_user_args()
	for startup_arg: String in args:
		if startup_arg.begins_with("--qa-render-health=") and DisplayServer.get_name()!="headless":
			var health=preload("res://src/systems/render_startup_health.gd").new()
			health.nonce=startup_arg.trim_prefix("--qa-render-health=")
			add_child(health)
			break
	var qa_session := "--test" in args or "--capture" in args or "--qa-session" in args
	for arg in args:
		if arg.begins_with("--save-probe="): qa_session = true
	if qa_session:
		# Wave A integration (harness hazard found by critics street-life-A2 and
		# lighting-A4): a QA run must never write the player's real save slot.
		# Without an explicit --save-path=, save next to the --qa-session dir
		# (or to a separate QA file in user://).
		_save_path = QA_SAVE_PATH
		var qa_dir_index := args.find("--qa-session")
		if qa_dir_index >= 0 and qa_dir_index + 1 < args.size():
			var qa_dir: String = args[qa_dir_index + 1]
			if qa_dir.is_absolute_path() and not qa_dir.begins_with("--"):
				_save_path = qa_dir.path_join("orchard_reach_save.json")
		for arg in args:
			if arg.begins_with("--save-path=") and not arg.trim_prefix("--save-path=").is_empty():
				_save_path = arg.trim_prefix("--save-path=")
	_setup_input_map()
	Events.mode_changed.connect(_on_mode_changed)
	Events.health_changed.connect(_on_health_changed)
	Events.wanted_changed.connect(_on_wanted_changed)
	Events.shot_fired.connect(func(_o, _d, _w) -> void: _last_shot_at = elapsed_seconds)

var _lost_search_msg_at := -100.0  # integ-P: no stacked 'lost the search' toasts
var _last_shot_at := -100.0  # integ-P: never announce a lost search mid-firefight

func _process(delta: float) -> void:
	if simulation_paused:
		return
	elapsed_seconds += delta
	_regenerate(delta)
	# Pursuit decay only happens while nobody is looking (LAW-04: fair escape).
	if wanted_level > 0 and not player_seen:
		search_timer = maxf(0.0, search_timer - delta)
		decay_heat(delta * 1.4)
		if wanted_level == 0 and elapsed_seconds - _lost_search_msg_at > 12.0 and elapsed_seconds - _last_shot_at > 6.0:
			_lost_search_msg_at = elapsed_seconds
			Events.notify.emit("You lost the search.", "good")

## Health comes back slowly once the player has been out of fire for a few
## seconds, so a firefight is survivable and a chase can be broken (COMBAT-04).
## Without it, one close encounter with three guards was lethal.
func _regenerate(delta: float) -> void:
	if health <= 0.0 or health >= MAX_HEALTH:
		_since_damage = 0.0
		return
	_since_damage += delta
	if _since_damage < REGEN_DELAY:
		return
	var before := health
	health = minf(MAX_HEALTH, health + REGEN_RATE * delta)
	if not is_equal_approx(before, health):
		Events.health_changed.emit(health, MAX_HEALTH)

# ---------------------------------------------------------------- input setup
func _setup_input_map() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("jump", [KEY_SPACE])
	_add_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_add_mouse_action("aim", MOUSE_BUTTON_RIGHT)
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

func _add_mouse_action(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

# ------------------------------------------------------------------- helpers
func set_mode(new_mode: int) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	Events.mode_changed.emit(mode)

func health_ratio() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)

func damage_player(amount: float) -> void:
	# A deliberate source load/recovery holds the player in place. Incoming
	# damage must pause with controls, rather than kill an immobile actor and
	# race a pending load against a second death transaction.
	if _source_recovery_hold and _source_player() != null: return
	if health <= 0.0:
		return
	_since_damage = 0.0
	health = maxf(0.0, health - amount)
	Events.health_changed.emit(health, MAX_HEALTH)
	if health <= 0.0:
		Events.notify.emit("You are down. Respawning at the last checkpoint.", "bad")
		respawn()

func respawn() -> void:
	if _source_player() != null:
		var service := _bound_source_session()
		if service != null:
			service.request_recovery("death")
		else:
			Events.notify.emit("Recovery is waiting for the source-world checkpoint service.", "warn")
		return
	death_count += 1
	health = MAX_HEALTH
	Events.health_changed.emit(health, MAX_HEALTH)
	wanted_heat = 0.0
	set_wanted(0)
	var body := get_tree().get_first_node_in_group("player")
	if body and body.has_method("respawn_at"):
		body.respawn_at(last_safe_position, last_safe_rotation)
	var mission := get_tree().get_first_node_in_group("mission")
	if mission and mission.has_method("on_player_respawn"):
		mission.on_player_respawn()

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
	if _source_player() != null:
		var service := _bound_source_session()
		if service != null: service.capture_anchor()
		return
	last_safe_position = pos
	last_safe_rotation = rot

# ------------------------------------------------------------------ save/load
func save_game(path: String = "") -> bool:
	if _source_player() != null:
		var service := _bound_source_session()
		return service != null and _source_slot_request(path, service) and service.save()
	if path.is_empty(): path = _save_path
	var data := {
		"version": SAVE_VERSION,
		"mode": mode,
		"settings": settings.duplicate(true),
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
	var activity := get_tree().get_first_node_in_group("downtown_activity")
	if activity and activity.has_method("serialize_state"):
		data["downtown_activity"] = activity.serialize_state()
	if not _validate_save_data(data):
		return false
	var destination := ProjectSettings.globalize_path(path)
	var directory := destination.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	# Same-directory rename publishes a complete checkpoint. Until then the
	# previous save remains intact; no reader can observe a truncated JSON.
	var temporary := destination + ".tmp-%d" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	var payload := JSON.stringify(data, "\t")
	file.store_string(payload)
	file.flush()
	var written := file.get_error() == OK and file.get_length() == payload.to_utf8_buffer().size()
	file.close()
	if not written:
		DirAccess.remove_absolute(temporary)
		return false
	var replaced := DirAccess.rename_absolute(temporary, destination) == OK
	if not replaced:
		DirAccess.remove_absolute(temporary)
	return replaced

func load_game(path: String = "") -> bool:
	if _source_player() != null:
		var service := _bound_source_session()
		return service != null and _source_slot_request(path, service) and service.load()
	if path.is_empty(): path = _save_path
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	if f.get_length() > 1048576:
		f.close()
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	# Validate the complete input before changing any global or scene state.
	# A well-formed JSON document is not necessarily a valid save.
	if not _validate_save_data(parsed):
		return false
	health = float(parsed.get("health", MAX_HEALTH))
	_since_damage = 0.0
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
	if data_has_settings(parsed):
		var restored_settings: Dictionary = parsed["settings"]
		for key in ["mouse_sensitivity", "invert_y", "reduced_shake", "hud_visible"]:
			settings[key] = restored_settings[key]
	Events.health_changed.emit(health, MAX_HEALTH)
	Events.wanted_changed.emit(wanted_level)
	Events.ammo_changed.emit(current_mag(), current_reserve())
	Events.settings_changed.emit(settings.duplicate(true))
	# Apply the restored state to the world: a save that stores values nobody
	# reads is not a save (B7).
	var body := get_tree().get_first_node_in_group("player")
	if body and body.has_method("respawn_at"):
		if int(parsed.get("mode", MODE_FOOT)) != MODE_FOOT:
			player_position = last_safe_position
			player_rotation = last_safe_rotation
		body.respawn_at(player_position, player_rotation)
	var mission := get_tree().get_first_node_in_group("mission")
	if mission and mission.has_method("restore_stage"):
		mission.restore_stage(mission_stage)
	var activity := get_tree().get_first_node_in_group("downtown_activity")
	if activity:
		if parsed.has("downtown_activity"):
			activity.restore_state(parsed["downtown_activity"])
		else:
			activity.reset_state()
	Events.state_restored.emit()
	return true

func _number_in_range(value: Variant, low: float, high: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number >= low and number <= high

func _integer_in_range(value: Variant, low: int, high: int) -> bool:
	return _number_in_range(value, low, high) and float(value) == floorf(float(value))

func _valid_saved_vector(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for coordinate in value:
		if not _number_in_range(coordinate, -1000000.0, 1000000.0):
			return false
	return true

func _validate_save_data(data: Dictionary) -> bool:
	# Optional for legacy saves. Validate before touching player/story state;
	# an invalid side activity must not partially load the rest of a save.
	if data.has("downtown_activity"):
		var activity: Variant = data["downtown_activity"]
		if typeof(activity) != TYPE_DICTIONARY: return false
		if not _integer_in_range(activity.get("version"), 1, 1): return false
		if not _integer_in_range(activity.get("stage"), 0, 2): return false
		if not _integer_in_range(activity.get("completed_runs"), 0, 1000000): return false
	if not _integer_in_range(data.get("version"), SAVE_VERSION, SAVE_VERSION): return false
	if not _number_in_range(data.get("health"), 0.01, MAX_HEALTH): return false
	if not _integer_in_range(data.get("wanted_level"), 0, 3): return false
	if not _number_in_range(data.get("wanted_heat"), 0.0, 1000000000.0): return false
	if not _integer_in_range(data.get("mission_stage"), 0, 8): return false
	if not _integer_in_range(data.get("checkpoint_index"), 0, 3): return false
	if not _integer_in_range(data.get("seed"), 0, 2147483647): return false
	if not _number_in_range(data.get("elapsed"), 0.0, 1000000000.0): return false
	if not _valid_saved_vector(data.get("player_position")): return false
	if not _valid_saved_vector(data.get("last_safe_position")): return false
	if not _number_in_range(data.get("player_rotation"), -1000000.0, 1000000.0): return false
	if not _number_in_range(data.get("last_safe_rotation"), -1000000.0, 1000000.0): return false
	if not _integer_in_range(data.get("mode", MODE_FOOT), MODE_FOOT, MODE_HELI): return false
	if typeof(data.get("carried_weapon")) != TYPE_STRING or not ammo.has(data["carried_weapon"]): return false
	if typeof(data.get("ammo")) != TYPE_DICTIONARY: return false
	var saved_ammo: Dictionary = data["ammo"]
	for weapon_id in ["pistol", "smg"]:
		if typeof(saved_ammo.get(weapon_id)) != TYPE_DICTIONARY: return false
		var slot: Dictionary = saved_ammo[weapon_id]
		if not _integer_in_range(slot.get("mag"), 0, _mag_size(weapon_id)): return false
		if not _integer_in_range(slot.get("reserve"), 0, 1000000): return false
	var heat := float(data["wanted_heat"])
	var heat_level := 3 if heat >= 100.0 else (2 if heat >= 45.0 else (1 if heat >= 12.0 else 0))
	if int(data["wanted_level"]) != heat_level: return false
	var saved_stage := int(data["mission_stage"])
	var expected_checkpoint := 0 if saved_stage == 0 else (1 if saved_stage <= 3 else (2 if saved_stage <= 5 else 3))
	if int(data["checkpoint_index"]) != expected_checkpoint: return false
	if data.has("settings"):
		if not data_has_settings(data): return false
		var saved_settings: Dictionary = data["settings"]
		if not _number_in_range(saved_settings.get("mouse_sensitivity"), 0.2, 3.0): return false
		for key in ["invert_y", "reduced_shake", "hud_visible"]:
			if typeof(saved_settings.get(key)) != TYPE_BOOL: return false
	return true

func data_has_settings(data: Dictionary) -> bool:
	return data.has("settings") and typeof(data["settings"]) == TYPE_DICTIONARY

func has_save() -> bool:
	if _source_player() != null:
		var service := _bound_source_session()
		return service != null and service.has_save()
	return FileAccess.file_exists(_save_path)

# --------------------------------------------------------------------- slots
func _on_mode_changed(_m: int) -> void:
	pass

func _on_health_changed(v: float, m: float) -> void:
	health = v

func _on_wanted_changed(l: int) -> void:
	wanted_level = l
