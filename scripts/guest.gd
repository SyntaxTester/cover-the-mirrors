extends Interactable

enum S { DOOR, WALK, SEATED, ASLEEP, LEAVE, STALK }

@onready var legs: Node3D = $Legs
@onready var knee: Node3D = $Legs/Knee
@onready var head: Node3D = $Head
@onready var breath: GPUParticles3D = $Head/Breath
@onready var voice: AudioStreamPlayer3D = $Voice

var nick := ""
var line := ""
var double := false
var signs: Array = []
var state := S.DOOR
var path: Array = []
var seat: Node3D
var hold_t := 0.0
var holding := false
var stalk_t := 0.0
var breath_t := 0.0
var speed := 1.0
var pitch := 0.0
var yaw := 0.0


func _ready() -> void:
	hold = true
	add_to_group("guests")
	breath_t = randf() * 3.0
	breath.emitting = false


func setup(d: Dictionary, look: Dictionary) -> void:
	nick = d.get("name", "Guest")
	line = d.get("line", "")
	double = d.get("double", false)
	signs = d.get("signs", []) if double else []
	paint($Torso, look.get("coat", "#4a4038"))
	paint($Head/Hat/Brim, look.get("hat_color", "#222222"))
	paint($Head/Hat/Crown, look.get("hat_color", "#222222"))
	paint($Scarf, look.get("scarf_color", "#7a2a22"))
	$Head/Hat.visible = look.get("hat", false)
	$Scarf.visible = look.get("scarf", false)
	var boot: Material = load("res://assets/materials/boot_clean.tres" if sign_on("clean_boots") else "res://assets/materials/boot_mud.tres")
	$Legs/Knee/BootL.material_override = boot
	$Legs/Knee/BootR.material_override = boot
	if double:
		for n in find_children("*", "GeometryInstance3D", true, false):
			n.layers = 2


func paint(n: MeshInstance3D, hex: String) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	n.material_override = m
	for c in n.find_children("*", "MeshInstance3D", true, false):
		c.material_override = m


func sign_on(s: String) -> bool:
	return signs.has(s)


func _process(dt: float) -> void:
	match state:
		S.WALK, S.LEAVE, S.STALK:
			step(dt)
		S.SEATED:
			if double and Game.state == Game.State.PLAY:
				stalk_t -= dt
				if stalk_t <= 0.0:
					stalk()
	if holding and state != S.ASLEEP:
		hold_t += dt
		if hold_t >= Config.expel_hold:
			holding = false
			hold_t = 0.0
			get_tree().call_group("visitors", "expel", self)
	var ty := 0.0
	var tp := 0.0
	if state == S.ASLEEP:
		tp = -0.65
	elif state == S.SEATED or state == S.DOOR:
		ty = yaw_to_player()
	yaw = lerp_angle(yaw, ty, dt * 3.0)
	pitch = lerpf(pitch, tp, dt * 2.0)
	head.rotation = Vector3(pitch, yaw, 0)
	breathe(dt)


func yaw_to_player() -> float:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if not p:
		return 0.0
	var l := to_local(p.global_position)
	return clampf(atan2(-l.x, -l.z), -1.2, 1.2)


func breathe(dt: float) -> void:
	if sign_on("no_breath"):
		breath.emitting = false
		return
	breath_t += dt
	breath.emitting = fmod(breath_t, 3.2) < 0.8


func step(dt: float) -> void:
	if path.is_empty():
		arrive()
		return
	var tgt: Vector3 = path[0]
	var pos := global_position
	var d := tgt - pos
	d.y = 0.0
	var dist := d.length()
	var mv := speed * dt
	if dist <= mv:
		global_position = Vector3(tgt.x, pos.y, tgt.z)
		path.pop_front()
	else:
		global_position = pos + d / dist * mv
	if dist > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), dt * 6.0)


func arrive() -> void:
	match state:
		S.WALK:
			sit()
		S.LEAVE:
			queue_free()
		S.STALK:
			state = S.DOOR
			Game.lose("double")


func stand() -> void:
	legs.rotation.x = 0.0
	knee.rotation.x = 0.0
	global_position.y = 0.0


func sit() -> void:
	global_transform = seat.global_transform
	global_position.y = seat.global_position.y - 0.8
	legs.rotation.x = PI / 2
	knee.rotation.x = -PI / 2
	state = S.SEATED
	if double:
		stalk_t = randf_range(Game.cfg().double_walk_min, Game.cfg().double_walk_max)


func walk_in(s: Node3D, pts: Array) -> void:
	seat = s
	path = pts.duplicate()
	path.append(Vector3(s.global_position.x, 0.0, s.global_position.z))
	state = S.WALK
	speed = Config.guest_speed
	stand()


func leave(pts: Array) -> void:
	seat = null
	holding = false
	path = pts.duplicate()
	state = S.LEAVE
	speed = Config.guest_speed
	stand()


func stalk() -> void:
	var v = get_tree().get_first_node_in_group("visitors")
	path = v.stalk_path().duplicate() if v else []
	state = S.STALK
	speed = Config.stalk_speed
	stand()


func can_sleep() -> bool:
	return state == S.SEATED and not double


func fall_asleep() -> void:
	if can_sleep():
		state = S.ASLEEP


func wake() -> void:
	if state == S.ASLEEP:
		state = S.SEATED


func is_awake() -> bool:
	return state == S.SEATED or state == S.STALK


func is_asleep() -> bool:
	return state == S.ASLEEP


func say() -> void:
	if voice.stream:
		voice.play()
	get_tree().call_group("hud", "say", nick, line)


func get_prompt() -> String:
	if state == S.ASLEEP:
		return "Wake"
	if holding:
		return "Asking to leave" + ".".repeat(int(hold_t / Config.expel_hold * 3.0) + 1)
	return "Ask to leave (hold E)"


func can_interact(_p: Node) -> bool:
	return state == S.SEATED or state == S.ASLEEP or state == S.STALK


func interact(_p: Node) -> void:
	if state == S.ASLEEP:
		wake()
		return
	holding = true
	hold_t = 0.0


func release(_p: Node) -> void:
	holding = false
	hold_t = 0.0
