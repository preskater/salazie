extends GdUnitTestSuite
## Invalid input is refused instead of quietly corrupting the state (#48), and
## each generation shows the money it really has (#46).

const MAROON_SCENE := preload("res://scenes/maps/maroon.tscn")
const TEST_PATH := "user://test_state_validation.json"
const TEST_CONFIG := "user://test_state_validation.cfg"

var _original_path := ""
var _original_config := ""


func before_test() -> void:
	_original_path = SaveGame.save_path
	SaveGame.save_path = TEST_PATH
	_original_config = Settings.config_path
	Settings.config_path = TEST_CONFIG
	GameState.playing = false
	Campaign.reset()
	GameState.reset()


func after_test() -> void:
	GameState.playing = false
	Campaign.reset()
	GameState.reset()
	GameState.farm_active = true
	SaveGame.delete_save()
	SaveGame.save_path = _original_path
	if FileAccess.file_exists(TEST_CONFIG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG))
	Settings.config_path = _original_config
	Settings.load_settings()
	if get_tree() != null:
		get_tree().paused = false


# --- Game state ----------------------------------------------------------------

func test_seeds_of_an_unknown_crop_or_a_negative_count_are_refused() -> void:
	var before := GameState.seeds.duplicate(true)
	var changes: Array[bool] = []
	var listener := func() -> void: changes.append(true)
	GameState.inventory_changed.connect(listener)

	GameState.add_seeds("ananas", 3)
	GameState.add_seeds("corn", -2)
	GameState.add_seeds("corn", 0)

	GameState.inventory_changed.disconnect(listener)
	assert_dict(GameState.seeds).is_equal(before)
	assert_int(changes.size()).is_equal(0)


func test_an_unknown_crop_has_no_trend_and_cannot_be_sold() -> void:
	GameState.produce["ananas"] = 4

	assert_int(GameState.price_trend("ananas")).is_equal(0)
	assert_int(GameState.sell("ananas", 2)).is_equal(0)
	assert_int(int(GameState.produce["ananas"])).is_equal(4)
	GameState.produce.erase("ananas")


func test_setting_the_money_announces_it_once() -> void:
	var seen: Array[int] = []
	var listener := func(value: int) -> void: seen.append(value)
	GameState.money_changed.connect(listener)

	GameState.set_money(77)

	GameState.money_changed.disconnect(listener)
	assert_array(seen).is_equal([77])


func test_setting_the_money_without_an_economy_still_announces_it() -> void:
	Economy.set_enabled(false)
	var seen: Array[int] = []
	var listener := func(value: int) -> void: seen.append(value)
	GameState.money_changed.connect(listener)

	GameState.set_money(40)

	GameState.money_changed.disconnect(listener)
	Economy.set_enabled(true)
	assert_array(seen).is_equal([40])


# --- Economy -----------------------------------------------------------------

func test_a_typo_does_not_swap_the_running_economy() -> void:
	assert_str(String(Economy.current_generation_id())).is_equal("cultivateur")

	assert_bool(Economy.select_generation(&"cultivatuer")).is_false()

	assert_str(String(Economy.current_generation_id())).is_equal("cultivateur")
	assert_bool(Economy.is_enabled()).is_true()


func test_a_save_cannot_grant_assets_the_generation_does_not_sell() -> void:
	var payload := Economy.to_dict()
	payload["owned"] = {"barn": 1, "palace": 3, "hoe": "many"}

	assert_bool(Economy.from_dict(payload)).is_true()

	assert_int(Economy.owned_count(&"barn")).is_equal(1)
	assert_int(Economy.owned_count(&"palace")).is_equal(0)
	assert_int(Economy.owned_count(&"hoe")).is_equal(0)


# --- Campaign ----------------------------------------------------------------

func test_results_keep_integer_keys_after_a_real_save_load() -> void:
	for definition: Dictionary in Campaign.TASKS[1]:
		Campaign.complete_task(String(definition["id"]), 1)
	var payload: Dictionary = JSON.parse_string(JSON.stringify(Campaign.to_dict()))

	Campaign.reset()
	assert_bool(Campaign.from_dict(payload)).is_true()

	assert_bool(Campaign.results.has(1)).is_true()
	assert_bool(Campaign.results.has("1")).is_false()
	# A setback after the load refreshes the stored result instead of adding a
	# second entry next to a string-keyed one.
	Campaign.record_setback("Repéré", 1)
	assert_int(Campaign.results.size()).is_equal(1)
	assert_str(String(Campaign.results[1]["rank"])).is_equal("partial")


