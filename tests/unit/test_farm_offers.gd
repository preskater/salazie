extends GdUnitTestSuite
## What the farmer buys at the market changes the farm (#27).

const FARM_SCENE := preload("res://scenes/maps/farm.tscn")
const TEST_SAVE_PATH := "user://test_farm_offers_save.json"

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


func _plot(map: FarmMap, plot_name: String) -> CropPlot:
	return map.get_node("World/" + plot_name) as CropPlot


# --- Field slots -------------------------------------------------------------

func test_the_starting_garden_is_four_plots() -> void:
	var map := await _spawn_farm()
	var open := 0
	var fallow := 0
	for node: Node in get_tree().get_nodes_in_group("crops"):
		if (node as CropPlot).is_locked():
			fallow += 1
		else:
			open += 1

	assert_int(open).is_equal(4)
	assert_int(fallow).is_equal(4)
	assert_bool(_plot(map, "Plot_32_35").is_locked()).is_false()
	assert_bool(_plot(map, "Plot_35_36").is_locked()).is_true()


func test_a_fallow_plot_cannot_be_worked() -> void:
	var map := await _spawn_farm()
	var plot := _plot(map, "Plot_34_35")
	var seeds := GameState.seed_count(GameState.selected_seed)

	assert_str(plot.get_interaction_prompt()).contains("friche")
	plot.interact(map.player)

	assert_int(plot.state).is_equal(CropPlot.State.EMPTY)
	assert_int(GameState.seed_count(GameState.selected_seed)).is_equal(seeds)
	assert_int(Campaign.task_status("prepare_plot")).is_equal(Campaign.TaskStatus.PENDING)


func test_each_field_slot_opens_two_more_plots() -> void:
	var map := await _spawn_farm()
	GameState.money = 200

	assert_bool(Economy.buy(&"slot_field")).is_true()
	assert_bool(_plot(map, "Plot_34_35").is_locked()).is_false()
	assert_bool(_plot(map, "Plot_34_36").is_locked()).is_false()
	assert_bool(_plot(map, "Plot_35_35").is_locked()).is_true()

	assert_bool(Economy.buy(&"slot_field")).is_true()
	assert_bool(_plot(map, "Plot_35_35").is_locked()).is_false()
	assert_bool(_plot(map, "Plot_35_36").is_locked()).is_false()

	var plot := _plot(map, "Plot_35_36")
	plot.interact(map.player)
	assert_int(plot.state).is_equal(CropPlot.State.TILLED)
	assert_str(plot.get_interaction_prompt()).contains("Planter")


func test_a_crop_on_land_that_was_sold_can_still_be_harvested() -> void:
	var map := await _spawn_farm()
	GameState.money = 200
	Economy.buy(&"slot_field")
	var plot := _plot(map, "Plot_34_35")
	plot.interact(map.player)
	plot.interact(map.player)
	assert_int(plot.state).is_equal(CropPlot.State.GROWING)

	assert_int(Economy.sell(&"slot_field")).is_greater(0)
	assert_bool(plot.is_locked()).is_true()
	assert_str(plot.get_interaction_prompt()).contains("croissance")
	plot.interact(map.player)
	assert_int(plot.state).is_equal(CropPlot.State.GROWING)

	plot.growth = 1000.0
	plot._process(0.1)
	assert_str(plot.get_interaction_prompt()).contains("Récolter")
	plot.interact(map.player)

	assert_int(plot.state).is_equal(CropPlot.State.TILLED)
	assert_str(plot.get_interaction_prompt()).contains("friche")


# --- Hoe ---------------------------------------------------------------------

func test_the_hoe_makes_crops_grow_faster() -> void:
	var map := await _spawn_farm()
	GameState.money = 200
	var plot := _plot(map, "Plot_32_35")
	plot.from_dict({"state": CropPlot.State.GROWING, "crop": "corn", "growth": 0.0})

	plot._process(4.0)
	assert_float(plot.growth).is_equal_approx(4.0, 0.001)
	assert_float(plot.growth_speed()).is_equal(1.0)

	assert_bool(Economy.buy(&"item_hoe")).is_true()
	plot._process(4.0)

	assert_float(plot.growth_speed()).is_equal(CropPlot.HOE_GROWTH_BONUS)
	assert_float(plot.growth).is_equal_approx(4.0 + 4.0 * CropPlot.HOE_GROWTH_BONUS, 0.001)


# --- Barn --------------------------------------------------------------------

func test_without_a_barn_the_cyclone_destroys_ripe_crops() -> void:
	var map := await _spawn_farm()
	var plot := _plot(map, "Plot_32_35")
	plot.from_dict({"state": CropPlot.State.READY, "crop": "tomato", "growth": 99.0})
	var produce := GameState.produce_count("tomato")

	var lost: int = map.call("_destroy_ripe_crops_on_path",
		plot.global_position + Vector2(-50, 0), plot.global_position + Vector2(50, 0))

	assert_int(lost).is_equal(1)
	assert_int(plot.state).is_equal(CropPlot.State.TILLED)
	assert_int(GameState.produce_count("tomato")).is_equal(produce)


