extends GdUnitTestSuite
## Edge cases of the core systems: timed scene transitions, damaged save
## files, the night tint and device tracking from real input events.

const TRANSITION_SCENE := preload("res://scenes/preloads/scene_transition.tscn")
const CYCLE_SCRIPT := preload("res://scripts/world/day_night_cycle.gd")
const SAVE_PATH := "user://test_systems_edges.json"
const KNOWN_SCENE := "res://scenes/ui/menus/main_menu.tscn"

const DAY_SECONDS := 10.0
const NIGHT_SECONDS := 10.0

var _original_save_path := ""
var _swaps: Array[String] = []


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = SAVE_PATH
	SaveGame.delete_save()
	GameState.playing = false
	Campaign.reset()
	GameState.reset()
	_swaps = []
	InputHints.using_gamepad = false


func after_test() -> void:
	GameState.playing = false
	SaveGame.save_path = SAVE_PATH
	SaveGame.delete_save()
	SaveGame.save_path = _original_save_path
	Campaign.reset()
	GameState.reset()
	InputHints.using_gamepad = false


# --- Scene transition ----------------------------------------------------------

func _spawn_transition(fade := 0.0, hold := 0.0) -> CanvasLayer:
	var transition: CanvasLayer = TRANSITION_SCENE.instantiate()
	transition.set("fade_out_duration", fade)
	transition.set("hold_duration", hold)
	transition.set("fade_in_duration", fade)
	transition.set("scene_changer", func(path: String) -> Error:
		_swaps.append(path)
		return OK)
	add_child(auto_free(transition))
	return transition


func _alpha(transition: CanvasLayer) -> float:
	return (transition.get_node("Backdrop") as ColorRect).color.a


func test_a_timed_transition_swaps_the_scene_under_a_fully_covered_screen() -> void:
	var transition := _spawn_transition(0.05, 0.05)
	var alpha_at_swap: Array[float] = []
	var announced: Array[String] = []
	transition.connect("scene_changed", func(path: String) -> void:
		announced.append(path)
		alpha_at_swap.append(_alpha(transition)))

	var swapped: bool = await transition.call("change_scene", KNOWN_SCENE, "Chapitre", "Sous-titre")

	assert_bool(swapped).is_true()
	assert_array(_swaps).is_equal([KNOWN_SCENE])
	assert_array(announced).is_equal([KNOWN_SCENE])
	assert_float(alpha_at_swap[0]).is_equal_approx(1.0, 0.001)
	assert_str((transition.get_node("Text/Layout/Title") as Label).text).is_equal("Chapitre")
	assert_float(_alpha(transition)).is_equal_approx(0.0, 0.001)
	assert_bool(bool(transition.get("is_transitioning"))).is_false()


func test_the_fade_is_progressive_when_it_has_a_duration() -> void:
	var transition := _spawn_transition(0.2, 0.0)

	transition.call("cover", "Titre", "")
	assert_bool(bool(transition.get("is_transitioning"))).is_true()
	await get_tree().process_frame
	await get_tree().process_frame

	# Not instantaneous: after two frames the screen is not fully covered yet.
	assert_float(_alpha(transition)).is_less(1.0)
	await get_tree().create_timer(0.4).timeout
	assert_float(_alpha(transition)).is_equal_approx(1.0, 0.001)


func test_a_second_scene_change_is_refused_while_one_runs() -> void:
	var transition := _spawn_transition(0.0, 0.05)
	transition.call("change_scene", KNOWN_SCENE)
	assert_bool(bool(transition.get("is_transitioning"))).is_true()

	var second: bool = await transition.call("change_scene", "res://scenes/maps/farm.tscn")

	assert_bool(second).is_false()
	await transition.transition_finished
	assert_array(_swaps).is_equal([KNOWN_SCENE])


