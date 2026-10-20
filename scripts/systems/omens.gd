extends Node

@onready var heart: AudioStreamPlayer = $Heartbeat

var level: Node3D
var danger := false
var lit_before := -1
var wake_was := false


func _ready() -> void:
	add_to_group("debug")
	level = get_node("../../Level")
	Game.night_lost.connect(lost)


func lost(reason: String) -> void:
	if reason == "double" or reason == "left" or reason in Game.SCARE_DEATHS:
		return   # the creature already did the scaring (attack.gd)
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
	# the mirror has its own heartbeat (blind.gd) and no violin; this one is
	# for the wake falling silent and the candles going out
	var wake_danger := Game.state == Game.State.PLAY and (v < 25.0 or c <= 1)
	if wake_danger and not wake_was:
		Sounds.play(self, Sounds.VIOLIN_RISE, -6.0)   # things are slipping
	wake_was = wake_danger
	if Game.state == Game.State.PLAY and lit_before > 0 and c == 0:
		Sounds.play(self, Sounds.VIOLIN_STING, -3.0)   # the last candle just died
	lit_before = c
	if heart.stream:
		if wake_danger and not heart.playing:
			heart.play()
		elif not wake_danger and heart.playing:
			heart.stop()


func debug_line() -> String:
	return "danger %s" % danger
