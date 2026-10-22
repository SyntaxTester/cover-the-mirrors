extends Control

const BG := preload("res://assets/ui/menu_frame.png")
## The same frame with someone standing by the cross. Shown for a blink, rarely.
const BG_ALT := preload("res://assets/ui/menu_frame_alt.png")

var main_box: VBoxContainer
var settings_box: SettingsPanel
var music: AudioStreamPlayer
var flick := 0.0
var bg: TextureRect
var scare_in := randf_range(18.0, 34.0)
var scare_t := 0.0


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	bg = TextureRect.new()
	bg.texture = BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # keep the PS1 pixels sharp
	bg.modulate = Color(0.95, 0.9, 0.86)
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.025, 0.02, 0.25)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 28.0
	col.offset_right = 230.0
	col.offset_top = 16.0
	col.add_theme_constant_override("separation", 2)
	add_child(col)
	var t1 := UiKit.label("COVER", 24)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var t2 := UiKit.label("THE MIRRORS", 18, UiKit.ACCENT)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(t1)
	col.add_child(t2)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap)
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 0)
	col.add_child(main_box)
	_add(main_box, "Begin the wake", func(): _start(0))
	_add(main_box, "Night two", func(): _start(1))
	_add(main_box, "Night three", func(): _start(2))
	_add(main_box, "Settings", func(): _show_settings(true))
	_add(main_box, "Leave", func(): get_tree().quit())
	settings_box = SettingsPanel.new()
	settings_box.visible = false
	settings_box.back.connect(func(): _show_settings(false))
	col.add_child(settings_box)
	var hint := UiKit.label("Esmagzam Studios", 8, UiKit.DIM)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -14.0
	hint.offset_bottom = -3.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.offset_right = -10.0
	add_child(hint)
	music = AudioStreamPlayer.new()
	music.stream = Sounds.looped(Sounds.MUSIC_MORNING)
	music.volume_db = -12.0
	music.bus = "Master"
	add_child(music)
	music.play()
	(main_box.get_child(0) as Button).grab_focus()


func _add(box: VBoxContainer, text: String, f: Callable) -> void:
	var b := UiKit.button(text, 10)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		Sounds.play(Game, Sounds.UI_SELECT, -6.0)
		f.call())
	box.add_child(b)


func _show_settings(on: bool) -> void:
	main_box.visible = not on
	settings_box.visible = on
	if on:
		settings_box.focus()
	else:
		(main_box.get_child(0) as Button).grab_focus()


func _start(n: int) -> void:
	Game.start_from_menu(n)


func _process(dt: float) -> void:
	flick += dt
	var f := 0.92 + 0.06 * sin(flick * 7.0) + 0.03 * sin(flick * 13.0)
	bg.modulate = Color(f + 0.03, f, f - 0.04)
	# once in a long while, for a moment, someone is standing by the cross
	if scare_t > 0.0:
		scare_t -= dt
		if scare_t <= 0.0:
			bg.texture = BG
	elif not settings_box.visible:
		scare_in -= dt
		if scare_in <= 0.0:
			scare_in = randf_range(25.0, 50.0)
			scare_t = randf_range(0.12, 0.25)
			bg.texture = BG_ALT
