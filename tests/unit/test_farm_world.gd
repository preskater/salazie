extends GdUnitTestSuite
## The farm as a place: the cyclone's wind, what the interact key reaches, the
## market deadline, and the small things that live there.

const FARM_SCENE := preload("res://scenes/maps/farm.tscn")
const CYCLONE_SCENE := preload("res://scenes/world/fx/cyclone.tscn")
const CROP_PLOT_SCENE := preload("res://scenes/farm/crop_plot.tscn")
const ANIMAL_SCENE := preload("res://scenes/farm/animals/animal.tscn")
const LEAVES_SCENE := preload("res://scenes/world/ambient_leaves.tscn")
const CHICKEN_SHEET := "res://sprites/farm_48x48/animals/Chickens_and_Roosters_48x48/Chicken_White_48x48.png"
const LEAF_FRAMES := "res://game_resources/animations/Leaves_Green.tres"
const TREE_SHAKE_FRAMES := "res://game_resources/animations/Tree_Oak_Green_Big_Shake.tres"
const TEST_SAVE_PATH := "user://test_farm_world_save.json"
const MAX_PHYSICS_FRAMES := 30

var _original_save_path := ""


## Stands in for the player: records what the cyclone does to it and never moves.
class WindVane extends CharacterBody2D:
	var winds: Array[Vector2] = []
	var knockbacks: Array[Vector2] = []
	var stuns: Array[float] = []

	func add_wind(v: Vector2) -> void:
		winds.append(v)

	func apply_knockback(v: Vector2) -> void:
		knockbacks.append(v)

	func stun(duration: float) -> void:
		stuns.append(duration)


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	GameState.playing = false
	GameState.farm_active = true
	Campaign.reset()
	GameState.reset()


func after_test() -> void:
	if get_tree() != null:
		get_tree().paused = false
	GameState.playing = false
	GameState.farm_active = true
	Campaign.reset()
	GameState.reset()
	SaveGame.save_path = _original_save_path
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _spawn_farm() -> FarmMap:
	var map: FarmMap = FARM_SCENE.instantiate()
	add_child(auto_free(map))
	await get_tree().process_frame
	await get_tree().physics_frame
	return map


func _plot(map: FarmMap, plot_name: String) -> CropPlot:
	return map.get_node("World/" + plot_name) as CropPlot


## A plot of the starting garden, put back to bare ground.
func _untouched_plot(map: FarmMap) -> CropPlot:
	var plot := _plot(map, "Plot_32_35")
	plot.from_dict({"state": CropPlot.State.EMPTY, "crop": "corn", "growth": 0.0})
	return plot


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


## Puts the farmer on a spot and lets the map pick what is in reach.
func _stand_at(map: FarmMap, spot: Vector2) -> void:
	map.player.global_position = spot
	map._process(0.0)


func _listen() -> Array[String]:
	var messages: Array[String] = []
	var on_notify := func(text: String) -> void: messages.append(text)
	GameState.notification_requested.connect(on_notify)
	# Disconnected with the suite's helper node, which dies with the test.
	var holder: Node = auto_free(Node.new())
	holder.tree_exiting.connect(func() -> void:
		if GameState.notification_requested.is_connected(on_notify):
			GameState.notification_requested.disconnect(on_notify))
	add_child(holder)
	return messages


func _heard(messages: Array[String], fragment: String) -> bool:
	return messages.any(func(text: String) -> bool: return text.contains(fragment))


func _spawn_cyclone(at: Vector2) -> Node2D:
	var cyclone: Node2D = auto_free(CYCLONE_SCENE.instantiate())
	cyclone.position = at
	add_child(cyclone)
	return cyclone


func _spawn_vane(at: Vector2) -> WindVane:
	var vane: WindVane = auto_free(WindVane.new())
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	vane.add_child(shape)
	vane.position = at
	add_child(vane)
	return vane


# --- Cyclone -----------------------------------------------------------------

