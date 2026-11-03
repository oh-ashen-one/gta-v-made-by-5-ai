class_name HUD
extends CanvasLayer
## Original readable HUD (UI-02), navigation display, pause/controls shell
## (UI-01, PLAYER-05) and accessibility basics (UI-03).

var world: WorldBuilder
var player: Player
var mission: Mission

var _objective_label: Label
var _objective_tag: Label
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
var _hotel_status := ""
const ThemeKit := preload("res://src/ui/jade_theme.gd")
const Wheel := preload("res://src/ui/weapon_wheel.gd")
var _wheel: Control
var _wheel_open := false
var _sensitivity: HSlider
var _setting_buttons := {}
var _radio_label: Label

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
	_panel(root,Vector2(30,30),Vector2(370,94),ThemeKit.PANEL)
	_panel(root,Vector2(30,42),Vector2(3,70),ThemeKit.JADE)
	_objective_tag = _mk_label(root,Vector2(48,43),11,ThemeKit.JADE)
	_objective_tag.text = "HARBOUR RELAY"
	_objective_label = _mk_label(root,Vector2(48,65),17,ThemeKit.TEXT)
	_objective_label.size = Vector2(332,48)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label = _mk_label(root,Vector2(340,620),16,ThemeKit.TEXT)
	_prompt_label.size = Vector2(600,34)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_bar = Control.new()
	_health_bar.position=Vector2(30,668); _health_bar.size=Vector2(180,5)
	_health_bar.draw.connect(func():
		_health_bar.draw_rect(Rect2(Vector2.ZERO,Vector2(180,5)),ThemeKit.PANEL)
		_health_bar.draw_rect(Rect2(Vector2.ZERO,Vector2(180*Game.health_ratio(),5)),ThemeKit.JADE))
	root.add_child(_health_bar)
	_health_label = _mk_label(root,Vector2(30,680),11,ThemeKit.MUTED)
	_health_label.text = "HEALTH 100"
	_panel(root,Vector2(1092,647),Vector2(158,57),ThemeKit.PANEL)
	_weapon_label = _mk_label(root,Vector2(1108,653),10,ThemeKit.JADE)
	_weapon_label.text = "PISTOL"
	_ammo_label = _mk_label(root,Vector2(1108,668),26,ThemeKit.TEXT)
	_ammo_label.text = "12 / 96"
	_wanted_label = _mk_label(root,Vector2(840,32),13,ThemeKit.AMBER)
	_wanted_label.size=Vector2(410,34); _wanted_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_stats_label = _mk_label(root,Vector2(985,419),21,ThemeKit.TEXT)
	_stats_label.size=Vector2(265,36); _stats_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_radio_label = _mk_label(root,Vector2(360,677),12,ThemeKit.MUTED)
	_radio_label.size=Vector2(600,28); _radio_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_debug_label = _mk_label(root,Vector2(30,134),13,ThemeKit.MUTED)
	_debug_label.visible=false
	_notifications=VBoxContainer.new(); _notifications.position=Vector2(890,90); _notifications.size=Vector2(360,180)
	_notifications.add_theme_constant_override("separation",8)
	_notifications.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(_notifications)
	_crosshair=Control.new(); _crosshair.size=Vector2(1280,720)
	_crosshair.mouse_filter=Control.MOUSE_FILTER_IGNORE; _crosshair.draw.connect(_draw_crosshair); root.add_child(_crosshair)
	_minimap=Control.new(); _minimap.position=Vector2(30,476); _minimap.size=Vector2(180,180)
	_minimap.clip_contents=true; _minimap.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_minimap.draw.connect(_draw_minimap); root.add_child(_minimap)
	_wheel=Wheel.new(); _wheel.position=Vector2(1070,460); root.add_child(_wheel)
	for child in root.get_children():
		if child is CanvasItem: _gameplay_controls.append(child)
	_build_pause_panel(root); _build_title_panel(root); _build_settings_panel(root)

func _fit_layout() -> void:
	if _layout_root != null:
		var viewport_size := get_viewport().get_visible_rect().size
		var factor := minf(viewport_size.x/1280.0,viewport_size.y/720.0)
		_layout_root.scale=Vector2.ONE*factor
		_layout_root.position=(viewport_size-Vector2(1280,720)*factor)*0.5

func _panel(parent: Control, pos: Vector2, dimensions: Vector2, color: Color) -> Panel:
	var panel:=Panel.new(); panel.position=pos; panel.size=dimensions
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",ThemeKit.box(color))
	parent.add_child(panel)
	return panel

