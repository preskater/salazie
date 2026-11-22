extends GdUnitTestSuite


func before_test() -> void:
	GameState.playing = false
	GameState.farm_active = true
	Campaign.reset()


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	GameState.farm_active = true
	if get_tree() != null:
		get_tree().paused = false


func _complete_map_one(except := "") -> void:
	for definition: Dictionary in Campaign.TASKS[1]:
		var task_id := String(definition.get("id", ""))
		if task_id == except:
			continue
		Campaign.complete_task(task_id, 1)


func test_each_generation_starts_with_pending_tasks() -> void:
	assert_int(Campaign.current_map).is_equal(1)
	for map_id: int in Campaign.MAP_ORDER:
		var summary := Campaign.map_summary(map_id)
		var expected := 4 if map_id == 1 else (5 if map_id == 2 else 4)
		assert_int(int(summary["pending"])).override_failure_message(
			"Map %d should start with its required tasks pending" % map_id).is_equal(expected)
		if map_id == 1:
			assert_int(int(summary.get("optional_pending", 0))).is_equal(1)
		assert_int(int(summary["done"])).is_equal(0)
		assert_int(int(summary["failed"])).is_equal(0)


func test_multi_step_task_completes_at_its_target() -> void:
	assert_bool(Campaign.add_task_progress("find_food", 1)).is_false()
	assert_int(Campaign.task_progress("find_food")).is_equal(1)
	assert_bool(Campaign.add_task_progress("find_food", 2)).is_true()
	assert_int(Campaign.task_status("find_food")).is_equal(Campaign.TaskStatus.DONE)
	assert_int(Campaign.task_progress("find_food")).is_equal(3)


func test_failure_history_survives_completion() -> void:
	assert_bool(Campaign.fail_task("find_food", "Repéré par une patrouille")).is_true()
	assert_int(Campaign.task_status("find_food")).is_equal(Campaign.TaskStatus.FAILED)
	assert_int(Campaign.task_failure_count("find_food")).is_equal(1)
	assert_str(Campaign.task_last_failure("find_food")).is_equal("Repéré par une patrouille")
	assert_bool(Campaign.retry_task("find_food")).is_false()

	assert_bool(Campaign.complete_task("find_food")).is_true()
	assert_int(Campaign.task_status("find_food")).is_equal(Campaign.TaskStatus.DONE)
	assert_int(Campaign.task_failure_count("find_food")).is_equal(1)
	assert_int(Campaign.task_attempts("find_food")).is_equal(2)


func test_map_resolves_with_a_mix_of_done_and_failed_tasks() -> void:
	_complete_map_one("find_water")
	var resolved_events: Array[int] = []
	Campaign.map_resolved.connect(func(map_id: int, _summary: Dictionary) -> void:
		if map_id == 1:
			resolved_events.append(map_id))
	Campaign.fail_task("find_water", "Repéré avant d'avoir pu boire")

	var summary := Campaign.map_summary(1)
	assert_bool(Campaign.is_map_resolved()).is_true()
	assert_int(int(summary["done"])).is_equal(4)
	assert_int(int(summary["failed"])).is_equal(1)
	assert_int(int(summary["pending"])).is_equal(0)
	assert_str(String(summary["rank"])).is_equal("partial")
	assert_int(Campaign.failure_events_for_map(1)).is_equal(1)
	assert_int(resolved_events.size()).is_equal(1)


func test_advancing_changes_the_scene_to_the_next_generation() -> void:
	_complete_map_one()
	assert_bool(Campaign.advance_to_next_map()).is_true()
	assert_int(Campaign.current_map).is_equal(2)
	assert_str(Campaign.current_scene_path()).is_equal("res://scenes/maps/farm.tscn")
	assert_str(Campaign.map_title()).is_equal("Le cultivateur")


