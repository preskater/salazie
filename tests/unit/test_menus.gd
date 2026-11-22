extends GdUnitTestSuite

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const PAUSE_MENU_SCENE := "res://scenes/preloads/pause_menu.tscn"

var _original_save_path := ""
var _original_settings_path := ""


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = "user://test_menus_save.json"
	SaveGame.delete_save()
	_original_settings_path = Settings.config_path
	Settings.config_path = "user://test_menus_settings.cfg"
	_remove_file(Settings.config_path)
	GameState.playing = true
	GameState.reset()


func after_test() -> void:
	SaveGame.delete_save()
	SaveGame.save_path = _original_save_path
	_remove_file(Settings.config_path)
	Settings.config_path = _original_settings_path
	GameState.playing = false
	SceneRouter.is_gameplay = false
	if get_tree() != null:
		get_tree().paused = false


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _spawn_main_menu() -> Control:
	var menu: Control = load(MAIN_MENU_SCENE).instantiate()
	add_child(menu)
	auto_free(menu)
	return menu


func test_main_menu_builds_expected_buttons() -> void:
	var menu := _spawn_main_menu()
	await get_tree().process_frame

	for node_name: String in [
		"%NewGameButton", "%ContinueButton", "%OptionsButton",
		"%CreditsButton", "%QuitButton", "%VersionLabel",
	]:
		assert_object(menu.get_node_or_null(node_name)).override_failure_message(
			"Missing main menu node %s" % node_name).is_not_null()


func test_main_menu_starts_on_home_screen() -> void:
	var menu := _spawn_main_menu()
	await get_tree().process_frame

	var stack: Node = menu.get_node("%MenuStack")
	assert_str(String(stack.call("current_name"))).is_equal("Home")


func test_continue_is_disabled_without_a_save() -> void:
	var menu := _spawn_main_menu()
	await get_tree().process_frame

	var continue_button: Button = menu.get_node("%ContinueButton")
	var info: Label = menu.get_node("%ContinueInfo")
	assert_bool(continue_button.disabled).is_true()
	assert_str(info.text).is_equal("Aucune sauvegarde")


func test_options_pushes_the_settings_screen() -> void:
	var menu := _spawn_main_menu()
	await get_tree().process_frame

	(menu.get_node("%OptionsButton") as Button).pressed.emit()
	await get_tree().process_frame

	var stack: Node = menu.get_node("%MenuStack")
	assert_str(String(stack.call("current_name"))).is_equal("Settings")


func test_ui_cancel_returns_from_settings_to_home() -> void:
	var menu := _spawn_main_menu()
	await get_tree().process_frame

	(menu.get_node("%OptionsButton") as Button).pressed.emit()
	await get_tree().process_frame
	var stack: Node = menu.get_node("%MenuStack")
	assert_str(String(stack.call("current_name"))).is_equal("Settings")

	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	menu.call("_unhandled_input", event)
	assert_str(String(stack.call("current_name"))).is_equal("Home")


func test_pause_menu_pauses_and_resumes_the_tree() -> void:
	var pause = load(PAUSE_MENU_SCENE).instantiate()
	add_child(pause)
	auto_free(pause)
	await get_tree().process_frame

	GameState.playing = true
	SceneRouter.is_gameplay = true
	pause.call("open")

	assert_bool(get_tree().paused).is_true()
	assert_bool(pause.visible).is_true()

	pause.call("close")

	assert_bool(get_tree().paused).is_false()
	assert_bool(pause.visible).is_false()


func test_continue_is_enabled_with_a_valid_save() -> void:
	GameState.money = 55
	GameState.day = 2
	assert_bool(SaveGame.save_game()).is_true()

	var menu := _spawn_main_menu()
	await get_tree().process_frame

	var continue_button: Button = menu.get_node("%ContinueButton")
	var info: Label = menu.get_node("%ContinueInfo")
	assert_bool(continue_button.disabled).is_false()
	assert_str(info.text).is_equal("Gén. 1 · Le marron · Jour 2 · 55 G")


func test_hud_ignores_inventory_when_paused_by_another_system() -> void:
	var hud: CanvasLayer = load("res://scenes/farm/farm_hud.tscn").instantiate()
	add_child(hud)
	auto_free(hud)
	await get_tree().process_frame

	get_tree().paused = true
	var event := InputEventAction.new()
	event.action = "toggle_inventory"
	event.pressed = true
	hud.call("_unhandled_input", event)

	assert_bool((hud.get_node("%InventoryOverlay") as Control).visible).is_false()
	get_tree().paused = false


func test_pause_action_exists_and_is_bound_to_keyboard() -> void:
	assert_bool(InputMap.has_action("pause")).is_true()
	var events := InputMap.action_get_events("pause")
	var has_key := false
	for event: InputEvent in events:
		if event is InputEventKey:
			has_key = true
			break
	assert_bool(has_key).is_true()


func test_task_list_action_exists() -> void:
	assert_bool(InputMap.has_action("toggle_tasks")).is_true()
	assert_int(InputMap.action_get_events("toggle_tasks").size()).is_greater(0)


func test_game_scene_path_exists() -> void:
	assert_bool(ResourceLoader.exists(SceneRouter.GAME_SCENE)).is_true()
	assert_bool(ResourceLoader.exists(SceneRouter.MAIN_MENU_SCENE)).is_true()


func test_a_finished_story_offers_its_epilogue() -> void:
	# Regression (#25).
	Campaign.reset()
	Campaign.current_map = 3
	Campaign.finished = true
	assert_bool(SaveGame.save_game()).is_true()
	# At the menu nothing autosaves; the reset must not rewrite the file.
	GameState.playing = false
	Campaign.reset()
	var menu := _spawn_main_menu()

	assert_bool((menu.get_node("%ContinueButton") as Button).disabled).is_false()
	assert_str((menu.get_node("%ContinueButton") as Button).text).contains("épilogue")
	assert_str((menu.get_node("%ContinueInfo") as Label).text).contains("terminée")


func test_continue_reports_a_save_that_cannot_be_read() -> void:
	# Regression (#24): the button did nothing and said nothing.
	assert_bool(SaveGame.save_game()).is_true()
	var menu := _spawn_main_menu()
	var file := FileAccess.open(SaveGame.save_path, FileAccess.WRITE)
	file.store_string("{")
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.save_path + ".bak"))

	(menu.get_node("%ContinueButton") as Button).pressed.emit()

	assert_bool((menu.get_node("%ContinueButton") as Button).disabled).is_true()
	assert_str((menu.get_node("%ContinueInfo") as Label).text).is_equal("Aucune sauvegarde")


func test_pause_menu_refuses_to_open_outside_gameplay_or_when_paused() -> void:
	var pause: CanvasLayer = auto_free(load(PAUSE_MENU_SCENE).instantiate())
	add_child(pause)

	SceneRouter.is_gameplay = false
	pause.call("open")
	assert_bool(pause.visible).is_false()

	SceneRouter.is_gameplay = true
	get_tree().paused = true
	pause.call("open")
	assert_bool(pause.visible).is_false()
	get_tree().paused = false
