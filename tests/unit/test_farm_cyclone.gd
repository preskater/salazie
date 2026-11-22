extends GdUnitTestSuite

const FARM_SCENE := preload("res://scenes/maps/farm.tscn")
const TEST_SAVE_PATH := "user://test_farm_cyclone_save.json"

var _original_save_path := ""


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	GameState.playing = false
	GameState.farm_active = true
	Campaign.reset()
	GameState.reset()


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	GameState.farm_active = true
	SaveGame.save_path = _original_save_path
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if get_tree() != null:
		get_tree().paused = false


func _spawn_farm() -> FarmMap:
	var map: FarmMap = FARM_SCENE.instantiate()
	add_child(auto_free(map))
	await get_tree().process_frame
	await get_tree().physics_frame
	return map


func test_cyclone_warns_the_day_before_a_strike() -> void:
	var map := await _spawn_farm()
	var cyclone: Node2D = map.get_node("World/Cyclone")
	var before := cyclone.global_position
	var messages: Array[String] = []
	var on_notify := func(text: String) -> void: messages.append(text)
	GameState.notification_requested.connect(on_notify)

	GameState.day_advanced.emit(2)

	GameState.notification_requested.disconnect(on_notify)
	var has_warning := false
	for message: String in messages:
		if message.contains("cyclone"):
			has_warning = true
	assert_bool(has_warning) \
		.override_failure_message("No cyclone warning on the day before").is_true()
	assert_vector(cyclone.global_position).is_equal(before)


func test_cyclone_moves_on_the_third_day() -> void:
	var map := await _spawn_farm()
	map.cyclone_leg_time = 0.05
	map.cyclone_speed = 3000.0
	var cyclone: Node2D = map.get_node("World/Cyclone")
	var before := cyclone.global_position

	GameState.day_advanced.emit(3)
	await get_tree().create_timer(0.5).timeout

	assert_float(cyclone.global_position.distance_to(before)).is_greater(50.0)


func test_only_ripe_crops_are_destroyed() -> void:
	var map := await _spawn_farm()
	var plots := get_tree().get_nodes_in_group("crops")
	assert_int(plots.size()).is_equal(8)
	if plots.size() < 2:
		return

	var ripe := plots[0] as CropPlot
	var growing := plots[1] as CropPlot
	ripe.state = CropPlot.State.READY
	growing.state = CropPlot.State.GROWING

	var destroyed: int = map.call(
		"_destroy_ripe_crops_on_path", ripe.global_position, ripe.global_position)

	assert_int(destroyed).is_equal(1)
	assert_int(ripe.state).is_equal(CropPlot.State.TILLED)
	assert_int(growing.state).is_equal(CropPlot.State.GROWING)


func test_crop_destroy_requires_a_ripe_crop() -> void:
	await _spawn_farm()
	var plots := get_tree().get_nodes_in_group("crops")
	assert_bool(plots.is_empty()).is_false()
	if plots.is_empty():
		return
	var plot := plots[0] as CropPlot

	plot.state = CropPlot.State.GROWING
	assert_bool(plot.destroy_crop()).is_false()
	assert_int(plot.state).is_equal(CropPlot.State.GROWING)

	plot.state = CropPlot.State.READY
	assert_bool(plot.destroy_crop()).is_true()
	assert_int(plot.state).is_equal(CropPlot.State.TILLED)


func test_strike_reports_its_result() -> void:
	var map := await _spawn_farm()
	map.cyclone_legs = 2
	map.cyclone_leg_time = 0.05
	var messages: Array[String] = []
	var on_notify := func(text: String) -> void: messages.append(text)
	GameState.notification_requested.connect(on_notify)

	map.call("_strike_cyclone")
	await get_tree().create_timer(0.3).timeout

	GameState.notification_requested.disconnect(on_notify)
	var has_report := false
	for message: String in messages:
		if message.contains("cyclone"):
			has_report = true
	assert_bool(has_report).is_true()


func test_cyclone_path_has_many_turning_segments() -> void:
	var map := await _spawn_farm()
	var path: PackedVector2Array = map.call("_cyclone_path", Vector2(2304, 1632))

	assert_int(path.size()).is_equal(7)
	var turns := 0
	for index in range(2, path.size()):
		var previous := (path[index - 1] - path[index - 2]).angle()
		var current := (path[index] - path[index - 1]).angle()
		if absf(angle_difference(previous, current)) > 0.01:
			turns += 1
	assert_int(turns).is_greater(0)


