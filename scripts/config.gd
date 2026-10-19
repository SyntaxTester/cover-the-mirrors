extends Node

var walk_speed := 1.5
var walk_accel := 10.0
var mouse_sens := 0.0022
var bob_freq := 7.0
var bob_amount := 0.025
var interact_dist := 2.0
var zoom_fov := 32.0

var guest_speed := 1.1
var stalk_speed := 1.5         # a double only moves while nobody is looking at it
var sight_dist := 14.0         # how far the player "sees" a double / an apparition
var signs_per_double := 2
var human_sign_chance := 0.2   # a real guest shows one innocent-looking sign
var expel_draft_chance := 0.5  # opening the door to throw someone out may blow a candle out
var corpse_stages := 3         # doubles reaching the coffin before the dead man sits up
var knock_start := 4.0
var knock_end_margin := 50.0
var knock_jitter := 8.0
var knock_repeat := 10.0
var door_wait := 40.0
var expel_hold := 1.2
var expel_penalty := 15.0
var vigil_start := 80.0
var end_delay := 2.5
var subtitle_time := 6.5

var approach_speed := 1.4
var rush_speed := 3.4
var double_field_chance := 0.4
var attack_dark := 5.5
var attack_reveal := 1.6
var attack_speed := 8.5
var attack_catch_dist := 1.3
var storm_min := 28.0
var storm_max := 65.0
var blind_from := 30.0

var start_hour := 22.0
var night_hours := 8.0
var bell_every := 45.0

var nights := [
	{
		"duration": 330.0,
		"candle_min": 140.0,
		"candle_max": 200.0,
		"dark_grace": 15.0,
		"soul_up": 14.0,
		"soul_down": 7.0,
		"questions": 4,
		"sabotage_min": 15.0,
		"sabotage_max": 25.0,
		"event_every": 42.0,
		"signs": ["no_breath", "clean_boots", "dog_growl", "dry", "wrong_answer", "wrong_detail"],
		"doubles": 1,
		"sleep_every": 90.0,
		"vigil_drain": 0.6,
		"vigil_per_guest": 0.5,
		"double_walk_min": 35.0,
		"double_walk_max": 55.0,
	},
	{
		"duration": 420.0,
		"candle_min": 110.0,
		"candle_max": 170.0,
		"dark_grace": 12.0,
		"soul_up": 18.0,
		"soul_down": 5.0,
		"questions": 3,
		"sabotage_min": 12.0,
		"sabotage_max": 20.0,
		"event_every": 34.0,
		"signs": ["no_breath", "clean_boots", "dog_growl", "dry", "wrong_answer", "wrong_detail", "no_shadow"],
		"doubles": 2,
		"sleep_every": 70.0,
		"vigil_drain": 0.8,
		"vigil_per_guest": 0.5,
		"double_walk_min": 28.0,
		"double_walk_max": 42.0,
	},
	{
		"duration": 510.0,
		"candle_min": 90.0,
		"candle_max": 150.0,
		"dark_grace": 10.0,
		"soul_up": 22.0,
		"soul_down": 4.0,
		"questions": 3,
		"sabotage_min": 9.0,
		"sabotage_max": 16.0,
		"event_every": 26.0,
		"signs": ["no_breath", "clean_boots", "dog_growl", "dry", "wrong_answer", "wrong_detail", "no_shadow", "cold"],
		"doubles": 3,
		"sleep_every": 55.0,
		"vigil_drain": 1.0,
		"vigil_per_guest": 0.5,
		"double_walk_min": 20.0,
		"double_walk_max": 32.0,
	},
]
