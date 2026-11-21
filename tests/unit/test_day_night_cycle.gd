extends GdUnitTestSuite

const CYCLE_SCRIPT := preload("res://scripts/world/day_night_cycle.gd")

const DAY_SECONDS := 10.0
const NIGHT_SECONDS := 4.0


func _spawn_cycle(day := DAY_SECONDS, night := NIGHT_SECONDS):
	var cycle = CYCLE_SCRIPT.new()
	cycle.day_duration = day
	cycle.night_duration = night
	cycle.set_process(false)
	add_child(auto_free(cycle))
	return cycle


func _spend_night(cycle) -> void:
	cycle.advance(DAY_SECONDS)
	cycle.advance(NIGHT_SECONDS)


func test_cycle_starts_during_day_with_no_nights_spent() -> void:
	var cycle = _spawn_cycle()

	assert_bool(cycle.is_night()).is_false()
	assert_int(cycle.nights_spent).is_equal(0)
	assert_int(cycle.day_number).is_equal(1)
	assert_bool(cycle.is_ready_for_next_map()).is_false()


func test_day_turns_into_night_after_day_duration() -> void:
	var cycle = _spawn_cycle()

	cycle.advance(DAY_SECONDS - 0.5)
	assert_bool(cycle.is_night()).is_false()

	cycle.advance(0.5)
	assert_bool(cycle.is_night()).is_true()
	assert_int(cycle.nights_spent).is_equal(0)


func test_completed_night_is_counted_and_starts_a_new_day() -> void:
	var cycle = _spawn_cycle()

	_spend_night(cycle)

	assert_int(cycle.nights_spent).is_equal(1)
	assert_bool(cycle.is_night()).is_false()
	assert_int(cycle.day_number).is_equal(2)


func test_ready_only_after_required_nights_are_spent() -> void:
	var cycle = _spawn_cycle()
	cycle.nights_required_for_next_map = 2
	var ready_emissions := [0]
	cycle.ready_for_next_map.connect(func() -> void: ready_emissions[0] += 1)

	_spend_night(cycle)
	assert_int(cycle.nights_remaining()).is_equal(1)
	assert_bool(cycle.is_ready_for_next_map()).is_false()
	assert_int(ready_emissions[0]).is_equal(0)

	_spend_night(cycle)
	assert_int(cycle.nights_remaining()).is_equal(0)
	assert_bool(cycle.is_ready_for_next_map()).is_true()
	assert_int(ready_emissions[0]).is_equal(1)

	_spend_night(cycle)
	assert_int(ready_emissions[0]).is_equal(1)


func test_night_completed_signal_reports_running_total() -> void:
	var cycle = _spawn_cycle()
	cycle.nights_required_for_next_map = 3
	var totals: Array[int] = []
	cycle.night_completed.connect(func(nights_spent: int) -> void: totals.append(nights_spent))

	_spend_night(cycle)
	_spend_night(cycle)

	assert_array(totals).contains_exactly([1, 2])


func test_zero_required_nights_is_ready_immediately() -> void:
	var cycle = _spawn_cycle()
	cycle.nights_required_for_next_map = 0

	assert_bool(cycle.is_ready_for_next_map()).is_true()
	assert_int(cycle.nights_remaining()).is_equal(0)


func test_negative_required_nights_is_clamped_to_zero() -> void:
	var cycle = _spawn_cycle()
	cycle.nights_required_for_next_map = -3

	assert_int(cycle.nights_required_for_next_map).is_equal(0)
	assert_bool(cycle.is_ready_for_next_map()).is_true()


func test_reset_for_new_map_clears_progress() -> void:
	var cycle = _spawn_cycle()
	_spend_night(cycle)

	cycle.reset_for_new_map(3)

	assert_int(cycle.nights_spent).is_equal(0)
	assert_int(cycle.nights_required_for_next_map).is_equal(3)
	assert_int(cycle.day_number).is_equal(1)
	assert_bool(cycle.is_night()).is_false()
	assert_bool(cycle.is_ready_for_next_map()).is_false()


func test_reset_for_new_map_can_start_at_night() -> void:
	var cycle = _spawn_cycle()

	cycle.reset_for_new_map(1, true)

	assert_bool(cycle.is_night()).is_true()


func test_world_tint_darkens_during_night() -> void:
	var cycle = _spawn_cycle()
	var tint: CanvasModulate = cycle.get_node("Tint")
	assert_object(tint).is_not_null()
	var day_luminance := tint.color.get_luminance()

	cycle.advance(DAY_SECONDS)
	cycle.advance(NIGHT_SECONDS / 2.0)

	assert_float(tint.color.get_luminance()).is_less(day_luminance)


func test_tint_can_be_disabled() -> void:
	var cycle = _spawn_cycle()
	var tint: CanvasModulate = cycle.get_node("Tint")

	cycle.tint_enabled = false
	cycle.advance(1.0)

	assert_bool(tint.visible).is_false()


func test_advance_ignores_non_positive_delta() -> void:
	var cycle = _spawn_cycle()
	var started_at: float = cycle.time_left

	cycle.advance(0.0)
	cycle.advance(-5.0)

	assert_float(cycle.time_left).is_equal(started_at)


func test_raising_requirement_after_ready_clears_readiness() -> void:
	var cycle = _spawn_cycle()
	cycle.nights_required_for_next_map = 1
	var ready_emissions := [0]
	cycle.ready_for_next_map.connect(func() -> void: ready_emissions[0] += 1)

	_spend_night(cycle)
	assert_int(ready_emissions[0]).is_equal(1)

	cycle.nights_required_for_next_map = 2
	assert_bool(cycle.is_ready_for_next_map()).is_false()

	_spend_night(cycle)
	assert_bool(cycle.is_ready_for_next_map()).is_true()
	assert_int(ready_emissions[0]).is_equal(2)


func test_project_registers_the_autoload() -> void:
	var cycle = get_tree().root.get_node_or_null("DayNightCycle")

	assert_object(cycle).is_not_null()
	assert_int(cycle.nights_required_for_next_map).is_equal(2)
	assert_object(cycle.get_node_or_null("Tint")).is_not_null()
