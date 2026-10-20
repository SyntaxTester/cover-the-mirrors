extends Node

const CREATURE := preload("res://scripts/creature.gd")

enum Phase { IDLE, DARK, REVEAL, RUSH, CATCH, DONE }

const DOORS := {
	"coffin": [Vector3(5.3, 0, 4.4), Vector3(6.7, 0, 4.4)],
	"bed": [Vector3(5.3, 0, 6.7), Vector3(6.7, 0, 6.7)],
	"out": [Vector3(14.9, 0, 2.6), Vector3(13.3, 0, 2.6)],
}

var phase := Phase.IDLE
var t := 0.0
var level: Node3D
var creature: Node3D
var env: Environment
var amb := 0.0
var skitter: AudioStreamPlayer3D
var heart: AudioStreamPlayer
var flash: ColorRect
var via := Vector3.INF
var cam: Camera3D
var shake := 0.0
var glitch: ColorRect
var glitch_mat: ShaderMaterial
var nav_goal := Vector3.INF
var nav_t := 0.0

## The catch: the picture tears, colours split, it flickers to negative.
const GLITCH := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float k = 0.0;
uniform float seed = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float band = floor(uv.y * 24.0);
	uv.x += (h(vec2(band, 1.0)) - 0.5) * 0.09 * k * step(0.55, h(vec2(band, 2.0)));
	float sp = 0.018 * k;
	vec3 c = vec3(texture(screen_tex, uv + vec2(sp, 0.0)).r, texture(screen_tex, uv).g,
		texture(screen_tex, uv - vec2(sp, 0.0)).b);
	c = mix(c, vec3(1.0) - c, step(0.9, h(vec2(seed, 3.0))) * step(0.5, k));
	c += (h(floor(FRAGCOORD.xy * 0.5)) - 0.5) * 0.12 * k;
	c *= mix(vec3(1.0), vec3(1.3, 0.55, 0.5), k * 0.6);
	COLOR = vec4(c, 1.0);
}
"""


func _ready() -> void:
	add_to_group("attack")
	add_to_group("debug")
	level = get_node("../../Level")
	var we := level.get_node_or_null("Env") as WorldEnvironment
	if we:
		env = we.environment
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	flash = ColorRect.new()
	flash.color = Color(0, 0, 0, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(flash)
	glitch = ColorRect.new()
	glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = GLITCH
	glitch_mat = ShaderMaterial.new()
	glitch_mat.shader = sh
	glitch.material = glitch_mat
	glitch.visible = false
	layer.add_child(glitch)
	layer.move_child(glitch, 0)


func begin(g) -> void:
	if phase != Phase.IDLE or Game.state != Game.State.PLAY:
		if is_instance_valid(g):
			g.queue_free()
		return
	Game.begin_attack()
	var pos: Vector3 = g.global_position
	pos.y = 0.0
	g.queue_free()
	creature = CREATURE.new()
	level.add_child(creature)
	creature.global_position = pos
	creature.visible = false
	_blackout()
	Sounds.play(self, Sounds.VIOLIN_STING, -2.0)
	heart = Sounds.play(self, Sounds.HEART, -4.0)
	phase = Phase.DARK
	t = 0.0


func _blackout() -> void:
	for l in level.find_children("*", "Light3D", true, false):
		if l != creature.get("glow"):
			(l as Light3D).visible = false
	for m in level.find_children("*", "GeometryInstance3D", true, false):
		var mi := m as GeometryInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat and (mat.emission_enabled or (mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and String(mi.name) in ["Glass", "LampGlass", "Mesh", "Embers"])):
			mi.visible = false
	for f in level.find_children("Flame*", "Node3D", true, false):
		(f as Node3D).visible = false
	if env:
		amb = env.ambient_light_energy
		create_tween().tween_property(env, "ambient_light_energy", amb * 0.06, 0.6)
	Sounds.play(self, Sounds.CLOTH, 0.0, "SFX", 0.1)


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _room(p: Vector3) -> String:
	if p.x < 5.95:
		return "coffin" if p.z < 5.5 else "bed"
	if p.x <= 14.05:
		return "hall"
	return "out"


## Around walls and furniture (scripts/nav.gd); the old door table if the
## navigation mesh isn't ready.
func _goal(c: Vector3, p: Vector3, dt: float) -> Vector3:
	if not Nav.is_baked:
		return _next_point(c, p)
	nav_t -= dt
	if nav_t <= 0.0 or nav_goal == Vector3.INF or Vector2(c.x - nav_goal.x, c.z - nav_goal.z).length() < 0.25:
		nav_t = 0.25
		var r := Nav.route(c, [p])
		nav_goal = r[0] if not r.is_empty() else p
		if r.size() > 1 and Vector2(c.x - nav_goal.x, c.z - nav_goal.z).length() < 0.25:
			nav_goal = r[1]
	return nav_goal


func _next_point(c: Vector3, p: Vector3) -> Vector3:
	if via != Vector3.INF:
		if Vector2(c.x - via.x, c.z - via.z).length() < 0.3:
			via = Vector3.INF
		else:
			return via
	var rc := _room(c)
	var rp := _room(p)
	if rc == rp:
		return p
	var key := rc if rc != "hall" else rp
	var pair: Array = DOORS[key]
	var near: Vector3 = pair[0] if rc == key else pair[1]
	var far: Vector3 = pair[1] if rc == key else pair[0]
	if Vector2(c.x - near.x, c.z - near.z).length() < 0.35:
		via = far
		return far
	return near


func _process(dt: float) -> void:
	if phase == Phase.IDLE or phase == Phase.DONE:
		return
	t += dt
	var p := _player()
	cam = get_viewport().get_camera_3d()
	match phase:
		Phase.DARK:
			if t >= Config.attack_dark:
				creature.visible = true
				creature.set_pose(CREATURE.Pose.STAND)
				creature.reveal(true)
				if p:
					creature.look_at(Vector3(p.global_position.x, 0, p.global_position.z), Vector3.UP)
				Sounds.play_at(self, creature.global_position + Vector3(0, 1.8, 0), Sounds.VIOLIN_RISE, 2.0, "SFX", 0.8)
				phase = Phase.REVEAL
				t = 0.0
		Phase.REVEAL:
			if p:
				var tgt := Vector3(p.global_position.x, 0, p.global_position.z)
				if tgt.distance_to(creature.global_position) > 0.1:
					creature.look_at(tgt, Vector3.UP)
			if t >= Config.attack_reveal:
				creature.set_pose(CREATURE.Pose.RUN)
				skitter = AudioStreamPlayer3D.new()
				skitter.stream = Sounds.looped(Sounds.SKITTER)
				skitter.volume_db = 8.0
				skitter.unit_size = 7.0
				skitter.max_db = 10.0
				skitter.bus = "SFX"
				creature.add_child(skitter)
				skitter.position = Vector3(0, 0.6, 0)
				skitter.play()
				Sounds.play(self, Sounds.CHASE, -2.0)
				phase = Phase.RUSH
				t = 0.0
		Phase.RUSH:
			if p == null:
				return
			var c := creature.global_position
			var goal := _goal(c, p.global_position, dt)
			var d := Vector3(goal.x - c.x, 0, goal.z - c.z)
			var dist := d.length()
			var step := Config.attack_speed * dt
			if dist > 0.01:
				creature.global_position = c + d / dist * minf(step, dist)
				creature.look_at(creature.global_position + d / dist, Vector3.UP)
			var to_p := Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length()
			if (to_p < Config.attack_catch_dist and _room(c) == _room(p.global_position)) or t > 12.0:
				_catch()
		Phase.CATCH:
			_hold_face()
			shake = maxf(shake - dt * 0.6, 0.0)
			if cam:
				cam.h_offset = randf_range(-1, 1) * 0.05 * shake
				cam.v_offset = randf_range(-1, 1) * 0.05 * shake
			# a white frame, then red flicker, the picture tearing apart
			glitch.visible = t < 1.45
			glitch_mat.set_shader_parameter("k", clampf(0.9 - t * 0.6, 0.0, 1.0))
			glitch_mat.set_shader_parameter("seed", randf() * 100.0)
			if t < 0.04:
				flash.color = Color(1, 1, 1, 0.85)
			elif t < 1.45:
				flash.color = Color(0.6, 0.0, 0.0, (0.28 if fmod(t, 0.16) < 0.05 else 0.0) * shake)
			else:
				flash.color = Color(0, 0, 0, clampf((t - 1.45) * 4.0, 0, 1))
			if t >= 1.7:
				glitch.visible = false
				phase = Phase.DONE
				if skitter:
					skitter.stop()
				if cam:
					cam.h_offset = 0.0
					cam.v_offset = 0.0
				Game.lose("double")
				var tw := create_tween()
				tw.tween_interval(Config.end_delay - 0.1)
				tw.tween_property(flash, "color:a", 0.0, 0.3)


func _catch() -> void:
	phase = Phase.CATCH
	t = 0.0
	shake = 1.0
	creature.set_pose(CREATURE.Pose.LUNGE)
	creature.reveal(true)
	var p := _player()
	if p:
		p.set_physics_process(false)
		p.set_process_unhandled_input(false)
	Sounds.play(self, Sounds.SCREAM, 8.0)
	var deep := Sounds.play(self, Sounds.SCREAM, 8.0)
	if deep:
		deep.pitch_scale = 0.55   # a deeper roar under it
	Sounds.play(self, Sounds.JUMPSCARE, 4.0)
	if cam:
		# the view lurches: wide, then slammed in on the face
		cam.fov = 105.0
		create_tween().tween_property(cam, "fov", 58.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_hold_face()


func _hold_face() -> void:
	if cam == null or creature == null:
		return
	var fwd := -cam.global_basis.z
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	if flat.length() < 0.1:
		flat = Vector3(0, 0, -1)
	var cp := cam.global_position
	creature.global_position = Vector3(cp.x, 0, cp.z) + flat * 0.6
	creature.look_at(Vector3(cp.x, 0, cp.z), Vector3.UP)
	var head: Node3D = creature.get("head")
	if head:
		# closer every frame for the first instant: it lunges into the lens,
		# eyes level with yours
		var d := lerpf(0.7, 0.3, clampf(t / 0.18, 0.0, 1.0))
		var eyes := head.global_transform * Vector3(0, 0.13, -0.1)
		var off := (cp + fwd * d + Vector3(0, -0.03, 0)) - eyes
		creature.global_position += off
		creature.set("face_target", cp)
	var glow: OmniLight3D = creature.get("glow")
	if glow:
		# cold light from just under the chin
		glow.global_position = cp + fwd * 0.12 + Vector3(0, -0.22, 0)
		glow.light_energy = 1.8


func debug_line() -> String:
	return "attack %s %.1f" % [Phase.keys()[phase], t]
