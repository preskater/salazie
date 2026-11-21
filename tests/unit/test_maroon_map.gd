extends GdUnitTestSuite

const MAROON_SCENE := preload("res://scenes/maps/maroon.tscn")
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


func test_map_runs_from_the_sea_to_the_mountain_pass() -> void:
	var map := await _spawn_map()

	assert_vector(map.map_size()).is_equal(Vector2(72 * 48, 112 * 48))
	var spawn: Vector2 = map.get_node("World/StartCheckpoint").global_position
	var mouth: Vector2 = map.get_node("World/RiverMouthCheckpoint").global_position
	var camp: Vector2 = map.get_node("World/ForestCheckpoint").global_position
	var upper: Vector2 = map.get_node("World/UpperCheckpoint").global_position
	var refuge: Vector2 = map.get_node("RefugeExit").global_position
	assert_float(spawn.y).is_greater(mouth.y)
	assert_float(mouth.y).is_greater(camp.y)
	assert_float(camp.y).is_greater(upper.y)
	assert_float(upper.y).is_greater(refuge.y)


func test_map_paints_ground_water_bridges_and_collisions() -> void:
	var map := await _spawn_map()

	var ground: TileMapLayer = map.get_node("Terrain/Ground")
	var water: TileMapLayer = map.get_node("Terrain/Water")
	var bridges: TileMapLayer = map.get_node("Terrain/Bridges")
	assert_object(ground).is_not_null()
	assert_object(water).is_not_null()
	assert_object(bridges).is_not_null()
	assert_int(ground.get_used_cells().size()).is_greater(3000)
	assert_int(water.get_used_cells().size()).is_greater(500)
	assert_int(bridges.get_used_cells().size()).is_greater(30)
	var collision: StaticBody2D = map.get_node("Terrain/WorldCollision")
	assert_object(collision).is_not_null()
	assert_int(collision.get_child_count()).is_greater(80)


func test_map_has_animated_life_and_wildlife() -> void:
	var map := await _spawn_map()

	var animated := map.find_children("*", "AnimatedSprite2D", true, false)
	assert_int(animated.size()).is_greater(40)
	var playing := 0
	for node: Node in animated:
		if (node as AnimatedSprite2D).is_playing():
			playing += 1
	assert_int(playing).is_greater(40)
	assert_int(get_tree().get_nodes_in_group("wildlife").size()).is_greater(3)


func test_river_mouth_checkpoint_starts_the_route() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var checkpoint: Area2D = map.get_node("World/RiverMouthCheckpoint")

	checkpoint.call("_on_body_entered", player)

	assert_int(Campaign.task_status("follow_river")).is_equal(Campaign.TaskStatus.DONE)


