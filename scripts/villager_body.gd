class_name VillagerBody
extends Node3D
## A villager's body built from the split PS1Villager meshes, posed in code.
## Each leg and arm swings on its own pivot, so people walk one foot after the
## other, swing their arms, sit down and get up instead of snapping, nod and
## gesture while they talk, and slump when they doze off.
##
## The owner sets the inputs every frame (mode, moving, speed) and positions
## the head itself; this node does the rest in its own _process.

const STRIDE := 1.15          # metres per full walk cycle (two steps)
const SIT_TIME := 0.55

## Inputs from the owner
var mode := "stand"           # stand, walk, sit, sleep, stalk, hold
var speed := 0.0              # m/s actually moved this frame
var hop := false              # both feet at once (Esmagzam walks like this)
var calm := true              # breathing and fidgeting (doubles keep still)

var sit_k := 0.0              # 0 standing .. 1 seated (eased)
var sit_target := 0.0
var head: Node3D
var hip := Vector3(0, 0.86, 0)
var knee_off := Vector3(0, -0.39, 0)
var thighs: Array[Node3D] = []
var shins: Array[Node3D] = []
var arms: Array[Node3D] = []
var lap_stand: Node3D         # coat tails / upper skirt that ride the thighs
var hem: Node3D               # lower skirt hanging from the knees
var lap_sit: MeshInstance3D   # the same cloth bent into a lap, shown seated
var arm_style := "swing"      # swing, clasp, still
var mug_arm := false          # right hand holds something to raise
var arm_pose: Array = []      # two Vector3 rotations: holds the arms there instead

var t := 0.0
var phase := 0.0
var walk_k := 0.0
var talk_t := 0.0
var talk_k := 0.0
var sleep_k := 0.0
var fidget := Vector2.ZERO
var fidget_to := Vector2.ZERO
var fidget_t := 0.0


## parts: PS1Villager.build_guest_parts(). head_node: the owner's head pivot
## (it keeps its children, e.g. the breath particles).
func build(parts: Dictionary, head_node: Node3D) -> void:
	var piv: Dictionary = parts["pivots"]
	var mat: Material = parts["material"]
	hip = piv.get("leg_l", piv.get("legs", Vector3(0, 0.86, 0)))
	var kp: Vector3 = piv.get("knee_l", piv.get("knee", hip + Vector3(0, -0.39, 0)))
	knee_off = Vector3(0, kp.y - hip.y, 0)
	_mesh(self, parts.get("body"), mat)
	head = head_node if head_node else Node3D.new()
	if head.get_parent():
		head.reparent(self, false)
	else:
		add_child(head)
	head.position = piv["head"]
	_mesh(head, parts.get("head"), mat)
	for side in ["l", "r"]:
		var th := Node3D.new()
		th.name = "Thigh_" + side
		th.position = hip
		add_child(th)
		_mesh(th, parts.get("leg_" + side), mat)
		var sh := Node3D.new()
		sh.name = "Shin_" + side
		sh.position = knee_off
		th.add_child(sh)
		_mesh(sh, parts.get("knee_" + side), mat)
		thighs.append(th)
		shins.append(sh)
		var arm := Node3D.new()
		arm.name = "Arm_" + side
		arm.position = piv.get("arm_" + side, Vector3(0.18 * (1 if side == "l" else -1), 1.36, 0))
		add_child(arm)
		_mesh(arm, parts.get("arm_" + side), mat)
		arms.append(arm)
	lap_stand = Node3D.new()
	lap_stand.name = "Lap"
	lap_stand.position = hip
	add_child(lap_stand)
	_mesh(lap_stand, parts.get("legs"), mat)
	hem = Node3D.new()
	hem.name = "Hem"
	hem.position = knee_off
	lap_stand.add_child(hem)
	_mesh(hem, parts.get("knee"), mat)
	lap_sit = _mesh(self, parts.get("lap"), mat)
	if lap_sit:
		lap_sit.visible = false
	var pose: String = parts.get("pose", "rest")
	match pose:
		"clasp", "nervous":
			arm_style = "clasp"
		"fiddle":
			arm_style = "still"
		_:
			arm_style = "swing"
	mug_arm = parts.get("prop", "") == "ale"
	t = randf() * 20.0
	fidget_t = randf_range(2.0, 6.0)


func _mesh(parent: Node3D, m: Mesh, mat: Material) -> MeshInstance3D:
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Sit down (1) or get up (0) over SIT_TIME; `instant` skips the motion.
func set_seated(on: bool, instant := false) -> void:
	sit_target = 1.0 if on else 0.0
	if instant:
		sit_k = sit_target
		_apply(0.0)


func sitting_done() -> bool:
	return absf(sit_k - sit_target) < 0.01


## Gesture and nod for roughly as long as a line takes to read.
func talk(seconds: float) -> void:
	talk_t = clampf(seconds, 1.0, 6.0)


func _process(dt: float) -> void:
	_apply(dt)


