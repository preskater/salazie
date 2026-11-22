class_name HeirMap
extends Node2D
## Map 3 — L'héritier. A modern valley where the player listens to the
## inhabitants, assesses the fragile sites, chooses a plan and faces the
## final council vote. The world layout lives in scenes/maps/heir.tscn.

signal ride_finished

const MAP_SIZE := Vector2(3456.0, 2496.0)
const ECONOMY_GENERATION := &"heritier"
const EURO := &"euro"
const GREEN_CREDIT := &"credit_vert"
## Green credits are the residents' trust: listening and walking the village
## earn them, and they pay for what money cannot buy.
const CREDITS_PER_RESIDENT := 4
const CREDITS_PER_LANDMARK := 3
const SHUTTLE_LANE_X := 1752.0
const SHUTTLE_SCENE := preload("res://scenes/heir/shuttle.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const TASK_LIST_SCENE := preload("res://scenes/ui/tasks/task_list.tscn")
const RESULT_SCENE := preload("res://scenes/ui/tasks/generation_result.tscn")
const DIALOGUE_SCENE := preload("res://scenes/ui/dialogue/dialogue_box.tscn")
const DECISION_SCENE := preload("res://scenes/ui/decision/decision_panel.tscn")

var _world: Node2D
var _player: Node2D
var _dialogue: DialogueBox
var _decision_panel: DecisionPanel
var _notification_label: Label
var _prompt_label: Label
var _hint_label: Label
var _notification_timer: Timer
var _target: Node = null
var _shuttle: Node2D
var _shuttle_active := false
var _council_done := false
var _budget_label: Label
var _support_label: Label


## The farm's gourdes become the heir's euros, once: a save made in the village
## already holds the heir's wallets and must not be reset.
func _enter_tree() -> void:
	if not Economy.has_generation(ECONOMY_GENERATION) \
			or Economy.current_generation_id() == ECONOMY_GENERATION:
		return
	# Read while the farm's economy is still selected.
	if Campaign.heritage <= 0:
		Campaign.heritage = Campaign.heritage_for_map3()
	Economy.select_generation(ECONOMY_GENERATION)
	Economy.set_balance(EURO, Campaign.heritage)
	Economy.set_balance(GREEN_CREDIT, 0)


func _ready() -> void:
	if not SceneRouter.is_gameplay:
		SceneRouter.is_gameplay = true
	if not GameState.playing:
		GameState.playing = true
	GameState.farm_active = false
	Campaign.ensure_map(3)
	Campaign.current_map = 3
	DayNightCycle.nights_required_for_next_map = 0
	DayNightCycle.running = true
	DayNightCycle.tint_enabled = true
	_world = $World
	_add_player()
	_add_ui()
	_connect_world()
	_restore_world(SaveGame.register_world(3, save_world))
	_notify("Map 3 — L'héritier : écoutez, évaluez et décidez de l'avenir de Salazie.")


func _exit_tree() -> void:
	SaveGame.unregister_world(3)


## The village keeps its state in `Campaign`; only the heir's position is left.
## During a shuttle ride the player is a passenger, so nothing is recorded.
func save_world() -> Dictionary:
	if _shuttle_active or _player.get_parent() != _world:
		return {}
	return {"player": [_player.global_position.x, _player.global_position.y]}


func _restore_world(data: Dictionary) -> void:
	var position_data: Variant = data.get("player", null)
	if position_data is Array and (position_data as Array).size() == 2:
		var point := Vector2(float(position_data[0]), float(position_data[1]))
		if Rect2(Vector2.ZERO, MAP_SIZE).has_point(point):
			_player.global_position = point
			_player.reset_physics_interpolation()


func _add_player() -> void:
	var spawn := Vector2(1752, 2376)
	var marker := get_node_or_null("PlayerSpawn") as Node2D
	if marker != null:
		spawn = marker.position
	_player = PLAYER_SCENE.instantiate()
	_player.name = "Player"
	_player.position = spawn
	_player.set("camera_limits", Rect2i(0, 0, int(MAP_SIZE.x), int(MAP_SIZE.y)))
	_world.add_child(_player)
	var survival := _player.get_node_or_null("Survival")
	if survival != null:
		survival.set("active", false)


func _connect_world() -> void:
	for node: Node in get_tree().get_nodes_in_group("npc"):
		var npc := node as FarmNPC
		if npc:
			npc.dialogue_requested.connect(
				_on_npc_dialogue.bind(String(npc.name).trim_prefix("NPC_")))
			npc.player = _player
	for node: Node in get_tree().get_nodes_in_group("fragile_sites"):
		node.inspected.connect(_on_site_inspected)
		node.funding_requested.connect(_on_site_funding_requested.bind(node))
	Economy.balance_changed.connect(_refresh_status.unbind(2))
	Campaign.choices_changed.connect(_refresh_status)
	for node: Node in get_tree().get_nodes_in_group("decision_points"):
		node.requested.connect(_on_decision_requested)
	for node: Node in get_tree().get_nodes_in_group("town_halls"):
		node.requested.connect(_on_town_hall_requested)
	for node: Node in get_tree().get_nodes_in_group("landmarks"):
		node.inspected.connect(_on_landmark_inspected.bind(String(node.get("landmark_id"))))
	for node: Node in get_tree().get_nodes_in_group("bus_stops"):
		node.ride_requested.connect(_on_ride_requested.bind(node))


func _add_ui() -> void:
	var tasks: CanvasLayer = TASK_LIST_SCENE.instantiate()
	tasks.name = "TaskList"
	add_child(tasks)
	var result: CanvasLayer = RESULT_SCENE.instantiate()
	result.name = "GenerationResult"
	add_child(result)
	_dialogue = DIALOGUE_SCENE.instantiate()
	_dialogue.name = "DialogueBox"
	add_child(_dialogue)
	_decision_panel = DECISION_SCENE.instantiate()
	_decision_panel.name = "DecisionPanel"
	_decision_panel.plan_chosen.connect(_on_plan_chosen)
	add_child(_decision_panel)

	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 5
	add_child(overlay)

	var heritage := _status_label("HeritageLabel", Vector2(22, 18), 20)
	heritage.text = "Héritage familial : %d G" % Campaign.heritage
	overlay.add_child(heritage)
	_budget_label = _status_label("BudgetLabel", Vector2(22, 46), 17)
	overlay.add_child(_budget_label)
	_support_label = _status_label("SupportLabel", Vector2(22, 70), 17)
	overlay.add_child(_support_label)
	_refresh_status()

	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.text = _controls_hint()
	InputHints.device_changed.connect(_on_input_device_changed)
	_hint_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_hint_label.add_theme_constant_override("outline_size", 6)
	overlay.add_child(_hint_label)

	_notification_label = Label.new()
	_notification_label.name = "NotificationLabel"
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.66))
	_notification_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_notification_label.add_theme_constant_override("outline_size", 7)
	_notification_label.add_theme_font_size_override("font_size", 22)
	overlay.add_child(_notification_label)

	_notification_timer = Timer.new()
	_notification_timer.one_shot = true
	_notification_timer.wait_time = 4.0
	_notification_timer.timeout.connect(_hide_notification)
	overlay.add_child(_notification_timer)

	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.74))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.add_theme_font_size_override("font_size", 19)
	overlay.add_child(_prompt_label)

	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()


