extends CanvasLayer

var box: Control
var items: VBoxContainer
var settings: SettingsPanel


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	box = ColorRect.new()
	(box as ColorRect).color = Color(0.02, 0.018, 0.015, 0.82)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.visible = false
	add_child(box)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -80.0
	col.offset_right = 80.0
	col.offset_top = -50.0
	col.offset_bottom = 50.0
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	box.add_child(col)
	col.add_child(UiKit.label("The wake waits.", 14))
	items = VBoxContainer.new()
	items.add_theme_constant_override("separation", 4)
	col.add_child(items)
	for item in [["Return to the wake", _resume], ["Settings", func(): _settings(true)],
			["Main menu", func(): Game.to_menu()], ["Leave", func(): get_tree().quit()]]:
		var b := UiKit.button(item[0])
		var f: Callable = item[1]
		b.pressed.connect(func():
			Sounds.play(Game, Sounds.UI_SELECT, -6.0)
			f.call())
		items.add_child(b)
	settings = SettingsPanel.new()
	settings.visible = false
	settings.back.connect(func(): _settings(false))
	col.add_child(settings)


func _settings(on: bool) -> void:
	items.visible = not on
	settings.visible = on
	if on:
		settings.focus()
	else:
		(items.get_child(0) as Button).grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if not e.is_action_pressed("pause"):
		return
	if box.visible:
		if settings.visible:
			_settings(false)
		else:
			_resume()
	elif Game.state != Game.State.ATTACK:   # also on the morning / game-over screens
		_open()
	get_viewport().set_input_as_handled()


func _open() -> void:
	box.visible = true
	_settings(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sounds.play(self, Sounds.UI_OPEN, -8.0)
	var first := box.find_children("*", "Button", true, false)
	if not first.is_empty():
		(first[0] as Button).grab_focus()


func _resume() -> void:
	box.visible = false
	get_tree().paused = false
	if Game.state == Game.State.PLAY:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sounds.play(self, Sounds.UI_CLOSE, -8.0)
