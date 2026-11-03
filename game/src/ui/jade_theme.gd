extends RefCounted
## Native UI translation of the selected 01-jade concept.
const INK := Color("101918")
const PANEL := Color(0.045, 0.075, 0.069, 0.94)
const TEXT := Color("f2f1e9")
const MUTED := Color("9eafa7")
const JADE := Color("99d8ae")
const LINE := Color(0.61, 0.78, 0.68, 0.23)
const AMBER := Color("edb85d")

static func box(color: Color = PANEL, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = LINE
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

static func button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(Color(0.08,0.12,0.105,0.95)))
	b.add_theme_stylebox_override("hover", box(Color(0.15,0.24,0.18,1)))
	b.add_theme_stylebox_override("pressed", box(Color(0.23,0.34,0.26,1)))
	var focus := box(Color.TRANSPARENT)
	focus.border_color = JADE
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", JADE)
	b.add_theme_font_size_override("font_size", 16)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func toggle(b: CheckButton) -> void:
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", JADE)
	b.add_theme_color_override("font_pressed_color", JADE)
	b.add_theme_stylebox_override("focus", box(Color(0.13,0.21,0.16,0.9)))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
