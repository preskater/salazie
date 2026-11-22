extends GdUnitTestSuite
## The task list and the generation report: what each row says, when the list
## opens by itself and what the report does to the pause.

const TASK_LIST_SCENE := preload("res://scenes/ui/tasks/task_list.tscn")
const RESULT_SCENE := preload("res://scenes/ui/tasks/generation_result.tscn")


func before_test() -> void:
	GameState.playing = false
	Campaign.reset()


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	if get_tree() != null:
		get_tree().paused = false


func _spawn_list() -> TaskList:
	var list: TaskList = TASK_LIST_SCENE.instantiate()
	add_child(auto_free(list))
	return list


func _spawn_result() -> GenerationResult:
	var result: GenerationResult = RESULT_SCENE.instantiate()
	add_child(auto_free(result))
	return result


func _row(rows: PackedStringArray, label: String) -> String:
	for row: String in rows:
		if row.contains(label):
			return row
	return ""


func _complete_map(map_id: int, except: Array[String] = []) -> void:
	for definition: Dictionary in Campaign.TASKS[map_id]:
		var task_id := String(definition["id"])
		if not except.has(task_id):
			Campaign.complete_task(task_id, map_id)


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


# --- Task list -------------------------------------------------------------------

func test_a_list_outside_the_tree_shows_nothing() -> void:
	var list: TaskList = auto_free(TASK_LIST_SCENE.instantiate())

	list.refresh()

	assert_str(list.get_compact_text()).is_empty()
	assert_str(list.get_result_text()).is_empty()
	assert_int(list.get_row_texts().size()).is_equal(0)
	assert_bool(list.is_expanded()).is_false()


func test_the_list_can_be_expanded_and_collapsed_from_code() -> void:
	var list := _spawn_list()
	var box: Control = list.find_child("ExpandedBox", true, false)
	assert_bool(box.visible).is_false()

	list.set_expanded(true)
	assert_bool(list.is_expanded()).is_true()
	assert_bool(box.visible).is_true()

	list.set_expanded(false)
	assert_bool(list.is_expanded()).is_false()
	assert_bool(box.visible).is_false()


func test_an_optional_task_says_so_on_its_row() -> void:
	var list := _spawn_list()

	var rows := list.get_row_texts()
	assert_str(_row(rows, "Ramasser des graines sauvages")).is_equal(
		"○ Ramasser des graines sauvages (0/3) (optionnel)")
	assert_str(_row(rows, "Boire à la rivière")).is_equal("○ Boire à la rivière")

	Campaign.complete_task("gather_seeds")
	assert_str(_row(list.get_row_texts(), "Ramasser des graines sauvages")).is_equal(
		"✓ Ramasser des graines sauvages (optionnel)")


func test_a_task_won_after_a_failure_keeps_the_failure_on_its_row() -> void:
	var list := _spawn_list()
	Campaign.fail_task("find_water", "Rivière gardée")

	Campaign.complete_task("find_water")

	assert_str(_row(list.get_row_texts(), "Boire à la rivière")).is_equal(
		"✓ Boire à la rivière (1 échec)")
	assert_str(list.get_compact_text()).contains("1 faites · 0 échouées")


func test_several_failures_of_a_loaded_save_are_counted_on_the_row() -> void:
	var list := _spawn_list()
	Campaign.from_dict({"current_map": 1, "tasks": {1: {"find_water": {
		"status": Campaign.TaskStatus.DONE, "progress": 1,
		"failures": [{"reason": "Repéré"}, {"reason": "Repéré encore"}]}}}})

	list.refresh()

	assert_str(_row(list.get_row_texts(), "Boire à la rivière")).is_equal(
		"✓ Boire à la rivière (2 échecs)")


func test_a_failure_without_reason_shows_only_the_task() -> void:
	var list := _spawn_list()

	Campaign.fail_task("find_water")

	assert_str(_row(list.get_row_texts(), "Boire à la rivière")).is_equal("✗ Boire à la rivière")


func test_the_list_names_the_next_objective() -> void:
	var list := _spawn_list()
	assert_str(list.get_result_text()).is_equal(
		"Objectif en cours : Quittez la plage et remontez l'estuaire jusqu'au premier pont.")

	Campaign.complete_task("follow_river")

	assert_str(list.get_result_text()).is_equal("Objectif en cours : Buvez au bassin, sous la cascade.")


func test_a_failed_task_is_skipped_by_the_objective() -> void:
	var list := _spawn_list()

	Campaign.fail_task("follow_river", "Perdu")

	assert_str(list.get_result_text()).contains("Buvez au bassin")


