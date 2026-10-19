extends Node

signal plan_ready(plan: Dictionary)
signal visitor_arrived(g)
signal visitor_spoke(g)

const GUEST := preload("res://scenes/guest.tscn")
const IN_PT := Vector3(13.2, 0, 2.6)
const OUT_PT := Vector3(15.4, 0, 2.6)
const LANE_FAR := Vector3(36.0, 0, 13.0)
const LANE_GATE := Vector3(21.6, 0, 13.0)
const YARD := Vector3(17.6, 0, 8.2)
const FIELD := [Vector3(19.4, 0, -2.2), Vector3(17.2, 0, 0.6)]
const AWAY := [Vector3(17.6, 0, 8.2), Vector3(21.6, 0, 13.0), Vector3(36.0, 0, 13.0)]
const DEATHS := [
	"%s was found by the bog road at first light.",
	"They pulled %s out of the bog water at dawn, a lantern still in hand.",
	"%s never made it home. A shawl was left caught on the hawthorn by the road.",
	"At first light %s lay face down in the ditch at the crossroads.",
	"%s was found sitting against the chapel wall, cold as stone, eyes open.",
	"Only %s's boots were found, side by side at the edge of the bog.",
	"The carter found %s on the road at dawn. Nobody would say how they looked.",
]
const STALK := [Vector3(7.4, 0, 4.4), Vector3(5.4, 0, 4.4), Vector3(4.05, 0, 3.55)]

var level: Node3D
var holder: Node3D
var spot: Node3D
var hatch
var door
var dog
var board: Label3D
var lamp: OmniLight3D
var lamp_energy := 0.0
var lamp_col := Color.WHITE
var raw: Dictionary = {}
var plan: Dictionary = {}
var queue: Array = []
var looks: Dictionary = {}
var times: Array = []
var idx := 0
var at_door
var approaching
var door_t := 0.0
var knock_t := 0.0
var spoken := false
var inside: Array = []
var seats: Array = []
var taken := {}
var sleep_t := 0.0
var report: Array = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("visitors")
	add_to_group("debug")
	level = get_node("../../Level")
	holder = level.get_node("Guests")
	spot = level.get_node("Markers/KnockSpot")
	hatch = level.get_node("FrontDoor/Swing/Hatch")
	door = level.get_node("FrontDoor")
	dog = level.get_node("Hall/Dog")
	board = level.get_node("Hall/GuestList")
	lamp = level.get_node_or_null("Hall/DoorLamp/Light") as OmniLight3D
	if lamp:
		lamp_energy = lamp.light_energy
		lamp_col = lamp.light_color
	seats = level.get_node("Markers/Seats").get_children()
	rng.randomize()
	Game.night_started.connect(begin)
	Game.night_won.connect(_morning)


func begin(n: int) -> void:
	raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/guests.json"))
	looks = raw.get("looks", {})
	plan = NightPlan.build(n, raw, Game.run, rng)
	queue = plan.queue
	var k := queue.size()
	times.clear()
	var t0: float = Config.knock_start
	var t1: float = Game.cfg().duration - Config.knock_end_margin
	for i in k:
		if i == 0:
			times.append(t0)
		else:
			times.append(lerpf(t0, t1, float(i) / maxf(k - 1, 1)) + randf_range(-Config.knock_jitter, Config.knock_jitter))
	Game.doubles_total = 0
	for e in queue:
		if e.get("double", false):
			Game.doubles_total += 1
	sleep_t = next_sleep()
	update_board()
	plan_ready.emit(plan)


func next_sleep() -> float:
	return Game.cfg().sleep_every * randf_range(0.7, 1.3)


func _process(dt: float) -> void:
	if Game.state != Game.State.PLAY:
		return
	if at_door == null and approaching == null and idx < times.size() and Game.t >= times[idx]:
		arrive(queue[idx])
		idx += 1
	if at_door != null:
		door_t += dt
		if not hatch.open:
			knock_t -= dt
			if knock_t <= 0.0:
				door.knock()
				knock_t = Config.knock_repeat
			if door_t >= Config.door_wait:
				turn_away()
	_lamp(dt)
	sleep_t -= dt
	if sleep_t <= 0.0:
		sleep_t = next_sleep()
		var c := inside.filter(func(g): return g.can_sleep())
		if not c.is_empty():
			# the drunk and the old dozers go first
			var heavy := c.filter(func(g): return g.role in ["drunk", "sleepy"])
			var pick = heavy.pick_random() if not heavy.is_empty() and randf() < 0.6 else c.pick_random()
			pick.fall_asleep()


## The lamp by the door burns low and blue while a cold one stands outside.
func _lamp(dt: float) -> void:
	if lamp == null:
		return
	var cold: bool = at_door != null and is_instance_valid(at_door) and at_door.sign_on("cold")
	var k := 1.0 if cold else 0.0
	lamp.light_color = lamp.light_color.lerp(lamp_col.lerp(Color(0.55, 0.7, 1.0), k), dt * 2.0)
	var flick := 1.0 - (0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.03)) * k
	lamp.light_energy = lerpf(lamp.light_energy, lamp_energy * flick, dt * 6.0)


