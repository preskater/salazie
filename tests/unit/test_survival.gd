extends GdUnitTestSuite

const SURVIVAL_SCRIPT := preload("res://scripts/systems/survival/survival_component.gd")


func _spawn(active := true) -> Node:
	var component: Node = auto_free(SURVIVAL_SCRIPT.new())
	component.active = active
	add_child(component)
	return component


func test_starts_full() -> void:
	var survival := _spawn()

	assert_float(survival.food).is_equal(100.0)
	assert_float(survival.water).is_equal(100.0)


func test_tick_drains_food_and_water() -> void:
	var survival := _spawn()

	survival.tick(1.0)

	assert_float(survival.food).is_equal_approx(99.0, 0.001)
	assert_float(survival.water).is_equal_approx(98.5, 0.001)


func test_inactive_component_does_not_drain() -> void:
	var survival := _spawn(false)

	survival.tick(10.0)

	assert_float(survival.food).is_equal(100.0)
	assert_float(survival.water).is_equal(100.0)


func test_add_food_clamps_to_max() -> void:
	var survival := _spawn()

	survival.add_food(500.0)

	assert_float(survival.food).is_equal(100.0)


func test_add_water_clamps_to_max() -> void:
	var survival := _spawn()

	survival.add_water(500.0)

	assert_float(survival.water).is_equal(100.0)


func test_food_changed_is_emitted_with_new_value() -> void:
	var survival := _spawn()
	var values: Array[float] = []
	survival.food_changed.connect(
		func(current: float, _maximum: float) -> void: values.append(current)
	)

	survival.add_food(-25.0)

	assert_int(values.size()).is_equal(1)
	assert_float(values[0]).is_equal_approx(75.0, 0.001)


func test_depleted_is_emitted_once_per_resource() -> void:
	var survival := _spawn()
	var kinds: Array[StringName] = []
	survival.depleted.connect(
		func(kind: StringName) -> void: kinds.append(kind)
	)

	survival.tick(1000.0)
	survival.tick(1000.0)

	assert_int(kinds.size()).is_equal(2)
	assert_array(kinds).contains_exactly_in_any_order([&"food", &"water"])


func test_depleted_rearms_after_refill() -> void:
	var survival := _spawn()
	var kinds: Array[StringName] = []
	survival.depleted.connect(
		func(kind: StringName) -> void: kinds.append(kind)
	)

	survival.tick(1000.0)
	survival.add_food(50.0)
	survival.tick(1000.0)

	assert_int(kinds.size()).is_equal(3)
	assert_array(kinds).contains_exactly_in_any_order([&"food", &"water", &"food"])


func test_drain_adds_up_over_very_short_frames() -> void:
	# Regression (#38): above ~350 fps the drain of one frame was smaller than
	# the tolerance of is_equal_approx and the bars never went down.
	var survival: Node = auto_free(load("res://scripts/systems/survival/survival_component.gd").new())
	add_child(survival)
	survival.set_process(false)
	survival.set("food_drain", 0.35)
	survival.set("water_drain", 0.55)

	for frame: int in 2000:
		survival.call("tick", 1.0 / 1000.0)

	assert_float(float(survival.get("food"))).is_equal_approx(100.0 - 0.35 * 2.0, 0.01)
	assert_float(float(survival.get("water"))).is_equal_approx(100.0 - 0.55 * 2.0, 0.01)