func _button(parent: Control, text: String, pos: Vector2, callback: Callable) -> Button:
	var button:=Button.new(); button.text=text; button.position=pos; button.size=Vector2(320,46)
	button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	ThemeKit.button(button)
	button.pressed.connect(callback); parent.add_child(button)
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
	_pause_panel=Control.new(); _pause_panel.size=Vector2(1280,720); _pause_panel.visible=false; root.add_child(_pause_panel)
	_panel(_pause_panel,Vector2.ZERO,Vector2(1280,720),Color(0.025,0.045,0.038,0.94))
	_mk_label(_pause_panel,Vector2(80,66),12,ThemeKit.JADE).text="ORCHARD REACH / PAUSED"
	_mk_label(_pause_panel,Vector2(80,102),46,ThemeKit.TEXT).text="Take a breath."
	_button(_pause_panel,"Resume                                      Esc",Vector2(80,214),func():get_tree().current_scene._toggle_pause())
	_button(_pause_panel,"Save progress                               F5",Vector2(80,272),func():
		if Game.save_game(): Events.toast("Progress saved.","good"))
	_button(_pause_panel,"Restart Harbour Relay                     F10",Vector2(80,330),func():get_tree().current_scene._restart_mission();get_tree().current_scene._toggle_pause())
	_button(_pause_panel,"Settings                                      F3",Vector2(80,388),func():get_tree().current_scene._toggle_settings())
	_button(_pause_panel,"Quit game",Vector2(80,446),func():get_tree().current_scene._quit_game())
	_panel(_pause_panel,Vector2(570,206),Vector2(610,360),ThemeKit.PANEL)
	_mk_label(_pause_panel,Vector2(598,234),12,ThemeKit.JADE).text="THE CITY IS YOURS"
	_mk_label(_pause_panel,Vector2(598,270),16,ThemeKit.TEXT).text="ON FOOT
WASD move · Shift sprint · Space jump
Mouse look · Right mouse aim · Left mouse fire
R reload · Q cycle weapon · Hold Tab for weapon wheel
E interact / enter vehicle

DRIVING   W/S throttle · A/D steer · Space brake
FLIGHT     Space climb · Shift descend · A/D turn
E exit a vehicle when safe"

func _build_title_panel(root: Control) -> void:
	_title_panel=Control.new(); _title_panel.size=Vector2(1280,720); root.add_child(_title_panel)
	_panel(_title_panel,Vector2(32,32),Vector2(510,656),ThemeKit.PANEL)
	_mk_label(_title_panel,Vector2(70,91),12,ThemeKit.JADE).text="SINGAPORE / THE HARBOUR DISTRICT"
	_mk_label(_title_panel,Vector2(65,140),58,ThemeKit.TEXT).text="ORCHARD
REACH"
	_mk_label(_title_panel,Vector2(70,292),16,ThemeKit.MUTED).text="A city to cross. A package to deliver."
	_button(_title_panel,"New game                                  Enter",Vector2(70,352),func():get_tree().current_scene._new_game())
	_button(_title_panel,"Continue                                      F6",Vector2(70,410),func():get_tree().current_scene._continue_game())
	_button(_title_panel,"Settings                                       F3",Vector2(70,468),func():get_tree().current_scene._toggle_settings())
	_button(_title_panel,"Quit game",Vector2(70,526),func():get_tree().current_scene._quit_game())
	_mk_label(_title_panel,Vector2(70,629),12,ThemeKit.MUTED).text="Walk the arcades. Take the wheel. Take to the air."

