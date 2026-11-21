extends GdUnitTestSuite

const TEST_SAVE_PATH := "user://test_game_state_save.json"

var _original_save_path := ""


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	_remove_test_save()
	GameState.playing = false
	GameState.farm_active = true
	GameState.reset()


func after_test() -> void:
	GameState.playing = false
	GameState.reset()
	_remove_test_save()
	SaveGame.save_path = _original_save_path


func _remove_test_save() -> void:
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_reset_restores_starting_values() -> void:
	GameState.money = 999
	GameState.day = 12
	GameState.selected_seed = "pumpkin"
	GameState.seeds["corn"] = 0
	GameState.produce["corn"] = 5
	GameState.prices["corn"] = 99

	GameState.reset()

	assert_int(GameState.money).is_equal(GameState.START_MONEY)
	assert_int(GameState.day).is_equal(GameState.START_DAY)
	assert_str(GameState.selected_seed).is_equal("corn")
	assert_int(GameState.seed_count("corn")).is_equal(2)
	assert_int(GameState.produce_count("corn")).is_equal(0)
	assert_int(int(GameState.prices["corn"])).is_equal(10)


func test_reset_emits_state_signals() -> void:
	var money_values: Array[int] = []
	var inventory_events: Array[bool] = []
	GameState.money_changed.connect(func(value: int) -> void: money_values.append(value))
	GameState.inventory_changed.connect(func() -> void: inventory_events.append(true))

	GameState.reset()

	assert_int(money_values.size()).is_equal(1)
	assert_int(money_values[0]).is_equal(GameState.START_MONEY)
	assert_int(inventory_events.size()).is_equal(1)


func test_day_does_not_advance_when_not_playing() -> void:
	GameState.playing = false
	GameState.day = 1
	GameState.set("_day_time", 59.0)

	GameState.call("_process", 2.0)

	assert_int(GameState.day).is_equal(1)


func test_day_advances_when_playing() -> void:
	GameState.playing = true
	GameState.day = 1
	GameState.set("_day_time", 59.0)

	GameState.call("_process", 2.0)

	assert_int(GameState.day).is_equal(2)
	assert_bool(FileAccess.file_exists(TEST_SAVE_PATH)).is_true()


func test_from_dict_accepts_json_floats() -> void:
	var payload := {
		"money": 42.0,
		"day": 3.0,
		"day_time": 12.5,
		"selected_seed": "pumpkin",
		"seeds": {"corn": 1.0, "pumpkin": 2.0, "tomato": 0.0, "carrot": 4.0},
		"produce": {"corn": 0.0, "pumpkin": 1.0, "tomato": 2.0, "carrot": 0.0},
		"prices": {"corn": 11.0, "pumpkin": 18.0, "tomato": 8.0, "carrot": 6.0},
		"previous_prices": {"corn": 10.0, "pumpkin": 16.0, "tomato": 9.0, "carrot": 7.0},
	}

	assert_bool(GameState.from_dict(payload)).is_true()
	assert_int(GameState.money).is_equal(42)
	assert_int(GameState.day).is_equal(3)
	assert_str(GameState.selected_seed).is_equal("pumpkin")
	assert_int(GameState.seed_count("pumpkin")).is_equal(2)
	assert_int(GameState.produce_count("tomato")).is_equal(2)


func test_from_dict_rejects_invalid_payload_without_mutating_state() -> void:
	GameState.money = 77
	GameState.day = 5

	assert_bool(GameState.from_dict({"money": "bad"})).is_false()
	assert_int(GameState.money).is_equal(77)
	assert_int(GameState.day).is_equal(5)
