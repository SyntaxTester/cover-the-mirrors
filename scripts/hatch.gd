extends Interactable

signal toggled(open: bool)

@onready var lid: Node3D = $Lid

var open := false
var k := 0.0
var x0 := 0.0


func _ready() -> void:
	add_to_group("hatch")
	x0 = lid.position.x


func get_prompt() -> String:
	return "Закрыть окошко" if open else "Открыть окошко"


func interact(_p: Node) -> void:
	open = not open
	toggled.emit(open)


func _process(dt: float) -> void:
	k = move_toward(k, 1.0 if open else 0.0, dt * 5.0)
	lid.position.x = x0 + k * 0.22
