class_name ClimbPoint
extends Area2D
## A climb between the river trail and the cliff ridge.

signal climb_requested(destination: Vector2)

## `{interact}` is replaced by the key or button bound to the action.
@export var label := "{interact} — Grimper"
@export var destination := Vector2.ZERO


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("climb_points")


func get_interaction_prompt() -> String:
	return InputHints.format(label)


func interact(_player: Node2D) -> void:
	climb_requested.emit(destination)
