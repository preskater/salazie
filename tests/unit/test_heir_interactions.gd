extends GdUnitTestSuite
## Map 3 as the player meets it: the prompt of the nearest thing, the interact
## key, the shuttle, the notifications and the vote that ends the campaign.

const HEIR_SCENE := preload("res://scenes/maps/heir.tscn")
const LANDMARK_SCENE := preload("res://scenes/heir/landmark_point.tscn")
const SITE_SCENE := preload("res://scenes/heir/fragile_site.tscn")
const DECISION_POINT_SCENE := preload("res://scenes/heir/decision_point.tscn")
const TOWN_HALL_SCENE := preload("res://scenes/heir/town_hall.tscn")
const BUS_STOP_SCENE := preload("res://scenes/heir/bus_stop.tscn")
const SHUTTLE_SCENE := preload("res://scenes/heir/shuttle.tscn")
const TEST_SAVE_PATH := "user://test_heir_interactions.json"

var _original_save_path := ""
var _day_night: Array = []
var _swaps: Array[String] = []


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	_day_night = [DayNightCycle.running, DayNightCycle.tint_enabled,
		DayNightCycle.nights_required_for_next_map, DayNightCycle.nights_spent]
	_swaps = []
	SceneRouter.scene_changer = func(path: String) -> Error:
		_swaps.append(path)
		return OK
	SceneRouter.fade_time = 0.01
	SceneRouter.is_gameplay = false
	GameState.playing = false
	# Back on the farm's economy: the map converts it into the heir's on entry.
	GameState.reset()
	GameState.money = 100
	Campaign.reset()


func after_test() -> void:
	GameState.playing = false
	Campaign.reset()
	GameState.reset()
	GameState.farm_active = true
	SceneRouter.scene_changer = Callable()
	SceneRouter.fade_time = SceneRouter.FADE_TIME
	SceneRouter.is_gameplay = false
	DayNightCycle.running = _day_night[0]
	DayNightCycle.tint_enabled = _day_night[1]
	DayNightCycle.nights_required_for_next_map = _day_night[2]
	DayNightCycle.nights_spent = _day_night[3]
	if InputHints.using_gamepad:
		InputHints.note_event(InputEventKey.new())
	SaveGame.save_path = _original_save_path
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if get_tree() != null:
		get_tree().paused = false


func _spawn_map() -> HeirMap:
	var map: HeirMap = HEIR_SCENE.instantiate()
	add_child(auto_free(map))
	await get_tree().process_frame
	await get_tree().physics_frame
	return map


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _landmark(landmark_id: String) -> Area2D:
	for node: Node in get_tree().get_nodes_in_group("landmarks"):
		if String(node.get("landmark_id")) == landmark_id:
			return node as Area2D
	return null


func _bus_stop(stop_id: String) -> Area2D:
	for node: Node in get_tree().get_nodes_in_group("bus_stops"):
		if String(node.get("stop_id")) == stop_id:
			return node as Area2D
	return null


## Puts the heir on `point` and lets the map look for what is in reach.
func _stand_at(map: HeirMap, point: Vector2) -> void:
	var player: Node2D = map.get_node("World/Player")
	player.global_position = point
	await get_tree().process_frame
	await get_tree().process_frame


## A spot of the map with nothing to interact with around.
func _empty_spot() -> Vector2:
	for y: int in range(200, 2400, 150):
		for x: int in range(200, 3300, 150):
			var point := Vector2(x, y)
			var free := true
			for node: Node in get_tree().get_nodes_in_group("interactable"):
				if node is Node2D and (node as Node2D).global_position.distance_to(point) < 400.0:
					free = false
					break
			if free:
				return point
	return Vector2.ZERO


func _resolve_fieldwork_and_plan() -> void:
	Campaign.complete_task("listen")
	Campaign.complete_task("assess")
	Campaign.set_choice("map3_plan", "forest")
	Campaign.complete_task("choose_plan")


# --- Arrival ---------------------------------------------------------------------

