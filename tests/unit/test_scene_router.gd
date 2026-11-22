extends GdUnitTestSuite
## Game lifecycle: new game, continue, next map, ending, back to the menu.
## The scene swap itself is replaced by a recorder, so the transitions run for
## real without tearing down the test runner's scene.

const TEST_PATH := "user://test_scene_router.json"
const PAUSE_MENU_SCENE := "res://scenes/preloads/pause_menu.tscn"

var _original_path := ""
var _swaps: Array[String] = []
var _swap_result: Error = OK
var _durations: Array[float] = []


func before_test() -> void:
	_original_path = SaveGame.save_path
	SaveGame.save_path = TEST_PATH
	SaveGame.delete_save()
	_swaps = []
	_swap_result = OK
	var recorder := func(path: String) -> Error:
		_swaps.append(path)
		return _swap_result
	SceneRouter.scene_changer = recorder
	SceneRouter.fade_time = 0.01
	SceneTransition.scene_changer = recorder
	_durations = [SceneTransition.fade_out_duration, SceneTransition.hold_duration,
		SceneTransition.fade_in_duration]
	SceneTransition.fade_out_duration = 0.0
	SceneTransition.hold_duration = 0.0
	SceneTransition.fade_in_duration = 0.0
	Campaign.reset()
	GameState.reset()
	GameState.playing = false
	SceneRouter.is_gameplay = false


func after_test() -> void:
	SceneRouter.scene_changer = Callable()
	SceneRouter.fade_time = SceneRouter.FADE_TIME
	SceneTransition.scene_changer = Callable()
	SceneTransition.fade_out_duration = _durations[0]
	SceneTransition.hold_duration = _durations[1]
	SceneTransition.fade_in_duration = _durations[2]
	SaveGame.delete_save()
	SaveGame.save_path = _original_path
	Campaign.reset()
	GameState.reset()
	GameState.playing = false
	GameState.farm_active = true
	SceneRouter.is_gameplay = false
	DayNightCycle.running = false
	DayNightCycle.tint_enabled = false
	if get_tree() != null:
		get_tree().paused = false


func _write_save(mutate: Callable = Callable()) -> void:
	GameState.playing = true
	assert_bool(SaveGame.save_game()).is_true()
	GameState.playing = false
	if mutate.is_valid():
		var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
		mutate.call(payload)
		var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(payload))
		file.close()


func _resolve_map(map_id: int) -> void:
	for definition: Dictionary in Campaign.TASKS[map_id]:
		Campaign.complete_task(String(definition["id"]), map_id)


# --- New game ----------------------------------------------------------------

func test_only_a_scene_run_on_its_own_bootstraps_a_gameplay_session() -> void:
	var added: Node = auto_free(Node.new())
	add_child(added)

	assert_bool(SceneRouter.bootstrap_direct_run(added)).is_false()
	assert_bool(GameState.playing).is_false()
	assert_bool(SceneRouter.is_gameplay).is_false()

	assert_bool(SceneRouter.bootstrap_direct_run(get_tree().current_scene)).is_true()
	assert_bool(GameState.playing).is_true()
	assert_bool(SceneRouter.is_gameplay).is_true()


func test_new_game_starts_on_map_one_and_saves() -> void:
	Campaign.current_map = 3
	Campaign.record_setback("ancien", 1)
	SaveGame.world = {3: {"player": [1, 2]}}

	assert_bool(await SceneRouter.start_new_game()).is_true()

	assert_array(_swaps).is_equal([SceneRouter.GAME_SCENE])
	assert_int(Campaign.current_map).is_equal(1)
	assert_int(Campaign.setbacks_for_map(1)).is_equal(0)
	assert_dict(SaveGame.world).is_empty()
	assert_bool(GameState.playing).is_true()
	assert_bool(GameState.farm_active).is_false()
	assert_bool(SceneRouter.is_gameplay).is_true()
	assert_bool(DayNightCycle.running).is_true()
	assert_bool(SaveGame.has_valid_save()).is_true()
	assert_bool(SceneRouter.is_transitioning()).is_false()


func test_new_game_that_cannot_load_its_scene_stays_out_of_gameplay() -> void:
	_swap_result = ERR_CANT_OPEN

	assert_bool(await SceneRouter.start_new_game()).is_false()

	assert_bool(GameState.playing).is_false()
	assert_bool(SceneRouter.is_gameplay).is_false()
	assert_bool(DayNightCycle.running).is_false()
	assert_bool(SaveGame.has_valid_save()).is_false()
	assert_bool(SceneRouter.is_transitioning()).is_false()


