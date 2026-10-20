extends CanvasLayer

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float k = 0.0;
uniform float t = 0.0;
uniform float pulse = 0.0;   // heartbeat thump
void fragment() {
	vec2 uv = SCREEN_UV;
	uv = (uv - 0.5) * (1.0 - pulse * 0.018) + 0.5;
	uv += vec2(sin(uv.y * 40.0 + t * 3.0), cos(uv.x * 35.0 + t * 2.0)) * 0.004 * k;
	vec3 c = textureLod(screen_tex, uv, k * 4.0).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g) * vec3(0.9, 0.95, 1.05), k * 0.85);
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.7, 1.0);
	float r = length(d);
	float rad = mix(1.25, 0.1, k) - pulse * 0.12 * (0.3 + k);
	float v = 1.0 - smoothstep(rad - 0.32, rad, r);
	c *= v * (1.0 - 0.5 * k);
	COLOR = vec4(c, 1.0);
}
"""

var rect: ColorRect
var mat: ShaderMaterial
var soul
var lp: AudioEffectLowPassFilter
var bus := 0
var fx := -1
var k := 0.0
var heart: AudioStreamPlayer
var beat := 0.0

const HEART := preload("res://assets/sounds/heartbeat_mirror.ogg")
## Onsets (seconds) of every beat in the heartbeat recording, for the screen thump.
const BEATS := [0.47, 0.78, 1.46, 1.76, 2.66, 2.94, 3.52, 3.79, 4.42, 4.7, 5.54, 5.84, 6.52, 6.82,
	7.73, 8.0, 8.59, 8.85, 9.48, 9.77, 10.39, 11.16, 11.46, 12.14, 12.44, 13.35, 13.62, 14.21,
	14.47, 15.11, 15.39, 16.22, 16.53, 17.21, 17.51, 18.41, 18.69, 19.27, 19.53, 20.16, 20.45, 21.08]


func _ready() -> void:
	layer = 4
	add_to_group("debug")
	rect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	rect.visible = false
	add_child(rect)
	soul = get_node_or_null("../Soul")
	bus = AudioServer.get_bus_index("Master")
	lp = AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(bus, lp)
	fx = AudioServer.get_bus_effect_count(bus) - 1
	# the heartbeat while you stare into the glass (its low thump survives the
	# muffling above, which is the point: it's the only clear sound left)
	if AudioServer.get_bus_index("Heart") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Heart")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	heart = AudioStreamPlayer.new()
	heart.stream = Sounds.looped(HEART)
	heart.bus = "Heart"
	heart.volume_db = -40.0
	add_child(heart)


func _exit_tree() -> void:
	if heart:
		heart.stop()
	if fx >= 0 and fx < AudioServer.get_bus_effect_count(bus) and AudioServer.get_bus_effect(bus, fx) == lp:
		AudioServer.remove_bus_effect(bus, fx)


func _process(dt: float) -> void:
	var s: float = soul.soul if soul else 0.0
	var want := smoothstep(Config.blind_from, 98.0, s)
	if Game.state == Game.State.LOST or Game.state == Game.State.WON:
		want = 0.0
	k = move_toward(k, want, dt * 0.8)
	rect.visible = k > 0.005
	mat.set_shader_parameter("k", k)
	mat.set_shader_parameter("t", Time.get_ticks_msec() * 0.001)
	lp.cutoff_hz = lerpf(20000.0, 450.0, pow(k, 0.7))
	_heart(dt, s)


## Louder and faster the longer you look; it thumps the picture with each beat.
func _heart(dt: float, s: float) -> void:
	var on := Game.state == Game.State.PLAY and s > Config.blind_from * 0.5
	var h := clampf((s - Config.blind_from * 0.5) / (100.0 - Config.blind_from * 0.5), 0.0, 1.0)
	if on and not heart.playing:
		heart.play(randf() * 4.0)
	var want_db := lerpf(-8.0, 6.0, h) if on else -50.0
	heart.volume_db = move_toward(heart.volume_db, want_db, dt * (30.0 if on else 12.0))
	heart.pitch_scale = lerpf(1.0, 1.7, h * h)
	if heart.playing and heart.volume_db <= -49.0 and not on:
		heart.stop()
	# thump: the time since the last beat in the recording
	beat = maxf(beat - dt * 6.0, 0.0)
	if heart.playing:
		var p := heart.get_playback_position()
		for b in BEATS:
			if p >= b and p - b < dt * heart.pitch_scale + 0.001:
				beat = 1.0
	var vol := clampf((heart.volume_db + 20.0) / 26.0, 0.0, 1.0)
	mat.set_shader_parameter("pulse", beat * vol)
	rect.visible = rect.visible or (beat * vol > 0.02)


func debug_line() -> String:
	return "blind %.2f" % k