func test_the_objective_names_the_key_of_the_device_in_use() -> void:
	Campaign.current_map = 2
	var list := _spawn_list()

	var text := list.get_result_text()
	assert_str(text).starts_with("Objectif en cours : Préparez une parcelle du potager (")
	assert_str(text).contains(InputHints.label(&"interact"))
	assert_bool(text.contains("{")).is_false()


func test_changing_generation_collapses_the_list_and_shows_the_new_tasks() -> void:
	var list := _spawn_list()
	list.set_expanded(true)

	Campaign.advance_to_next_map()

	assert_bool(list.is_expanded()).is_false()
	var rows := list.get_row_texts()
	assert_int(rows.size()).is_equal(5)
	assert_str(rows[0]).is_equal("○ Préparer une parcelle")
	assert_str(list.get_compact_text()).contains("5 en cours")


func test_a_reopened_map_goes_back_to_its_objective() -> void:
	_complete_map(1)
	var list := _spawn_list()
	assert_str(list.get_compact_text()).contains("carte terminée")
	# A task reopened by hand (a save edit) before the campaign announces it.
	Campaign.tasks[1]["find_water"]["status"] = Campaign.TaskStatus.PENDING

	# Another generation reopening is none of this list's business.
	Campaign.map_unresolved.emit(2)
	assert_str(list.get_compact_text()).contains("carte terminée")

	Campaign.map_unresolved.emit(1)

	assert_str(list.get_compact_text()).contains("4 faites · 0 échouées · 1 en cours")
	assert_str(list.get_result_text()).contains("Buvez au bassin")
	assert_str(_row(list.get_row_texts(), "Boire à la rivière")).starts_with("○")


func test_the_task_key_is_ignored_while_the_game_is_paused() -> void:
	var list := _spawn_list()
	get_tree().paused = true

	list._unhandled_input(_press(&"toggle_tasks"))
	assert_bool(list.is_expanded()).is_false()

	get_tree().paused = false
	list._unhandled_input(_press(&"toggle_tasks"))
	assert_bool(list.is_expanded()).is_true()


func test_another_key_does_not_open_the_list() -> void:
	var list := _spawn_list()

	list._unhandled_input(_press(&"interact"))

	assert_bool(list.is_expanded()).is_false()


func test_the_list_opens_by_itself_on_a_map_already_resolved() -> void:
	_complete_map(1, ["gather_seeds"])

	var list := _spawn_list()

	assert_bool(list.is_expanded()).is_true()
	assert_bool((list.find_child("ExpandedBox", true, false) as Control).visible).is_true()
	assert_str(list.get_result_text()).starts_with("Génération accomplie — 4 réussies · 0 échouée\n")


func test_the_list_stays_closed_when_another_generation_is_resolved() -> void:
	var list := _spawn_list()

	_complete_map(2)

	assert_bool(list.is_expanded()).is_false()
	assert_str(list.get_compact_text()).contains("0 faites")


func test_a_partial_generation_is_named_with_its_next_step() -> void:
	var list := _spawn_list()
	Campaign.fail_task("find_water", "Rivière gardée")

	_complete_map(1, ["find_water"])

	assert_bool(list.is_expanded()).is_true()
	assert_str(list.get_result_text()).is_equal(
		"Génération partielle — 4 réussies · 1 échouée\nProchaine génération : Le cultivateur")
	assert_str(list.get_compact_text()).contains("4 réussies · 1 échouées · carte terminée")


func test_a_poor_last_generation_points_at_the_epilogue() -> void:
	Campaign.current_map = 3
	var list := _spawn_list()
	Campaign.complete_task("listen")
	Campaign.fail_task("assess", "Zones ignorées")
	Campaign.fail_task("choose_plan", "Aucun plan")

	Campaign.fail_task("become_mayor", "Le conseil a rejeté le plan")

	assert_str(list.get_result_text()).is_equal(
		"Génération difficile — 1 réussie · 3 échouées\nÉpilogue de Salazie")
	assert_str(_row(list.get_row_texts(), "Convaincre le conseil")).is_equal(
		"✗ Convaincre le conseil — Le conseil a rejeté le plan")


# --- Generation report --------------------------------------------------------------

func test_a_report_outside_the_tree_is_empty() -> void:
	var result: GenerationResult = auto_free(RESULT_SCENE.instantiate())

	assert_str(result.get_title_text()).is_empty()
	assert_int(result.get_row_texts().size()).is_equal(0)


