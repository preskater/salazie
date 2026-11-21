extends GdUnitTestSuite

const TEST_PATH := "user://test_savegame.json"

var _original_path := ""


func before_test() -> void:
	_original_path = SaveGame.save_path
	SaveGame.save_path = TEST_PATH
	_cleanup()
	Campaign.reset()
	GameState.playing = true
	GameState.reset()


func after_test() -> void:
	_cleanup()
	SaveGame.save_path = _original_path
	GameState.playing = false
	GameState.reset()
	Campaign.reset()


func _cleanup() -> void:
	for path: String in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_round_trip_restores_farm_state() -> void:
	GameState.money = 123
	GameState.day = 4
	GameState.selected_seed = "tomato"
	GameState.seeds["corn"] = 7
	GameState.produce["tomato"] = 2
	GameState.prices["corn"] = 14

	assert_bool(SaveGame.save_game()).is_true()

	GameState.money = 0
	GameState.day = 1
	GameState.selected_seed = "corn"
	GameState.seeds["corn"] = 0
	GameState.produce["tomato"] = 0
	GameState.prices["corn"] = 1

	assert_bool(SaveGame.load_game()).is_true()
	assert_int(GameState.money).is_equal(123)
	assert_int(GameState.day).is_equal(4)
	assert_str(GameState.selected_seed).is_equal("tomato")
	assert_int(GameState.seed_count("corn")).is_equal(7)
	assert_int(GameState.produce_count("tomato")).is_equal(2)
	assert_int(int(GameState.prices["corn"])).is_equal(14)


func test_metadata_is_read_without_applying_the_save() -> void:
	GameState.money = 88
	GameState.day = 6
	assert_bool(SaveGame.save_game()).is_true()
	GameState.money = 1
	GameState.day = 1

	var metadata := SaveGame.read_metadata()

	assert_int(int(metadata["money"])).is_equal(88)
	assert_int(int(metadata["day"])).is_equal(6)
	assert_int(GameState.money).is_equal(1)
	assert_int(GameState.day).is_equal(1)


func test_invalid_primary_falls_back_to_the_backup() -> void:
	GameState.money = 111
	assert_bool(SaveGame.save_game()).is_true()
	GameState.money = 222
	assert_bool(SaveGame.save_game()).is_true()

	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{\"version\": 1, \"money\": 0}")
	file.close()

	GameState.money = 0
	assert_bool(SaveGame.load_game()).is_true()
	assert_int(GameState.money).is_equal(111)


func test_newer_save_version_is_refused() -> void:
	var payload := GameState.to_dict()
	payload["version"] = 99
	payload["money"] = 500
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	GameState.money = 7

	assert_bool(SaveGame.load_game()).is_false()
	assert_int(GameState.money).is_equal(7)


func test_delete_save_removes_all_candidates() -> void:
	GameState.money = 50
	assert_bool(SaveGame.save_game()).is_true()
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_true()

	SaveGame.delete_save()

	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()
	assert_bool(FileAccess.file_exists(TEST_PATH + ".bak")).is_false()


func test_save_requires_a_running_game() -> void:
	GameState.playing = false

	assert_bool(SaveGame.save_game()).is_false()
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_false()


func test_version_one_save_migrates_to_the_farm_generation() -> void:
	Campaign.reset()
	var payload := {
		"version": 1,
		"money": 120,
		"day": 3,
		"day_time": 4.0,
		"selected_seed": "corn",
		"seeds": {"corn": 1, "pumpkin": 0, "tomato": 0, "carrot": 0},
		"produce": {"corn": 0, "pumpkin": 0, "tomato": 0, "carrot": 0},
		"prices": {"corn": 10, "pumpkin": 16, "tomato": 9, "carrot": 7},
	}
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

	assert_bool(SaveGame.load_game()).is_true()
	assert_int(GameState.money).is_equal(120)
	assert_int(Campaign.current_map).is_equal(2)
	assert_int(Campaign.task_status("find_food", 1)).is_equal(Campaign.TaskStatus.DONE)
	assert_int(Campaign.task_status("earn_100", 2)).is_equal(Campaign.TaskStatus.DONE)
