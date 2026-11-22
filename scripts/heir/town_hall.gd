extends Area2D
## The town hall: the last interaction of the campaign.

signal requested()


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("town_halls")


func get_interaction_prompt() -> String:
	return InputHints.prompt(&"interact", "Présenter le plan au conseil")


func interact(_player: Node2D) -> void:
	requested.emit()
