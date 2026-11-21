extends GdUnitTestSuite

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const GUARD_SCENE := "res://scenes/world/ai/guard/guard.tscn"
const GUARD_SCRIPT := preload("res://scripts/world/ai/guard/guard.gd")


func _spawn_player() -> CharacterBody2D:
	var player: CharacterBody2D = auto_free(load(PLAYER_SCENE).instantiate())
	add_child(player)
	player.set_physics_process(false)
	return player


func test_run_multiplier_applies_to_speed() -> void:
	var player := _spawn_player()

	player.is_running = false
	assert_float(player.get_current_speed()).is_equal(300.0)

	player.is_running = true
	assert_float(player.get_current_speed()).is_equal_approx(510.0, 0.001)


func test_emit_noise_alerts_nearby_guard() -> void:
	var player := _spawn_player()
	player.global_position = Vector2(40, 0)

	var guard: CharacterBody2D = auto_free(load(GUARD_SCENE).instantiate())
	guard.set_physics_process(false)
	add_child(guard)
	guard.global_position = Vector2.ZERO

	player.emit_noise()

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.SUSPICIOUS)
