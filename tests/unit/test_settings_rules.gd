extends GdUnitTestSuite
## Settings autoload rules (clamping, signals, audio buses, tolerant loading)
## and the options screen that drives it.

const SETTINGS_SCREEN := "res://scenes/ui/menus/screens/settings_screen.tscn"
const TEST_PATH := "user://test_settings_rules.cfg"

var _original_path := ""
var _original_master := 0.0
var _original_music := 0.0
var _original_sfx := 0.0
var _original_window_mode := 0
var _original_resolution := Vector2i.ZERO
var _original_vsync := true
var _original_controls_override := -1
var _original_screen_override := Vector2i.ZERO
var _original_ui_scale := 1.0
var _original_pause_focus := false
var _original_reduced_shake := false
var _original_reduced_flash := false
var _changes := 0


func before_test() -> void:
	_original_path = Settings.config_path
	_original_master = Settings.master_volume
	_original_music = Settings.music_volume
	_original_sfx = Settings.sfx_volume
	_original_window_mode = Settings.window_mode
	_original_resolution = Settings.resolution
	_original_vsync = Settings.vsync_enabled
	_original_controls_override = Settings.controls_window_override
	_original_screen_override = Settings.screen_size_override
	_original_ui_scale = Settings.ui_scale
	_original_pause_focus = Settings.pause_on_focus_loss
	_original_reduced_shake = Settings.reduced_shake
	_original_reduced_flash = Settings.reduced_flash
	# A runner may have a real screen (X11 under a CI agent) or none at all;
	# pin both so the options screen is tested, not the machine running it.
	Settings.controls_window_override = 0
	Settings.screen_size_override = Vector2i(1920, 1080)
	Settings.config_path = TEST_PATH
	_remove_file(TEST_PATH)
	Settings.master_volume = Settings.DEFAULT_MASTER
	Settings.music_volume = Settings.DEFAULT_MUSIC
	Settings.sfx_volume = Settings.DEFAULT_SFX
	Settings.window_mode = Settings.WINDOWED
	Settings.resolution = Settings.RESOLUTIONS[0]
	Settings.vsync_enabled = true
	Settings.ui_scale = 1.0
	Settings.pause_on_focus_loss = false
	Settings.reduced_shake = false
	Settings.reduced_flash = false
	Settings.apply_audio()
	_changes = 0
	Settings.settings_changed.connect(_on_settings_changed)


func after_test() -> void:
	Settings.settings_changed.disconnect(_on_settings_changed)
	_remove_file(TEST_PATH)
	Settings.config_path = _original_path
	Settings.master_volume = _original_master
	Settings.music_volume = _original_music
	Settings.sfx_volume = _original_sfx
	Settings.window_mode = _original_window_mode
	Settings.resolution = _original_resolution
	Settings.vsync_enabled = _original_vsync
	Settings.controls_window_override = _original_controls_override
	Settings.screen_size_override = _original_screen_override
	Settings.ui_scale = _original_ui_scale
	Settings.pause_on_focus_loss = _original_pause_focus
	Settings.reduced_shake = _original_reduced_shake
	Settings.reduced_flash = _original_reduced_flash
	Settings.apply_audio()


func _on_settings_changed() -> void:
	_changes += 1


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_config(values: Dictionary) -> void:
	var config := ConfigFile.new()
	for key: String in values:
		var parts := key.split("/")
		config.set_value(parts[0], parts[1], values[key])
	assert_int(config.save(TEST_PATH)).is_equal(OK)


func _read_config() -> ConfigFile:
	var config := ConfigFile.new()
	assert_int(config.load(TEST_PATH)).is_equal(OK)
	return config


func _bus_db(bus: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))


func _bus_muted(bus: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))


func _spawn_screen() -> Control:
	var screen: Control = auto_free(load(SETTINGS_SCREEN).instantiate())
	add_child(screen)
	return screen


# --- Setters -------------------------------------------------------------------

