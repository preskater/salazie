extends GdUnitTestSuite
## Save version 3: the world of the map being played survives Continue (#16).

const MAROON_SCENE := preload("res://scenes/maps/maroon.tscn")
const FARM_SCENE := preload("res://scenes/maps/farm.tscn")
const HEIR_SCENE := preload("res://scenes/maps/heir.tscn")
const TEST_PATH := "user://test_save_world.json"

var _original_path := ""


func before_test() -> void:
	_original_path = SaveGame.save_path
	SaveGame.save_path = TEST_PATH
	_cleanup()
	SaveGame.clear_world()
	Campaign.reset()
	GameState.reset()
	GameState.playing = false
	DayNightCycle.reset_for_new_map(0)


func after_test() -> void:
	_cleanup()
	SaveGame.clear_world()
	SaveGame.save_path = _original_path
	Campaign.reset()
	GameState.reset()
	GameState.playing = false
	GameState.farm_active = true
	DayNightCycle.reset_for_new_map(0)
	if get_tree() != null:
		get_tree().paused = false


func _cleanup() -> void:
	for path: String in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _spawn(scene: PackedScene) -> Node:
	var map: Node = scene.instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().physics_frame
	# A map is normally entered through the router: start the session it would
	# have started, so saving works and no autosave fires from a menu state.
	SceneRouter.is_gameplay = true
	GameState.playing = true
	return map


## Frees the map the way a scene change does, then loads the file back.
func _quit_and_continue(map: Node) -> void:
	assert_bool(SaveGame.save_game()).is_true()
	await _dispose(map)
	# Back at the menu nothing autosaves; otherwise the resets below would
	# overwrite the file that was just written.
	GameState.playing = false
	SaveGame.clear_world()
	Campaign.reset()
	GameState.reset()
	assert_bool(SaveGame.load_game()).is_true()


## A map cannot be freed from inside one of its own signals or coroutines.
func _dispose(map: Node) -> void:
	map.queue_free()
	await get_tree().process_frame


func _read_file() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))


# --- SaveGame --------------------------------------------------------------

func test_provider_state_is_written_and_handed_back_after_a_load() -> void:
	GameState.playing = true
	Campaign.current_map = 2
	var provider := func() -> Dictionary: return {"plots": {"A": {"state": 2}}}
	assert_dict(SaveGame.register_world(2, provider)).is_empty()

	assert_bool(SaveGame.save_game()).is_true()

	assert_int(int(_read_file()["version"])).is_equal(3)
	assert_int(int(_read_file()["world"]["map"])).is_equal(2)
	SaveGame.unregister_world(2)
	SaveGame.clear_world()
	assert_bool(SaveGame.load_game()).is_true()
	var restored := SaveGame.register_world(2, provider)
	assert_int(int(restored["plots"]["A"]["state"])).is_equal(2)
	# Handed over once: a second map instance starts from what is live.
	assert_dict(SaveGame.register_world(2, provider)).is_empty()
	SaveGame.unregister_world(2)


func test_world_of_a_generation_that_was_left_is_dropped() -> void:
	# `go_to_next_map` saves after the campaign moved on, while the old map is
	# still the registered provider.
	GameState.playing = true
	Campaign.current_map = 2
	SaveGame.register_world(1, func() -> Dictionary: return {"respawn": [1, 2]})

	assert_bool(SaveGame.save_game()).is_true()

	assert_dict(_read_file()["world"]).is_empty()
	SaveGame.unregister_world(1)


func test_loaded_world_is_kept_until_its_map_registers() -> void:
	GameState.playing = true
	Campaign.current_map = 3
	SaveGame.world = {3: {"player": [10, 20]}, 1: {"stale": true}}

	assert_bool(SaveGame.save_game()).is_true()

	assert_int(int(_read_file()["world"]["map"])).is_equal(3)
	assert_bool(SaveGame.world.has(1)).is_false()


