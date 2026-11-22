extends GdUnitTestSuite
## Map 1 from the player's side: what `interact` reaches, the drink prompt and
## its cooldown, the objective bar, the notifications and the clock.

const MAROON_SCENE := preload("res://scenes/maps/maroon.tscn")
const LAYOUT := preload("res://scripts/maroon/maroon_layout.gd")
const TEST_SAVE_PATH := "user://test_maroon_interactions.json"
const TILE := 48.0
## Far enough from every pickup, climb and bush to leave the prompt to the river.
const CLEAR_OF_INTERACTABLES := 160.0

var _original_save_path := ""


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	GameState.playing = false
	SceneRouter.is_gameplay = false
	GameState.reset()
	Campaign.reset()


func after_test() -> void:
	GameState.playing = false
	Campaign.reset()
	GameState.reset()
	GameState.farm_active = true
	SceneRouter.is_gameplay = false
	DayNightCycle.phase = DayNightCycle.Phase.DAY
	DayNightCycle.nights_required_for_next_map = 2
	DayNightCycle.nights_spent = 0
	DayNightCycle.running = false
	DayNightCycle.tint_enabled = false
	SaveGame.save_path = _original_save_path
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if get_tree() != null:
		get_tree().paused = false


func _spawn_map() -> MaroonMap:
	var map: MaroonMap = MAROON_SCENE.instantiate()
	add_child(auto_free(map))
	await get_tree().process_frame
	await get_tree().physics_frame
	return map


func _finish_respawn(map: MaroonMap) -> void:
	while bool(map.get("_respawning")):
		await get_tree().process_frame


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _player(map: MaroonMap) -> Node2D:
	return map.get_node("World/Player") as Node2D


func _prompt_label(map: MaroonMap) -> Label:
	return map.get_node("MaroonUI/Root/PromptLabel") as Label


func _notice(map: MaroonMap) -> Label:
	return map.get_node("MaroonUI/Root/Notification") as Label


func _seed_spot() -> Area2D:
	for node: Node in get_tree().get_nodes_in_group("forage_spots"):
		if String(node.get("kind")) == "seed":
			return node as Area2D
	return null


func _food_spots(map: MaroonMap) -> Array[Area2D]:
	var spots: Array[Area2D] = []
	for node: Node in get_tree().get_nodes_in_group("forage_spots"):
		if map.is_ancestor_of(node) and String(node.get("kind")) == "food":
			spots.append(node as Area2D)
	return spots


func _nearest_unused(spots: Array[Area2D], from: Vector2) -> Area2D:
	var best: Area2D = null
	for spot: Area2D in spots:
		if bool(spot.call("is_used")):
			continue
		if best == null or from.distance_to(spot.global_position) \
				< from.distance_to(best.global_position):
			best = spot
	return best


func _is_clear_of_interactables(point: Vector2) -> bool:
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		var node2d := node as Node2D
		if node2d != null and node2d.global_position.distance_to(point) < CLEAR_OF_INTERACTABLES:
			return false
	return true


func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE + TILE * 0.5, tile.y * TILE + TILE * 0.5)


## A dry tile next to the river, away from the basin and from anything else
## that answers to `interact`.
func _river_bank(map: MaroonMap) -> Vector2:
	var water: TileMapLayer = map.get_node("Terrain/Water")
	var basin: Vector2 = map.get("_anchors")["water_spot"]
	for cell: Vector2i in water.get_used_cells():
		if cell.y >= LAYOUT.SEA_ROW - 4:
			continue
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT]:
			var bank: Vector2i = cell + offset
			if water.get_cell_source_id(bank) != -1:
				continue
			var point := _tile_center(bank)
			if point.distance_to(basin) <= MaroonMap.WATERFALL_TASK_RADIUS + TILE:
				continue
			if _is_clear_of_interactables(point):
				return point
	return Vector2.ZERO


## A beach tile on the last dry row: the sea is one step away, the river is not.
func _shore(map: MaroonMap) -> Vector2:
	var water: TileMapLayer = map.get_node("Terrain/Water")
	var row: int = LAYOUT.SEA_ROW - 1
	for x in range(3, 69):
		if water.get_cell_source_id(Vector2i(x, LAYOUT.SEA_ROW)) == -1:
			continue
		var fresh := false
		for y in range(row - MaroonMap.DRINK_REACH_TILES, LAYOUT.SEA_ROW):
			for near_x in range(x - MaroonMap.DRINK_REACH_TILES, x + MaroonMap.DRINK_REACH_TILES + 1):
				if water.get_cell_source_id(Vector2i(near_x, y)) != -1:
					fresh = true
		var point := _tile_center(Vector2i(x, row))
		if not fresh and _is_clear_of_interactables(point):
			return point
	return Vector2.ZERO


