extends Node3D

@onready var player: Node3D = $Player
@onready var level: Node3D = $Level


func _ready() -> void:
	var sp := level.get_node_or_null("Markers/Spawn") as Node3D
	if sp:
		player.global_transform = sp.global_transform
	Game.start_night(Game.night)
