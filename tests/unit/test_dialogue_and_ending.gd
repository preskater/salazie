extends GdUnitTestSuite
## The dialogue box, the decision panel on its own and the epilogue screen.

const DIALOGUE_SCENE := preload("res://scenes/ui/dialogue/dialogue_box.tscn")
const DECISION_SCENE := preload("res://scenes/ui/decision/decision_panel.tscn")
const ENDING_SCENE := preload("res://scenes/ui/ending/ending_screen.tscn")
const TEST_SAVE_PATH := "user://test_dialogue_and_ending.json"

var _original_save_path := ""
var _swaps: Array[String] = []


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	_swaps = []
	SceneRouter.scene_changer = func(path: String) -> Error:
		_swaps.append(path)
		return OK
	SceneRouter.fade_time = 0.01
	SceneRouter.is_gameplay = false
	GameState.playing = false
	Campaign.reset()
	Campaign.current_map = 3


func after_test() -> void:
	GameState.playing = false
	Campaign.reset()
	SceneRouter.scene_changer = Callable()
	SceneRouter.fade_time = SceneRouter.FADE_TIME
	SceneRouter.is_gameplay = false
	SaveGame.save_path = _original_save_path
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if get_tree() != null:
		get_tree().paused = false


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _spawn_dialogue() -> DialogueBox:
	var box: DialogueBox = DIALOGUE_SCENE.instantiate()
	add_child(auto_free(box))
	return box


func _spawn_panel() -> DecisionPanel:
	var panel: DecisionPanel = DECISION_SCENE.instantiate()
	add_child(auto_free(panel))
	return panel


func _spawn_ending() -> Control:
	var ending: Control = ENDING_SCENE.instantiate()
	add_child(auto_free(ending))
	return ending


