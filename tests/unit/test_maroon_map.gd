extends GdUnitTestSuite

const MAROON_SCENE := preload("res://game/world/maps/Maroon.tscn")
const TEST_SAVE_PATH := "user://test_maroon_save.json"

var _original_save_path := ""


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	GameState.playing = false
	Campaign.reset()


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	GameState.farm_active = true
	DayNightCycle.nights_required_for_next_map = 2
	DayNightCycle.nights_spent = 0
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


func test_map_builds_player_survival_and_generation_ui() -> void:
	var map := await _spawn_map()

	assert_object(map.get_node_or_null("World/Player")).is_not_null()
	assert_object(map.get_node_or_null("SurvivalHUD")).is_not_null()
	assert_object(map.get_node_or_null("TaskList")).is_not_null()
	assert_object(map.get_node_or_null("GenerationResult")).is_not_null()
	var survival := map.get_node("World/Player/Survival")
	assert_bool(bool(survival.get("active"))).is_true()


func test_map_places_guards_forage_hides_and_checkpoints() -> void:
	var map := await _spawn_map()

	assert_int(get_tree().get_nodes_in_group("guards").size()).is_equal(5)
	assert_int(get_tree().get_nodes_in_group("forage_spots").size()).is_equal(5)
	assert_int(get_tree().get_nodes_in_group("hide_spots").size()).is_equal(3)
	assert_object(map.get_node_or_null("World/UpperCheckpoint")).is_not_null()


func test_forage_restores_food_and_advances_find_food() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var survival := player.get_node("Survival")
	survival.set("food", 40.0)

	var spots := get_tree().get_nodes_in_group("forage_spots")
	var food_spot: Area2D = null
	for spot: Node in spots:
		if String(spot.get("kind")) == "food":
			food_spot = spot
			break
	assert_object(food_spot).is_not_null()
	food_spot.call("_on_body_entered", player)

	assert_float(float(survival.get("food"))).is_greater(40.0)
	assert_int(Campaign.task_progress("find_food")).is_equal(1)
	assert_bool(food_spot.call("is_used")).is_true()


func test_hiding_completes_hide_task_and_conceals_player() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var spots := get_tree().get_nodes_in_group("hide_spots")
	var hide_spot: Area2D = spots[0]

	hide_spot.call("_on_body_entered", player)
	assert_bool(bool(player.get("concealed"))).is_true()
	hide_spot.call("_process", 2.0)

	assert_int(Campaign.task_status("hide_from_patrol")).is_equal(Campaign.TaskStatus.DONE)
	hide_spot.call("_on_body_exited", player)
	assert_bool(bool(player.get("concealed"))).is_false()


func test_upper_checkpoint_completes_cross_patrol() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var checkpoint: Area2D = map.get_node("World/UpperCheckpoint")

	checkpoint.call("_on_body_entered", player)

	assert_int(Campaign.task_status("cross_patrol")).is_equal(Campaign.TaskStatus.DONE)


func test_refuge_waits_for_the_generation_tasks() -> void:
	var map := await _spawn_map()
	var exit: Area2D = map.get_node("RefugeExit")

	assert_str(String(exit.get("complete_task_on_enter"))).is_equal("reach_refuge")
	assert_bool(bool(exit.get("requires_map_complete"))).is_true()
	assert_bool(exit.call("can_leave")).is_false()

	for definition: Dictionary in Campaign.TASKS[1]:
		var task_id := String(definition["id"])
		if task_id != "reach_refuge":
			Campaign.complete_task(task_id)
	assert_bool(exit.call("can_leave")).is_false()

	Campaign.complete_task("reach_refuge")
	assert_bool(exit.call("can_leave")).is_true()


func test_concealed_player_is_not_seen_by_a_guard() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var guard: CharacterBody2D = get_tree().get_nodes_in_group("guards")[0]
	var ray := guard.get_node_or_null("VisionRay") as RayCast2D
	if ray != null:
		ray.enabled = false
	guard.set("facing", Vector2.RIGHT)
	player.global_position = guard.global_position + Vector2(200, 0)
	player.call("set_hidden", true)

	assert_bool(guard.call("_sees_player")).is_false()

	player.call("set_hidden", false)
	guard.set("facing", Vector2.RIGHT)
	assert_bool(guard.call("_sees_player")).is_true()