func _status_label(label_name: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.position = at
	label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", font_size)
	return label


## Budget left and where the council stands, always on screen.
func _refresh_status() -> void:
	if _budget_label == null:
		return
	_budget_label.text = "Budget : %s" % GameState.format_wallets()
	var support := Campaign.support_breakdown()
	_support_label.text = "Soutien du conseil : %d / %d" % [
		int(support["total"]), int(support["needed"])]


func _controls_hint() -> String:
	return InputHints.format(
		"Déplacez-vous : {move} · Interagir : {interact} · Tâches : {toggle_tasks}")


func _on_input_device_changed(_using_gamepad: bool) -> void:
	_hint_label.text = _controls_hint()


func _layout_hud() -> void:
	var screen := get_viewport_rect().size
	_hint_label.position = Vector2(18, screen.y - 42)
	_notification_label.position = Vector2(240, screen.y - 92)
	_notification_label.size = Vector2(screen.x - 480, 44)
	_prompt_label.position = Vector2(240, screen.y - 144)
	_prompt_label.size = Vector2(screen.x - 480, 40)


func _process(_delta: float) -> void:
	if _shuttle_active:
		return
	var best: Node = null
	var best_distance := 92.0
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		var node2d := node as Node2D
		if node2d == null or not node2d.is_inside_tree():
			continue
		var distance := _player.global_position.distance_to(node2d.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	_target = best
	if _target:
		_set_prompt(String(_target.call("get_interaction_prompt")))
	else:
		_set_prompt("")


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or _shuttle_active:
		return
	if event.is_action_pressed("interact"):
		if _target and _target.has_method("interact"):
			_target.call("interact", _player)
			get_viewport().set_input_as_handled()


func _set_prompt(text: String) -> void:
	if _prompt_label == null:
		return
	_prompt_label.text = text
	_prompt_label.visible = not text.is_empty()


func _on_npc_dialogue(speaker: String, text: String, npc_id: String) -> void:
	_dialogue.show_line(speaker, text)
	if Campaign.get_choice("listened_" + npc_id) != "1":
		Campaign.set_choice("listened_" + npc_id, "1")
		Campaign.add_task_progress("listen", 1)
		Economy.add_currency(GREEN_CREDIT, CREDITS_PER_RESIDENT)
		_notify("Vous écoutez %s (%d/%d) : +%s." % [
			speaker, Campaign.residents_heard(), Campaign.RESIDENT_COUNT,
			Economy.format_amount(GREEN_CREDIT, CREDITS_PER_RESIDENT)])


func _on_site_inspected(site_id: String, title: String, description: String) -> void:
	_dialogue.show_line(title, description)
	if Campaign.get_choice("assessed_" + site_id) != "1":
		Campaign.set_choice("assessed_" + site_id, "1")
		Campaign.add_task_progress("assess", 1)
		_notify("Zone évaluée : %s (%d/3)." % [title, Campaign.task_progress("assess")])


func _on_landmark_inspected(title: String, text: String, landmark_id: String) -> void:
	_dialogue.show_line(String(title).capitalize(), text)
	if Campaign.get_choice("visited_" + landmark_id) != "1":
		Campaign.set_choice("visited_" + landmark_id, "1")
		Economy.add_currency(GREEN_CREDIT, CREDITS_PER_LANDMARK)
		_notify("Lieu découvert : %s : +%s." % [String(title).capitalize(),
			Economy.format_amount(GREEN_CREDIT, CREDITS_PER_LANDMARK)])


## The heir pays for the protection of an inspected site. Each funded site is
## one more voice at the council.
func _on_site_funding_requested(site_id: String, offer_id: StringName, site: Node) -> void:
	var offer := Economy.offer(offer_id)
	if offer == null:
		return
	if not Economy.buy(offer_id):
		var missing := offer.price - Economy.balance(offer.currency_id)
		_notify("%s : il manque %s." % [offer.label,
			Economy.format_amount(offer.currency_id, maxi(missing, 0))])
		return
	Campaign.set_choice("funded_" + site_id, "1")
	_dialogue.show_line(String(site.get("title")),
		"%s est financé. Les habitants s'en souviendront au conseil." % offer.label)
	_notify("Site protégé : %s." % String(site.get("title")))


func _on_ride_requested(stop_id: String, destination: Vector2, stop: Node2D) -> void:
	# `_shuttle` outlives `_shuttle_active`: the bus is still driving away after
	# the player got control back, and a second bus must not spawn on top of it.
	if _shuttle_active or _shuttle != null:
		return
	_shuttle_active = true
	_target = null
	_set_prompt("")
	_player.set_physics_process(false)
	var origin := Vector2(SHUTTLE_LANE_X, stop.global_position.y)
	var offscreen := Vector2(SHUTTLE_LANE_X, MAP_SIZE.y + 6.0 * 48.0)
	_shuttle = SHUTTLE_SCENE.instantiate()
	_shuttle.name = "Shuttle"
	_shuttle.position = offscreen
	_world.add_child(_shuttle)
	_notify("La navette arrive...")
	await _shuttle.drive_to(origin)

	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	_dialogue.show_line("La navette", "Vous montez à bord. Destination : %s."
		% ("la mairie" if stop_id == "south" else "l'entrée du village"))
	var door := Vector2(origin.x + 72.0, origin.y - 24.0)
	var board := create_tween()
	board.tween_property(_player, "global_position", door, 0.4)
	await board.finished
	_player.visible = false
	_player.reparent(_shuttle)
	_player.position = Vector2(0, -90)
	if camera != null:
		camera.reset_smoothing()
	await get_tree().create_timer(0.2).timeout
	_dialogue.hide_line()
	_notify("La navette vous emmène...")

	var other := Vector2(SHUTTLE_LANE_X, destination.y)
	await _shuttle.drive_to(other)

	_player.reparent(_world)
	_player.global_position = Vector2(other.x + 72.0, other.y - 24.0)
	_player.visible = true
	if camera != null:
		camera.reset_smoothing()
	var exit := create_tween()
	exit.tween_property(_player, "global_position", destination, 0.4)
	await exit.finished
	_player.reset_physics_interpolation()
	_player.set_physics_process(true)
	_notify("La navette vous dépose %s."
		% ("à la mairie" if stop_id == "south" else "à l'entrée du village"))
	# The player is free again: prompts and interactions must not wait for the
	# bus to leave the map.
	_shuttle_active = false

	await _shuttle.drive_to(offscreen)
	_shuttle.queue_free()
	_shuttle = null
	ride_finished.emit()


func _on_decision_requested() -> void:
	# The choice is permanent. Reopening the panel would pause the game on
	# buttons that can no longer do anything.
	if Campaign.task_status("choose_plan") == Campaign.TaskStatus.DONE:
		_notify("Votre plan est choisi : présentez-le à la mairie.")
		return
	if Campaign.task_status("listen") != Campaign.TaskStatus.DONE:
		_notify("Écoutez d'abord les habitants avant de proposer un plan.")
		return
	if Campaign.task_status("assess") != Campaign.TaskStatus.DONE:
		_notify("Évaluez les trois zones fragiles avant de proposer un plan.")
		return
	_decision_panel.open()


func _on_plan_chosen(plan_id: String) -> void:
	var label: String = {
		"forest": "Protéger la forêt et la rivière",
		"tourism": "Développer un tourisme durable",
		"farms": "Soutenir les familles paysannes",
	}.get(plan_id, plan_id)
	_notify("Plan choisi : %s" % label)


func _on_town_hall_requested() -> void:
	# The map stays live while the ending fades in; a second vote would pause
	# the tree again and carry that pause into the ending screen.
	if _council_done:
		return
	if Campaign.task_status("choose_plan") != Campaign.TaskStatus.DONE:
		_notify("Choisissez d'abord un plan au conseil du village.")
		return
	if Campaign.task_status("listen") != Campaign.TaskStatus.DONE \
			or Campaign.task_status("assess") != Campaign.TaskStatus.DONE:
		_notify("Le conseil veut savoir ce que vous avez appris du terrain.")
		return
	_council_done = true
	var support := Campaign.mayor_support()
	if Campaign.has_mayor_support():
		Campaign.complete_task("become_mayor")
		_dialogue.show_line("Le conseil", "Votre plan est adopté. Salazie vous confie son avenir.")
	else:
		Campaign.fail_task("become_mayor", "Le conseil a rejeté votre plan (soutien %d/%d)"
			% [support, Campaign.SUPPORT_NEEDED])
		_dialogue.show_line("Le conseil", "Votre plan est refusé. Le village se divisera, mais la vallée continuera.")
	await _show_result_and_end()


func _show_result_and_end() -> void:
	var overlay := get_tree().get_first_node_in_group("generation_result") as GenerationResult
	if overlay != null:
		overlay.show_result(Campaign.map_summary(), "Épilogue de Salazie",
			"Héritage familial : %d G · Soutien du conseil : %d / %d" % [
				Campaign.heritage, Campaign.mayor_support(), Campaign.SUPPORT_NEEDED])
		await overlay.confirmed
	await SceneRouter.go_to_ending()


func _notify(text: String) -> void:
	if _notification_label == null:
		return
	_notification_label.text = text
	_notification_label.visible = true
	if _notification_timer != null:
		_notification_timer.start()


func _hide_notification() -> void:
	if _notification_label != null:
		_notification_label.visible = false
