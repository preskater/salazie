extends GdUnitTestSuite
## Pause overlay: opening and closing from the keyboard or gamepad, the back
## action inside a sub-screen, the manual save and the two confirmations.
## The scene swap is replaced by a recorder, so "back to the menu" runs for
## real without tearing down the test runner's scene.

const PAUSE_MENU_SCENE := "res://scenes/preloads/pause_menu.tscn"
const SAVE_PATH := "user://test_pause_menu_flows.json"
const SETTINGS_PATH := "user://test_pause_menu_flows.cfg"

var _original_save_path := ""
var _original_settings_path := ""
var _swaps: Array[String] = []


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = SAVE_PATH
	SaveGame.delete_save()
	_original_settings_path = Settings.config_path
	Settings.config_path = SETTINGS_PATH
	_remove_file(SETTINGS_PATH)
	_swaps = []
	var recorder := func(path: String) -> Error:
		_swaps.append(path)
		return OK
	SceneRouter.scene_changer = recorder
	SceneRouter.fade_time = 0.01
	SceneTransition.scene_changer = recorder
	GameState.playing = false
	Campaign.reset()
	GameState.reset()
	GameState.playing = true
	SceneRouter.is_gameplay = true


func after_test() -> void:
	if get_tree() != null:
		get_tree().paused = false
	SceneRouter.scene_changer = Callable()
	SceneRouter.fade_time = SceneRouter.FADE_TIME
	SceneTransition.scene_changer = Callable()
	GameState.playing = false
	SceneRouter.is_gameplay = false
	SaveGame.save_path = SAVE_PATH
	SaveGame.delete_save()
	SaveGame.save_path = _original_save_path
	_remove_file(SETTINGS_PATH)
	Settings.config_path = _original_settings_path
	Campaign.reset()
	GameState.reset()
	DayNightCycle.running = false
	DayNightCycle.tint_enabled = false


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _spawn_pause() -> CanvasLayer:
	var pause: CanvasLayer = auto_free(load(PAUSE_MENU_SCENE).instantiate())
	add_child(pause)
	return pause


