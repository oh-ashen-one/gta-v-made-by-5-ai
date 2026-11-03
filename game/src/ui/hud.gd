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
const Art := preload("res://src/ui/hud_art.gd")
const DetailedMap := preload("res://src/ui/detailed_minimap.gd")
var _minimap_frame: Control
var _weapon_icon: TextureRect
var _prompt_plate: Panel
var _map_caption: Label
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
	Events.objective_changed.connect(func(text): _objective_label.text = _objective_sentence(String(text)))
	Events.interaction_prompt.connect(func(text): _prompt_label.text = text)
	Events.health_changed.connect(_on_health)
	Events.ammo_changed.connect(_on_ammo)
	Events.wanted_changed.connect(_on_wanted)
	Events.notify.connect(_on_notify)
	Events.settings_changed.connect(func(_settings: Dictionary):
		refresh_settings()
		set_gameplay_visible(bool(Game.settings.get("hud_visible",true))))
	if mission:
		_objective_label.text = _objective_sentence(mission.current_objective())

func _objective_sentence(text: String) -> String:
	var sentence:=text.replace("Harbour Relay — ","").strip_edges()
	return sentence.substr(0,1).to_upper()+sentence.substr(1) if not sentence.is_empty() else ""

func _build() -> void:
	var root := Control.new()
	_layout_root = root
	root.size = Vector2(1280,720)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_fit_layout()
	get_viewport().size_changed.connect(_fit_layout)
	_panel(root,Vector2(866,18),Vector2(396,40),ThemeKit.PANEL)
	_objective_tag = _mk_label(root,Vector2(882,20),11,ThemeKit.JADE)
	_objective_tag.text = ""; _objective_tag.hide()
	_objective_label = _mk_label(root,Vector2(882,29),13,ThemeKit.TEXT)
	_objective_label.size = Vector2(364,24)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_objective_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_prompt_plate=_panel(root,Vector2(540,638),Vector2(200,28),ThemeKit.PANEL)
	_prompt_label = _mk_label(root,Vector2(340,645),12,ThemeKit.TEXT)
	_prompt_label.size = Vector2(600,34)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_bar = Control.new()
	_health_bar.position=Vector2(24,685); _health_bar.size=Vector2(176,3)
	_health_bar.draw.connect(func():
		_health_bar.draw_rect(Rect2(Vector2.ZERO,Vector2(176,3)),ThemeKit.PANEL)
		_health_bar.draw_rect(Rect2(Vector2.ZERO,Vector2(176*Game.health_ratio(),3)),ThemeKit.JADE))
	root.add_child(_health_bar)
	_health_label = _mk_label(root,Vector2(24,695),11,ThemeKit.MUTED)
	_health_label.text = "HEALTH 100"
	_panel(root,Vector2(1094,651),Vector2(168,53),ThemeKit.PANEL)
	_weapon_label = _mk_label(root,Vector2(1158,658),10,ThemeKit.JADE)
	_weapon_label.text = "1  PISTOL"
	_ammo_label = _mk_label(root,Vector2(1158,676),17,ThemeKit.TEXT)
	_ammo_label.text = "12 / 96"
	_weapon_icon=TextureRect.new();_weapon_icon.position=Vector2(1102,659);_weapon_icon.size=Vector2(48,30)
	_weapon_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_weapon_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_icon.texture=Art.texture("pistol");_weapon_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(_weapon_icon)
	_wanted_label = _mk_label(root,Vector2(840,67),13,ThemeKit.AMBER)
	_wanted_label.size=Vector2(410,34); _wanted_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_stats_label = _mk_label(root,Vector2(1074,619),14,ThemeKit.TEXT)
	_stats_label.size=Vector2(180,36); _stats_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_radio_label = _mk_label(root,Vector2(360,677),12,ThemeKit.MUTED)
	_radio_label.size=Vector2(600,28); _radio_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_debug_label = _mk_label(root,Vector2(30,134),13,ThemeKit.MUTED)
	_debug_label.visible=false
	_notifications=VBoxContainer.new(); _notifications.position=Vector2(966,102); _notifications.size=Vector2(296,160)
	_notifications.add_theme_constant_override("separation",8)
	_notifications.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(_notifications)
	_crosshair=Control.new(); _crosshair.size=Vector2(1280,720)
	_crosshair.mouse_filter=Control.MOUSE_FILTER_IGNORE; _crosshair.draw.connect(_draw_crosshair); root.add_child(_crosshair)
	_minimap_frame=_panel(root,Vector2(20,500),Vector2(184,184),Color(.97,.97,.97,.97))
	_minimap=DetailedMap.new();_minimap.position=Vector2(24,504);_minimap.size=Vector2(176,176)
	root.add_child(_minimap);_minimap.setup(world,player,mission)
	_map_caption=_mk_label(root,Vector2(24,484),11,ThemeKit.TEXT);_map_caption.text="HERITAGE DISTRICT"
	_wheel=Wheel.new(); _wheel.hide(); root.add_child(_wheel)
	for child in root.get_children():
		if child is CanvasItem: _gameplay_controls.append(child)
	_build_pause_panel(root); _build_title_panel(root); _build_settings_panel(root)
	_build_map(root)

