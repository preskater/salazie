extends GdUnitTestSuite
## The small pieces the maps are made of: the map exit and its result screen,
## wild pickups, the player's movement, the camera shake and looping sprites.
## The scene swap is replaced by a recorder so an exit can run to its end.

const MAP_EXIT_SCENE := preload("res://scenes/world/map_exit.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const GUARD_SCENE := preload("res://scenes/world/ai/guard/guard.tscn")
const RESULT_SCENE := preload("res://scenes/ui/tasks/generation_result.tscn")
const FORAGE_SCENE := preload("res://scenes/maroon/forage_spot.tscn")
const HIDE_SCENE := preload("res://scenes/maroon/hide_spot.tscn")
const ANIMATED_SHEET := preload("res://scripts/world/animated_sheet.gd")
const AMBIENT_LEAVES := preload("res://scripts/world/ambient_leaves.gd")
const SEED_TEXTURE := "res://sprites/farm_48x48/singles/Crops/Seed_Corn_48x48.png"
const TEST_SAVE_PATH := "user://test_world_helpers.json"
const INPUT_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"run"]

var _original_save_path := ""
var _swaps: Array[String] = []
var _durations: Array[float] = []


class NoiseListener:
	extends Node2D

	var heard: Array[Vector2] = []

	func hear_noise(source: Vector2, _radius: float) -> void:
		heard.append(source)


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	_swaps = []
	var recorder := func(path: String) -> Error:
		_swaps.append(path)
		return OK
	SceneRouter.scene_changer = recorder
	SceneRouter.fade_time = 0.01
	SceneTransition.scene_changer = recorder
	_durations = [SceneTransition.fade_out_duration, SceneTransition.hold_duration,
		SceneTransition.fade_in_duration]
	SceneTransition.fade_out_duration = 0.0
	SceneTransition.hold_duration = 0.0
	SceneTransition.fade_in_duration = 0.0
	GameState.playing = false
	Campaign.reset()
	GameState.reset()
	SceneRouter.is_gameplay = false
	DayNightCycle.nights_required_for_next_map = 2
	DayNightCycle.nights_spent = 0


func after_test() -> void:
	for action: StringName in INPUT_ACTIONS:
		Input.action_release(action)
	SceneRouter.scene_changer = Callable()
	SceneRouter.fade_time = SceneRouter.FADE_TIME
	SceneTransition.scene_changer = Callable()
	SceneTransition.fade_out_duration = _durations[0]
	SceneTransition.hold_duration = _durations[1]
	SceneTransition.fade_in_duration = _durations[2]
	GameState.playing = false
	Campaign.reset()
	GameState.reset()
	GameState.farm_active = true
	SceneRouter.is_gameplay = false
	DayNightCycle.nights_required_for_next_map = 2
	DayNightCycle.nights_spent = 0
	DayNightCycle.running = false
	DayNightCycle.tint_enabled = false
	SaveGame.clear_world()
	SaveGame.save_path = _original_save_path
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if get_tree() != null:
		get_tree().paused = false


func _wait_until(condition: Callable, frames := 600) -> bool:
	for _frame in frames:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _spawn_player(at := Vector2.ZERO) -> CharacterBody2D:
	var player: CharacterBody2D = auto_free(PLAYER_SCENE.instantiate())
	player.position = at
	add_child(player)
	return player


## A player moved by the test's own ticks instead of the physics loop.
func _spawn_driven_player() -> CharacterBody2D:
	var player := _spawn_player()
	player.set_physics_process(false)
	return player


# --- Map exit ----------------------------------------------------------------

## An exit set up like the refuge of Map 1: open once every task is resolved.
func _spawn_gated_exit(scene_path: String, task_on_enter := "") -> Area2D:
	var exit: Area2D = auto_free(MAP_EXIT_SCENE.instantiate())
	exit.next_scene_path = scene_path
	exit.requires_map_ready = false
	exit.requires_map_complete = true
	exit.complete_task_on_enter = task_on_enter
	exit.show_result = true
	add_child(exit)
	return exit


func _spawn_result() -> GenerationResult:
	var overlay: GenerationResult = auto_free(RESULT_SCENE.instantiate())
	add_child(overlay)
	return overlay


func _resolve_map(map_id: int, except := "") -> void:
	for definition: Dictionary in Campaign.TASKS[map_id]:
		if String(definition["id"]) != except:
			Campaign.complete_task(String(definition["id"]), map_id)


func _footer(overlay: GenerationResult) -> String:
	return (overlay.find_child("Footer", true, false) as Label).text


