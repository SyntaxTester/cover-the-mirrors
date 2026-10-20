extends Node

const CREATURE := preload("res://scripts/creature.gd")

var level: Node3D
var env: Environment
var sky: DirectionalLight3D
var next_t := 18.0
var flash := 0.0
var added := 0.0
var strikes := 0
var white: ColorRect      # the flash itself, over the whole picture
var shake := 0.0


func _ready() -> void:
	add_to_group("debug")
	add_to_group("storm")
	level = get_node("../../Level")
	var we := level.get_node_or_null("Env") as WorldEnvironment
	if we:
		env = we.environment
	sky = DirectionalLight3D.new()
	sky.light_color = Color(0.75, 0.82, 1.0)
	sky.light_energy = 0.0
	sky.shadow_enabled = true
	sky.rotation_degrees = Vector3(-52, 115, 0)
	level.add_child(sky)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	white = ColorRect.new()
	white.color = Color(0.85, 0.9, 1.0, 0.0)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(white)
	next_t = randf_range(10.0, 22.0)


func _process(dt: float) -> void:
	if Game.state != Game.State.PLAY:
		if added != 0.0 and env:
			env.ambient_light_energy -= added
			added = 0.0
		sky.light_energy = 0.0
		return
	next_t -= dt
	if next_t <= 0.0:
		next_t = randf_range(Config.storm_min, Config.storm_max)
		strike()
	if env:
		var want := flash * 2.2
		env.ambient_light_energy += want - added
		added = want
	sky.light_energy = flash * 4.5
	white.color.a = flash * flash * 0.45
	# the thunder of a close strike shakes the view
	shake = maxf(shake - dt * 2.5, 0.0)
	var cam := get_viewport().get_camera_3d()
	if cam and Game.state == Game.State.PLAY:
		cam.h_offset = randf_range(-1, 1) * 0.02 * shake
		cam.v_offset = randf_range(-1, 1) * 0.02 * shake


func strike() -> void:
	strikes += 1
	var near := randf() * randf()   # most strikes now land close to the house
	var tw := create_tween()
	# a stutter of flashes, the way real lightning flickers
	tw.tween_property(self, "flash", 1.0, 0.02)
	tw.tween_property(self, "flash", 0.1, 0.06)
	tw.tween_property(self, "flash", 0.95, 0.03)
	tw.tween_property(self, "flash", 0.2, 0.08)
	tw.tween_property(self, "flash", 0.7 * (1.0 - near * 0.5), 0.03)
	tw.tween_property(self, "flash", 0.0, 0.5)
	_glimpse()
	var delay := lerpf(0.08, 2.4, near)
	get_tree().create_timer(delay).timeout.connect(func():
		if near < 0.6:
			Sounds.play(self, Sounds.THUNDER_NEAR, lerpf(10.0, 4.0, near / 0.6), "Ambience", 0.05)
			shake = 1.0 - near
		else:
			Sounds.play(self, Sounds.THUNDER, lerpf(6.0, 1.0, near), "Ambience", 0.06))


func _glimpse() -> void:
	for g in get_tree().get_nodes_in_group("doubles"):
		if not is_instance_valid(g) or g.get("rig") == null or not g.is_inside_tree():
			continue
		if not (g.is_seated() or g.is_stalking()):
			continue
		var c: Node3D = CREATURE.new()
		level.add_child(c)
		c.global_position = Vector3(g.global_position.x, 0.0, g.global_position.z)
		c.global_rotation.y = g.global_rotation.y
		g.rig.visible = false
		get_tree().create_timer(0.16).timeout.connect(func():
			if is_instance_valid(g):
				g.rig.visible = true
			c.queue_free())


func debug_line() -> String:
	return "storm next %.0f strikes %d" % [next_t, strikes]