func _fit_layout() -> void:
	if _layout_root != null:
		var viewport_size := get_viewport().get_visible_rect().size
		var factor := minf(viewport_size.x/1280.0,viewport_size.y/720.0)
		_layout_root.scale=Vector2.ONE*factor
		_layout_root.position=(viewport_size-Vector2(1280,720)*factor)*0.5

func _panel(parent: Control, pos: Vector2, dimensions: Vector2, color: Color) -> Panel:
	var panel:=Panel.new(); panel.position=pos; panel.size=dimensions
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",ThemeKit.box(color,6))
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
	_mk_label(_pause_panel,Vector2(80,102),46,ThemeKit.TEXT).text="PAUSED"
	_button(_pause_panel,"Resume                                      Esc",Vector2(80,214),func():get_tree().current_scene._toggle_pause())
	_button(_pause_panel,"Save progress                               F5",Vector2(80,272),func():
		if Game.save_game(): Events.toast("Progress saved.","good"))
	_button(_pause_panel,"Restart Harbour Relay                     F10",Vector2(80,330),func():get_tree().current_scene._restart_mission();get_tree().current_scene._toggle_pause())
	_button(_pause_panel,"Settings                                      F3",Vector2(80,388),func():get_tree().current_scene._toggle_settings())
	_button(_pause_panel,"Quit game",Vector2(80,446),func():get_tree().current_scene._quit_game())
	var guide := TextureRect.new()
	guide.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; guide.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	guide.texture = load("res://assets/ui/generated/controls-manual.png")
	guide.position = Vector2(478,100); guide.size = Vector2(770,514)
	guide.name="VisualControlsGuide"
	_pause_panel.add_child(guide)

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
	_weapon_label.text = ("1  " if Game.carried_weapon=="pistol" else "2  ")+Game.carried_weapon.to_upper()
	_weapon_icon.texture=Art.texture(Game.carried_weapon)

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
	var notice:=PanelContainer.new(); notice.custom_minimum_size=Vector2(296,40)
	var style:=ThemeKit.box(ThemeKit.PANEL,6)
	notice.add_theme_stylebox_override("panel",style); notice.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_notifications.add_child(notice)
	var label:=Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size=Vector2(260,24); label.add_theme_font_size_override("font_size",14)
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
	if navigation:
		navigation.update(player.controlled_actor().global_position)
		_gps_label.text=("%s · %d m" % [navigation.title,navigation.distance_remaining(player.controlled_actor().global_position)]) if navigation.active else "M  Map"
	if _full_map.visible:
		set_gameplay_visible(false); _city_map.queue_redraw(); return
	# Keep every gameplay element off modal screens.
	set_gameplay_visible(bool(Game.settings.get("hud_visible",true)) and not _title_panel.visible and not _settings_panel.visible and not _pause_panel.visible)
	# Gameplay messages must not draw over modal controls or settings values.
	_wheel.hide()
	_objective_tag.hide()
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
	_minimap_frame.visible=_minimap.visible
	_map_caption.visible=_minimap.visible
	_map_caption.text="HERITAGE DISTRICT" if absf(player.global_position.x)<340 and player.global_position.z> -330 else "MARINA BAY"
	var normal_hud:=not _title_panel.visible and not _pause_panel.visible and not _settings_panel.visible and bool(Game.settings.get("hud_visible",true))
	_prompt_plate.visible=normal_hud and not _prompt_label.text.is_empty()
	_weapon_icon.visible=normal_hud
	_ammo_label.visible=_weapon_icon.visible
	_weapon_label.visible=_weapon_icon.visible
	if not _hotel_status.is_empty():_objective_label.text=_hotel_status
	elif mission: _objective_label.text=_objective_sentence(mission.current_objective())
	for activity in get_tree().get_nodes_in_group("downtown_activity"):
		if activity.has_method("is_active") and activity.is_active(): _objective_label.text=activity.current_objective()
	_minimap.queue_redraw()
	if _debug_label.visible:
		_debug_label.text = "mode=%d stage=%d wanted=%d heat=%.0f hp=%.0f peds=%d" % [
			Game.mode, Game.mission_stage, Game.wanted_level, Game.wanted_heat,
			Game.health, _count_group("npcs")]

