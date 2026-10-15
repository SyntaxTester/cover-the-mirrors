extends Node

@onready var heart: AudioStreamPlayer = $Heartbeat

var level: Node3D
var danger := false


func _ready() -> void:
	add_to_group("debug")
	level = get_node("../../Level")
	Game.night_lost.connect(lost)


func lost(reason: String) -> void:
	if reason == "candles":
		level.get_node("Outside/Face").visible = true
	else:
		level.get_node("CoffinRoom/Corpse").sit()


func _process(_dt: float) -> void:
	var v: float = get_node("../Vigil").vigil
	var s: float = get_node("../Soul").soul
	var c: int = get_node("../Candles").lit_count()
	danger = Game.state == Game.State.PLAY and (v < 25.0 or s > 60.0 or c <= 1)
	if heart.stream:
		if danger and not heart.playing:
			heart.play()
		elif not danger and heart.playing:
			heart.stop()


func debug_line() -> String:
	return "danger %s" % danger
