extends Area2D
## A shuttle stop. The map owns the ride itself.

signal ride_requested(stop_id: String, destination: Vector2)

@export var stop_id := "south"
@export var destination := Vector2.ZERO


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("bus_stops")


func get_interaction_prompt() -> String:
	return "E — Prendre la navette"


func interact(_player: Node2D) -> void:
	ride_requested.emit(stop_id, destination)
