extends Node

@onready var murmur: AudioStreamPlayer = $Murmur

var vigil := 0.0


func _ready() -> void:
	add_to_group("vigil")
	add_to_group("debug")
	vigil = Config.vigil_start


func _process(dt: float) -> void:
	if Game.state != Game.State.PLAY:
		return
	var v = get_tree().get_first_node_in_group("visitors")
	var awake: int = v.awake_count() if v else 0
	vigil += (awake * Game.cfg().vigil_per_guest - Game.cfg().vigil_drain) * dt
	vigil = clampf(vigil, 0.0, 100.0)
	#wmurmur.volume_db = linear_to_db(maxf(vigil / 100.0, 0.001))
	if vigil <= 0.0:
		Game.lose("vigil")


func penalty() -> void:
	vigil -= Config.expel_penalty


func debug_line() -> String:
	return "vigil %.0f" % vigil