func test_map_one_failures_reduce_the_farmer_starting_money() -> void:
	Campaign.fail_task("find_food", "Repéré")
	Campaign.fail_task("find_water", "Repéré encore")

	assert_int(Campaign.starting_money_for_map(2)).is_equal(20)


func test_map_two_failures_reduce_the_heritage() -> void:
	GameState.money = 100
	Campaign.fail_task("earn_100", "Délai dépassé", 2)

	assert_int(Campaign.heritage_for_map3()).is_equal(90)


func test_inherited_support_drops_with_failures() -> void:
	assert_int(Campaign.mayor_support()).is_equal(Campaign.SUPPORT_START)

	var failures: Array[String] = ["find_food", "find_water", "reach_refuge"]
	for i in failures.size():
		Campaign.fail_task(failures[i], "Échec %d" % i, 1)

	assert_int(Campaign.mayor_support()).is_equal(Campaign.SUPPORT_START - 3)
	assert_int(int(Campaign.support_breakdown()["inherited"])).is_equal(2)

	Campaign.fail_task("earn_100", "a", 2)
	Campaign.record_setback("b", 2)
	Campaign.record_setback("c", 2)
	assert_int(int(Campaign.support_breakdown()["inherited"])).is_equal(0)


func test_a_flawless_family_still_has_to_act_in_the_village() -> void:
	# Regression (#26): the vote was decided before Map 3 loaded.
	assert_bool(Campaign.has_mayor_support()).is_false()

	Campaign.set_choice("funded_foret", "1")

	assert_int(Campaign.mayor_support()).is_equal(Campaign.SUPPORT_NEEDED)
	assert_bool(Campaign.has_mayor_support()).is_true()


func test_every_village_action_is_one_voice() -> void:
	for site_id: String in Campaign.FRAGILE_SITES:
		Campaign.set_choice("funded_" + site_id, "1")
	assert_int(int(Campaign.support_breakdown()["sites"])).is_equal(3)

	for index: int in Campaign.RESIDENT_COUNT - 1:
		Campaign.set_choice("listened_%d" % index, "1")
	assert_int(Campaign.residents_heard()).is_equal(4)
	assert_int(int(Campaign.support_breakdown()["residents"])).is_equal(0)
	Campaign.set_choice("listened_last", "1")
	assert_int(int(Campaign.support_breakdown()["residents"])).is_equal(1)

	Campaign.set_choice("visited_belvedere", "1")
	assert_int(int(Campaign.support_breakdown()["landmarks"])).is_equal(0)
	Campaign.set_choice("visited_jardin", "1")
	assert_int(int(Campaign.support_breakdown()["landmarks"])).is_equal(1)

	var breakdown := Campaign.support_breakdown()
	assert_int(int(breakdown["total"])).is_equal(Campaign.SUPPORT_START + 5)
	assert_int(int(breakdown["needed"])).is_equal(Campaign.SUPPORT_NEEDED)


func test_a_plan_is_coherent_with_what_the_heir_did() -> void:
	assert_bool(Campaign.plan_is_coherent()).is_false()

	Campaign.set_choice("map3_plan", "forest")
	assert_bool(Campaign.plan_is_coherent()).is_false()
	Campaign.set_choice("funded_berge", "1")
	assert_bool(Campaign.plan_is_coherent()).is_true()
	assert_int(int(Campaign.support_breakdown()["coherence"])).is_equal(1)

	Campaign.set_choice("map3_plan", "farms")
	assert_bool(Campaign.plan_is_coherent()).is_false()
	Campaign.set_choice("funded_marche", "1")
	assert_bool(Campaign.plan_is_coherent()).is_true()

	Campaign.set_choice("map3_plan", "tourism")
	assert_bool(Campaign.plan_is_coherent()).is_false()
	Campaign.set_choice("visited_belvedere", "1")
	Campaign.set_choice("visited_jardin", "1")
	assert_bool(Campaign.plan_is_coherent()).is_true()

	Campaign.set_choice("map3_plan", "casino")
	assert_bool(Campaign.plan_is_coherent()).is_false()


