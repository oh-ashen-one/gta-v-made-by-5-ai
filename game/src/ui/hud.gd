class_name HUD
extends CanvasLayer
## Original readable HUD (UI-02), navigation display, pause/controls shell
## (UI-01, PLAYER-05) and accessibility basics (UI-03).

var world: WorldBuilder
var player: Player
var mission: Mission

var _objective_label: Label
var _prompt_label: Label
var _health_bar: Control
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
var _gameplay_controls: Array[CanvasItem] = []
var _layout_root: Control

const NOTIFICATION_LIFETIME := 4.0

func setup(w: WorldBuilder, p: Player, m: Mission) -> void:
	world = w
	player = p
	mission = m
	layer = 10
	_build()
	Events.objective_changed.connect(func(text): _objective_label.text = String(text).replace("Harbour Relay — ", ""))
	Events.interaction_prompt.connect(func(text): _prompt_label.text = text)
	Events.health_changed.connect(_on_health)
	Events.ammo_changed.connect(_on_ammo)
	Events.wanted_changed.connect(_on_wanted)
	Events.notify.connect(_on_notify)
	Events.settings_changed.connect(func(_settings: Dictionary):
		refresh_settings()
		set_gameplay_visible(bool(Game.settings.get("hud_visible",true))))
	if mission:
		_objective_label.text = mission.current_objective().replace("Harbour Relay — ", "")

func _build() -> void:
	var root := Control.new()
	_layout_root = root
	root.size = Vector2(1280,720)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_fit_layout()
	get_viewport().size_changed.connect(_fit_layout)
	_panel(root,Vector2(24,24),Vector2(620,78),Color(.025,.055,.058,.88))
	var tag := _mk_label(root,Vector2(40,34),11,Color(.57,.78,.70))
	tag.text="HARBOUR RELAY"
	_objective_label=_mk_label(root,Vector2(40,53),18,Color(.96,.94,.86))
	_objective_label.size=Vector2(586,44)
	_objective_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_prompt_label=_mk_label(root,Vector2(300,626),18,Color(1,.88,.58))
	_prompt_label.size=Vector2(680,32)
	_prompt_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_health_bar=Control.new()
	_health_bar.position=Vector2(24,665);_health_bar.size=Vector2(206,6)
	_health_bar.draw.connect(func():
		_health_bar.draw_rect(Rect2(Vector2.ZERO,Vector2(206,6)),Color(.02,.04,.04,.85))
		_health_bar.draw_rect(Rect2(Vector2.ZERO,Vector2(206*Game.health_ratio(),6)),Color(.43,.76,.63)))
	root.add_child(_health_bar)
	_health_label=_mk_label(root,Vector2(24,678),12,Color(.88,.93,.88));_health_label.text="HEALTH 100"
	_ammo_label=_mk_label(root,Vector2(1110,30),26,Color(.97,.95,.88));_ammo_label.text="12 / 96"
	_weapon_label=_mk_label(root,Vector2(1112,64),12,Color(.65,.74,.74));_weapon_label.text="PISTOL"
	_wanted_label=_mk_label(root,Vector2(815,110),16,Color(.97,.68,.36));_wanted_label.size=Vector2(430,45)
	_wanted_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_stats_label=_mk_label(root,Vector2(1000,660),18,Color(.94,.95,.92));_stats_label.size=Vector2(245,40)
	_stats_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_debug_label=_mk_label(root,Vector2(24,120),14,Color(.7,.8,.85));_debug_label.visible=false
	_notifications=VBoxContainer.new();_notifications.position=Vector2(790,165);_notifications.size=Vector2(450,120)
	_notifications.z_index=100
	_notifications.alignment=BoxContainer.ALIGNMENT_END;root.add_child(_notifications)
	_crosshair=Control.new();_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter=Control.MOUSE_FILTER_IGNORE;_crosshair.draw.connect(_draw_crosshair);root.add_child(_crosshair)
	_minimap=Control.new();_minimap.position=Vector2(24,442);_minimap.size=Vector2(206,206)
	_minimap.clip_contents=true;_minimap.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_minimap.draw.connect(_draw_minimap);root.add_child(_minimap)
	for child in root.get_children():
		if child is CanvasItem: _gameplay_controls.append(child)
	_build_pause_panel(root);_build_title_panel(root);_build_settings_panel(root)

