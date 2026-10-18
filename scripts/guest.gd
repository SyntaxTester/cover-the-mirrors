extends Interactable

enum S { DOOR, WALK, SEATED, ASLEEP, LEAVE, STALK }

const BOOT_CLEAN := preload("res://assets/materials/boot_clean.tres")
const BOOT_MUD := preload("res://assets/materials/boot_mud.tres")
const FALLBACK_MODEL := "SEAN"
const WET_FOR := 150.0          # real guests drip rain this long after arriving

@onready var legs: Node3D = $Legs
@onready var knee: Node3D = $Legs/Knee
@onready var head: Node3D = $Head
@onready var breath: GPUParticles3D = $Head/Breath
@onready var voice: AudioStreamPlayer3D = $Voice

var nick := ""
var line := ""
var double := false
var signs: Array = []
var answers: Dictionary = {}
var asked: Array = []           # questions already asked at the hatch
var role := ""
var state := S.DOOR
var path: Array = []
var seat: Node3D
var hold_t := 0.0
var holding := false
var stalk_t := 0.0
var wants_stalk := false
var sabotage_t := 0.0
var breath_t := 0.0
var speed := 1.0
var pitch := 0.0
var yaw := 0.0
var hip_y := 0.85
var age := 0.0
var seen := false
var steps: AudioStreamPlayer3D
var chase: AudioStreamPlayer3D
var drips: CPUParticles3D


func _ready() -> void:
	hold = true
	add_to_group("guests")
	breath_t = randf() * 3.0
	breath.emitting = false
	steps = _loop_player(Sounds.STEPS, -6.0, 2.5)
	chase = _loop_player(Sounds.CHASE, -10.0, 4.0)


func _loop_player(s: AudioStream, db: float, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = Sounds.looped(s)
	p.volume_db = db
	p.unit_size = unit
	p.bus = "SFX"
	add_child(p)
	p.position = Vector3(0, 0.3, 0)
	return p


## Footsteps while walking; slow and heavy for a double creeping to the coffin.
func _update_sounds() -> void:
	var moving := (state == S.WALK or state == S.LEAVE or state == S.STALK) and not path.is_empty()
	if state == S.STALK and seen:
		moving = false   # frozen while watched
	if moving and not steps.playing:
		steps.pitch_scale = 0.8 if state == S.STALK else randf_range(0.95, 1.05)
		steps.play(randf() * 40.0)
	elif not moving and steps.playing:
		steps.stop()
	if state != S.STALK and chase.playing:
		chase.stop()
	if state == S.STALK:
		chase.volume_db = lerpf(chase.volume_db, -22.0 if seen else -10.0, 0.1)


## d: one entry from NightPlan; look: the guest's look from guests.json.
func setup(d: Dictionary, look: Dictionary) -> void:
	nick = d.get("name", "Guest")
	line = d.get("line", "")
	double = d.get("double", false)
	signs = d.get("signs", [])
	answers = d.get("answers", look.get("answers", {}))
	role = "" if double else str(look.get("role", ""))
	build_model(str(look.get("model", FALLBACK_MODEL)), d.get("mutation", {}))
	if double:
		add_to_group("doubles")
		for n in find_children("*", "GeometryInstance3D", true, false):
			n.layers = 2   # the glass won't hold them: mirrors don't render layer 2
	if sign_on("no_shadow"):
		for n in find_children("*", "GeometryInstance3D", true, false):
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if sign_on("cold"):
		add_to_group("cold_ones")   # candles and the door lamp gutter near them
	if not sign_on("dry"):
		_make_drips()


# Builds the PS1 villager (scenes/ps1_villager.gd) named in guests.json as
# four meshes on the Legs / Knee / Head pivots so sitting and head turns work.
func build_model(model: String, mutation: Dictionary = {}) -> void:
	var id := PS1Villager.character_from_name(model)
	if id < 0:
		push_warning("Guest '%s': unknown model '%s', using %s" % [nick, model, FALLBACK_MODEL])
		id = PS1Villager.character_from_name(FALLBACK_MODEL)
	# the "clean_boots" sign: real guests are muddy from the road, doubles are not
	var clean := sign_on("clean_boots")
	var boot: StandardMaterial3D = BOOT_CLEAN if clean else BOOT_MUD
	var o := {"shoe_col": boot.albedo_color, "boots": "clean" if clean else "mud"}
	o.merge(mutation, true)   # a double's one wrong detail
	var parts := PS1Villager.build_guest_parts(id, o)
	var piv: Dictionary = parts["pivots"]
	var p_legs: Vector3 = piv["legs"]
	var p_knee: Vector3 = piv["knee"]
	var p_head: Vector3 = piv["head"]
	hip_y = p_legs.y
	legs.position = p_legs
	knee.position = p_knee - p_legs
	head.position = p_head
	breath.position = parts["mouth"]
	var mat: Material = parts["material"]
	add_part(self, parts.get("body"), mat)
	add_part(legs, parts.get("legs"), mat)
	add_part(knee, parts.get("knee"), mat)
	add_part(head, parts.get("head"), mat)


func add_part(parent: Node3D, mesh: Mesh, mat: Material) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)


