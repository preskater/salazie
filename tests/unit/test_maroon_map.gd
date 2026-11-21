extends GdUnitTestSuite

const MAROON_SCENE := preload("res://scenes/maps/maroon.tscn")
const LAYOUT := preload("res://scripts/maroon/maroon_layout.gd")
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
	assert_object(map.get_node_or_null("MaroonUI/Root")).is_not_null()
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


func test_animation_sheets_use_their_real_frame_grid() -> void:
	var map := await _spawn_map()
	var expectations := {
		"res://sprites/exteriors_48x48/animated/sheets/Fishing_Boat_right_48x48.png":
			{"cell": Vector2(240, 96), "frames": 8},
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Water_Buoy_1_48x48.png":
			{"cell": Vector2(96, 96), "frames": 8},
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Seagull_Idle_Left_48x48.png":
			{"cell": Vector2(96, 48), "frames": 6},
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Seagull_Idle_Right_48x48.png":
			{"cell": Vector2(96, 48), "frames": 6},
		"res://sprites/exteriors_48x48/animated/sheets/Crow_Flap_Right_48x48.png":
			{"cell": Vector2(96, 96), "frames": 6},
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Stage_Fog_Machine_Fog_Only_Loop_48x48.png":
			{"cell": Vector2(288, 48), "frames": 6},
		"res://sprites/farm_48x48/animated/Stone_Oven_Smoke_Effect_48x48.png":
			{"cell": Vector2(144, 192), "frames": 8},
		"res://sprites/custom/fishes_1.png": {"cell": Vector2(48, 48), "frames": 12},
		"res://sprites/custom/fishes_2.png": {"cell": Vector2(48, 48), "frames": 14},
		"res://sprites/custom/fishes_3.png": {"cell": Vector2(48, 48), "frames": 14},
	}
	for path: String in expectations:
		var expected: Dictionary = expectations[path]
		var sprite := _animated_sprite_for_texture(map, path)
		assert_object(sprite).override_failure_message(
			"missing animation %s" % path).is_not_null()
		if sprite == null:
			continue
		var frames := sprite.sprite_frames
		assert_int(frames.get_frame_count(&"play")).override_failure_message(
			"wrong frame count for %s" % path).is_equal(int(expected["frames"]))
		var texture := frames.get_frame_texture(&"play", 0) as AtlasTexture
		assert_object(texture).override_failure_message(
			"missing atlas for %s" % path).is_not_null()
		if texture != null:
			assert_vector(texture.region.size).override_failure_message(
				"wrong cell for %s" % path).is_equal(expected["cell"])
			if path.begins_with("res://sprites/custom/fishes_"):
				var atlas: Image = texture.atlas.get_image()
				assert_object(atlas).is_not_null()
				if atlas != null:
					assert_bool(atlas.get_pixel(0, 0).a < 0.01).override_failure_message(
						"%s still has the opaque water background" % path).is_true()


func _animated_sprite_for_texture(map: Node, texture_path: String) -> AnimatedSprite2D:
	for node: Node in map.find_children("*", "AnimatedSprite2D", true, false):
		var sprite := node as AnimatedSprite2D
		if sprite.sprite_frames == null:
			continue
		for animation: StringName in sprite.sprite_frames.get_animation_names():
			if sprite.sprite_frames.get_frame_count(animation) == 0:
				continue
			var texture := sprite.sprite_frames.get_frame_texture(animation, 0) as AtlasTexture
			if texture != null and texture.atlas.resource_path == texture_path:
				return sprite
	return null


func test_wild_animals_walk_on_row_two_and_graze_on_row_three() -> void:
	var map := await _spawn_map()
	var animals := get_tree().get_nodes_in_group("wildlife")
	assert_int(animals.size()).is_greater(0)
	for node: Node in animals:
		assert_int(int(node.get("walk_row"))).override_failure_message(
			"%s walks on the wrong row" % node.name).is_equal(2)
		assert_int(int(node.get("graze_row"))).override_failure_message(
			"%s grazes on the wrong row" % node.name).is_equal(3)


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
	assert_int(get_tree().get_nodes_in_group("forage_spots").size()).is_equal(7)
	assert_int(get_tree().get_nodes_in_group("hide_spots").size()).is_equal(10)
	assert_int(get_tree().get_nodes_in_group("climb_points").size()).is_equal(2)
	assert_int(get_tree().get_nodes_in_group("stealth_zones").size()).is_equal(3)
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