func _fit_layout() -> void:
	if _layout_root != null:
		_layout_root.scale = get_viewport().get_visible_rect().size / Vector2(1280,720)

func _panel(parent: Control, pos: Vector2, size: Vector2, color: Color) -> Panel:
	var panel:=Panel.new();panel.position=pos;panel.size=size;panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style:=StyleBoxFlat.new();style.bg_color=color
	style.corner_radius_top_left=6;style.corner_radius_top_right=6;style.corner_radius_bottom_left=6;style.corner_radius_bottom_right=6
	panel.add_theme_stylebox_override("panel",style);parent.add_child(panel);return panel

func _button(parent: Control, text: String, pos: Vector2, callback: Callable) -> Button:
	var button:=Button.new();button.text=text;button.position=pos;button.size=Vector2(300,45)
	button.add_theme_font_size_override("font_size",17)
	var normal:=StyleBoxFlat.new();normal.bg_color=Color(.09,.15,.15,.94)
	normal.content_margin_left=18;normal.corner_radius_top_left=4;normal.corner_radius_bottom_left=4
	var hover:=normal.duplicate() as StyleBoxFlat;hover.bg_color=Color(.23,.36,.32,.98)
	button.add_theme_stylebox_override("normal",normal);button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",hover);button.pressed.connect(callback);parent.add_child(button)
	return button

func _mk_label(parent: Control, pos: Vector2, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.06, 0.85))
	l.add_theme_constant_override("outline_size", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build_pause_panel(root: Control) -> void:
	_pause_panel=Control.new();_pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT);_pause_panel.visible=false;root.add_child(_pause_panel)
	_panel(_pause_panel,Vector2.ZERO,Vector2(1280,720),Color(.015,.035,.038,.9))
	var title:=_mk_label(_pause_panel,Vector2(96,110),42,Color(.97,.94,.86));title.text="Take a breath."
	_button(_pause_panel,"Resume   ·   Esc",Vector2(96,210),func():get_tree().current_scene._toggle_pause())
	_button(_pause_panel,"Save progress   ·   F5",Vector2(96,265),func():
		if Game.save_game(): Events.toast("Progress saved.","good"))
	_button(_pause_panel,"Restart Harbour Relay   ·   F10",Vector2(96,320),func():mission.restart();get_tree().current_scene._toggle_pause())
	_button(_pause_panel,"Settings   ·   F3",Vector2(96,375),func():get_tree().current_scene._toggle_settings())
	_button(_pause_panel,"Quit game",Vector2(96,430),func():get_tree().current_scene._quit_game())
	var controls:=_mk_label(_pause_panel,Vector2(650,210),18,Color(.78,.85,.82))
	controls.text="ON FOOT\nWASD move   /   Shift sprint   /   Space jump\nMouse look   /   Right mouse aim   /   Left mouse fire\nR reload   /   Q change weapon   /   E interact\n\nDRIVING\nW/S accelerate and reverse   /   A/D steer\nSpace brake   /   E exit when safe\n\nFLIGHT\nSpace climb   /   Shift descend   /   W/S forward/back\nA/D turn   /   E exit after landing"