func test_a_second_transition_is_refused_while_one_runs() -> void:
	SceneRouter.start_new_game()

	assert_bool(SceneRouter.is_transitioning()).is_true()
	assert_bool(await SceneRouter.start_new_game()).is_false()
	assert_bool(await SceneRouter.continue_game()).is_false()
	assert_bool(await SceneRouter.go_to_next_map()).is_false()
	await SceneRouter.go_to_main_menu()
	await SceneRouter.go_to_ending()
	await SceneRouter.transition_finished

	assert_array(_swaps).is_equal([SceneRouter.GAME_SCENE])


func test_pause_menu_stays_closed_during_the_fade_to_a_new_game() -> void:
	# Regression (#30): Escape during the fade opened the pause overlay over the
	# main menu and the map started paused.
	var pause: CanvasLayer = auto_free(load(PAUSE_MENU_SCENE).instantiate())
	add_child(pause)
	SceneRouter.start_new_game()

	pause.call("open")
	SceneRouter.is_gameplay = true
	pause.call("open")

	assert_bool(pause.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	await SceneRouter.transition_finished
	pause.call("open")
	assert_bool(pause.visible).is_true()
	pause.call("close")


# --- Continue ----------------------------------------------------------------

func test_continue_resumes_the_saved_generation_and_clock() -> void:
	Campaign.current_map = 2
	GameState.money = 77
	DayNightCycle.running = true
	DayNightCycle.reset_for_new_map(0)
	DayNightCycle.advance(DayNightCycle.day_duration + 5.0)
	_write_save()
	Campaign.reset()
	GameState.reset()
	DayNightCycle.reset_for_new_map(0)

	assert_bool(await SceneRouter.continue_game()).is_true()

	assert_array(_swaps).is_equal([SceneRouter.FARM_SCENE])
	assert_int(GameState.money).is_equal(77)
	assert_bool(GameState.playing).is_true()
	assert_bool(GameState.farm_active).is_true()
	assert_bool(SceneRouter.is_gameplay).is_true()
	# The farm's sky follows the farm's own day, not a second clock.
	assert_bool(DayNightCycle.running).is_false()


func test_continue_restores_the_sky_of_a_map_without_its_own_clock() -> void:
	Campaign.current_map = 1
	DayNightCycle.running = true
	DayNightCycle.reset_for_new_map(0)
	DayNightCycle.advance(DayNightCycle.day_duration + 5.0)
	_write_save()
	Campaign.reset()
	DayNightCycle.reset_for_new_map(0)

	assert_bool(await SceneRouter.continue_game()).is_true()

	assert_bool(DayNightCycle.is_night()).is_true()
	assert_bool(DayNightCycle.running).is_true()


func test_continue_without_a_save_does_nothing() -> void:
	assert_bool(await SceneRouter.continue_game()).is_false()

	assert_array(_swaps).is_empty()
	assert_bool(GameState.playing).is_false()


func test_continue_that_cannot_load_its_scene_stays_out_of_gameplay() -> void:
	_write_save()
	_swap_result = ERR_CANT_OPEN

	assert_bool(await SceneRouter.continue_game()).is_false()

	assert_bool(GameState.playing).is_false()
	assert_bool(SceneRouter.is_gameplay).is_false()


func test_a_finished_story_resumes_on_its_epilogue() -> void:
	# Regression (#25): Continue reopened Map 3 with every task resolved.
	Campaign.current_map = 3
	Campaign.finished = true
	_write_save()
	Campaign.reset()

	assert_bool(await SceneRouter.continue_game()).is_true()

	assert_array(_swaps).is_equal([SceneRouter.ENDING_SCENE])
	assert_bool(Campaign.finished).is_true()
	assert_bool(GameState.playing).is_false()
	assert_bool(SceneRouter.is_gameplay).is_false()


# --- Next map and ending -----------------------------------------------------

func test_next_map_needs_every_task_resolved() -> void:
	GameState.playing = true

	assert_bool(await SceneRouter.go_to_next_map()).is_false()

	assert_array(_swaps).is_empty()
	assert_int(Campaign.current_map).is_equal(1)


func test_leaving_map_one_prepares_the_farm() -> void:
	GameState.playing = true
	SceneRouter.is_gameplay = true
	_resolve_map(1)
	Campaign.record_setback("Repéré", 1)
	Campaign.add_bonus_seed("corn", 2)
	var seeds_before := int(GameState.START_SEEDS["corn"])
	var finished: Array[bool] = []
	var listener := func() -> void: finished.append(true)
	SceneRouter.transition_finished.connect(listener)

	assert_bool(await SceneRouter.go_to_next_map()).is_true()

	SceneRouter.transition_finished.disconnect(listener)
	assert_array(_swaps).is_equal([SceneRouter.FARM_SCENE])
	assert_int(Campaign.current_map).is_equal(2)
	assert_int(GameState.money).is_equal(25)
	assert_int(GameState.seed_count("corn")).is_equal(seeds_before + 2)
	assert_bool(GameState.farm_active).is_true()
	assert_bool(SceneRouter.is_gameplay).is_true()
	assert_int(finished.size()).is_equal(1)
	assert_int(int(SaveGame.read_metadata()["map"])).is_equal(2)


func test_leaving_the_farm_hands_down_the_heritage() -> void:
	GameState.playing = true
	Campaign.current_map = 2
	_resolve_map(2)
	GameState.money = 140

	assert_bool(await SceneRouter.go_to_next_map()).is_true()

	assert_array(_swaps).is_equal([SceneRouter.HEIR_SCENE])
	assert_int(Campaign.heritage).is_equal(140)
	assert_bool(GameState.farm_active).is_false()


func test_a_failed_swap_to_the_next_map_falls_back_to_the_menu() -> void:
	# Regression (#49): the router carried on as if the new map had loaded.
	GameState.playing = true
	SceneRouter.is_gameplay = true
	_resolve_map(1)
	var announced: Array = []
	var listener := func(scene: Node) -> void: announced.append(scene)
	SceneRouter.scene_changed.connect(listener)
	SceneTransition.scene_changer = func(_path: String) -> Error: return ERR_CANT_OPEN

	assert_bool(await SceneRouter.go_to_next_map()).is_false()

	SceneRouter.scene_changed.disconnect(listener)
	assert_array(_swaps).is_equal([SceneRouter.MAIN_MENU_SCENE])
	assert_bool(SceneRouter.is_gameplay).is_false()
	assert_bool(GameState.playing).is_false()
	# The save already points at the new generation, which Continue resumes.
	assert_int(int(SaveGame.read_metadata()["map"])).is_equal(2)
	assert_int(announced.size()).is_equal(1)


func test_the_last_map_leads_to_the_ending() -> void:
	GameState.playing = true
	SceneRouter.is_gameplay = true
	Campaign.current_map = 3
	_resolve_map(3)

	assert_bool(await SceneRouter.go_to_next_map()).is_true()

	assert_array(_swaps).is_equal([SceneRouter.ENDING_SCENE])
	assert_bool(Campaign.finished).is_true()
	assert_bool(GameState.playing).is_false()
	assert_bool(SceneRouter.is_gameplay).is_false()
	assert_bool(DayNightCycle.running).is_false()
	assert_bool(bool(SaveGame.read_metadata()["finished"])).is_true()


func test_going_to_the_ending_outside_a_game_writes_no_save() -> void:
	Campaign.current_map = 3

	await SceneRouter.go_to_ending()

	assert_array(_swaps).is_equal([SceneRouter.ENDING_SCENE])
	assert_bool(SaveGame.has_valid_save()).is_false()


# --- Menu --------------------------------------------------------------------

func test_back_to_the_menu_saves_and_leaves_gameplay() -> void:
	GameState.playing = true
	SceneRouter.is_gameplay = true
	GameState.money = 51
	get_tree().paused = true

	await SceneRouter.go_to_main_menu()

	assert_array(_swaps).is_equal([SceneRouter.MAIN_MENU_SCENE])
	assert_int(int(SaveGame.read_metadata()["money"])).is_equal(51)
	assert_bool(GameState.playing).is_false()
	assert_bool(SceneRouter.is_gameplay).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_bool(DayNightCycle.running).is_false()


func test_back_to_the_menu_from_the_ending_writes_no_save() -> void:
	await SceneRouter.go_to_main_menu()

	assert_array(_swaps).is_equal([SceneRouter.MAIN_MENU_SCENE])
	assert_bool(SaveGame.has_valid_save()).is_false()
