extends Control
## Controls reference. Every row is read from the InputMap through `InputHints`,
## so it shows the keys of the player's own layout and stays true after a
## binding changes.

signal back_requested()

const HEADER_COLOR := Color(0.44, 0.36, 0.28)
## Menu navigation uses Godot's built-in `ui_*` actions.
const MENU_ROWS: Array[Dictionary] = [
	{"label": "Naviguer dans les menus", "keyboard": "Flèches + Entrée", "gamepad": "Croix + A"},
	{"label": "Retour / fermer", "action": "ui_cancel"},
]

@onready var back_button: Button = %BackButton
@onready var rows: GridContainer = %Rows


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_build_rows()


func on_shown() -> void:
	_build_rows()
	back_button.grab_focus()


## Text of the grid, one array per row: [action label, keyboard, gamepad].
func get_row_texts() -> Array:
	var result: Array = []
	var cells := rows.get_children()
	for index in range(3, cells.size(), 3):
		result.append([
			(cells[index] as Label).text,
			(cells[index + 1] as Label).text,
			(cells[index + 2] as Label).text,
		])
	return result


func _build_rows() -> void:
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for title: String in ["", "Clavier", "Manette"]:
		_add_cell(title, true)
	for entry: Dictionary in InputHints.CONTROLS:
		var action := StringName(String(entry["action"]))
		_add_row(String(entry["label"]),
			InputHints.keyboard_label(action), InputHints.gamepad_label(action))
	for entry: Dictionary in MENU_ROWS:
		if entry.has("action"):
			var action := StringName(String(entry["action"]))
			_add_row(String(entry["label"]),
				InputHints.keyboard_label(action), InputHints.gamepad_label(action))
		else:
			_add_row(String(entry["label"]), String(entry["keyboard"]), String(entry["gamepad"]))


func _add_row(title: String, keyboard: String, gamepad: String) -> void:
	_add_cell(title)
	_add_cell(keyboard)
	_add_cell(gamepad)


func _add_cell(text: String, header := false) -> void:
	var cell := Label.new()
	cell.text = text
	if header:
		cell.add_theme_color_override("font_color", HEADER_COLOR)
		cell.add_theme_font_size_override("font_size", 15)
	rows.add_child(cell)


func _on_back_pressed() -> void:
	back_requested.emit()
