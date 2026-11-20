extends GdUnitTestSuite

const MAP_EXIT_SCENE := preload("res://game/world/MapExit.tscn")
const PLAYER_SCENE := preload("res://game/player/player.tscn")
const FARM_SCENE_PATH := "res://game/world/maps/Farm.tscn"


class FakeTransition:
	extends Node

	var is_transitioning := false
	var calls: Array[Array] = []

	func change_scene(scene_path: String, title: String, subtitle: String) -> void:
		calls.append([scene_path, title, subtitle])


func before_test() -> void:
	DayNightCycle.nights_required_for_next_map = 2
	DayNightCycle.nights_spent = 0


func after_test() -> void:
	DayNightCycle.nights_required_for_next_map = 2
	DayNightCycle.nights_spent = 0


func _spawn_exit() -> Node:
	var exit = MAP_EXIT_SCENE.instantiate()
	exit.next_scene_path = FARM_SCENE_PATH
	exit.title = "Le cultivateur"
	exit.subtitle = "Deuxième génération"
	var fake := FakeTransition.new()
	exit.add_child(fake)
	exit.transition_override = fake
	add_child(auto_free(exit))
	return exit


func _instantiate_player() -> Node:
	var player = PLAYER_SCENE.instantiate()
	add_child(auto_free(player))
	return player


func test_exit_is_blocked_until_required_nights_are_spent() -> void:
	var exit = _spawn_exit()

	assert_bool(exit.can_leave()).is_false()

	DayNightCycle.nights_spent = 2
	assert_bool(exit.can_leave()).is_true()


func test_exit_can_skip_the_night_requirement() -> void:
	var exit = _spawn_exit()
	exit.requires_map_ready = false

	assert_bool(exit.can_leave()).is_true()


func test_exit_without_destination_cannot_be_used() -> void:
	var exit = _spawn_exit()
	exit.next_scene_path = ""
	DayNightCycle.nights_spent = 2

	assert_bool(exit.can_leave()).is_false()


func test_player_entry_requests_transition_with_configured_text() -> void:
	var exit = _spawn_exit()
	DayNightCycle.nights_spent = 2
	_instantiate_player()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var fake: FakeTransition = exit.transition_override
	assert_array(fake.calls).has_size(1)
	assert_str(fake.calls[0][0]).is_equal(FARM_SCENE_PATH)
	assert_str(fake.calls[0][1]).is_equal("Le cultivateur")
	assert_str(fake.calls[0][2]).is_equal("Deuxième génération")


func test_player_entry_is_blocked_before_nights_are_spent() -> void:
	var exit = _spawn_exit()
	var blocked := [0]
	exit.blocked.connect(func() -> void: blocked[0] += 1)
	_instantiate_player()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var fake: FakeTransition = exit.transition_override
	assert_int(blocked[0]).is_equal(1)
	assert_array(fake.calls).is_empty()


func test_non_player_body_does_not_use_the_exit() -> void:
	var exit = _spawn_exit()
	DayNightCycle.nights_spent = 2
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 48)
	shape.shape = rect
	body.add_child(shape)
	add_child(auto_free(body))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var fake: FakeTransition = exit.transition_override
	assert_array(fake.calls).is_empty()
