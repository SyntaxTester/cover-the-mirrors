extends Node
## Scares that come from people, not things. Every one is silent: no sting,
## no footsteps, nothing to warn you. Someone is simply there when you turn,
## close enough that their face fills the screen, and they say something.
##
##   behind   someone stands right behind you; turn round and they're there
##   creep    a stranger in the corner of the room, closer every time you
##            look away, until it's at your shoulder
##   hatch    open the hatch with nobody knocking: a face pressed to it
##
## The director (director.gd) decides when; this node runs one at a time.

const GUEST := preload("res://scenes/guest.tscn")
const FACE_DIST := 0.24         # metres from the lens: the face fills the screen

## A neighbour from the wake who wandered over without a sound.
const LINES_GUEST := [
	"Ronan. You've not blinked in an hour.",
	"Did you hear it too? Under the floor?",
	"He was asking for you. Your father. Just now.",
	"Don't turn round so fast, child. You'll wake him.",
	"Is it you, Ronan? Is it really you?",
	"I counted the chairs. There's one more than there was.",
]
## Someone who was never let in.
const LINES_STRANGER := [
	"You left me out in the rain, Ronan.",
	"Why won't you let me sit with him?",
	"I can see you in the glass.",
	"Count us again. Go on.",
	"He's cold, isn't he? I'm colder.",
	"Shh. He's listening.",
	"There's room in the box for two.",
	"You have his eyes. I'll have them too.",
]
const LINES_HATCH := [
	"Let me in, Ronan. It's only me.",
	"It's cold out here. So cold.",
	"I came back for him.",
	"Open the door. Open the door. Open the door.",
	"Why did you leave me on the road?",
]
const WHISPER := "(whispers right behind you) Ronan..."

enum K { NONE, BEHIND, CREEP, HATCH }

var kind := K.NONE
var who: Node3D             # the guest doing the scaring
var stranger := false       # spawned for the scare (vanishes) or a real mourner (walks back)
var phase := 0
var t := 0.0
var line := ""
var visitors
var level: Node3D
var hatch
var hatch_armed := false


func _ready() -> void:
	add_to_group("scares")
	add_to_group("debug")
	visitors = get_node("../Visitors")
	level = get_node("../../Level")
	hatch = get_tree().get_first_node_in_group("hatch")
	if hatch:
		hatch.toggled.connect(_on_hatch)


func busy() -> bool:
	return kind != K.NONE


func _cam() -> Camera3D:
	return get_viewport().get_camera_3d()


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


# ── starting one ─────────────────────────────────────────────────────────────
func start_behind() -> bool:
	if busy() or _cam() == null:
		return false
	if not _pick_actor(0.5):
		return false
	kind = K.BEHIND
	phase = 0
	t = 0.0
	_glue_behind()
	return true


func start_creep() -> bool:
	if busy() or _cam() == null or _player() == null:
		return false
	var p := _player().global_position
	# somewhere behind you in the same room, out of sight
	var back := _cam().global_basis.z
	back = Vector3(back.x, 0.0, back.z).normalized()
	var spot := Nav.snap(p + back * 3.6)
	if spot.distance_to(Vector3(p.x, 0, p.z)) < 2.0 or Sight.sees(self, spot + Vector3(0, 1.4, 0), 12.0, 0.4):
		return false
	if not _spawn_stranger():
		return false
	who.global_position = spot
	who.look_at(Vector3(p.x, 0.0, p.z), Vector3.UP)
	kind = K.CREEP
	phase = 0
	t = 0.0
	return true


## Armed: the next time the hatch opens with nobody at the door.
func arm_hatch() -> bool:
	if busy() or hatch == null or hatch.open or visitors.at_door != null or visitors.approaching != null:
		return false
	hatch_armed = true
	return true


func _on_hatch(o: bool) -> void:
	if not o:
		if kind == K.HATCH:
			_finish(true)
		return
	if not hatch_armed or busy() or visitors.at_door != null or Game.state != Game.State.PLAY:
		return
	hatch_armed = false
	if not _spawn_stranger():
		return
	kind = K.HATCH
	phase = 1
	t = 0.0
	line = LINES_HATCH.pick_random()
	# the zoomed hatch view needs a frame to settle before we stand in it
	await get_tree().process_frame
	await get_tree().process_frame
	if kind == K.HATCH and is_instance_valid(who) and _cam():
		who.visible = true
		# just outside the door, pressed up to the little window
		var cam := _cam()
		var spot: Vector3 = hatch.global_position + Vector3(0.34, -0.02, 0.0)   # the door faces +X
		who.face_camera(cam, cam.global_position.distance_to(spot), spot - cam.global_position)
		_lamp(true)
		who.speak(line, true)


## Either a mourner from the wake (not a double, not watched) or a stranger.
func _pick_actor(stranger_chance: float) -> bool:
	var real: Array = visitors.inside.filter(func(g): return is_instance_valid(g) and not g.double \
		and (g.is_seated() or g.is_asleep()) and not g.seen)
	if real.is_empty() or randf() < stranger_chance:
		return _spawn_stranger()
	who = real.pick_random()
	stranger = false
	who.begin_scare()
	line = LINES_GUEST.pick_random()
	return true


