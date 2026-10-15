class_name Interactable
extends Node3D

@export var prompt := "Interact"
@export var hold := false


func get_prompt() -> String:
	return prompt


func can_interact(_p: Node) -> bool:
	return true


func interact(_p: Node) -> void:
	pass


func release(_p: Node) -> void:
	pass


func wants_zoom() -> bool:
	return false


static func find(n: Node) -> Interactable:
	while n and not (n is Interactable):
		n = n.get_parent()
	return n as Interactable