# --- Entering the map --------------------------------------------------------

func test_a_map_does_not_start_a_gameplay_session_on_its_own() -> void:
	# The router owns the session: a map added by a test must not flip it, or
	# the suite would write saves in the middle of a menu state.
	await _spawn_map()

	assert_bool(SceneRouter.is_gameplay).is_false()
	assert_bool(GameState.playing).is_false()
	assert_bool(GameState.farm_active).is_false()
	assert_int(Campaign.current_map).is_equal(1)


# --- Interact: pickups -------------------------------------------------------

func test_interact_gathers_the_seeds_the_player_stands_on() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var spot := _seed_spot()
	assert_object(spot).is_not_null()
	player.global_position = spot.global_position

	map.call("_process", 0.0)
	assert_bool(_prompt_label(map).visible).is_true()
	assert_str(_prompt_label(map).text).contains("Ramasser des graines")

	map.call("_unhandled_input", _press(&"interact"))

	assert_bool(bool(spot.call("is_used"))).is_true()
	assert_int(int(Campaign.bonus_seeds.get(String(spot.get("seed_crop")), 0))).is_equal(1)
	assert_str(_notice(map).text).contains("Graines sauvages (1/3)")

	# A gathered spot has nothing left to offer.
	map.call("_process", 0.0)
	assert_object(map.get("_interact_target")).is_null()
	assert_bool(_prompt_label(map).visible).is_false()


func test_only_the_interact_action_gathers() -> void:
	var map := await _spawn_map()
	var spot := _seed_spot()
	_player(map).global_position = spot.global_position
	map.call("_process", 0.0)

	map.call("_unhandled_input", _press(&"run"))

	assert_bool(bool(spot.call("is_used"))).is_false()


func test_interact_does_nothing_while_the_game_is_paused() -> void:
	var map := await _spawn_map()
	var spot := _seed_spot()
	_player(map).global_position = spot.global_position
	map.call("_process", 0.0)

	get_tree().paused = true
	map.call("_unhandled_input", _press(&"interact"))
	get_tree().paused = false

	assert_bool(bool(spot.call("is_used"))).is_false()


func test_a_pickup_out_of_reach_is_not_offered() -> void:
	var map := await _spawn_map()
	var spot := _seed_spot()
	_player(map).global_position = spot.global_position \
		+ Vector2(MaroonMap.INTERACT_RANGE + 8.0, 0)

	map.call("_process", 0.0)

	assert_object(map.get("_interact_target")).is_not_same(spot)


func test_things_without_a_place_or_a_prompt_are_never_targeted() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var spot := _seed_spot()
	player.global_position = spot.global_position + Vector2(30, 0)
	# Nearer than the seeds, but neither can be interacted with.
	var abstract_thing: Node = auto_free(Node.new())
	abstract_thing.add_to_group("interactable")
	add_child(abstract_thing)
	var silent_thing: Node2D = auto_free(Node2D.new())
	silent_thing.add_to_group("interactable")
	add_child(silent_thing)
	silent_thing.global_position = player.global_position

	map.call("_process", 0.0)

	assert_object(map.get("_interact_target")).is_same(spot)


func test_the_nearest_of_two_pickups_is_the_one_offered() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var spot := _seed_spot()
	var climb: Area2D = auto_free(MaroonMap.CLIMB_SCENE.instantiate())
	add_child(climb)
	climb.global_position = spot.global_position + Vector2(50, 0)

	player.global_position = spot.global_position + Vector2(10, 0)
	map.call("_process", 0.0)
	assert_object(map.get("_interact_target")).is_same(spot)
	assert_str(_prompt_label(map).text).contains("Ramasser des graines")

	player.global_position = spot.global_position + Vector2(40, 0)
	map.call("_process", 0.0)
	assert_object(map.get("_interact_target")).is_same(climb)
	assert_str(_prompt_label(map).text).contains("Grimper")


# --- Interact: drinking ------------------------------------------------------

