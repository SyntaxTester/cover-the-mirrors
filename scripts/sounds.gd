class_name Sounds
extends RefCounted
## Every sound the game plays from code, in one place.
## A list means variants: one is picked at random each time, so adding a file
## to a list (e.g. a new knock) is all it takes to get more variety.

const KNOCK := [
	preload("res://assets/sounds/knock_1.wav"),
	preload("res://assets/sounds/knock_2.wav"),
	preload("res://assets/sounds/knock_3.wav"),
]
const DOOR_OPEN := [preload("res://assets/sounds/DOOR_OPEN_Modified_ver.mp3")]
const DOOR_CLOSE := [preload("res://assets/sounds/DOOR_CLOSE_Modified_ver.mp3")]
const CLOTH := [preload("res://assets/sounds/Clothing_ruffle_2.wav")]
const STEPS := preload("res://assets/sounds/Steps_sounds.wav")
const WIND := preload("res://assets/sounds/wind_outside.mp3")

const UI_OPEN := preload("res://assets/sounds/UI_Open_sfx.mp3")
const UI_CLOSE := preload("res://assets/sounds/UI_Close_sfx.mp3")
const UI_SELECT := preload("res://assets/sounds/UI_Selection_sfx.mp3")
const TEXT := preload("res://assets/sounds/text_sound.mp3")

const MUSIC_NIGHT := preload("res://assets/sounds/COVER_THE_MIRRORS_-_Irish_folklore.mp3")
const MUSIC_MORNING := preload("res://assets/sounds/CTM_-_Main_Theme_2_Variant_2.mp3")

const JUMPSCARE := preload("res://assets/sounds/Piano_jumpscare.mp3")
const CHASE := preload("res://assets/sounds/Scary_chase_sound.mp3")
const RISER := preload("res://assets/sounds/universfield-suspense-riser-191979.mp3")
const VIOLIN_RISE := preload("res://assets/sounds/Increasing_spooky_violin_sound.mp3")
const VIOLIN_STING := preload("res://assets/sounds/Sudden_spooky_violin_sound.mp3")
const VIOLINS := preload("res://assets/sounds/Scary_violins.mp3")
const HEART := preload("res://assets/sounds/A_bit_rapid_heartbeat.mp3")
const THUNDER := [   # compressed, bass-boosted and normalised copies of thunder_1..3.wav
	preload("res://assets/sounds/thunder_loud_1.ogg"),
	preload("res://assets/sounds/thunder_loud_2.ogg"),
	preload("res://assets/sounds/thunder_loud_3.ogg"),
]
const THUNDER_NEAR := preload("res://assets/sounds/thunder_strike.ogg")   # a strike right over the house
## Esmagzam's noises: a different one every time he comes to the door.
const ESMAGZAM := [
	preload("res://assets/sounds/esmagzam_1.ogg"),   # hee hee
	preload("res://assets/sounds/esmagzam_2.ogg"),   # higher and quicker
	preload("res://assets/sounds/esmagzam_3.ogg"),   # slow and low, in an echo
	preload("res://assets/sounds/esmagzam_4.ogg"),   # backwards
]
const SKITTER := preload("res://assets/sounds/skitter.wav")
const SCREAM := preload("res://assets/sounds/scream.wav")


## One stream from a list of variants (or the stream itself).
static func pick(s: Variant) -> AudioStream:
	if s is Array:
		var a: Array = s
		return a.pick_random() if not a.is_empty() else null
	return s as AudioStream


## A looping copy of a stream (the shared resource is left untouched).
static func looped(s: AudioStream) -> AudioStream:
	var c := s.duplicate() as AudioStream
	if c is AudioStreamMP3:
		(c as AudioStreamMP3).loop = true
	elif c is AudioStreamOggVorbis:
		(c as AudioStreamOggVorbis).loop = true
	elif c is AudioStreamWAV:
		var w := c as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return c


## Fire-and-forget 2D sound (music stingers, UI). Frees itself when done.
static func play(owner: Node, s: Variant, volume_db := 0.0, bus := "SFX", pitch_jitter := 0.0) -> AudioStreamPlayer:
	var stream := pick(s)
	if stream == null or owner == null or not owner.is_inside_tree():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = bus
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	owner.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Fire-and-forget positional sound at a world position. Frees itself when done.
static func play_at(owner: Node, pos: Vector3, s: Variant, volume_db := 0.0, bus := "SFX",
		pitch := 1.0, pitch_jitter := 0.0, unit_size := 3.0) -> AudioStreamPlayer3D:
	var stream := pick(s)
	if stream == null or owner == null or not owner.is_inside_tree():
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = bus
	p.unit_size = unit_size
	p.pitch_scale = pitch + randf_range(-pitch_jitter, pitch_jitter)
	owner.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p
