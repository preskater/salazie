extends GdUnitTestSuite
## Regression suite for #15: a ruined farmer could never resolve the farm tasks
## and the exit stayed locked for good.

const FARM_SCENE := preload("res://scenes/maps/farm.tscn")
const TEST_SAVE_PATH := "user://test_farm_relief_save.json"

var _original_save_path := ""


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	GameState.playing = false
	GameState.farm_active = true
	Campaign.reset()
	GameState.reset()


func after_test() -> void:
	Campaign.reset()
	GameState.reset()
	GameState.playing = false
	GameState.farm_active = true
	SaveGame.save_path = _original_save_path
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if get_tree() != null:
		get_tree().paused = false


func _spawn_farm() -> FarmMap:
	var map: FarmMap = FARM_SCENE.instantiate()
	add_child(auto_free(map))
	await get_tree().process_frame
	await get_tree().physics_frame
	return map


func _ruin() -> void:
	for crop: String in GameState.CROP_ORDER:
		GameState.seeds[crop] = 0
		GameState.produce[crop] = 0
	GameState.money = 2


func _first_plot() -> CropPlot:
	return get_tree().get_nodes_in_group("crops")[0] as CropPlot


func test_a_new_farmer_is_not_destitute() -> void:
	var map := await _spawn_farm()

	assert_bool(map.is_destitute()).is_false()
	assert_str((map.hud.objective_label as Label).text).not_contains("Marchande")


func test_destitution_needs_every_way_out_to_be_closed() -> void:
	var map := await _spawn_farm()
	_ruin()
	assert_bool(map.is_destitute()).is_true()

	GameState.seeds["tomato"] = 1
	assert_bool(map.is_destitute()).is_false()
	GameState.seeds["tomato"] = 0

	GameState.produce["corn"] = 1
	assert_bool(map.is_destitute()).is_false()
	GameState.produce["corn"] = 0

	GameState.money = int(GameState.CROPS["carrot"]["seed_price"])
	assert_bool(map.is_destitute()).is_false()
	GameState.money = 0

	var plot := _first_plot()
	plot.state = CropPlot.State.GROWING
	assert_bool(map.is_destitute()).is_false()
	plot.state = CropPlot.State.READY
	assert_bool(map.is_destitute()).is_false()
	plot.state = CropPlot.State.TILLED
	assert_bool(map.is_destitute()).is_true()


func test_ruin_is_announced_once_and_changes_the_objective() -> void:
	var map := await _spawn_farm()
	var messages: Array[String] = []
	var on_notify := func(text: String) -> void: messages.append(text)
	GameState.notification_requested.connect(on_notify)

	_ruin()
	GameState.inventory_changed.emit()
	await get_tree().process_frame
	GameState.inventory_changed.emit()
	await get_tree().process_frame

	GameState.notification_requested.disconnect(on_notify)
	assert_int(messages.filter(func(text: String) -> bool: return text.contains("Marchande")).size()) \
		.is_equal(1)
	assert_str((map.hud.objective_label as Label).text).contains("Marchande")


func test_the_seller_advances_a_seed_to_a_ruined_farmer() -> void:
	var map := await _spawn_farm()
	var seller: FarmNPC = map.get_node("World/NPCSeller")
	_ruin()

	seller.interact(map.player)

	assert_int(GameState.seed_count(FarmMap.RELIEF_CROP)).is_equal(1)
	assert_str(GameState.selected_seed).is_equal(FarmMap.RELIEF_CROP)
	assert_bool(map.is_destitute()).is_false()
	assert_str((map.hud.dialogue_text as Label).text).contains("graine")
	assert_str((map.hud.objective_label as Label).text).not_contains("Marchande")

	# No second seed while the first one is still in the pocket.
	seller.interact(map.player)
	assert_int(GameState.seed_count(FarmMap.RELIEF_CROP)).is_equal(1)


func test_the_seller_gives_nothing_to_a_farmer_who_can_cope() -> void:
	var map := await _spawn_farm()
	var seller: FarmNPC = map.get_node("World/NPCSeller")
	var before := GameState.seed_count(FarmMap.RELIEF_CROP)

	seller.interact(map.player)

	assert_int(GameState.seed_count(FarmMap.RELIEF_CROP)).is_equal(before)


