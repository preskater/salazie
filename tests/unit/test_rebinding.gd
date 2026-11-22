extends GdUnitTestSuite
## Key and button rebinding (#23).

const CONTROLS_SCENE := preload("res://scenes/ui/menus/screens/controls_screen.tscn")
const TEST_CONFIG := "user://test_rebinding.cfg"

var _original_config := ""


func before_test() -> void:
	_original_config = Settings.config_path
	Settings.config_path = TEST_CONFIG
	_remove_config()
	Settings.reset_bindings()
	InputHints.using_gamepad = false


func after_test() -> void:
	Settings.reset_bindings()
	_remove_config()
	Settings.config_path = _original_config
	InputHints.using_gamepad = false


func _remove_config() -> void:
	if FileAccess.file_exists(TEST_CONFIG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG))


func _key(physical: Key, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.pressed = pressed
	return event


func _button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event


func _spawn_screen() -> Control:
	var screen: Control = auto_free(CONTROLS_SCENE.instantiate())
	add_child(screen)
	return screen


func _row(screen: Control, label: String) -> Array:
	var rows: Array = screen.call("get_row_texts")
	return rows.filter(func(row: Array) -> bool: return row[0] == label)[0]


# --- Settings ----------------------------------------------------------------

func test_a_new_key_replaces_the_main_one_and_keeps_the_rest() -> void:
	assert_bool(Settings.rebind_key(&"interact", KEY_F)).is_true()

	assert_int(Settings.primary_key(&"interact")).is_equal(KEY_F)
	assert_bool(InputMap.action_has_event(&"interact", _key(KEY_F))).is_true()
	assert_bool(InputMap.action_has_event(&"interact", _key(KEY_E))).is_false()
	# The gamepad button of the same action is untouched.
	assert_int(Settings.primary_button(&"interact")).is_equal(JOY_BUTTON_A)
	assert_str(InputHints.keyboard_label(&"interact")).is_equal("F")
	assert_str(InputHints.prompt(&"interact", "Parler")).is_equal("F — Parler")


func test_arrow_keys_and_the_stick_survive_a_movement_rebind() -> void:
	Settings.rebind_key(&"move_up", KEY_I)

	assert_bool(InputMap.action_has_event(&"move_up", _key(KEY_I))).is_true()
	assert_bool(InputMap.action_has_event(&"move_up", _key(KEY_UP))).is_true()
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = -1.0
	assert_bool(InputMap.action_has_event(&"move_up", stick)).is_true()


func test_taking_a_key_from_another_action_swaps_them() -> void:
	var run_key := Settings.primary_key(&"run")
	var interact_key := Settings.primary_key(&"interact")

	assert_bool(Settings.rebind_key(&"interact", run_key)).is_true()

	assert_int(Settings.primary_key(&"interact")).is_equal(run_key)
	assert_int(Settings.primary_key(&"run")).is_equal(interact_key)
	for action: StringName in Settings.REBINDABLE:
		assert_int(Settings.primary_key(action)).override_failure_message(
			"%s lost its key" % action).is_not_equal(KEY_NONE)


func test_keys_of_the_seed_shortcuts_cannot_be_taken() -> void:
	var before := Settings.primary_key(&"interact")

	assert_bool(Settings.rebind_key(&"interact", KEY_1)).is_false()
	assert_bool(Settings.rebind_key(&"interact", KEY_NONE)).is_false()
	assert_bool(Settings.rebind_key(&"select_seed_1", KEY_F)).is_false()
	assert_bool(Settings.rebind_key(&"ui_accept", KEY_F)).is_false()

	assert_int(Settings.primary_key(&"interact")).is_equal(before)
	assert_dict(Settings.key_bindings).is_empty()


func test_a_new_button_replaces_the_main_one_and_swaps_on_conflict() -> void:
	assert_bool(Settings.rebind_button(&"interact", JOY_BUTTON_B)).is_true()
	assert_int(Settings.primary_button(&"interact")).is_equal(JOY_BUTTON_B)
	assert_str(InputHints.gamepad_label(&"interact")).is_equal("B")

	var inventory_button := Settings.primary_button(&"toggle_inventory")
	assert_bool(Settings.rebind_button(&"run", inventory_button as JoyButton)).is_true()
	assert_int(Settings.primary_button(&"run")).is_equal(inventory_button)
	assert_int(Settings.primary_button(&"toggle_inventory")).is_equal(JOY_BUTTON_X)

	assert_bool(Settings.rebind_button(&"interact", JOY_BUTTON_INVALID)).is_false()
	assert_bool(Settings.rebind_button(&"ui_accept", JOY_BUTTON_Y)).is_false()
	# The right trigger still runs: only the button moved.
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	assert_bool(InputMap.action_has_event(&"run", trigger)).is_true()


func test_bindings_are_saved_and_restored() -> void:
	Settings.rebind_key(&"interact", KEY_F)
	Settings.rebind_button(&"run", JOY_BUTTON_B)

	Settings.key_bindings = {}
	Settings.button_bindings = {}
	Settings.apply_bindings()
	assert_int(Settings.primary_key(&"interact")).is_equal(KEY_E)
	Settings.load_settings()
	Settings.apply_bindings()

	assert_int(Settings.primary_key(&"interact")).is_equal(KEY_F)
	assert_int(Settings.primary_button(&"run")).is_equal(JOY_BUTTON_B)


func test_a_damaged_file_cannot_bind_nonsense() -> void:
	var config := ConfigFile.new()
	config.set_value(Settings.SECTION_INPUT, "interact/key", "F")
	config.set_value(Settings.SECTION_INPUT, "run/key", -4)
	config.set_value(Settings.SECTION_INPUT, "pause/key", KEY_2)
	config.set_value(Settings.SECTION_INPUT, "interact/button", 999)
	config.set_value(Settings.SECTION_INPUT, "ui_accept/key", KEY_F)
	config.save(TEST_CONFIG)

	Settings.load_settings()
	Settings.apply_bindings()

	assert_dict(Settings.key_bindings).is_empty()
	assert_dict(Settings.button_bindings).is_empty()
	assert_int(Settings.primary_key(&"interact")).is_equal(KEY_E)


func test_reset_restores_every_default() -> void:
	Settings.rebind_key(&"interact", KEY_F)
	Settings.rebind_button(&"interact", JOY_BUTTON_Y)
	var changes: Array[bool] = []
	var listener := func() -> void: changes.append(true)
	Settings.bindings_changed.connect(listener)

	Settings.reset_bindings()

	Settings.bindings_changed.disconnect(listener)
	assert_int(changes.size()).is_equal(1)
	assert_int(Settings.primary_key(&"interact")).is_equal(KEY_E)
	assert_int(Settings.primary_button(&"interact")).is_equal(JOY_BUTTON_A)
	assert_int(Settings.primary_button(&"toggle_inventory")).is_equal(JOY_BUTTON_Y)
	Settings.load_settings()
	assert_dict(Settings.key_bindings).is_empty()


func test_resetting_all_settings_resets_the_bindings_too() -> void:
	Settings.rebind_key(&"run", KEY_C)

	Settings.reset_defaults()

	assert_int(Settings.primary_key(&"run")).is_equal(KEY_SHIFT)


func test_unknown_actions_have_no_binding() -> void:
	assert_int(Settings.primary_key(&"select_seed_1")).is_equal(KEY_1)
	assert_int(Settings.primary_button(&"select_seed_1")).is_equal(-1)
	InputMap.add_action(&"test_empty_action")
	assert_int(Settings.primary_key(&"test_empty_action")).is_equal(KEY_NONE)
	InputMap.erase_action(&"test_empty_action")


# --- Controls screen ---------------------------------------------------------

func test_pressing_a_key_cell_waits_for_the_next_key() -> void:
	var screen := _spawn_screen()
	var cell: Button = screen.get_node("%Rows/interact_key")

	cell.pressed.emit()

	assert_bool(bool(screen.call("is_listening"))).is_true()
	assert_str(String(_row(screen, "Interagir")[1])).is_equal("…")

	screen._input(_key(KEY_F))

	assert_bool(bool(screen.call("is_listening"))).is_false()
	assert_array(_row(screen, "Interagir")).is_equal(["Interagir", "F", "A"])
	assert_int(Settings.primary_key(&"interact")).is_equal(KEY_F)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(
		screen.get_node("%Rows/interact_key"))


func test_escape_cancels_and_is_never_given_away() -> void:
	var screen := _spawn_screen()
	screen.call("listen", &"interact", 0)

	screen._input(_key(KEY_ESCAPE))

	assert_bool(bool(screen.call("is_listening"))).is_false()
	assert_int(Settings.primary_key(&"interact")).is_equal(KEY_E)
	assert_int(Settings.primary_key(&"pause")).is_equal(KEY_ESCAPE)


func test_a_gamepad_cell_only_takes_a_gamepad_button() -> void:
	var screen := _spawn_screen()
	(screen.get_node("%Rows/run_pad") as Button).pressed.emit()

	# A key press while waiting for a button cancels without binding anything.
	screen._input(_key(KEY_F))
	assert_int(Settings.primary_key(&"run")).is_equal(KEY_SHIFT)
	assert_bool(bool(screen.call("is_listening"))).is_false()

	(screen.get_node("%Rows/run_pad") as Button).pressed.emit()
	screen._input(_button(JOY_BUTTON_B))
	assert_int(Settings.primary_button(&"run")).is_equal(JOY_BUTTON_B)
	assert_array(_row(screen, "Courir")).is_equal(["Courir", "Maj", "B"])

	# And a button press while waiting for a key binds nothing either.
	(screen.get_node("%Rows/run_key") as Button).pressed.emit()
	screen._input(_button(JOY_BUTTON_Y))
	assert_int(Settings.primary_key(&"run")).is_equal(KEY_SHIFT)
	assert_int(Settings.primary_button(&"toggle_inventory")).is_equal(JOY_BUTTON_Y)


func test_input_is_ignored_when_nothing_is_waiting() -> void:
	var screen := _spawn_screen()

	screen._input(_key(KEY_F))
	screen._input(_key(KEY_G, false))

	assert_int(Settings.primary_key(&"interact")).is_equal(KEY_E)
	screen.call("listen", &"interact", 0)
	screen._input(_key(KEY_G, false))
	assert_bool(bool(screen.call("is_listening"))).is_true()
	screen.call("listen", &"ui_cancel", 0)
	assert_bool(bool(screen.call("is_listening"))).is_true()


func test_fixed_actions_are_plain_text() -> void:
	var screen := _spawn_screen()

	assert_object(screen.get_node_or_null("%Rows/select_seed_key")).is_null()
	assert_object(screen.get_node_or_null("%Rows/ui_cancel_key")).is_null()
	for action: StringName in Settings.REBINDABLE:
		assert_object(screen.get_node_or_null("%%Rows/%s_key" % action)) \
			.override_failure_message("%s has no key cell" % action).is_not_null()
		assert_object(screen.get_node_or_null("%%Rows/%s_pad" % action)) \
			.override_failure_message("%s has no gamepad cell" % action).is_not_null()


func test_the_reset_button_restores_the_defaults_on_screen() -> void:
	var screen := _spawn_screen()
	Settings.rebind_key(&"interact", KEY_F)
	assert_array(_row(screen, "Interagir")).is_equal(["Interagir", "F", "A"])
	screen.call("listen", &"run", 0)

	(screen.get_node("%ResetButton") as Button).pressed.emit()

	assert_bool(bool(screen.call("is_listening"))).is_false()
	assert_array(_row(screen, "Interagir")).is_equal(["Interagir", "E", "A"])


func test_leaving_the_screen_stops_waiting() -> void:
	var screen := _spawn_screen()
	screen.call("listen", &"interact", 0)

	(screen.get_node("%BackButton") as Button).pressed.emit()
	assert_bool(bool(screen.call("is_listening"))).is_false()

	screen.call("listen", &"interact", 0)
	screen.call("on_shown")
	assert_bool(bool(screen.call("is_listening"))).is_false()
