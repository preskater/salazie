extends GdUnitTestSuite

const RESULT_SCENE := preload("res://scenes/ui/tasks/generation_result.tscn")


func before_test() -> void:
	GameState.playing = false
	Campaign.reset()


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	if get_tree() != null:
		get_tree().paused = false


func test_result_lists_every_task_and_pauses_the_game() -> void:
	for definition: Dictionary in Campaign.TASKS[1]:
		Campaign.complete_task(String(definition["id"]))
	var result: GenerationResult = RESULT_SCENE.instantiate()
	add_child(auto_free(result))
	await get_tree().process_frame

	result.show_result(Campaign.map_summary(), "Prochaine génération : Le cultivateur", "20 G")

	assert_bool(result.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_str(result.get_title_text()).contains("Le marron")
	assert_int(result.get_row_texts().size()).is_equal(6)
	assert_str(result.get_row_texts()[0]).starts_with("✓")

	result.close()
	assert_bool(result.visible).is_false()
	assert_bool(get_tree().paused).is_false()
