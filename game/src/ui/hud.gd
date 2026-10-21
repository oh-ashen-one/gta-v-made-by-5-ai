class_name HUD
extends CanvasLayer
## Original readable HUD (UI-02), navigation display, pause/controls shell
## (UI-01, PLAYER-05) and accessibility basics (UI-03).

var world: WorldBuilder
var player: Player
var mission: Mission

var _objective_label: Label
var _prompt_label: Label
var _health_bar: ProgressBar
var _health_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _wanted_label: Label
var _stats_label: Label
var _notifications: VBoxContainer
var _crosshair: Control
var _minimap: Control
var _pause_panel: Control
var _title_panel: Control
var _debug_label: Label
var _settings_panel: Control
var _settings_values: Label
var _settings_rows: Array = []
var _marker: Vector3 = Vector3.ZERO

const NOTIFICATION_LIFETIME := 4.0

func setup(w: WorldBuilder, p: Player, m: Mission) -> void:
	world = w
	player = p
	mission = m
	layer = 10
	_build()
	Events.objective_changed.connect(func(text): _objective_label.text = text)
	Events.interaction_prompt.connect(func(text): _prompt_label.text = text)
	Events.health_changed.connect(_on_health)
	Events.ammo_changed.connect(_on_ammo)
	Events.wanted_changed.connect(_on_wanted)
	Events.notify.connect(_on_notify)
	if mission:
		_objective_label.text = mission.current_objective()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_objective_label = _mk_label(root, Vector2(24, 18), 22, Color(0.97, 0.95, 0.88))
	_objective_label.size = Vector2(760, 60)
	_objective_label.text = "Objective: —"

	_prompt_label = _mk_label(root, Vector2(640, 620), 20, Color(1.0, 0.92, 0.6))
	_prompt_label.size = Vector2(600, 30)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_health_bar = ProgressBar.new()
	_health_bar.position = Vector2(24, 96)
	_health_bar.size = Vector2(240, 18)
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = false
	root.add_child(_health_bar)
	var hp_frame := ColorRect.new()
	hp_frame.position = Vector2(24, 96)
	hp_frame.size = Vector2(240, 18)
	hp_frame.color = Color(0.1, 0.1, 0.1, 0.45)
	root.add_child(hp_frame)
	_health_bar.position = Vector2(24, 96)

	_health_label = _mk_label(root, Vector2(24, 112), 16, Color(0.95, 0.93, 0.88))
	_health_label.text = "HEALTH 100"

	_ammo_label = _mk_label(root, Vector2(1000, 96), 22, Color(0.95, 0.93, 0.88))
	_ammo_label.text = "12 / 96"
	_weapon_label = _mk_label(root, Vector2(1000, 122), 15, Color(0.78, 0.80, 0.86))
	_weapon_label.text = "PISTOL"

	_wanted_label = _mk_label(root, Vector2(1000, 24), 22, Color(0.95, 0.72, 0.35))
	_wanted_label.text = ""

	_stats_label = _mk_label(root, Vector2(24, 640), 17, Color(0.88, 0.90, 0.94))
	_stats_label.text = ""

	_debug_label = _mk_label(root, Vector2(24, 140), 15, Color(0.75, 0.85, 0.95))
	_debug_label.visible = false

	_notifications = VBoxContainer.new()
	_notifications.position = Vector2(760, 560)
	_notifications.size = Vector2(480, 120)
	_notifications.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_notifications)

	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	root.add_child(_crosshair)

	_minimap = Control.new()
	_minimap.position = Vector2(1010, 400)
	_minimap.size = Vector2(240, 240)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.draw.connect(_draw_minimap)
	root.add_child(_minimap)

	_build_pause_panel(root)
	_build_title_panel(root)
	_build_settings_panel(root)

