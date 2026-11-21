extends GdUnitTestSuite

const ENDING_SCENE := preload("res://scenes/ui/ending/ending_screen.tscn")


func before_test() -> void:
	GameState.playing = false
	Campaign.reset()
	Campaign.current_map = 3
	Campaign.heritage = 120


func after_test() -> void:
	Campaign.reset()
	GameState.playing = false
	if get_tree() != null:
		get_tree().paused = false


func _spawn_ending() -> Control:
	var ending: Control = ENDING_SCENE.instantiate()
	add_child(auto_free(ending))
	await get_tree().process_frame
	return ending


func test_forest_plan_and_election_produce_a_positive_epilogue() -> void:
	Campaign.set_choice("map3_plan", "forest")
	Campaign.complete_task("become_mayor")
	var ending := await _spawn_ending()

	var text := String(ending.call("get_epilogue_text"))
	assert_str(text).contains("forêt")
	assert_str(text).contains("maire")
	assert_str(String(ending.call("get_stats_text"))).contains("120 G")


func test_failed_council_vote_produces_a_secondary_epilogue() -> void:
	Campaign.set_choice("map3_plan", "farms")
	Campaign.fail_task("become_mayor", "Le conseil a rejeté le plan")
	var ending := await _spawn_ending()

	var text := String(ending.call("get_epilogue_text"))
	assert_str(text).contains("ne vous suit pas")
	assert_str(text).contains("échecs")
