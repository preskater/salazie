extends GdUnitTestSuite
## Campaign rules that the first suite leaves aside: refused task changes, the
## generation ranks, the end of the campaign and what a damaged save may hold.

var _recorders: Array[Dictionary] = []


func before_test() -> void:
	GameState.playing = false
	GameState.reset()
	GameState.farm_active = true
	Campaign.reset()


func after_test() -> void:
	for recorder: Dictionary in _recorders:
		(recorder["signal"] as Signal).disconnect(recorder["callable"] as Callable)
	_recorders.clear()
	Campaign.reset()
	GameState.playing = false
	GameState.reset()
	GameState.farm_active = true
	if get_tree() != null:
		get_tree().paused = false


## Returns an array that receives the arguments of every emission of `source`.
func _record(source: Signal) -> Array:
	var calls: Array = []
	var callable := func(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
		calls.append([a, b, c])
	source.connect(callable)
	_recorders.append({"signal": source, "callable": callable})
	return calls


func _complete_map(map_id: int, except: Array[String] = []) -> void:
	for definition: Dictionary in Campaign.TASKS[map_id]:
		var task_id := String(definition["id"])
		if not except.has(task_id):
			Campaign.complete_task(task_id, map_id)


# --- Refused task changes -----------------------------------------------------

func test_an_unknown_task_cannot_be_changed() -> void:
	var changes := _record(Campaign.task_status_changed)

	assert_bool(Campaign.complete_task("build_a_casino")).is_false()
	assert_bool(Campaign.add_task_progress("build_a_casino", 2)).is_false()
	assert_bool(Campaign.fail_task("build_a_casino", "Refusé")).is_false()

	assert_array(changes).is_empty()
	assert_dict(Campaign.task_definition("build_a_casino")).is_empty()
	assert_int(Campaign.task_status("build_a_casino")).is_equal(Campaign.TaskStatus.PENDING)
	assert_int(Campaign.task_target("build_a_casino")).is_equal(1)
	assert_bool(Campaign.tasks[1].has("build_a_casino")).is_false()


func test_a_task_of_another_generation_is_unknown_on_this_map() -> void:
	assert_bool(Campaign.complete_task("listen")).is_false()
	assert_bool(Campaign.complete_task("listen", 3)).is_true()

	assert_int(Campaign.task_status("listen", 3)).is_equal(Campaign.TaskStatus.DONE)
	assert_int(Campaign.task_progress("listen", 3)).is_equal(3)
	assert_int(int(Campaign.map_summary(1)["done"])).is_equal(0)


func test_a_done_task_is_final() -> void:
	Campaign.complete_task("find_water")
	var changes := _record(Campaign.task_status_changed)

	assert_bool(Campaign.complete_task("find_water")).is_false()
	assert_bool(Campaign.add_task_progress("find_water", 1)).is_false()
	assert_bool(Campaign.fail_task("find_water", "Trop tard")).is_false()

	assert_array(changes).is_empty()
	assert_int(Campaign.task_status("find_water")).is_equal(Campaign.TaskStatus.DONE)
	assert_int(Campaign.task_attempts("find_water")).is_equal(1)
	assert_int(Campaign.task_failure_count("find_water")).is_equal(0)


func test_a_failed_task_is_not_failed_twice_and_takes_no_progress() -> void:
	Campaign.add_task_progress("find_food", 1)
	Campaign.fail_task("find_food", "Repéré")

	assert_bool(Campaign.fail_task("find_food", "Repéré encore")).is_false()
	assert_bool(Campaign.add_task_progress("find_food", 1)).is_false()

	assert_int(Campaign.task_failure_count("find_food")).is_equal(1)
	assert_str(Campaign.task_last_failure("find_food")).is_equal("Repéré")
	assert_int(Campaign.task_progress("find_food")).is_equal(1)
	assert_int(Campaign.task_attempts("find_food")).is_equal(1)


func test_a_task_without_failure_has_no_last_failure() -> void:
	assert_str(Campaign.task_last_failure("find_food")).is_empty()
	assert_array(Campaign.task_failures("find_food")).is_empty()


func test_negative_progress_never_takes_steps_back() -> void:
	Campaign.add_task_progress("find_food", 2)

	assert_bool(Campaign.add_task_progress("find_food", -5)).is_false()

	assert_int(Campaign.task_progress("find_food")).is_equal(2)


func test_progress_beyond_the_target_is_capped() -> void:
	assert_bool(Campaign.add_task_progress("find_food", 40)).is_true()

	assert_int(Campaign.task_progress("find_food")).is_equal(3)
	assert_int(Campaign.task_target("find_food")).is_equal(3)


func test_a_failure_stays_on_the_record() -> void:
	# A generation that misses its goal keeps the failure: there is no retry.
	for map_id: int in Campaign.MAP_ORDER:
		for definition: Dictionary in Campaign.TASKS[map_id]:
			var task_id := String(definition["id"])
			Campaign.fail_task(task_id, "Échec", map_id)
			assert_int(Campaign.task_status(task_id, map_id)).is_equal(Campaign.TaskStatus.FAILED)


func test_a_missing_map_gets_its_tasks_back() -> void:
	Campaign.tasks.erase(3)

	assert_int(Campaign.task_status("listen", 3)).is_equal(Campaign.TaskStatus.PENDING)
	assert_int(Campaign.task_progress("listen", 3)).is_equal(0)
	assert_bool(Campaign.add_task_progress("listen", 1, 3)).is_false()

	assert_int(Campaign.task_progress("listen", 3)).is_equal(1)
	assert_int((Campaign.tasks[3] as Dictionary).size()).is_equal(Campaign.TASKS[3].size())


func test_map_ids_outside_the_campaign_are_clamped() -> void:
	assert_str(Campaign.map_title(0)).is_equal("Le marron")
	assert_str(Campaign.map_title(9)).is_equal("L'héritier")
	assert_str(Campaign.map_subtitle(2)).is_equal("Deuxième génération")
	assert_int(Campaign.next_map_id(9)).is_equal(0)


# --- Ranks ---------------------------------------------------------------------

func test_a_generation_in_progress_has_no_rank_yet() -> void:
	_complete_map(1, ["reach_refuge"])

	assert_str(String(Campaign.map_summary(1)["rank"])).is_equal("pending")
	assert_bool(Campaign.is_map_resolved(1)).is_false()
	assert_bool(Campaign.is_map_resolved(1)).is_false()


func test_a_flawless_generation_is_full() -> void:
	_complete_map(1)

	assert_str(String(Campaign.map_summary(1)["rank"])).is_equal("full")
	assert_bool(Campaign.is_map_resolved(1)).is_true()


func test_a_failed_ordinary_task_makes_the_generation_partial() -> void:
	Campaign.fail_task("find_water", "Rivière gardée", 1)
	_complete_map(1, ["find_water"])

	var summary := Campaign.map_summary(1)
	assert_str(String(summary["rank"])).is_equal("partial")
	assert_int(int(summary["failed"])).is_equal(1)
	assert_int(int(summary["failure_events"])).is_equal(1)


func test_a_task_won_after_a_failure_still_makes_the_generation_partial() -> void:
	Campaign.fail_task("find_water", "Rivière gardée", 1)
	_complete_map(1)

	var summary := Campaign.map_summary(1)
	assert_int(int(summary["failed"])).is_equal(0)
	assert_str(String(summary["rank"])).is_equal("partial")


func test_a_failed_critical_task_makes_the_generation_poor() -> void:
	Campaign.current_map = 3
	_complete_map(3, ["become_mayor"])
	Campaign.fail_task("become_mayor", "Le conseil a rejeté le plan")

	var summary := Campaign.map_summary()
	assert_str(String(summary["rank"])).is_equal("poor")
	assert_bool(bool(summary["tasks"]["become_mayor"]["critical"])).is_true()
	assert_bool(bool(summary["tasks"]["listen"]["critical"])).is_false()


# --- Resolution ------------------------------------------------------------------

func test_an_unresolved_map_cannot_be_finalised() -> void:
	var resolved := _record(Campaign.map_resolved)
	_complete_map(1, ["reach_refuge"])

	assert_dict(Campaign.finalize_map(1)).is_empty()

	assert_bool(Campaign.results.has(1)).is_false()
	assert_array(resolved).is_empty()


func test_a_resolved_map_is_announced_only_once() -> void:
	var resolved := _record(Campaign.map_resolved)
	_complete_map(1, ["gather_seeds"])
	assert_int(resolved.size()).is_equal(1)

	var summary := Campaign.finalize_map(1)
	Campaign.finalize_map(1)
	# The optional task ends after the map was resolved.
	Campaign.complete_task("gather_seeds", 1)

	assert_int(resolved.size()).is_equal(1)
	assert_int(int(resolved[0][0])).is_equal(1)
	assert_str(String(summary["rank"])).is_equal("full")
	assert_int(int(Campaign.results[1]["done"])).is_equal(5)


func test_finalising_announces_a_map_resolved_outside_the_task_calls() -> void:
	# `tasks` is public: a map can be found resolved without any task call.
	for task_id: String in Campaign.tasks[2]:
		Campaign.tasks[2][task_id]["status"] = Campaign.TaskStatus.DONE
	var resolved := _record(Campaign.map_resolved)

	var summary := Campaign.finalize_map(2)
	Campaign.finalize_map(2)

	assert_int(resolved.size()).is_equal(1)
	assert_int(int(resolved[0][0])).is_equal(2)
	assert_int(int(summary["done"])).is_equal(5)
	assert_int(int(Campaign.results[2]["pending"])).is_equal(0)


func test_a_resolved_map_with_a_reopened_task_is_announced_unresolved() -> void:
	_complete_map(1)
	var unresolved := _record(Campaign.map_unresolved)
	# A task reopened by hand: two tasks pending again.
	Campaign.tasks[1]["find_water"]["status"] = Campaign.TaskStatus.PENDING
	Campaign.tasks[1]["reach_refuge"]["status"] = Campaign.TaskStatus.PENDING

	Campaign.complete_task("find_water", 1)

	assert_int(unresolved.size()).is_equal(1)
	assert_int(int(unresolved[0][0])).is_equal(1)
	assert_bool(Campaign.results.has(1)).is_false()

	# Resolved again: the map is announced a second time.
	var resolved := _record(Campaign.map_resolved)
	Campaign.complete_task("reach_refuge", 1)
	assert_int(resolved.size()).is_equal(1)
	assert_int(unresolved.size()).is_equal(1)
	assert_bool(Campaign.results.has(1)).is_true()


# --- End of the campaign -----------------------------------------------------------

func test_each_generation_leads_to_the_next() -> void:
	var changes := _record(Campaign.map_changed)
	assert_str(Campaign.next_map_label()).is_equal("Prochaine génération : Le cultivateur")

	assert_bool(Campaign.advance_to_next_map()).is_true()
	assert_bool(Campaign.advance_to_next_map()).is_true()

	assert_int(Campaign.current_map).is_equal(3)
	assert_str(Campaign.current_scene_path()).is_equal("res://scenes/maps/heir.tscn")
	assert_bool(Campaign.finished).is_false()
	assert_array(changes).contains_exactly([[2, null, null], [3, null, null]])


func test_the_campaign_ends_after_the_third_generation() -> void:
	Campaign.current_map = 3
	_complete_map(3)
	var changes := _record(Campaign.map_changed)
	assert_str(Campaign.next_map_label()).is_equal("Épilogue de Salazie")

	assert_bool(Campaign.advance_to_next_map()).is_false()

	assert_bool(Campaign.finished).is_true()
	assert_int(Campaign.current_map).is_equal(3)
	assert_array(changes).contains_exactly([[3, null, null]])
	assert_str(String(Campaign.results[3]["rank"])).is_equal("full")


# --- What is handed down --------------------------------------------------------------

func test_the_first_generation_always_starts_with_the_base_purse() -> void:
	Campaign.fail_task("find_water", "Repéré", 1)

	assert_int(Campaign.starting_money_for_map(1)).is_equal(Campaign.BASE_START_MONEY)
	assert_int(Campaign.starting_money_for_map(0)).is_equal(Campaign.BASE_START_MONEY)


func test_the_farmer_never_starts_with_less_than_half_the_purse() -> void:
	assert_int(Campaign.starting_money_for_map(2)).is_equal(30)
	for definition: Dictionary in Campaign.TASKS[1]:
		Campaign.fail_task(String(definition["id"]), "Repéré", 1)
	Campaign.record_setback("Effondré", 1)
	Campaign.record_setback("Effondré", 1)

	assert_int(Campaign.failure_events_for_map(1)).is_equal(7)
	assert_int(Campaign.starting_money_for_map(2)).is_equal(15)
	assert_int(Campaign.starting_money_for_map(3)).is_equal(15)


func test_a_ruinous_farm_hands_down_nothing_rather_than_a_debt() -> void:
	GameState.money = 200
	var failures: Array = []
	for index: int in 12:
		failures.append({"reason": "Récolte perdue %d" % index, "at": ""})
	Campaign.from_dict({"current_map": 2, "tasks": {2: {"harvest_crop": {
		"status": Campaign.TaskStatus.FAILED, "failures": failures}}}})

	assert_int(Campaign.failure_events_for_map(2)).is_equal(12)
	assert_int(Campaign.heritage_for_map3()).is_equal(0)


func test_bonus_seeds_only_count_real_crops_and_positive_amounts() -> void:
	Campaign.add_bonus_seed("corn", 2)
	Campaign.add_bonus_seed("corn")
	Campaign.add_bonus_seed("corn", 0)
	Campaign.add_bonus_seed("corn", -4)
	Campaign.add_bonus_seed("dragonfruit", 3)

	assert_dict(Campaign.bonus_seeds).is_equal({"corn": 3})


func test_an_unanswered_choice_gives_the_fallback() -> void:
	assert_str(Campaign.get_choice("map3_plan")).is_empty()
	assert_str(Campaign.get_choice("map3_plan", "farms")).is_equal("farms")

	Campaign.set_choice("map3_plan", "tourism")

	assert_str(Campaign.get_choice("map3_plan", "farms")).is_equal("tourism")
	assert_bool(Campaign.plan_is_coherent()).is_false()


# --- Saves -------------------------------------------------------------------------------

func test_an_empty_save_is_refused_and_leaves_the_campaign_untouched() -> void:
	Campaign.current_map = 2
	Campaign.complete_task("prepare_plot")
	Campaign.set_choice("map3_plan", "forest")

	assert_bool(Campaign.can_restore({})).is_false()
	assert_bool(Campaign.from_dict({})).is_false()

	assert_int(Campaign.current_map).is_equal(2)
	assert_int(Campaign.task_status("prepare_plot")).is_equal(Campaign.TaskStatus.DONE)
	assert_str(Campaign.get_choice("map3_plan")).is_equal("forest")


func test_unknown_maps_and_tasks_of_a_save_are_dropped() -> void:
	var payload := {
		"current_map": 1,
		"tasks": {
			"7": {"find_water": {"status": Campaign.TaskStatus.DONE}},
			"2": "corrompu",
			"1": {
				"hide_from_patrol": {"status": Campaign.TaskStatus.DONE},
				"find_water": "corrompu",
				"find_food": {"status": Campaign.TaskStatus.PENDING, "progress": 2},
			},
		},
	}

	assert_bool(Campaign.from_dict(payload)).is_true()

	assert_array(Campaign.tasks.keys()).contains_exactly_in_any_order([1, 2, 3])
	assert_bool(Campaign.tasks[1].has("hide_from_patrol")).is_false()
	assert_int(Campaign.task_status("find_water", 1)).is_equal(Campaign.TaskStatus.PENDING)
	assert_int(Campaign.task_progress("find_food", 1)).is_equal(2)
	assert_int(int(Campaign.map_summary(2)["pending"])).is_equal(5)


func test_out_of_range_task_values_of_a_save_are_brought_back() -> void:
	var payload := {
		"current_map": 1,
		"tasks": {1: {
			"find_food": {
				"status": 9,
				"progress": -4,
				"attempts": -1,
				"failures": [{"reason": "Repéré", "at": "1848"}, "corrompu", 12, {}],
			},
			"find_water": {"status": -3, "failures": "corrompu"},
		}},
	}

	assert_bool(Campaign.from_dict(payload)).is_true()

	assert_int(Campaign.task_status("find_food")).is_equal(Campaign.TaskStatus.FAILED)
	assert_int(Campaign.task_progress("find_food")).is_equal(0)
	assert_int(Campaign.task_attempts("find_food")).is_equal(0)
	assert_array(Campaign.task_failures("find_food")).contains_exactly([
		{"reason": "Repéré", "at": "1848"}, {"reason": "", "at": ""}])
	assert_str(Campaign.task_last_failure("find_food")).is_empty()
	assert_int(Campaign.task_status("find_water")).is_equal(Campaign.TaskStatus.PENDING)
	assert_array(Campaign.task_failures("find_water")).is_empty()


func test_badly_typed_blocks_of_a_save_fall_back_to_empty() -> void:
	Campaign.set_choice("map3_plan", "forest")
	Campaign.add_bonus_seed("corn", 2)
	var payload := {
		"current_map": 12,
		"tasks": "corrompu",
		"results": [1, 2],
		"choices": "corrompu",
		"bonus_seeds": ["corn"],
		"setbacks": 4,
		"heritage": -50,
		"finished": 1,
	}

	assert_bool(Campaign.from_dict(payload)).is_true()

	assert_int(Campaign.current_map).is_equal(3)
	assert_dict(Campaign.results).is_empty()
	assert_dict(Campaign.choices).is_empty()
	assert_dict(Campaign.bonus_seeds).is_empty()
	assert_dict(Campaign.setbacks).is_empty()
	assert_int(Campaign.heritage).is_equal(0)
	assert_bool(Campaign.finished).is_true()
	assert_int(int(Campaign.map_summary(3)["pending"])).is_equal(4)


func test_saved_bonus_seeds_keep_only_real_crops() -> void:
	assert_bool(Campaign.from_dict({
		"current_map": 1,
		"bonus_seeds": {"corn": 3, "dragonfruit": 8, "tomato": -2},
	})).is_true()

	assert_int(int(Campaign.bonus_seeds["corn"])).is_equal(3)
	assert_bool(Campaign.bonus_seeds.has("dragonfruit")).is_false()
	if GameState.CROPS.has("tomato"):
		assert_int(int(Campaign.bonus_seeds["tomato"])).is_equal(0)


func test_a_loaded_resolved_map_is_not_announced_again() -> void:
	_complete_map(1)
	var payload := Campaign.to_dict()
	Campaign.reset()
	var resolved := _record(Campaign.map_resolved)

	Campaign.from_dict(payload)
	Campaign.finalize_map(1)

	assert_array(resolved).is_empty()
	assert_bool(Campaign.is_map_resolved(1)).is_true()


func test_the_campaign_survives_a_real_json_file_round_trip() -> void:
	_complete_map(1, ["find_water", "gather_seeds"])
	Campaign.fail_task("find_water", "Rivière gardée", 1)
	Campaign.add_task_progress("gather_seeds", 2, 1)
	Campaign.record_setback("Repéré", 1)
	Campaign.add_bonus_seed("corn", 2)
	Campaign.advance_to_next_map()
	Campaign.complete_task("prepare_plot")
	Campaign.set_choice("map3_plan", "tourism")
	Campaign.heritage = 140
	var text := JSON.stringify(Campaign.to_dict())

	Campaign.reset()
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	assert_bool(Campaign.from_dict(parsed as Dictionary)).is_true()

	assert_int(Campaign.current_map).is_equal(2)
	assert_int(Campaign.task_status("find_water", 1)).is_equal(Campaign.TaskStatus.FAILED)
	assert_str(Campaign.task_last_failure("find_water", 1)).is_equal("Rivière gardée")
	assert_int(Campaign.task_attempts("find_water", 1)).is_equal(1)
	assert_int(Campaign.task_progress("gather_seeds", 1)).is_equal(2)
	assert_int(Campaign.task_status("prepare_plot", 2)).is_equal(Campaign.TaskStatus.DONE)
	assert_int(Campaign.setbacks_for_map(1)).is_equal(1)
	assert_int(Campaign.failure_events_for_map(1)).is_equal(2)
	assert_int(Campaign.starting_money_for_map(2)).is_equal(20)
	assert_int(int(Campaign.bonus_seeds["corn"])).is_equal(2)
	assert_str(Campaign.get_choice("map3_plan")).is_equal("tourism")
	assert_int(Campaign.heritage).is_equal(140)
	assert_bool(Campaign.finished).is_false()
	assert_str(String(Campaign.map_summary(1)["rank"])).is_equal("partial")
	# Every status is an integer again, not the float JSON hands back.
	for map_id: int in Campaign.MAP_ORDER:
		for task_id: String in Campaign.tasks[map_id]:
			assert_int(typeof(Campaign.tasks[map_id][task_id]["status"])).is_equal(TYPE_INT)