func test_drinking_restores_ten_water_and_respects_the_cooldown() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var survival := player.get_node("Survival")
	survival.set("water", 30.0)

	map.call("_drink")
	assert_float(float(survival.get("water"))).is_equal(40.0)

	map.set("_drink_cooldown", 10.0)
	map.call("_drink")
	assert_float(float(survival.get("water"))).is_equal(40.0)

	map.set("_drink_cooldown", 0.0)
	map.call("_drink")
	assert_float(float(survival.get("water"))).is_equal(50.0)


func test_drinking_at_the_waterfall_basin_completes_find_water() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	player.global_position = map.get("_anchors")["water_spot"]

	map.call("_drink")

	assert_int(Campaign.task_status("find_water")).is_equal(Campaign.TaskStatus.DONE)


func test_drink_reach_requires_fresh_water() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	assert_bool(map.call("_is_near_fresh_water")).override_failure_message(
		"the beach spawn must be out of freshwater reach").is_false()

	var water: TileMapLayer = map.get_node("Terrain/Water")
	for cell: Vector2i in water.get_used_cells():
		if cell.y >= LAYOUT.SEA_ROW:
			continue
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var bank: Vector2i = cell + offset
			if water.get_cell_source_id(bank) != -1:
				continue
			if bank.x < 1 or bank.y < 1 or bank.x >= 71 or bank.y >= 111:
				continue
			player.global_position = Vector2(bank.x * 48 + 24, bank.y * 48 + 24)
			assert_bool(map.call("_is_near_fresh_water")).override_failure_message(
				"fresh water at %s cannot be reached from %s" % [cell, bank]).is_true()
			return
	assert_bool(false).override_failure_message("no freshwater bank found").is_true()


func test_objective_indicator_only_tracks_the_current_task() -> void:
	var map := await _spawn_map()
	var label: Label = map.get_node_or_null("MaroonUI/Root/ObjectiveBar/ObjectiveLabel")
	assert_object(label).is_not_null()
	if label == null:
		return
	assert_bool(label.text.contains("Trouver la rivière")).override_failure_message(
		"the first objective should be the river").is_true()

	Campaign.complete_task("follow_river")
	await get_tree().process_frame
	await get_tree().process_frame

	assert_bool(label.text.contains("Boire à la rivière")).override_failure_message(
		"the indicator should move to the next task").is_true()
	assert_bool(label.text.contains("Trouver la rivière")).is_false()


func test_hiding_conceals_the_player_without_a_task() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var spots := get_tree().get_nodes_in_group("hide_spots")
	var hide_spot: Area2D = spots[0]

	hide_spot.call("_on_body_entered", player)
	assert_bool(bool(player.get("concealed"))).is_true()
	assert_bool((hide_spot.get_node("Ring") as Sprite2D).visible).is_true()
	assert_bool((hide_spot.get_node("HiddenLabel") as Label).visible).is_true()
	hide_spot.call("_process", 2.0)
	assert_bool(Campaign.task_definition("hide_from_patrol").is_empty()).is_true()

	hide_spot.call("_on_body_exited", player)
	assert_bool(bool(player.get("concealed"))).is_false()
	assert_bool((hide_spot.get_node("Ring") as Sprite2D).visible).is_false()
	assert_bool((hide_spot.get_node("HiddenLabel") as Label).visible).is_false()


func test_climb_point_moves_the_player_to_its_destination() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var climb: Area2D = get_tree().get_nodes_in_group("climb_points")[0]
	var destination: Vector2 = climb.get("destination")

	climb.call("interact", player)
	await map.climb_finished

	assert_float(player.global_position.distance_to(destination)).is_less(1.0)


