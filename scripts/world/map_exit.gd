extends Area2D

## Placeable map exit. When the player enters it, a `SceneTransition` fades to
## the configured scene with this exit's title and subtitle. The exit can be
## gated on Map 1's night requirement and on the current generation's tasks.

signal blocked
signal exit_taken(scene_path: String)

## Destination scene. Leave empty to keep the exit inactive.
@export_file("*.tscn") var next_scene_path := ""
## Text displayed during the transition to the next scene.
@export var title := ""
@export_multiline var subtitle := ""
## When true, the exit only fires once the night requirement is met.
@export var requires_map_ready := true
## When true, every task of the current generation must be resolved.
@export var requires_map_complete := false
## Task completed when the player first enters the exit area.
@export var complete_task_on_enter := ""
## Shows the generation result before the transition.
@export var show_result := true

## Test seam: replaces the SceneTransition autoload when set.
var transition_override: Node = null
var _triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func can_leave() -> bool:
	if next_scene_path.is_empty():
		return false
	if requires_map_ready and not DayNightCycle.is_ready_for_next_map():
		return false
	if requires_map_complete and not Campaign.can_leave_map():
		return false
	return true


func _on_body_entered(body: Node2D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	if not complete_task_on_enter.is_empty():
		Campaign.complete_task(complete_task_on_enter)
	if not can_leave():
		blocked.emit()
		return
	_triggered = true
	exit_taken.emit(next_scene_path)
	await _leave()


func _leave() -> void:
	if transition_override != null:
		transition_override.change_scene(next_scene_path, title, subtitle)
		return
	if show_result:
		var overlay := get_tree().get_first_node_in_group("generation_result") as GenerationResult
		if overlay != null:
			overlay.show_result(Campaign.map_summary(), Campaign.next_map_label(), _carry_note())
			await overlay.confirmed
	if not await SceneRouter.go_to_next_map():
		# Refused (a transition was already running): the exit must answer again.
		_triggered = false


func _carry_note() -> String:
	match Campaign.current_map:
		1:
			return "Prochaine ferme : %d G" % Campaign.starting_money_for_map(2)
		2:
			return "Héritage familial : %d G" % Campaign.heritage_for_map3()
		_:
			return ""
