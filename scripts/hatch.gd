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
	var v = get_tree().get_first_node_in_group("visitors")
	if open:
		return "Turn away (close)" if v and v.at_door else "Close hatch"
	return "Open hatch"


func interact(_p: Node) -> void:
	set_open(not open)


func set_open(o: bool) -> void:
	if o == open:
		return
	open = o
	# the little sliding shutter: the door sounds, higher and quieter
	Sounds.play_at(self, lid.global_position, Sounds.DOOR_OPEN if o else Sounds.DOOR_CLOSE, -9.0, "SFX", 1.45, 0.05, 1.5)
	toggled.emit(o)
	get_tree().call_group("visitors", "hatch_changed", o)


func wants_zoom() -> bool:
	return open


func _process(dt: float) -> void:
	k = move_toward(k, 1.0 if open else 0.0, dt * 5.0)
	lid.position.x = x0 + k * 0.22