func test_interact_on_the_river_bank_drinks_and_starts_the_cooldown() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var survival: Node = player.get_node("Survival")
	var bank := _river_bank(map)
	assert_vector(bank).is_not_equal(Vector2.ZERO)
	player.global_position = bank
	survival.call("add_water", 30.0 - float(survival.get("water")))

	map.call("_process", 0.0)
	assert_object(map.get("_interact_target")).is_null()
	assert_str(_prompt_label(map).text).contains("Boire (+10 eau)")

	map.call("_unhandled_input", _press(&"interact"))

	assert_float(float(survival.get("water"))).is_equal_approx(40.0, 0.01)
	# Away from the waterfall basin the sip does not count for the task.
	assert_str(_notice(map).text).contains("rivière")
	assert_int(Campaign.task_status("find_water")).is_equal(Campaign.TaskStatus.PENDING)

	# The silt has to settle: the prompt counts down and a second sip is refused.
	map.call("_process", 0.0)
	assert_str(_prompt_label(map).text).is_equal(
		"L'eau se décante — %d s" % ceili(MaroonMap.DRINK_COOLDOWN))
	map.call("_unhandled_input", _press(&"interact"))
	assert_float(float(survival.get("water"))).is_equal_approx(40.0, 0.01)
	assert_str(_notice(map).text).contains("trouble")

	map.call("_process", MaroonMap.DRINK_COOLDOWN)
	assert_str(_prompt_label(map).text).contains("Boire (+10 eau)")
	map.call("_unhandled_input", _press(&"interact"))
	assert_float(float(survival.get("water"))).is_equal_approx(50.0, 0.01)


func test_sea_water_cannot_be_drunk() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var survival: Node = player.get_node("Survival")
	var shore := _shore(map)
	assert_vector(shore).is_not_equal(Vector2.ZERO)
	player.global_position = shore
	survival.call("add_water", 30.0 - float(survival.get("water")))

	map.call("_process", 0.0)
	assert_bool(bool(map.call("_is_near_fresh_water"))).is_false()
	assert_bool(_prompt_label(map).visible).is_false()

	map.call("_unhandled_input", _press(&"interact"))

	assert_float(float(survival.get("water"))).is_equal_approx(30.0, 0.01)
	assert_float(float(map.get("_drink_cooldown"))).is_equal(0.0)


# --- Interact while the player has no control --------------------------------

func test_interact_is_ignored_while_waking_at_a_checkpoint() -> void:
	var map := await _spawn_map()
	var spot := _seed_spot()
	_player(map).global_position = spot.global_position
	map.call("_process", 0.0)
	assert_bool(_prompt_label(map).visible).is_true()

	(map.get_node("World/Guard1") as Node).emit_signal("caught")
	map.call("_unhandled_input", _press(&"interact"))
	map.call("_process", 0.0)

	assert_bool(bool(spot.call("is_used"))).is_false()
	assert_bool(_prompt_label(map).visible).is_false()
	await _finish_respawn(map)


func test_interact_is_ignored_during_a_climb() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var spot := _seed_spot()
	var climb: Area2D = get_tree().get_nodes_in_group("climb_points")[0]
	player.global_position = spot.global_position
	map.call("_process", 0.0)

	climb.call("interact", player)
	map.call("_unhandled_input", _press(&"interact"))
	map.call("_process", 0.0)

	assert_bool(bool(spot.call("is_used"))).is_false()
	assert_bool(_prompt_label(map).visible).is_false()
	await map.climb_finished


func test_a_second_climb_request_during_a_climb_is_ignored() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var climbs := get_tree().get_nodes_in_group("climb_points")
	var first: Area2D = climbs[0]
	var second: Area2D = climbs[1]
	var finished := [0]
	map.climb_finished.connect(func() -> void: finished[0] += 1)

	first.call("interact", player)
	second.call("interact", player)
	await map.climb_finished
	for _frame in 40:
		await get_tree().process_frame

	assert_int(finished[0]).is_equal(1)
	assert_float(player.global_position.distance_to(first.get("destination"))).is_less(4.0)


func test_a_climb_cannot_start_while_waking_at_a_checkpoint() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var climb: Area2D = get_tree().get_nodes_in_group("climb_points")[0]
	var start: Vector2 = map.get_node("World/StartCheckpoint").global_position
	var finished := [0]
	map.climb_finished.connect(func() -> void: finished[0] += 1)

	(map.get_node("World/Guard1") as Node).emit_signal("caught")
	climb.call("interact", player)
	await _finish_respawn(map)

	assert_int(finished[0]).is_equal(0)
	assert_bool(bool(map.get("_climbing"))).is_false()
	assert_vector(player.global_position).is_equal(start)


