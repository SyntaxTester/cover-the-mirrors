extends Interactable

enum S { DOOR, WALK, SEATED, ASLEEP, LEAVE, STALK, APPROACH, WANDER, HOLD, RETURN, SCARE }

const BOOT_CLEAN := preload("res://assets/materials/boot_clean.tres")
const BOOT_MUD := preload("res://assets/materials/boot_mud.tres")
const FALLBACK_MODEL := "SEAN"
const WET_FOR := 150.0
const HOPPER := "SULTAN_ESMAGZAM"   # Esmagzam bounces along on both feet; leave him be
const STAND_TIME := 0.45
const SEAT_FRONT := 0.42          # metres in front of a seat where they stand to sit          # real guests drip rain this long after arriving

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
var rig: Node3D
var body: VillagerBody
var moved := 0.0
var sit_blend := 1.0
var sit_from := Transform3D.IDENTITY
var sit_to := Transform3D.IDENTITY
var stand_left := 0.0
var stand_from_y := 0.0
var last_seat: Node3D
var hold_wait := 0.0
var stand_slide := false
var anim_t := 0.0
var walk_ph := 0.0
var shiver_t := 0.0
var snap_t := 0.0
var snap_yaw := 0.0
var hold_left := 0.0
var home: Node3D


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
	var moving := _walking() and not path.is_empty()
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


# Builds the PS1 villager (scenes/ps1_villager.gd) named in guests.json as a
# VillagerBody: legs, arms and head on their own pivots (scripts/villager_body.gd).
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
	body = VillagerBody.new()
	body.name = "Rig"
	add_child(body)
	body.build(parts, head)
	body.hop = model == HOPPER
	body.calm = not double
	rig = body
	hip_y = body.hip.y
	breath.position = parts["mouth"]
	legs.visible = false   # the scene's old single-leg pivots are unused now
	anim_t = randf() * 10.0
	shiver_t = randf_range(3.0, 8.0)
	snap_t = randf_range(6.0, 12.0)


func _walking() -> bool:
	return state in [S.WALK, S.LEAVE, S.STALK, S.APPROACH, S.WANDER, S.RETURN]


func _animate(dt: float) -> void:
	if body == null:
		return
	anim_t += dt
	match state:
		S.SEATED:
			body.mode = "sit"
		S.ASLEEP:
			body.mode = "sleep"
		S.STALK:
			body.mode = "stalk"
		S.DOOR, S.HOLD, S.SCARE:
			body.mode = "hold"
		_:
			body.mode = "walk"
	body.speed = moved / dt if dt > 0.0 else 0.0
	moved = 0.0
	# sitting down: ease from where they stand onto the chair
	if sit_blend < 1.0:
		sit_blend = minf(sit_blend + dt / VillagerBody.SIT_TIME, 1.0)
		global_transform = sit_from.interpolate_with(sit_to, smoothstep(0.0, 1.0, sit_blend))
	# getting up: rise before the first step
	if stand_left > 0.0:
		stand_left = maxf(stand_left - dt, 0.0)
		global_position.y = lerpf(0.0, stand_from_y, smoothstep(0.0, 1.0, stand_left / STAND_TIME))
		if stand_slide and not path.is_empty():
			# rise and step forward off the seat together, not through it
			var k := 1.0 - stand_left / STAND_TIME
			var tgt: Vector3 = path[0]
			var cur := Vector3(global_position.x, 0.0, global_position.z)
			var nxt := cur.lerp(tgt, minf(dt / maxf(stand_left + dt, 0.01), 1.0))
			global_position = Vector3(nxt.x, global_position.y, nxt.z)
			if k >= 1.0:
				stand_slide = false
	elif stand_slide:
		stand_slide = false
	# a double at the door shivers now and then, like the cold got into it
	if (state == S.DOOR or state == S.HOLD) and not double:
		shiver_t -= dt
		if shiver_t < 0.0:
			body.rotation += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.01
			if shiver_t < -0.6:
				shiver_t = randf_range(3.0, 8.0)


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


func speak(text: String, now := false) -> void:
	get_tree().call_group("hud", "say", nick, text, now)
	if body:
		body.talk(2.0 + text.length() / 30.0)


func head_pos() -> Vector3:
	return head.global_position + Vector3(0, 0.15, 0)