func test_entering_the_village_starts_a_running_game_on_map_three() -> void:
	Campaign.current_map = 2
	GameState.farm_active = true
	DayNightCycle.running = false
	DayNightCycle.nights_required_for_next_map = 2

	await _spawn_map()

	assert_bool(SceneRouter.is_gameplay).is_true()
	assert_bool(GameState.playing).is_true()
	assert_bool(GameState.farm_active).is_false()
	assert_int(Campaign.current_map).is_equal(3)
	assert_bool(DayNightCycle.running).is_true()
	assert_int(DayNightCycle.nights_required_for_next_map).is_equal(0)


func test_the_heir_arrives_on_the_spawn_marker() -> void:
	var map: HeirMap = HEIR_SCENE.instantiate()
	(map.get_node("PlayerSpawn") as Node2D).position = Vector2(1500, 2000)

	add_child(auto_free(map))

	var player: Node2D = map.get_node("World/Player")
	assert_vector(player.position).is_equal(Vector2(1500, 2000))
	assert_bool(bool(player.get_node("Survival").get("active"))).is_false()


func test_a_village_without_spawn_marker_uses_the_south_entrance() -> void:
	var map: HeirMap = HEIR_SCENE.instantiate()
	map.get_node("PlayerSpawn").free()

	add_child(auto_free(map))

	assert_vector((map.get_node("World/Player") as Node2D).position).is_equal(Vector2(1752, 2376))


func test_the_arrival_message_fades_after_its_delay() -> void:
	var map := await _spawn_map()
	var label: Label = map.get_node("Overlay/NotificationLabel")
	var timer: Timer = map.get_node("Overlay").find_children("*", "Timer", false, false)[0]
	assert_bool(label.visible).is_true()
	assert_str(label.text).contains("L'héritier")
	assert_bool(timer.is_stopped()).is_false()
	assert_bool(timer.one_shot).is_true()

	timer.timeout.emit()
	assert_bool(label.visible).is_false()

	# The next message shows the label again and restarts the delay.
	timer.stop()
	(get_tree().get_first_node_in_group("town_halls") as Node).call(
		"interact", map.get_node("World/Player"))
	assert_bool(label.visible).is_true()
	assert_str(label.text).contains("plan")
	assert_bool(timer.is_stopped()).is_false()


func test_the_controls_hint_follows_the_device_in_use() -> void:
	var map := await _spawn_map()
	var hint: Label = map.get_node("Overlay/HintLabel")
	var keyboard_text := hint.text
	assert_str(keyboard_text).contains(InputHints.keyboard_label(&"interact"))

	InputHints.note_event(InputEventJoypadButton.new())

	assert_str(hint.text).is_not_equal(keyboard_text)
	assert_str(hint.text).contains("Interagir : %s" % InputHints.gamepad_label(&"interact"))
	assert_str(hint.text).contains("Tâches : %s" % InputHints.gamepad_label(&"toggle_tasks"))

	InputHints.note_event(InputEventKey.new())
	assert_str(hint.text).is_equal(keyboard_text)


# --- Prompt and interact key --------------------------------------------------------

func test_the_prompt_names_what_the_heir_stands_next_to() -> void:
	var map := await _spawn_map()
	var prompt: Label = map.get_node("Overlay/PromptLabel")
	var key := InputHints.label(&"interact")

	await _stand_at(map, _landmark("belvedere").global_position + Vector2(20, 0))
	assert_bool(prompt.visible).is_true()
	assert_str(prompt.text).is_equal("%s — Observer le belvédère" % key)

	var point: Node2D = get_tree().get_first_node_in_group("decision_points")
	await _stand_at(map, point.global_position + Vector2(0, 30))
	assert_str(prompt.text).is_equal("%s — Prendre une décision" % key)

	await _stand_at(map, _bus_stop("south").global_position)
	assert_str(prompt.text).is_equal("%s — Prendre la navette" % key)

	var hall: Node2D = get_tree().get_first_node_in_group("town_halls")
	await _stand_at(map, hall.global_position)
	assert_str(prompt.text).is_equal("%s — Présenter le plan au conseil (soutien %d/%d)" % [
		key, Campaign.SUPPORT_START, Campaign.SUPPORT_NEEDED])


