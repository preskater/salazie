extends Area2D
## Interactive point where the heir commits to a plan for Salazie.

signal requested()

@export var label := "Point de décision"


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("decision_points")


func get_interaction_prompt() -> String:
	return "E — Prendre une décision"


func interact(_player: Node2D) -> void:
	requested.emit()
