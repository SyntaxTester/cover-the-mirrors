extends Node3D

@onready var body: Node3D = $Body
@onready var head: Node3D = $Head
@onready var legs: Node3D = $Legs
@onready var growl: AudioStreamPlayer3D = $Growl

var alert_on := false
var k := 0.0
var t := 0.0
var body_y := 0.0
var head_p := Vector3.ZERO


func _ready() -> void:
	add_to_group("dog")
	body_y = body.position.y
	head_p = head.position


func alert(on: bool) -> void:
	alert_on = on
	if on and growl.stream:
		growl.play()
	elif not on:
		growl.stop()


func _process(dt: float) -> void:
	k = move_toward(k, 1.0 if alert_on else 0.0, dt * 3.0)
	t += dt
	var sh := sin(t * 40.0) * 0.006 * k
	body.position.y = body_y + k * 0.2 + sh
	head.position = head_p + Vector3(0.05 * k, 0.3 * k + sh, 0)
	legs.scale.y = maxf(k, 0.01)
	legs.visible = k > 0.02
