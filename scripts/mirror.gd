extends Interactable

@onready var cloth: Node3D = $Cloth

var lifted := false
var k := 0.0
var cloth_y := 0.0


func _ready() -> void:
	prompt = "Приподнять ткань"
	hold = true
	add_to_group("mirrors")
	cloth_y = cloth.position.y


func interact(_p: Node) -> void:
	lifted = true


func release(_p: Node) -> void:
	lifted = false


func _process(dt: float) -> void:
	k = move_toward(k, 1.0 if lifted else 0.0, dt * 4.0)
	cloth.position.y = cloth_y + k * 0.42
	cloth.scale.y = 1.0 - k * 0.7
