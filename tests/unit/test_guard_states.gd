extends GdUnitTestSuite
## Guard state machine beyond the first sighting: what a guard does on arrival,
## when it loses interest, after a catch, and at the edge of walkable ground.

const GUARD_SCENE := "res://scenes/world/ai/guard/guard.tscn"
const GUARD_SCRIPT := preload("res://scripts/world/ai/guard/guard.gd")


func before_test() -> void:
	if get_tree() != null:
		get_tree().paused = false


func after_test() -> void:
	if get_tree() != null:
		get_tree().paused = false


func _new_guard() -> CharacterBody2D:
	var guard: CharacterBody2D = auto_free(load(GUARD_SCENE).instantiate())
	guard.set_physics_process(false)
	# Keep movement tests independent of leftover collisions and navigation maps.
	guard.collision_layer = 0
	guard.collision_mask = 0
	guard.use_navigation = false
	return guard


func _spawn_guard(at := Vector2.ZERO) -> CharacterBody2D:
	var guard := _new_guard()
	add_child(guard)
	guard.global_position = at
	guard.facing = Vector2.RIGHT
	return guard


func _fake_player(at: Vector2) -> Node2D:
	var player: Node2D = auto_free(Node2D.new())
	add_child(player)
	player.global_position = at
	return player


## A guard standing still that has watched `player` long enough to give chase.
func _alerted_guard(player: Node2D) -> CharacterBody2D:
	var guard := _spawn_guard()
	guard.patrol_speed = 0.0
	guard.chase_speed = 0.0
	guard.pause_on_catch = false
	guard.catch_distance = 0.0
	guard.player = player
	guard.hear_noise(player.global_position, 9999.0)
	for i in range(25):
		guard.tick(0.1)
	return guard


# --- Patrol ------------------------------------------------------------------

func test_a_guard_that_reaches_its_patrol_point_waits_before_moving_on() -> void:
	var guard := _new_guard()
	# A zone with no size keeps every patrol point on the spawn.
	guard.zone_size = Vector2.ZERO
	guard.wait_min = 1.5
	guard.wait_max = 1.5
	add_child(guard)
	guard.velocity = Vector2(40, 0)

	guard.tick(0.1)
	assert_float(float(guard.get("_wait_timer"))).is_equal(1.5)

	guard.tick(0.5)
	assert_vector(guard.velocity).is_equal(Vector2.ZERO)
	assert_float(float(guard.get("_wait_timer"))).is_equal_approx(1.0, 0.001)
	assert_vector(guard.global_position).is_equal(Vector2.ZERO)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)


func test_the_patrol_zone_follows_its_centre_node() -> void:
	var centre: Node2D = auto_free(Node2D.new())
	add_child(centre)
	centre.global_position = Vector2(900, 300)
	var guard := _new_guard()
	guard.zone_center = centre
	guard.zone_size = Vector2(120, 80)
	add_child(guard)
	var zone := Rect2(centre.global_position - guard.zone_size * 0.5, guard.zone_size)

	for i in range(20):
		assert_bool(zone.has_point(guard.get("_patrol_point"))).is_true()
		guard.call("_pick_patrol_point")
	assert_bool((guard.call("_zone_rect") as Rect2).is_equal_approx(zone)).is_true()

	# The guard spawned at the origin sets off towards its zone.
	guard.tick(0.1)
	assert_float(guard.velocity.x).is_greater(0.0)
	assert_float(guard.velocity.length()).is_equal_approx(guard.patrol_speed, 0.01)


# --- Suspicion ---------------------------------------------------------------

func test_suspicion_fades_and_the_guard_returns_to_patrol() -> void:
	var guard := _spawn_guard()
	guard.patrol_speed = 0.0
	var alert: Label = guard.get_node("Alert")
	guard.hear_noise(guard.global_position + Vector2(200, 0), 9999.0)
	guard.suspicion = 1.0
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.SUSPICIOUS)
	assert_bool(alert.visible).is_true()

	guard.tick(1.0)
	assert_float(guard.suspicion).is_equal_approx(0.5, 0.001)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.SUSPICIOUS)

	for i in range(int(guard.investigate_timeout)):
		guard.tick(1.0)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)
	assert_float(guard.suspicion).is_equal(0.0)
	assert_bool(alert.visible).is_false()