func test_a_scene_that_does_not_exist_is_refused_before_any_fade() -> void:
	var transition := _spawn_transition()
	var started: Array[bool] = []
	transition.connect("transition_started", func() -> void: started.append(true))

	var swapped: bool = await transition.call("change_scene", "res://scenes/maps/atlantis.tscn")

	assert_bool(swapped).is_false()
	assert_array(_swaps).is_empty()
	assert_array(started).is_empty()
	assert_bool(bool(transition.get("is_transitioning"))).is_false()
	assert_float(_alpha(transition)).is_equal(0.0)


func test_a_swap_that_fails_reveals_the_old_scene_again() -> void:
	var transition := _spawn_transition()
	transition.set("scene_changer", func(_path: String) -> Error: return ERR_CANT_OPEN)
	var announced: Array[String] = []
	transition.connect("scene_changed", func(path: String) -> void: announced.append(path))

	var swapped: bool = await transition.call("change_scene", KNOWN_SCENE)

	assert_bool(swapped).is_false()
	assert_array(announced).is_empty()
	assert_bool(bool(transition.get("is_transitioning"))).is_false()
	assert_float(_alpha(transition)).is_equal(0.0)


func test_reveal_without_a_running_transition_announces_nothing() -> void:
	var transition := _spawn_transition()
	var finished: Array[bool] = []
	transition.connect("transition_finished", func() -> void: finished.append(true))

	await transition.call("reveal")

	assert_array(finished).is_empty()
	assert_bool(bool(transition.get("is_transitioning"))).is_false()


# --- Save file -----------------------------------------------------------------

func _write_valid_save(money: int) -> Dictionary:
	GameState.money = money
	GameState.playing = true
	assert_bool(SaveGame.save_game()).is_true()
	GameState.playing = false
	return JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))


