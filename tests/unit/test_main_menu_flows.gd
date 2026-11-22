extends GdUnitTestSuite
## Main menu: new game with and without a save, continue, credits, the back
## action on every screen and the confirmations.
## The scene swap is replaced by a recorder, as in test_scene_router.gd.

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const SAVE_PATH := "user://test_main_menu_flows.json"
const SETTINGS_PATH := "user://test_main_menu_flows.cfg"

var _original_save_path := ""
var _original_settings_path := ""
var _swaps: Array[String] = []
var _swap_result: Error = OK


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = SAVE_PATH
	SaveGame.delete_save()
	_original_settings_path = Settings.config_path
	Settings.config_path = SETTINGS_PATH
	_remove_file(SETTINGS_PATH)
	_swaps = []
	_swap_result = OK
	var recorder := func(path: String) -> Error:
		_swaps.append(path)
		return _swap_result
	SceneRouter.scene_changer = recorder
	SceneRouter.fade_time = 0.01
	SceneTransition.scene_changer = recorder
	GameState.playing = false
	Campaign.reset()
	GameState.reset()
	SceneRouter.is_gameplay = false


func after_test() -> void:
	SceneRouter.scene_changer = Callable()
	SceneRouter.fade_time = SceneRouter.FADE_TIME
	SceneTransition.scene_changer = Callable()
	GameState.playing = false
	SaveGame.delete_save()
	SaveGame.save_path = _original_save_path
	_remove_file(SETTINGS_PATH)
	Settings.config_path = _original_settings_path
	Campaign.reset()
	GameState.reset()
	GameState.farm_active = true
	SceneRouter.is_gameplay = false
	DayNightCycle.running = false
	DayNightCycle.tint_enabled = false
	if get_tree() != null:
		get_tree().paused = false


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _spawn_menu() -> Control:
	var menu: Control = auto_free(load(MAIN_MENU_SCENE).instantiate())
	add_child(menu)
	return menu


## Writes a save for the given generation, then goes back to a clean menu state.
func _write_save(map_id: int, money: int) -> void:
	Campaign.current_map = map_id
	GameState.money = money
	GameState.playing = true
	assert_bool(SaveGame.save_game()).is_true()
	GameState.playing = false
	Campaign.reset()
	GameState.reset()


func _cancel(menu: Control) -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	menu.call("_unhandled_input", event)


func _current(menu: Control) -> String:
	return String(menu.get_node("%MenuStack").call("current_name"))


func _click(menu: Control, button: String) -> void:
	(menu.get_node(button) as Button).pressed.emit()


func _confirm_button(menu: Control, button: String) -> Button:
	return (menu.get_node("%ConfirmScreen") as Control).get_node(button) as Button


# --- New game ------------------------------------------------------------------

func test_new_game_starts_at_once_when_there_is_no_save() -> void:
	var menu := _spawn_menu()

	_click(menu, "%NewGameButton")

	assert_str(_current(menu)).is_equal("Home")
	await SceneRouter.transition_finished
	await get_tree().process_frame
	assert_array(_swaps).is_equal([SceneRouter.GAME_SCENE])
	assert_bool(GameState.playing).is_true()
	assert_bool(SceneRouter.is_gameplay).is_true()
	assert_int(int(SaveGame.read_metadata()["map"])).is_equal(1)


func test_new_game_asks_before_replacing_a_save() -> void:
	_write_save(2, 140)
	var menu := _spawn_menu()

	_click(menu, "%NewGameButton")

	var confirm: Control = menu.get_node("%ConfirmScreen")
	assert_str(_current(menu)).is_equal("Confirm")
	assert_bool(confirm.visible).is_true()
	assert_bool((menu.get_node("%HomeScreen") as Control).visible).is_false()
	assert_str((confirm.get_node("%TitleLabel") as Label).text).is_equal("Nouvelle partie")
	assert_str((confirm.get_node("%MessageLabel") as Label).text).is_equal(
		"Une sauvegarde existe déjà. Voulez-vous la remplacer ?")
	assert_str(_confirm_button(menu, "%ConfirmButton").text).is_equal("Remplacer")
	assert_str(_confirm_button(menu, "%CancelButton").text).is_equal("Annuler")
	assert_array(_swaps).is_empty()
	assert_bool(SceneRouter.is_transitioning()).is_false()