func test_each_volume_drives_its_own_audio_bus() -> void:
	Settings.set_master_volume(0.5)
	Settings.set_music_volume(0.25)
	Settings.set_sfx_volume(1.0)

	assert_float(_bus_db("Master")).is_equal_approx(linear_to_db(0.5), 0.01)
	assert_float(_bus_db("Music")).is_equal_approx(linear_to_db(0.25), 0.01)
	assert_float(_bus_db("SFX")).is_equal_approx(0.0, 0.01)
	assert_bool(_bus_muted("Master")).is_false()
	assert_bool(_bus_muted("Music")).is_false()
	assert_bool(_bus_muted("SFX")).is_false()
	assert_int(_changes).is_equal(3)


func test_a_volume_at_zero_mutes_its_bus_and_raising_it_unmutes() -> void:
	Settings.set_sfx_volume(0.0)

	assert_bool(_bus_muted("SFX")).is_true()
	assert_bool(_bus_muted("Music")).is_false()

	Settings.set_sfx_volume(0.6)

	assert_bool(_bus_muted("SFX")).is_false()
	assert_float(_bus_db("SFX")).is_equal_approx(linear_to_db(0.6), 0.01)


func test_sfx_volume_is_clamped() -> void:
	Settings.set_sfx_volume(3.0)
	assert_float(Settings.sfx_volume).is_equal(1.0)

	Settings.set_sfx_volume(-1.0)
	assert_float(Settings.sfx_volume).is_equal(0.0)
	assert_bool(_bus_muted("SFX")).is_true()


func test_window_mode_is_clamped_to_the_known_modes() -> void:
	Settings.set_window_mode(Settings.FULLSCREEN)
	assert_int(Settings.window_mode).is_equal(Settings.FULLSCREEN)

	Settings.set_window_mode(7)
	assert_int(Settings.window_mode).is_equal(Settings.FULLSCREEN)

	Settings.set_window_mode(-3)
	assert_int(Settings.window_mode).is_equal(Settings.WINDOWED)
	assert_int(_changes).is_equal(3)


func test_a_listed_resolution_is_kept_and_announced() -> void:
	Settings.set_resolution(Vector2i(1920, 1080))

	assert_that(Settings.resolution).is_equal(Vector2i(1920, 1080))
	assert_int(_changes).is_equal(1)


func test_an_unlisted_resolution_announces_nothing() -> void:
	Settings.set_resolution(Vector2i(640, 480))

	assert_that(Settings.resolution).is_equal(Settings.RESOLUTIONS[0])
	assert_int(_changes).is_equal(0)


func test_vsync_can_be_turned_off_and_on() -> void:
	Settings.set_vsync_enabled(false)
	assert_bool(Settings.vsync_enabled).is_false()

	Settings.set_vsync_enabled(true)
	assert_bool(Settings.vsync_enabled).is_true()
	assert_int(_changes).is_equal(2)


func test_reset_restores_every_default_and_writes_the_file() -> void:
	Settings.set_master_volume(0.1)
	Settings.set_music_volume(0.0)
	Settings.set_sfx_volume(0.2)
	Settings.set_window_mode(Settings.FULLSCREEN)
	Settings.set_resolution(Vector2i(1600, 900))
	Settings.set_vsync_enabled(false)
	_changes = 0

	Settings.reset_defaults()

	assert_float(Settings.master_volume).is_equal(Settings.DEFAULT_MASTER)
	assert_float(Settings.music_volume).is_equal(Settings.DEFAULT_MUSIC)
	assert_float(Settings.sfx_volume).is_equal(Settings.DEFAULT_SFX)
	assert_int(Settings.window_mode).is_equal(Settings.WINDOWED)
	assert_that(Settings.resolution).is_equal(Settings.RESOLUTIONS[0])
	assert_bool(Settings.vsync_enabled).is_true()
	assert_int(_changes).is_equal(1)
	assert_bool(_bus_muted("Music")).is_false()
	assert_float(_bus_db("Music")).is_equal_approx(linear_to_db(Settings.DEFAULT_MUSIC), 0.01)
	var config := _read_config()
	assert_float(float(config.get_value("audio", "master"))).is_equal(Settings.DEFAULT_MASTER)
	assert_bool(bool(config.get_value("display", "vsync"))).is_true()
	assert_array(config.get_value("display", "resolution")).is_equal([1280, 720])