func arrive(e: Dictionary) -> void:
	var g = GUEST.instantiate()
	holder.add_child(g)
	g.setup(e, looks.get(e.get("name", ""), {}))
	var from_field: bool = g.double and rng.randf() < Config.double_field_chance
	var pts: Array = FIELD.duplicate() if from_field else [LANE_GATE, YARD]
	pts.append(Vector3(spot.global_position.x, 0.0, spot.global_position.z))
	g.global_position = pts[0] if from_field else LANE_FAR
	g.approach(pts, spot.global_rotation.y)
	approaching = g


func arrive_now(e: Dictionary) -> void:
	var g = GUEST.instantiate()
	holder.add_child(g)
	g.global_transform = spot.global_transform
	g.setup(e, looks.get(e.get("name", ""), {}))
	on_at_spot(g)


func on_at_spot(g) -> void:
	if approaching == g:
		approaching = null
	at_door = g
	door_t = 0.0
	knock_t = 0.2
	spoken = false
	if g.sign_on("dog_growl"):
		dog.alert(true)
	visitor_arrived.emit(g)
	get_tree().call_group("roles", "on_visitor_arrived", g)
	if hatch.open:
		hatch_changed(true)


func hatch_changed(o: bool) -> void:
	if at_door == null:
		return
	if o:
		door.stop_knock()
	if o and not spoken:
		spoken = true
		at_door.say()
		visitor_spoke.emit(at_door)
		get_tree().call_group("roles", "on_visitor_spoke", at_door)
	elif not o and spoken:
		turn_away()


func can_let_in() -> bool:
	return at_door != null and hatch.open


func let_in() -> void:
	if not can_let_in():
		return
	var g = at_door
	at_door = null
	dog.alert(false)
	door.stop_knock()
	hatch.set_open(false)
	door.pass_through(g, -1.0)
	var s := free_seat()
	taken[s] = g
	g.walk_in(s, [IN_PT])
	inside.append(g)
	if g.double:
		Game.doubles_let += 1
		Game.run.doubles_let += 1
	update_board()


func turn_away() -> void:
	var g = at_door
	at_door = null
	dog.alert(false)
	door.stop_knock()
	if not g.double:
		# a real neighbour left out in the rain on a night like this...
		Game.run.humans_refused += 1
		if not Game.run.refused_tonight.has(g.nick):
			Game.run.refused_tonight.append(g.nick)
	g.leave(AWAY)


func expel(g) -> void:
	if not inside.has(g):
		return
	inside.erase(g)
	taken.erase(g.seat)
	if not g.double:
		get_tree().call_group("vigil", "penalty")
		Game.run.humans_expelled += 1
	else:
		Game.run.doubles_expelled += 1
		Sounds.play(self, Sounds.VIOLINS, -8.0)   # you were right: it was one of them
	door.pass_through(g, 1.0)
	if randf() < Config.expel_draft_chance:
		_draft()
	g.leave([IN_PT, OUT_PT] + AWAY)
	update_board()


## Opening the door at night lets the wind in: one candle may go out.
func _draft() -> void:
	var lit := get_tree().get_nodes_in_group("coffin_candles").filter(func(c): return c.lit)
	if lit.size() > 1:
		var c = lit.pick_random()
		get_tree().create_timer(1.5).timeout.connect(_blow_out.bind(c))


func _blow_out(c) -> void:
	if is_instance_valid(c) and c.lit:
		c.put_out()


## A double made it to the coffin: it is gone, and the dead man stirs.
func double_reached(g) -> void:
	inside.erase(g)
	taken.erase(g.seat)
	update_board()
	if get_tree().get_first_node_in_group("attack"):
		get_tree().call_group("attack", "begin", g)
		return
	Sounds.play(self, Sounds.JUMPSCARE, -4.0)
	g.queue_free()
	Game.corpse_stir()


func free_seat() -> Node3D:
	var c := seats.filter(func(s): return not taken.has(s))
	return c.pick_random() if not c.is_empty() else seats[0]


func awake_count() -> int:
	return inside.filter(func(g): return g.is_awake()).size()


func asleep_count() -> int:
	return inside.filter(func(g): return g.is_asleep()).size()


func stalk_path() -> Array:
	return STALK


func update_board() -> void:
	var names := PackedStringArray()
	for g in inside:
		names.append(g.nick)
	board.text = "INSIDE:\n" + ("\n".join(names) if names.size() > 0 else "-")


## Dawn: who is missing, and who sat with us that shouldn't have.
func _morning(_n: int) -> void:
	report.clear()
	var lines: Array = DEATHS.duplicate()
	lines.shuffle()
	var i := 0
	for n in Game.run.refused_last:
		report.append(lines[i % lines.size()] % n)
		i += 1
		if not Game.run.lost.has(n):
			Game.run.lost.append(n)
	var left := inside.filter(func(g): return is_instance_valid(g) and g.double)
	Game.run.doubles_left_inside += left.size()
	for g in left:
		report.append("%s's chair was cold at dawn. Nobody saw them leave." % g.nick)


func debug_line() -> String:
	var nxt := "-"
	if idx < times.size():
		nxt = "%.0f" % times[idx]
	var who := "-"
	if at_door:
		who = "%s%s %s" % [at_door.nick, " (D)" if at_door.double else "", at_door.signs]
	return "guests %d awake %d  door %s  knock %d/%d next %s  sleep %.0f  corpse %d" % [
		inside.size(), awake_count(), who, idx, times.size(), nxt, sleep_t, Game.run.corpse_stage]