func _store(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_an_empty_save_file_is_not_a_save() -> void:
	_store(SAVE_PATH, "")

	assert_bool(SaveGame.has_valid_save()).is_false()
	assert_dict(SaveGame.read_metadata()).is_empty()
	assert_bool(SaveGame.load_game()).is_false()


func test_a_save_file_that_is_not_an_object_is_not_a_save() -> void:
	_store(SAVE_PATH, "[1, 2, 3]")

	assert_bool(SaveGame.has_valid_save()).is_false()
	assert_dict(SaveGame.read_cycle()).is_empty()


func test_a_save_without_a_version_is_refused() -> void:
	var payload := _write_valid_save(50)
	SaveGame.delete_save()
	payload.erase("version")
	_store(SAVE_PATH, JSON.stringify(payload))

	assert_bool(SaveGame.has_valid_save()).is_false()


func test_a_save_missing_a_required_block_is_refused() -> void:
	var payload := _write_valid_save(50)
	for key: String in ["money", "day", "seeds", "produce", "prices"]:
		SaveGame.delete_save()
		var damaged := payload.duplicate(true)
		damaged.erase(key)
		_store(SAVE_PATH, JSON.stringify(damaged))

		assert_bool(SaveGame.has_valid_save()).override_failure_message(
			"A save without '%s' should be refused" % key).is_false()


func test_a_current_save_without_its_campaign_is_refused() -> void:
	var payload := _write_valid_save(50)
	SaveGame.delete_save()
	payload.erase("campaign")
	_store(SAVE_PATH, JSON.stringify(payload))

	assert_bool(SaveGame.has_valid_save()).is_false()
	assert_bool(SaveGame.load_game()).is_false()


func test_a_save_whose_place_is_taken_by_a_folder_reports_the_failure() -> void:
	# The temporary file can be written but cannot be moved into place.
	var folder := ProjectSettings.globalize_path(SAVE_PATH)
	assert_int(DirAccess.make_dir_absolute(folder)).is_equal(OK)
	GameState.playing = true

	var saved := SaveGame.save_game()

	GameState.playing = false
	var still_a_folder := DirAccess.dir_exists_absolute(folder)
	DirAccess.remove_absolute(folder)
	assert_bool(saved).is_false()
	assert_bool(still_a_folder).is_true()
	assert_bool(SaveGame.has_valid_save()).is_false()


func test_a_damaged_save_falls_back_to_its_backup() -> void:
	_write_valid_save(50)
	_write_valid_save(61)
	# The first write is now the backup; the primary gets truncated.
	_store(SAVE_PATH, "")

	assert_bool(SaveGame.has_valid_save()).is_true()
	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(50)


func test_a_save_that_cannot_be_written_reports_the_failure() -> void:
	SaveGame.save_path = "user://test_systems_edges_missing_dir/save.json"
	GameState.playing = true

	var saved := SaveGame.save_game()

	GameState.playing = false
	assert_bool(saved).is_false()
	assert_bool(SaveGame.has_valid_save()).is_false()


# --- Day/night tint ------------------------------------------------------------

func _spawn_cycle() -> Node:
	var cycle: Node = CYCLE_SCRIPT.new()
	cycle.set("day_duration", DAY_SECONDS)
	cycle.set("night_duration", NIGHT_SECONDS)
	cycle.set_process(false)
	add_child(auto_free(cycle))
	return cycle


func _tint(cycle: Node) -> Color:
	return (cycle.get_node("Tint") as CanvasModulate).color


func test_night_falls_from_dusk_and_ends_towards_dawn() -> void:
	var cycle := _spawn_cycle()
	var dusk: Color = cycle.get("dusk_color")
	var night: Color = cycle.get("night_color")
	var dawn: Color = cycle.get("dawn_color")

	var day: Color = cycle.get("day_color")

	# A tenth before sunset: the light already turns towards dusk.
	cycle.call("advance", DAY_SECONDS * 0.5)
	assert_bool(_tint(cycle).is_equal_approx(day)).is_true()
	cycle.call("advance", DAY_SECONDS * 0.4)
	var setting := _tint(cycle)
	assert_float(setting.get_luminance()).is_less(day.get_luminance())
	assert_float(setting.get_luminance()).is_greater(dusk.get_luminance())

	cycle.call("advance", DAY_SECONDS * 0.1)
	assert_bool(bool(cycle.call("is_night"))).is_true()
	assert_bool(_tint(cycle).is_equal_approx(dusk)).is_true()

	# A tenth into the night: between dusk and full night.
	cycle.call("advance", NIGHT_SECONDS * 0.1)
	var falling := _tint(cycle)
	assert_float(falling.get_luminance()).is_less(dusk.get_luminance())
	assert_float(falling.get_luminance()).is_greater(night.get_luminance())

	cycle.call("advance", NIGHT_SECONDS * 0.4)
	assert_bool(_tint(cycle).is_equal_approx(night)).is_true()

	# A tenth before sunrise: already lighter than full night, not yet dawn.
	cycle.call("advance", NIGHT_SECONDS * 0.4)
	var rising := _tint(cycle)
	assert_float(rising.get_luminance()).is_greater(night.get_luminance())
	assert_float(rising.get_luminance()).is_less(dawn.get_luminance())


func test_a_cycle_can_be_configured_before_it_enters_the_tree() -> void:
	var cycle: Node = auto_free(CYCLE_SCRIPT.new())
	cycle.set_process(false)

	# No tint node exists yet; the choice must still be honoured once it does.
	cycle.set("tint_enabled", false)
	assert_object(cycle.get_node_or_null("Tint")).is_null()
	add_child(cycle)

	assert_bool((cycle.get_node("Tint") as CanvasModulate).visible).is_false()


# --- Input device tracking -----------------------------------------------------

func test_a_real_gamepad_press_switches_the_hints_to_the_gamepad() -> void:
	var changes: Array[bool] = []
	var listener := func(gamepad: bool) -> void: changes.append(gamepad)
	InputHints.device_changed.connect(listener)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true

	# The engine delivers events through `_input`, not through `note_event`.
	InputHints._input(button)
	assert_bool(InputHints.using_gamepad).is_true()
	InputHints._input(key)

	InputHints.device_changed.disconnect(listener)
	assert_bool(InputHints.using_gamepad).is_false()
	assert_array(changes).is_equal([true, false])
