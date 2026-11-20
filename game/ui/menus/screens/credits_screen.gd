extends Control
## Static credits screen.

signal back_requested()

const LIMEZU_URL := "https://limezu.itch.io/"

@onready var limezu_link: LinkButton = %LimezuLink
@onready var back_button: Button = %BackButton


func _ready() -> void:
	limezu_link.pressed.connect(_on_limezu_pressed)
	back_button.pressed.connect(_on_back_pressed)


func on_shown() -> void:
	back_button.grab_focus()


func _on_limezu_pressed() -> void:
	OS.shell_open(LIMEZU_URL)


func _on_back_pressed() -> void:
	back_requested.emit()
