extends Node

signal night_started(n: int)
signal night_lost(reason: String)
signal night_won(n: int)
signal bell
signal corpse_stirred(stage: int)

enum State { PLAY, LOST, WON }

var state := State.PLAY
var night := 0
var t := 0.0
var bell_t := 0.0
var doubles_let := 0
var doubles_total := 0
## What happened over the whole run (all nights); decides the ending.
var run := {}
var run_at_night_start := {}


func _ready() -> void:
	reset_run()


func reset_run() -> void:
	run = {
		"corpse_stage": 0,        # doubles that reached the coffin
		"refused_tonight": [],    # real guests left out in the rain tonight
		"refused_last": [],       # ...last night: their doubles come back
		"lost": [],               # everyone who didn't make it, for the ending
		"humans_refused": 0,
		"humans_expelled": 0,
		"doubles_let": 0,
		"doubles_expelled": 0,
		"doubles_left_inside": 0,
	}


func cfg() -> Dictionary:
	return Config.nights[night]


func start_night(n: int) -> void:
	night = clampi(n, 0, Config.nights.size() - 1)
	t = 0.0
	bell_t = 0.0
	doubles_let = 0
	state = State.PLAY
	if run.is_empty():
		reset_run()
	run_at_night_start = run.duplicate(true)
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
		run.refused_last = run.refused_tonight.duplicate()
		run.refused_tonight = []
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
	run = run_at_night_start.duplicate(true)   # replay the night as it began
	get_tree().reload_current_scene()


func next_night() -> void:
	night = mini(night + 1, Config.nights.size() - 1)
	get_tree().reload_current_scene()


func new_game() -> void:
	night = 0
	reset_run()
	get_tree().reload_current_scene()


## A double reached the coffin. The dead man stirs; at the last stage he sits up.
func corpse_stir() -> void:
	if state != State.PLAY:
		return
	run.corpse_stage += 1
	corpse_stirred.emit(run.corpse_stage)
	if run.corpse_stage >= Config.corpse_stages:
		lose("double")
