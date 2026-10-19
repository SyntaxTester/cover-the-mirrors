extends Interactable

@onready var swing: Node3D = $Swing
@onready var knock_snd: AudioStreamPlayer3D = $Knock

var open_t := 0.0
var ang := 0.0
var rattle := 0.0
var wind: AudioStreamPlayer3D
var was_open := false
var passers: Array = []
var center := Vector3.ZERO

const WIND_SHUT_DB := -24.0     # wind heard through the closed door
const WIND_OPEN_DB := -8.0      # wind rushing in while it stands open


func _ready() -> void:
	prompt = "Let in"
	add_to_group("front_door")
	center = to_global(Vector3(0.5, 0, 0))
	knock_snd.unit_size = 9.0
	knock_snd.max_db = 6.0
	knock_snd.volume_db = 4.0
	# wind outside: always there, louder when the door (or the hatch) is open
	wind = AudioStreamPlayer3D.new()
	wind.stream = Sounds.looped(Sounds.WIND)
	wind.bus = "Ambience"
	wind.unit_size = 4.0
	wind.volume_db = WIND_SHUT_DB
	add_child(wind)
	var outside := get_node_or_null("../Markers/KnockSpot") as Node3D   # where visitors stand
	if outside:
		wind.global_position = outside.global_position + Vector3(0, 1.4, 0)
	else:
		wind.position = Vector3(0, 1.4, 0)
	wind.play(randf() * 60.0)


func can_interact(_p: Node) -> bool:
	var v = get_tree().get_first_node_in_group("visitors")
	return v != null and v.can_let_in()


func interact(_p: Node) -> void:
	get_tree().call_group("visitors", "let_in")


func swing_open(t: float) -> void:
	if open_t <= 0.0 and ang > -0.05:
		Sounds.play_at(self, swing.global_position + Vector3(0, 1.2, 0), Sounds.DOOR_OPEN, -4.0, "SFX", 1.0, 0.05)
	open_t = maxf(open_t, t)


func pass_through(g, side: float) -> void:
	passers.append([g, side])


func stop_knock() -> void:
	rattle = 0.0
	if knock_snd.playing:
		var tw := create_tween()
		tw.tween_property(knock_snd, "volume_db", -40.0, 0.12)
		tw.tween_callback(func():
			knock_snd.stop()
			knock_snd.volume_db = 4.0)


## A random knock each time (see Sounds.KNOCK), slightly different pitch.
func knock() -> void:
	rattle = 0.35
	var s := Sounds.pick(Sounds.KNOCK)
	if s:
		knock_snd.stream = s
	knock_snd.pitch_scale = randf_range(0.94, 1.06)
	knock_snd.volume_db = 4.0
	if knock_snd.stream:
		knock_snd.play()


func _process(dt: float) -> void:
	_passers()
	open_t -= dt
	rattle = maxf(rattle - dt, 0.0)
	var tgt := -1.35 if open_t > 0.0 else 0.0
	ang = move_toward(ang, tgt, dt * 1.8)
	swing.rotation.y = ang + (sin(rattle * 90.0) * 0.012 if rattle > 0.0 else 0.0)
	var is_open := ang < -0.02
	if was_open and not is_open:   # just swung shut
		Sounds.play_at(self, swing.global_position + Vector3(0, 1.2, 0), Sounds.DOOR_CLOSE, -2.0, "SFX", 1.0, 0.05)
	was_open = is_open
	var hatch = get_tree().get_first_node_in_group("hatch")
	var openness := clampf(-ang / 1.35, 0.0, 1.0)
	if hatch and hatch.open:
		openness = maxf(openness, 0.35)
	wind.volume_db = lerpf(wind.volume_db, lerpf(WIND_SHUT_DB, WIND_OPEN_DB, openness), dt * 3.0)


func _passers() -> void:
	var near := false
	for i in range(passers.size() - 1, -1, -1):
		var g = passers[i][0]
		var side: float = passers[i][1]
		if not is_instance_valid(g):
			passers.remove_at(i)
			continue
		var gp: Vector3 = g.global_position
		if (gp.x - center.x) * side > 0.7:
			passers.remove_at(i)
			continue
		if Vector2(gp.x - center.x, gp.z - center.z).length() < 2.6:
			near = true
	if near:
		swing_open(0.7)