func test_the_wind_pulls_towards_the_eye_and_stops_at_the_edge() -> void:
	var cyclone := _spawn_cyclone(Vector2(500, 500))
	var radius: float = cyclone.pull_radius

	var near: Vector2 = cyclone.get_wind_at(Vector2(500 + radius * 0.25, 500))
	var far: Vector2 = cyclone.get_wind_at(Vector2(500 + radius * 0.75, 500))

	# East of the eye the pull is westward, and stronger closer in.
	assert_float(near.x).is_less(0.0)
	assert_float(far.x).is_less(0.0)
	assert_float(near.length()).is_greater(far.length())
	var falloff := pow(0.5, float(cyclone.falloff_power))
	var halfway: Vector2 = cyclone.get_wind_at(Vector2(500 + radius * 0.5, 500))
	assert_vector(halfway).is_equal_approx(
		Vector2(-cyclone.pull_speed * falloff, -cyclone.swirl_speed * falloff),
		Vector2(0.01, 0.01))

	assert_vector(cyclone.get_wind_at(Vector2(500 + radius + 1.0, 500))).is_equal(Vector2.ZERO)
	assert_vector(cyclone.get_wind_at(Vector2(500, 500))).is_equal(Vector2.ZERO)
	assert_bool(cyclone.is_in_group("cyclones")).is_true()


func test_the_swirl_turns_the_other_way_when_the_spin_is_reversed() -> void:
	var cyclone := _spawn_cyclone(Vector2(500, 500))
	var spot := Vector2(500 + float(cyclone.pull_radius) * 0.5, 500)

	var clockwise: Vector2 = cyclone.get_wind_at(spot)
	cyclone.spin = -1.0
	var counter: Vector2 = cyclone.get_wind_at(spot)

	assert_float(counter.x).is_equal_approx(clockwise.x, 0.01)
	assert_float(counter.y).is_equal_approx(-clockwise.y, 0.01)
	assert_float(absf(clockwise.y)).is_greater(1.0)


func test_a_body_in_the_field_is_blown_by_the_wind_of_its_spot() -> void:
	var cyclone := _spawn_cyclone(Vector2(500, 500))
	var vane := _spawn_vane(Vector2(540, 500))
	var outside := _spawn_vane(Vector2(900, 500))

	for _frame in MAX_PHYSICS_FRAMES:
		await get_tree().physics_frame
		if not vane.winds.is_empty():
			break

	assert_bool(vane.winds.is_empty()).override_failure_message(
		"The cyclone never blew on a body inside its field").is_false()
	var expected: Vector2 = cyclone.get_wind_at(vane.global_position)
	assert_vector(vane.winds[-1]).is_equal_approx(expected, Vector2(0.01, 0.01))
	assert_float(expected.length()).is_greater(1.0)
	assert_array(vane.knockbacks).is_empty()
	assert_array(outside.winds).is_empty()


func test_a_body_reaching_the_eye_is_thrown_out_then_left_alone_for_a_while() -> void:
	var cyclone := _spawn_cyclone(Vector2(500, 500))
	var vane := _spawn_vane(Vector2(505, 500))
	var ejected: Array[Node2D] = []
	cyclone.body_ejected.connect(func(body: Node2D) -> void: ejected.append(body))

	for _frame in MAX_PHYSICS_FRAMES:
		await get_tree().physics_frame
		if not vane.knockbacks.is_empty():
			break

	assert_int(vane.knockbacks.size()).is_equal(1)
	if vane.knockbacks.is_empty():
		return
	# Straight away from the eye, plus half of that as a sideways kick.
	assert_vector(vane.knockbacks[0]).is_equal_approx(
		Vector2(cyclone.eject_speed, cyclone.eject_speed * cyclone.eject_spin),
		Vector2(0.01, 0.01))
	assert_array(vane.stuns).is_equal([0.25])
	assert_array(ejected).is_equal([vane])

	# Grace: no wind. Cooldown: no second ejection.
	for _frame in 3:
		await get_tree().physics_frame
	assert_int(vane.knockbacks.size()).is_equal(1)
	assert_array(vane.winds).is_empty()

	# Grace over, cooldown still running: the wind takes the body again.
	cyclone._physics_process(float(cyclone.eject_grace) + 0.05)
	assert_int(vane.winds.size()).is_equal(1)
	assert_int(vane.knockbacks.size()).is_equal(1)

	# Cooldown over: a body still in the eye is thrown out again.
	cyclone._physics_process(float(cyclone.eject_cooldown))
	assert_int(vane.knockbacks.size()).is_equal(2)
	assert_int(ejected.size()).is_equal(2)


func test_a_body_exactly_on_the_eye_is_thrown_downwards() -> void:
	var cyclone := _spawn_cyclone(Vector2(500, 500))
	var vane := _spawn_vane(Vector2(500, 500))

	for _frame in MAX_PHYSICS_FRAMES:
		await get_tree().physics_frame
		if not vane.knockbacks.is_empty():
			break

	assert_int(vane.knockbacks.size()).is_equal(1)
	if vane.knockbacks.is_empty():
		return
	assert_vector(vane.knockbacks[0]).is_equal_approx(
		Vector2(-cyclone.eject_speed * cyclone.eject_spin, cyclone.eject_speed),
		Vector2(0.01, 0.01))