func test_unregistering_another_map_keeps_the_provider() -> void:
	GameState.playing = true
	Campaign.current_map = 2
	SaveGame.register_world(2, func() -> Dictionary: return {"ok": true})

	SaveGame.unregister_world(1)
	SaveGame.save_game()

	assert_bool(bool(_read_file()["world"]["state"]["ok"])).is_true()
	SaveGame.unregister_world(2)


func test_a_provider_that_returns_no_dictionary_stores_nothing() -> void:
	GameState.playing = true
	Campaign.current_map = 2
	SaveGame.register_world(2, func() -> Variant: return null)

	SaveGame.save_game()

	assert_dict(_read_file()["world"]).is_empty()
	SaveGame.unregister_world(2)


func test_malformed_or_stale_world_blocks_are_ignored() -> void:
	GameState.playing = true
	Campaign.current_map = 2
	SaveGame.save_game()
	var payload := _read_file()
	for bad: Variant in ["oops", {"map": 9, "state": {}}, {"map": 2, "state": []},
			{"map": "two", "state": {}}, {"map": 1, "state": {"respawn": [0, 0]}}]:
		payload["world"] = bad
		var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(payload))
		file.close()

		assert_bool(SaveGame.load_game()).is_true()
		assert_dict(SaveGame.world).override_failure_message(
			"%s should be ignored" % str(bad)).is_empty()


func test_version_2_save_migrates_without_a_world() -> void:
	GameState.playing = true
	Campaign.current_map = 2
	SaveGame.save_game()
	var payload := _read_file()
	payload["version"] = 2
	payload.erase("world")
	payload.erase("cycle")
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

	assert_bool(SaveGame.load_game()).is_true()

	assert_dict(SaveGame.world).is_empty()
	assert_dict(SaveGame.read_cycle()).is_empty()
	assert_int(Campaign.current_map).is_equal(2)


func test_deleting_the_save_forgets_the_world() -> void:
	SaveGame.world = {2: {"plots": {}}}

	SaveGame.delete_save()

	assert_dict(SaveGame.world).is_empty()


# --- Day/night ---------------------------------------------------------------

func test_cycle_round_trips_through_the_save() -> void:
	GameState.playing = true
	DayNightCycle.running = true
	DayNightCycle.advance(DayNightCycle.day_duration + 12.0)
	DayNightCycle.running = false
	var day := DayNightCycle.day_number
	var left := DayNightCycle.time_left
	assert_bool(DayNightCycle.is_night()).is_true()
	SaveGame.save_game()

	DayNightCycle.reset_for_new_map(0)
	assert_bool(DayNightCycle.is_night()).is_false()
	DayNightCycle.from_dict(SaveGame.read_cycle())

	assert_bool(DayNightCycle.is_night()).is_true()
	assert_int(DayNightCycle.day_number).is_equal(day)
	assert_float(DayNightCycle.time_left).is_equal_approx(left, 0.01)


func test_cycle_ignores_missing_and_absurd_values() -> void:
	DayNightCycle.reset_for_new_map(0)

	DayNightCycle.from_dict({"day_number": "x", "phase": [], "time_left": -50.0})
	assert_int(DayNightCycle.day_number).is_equal(1)
	assert_bool(DayNightCycle.is_night()).is_false()
	assert_float(DayNightCycle.time_left).is_greater(0.0)

	DayNightCycle.from_dict({"day_number": -4, "phase": 7, "time_left": 1.0e9})
	assert_int(DayNightCycle.day_number).is_equal(1)
	assert_bool(DayNightCycle.is_night()).is_false()
	assert_float(DayNightCycle.time_left).is_equal(DayNightCycle.day_duration)

	DayNightCycle.from_dict({})
	assert_float(DayNightCycle.time_left).is_equal(DayNightCycle.day_duration)


# --- Map 2 -------------------------------------------------------------------

