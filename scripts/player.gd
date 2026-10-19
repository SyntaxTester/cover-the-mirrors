extends CharacterBody3D

@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera
@onready var ray: RayCast3D = $Head/Camera/Ray

var target: Interactable
var held: Interactable
var hud: Node
var bob := 0.0
var cam_y := 0.0
var steps: AudioStreamPlayer
@export var run_speed := 4.0


func _ready() -> void:
	add_to_group("player")
	ray.target_position = Vector3(0, 0, -Config.interact_dist)
	cam_y = cam.position.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	steps = AudioStreamPlayer.new()
	steps.stream = Sounds.looped(Sounds.STEPS)
	steps.volume_db = -14.0
	steps.bus = "SFX"
	add_child(steps)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-e.relative.x * Config.mouse_sens)
		head.rotation.x = clampf(head.rotation.x - e.relative.y * Config.mouse_sens, -1.4, 1.4)
	elif e is InputEventMouseButton and e.pressed and Game.state == Game.State.PLAY:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Sounds.play(self, Sounds.UI_OPEN, -8.0)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(dt: float) -> void:
	var live := Game.state == Game.State.PLAY or Game.state == Game.State.ATTACK
	var inp := Vector2.ZERO
	if live:
		inp = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var running := live and Input.is_key_pressed(KEY_SHIFT) and inp.length() > 0.0
	var speed := run_speed if running else Config.walk_speed

	var dir := (transform.basis * Vector3(inp.x, 0, inp.y)).normalized()
	velocity.x = move_toward(velocity.x, dir.x * speed, Config.walk_accel * dt)
	velocity.z = move_toward(velocity.z, dir.z * speed, Config.walk_accel * dt)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= 9.8 * dt

	move_and_slide()

	var sp := Vector2(velocity.x, velocity.z).length()
	var walking := live and is_on_floor() and sp > 0.4
	if walking and not steps.playing:
		steps.play(randf() * 40.0)
	elif not walking and steps.playing:
		steps.stop()
	steps.pitch_scale = 1.3 if running else 1.0
	bob += dt * sp * Config.bob_freq
	cam.position.y = cam_y + sin(bob) * Config.bob_amount * minf(sp / speed, 1.0)

	scan(Game.state == Game.State.PLAY)
	var z := target != null and target.wants_zoom()
	cam.fov = lerpf(cam.fov, Config.zoom_fov if z else 70.0, dt * 6.0)


func scan(live: bool) -> void:
	var t: Interactable = null
	if live and ray.is_colliding():
		t = Interactable.find(ray.get_collider())
		if t and not t.can_interact(self):
			t = null
	target = t
	if held and (held != target or not Input.is_action_pressed("interact")):
		held.release(self)
		held = null
	if target and Input.is_action_just_pressed("interact"):
		target.interact(self)
		if target.hold:
			held = target
	if not hud:
		hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_hint(target.get_prompt() if target else "")
