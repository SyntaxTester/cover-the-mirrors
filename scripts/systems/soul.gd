extends Node

var soul := 0.0


func _ready() -> void:
	add_to_group("debug")


func _process(dt: float) -> void:
	if Game.state != Game.State.PLAY:
		return
	var open := false
	for m in get_tree().get_nodes_in_group("mirrors"):
		if m.lifted:
			open = true
	if open:
		soul += Game.cfg().soul_up * dt
	else:
		soul -= Game.cfg().soul_down * dt
	soul = clampf(soul, 0.0, 100.0)
	if soul >= 100.0:
		Game.lose("soul")


func debug_line() -> String:
	return "soul %.0f" % soul