func test_crops_and_the_farmer_survive_continue() -> void:
	var farm: FarmMap = await _spawn(FARM_SCENE)
	var plots := get_tree().get_nodes_in_group("crops")
	var growing: CropPlot = plots[0]
	var ripe: CropPlot = plots[1]
	var tilled: CropPlot = plots[2]
	var growing_name := String(growing.name)
	var ripe_name := String(ripe.name)
	var tilled_name := String(tilled.name)
	GameState.select_seed("pumpkin")
	growing.state = CropPlot.State.TILLED
	growing.interact(farm.player)
	growing.growth = 7.5
	ripe.from_dict({"state": CropPlot.State.READY, "crop": "tomato", "growth": 16.0})
	tilled.from_dict({"state": CropPlot.State.TILLED, "crop": "corn"})
	farm.player.global_position = Vector2(1700, 1900)
	var seeds_left := GameState.seed_count("pumpkin")

	await _quit_and_continue(farm)
	var again: FarmMap = await _spawn(FARM_SCENE)

	var restored: CropPlot = again.get_node("World").find_child(growing_name, true, false)
	assert_int(restored.state).is_equal(CropPlot.State.GROWING)
	assert_str(restored.crop_type).is_equal("pumpkin")
	assert_float(restored.growth).is_equal_approx(7.5, 0.5)
	var restored_ripe: CropPlot = again.get_node("World").find_child(ripe_name, true, false)
	assert_int(restored_ripe.state).is_equal(CropPlot.State.READY)
	assert_str(restored_ripe.crop_type).is_equal("tomato")
	var restored_tilled: CropPlot = again.get_node("World").find_child(tilled_name, true, false)
	assert_int(restored_tilled.state).is_equal(CropPlot.State.TILLED)
	assert_int(GameState.seed_count("pumpkin")).is_equal(seeds_left)
	assert_float(again.player.global_position.distance_to(Vector2(1700, 1900))).is_less(16.0)
	await _dispose(again)


func test_a_fresh_farm_ignores_a_broken_world() -> void:
	Campaign.current_map = 2
	SaveGame.world = {2: {"plots": "oops", "player": [99999, -5]}}
	var farm: FarmMap = await _spawn(FARM_SCENE)

	assert_object(farm.player).is_not_null()
	assert_bool(Rect2(Vector2.ZERO, FarmMap.FARM_SIZE).has_point(farm.player.global_position)).is_true()
	await _dispose(farm)


func test_crop_plot_refuses_an_invalid_state() -> void:
	var farm: FarmMap = await _spawn(FARM_SCENE)
	var plot: CropPlot = get_tree().get_nodes_in_group("crops")[0]
	plot.from_dict({"state": CropPlot.State.TILLED, "crop": "corn"})

	plot.from_dict({"state": 12, "crop": "corn"})
	plot.from_dict({"state": CropPlot.State.READY, "crop": "ananas"})
	plot.from_dict({"state": "ready", "crop": "corn"})
	plot.from_dict({})

	assert_int(plot.state).is_equal(CropPlot.State.TILLED)
	plot.from_dict({"state": CropPlot.State.GROWING, "crop": "corn", "growth": "soon"})
	assert_float(plot.growth).is_equal(0.0)
	assert_dict(plot.to_dict()).is_equal(
		{"state": CropPlot.State.GROWING, "crop": "corn", "growth": 0.0})
	await _dispose(farm)


# --- Map 1 -------------------------------------------------------------------