func test_the_barn_brings_ripe_crops_in_before_the_cyclone() -> void:
	var map := await _spawn_farm()
	GameState.money = 200
	assert_bool(Economy.buy(&"building_barn")).is_true()
	var ripe := _plot(map, "Plot_32_35")
	var growing := _plot(map, "Plot_33_35")
	ripe.from_dict({"state": CropPlot.State.READY, "crop": "tomato", "growth": 99.0})
	growing.from_dict({"state": CropPlot.State.GROWING, "crop": "corn", "growth": 2.0})
	var produce := GameState.produce_count("tomato")

	var lost: int = map.call("_destroy_ripe_crops_on_path",
		ripe.global_position + Vector2(-50, 0), ripe.global_position + Vector2(50, 0))

	assert_int(lost).is_equal(0)
	assert_int(ripe.state).is_equal(CropPlot.State.TILLED)
	assert_int(GameState.produce_count("tomato")).is_equal(produce + 1)
	assert_int(growing.state).is_equal(CropPlot.State.GROWING)
	assert_bool(growing.shelter_crop()).is_false()


func test_a_strike_reports_what_the_barn_saved() -> void:
	var map := await _spawn_farm()
	GameState.money = 200
	Economy.buy(&"building_barn")
	map.cyclone_legs = 1
	map.cyclone_leg_time = 0.05
	var plot := _plot(map, "Plot_32_35")
	plot.from_dict({"state": CropPlot.State.READY, "crop": "carrot", "growth": 99.0})
	# One short leg starting on the garden always passes over the plot.
	map.cyclone.global_position = plot.global_position
	map.cyclone_speed = 10.0
	var messages: Array[String] = []
	var on_notify := func(text: String) -> void: messages.append(text)
	GameState.notification_requested.connect(on_notify)

	await map.call("_strike_cyclone")

	GameState.notification_requested.disconnect(on_notify)
	assert_bool(messages.any(func(text: String) -> bool: return text.contains("grange"))).is_true()
	assert_bool(messages.any(func(text: String) -> bool: return text.contains("détruit"))).is_false()


# --- Wealth ------------------------------------------------------------------

func test_buying_does_not_reduce_the_net_worth() -> void:
	await _spawn_farm()
	GameState.money = 90
	assert_int(GameState.net_worth()).is_equal(90)

	Economy.buy(&"building_barn")

	assert_int(GameState.money).is_equal(30)
	assert_int(Economy.owned_value()).is_equal(60)
	assert_int(Economy.owned_value(&"gourde")).is_equal(60)
	assert_int(Economy.owned_value(&"euro")).is_equal(0)
	assert_int(GameState.net_worth()).is_equal(90)

	# Selling back at half price is a real loss.
	Economy.sell(&"building_barn")
	assert_int(GameState.net_worth()).is_equal(60)


func test_prosperity_counts_what_was_invested() -> void:
	# Regression: with 90 G, buying a barn used to push the 100 G goal away.
	await _spawn_farm()
	GameState.money = 90
	Economy.buy(&"building_barn")
	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.PENDING)

	GameState.add_money(10)

	assert_int(GameState.money).is_equal(40)
	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.DONE)


func test_prosperity_stays_pending_below_the_goal_and_done_once_reached() -> void:
	await _spawn_farm()
	GameState.money = 99
	await get_tree().process_frame
	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.PENDING)

	GameState.money = 100
	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.DONE)

	GameState.money = 5
	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.DONE)


func test_the_heritage_includes_buildings_land_and_tools() -> void:
	await _spawn_farm()
	GameState.money = 200
	Economy.buy(&"building_barn")
	Economy.buy(&"slot_field")
	Economy.buy(&"item_hoe")

	assert_int(GameState.money).is_equal(85)
	assert_int(Campaign.heritage_for_map3()).is_equal(200)

	# Each failure event of the generation takes a tenth of it.
	Campaign.record_setback("Récolte perdue", 2)
	assert_int(Campaign.heritage_for_map3()).is_equal(180)


func test_net_worth_is_the_purse_when_the_economy_is_off() -> void:
	Economy.set_enabled(false)
	GameState.money = 42

	assert_int(GameState.net_worth()).is_equal(42)
	Economy.set_enabled(true)


func test_shipped_offers_describe_what_they_do() -> void:
	await _spawn_farm()
	for offer_id: StringName in [&"building_barn", &"slot_field", &"item_hoe"]:
		var offer := Economy.offer(offer_id)
		assert_object(offer).override_failure_message("%s is not sold" % offer_id).is_not_null()
		assert_str(offer.description).is_not_empty()
	assert_str(Economy.offer(&"building_barn").description).contains("cyclone")
	assert_str(Economy.offer(&"item_hoe").description).contains("25")
	assert_str(String(Economy.offer(&"slot_field").grant_id)).is_equal(String(CropPlot.FIELD_SLOT_ASSET))
	assert_str(String(Economy.offer(&"item_hoe").grant_id)).is_equal(String(CropPlot.HOE_ASSET))
	assert_str(String(Economy.offer(&"building_barn").grant_id)).is_equal(String(FarmMap.BARN_ASSET))
