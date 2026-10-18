extends Node3D

const SYSTEMS := [
	["Portraits", preload("res://scripts/systems/portraits.gd")],
	["Interview", preload("res://scripts/systems/interview.gd")],
	["Roles", preload("res://scripts/systems/roles.gd")],
	["Director", preload("res://scripts/systems/director.gd")],
]
const PRIEST := preload("res://scripts/priest.gd")
const PRIEST_SEAT := Vector3(2.4, 0.46, 4.85)   # ChairA in the coffin room, facing the coffin

@onready var player: Node3D = $Player
@onready var level: Node3D = $Level


func _ready() -> void:
	var sp := level.get_node_or_null("Markers/Spawn") as Node3D
	if sp:
		player.global_transform = sp.global_transform
	var systems := get_node("Systems")
	for s in SYSTEMS:
		if systems.has_node(s[0]):
			continue
		var n: Node = (s[1] as GDScript).new()
		n.name = s[0]
		systems.add_child(n)
	var priest: Node3D = PRIEST.new()
	priest.name = "Priest"
	level.get_node("CoffinRoom").add_child(priest)
	priest.setup(Transform3D(Basis(), PRIEST_SEAT))
	Game.start_night(Game.night)