func test_village_progress_follows_the_flags_of_a_damaged_save() -> void:
	# Every site flagged but the task one short: nothing would be left to inspect.
	var payload := Campaign.to_dict()
	payload["current_map"] = 3
	payload["choices"] = {"assessed_berge": "1", "assessed_foret": "1", "assessed_marche": "1",
		"listened_A": "1"}
	(payload["tasks"][3]["assess"] as Dictionary)["progress"] = 2

	assert_bool(Campaign.from_dict(payload)).is_true()

	assert_int(Campaign.task_status("assess", 3)).is_equal(Campaign.TaskStatus.DONE)
	assert_int(Campaign.task_progress("assess", 3)).is_equal(3)
	assert_int(Campaign.task_progress("listen", 3)).is_equal(1)
	assert_int(Campaign.task_status("listen", 3)).is_equal(Campaign.TaskStatus.PENDING)


# --- Settings ----------------------------------------------------------------

func test_a_hand_edited_settings_file_cannot_raise_at_boot() -> void:
	var config := ConfigFile.new()
	config.set_value(Settings.SECTION_AUDIO, "master", "fort")
	config.set_value(Settings.SECTION_AUDIO, "music", [1, 2])
	config.set_value(Settings.SECTION_AUDIO, "sfx", 0.25)
	config.set_value(Settings.SECTION_DISPLAY, "window_mode", "plein")
	config.set_value(Settings.SECTION_DISPLAY, "vsync", "oui")
	config.save(TEST_CONFIG)
	Settings.master_volume = 0.4
	Settings.music_volume = 0.6
	Settings.vsync_enabled = true

	Settings.load_settings()

	assert_float(Settings.master_volume).is_equal(0.4)
	assert_float(Settings.music_volume).is_equal(0.6)
	assert_float(Settings.sfx_volume).is_equal(0.25)
	assert_int(Settings.window_mode).is_equal(Settings.WINDOWED)
	assert_bool(Settings.vsync_enabled).is_true()


# --- What the player holds, per generation -----------------------------------

func test_the_maroon_has_no_purse() -> void:
	# Regression (#46): Map 1 ran on the farmer's wallet and the pause menu
	# showed "30 G" to a man who owns nothing.
	var map: Node = auto_free(MAROON_SCENE.instantiate())
	add_child(map)

	assert_str(String(Economy.current_generation_id())).is_equal("marron")
	assert_bool(GameState.is_economy_enabled()).is_false()
	assert_str(GameState.status_line()).is_equal("Le marron")


func test_the_farm_counts_its_days_and_its_gourdes() -> void:
	Campaign.current_map = 2
	GameState.day = 4
	GameState.money = 63

	assert_str(GameState.status_line()).is_equal("Le cultivateur · Jour 4 · 63 G")


func test_the_heir_holds_euros_and_green_credits() -> void:
	Campaign.current_map = 3
	Economy.select_generation(&"heritier")
	Economy.set_balance(&"euro", 85)
	Economy.set_balance(&"credit_vert", 12)

	var line := GameState.status_line()

	assert_str(line).starts_with("L'héritier · ")
	assert_str(line).contains("85")
	assert_str(line).contains("€")
	assert_str(line).contains("CV")
	assert_str(line).not_contains("Jour")


func test_leaving_the_escape_gives_the_farmer_a_purse_again() -> void:
	var map: Node = auto_free(MAROON_SCENE.instantiate())
	add_child(map)
	Campaign.record_setback("Repéré", 1)

	SceneRouter.call("_prepare_map_entry", 2)

	assert_str(String(Economy.current_generation_id())).is_equal("cultivateur")
	assert_int(GameState.money).is_equal(25)
	DayNightCycle.running = false
	DayNightCycle.tint_enabled = false


func test_the_save_carries_its_own_summary() -> void:
	GameState.playing = true
	Campaign.current_map = 2
	GameState.money = 48
	GameState.day = 2

	assert_bool(SaveGame.save_game()).is_true()

	assert_str(String(SaveGame.read_metadata()["summary"])).is_equal(
		"Le cultivateur · Jour 2 · 48 G")
