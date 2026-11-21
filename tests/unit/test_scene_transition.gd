extends GdUnitTestSuite

const TRANSITION_SCENE := preload("res://scenes/preloads/scene_transition.tscn")


func _spawn_transition():
	var transition = TRANSITION_SCENE.instantiate()
	transition.fade_out_duration = 0.0
	transition.hold_duration = 0.0
	transition.fade_in_duration = 0.0
	add_child(auto_free(transition))
	return transition


func test_transition_instantiates_hidden() -> void:
	var transition = _spawn_transition()

	assert_object(transition.get_node_or_null("Backdrop")).is_not_null()
	assert_object(transition.get_node_or_null("Text/Layout/Title")).is_not_null()
	assert_object(transition.get_node_or_null("Text/Layout/Subtitle")).is_not_null()
	assert_float(transition.get_node("Backdrop").color.a).is_equal(0.0)
	assert_bool(transition.is_transitioning).is_false()


func test_cover_shows_configured_title_and_subtitle() -> void:
	var transition = _spawn_transition()

	await transition.cover("Le cultivateur", "Deuxième génération")

	assert_str(transition.get_node("Text/Layout/Title").text).is_equal("Le cultivateur")
	assert_str(transition.get_node("Text/Layout/Subtitle").text).is_equal("Deuxième génération")
	assert_float(transition.get_node("Backdrop").color.a).is_equal(1.0)
	assert_bool(transition.is_transitioning).is_true()


func test_default_text_is_used_when_not_provided() -> void:
	var transition = _spawn_transition()
	transition.default_title = "Salazie"
	transition.default_subtitle = "Trois générations"

	await transition.cover()

	assert_str(transition.get_node("Text/Layout/Title").text).is_equal("Salazie")
	assert_str(transition.get_node("Text/Layout/Subtitle").text).is_equal("Trois générations")


func test_reveal_clears_transition() -> void:
	var transition = _spawn_transition()
	await transition.cover("Titre", "Sous-texte")

	await transition.reveal()

	assert_float(transition.get_node("Backdrop").color.a).is_equal(0.0)
	assert_bool(transition.is_transitioning).is_false()


func test_backdrop_blocks_input_only_while_transitioning() -> void:
	var transition = _spawn_transition()
	var backdrop: ColorRect = transition.get_node("Backdrop")

	assert_int(backdrop.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

	await transition.cover("Titre", "")
	assert_int(backdrop.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)

	await transition.reveal()
	assert_int(backdrop.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_signals_fire_on_cover_and_reveal() -> void:
	var transition = _spawn_transition()
	var started := [0]
	var finished := [0]
	transition.transition_started.connect(func() -> void: started[0] += 1)
	transition.transition_finished.connect(func() -> void: finished[0] += 1)

	await transition.cover("Titre", "")
	assert_int(started[0]).is_equal(1)
	assert_int(finished[0]).is_equal(0)

	await transition.reveal()
	assert_int(finished[0]).is_equal(1)


func test_cover_is_ignored_while_already_transitioning() -> void:
	var transition = _spawn_transition()
	await transition.cover("Premier", "")

	await transition.cover("Deuxième", "")

	assert_str(transition.get_node("Text/Layout/Title").text).is_equal("Premier")


func test_fade_applies_configured_color() -> void:
	var transition = _spawn_transition()
	transition.fade_color = Color(0.1, 0.2, 0.3)

	await transition.cover("Titre", "")

	var color: Color = transition.get_node("Backdrop").color
	assert_float(color.r).is_equal_approx(0.1, 0.001)
	assert_float(color.g).is_equal_approx(0.2, 0.001)
	assert_float(color.b).is_equal_approx(0.3, 0.001)
	assert_float(color.a).is_equal(1.0)
