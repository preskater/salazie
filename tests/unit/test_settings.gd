extends GdUnitTestSuite

const TEST_PATH := "user://test_settings.cfg"

var _original_path := ""
var _original_master := 0.0
var _original_music := 0.0
var _original_sfx := 0.0
var _original_window_mode := 0
var _original_resolution := Vector2i.ZERO
var _original_vsync := true


func before_test() -> void:
	_original_path = Settings.config_path
	_original_master = Settings.master_volume
	_original_music = Settings.music_volume
	_original_sfx = Settings.sfx_volume
	_original_window_mode = Settings.window_mode
	_original_resolution = Settings.resolution
	_original_vsync = Settings.vsync_enabled
	Settings.config_path = TEST_PATH
	_remove_file(TEST_PATH)


func after_test() -> void:
	_remove_file(TEST_PATH)
	Settings.config_path = _original_path
	Settings.master_volume = _original_master
	Settings.music_volume = _original_music
	Settings.sfx_volume = _original_sfx
	Settings.window_mode = _original_window_mode
	Settings.resolution = _original_resolution
	Settings.vsync_enabled = _original_vsync
	Settings.apply_audio()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_defaults_are_within_expected_ranges() -> void:
	Settings.reset_defaults()

	assert_float(Settings.master_volume).is_equal_approx(0.8, 0.001)
	assert_float(Settings.music_volume).is_equal_approx(0.7, 0.001)
	assert_float(Settings.sfx_volume).is_equal_approx(0.8, 0.001)
	assert_int(Settings.window_mode).is_equal(Settings.WINDOWED)
	assert_int(Settings.resolution.x).is_equal(1280)
	assert_int(Settings.resolution.y).is_equal(720)
	assert_bool(Settings.vsync_enabled).is_true()


func test_save_and_load_round_trip() -> void:
	Settings.master_volume = 0.42
	Settings.music_volume = 0.33
	Settings.sfx_volume = 0.21
	Settings.window_mode = Settings.FULLSCREEN
	Settings.resolution = Vector2i(1600, 900)
	Settings.vsync_enabled = false
	Settings.save_settings()

	Settings.master_volume = 1.0
	Settings.music_volume = 1.0
	Settings.sfx_volume = 1.0
	Settings.window_mode = Settings.WINDOWED
	Settings.resolution = Vector2i(1280, 720)
	Settings.vsync_enabled = true
	Settings.load_settings()

	assert_float(Settings.master_volume).is_equal_approx(0.42, 0.001)
	assert_float(Settings.music_volume).is_equal_approx(0.33, 0.001)
	assert_float(Settings.sfx_volume).is_equal_approx(0.21, 0.001)
	assert_int(Settings.window_mode).is_equal(Settings.FULLSCREEN)
	assert_int(Settings.resolution.x).is_equal(1600)
	assert_int(Settings.resolution.y).is_equal(900)
	assert_bool(Settings.vsync_enabled).is_false()


func test_volume_setters_clamp_values() -> void:
	Settings.set_master_volume(2.0)
	Settings.set_music_volume(-1.0)

	assert_float(Settings.master_volume).is_equal(1.0)
	assert_float(Settings.music_volume).is_equal(0.0)


func test_unknown_resolution_is_ignored() -> void:
	Settings.resolution = Vector2i(1280, 720)
	Settings.set_resolution(Vector2i(999, 999))

	assert_int(Settings.resolution.x).is_equal(1280)
	assert_int(Settings.resolution.y).is_equal(720)


func test_settings_slider_updates_the_audio_value() -> void:
	var screen: Control = load("res://game/ui/menus/screens/settings_screen.tscn").instantiate()
	add_child(screen)
	auto_free(screen)
	await get_tree().process_frame

	var slider: HSlider = screen.get_node("%MasterSlider")
	slider.value = 40.0

	assert_float(Settings.master_volume).is_equal_approx(0.4, 0.001)
	assert_str((screen.get_node("%MasterValue") as Label).text).is_equal("40 %")


func test_audio_buses_exist() -> void:
	assert_bool(AudioServer.get_bus_index("Master") >= 0).is_true()
	assert_bool(AudioServer.get_bus_index("Music") >= 0).is_true()
	assert_bool(AudioServer.get_bus_index("SFX") >= 0).is_true()