func _apply(dt: float) -> void:
	t += dt
	sit_k = move_toward(sit_k, sit_target, dt / SIT_TIME)
	var s := smoothstep(0.0, 1.0, sit_k)
	var walking := mode in ["walk", "stalk"] and speed > 0.05
	walk_k = move_toward(walk_k, 1.0 if walking else 0.0, dt * 5.0)
	if walking:
		phase += speed * dt / STRIDE * TAU
	talk_t = maxf(talk_t - dt, 0.0)
	talk_k = move_toward(talk_k, 1.0 if talk_t > 0.0 else 0.0, dt * 3.0)
	sleep_k = move_toward(sleep_k, 1.0 if mode == "sleep" else 0.0, dt * 0.6)
	fidget_t -= dt
	if fidget_t <= 0.0:
		fidget_t = randf_range(2.5, 7.0)
		fidget_to = Vector2(randf_range(-0.12, 0.12), randf_range(-0.06, 0.08)) if calm else Vector2.ZERO
	fidget = fidget.lerp(fidget_to, minf(dt * 1.5, 1.0))

	var w := walk_k * (1.0 - s)
	var stalk := mode == "stalk"
	var amp := 0.18 if stalk else 0.42
	var ph := phase
	var sw := sin(ph)
	# legs: one after the other; the knee bends as the foot comes through
	var th := [0.0, 0.0]
	var kn := [0.0, 0.0]
	for i in 2:
		var p := ph + (0.0 if (hop or i == 0) else PI)
		if hop:
			th[i] = (0.25 + 0.35 * sin(p)) * w
			kn[i] = -(0.35 + 0.35 * maxf(0.0, -sin(p))) * w
		else:
			th[i] = amp * sin(p) * w
			kn[i] = -(0.0 if stalk else 0.55) * maxf(0.0, cos(p + 0.6)) * w
	for i in 2:
		thighs[i].rotation = Vector3(lerpf(th[i], PI * 0.5, s), 0, 0)
		shins[i].rotation = Vector3(lerpf(kn[i], -PI * 0.5, s), 0, 0)
	# the cloth over the thighs follows their average; seated it swaps for
	# the bent lap mesh so skirts don't tear at hip and knee
	var seated_mesh := lap_sit != null and sit_k > 0.5
	if lap_sit:
		lap_sit.visible = seated_mesh
	lap_stand.visible = not seated_mesh
	lap_stand.rotation = Vector3(lerpf((th[0] + th[1]) * 0.5, PI * 0.5, s), 0, 0)
	hem.rotation = Vector3(lerpf((kn[0] + kn[1]) * 0.5 * 0.5, -PI * 0.5, s), 0, 0)

	# arms: counter-swing when walking, a little life when still, a gesture
	# while talking, dropped in sleep
	var arm_x := [0.0, 0.0]
	var arm_z := [0.0, 0.0]
	match arm_style:
		"swing":
			for i in 2:
				arm_x[i] = -0.32 * sin(ph + (0.0 if (hop or i == 0) else PI)) * w * (0.0 if stalk else 1.0)
				if hop:
					arm_z[i] = 0.25 * absf(sin(ph)) * w * (1.0 if i == 0 else -1.0)
			arm_x[1] += 0.55 * talk_k                       # the right hand comes up to make a point
			arm_z[1] += -0.12 * talk_k
			if mug_arm:
				arm_x[1] += 0.25 * talk_k                   # raises the tankard
			arm_x[0] += fidget.y * 0.5
		"clasp":
			var c := 0.08 * sin(ph * 2.0) * w + 0.18 * talk_k + fidget.y * 0.4
			arm_x = [c, c]
	for i in 2:
		arm_x[i] -= 0.12 * sleep_k
		arm_z[i] += 0.05 * sleep_k * (1.0 if i == 0 else -1.0)
		arms[i].rotation = arm_pose[i] if arm_pose.size() == 2 else Vector3(arm_x[i], 0, arm_z[i])

	# whole body: bob and sway with the steps, breathe, lean
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	if hop:
		pos.y = absf(sin(ph)) * 0.11 * w
		rot.x = -0.06 * w
	else:
		pos.y = (absf(cos(ph)) - 0.6) * 0.035 * w
		rot.z = sw * 0.03 * w
		rot.x = -0.04 * w
	if stalk:
		rot.x = -0.28 * walk_k + (-0.12 if mode == "stalk" else 0.0)
		rot.z = sin(ph * 0.5) * 0.07 * walk_k
	if calm:
		var br := 0.9 if mode == "sleep" else 1.7
		pos.y += sin(t * br) * (0.008 if mode == "sleep" else 0.004)
		rot.z += sin(t * 0.23) * 0.015 * (1.0 - w)
		rot.y += fidget.x * 0.25 * (1.0 - w)
	rot.x += 0.16 * sleep_k
	position = position.lerp(pos, minf(dt * 14.0, 1.0)) if dt > 0.0 else pos
	rotation = rotation.lerp(rot, minf(dt * 10.0, 1.0)) if dt > 0.0 else rot
	# a nod now and then while speaking
	if head and talk_k > 0.0:
		head.rotation.x += sin(t * 6.5) * 0.07 * talk_k