func _spawn_stranger() -> bool:
	var tonight: Array = visitors.plan.get("portraits", [])
	var names: Array = visitors.looks.keys().filter(func(n): return not tonight.has(n))
	if names.is_empty():
		names = visitors.looks.keys()
	if names.is_empty():
		return false
	var n: String = names.pick_random()
	var g = GUEST.instantiate()
	level.get_node("Guests").add_child(g)
	g.setup({"name": n, "double": true, "signs": ["dry", "no_breath"],
		"mutation": {"expr": "stare", "skin": Color(0.74, 0.72, 0.70), "dark_circles": true, "sunken_eyes": true}}, visitors.looks[n])
	g.set_process(false)    # no AI: it only does what this script says
	g.visible = false
	who = g
	stranger = true
	line = LINES_STRANGER.pick_random()
	return true


# ── running it ───────────────────────────────────────────────────────────────
func _process(dt: float) -> void:
	if kind == K.NONE:
		return
	if not is_instance_valid(who) or Game.state != Game.State.PLAY:
		_finish(true)
		return
	t += dt
	var cam := _cam()
	if cam == null:
		return
	match kind:
		K.BEHIND:
			_run_behind(cam)
		K.CREEP:
			_run_creep(cam)
		K.HATCH:
			if t > 4.0 or (hatch and not hatch.open):
				_finish(true)


## How squarely the camera looks at the face (1 = dead on).
func _facing(cam: Camera3D) -> float:
	var f: Vector3 = who.head_pos() - cam.global_position
	return (-cam.global_basis.z).dot(f.normalized())


## Keep standing at your back, so close you'd feel the breath.
func _glue_behind() -> void:
	var cam := _cam()
	who.visible = true
	who.face_camera(cam, FACE_DIST, cam.global_basis.z)
	_lamp(true)


## A faint cold light on the face, so in a dark room you still see it.
var lamp: OmniLight3D
func _lamp(on: bool) -> void:
	if on and (lamp == null or not is_instance_valid(lamp)) and is_instance_valid(who):
		lamp = OmniLight3D.new()
		lamp.light_color = Color(0.7, 0.78, 0.85)
		lamp.light_energy = 0.55
		lamp.omni_range = 0.9
		lamp.shadow_enabled = false
		who.head.add_child(lamp)
		lamp.position = Vector3(0, -0.05, -0.35)
	elif not on and lamp and is_instance_valid(lamp):
		lamp.queue_free()
		lamp = null


func _run_behind(cam: Camera3D) -> void:
	var f: float = _facing(cam)
	match phase:
		0:   # waiting at your back; follows you while you don't turn
			if f < -0.25:
				_glue_behind()
			if f > 0.75:
				_reveal()
			elif t > 9.0 and phase == 0:
				# you never turned: it leans in and says your name
				get_tree().call_group("hud", "say", who.nick, WHISPER, true)
				phase = 3
				t = 0.0
		1:   # face to face
			if t > 2.4 or (stranger and t > 0.9 and f < 0.4):
				_finish(stranger)
		3:   # the whisper: turn round now and there's nobody there
			if f > 0.6 or t > 3.0:
				_finish(true)
			elif f < -0.25:
				_glue_behind()


func _reveal() -> void:
	phase = 1
	t = 0.0
	who.speak(line, true)


func _run_creep(cam: Camera3D) -> void:
	var p := _player()
	if p == null:
		_finish(true)
		return
	var f: float = _facing(cam)
	var pp := Vector3(p.global_position.x, 0.0, p.global_position.z)
	match phase:
		0:   # in the corner; it only moves while you're not looking
			who.visible = true
			if f < 0.3 and t > 0.7:
				t = 0.0
				var d := pp.distance_to(who.global_position)
				if d < 1.5:
					phase = 2
					_glue_behind()
				else:
					var nxt: Vector3 = who.global_position.move_toward(pp, minf(1.1, d - 1.2))
					who.global_position = Nav.snap(nxt)
					who.look_at(pp, Vector3.UP)
			if t > 25.0:
				_finish(true)
		2:   # at your shoulder
			if f < -0.25:
				_glue_behind()
			if f > 0.75:
				phase = 1
				t = 0.0
				who.speak(line, true)
			elif t > 8.0:
				_finish(true)
		1:
			if t > 2.2 or (t > 0.9 and f < 0.4):
				_finish(true)


## Strangers are gone between one frame and the next; mourners go back to
## their seat as if nothing happened.
func _finish(_vanish: bool) -> void:
	_lamp(false)
	if is_instance_valid(who):
		if stranger:
			who.queue_free()
		else:
			who.end_scare()
	who = null
	kind = K.NONE
	phase = 0


func debug_line() -> String:
	return "scare %s %d %.1f%s" % [K.keys()[kind], phase, t, " hatch armed" if hatch_armed else ""]