func test_a_missing_bus_does_not_stop_the_other_volumes() -> void:
	var layout: AudioBusLayout = load(
		String(ProjectSettings.get_setting("audio/buses/default_bus_layout")))
	AudioServer.remove_bus(AudioServer.get_bus_index("Music"))
	assert_int(AudioServer.get_bus_index("Music")).is_equal(-1)

	Settings.set_master_volume(0.3)
	Settings.set_sfx_volume(0.4)

	var master_db := _bus_db("Master")
	var sfx_db := _bus_db("SFX")
	AudioServer.set_bus_layout(layout)
	assert_float(master_db).is_equal_approx(linear_to_db(0.3), 0.01)
	assert_float(sfx_db).is_equal_approx(linear_to_db(0.4), 0.01)
	assert_bool(AudioServer.get_bus_index("Music") >= 0).is_true()
	assert_bool(AudioServer.get_bus_index("SFX") >= 0).is_true()


# --- Loading -------------------------------------------------------------------

func test_out_of_range_values_are_clamped_on_load() -> void:
	_write_config({
		"audio/master": 4.0,
		"audio/music": -2.0,
		"audio/sfx": 0.35,
		"display/window_mode": 9,
		"display/vsync": false,
		"display/resolution": [1600, 900],
	})

	Settings.load_settings()

	assert_float(Settings.master_volume).is_equal(1.0)
	assert_float(Settings.music_volume).is_equal(0.0)
	assert_float(Settings.sfx_volume).is_equal_approx(0.35, 0.001)
	assert_int(Settings.window_mode).is_equal(Settings.FULLSCREEN)
	assert_bool(Settings.vsync_enabled).is_false()
	assert_that(Settings.resolution).is_equal(Vector2i(1600, 900))


func test_a_negative_window_mode_loads_as_windowed() -> void:
	Settings.window_mode = Settings.FULLSCREEN
	_write_config({"display/window_mode": -5})

	Settings.load_settings()

	assert_int(Settings.window_mode).is_equal(Settings.WINDOWED)


func test_a_malformed_resolution_keeps_the_current_one() -> void:
	Settings.resolution = Vector2i(1600, 900)
	for stored: Variant in ["1920x1080", [1920], [1920, 1080, 60], [800, 600], 1080]:
		_write_config({"display/resolution": stored})

		Settings.load_settings()

		assert_that(Settings.resolution).override_failure_message(
			"Stored resolution %s should have been ignored" % str(stored)
		).is_equal(Vector2i(1600, 900))


func test_a_partial_file_keeps_the_values_it_does_not_mention() -> void:
	Settings.master_volume = 0.15
	Settings.vsync_enabled = false
	_write_config({"audio/music": 0.45})

	Settings.load_settings()

	assert_float(Settings.music_volume).is_equal_approx(0.45, 0.001)
	assert_float(Settings.master_volume).is_equal_approx(0.15, 0.001)
	assert_bool(Settings.vsync_enabled).is_false()


func test_a_missing_file_keeps_the_current_settings() -> void:
	Settings.master_volume = 0.33
	Settings.window_mode = Settings.FULLSCREEN

	Settings.load_settings()

	assert_float(Settings.master_volume).is_equal_approx(0.33, 0.001)
	assert_int(Settings.window_mode).is_equal(Settings.FULLSCREEN)


func test_a_file_that_cannot_be_written_leaves_the_settings_in_memory() -> void:
	Settings.config_path = "user://test_settings_rules_missing_dir/settings.cfg"
	Settings.master_volume = 0.42

	Settings.save_settings()

	assert_bool(FileAccess.file_exists(Settings.config_path)).is_false()
	assert_float(Settings.master_volume).is_equal_approx(0.42, 0.001)


# --- Options screen ------------------------------------------------------------

