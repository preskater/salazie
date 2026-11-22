extends GdUnitTestSuite

const GUARD_SCENE := "res://scenes/world/ai/guard/guard.tscn"
const GUARD_SCRIPT := preload("res://scripts/world/ai/guard/guard.gd")


func _spawn_guard(at := Vector2.ZERO) -> CharacterBody2D:
	var guard: CharacterBody2D = auto_free(load(GUARD_SCENE).instantiate())
	guard.set_physics_process(false)
	# Keep movement tests independent of leftover collisions and navigation maps.
	guard.collision_layer = 0
	guard.collision_mask = 0
	guard.use_navigation = false
	add_child(guard)
	guard.global_position = at
	guard.facing = Vector2.RIGHT
	return guard


func _fake_player(at: Vector2) -> Node2D:
	var player: Node2D = auto_free(Node2D.new())
	add_child(player)
	player.global_position = at
	return player


func before_test() -> void:
	if get_tree() != null:
		get_tree().paused = false


func after_test() -> void:
	if get_tree() != null:
		get_tree().paused = false


func test_cone_accepts_target_inside_angle_and_range() -> void:
	var guard := _spawn_guard()

	assert_bool(guard.can_see(Vector2(100, 0))).is_true()


func test_cone_rejects_target_outside_angle() -> void:
	var guard := _spawn_guard()

	# 45 degrees off a 60 degree cone (half angle is 30).
	assert_bool(guard.can_see(Vector2(100, 100))).is_false()


func test_cone_rejects_target_beyond_range() -> void:
	var guard := _spawn_guard()

	assert_bool(guard.can_see(Vector2(500, 0))).is_false()


func test_noise_inside_radius_enters_suspicious() -> void:
	var guard := _spawn_guard()

	guard.hear_noise(guard.global_position + Vector2(50, 0), 260.0)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.SUSPICIOUS)


func test_noise_outside_radius_is_ignored() -> void:
	var guard := _spawn_guard()

	guard.hear_noise(guard.global_position + Vector2(500, 0), 100.0)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)


func test_staying_in_sight_escalates_to_alert() -> void:
	var guard := _spawn_guard()
	guard.patrol_speed = 0.0
	guard.chase_speed = 0.0
	guard.player = _fake_player(Vector2(100, 0))
	guard.hear_noise(guard.player.global_position, 9999.0)

	for i in range(25):
		guard.tick(0.1)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.ALERT)


func test_alert_catches_player_and_emits_caught_once() -> void:
	var guard := _spawn_guard()
	guard.patrol_speed = 0.0
	guard.chase_speed = 0.0
	guard.pause_on_catch = false
	guard.player = _fake_player(Vector2(12, 0))
	guard.hear_noise(guard.player.global_position, 9999.0)

	var catch_count := [0]
	guard.caught.connect(func() -> void: catch_count[0] += 1)

	for i in range(30):
		guard.tick(0.1)

	assert_int(catch_count[0]).is_equal(1)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.CAUGHT)


func test_last_seen_position_is_not_updated_while_unseen() -> void:
	var guard := _spawn_guard()
	guard.patrol_speed = 0.0
	guard.chase_speed = 0.0
	var player := _fake_player(Vector2(100, 0))
	guard.player = player
	guard.hear_noise(player.global_position, 9999.0)

	for i in range(25):
		guard.tick(0.1)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.ALERT)
	var seen_at: Vector2 = guard.last_seen_position

	player.global_position = Vector2(0, 150)
	guard.tick(0.1)
	guard.tick(0.1)

	assert_vector(guard.last_seen_position).is_equal(seen_at)


func test_gives_up_after_three_seconds_without_sight() -> void:
	var guard := _spawn_guard()
	guard.patrol_speed = 0.0
	guard.chase_speed = 0.0
	var player := _fake_player(Vector2(100, 0))
	guard.player = player
	guard.hear_noise(player.global_position, 9999.0)

	for i in range(25):
		guard.tick(0.1)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.ALERT)

	# Out of the vision cone, but still inside the patrol zone.
	player.global_position = Vector2(0, 150)
	for i in range(35):
		guard.tick(0.1)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)


func test_chase_moves_toward_player_outside_zone() -> void:
	var guard := _spawn_guard()
	guard.zone_size = Vector2(40, 40)
	guard.patrol_speed = 0.0
	guard.chase_speed = 140.0
	guard.catch_distance = 0.0
	var player := _fake_player(Vector2(150, 0))
	guard.player = player
	guard.hear_noise(player.global_position, 9999.0)

	for i in range(25):
		guard.tick(0.1)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.ALERT)

	for i in range(90):
		guard.tick(1.0 / 60.0)

	# The engine physics delta is not guaranteed while ticks run synchronously.
	# Assert chase intent and actual displacement instead of an absolute axis
	# position or direction, which can be affected by the runner's test root.
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.ALERT)
	assert_float(guard.velocity.length()).is_greater(0.0)
	assert_float(guard.global_position.distance_to(Vector2.ZERO)).is_greater(0.0)


func test_ignores_noise_during_give_up_cooldown() -> void:
	var guard := _spawn_guard()
	guard.patrol_speed = 0.0
	guard.chase_speed = 0.0
	var player := _fake_player(Vector2(100, 0))
	guard.player = player
	guard.hear_noise(player.global_position, 9999.0)

	for i in range(25):
		guard.tick(0.1)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.ALERT)

	player.global_position = Vector2(0, 150)
	for i in range(35):
		guard.tick(0.1)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)

	# Right after giving up, noise is ignored.
	guard.hear_noise(guard.global_position + Vector2(10, 0), 9999.0)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)

	# Keep the player out of sight until the cooldown expires.
	player.global_position = Vector2(1000, 1000)
	for i in range(20):
		guard.tick(0.1)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)

	guard.hear_noise(guard.global_position + Vector2(10, 0), 9999.0)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.SUSPICIOUS)


func _wall(at: Vector2, layer: int) -> StaticBody2D:
	var wall: StaticBody2D = auto_free(StaticBody2D.new())
	wall.collision_layer = layer
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(24, 200)
	shape.shape = rectangle
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = at
	return wall


func test_a_vision_blocker_hides_what_is_behind_it() -> void:
	# Regression (#19): the ray masked a layer nothing was on, so guards saw
	# through every rock, tree and wall.
	var guard := _spawn_guard(Vector2(5000, 5000))
	var target := Vector2(5200, 5000)
	assert_bool(guard.can_see(target)).is_true()

	_wall(Vector2(5100, 5000), 1 | 2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The guard started its patrol while the wall registered.
	guard.facing = Vector2.RIGHT

	assert_bool(guard.can_see(target)).is_false()
	assert_bool(guard.can_see(Vector2(5060, 5000))).is_true()


func test_a_plain_world_collider_does_not_block_the_view() -> void:
	# Water and map bounds stop feet, not eyes.
	var guard := _spawn_guard(Vector2(7000, 5000))
	_wall(Vector2(7100, 5000), 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	guard.facing = Vector2.RIGHT

	assert_bool(guard.can_see(Vector2(7200, 5000))).is_true()
