extends CanvasLayer

const LOSE := {
	"candles": "The candles went out.",
	"soul": "You looked into the mirror for too long.",
	"vigil": "The wake fell silent.",
	"double": "It reached the coffin. Then it came for you.",
}
const TYPE_SPEED := 24.0          # subtitle letters per second
const TITLES := {
	"double": "It found you.",
	"candles": "The dark came in.",
	"soul": "The glass took you.",
	"vigil": "The dead man sat up.",
}
const NIGHT_MUSIC_DB := -14.0
const NIGHT_MUSIC_FOR := 70.0     # the folk tune opens the night, then leaves the house to its sounds

@onready var hint: Label = $Hint
@onready var dbg: Label = $Debug
@onready var dot: Control = $Dot
@onready var intro: Label = $Intro
@onready var end: Control = $End
@onready var title: Label = $End/Title
@onready var sub: Label = $End/Sub
@onready var subtitle: Label = $Subtitle

var intro_t := 0.0
var sub_t := 0.0
var typing := false
var type_pos := 0.0
var music: AudioStreamPlayer
var text_snd: AudioStreamPlayer
var music_tween: Tween
var questions: Label


func _ready() -> void:
	add_to_group("hud")
	end.visible = false
	dbg.visible = false
	intro.modulate.a = 0.0
	subtitle.text = ""
	sub.offset_bottom = 125.0
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	questions = Label.new()   # what you can ask through the hatch
	questions.add_theme_font_size_override("font_size", 9)
	questions.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74))
	questions.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	questions.add_theme_constant_override("outline_size", 2)
	questions.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	questions.offset_left = 8.0
	questions.offset_top = -100.0
	questions.offset_right = 230.0
	questions.offset_bottom = -40.0
	questions.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(questions)
	music = AudioStreamPlayer.new()
	music.bus = "Master"
	add_child(music)
	text_snd = AudioStreamPlayer.new()
	text_snd.stream = Sounds.looped(Sounds.TEXT)
	text_snd.volume_db = -16.0
	text_snd.bus = "SFX"
	add_child(text_snd)
	Game.night_started.connect(started)
	Game.night_lost.connect(lost)
	Game.night_won.connect(won)


func set_hint(s: String) -> void:
	hint.text = s


func set_questions(s: String) -> void:
	if questions.text != s:
		questions.text = s


## Subtitle that types itself out, with the typing sound while it does.
func say(who: String, text: String) -> void:
	subtitle.text = "%s: %s" % [who, text]
	type_pos = who.length() + 2.0   # the name appears at once
	subtitle.visible_characters = int(type_pos)
	typing = true
	sub_t = Config.subtitle_time + text.length() / TYPE_SPEED
	if not text_snd.playing:
		text_snd.play(randf() * 6.0)


func started(n: int) -> void:
	intro.text = "Night %d\n%s" % [n + 1, Game.clock()]
	intro_t = 4.0
	Sounds.play(self, Sounds.UI_OPEN, -8.0)


func lost(reason: String) -> void:
	dot.visible = false
	hint.text = ""
	_fade_music(0.4)
	await get_tree().create_timer(Config.end_delay).timeout
	show_end(TITLES.get(reason, "The dead man sat up."), "%s\n\nR - try again    M - main menu" % LOSE.get(reason, reason))


func won(n: int) -> void:
	_music(Sounds.MUSIC_MORNING, -6.0, 4.0)
	questions.text = ""
	var v = get_tree().get_first_node_in_group("visitors")
	var lines := PackedStringArray()
	if v:
		for l in v.report:
			lines.append(l)
	lines.append("Doubles let in tonight: %d of %d" % [Game.doubles_let, Game.doubles_total])
	if Game.is_last():
		var e := ending()
		lines.insert(0, e[1])
		lines.insert(1, EPILOGUE)
		show_end(e[0], "%s\n\nR - start over" % "\n".join(lines))
	else:
		show_end("Morning.", "Night %d survived\n%s\n\nE - next night   R - restart" % [n + 1, "\n".join(lines)])


const EPILOGUE := "The sexton had dug two graves by the chapel wall. The second stone read: Ronan Donnelly."


## The last morning: what the parish remembers about this wake.
func ending() -> Array:
	var r: Dictionary = Game.run
	if r.corpse_stage >= 2:
		return ["The lid was nailed down in a hurry.",
			"Twice they reached him. The priest would not say what he saw in the coffin."]
	if r.doubles_left_inside >= 2:
		return ["More walked behind the coffin than were ever let in.",
			"Some of the mourners at the funeral had come a long way. Further than the bog road."]
	if r.lost.size() >= 2 or r.humans_refused >= 3:
		return ["Fewer at the funeral than at the wake.",
			"You kept the dead out. You kept the living out too: %s." % ", ".join(r.lost)]
	return ["They carried him to the churchyard with the whole parish behind.",
		"Not one of the other crowd sat with him. He went to his rest in peace."]


func show_end(a: String, b: String) -> void:
	title.text = a
	sub.text = b
	end.visible = true
	dot.visible = false
	hint.text = ""
	Sounds.play(self, Sounds.UI_OPEN, -4.0)


func _music(s: AudioStream, db: float, fade_in: float) -> void:
	if music_tween:
		music_tween.kill()
	music.stream = s
	music.volume_db = -40.0
	music.play()
	music_tween = create_tween()
	music_tween.tween_property(music, "volume_db", db, fade_in)


func _fade_music(t: float) -> void:
	if not music.playing:
		return
	if music_tween:
		music_tween.kill()
	music_tween = create_tween()
	music_tween.tween_property(music, "volume_db", -40.0, t)
	music_tween.tween_callback(music.stop)


func _process(dt: float) -> void:
	if typing:
		type_pos += dt * TYPE_SPEED
		subtitle.visible_characters = int(type_pos)
		if type_pos >= subtitle.text.length():
			typing = false
			subtitle.visible_characters = -1
			text_snd.stop()
	if sub_t > 0.0:
		sub_t -= dt
		if sub_t <= 0.0:
			subtitle.text = ""
			typing = false
			text_snd.stop()
	if intro_t > 0.0:
		intro_t -= dt
		intro.modulate.a = clampf(intro_t, 0.0, 1.0)
	if dbg.visible:
		var s := "night %d  %s  %.0f/%.0f s  fps %d" % [Game.night + 1, Game.clock(), Game.t, Game.cfg().duration, Engine.get_frames_per_second()]
		for n in get_tree().get_nodes_in_group("debug"):
			s += "\n" + n.debug_line()
		dbg.text = s


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("debug"):
		dbg.visible = not dbg.visible
	elif e.is_action_pressed("debug_skip") and dbg.visible:
		Game.t += 30.0
	elif end.visible and e.is_action_pressed("restart"):
		Sounds.play(Game, Sounds.UI_SELECT, -4.0)   # on the autoload: survives the reload
		if Game.state == Game.State.WON and Game.is_last():
			Game.new_game()
		else:
			Game.restart()
	elif end.visible and e is InputEventKey and e.pressed and (e as InputEventKey).physical_keycode == KEY_M:
		Game.to_menu()
	elif end.visible and e.is_action_pressed("interact") and Game.state == Game.State.WON and not Game.is_last():
		Sounds.play(Game, Sounds.UI_SELECT, -4.0)
		Game.next_night()
