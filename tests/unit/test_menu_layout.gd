extends GdUnitTestSuite

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const PAUSE_MENU_SCENE := "res://scenes/preloads/pause_menu.tscn"
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1536, 648),
	Vector2i(1152, 864),
	Vector2i(2560, 1080),
]

var _original_save_path := ""


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = "user://test_menu_layout_save.json"
	SaveGame.delete_save()
	GameState.playing = true


func after_test() -> void:
	GameState.playing = false
	SceneRouter.is_gameplay = false
	get_tree().paused = false
	SaveGame.delete_save()
	SaveGame.save_path = _original_save_path


func test_main_menu_screens_fit_and_focus_at_supported_sizes() -> void:
	for size: Vector2i in SIZES:
		var viewport := SubViewport.new()
		viewport.size = size
		add_child(viewport)

		var menu: Control = load(MAIN_MENU_SCENE).instantiate()
		viewport.add_child(menu)
		await get_tree().process_frame
		await get_tree().process_frame

		var stack: Control = menu.get_node("%MenuStack")
		_assert_screen(stack, viewport, size, "Home")

		for screen_name: String in ["Settings", "Credits"]:
			stack.push(screen_name)
			await get_tree().process_frame
			await get_tree().process_frame
			_assert_screen(stack, viewport, size, screen_name)
			stack.pop()
			await get_tree().process_frame

		menu.call("_open_confirmation", "test", "Titre", "Message de test", "Oui", "Non")
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_screen(stack, viewport, size, "Confirm")
		menu.call("_on_cancelled")
		await get_tree().process_frame

		viewport.queue_free()
		await get_tree().process_frame


func test_pause_menu_screens_fit_and_focus_at_supported_sizes() -> void:
	for size: Vector2i in SIZES:
		var viewport := SubViewport.new()
		viewport.size = size
		add_child(viewport)

		var pause = load(PAUSE_MENU_SCENE).instantiate()
		viewport.add_child(pause)
		await get_tree().process_frame
		await get_tree().process_frame

		SceneRouter.is_gameplay = true
		pause.call("open")
		await get_tree().process_frame
		await get_tree().process_frame

		var stack: Control = pause.get_node("%MenuStack")
		_assert_screen(stack, viewport, size, "Pause")

		for screen_name: String in ["Settings", "Controls"]:
			stack.push(screen_name)
			await get_tree().process_frame
			await get_tree().process_frame
			_assert_screen(stack, viewport, size, screen_name)
			stack.pop()
			await get_tree().process_frame

		pause.call("_open_confirmation", "test", "Titre", "Message de test", "Oui", "Non")
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_screen(stack, viewport, size, "Confirm")
		pause.call("_on_cancelled")
		pause.call("close")
		await get_tree().process_frame

		viewport.queue_free()
		await get_tree().process_frame


func _assert_screen(stack: Control, viewport: SubViewport, size: Vector2i, screen_name: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	var failures: Array[String] = []
	for node: Node in stack.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		if _is_inside_scroll(control):
			continue
		if not screen.encloses(control.get_global_rect()):
			failures.append("%s at %s is outside %s" % [
				stack.get_path_to(control), control.get_global_rect(), screen])
	assert_array(failures).override_failure_message(
		"Off-screen controls in %s at %s" % [screen_name, size]).is_empty()

	var focus := viewport.gui_get_focus_owner()
	assert_object(focus).override_failure_message(
		"No focused control in %s at %s, gamepad navigation is stuck" % [screen_name, size]).is_not_null()


func _is_inside_scroll(control: Control) -> bool:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false
