extends GdUnitTestSuite

const HEIR_SCENE := preload("res://scenes/maps/heir.tscn")
const TEST_SAVE_PATH := "user://test_heir_save.json"

var _original_save_path := ""


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	GameState.playing = false
	# Back on the farm's economy: the map converts it into the heir's on entry.
	GameState.reset()
	GameState.money = 100
	Campaign.reset()


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	GameState.reset()
	GameState.farm_active = true
	DayNightCycle.nights_required_for_next_map = 2
	DayNightCycle.nights_spent = 0
	SaveGame.save_path = _original_save_path
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if get_tree() != null:
		get_tree().paused = false


func _spawn_map() -> HeirMap:
	var map: HeirMap = HEIR_SCENE.instantiate()
	add_child(auto_free(map))
	await get_tree().process_frame
	await get_tree().physics_frame
	return map


func test_map_builds_npcs_sites_decision_and_town_hall() -> void:
	var map := await _spawn_map()

	assert_object(map.get_node_or_null("World/Player")).is_not_null()
	assert_int(get_tree().get_nodes_in_group("npc").size()).is_equal(5)
	assert_int(get_tree().get_nodes_in_group("fragile_sites").size()).is_equal(3)
	assert_int(get_tree().get_nodes_in_group("decision_points").size()).is_equal(1)
	assert_int(get_tree().get_nodes_in_group("town_halls").size()).is_equal(1)
	assert_object(map.get_node_or_null("TaskList")).is_not_null()
	assert_object(map.get_node_or_null("GenerationResult")).is_not_null()
	assert_object(map.get_node_or_null("DialogueBox")).is_not_null()
	assert_object(map.get_node_or_null("DecisionPanel")).is_not_null()


func test_heritage_is_computed_from_the_farm() -> void:
	var map := await _spawn_map()

	assert_int(Campaign.heritage).is_equal(100)
	var label: Label = map.get_node("Overlay/HeritageLabel")
	assert_str(label.text).contains("100 G")


func test_talking_to_each_npc_counts_once() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var npcs := get_tree().get_nodes_in_group("npc")
	var npc: Node2D = npcs[0]

	npc.call("interact", player)
	assert_int(Campaign.task_progress("listen")).is_equal(1)
	npc.call("interact", player)
	assert_int(Campaign.task_progress("listen")).is_equal(1)

	(npcs[1] as Node2D).call("interact", player)
	assert_int(Campaign.task_progress("listen")).is_equal(2)


func test_inspecting_each_fragile_site_counts_once() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var sites := get_tree().get_nodes_in_group("fragile_sites")
	var site: Area2D = sites[0]

	site.call("interact", player)
	assert_int(Campaign.task_progress("assess")).is_equal(1)
	site.call("interact", player)
	assert_int(Campaign.task_progress("assess")).is_equal(1)

	(sites[1] as Area2D).call("interact", player)
	assert_int(Campaign.task_progress("assess")).is_equal(2)


func test_plan_choice_is_stored_and_completes_the_task() -> void:
	var map := await _spawn_map()
	var panel: DecisionPanel = map.get_node("DecisionPanel")

	panel.choose_plan("forest")

	assert_str(Campaign.get_choice("map3_plan")).is_equal("forest")
	assert_int(Campaign.task_status("choose_plan")).is_equal(Campaign.TaskStatus.DONE)
	assert_bool(panel.visible).is_false()


func test_optional_landmarks_and_bus_stops_exist() -> void:
	var map := await _spawn_map()

	assert_int(get_tree().get_nodes_in_group("landmarks").size()).is_equal(2)
	assert_int(get_tree().get_nodes_in_group("bus_stops").size()).is_equal(2)
	assert_object(map.get_node_or_null("Overlay/HeritageLabel")).is_not_null()


func test_landmark_marks_the_village_discovered() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var landmark: Area2D = get_tree().get_nodes_in_group("landmarks")[0]
	var landmark_id := String(landmark.get("landmark_id"))

	landmark.call("interact", player)

	assert_str(Campaign.get_choice("visited_" + landmark_id)).is_equal("1")


func test_bus_stop_moves_the_player_to_its_destination() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var stop: Area2D = get_tree().get_nodes_in_group("bus_stops")[0]
	var destination: Vector2 = stop.get("destination")

	stop.call("interact", player)
	await map.ride_finished

	assert_float(player.global_position.distance_to(destination)).is_less(1.0)


