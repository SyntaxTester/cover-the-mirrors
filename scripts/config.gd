extends Node

var walk_speed := 1.5
var walk_accel := 10.0
var mouse_sens := 0.0022
var bob_freq := 7.0
var bob_amount := 0.025
var interact_dist := 2.0
var zoom_fov := 32.0

var guest_speed := 1.1
var stalk_speed := 0.55
var knock_start := 12.0
var knock_end_margin := 50.0
var knock_jitter := 8.0
var knock_repeat := 10.0
var door_wait := 40.0
var expel_hold := 1.2
var expel_penalty := 15.0
var vigil_start := 80.0
var end_delay := 2.5
var subtitle_time := 4.5

var start_hour := 22.0
var night_hours := 8.0
var bell_every := 45.0

var nights := [
	{
		"duration": 300.0,
		"candle_min": 140.0,
		"candle_max": 200.0,
		"dark_grace": 15.0,
		"soul_up": 14.0,
		"soul_down": 7.0,
		"knocks": 7,
		"doubles": 1,
		"sleep_every": 90.0,
		"vigil_drain": 0.6,
		"vigil_per_guest": 0.5,
		"double_walk_min": 60.0,
		"double_walk_max": 80.0,
	},
	{
		"duration": 360.0,
		"candle_min": 110.0,
		"candle_max": 170.0,
		"dark_grace": 12.0,
		"soul_up": 18.0,
		"soul_down": 5.0,
		"knocks": 10,
		"doubles": 2,
		"sleep_every": 70.0,
		"vigil_drain": 0.8,
		"vigil_per_guest": 0.5,
		"double_walk_min": 50.0,
		"double_walk_max": 70.0,
	},
	{
		"duration": 420.0,
		"candle_min": 90.0,
		"candle_max": 150.0,
		"dark_grace": 10.0,
		"soul_up": 22.0,
		"soul_down": 4.0,
		"knocks": 11,
		"doubles": 3,
		"sleep_every": 55.0,
		"vigil_drain": 1.0,
		"vigil_per_guest": 0.5,
		"double_walk_min": 40.0,
		"double_walk_max": 60.0,
	},
]
