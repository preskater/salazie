class_name FarmMap
extends Node2D

const INTERACT_RANGE := 84.0
const PROSPERITY_DEADLINE_DAY := 6
const MAP_EXIT_SCENE := preload("res://game/world/MapExit.tscn")
const TASK_LIST_SCENE := preload("res://game/ui/tasks/task_list.tscn")
const SIGN_TEXTURE := "res://assets/farm_48x48/singles/Props_and_Buildings/Sign_1_48x48.png"

@export var economy_generation: StringName = &"cultivateur"

@onready var player: Node2D = _find_player()
@onready var hud: FarmHUD = $HUD
@onready var market_stand: MarketStand = $World/MarketStand

var _target: Node = null


func _find_player() -> Node2D:
	var node := get_node_or_null("World/Player2")
	if node == null:
		node = get_node_or_null("World/Player")
	return node as Node2D


func _enter_tree() -> void:
	# Runs before the HUD builds its offer rows. A loaded save already matches.
	if Economy.has_generation(economy_generation) \
			and Economy.current_generation_id() != economy_generation:
		Economy.select_generation(economy_generation)


func _ready() -> void:
	# Allow opening Farm.tscn directly for debugging, without going through the menu.
	if not SceneRouter.is_gameplay:
		SceneRouter.is_gameplay = true
	if not GameState.playing:
		GameState.playing = true
	GameState.farm_active = true
	Campaign.ensure_map(2)
	Campaign.current_map = 2
	var survival := player.get_node_or_null("Survival")
	if survival != null:
		survival.set("active", false)
	_install_generation_ui()
	_install_map_exit()
	market_stand.market_requested.connect(hud.open_market)
	for node: Node in get_tree().get_nodes_in_group("npc"):
		var npc := node as FarmNPC
		if npc:
			npc.dialogue_requested.connect(hud.show_dialogue)
			npc.player = player
	GameState.plot_prepared.connect(_on_plot_prepared)
	GameState.crop_planted.connect(_on_crop_planted)
	GameState.crop_harvested.connect(_on_crop_harvested)
	GameState.produce_sold.connect(_on_produce_sold)
	GameState.money_changed.connect(_on_money_changed)
	GameState.day_changed.connect(_on_day_changed)
	Campaign.task_status_changed.connect(_on_task_status_changed)
	_refresh_objective()
	GameState.announce("Map 2 — Le cultivateur : préparez la terre, cultivez, vendez au marché.")
	if GameState.day >= PROSPERITY_DEADLINE_DAY:
		_check_prosperity_deadline(GameState.day)


func _process(_delta: float) -> void:
	var best: Node = null
	var best_distance := INTERACT_RANGE
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		var node2d := node as Node2D
		if node2d == null or not node2d.is_inside_tree():
			continue
		var distance := player.global_position.distance_to(node2d.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	_target = best
	if _target:
		hud.set_prompt(String(_target.call("get_interaction_prompt")))
	else:
		hud.set_prompt("")


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("interact"):
		if _target and _target.has_method("interact"):
			_target.call("interact", player)
			get_viewport().set_input_as_handled()
		return
	for i in GameState.CROP_ORDER.size():
		if event.is_action_pressed("select_seed_%d" % (i + 1)):
			GameState.select_seed(GameState.CROP_ORDER[i])
			get_viewport().set_input_as_handled()
			return


func _install_generation_ui() -> void:
	if get_node_or_null("TaskList") == null:
		var task_list: CanvasLayer = TASK_LIST_SCENE.instantiate()
		add_child(task_list)
	if get_node_or_null("GenerationResult") == null:
		var result: CanvasLayer = load("res://game/ui/tasks/generation_result.tscn").instantiate()
		add_child(result)


func _install_map_exit() -> void:
	if get_node_or_null("MapExit") != null:
		return
	var exit: Area2D = MAP_EXIT_SCENE.instantiate()
	exit.name = "MapExit"
	exit.position = Vector2(4360, 3168)
	exit.next_scene_path = SceneRouter.HEIR_SCENE
	exit.title = "L'héritier"
	exit.subtitle = "Troisième génération"
	exit.requires_map_ready = false
	exit.requires_map_complete = true
	exit.show_result = true
	add_child(exit)
	exit.blocked.connect(_on_exit_blocked)

	var sign := Sprite2D.new()
	sign.name = "RoadSign"
	sign.texture = load(SIGN_TEXTURE)
	sign.position = Vector2(4360, 3104)
	sign.scale = Vector2(1.5, 1.5)
	add_child(sign)

	var label := Label.new()
	label.name = "RoadSignLabel"
	label.text = "Route de la ville"
	label.position = Vector2(4260, 3030)
	label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)


func _on_plot_prepared() -> void:
	Campaign.complete_task("prepare_plot")
	_refresh_objective()


func _on_crop_planted(_crop: String) -> void:
	Campaign.complete_task("plant_seed")
	_refresh_objective()


func _on_crop_harvested(_crop: String, _amount: int) -> void:
	Campaign.complete_task("harvest_crop")
	_refresh_objective()


func _on_produce_sold(_crop: String, _amount: int, _total: int) -> void:
	Campaign.complete_task("sell_produce")
	_refresh_objective()


func _on_money_changed(value: int) -> void:
	if value >= 100 and Campaign.task_status("earn_100") == Campaign.TaskStatus.PENDING:
		Campaign.complete_task("earn_100")
		GameState.announce(
			"Objectif atteint : %s — la ferme prospère !" % GameState.format_money(100))
	_refresh_objective()


func _on_day_changed(day: int) -> void:
	_check_prosperity_deadline(day)
	_refresh_objective()


func _check_prosperity_deadline(day: int) -> void:
	if day < PROSPERITY_DEADLINE_DAY:
		return
	if Campaign.task_status("earn_100") != Campaign.TaskStatus.PENDING:
		return
	Campaign.fail_task("earn_100",
		"Délai dépassé : %s non atteints avant le jour %d"
			% [GameState.format_money(100), PROSPERITY_DEADLINE_DAY])
	GameState.announce("Le délai du marché est passé : la ferme termine la génération en difficulté.")


func _on_task_status_changed(_map_id: int, _task_id: String, _status: int) -> void:
	_refresh_objective()


func _on_exit_blocked() -> void:
	GameState.announce("Terminez les tâches de la ferme avant de prendre la route.")


func _refresh_objective() -> void:
	hud.set_objective(_objective_text())


func _objective_text() -> String:
	var summary := Campaign.map_summary()
	if int(summary.get("pending", 0)) == 0:
		return "Map 2 terminée — prenez la route vers la ville, à l'est du hameau."
	for definition: Dictionary in Campaign.TASKS[2]:
		var task_id := String(definition.get("id", ""))
		if Campaign.task_status(task_id) == Campaign.TaskStatus.PENDING:
			return "Objectif : %s" % String(definition.get("hint", definition.get("label", "")))
	return "Objectif : terminez les tâches de la ferme."