func _build_settings_panel(root: Control) -> void:
	_settings_panel=Control.new(); _settings_panel.size=Vector2(1280,720); _settings_panel.visible=false; root.add_child(_settings_panel)
	_panel(_settings_panel,Vector2.ZERO,Vector2(1280,720),Color(0.015,0.025,0.02,0.86))
	_panel(_settings_panel,Vector2(320,52),Vector2(640,616),ThemeKit.PANEL)
	_mk_label(_settings_panel,Vector2(360,82),11,ThemeKit.JADE).text="ORCHARD REACH / PREFERENCES"
	_mk_label(_settings_panel,Vector2(360,108),32,ThemeKit.TEXT).text="Settings"
	_mk_label(_settings_panel,Vector2(360,176),17,ThemeKit.TEXT).text="Mouse sensitivity"
	_sensitivity=HSlider.new(); _sensitivity.position=Vector2(360,214); _sensitivity.size=Vector2(485,28)
	_sensitivity.min_value=.2; _sensitivity.max_value=3.0; _sensitivity.step=.1
	_sensitivity.add_theme_stylebox_override("slider",ThemeKit.box(Color(0.17,0.23,0.19,1),3))
	_sensitivity.add_theme_stylebox_override("grabber_area",ThemeKit.box(ThemeKit.JADE,3))
	_settings_panel.add_child(_sensitivity)
	_sensitivity.value_changed.connect(func(value):Game.settings["mouse_sensitivity"]=value; refresh_settings())
	_settings_values=_mk_label(_settings_panel,Vector2(869,215),15,ThemeKit.JADE)
	var rows := [["invert_y","Invert Y","Invert vertical camera movement"],["reduced_shake","Reduced camera shake","Less movement from impacts and explosions"],["hud_visible","Gameplay HUD","Show objectives, map and ammunition"],["radio_enabled","Car radio","Shuffle music automatically while driving"]]
	for i in rows.size():
		var key: String=rows[i][0]
		var toggle:=CheckButton.new(); toggle.position=Vector2(354,270+i*67); toggle.size=Vector2(550,36)
		toggle.text=rows[i][1]; ThemeKit.toggle(toggle); _settings_panel.add_child(toggle)
		_mk_label(_settings_panel,Vector2(362,307+i*67),11,ThemeKit.MUTED).text=rows[i][2]
		_setting_buttons[key]=toggle
		toggle.toggled.connect(func(value):Game.settings[key]=value; set_gameplay_visible(bool(Game.settings.get("hud_visible",true))); refresh_settings())
	_button(_settings_panel,"‹  Back                                         Esc",Vector2(360,590),func():get_tree().current_scene._toggle_settings())

func refresh_settings() -> void:
	if _settings_values == null: return
	_settings_values.text="%.1f" % float(Game.settings.get("mouse_sensitivity",1.0))
	_sensitivity.set_value_no_signal(float(Game.settings.get("mouse_sensitivity",1.0)))
	for key in _setting_buttons:
		(_setting_buttons[key] as CheckButton).set_pressed_no_signal(bool(Game.settings.get(key,true if key in ["hud_visible","radio_enabled"] else false)))

func toggle_settings() -> void:
	_settings_panel.visible = not _settings_panel.visible
	refresh_settings()

func settings_visible() -> bool:
	return _settings_panel != null and _settings_panel.visible

func show_title(show: bool) -> void:
	_title_panel.visible = show
	set_gameplay_visible(not show and bool(Game.settings.get("hud_visible",true)))

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
		var old:=_notifications.get_child(0); _notifications.remove_child(old); old.queue_free()
	var notice:=PanelContainer.new(); notice.custom_minimum_size=Vector2(360,54)
	var style:=ThemeKit.box(); style.border_color=ThemeKit.AMBER if kind in ["warn","bad"] else ThemeKit.LINE
	notice.add_theme_stylebox_override("panel",style); notice.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_notifications.add_child(notice)
	var label:=Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size=Vector2(320,30); label.add_theme_font_size_override("font_size",14)
	label.add_theme_color_override("font_color",ThemeKit.AMBER if kind in ["warn","bad"] else ThemeKit.TEXT)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE; notice.add_child(label)
	var tween:=create_tween(); notice.modulate.a=0
	tween.tween_property(notice,"modulate:a",1.0,.18)
	tween.tween_interval(NOTIFICATION_LIFETIME)
	tween.tween_property(notice,"modulate:a",0.0,.3)
	tween.tween_callback(notice.queue_free)

