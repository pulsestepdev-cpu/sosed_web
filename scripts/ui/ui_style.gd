class_name UiStyle
extends RefCounted
## Общий вид интерфейса: тёплые «деревянные» кнопки и панели в стиле обложки.

const C_TEXT := Color("fff1d0")
const C_TITLE := Color("ffcf5a")
const C_OUTLINE := Color("3a1b0c")
const C_PANEL := Color(0.18, 0.09, 0.04, 0.93)

static func box(bg: Color, border: Color, radius := 18, bw := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 5)
	return sb

static func button(text: String, size := 44, width := 420.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, size * 1.9)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("ffe08a"))
	b.add_theme_color_override("font_outline_color", C_OUTLINE)
	b.add_theme_constant_override("outline_size", 10)
	b.add_theme_stylebox_override("normal", box(Color("b5541b"), Color("ffd27a")))
	b.add_theme_stylebox_override("hover", box(Color("d8691f"), Color("fff0b0")))
	b.add_theme_stylebox_override("pressed", box(Color("8f3f12"), Color("ffd27a")))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(func(): Settings.sfx("click", 0.25, 1.3))
	b.pressed.connect(func(): Settings.sfx("click", 0.8))
	return b

static func label(text: String, size: int, color := C_TEXT, outline := 10) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", C_OUTLINE)
	l.add_theme_constant_override("outline_size", outline)
	return l

static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(C_PANEL, Color("e0a24a"), 24, 5)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 30
	sb.content_margin_bottom = 34
	p.add_theme_stylebox_override("panel", sb)
	return p