func test_refusing_to_replace_the_save_keeps_it() -> void:
	_write_save(2, 140)
	var menu := _spawn_menu()
	_click(menu, "%NewGameButton")

	_confirm_button(menu, "%CancelButton").pressed.emit()

	assert_str(_current(menu)).is_equal("Home")
	assert_array(_swaps).is_empty()
	assert_int(int(SaveGame.read_metadata()["map"])).is_equal(2)
	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(140)
	# The refused action is forgotten: a stray confirmation starts nothing.
	(menu.get_node("%ConfirmScreen") as Control).emit_signal("confirmed")
	await get_tree().process_frame
	assert_array(_swaps).is_empty()
	assert_bool(SceneRouter.is_transitioning()).is_false()


func test_accepting_to_replace_the_save_starts_a_fresh_game() -> void:
	_write_save(2, 140)
	var menu := _spawn_menu()
	_click(menu, "%NewGameButton")

	_confirm_button(menu, "%ConfirmButton").pressed.emit()

	assert_str(_current(menu)).is_equal("Home")
	await SceneRouter.transition_finished
	await get_tree().process_frame
	assert_array(_swaps).is_equal([SceneRouter.GAME_SCENE])
	assert_int(Campaign.current_map).is_equal(1)
	var metadata := SaveGame.read_metadata()
	assert_int(int(metadata["map"])).is_equal(1)
	assert_int(int(metadata["money"])).is_equal(Campaign.starting_money_for_map(1))


# --- Continue ------------------------------------------------------------------

func test_continue_resumes_the_saved_generation() -> void:
	_write_save(2, 77)
	var menu := _spawn_menu()
	assert_str((menu.get_node("%ContinueInfo") as Label).text).is_equal(
		"Gén. 2 · %s · Jour 1 · 77 G" % Campaign.map_title(2))

	_click(menu, "%ContinueButton")

	await SceneRouter.transition_finished
	await get_tree().process_frame
	assert_array(_swaps).is_equal([SceneRouter.FARM_SCENE])
	assert_int(GameState.money).is_equal(77)
	assert_int(Campaign.current_map).is_equal(2)
	assert_bool(SceneRouter.is_gameplay).is_true()


func test_continue_says_so_when_the_game_could_not_be_resumed() -> void:
	_write_save(2, 77)
	var menu := _spawn_menu()
	_swap_result = ERR_CANT_OPEN

	_click(menu, "%ContinueButton")

	await SceneRouter.transition_finished
	await get_tree().process_frame
	var info: Label = menu.get_node("%ContinueInfo")
	assert_str(info.text).is_equal("Sauvegarde illisible")
	assert_bool(SceneRouter.is_gameplay).is_false()
	assert_bool(GameState.playing).is_false()
	# The save itself is still there, so the button stays usable.
	assert_bool((menu.get_node("%ContinueButton") as Button).disabled).is_false()


func test_continue_is_ignored_while_a_transition_runs() -> void:
	_write_save(2, 77)
	var menu := _spawn_menu()
	SceneRouter.go_to_main_menu()
	assert_bool(SceneRouter.is_transitioning()).is_true()

	_click(menu, "%ContinueButton")

	await SceneRouter.transition_finished
	await get_tree().process_frame
	assert_array(_swaps).is_equal([SceneRouter.MAIN_MENU_SCENE])
	assert_bool(GameState.playing).is_false()
	assert_str((menu.get_node("%ContinueInfo") as Label).text).contains("Gén. 2")


# --- Screens and the back action -----------------------------------------------

