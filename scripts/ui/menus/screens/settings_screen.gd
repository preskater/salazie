extends Control
## Audio, display and persistence for the options screen.
## Shared by the main menu and the pause menu.

signal back_requested()

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var master_value: Label = %MasterValue
@onready var music_value: Label = %MusicValue
@onready var sfx_value: Label = %SfxValue
@onready var window_mode_option: OptionButton = %WindowModeOption
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var vsync_toggle: CheckBox = %VsyncToggle
@onready var reset_button: Button = %ResetButton
@onready var back_button: Button = %BackButton
@onready var save_timer: Timer = %SaveTimer

var _refreshing := false


func _ready() -> void:
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	window_mode_option.item_selected.connect(_on_window_mode_selected)
	resolution_option.item_selected.connect(_on_resolution_selected)
	vsync_toggle.toggled.connect(_on_vsync_toggled)
	reset_button.pressed.connect(_on_reset_pressed)
	back_button.pressed.connect(_on_back_pressed)
	save_timer.timeout.connect(Settings.save_settings)
	_build_options()
	_refresh()


func on_shown() -> void:
	_refresh()
	back_button.grab_focus()


func _build_options() -> void:
	window_mode_option.clear()
	window_mode_option.add_item("Fenêtré", Settings.WINDOWED)
	window_mode_option.add_item("Plein écran", Settings.FULLSCREEN)
	resolution_option.clear()
	# Only what the screen can show; ids stay indices into Settings.RESOLUTIONS.
	var offered := Settings.available_resolutions(_screen_size())
	for index in Settings.RESOLUTIONS.size():
		var value: Vector2i = Settings.RESOLUTIONS[index]
		if offered.has(value) or value == Settings.resolution:
			resolution_option.add_item("%d × %d" % [value.x, value.y], index)
	# In a browser the page owns the canvas: these rows would do nothing.
	var windowed_platform := not OS.has_feature("web")
	(resolution_option.get_parent() as Control).visible = windowed_platform
	(vsync_toggle.get_parent() as Control).visible = windowed_platform


func _screen_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Settings.RESOLUTIONS[-1]
	return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size


func _refresh() -> void:
	_refreshing = true
	master_slider.value = Settings.master_volume * 100.0
	music_slider.value = Settings.music_volume * 100.0
	sfx_slider.value = Settings.sfx_volume * 100.0
	window_mode_option.select(Settings.window_mode)
	resolution_option.select(resolution_option.get_item_index(
		Settings.RESOLUTIONS.find(Settings.resolution)))
	vsync_toggle.button_pressed = Settings.vsync_enabled
	resolution_option.disabled = Settings.window_mode != Settings.WINDOWED
	_update_value_labels()
	_refreshing = false


func _on_master_changed(value: float) -> void:
	if _refreshing:
		return
	Settings.set_master_volume(value / 100.0)
	master_value.text = "%d %%" % int(round(value))
	_schedule_save()


func _on_music_changed(value: float) -> void:
	if _refreshing:
		return
	Settings.set_music_volume(value / 100.0)
	music_value.text = "%d %%" % int(round(value))
	_schedule_save()


func _on_sfx_changed(value: float) -> void:
	if _refreshing:
		return
	Settings.set_sfx_volume(value / 100.0)
	sfx_value.text = "%d %%" % int(round(value))
	_schedule_save()


func _on_window_mode_selected(index: int) -> void:
	if _refreshing:
		return
	Settings.set_window_mode(window_mode_option.get_item_id(index))
	resolution_option.disabled = Settings.window_mode != Settings.WINDOWED
	_schedule_save()


func _on_resolution_selected(index: int) -> void:
	if _refreshing:
		return
	var resolution_index := resolution_option.get_item_id(index)
	if resolution_index >= 0 and resolution_index < Settings.RESOLUTIONS.size():
		Settings.set_resolution(Settings.RESOLUTIONS[resolution_index])
	_schedule_save()


func _on_vsync_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	Settings.set_vsync_enabled(pressed)
	_schedule_save()


func _on_reset_pressed() -> void:
	Settings.reset_defaults()
	_refresh()


func _on_back_pressed() -> void:
	Settings.save_settings()
	back_requested.emit()


func _schedule_save() -> void:
	save_timer.start()


func _update_value_labels() -> void:
	master_value.text = "%d %%" % int(round(master_slider.value))
	music_value.text = "%d %%" % int(round(music_slider.value))
	sfx_value.text = "%d %%" % int(round(sfx_slider.value))