# --- Farm map: arriving ------------------------------------------------------

func test_the_farm_brings_back_its_own_economy() -> void:
	Economy.select_generation(&"heritier")

	var map := await _spawn_farm()

	assert_str(String(Economy.current_generation_id())).is_equal("cultivateur")
	assert_str(String(GameState.currency_id())).is_equal("gourde")
	assert_object(map.hud.buy_rows.get_node_or_null("Buy_building_barn")).is_not_null()


func test_arriving_after_the_market_deadline_fails_prosperity() -> void:
	GameState.day = FarmMap.PROSPERITY_DEADLINE_DAY

	await _spawn_farm()

	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.FAILED)
	assert_str(Campaign.task_last_failure("earn_100")).contains("Délai dépassé").contains("100 G")


func test_the_deadline_fails_prosperity_only_while_it_is_still_open() -> void:
	var map := await _spawn_farm()
	map.cyclone_legs = 0
	var messages := _listen()

	GameState.day_changed.emit(FarmMap.PROSPERITY_DEADLINE_DAY - 1)
	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.PENDING)

	GameState.day_changed.emit(FarmMap.PROSPERITY_DEADLINE_DAY)
	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.FAILED)
	assert_bool(_heard(messages, "délai du marché")).is_true()
	assert_int(Campaign.task_failure_count("earn_100")).is_equal(1)

	# A later day does not fail it a second time.
	GameState.day_changed.emit(FarmMap.PROSPERITY_DEADLINE_DAY + 1)
	assert_int(Campaign.task_failure_count("earn_100")).is_equal(1)


func test_a_farm_that_prospered_in_time_keeps_its_success() -> void:
	var map := await _spawn_farm()
	map.cyclone_legs = 0
	GameState.money = FarmMap.PROSPERITY_GOAL
	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.DONE)

	GameState.day_changed.emit(FarmMap.PROSPERITY_DEADLINE_DAY)

	assert_int(Campaign.task_status("earn_100")).is_equal(Campaign.TaskStatus.DONE)
	assert_int(Campaign.task_failure_count("earn_100")).is_equal(0)


func test_the_road_to_town_is_installed_once() -> void:
	var map := await _spawn_farm()
	var exit := map.get_node("MapExit")

	assert_str(String(exit.get("next_scene_path"))).is_equal(SceneRouter.HEIR_SCENE)
	assert_bool(bool(exit.get("requires_map_complete"))).is_true()
	assert_str((map.get_node("RoadSignLabel") as Label).text).is_equal("Route de la ville")

	# A farm scene that already carries its exit keeps it as it is.
	var prepared: FarmMap = FARM_SCENE.instantiate()
	var own_exit := Node2D.new()
	own_exit.name = "MapExit"
	prepared.add_child(own_exit)
	add_child(auto_free(prepared))
	await get_tree().process_frame

	assert_object(prepared.get_node("MapExit")).is_same(own_exit)
	assert_object(prepared.get_node_or_null("RoadSign")).is_null()
	assert_object(prepared.get_node_or_null("RoadSignLabel")).is_null()


# --- Farm map: reach and keys ------------------------------------------------

func test_only_things_with_a_place_in_the_world_can_be_reached() -> void:
	var map := await _spawn_farm()
	var plot := _untouched_plot(map)
	# In the group, but with no position: it can never be the closest thing.
	var ledger: Node = auto_free(Node.new())
	ledger.add_to_group("interactable")
	map.add_child(ledger)

	_stand_at(map, Vector2(96, 96))
	assert_bool(map.hud.prompt_panel.visible).is_false()

	_stand_at(map, plot.global_position)
	assert_str(map.hud.prompt_label.text).is_equal(plot.get_interaction_prompt())


func test_the_prompt_names_what_is_in_reach() -> void:
	var map := await _spawn_farm()
	var plot := _untouched_plot(map)

	_stand_at(map, plot.global_position)
	assert_bool(map.hud.prompt_panel.visible).is_true()
	assert_str(map.hud.prompt_label.text).is_equal(plot.get_interaction_prompt())
	assert_str(map.hud.prompt_label.text).contains("Préparer la parcelle")

	# Somewhere with nothing within arm's length.
	var nowhere := Vector2(96, 96)
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		assert_float((node as Node2D).global_position.distance_to(nowhere)) \
			.is_greater(FarmMap.INTERACT_RANGE)
	_stand_at(map, nowhere)
	assert_bool(map.hud.prompt_panel.visible).is_false()


