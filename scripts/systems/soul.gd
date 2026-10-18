extends Node

var soul := 0.0


func _ready() -> void:
	add_to_group("debug")


func _process(dt: float) -> void:
	if Game.state != Game.State.PLAY:
		return
	var open := 0.0   # 1 = a mirror drawn back, 0.25 = a cloth that slipped
	for m in get_tree().get_nodes_in_group("mirrors"):
		if m.lifted:
			open = 1.0
		elif m.slipped:
			open = maxf(open, 0.25)   # a slipped cloth: there's time to fix it, not forever
	if open > 0.0:
		soul += Game.cfg().soul_up * open * dt
	else:
		soul -= Game.cfg().soul_down * dt
	soul = clampf(soul, 0.0, 100.0)
	if soul >= 100.0:
		Game.lose("soul")


func debug_line() -> String:
	return "soul %.0f" % soul