func test_cyclone_path_stays_inside_the_farm() -> void:
	var map := await _spawn_farm()
	var max_x := 4608.0 - 300.0
	var max_y := 3264.0 - 300.0
	for _attempt in 20:
		var path: PackedVector2Array = map.call("_cyclone_path",
			Vector2(randf_range(300.0, max_x), randf_range(300.0, max_y)))
		for point: Vector2 in path:
			assert_float(point.x).is_greater_equal(299.99)
			assert_float(point.x).is_less_equal(max_x + 0.01)
			assert_float(point.y).is_greater_equal(299.99)
			assert_float(point.y).is_less_equal(max_y + 0.01)


func test_cyclone_turn_is_capped() -> void:
	var map := await _spawn_farm()
	var limit := deg_to_rad(float(map.cyclone_turn_deg)) + 0.0001
	var heading := 0.7
	for step in 100:
		var next: float = map.call("_next_heading", heading)
		assert_float(absf(angle_difference(heading, next))).is_less_equal(limit)
		heading = next


# --- #43 -----------------------------------------------------------------------

func test_the_cyclone_is_hidden_and_harmless_between_strikes() -> void:
	# Regression: it sat in the middle of the farm from day 1, pulling the
	# player in.
	var map := await _spawn_farm()
	var cyclone: Node2D = map.get_node("World/Cyclone")

	assert_bool(cyclone.visible).is_false()
	assert_bool(cyclone.is_physics_processing()).is_false()
	assert_vector(cyclone.call("get_wind_at", cyclone.global_position + Vector2(20, 0))) \
		.is_equal(Vector2.ZERO)


func test_a_strike_shows_the_storm_then_puts_it_away() -> void:
	var map := await _spawn_farm()
	var cyclone: Node2D = map.get_node("World/Cyclone")
	map.cyclone_legs = 2
	map.cyclone_leg_time = 0.05

	map.call("_strike_cyclone")
	assert_bool(cyclone.visible).is_true()
	assert_bool(bool(cyclone.get("active"))).is_true()
	# A second strike cannot start on top of the first.
	var position_before := cyclone.global_position
	map.call("_strike_cyclone")
	assert_vector(cyclone.global_position).is_equal(position_before)
	await get_tree().create_timer(0.3).timeout

	assert_bool(cyclone.visible).is_false()
	assert_bool(bool(map.get("_striking"))).is_false()


func test_the_storm_enters_from_the_edge_of_its_zone_and_stays_inside() -> void:
	var map := await _spawn_farm()
	var zone: Rect2 = map.cyclone_zone
	for attempt: int in 40:
		var entry: Vector2 = map.call("_cyclone_entry_point")
		var on_border := is_equal_approx(entry.x, zone.position.x) \
			or is_equal_approx(entry.x, zone.end.x) \
			or is_equal_approx(entry.y, zone.position.y) or is_equal_approx(entry.y, zone.end.y)
		assert_bool(on_border).override_failure_message("%s is not on the border" % entry).is_true()
		for point: Vector2 in map.call("_cyclone_path", entry):
			assert_bool(zone.grow(0.5).has_point(point)).override_failure_message(
				"%s left the travel zone" % point).is_true()


func test_the_travel_zone_covers_the_garden() -> void:
	var map := await _spawn_farm()
	for node: Node in get_tree().get_nodes_in_group("crops"):
		assert_bool(map.cyclone_zone.has_point((node as Node2D).global_position)).is_true()
	# The house yard and the market are out of it.
	assert_bool(map.cyclone_zone.has_point(map.market_stand.global_position)).is_false()


func test_a_refreshed_state_does_not_call_the_storm() -> void:
	# `day_changed` also fires on a load or a reset.
	var map := await _spawn_farm()
	var cyclone: Node2D = map.get_node("World/Cyclone")

	GameState.day_changed.emit(3)

	assert_bool(cyclone.visible).is_false()
	assert_bool(bool(map.get("_striking"))).is_false()


func test_a_crop_falls_when_the_funnel_reaches_it() -> void:
	var map := await _spawn_farm()
	var plot: CropPlot = get_tree().get_nodes_in_group("crops")[0]
	plot.from_dict({"state": CropPlot.State.READY, "crop": "corn", "growth": 99.0})
	var cyclone: Node2D = map.get_node("World/Cyclone")
	map.set("_striking", true)

	cyclone.global_position = plot.global_position + Vector2(FarmMap.CYCLONE_STEAL_RADIUS + 60.0, 0)
	map._physics_process(0.016)
	assert_int(plot.state).is_equal(CropPlot.State.READY)

	cyclone.global_position = plot.global_position + Vector2(40, 0)
	map._physics_process(0.016)
	assert_int(plot.state).is_equal(CropPlot.State.TILLED)
	assert_int(int(map.get("_destroyed"))).is_equal(1)
	map.set("_striking", false)
