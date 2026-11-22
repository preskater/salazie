extends Node
## Persistent user settings: audio bus volumes, window mode, resolution, VSync
## and input bindings. Menus write through the setters; the file is loaded once
## at startup.

signal settings_changed()
signal bindings_changed()

const SETTINGS_PATH := "user://settings.cfg"
const SECTION_AUDIO := "audio"
const SECTION_DISPLAY := "display"
const SECTION_INPUT := "input"
## Actions the player may rebind: their main key and their main gamepad button.
## Arrow keys, the stick and the menu actions keep their defaults, so a bad
## binding can never lock the player out of the menus.
const REBINDABLE: Array[StringName] = [
	&"move_up", &"move_left", &"move_down", &"move_right", &"run", &"interact",
	&"toggle_inventory", &"toggle_prices", &"toggle_tasks", &"pause",
]
## Keys of actions that cannot be rebound and must stay free.
const RESERVED_ACTIONS: Array[StringName] = [
	&"select_seed_1", &"select_seed_2", &"select_seed_3", &"select_seed_4",
]

const WINDOWED := 0
const FULLSCREEN := 1

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

const DEFAULT_MASTER := 0.8
const DEFAULT_MUSIC := 0.7
const DEFAULT_SFX := 0.8
const DEFAULT_WINDOW_MODE := WINDOWED

var config_path := SETTINGS_PATH
var master_volume := DEFAULT_MASTER
var music_volume := DEFAULT_MUSIC
var sfx_volume := DEFAULT_SFX
var window_mode := DEFAULT_WINDOW_MODE
var resolution: Vector2i = RESOLUTIONS[0]
var vsync_enabled := true
## Overrides only: action -> physical keycode / gamepad button index.
var key_bindings: Dictionary = {}
var button_bindings: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	master_volume = clampf(float(config.get_value(SECTION_AUDIO, "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(config.get_value(SECTION_AUDIO, "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value(SECTION_AUDIO, "sfx", sfx_volume)), 0.0, 1.0)
	window_mode = clampi(int(config.get_value(SECTION_DISPLAY, "window_mode", window_mode)), WINDOWED, FULLSCREEN)
	vsync_enabled = bool(config.get_value(SECTION_DISPLAY, "vsync", vsync_enabled))
	var stored: Variant = config.get_value(SECTION_DISPLAY, "resolution", [resolution.x, resolution.y])
	if stored is Array and (stored as Array).size() == 2:
		var candidate := Vector2i(int(stored[0]), int(stored[1]))
		if RESOLUTIONS.has(candidate):
			resolution = candidate
	key_bindings = {}
	button_bindings = {}
	for action: StringName in REBINDABLE:
		# -1 stands for "not set": ConfigFile refuses null as a default.
		var key: Variant = config.get_value(SECTION_INPUT, "%s/key" % action, -1)
		if key is int and int(key) > 0 and not _is_reserved_key(int(key)):
			key_bindings[action] = int(key)
		var button: Variant = config.get_value(SECTION_INPUT, "%s/button" % action, -1)
		if button is int and int(button) >= 0 and int(button) < JOY_BUTTON_MAX:
			button_bindings[action] = int(button)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION_AUDIO, "master", master_volume)
	config.set_value(SECTION_AUDIO, "music", music_volume)
	config.set_value(SECTION_AUDIO, "sfx", sfx_volume)
	config.set_value(SECTION_DISPLAY, "window_mode", window_mode)
	config.set_value(SECTION_DISPLAY, "resolution", [resolution.x, resolution.y])
	config.set_value(SECTION_DISPLAY, "vsync", vsync_enabled)
	for action: StringName in key_bindings:
		config.set_value(SECTION_INPUT, "%s/key" % action, int(key_bindings[action]))
	for action: StringName in button_bindings:
		config.set_value(SECTION_INPUT, "%s/button" % action, int(button_bindings[action]))
	var err := config.save(config_path)
	if err != OK:
		push_error("Could not save settings to %s (error %d)." % [config_path, err])


func apply_all() -> void:
	apply_audio()
	apply_display()
	apply_bindings()
	settings_changed.emit()


