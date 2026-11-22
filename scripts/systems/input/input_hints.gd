extends Node
## Turns input actions into the words shown to the player.
##
## Bindings are physical keys, so the label depends on the keyboard layout
## (the `move_up` key reads W on QWERTY and Z on AZERTY) and on the device used
## last. Every prompt goes through this autoload instead of spelling a key.

signal device_changed(using_gamepad: bool)

## Rows of the controls screen, in display order. `move` is the four movement
## actions shown as one entry.
const CONTROLS: Array[Dictionary] = [
	{"action": "move", "label": "Se déplacer"},
	{"action": "run", "label": "Courir"},
	{"action": "interact", "label": "Interagir"},
	{"action": "select_seed", "label": "Choisir une graine"},
	{"action": "toggle_inventory", "label": "Inventaire"},
	{"action": "toggle_prices", "label": "Prix du marché"},
	{"action": "toggle_tasks", "label": "Liste des tâches"},
	{"action": "pause", "label": "Pause"},
]
const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_left", &"move_down", &"move_right"]
const UNBOUND := "?"

const KEY_NAMES := {
	KEY_ESCAPE: "Échap",
	KEY_SHIFT: "Maj",
	KEY_CTRL: "Ctrl",
	KEY_ALT: "Alt",
	KEY_ENTER: "Entrée",
	KEY_KP_ENTER: "Entrée",
	KEY_SPACE: "Espace",
	KEY_TAB: "Tab",
	KEY_BACKSPACE: "Retour arrière",
	KEY_UP: "↑",
	KEY_DOWN: "↓",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
}
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Select",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "Croix ↑",
	JOY_BUTTON_DPAD_DOWN: "Croix ↓",
	JOY_BUTTON_DPAD_LEFT: "Croix ←",
	JOY_BUTTON_DPAD_RIGHT: "Croix →",
}
const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: "Stick gauche",
	JOY_AXIS_LEFT_Y: "Stick gauche",
	JOY_AXIS_RIGHT_X: "Stick droit",
	JOY_AXIS_RIGHT_Y: "Stick droit",
	JOY_AXIS_TRIGGER_LEFT: "LT",
	JOY_AXIS_TRIGGER_RIGHT: "RT",
}
## A resting stick still reports small values; they must not count as "the
## player picked up the gamepad".
const AXIS_WAKE_THRESHOLD := 0.5

var using_gamepad := false

## The headless and Web display servers cannot tell which layout is in use and
## log an error when asked; physical keys then keep their US names.
var _layout_known := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layout_known = DisplayServer.get_name() != "headless" and not OS.has_feature("web")


func _input(event: InputEvent) -> void:
	note_event(event)


## Records which device the player is using. Exposed for tests.
func note_event(event: InputEvent) -> void:
	var gamepad := using_gamepad
	if event is InputEventJoypadButton:
		gamepad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < AXIS_WAKE_THRESHOLD:
			return
		gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		gamepad = false
	else:
		return
	if gamepad != using_gamepad:
		using_gamepad = gamepad
		device_changed.emit(using_gamepad)


## Label of `action` for the device in use, falling back to the other device
## when the action has no binding there.
func label(action: StringName) -> String:
	var preferred := gamepad_label(action) if using_gamepad else keyboard_label(action)
	if preferred != UNBOUND:
		return preferred
	return keyboard_label(action) if using_gamepad else gamepad_label(action)


func keyboard_label(action: StringName) -> String:
	if action == &"move":
		return _keyboard_move_label()
	if action == &"select_seed":
		return "%s à %s" % [keyboard_label(&"select_seed_1"), keyboard_label(&"select_seed_4")]
	for event: InputEvent in _events(action):
		if event is InputEventKey:
			return key_label(event as InputEventKey)
	return UNBOUND


func gamepad_label(action: StringName) -> String:
	if action == &"move":
		return gamepad_label(&"move_up")
	if action == &"select_seed":
		return "%s / %s" % [gamepad_label(&"seed_previous"), gamepad_label(&"seed_next")]
	for event: InputEvent in _events(action):
		if event is InputEventJoypadButton:
			var index := (event as InputEventJoypadButton).button_index
			return String(BUTTON_NAMES.get(index, "Bouton %d" % index))
		if event is InputEventJoypadMotion:
			var axis := (event as InputEventJoypadMotion).axis
			return String(AXIS_NAMES.get(axis, "Axe %d" % axis))
	return UNBOUND


## Name printed on the keycap for the player's layout.
func key_label(event: InputEventKey) -> String:
	var keycode := event.keycode
	if event.physical_keycode != KEY_NONE:
		keycode = event.physical_keycode
		if _layout_known:
			var printed := DisplayServer.keyboard_get_label_from_physical(event.physical_keycode)
			if printed != KEY_NONE:
				keycode = printed
	if KEY_NAMES.has(keycode):
		return String(KEY_NAMES[keycode])
	var text := OS.get_keycode_string(keycode)
	return text if not text.is_empty() else UNBOUND


## "E — Parler" for the keyboard, "A — Parler" for a gamepad.
func prompt(action: StringName, text: String) -> String:
	return "%s — %s" % [label(action), text]


## Replaces `{action}` tokens: "Plantez ({interact})." becomes "Plantez (E).".
## Text written in scenes and data tables uses this instead of naming a key.
func format(text: String) -> String:
	var result := text
	var from := result.find("{")
	while from != -1:
		var to := result.find("}", from)
		if to == -1:
			break
		var token := result.substr(from + 1, to - from - 1)
		if token == "move" or token == "select_seed" or InputMap.has_action(token):
			var replacement := label(StringName(token))
			result = result.substr(0, from) + replacement + result.substr(to + 1)
			from = result.find("{", from + replacement.length())
		else:
			from = result.find("{", to + 1)
	return result


func _keyboard_move_label() -> String:
	var keys: PackedStringArray = []
	for action: StringName in MOVE_ACTIONS:
		keys.append(keyboard_label(action))
	# Four letters read best glued together ("ZQSD"); anything else is spaced.
	var compact := true
	for key: String in keys:
		if key.length() != 1 or key.unicode_at(0) > 127:
			compact = false
	return "".join(keys) if compact else " ".join(keys)


func _events(action: StringName) -> Array[InputEvent]:
	if not InputMap.has_action(action):
		return []
	return InputMap.action_get_events(action)