func test_the_interact_key_works_the_plot_in_reach() -> void:
	var map := await _spawn_farm()
	var plot := _untouched_plot(map)
	_stand_at(map, plot.global_position)

	map._unhandled_input(_press(&"interact"))

	assert_int(plot.state).is_equal(CropPlot.State.TILLED)
	assert_int(Campaign.task_status("prepare_plot")).is_equal(Campaign.TaskStatus.DONE)

	GameState.select_seed("tomato")
	map._unhandled_input(_press(&"interact"))

	assert_int(plot.state).is_equal(CropPlot.State.GROWING)
	assert_str(plot.crop_type).is_equal("tomato")
	assert_int(Campaign.task_status("plant_seed")).is_equal(Campaign.TaskStatus.DONE)


func test_the_interact_key_does_nothing_out_of_reach_or_while_paused() -> void:
	var map := await _spawn_farm()
	var plot := _untouched_plot(map)

	_stand_at(map, Vector2(96, 96))
	map._unhandled_input(_press(&"interact"))
	assert_int(plot.state).is_equal(CropPlot.State.EMPTY)

	_stand_at(map, plot.global_position)
	get_tree().paused = true
	map._unhandled_input(_press(&"interact"))
	map._unhandled_input(_press(&"select_seed_3"))
	assert_int(plot.state).is_equal(CropPlot.State.EMPTY)
	assert_str(GameState.selected_seed).is_equal("corn")


func test_the_number_keys_pick_the_seed() -> void:
	var map := await _spawn_farm()

	for index in GameState.CROP_ORDER.size():
		map._unhandled_input(_press(StringName("select_seed_%d" % (index + 1))))
		assert_str(GameState.selected_seed).is_equal(GameState.CROP_ORDER[index])

	# A key the farm does not use changes nothing.
	map._unhandled_input(_press(&"toggle_prices"))
	assert_str(GameState.selected_seed).is_equal(GameState.CROP_ORDER[-1])


func test_the_market_stand_opens_the_market() -> void:
	var map := await _spawn_farm()
	var stand := map.market_stand
	assert_bool(stand.is_in_group("interactable")).is_true()

	_stand_at(map, stand.global_position)
	assert_str(map.hud.prompt_label.text).is_equal(stand.get_interaction_prompt())
	assert_str(stand.get_interaction_prompt()).contains("Marché de Salazie")

	map._unhandled_input(_press(&"interact"))

	assert_bool(map.hud.market_overlay.visible).is_true()
	assert_bool(get_tree().paused).is_true()


# --- Farm map: events --------------------------------------------------------

func test_a_strike_reports_the_crops_it_destroyed() -> void:
	var map := await _spawn_farm()
	map.cyclone_legs = 1
	map.cyclone_leg_time = 0.05
	map.cyclone_speed = 10.0
	var plot := _plot(map, "Plot_32_35")
	plot.from_dict({"state": CropPlot.State.READY, "crop": "carrot", "growth": 99.0})
	# A travel zone the size of the plot: the storm cannot miss it.
	map.cyclone_zone = Rect2(plot.global_position - Vector2(4, 4), Vector2(8, 8))
	var produce := GameState.produce_count("carrot")
	var messages := _listen()

	await map.call("_strike_cyclone")

	assert_bool(_heard(messages, "Le cyclone traverse la ferme")).is_true()
	assert_bool(_heard(messages, "détruit 1 récolte")).is_true()
	assert_bool(_heard(messages, "grange")).is_false()
	assert_int(plot.state).is_equal(CropPlot.State.TILLED)
	assert_int(GameState.produce_count("carrot")).is_equal(produce)


func test_the_cyclone_only_counts_real_plots() -> void:
	var map := await _spawn_farm()
	var plot := _plot(map, "Plot_32_35")
	plot.from_dict({"state": CropPlot.State.READY, "crop": "corn", "growth": 99.0})
	# A scarecrow planted among the crops is not a plot.
	var scarecrow: Node2D = auto_free(Node2D.new())
	scarecrow.name = "Scarecrow"
	scarecrow.add_to_group("crops")
	map.get_node("World").add_child(scarecrow)
	scarecrow.global_position = plot.global_position

	var lost: int = map.call("_destroy_ripe_crops_on_path",
		plot.global_position, plot.global_position + Vector2(10, 0))

	assert_int(lost).is_equal(1)
	assert_bool((map.save_world()["plots"] as Dictionary).has("Scarecrow")).is_false()
	assert_bool((map.save_world()["plots"] as Dictionary).has("Plot_32_35")).is_true()