func test_task_anchors_are_not_inside_static_collisions() -> void:
	var map := await _spawn_map()
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState2D = map.get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.collision_mask = 1
	params.collide_with_areas = false
	var anchors: Array[Node2D] = []
	for group: String in ["forage_spots", "hide_spots", "checkpoints"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node is Node2D:
				anchors.append(node as Node2D)
	anchors.append(map.get_node("RefugeExit") as Node2D)

	for anchor: Node2D in anchors:
		params.position = anchor.global_position
		var hits: Array[Dictionary] = space.intersect_point(params)
		assert_int(hits.size()).override_failure_message(
			"%s is inside a static collision" % anchor.name).is_equal(0)


func test_animated_frames_stay_inside_their_sheets() -> void:
	var map := await _spawn_map()
	for node: Node in map.find_children("*", "AnimatedSprite2D", true, false):
		var sprite := node as AnimatedSprite2D
		if sprite.sprite_frames == null:
			continue
		for animation: StringName in sprite.sprite_frames.get_animation_names():
			for index in sprite.sprite_frames.get_frame_count(animation):
				var texture := sprite.sprite_frames.get_frame_texture(animation, index)
				if texture is not AtlasTexture:
					continue
				var atlas := (texture as AtlasTexture).atlas
				var region := (texture as AtlasTexture).region
				assert_object(atlas).override_failure_message(
					"%s/%s frame %d has no atlas" % [sprite.name, animation, index]).is_not_null()
				assert_bool(region.end.x <= float(atlas.get_width()) + 0.01).override_failure_message(
					"%s/%s frame %d is outside the sheet" % [sprite.name, animation, index]).is_true()
				assert_bool(region.end.y <= float(atlas.get_height()) + 0.01).override_failure_message(
					"%s/%s frame %d is outside the sheet" % [sprite.name, animation, index]).is_true()


func test_wild_animals_walk_on_row_two_and_graze_on_row_one() -> void:
	var map := await _spawn_map()
	var animals := get_tree().get_nodes_in_group("wildlife")
	assert_int(animals.size()).is_greater(0)
	for node: Node in animals:
		assert_int(int(node.get("walk_row"))).override_failure_message(
			"%s walks on the wrong row" % node.name).is_equal(2)
		assert_int(int(node.get("graze_row"))).override_failure_message(
			"%s grazes on the wrong row" % node.name).is_equal(1)


func test_world_props_keep_integer_scales() -> void:
	var map := await _spawn_map()
	for node: Node in map.get_node("World").find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		assert_bool(is_equal_approx(sprite.scale.x, roundf(sprite.scale.x))).override_failure_message(
			"%s uses a fractional x scale" % sprite.name).is_true()
		assert_bool(is_equal_approx(sprite.scale.y, roundf(sprite.scale.y))).override_failure_message(
			"%s uses a fractional y scale" % sprite.name).is_true()


func test_ground_transitions_use_the_pack_edge_variants() -> void:
	var map := await _spawn_map()
	var ground: TileMapLayer = map.get_node("Terrain/Ground")
	var water: TileMapLayer = map.get_node("Terrain/Water")

	# Grass river bank: water immediately east.
	_assert_ground_cell(ground, Vector2i(28, 44), 0, Vector2i(10, 7))
	# One-tile trail through grass: vertical corridor and pure grass sides.
	_assert_ground_cell(ground, Vector2i(46, 77), 1, Vector2i(15, 9))
	var grass_tiles := [Vector2i(1, 7), Vector2i(9, 7), Vector2i(17, 7)]
	for tile: Vector2i in [Vector2i(45, 77), Vector2i(47, 77)]:
		assert_int(ground.get_cell_source_id(tile)).is_equal(0)
		assert_bool(grass_tiles.has(ground.get_cell_atlas_coords(tile))).is_true()
	# Sand shoreline: sand stays pure and the water side gets the foam contour.
	_assert_ground_cell(ground, Vector2i(19, 101), 2,
		ground.get_cell_atlas_coords(Vector2i(19, 101)))
	assert_int(water.get_cell_source_id(Vector2i(19, 102))).is_equal(0)
	var shore_coords := water.get_cell_atlas_coords(Vector2i(19, 102))
	assert_int(shore_coords.x).is_equal(27)
	assert_int(shore_coords.y).is_equal(5)
	var edges: Node2D = map.get_node("Terrain/WaterEdges")
	assert_int(edges.get_child_count()).is_greater(40)
	var shore_center := Vector2(19 * 48 + 24, 102 * 48 + 24)
	var found_north := false
	for child: Node in edges.get_children():
		var sprite := child as Sprite2D
		if sprite == null or not sprite.position.is_equal_approx(shore_center):
			continue
		var atlas := sprite.texture as AtlasTexture
		if atlas == null:
			continue
		if is_zero_approx(sprite.rotation) and int(atlas.region.position.x) == 48:
			found_north = true
	assert_bool(found_north).override_failure_message(
		"no north water edge at the beach shoreline").is_true()
	# Sand climbing into grass: grass immediately north.
	_assert_ground_cell(ground, Vector2i(60, 94), 1, Vector2i(1, 4))
	# The river body itself stays a single clean tile.
	assert_int(water.get_cell_source_id(Vector2i(29, 44))).is_equal(0)
	assert_int(water.get_cell_atlas_coords(Vector2i(29, 44)).x).is_equal(27)
	assert_int(water.get_cell_atlas_coords(Vector2i(29, 44)).y).is_equal(5)


func _assert_ground_cell(ground: TileMapLayer, tile: Vector2i, source: int,
		coords: Vector2i) -> void:
	assert_int(ground.get_cell_source_id(tile)).override_failure_message(
		"wrong source at %s" % tile).is_equal(source)
	var actual := ground.get_cell_atlas_coords(tile)
	assert_int(actual.x).override_failure_message(
		"wrong atlas x at %s" % tile).is_equal(coords.x)
	assert_int(actual.y).override_failure_message(
		"wrong atlas y at %s" % tile).is_equal(coords.y)


func test_map_places_guards_forage_hides_and_checkpoints() -> void:
	var map := await _spawn_map()

	assert_int(get_tree().get_nodes_in_group("guards").size()).is_equal(5)
	assert_int(get_tree().get_nodes_in_group("forage_spots").size()).is_equal(6)
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


func _wait_for_bake(region: NavigationRegion2D, frames := 240) -> bool:
	for _i in frames:
		if region.navigation_polygon != null \
				and region.navigation_polygon.get_polygon_count() > 0:
			return true
		await get_tree().process_frame
	return false


func test_map_bakes_a_navigation_region() -> void:
	var map := await _spawn_map()
	var region := map.get_node_or_null("Navigation") as NavigationRegion2D
	assert_object(region).is_not_null()
	if region == null:
		return

	var baked := await _wait_for_bake(region)
	assert_bool(baked) \
		.override_failure_message("Navigation polygon was never baked").is_true()
	assert_int(region.navigation_polygon.get_polygon_count()).is_greater(0)


func test_maroon_guards_use_navigation() -> void:
	var map := await _spawn_map()

	for guard: Node in get_tree().get_nodes_in_group("guards"):
		assert_bool(bool(guard.get("use_navigation"))) \
			.override_failure_message("Guard %s does not use navigation" % guard.name) \
			.is_true()


func test_navigation_excludes_the_river_and_keeps_the_bridge() -> void:
	var map := await _spawn_map()
	var region := map.get_node_or_null("Navigation") as NavigationRegion2D
	assert_object(region).is_not_null()
	if region == null:
		return
	var baked := await _wait_for_bake(region)
	assert_bool(baked).is_true()

	var collision := map.get_node_or_null("Terrain/WorldCollision")
	assert_object(collision).is_not_null()
	if collision == null or collision.get_child_count() == 0:
		return

	var water_shape := collision.get_child(0) as CollisionShape2D
	assert_object(water_shape).is_not_null()
	if water_shape == null:
		return

	var nav_map := map.get_world_2d().navigation_map
	var water_center := water_shape.global_position
	var snapped := NavigationServer2D.map_get_closest_point(nav_map, water_center)
	assert_bool(snapped.distance_to(water_center) > 24.0) \
		.override_failure_message("River point is walkable: %s" % snapped).is_true()


func test_guards_move_after_the_bake() -> void:
	var map := await _spawn_map()
	var region := map.get_node_or_null("Navigation") as NavigationRegion2D
	assert_object(region).is_not_null()
	if region == null:
		return
	var baked := await _wait_for_bake(region)
	assert_bool(baked).is_true()

	var starts: Dictionary = {}
	for guard: Node in get_tree().get_nodes_in_group("guards"):
		starts[guard] = (guard as Node2D).global_position

	for _i in 240:
		await get_tree().physics_frame

	for guard: Node in get_tree().get_nodes_in_group("guards"):
		var moved := (guard as Node2D).global_position.distance_to(starts[guard])
		assert_float(moved) \
			.override_failure_message("Guard %s stayed frozen" % guard.name) \
			.is_greater(15.0)