func test_planting_the_last_seed_is_not_ruin() -> void:
	# The seed is spent before the plot starts growing; the check must look at
	# the settled state.
	var map := await _spawn_farm()
	_ruin()
	GameState.seeds["carrot"] = 1
	GameState.select_seed("carrot")
	var plot := _first_plot()
	plot.state = CropPlot.State.TILLED
	var messages: Array[String] = []
	var on_notify := func(text: String) -> void: messages.append(text)
	GameState.notification_requested.connect(on_notify)

	plot.interact(map.player)
	await get_tree().process_frame

	GameState.notification_requested.disconnect(on_notify)
	assert_int(plot.state).is_equal(CropPlot.State.GROWING)
	assert_int(messages.filter(func(text: String) -> bool: return text.contains("Marchande")).size()) \
		.is_equal(0)


func test_a_ruined_farmer_can_still_finish_the_generation() -> void:
	var map := await _spawn_farm()
	var seller: FarmNPC = map.get_node("World/NPCSeller")
	var plot := _first_plot()
	plot.state = CropPlot.State.EMPTY
	_ruin()

	seller.interact(map.player)
	plot.interact(map.player)
	plot.interact(map.player)
	plot.growth = 1000.0
	plot._process(0.1)
	plot.interact(map.player)
	GameState.sell(FarmMap.RELIEF_CROP, 1)

	for task_id: String in ["prepare_plot", "plant_seed", "harvest_crop", "sell_produce"]:
		assert_int(Campaign.task_status(task_id)).override_failure_message(
			"%s should be done" % task_id).is_equal(Campaign.TaskStatus.DONE)


func test_shoulder_buttons_walk_through_the_seeds() -> void:
	var map := await _spawn_farm()
	GameState.select_seed(GameState.CROP_ORDER[0])
	var next := InputEventAction.new()
	next.action = &"seed_next"
	next.pressed = true
	var previous := InputEventAction.new()
	previous.action = &"seed_previous"
	previous.pressed = true

	map._unhandled_input(next)
	assert_str(GameState.selected_seed).is_equal(GameState.CROP_ORDER[1])
	map._unhandled_input(previous)
	map._unhandled_input(previous)
	assert_str(GameState.selected_seed).is_equal(GameState.CROP_ORDER[-1])
	map._unhandled_input(next)
	assert_str(GameState.selected_seed).is_equal(GameState.CROP_ORDER[0])


func test_villagers_say_their_lines_in_order() -> void:
	# Regression (#44): lines were drawn at random, so one could be heard twice
	# while another never came up.
	var map := await _spawn_farm()
	var villager: FarmNPC = map.get_node("World/NPCVillager")
	var heard: Array[String] = []
	for index: int in villager.lines.size() * 2:
		heard.append(villager.next_line())

	assert_array(heard.slice(0, villager.lines.size())).is_equal(Array(villager.lines))
	assert_array(heard.slice(villager.lines.size())).is_equal(Array(villager.lines))


func test_a_villager_with_nothing_to_say_still_greets() -> void:
	var map := await _spawn_farm()
	var villager: FarmNPC = map.get_node("World/NPCVillager")
	villager.lines = PackedStringArray()

	assert_str(villager.next_line()).is_equal("Bienvenue à Salazie.")


func test_the_seller_talks_about_todays_prices() -> void:
	var map := await _spawn_farm()
	var seller: FarmNPC = map.get_node("World/NPCSeller")
	for crop: String in GameState.CROP_ORDER:
		GameState.prices[crop] = int(GameState.CROPS[crop]["base_price"])
	GameState.prices["tomato"] = int(GameState.CROPS["tomato"]["base_price"]) + 4

	var first := seller.next_line()

	assert_str(first).contains("tomate")
	assert_str(first).contains("%d" % int(GameState.prices["tomato"]))
	assert_str(seller.next_line()).is_equal(seller.lines[0])

	# A bad day for every crop is said as such.
	for crop: String in GameState.CROP_ORDER:
		GameState.prices[crop] = maxi(1, int(GameState.CROPS[crop]["base_price"]) - 3)
	assert_str(map.market_tip()).contains("bas")
	GameState.prices.clear()
	assert_str(map.market_tip()).is_empty()
	GameState.reset()