func test_the_report_starts_hidden_and_leaves_the_game_running() -> void:
	var result := _spawn_result()

	assert_bool(result.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_bool(result.is_in_group("generation_result")).is_true()


func test_the_report_tells_each_task_outcome() -> void:
	Campaign.fail_task("follow_river", "Rivière gardée")
	Campaign.complete_task("follow_river")
	Campaign.fail_task("find_water", "Bassin à sec")
	Campaign.fail_task("find_food")
	Campaign.complete_task("reach_refuge")
	var result := _spawn_result()

	result.show_result(Campaign.map_summary())

	assert_array(Array(result.get_row_texts())).contains_exactly([
		"✓ Trouver la rivière (1 échec)",
		"✗ Boire à la rivière — Bassin à sec",
		"✗ Rassembler des vivres",
		"✓ Rejoindre le refuge du col",
		"○ Ramasser des graines sauvages",
	])
	var subtitle: Label = result.find_child("Subtitle", true, false)
	assert_str(subtitle.text).is_equal("Génération partielle — 2 réussies · 2 échouées")
	result.close()


func test_the_report_counts_several_failures_of_a_task() -> void:
	var summary := Campaign.map_summary()
	summary["tasks"]["find_water"]["status"] = Campaign.TaskStatus.DONE
	summary["tasks"]["find_water"]["failures"] = [{"reason": "a"}, {"reason": "b"}]
	var result := _spawn_result()

	result.show_result(summary)

	assert_str(_row(result.get_row_texts(), "Boire à la rivière")).is_equal(
		"✓ Boire à la rivière (2 échecs)")
	result.close()


func test_the_report_names_every_rank() -> void:
	var result := _spawn_result()
	var subtitle: Label = result.find_child("Subtitle", true, false)

	result.show_result({"map": 3, "title": "L'héritier", "rank": "poor", "done": 1, "failed": 1})
	assert_str(subtitle.text).is_equal("Génération difficile — 1 réussie · 1 échouée")
	assert_str(result.get_title_text()).is_equal("Map 3 — L'héritier")

	result.show_result({"map": 1, "rank": "full", "done": 5, "failed": 0})
	assert_str(subtitle.text).is_equal("Génération accomplie — 5 réussies · 0 échouée")

	# A generation still in progress has no rank to boast about.
	result.show_result(Campaign.map_summary())
	assert_str(subtitle.text).is_equal("Génération terminée — 0 réussie · 0 échouée")
	result.close()


func test_a_second_report_replaces_the_rows_of_the_first() -> void:
	var result := _spawn_result()
	Campaign.record_setback("Repéré", 1)
	result.show_result(Campaign.map_summary(1))
	assert_int(result.get_row_texts().size()).is_equal(6)

	result.show_result(Campaign.map_summary(3))

	var rows := result.get_row_texts()
	assert_int(rows.size()).is_equal(4)
	assert_str(rows[0]).is_equal("○ Écouter les habitants")
	assert_object(result.find_child("SetbackRow", true, false)).is_null()
	result.close()


func test_a_result_saved_before_a_task_existed_skips_that_task() -> void:
	var summary := Campaign.map_summary(1)
	(summary["tasks"] as Dictionary).erase("follow_river")
	var result := _spawn_result()

	result.show_result(summary)

	var rows := result.get_row_texts()
	assert_int(rows.size()).is_equal(4)
	assert_str(rows[0]).is_equal("○ Boire à la rivière")
	result.close()


func test_the_footer_joins_the_next_step_and_the_note() -> void:
	var result := _spawn_result()
	var footer: Label = result.find_child("Footer", true, false)

	result.show_result(Campaign.map_summary(), "Prochaine génération : Le cultivateur", "20 G")
	assert_str(footer.text).is_equal("Prochaine génération : Le cultivateur\n20 G")

	result.show_result(Campaign.map_summary(), "", "20 G")
	assert_str(footer.text).is_equal("20 G")

	result.show_result(Campaign.map_summary())
	assert_str(footer.text).is_empty()
	result.close()


func test_continue_closes_the_report_and_confirms_once() -> void:
	var result := _spawn_result()
	var confirmations: Array[int] = []
	result.confirmed.connect(func() -> void: confirmations.append(1))
	result.show_result(Campaign.map_summary())
	var button: Button = result.find_child("ContinueButton", true, false)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(button)
	assert_bool(get_tree().paused).is_true()

	button.pressed.emit()

	assert_int(confirmations.size()).is_equal(1)
	assert_bool(result.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_the_report_leaves_a_pause_it_did_not_start() -> void:
	var result := _spawn_result()
	get_tree().paused = true

	result.show_result(Campaign.map_summary())
	result.close()

	assert_bool(result.visible).is_false()
	assert_bool(get_tree().paused).is_true()
