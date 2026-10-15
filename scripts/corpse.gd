extends Node3D

@onready var torso: Node3D = $Torso

var up := false
var k := 0.0


func sit() -> void:
	up = true


func _process(dt: float) -> void:
	if up and k < 1.0:
		k = minf(k + dt * 1.2, 1.0)
		torso.rotation.z = -1.35 * ease(k, 0.4)