func _process(dt: float) -> void:
	age += dt
	seen = Sight.sees(self, head_pos())
	if drips and drips.emitting and age > WET_FOR:
		drips.emitting = false
	match state:
		S.WALK, S.LEAVE, S.APPROACH, S.WANDER, S.RETURN:
			step(dt)
		S.HOLD:
			# a neighbour who rushed up to you waits until you've seen them
			hold_wait += dt
			if seen and has_meta("rush_say"):
				speak(str(get_meta("rush_say")), true)
				remove_meta("rush_say")
			if seen or hold_wait > 8.0:
				hold_left -= dt
			if hold_left <= 0.0:
				_go_home()
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
	elif state == S.SEATED or state == S.DOOR or state == S.HOLD or (state == S.STALK and seen):
		ty = yaw_to_player()
	elif state == S.SCARE:
		ty = 0.0   # the whole body faces you; see face_camera()
	var turn := 3.0
	if double and (state == S.SEATED or state == S.DOOR):
		snap_t -= dt
		if snap_t <= 0.0:
			snap_t = randf_range(7.0, 14.0)
			snap_yaw = 1.0
		if snap_yaw > 0.0:
			snap_yaw -= dt * 0.5
			ty = _yaw_raw()
			turn = 18.0
	yaw = lerp_angle(yaw, ty, minf(dt * turn, 1.0))
	pitch = lerpf(pitch, tp, dt * 2.0)
	head.rotation = Vector3(pitch, yaw, 0)
	breathe(dt)
	_animate(dt)
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
	return clampf(_yaw_raw(), -1.2, 1.2)


func _yaw_raw() -> float:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if not p:
		return 0.0
	var l := to_local(p.global_position)
	return atan2(-l.x, -l.z)


func breathe(dt: float) -> void:
	if sign_on("no_breath"):
		breath.emitting = false
		return
	breath_t += dt
	breath.emitting = fmod(breath_t, 3.2) < 0.8


func step(dt: float) -> void:
	if stand_left > 0.0 or sit_blend < 1.0:
		return   # still getting up off the chair
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
		moved += dist
	else:
		global_position = pos + d / dist * mv
		moved += mv
	if dist > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), dt * 6.0)


func arrive() -> void:
	match state:
		S.WALK:
			sit()
		S.LEAVE:
			queue_free()
		S.APPROACH:
			state = S.DOOR
			rotation.y = float(get_meta("final_yaw", rotation.y))
			get_tree().call_group("visitors", "on_at_spot", self)
		S.WANDER:
			state = S.HOLD
			hold_wait = 0.0
			if has_meta("rush_line"):
				# the last step is right into your face
				var cam := get_viewport().get_camera_3d()
				if cam:
					var dir := global_position - cam.global_position
					face_camera(cam, 0.34, dir)
				set_meta("rush_say", get_meta("rush_line"))   # said when you see them
				remove_meta("rush_line")
		S.RETURN:
			sit()
		S.STALK:
			state = S.DOOR
			get_tree().call_group("visitors", "double_reached", self)


## Where you stand to sit on a seat: just in front of it, never inside it.
func _front_of(s: Node3D) -> Vector3:
	var f := -s.global_basis.z
	var p := s.global_position + Vector3(f.x, 0.0, f.z).normalized() * SEAT_FRONT
	return Vector3(p.x, 0.0, p.z)


func stand() -> void:
	sit_blend = 1.0
	if body and body.sit_k > 0.01:
		stand_from_y = global_position.y
		stand_left = STAND_TIME
		body.set_seated(false)
		if last_seat and is_instance_valid(last_seat):
			# step forward off the bench first, then go wherever
			path.push_front(_front_of(last_seat))
			stand_slide = true
	else:
		global_position.y = 0.0


func _seat_xf(s: Node3D) -> Transform3D:
	var xf := s.global_transform
	xf.origin.y = s.global_position.y - (hip_y - 0.05)
	return xf


## On the chair at once (for things that appear already seated).
func place_seated(s: Node3D) -> void:
	seat = s
	last_seat = s
	global_transform = _seat_xf(s)
	sit_blend = 1.0
	stand_left = 0.0
	if body:
		body.set_seated(true, true)


