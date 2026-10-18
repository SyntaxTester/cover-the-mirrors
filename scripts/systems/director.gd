extends Node
## When the house goes quiet for too long, something happens. Events are
## chosen so the player can actually notice them, and some carry a hint:
## the photograph that turns upside down belongs to someone with a double.

const GUEST := preload("res://scenes/guest.tscn")

var level: Node3D
var visitors
var portraits
var omens
var next_t := 60.0
var apparition: Node3D
var app_seat: Node3D
var app_seen := 0.0
var app_age := 0.0
var flip_seen := 0.0
var flip_age := 0.0
var last := ""


func _ready() -> void:
	add_to_group("debug")
	level = get_node("../../Level")
	visitors = get_node("../Visitors")
	portraits = get_node_or_null("../Portraits")
	omens = get_node("../Omens")
	Game.night_started.connect(func(_n): next_t = _gap() * 0.8)


func _gap() -> float:
	return float(Game.cfg().get("event_every", 60.0)) * randf_range(0.7, 1.3)


func _calm() -> bool:
	if Game.state != Game.State.PLAY or visitors.at_door != null or omens.danger:
		return false
	for g in visitors.inside:
		if is_instance_valid(g) and g.is_stalking():
			return false
	return true


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _process(dt: float) -> void:
	_watch_apparition(dt)
	_watch_flip(dt)
	if not _calm():
		return
	next_t -= dt
	if next_t > 0.0:
		return
	next_t = _gap()
	var events := ["window", "steps", "mourner", "candles", "portrait", "clock", "dog", "draft"]
	events.erase(last)
	events.shuffle()
	for e in events:
		if call("_ev_" + e):
			last = e
			return


# ── events ───────────────────────────────────────────────────────────────────
func _ev_window() -> bool:
	var m := level.get_node_or_null("Markers/WindowFace") as Node3D
	var face := level.get_node_or_null("Outside/Face") as Node3D
	var p := _player()
	if m == null or p == null or p.global_position.distance_to(m.global_position) > 9.0:
		return false
	Sounds.play_at(self, m.global_position, Sounds.KNOCK, -4.0, "SFX", 1.25, 0.05)
	if face and Sight.sees(self, m.global_position, 10.0, 0.6):
		face.visible = true
		get_tree().create_timer(0.35).timeout.connect(func(): face.visible = false)
	return true


func _ev_steps() -> bool:
	var p := _player()
	if p == null:
		return false
	var behind := p.global_position + p.global_basis.z * 2.6 + Vector3(0, 0.3, 0)
	var s := Sounds.play_at(self, behind, Sounds.STEPS, -4.0, "SFX", 0.9, 0.05)
	if s:
		s.seek(randf() * 35.0)
		get_tree().create_timer(2.2).timeout.connect(s.queue_free)
	return s != null


## Someone sits among the mourners who wasn't let in. Look at them and they're gone.
func _ev_mourner() -> bool:
	if apparition != null or visitors.plan.is_empty():
		return false
	var free: Array = visitors.seats.filter(func(s): return not visitors.taken.has(s) \
		and not Sight.sees(self, (s as Node3D).global_position + Vector3(0, 0.8, 0)))
	if free.is_empty():
		return false
	var tonight: Array = visitors.plan.get("portraits", [])
	var strangers: Array = visitors.looks.keys().filter(func(n): return not tonight.has(n))
	if strangers.is_empty():
		return false
	var n: String = strangers.pick_random()
	var seat: Node3D = free.pick_random()
	var g = GUEST.instantiate()
	level.get_node("Guests").add_child(g)
	g.setup({"name": n, "double": true, "signs": ["dry", "no_breath", "no_shadow"]}, visitors.looks[n])
	g.set_process(false)
	g.global_transform = seat.global_transform
	g.global_position.y = seat.global_position.y - (g.hip_y - 0.05)
	g.legs.rotation.x = PI / 2
	g.knee.rotation.x = -PI / 2
	apparition = g
	app_seat = seat
	visitors.taken[seat] = g   # nobody else gets that chair while it sits there
	app_seen = 0.0
	app_age = 0.0
	return true


func _watch_apparition(dt: float) -> void:
	if apparition == null:
		return
	if not is_instance_valid(apparition):
		_free_seat()
		apparition = null
		return
	app_age += dt
	if Sight.sees(self, apparition.head_pos(), 7.0):
		app_seen += dt
	if app_seen > 0.6 or app_age > 25.0:
		if app_seen > 0.6:
			Sounds.play(self, Sounds.VIOLIN_STING, -12.0)
		apparition.queue_free()
		apparition = null
		_free_seat()


func _free_seat() -> void:
	if app_seat and visitors.taken.has(app_seat) and not visitors.inside.has(visitors.taken[app_seat]):
		visitors.taken.erase(app_seat)
	app_seat = null


func _ev_candles() -> bool:
	var lit := get_tree().get_nodes_in_group("coffin_candles").filter(func(c): return c.lit)
	if lit.is_empty():
		return false
	for c in lit:
		c.chill_for(4.0)
	Sounds.play(self, Sounds.VIOLIN_STING, -14.0)
	return true


## A photograph turns upside down: it's someone whose double walks tonight.
func _ev_portrait() -> bool:
	if portraits == null or portraits.flipped != "":
		return false
	var marked: Array = []
	for e in visitors.queue:
		if e.get("double", false) and not marked.has(e.name):
			marked.append(e.name)
	marked.shuffle()
	for n in marked:
		var pos: Vector3 = portraits.frame_pos(n)
		if pos != Vector3.INF and not Sight.sees(self, pos):
			if portraits.flip(n):
				flip_seen = 0.0
				flip_age = 0.0
				return true
	return false


func _watch_flip(dt: float) -> void:
	if portraits == null or portraits.flipped == "":
		return
	flip_age += dt
	if Sight.sees(self, portraits.frame_pos(portraits.flipped), 6.0):
		flip_seen += dt
	if flip_seen > 2.0 or flip_age > 60.0:
		portraits.unflip()


func _ev_clock() -> bool:
	var a1 := level.get_node_or_null("Hall/Furniture/ClockArrow1") as Node3D
	var a2 := level.get_node_or_null("Hall/Furniture/ClockArrow2") as Node3D
	if a1 == null or a2 == null or not Sight.sees(self, a1.global_position, 8.0):
		return false
	var tw := create_tween().set_parallel()
	tw.tween_property(a1, "rotation:z", a1.rotation.z + TAU, 3.0)
	tw.tween_property(a2, "rotation:z", a2.rotation.z + TAU * 3.0, 3.0)
	Sounds.play(self, Sounds.VIOLIN_RISE, -14.0)
	return true


func _ev_dog() -> bool:
	var dog = level.get_node_or_null("Hall/Dog")
	if dog == null:
		return false
	dog.alert(true)
	get_tree().create_timer(2.5).timeout.connect(_calm_dog.bind(dog))
	return true


func _calm_dog(dog) -> void:
	if visitors.at_door == null and is_instance_valid(dog):
		dog.alert(false)


## The draught from under the door pulls a mirror cloth half off.
func _ev_draft() -> bool:
	var ms := get_tree().get_nodes_in_group("mirrors").filter(func(m): return not m.lifted and not m.slipped)
	if ms.is_empty():
		return false
	ms.pick_random().slip()
	return true


func debug_line() -> String:
	return "director next %.0f last %s" % [next_t, last]