func test_checkpoint_bars_and_pickups_survive_continue() -> void:
	var map: MaroonMap = await _spawn(MAROON_SCENE)
	var player: Node2D = map.get_node("World/Player")
	var survival: Node = player.get_node("Survival")
	var checkpoint: Vector2 = map.get_node("World/ForestCheckpoint").global_position
	map.call("_on_checkpoint_reached", checkpoint)
	survival.call("add_food", -60.0)
	survival.call("add_water", -25.0)
	var food := float(survival.get("food"))
	var water := float(survival.get("water"))
	var seed_spot: Node = null
	for node: Node in get_tree().get_nodes_in_group("forage_spots"):
		if not String(node.get("seed_crop")).is_empty():
			seed_spot = node
			break
	var spot_name := String(seed_spot.name)
	seed_spot.call("interact", player)
	var seeds_before := Campaign.bonus_seeds.duplicate(true)
	assert_int(Campaign.task_progress("gather_seeds", 1)).is_equal(1)

	await _quit_and_continue(map)
	var again: MaroonMap = await _spawn(MAROON_SCENE)
	var player_again: Node2D = again.get_node("World/Player")
	var survival_again: Node = player_again.get_node("Survival")

	assert_float(player_again.global_position.distance_to(checkpoint)).is_less(16.0)
	assert_float(float(survival_again.get("food"))).is_equal_approx(food, 0.5)
	assert_float(float(survival_again.get("water"))).is_equal_approx(water, 0.5)
	var spot_again: Node = again.get_node("World").find_child(spot_name, true, false)
	assert_bool(bool(spot_again.call("is_used"))).is_true()
	assert_str(String(spot_again.call("get_interaction_prompt"))).is_empty()

	# Regression: pickups respawned on Continue and bonus seeds could be farmed.
	spot_again.call("interact", player_again)
	assert_dict(Campaign.bonus_seeds).is_equal(seeds_before)
	assert_int(Campaign.task_progress("gather_seeds", 1)).is_equal(1)
	await _dispose(again)


func test_a_fresh_escape_ignores_a_broken_world() -> void:
	SaveGame.world = {1: {"respawn": [-10, 99999], "used_spots": "all", "food": "lots"}}
	var map: MaroonMap = await _spawn(MAROON_SCENE)
	var player: Node2D = map.get_node("World/Player")

	assert_vector(player.global_position).is_equal(
		map.get_node("World/StartCheckpoint").global_position)
	assert_float(float(player.get_node("Survival").get("food"))).is_greater(90.0)
	await _dispose(map)


# --- Map 3 -------------------------------------------------------------------

func test_the_heir_resumes_where_they_stood() -> void:
	GameState.money = 80
	Campaign.current_map = 3
	var map: HeirMap = await _spawn(HEIR_SCENE)
	var player: Node2D = map.get_node("World/Player")
	player.global_position = Vector2(1500, 1700)
	Campaign.set_choice("visited_belvedere", "1")

	await _quit_and_continue(map)
	var again: HeirMap = await _spawn(HEIR_SCENE)

	# One physics frame has run since the restore, so allow a few pixels.
	assert_float((again.get_node("World/Player") as Node2D).global_position
		.distance_to(Vector2(1500, 1700))).is_less(16.0)
	assert_str(Campaign.get_choice("visited_belvedere")).is_equal("1")
	await _dispose(again)


func test_a_shuttle_passenger_has_no_position_to_save() -> void:
	Campaign.current_map = 3
	var map: HeirMap = await _spawn(HEIR_SCENE)
	var player: Node2D = map.get_node("World/Player")
	assert_bool(map.save_world().has("player")).is_true()

	(get_tree().get_nodes_in_group("bus_stops")[0] as Node).call("interact", player)

	assert_dict(map.save_world()).is_empty()
	await map.ride_finished
	assert_bool(map.save_world().has("player")).is_true()
	await _dispose(map)


func test_the_heir_ignores_a_position_outside_the_map() -> void:
	Campaign.current_map = 3
	SaveGame.world = {3: {"player": [-500, 100]}}
	var map: HeirMap = await _spawn(HEIR_SCENE)

	assert_bool(Rect2(Vector2.ZERO, HeirMap.MAP_SIZE).has_point(
		(map.get_node("World/Player") as Node2D).global_position)).is_true()
	await _dispose(map)
