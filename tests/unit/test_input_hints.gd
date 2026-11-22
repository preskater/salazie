extends GdUnitTestSuite
## Input map coverage (#21) and layout-aware labels (#22).

const CONTROLS_SCENE := preload("res://scenes/ui/menus/screens/controls_screen.tscn")
const CLIMB_SCENE := preload("res://scenes/maroon/climb_point.tscn")
const NPC_SCENE := preload("res://scenes/farm/npc.tscn")

## Actions a player needs during play. Seed shortcuts 1-4 are keyboard-only by
## design: a gamepad walks through the seeds with `seed_previous` / `seed_next`.
const BOTH_DEVICES: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"interact", &"run",
	&"toggle_inventory", &"toggle_prices", &"toggle_tasks", &"pause",
]


func before_test() -> void:
	InputHints.using_gamepad = false


func after_test() -> void:
	InputHints.using_gamepad = false


func _key(physical: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.pressed = true
	return event


func _button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


# --- Input map ---------------------------------------------------------------

func test_every_gameplay_action_works_on_keyboard_and_gamepad() -> void:
	for action: StringName in BOTH_DEVICES:
		assert_bool(InputMap.has_action(action)).override_failure_message(
			"Missing action %s" % action).is_true()
		var has_key := false
		var has_pad := false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				has_key = true
			elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
				has_pad = true
		assert_bool(has_key).override_failure_message("%s has no key" % action).is_true()
		assert_bool(has_pad).override_failure_message("%s has no gamepad input" % action).is_true()


func test_gamepad_can_walk_through_the_seeds() -> void:
	for action: StringName in [&"seed_previous", &"seed_next"]:
		assert_bool(InputMap.has_action(action)).is_true()
		assert_str(InputHints.gamepad_label(action)).is_not_equal(InputHints.UNBOUND)


func test_project_keys_are_physical_so_azerty_keeps_the_same_positions() -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				assert_int((event as InputEventKey).physical_keycode).override_failure_message(
					"%s is bound to a layout-dependent keycode" % action).is_not_equal(KEY_NONE)


func test_movement_reads_the_left_stick_and_the_d_pad() -> void:
	var axes := {&"move_left": [JOY_AXIS_LEFT_X, -1.0], &"move_right": [JOY_AXIS_LEFT_X, 1.0],
		&"move_up": [JOY_AXIS_LEFT_Y, -1.0], &"move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	for action: StringName in axes:
		assert_bool(InputMap.action_has_event(action, _axis(axes[action][0], axes[action][1]))) \
			.override_failure_message("%s ignores the stick" % action).is_true()
	assert_bool(InputMap.action_has_event(&"move_up", _button(JOY_BUTTON_DPAD_UP))).is_true()
	assert_bool(InputMap.action_has_event(&"move_right", _button(JOY_BUTTON_DPAD_RIGHT))).is_true()
	assert_bool(InputMap.action_has_event(&"interact", _button(JOY_BUTTON_A))).is_true()


# --- Labels ------------------------------------------------------------------

func test_labels_name_the_key_and_the_button() -> void:
	assert_str(InputHints.keyboard_label(&"interact")).is_equal("E")
	assert_str(InputHints.gamepad_label(&"interact")).is_equal("A")
	assert_str(InputHints.keyboard_label(&"pause")).is_equal("Échap")
	assert_str(InputHints.gamepad_label(&"pause")).is_equal("Start")
	assert_str(InputHints.keyboard_label(&"run")).is_equal("Maj")
	assert_str(InputHints.gamepad_label(&"toggle_tasks")).is_equal("Select")
	assert_str(InputHints.gamepad_label(&"move")).is_equal("Stick gauche")
	assert_str(InputHints.keyboard_label(&"select_seed")).is_equal("1 à 4")
	assert_str(InputHints.gamepad_label(&"select_seed")).is_equal("LB / RB")


func test_movement_label_is_built_from_the_four_keys() -> void:
	# The headless runner has no layout, so physical keys keep their US names.
	assert_str(InputHints.keyboard_label(&"move")).is_equal("WASD")

	var original := InputMap.action_get_events(&"move_up")
	InputMap.action_erase_events(&"move_up")
	InputMap.action_add_event(&"move_up", _key(KEY_UP))
	var rebound := InputHints.keyboard_label(&"move")
	InputMap.action_erase_events(&"move_up")
	for event: InputEvent in original:
		InputMap.action_add_event(&"move_up", event)

	assert_array(Array(rebound.split(" "))).is_equal(["↑", "A", "S", "D"])


func test_key_label_falls_back_gracefully() -> void:
	var by_keycode := InputEventKey.new()
	by_keycode.keycode = KEY_ESCAPE
	assert_str(InputHints.key_label(by_keycode)).is_equal("Échap")
	assert_str(InputHints.key_label(_key(KEY_F5))).is_equal("F5")
	assert_str(InputHints.key_label(InputEventKey.new())).is_equal(InputHints.UNBOUND)


func test_unknown_or_unbound_actions_read_as_unbound() -> void:
	assert_str(InputHints.keyboard_label(&"does_not_exist")).is_equal(InputHints.UNBOUND)
	assert_str(InputHints.gamepad_label(&"does_not_exist")).is_equal(InputHints.UNBOUND)
	assert_str(InputHints.gamepad_label(&"select_seed_1")).is_equal(InputHints.UNBOUND)


func test_unnamed_buttons_and_axes_still_get_a_label() -> void:
	InputMap.add_action(&"test_odd_pad")
	InputMap.action_add_event(&"test_odd_pad", _button(JOY_BUTTON_PADDLE1))
	var button_label := InputHints.gamepad_label(&"test_odd_pad")
	InputMap.action_erase_events(&"test_odd_pad")
	InputMap.action_add_event(&"test_odd_pad", _axis(JOY_AXIS_SDL_MAX, 1.0))
	var axis_label := InputHints.gamepad_label(&"test_odd_pad")
	InputMap.erase_action(&"test_odd_pad")

	assert_str(button_label).starts_with("Bouton")
	assert_str(axis_label).starts_with("Axe")


# --- Device tracking -------------------------------------------------------

func test_the_last_device_used_picks_the_label() -> void:
	var changes: Array[bool] = []
	var listener := func(gamepad: bool) -> void: changes.append(gamepad)
	InputHints.device_changed.connect(listener)

	InputHints.note_event(_button(JOY_BUTTON_A))
	assert_str(InputHints.label(&"interact")).is_equal("A")
	assert_str(InputHints.prompt(&"interact", "Parler")).is_equal("A — Parler")
	InputHints.note_event(_button(JOY_BUTTON_B))
	InputHints.note_event(_key(KEY_E))
	assert_str(InputHints.label(&"interact")).is_equal("E")

	InputHints.device_changed.disconnect(listener)
	assert_array(changes).is_equal([true, false])


func test_a_resting_stick_does_not_switch_to_the_gamepad() -> void:
	InputHints.note_event(_axis(JOY_AXIS_LEFT_X, 0.12))
	assert_bool(InputHints.using_gamepad).is_false()

	InputHints.note_event(_axis(JOY_AXIS_LEFT_X, -0.9))
	assert_bool(InputHints.using_gamepad).is_true()

	InputHints.note_event(InputEventMouseMotion.new())
	assert_bool(InputHints.using_gamepad).is_true()
	InputHints.note_event(InputEventMouseButton.new())
	assert_bool(InputHints.using_gamepad).is_false()


func test_label_borrows_the_other_device_when_one_has_no_binding() -> void:
	InputHints.using_gamepad = true
	assert_str(InputHints.label(&"select_seed_1")).is_equal("1")

	InputHints.using_gamepad = false
	assert_str(InputHints.label(&"seed_next")).is_equal("RB")


# --- Text with tokens ------------------------------------------------------

func test_format_replaces_action_tokens_only() -> void:
	assert_str(InputHints.format("Plantez ({interact}).")).is_equal("Plantez (E).")
	assert_str(InputHints.format("{move} · {run} courir")).is_equal("WASD · Maj courir")
	assert_str(InputHints.format("{select_seed} graines")).is_equal("1 à 4 graines")
	assert_str(InputHints.format("{inconnu} reste, {interact} change")) \
		.is_equal("{inconnu} reste, E change")
	assert_str(InputHints.format("accolade { ouverte")).is_equal("accolade { ouverte")
	assert_str(InputHints.format("rien à changer")).is_equal("rien à changer")

	InputHints.using_gamepad = true
	assert_str(InputHints.format("Plantez ({interact}).")).is_equal("Plantez (A).")


func test_task_hints_never_spell_a_key() -> void:
	for map_id: int in Campaign.TASKS:
		for definition: Dictionary in Campaign.TASKS[map_id]:
			var hint := String(definition["hint"])
			assert_bool(hint.contains("(E)") or hint.contains("(1-4)") or hint.contains("WASD")) \
				.override_failure_message("Hardcoded key in: %s" % hint).is_false()
			assert_bool(InputHints.format(hint).contains("{")).override_failure_message(
				"Unresolved token in: %s" % hint).is_false()


# --- Consumers -------------------------------------------------------------

func test_controls_screen_lists_every_action_for_both_devices() -> void:
	var screen: Control = auto_free(CONTROLS_SCENE.instantiate())
	add_child(screen)

	var rows: Array = screen.call("get_row_texts")

	var by_label := {}
	for row: Array in rows:
		by_label[row[0]] = row
		assert_str(String(row[1])).is_not_empty()
		assert_str(String(row[2])).is_not_empty()
	assert_array(by_label["Courir"]).is_equal(["Courir", "Maj", "X"])
	assert_array(by_label["Aller en haut"]).is_equal(["Aller en haut", "W", "Croix ↑"])
	assert_array(by_label["Choisir une graine"]).is_equal(["Choisir une graine", "1 à 4", "LB / RB"])
	assert_array(by_label["Retour / fermer"]).is_equal(["Retour / fermer", "Échap", "B"])
	# Every action the player may rebind has its row.
	var listed := (screen.get("ROWS") as Array).map(
		func(entry: Dictionary) -> StringName: return StringName(String(entry["action"])))
	for action: StringName in Settings.REBINDABLE:
		assert_bool(listed.has(action)).override_failure_message(
			"%s has no row" % action).is_true()


func test_controls_screen_follows_a_changed_binding() -> void:
	var screen: Control = auto_free(CONTROLS_SCENE.instantiate())
	add_child(screen)
	var original := InputMap.action_get_events(&"interact")
	InputMap.action_erase_events(&"interact")
	InputMap.action_add_event(&"interact", _key(KEY_F))

	screen.call("on_shown")
	var rows: Array = screen.call("get_row_texts")

	InputMap.action_erase_events(&"interact")
	for event: InputEvent in original:
		InputMap.action_add_event(&"interact", event)
	var interact_row: Array = rows.filter(func(row: Array) -> bool: return row[0] == "Interagir")[0]
	assert_str(String(interact_row[1])).is_equal("F")
	assert_str(String(interact_row[2])).is_equal(InputHints.UNBOUND)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(screen.get_node("%BackButton"))


func test_controls_screen_back_button_asks_to_go_back() -> void:
	var screen: Control = auto_free(CONTROLS_SCENE.instantiate())
	add_child(screen)
	var asked: Array[bool] = []
	screen.connect("back_requested", func() -> void: asked.append(true))

	(screen.get_node("%BackButton") as Button).pressed.emit()

	assert_int(asked.size()).is_equal(1)


func test_scene_prompts_resolve_their_tokens() -> void:
	var climb: Area2D = auto_free(CLIMB_SCENE.instantiate())
	add_child(climb)
	assert_str(String(climb.call("get_interaction_prompt"))).is_equal("E — Grimper")

	var npc: FarmNPC = auto_free(NPC_SCENE.instantiate())
	npc.speaker = "Marchande"
	add_child(npc)
	assert_str(npc.get_interaction_prompt()).is_equal("E — Parler à Marchande")
	npc.talk_prompt = "{interact} — Parler au pêcheur"
	InputHints.using_gamepad = true
	assert_str(npc.get_interaction_prompt()).is_equal("A — Parler au pêcheur")


func test_menus_can_be_confirmed_and_cancelled_with_a_gamepad() -> void:
	# Godot's built-in ui_accept and ui_cancel ship without any gamepad button.
	assert_bool(InputMap.action_has_event(&"ui_accept", _button(JOY_BUTTON_A))).is_true()
	assert_bool(InputMap.action_has_event(&"ui_cancel", _button(JOY_BUTTON_B))).is_true()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	assert_bool(InputMap.action_has_event(&"ui_accept", enter)).is_true()
	assert_bool(InputMap.action_has_event(&"ui_cancel", escape)).is_true()