## Rain dripping off hat and shoulders: everyone who walked here is wet.
func _make_drips() -> void:
	drips = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color(0.75, 0.82, 0.9, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	drips.mesh = q
	drips.amount = 10
	drips.lifetime = 0.55
	drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drips.emission_box_extents = Vector3(0.2, 0.02, 0.12)
	drips.direction = Vector3.DOWN
	drips.spread = 5.0
	drips.initial_velocity_min = 0.2
	drips.initial_velocity_max = 0.5
	drips.gravity = Vector3(0, -9.0, 0)
	drips.local_coords = false
	head.add_child(drips)
	drips.position = Vector3(0, 0.12, 0)
	if double:
		drips.layers = 2


func sign_on(s: String) -> bool:
	return signs.has(s)


## What they say when asked through the hatch.
func answer(q: String) -> String:
	if not asked.has(q):
		asked.append(q)
	return str(answers.get(q, "..."))


func speak(text: String) -> void:
	get_tree().call_group("hud", "say", nick, text)


func head_pos() -> Vector3:
	return head.global_position + Vector3(0, 0.15, 0)


func _process(dt: float) -> void:
	age += dt
	seen = Sight.sees(self, head_pos())
	if drips and drips.emitting and age > WET_FOR:
		drips.emitting = false
	match state:
		S.WALK, S.LEAVE:
			step(dt)
		S.STALK:
			if not seen:   # it only moves while nobody is watching
				step(dt)
		S.SEATED:
			if double and Game.state == Game.State.PLAY:
				_double_tick(dt)
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
	elif state == S.SEATED or state == S.DOOR or (state == S.STALK and seen):
		ty = yaw_to_player()
	yaw = lerp_angle(yaw, ty, dt * 3.0)
	pitch = lerpf(pitch, tp, dt * 2.0)
	head.rotation = Vector3(pitch, yaw, 0)
	breathe(dt)
	_update_sounds()


## A seated double works against the wake while your back is turned,
## then goes for the coffin when it gets the chance.
func _double_tick(dt: float) -> void:
	stalk_t -= dt
	sabotage_t -= dt
	if stalk_t <= 0.0:
		wants_stalk = true
	if wants_stalk and not seen:
		stalk()
		return
	if sabotage_t <= 0.0 and not seen:
		sabotage_t = randf_range(Game.cfg().get("sabotage_min", 20.0), Game.cfg().get("sabotage_max", 35.0))
		sabotage()


func sabotage() -> void:
	var acts: Array = []
	var lit := get_tree().get_nodes_in_group("coffin_candles").filter(func(c): return c.lit)
	if lit.size() > 1:
		acts.append(func(): lit.pick_random().put_out())
	var mirrors := get_tree().get_nodes_in_group("mirrors").filter(
		func(m): return not m.lifted and not m.get("slipped"))
	if not mirrors.is_empty():
		acts.append(func(): mirrors.pick_random().slip())
	var sleepers := get_tree().get_nodes_in_group("guests").filter(
		func(g): return g != self and g.can_sleep() and g.global_position.distance_to(global_position) < 3.5)
	if not sleepers.is_empty():
		acts.append(func(): sleepers.pick_random().fall_asleep())
	if acts.is_empty():
		return
	var f: Callable = acts.pick_random()
	f.call()
	get_tree().call_group("roles", "on_sabotage", self)


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
			get_tree().call_group("visitors", "double_reached", self)


func stand() -> void:
	legs.rotation.x = 0.0
	knee.rotation.x = 0.0
	global_position.y = 0.0


func sit() -> void:
	global_transform = seat.global_transform
	global_position.y = seat.global_position.y - (hip_y - 0.05)
	legs.rotation.x = PI / 2
	knee.rotation.x = -PI / 2
	state = S.SEATED
	if double:
		stalk_t = randf_range(Game.cfg().double_walk_min, Game.cfg().double_walk_max)
		sabotage_t = randf_range(Game.cfg().get("sabotage_min", 20.0), Game.cfg().get("sabotage_max", 35.0)) * 0.6
	get_tree().call_group("roles", "on_seated", self)


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
	wants_stalk = false
	speed = Config.stalk_speed
	stand()
	Sounds.play(self, Sounds.RISER, -6.0)   # something is wrong in the room
	chase.play()
	get_tree().call_group("roles", "on_stalk", self)


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


func is_stalking() -> bool:
	return state == S.STALK


func is_seated() -> bool:
	return state == S.SEATED


func is_asleep() -> bool:
	return state == S.ASLEEP


func say() -> void:
	if voice.stream:
		voice.play()
	speak(line)


func get_prompt() -> String:
	if state == S.ASLEEP:
		return "Wake"
	if holding:
		return "Asking to leave" + ".".repeat(int(hold_t / Config.expel_hold * 3.0) + 1)
	if state == S.STALK:
		return "Stop them (hold E)"
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
