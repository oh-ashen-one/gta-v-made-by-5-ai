extends Control
## Raster weapon artwork and selection plates; native labels remain live game data.
const Art := preload("res://src/ui/hud_art.gd")
const ThemeKit := preload("res://src/ui/jade_theme.gd")
var expanded := false
var selected := "pistol"
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	size=Vector2(244,244)
func update_hover() -> void:
	var local:=get_local_mouse_position()-size*.5
	if local.length()<=118.0 and local.length()>=18.0:
		selected="pistol" if local.y<0 else "smg"
	queue_redraw()
func _draw() -> void:
	var c:=size*.5
	var r:=118.0 if expanded else 100.0
	var scale:=r/100.0
	var chosen: String=selected if expanded else Game.carried_weapon
	var plate:=Art.texture("wheel_"+chosen)
	if plate:draw_texture_rect(plate,Rect2(c-Vector2.ONE*r,Vector2.ONE*r*2),false)
	for i in 2:
		var id: String="pistol" if i==0 else "smg"
		var icon:=Art.texture(id)
		var area:=Rect2(c+Vector2(-58,-85 if i==0 else 26)*scale,Vector2(116,54)*scale)
		if icon:draw_texture_rect(icon,Art.fit(icon,area),false,Color.WHITE if chosen==id else Color(.68,.73,.71,.9))
		var label:=id.to_upper()
		var font:=ThemeDB.fallback_font
		var font_size:=13 if expanded else 11
		var width:=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		draw_string(font,c+Vector2(-width*.5,(-18 if i==0 else 91)*scale),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,ThemeKit.TEXT if chosen==id else ThemeKit.MUTED)
	if expanded:
		draw_string(ThemeDB.fallback_font,c+Vector2(-10,4),"TAB",HORIZONTAL_ALIGNMENT_LEFT,-1,9,ThemeKit.TEXT)
	else:
		draw_string(ThemeDB.fallback_font,Vector2(69,239),"HOLD TAB · SELECT",HORIZONTAL_ALIGNMENT_LEFT,-1,10,ThemeKit.MUTED)