func _process(_delta: float) -> void:
	if player == null:
		return
	# Keep every gameplay element off modal screens.
	set_gameplay_visible(bool(Game.settings.get("hud_visible",true)) and not _title_panel.visible and not _settings_panel.visible and not _pause_panel.visible)
	# Gameplay messages must not draw over modal controls or settings values.
	_wheel.visible = not _title_panel.visible and not _settings_panel.visible and not _pause_panel.visible and bool(Game.settings.get("hud_visible",true)) and Game.mode==Game.MODE_FOOT
	if _wheel_open: _wheel.update_hover()
	else: _wheel.queue_redraw()
	_radio_label.text = "RADIO  /  " + String(Sfx.radio_title()) if Sfx.has_method("radio_title") and Game.mode==Game.MODE_CAR else ""
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
	_minimap.visible=_hotel_status.is_empty() and bool(Game.settings.get("hud_visible",true)) and not _title_panel.visible and not _settings_panel.visible and not _pause_panel.visible
	if not _hotel_status.is_empty():_objective_label.text=_hotel_status
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
	_minimap.draw_rect(rect, Color(0.035, 0.06, 0.05, 0.92), true)
	var centre: Vector3 = player.controlled_actor().global_position
	var scale := 0.38
	var to_map := func(p: Vector3) -> Vector2:
		return Vector2((p.x - centre.x) * scale, (p.z - centre.z) * scale) + _minimap.size * 0.5
	# Wave M (downtown-map): the Marina Bay downtown layer (land, water, plots,
	# roads and bridges) under the district; the old bay/far-shore rects below
	# are only drawn without it.
	var downtown_layer := ResourceLoader.exists("res://src/world/downtown/map.gd")
	if downtown_layer:
		preload("res://src/world/downtown/minimap.gd").draw(_minimap, to_map, scale)
	# roads
	for x in WorldBuilder.X_LINES:
		var p0: Vector2 = to_map.call(Vector3(x, 0, -340.0))
		var p1: Vector2 = to_map.call(Vector3(x, 0, 340.0))
		_minimap.draw_line(p0, p1, Color(0.40, 0.49, 0.44, 0.65), 2.0)
	for z in WorldBuilder.Z_LINES:
		var q0: Vector2 = to_map.call(Vector3(-340.0, 0, z))
		var q1: Vector2 = to_map.call(Vector3(340.0, 0, z))
		_minimap.draw_line(q0, q1, Color(0.40, 0.49, 0.44, 0.65), 2.0)
	# block footprints
	for bx in [-240.0, -80.0, 80.0, 240.0]:
		for bz in [-240.0, -80.0, 80.0, 240.0]:
			var centre_p := Vector3(bx, 0.0, bz)
			var c0: Vector2 = to_map.call(centre_p - Vector3(72.0, 0.0, 72.0))
			_minimap.draw_rect(Rect2(c0, Vector2(144.0 * scale, 144.0 * scale)), Color(0.09, 0.13, 0.11, 0.96), true)
	# water: the whole bay out to the far shore (wave 5). A 30 m strip left the
	# bay as bare background, so the waterfront map was half black.
	if not downtown_layer:
		var wrect := Rect2(to_map.call(Vector3(-900.0, 0, -633.0)), Vector2(1800.0 * scale, 284.0 * scale))
		_minimap.draw_rect(wrect, Color(0.16, 0.31, 0.36, 0.85), true)
		# far-shore ground (Marina Bay Sands, ArtScience, Flyer) and the promenade deck
		_minimap.draw_rect(Rect2(to_map.call(Vector3(-480.0, 0, -863.0)), Vector2(920.0 * scale, 230.0 * scale)), Color(0.22, 0.26, 0.21, 0.9), true)
	_minimap.draw_rect(Rect2(to_map.call(Vector3(-205.0, 0, -738.0)), Vector2(234.0 * scale, 66.0 * scale)), Color(0.55, 0.57, 0.58, 0.95), true)
	_minimap.draw_rect(Rect2(to_map.call(Vector3(-350.0, 0, -349.0)), Vector2(700.0 * scale, 22.0 * scale)), Color(0.42, 0.42, 0.40, 0.9), true)
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
	_minimap.draw_rect(rect, ThemeKit.LINE, false, 1.0)
	_minimap.draw_string(ThemeDB.fallback_font,Vector2(9,17),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,11,ThemeKit.TEXT)

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

func set_hotel_status(text:String)->void:
	_hotel_status=text
	_objective_tag.text="HARBOUR RELAY" if text.is_empty() else "MARINA BAY SANDS"
	if text.is_empty() and is_instance_valid(mission):_objective_label.text=mission.current_objective().replace("Harbour Relay — ","")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode==KEY_TAB and not event.echo:
		if event.pressed and not Game.simulation_paused and Game.mode==Game.MODE_FOOT and not _title_panel.visible:
			open_weapon_wheel()
		elif not event.pressed and _wheel_open:
			close_weapon_wheel(true)
		else: return
		get_viewport().set_input_as_handled()
	elif _wheel_open and event.is_action_pressed("pause"):
		close_weapon_wheel(false)
		get_viewport().set_input_as_handled()

func open_weapon_wheel() -> void:
	if _wheel_open or Game.simulation_paused or Game.mode!=Game.MODE_FOOT: return
	_wheel_open=true; _wheel.expanded=true; _wheel.selected=Game.carried_weapon
	Game.simulation_paused=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_wheel.queue_redraw()

func close_weapon_wheel(equip: bool) -> void:
	if not _wheel_open: return
	if equip: player.equip_weapon(_wheel.selected)
	_wheel_open=false; _wheel.expanded=false
	Game.simulation_paused=false
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	_wheel.queue_redraw()
