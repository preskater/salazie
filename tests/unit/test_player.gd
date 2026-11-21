extends GdUnitTestSuite

const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"

const DIRECTIONS := {
	"right": Vector2.RIGHT,
	"left": Vector2.LEFT,
	"up": Vector2.UP,
	"down": Vector2.DOWN,
}


func _spawn_player() -> Node:
	return auto_free(load(PLAYER_SCENE_PATH).instantiate())


func test_player_scene_instantiates() -> void:
	var player = _spawn_player()

	assert_object(player).is_not_null()
	assert_bool(player is CharacterBody2D).is_true()
	assert_object(player.get_node_or_null("Sprite2D")).is_not_null()
	assert_object(player.get_node_or_null("CollisionShape2D")).is_not_null()


func test_all_directional_animations_exist() -> void:
	var player = _spawn_player()
	var sprite: AnimatedSprite2D = player.get_node("Sprite2D")

	for direction_name in DIRECTIONS:
		assert_bool(sprite.sprite_frames.has_animation("walk_%s" % direction_name)) \
			.override_failure_message("Missing walk animation for %s" % direction_name) \
			.is_true()
		assert_bool(sprite.sprite_frames.has_animation("idle_%s" % direction_name)) \
			.override_failure_message("Missing idle animation for %s" % direction_name) \
			.is_true()


func test_walk_animation_follows_direction() -> void:
	var player = _spawn_player()
	add_child(player)
	await get_tree().process_frame

	var sprite: AnimatedSprite2D = player.get_node("Sprite2D")

	for direction_name in DIRECTIONS:
		player.call("play_walk_animation", DIRECTIONS[direction_name])
		assert_str(String(sprite.animation)).is_equal("walk_%s" % direction_name)


func test_idle_animation_follows_direction() -> void:
	var player = _spawn_player()
	add_child(player)
	await get_tree().process_frame

	var sprite: AnimatedSprite2D = player.get_node("Sprite2D")

	for direction_name in DIRECTIONS:
		player.call("play_idle_animation", DIRECTIONS[direction_name])
		assert_str(String(sprite.animation)).is_equal("idle_%s" % direction_name)
