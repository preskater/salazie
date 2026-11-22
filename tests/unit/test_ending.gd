extends GdUnitTestSuite

const ENDING_SCENE := preload("res://scenes/ui/ending/ending_screen.tscn")


func before_test() -> void:
	GameState.playing = false
	Campaign.reset()
	Campaign.current_map = 3
	Campaign.heritage = 120


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	if get_tree() != null:
		get_tree().paused = false


func _spawn_ending() -> Control:
	var ending: Control = ENDING_SCENE.instantiate()
	add_child(auto_free(ending))
	await get_tree().process_frame
	return ending


func test_forest_plan_and_election_produce_a_positive_epilogue() -> void:
	Campaign.set_choice("map3_plan", "forest")
	Campaign.complete_task("become_mayor")
	var ending := await _spawn_ending()

	var text := String(ending.call("get_epilogue_text"))
	assert_str(text).contains("forêt")
	assert_str(text).contains("maire")
	assert_str(String(ending.call("get_stats_text"))).contains("120 G")


func test_failed_council_vote_produces_a_secondary_epilogue() -> void:
	Campaign.set_choice("map3_plan", "farms")
	Campaign.fail_task("become_mayor", "Le conseil a rejeté le plan")
	var ending := await _spawn_ending()

	var text := String(ending.call("get_epilogue_text"))
	assert_str(text).contains("ne vous suit pas")
	# The rejection is the outcome told here, not a failure of the family.
	assert_str(text).contains("sans faute")


func test_ending_never_starts_paused() -> void:
	# Regression (#29): the ending could load with the tree paused and its only
	# button frozen.
	get_tree().paused = true
	var ending: Control = ENDING_SCENE.instantiate()
	add_child(auto_free(ending))

	assert_bool(get_tree().paused).is_false()
	assert_int(ending.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_object(get_viewport().gui_get_focus_owner()).is_not_null()


# --- #53 -----------------------------------------------------------------------

func test_the_epilogue_recaps_the_three_generations() -> void:
	for map_id: int in [1, 2]:
		for definition: Dictionary in Campaign.TASKS[map_id]:
			Campaign.complete_task(String(definition["id"]), map_id)
	Campaign.record_setback("Repéré", 1)
	Campaign.set_choice("map3_plan", "forest")
	Campaign.set_choice("map3_support", "5")
	Campaign.complete_task("listen", 3)
	Campaign.complete_task("assess", 3)
	Campaign.complete_task("choose_plan", 3)
	Campaign.fail_task("become_mayor", "rejeté", 3)
	var ending := await _spawn_ending()

	var lines: PackedStringArray = ending.call("get_recap_lines")

	assert_int(lines.size()).is_equal(3)
	assert_str(lines[0]).is_equal("Le marron — accomplie non sans mal · 1 revers")
	assert_str(lines[1]).is_equal("Le cultivateur — accomplie")
	assert_str(lines[2]).is_equal("L'héritier — difficile · 1 tâche manquée")
	assert_str((ending.find_child("Recap", true, false) as Label).text).contains("Le cultivateur")
	# The rejection is the outcome, not one more failure of the family.
	assert_int(int(ending.call("inherited_failures"))).is_equal(1)
	var stats := String(ending.call("get_stats_text"))
	assert_str(stats).contains("Échecs en chemin : 1")
	assert_str(stats).contains("Voix au conseil : 5 / %d" % Campaign.SUPPORT_NEEDED)


func test_an_unfinished_generation_and_a_missing_score_are_said_plainly() -> void:
	var ending := await _spawn_ending()

	var lines: PackedStringArray = ending.call("get_recap_lines")

	assert_str(lines[0]).is_equal("Le marron — inachevée")
	assert_str(String(ending.call("get_stats_text"))).not_contains("Voix")
	assert_int(int(ending.call("inherited_failures"))).is_equal(0)


func test_several_missed_tasks_are_counted_in_the_plural() -> void:
	Campaign.complete_task("listen", 3)
	Campaign.complete_task("assess", 3)
	Campaign.fail_task("choose_plan", "a", 3)
	Campaign.fail_task("become_mayor", "b", 3)
	var ending := await _spawn_ending()

	assert_str((ending.call("get_recap_lines") as PackedStringArray)[2]) \
		.contains("2 tâches manquées")


func test_the_epilogue_offers_the_menu_or_a_new_story() -> void:
	var swaps: Array[String] = []
	SceneRouter.scene_changer = func(path: String) -> Error:
		swaps.append(path)
		return OK
	SceneRouter.fade_time = 0.01
	var ending := await _spawn_ending()
	var menu: Button = ending.find_child("MenuButton", true, false)
	var new_game: Button = ending.find_child("NewGameButton", true, false)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu)
	Campaign.finished = true
	Campaign.current_map = 3

	new_game.pressed.emit()
	await SceneRouter.transition_finished

	assert_array(swaps).is_equal([SceneRouter.GAME_SCENE])
	assert_int(Campaign.current_map).is_equal(1)
	assert_bool(Campaign.finished).is_false()
	SceneRouter.scene_changer = Callable()
	SceneRouter.fade_time = SceneRouter.FADE_TIME
	SceneRouter.is_gameplay = false
	GameState.playing = false
	DayNightCycle.running = false
	DayNightCycle.tint_enabled = false
	SaveGame.delete_save()


func test_the_longest_epilogue_fits_the_smallest_supported_window() -> void:
	# Worst case: every optional line is present.
	Campaign.set_choice("map3_plan", "tourism")
	Campaign.set_choice("map3_support", "2")
	for index: int in 4:
		Campaign.record_setback("Repéré %d" % index, 1)
	Campaign.fail_task("earn_100", "Jour 6 passé", 2)
	Campaign.fail_task("become_mayor", "rejeté", 3)
	var ending := await _spawn_ending()
	ending.size = Vector2(1152, 648)
	await get_tree().process_frame
	await get_tree().process_frame

	var panel: PanelContainer = ending.find_children("*", "PanelContainer", true, false)[0]
	assert_float(panel.size.y).override_failure_message(
		"The epilogue panel is %d px tall" % int(panel.size.y)).is_less_equal(648.0)
	assert_float(panel.size.x).is_less_equal(1152.0)