func _labels(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for label: Label in node.find_children("*", "Label", true, false):
		texts.append(label.text)
	return texts


func _timer(box: DialogueBox) -> Timer:
	return box.find_children("*", "Timer", false, false)[0] as Timer


# --- Dialogue box ------------------------------------------------------------------

func test_the_dialogue_box_starts_hidden_and_silent() -> void:
	var outside: DialogueBox = auto_free(DIALOGUE_SCENE.instantiate())
	assert_str(outside.get_text()).is_empty()

	var box := _spawn_dialogue()

	assert_bool(box.visible).is_false()
	assert_str(box.get_text()).is_empty()
	assert_bool(_timer(box).is_stopped()).is_true()


func test_a_line_shows_who_speaks_and_what_is_said() -> void:
	var box := _spawn_dialogue()

	box.show_line("Mamie Rose", "La rivière a toujours nourri le village.")

	assert_bool(box.visible).is_true()
	assert_str(box.get_text()).is_equal("La rivière a toujours nourri le village.")
	assert_array(_labels(box)).contains_exactly([
		"Mamie Rose", "La rivière a toujours nourri le village."])


func test_a_line_never_pauses_the_game() -> void:
	var box := _spawn_dialogue()

	box.show_line("Le conseil", "Votre plan est adopté.")

	assert_bool(get_tree().paused).is_false()
	# It keeps running behind a panel that does pause the tree.
	assert_int(box.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


func test_a_line_hides_itself_after_its_reading_time() -> void:
	var box := _spawn_dialogue()
	box.show_line("Mamie Rose", "Bonjour.")
	var timer := _timer(box)
	assert_bool(timer.one_shot).is_true()
	assert_float(timer.time_left).is_between(
		DialogueBox.MIN_DURATION - 0.5, DialogueBox.MIN_DURATION)

	timer.timeout.emit()

	assert_bool(box.visible).is_false()
	# The last line stays readable for whoever asks, e.g. the tests of the map.
	assert_str(box.get_text()).is_equal("Bonjour.")


func test_a_new_line_replaces_the_previous_one_and_restarts_the_delay() -> void:
	var box := _spawn_dialogue()
	box.show_line("Mamie Rose", "Bonjour.")
	var timer := _timer(box)
	await get_tree().create_timer(0.3).timeout
	assert_float(timer.time_left).is_less(DialogueBox.MIN_DURATION - 0.1)

	box.show_line("Le facteur", "Du courrier pour la mairie.")

	assert_array(_labels(box)).contains_exactly(["Le facteur", "Du courrier pour la mairie."])
	assert_float(timer.time_left).is_between(
		DialogueBox.MIN_DURATION - 0.1, DialogueBox.MIN_DURATION)
	assert_bool(box.visible).is_true()


func test_a_line_can_be_dismissed_and_shown_again() -> void:
	var box := _spawn_dialogue()
	box.show_line("Mamie Rose", "Bonjour.")

	box.hide_line()
	assert_bool(box.visible).is_false()

	box.show_line("Mamie Rose", "Encore vous ?")
	assert_bool(box.visible).is_true()
	assert_str(box.get_text()).is_equal("Encore vous ?")


func test_the_dialogue_box_lets_clicks_through() -> void:
	var box := _spawn_dialogue()
	box.show_line("Mamie Rose", "Bonjour.")

	for control: Control in box.find_children("*", "Control", false, false):
		assert_int(control.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var panel: PanelContainer = box.find_children("*", "PanelContainer", true, false)[0]
	assert_int(panel.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


# --- Decision panel -------------------------------------------------------------------

func test_the_decision_panel_offers_the_three_plans() -> void:
	var panel := _spawn_panel()

	assert_bool(panel.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	var buttons := panel.find_children("Plan_*", "Button", true, false)
	assert_int(buttons.size()).is_equal(3)
	for index: int in DecisionPanel.PLANS.size():
		var plan: Dictionary = DecisionPanel.PLANS[index]
		var button := buttons[index] as Button
		assert_str(String(button.name)).is_equal("Plan_%s" % plan["id"])
		assert_str(button.text).is_equal(String(plan["label"]))
		assert_array(_labels(panel)).contains([String(plan["description"])])


func test_opening_the_panel_pauses_and_focuses_the_first_plan() -> void:
	var panel := _spawn_panel()

	panel.open()

	assert_bool(panel.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(
		panel.find_child("Plan_forest", true, false))
	panel.close()
	assert_bool(get_tree().paused).is_false()


func test_a_chosen_plan_is_announced_once_and_an_unknown_one_never() -> void:
	var panel := _spawn_panel()
	var chosen: Array[String] = []
	panel.plan_chosen.connect(func(plan_id: String) -> void: chosen.append(plan_id))
	panel.open()

	panel.choose_plan("casino")
	assert_array(chosen).is_empty()
	assert_str(Campaign.get_choice("map3_plan")).is_empty()

	panel.choose_plan("tourism")
	panel.choose_plan("farms")

	assert_array(chosen).contains_exactly(["tourism"])
	assert_str(Campaign.get_choice("map3_plan")).is_equal("tourism")
	assert_int(Campaign.task_status("choose_plan")).is_equal(Campaign.TaskStatus.DONE)
	assert_bool(panel.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_only_cancel_closes_the_open_panel() -> void:
	var panel := _spawn_panel()
	# Hidden: cancel belongs to whoever else listens, e.g. the pause menu.
	panel._unhandled_input(_press(&"ui_cancel"))
	assert_bool(panel.visible).is_false()
	panel.open()

	panel._unhandled_input(_press(&"interact"))
	assert_bool(panel.visible).is_true()
	assert_bool(get_tree().paused).is_true()

	panel._unhandled_input(_press(&"ui_cancel"))
	assert_bool(panel.visible).is_false()
	assert_bool(get_tree().paused).is_false()


# --- Epilogue ---------------------------------------------------------------------------

func test_the_epilogue_is_titled_and_focuses_the_way_back() -> void:
	var ending := _spawn_ending()

	assert_array(_labels(ending)).contains(["Salazie — Trois générations"])
	var button: Button = ending.find_children("*", "Button", true, false)[0]
	assert_str(button.text).is_equal("Retour au menu")
	assert_object(get_viewport().gui_get_focus_owner()).is_same(button)
	assert_array(_labels(ending)).contains([
		String(ending.call("get_epilogue_text")), String(ending.call("get_stats_text"))])


func test_a_flawless_family_is_remembered_without_fault() -> void:
	Campaign.set_choice("map3_plan", "tourism")
	Campaign.complete_task("become_mayor")
	var ending := _spawn_ending()

	var text := String(ending.call("get_epilogue_text"))
	assert_str(text).contains("tourisme durable")
	assert_str(text).contains("vous devenez maire")
	assert_str(text).contains("Trois générations sans faute")
	assert_str(String(ending.call("get_stats_text"))).is_equal(
		"Héritage familial : 0 G · Échecs en chemin : 0")


func test_a_few_failures_do_not_erase_what_was_built() -> void:
	Campaign.record_setback("Repéré", 1)
	Campaign.fail_task("earn_100", "Jour 6 passé", 2)
	var ending := _spawn_ending()

	var text := String(ending.call("get_epilogue_text"))
	assert_str(text).contains("Quelques échecs ont marqué le chemin")
	assert_str(String(ending.call("get_stats_text"))).contains("Échecs en chemin : 2")


func test_many_failures_weigh_on_every_generation() -> void:
	Campaign.heritage = 45
	Campaign.fail_task("find_water", "Repéré", 1)
	Campaign.fail_task("find_food", "Rien trouvé", 1)
	Campaign.fail_task("earn_100", "Jour 6 passé", 2)
	Campaign.fail_task("become_mayor", "Le conseil a rejeté le plan", 3)
	var ending := _spawn_ending()

	var text := String(ending.call("get_epilogue_text"))
	assert_str(text).contains("Les échecs se sont accumulés")
	assert_str(text).contains("Le conseil ne vous suit pas")
	assert_bool(text.contains("Quelques échecs")).is_false()
	assert_str(String(ending.call("get_stats_text"))).is_equal(
		"Héritage familial : 45 G · Échecs en chemin : 3")


func test_an_heir_without_plan_is_told_the_farm_story() -> void:
	var ending := _spawn_ending()

	var text := String(ending.call("get_epilogue_text"))
	assert_str(text).contains("Les marchés de Salazie vivent à nouveau")
	assert_str(text).contains("Le conseil ne vous suit pas")


func test_a_plan_from_another_version_falls_back_to_a_short_farm_story() -> void:
	Campaign.set_choice("map3_plan", "casino")
	var ending := _spawn_ending()

	var text := String(ending.call("get_epilogue_text"))
	assert_str(text).starts_with("Vous avez choisi de soutenir les familles paysannes.\n\n")
	assert_bool(text.contains("marchés")).is_false()


func test_the_epilogue_is_three_paragraphs() -> void:
	Campaign.set_choice("map3_plan", "forest")
	var ending := _spawn_ending()

	assert_int(String(ending.call("get_epilogue_text")).split("\n\n").size()).is_equal(3)


func test_the_button_goes_back_to_the_main_menu() -> void:
	var ending := _spawn_ending()
	var button: Button = ending.find_children("*", "Button", true, false)[0]

	button.pressed.emit()
	await SceneRouter.transition_finished

	assert_array(_swaps).contains_exactly([SceneRouter.MAIN_MENU_SCENE])
	assert_bool(GameState.playing).is_false()
	assert_bool(SceneRouter.is_gameplay).is_false()
	# The campaign is over: leaving the epilogue writes no save.
	assert_bool(FileAccess.file_exists(TEST_SAVE_PATH)).is_false()


# --- #44 -----------------------------------------------------------------------

func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_a_long_line_stays_longer_than_a_short_one() -> void:
	var box := _spawn_dialogue()
	var long_text := "La rivière ronge la berge. Sans végétation, le sol part avec chaque crue, " \
		+ "et les maisons du bas se rapprochent de l'eau d'année en année."

	assert_float(box.reading_time("Bonjour.")).is_equal(DialogueBox.MIN_DURATION)
	assert_float(box.reading_time(long_text)).is_equal_approx(
		long_text.length() * DialogueBox.SECONDS_PER_CHARACTER, 0.001)
	assert_float(box.reading_time(long_text)).is_greater(7.0)
	assert_float(box.reading_time(long_text.repeat(10))).is_equal(DialogueBox.MAX_DURATION)


func test_interact_or_accept_dismisses_the_line() -> void:
	var box := _spawn_dialogue()
	var closes: Array[bool] = []
	box.closed.connect(func() -> void: closes.append(true))

	box.show_line("Mamie Rose", "Bonjour.")
	box._unhandled_input(_action(&"move_left"))
	assert_bool(box.visible).is_true()
	box._unhandled_input(_action(&"interact"))
	assert_bool(box.visible).is_false()

	box.show_line("Mamie Rose", "Encore vous ?")
	box._unhandled_input(_action(&"ui_accept"))
	assert_bool(box.visible).is_false()
	assert_int(closes.size()).is_equal(2)

	# Nothing to dismiss: the press is left for whoever needs it.
	box._unhandled_input(_action(&"interact"))
	box.hide_line()
	assert_int(closes.size()).is_equal(2)


func test_queued_lines_follow_each_other() -> void:
	var box := _spawn_dialogue()

	box.queue_line("Le marron", "Première.")
	box.queue_line("Le marron", "Deuxième.")
	box.queue_line("Le marron", "Troisième.")

	assert_str(box.get_text()).is_equal("Première.")
	assert_int(box.pending_lines()).is_equal(2)
	box.hide_line()
	assert_str(box.get_text()).is_equal("Deuxième.")
	assert_bool(box.visible).is_true()
	box.hide_line()
	box.hide_line()
	assert_bool(box.visible).is_false()
	assert_int(box.pending_lines()).is_equal(0)
