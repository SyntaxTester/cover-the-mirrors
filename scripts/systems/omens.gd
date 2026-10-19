extends Node

@onready var heart: AudioStreamPlayer = $Heartbeat

var level: Node3D
var danger := false
var lit_before := -1


func _ready() -> void:
	add_to_group("debug")
	level = get_node("../../Level")
	Game.night_lost.connect(lost)


func lost(reason: String) -> void:
	if reason == "double":
		return
	Sounds.play(self, Sounds.JUMPSCARE, 0.0)
	if reason == "candles":
		level.get_node("Outside/Face").visible = true
	else:
		level.get_node("CoffinRoom/Corpse").sit()


func _process(_dt: float) -> void:
	var v: float = get_node("../Vigil").vigil
	var s: float = get_node("../Soul").soul
	var c: int = get_node("../Candles").lit_count()
	var was := danger
	danger = Game.state == Game.State.PLAY and (v < 25.0 or s > 60.0 or c <= 1)
	if danger and not was:
		Sounds.play(self, Sounds.VIOLIN_RISE, -6.0)   # things are slipping
	if Game.state == Game.State.PLAY and lit_before > 0 and c == 0:
		Sounds.play(self, Sounds.VIOLIN_STING, -3.0)   # the last candle just died
	lit_before = c
	if heart.stream:
		if danger and not heart.playing:
			heart.play()
		elif not danger and heart.playing:
			heart.stop()


func debug_line() -> String:
	return "danger %s" % danger
