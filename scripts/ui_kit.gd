class_name UiKit
extends RefCounted

const INK := Color(0.9, 0.85, 0.76)
const DIM := Color(0.62, 0.57, 0.5)
const ACCENT := Color(0.89, 0.66, 0.34)


static func label(text: String, size: int, col := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func button(text: String, size := 11) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.add_theme_color_override("font_pressed_color", INK)
	b.mouse_entered.connect(func(): Sounds.play(b, Sounds.UI_SELECT, -18.0))
	return b


static func slider(min_v: float, max_v: float, v: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = (max_v - min_v) / 100.0
	s.value = v
	s.custom_minimum_size = Vector2(110, 10)
	return s
