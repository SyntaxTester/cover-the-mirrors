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
			var goal := _next_point(c, p.global_position)
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
			shake = maxf(shake - dt, 0.0)
			if cam:
				cam.h_offset = randf_range(-1, 1) * 0.04 * shake
				cam.v_offset = randf_range(-1, 1) * 0.04 * shake
			flash.color = Color(0.5, 0.02, 0.0, 0.35 * shake) if t < 0.9 else Color(0, 0, 0, clampf((t - 0.9) * 4.0, 0, 1))
			if t >= 1.15:
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
	Sounds.play(self, Sounds.SCREAM, 6.0)
	Sounds.play(self, Sounds.JUMPSCARE, 2.0)
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
		var off := (cp + fwd * 0.55 + Vector3(0, -0.05, 0)) - head.global_position
		creature.global_position += off
		creature.set("face_target", cp)
	var glow: OmniLight3D = creature.get("glow")
	if glow:
		glow.global_position = cp + fwd * 0.25 + Vector3(0, 0.25, 0)
		glow.light_energy = 1.4


func debug_line() -> String:
	return "attack %s %.1f" % [Phase.keys()[phase], t]
