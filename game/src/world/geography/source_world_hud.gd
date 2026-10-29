extends "res://src/ui/hud.gd"
## Production health/ammo/controls shell with source geometry navigation.
## Legacy fictional minimap, mission restart and v1 save callbacks are absent.
var source_world: Node3D

func setup_source(owner: Node3D, actor: Player) -> void:
	source_world = owner
	super.setup(null, actor, null)
	for child: Node in _layout_root.get_children():
		if child is Label and child.text == "HARBOUR RELAY": child.text = "SINGAPORE"
	_objective_label.text = "Explore the city · E enter or exit · Esc controls"
	_title_panel.visible = false
	set_gameplay_visible(true)

func _build_pause_panel(root: Control) -> void:
	_pause_panel = Control.new()
	_pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	root.add_child(_pause_panel)
	_panel(_pause_panel,Vector2.ZERO,Vector2(1280,720),Color(.015,.035,.038,.92))
	var heading := _mk_label(_pause_panel,Vector2(96,110),42,Color(.97,.94,.86))
	heading.text = "Singapore"
	_button(_pause_panel,"Resume · Esc",Vector2(96,210),func(): source_world._toggle_pause())
	_button(_pause_panel,"Settings · F3",Vector2(96,270),func(): source_world._toggle_settings())
	_button(_pause_panel,"Quit game",Vector2(96,330),func(): source_world._quit_game())
	var controls := _mk_label(_pause_panel,Vector2(570,190),17,Color(.78,.85,.82))
	controls.text = "ON FOOT\nWASD move · Shift sprint · Space jump\nMouse look · RMB aim · LMB fire\nR reload · Q weapon · E interact\n\nCAR\nW/S throttle · A/D steer · Space brake · E exit\n\nHELICOPTER\nW/S forward/back · A/D turn\nSpace climb · Shift descend · E exit after landing"

func _build_title_panel(root: Control) -> void:
	_title_panel = Control.new()
	_title_panel.visible = false
	root.add_child(_title_panel)

func _draw_minimap() -> void:
	if not is_instance_valid(source_world) or not is_instance_valid(player): return
	_minimap.draw_rect(Rect2(Vector2.ZERO,_minimap.size),Color(.035,.065,.075,.88))
	var position: Dictionary = source_world.canonical_actor_position()
	if not position.get("ok",false): return
	var center: Array = position.source_xyz
	var scale := .34
	var project := func(point: Array) -> Vector2:
		# Canonical subtraction precedes the small native 2D display vector.
		return Vector2((float(point[0])-float(center[0]))*scale,(float(point[2])-float(center[2]))*scale)+_minimap.size*.5
	for line: Dictionary in source_world.minimap_lines:
		var bounds: Array = line.bounds_xz
		if float(bounds[2]) < float(center[0])-320.0 or float(bounds[0]) > float(center[0])+320.0 or float(bounds[3]) < float(center[2])-320.0 or float(bounds[1]) > float(center[2])+320.0: continue
		var points: Array = line.points
		for i in range(1,points.size()):
			var a: Vector2 = project.call(points[i-1])
			var b: Vector2 = project.call(points[i])
			if Rect2(Vector2(-8,-8),_minimap.size+Vector2(16,16)).intersects(Rect2(a,Vector2(.01,.01)).expand(b)):
				_minimap.draw_line(a,b,Color(.64,.70,.67),1.4)
	_minimap.draw_circle(_minimap.size*.5,4,Color(.97,.82,.48))
	# X south / -Z east: north is -X, not a borrowed US-city map grid.
	_minimap.draw_string(ThemeDB.fallback_font,Vector2(8,17),"N ←",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(.88,.91,.87))