func test_the_prompt_disappears_away_from_everything() -> void:
	var map := await _spawn_map()
	var prompt: Label = map.get_node("Overlay/PromptLabel")
	await _stand_at(map, _landmark("jardin").global_position)
	assert_bool(prompt.visible).is_true()
	var spot := _empty_spot()
	assert_vector(spot).is_not_equal(Vector2.ZERO)

	await _stand_at(map, spot)

	assert_bool(prompt.visible).is_false()
	assert_str(prompt.text).is_empty()


func test_the_prompt_picks_the_nearest_of_two_things_in_reach() -> void:
	var map := await _spawn_map()
	var prompt: Label = map.get_node("Overlay/PromptLabel")
	var near := _landmark("jardin")
	var far := _landmark("belvedere")
	var spot := _empty_spot()
	near.global_position = spot + Vector2(30, 0)
	far.global_position = spot + Vector2(-70, 0)

	await _stand_at(map, spot)
	assert_str(prompt.text).contains("le jardin partagé")

	far.global_position = spot + Vector2(-10, 0)
	await _stand_at(map, spot)
	assert_str(prompt.text).contains("le belvédère")


func test_an_interactable_that_is_not_in_the_world_is_never_the_target() -> void:
	var map := await _spawn_map()
	var prompt: Label = map.get_node("Overlay/PromptLabel")
	var ghost := Node.new()
	ghost.add_to_group("interactable")
	map.add_child(ghost)

	await _stand_at(map, _landmark("jardin").global_position)

	assert_str(prompt.text).contains("le jardin partagé")
	await _stand_at(map, _empty_spot())
	assert_bool(prompt.visible).is_false()


func test_the_interact_key_acts_on_what_the_prompt_names() -> void:
	var map := await _spawn_map()
	await _stand_at(map, _landmark("jardin").global_position)

	map._unhandled_input(_press(&"interact"))

	assert_str(Campaign.get_choice("visited_jardin")).is_equal("1")
	assert_str(Campaign.get_choice("visited_belvedere")).is_empty()
	var dialogue: DialogueBox = map.get_node("DialogueBox")
	assert_bool(dialogue.visible).is_true()
	assert_str(dialogue.get_text()).contains("Le jardin nourrit le quartier")
	assert_str((map.get_node("Overlay/NotificationLabel") as Label).text).contains(
		"Lieu découvert : Le Jardin Partagé")


func test_another_key_does_not_interact() -> void:
	var map := await _spawn_map()
	await _stand_at(map, _landmark("jardin").global_position)

	map._unhandled_input(_press(&"toggle_tasks"))

	assert_str(Campaign.get_choice("visited_jardin")).is_empty()
	assert_bool((map.get_node("DialogueBox") as DialogueBox).visible).is_false()


func test_the_interact_key_does_nothing_with_nothing_in_reach() -> void:
	var map := await _spawn_map()
	await _stand_at(map, _empty_spot())

	map._unhandled_input(_press(&"interact"))

	assert_bool((map.get_node("DialogueBox") as DialogueBox).visible).is_false()
	assert_dict(Campaign.choices).is_empty()


func test_the_interact_key_is_ignored_while_the_game_is_paused() -> void:
	var map := await _spawn_map()
	await _stand_at(map, _landmark("jardin").global_position)
	get_tree().paused = true

	map._unhandled_input(_press(&"interact"))
	assert_str(Campaign.get_choice("visited_jardin")).is_empty()

	get_tree().paused = false
	map._unhandled_input(_press(&"interact"))
	assert_str(Campaign.get_choice("visited_jardin")).is_equal("1")


# --- Shuttle ----------------------------------------------------------------------

