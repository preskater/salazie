extends GdUnitTestSuite

const TASK_LIST_SCENE := preload("res://game/ui/tasks/task_list.tscn")


func before_test() -> void:
	GameState.playing = false
	Campaign.reset()


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	if get_tree() != null:
		get_tree().paused = false


func _spawn() -> TaskList:
	var list: TaskList = TASK_LIST_SCENE.instantiate()
	add_child(auto_free(list))
	return list


func test_task_list_starts_with_every_task_pending() -> void:
	var list := _spawn()
	await get_tree().process_frame

	assert_str(list.get_compact_text()).contains("0 faites")
	var rows := list.get_row_texts()
	assert_int(rows.size()).is_equal(5)
	assert_str(rows[0]).starts_with("○ Trouver de la nourriture")


func test_progress_and_done_rows_are_refreshed_by_signals() -> void:
	var list := _spawn()
	await get_tree().process_frame

	Campaign.add_task_progress("find_food", 1)
	var rows := list.get_row_texts()
	assert_str(rows[0]).contains("(1/3)")

	Campaign.add_task_progress("find_food", 2)
	rows = list.get_row_texts()
	assert_str(rows[0]).starts_with("✓ Trouver de la nourriture")


func test_failed_row_shows_reason_and_retry_hint() -> void:
	var list := _spawn()
	await get_tree().process_frame

	Campaign.fail_task("cross_patrol", "Repéré par une patrouille")
	var rows := list.get_row_texts()
	var found := false
	for row: String in rows:
		if row.begins_with("✗ Traverser la zone patrouillée"):
			found = true
			assert_str(row).contains("Repéré par une patrouille")
			assert_str(row).contains("[Réessayer]")
	assert_bool(found).override_failure_message("Failed task row was not rendered").is_true()
	assert_str(list.get_compact_text()).contains("1 échouées")


func test_resolved_map_shows_the_generation_result() -> void:
	var list := _spawn()
	await get_tree().process_frame

	for definition: Dictionary in Campaign.TASKS[1]:
		Campaign.complete_task(String(definition["id"]))
	await get_tree().process_frame

	assert_bool(list.is_expanded()).is_true()
	assert_str(list.get_compact_text()).contains("carte terminée")
	assert_str(list.get_result_text()).contains("Génération accomplie")


func test_toggle_tasks_opens_and_closes_the_panel() -> void:
	var list := _spawn()
	await get_tree().process_frame
	assert_bool(list.is_expanded()).is_false()

	var event := InputEventAction.new()
	event.action = "toggle_tasks"
	event.pressed = true
	list.call("_unhandled_input", event)
	assert_bool(list.is_expanded()).is_true()

	list.call("_unhandled_input", event)
	assert_bool(list.is_expanded()).is_false()