func _mk_label(parent: Control, pos: Vector2, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.06, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build_pause_panel(root: Control) -> void:
	_pause_panel = Control.new()
	_pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	root.add_child(_pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.add_child(dim)
	var title := _mk_label(_pause_panel, Vector2(520, 180), 40, Color(0.97, 0.95, 0.9))
	title.text = "PAUSED"
	var opts := [
		"[ESC] Resume",
		"[F5] Save progress",
		"[F6] Load last save",
		"[F7] Restart mission checkpoint",
		"[F8] Toggle HUD (accessibility)",
		"[F9] Quit to title",
	]
	for i in opts.size():
		var l := _mk_label(_pause_panel, Vector2(520, 250 + i * 34), 20, Color(0.9, 0.92, 0.96))
		l.text = opts[i]
	var ctrl := _mk_label(_pause_panel, Vector2(520, 480), 16, Color(0.72, 0.76, 0.84))
	ctrl.text = "WASD move  •  Shift sprint  •  Space jump  •  Mouse look  •  LMB fire  •  RMB aim  •  R reload  •  Q swap  •  E enter/exit  •  F1 debug"

func _build_title_panel(root: Control) -> void:
	_title_panel = Control.new()
	_title_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_panel.visible = true
	root.add_child(_title_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.07, 0.10, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_panel.add_child(dim)
	var t := _mk_label(_title_panel, Vector2(420, 220), 52, Color(0.98, 0.95, 0.86))
	t.text = "ORCHARD REACH"
	var s := _mk_label(_title_panel, Vector2(460, 285), 20, Color(0.82, 0.85, 0.9))
	s.text = "A Singapore-inspired open-world slice — wave 1 build"
	var lines := [
		"[ENTER] New game",
		"[F6] Continue from save",
		"",
		"WASD move • Shift sprint • Space jump • Mouse look",
		"LMB fire • RMB aim • R reload • Q swap weapon",
		"E enter/exit vehicle • Esc pause",
	]
	for i in lines.size():
		var l := _mk_label(_title_panel, Vector2(470, 340 + i * 32), 19, Color(0.88, 0.90, 0.95))
		l.text = lines[i]

func _build_settings_panel(root: Control) -> void:
	_settings_panel = Control.new()
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	root.add_child(_settings_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.06, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.add_child(dim)
	var t := _mk_label(_settings_panel, Vector2(500, 190), 32, Color(0.97, 0.95, 0.9))
	t.text = "SETTINGS"
	_settings_rows = [
		"[1/2] Mouse sensitivity",
		"[3] Invert look Y",
		"[4] Reduced camera shake",
		"[5] HUD visible",
	]
	for i in _settings_rows.size():
		var l := _mk_label(_settings_panel, Vector2(500, 250 + i * 30), 18, Color(0.9, 0.92, 0.96))
		l.text = _settings_rows[i]
	_settings_values = _mk_label(_settings_panel, Vector2(800, 250), 18, Color(0.95, 0.85, 0.55))
	_settings_values.size = Vector2(320, 140)

func refresh_settings() -> void:
	if _settings_values == null:
		return
	_settings_values.text = "sensitivity %.2f\ninvert Y %s\nreduced shake %s\nHUD %s" % [
		float(Game.settings.get("mouse_sensitivity", 1.0)),
		"ON" if bool(Game.settings.get("invert_y", false)) else "OFF",
		"ON" if bool(Game.settings.get("reduced_shake", false)) else "OFF",
		"ON" if bool(Game.settings.get("hud_visible", true)) else "OFF"]

func toggle_settings() -> void:
	_settings_panel.visible = not _settings_panel.visible
	refresh_settings()

func settings_visible() -> bool:
	return _settings_panel != null and _settings_panel.visible

func show_title(show: bool) -> void:
	_title_panel.visible = show

func set_paused(paused: bool) -> void:
	_pause_panel.visible = paused

func _on_health(value: float, max_value: float) -> void:
	_health_bar.value = value
	_health_label.text = "HEALTH %d" % int(round(value))

func _on_ammo(mag: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [mag, reserve]
	_weapon_label.text = Game.carried_weapon.to_upper()

func _on_wanted(level: int) -> void:
	_update_wanted_label()

func _update_wanted_label() -> void:
	var level := Game.wanted_level
	var stars := ""
	for i in level:
		stars += "★ "
	var state := ""
	if level > 0:
		state = "  ·  SEARCHING %ds" % int(ceil(Game.search_timer)) if not Game.player_seen else "  ·  SPOTTED"
	_wanted_label.text = "WANTED  " + stars + state

func _on_notify(text: String, kind: String) -> void:
	var l := _mk_label(_notifications, Vector2.ZERO, 18, Color(0.95, 0.95, 0.9) if kind != "bad" else Color(1.0, 0.55, 0.45))
	l.text = text
	l.custom_minimum_size = Vector2(460, 24)
	l.size = Vector2(460, 24)
	var timer := get_tree().create_timer(NOTIFICATION_LIFETIME)
	timer.timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free())

func _process(_delta: float) -> void:
	if player == null:
		return
	var speed := 0.0
	var alt := 0.0
	if Game.mode == Game.MODE_CAR and player.current_vehicle:
		speed = player.current_vehicle.speed_kmh()
	elif Game.mode == Game.MODE_HELI and player.current_vehicle:
		speed = player.current_vehicle.velocity.length() * 3.6
		alt = player.current_vehicle.global_position.y
	_stats_label.text = "SPEED %d km/h" % int(speed)
	if Game.mode == Game.MODE_HELI:
		_stats_label.text += "   ALT %d m" % int(alt)
	_update_wanted_label()
	_crosshair.queue_redraw()
	_minimap.queue_redraw()
	if _debug_label.visible:
		_debug_label.text = "mode=%d stage=%d wanted=%d heat=%.0f hp=%.0f peds=%d" % [
			Game.mode, Game.mission_stage, Game.wanted_level, Game.wanted_heat,
			Game.health, _count_group("npcs")]

func _count_group(name: String) -> int:
	return get_tree().get_nodes_in_group(name).size()

func _draw_crosshair() -> void:
	var c := _crosshair.size * 0.5
	var col := Color(0.98, 0.96, 0.90, 0.9)
	_crosshair.draw_line(c + Vector2(-9, 0), c + Vector2(-3, 0), col, 2.0)
	_crosshair.draw_line(c + Vector2(3, 0), c + Vector2(9, 0), col, 2.0)
	_crosshair.draw_line(c + Vector2(0, -9), c + Vector2(0, -3), col, 2.0)
	_crosshair.draw_line(c + Vector2(0, 3), c + Vector2(0, 9), col, 2.0)
	_crosshair.draw_circle(c, 1.5, col)

func _draw_minimap() -> void:
	if world == null or player == null:
		return
	var rect := Rect2(Vector2.ZERO, _minimap.size)
	_minimap.draw_rect(rect, Color(0.06, 0.08, 0.10, 0.72), true)
	var centre: Vector3 = player.controlled_actor().global_position
	var scale := 0.16
	var to_map := func(p: Vector3) -> Vector2:
		return Vector2((p.x - centre.x) * scale, (p.z - centre.z) * scale) + _minimap.size * 0.5
	# roads
	for x in WorldBuilder.X_LINES:
		var p0: Vector2 = to_map.call(Vector3(x, 0, -340.0))
		var p1: Vector2 = to_map.call(Vector3(x, 0, 340.0))
		_minimap.draw_line(p0, p1, Color(0.35, 0.37, 0.40, 0.9), 3.0)
	for z in WorldBuilder.Z_LINES:
		var q0: Vector2 = to_map.call(Vector3(-340.0, 0, z))
		var q1: Vector2 = to_map.call(Vector3(340.0, 0, z))
		_minimap.draw_line(q0, q1, Color(0.35, 0.37, 0.40, 0.9), 3.0)
	# block footprints
	for bx in [-240.0, -80.0, 80.0, 240.0]:
		for bz in [-240.0, -80.0, 80.0, 240.0]:
			var centre_p := Vector3(bx, 0.0, bz)
			var c0: Vector2 = to_map.call(centre_p - Vector3(72.0, 0.0, 72.0))
			_minimap.draw_rect(Rect2(c0, Vector2(144.0 * scale, 144.0 * scale)), Color(0.20, 0.21, 0.23, 0.9), true)
	# water
	var wrect := Rect2(to_map.call(Vector3(-360, 0, -350.0)), Vector2(720.0 * scale, 30.0 * scale))
	_minimap.draw_rect(wrect, Color(0.16, 0.31, 0.36, 0.85), true)
	# objective marker
	if mission:
		var obj: Vector3 = mission.get_meta("marker", Vector3.ZERO)
		var mp: Vector2 = to_map.call(obj)
		_minimap.draw_circle(mp, 6.0, Color(0.35, 0.95, 0.75, 0.95))
	# police
	for p in get_tree().get_nodes_in_group("npcs"):
		if p.is_police and p.state != NPC.State.DEAD:
			_minimap.draw_circle(to_map.call(p.global_position), 3.5, Color(0.95, 0.35, 0.30, 0.95))
	# player arrow
	var c := _minimap.size * 0.5
	_minimap.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -7), c + Vector2(5, 6), c + Vector2(0, 3), c + Vector2(-5, 6)]), Color(0.98, 0.94, 0.80, 0.98))
	_minimap.draw_rect(rect, Color(0.8, 0.8, 0.85, 0.35), false, 2.0)

func set_marker(pos: Vector3) -> void:
	_marker = pos
	if mission:
		mission.set_meta("marker", pos)
