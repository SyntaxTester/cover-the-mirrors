extends AudioStreamPlayer

var rings := 0


func _ready() -> void:
	add_to_group("debug")
	Game.bell.connect(ring)


func ring() -> void:
	rings += 1
	if stream:
		play()


func debug_line() -> String:
	return "колокол %d" % rings
