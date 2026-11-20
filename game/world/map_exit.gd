extends Area2D

## Placeable map exit. When the player enters it, a `SceneTransition` fades to
## the configured scene with this exit's title and subtitle. The exit can be
## gated on `DayNightCycle.is_ready_for_next_map()`.

signal blocked
signal exit_taken(scene_path: String)

## Destination scene. Leave empty to keep the exit inactive.
@export_file("*.tscn") var next_scene_path := ""
## Text displayed during the transition to the next scene.
@export var title := ""
@export_multiline var subtitle := ""
## When true, the exit only fires once the night requirement is met.
@export var requires_map_ready := true

## Test seam: replaces the SceneTransition autoload when set.
var transition_override: Node = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func can_leave() -> bool:
	if next_scene_path.is_empty():
		return false
	if requires_map_ready and not DayNightCycle.is_ready_for_next_map():
		return false
	return true

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not can_leave():
		blocked.emit()
		return
	var transition = _transition()
	if transition.is_transitioning:
		return
	exit_taken.emit(next_scene_path)
	transition.change_scene(next_scene_path, title, subtitle)

func _transition():
	return transition_override if transition_override != null else SceneTransition