func test_the_north_stop_takes_the_heir_back_to_the_village_entrance() -> void:
	var map := await _spawn_map()
	var world: Node = map.get_node("World")
	var player: Node2D = map.get_node("World/Player")
	var prompt: Label = map.get_node("Overlay/PromptLabel")
	var notification: Label = map.get_node("Overlay/NotificationLabel")
	var dialogue: DialogueBox = map.get_node("DialogueBox")
	var stop := _bus_stop("north")
	var destination: Vector2 = stop.get("destination")
	await _stand_at(map, stop.global_position)
	assert_str(prompt.text).contains("Prendre la navette")

	map._unhandled_input(_press(&"interact"))

	assert_str(notification.text).is_equal("La navette arrive...")
	assert_bool(prompt.visible).is_false()
	assert_bool(player.is_physics_processing()).is_false()

	# The heir is a passenger: the interact key and the prompt stay off, and
	# nothing is recorded for the save.
	while player.get_parent() == world:
		await get_tree().process_frame
	map._unhandled_input(_press(&"interact"))
	await get_tree().process_frame
	assert_bool(player.visible).is_false()
	assert_bool(prompt.visible).is_false()
	assert_dict(map.save_world()).is_empty()
	assert_str(dialogue.get_text()).is_equal("Vous montez à bord. Destination : l'entrée du village.")
	assert_int(world.find_children("Shuttle*", "", false, false).size()).is_equal(1)

	while not player.is_physics_processing():
		await get_tree().process_frame
	assert_bool(player.visible).is_true()
	assert_object(player.get_parent()).is_same(world)
	assert_float(player.global_position.distance_to(destination)).is_less(4.0)
	assert_str(notification.text).is_equal("La navette vous dépose à l'entrée du village.")
	assert_bool(map.save_world().has("player")).is_true()

	await map.ride_finished
	await get_tree().process_frame
	assert_object(world.get_node_or_null("Shuttle")).is_null()


func test_the_shuttle_faces_the_way_it_drives() -> void:
	var shuttle: Node2D = SHUTTLE_SCENE.instantiate()
	add_child(auto_free(shuttle))
	var sprite: AnimatedSprite2D = shuttle.get_node("Sprite")
	assert_str(String(sprite.animation)).is_equal("bus_up")
	assert_bool(sprite.is_playing()).is_true()

	await shuttle.call("drive_to", Vector2(60, 10))
	assert_str(String(sprite.animation)).is_equal("bus_right")
	assert_vector(shuttle.position).is_equal_approx(Vector2(60, 10), Vector2.ONE)

	await shuttle.call("drive_to", Vector2(-40, 0))
	assert_str(String(sprite.animation)).is_equal("bus_left")

	await shuttle.call("drive_to", Vector2(-40, 80))
	assert_str(String(sprite.animation)).is_equal("bus_down")

	await shuttle.call("drive_to", Vector2(-40, -20))
	assert_str(String(sprite.animation)).is_equal("bus_up")
	assert_vector(shuttle.position).is_equal_approx(Vector2(-40, -20), Vector2.ONE)
	# Parked: the bodywork no longer bobs and stands on its wheels.
	await get_tree().process_frame
	assert_float(sprite.position.y).is_equal(0.0)
	var frame := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	assert_float(sprite.offset.y).is_equal(-frame.get_height() / 2.0)


# --- Council ----------------------------------------------------------------------

func test_the_council_wants_the_fieldwork_behind_a_plan() -> void:
	var map := await _spawn_map()
	var hall: Node = get_tree().get_first_node_in_group("town_halls")
	(map.get_node("DecisionPanel") as DecisionPanel).choose_plan("forest")

	hall.call("interact", map.get_node("World/Player"))

	assert_str((map.get_node("Overlay/NotificationLabel") as Label).text).is_equal(
		"Le conseil veut savoir ce que vous avez appris du terrain.")
	assert_int(Campaign.task_status("become_mayor")).is_equal(Campaign.TaskStatus.PENDING)
	assert_bool((map.get_node("GenerationResult") as GenerationResult).visible).is_false()
	assert_bool(get_tree().paused).is_false()

	# Listening alone is not enough either.
	Campaign.complete_task("listen")
	hall.call("interact", map.get_node("World/Player"))
	assert_int(Campaign.task_status("become_mayor")).is_equal(Campaign.TaskStatus.PENDING)