func test_a_guard_standing_on_the_noise_listens_without_moving() -> void:
	var guard := _spawn_guard(Vector2(50, 50))
	guard.velocity = Vector2(30, 0)

	guard.hear_noise(guard.global_position + Vector2(4, 0), 100.0)
	guard.tick(0.1)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.SUSPICIOUS)
	assert_vector(guard.velocity).is_equal(Vector2.ZERO)
	assert_vector(guard.global_position).is_equal(Vector2(50, 50))
	assert_str(String((guard.get_node("Sprite") as AnimatedSprite2D).animation)) \
		.is_equal("idle_right")


func test_a_noise_does_not_distract_a_guard_already_chasing() -> void:
	var player := _fake_player(Vector2(100, 0))
	var guard := _alerted_guard(player)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.ALERT)

	guard.hear_noise(guard.global_position + Vector2(0, 20), 9999.0)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.ALERT)
	assert_vector(guard.get("_investigate_point")).is_equal(player.global_position)


func test_a_noise_does_not_wake_a_guard_that_holds_the_player() -> void:
	var player := _fake_player(Vector2(100, 0))
	var guard := _alerted_guard(player)
	guard.catch_distance = 150.0
	guard.tick(0.1)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.CAUGHT)

	guard.hear_noise(guard.global_position + Vector2(0, 20), 9999.0)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.CAUGHT)


# --- Chase and catch ---------------------------------------------------------

func test_a_chase_ends_when_the_player_is_gone() -> void:
	var player := Node2D.new()
	add_child(player)
	player.global_position = Vector2(100, 0)
	var guard := _alerted_guard(player)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.ALERT)

	player.free()
	guard.tick(0.1)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)
	assert_float(guard.suspicion).is_equal(0.0)
	assert_bool((guard.get_node("Alert") as Label).visible).is_false()


func test_a_catch_pauses_the_game_unless_the_map_handles_it() -> void:
	var guard := _alerted_guard(_fake_player(Vector2(100, 0)))
	guard.pause_on_catch = true
	guard.catch_distance = 150.0
	var caught := [0]
	guard.caught.connect(func() -> void: caught[0] += 1)

	guard.tick(0.1)
	var paused := get_tree().paused
	get_tree().paused = false

	assert_int(caught[0]).is_equal(1)
	assert_bool(paused).is_true()
	assert_vector(guard.velocity).is_equal(Vector2.ZERO)


func test_a_catch_handled_by_the_map_leaves_the_game_running() -> void:
	var guard := _alerted_guard(_fake_player(Vector2(100, 0)))
	guard.catch_distance = 150.0

	guard.tick(0.1)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.CAUGHT)
	assert_bool(get_tree().paused).is_false()


func test_a_guard_sent_back_on_patrol_can_catch_again_after_its_cooldown() -> void:
	var player := _fake_player(Vector2(100, 0))
	var guard := _alerted_guard(player)
	guard.catch_distance = 150.0
	var caught := [0]
	guard.caught.connect(func() -> void: caught[0] += 1)
	guard.tick(0.1)
	assert_int(caught[0]).is_equal(1)

	guard.reset_after_catch(Vector2(400, 200))
	guard.facing = Vector2.RIGHT
	player.global_position = Vector2(500, 200)

	assert_vector(guard.global_position).is_equal(Vector2(400, 200))
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)
	assert_float(guard.suspicion).is_equal(0.0)
	assert_bool((guard.get_node("Alert") as Label).visible).is_false()

	# The player in plain sight is ignored while the guard walks back.
	guard.tick(0.1)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)
	guard.hear_noise(player.global_position, 9999.0)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.PATROL)

	for i in range(int(guard.give_up_cooldown / 0.1) + 2):
		guard.tick(0.1)
	guard.facing = Vector2.RIGHT
	for i in range(30):
		guard.tick(0.1)
		guard.facing = Vector2.RIGHT

	assert_int(caught[0]).is_equal(2)
	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.CAUGHT)