# --- Input bindings -----------------------------------------------------------

## Physical keycode of the main key of `action`, or KEY_NONE.
func primary_key(action: StringName) -> Key:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return KEY_NONE


## Index of the main gamepad button of `action`, or -1.
func primary_button(action: StringName) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return (event as InputEventJoypadButton).button_index
	return -1


## Gives `action` a new main key. A key already held by another rebindable
## action is swapped with it, so no action is ever left without a key. Returns
## false for a key that must stay free.
func rebind_key(action: StringName, physical_keycode: Key) -> bool:
	if not REBINDABLE.has(action) or physical_keycode == KEY_NONE \
			or _is_reserved_key(physical_keycode):
		return false
	var previous := primary_key(action)
	for other: StringName in REBINDABLE:
		if other != action and primary_key(other) == physical_keycode:
			key_bindings[other] = previous
	key_bindings[action] = physical_keycode
	apply_bindings()
	save_settings()
	return true


## Same as `rebind_key` for the main gamepad button.
func rebind_button(action: StringName, button: JoyButton) -> bool:
	if not REBINDABLE.has(action) or button < 0 or button >= JOY_BUTTON_MAX:
		return false
	var previous := primary_button(action)
	for other: StringName in REBINDABLE:
		if other != action and primary_button(other) == button:
			button_bindings[other] = previous
	button_bindings[action] = button
	apply_bindings()
	save_settings()
	return true


func reset_bindings() -> void:
	key_bindings = {}
	button_bindings = {}
	apply_bindings()
	save_settings()


## Rebuilds the rebindable actions from the project defaults plus the overrides.
func apply_bindings() -> void:
	for action: StringName in REBINDABLE:
		var defaults := _default_events(action)
		if defaults.is_empty():
			continue
		var key_done := false
		var button_done := false
		InputMap.action_erase_events(action)
		for event: InputEvent in defaults:
			var copy := event.duplicate() as InputEvent
			if copy is InputEventKey and not key_done:
				key_done = true
				if key_bindings.has(action):
					(copy as InputEventKey).physical_keycode = int(key_bindings[action]) as Key
					(copy as InputEventKey).keycode = KEY_NONE
					(copy as InputEventKey).unicode = 0
			elif copy is InputEventJoypadButton and not button_done:
				button_done = true
				if button_bindings.has(action) and int(button_bindings[action]) >= 0:
					(copy as InputEventJoypadButton).button_index = \
						int(button_bindings[action]) as JoyButton
			InputMap.action_add_event(action, copy)
	bindings_changed.emit()


func _default_events(action: StringName) -> Array:
	var setting: Variant = ProjectSettings.get_setting("input/%s" % action, {})
	if setting is Dictionary:
		var events: Variant = (setting as Dictionary).get("events", [])
		if events is Array:
			return events
	return []


func _is_reserved_key(physical_keycode: int) -> bool:
	for action: StringName in RESERVED_ACTIONS:
		for event: InputEvent in _default_events(action):
			if event is InputEventKey \
					and (event as InputEventKey).physical_keycode == physical_keycode:
				return true
	return false


func apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if window_mode == FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	if window_mode == WINDOWED:
		DisplayServer.window_set_size(resolution)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	settings_changed.emit()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	settings_changed.emit()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	settings_changed.emit()


func set_window_mode(value: int) -> void:
	window_mode = clampi(value, WINDOWED, FULLSCREEN)
	apply_display()
	settings_changed.emit()


func set_resolution(value: Vector2i) -> void:
	if not RESOLUTIONS.has(value):
		return
	resolution = value
	apply_display()
	settings_changed.emit()


func set_vsync_enabled(value: bool) -> void:
	vsync_enabled = value
	apply_display()
	settings_changed.emit()


func reset_defaults() -> void:
	master_volume = DEFAULT_MASTER
	music_volume = DEFAULT_MUSIC
	sfx_volume = DEFAULT_SFX
	window_mode = DEFAULT_WINDOW_MODE
	resolution = RESOLUTIONS[0]
	vsync_enabled = true
	key_bindings = {}
	button_bindings = {}
	apply_all()
	save_settings()


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))
