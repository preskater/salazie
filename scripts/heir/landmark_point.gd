extends Area2D
## Optional flavour point in the modern village: a viewpoint, the shared garden...

signal inspected(title: String, text: String)

@export var landmark_id := ""
@export var title := "Point de vue"
@export_multiline var text := ""
@export var texture: Texture2D
@export var tint := Color.WHITE

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("landmarks")
	if texture != null:
		sprite.texture = texture
	sprite.modulate = tint


func get_interaction_prompt() -> String:
	return InputHints.prompt(&"interact", "Observer %s" % title)


func interact(_player: Node2D) -> void:
	inspected.emit(title, text)