func test_a_rejected_plan_still_leads_to_the_epilogue() -> void:
	var map := await _spawn_map()
	var hall: Node = get_tree().get_first_node_in_group("town_halls")
	var result: GenerationResult = map.get_node("GenerationResult")
	_resolve_fieldwork_and_plan()

	hall.call("interact", map.get_node("World/Player"))

	assert_bool(result.visible).is_true()
	assert_str(result.get_title_text()).is_equal("Map 3 — L'héritier")
	assert_str((result.find_child("Subtitle", true, false) as Label).text).starts_with(
		"Génération difficile")
	assert_str((result.find_child("Footer", true, false) as Label).text).is_equal(
		"Le conseil refuse votre plan : le village se divisera, mais la vallée continuera."
		+ "\nHéritage familial : 100 G · Soutien du conseil : %d / %d" % [
			Campaign.SUPPORT_START, Campaign.SUPPORT_NEEDED])
	assert_str(Campaign.task_last_failure("become_mayor")).is_equal(
		"Le conseil a rejeté votre plan (soutien %d/%d)" % [
			Campaign.SUPPORT_START, Campaign.SUPPORT_NEEDED])
	# Nothing moves until the player has read the report.
	assert_array(_swaps).is_empty()
	assert_bool(Campaign.finished).is_false()

	(result.find_child("ContinueButton", true, false) as Button).pressed.emit()
	await SceneRouter.transition_finished

	assert_array(_swaps).contains_exactly([SceneRouter.ENDING_SCENE])
	assert_bool(Campaign.finished).is_true()
	assert_bool(GameState.playing).is_false()
	assert_bool(SceneRouter.is_gameplay).is_false()
	assert_bool(get_tree().paused).is_false()
	assert_str(String(Campaign.results[3]["rank"])).is_equal("poor")


func test_an_adopted_plan_leads_to_the_epilogue_as_mayor() -> void:
	var map := await _spawn_map()
	var hall: Node = get_tree().get_first_node_in_group("town_halls")
	var result: GenerationResult = map.get_node("GenerationResult")
	_resolve_fieldwork_and_plan()
	Campaign.set_choice("funded_foret", "1")

	hall.call("interact", map.get_node("World/Player"))
	assert_str(((map.get_node("GenerationResult") as GenerationResult).get("_footer") as Label).text) \
		.contains("adopte")
	assert_str((result.find_child("Subtitle", true, false) as Label).text).starts_with(
		"Génération accomplie")
	(result.find_child("ContinueButton", true, false) as Button).pressed.emit()
	await SceneRouter.transition_finished

	assert_array(_swaps).contains_exactly([SceneRouter.ENDING_SCENE])
	assert_int(Campaign.task_status("become_mayor")).is_equal(Campaign.TaskStatus.DONE)
	assert_bool(Campaign.finished).is_true()
	assert_bool(FileAccess.file_exists(TEST_SAVE_PATH)).is_true()


# --- Interactive points on their own --------------------------------------------------

func test_a_landmark_shows_its_own_picture_and_tint() -> void:
	var texture := PlaceholderTexture2D.new()
	var landmark: Area2D = LANDMARK_SCENE.instantiate()
	landmark.set("texture", texture)
	landmark.set("tint", Color(0.5, 0.75, 1.0))
	landmark.set("title", "la vieille école")
	landmark.set("text", "Les bancs sont encore là.")
	add_child(auto_free(landmark))
	var inspections: Array = []
	landmark.connect("inspected", func(title: String, text: String) -> void:
		inspections.append([title, text]))

	var sprite: Sprite2D = landmark.get_node("Sprite2D")
	assert_object(sprite.texture).is_same(texture)
	assert_bool(sprite.modulate.is_equal_approx(Color(0.5, 0.75, 1.0))).is_true()
	assert_bool(landmark.is_in_group("interactable")).is_true()
	assert_bool(landmark.is_in_group("landmarks")).is_true()
	assert_str(String(landmark.call("get_interaction_prompt"))).is_equal(
		"%s — Observer la vieille école" % InputHints.label(&"interact"))

	landmark.call("interact", null)
	assert_array(inspections).contains_exactly([["la vieille école", "Les bancs sont encore là."]])


func test_a_landmark_without_picture_keeps_its_scene_sprite() -> void:
	var landmark: Area2D = LANDMARK_SCENE.instantiate()
	add_child(auto_free(landmark))

	var sprite: Sprite2D = landmark.get_node("Sprite2D")
	assert_object(sprite.texture).is_null()
	assert_bool(sprite.modulate.is_equal_approx(Color.WHITE)).is_true()
	assert_str(String(landmark.call("get_interaction_prompt"))).ends_with("Observer Point de vue")