func test_the_screen_opens_on_the_current_settings() -> void:
	Settings.master_volume = 0.3
	Settings.music_volume = 0.55
	Settings.sfx_volume = 1.0
	Settings.resolution = Vector2i(1920, 1080)
	Settings.vsync_enabled = false

	var screen := _spawn_screen()

	assert_float((screen.get_node("%MasterSlider") as HSlider).value).is_equal_approx(30.0, 0.01)
	assert_str((screen.get_node("%MasterValue") as Label).text).is_equal("30 %")
	assert_str((screen.get_node("%MusicValue") as Label).text).is_equal("55 %")
	assert_str((screen.get_node("%SfxValue") as Label).text).is_equal("100 %")
	var resolution: OptionButton = screen.get_node("%ResolutionOption")
	# The pinned screen can show every preset, so all three are listed.
	assert_int(resolution.item_count).is_equal(Settings.RESOLUTIONS.size())
	assert_str(resolution.get_item_text(resolution.selected)).is_equal("1920 × 1080")
	assert_bool((screen.get_node("%VsyncToggle") as CheckBox).button_pressed).is_false()
	var mode: OptionButton = screen.get_node("%WindowModeOption")
	assert_str(mode.get_item_text(mode.selected)).is_equal("Fenêtré")
	# Showing the values is not a change: nothing is scheduled for saving.
	assert_bool((screen.get_node("%SaveTimer") as Timer).is_stopped()).is_true()
	assert_int(_changes).is_equal(0)


func test_the_music_and_sfx_sliders_set_their_volume_and_label() -> void:
	var screen := _spawn_screen()

	(screen.get_node("%MusicSlider") as HSlider).value = 35.0
	(screen.get_node("%SfxSlider") as HSlider).value = 0.0

	assert_float(Settings.music_volume).is_equal_approx(0.35, 0.001)
	assert_str((screen.get_node("%MusicValue") as Label).text).is_equal("35 %")
	assert_float(Settings.sfx_volume).is_equal(0.0)
	assert_str((screen.get_node("%SfxValue") as Label).text).is_equal("0 %")
	assert_bool(_bus_muted("SFX")).is_true()
	assert_float(_bus_db("Music")).is_equal_approx(linear_to_db(0.35), 0.01)
	# The master volume was not touched.
	assert_float(Settings.master_volume).is_equal(Settings.DEFAULT_MASTER)


func test_fullscreen_disables_the_resolution_choice() -> void:
	var screen := _spawn_screen()
	var mode: OptionButton = screen.get_node("%WindowModeOption")
	var resolution: OptionButton = screen.get_node("%ResolutionOption")
	assert_bool(resolution.disabled).is_false()

	mode.select(1)
	mode.item_selected.emit(1)

	assert_int(Settings.window_mode).is_equal(Settings.FULLSCREEN)
	assert_bool(resolution.disabled).is_true()

	mode.select(0)
	mode.item_selected.emit(0)

	assert_int(Settings.window_mode).is_equal(Settings.WINDOWED)
	assert_bool(resolution.disabled).is_false()


func test_a_screen_opened_in_fullscreen_has_no_resolution_choice() -> void:
	Settings.window_mode = Settings.FULLSCREEN

	var screen := _spawn_screen()

	assert_bool((screen.get_node("%ResolutionOption") as OptionButton).disabled).is_true()
	var mode: OptionButton = screen.get_node("%WindowModeOption")
	assert_str(mode.get_item_text(mode.selected)).is_equal("Plein écran")


func test_choosing_a_resolution_applies_it() -> void:
	var screen := _spawn_screen()
	var resolution: OptionButton = screen.get_node("%ResolutionOption")

	resolution.select(2)
	resolution.item_selected.emit(2)

	assert_that(Settings.resolution).is_equal(Settings.RESOLUTIONS[2])
	assert_bool((screen.get_node("%SaveTimer") as Timer).is_stopped()).is_false()


func test_the_vsync_box_toggles_vsync() -> void:
	var screen := _spawn_screen()
	var toggle: CheckBox = screen.get_node("%VsyncToggle")

	toggle.button_pressed = false
	assert_bool(Settings.vsync_enabled).is_false()

	toggle.button_pressed = true
	assert_bool(Settings.vsync_enabled).is_true()


