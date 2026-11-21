extends Control
## Read-only controls reference. Rebinding is intentionally out of scope for now.

signal back_requested()

@onready var back_button: Button = %BackButton


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)


func on_shown() -> void:
	back_button.grab_focus()


func _on_back_pressed() -> void:
	back_requested.emit()
