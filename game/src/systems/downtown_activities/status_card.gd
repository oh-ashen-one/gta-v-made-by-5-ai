extends CanvasLayer
## Separate from the story objective: the optional errand never steals its
## minimap marker, stage events, or save checkpoint.
var activity: Node
var _root: Control
var _panel: Panel
var _body: Label
var _marker: Label
var _refresh_time := 0.0

func setup(owner_activity: Node) -> void:
	activity = owner_activity
	layer = 2
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = Panel.new()
	_panel.position = Vector2(24, 112)
	_panel.size = Vector2(432, 100)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.058, 0.9)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)
	var heading := Label.new()
	heading.text = "BAYFRONT COURIER  ·  OPTIONAL"
	heading.position = Vector2(14, 8)
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Color(0.57, 0.78, 0.70))
	_panel.add_child(heading)
	_body = Label.new()
	_body.position = Vector2(14, 28)
	_body.size = Vector2(408, 68)
	_body.add_theme_font_size_override("font_size", 15)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_body)
	_marker = Label.new()
	_marker.add_theme_font_size_override("font_size", 16)
	_marker.add_theme_color_override("font_color", Color(0.55, 1.0, 0.79))
	_marker.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.04))
	_marker.add_theme_constant_override("outline_size", 6)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_marker)
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	_root.scale = get_viewport().get_visible_rect().size / Vector2(1280, 720)

func _process(delta: float) -> void:
	if not activity or not is_instance_valid(activity.player): return
	var show := not Game.simulation_paused and bool(Game.settings.get("hud_visible", true))
	_root.visible = show
	if not show: return
	var actor: Node3D = activity.player.controlled_actor()
	var distance: float = actor.global_position.distance_to(activity.objective_position())
	_panel.visible = activity.is_active() or distance < 100.0
	_marker.visible = _panel.visible
	_refresh_time -= delta
	if _refresh_time <= 0.0:
		_refresh_time = 0.2
		var hint := "Walk, drive or fly · step out and press E at the ring."
		if activity.stage == activity.Stage.OUTBOUND: hint = "Return the parcel at Heritage Waterfront to cancel."
		_body.text = "%s\n%d m · %s" % [activity.current_objective(), roundi(distance), hint]
	if not _marker.visible: return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var target: Vector3 = activity.objective_position() + Vector3(0, 3.2, 0)
	var projected := camera.unproject_position(target) / _root.scale
	var behind := camera.is_position_behind(target)
	if behind: projected = Vector2(1280, 720) - projected
	_marker.text = "◇ COURIER  %d m%s" % [roundi(distance), " · turn around" if behind else ""]
	_marker.position = Vector2(clampf(projected.x - 90, 250, 1000), clampf(projected.y - 14, 240, 580))
