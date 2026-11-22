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


func test_round_trip_restores_economy_state() -> void:
	Economy.select_generation(&"cultivateur")
	GameState.money = 100
	assert_bool(Economy.buy(&"building_barn")).is_true()
	var wallet := Economy.balance(&"gourde")
	var owned := Economy.owned_count(&"barn")
	assert_bool(SaveGame.save_game()).is_true()

	Economy.select_generation(&"cultivateur")
	assert_int(Economy.balance(&"gourde")).is_equal(30)
	assert_int(Economy.owned_count(&"barn")).is_equal(0)

	assert_bool(SaveGame.load_game()).is_true()
	assert_int(Economy.balance(&"gourde")).is_equal(wallet)
	assert_int(Economy.owned_count(&"barn")).is_equal(owned)
	assert_int(GameState.money).is_equal(wallet)


func test_version_1_payload_without_economy_still_loads() -> void:
	var payload := GameState.to_dict()
	payload.erase("economy")
	payload["version"] = 1
	payload["money"] = 55
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	GameState.money = 1

	assert_bool(SaveGame.load_game()).is_true()
	assert_int(GameState.money).is_equal(55)


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


func _rewrite(mutate: Callable) -> void:
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	mutate.call(payload)
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()


func test_a_save_the_game_would_refuse_is_not_a_valid_save() -> void:
	# Regression (#24): Continue stayed enabled and did nothing when pressed.
	SaveGame.save_game()
	for mutate: Callable in [
		func(data: Dictionary) -> void: data["money"] = "beaucoup",
		func(data: Dictionary) -> void: data["economy"]["generation"] = "disparue",
		func(data: Dictionary) -> void: data["campaign"] = {},
		func(data: Dictionary) -> void: data["seeds"] = [],
	]:
		SaveGame.save_game()
		_rewrite(mutate)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".bak"))

		assert_bool(SaveGame.has_valid_save()).is_false()
		assert_dict(SaveGame.read_metadata()).is_empty()
		assert_bool(SaveGame.load_game()).is_false()


func test_an_unloadable_primary_falls_back_to_a_healthy_backup() -> void:
	GameState.money = 64
	SaveGame.save_game()
	GameState.money = 99
	SaveGame.save_game()
	_rewrite(func(data: Dictionary) -> void: data["money"] = "x")
	GameState.money = 0

	assert_bool(SaveGame.has_valid_save()).is_true()
	assert_bool(SaveGame.load_game()).is_true()

	assert_int(GameState.money).is_equal(64)


func test_a_refused_load_leaves_the_game_untouched() -> void:
	# The game state used to be applied before the campaign was found invalid.
	GameState.money = 12
	SaveGame.save_game()
	_rewrite(func(data: Dictionary) -> void:
		data["money"] = 500
		data["campaign"] = {})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH + ".bak"))
	GameState.money = 33
	Campaign.current_map = 2

	assert_bool(SaveGame.load_game()).is_false()

	assert_int(GameState.money).is_equal(33)
	assert_int(Campaign.current_map).is_equal(2)


func test_metadata_survives_hand_edited_values() -> void:
	Campaign.current_map = 3
	Campaign.finished = true
	SaveGame.save_game()
	var metadata := SaveGame.read_metadata()
	assert_int(int(metadata["map"])).is_equal(3)
	assert_bool(bool(metadata["finished"])).is_true()
	assert_str(String(metadata["saved_at"])).is_not_empty()

	_rewrite(func(data: Dictionary) -> void:
		data["campaign"]["current_map"] = 42
		data["campaign"]["finished"] = "oui")

	metadata = SaveGame.read_metadata()
	assert_int(int(metadata["map"])).is_equal(3)
	assert_bool(bool(metadata["finished"])).is_false()


# --- #59 -----------------------------------------------------------------------

func test_the_backup_stays_a_while_behind() -> void:
	# Regression: every save rotated the backup, which was then seconds old.
	GameState.money = 10
	SaveGame.save_game()
	GameState.money = 20
	SaveGame.save_game()
	GameState.money = 30
	SaveGame.save_game()
	GameState.money = 40
	SaveGame.save_game()

	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH + ".bak"))
	assert_int(int(backup["money"])).is_equal(10)
	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(40)


func test_an_old_backup_is_replaced() -> void:
	GameState.money = 10
	SaveGame.save_game()
	GameState.money = 20
	SaveGame.save_game()
	SaveGame.backup_interval = 0.0

	GameState.money = 30
	SaveGame.save_game()

	SaveGame.backup_interval = SaveGame.BACKUP_INTERVAL
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH + ".bak"))
	assert_int(int(backup["money"])).is_equal(20)


func test_a_write_interrupted_before_the_rename_is_recovered() -> void:
	GameState.money = 55
	SaveGame.save_game()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(TEST_PATH),
		ProjectSettings.globalize_path(TEST_PATH + ".tmp"))
	GameState.money = 0

	assert_bool(SaveGame.load_game()).is_true()

	assert_int(GameState.money).is_equal(55)


func test_autosave_only_writes_while_a_game_is_running() -> void:
	GameState.playing = false
	assert_bool(SaveGame.autosave()).is_false()
	assert_bool(SaveGame.has_valid_save()).is_false()

	GameState.playing = true
	GameState.money = 66
	assert_bool(SaveGame.autosave()).is_true()
	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(66)

	var timer: Timer = SaveGame.get_node("AutosaveTimer")
	assert_float(timer.wait_time).is_equal(SaveGame.AUTOSAVE_INTERVAL)
	assert_bool(timer.is_stopped()).is_false()


func test_losing_focus_saves_the_game() -> void:
	# The last thing a browser tells a page before the tab may be closed.
	GameState.playing = true
	GameState.money = 71

	SaveGame.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)

	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(71)