func test_credits_open_and_their_back_button_returns_home() -> void:
	var menu := _spawn_menu()

	_click(menu, "%CreditsButton")

	var credits: Control = menu.get_node("%CreditsScreen")
	assert_str(_current(menu)).is_equal("Credits")
	assert_bool(credits.visible).is_true()
	assert_bool((menu.get_node("%HomeScreen") as Control).visible).is_false()

	(credits.get_node("%BackButton") as Button).pressed.emit()

	assert_str(_current(menu)).is_equal("Home")
	assert_bool(credits.visible).is_false()
	assert_bool((menu.get_node("%HomeScreen") as Control).visible).is_true()


func test_cancel_leaves_the_credits() -> void:
	var menu := _spawn_menu()
	_click(menu, "%CreditsButton")

	_cancel(menu)

	assert_str(_current(menu)).is_equal("Home")


func test_cancel_leaves_the_options_and_saves_them() -> void:
	var menu := _spawn_menu()
	_click(menu, "%OptionsButton")
	assert_bool(FileAccess.file_exists(SETTINGS_PATH)).is_false()

	_cancel(menu)

	assert_str(_current(menu)).is_equal("Home")
	assert_bool(FileAccess.file_exists(SETTINGS_PATH)).is_true()


func test_the_back_button_of_the_options_returns_home() -> void:
	var menu := _spawn_menu()
	_click(menu, "%OptionsButton")

	((menu.get_node("%SettingsScreen") as Control).get_node("%BackButton") as Button).pressed.emit()

	assert_str(_current(menu)).is_equal("Home")


func test_cancel_refuses_a_confirmation() -> void:
	_write_save(2, 140)
	var menu := _spawn_menu()
	_click(menu, "%NewGameButton")
	assert_str(_current(menu)).is_equal("Confirm")

	_cancel(menu)

	assert_str(_current(menu)).is_equal("Home")
	assert_array(_swaps).is_empty()
	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(140)


func test_cancel_on_the_home_screen_does_nothing() -> void:
	var menu := _spawn_menu()

	_cancel(menu)

	assert_str(_current(menu)).is_equal("Home")
	assert_bool((menu.get_node("%HomeScreen") as Control).visible).is_true()
	assert_bool(FileAccess.file_exists(SETTINGS_PATH)).is_false()


func test_a_hidden_menu_ignores_cancel() -> void:
	var menu := _spawn_menu()
	_click(menu, "%CreditsButton")
	menu.visible = false

	_cancel(menu)

	assert_str(_current(menu)).is_equal("Credits")


# --- Quit and version ----------------------------------------------------------

func test_quitting_asks_first_and_can_be_refused() -> void:
	var menu := _spawn_menu()

	_click(menu, "%QuitButton")

	var confirm: Control = menu.get_node("%ConfirmScreen")
	assert_str(_current(menu)).is_equal("Confirm")
	assert_str((confirm.get_node("%TitleLabel") as Label).text).is_equal("Quitter")
	assert_str((confirm.get_node("%MessageLabel") as Label).text).is_equal(
		"Voulez-vous quitter Salazie ?")
	assert_str(_confirm_button(menu, "%ConfirmButton").text).is_equal("Quitter")

	_confirm_button(menu, "%CancelButton").pressed.emit()

	assert_str(_current(menu)).is_equal("Home")


func test_the_quit_button_is_offered_on_desktop() -> void:
	var menu := _spawn_menu()

	# Only a Web build hides it: a browser tab cannot be quit.
	assert_bool((menu.get_node("%QuitButton") as Button).visible).is_equal(
		not OS.has_feature("web"))


func test_the_version_label_shows_the_project_version() -> void:
	var menu := _spawn_menu()

	var expected := "v%s" % String(
		ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var label: Label = menu.get_node("%VersionLabel")
	assert_str(label.text).is_equal(expected)
	assert_str(label.text).is_not_equal("v")