func test_a_fragile_site_shows_its_own_picture_and_states() -> void:
	var texture := PlaceholderTexture2D.new()
	var site: Area2D = SITE_SCENE.instantiate()
	site.set("site_id", "berge")
	site.set("title", "La berge érodée")
	site.set("description", "La rivière ronge la berge.")
	site.set("texture", texture)
	site.set("tint", Color(0.6, 0.8, 1.0))
	add_child(auto_free(site))
	var inspections: Array = []
	site.connect("inspected", func(site_id: String, title: String, description: String) -> void:
		inspections.append([site_id, title, description]))

	assert_object((site.get_node("Sprite2D") as Sprite2D).texture).is_same(texture)
	assert_bool((site.get_node("Sprite2D") as Sprite2D).modulate.is_equal_approx(
		Color(0.6, 0.8, 1.0))).is_true()
	assert_bool(bool(site.call("is_assessed"))).is_false()
	assert_str(String(site.call("get_interaction_prompt"))).ends_with("Inspecter La berge érodée")

	site.call("interact", null)
	assert_array(inspections).contains_exactly([
		["berge", "La berge érodée", "La rivière ronge la berge."]])

	# No offer on this site: once assessed there is nothing to fund.
	Campaign.set_choice("assessed_berge", "1")
	assert_bool(bool(site.call("is_assessed"))).is_true()
	assert_bool(bool(site.call("can_be_funded"))).is_false()

	Campaign.set_choice("funded_berge", "1")
	assert_bool(bool(site.call("is_funded"))).is_true()
	assert_str(String(site.call("get_interaction_prompt"))).is_equal("La berge érodée — protégée")
	site.call("interact", null)
	assert_int(inspections.size()).is_equal(1)


func test_the_decision_point_asks_for_a_decision() -> void:
	var point: Area2D = DECISION_POINT_SCENE.instantiate()
	add_child(auto_free(point))
	var requests: Array[int] = []
	point.connect("requested", func() -> void: requests.append(1))

	assert_bool(point.is_in_group("interactable")).is_true()
	assert_bool(point.is_in_group("decision_points")).is_true()
	assert_str(String(point.call("get_interaction_prompt"))).is_equal(
		"%s — Prendre une décision" % InputHints.label(&"interact"))

	point.call("interact", null)
	assert_int(requests.size()).is_equal(1)


func test_the_town_hall_prompt_follows_the_support_of_the_council() -> void:
	var hall: Area2D = TOWN_HALL_SCENE.instantiate()
	add_child(auto_free(hall))
	var requests: Array[int] = []
	hall.connect("requested", func() -> void: requests.append(1))
	assert_bool(hall.is_in_group("town_halls")).is_true()
	assert_str(String(hall.call("get_interaction_prompt"))).ends_with("(soutien 5/6)")

	Campaign.set_choice("funded_berge", "1")
	Campaign.set_choice("funded_marche", "1")
	assert_str(String(hall.call("get_interaction_prompt"))).ends_with("(soutien 7/6)")

	Campaign.record_setback("Repéré", 1)
	assert_str(String(hall.call("get_interaction_prompt"))).ends_with("(soutien 6/6)")

	hall.call("interact", null)
	assert_int(requests.size()).is_equal(1)


func test_a_bus_stop_asks_for_a_ride_to_its_destination() -> void:
	var stop: Area2D = BUS_STOP_SCENE.instantiate()
	stop.set("stop_id", "north")
	stop.set("destination", Vector2(1992, 2184))
	add_child(auto_free(stop))
	var rides: Array = []
	stop.connect("ride_requested", func(stop_id: String, destination: Vector2) -> void:
		rides.append([stop_id, destination]))

	assert_bool(stop.is_in_group("interactable")).is_true()
	assert_bool(stop.is_in_group("bus_stops")).is_true()
	assert_str(String(stop.call("get_interaction_prompt"))).is_equal(
		"%s — Prendre la navette" % InputHints.label(&"interact"))

	stop.call("interact", null)
	assert_array(rides).contains_exactly([["north", Vector2(1992, 2184)]])
