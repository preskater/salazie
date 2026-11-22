extends Area2D
## A fragile place in the modern valley. Inspecting it is an `assess` task step.

signal inspected(site_id: String, title: String, description: String)

@export var site_id := ""
@export var title := "Zone fragile"
@export_multiline var description := ""
@export var texture: Texture2D
@export var tint := Color.WHITE

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("fragile_sites")
	if texture != null:
		sprite.texture = texture
	sprite.modulate = tint


func get_interaction_prompt() -> String:
	return InputHints.prompt(&"interact", "Inspecter %s" % title)


func interact(_player: Node2D) -> void:
	inspected.emit(site_id, title, description)