func _press(pause: CanvasLayer, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	pause.call("_unhandled_input", event)


func _current(pause: CanvasLayer) -> String:
	return String(pause.get_node("%MenuStack").call("current_name"))


func _click(pause: CanvasLayer, button: String) -> void:
	(pause.get_node(button) as Button).pressed.emit()


# --- Opening and closing -------------------------------------------------------

func test_the_pause_action_opens_the_menu_and_freezes_the_game() -> void:
	var pause := _spawn_pause()

	_press(pause, &"pause")

	assert_bool(pause.visible).is_true()
	assert_bool((pause.get_node("%Root") as Control).visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_str(_current(pause)).is_equal("Pause")


func test_the_subtitle_sums_up_the_generation_the_day_and_the_money() -> void:
	var pause := _spawn_pause()
	GameState.day = 4
	GameState.money = 63

	_press(pause, &"pause")

	assert_str((pause.get_node("%Subtitle") as Label).text).is_equal(
		"%s · Jour 4 · 63 G" % Campaign.map_title())


func test_opening_the_menu_saves_the_game() -> void:
	var pause := _spawn_pause()
	GameState.money = 41
	assert_bool(SaveGame.has_valid_save()).is_false()

	_press(pause, &"pause")

	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(41)


func test_the_pause_action_closes_the_menu_again() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")

	_press(pause, &"pause")

	assert_bool(pause.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_cancel_closes_the_menu_from_its_first_screen() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")

	_press(pause, &"ui_cancel")

	assert_bool(pause.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_another_action_leaves_the_open_menu_alone() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")

	_press(pause, &"interact")

	assert_bool(pause.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_str(_current(pause)).is_equal("Pause")


func test_cancel_does_not_open_the_menu() -> void:
	var pause := _spawn_pause()

	_press(pause, &"ui_cancel")

	assert_bool(pause.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_the_pause_action_is_ignored_outside_gameplay() -> void:
	var pause := _spawn_pause()
	SceneRouter.is_gameplay = false

	_press(pause, &"pause")

	assert_bool(pause.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_the_pause_action_is_ignored_while_another_panel_holds_the_pause() -> void:
	var pause := _spawn_pause()
	get_tree().paused = true

	_press(pause, &"pause")

	assert_bool(pause.visible).is_false()
	# The other panel still owns the pause.
	assert_bool(get_tree().paused).is_true()


func test_the_resume_button_closes_the_menu() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")

	_click(pause, "%ResumeButton")

	assert_bool(pause.visible).is_false()
	assert_bool(get_tree().paused).is_false()


# --- Sub-screens ---------------------------------------------------------------

func test_cancel_inside_the_options_saves_them_and_returns_to_the_pause_screen() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")
	_click(pause, "%OptionsButton")
	assert_str(_current(pause)).is_equal("Settings")
	assert_bool(FileAccess.file_exists(SETTINGS_PATH)).is_false()

	_press(pause, &"ui_cancel")

	assert_str(_current(pause)).is_equal("Pause")
	assert_bool(pause.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_bool(FileAccess.file_exists(SETTINGS_PATH)).is_true()


func test_the_pause_action_inside_the_controls_returns_to_the_pause_screen() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")
	_click(pause, "%ControlsButton")
	assert_str(_current(pause)).is_equal("Controls")
	assert_bool((pause.get_node("%ControlsScreen") as Control).visible).is_true()
	assert_bool((pause.get_node("%PauseScreen") as Control).visible).is_false()

	_press(pause, &"pause")

	assert_str(_current(pause)).is_equal("Pause")
	assert_bool(pause.visible).is_true()


func test_the_back_button_of_a_sub_screen_returns_to_the_pause_screen() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")
	_click(pause, "%OptionsButton")

	((pause.get_node("%SettingsScreen") as Control).get_node("%BackButton") as Button).pressed.emit()

	assert_str(_current(pause)).is_equal("Pause")
	assert_bool((pause.get_node("%PauseScreen") as Control).visible).is_true()


func test_reopening_the_menu_starts_on_the_pause_screen_again() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")
	_click(pause, "%OptionsButton")
	pause.call("close")

	_press(pause, &"pause")

	assert_str(_current(pause)).is_equal("Pause")


# --- Manual save ---------------------------------------------------------------

func test_the_save_button_saves_and_says_so_for_a_moment() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")
	var status: Label = pause.get_node("%SaveStatus")
	var timer: Timer = pause.get_node("%SaveStatusTimer")
	timer.wait_time = 0.05
	assert_bool(status.visible).is_false()
	GameState.money = 88

	_click(pause, "%SaveButton")

	assert_str(status.text).is_equal("Partie sauvegardée.")
	assert_bool(status.visible).is_true()
	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(88)
	assert_bool(timer.is_stopped()).is_false()

	await timer.timeout

	assert_bool(status.visible).is_false()
	# The menu is still open: only the message went away.
	assert_bool(pause.visible).is_true()


func test_the_save_button_reports_a_save_that_could_not_be_written() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")
	# A folder that does not exist: the temporary file cannot be created.
	SaveGame.save_path = "user://test_pause_menu_flows_missing_dir/save.json"

	_click(pause, "%SaveButton")

	var status: Label = pause.get_node("%SaveStatus")
	assert_str(status.text).is_equal("Échec de la sauvegarde.")
	assert_bool(status.visible).is_true()
	assert_bool(FileAccess.file_exists(SaveGame.save_path)).is_false()


func test_reopening_the_menu_clears_the_save_message() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")
	_click(pause, "%SaveButton")
	pause.call("close")

	_press(pause, &"pause")

	assert_bool((pause.get_node("%SaveStatus") as Label).visible).is_false()


# --- Confirmations -------------------------------------------------------------

func test_back_to_the_menu_asks_first() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")

	_click(pause, "%MainMenuButton")

	var confirm: Control = pause.get_node("%ConfirmScreen")
	assert_str(_current(pause)).is_equal("Confirm")
	assert_str((confirm.get_node("%TitleLabel") as Label).text).is_equal("Menu principal")
	assert_str((confirm.get_node("%MessageLabel") as Label).text).contains("sauvegardée")
	assert_str((confirm.get_node("%ConfirmButton") as Button).text).is_equal("Revenir")
	assert_str((confirm.get_node("%CancelButton") as Button).text).is_equal("Annuler")
	assert_array(_swaps).is_empty()


func test_refusing_to_go_back_to_the_menu_keeps_the_game_paused() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")
	_click(pause, "%MainMenuButton")

	((pause.get_node("%ConfirmScreen") as Control).get_node("%CancelButton") as Button).pressed.emit()

	assert_str(_current(pause)).is_equal("Pause")
	assert_bool(pause.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_bool(SceneRouter.is_gameplay).is_true()
	assert_array(_swaps).is_empty()


func test_cancel_on_a_confirmation_refuses_it() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")
	_click(pause, "%MainMenuButton")

	_press(pause, &"ui_cancel")

	assert_str(_current(pause)).is_equal("Pause")
	assert_bool(pause.visible).is_true()
	assert_array(_swaps).is_empty()
	# The refused action is forgotten: confirming later must not replay it.
	(pause.get_node("%ConfirmScreen") as Control).emit_signal("confirmed")
	await get_tree().process_frame
	assert_array(_swaps).is_empty()
	assert_bool(SceneRouter.is_gameplay).is_true()


func test_confirming_goes_back_to_the_main_menu_and_saves() -> void:
	var pause := _spawn_pause()
	GameState.money = 72
	_press(pause, &"pause")
	_click(pause, "%MainMenuButton")
	GameState.money = 73

	((pause.get_node("%ConfirmScreen") as Control).get_node("%ConfirmButton") as Button).pressed.emit()

	assert_bool(pause.visible).is_false()
	await SceneRouter.transition_finished
	assert_array(_swaps).is_equal([SceneRouter.MAIN_MENU_SCENE])
	assert_bool(get_tree().paused).is_false()
	assert_bool(SceneRouter.is_gameplay).is_false()
	assert_bool(GameState.playing).is_false()
	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(73)


func test_quitting_asks_first_and_can_be_refused() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")

	_click(pause, "%QuitButton")

	var confirm: Control = pause.get_node("%ConfirmScreen")
	assert_str(_current(pause)).is_equal("Confirm")
	assert_str((confirm.get_node("%TitleLabel") as Label).text).is_equal("Quitter")
	assert_str((confirm.get_node("%MessageLabel") as Label).text).is_equal(
		"Voulez-vous quitter Salazie ? La partie sera sauvegardée.")
	assert_str((confirm.get_node("%ConfirmButton") as Button).text).is_equal("Quitter")

	(confirm.get_node("%CancelButton") as Button).pressed.emit()

	assert_str(_current(pause)).is_equal("Pause")
	assert_bool(pause.visible).is_true()
	assert_bool(get_tree().paused).is_true()


# --- Scene changes -------------------------------------------------------------

func test_the_menu_closes_when_the_game_leaves_gameplay() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")

	# Something else than the pause menu sends the player back to the menu.
	await SceneRouter.go_to_main_menu()

	assert_bool(pause.visible).is_false()
	assert_bool((pause.get_node("%Root") as Control).visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_the_menu_stays_open_when_a_gameplay_scene_is_announced() -> void:
	var pause := _spawn_pause()
	_press(pause, &"pause")

	SceneRouter.scene_changed.emit(null)

	assert_bool(pause.visible).is_true()
	assert_bool(get_tree().paused).is_true()