func test_a_hard_family_history_can_still_be_won_back() -> void:
	Campaign.record_setback("a", 1)
	Campaign.record_setback("b", 1)
	Campaign.fail_task("earn_100", "Le délai est passé", 2)
	assert_int(Campaign.mayor_support()).is_equal(2)

	Campaign.set_choice("map3_plan", "forest")
	for site_id: String in Campaign.FRAGILE_SITES:
		Campaign.set_choice("funded_" + site_id, "1")

	assert_int(Campaign.mayor_support()).is_equal(6)
	assert_bool(Campaign.has_mayor_support()).is_true()


func test_round_trip_keeps_tasks_failures_and_results() -> void:
	Campaign.add_task_progress("find_food", 2)
	Campaign.fail_task("find_water", "Repéré")
	Campaign.set_choice("map3_plan", "forest")
	var payload := Campaign.to_dict()

	Campaign.reset()
	assert_int(Campaign.task_progress("find_food")).is_equal(0)
	assert_bool(Campaign.from_dict(payload)).is_true()

	assert_int(Campaign.task_progress("find_food")).is_equal(2)
	assert_int(Campaign.task_status("find_water")).is_equal(Campaign.TaskStatus.FAILED)
	assert_int(Campaign.task_failure_count("find_water")).is_equal(1)
	assert_str(Campaign.get_choice("map3_plan")).is_equal("forest")


func test_legacy_v1_save_unlocks_the_farm_without_escape_tasks() -> void:
	GameState.money = 120
	assert_bool(Campaign.from_dict({"legacy_v1": true, "current_map": 2})).is_true()

	assert_int(Campaign.current_map).is_equal(2)
	for definition: Dictionary in Campaign.TASKS[1]:
		assert_int(Campaign.task_status(String(definition["id"]), 1)).is_equal(Campaign.TaskStatus.DONE)
	assert_int(Campaign.task_status("earn_100", 2)).is_equal(Campaign.TaskStatus.DONE)


func test_old_map_two_save_gets_the_river_task_done() -> void:
	var payload := {
		"current_map": 2,
		"tasks": {
			1: {
				"find_food": {"status": Campaign.TaskStatus.DONE, "progress": 3},
				"find_water": {"status": Campaign.TaskStatus.DONE, "progress": 1},
				"hide_from_patrol": {"status": Campaign.TaskStatus.DONE, "progress": 1},
				"cross_patrol": {"status": Campaign.TaskStatus.DONE, "progress": 1},
				"reach_refuge": {"status": Campaign.TaskStatus.DONE, "progress": 1},
			},
		},
	}
	assert_bool(Campaign.from_dict(payload)).is_true()

	assert_int(Campaign.current_map).is_equal(2)
	assert_int(Campaign.task_status("follow_river", 1)).is_equal(Campaign.TaskStatus.DONE)


func test_optional_seed_task_does_not_block_map_one() -> void:
	_complete_map_one("gather_seeds")

	assert_bool(Campaign.is_map_resolved(1)).is_true()
	assert_int(Campaign.task_status("gather_seeds")).is_equal(Campaign.TaskStatus.PENDING)


func test_bonus_seeds_are_applied_when_map_two_starts() -> void:
	GameState.playing = true
	Campaign.add_bonus_seed("corn", 3)
	Campaign.add_bonus_seed("carrot", 1)

	SceneRouter._prepare_map_entry(2)

	assert_int(GameState.seed_count("corn")).is_equal(
		int(GameState.START_SEEDS["corn"]) + 3)
	assert_int(GameState.seed_count("carrot")).is_equal(
		int(GameState.START_SEEDS["carrot"]) + 1)
	GameState.reset()
	DayNightCycle.nights_required_for_next_map = 2
	DayNightCycle.nights_spent = 0