func test_a_change_is_written_after_a_short_delay_not_at_once() -> void:
	var screen := _spawn_screen()
	var timer: Timer = screen.get_node("%SaveTimer")
	timer.wait_time = 0.05

	(screen.get_node("%MasterSlider") as HSlider).value = 20.0

	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()
	assert_bool(timer.is_stopped()).is_false()

	await timer.timeout

	assert_float(float(_read_config().get_value("audio", "master"))).is_equal_approx(0.2, 0.001)


func test_reset_puts_the_controls_back_to_the_defaults() -> void:
	var screen := _spawn_screen()
	var mode: OptionButton = screen.get_node("%WindowModeOption")
	(screen.get_node("%MasterSlider") as HSlider).value = 10.0
	(screen.get_node("%SfxSlider") as HSlider).value = 5.0
	mode.select(1)
	mode.item_selected.emit(1)
	(screen.get_node("%VsyncToggle") as CheckBox).button_pressed = false

	(screen.get_node("%ResetButton") as Button).pressed.emit()

	assert_float((screen.get_node("%MasterSlider") as HSlider).value).is_equal_approx(80.0, 0.01)
	assert_float((screen.get_node("%MusicSlider") as HSlider).value).is_equal_approx(70.0, 0.01)
	assert_float((screen.get_node("%SfxSlider") as HSlider).value).is_equal_approx(80.0, 0.01)
	assert_str((screen.get_node("%MasterValue") as Label).text).is_equal("80 %")
	assert_str((screen.get_node("%SfxValue") as Label).text).is_equal("80 %")
	assert_int(mode.selected).is_equal(0)
	assert_bool((screen.get_node("%ResolutionOption") as OptionButton).disabled).is_false()
	assert_bool((screen.get_node("%VsyncToggle") as CheckBox).button_pressed).is_true()
	assert_float(Settings.master_volume).is_equal(Settings.DEFAULT_MASTER)
	assert_float(float(_read_config().get_value("audio", "sfx"))).is_equal(Settings.DEFAULT_SFX)


func test_back_saves_at_once_and_asks_to_leave() -> void:
	var screen := _spawn_screen()
	var requests: Array[bool] = []
	screen.connect("back_requested", func() -> void: requests.append(true))
	(screen.get_node("%MusicSlider") as HSlider).value = 15.0
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()

	(screen.get_node("%BackButton") as Button).pressed.emit()

	assert_int(requests.size()).is_equal(1)
	assert_float(float(_read_config().get_value("audio", "music"))).is_equal_approx(0.15, 0.001)


func test_showing_the_screen_again_picks_up_settings_changed_elsewhere() -> void:
	var screen := _spawn_screen()
	Settings.set_master_volume(0.25)
	Settings.set_window_mode(Settings.FULLSCREEN)
	_changes = 0

	screen.call("on_shown")

	assert_float((screen.get_node("%MasterSlider") as HSlider).value).is_equal_approx(25.0, 0.01)
	assert_str((screen.get_node("%MasterValue") as Label).text).is_equal("25 %")
	assert_bool((screen.get_node("%ResolutionOption") as OptionButton).disabled).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(screen.get_node("%BackButton"))
	# Refreshing the controls is not a player change.
	assert_int(_changes).is_equal(0)
	assert_bool((screen.get_node("%SaveTimer") as Timer).is_stopped()).is_true()


# --- #47 -----------------------------------------------------------------------

func test_only_resolutions_the_screen_can_show_are_offered() -> void:
	assert_array(Settings.available_resolutions(Vector2i(1920, 1080))) \
		.is_equal(Array(Settings.RESOLUTIONS))
	assert_array(Settings.available_resolutions(Vector2i(1728, 1000))) \
		.is_equal([Vector2i(1280, 720), Vector2i(1600, 900)])
	# A screen smaller than every preset still gets the smallest one.
	assert_array(Settings.available_resolutions(Vector2i(1024, 600))) \
		.is_equal([Vector2i(1280, 720)])


func test_a_resolution_too_large_for_the_screen_falls_back_to_one_that_fits() -> void:
	assert_vector(Settings.fitting_resolution(Vector2i(1920, 1080), Vector2i(1728, 1000))) \
		.is_equal(Vector2i(1600, 900))
	assert_vector(Settings.fitting_resolution(Vector2i(1280, 720), Vector2i(1728, 1000))) \
		.is_equal(Vector2i(1280, 720))


