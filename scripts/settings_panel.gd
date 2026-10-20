class_name SettingsPanel
extends VBoxContainer
## Mouse sensitivity and volume, shared by the main menu and the pause menu.
## Changes apply at once and are remembered between sessions (Config).

signal back

var first: Control


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_slider("Mouse sensitivity", 0.0005, 0.006, Config.mouse_sens, func(v):
		Config.mouse_sens = v
		Config.save_settings())
	_slider("Volume", 0.0, 1.0, Config.volume, func(v):
		Config.volume = v
		Config.apply_settings()
		Config.save_settings())
	var b := UiKit.button("Back", 10)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		Sounds.play(Game, Sounds.UI_SELECT, -6.0)
		back.emit())
	add_child(b)


func _slider(text: String, lo: float, hi: float, v: float, f: Callable) -> void:
	var l := UiKit.label(text, 9, UiKit.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(l)
	var s := UiKit.slider(lo, hi, v)
	s.value_changed.connect(f)
	add_child(s)
	if first == null:
		first = s


func focus() -> void:
	if first:
		first.grab_focus()
