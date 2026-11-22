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


func test_speed_scale_slows_walking_and_running() -> void:
	var player := _spawn_player()
	player.speed_scale = 0.5

	player.is_running = false
	assert_float(player.get_current_speed()).is_equal_approx(150.0, 0.001)
	player.is_running = true
	assert_float(player.get_current_speed()).is_equal_approx(255.0, 0.001)


func test_concealment_counts_every_source() -> void:
	# Regression (#20): leaving a bush inside a cave revealed the player for
	# the rest of the cave.
	var player := _spawn_player()
	var cave: Node = auto_free(Node.new())
	var bush: Node = auto_free(Node.new())

	player.add_cover(cave)
	player.add_cover(bush)
	player.remove_cover(bush)
	assert_bool(player.concealed).is_true()
	assert_float(player.animations.modulate.a).is_equal_approx(0.55, 0.001)

	player.remove_cover(cave)
	assert_bool(player.concealed).is_false()
	assert_float(player.animations.modulate.a).is_equal(1.0)


func test_noise_masking_counts_every_source() -> void:
	var player := _spawn_player()
	var spray: Node = auto_free(Node.new())
	var alcove: Node = auto_free(Node.new())

	player.add_quiet(spray)
	player.add_quiet(alcove)
	player.remove_quiet(alcove)
	assert_bool(player.noise_muted).is_true()
	player.remove_quiet(spray)
	assert_bool(player.noise_muted).is_false()


func test_direct_switches_do_not_cancel_a_zone() -> void:
	var player := _spawn_player()
	var cave: Node = auto_free(Node.new())
	player.add_cover(cave)
	player.add_quiet(cave)

	player.set_hidden(true)
	player.set_hidden(false)
	player.set_noise_muted(true)
	player.set_noise_muted(false)

	assert_bool(player.concealed).is_true()
	assert_bool(player.noise_muted).is_true()


func test_a_freed_source_stops_covering() -> void:
	var player := _spawn_player()
	var bush := Node.new()
	player.add_cover(bush)
	bush.free()

	player.remove_cover(player)

	assert_bool(player.concealed).is_false()


func test_breath_runs_out_and_has_to_come_back() -> void:
	var player := _spawn_player()
	player.stamina_enabled = true

	assert_bool(player.tick_stamina(player.stamina_seconds * 0.5, true)).is_true()
	assert_float(player.stamina).is_equal_approx(0.5, 0.001)
	assert_bool(player.tick_stamina(player.stamina_seconds, true)).is_true()
	assert_float(player.stamina).is_equal(0.0)
	assert_bool(player.winded).is_true()

	# Holding the key does not help: the breath must come back first.
	assert_bool(player.tick_stamina(0.5, true)).is_false()
	assert_float(player.stamina).is_greater(0.0)
	player.tick_stamina(player.stamina_recovery_seconds * player.stamina_resume, false)
	assert_bool(player.tick_stamina(0.01, true)).is_true()
	assert_bool(player.winded).is_false()

	player.tick_stamina(1000.0, false)
	assert_float(player.stamina).is_equal(1.0)


func test_breath_is_unlimited_where_stamina_is_off() -> void:
	var player := _spawn_player()
	assert_bool(player.stamina_enabled).is_false()

	assert_bool(player.tick_stamina(1000.0, true)).is_true()
	assert_bool(player.tick_stamina(1.0, false)).is_false()

	assert_float(player.stamina).is_equal(1.0)