func test_setbacks_weigh_on_the_generation_but_are_capped() -> void:
	assert_int(Campaign.record_setback("Repéré", 1)).is_equal(1)
	assert_int(Campaign.setbacks_for_map(1)).is_equal(1)
	assert_int(Campaign.failure_events_for_map(1)).is_equal(1)
	assert_int(Campaign.starting_money_for_map(2)).is_equal(25)

	for index: int in 5:
		Campaign.record_setback("Repéré %d" % index, 1)

	assert_int(Campaign.setbacks_for_map(1)).is_equal(6)
	assert_int(Campaign.failure_events_for_map(1)).is_equal(Campaign.SETBACK_CAP)
	assert_int(Campaign.starting_money_for_map(2)).is_equal(20)
	assert_int(Campaign.mayor_support()).is_equal(Campaign.SUPPORT_START - Campaign.SETBACK_CAP)


func test_setback_announces_itself_and_defaults_to_the_current_map() -> void:
	var seen: Array = []
	var listener := func(map_id: int, count: int) -> void: seen.append([map_id, count])
	Campaign.setback_recorded.connect(listener)
	Campaign.current_map = 2

	Campaign.record_setback("Récolte perdue")

	Campaign.setback_recorded.disconnect(listener)
	assert_array(seen).is_equal([[2, 1]])
	assert_int(Campaign.setbacks_for_map(1)).is_equal(0)
	assert_int(Campaign.setbacks_for_map()).is_equal(1)


func test_setbacks_make_a_finished_generation_partial() -> void:
	_complete_map_one()
	assert_str(String(Campaign.map_summary(1)["rank"])).is_equal("full")

	Campaign.record_setback("Repéré", 1)

	assert_str(String(Campaign.map_summary(1)["rank"])).is_equal("partial")
	# The stored result follows, since the map was already resolved.
	assert_str(String(Campaign.results[1]["rank"])).is_equal("partial")
	assert_int((Campaign.map_summary(1)["setbacks"] as Array).size()).is_equal(1)


func test_setbacks_across_generations_can_cost_the_election() -> void:
	Campaign.record_setback("a", 1)
	Campaign.record_setback("b", 1)
	Campaign.fail_task("earn_100", "Le délai est passé", 2)

	assert_int(Campaign.total_failure_events()).is_equal(3)
	assert_int(Campaign.mayor_support()).is_equal(2)
	# One funded site is no longer enough for this family.
	Campaign.set_choice("funded_foret", "1")
	assert_bool(Campaign.has_mayor_support()).is_false()


func test_setbacks_survive_a_json_round_trip_and_a_reset_clears_them() -> void:
	Campaign.record_setback("Repéré par une patrouille", 1)
	Campaign.record_setback("Effondré", 1)
	var payload: Dictionary = JSON.parse_string(JSON.stringify(Campaign.to_dict()))

	Campaign.reset()
	assert_int(Campaign.setbacks_for_map(1)).is_equal(0)
	assert_bool(Campaign.from_dict(payload)).is_true()

	assert_int(Campaign.setbacks_for_map(1)).is_equal(2)
	assert_str(String(Campaign.setbacks[1][0]["reason"])).is_equal("Repéré par une patrouille")


func test_malformed_setbacks_are_ignored_on_load() -> void:
	var payload := Campaign.to_dict()
	payload["setbacks"] = {"1": "oops", "9": [{"reason": "x"}], "two": [], "2": [42, {"reason": "ok"}]}

	assert_bool(Campaign.from_dict(payload)).is_true()

	assert_int(Campaign.setbacks_for_map(1)).is_equal(0)
	assert_int(Campaign.setbacks_for_map(2)).is_equal(1)
	assert_bool(Campaign.setbacks.has(9)).is_false()

	payload["setbacks"] = "nope"
	assert_bool(Campaign.from_dict(payload)).is_true()
	assert_bool(Campaign.setbacks.is_empty()).is_true()
