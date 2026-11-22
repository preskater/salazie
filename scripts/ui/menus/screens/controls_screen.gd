extends Control
## Controls reference and rebinding. Every row is read from the InputMap through
## `InputHints`, so it shows the keys of the player's own layout. Pressing a
## key or button cell waits for the next key or gamepad button and gives it to
## that action (`Settings.rebind_key` / `rebind_button`).

signal back_requested()

enum Device { KEYBOARD, GAMEPAD }

const HEADER_COLOR := Color(0.44, 0.36, 0.28)
const WAITING_TEXT := "…"
const ROWS: Array[Dictionary] = [
	{"action": "move_up", "label": "Aller en haut"},
	{"action": "move_left", "label": "Aller à gauche"},
	{"action": "move_down", "label": "Aller en bas"},
	{"action": "move_right", "label": "Aller à droite"},
	{"action": "run", "label": "Courir"},
	{"action": "interact", "label": "Interagir"},
	{"action": "select_seed", "label": "Choisir une graine"},
	{"action": "toggle_inventory", "label": "Inventaire"},
	{"action": "toggle_prices", "label": "Prix du marché"},
	{"action": "toggle_tasks", "label": "Liste des tâches"},
	{"action": "pause", "label": "Pause"},
	{"action": "ui_cancel", "label": "Retour / fermer"},
]

@onready var back_button: Button = %BackButton
@onready var reset_button: Button = %ResetButton
@onready var rows: GridContainer = %Rows

var _listening_action: StringName = &""
var _listening_device := Device.KEYBOARD


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	Settings.bindings_changed.connect(_build_rows)
	_build_rows()


func on_shown() -> void:
	_stop_listening()
	_build_rows()
	back_button.grab_focus()


func is_listening() -> bool:
	return _listening_action != &""


## Text of the grid, one array per row: [action label, keyboard, gamepad].
func get_row_texts() -> Array:
	var result: Array = []
	var cells := rows.get_children()
	for index in range(3, cells.size(), 3):
		result.append([_cell_text(cells[index]), _cell_text(cells[index + 1]),
			_cell_text(cells[index + 2])])
	return result


## Starts waiting for the next key or button for `action`.
func listen(action: StringName, device: Device) -> void:
	if not Settings.REBINDABLE.has(action):
		return
	_listening_action = action
	_listening_device = device
	_build_rows()


func _input(event: InputEvent) -> void:
	if not is_listening() or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		# Escape always cancels, so it can never be given away by accident.
		if _listening_device == Device.KEYBOARD and key != KEY_ESCAPE:
			Settings.rebind_key(_listening_action, key)
		_finish_listening()
	elif event is InputEventJoypadButton and event.pressed:
		if _listening_device == Device.GAMEPAD:
			Settings.rebind_button(_listening_action,
				(event as InputEventJoypadButton).button_index)
		_finish_listening()


func _finish_listening() -> void:
	var action := _listening_action
	var device := _listening_device
	_stop_listening()
	# The press that was captured must not also act on the menu.
	get_viewport().set_input_as_handled()
	_build_rows()
	var cell := rows.get_node_or_null(_cell_name(action, device)) as Button
	if cell != null:
		cell.grab_focus()


func _stop_listening() -> void:
	_listening_action = &""


func _build_rows() -> void:
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for title: String in ["", "Clavier", "Manette"]:
		_add_label(title, true)
	for entry: Dictionary in ROWS:
		var action := StringName(String(entry["action"]))
		_add_label(String(entry["label"]))
		_add_binding(action, Device.KEYBOARD, InputHints.keyboard_label(action))
		# A rebindable cell shows the button it changes: movement also answers
		# to the left stick, which stays as it is.
		var pad_text := InputHints.gamepad_label(action)
		if Settings.REBINDABLE.has(action):
			pad_text = InputHints.button_label(Settings.primary_button(action))
		_add_binding(action, Device.GAMEPAD, pad_text)


func _add_binding(action: StringName, device: Device, text: String) -> void:
	if not Settings.REBINDABLE.has(action):
		_add_label(text)
		return
	var button := Button.new()
	button.name = _cell_name(action, device)
	button.custom_minimum_size = Vector2(120, 30)
	var waiting := action == _listening_action and device == _listening_device
	button.text = WAITING_TEXT if waiting else text
	button.pressed.connect(listen.bind(action, device))
	rows.add_child(button)


func _add_label(text: String, header := false) -> void:
	var cell := Label.new()
	cell.text = text
	if header:
		cell.add_theme_color_override("font_color", HEADER_COLOR)
		cell.add_theme_font_size_override("font_size", 15)
	rows.add_child(cell)


func _cell_name(action: StringName, device: Device) -> String:
	return "%s_%s" % [action, "key" if device == Device.KEYBOARD else "pad"]


func _cell_text(cell: Node) -> String:
	if cell is Button:
		return (cell as Button).text
	return (cell as Label).text


func _on_reset_pressed() -> void:
	_stop_listening()
	Settings.reset_bindings()


func _on_back_pressed() -> void:
	_stop_listening()
	back_requested.emit()