func test_stealth_zones_conceal_and_mute_the_player() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var cave: Area2D = null
	var cascade: Area2D = null
	for node: Node in get_tree().get_nodes_in_group("stealth_zones"):
		if String(node.get("zone_name")) == "la grotte":
			cave = node as Area2D
		elif String(node.get("zone_name")) == "la cascade":
			cascade = node as Area2D
	assert_object(cave).is_not_null()
	assert_object(cascade).is_not_null()

	cave.call("_on_body_entered", player)
	assert_bool(bool(player.get("concealed"))).is_true()
	assert_bool(bool(player.get("noise_muted"))).is_true()
	cave.call("_on_body_exited", player)
	assert_bool(bool(player.get("concealed"))).is_false()
	assert_bool(bool(player.get("noise_muted"))).is_false()

	cascade.call("_on_body_entered", player)
	assert_bool(bool(player.get("concealed"))).is_false()
	assert_bool(bool(player.get("noise_muted"))).is_true()
	cascade.call("_on_body_exited", player)
	assert_bool(bool(player.get("noise_muted"))).is_false()


func test_waterfall_noise_muting_keeps_guards_unaware() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var guard: CharacterBody2D = get_tree().get_nodes_in_group("guards")[0]
	player.global_position = guard.global_position + Vector2(100, 0)

	player.call("set_noise_muted", true)
	player.call("emit_noise")
	assert_int(int(guard.get("state"))).is_equal(0)

	player.call("set_noise_muted", false)
	player.call("emit_noise")
	assert_int(int(guard.get("state"))).is_equal(1)


func test_stealth_checklist_tasks_are_gone() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var checkpoint: Area2D = map.get_node("World/UpperCheckpoint")

	assert_bool(Campaign.task_definition("cross_patrol").is_empty()).is_true()
	assert_bool(Campaign.task_definition("hide_from_patrol").is_empty()).is_true()
	assert_bool(Campaign.task_definition("gather_seeds").is_empty()).is_false()

	checkpoint.call("_on_body_entered", player)
	assert_int(Campaign.task_status("follow_river")).is_equal(Campaign.TaskStatus.PENDING)


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


func test_forage_pickup_spawns_a_pop() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var spots := get_tree().get_nodes_in_group("forage_spots")
	assert_bool(spots.is_empty()).is_false()
	if spots.is_empty():
		return

	var spot: Area2D = spots[0]
	var parent := spot.get_parent()
	var before := parent.get_child_count()
	spot.call("_on_body_entered", player)

	assert_int(parent.get_child_count()).is_equal(before + 1)
	assert_object(parent.get_node_or_null("PickupPop")).is_not_null()


func test_map_ui_lives_in_a_canvas_layer_and_shows_the_clock() -> void:
	var map := await _spawn_map()
	var root := map.get_node_or_null("MaroonUI/Root")
	assert_object(root).is_not_null()
	if root == null:
		return

	assert_object(root.get_node_or_null("ControlsHint")).is_not_null()
	var clock := root.get_node_or_null("ClockLabel") as Label
	assert_object(clock).is_not_null()
	if clock != null:
		assert_str(clock.text).contains("Jour")


func test_seed_pickup_stores_bonus_seeds() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")

	var seed_spot: Area2D = null
	for spot: Node in get_tree().get_nodes_in_group("forage_spots"):
		if String(spot.get("kind")) == "seed":
			seed_spot = spot
			break
	assert_object(seed_spot).is_not_null()
	if seed_spot == null:
		return

	seed_spot.call("interact", player)

	assert_int(Campaign.task_progress("gather_seeds")).is_equal(1)
	assert_bool(Campaign.bonus_seeds.is_empty()).is_false()


func test_pickup_messages_match_the_pickup_kind() -> void:
	var map := await _spawn_map()
	var player: Node2D = map.get_node("World/Player")
	var notification := map.get_node("MaroonUI/Root/Notification") as Label

	var food_spot: Area2D = null
	var seed_spot: Area2D = null
	var water_spot: Area2D = null
	for spot: Node in get_tree().get_nodes_in_group("forage_spots"):
		var kind := String(spot.get("kind"))
		if kind == "food" and food_spot == null:
			food_spot = spot as Area2D
		elif kind == "seed" and seed_spot == null:
			seed_spot = spot as Area2D
		elif kind == "water" and water_spot == null:
			water_spot = spot as Area2D

	assert_object(food_spot).is_not_null()
	if food_spot != null:
		food_spot.call("_on_body_entered", player)
		assert_str(notification.text).contains("Vivres")
	if seed_spot != null:
		seed_spot.call("interact", player)
		assert_str(notification.text).contains("Graines")
	if water_spot != null:
		water_spot.call("interact", player)
		assert_str(notification.text).contains("buvez")
