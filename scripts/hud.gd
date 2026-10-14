extends CanvasLayer

const LOSE := {
	"candles": "Свечи погасли.",
	"soul": "Ты смотрел в зеркало слишком долго.",
	"vigil": "Бдение прервалось.",
	"double": "Чужой подошёл к гробу.",
}

@onready var hint: Label = $Hint
@onready var dbg: Label = $Debug
@onready var dot: Control = $Dot
@onready var intro: Label = $Intro
@onready var end: Control = $End
@onready var title: Label = $End/Title
@onready var sub: Label = $End/Sub

var intro_t := 0.0


func _ready() -> void:
	add_to_group("hud")
	end.visible = false
	dbg.visible = false
	intro.modulate.a = 0.0
	Game.night_started.connect(started)
	Game.night_lost.connect(lost)
	Game.night_won.connect(won)


func set_hint(s: String) -> void:
	hint.text = s


func started(n: int) -> void:
	intro.text = "Ночь %d\n%s" % [n + 1, Game.clock()]
	intro_t = 4.0


func lost(reason: String) -> void:
	show_end("Покойник сел.", "%s\n\nR - заново" % LOSE.get(reason, reason))


func won(n: int) -> void:
	if Game.is_last():
		show_end("Утро. Похороны.", "R - сначала")
	else:
		show_end("Утро.", "Ночь %d пережита\n\nE - следующая ночь   R - заново" % (n + 1))


func show_end(a: String, b: String) -> void:
	title.text = a
	sub.text = b
	end.visible = true
	dot.visible = false
	hint.text = ""


func _process(dt: float) -> void:
	if intro_t > 0.0:
		intro_t -= dt
		intro.modulate.a = clampf(intro_t, 0.0, 1.0)
	if dbg.visible:
		var s := "ночь %d  %s  %.0f/%.0f с  fps %d" % [Game.night + 1, Game.clock(), Game.t, Game.cfg().duration, Engine.get_frames_per_second()]
		for n in get_tree().get_nodes_in_group("debug"):
			s += "\n" + n.debug_line()
		dbg.text = s


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("debug"):
		dbg.visible = not dbg.visible
	elif e.is_action_pressed("debug_skip") and dbg.visible:
		Game.t += 30.0
	elif end.visible and e.is_action_pressed("restart"):
		if Game.state == Game.State.WON and Game.is_last():
			Game.new_game()
		else:
			Game.restart()
	elif end.visible and e.is_action_pressed("interact") and Game.state == Game.State.WON and not Game.is_last():
		Game.next_night()