func test_a_locked_road_tells_the_farmer_to_finish_first() -> void:
	var map := await _spawn_farm()
	var messages := _listen()
	var exit := map.get_node("MapExit")

	exit.emit_signal("blocked")

	assert_bool(_heard(messages, "Terminez les tâches de la ferme")).is_true()
	assert_bool(map.hud.notification_label.visible).is_true()


func test_the_objective_points_to_the_road_once_every_task_is_resolved() -> void:
	var map := await _spawn_farm()
	assert_str(map.hud.objective_label.text).starts_with("Objectif : ")

	for definition: Dictionary in Campaign.TASKS[2]:
		Campaign.complete_task(String(definition["id"]))

	assert_str(map.hud.objective_label.text).starts_with("Map 2 terminée")
	assert_str(map.hud.objective_label.text).contains("route vers la ville")


# --- Crop plot ---------------------------------------------------------------

func test_a_tilled_plot_asks_for_seeds_when_the_bag_is_empty() -> void:
	var plot: CropPlot = auto_free(CROP_PLOT_SCENE.instantiate())
	add_child(plot)
	assert_str(plot.get_interaction_prompt()).contains("Préparer la parcelle")
	plot.interact(null)
	assert_str(plot.get_interaction_prompt()).contains("Planter Maïs (2 graines)")
	GameState.seeds["corn"] = 0
	var messages := _listen()

	assert_str(plot.get_interaction_prompt()).is_equal(
		"Plus de graines de Maïs — achetez-en au marché")
	plot.interact(null)

	assert_int(plot.state).is_equal(CropPlot.State.TILLED)
	assert_bool(_heard(messages, "Plus de graines de Maïs")).is_true()
	assert_bool(_heard(messages, "Graine plantée")).is_false()


# --- Life on the farm --------------------------------------------------------

func test_an_animal_without_a_pasture_stays_where_it_is() -> void:
	var animal: Node2D = auto_free(ANIMAL_SCENE.instantiate())
	animal.set("sheet", load(CHICKEN_SHEET))
	animal.set("graze_time", Vector2.ZERO)
	animal.position = Vector2(50, 50)
	add_child(animal)

	for _frame in 5:
		await get_tree().physics_frame

	assert_vector(animal.position).is_equal(Vector2(50, 50))
	var sprite: AnimatedSprite2D = animal.get_node("AnimatedSprite2D")
	assert_str(String(sprite.animation)).is_equal("graze_down")


func test_an_animal_in_a_narrow_run_walks_up_or_down_facing_its_way() -> void:
	var animal: Node2D = auto_free(ANIMAL_SCENE.instantiate())
	animal.set("sheet", load(CHICKEN_SHEET))
	# 24 px wide: once the 12 px margins are taken there is only one column left.
	animal.set("roam_rect", Rect2(0, 0, 24, 400))
	animal.set("graze_time", Vector2.ZERO)
	animal.set("walk_time", Vector2(5, 5))
	animal.position = Vector2(12, 200)
	add_child(animal)
	var sprite: AnimatedSprite2D = animal.get_node("AnimatedSprite2D")

	for _frame in MAX_PHYSICS_FRAMES:
		await get_tree().physics_frame
		if String(sprite.animation).begins_with("walk_") and animal.position.y != 200.0:
			break

	assert_float(animal.position.x).is_equal_approx(12.0, 0.001)
	var expected := "walk_down" if animal.position.y > 200.0 else "walk_up"
	assert_str(String(sprite.animation)).is_equal(expected)


func test_leaves_only_fall_when_they_have_a_fall_animation() -> void:
	var bare: AnimatedSprite2D = auto_free(LEAVES_SCENE.instantiate())
	add_child(bare)
	var wrong: AnimatedSprite2D = auto_free(LEAVES_SCENE.instantiate())
	# A tree's shake frames have no "fall" animation.
	wrong.sprite_frames = load(TREE_SHAKE_FRAMES)
	add_child(wrong)
	var leaves: AnimatedSprite2D = auto_free(LEAVES_SCENE.instantiate())
	leaves.sprite_frames = load(LEAF_FRAMES)
	add_child(leaves)

	assert_bool(bare.is_playing()).is_false()
	assert_bool(wrong.is_playing()).is_false()
	assert_float(wrong.speed_scale).is_equal(1.0)
	assert_bool(leaves.is_playing()).is_true()
	assert_str(String(leaves.animation)).is_equal("fall")
	assert_float(leaves.speed_scale).is_between(0.7, 1.3)