# --- Objective bar -----------------------------------------------------------

func test_the_objective_arrow_points_at_each_task_in_turn() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var anchors: Dictionary = map.get("_anchors")
	var bar: Node2D = map.get_node("MaroonUI/Root/ObjectiveBar")
	var arrow: Node2D = bar.get_node("Arrow")
	var label: Label = bar.get_node("ObjectiveLabel")

	map.call("_process", 0.0)
	var to_mouth: Vector2 = anchors["river_mouth_checkpoint"] - player.global_position
	assert_bool(bar.visible).is_true()
	assert_float(arrow.rotation).is_equal_approx(to_mouth.angle(), 0.001)
	assert_str(label.text).is_equal(
		"Objectif : Trouver la rivière — %d m" % roundi(to_mouth.length() / TILE))

	Campaign.complete_task("follow_river")
	map.call("_process", 0.0)
	var to_basin: Vector2 = anchors["water_spot"] - player.global_position
	assert_float(arrow.rotation).is_equal_approx(to_basin.angle(), 0.001)
	assert_str(label.text).contains("Boire à la rivière")

	Campaign.complete_task("find_water")
	Campaign.complete_task("find_food")
	map.call("_process", 0.0)
	var to_refuge: Vector2 = anchors["refuge"] - player.global_position
	assert_float(arrow.rotation).is_equal_approx(to_refuge.angle(), 0.001)
	assert_str(label.text).contains("Rejoindre le refuge du col")


func test_the_food_objective_counts_and_moves_to_the_next_spot() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var bar: Node2D = map.get_node("MaroonUI/Root/ObjectiveBar")
	var arrow: Node2D = bar.get_node("Arrow")
	var label: Label = bar.get_node("ObjectiveLabel")
	var spots := _food_spots(map)
	assert_int(spots.size()).is_greater_equal(3)
	Campaign.complete_task("follow_river")
	Campaign.complete_task("find_water")

	map.call("_process", 0.0)
	var nearest := _nearest_unused(spots, player.global_position)
	assert_str(label.text).contains("Rassembler des vivres (0/3)")
	assert_float(arrow.rotation).is_equal_approx(
		(nearest.global_position - player.global_position).angle(), 0.001)

	# Once picked, the spot is skipped and the arrow turns to the next one.
	nearest.call("interact", player)
	map.call("_process", 0.0)
	var next := _nearest_unused(spots, player.global_position)
	assert_object(next).is_not_same(nearest)
	assert_str(label.text).contains("Rassembler des vivres (1/3)")
	assert_float(arrow.rotation).is_equal_approx(
		(next.global_position - player.global_position).angle(), 0.001)


func test_the_food_objective_ignores_a_spot_removed_from_the_world() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var arrow: Node2D = map.get_node("MaroonUI/Root/ObjectiveBar/Arrow")
	var spots := _food_spots(map)
	Campaign.complete_task("follow_river")
	Campaign.complete_task("find_water")
	var nearest := _nearest_unused(spots, player.global_position)

	spots.erase(nearest)
	nearest.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	map.call("_process", 0.0)

	var next := _nearest_unused(spots, player.global_position)
	assert_bool((map.get_node("MaroonUI/Root/ObjectiveBar") as Node2D).visible).is_true()
	assert_float(arrow.rotation).is_equal_approx(
		(next.global_position - player.global_position).angle(), 0.001)


func test_the_objective_bar_hides_when_no_food_is_left_to_point_at() -> void:
	var map := await _spawn_map()
	var bar: Node2D = map.get_node("MaroonUI/Root/ObjectiveBar")
	Campaign.complete_task("follow_river")
	Campaign.complete_task("find_water")
	map.call("_process", 0.0)
	assert_bool(bar.visible).is_true()

	# A save restored with every spot already taken leaves nothing to show.
	for spot: Area2D in _food_spots(map):
		spot.call("mark_used")
	map.call("_process", 0.0)

	assert_int(Campaign.task_status("find_food")).is_equal(Campaign.TaskStatus.PENDING)
	assert_bool(bar.visible).is_false()


