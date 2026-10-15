extends Node3D

@onready var light: OmniLight3D = $Light
@onready var flames: Node3D = $Flames

var base := 0.0
var ph := 0.0


func _ready() -> void:
	base = light.light_energy


func _process(dt: float) -> void:
	ph += dt
	light.light_energy = base * (0.82 + 0.1 * sin(ph * 7.0) + 0.06 * sin(ph * 13.3) + 0.04 * sin(ph * 2.1))
	var i := 0
	for f in flames.get_children():
		f.scale = Vector3(1.0, 0.8 + 0.25 * sin(ph * (6.0 + i * 1.7) + i), 1.0)
		i += 1
