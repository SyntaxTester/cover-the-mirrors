extends Node

var dark := 0.0


func _ready() -> void:
	add_to_group("debug")


func _process(dt: float) -> void:
	if Game.state != Game.State.PLAY:
		return
	var all := get_tree().get_nodes_in_group("coffin_candles")
	if all.is_empty() or lit_count() > 0:
		dark = 0.0
		return
	dark += dt
	if dark >= Game.cfg().dark_grace:
		Game.lose("candles")


func lit_count() -> int:
	var k := 0
	for c in get_tree().get_nodes_in_group("coffin_candles"):
		if c.lit:
			k += 1
	return k


func debug_line() -> String:
	var n := get_tree().get_nodes_in_group("coffin_candles").size()
	return "свечи %d/%d  темно %.1f" % [lit_count(), n, dark]
