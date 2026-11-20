class_name FarmMap
extends Node2D

const INTERACT_RANGE := 84.0

@onready var player: Node2D = _find_player()
@onready var hud: FarmHUD = $HUD
@onready var market_stand: MarketStand = $World/MarketStand

var _target: Node = null
var _prepared := false
var _planted := false
var _harvested := false
var _sold := false
var _goal := false

func _find_player() -> Node2D:
	var node := get_node_or_null("World/Player2")
	if node == null:
		node = get_node_or_null("World/Player")
	return node as Node2D

func _ready() -> void:
	# Allow opening Farm.tscn directly for debugging, without going through the menu.
	if not SceneRouter.is_gameplay:
		SceneRouter.is_gameplay = true
	if not GameState.playing:
		GameState.playing = true
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
	_refresh_objective()
	GameState.announce("Map 2 — Le cultivateur : préparez la terre, cultivez, vendez au marché.")

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

func _on_plot_prepared() -> void:
	_prepared = true
	_refresh_objective()

func _on_crop_planted(_crop: String) -> void:
	_planted = true
	_refresh_objective()

func _on_crop_harvested(_crop: String, _amount: int) -> void:
	_harvested = true
	_refresh_objective()

func _on_produce_sold(_crop: String, _amount: int, _total: int) -> void:
	_sold = true
	_refresh_objective()

func _on_money_changed(value: int) -> void:
	if value >= 100 and not _goal:
		_goal = true
		GameState.announce("Objectif atteint : 100 G — la ferme prospère !")
		_refresh_objective()

func _refresh_objective() -> void:
	hud.set_objective(_objective_text())

func _objective_text() -> String:
	if not _prepared:
		return "Objectif : préparez une parcelle du potager, au nord de la ferme (E)."
	if not _planted:
		return "Objectif : plantez une graine (1-4 choisit, E plante)."
	if not _harvested:
		return "Objectif : récoltez une culture mûre (E)."
	if not _sold:
		return "Objectif : portez la récolte au marché du hameau, au sud (E)."
	if not _goal:
		return "Objectif : atteignez 100 G pour faire prospérer la ferme."
	return "Map 2 réussie — la ferme de Salazie prospère !"