func _resolve_fieldwork() -> void:
	Campaign.complete_task("listen")
	Campaign.complete_task("assess")


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_decision_point_opens_only_after_the_fieldwork() -> void:
	var map := await _spawn_map()
	var panel: DecisionPanel = map.get_node("DecisionPanel")
	var point: Node = get_tree().get_first_node_in_group("decision_points")
	var notification: Label = map.get_node("Overlay/NotificationLabel")

	point.call("interact", map.get_node("World/Player"))
	assert_bool(panel.visible).is_false()
	assert_str(notification.text).contains("habitants")

	Campaign.complete_task("listen")
	point.call("interact", map.get_node("World/Player"))
	assert_bool(panel.visible).is_false()
	assert_str(notification.text).contains("zones fragiles")

	Campaign.complete_task("assess")
	point.call("interact", map.get_node("World/Player"))
	assert_bool(panel.visible).is_true()
	assert_bool(get_tree().paused).is_true()


func test_decision_point_does_not_reopen_once_a_plan_is_chosen() -> void:
	# Regression (#14): the panel reopened, paused the game and none of its
	# buttons could close it.
	var map := await _spawn_map()
	var panel: DecisionPanel = map.get_node("DecisionPanel")
	var point: Node = get_tree().get_first_node_in_group("decision_points")
	_resolve_fieldwork()
	point.call("interact", map.get_node("World/Player"))
	panel.choose_plan("tourism")

	point.call("interact", map.get_node("World/Player"))

	assert_bool(panel.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_str((map.get_node("Overlay/NotificationLabel") as Label).text).contains("mairie")


func test_decision_panel_never_stays_open_on_a_resolved_choice() -> void:
	var map := await _spawn_map()
	var panel: DecisionPanel = map.get_node("DecisionPanel")
	Campaign.set_choice("map3_plan", "forest")
	Campaign.complete_task("choose_plan")
	panel.open()
	assert_bool(get_tree().paused).is_true()

	panel.choose_plan("farms")

	assert_bool(panel.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_str(Campaign.get_choice("map3_plan")).is_equal("forest")


func test_decision_panel_ignores_an_unknown_plan() -> void:
	var map := await _spawn_map()
	var panel: DecisionPanel = map.get_node("DecisionPanel")
	panel.open()

	panel.choose_plan("casino")

	assert_bool(panel.visible).is_true()
	assert_int(Campaign.task_status("choose_plan")).is_equal(Campaign.TaskStatus.PENDING)
	panel.close()


func test_cancel_closes_the_decision_panel_and_restores_the_pause() -> void:
	var map := await _spawn_map()
	var panel: DecisionPanel = map.get_node("DecisionPanel")
	panel.open()

	panel._unhandled_input(_press(&"ui_cancel"))

	assert_bool(panel.visible).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_int(Campaign.task_status("choose_plan")).is_equal(Campaign.TaskStatus.PENDING)


func test_decision_panel_leaves_a_pause_it_did_not_start() -> void:
	var map := await _spawn_map()
	var panel: DecisionPanel = map.get_node("DecisionPanel")
	get_tree().paused = true

	panel.open()
	panel.close()

	assert_bool(get_tree().paused).is_true()


func test_plan_buttons_choose_their_plan_and_announce_it() -> void:
	var map := await _spawn_map()
	var panel: DecisionPanel = map.get_node("DecisionPanel")
	panel.open()
	var button: Button = panel.find_child("Plan_farms", true, false)

	assert_object(get_viewport().gui_get_focus_owner()).is_not_null()
	button.pressed.emit()

	assert_str(Campaign.get_choice("map3_plan")).is_equal("farms")
	assert_str((map.get_node("Overlay/NotificationLabel") as Label).text) \
		.contains("familles paysannes")


func test_town_hall_asks_for_a_plan_first() -> void:
	var map := await _spawn_map()
	var hall: Node = get_tree().get_first_node_in_group("town_halls")

	hall.call("interact", map.get_node("World/Player"))

	assert_int(Campaign.task_status("become_mayor")).is_equal(Campaign.TaskStatus.PENDING)
	assert_str((map.get_node("Overlay/NotificationLabel") as Label).text).contains("plan")
	assert_bool(get_tree().paused).is_false()


func test_council_adopts_the_plan_and_votes_only_once() -> void:
	# Regression (#29): a second vote during the fade to the ending paused the
	# tree again, and the ending screen loaded frozen.
	var map := await _spawn_map()
	var hall: Node = get_tree().get_first_node_in_group("town_halls")
	var result: GenerationResult = map.get_node("GenerationResult")
	_resolve_fieldwork()
	Campaign.set_choice("map3_plan", "forest")
	Campaign.complete_task("choose_plan")
	Campaign.set_choice("funded_foret", "1")
	assert_str(String(hall.call("get_interaction_prompt"))).contains(
		"%d/%d" % [Campaign.mayor_support(), Campaign.SUPPORT_NEEDED])

	hall.call("interact", map.get_node("World/Player"))

	assert_int(Campaign.task_status("become_mayor")).is_equal(Campaign.TaskStatus.DONE)
	assert_bool(result.visible).is_true()
	assert_bool(get_tree().paused).is_true()

	# What the "Continuer" button leaves behind while the ending fades in.
	result.close()
	assert_bool(get_tree().paused).is_false()
	hall.call("interact", map.get_node("World/Player"))

	assert_bool(result.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_council_rejects_the_plan_without_enough_support() -> void:
	var map := await _spawn_map()
	var hall: Node = get_tree().get_first_node_in_group("town_halls")
	_resolve_fieldwork()
	Campaign.set_choice("map3_plan", "forest")
	Campaign.complete_task("choose_plan")
	# Nothing was done for the village: the inherited support is not enough.

	hall.call("interact", map.get_node("World/Player"))

	assert_bool(Campaign.has_mayor_support()).is_false()
	assert_int(Campaign.task_status("become_mayor")).is_equal(Campaign.TaskStatus.FAILED)
	assert_str((map.get_node("DialogueBox") as DialogueBox).get_text()).contains("refusé")


func test_player_can_interact_while_the_bus_drives_away() -> void:
	# Regression (#45): prompts stayed off until the bus had left the map.
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var stop: Area2D = get_tree().get_nodes_in_group("bus_stops")[0]
	var world: Node = map.get_node("World")

	stop.call("interact", player)
	while not player.is_physics_processing() or player.get_parent() != world:
		await get_tree().process_frame

	assert_object(world.get_node_or_null("Shuttle")).is_not_null()
	assert_bool(map.get("_shuttle_active")).is_false()

	# A second bus must not spawn on top of the one that is leaving.
	stop.call("interact", player)
	assert_int(world.find_children("Shuttle*", "", false, false).size()).is_equal(1)
	await map.ride_finished
	await get_tree().process_frame
	assert_object(world.get_node_or_null("Shuttle")).is_null()


# --- Stakes (#26) -------------------------------------------------------------

func _site(site_id: String) -> Area2D:
	for node: Node in get_tree().get_nodes_in_group("fragile_sites"):
		if String(node.get("site_id")) == site_id:
			return node as Area2D
	return null


func test_the_heritage_becomes_the_heirs_euros() -> void:
	var map := await _spawn_map()

	assert_str(String(Economy.current_generation_id())).is_equal("heritier")
	assert_int(Economy.balance(&"euro")).is_equal(100)
	assert_int(Economy.balance(&"credit_vert")).is_equal(0)
	assert_str((map.get_node("Overlay/BudgetLabel") as Label).text).contains("100")
	assert_str((map.get_node("Overlay/SupportLabel") as Label).text).contains(
		"%d / %d" % [Campaign.SUPPORT_START, Campaign.SUPPORT_NEEDED])


func test_wallets_of_a_village_in_progress_are_not_reset() -> void:
	# Continue restores the heir's economy before the scene loads.
	Economy.select_generation(&"heritier")
	Economy.set_balance(&"euro", 7)
	Economy.set_balance(&"credit_vert", 9)
	Campaign.heritage = 100

	await _spawn_map()

	assert_int(Economy.balance(&"euro")).is_equal(7)
	assert_int(Economy.balance(&"credit_vert")).is_equal(9)
	assert_int(Campaign.heritage).is_equal(100)


func test_listening_and_walking_earn_green_credits_once() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var npc: Node2D = get_tree().get_nodes_in_group("npc")[0]
	var landmark: Area2D = get_tree().get_nodes_in_group("landmarks")[0]

	npc.call("interact", player)
	npc.call("interact", player)
	assert_int(Economy.balance(&"credit_vert")).is_equal(HeirMap.CREDITS_PER_RESIDENT)

	landmark.call("interact", player)
	landmark.call("interact", player)
	assert_int(Economy.balance(&"credit_vert")).is_equal(
		HeirMap.CREDITS_PER_RESIDENT + HeirMap.CREDITS_PER_LANDMARK)
	assert_str((map.get_node("Overlay/BudgetLabel") as Label).text).contains("CV")


func test_a_site_is_inspected_then_funded() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var site := _site("foret")
	var price := Economy.offer(&"item_seedling_kit").price

	assert_str(String(site.call("get_interaction_prompt"))).contains("Inspecter")
	site.call("interact", player)
	assert_int(Campaign.task_progress("assess")).is_equal(1)
	assert_str(String(site.call("get_interaction_prompt"))).contains("Financer")
	assert_str(String(site.call("get_interaction_prompt"))).contains("%d" % price)

	site.call("interact", player)

	assert_str(Campaign.get_choice("funded_foret")).is_equal("1")
	assert_int(Economy.balance(&"euro")).is_equal(100 - price)
	assert_int(Campaign.mayor_support()).is_equal(Campaign.SUPPORT_START + 1)
	assert_str(String(site.call("get_interaction_prompt"))).contains("protégée")
	assert_str((map.get_node("Overlay/SupportLabel") as Label).text).contains(
		"%d / " % (Campaign.SUPPORT_START + 1))

	# Paid once: a third interaction changes nothing.
	site.call("interact", player)
	assert_int(Economy.balance(&"euro")).is_equal(100 - price)
	assert_int(Campaign.task_progress("assess")).is_equal(1)


func test_a_site_too_expensive_says_what_is_missing() -> void:
	GameState.money = 30
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var site := _site("berge")

	site.call("interact", player)
	site.call("interact", player)

	assert_str(Campaign.get_choice("funded_berge")).is_empty()
	assert_int(Economy.balance(&"euro")).is_equal(30)
	assert_str((map.get_node("Overlay/NotificationLabel") as Label).text).contains("manque")


func test_the_market_is_secured_with_the_residents_trust() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var site := _site("marche")
	site.call("interact", player)

	site.call("interact", player)
	assert_str(Campaign.get_choice("funded_marche")).is_empty()

	for npc: Node in get_tree().get_nodes_in_group("npc").slice(0, 3):
		npc.call("interact", player)
	site.call("interact", player)

	assert_str(Campaign.get_choice("funded_marche")).is_equal("1")
	assert_int(Economy.balance(&"euro")).is_equal(100)


func test_a_site_without_an_offer_is_only_inspected() -> void:
	var map := await _spawn_map()
	var site := _site("foret")
	site.set("fund_offer", &"")

	site.call("interact", map.get_node("World/Player"))

	assert_bool(bool(site.call("can_be_funded"))).is_false()
	assert_str(String(site.call("get_interaction_prompt"))).contains("Inspecter")
	map.call("_on_site_funding_requested", "foret", &"inconnue", site)
	assert_str(Campaign.get_choice("funded_foret")).is_empty()


func test_every_site_points_at_an_offer_the_heir_can_buy() -> void:
	await _spawn_map()
	for site_id: String in Campaign.FRAGILE_SITES:
		var site := _site(site_id)
		assert_object(site).override_failure_message("No site %s" % site_id).is_not_null()
		assert_object(Economy.offer(site.get("fund_offer"))).override_failure_message(
			"%s has no offer" % site_id).is_not_null()
	assert_int(get_tree().get_nodes_in_group("npc").size()).is_equal(Campaign.RESIDENT_COUNT)
	for node: Node in get_tree().get_nodes_in_group("landmarks"):
		assert_bool(Campaign.LANDMARKS.has(String(node.get("landmark_id")))).is_true()


func test_a_rejection_reports_the_score_the_council_voted_on() -> void:
	# The rejection is itself a failure event; the report used to read the
	# score again and show one voice less than the vote.
	var map := await _spawn_map()
	var hall: Node = get_tree().get_first_node_in_group("town_halls")
	var result: GenerationResult = map.get_node("GenerationResult")
	_resolve_fieldwork()
	Campaign.set_choice("map3_plan", "forest")
	Campaign.complete_task("choose_plan")
	var voted := Campaign.mayor_support()

	hall.call("interact", map.get_node("World/Player"))

	assert_int(Campaign.task_status("become_mayor")).is_equal(Campaign.TaskStatus.FAILED)
	var footer: Label = result.get("_footer")
	assert_str(footer.text).contains("%d / %d" % [voted, Campaign.SUPPORT_NEEDED])
	result.close()
