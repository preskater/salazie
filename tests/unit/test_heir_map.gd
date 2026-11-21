extends GdUnitTestSuite

const HEIR_SCENE := preload("res://game/world/maps/Heir.tscn")
const TEST_SAVE_PATH := "user://test_heir_save.json"

var _original_save_path := ""


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	GameState.playing = false
	GameState.money = 100
	Campaign.reset()


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	GameState.money = 0
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
	var label: Label = map.get_node("HeritageLabel")
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
