extends GdUnitTestSuite

const ANIMAL_SCENE := "res://game/farm/animals/animal.tscn"
const NPC_SCENE := "res://game/farm/npc.tscn"
const CHICKEN_SHEET := "res://assets/farm_48x48/animals/Chickens_and_Roosters_48x48/Chicken_White_48x48.png"

const DIRECTIONS := ["right", "up", "left", "down"]


func _spawn_chicken(roam: Rect2 = Rect2(0, 0, 192, 192)) -> Node2D:
	var animal: Node2D = load(ANIMAL_SCENE).instantiate()
	animal.set("sheet", load(CHICKEN_SHEET))
	animal.set("cell_size", Vector2i(48, 48))
	animal.set("roam_rect", roam)
	animal.position = roam.get_center()
	add_child(animal)
	return auto_free(animal)


func test_animal_builds_four_direction_walk_and_graze_animations() -> void:
	var animal := _spawn_chicken()
	await get_tree().process_frame
	var sprite: AnimatedSprite2D = animal.get_node("AnimatedSprite2D")

	assert_object(sprite.sprite_frames).is_not_null()
	for direction in DIRECTIONS:
		for prefix in ["walk", "graze"]:
			var anim := "%s_%s" % [prefix, direction]
			assert_bool(sprite.sprite_frames.has_animation(anim)) \
				.override_failure_message("Missing animation %s" % anim).is_true()
			assert_int(sprite.sprite_frames.get_frame_count(anim)).is_equal(6)


func test_animal_roams_and_stays_inside_roam_rect() -> void:
	var animal: Node2D = auto_free(load(ANIMAL_SCENE).instantiate())
	animal.set("sheet", load(CHICKEN_SHEET))
	animal.set("cell_size", Vector2i(48, 48))
	animal.set("roam_rect", Rect2(0, 0, 192, 192))
	animal.set("graze_time", Vector2.ZERO)
	animal.set("walk_time", Vector2(5, 5))
	animal.position = Vector2(96, 96)
	add_child(animal)
	var start: Vector2 = animal.position
	var roam: Rect2 = animal.get("roam_rect")
	var max_distance := 0.0
	var escaped := false
	for i in 300:
		await get_tree().physics_frame
		max_distance = maxf(max_distance, animal.position.distance_to(start))
		if not roam.grow(2.0).has_point(animal.position):
			escaped = true

	assert_bool(escaped).override_failure_message("Animal left its roam rect").is_false()
	assert_float(max_distance).override_failure_message("Animal never moved").is_greater(4.0)


func test_tree_shake_resource_has_three_frames() -> void:
	var frames: SpriteFrames = load("res://game/world/animations/Tree_Oak_Green_Big_Shake.tres")

	assert_object(frames).is_not_null()
	assert_bool(frames.has_animation(&"shake")).is_true()
	assert_int(frames.get_frame_count(&"shake")).is_equal(3)


func test_fruit_tree_shake_slices_match_their_sheets() -> void:
	var cases := {
		"Peach": [240.0, 240.0, 720.0],
		"Lemon": [192.0, 240.0, 576.0],
	}
	for fruit: String in cases:
		var cell: Array = cases[fruit]
		var frame_w: float = cell[0]
		var frame_h: float = cell[1]
		var sheet_w: float = cell[2]
		var frames: SpriteFrames = load(
			"res://game/world/animations/Fruit_Tree_%s_Ripe_Shake.tres" % fruit)
		assert_object(frames).is_not_null()
		assert_int(frames.get_frame_count(&"shake")).is_equal(3)
		for i in 3:
			var atlas := frames.get_frame_texture(&"shake", i) as AtlasTexture
			assert_object(atlas).override_failure_message("Missing frame %d of %s" % [i, fruit]).is_not_null()
			if atlas == null:
				continue
			assert_float(atlas.region.position.x).is_equal(frame_w * i)
			assert_float(atlas.region.size.x).is_equal(frame_w)
			assert_float(atlas.region.size.y).is_equal(frame_h)
			assert_float(atlas.region.end.x).is_equal(frame_w * (i + 1))
		assert_float(float(frames.get_frame_texture(&"shake", 2).get_width())).is_equal(sheet_w / 3.0)


func test_leaf_frames_loop_over_24_frames() -> void:
	var frames: SpriteFrames = load("res://game/world/animations/Leaves_Green.tres")

	assert_object(frames).is_not_null()
	assert_bool(frames.has_animation(&"fall")).is_true()
	assert_bool(frames.get_animation_loop(&"fall")).is_true()
	assert_int(frames.get_frame_count(&"fall")).is_equal(24)


func test_npc_turns_to_face_a_nearby_player() -> void:
	var npc: Node2D = auto_free(load(NPC_SCENE).instantiate())
	add_child(npc)
	var target: Node2D = auto_free(Node2D.new())
	add_child(target)
	target.position = npc.position + Vector2(40, 0)
	npc.set("player", target)
	for i in 3:
		await get_tree().physics_frame
	var sprite: AnimatedSprite2D = npc.get_node("AnimatedSprite2D")

	assert_str(String(sprite.animation)).is_equal("idle_right")
