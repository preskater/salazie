extends Node
## Persistent user settings: audio bus volumes, window mode, resolution and VSync.
## Menus write through the setters; the file is loaded once at startup.

signal settings_changed()

const SETTINGS_PATH := "user://settings.cfg"
const SECTION_AUDIO := "audio"
const SECTION_DISPLAY := "display"

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


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION_AUDIO, "master", master_volume)
	config.set_value(SECTION_AUDIO, "music", music_volume)
	config.set_value(SECTION_AUDIO, "sfx", sfx_volume)
	config.set_value(SECTION_DISPLAY, "window_mode", window_mode)
	config.set_value(SECTION_DISPLAY, "resolution", [resolution.x, resolution.y])
	config.set_value(SECTION_DISPLAY, "vsync", vsync_enabled)
	var err := config.save(config_path)
	if err != OK:
		push_error("Could not save settings to %s (error %d)." % [config_path, err])


func apply_all() -> void:
	apply_audio()
	apply_display()
	settings_changed.emit()


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
	apply_all()
	save_settings()


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))