func test_the_platform_rules_decide_who_owns_the_window() -> void:
	assert_bool(Settings.owns_window("headless", false)).is_false()
	assert_bool(Settings.owns_window("X11", true)).is_false()
	assert_bool(Settings.owns_window("macOS", false)).is_true()
	# Without an override the rule is applied to this very runner.
	Settings.controls_window_override = -1
	assert_bool(Settings.controls_window()).is_equal(
		Settings.owns_window(DisplayServer.get_name(), OS.has_feature("web")))


func test_the_screen_size_comes_from_the_real_screen_without_an_override() -> void:
	Settings.screen_size_override = Vector2i.ZERO
	var size := Settings.screen_size()
	assert_bool(size.x > 0 and size.y > 0).is_true()
	if DisplayServer.get_name() == "headless":
		assert_vector(size).is_equal(Settings.RESOLUTIONS[-1])


func test_settings_are_kept_without_ever_touching_a_window() -> void:
	assert_bool(Settings.controls_window()).is_false()
	Settings.set_vsync_enabled(false)
	Settings.set_window_mode(Settings.FULLSCREEN)
	Settings.set_resolution(Vector2i(1600, 900))

	assert_int(Settings.window_mode).is_equal(Settings.FULLSCREEN)
	assert_vector(Settings.resolution).is_equal(Vector2i(1600, 900))
	assert_bool(Settings.vsync_enabled).is_false()


# --- #55 -----------------------------------------------------------------------

func test_the_comfort_options_start_off() -> void:
	assert_float(Settings.ui_scale).is_equal(1.0)
	assert_bool(Settings.pause_on_focus_loss).is_false()
	assert_bool(Settings.reduced_shake).is_false()
	assert_bool(Settings.reduced_flash).is_false()


func test_only_the_offered_display_scales_are_accepted() -> void:
	Settings.set_ui_scale(1.25)
	assert_float(Settings.ui_scale).is_equal(1.25)
	# Anything else is ignored rather than stretching the view at random.
	Settings.set_ui_scale(1.1)
	assert_float(Settings.ui_scale).is_equal(1.25)


func test_a_hand_edited_comfort_block_is_ignored() -> void:
	_write_config({"accessibility/ui_scale": 3.0, "accessibility/reduced_shake": "oui"})
	Settings.ui_scale = 1.25
	Settings.reduced_shake = false

	Settings.load_settings()

	# The scale is not one of the offered ones and the flag is not a boolean:
	# both keep the value already in memory, like a missing key.
	assert_float(Settings.ui_scale).is_equal(1.25)
	assert_bool(Settings.reduced_shake).is_false()


func test_the_comfort_options_round_trip_through_the_file() -> void:
	Settings.set_ui_scale(1.5)
	Settings.set_pause_on_focus_loss(true)
	Settings.set_reduced_shake(true)
	Settings.set_reduced_flash(true)
	Settings.save_settings()
	Settings.ui_scale = 1.0
	Settings.pause_on_focus_loss = false
	Settings.reduced_shake = false
	Settings.reduced_flash = false

	Settings.load_settings()

	assert_float(Settings.ui_scale).is_equal(1.5)
	assert_bool(Settings.pause_on_focus_loss).is_true()
	assert_bool(Settings.reduced_shake).is_true()
	assert_bool(Settings.reduced_flash).is_true()


func test_the_comfort_shares_scale_what_is_on_screen() -> void:
	assert_float(Settings.shake_share()).is_equal(1.0)
	assert_float(Settings.flash_share()).is_equal(1.0)

	Settings.set_reduced_shake(true)
	Settings.set_reduced_flash(true)

	assert_float(Settings.shake_share()).is_equal(Settings.REDUCED_SHAKE_SHARE)
	assert_float(Settings.flash_share()).is_equal(Settings.REDUCED_FLASH_SHARE)


