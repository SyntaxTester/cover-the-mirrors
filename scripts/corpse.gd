extends Node3D
## The dead man. Every double that reaches the coffin moves him a little:
## stage 1 the body shifts, stage 2 the head turns, the last stage he sits up.

@onready var torso: Node3D = $Torso
@onready var head: Node3D = get_node_or_null("Torso/Head")

var up := false
var k := 0.0
var stage := 0
var lift := 0.0
var head_yaw := 0.0
var head_base := Vector3.ZERO   # position: the head is a plain sphere, so it shifts rather than turns


func _ready() -> void:
	if head:
		head_base = head.position
	Game.corpse_stirred.connect(set_stage)
	set_stage(Game.run.get("corpse_stage", 0), true)


func set_stage(s: int, instant := false) -> void:
	stage = s
	var want_lift: float = [0.0, -0.1, -0.24][mini(stage, 2)]
	var want_yaw := 0.0 if stage < 2 else 0.9
	if instant:
		lift = want_lift
		head_yaw = want_yaw
	else:
		var tw := create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(self, "lift", want_lift, 1.6)
		tw.parallel().tween_property(self, "head_yaw", want_yaw, 2.4)


func sit() -> void:
	up = true


func _process(dt: float) -> void:
	if up and k < 1.0:
		k = minf(k + dt * 1.2, 1.0)
	torso.rotation.z = lerpf(lift, -1.35, ease(k, 0.4))
	if head:
		head.position = head_base + Vector3(0, 0.05, 0.07) * head_yaw / 0.9   # lolls toward the room