func _confirm(overlay: GenerationResult) -> void:
	(overlay.find_child("ContinueButton", true, false) as Button).pressed.emit()


func _exit_has_left() -> bool:
	return not _swaps.is_empty() and not SceneRouter.is_transitioning()


func test_walking_into_a_closed_exit_still_counts_as_reaching_it() -> void:
	var exit := _spawn_gated_exit(SceneRouter.FARM_SCENE, "reach_refuge")
	var blocked := [0]
	exit.blocked.connect(func() -> void: blocked[0] += 1)

	var player := _spawn_player()
	assert_bool(await _wait_until(func() -> bool: return blocked[0] > 0)).is_true()

	assert_int(Campaign.task_status("reach_refuge")).is_equal(Campaign.TaskStatus.DONE)
	assert_array(_swaps).is_empty()
	# Still closed, still answering: the player can come back later.
	exit.call("_on_body_entered", player)
	assert_int(blocked[0]).is_equal(2)


func test_the_refuge_shows_the_result_then_leaves_for_the_farm() -> void:
	var overlay := _spawn_result()
	_resolve_map(1, "reach_refuge")
	Campaign.record_setback("Repéré par une patrouille", 1)
	var exit := _spawn_gated_exit(SceneRouter.FARM_SCENE, "reach_refuge")
	var taken: Array[String] = []
	exit.exit_taken.connect(func(path: String) -> void: taken.append(path))

	var player := _spawn_player()
	assert_bool(await _wait_until(func() -> bool: return overlay.visible)).is_true()

	assert_int(Campaign.task_status("reach_refuge")).is_equal(Campaign.TaskStatus.DONE)
	assert_array(taken).is_equal([SceneRouter.FARM_SCENE])
	assert_str(overlay.get_title_text()).contains("Map 1")
	assert_str(_footer(overlay)).contains("Prochaine génération")
	assert_str(_footer(overlay)).contains("Prochaine ferme : 25 G")
	# Nothing moves until the player has read the result.
	assert_bool(get_tree().paused).is_true()
	assert_array(_swaps).is_empty()
	assert_int(Campaign.current_map).is_equal(1)

	# Touching the exit again while the result is open does not start over.
	exit.call("_on_body_entered", player)
	assert_array(taken).has_size(1)

	_confirm(overlay)
	assert_bool(await _wait_until(_exit_has_left)).is_true()

	assert_array(_swaps).is_equal([SceneRouter.FARM_SCENE])
	assert_int(Campaign.current_map).is_equal(2)
	assert_int(GameState.money).is_equal(25)
	assert_bool(overlay.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_leaving_the_farm_announces_the_family_heritage() -> void:
	var overlay := _spawn_result()
	Campaign.current_map = 2
	_resolve_map(2)
	GameState.money = 140
	var heritage := Campaign.heritage_for_map3()
	assert_int(heritage).is_greater_equal(140)
	_spawn_gated_exit(SceneRouter.HEIR_SCENE)

	_spawn_player()
	assert_bool(await _wait_until(func() -> bool: return overlay.visible)).is_true()
	assert_str(_footer(overlay)).contains("Héritage familial : %d G" % heritage)

	_confirm(overlay)
	assert_bool(await _wait_until(_exit_has_left)).is_true()

	assert_array(_swaps).is_equal([SceneRouter.HEIR_SCENE])
	assert_int(Campaign.current_map).is_equal(3)
	assert_int(Campaign.heritage).is_equal(heritage)


func test_the_last_generation_leaves_for_the_epilogue_with_nothing_to_carry() -> void:
	var overlay := _spawn_result()
	Campaign.current_map = 3
	_resolve_map(3)
	_spawn_gated_exit(SceneRouter.ENDING_SCENE)

	_spawn_player()
	assert_bool(await _wait_until(func() -> bool: return overlay.visible)).is_true()
	assert_str(_footer(overlay)).is_equal("Épilogue de Salazie")

	_confirm(overlay)
	assert_bool(await _wait_until(_exit_has_left)).is_true()

	assert_array(_swaps).is_equal([SceneRouter.ENDING_SCENE])
	assert_bool(Campaign.finished).is_true()


func test_an_exit_without_a_result_screen_leaves_at_once() -> void:
	_resolve_map(1)
	var exit := _spawn_gated_exit(SceneRouter.FARM_SCENE)
	assert_object(get_tree().get_first_node_in_group("generation_result")).is_null()

	_spawn_player()
	assert_bool(await _wait_until(_exit_has_left)).is_true()

	assert_array(_swaps).is_equal([SceneRouter.FARM_SCENE])
	assert_int(Campaign.current_map).is_equal(2)
	assert_bool(get_tree().paused).is_false()
	assert_bool(bool(exit.get("_triggered"))).is_true()


func test_an_exit_the_router_refuses_can_be_taken_again() -> void:
	# The exit itself asks for nothing, but the router wants every task resolved.
	var exit: Area2D = auto_free(MAP_EXIT_SCENE.instantiate())
	exit.next_scene_path = SceneRouter.FARM_SCENE
	exit.requires_map_ready = false
	exit.show_result = false
	add_child(exit)
	var taken: Array[String] = []
	exit.exit_taken.connect(func(path: String) -> void: taken.append(path))

	var player := _spawn_player()
	assert_bool(await _wait_until(func() -> bool: return not taken.is_empty())).is_true()
	await get_tree().process_frame
	assert_array(_swaps).is_empty()
	assert_int(Campaign.current_map).is_equal(1)

	_resolve_map(1)
	exit.call("_on_body_entered", player)
	assert_bool(await _wait_until(_exit_has_left)).is_true()

	assert_array(taken).has_size(2)
	assert_array(_swaps).is_equal([SceneRouter.FARM_SCENE])


# --- Wild pickups ------------------------------------------------------------

func _spawn_forage(setup: Dictionary) -> Area2D:
	var spot: Area2D = auto_free(FORAGE_SCENE.instantiate())
	# Out of the way: these pickups are taken by hand, not by walking on them.
	spot.position = Vector2(4000, 4000)
	for key: String in setup:
		spot.set(key, setup[key])
	add_child(spot)
	return spot


func _messages(spot: Area2D) -> Array[String]:
	var messages: Array[String] = []
	spot.connect("picked", func(_kind: String, message: String) -> void:
		messages.append(message))
	return messages


func test_pickups_without_their_own_message_say_what_was_found() -> void:
	var player := _spawn_player()
	var seeds := _spawn_forage({"seed_crop": "corn", "auto_pickup": false, "kind": "seed"})
	var seed_messages := _messages(seeds)
	var food := _spawn_forage({"food_amount": 10.0})
	var food_messages := _messages(food)
	assert_str(String(seeds.call("get_interaction_prompt"))).contains("Ramasser des graines")
	assert_str(String(food.call("get_interaction_prompt"))).contains("Ramasser")
	assert_str(String(food.call("get_interaction_prompt"))).not_contains("graines")

	seeds.call("interact", player)
	food.call("interact", player)

	assert_array(seed_messages).is_equal(["Graines ramassées."])
	assert_array(food_messages).is_equal(["Vivres trouvés."])
	assert_int(int(Campaign.bonus_seeds.get("corn", 0))).is_equal(1)


func test_a_pickup_message_reports_the_task_progress_it_asks_for() -> void:
	var player := _spawn_player()
	var plain := _spawn_forage({"food_amount": 5.0, "pickup_message": "Un fruit mûr."})
	var counted := _spawn_forage({"food_amount": 5.0, "task_id": "find_food",
		"pickup_message": "Vivres (%d)."})
	var ratio := _spawn_forage({"food_amount": 5.0, "task_id": "find_food",
		"pickup_message": "Vivres (%d/%d)."})
	var fixed := _spawn_forage({"food_amount": 5.0, "task_id": "find_food",
		"pickup_message": "Encore un."})
	var plain_messages := _messages(plain)
	var counted_messages := _messages(counted)
	var ratio_messages := _messages(ratio)
	var fixed_messages := _messages(fixed)

	plain.call("interact", player)
	counted.call("interact", player)
	ratio.call("interact", player)
	fixed.call("interact", player)

	assert_array(plain_messages).is_equal(["Un fruit mûr."])
	assert_array(counted_messages).is_equal(["Vivres (1)."])
	assert_array(ratio_messages).is_equal(["Vivres (2/3)."])
	assert_array(fixed_messages).is_equal(["Encore un."])
	assert_int(Campaign.task_status("find_food")).is_equal(Campaign.TaskStatus.DONE)


func test_only_the_player_picks_food_up_by_walking_on_it() -> void:
	var spot := _spawn_forage({"food_amount": 10.0, "task_id": "find_food"})
	var animal: CharacterBody2D = auto_free(CharacterBody2D.new())
	add_child(animal)

	spot.call("_on_body_entered", animal)
	assert_bool(bool(spot.call("is_used"))).is_false()
	assert_int(Campaign.task_progress("find_food")).is_equal(0)

	spot.call("_on_body_entered", _spawn_player())
	assert_bool(bool(spot.call("is_used"))).is_true()
	assert_int(Campaign.task_progress("find_food")).is_equal(1)


# --- Hide spot ---------------------------------------------------------------

func test_a_bush_knows_whether_the_player_is_inside() -> void:
	var bush: Area2D = auto_free(HIDE_SCENE.instantiate())
	bush.position = Vector2(4000, 4000)
	add_child(bush)
	var player := _spawn_player()
	var cancelled := [0]
	bush.connect("hidden_cancelled", func() -> void: cancelled[0] += 1)
	assert_bool(bool(bush.call("is_hidden_inside"))).is_false()

	bush.call("_on_body_entered", player)
	assert_bool(bool(bush.call("is_hidden_inside"))).is_true()

	# Leaving before the delay cancels the attempt.
	bush.call("_on_body_exited", player)
	assert_bool(bool(bush.call("is_hidden_inside"))).is_false()
	assert_int(cancelled[0]).is_equal(1)


# --- Player ------------------------------------------------------------------

func test_walking_follows_the_move_actions_and_remembers_the_direction() -> void:
	var player := _spawn_driven_player()
	var sprite: AnimatedSprite2D = player.get_node("Sprite2D")

	Input.action_press(&"move_right")
	player.call("_physics_process", 0.1)
	assert_vector(player.velocity).is_equal_approx(Vector2(float(player.get("speed")), 0),
		Vector2(0.01, 0.01))
	assert_str(String(sprite.animation)).is_equal("walk_right")
	assert_bool(bool(player.get("is_running"))).is_false()

	Input.action_release(&"move_right")
	player.call("_physics_process", 0.1)
	assert_vector(player.velocity).is_equal(Vector2.ZERO)
	assert_vector(player.get("last_direction")).is_equal(Vector2.RIGHT)
	assert_str(String(sprite.animation)).is_equal("idle_right")

	Input.action_press(&"move_up")
	player.call("_physics_process", 0.1)
	assert_str(String(sprite.animation)).is_equal("walk_up")
	assert_float(player.velocity.y).is_less(0.0)


func test_a_knockback_pushes_the_player_and_wears_off() -> void:
	var player := _spawn_driven_player()
	player.set("knockback_decay", 900.0)

	player.call("apply_knockback", Vector2(200, 0))
	player.call("_physics_process", 0.1)
	assert_vector(player.velocity).is_equal_approx(Vector2(110, 0), Vector2(0.01, 0.01))

	player.call("_physics_process", 0.1)
	assert_vector(player.velocity).is_equal_approx(Vector2(20, 0), Vector2(0.01, 0.01))
	player.call("_physics_process", 0.1)
	assert_vector(player.velocity).is_equal(Vector2.ZERO)


func test_a_gust_of_wind_pushes_for_one_step_only() -> void:
	var player := _spawn_driven_player()

	player.call("add_wind", Vector2(0, 60))
	player.call("add_wind", Vector2(30, 0))
	player.call("_physics_process", 0.1)
	assert_vector(player.velocity).is_equal_approx(Vector2(30, 60), Vector2(0.01, 0.01))

	player.call("_physics_process", 0.1)
	assert_vector(player.velocity).is_equal(Vector2.ZERO)


func test_a_stunned_player_cannot_walk_or_run_but_is_still_pushed() -> void:
	var player := _spawn_driven_player()
	Input.action_press(&"move_right")
	Input.action_press(&"run")

	player.call("stun", 0.15)
	player.call("add_wind", Vector2(0, 40))
	player.call("_physics_process", 0.1)
	assert_vector(player.velocity).is_equal_approx(Vector2(0, 40), Vector2(0.01, 0.01))
	assert_bool(bool(player.get("is_running"))).is_false()

	# A shorter stun does not cut a longer one short.
	player.call("stun", 0.01)
	player.call("_physics_process", 0.1)
	assert_vector(player.velocity).is_equal(Vector2.ZERO)

	player.call("_physics_process", 0.1)
	assert_bool(bool(player.get("is_running"))).is_true()
	assert_float(player.velocity.x).is_equal_approx(
		float(player.get("speed")) * float(player.get("run_multiplier")), 0.01)


func test_running_makes_noise_at_intervals_and_walking_makes_none() -> void:
	var player := _spawn_driven_player()
	player.set("noise_interval", 0.25)
	var listener: NoiseListener = auto_free(NoiseListener.new())
	listener.add_to_group("guards")
	add_child(listener)

	Input.action_press(&"move_right")
	player.call("_physics_process", 0.1)
	assert_array(listener.heard).is_empty()

	Input.action_press(&"run")
	for _step in 3:
		player.call("_physics_process", 0.1)
	assert_array(listener.heard).has_size(1)
	player.call("_physics_process", 0.1)
	assert_array(listener.heard).has_size(2)
	assert_vector(listener.heard[1]).is_equal(player.global_position)

	# Slowing to a walk resets the rhythm: the next stride is heard at once.
	Input.action_release(&"run")
	player.call("_physics_process", 0.1)
	assert_array(listener.heard).has_size(2)
	Input.action_press(&"run")
	player.call("_physics_process", 0.1)
	assert_array(listener.heard).has_size(3)


func test_a_running_player_is_heard_by_a_guard_nearby() -> void:
	var player := _spawn_driven_player()
	var guard: CharacterBody2D = auto_free(GUARD_SCENE.instantiate())
	guard.set_physics_process(false)
	guard.collision_layer = 0
	guard.collision_mask = 0
	guard.set("use_navigation", false)
	guard.position = Vector2(120, 0)
	add_child(guard)

	Input.action_press(&"move_left")
	Input.action_press(&"run")
	player.call("_physics_process", 0.1)

	assert_int(int(guard.get("state"))).is_equal(1)


# --- Camera shake ------------------------------------------------------------

func test_the_view_returns_to_its_base_once_the_shake_is_over() -> void:
	var camera: ShakeCamera2D = auto_free(ShakeCamera2D.new())
	camera.offset = Vector2(3, 4)
	camera.rotation = 0.1
	add_child(camera)
	camera.set_process(false)

	camera.add_trauma(0.4)
	camera.add_trauma(0.9)
	assert_float(camera.trauma).is_equal(1.0)
	assert_bool(camera.ignore_rotation).is_false()
	camera.call("_process", 0.1)
	assert_float(camera.trauma).is_equal_approx(1.0 - camera.decay * 0.1, 0.001)
	assert_float(absf(camera.offset.x - 3.0)).is_less_equal(camera.max_offset.x)
	assert_float(absf(camera.offset.y - 4.0)).is_less_equal(camera.max_offset.y)
	assert_float(absf(camera.rotation - 0.1)).is_less_equal(camera.max_roll + 0.0001)

	camera.call("_process", 1.0)
	assert_float(camera.trauma).is_equal(0.0)

	# Whatever nudged the view while it rested is undone on the next frame.
	camera.offset = Vector2(9, -2)
	camera.rotation = 0.3
	camera.call("_process", 0.016)
	assert_vector(camera.offset).is_equal(Vector2(3, 4))
	assert_float(camera.rotation).is_equal_approx(0.1, 0.0001)


# --- Looping sprites ---------------------------------------------------------

func test_an_animated_sheet_without_a_sheet_stays_still() -> void:
	var sprite: AnimatedSprite2D = auto_free(AnimatedSprite2D.new())
	sprite.set_script(ANIMATED_SHEET)
	add_child(sprite)

	assert_object(sprite.sprite_frames).is_null()
	assert_bool(sprite.is_playing()).is_false()
	assert_vector(sprite.offset).is_equal(Vector2.ZERO)


func test_an_animated_sheet_slices_its_row_and_plays_it() -> void:
	var sprite: AnimatedSprite2D = auto_free(AnimatedSprite2D.new())
	sprite.set_script(ANIMATED_SHEET)
	sprite.set("sheet", load(SEED_TEXTURE))
	sprite.set("cell_size", Vector2i(24, 24))
	sprite.set("frame_count", 4)
	sprite.set("columns", 2)
	sprite.set("fps", 6.0)
	sprite.set("loop", false)
	add_child(sprite)

	var frames := sprite.sprite_frames
	assert_array(Array(frames.get_animation_names())).is_equal(["play"])
	assert_int(frames.get_frame_count(&"play")).is_equal(4)
	assert_float(frames.get_animation_speed(&"play")).is_equal(6.0)
	assert_bool(frames.get_animation_loop(&"play")).is_false()
	# Four frames on two columns wrap onto a second row.
	var last := frames.get_frame_texture(&"play", 3) as AtlasTexture
	assert_bool(last.region.is_equal_approx(Rect2(24, 24, 24, 24))).is_true()
	assert_bool(sprite.is_playing()).is_true()
	assert_vector(sprite.offset).is_equal(Vector2(0, -12))


func test_falling_leaves_without_frames_stay_still() -> void:
	var leaves: AnimatedSprite2D = auto_free(AnimatedSprite2D.new())
	leaves.set_script(AMBIENT_LEAVES)
	add_child(leaves)

	assert_bool(leaves.is_playing()).is_false()
	assert_float(leaves.speed_scale).is_equal(1.0)
