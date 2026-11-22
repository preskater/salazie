class_name Checkpoint
extends Area2D
## A safe point that updates the respawn position and can complete a task when
## the player reaches it for the first time.

signal reached(position: Vector2)

@export var task_id := ""
@export var checkpoint_name := "Checkpoint"

var _task_done := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group("checkpoints")


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not _task_done and not task_id.is_empty():
		_task_done = true
		Campaign.complete_task(task_id)
	reached.emit(global_position)
