extends Control
## Two real inventory slots. Hold Tab, point at a half, release to equip.
const ThemeKit := preload("res://src/ui/jade_theme.gd")
var expanded := false
var selected := "pistol"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(180,180)

func update_hover() -> void:
	var local := get_local_mouse_position() - size * 0.5
	if local.length() <= 94.0 and local.length() >= 14.0:
		selected = "pistol" if local.y < 0 else "smg"
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := 86.0 if expanded else 40.0
	var font := ThemeDB.fallback_font
	for half in 2:
		var weapon := "pistol" if half == 0 else "smg"
		var start := PI if half == 0 else 0.0
		var points := PackedVector2Array([c])
		for step in 33:
			points.append(c + Vector2.from_angle(start + PI * float(step)/32.0) * r)
		var chosen := (selected if expanded else Game.carried_weapon) == weapon
		draw_colored_polygon(points, Color(0.21,0.34,0.25,0.97) if chosen else ThemeKit.PANEL)
		draw_arc(c,r,start,start+PI,48,ThemeKit.JADE if chosen else ThemeKit.LINE,1.5,true)
		var at := c + Vector2(0,-37 if half == 0 else 35) * (1.0 if expanded else 0.5)
		_draw_weapon(at,weapon,1.0 if expanded else 0.65,ThemeKit.TEXT if chosen else ThemeKit.MUTED)
		if expanded:
			var label := weapon.to_upper()
			draw_string(font,at+Vector2(-font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x/2,24),label,HORIZONTAL_ALIGNMENT_LEFT,-1,11,ThemeKit.TEXT)
	draw_line(c-Vector2(r,0),c+Vector2(r,0),ThemeKit.LINE,1,true)
	draw_circle(c,7 if expanded else 4,ThemeKit.INK)
	if not expanded:
		draw_string(font,c+Vector2(-32,60),"TAB  WEAPONS",HORIZONTAL_ALIGNMENT_LEFT,-1,9,ThemeKit.MUTED)

func _draw_weapon(at: Vector2, weapon: String, s: float, color: Color) -> void:
	# Crisp vector silhouettes remain legible at all viewport scales.
	var silhouette := PackedVector2Array()
	var pts := [Vector2(-21,-7),Vector2(23,-7),Vector2(23,1),Vector2(2,1),Vector2(-1,14),Vector2(-13,14),Vector2(-10,1),Vector2(-21,1)]
	if weapon == "smg":
		pts = [Vector2(-27,-6),Vector2(15,-6),Vector2(15,-3),Vector2(29,-3),Vector2(29,1),Vector2(12,1),Vector2(9,14),Vector2(1,14),Vector2(0,2),Vector2(-9,2),Vector2(-12,12),Vector2(-20,12),Vector2(-17,1),Vector2(-27,1)]
	for p in pts: silhouette.append(at+p*s)
	draw_colored_polygon(silhouette,color)