func _build_title_panel(root: Control) -> void:
	_title_panel=Control.new();_title_panel.set_anchors_preset(Control.PRESET_FULL_RECT);_title_panel.visible=true;root.add_child(_title_panel)
	_panel(_title_panel,Vector2.ZERO,Vector2(1280,720),Color(.015,.04,.045,.92))
	var small:=_mk_label(_title_panel,Vector2(96,105),13,Color(.65,.81,.71));small.text="THE HARBOUR DISTRICT"
	var title:=_mk_label(_title_panel,Vector2(91,142),64,Color(.98,.94,.84));title.text="ORCHARD REACH"
	var sub:=_mk_label(_title_panel,Vector2(96,230),18,Color(.72,.8,.78));sub.text="A city to cross. A package to deliver."
	_button(_title_panel,"New game   ·   Enter",Vector2(96,310),func():get_tree().current_scene._new_game())
	_button(_title_panel,"Continue   ·   F6",Vector2(96,365),func():get_tree().current_scene._continue_game())
	_button(_title_panel,"Settings   ·   F3",Vector2(96,420),func():get_tree().current_scene._toggle_settings())
	_button(_title_panel,"Quit game",Vector2(96,475),func():get_tree().current_scene._quit_game())
	var controls:=_mk_label(_title_panel,Vector2(720,320),17,Color(.78,.85,.80))
	controls.text="WALK THE ARCADES\nWASD move · Mouse look · Shift sprint\n\nTAKE THE WHEEL\nE enter/exit · W/S throttle · A/D steer\n\nTAKE TO THE AIR\nSpace climb · Shift descend · E land and exit"
	var footer:=_mk_label(_title_panel,Vector2(96,650),13,Color(.48,.62,.58));footer.text="Original fictional Singapore-inspired district"

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
	_health_bar.queue_redraw()
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
	_wanted_label.text = "ALERT %s%s" % ["I".repeat(level),state] if level>0 else ""

func _on_notify(text: String, kind: String) -> void:
	if text=="Civilian fleeing!": return
	while _notifications.get_child_count()>=3:
		var expired:=_notifications.get_child(0)
		_notifications.remove_child(expired)
		expired.queue_free()
	var l := _mk_label(_notifications, Vector2.ZERO, 15, Color(0.95, 0.95, 0.9) if kind != "bad" else Color(1.0, 0.55, 0.45))
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 24)
	l.size = Vector2(440, 24)
	var weak_label: WeakRef = weakref(l)
	var timer := get_tree().create_timer(NOTIFICATION_LIFETIME)
	timer.timeout.connect(func():
		var label := weak_label.get_ref() as Label
		if is_instance_valid(label): label.queue_free())

func _process(_delta: float) -> void:
	if player == null:
		return
	# Gameplay messages must not draw over modal controls or settings values.
	_notifications.visible = bool(Game.settings.get("hud_visible",true)) and not Game.simulation_paused and not _title_panel.visible and not _settings_panel.visible
	var speed := 0.0
	var alt := 0.0
	if Game.mode == Game.MODE_CAR and player.current_vehicle:
		speed = player.current_vehicle.speed_kmh()
	elif Game.mode == Game.MODE_HELI and player.current_vehicle:
		speed = player.current_vehicle.velocity.length() * 3.6
		alt = player.current_vehicle.global_position.y
	_stats_label.text = "%d km/h" % int(speed) if Game.mode!=Game.MODE_FOOT else ""
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
	if player==null or not player.aiming or Game.mode!=Game.MODE_FOOT: return
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
	var scale := 0.38
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
	var arrow:=PackedVector2Array()
	for point in [Vector2(0,-7),Vector2(5,6),Vector2(0,3),Vector2(-5,6)]:
		arrow.append(c+point.rotated(-player.controlled_actor().rotation.y))
	_minimap.draw_colored_polygon(arrow,Color(.98,.94,.80,.98))
	_minimap.draw_rect(rect, Color(0.8, 0.8, 0.85, 0.35), false, 2.0)

func set_marker(pos: Vector3) -> void:
	_marker = pos
	if mission:
		mission.set_meta("marker", pos)

func set_gameplay_visible(show: bool) -> void:
	for item in _gameplay_controls:
		if is_instance_valid(item) and item != _debug_label: item.visible = show

func clear_notifications() -> void:
	for notice in _notifications.get_children():
		_notifications.remove_child(notice)
		notice.queue_free()
