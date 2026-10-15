extends Interactable

@onready var swing: Node3D = $Swing
@onready var knock_snd: AudioStreamPlayer3D = $Knock

var open_t := 0.0
var ang := 0.0
var rattle := 0.0


func _ready() -> void:
	prompt = "Let in"
	add_to_group("front_door")


func can_interact(_p: Node) -> bool:
	var v = get_tree().get_first_node_in_group("visitors")
	return v != null and v.can_let_in()


func interact(_p: Node) -> void:
	get_tree().call_group("visitors", "let_in")


func swing_open(t: float) -> void:
	open_t = maxf(open_t, t)


func knock() -> void:
	rattle = 0.35
	if knock_snd.stream:
		knock_snd.play()


func _process(dt: float) -> void:
	open_t -= dt
	rattle = maxf(rattle - dt, 0.0)
	var tgt := -1.35 if open_t > 0.0 else 0.0
	ang = move_toward(ang, tgt, dt * 1.8)
	swing.rotation.y = ang + (sin(rattle * 90.0) * 0.012 if rattle > 0.0 else 0.0)