func _count_group(name: String) -> int:
	return get_tree().get_nodes_in_group(name).size()

func _draw_crosshair() -> void:
	if player==null or not player.aiming or Game.mode==Game.MODE_HELI: return
	var c := _crosshair.size * 0.5
	var col := Color(0.98, 0.96, 0.90, 0.9)
	_crosshair.draw_line(c + Vector2(-9, 0), c + Vector2(-3, 0), col, 2.0)
	_crosshair.draw_line(c + Vector2(3, 0), c + Vector2(9, 0), col, 2.0)
	_crosshair.draw_line(c + Vector2(0, -9), c + Vector2(0, -3), col, 2.0)
	_crosshair.draw_line(c + Vector2(0, 3), c + Vector2(0, 9), col, 2.0)
	_crosshair.draw_circle(c, 1.5, col)

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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M and not _title_panel.visible and not _settings_panel.visible and not _pause_panel.visible:
			_toggle_map(); get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE and _full_map.visible:
			_toggle_map(); get_viewport().set_input_as_handled()
		elif _full_map.visible:
			get_viewport().set_input_as_handled()
		elif not Game.simulation_paused and event.physical_keycode in [KEY_1,KEY_2]:
			player.equip_weapon("pistol" if event.physical_keycode==KEY_1 else "smg")
			get_viewport().set_input_as_handled()

var navigation: RefCounted
var _full_map: Control
var _city_map: Control
var _gps_label: Label
func _build_map(root: Control) -> void:
	navigation=preload("res://src/systems/city_navigation.gd").new();navigation.setup(world)
	_minimap.navigation=navigation
	_gps_label=_mk_label(root,Vector2(24,460),11,ThemeKit.TEXT);_gps_label.size=Vector2(320,24)
	_gameplay_controls.append(_gps_label)
	_full_map=Control.new();_full_map.size=Vector2(1280,720);root.add_child(_full_map);_full_map.hide()
	_panel(_full_map,Vector2.ZERO,Vector2(1280,720),Color(.94,.95,.96,1))
	_city_map=DetailedMap.new();_city_map.position=Vector2(310,20);_city_map.size=Vector2(950,680)
	_city_map.full_map=true;_city_map.navigation=navigation
	_full_map.add_child(_city_map);_city_map.setup(world,player,mission)
	_mk_label(_full_map,Vector2(24,24),25,Color("233348")).text="SINGAPORE"
	_mk_label(_full_map,Vector2(24,64),12,Color("596979")).text="Choose a destination · M / Esc close"
	var row:=0
	for poi in navigation.points:
		var button:=Button.new();button.text=poi.name;button.position=Vector2(20,104+row*46);button.size=Vector2(275,38)
		ThemeKit.button(button);button.add_theme_font_size_override("font_size",13);_full_map.add_child(button)
		button.pressed.connect(func():navigation.select(poi.position,poi.name);_toggle_map())
		row+=1
	var clear:=Button.new();clear.text="Clear waypoint";clear.position=Vector2(20,650);clear.size=Vector2(275,38);ThemeKit.button(clear);_full_map.add_child(clear)
	clear.pressed.connect(func():navigation.clear();_city_map.queue_redraw())
func _toggle_map() -> void:
	if not _full_map.visible and Game.simulation_paused:return
	_full_map.visible=not _full_map.visible
	Game.simulation_paused=_full_map.visible
	if not _full_map.visible:
		player.suppress_mouse_fire_until_release=true
		player._press_queue.clear()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if _full_map.visible else Input.MOUSE_MODE_CAPTURED
	_city_map.queue_redraw()
