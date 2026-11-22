extends Node
## Persistent user settings: audio bus volumes, window mode, resolution, VSync
## and input bindings. Menus write through the setters; the file is loaded once
## at startup.

signal settings_changed()
signal bindings_changed()

const SETTINGS_PATH := "user://settings.cfg"
const SECTION_AUDIO := "audio"
const SECTION_DISPLAY := "display"
const SECTION_ACCESSIBILITY := "accessibility"
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

## Offered display scales. One of these only: a hand-edited file cannot zoom the
## view to an arbitrary factor.
const UI_SCALES: Array[float] = [1.0, 1.25, 1.5]
## Share of the trauma a shake camera keeps when the comfort option is on.
const REDUCED_SHAKE_SHARE := 0.35
## Share of the peak alpha a damage flash keeps when the comfort option is on.
const REDUCED_FLASH_SHARE := 0.3

var config_path := SETTINGS_PATH
var master_volume := DEFAULT_MASTER
var music_volume := DEFAULT_MUSIC
var sfx_volume := DEFAULT_SFX
var window_mode := DEFAULT_WINDOW_MODE
var resolution: Vector2i = RESOLUTIONS[0]
var vsync_enabled := true
## Comfort options, all off by default so the game looks as designed.
var ui_scale := 1.0
var pause_on_focus_loss := false
var reduced_shake := false
var reduced_flash := false
## Overrides only: action -> physical keycode / gamepad button index.
var key_bindings: Dictionary = {}
var button_bindings: Dictionary = {}
## Test seam: runners disagree on the display (X11, macOS, headless), so tests
## pin the platform rules instead of asserting the machine's own screen.
## -1 asks the engine; `screen_size_override` of zero means "the real screen".
var controls_window_override := -1
var screen_size_override := Vector2i.ZERO


func _ready() -> void:
	# The fullscreen shortcut must work while the tree is paused by the menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_all()


func _unhandled_input(event: InputEvent) -> void:
	if handles_fullscreen_shortcut(event):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


## Whether `event` asks for the fullscreen toggle and the game owns a window.
func handles_fullscreen_shortcut(event: InputEvent) -> bool:
	return event.is_action_pressed(&"toggle_fullscreen") and controls_window()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	master_volume = clampf(_number(config, SECTION_AUDIO, "master", master_volume), 0.0, 1.0)
	music_volume = clampf(_number(config, SECTION_AUDIO, "music", music_volume), 0.0, 1.0)
	sfx_volume = clampf(_number(config, SECTION_AUDIO, "sfx", sfx_volume), 0.0, 1.0)
	window_mode = clampi(int(_number(config, SECTION_DISPLAY, "window_mode", window_mode)),
		WINDOWED, FULLSCREEN)
	var vsync: Variant = config.get_value(SECTION_DISPLAY, "vsync", vsync_enabled)
	if vsync is bool:
		vsync_enabled = vsync
	var stored: Variant = config.get_value(SECTION_DISPLAY, "resolution", [resolution.x, resolution.y])
	if stored is Array and (stored as Array).size() == 2:
		var candidate := Vector2i(int(stored[0]), int(stored[1]))
		if RESOLUTIONS.has(candidate):
			resolution = candidate
	ui_scale = _allowed_scale(config.get_value(SECTION_ACCESSIBILITY, "ui_scale", ui_scale),
		ui_scale)
	pause_on_focus_loss = _flag(config, SECTION_ACCESSIBILITY, "pause_on_focus_loss",
		pause_on_focus_loss)
	reduced_shake = _flag(config, SECTION_ACCESSIBILITY, "reduced_shake", reduced_shake)
	reduced_flash = _flag(config, SECTION_ACCESSIBILITY, "reduced_flash", reduced_flash)
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


## A hand-edited file can hold anything; `float("x")` or `float([1])` would
## raise a script error at boot.
func _number(config: ConfigFile, section: String, key: String, fallback: float) -> float:
	var value: Variant = config.get_value(section, key, fallback)
	return float(value) if (value is int or value is float) else fallback


## A boolean from a hand-edited file, or the fallback when it is not one.
func _flag(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value: Variant = config.get_value(section, key, fallback)
	return value if value is bool else fallback


## Only the scales the options screen offers are accepted; anything else keeps
## the value already in memory, like a missing key.
func _allowed_scale(value: Variant, fallback: float) -> float:
	var candidate := float(value) if (value is int or value is float) else fallback
	return candidate if UI_SCALES.has(candidate) else fallback


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION_AUDIO, "master", master_volume)
	config.set_value(SECTION_AUDIO, "music", music_volume)
	config.set_value(SECTION_AUDIO, "sfx", sfx_volume)
	config.set_value(SECTION_DISPLAY, "window_mode", window_mode)
	config.set_value(SECTION_DISPLAY, "resolution", [resolution.x, resolution.y])
	config.set_value(SECTION_DISPLAY, "vsync", vsync_enabled)
	config.set_value(SECTION_ACCESSIBILITY, "ui_scale", ui_scale)
	config.set_value(SECTION_ACCESSIBILITY, "pause_on_focus_loss", pause_on_focus_loss)
	config.set_value(SECTION_ACCESSIBILITY, "reduced_shake", reduced_shake)
	config.set_value(SECTION_ACCESSIBILITY, "reduced_flash", reduced_flash)
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


