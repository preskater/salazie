extends GdUnitTestSuite

const CROP_PLOT_SCENE := "res://game/farm/crop_plot.tscn"


func _spawn_plot(initial_state := 0) -> Node2D:
	var plot: Node2D = auto_free(load(CROP_PLOT_SCENE).instantiate())
	plot.set("initial_state", initial_state)
	add_child(plot)
	return plot


func _soil(plot: Node2D) -> Sprite2D:
	return plot.get_node("Soil") as Sprite2D


func _crop(plot: Node2D) -> Sprite2D:
	return plot.get_node("Sprite") as Sprite2D


func test_soil_sits_below_the_world_layer() -> void:
	var plot := _spawn_plot()

	assert_int(_soil(plot).z_index).is_equal(-1)
	assert_int(_crop(plot).z_index).is_equal(0)


func test_empty_plot_hides_both_sprites() -> void:
	var plot := _spawn_plot()

	assert_bool(_soil(plot).visible).is_false()
	assert_bool(_crop(plot).visible).is_false()


func test_tilled_plot_shows_the_soil_only() -> void:
	var plot := _spawn_plot()
	plot.call("interact", null)

	assert_bool(_soil(plot).visible).is_true()
	assert_bool(_crop(plot).visible).is_false()


func test_plot_can_start_tilled() -> void:
	var plot := _spawn_plot(1)

	assert_bool(_soil(plot).visible).is_true()
	assert_bool(_crop(plot).visible).is_false()