func test_reset_without_a_point_returns_to_the_spawn() -> void:
	var guard := _spawn_guard()
	var spawn: Vector2 = guard.get("_spawn_position")
	guard.global_position = spawn + Vector2(300, 120)

	guard.reset_after_catch()

	assert_vector(guard.global_position).is_equal(spawn)


# --- Animation ---------------------------------------------------------------

func test_the_sprite_follows_movement_and_facing() -> void:
	var guard := _spawn_guard()
	var sprite: AnimatedSprite2D = guard.get_node("Sprite")
	var cases := [
		[Vector2(-50, 0), Vector2.LEFT, "walk_left"],
		[Vector2(50, 0), Vector2.RIGHT, "walk_right"],
		[Vector2(0, -50), Vector2.UP, "walk_up"],
		[Vector2(0, 50), Vector2.DOWN, "walk_down"],
		[Vector2.ZERO, Vector2.UP, "idle_up"],
		[Vector2.ZERO, Vector2.LEFT, "idle_left"],
		[Vector2.ZERO, Vector2.DOWN, "idle_down"],
	]
	for case: Array in cases:
		guard.velocity = case[0]
		guard.facing = case[1]

		guard.update_animation()

		assert_str(String(sprite.animation)).is_equal(String(case[2]))
		assert_bool(sprite.is_playing()).is_true()


# --- Navigation --------------------------------------------------------------

## A 200 px square of walkable ground at the origin.
func _walkable_square() -> NavigationRegion2D:
	var polygon := NavigationPolygon.new()
	polygon.vertices = PackedVector2Array([
		Vector2(0, 0), Vector2(200, 0), Vector2(200, 200), Vector2(0, 200)])
	polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region: NavigationRegion2D = auto_free(NavigationRegion2D.new())
	region.navigation_polygon = polygon
	add_child(region)
	return region


func _navigating_guard(at: Vector2) -> CharacterBody2D:
	var guard := _new_guard()
	guard.use_navigation = true
	guard.zone_size = Vector2.ZERO
	guard.position = at
	add_child(guard)
	guard.facing = Vector2.RIGHT
	# The navigation server publishes a new region a few physics frames later.
	for _frame in 120:
		if bool(guard.call("_has_navigation_map")) and not NavigationServer2D.map_get_path(
				guard.get_world_2d().navigation_map, Vector2(20, 20), Vector2(180, 180),
				true).is_empty():
			break
		await get_tree().physics_frame
	guard.global_position = at
	return guard


func test_a_guard_at_the_edge_of_walkable_ground_does_not_push_towards_a_noise_beyond() -> void:
	_walkable_square()
	var guard := await _navigating_guard(Vector2(200, 100))
	assert_bool(bool(guard.call("_has_navigation_map"))).is_true()

	guard.hear_noise(Vector2(420, 100), 9999.0)
	guard.tick(0.1)

	assert_int(guard.state).is_equal(GUARD_SCRIPT.State.SUSPICIOUS)
	assert_vector(guard.velocity).is_equal(Vector2.ZERO)


func test_a_guard_walks_to_the_edge_nearest_to_an_unreachable_noise() -> void:
	_walkable_square()
	var guard := await _navigating_guard(Vector2(100, 100))

	# Straight above the top-right corner: a direct line would leave the ground.
	guard.hear_noise(Vector2(200, -300), 9999.0)
	guard.tick(0.1)

	var towards_corner := Vector2(100, 100).direction_to(Vector2(200, 0))
	assert_float(guard.velocity.length()).is_equal_approx(guard.patrol_speed * 1.2, 0.01)
	assert_float(guard.velocity.normalized().dot(towards_corner)).is_greater(0.99)
