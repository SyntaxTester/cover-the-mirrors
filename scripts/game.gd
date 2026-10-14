extends Node

signal night_started(n: int)
signal night_lost(reason: String)
signal night_won(n: int)
signal bell

enum State { PLAY, LOST, WON }

var state := State.PLAY
var night := 0
var t := 0.0
var bell_t := 0.0


func cfg() -> Dictionary:
	return Config.nights[night]


func start_night(n: int) -> void:
	night = clampi(n, 0, Config.nights.size() - 1)
	t = 0.0
	bell_t = 0.0
	state = State.PLAY
	night_started.emit(night)


func _process(dt: float) -> void:
	if state != State.PLAY:
		return
	t += dt
	bell_t += dt
	if bell_t >= Config.bell_every:
		bell_t -= Config.bell_every
		bell.emit()
	if t >= cfg().duration:
		state = State.WON
		night_won.emit(night)


func progress() -> float:
	return clampf(t / cfg().duration, 0.0, 1.0)


func clock() -> String:
	var m := int(Config.start_hour * 60.0 + progress() * Config.night_hours * 60.0) % 1440
	return "%02d:%02d" % [int(m / 60.0), m % 60]


func lose(reason: String) -> void:
	if state != State.PLAY:
		return
	state = State.LOST
	night_lost.emit(reason)


func is_last() -> bool:
	return night >= Config.nights.size() - 1


func restart() -> void:
	get_tree().reload_current_scene()


func next_night() -> void:
	night = mini(night + 1, Config.nights.size() - 1)
	get_tree().reload_current_scene()


func new_game() -> void:
	night = 0
	get_tree().reload_current_scene()
