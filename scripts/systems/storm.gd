extends Node

const CREATURE := preload("res://scripts/creature.gd")

var level: Node3D
var env: Environment
var sky: DirectionalLight3D
var next_t := 18.0
var flash := 0.0
var added := 0.0
var strikes := 0


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
		var want := flash * 1.4
		env.ambient_light_energy += want - added
		added = want
	sky.light_energy = flash * 2.6


func strike() -> void:
	strikes += 1
	var near := randf()
	var tw := create_tween()
	tw.tween_property(self, "flash", 1.0, 0.03)
	tw.tween_property(self, "flash", 0.15, 0.07)
	tw.tween_property(self, "flash", 0.85, 0.04)
	tw.tween_property(self, "flash", 0.0, 0.35)
	_glimpse()
	var delay := lerpf(0.15, 2.8, near)
	get_tree().create_timer(delay).timeout.connect(func():
		Sounds.play(self, Sounds.THUNDER, lerpf(2.0, -9.0, near), "Ambience", 0.06))


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
