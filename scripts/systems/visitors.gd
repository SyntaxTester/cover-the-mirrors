extends Node

const GUEST := preload("res://scenes/guest.tscn")
const IN_PT := Vector3(13.2, 0, 2.6)
const OUT_PT := Vector3(15.4, 0, 2.6)
const AWAY := [Vector3(17.0, 0, 4.2), Vector3(19.5, 0, 7.0)]
const STALK := [Vector3(7.4, 0, 4.4), Vector3(5.4, 0, 4.4), Vector3(4.05, 0, 3.55)]

var level: Node3D
var holder: Node3D
var spot: Node3D
var hatch
var door
var dog
var board: Label3D
var queue: Array = []
var looks: Dictionary = {}
var times: Array = []
var idx := 0
var at_door
var door_t := 0.0
var knock_t := 0.0
var spoken := false
var inside: Array = []
var seats: Array = []
var taken := {}
var sleep_t := 0.0


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
	seats = level.get_node("Markers/Seats").get_children()
	Game.night_started.connect(begin)


func begin(n: int) -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/guests.json"))
	looks = raw.get("looks", {})
	var nights: Array = raw.get("nights", [])
	queue = nights[n] if n < nights.size() else []
	var k := mini(int(Game.cfg().knocks), queue.size())
	queue = queue.slice(0, k)
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


func next_sleep() -> float:
	return Game.cfg().sleep_every * randf_range(0.7, 1.3)


func _process(dt: float) -> void:
	if Game.state != Game.State.PLAY:
		return
	if at_door == null and idx < times.size() and Game.t >= times[idx]:
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
	sleep_t -= dt
	if sleep_t <= 0.0:
		sleep_t = next_sleep()
		var c := inside.filter(func(g): return g.can_sleep())
		if not c.is_empty():
			c.pick_random().fall_asleep()


func arrive(e: Dictionary) -> void:
	var g = GUEST.instantiate()
	holder.add_child(g)
	g.global_transform = spot.global_transform
	g.setup(e, looks.get(e.get("name", ""), {}))
	at_door = g
	door_t = 0.0
	knock_t = 0.3
	spoken = false
	if g.sign_on("dog_growl"):
		dog.alert(true)


func hatch_changed(o: bool) -> void:
	if at_door == null:
		return
	if o and not spoken:
		spoken = true
		at_door.say()
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
	hatch.set_open(false)
	door.swing_open(3.5)
	var s := free_seat()
	taken[s] = g
	g.walk_in(s, [IN_PT])
	inside.append(g)
	if g.double:
		Game.doubles_let += 1
	update_board()


func turn_away() -> void:
	var g = at_door
	at_door = null
	dog.alert(false)
	g.leave(AWAY)


func expel(g) -> void:
	if not inside.has(g):
		return
	inside.erase(g)
	taken.erase(g.seat)
	if not g.double:
		get_tree().call_group("vigil", "penalty")
	door.swing_open(6.0)
	g.leave([IN_PT, OUT_PT] + AWAY)
	update_board()


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


func debug_line() -> String:
	var nxt := "-"
	if idx < times.size():
		nxt = "%.0f" % times[idx]
	return "guests %d awake %d  door %s  knock %d/%d next %s  sleep %.0f" % [inside.size(), awake_count(), at_door.nick if at_door else "-", idx, times.size(), nxt, sleep_t]