func test_the_fullscreen_shortcut_swaps_the_mode_and_remembers_it() -> void:
	Settings.window_mode = Settings.WINDOWED

	Settings.toggle_fullscreen()

	assert_int(Settings.window_mode).is_equal(Settings.FULLSCREEN)
	assert_int(int(_read_config().get_value("display", "window_mode"))).is_equal(Settings.FULLSCREEN)

	Settings.toggle_fullscreen()
	assert_int(Settings.window_mode).is_equal(Settings.WINDOWED)


func test_the_fullscreen_shortcut_needs_a_window_to_own() -> void:
	var event := InputEventAction.new()
	event.action = &"toggle_fullscreen"
	event.pressed = true

	assert_bool(Settings.handles_fullscreen_shortcut(event)).is_false()
	Settings.controls_window_override = 1
	assert_bool(Settings.handles_fullscreen_shortcut(event)).is_true()
	# Any other action is left to the game.
	var other := InputEventAction.new()
	other.action = &"pause"
	other.pressed = true
	assert_bool(Settings.handles_fullscreen_shortcut(other)).is_false()


func test_the_screen_shows_the_comfort_options() -> void:
	Settings.ui_scale = 1.25
	Settings.pause_on_focus_loss = true
	Settings.reduced_shake = true
	Settings.reduced_flash = true

	var screen := _spawn_screen()

	var scale_option: OptionButton = screen.get_node("%UiScaleOption")
	assert_str(scale_option.get_item_text(scale_option.selected)).is_equal("125 %")
	assert_bool((screen.get_node("%PauseFocusToggle") as CheckBox).button_pressed).is_true()
	assert_bool((screen.get_node("%ReducedShakeToggle") as CheckBox).button_pressed).is_true()
	assert_bool((screen.get_node("%ReducedFlashToggle") as CheckBox).button_pressed).is_true()
	var hint: String = (screen.get_node("%FullscreenHint") as Label).text
	assert_str(hint).contains(InputHints.label(&"toggle_fullscreen"))
	# Showing the values is not a change: nothing is scheduled for saving.
	assert_bool((screen.get_node("%SaveTimer") as Timer).is_stopped()).is_true()
	assert_int(_changes).is_equal(0)


func test_the_comfort_controls_write_their_settings() -> void:
	var screen := _spawn_screen()
	var scale_option: OptionButton = screen.get_node("%UiScaleOption")

	scale_option.select(2)
	scale_option.item_selected.emit(2)
	(screen.get_node("%PauseFocusToggle") as CheckBox).button_pressed = true
	(screen.get_node("%ReducedShakeToggle") as CheckBox).button_pressed = true
	(screen.get_node("%ReducedFlashToggle") as CheckBox).button_pressed = true

	assert_float(Settings.ui_scale).is_equal(1.5)
	assert_bool(Settings.pause_on_focus_loss).is_true()
	assert_bool(Settings.reduced_shake).is_true()
	assert_bool(Settings.reduced_flash).is_true()
	assert_bool((screen.get_node("%SaveTimer") as Timer).is_stopped()).is_false()


func test_the_reset_button_restores_the_comfort_defaults() -> void:
	Settings.ui_scale = 1.5
	Settings.pause_on_focus_loss = true
	Settings.reduced_shake = true
	Settings.reduced_flash = true
	var screen := _spawn_screen()

	(screen.get_node("%ResetButton") as Button).pressed.emit()

	assert_float(Settings.ui_scale).is_equal(1.0)
	assert_bool(Settings.pause_on_focus_loss).is_false()
	assert_bool(Settings.reduced_shake).is_false()
	assert_bool(Settings.reduced_flash).is_false()
	assert_int((screen.get_node("%UiScaleOption") as OptionButton).selected).is_equal(0)


func test_the_fullscreen_shortcut_is_bound_to_f11() -> void:
	assert_bool(InputMap.has_action(&"toggle_fullscreen")).is_true()
	var keys := 0
	for event: InputEvent in InputMap.action_get_events(&"toggle_fullscreen"):
		if event is InputEventKey:
			keys += 1
			assert_int((event as InputEventKey).physical_keycode).is_equal(KEY_F11)
	assert_int(keys).is_equal(1)
