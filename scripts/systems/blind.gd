extends CanvasLayer

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float k = 0.0;
uniform float t = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	uv += vec2(sin(uv.y * 40.0 + t * 3.0), cos(uv.x * 35.0 + t * 2.0)) * 0.004 * k;
	vec3 c = textureLod(screen_tex, uv, k * 4.0).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g) * vec3(0.9, 0.95, 1.05), k * 0.85);
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.7, 1.0);
	float r = length(d);
	float rad = mix(1.25, 0.1, k);
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


func _exit_tree() -> void:
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


func debug_line() -> String:
	return "blind %.2f" % k