func sit() -> void:
	last_seat = seat
	sit_from = global_transform
	sit_to = _seat_xf(seat)
	sit_blend = 0.0
	stand_left = 0.0
	if body:
		body.set_seated(true)
	state = S.SEATED
	if double:
		stalk_t = randf_range(Game.cfg().double_walk_min, Game.cfg().double_walk_max)
		sabotage_t = randf_range(Game.cfg().get("sabotage_min", 20.0), Game.cfg().get("sabotage_max", 35.0)) * 0.6
	get_tree().call_group("roles", "on_seated", self)


func walk_in(s: Node3D, pts: Array) -> void:
	seat = s
	# walk up to the front of the bench; sitting down slides them back onto it
	path = Nav.route(global_position, pts + [_front_of(s)])
	state = S.WALK
	speed = Config.guest_speed
	stand()


func leave(pts: Array) -> void:
	seat = null
	holding = false
	path = Nav.route(global_position, pts)
	state = S.LEAVE
	speed = Config.guest_speed
	stand()


func stalk() -> void:
	var v = get_tree().get_first_node_in_group("visitors")
	path = Nav.route(global_position, v.stalk_path()) if v else []
	state = S.STALK
	wants_stalk = false
	speed = Config.stalk_speed
	stand()
	Sounds.play(self, Sounds.RISER, -6.0)   # something is wrong in the room
	chase.play()
	get_tree().call_group("roles", "on_stalk", self)


func approach(pts: Array, final_yaw: float) -> void:
	path = Nav.route(global_position, pts)
	state = S.APPROACH
	speed = Config.approach_speed
	set_meta("final_yaw", final_yaw)
	stand()


## A harmless scare: get up, walk fast at something, stand there, go back.
func rush_to(p: Vector3, hold_for: float) -> bool:
	if state != S.SEATED or double or seat == null:
		return false
	home = seat
	path = Nav.route(global_position, [Vector3(p.x, 0.0, p.z)])
	state = S.WANDER
	speed = Config.rush_speed
	hold_left = hold_for
	stand()
	return true


## Stand so the face sits `dist` in front of the camera lens, looking into it.
## `from_dir` is where the face should be relative to the camera (default:
## straight ahead of it). Used by the scares (scripts/systems/scares.gd).
func face_camera(cam: Camera3D, dist: float, from_dir := Vector3.ZERO) -> void:
	var dir := from_dir if from_dir != Vector3.ZERO else -cam.global_basis.z
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var target := cam.global_position + dir * dist
	var look := Vector3(-dir.x, 0.0, -dir.z)
	global_basis = Basis.looking_at(look, Vector3.UP)
	head.rotation = Vector3.ZERO
	yaw = 0.0
	pitch = 0.0
	if body:
		body.rotation = Vector3.ZERO
		body.position = Vector3.ZERO
	var face := head.global_transform * Vector3(0, 0.1, -0.09)
	global_position += target - face


## Taken out of the room for a scare; afterwards they walk back to their seat.
func begin_scare() -> void:
	if state == S.SEATED or state == S.ASLEEP:
		home = seat
	state = S.SCARE
	sit_blend = 1.0
	stand_left = 0.0
	if body:
		body.set_seated(false, true)


func end_scare() -> void:
	global_position.y = 0.0
	if home != null:
		_go_home()
	else:
		state = S.HOLD
		hold_left = 1.0


func _go_home() -> void:
	global_position.y = 0.0
	if home == null:
		state = S.SEATED
		return
	path = Nav.route(global_position, [_front_of(home)])
	state = S.RETURN
	speed = Config.guest_speed


func can_sleep() -> bool:
	return state == S.SEATED and not double


func fall_asleep() -> void:
	if can_sleep():
		state = S.ASLEEP


func wake() -> void:
	if state == S.ASLEEP:
		state = S.SEATED


func is_awake() -> bool:
	return state in [S.SEATED, S.STALK, S.WANDER, S.HOLD, S.RETURN]


func is_stalking() -> bool:
	return state == S.STALK


func is_seated() -> bool:
	return state == S.SEATED


func is_asleep() -> bool:
	return state == S.ASLEEP


func say() -> void:
	if nick == "Esmagzam":
		# a different noise every visit
		var n := int(Game.run.get("esmagzam_visits", 0))
		Game.run["esmagzam_visits"] = n + 1
		voice.stream = Sounds.ESMAGZAM[n % Sounds.ESMAGZAM.size()]
		voice.volume_db = 4.0
	if voice.stream:
		voice.play()
	speak(line, true)   # the visitor at the door answers the hatch at once


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