## Platform rule, kept pure so that it can be checked on any runner.
func owns_window(server_name: String, is_web: bool) -> bool:
	return server_name != "headless" and not is_web


## True where the game owns its window. A browser owns the canvas: it sizes
## it, refuses fullscreen without a click and has no VSync switch.
func controls_window() -> bool:
	if controls_window_override != -1:
		return controls_window_override > 0
	return owns_window(DisplayServer.get_name(), OS.has_feature("web"))


## Usable screen. A headless runner has no display and reports a dummy one, so
## the largest preset stands in: the resolution list must never come out empty.
func screen_size() -> Vector2i:
	if screen_size_override != Vector2i.ZERO:
		return screen_size_override
	if DisplayServer.get_name() == "headless":
		return RESOLUTIONS[-1]
	return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size


func apply_display() -> void:
	apply_window()
	apply_vsync()
	apply_ui_scale()


## Scales the whole rendered view, so the 14–15 px HUD labels of the default
## 1280 × 720 canvas can be read on a small screen. A UI-only scale would need
## the interface in its own SubViewport; this project stretches the canvas.
func apply_ui_scale() -> void:
	if not controls_window():
		return
	var window := get_window()
	if window != null:
		window.content_scale_factor = ui_scale


## Window mode and size. Kept apart from VSync so that toggling VSync does not
## undo a window the player resized by hand.
func apply_window() -> void:
	if not controls_window():
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if window_mode == FULLSCREEN \
		else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	if window_mode != WINDOWED:
		return
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := fitting_resolution(resolution, screen.size)
	DisplayServer.window_set_size(size)
	# Centred, or a window as large as the screen ends up half outside it.
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


func apply_vsync() -> void:
	if not controls_window():
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)


## Resolutions that fit on a screen of `screen_size`. The smallest is always
## offered so the list is never empty.
func available_resolutions(screen_size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for candidate: Vector2i in RESOLUTIONS:
		if candidate.x <= screen_size.x and candidate.y <= screen_size.y:
			result.append(candidate)
	if result.is_empty():
		result.append(RESOLUTIONS[0])
	return result


## `wanted` if the screen can show it, otherwise the largest that fits.
func fitting_resolution(wanted: Vector2i, screen_size: Vector2i) -> Vector2i:
	var fitting := available_resolutions(screen_size)
	return wanted if fitting.has(wanted) else fitting[-1]


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
	apply_window()
	settings_changed.emit()


func set_resolution(value: Vector2i) -> void:
	if not RESOLUTIONS.has(value):
		return
	resolution = value
	apply_window()
	settings_changed.emit()


func set_vsync_enabled(value: bool) -> void:
	vsync_enabled = value
	apply_vsync()
	settings_changed.emit()


func set_ui_scale(value: float) -> void:
	if not UI_SCALES.has(value):
		return
	ui_scale = value
	apply_ui_scale()
	settings_changed.emit()


func set_pause_on_focus_loss(value: bool) -> void:
	pause_on_focus_loss = value
	settings_changed.emit()


func set_reduced_shake(value: bool) -> void:
	reduced_shake = value
	settings_changed.emit()


func set_reduced_flash(value: bool) -> void:
	reduced_flash = value
	settings_changed.emit()


## Share of a shake amplitude the comfort option keeps.
func shake_share() -> float:
	return REDUCED_SHAKE_SHARE if reduced_shake else 1.0


## Share of a flash's peak alpha the comfort option keeps.
func flash_share() -> float:
	return REDUCED_FLASH_SHARE if reduced_flash else 1.0


## Swaps windowed and fullscreen, from the `toggle_fullscreen` action. The
## choice is remembered, so the next boot opens the same way.
func toggle_fullscreen() -> void:
	set_window_mode(FULLSCREEN if window_mode == WINDOWED else WINDOWED)
	save_settings()


func reset_defaults() -> void:
	master_volume = DEFAULT_MASTER
	music_volume = DEFAULT_MUSIC
	sfx_volume = DEFAULT_SFX
	window_mode = DEFAULT_WINDOW_MODE
	resolution = RESOLUTIONS[0]
	vsync_enabled = true
	ui_scale = 1.0
	pause_on_focus_loss = false
	reduced_shake = false
	reduced_flash = false
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
