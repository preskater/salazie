extends Control
## Reusable confirmation panel. Cancel is focused by default for destructive actions.

signal confirmed()
signal cancelled()

@onready var title_label: Label = %TitleLabel
@onready var message_label: Label = %MessageLabel
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton


func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func show_confirmation(title: String, message: String, confirm_text := "Confirmer", cancel_text := "Annuler") -> void:
	title_label.text = title
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text


func on_shown() -> void:
	cancel_button.grab_focus()


func _on_confirm_pressed() -> void:
	confirmed.emit()


func _on_cancel_pressed() -> void:
	cancelled.emit()