func test_the_objective_bar_keeps_pointing_at_the_refuge_once_the_route_is_done() -> void:
	var map := await _spawn_map()
	var bar: Node2D = map.get_node("MaroonUI/Root/ObjectiveBar")
	map.call("_process", 0.0)
	assert_bool(bar.visible).is_true()

	for task_id: String in ["follow_river", "find_water", "find_food", "reach_refuge"]:
		Campaign.complete_task(task_id)
	map.call("_process", 0.0)

	# The optional seeds never get an arrow of their own: the bar goes back to
	# the cabin, which the player still has to enter.
	assert_int(Campaign.task_status("gather_seeds")).is_equal(Campaign.TaskStatus.PENDING)
	assert_bool(bar.visible).is_true()
	assert_str((map.get("_objective_label") as Label).text).contains("refuge")


# --- Notifications -----------------------------------------------------------

func test_a_notification_fades_after_its_delay_and_the_next_one_shows_again() -> void:
	var map := await _spawn_map()
	var notification := _notice(map)
	var timers := map.find_children("*", "Timer", false, false)
	assert_int(timers.size()).is_equal(1)
	var timer := timers[0] as Timer
	map.call("_notify", "Vivres trouvés.")
	assert_bool(notification.visible).is_true()
	assert_bool(timer.is_stopped()).is_false()
	assert_float(timer.wait_time).is_equal(4.0)

	timer.stop()
	timer.timeout.emit()
	assert_bool(notification.visible).is_false()

	map.call("_on_checkpoint_reached", map.get_node("World/ForestCheckpoint").global_position)
	assert_bool(notification.visible).is_true()
	assert_str(notification.text).contains("Checkpoint")
	assert_bool(timer.is_stopped()).is_false()


func test_the_refuge_says_why_it_stays_closed() -> void:
	var map := await _spawn_map()
	var exit: Area2D = map.get_node("RefugeExit")

	exit.call("_on_body_entered", _player(map))

	assert_str(_notice(map).text).contains("des tâches restent")
	assert_int(Campaign.task_status("reach_refuge")).is_equal(Campaign.TaskStatus.DONE)
	assert_bool(get_tree().paused).is_false()


func test_resolving_the_last_task_announces_the_open_refuge() -> void:
	var map := await _spawn_map()

	for task_id: String in ["follow_river", "find_water", "find_food"]:
		Campaign.complete_task(task_id)
	assert_str(_notice(map).text).not_contains("accomplies")
	Campaign.complete_task("reach_refuge")

	assert_bool(Campaign.is_map_resolved()).is_true()
	assert_str(_notice(map).text).contains("Toutes les tâches sont accomplies")
	# Said once: a later change does not repeat it over whatever came since.
	map.call("_notify", "autre chose")
	Campaign.add_task_progress("gather_seeds", 1)
	assert_str(_notice(map).text).is_equal("autre chose")


func test_stealth_zones_and_bushes_tell_the_player_what_they_do() -> void:
	var map := await _spawn_map()
	var player := _player(map)
	var notification := _notice(map)
	var cave: Area2D = null
	var cascade: Area2D = null
	for node: Node in get_tree().get_nodes_in_group("stealth_zones"):
		if String(node.get("zone_name")) == "la grotte":
			cave = node as Area2D
		elif String(node.get("zone_name")) == "la cascade":
			cascade = node as Area2D

	cave.call("_on_body_entered", player)
	assert_str(notification.text).is_equal("Vous vous fondez dans la grotte.")
	cave.call("_on_body_exited", player)
	assert_str(notification.text).is_equal("Vous quittez la grotte.")

	cascade.call("_on_body_entered", player)
	assert_str(notification.text).is_equal("Le grondement de la cascade couvre vos pas.")
	cascade.call("_on_body_exited", player)

	var bush: Area2D = get_tree().get_nodes_in_group("hide_spots")[0]
	bush.call("_on_body_entered", player)
	bush.call("_process", float(bush.get("required_time")))
	assert_str(notification.text).is_equal("Vous restez caché dans le fourré.")
	bush.call("_on_body_exited", player)


# --- Clock -------------------------------------------------------------------

func test_the_clock_names_the_night() -> void:
	var map := await _spawn_map()
	var clock: Label = map.get_node("MaroonUI/Root/ClockLabel")
	map.call("_process", 1.0)
	assert_str(clock.text).contains("jour")

	DayNightCycle.phase = DayNightCycle.Phase.NIGHT
	map.call("_process", 1.0)

	assert_str(clock.text).contains("nuit")
	assert_str(clock.text).starts_with("Jour %d" % DayNightCycle.day_number)
