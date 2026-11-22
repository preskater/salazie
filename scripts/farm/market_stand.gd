class_name MarketStand
extends StaticBody2D

signal market_requested

func _ready() -> void:
	add_to_group("interactable")

func get_interaction_prompt() -> String:
	return InputHints.prompt(&"interact", "Marché de Salazie")

func interact(_player: Node2D) -> void:
	market_requested.emit()
