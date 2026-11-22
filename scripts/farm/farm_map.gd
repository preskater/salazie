class_name FarmMap
extends Node2D

const INTERACT_RANGE := 84.0
const PROSPERITY_DEADLINE_DAY := 6
const CYCLONE_EVERY_DAYS := 3
const CYCLONE_STEAL_RADIUS := 220.0
const FARM_SIZE := Vector2(4608.0, 3264.0)
const MAP_EXIT_SCENE := preload("res://scenes/world/map_exit.tscn")
const TASK_LIST_SCENE := preload("res://scenes/ui/tasks/task_list.tscn")
## Seed the seller advances to a farmer who has nothing left to plant or sell.
const RELIEF_CROP := "carrot"
const PROSPERITY_GOAL := 100
## Asset bought at the market (`grant_id` in economy.tres): with a barn, ripe
## crops caught by the cyclone are brought in instead of destroyed.
const BARN_ASSET := &"barn"
const SIGN_TEXTURE := "res://sprites/farm_48x48/singles/Props_and_Buildings/Sign_1_48x48.png"

@export var economy_generation: StringName = &"cultivateur"
## One leg of the storm path: 6 legs × 5 s = a 30 s crossing at 120 px/s, legs
## of 600 px inside a zone 1350 px wide.
@export var cyclone_leg_time := 5.0
@export var cyclone_legs := 6
@export var cyclone_speed := 120.0
@export var cyclone_turn_deg := 60.0
## Where the storm travels: the garden and its surroundings. It enters from an
## edge of this rectangle and bounces off its sides, so it threatens the crops
## instead of wandering over the house, the market or the spawn.
@export var cyclone_zone := Rect2(1150.0, 1300.0, 1350.0, 900.0)

@onready var player: Player = _find_player() as Player
@onready var hud: FarmHUD = $HUD
@onready var market_stand: MarketStand = $World/MarketStand
@onready var cyclone: Node2D = $World/Cyclone

var _target: Node = null
var _relief_announced := false
var _sheltered := 0
var _destroyed := 0
var _striking := false


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
	SceneRouter.bootstrap_direct_run(self)
	GameState.farm_active = true
	# The farm day drives the sky (GameState.sync_sky); the cycle must not also
	# run on its own.
	DayNightCycle.running = false
	DayNightCycle.tint_enabled = true
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
	var seller := get_node_or_null("World/NPCSeller") as FarmNPC
	if seller != null:
		# Connected after the HUD so the relief line replaces the usual one.
		seller.dialogue_requested.connect(_on_seller_talked)
		seller.line_provider = market_tip
	# Deferred: planting spends the seed before the plot starts growing, and the
	# farmer must not look ruined in between.
	GameState.inventory_changed.connect(_check_relief, CONNECT_DEFERRED)
	GameState.money_changed.connect(_check_relief.unbind(1), CONNECT_DEFERRED)
	GameState.plot_prepared.connect(_on_plot_prepared)
	GameState.crop_planted.connect(_on_crop_planted)
	GameState.crop_harvested.connect(_on_crop_harvested)
	GameState.produce_sold.connect(_on_produce_sold)
	GameState.money_changed.connect(_on_money_changed)
	Economy.ownership_changed.connect(_on_ownership_changed)
	GameState.day_changed.connect(_on_day_changed)
	# `day_changed` also fires when the state is merely refreshed (load, reset);
	# the storm only follows days that really pass.
	GameState.day_advanced.connect(_on_day_advanced)
	cyclone.call("set_active", false)
	Campaign.task_status_changed.connect(_on_task_status_changed)
	_refresh_objective()
	_restore_world(SaveGame.register_world(2, save_world))
	GameState.announce("Map 2 — Le cultivateur : préparez la terre, cultivez, vendez au marché.")
	_check_relief()
	if GameState.day >= PROSPERITY_DEADLINE_DAY:
		_check_prosperity_deadline(GameState.day)


func _exit_tree() -> void:
	SaveGame.unregister_world(2)


## What the farm needs to come back as it was left: every plot and the farmer.
func save_world() -> Dictionary:
	var plots := {}
	for node: Node in get_tree().get_nodes_in_group("crops"):
		var plot := node as CropPlot
		if plot != null and is_ancestor_of(plot):
			plots[String(plot.name)] = plot.to_dict()
	return {
		"plots": plots,
		"player": [player.global_position.x, player.global_position.y],
	}


func _restore_world(data: Dictionary) -> void:
	var plots: Variant = data.get("plots", {})
	if plots is Dictionary:
		for node: Node in get_tree().get_nodes_in_group("crops"):
			var plot := node as CropPlot
			var saved: Variant = (plots as Dictionary).get(String(node.name), null)
			if plot != null and is_ancestor_of(plot) and saved is Dictionary:
				plot.from_dict(saved as Dictionary)
	var position_data: Variant = data.get("player", null)
	if position_data is Array and (position_data as Array).size() == 2:
		var point := Vector2(float(position_data[0]), float(position_data[1]))
		if Rect2(Vector2.ZERO, FARM_SIZE).has_point(point):
			player.teleport_to(point)


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
	# A gamepad has no number row: the shoulder buttons walk through the seeds.
	for step: int in [1, -1]:
		if event.is_action_pressed(&"seed_next" if step > 0 else &"seed_previous"):
			var order: Array = GameState.CROP_ORDER
			var index := order.find(GameState.selected_seed)
			GameState.select_seed(order[posmod(index + step, order.size())])
			get_viewport().set_input_as_handled()
			return


func _install_generation_ui() -> void:
	if get_node_or_null("TaskList") == null:
		var task_list: CanvasLayer = TASK_LIST_SCENE.instantiate()
		add_child(task_list)
	if get_node_or_null("GenerationResult") == null:
		var result: CanvasLayer = load("res://scenes/ui/tasks/generation_result.tscn").instantiate()
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


func _on_money_changed(_value: int) -> void:
	_check_prosperity()


func _on_ownership_changed(_asset_id: StringName, _amount: int) -> void:
	_check_prosperity()


## Prosperity is wealth, not cash in hand: investing in a barn or more land
## must not push the goal further away.
func _check_prosperity() -> void:
	if GameState.net_worth() >= PROSPERITY_GOAL \
			and Campaign.task_status("earn_100") == Campaign.TaskStatus.PENDING:
		Campaign.complete_task("earn_100")
		GameState.announce("Objectif atteint : %s de patrimoine — la ferme prospère !"
			% GameState.format_money(PROSPERITY_GOAL))
	_refresh_objective()


func _on_day_changed(day: int) -> void:
	_check_prosperity_deadline(day)
	_refresh_objective()


func _on_day_advanced(day: int) -> void:
	# Warn the day before so the player can harvest ripe crops in time.
	if (day + 1) % CYCLONE_EVERY_DAYS == 0:
		GameState.announce("Un cyclone approche demain — rentrez vos récoltes mûres.")
	if day % CYCLONE_EVERY_DAYS == 0:
		_strike_cyclone()


## While the storm crosses, what it touches is resolved where it is now: a ripe
## crop falls when the funnel reaches it, not at the end of a five-second leg.
func _physics_process(_delta: float) -> void:
	if _striking:
		_destroyed += _destroy_ripe_crops_on_path(
			cyclone.global_position, cyclone.global_position)


func _strike_cyclone() -> void:
	if cyclone == null or _striking:
		return
	_striking = true
	_destroyed = 0
	var sheltered_before := _sheltered
	var path := _cyclone_path(_cyclone_entry_point())
	cyclone.global_position = path[0]
	cyclone.call("set_active", true)
	GameState.announce("Le cyclone traverse la ferme !")
	Audio.play_ambience(&"wind")
	for index in range(1, path.size()):
		var tween := create_tween()
		tween.tween_property(cyclone, "global_position", path[index], cyclone_leg_time)
		await tween.finished
	_striking = false
	cyclone.call("set_active", false)
	Audio.stop_ambience()
	var destroyed := _destroyed
	var sheltered := _sheltered - sheltered_before
	if sheltered > 0:
		GameState.announce(
			"La grange a mis %d récolte(s) mûre(s) à l'abri du cyclone." % sheltered)
	elif destroyed > 0:
		GameState.announce(
			"Le cyclone a détruit %d récolte(s) mûre(s)." % destroyed)
	else:
		GameState.announce("Le cyclone est passé sans toucher les cultures mûres.")
	_check_relief()


## A random point on the border of the travel zone.
func _cyclone_entry_point() -> Vector2:
	var along := randf()
	match randi() % 4:
		0:
			return Vector2(lerpf(cyclone_zone.position.x, cyclone_zone.end.x, along),
				cyclone_zone.position.y)
		1:
			return Vector2(lerpf(cyclone_zone.position.x, cyclone_zone.end.x, along),
				cyclone_zone.end.y)
		2:
			return Vector2(cyclone_zone.position.x,
				lerpf(cyclone_zone.position.y, cyclone_zone.end.y, along))
	return Vector2(cyclone_zone.end.x,
		lerpf(cyclone_zone.position.y, cyclone_zone.end.y, along))


## Builds a slow polyline whose heading changes at every leg, bouncing off the
## sides of `cyclone_zone` so the storm stays over the fields.
func _cyclone_path(from: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([from])
	var pos := from
	var heading := randf() * TAU
	var step_length := cyclone_speed * cyclone_leg_time
	for _leg in cyclone_legs:
		heading = _next_heading(heading)
		var next := pos + Vector2.RIGHT.rotated(heading) * step_length
		var bounced := false
		if next.x < cyclone_zone.position.x or next.x > cyclone_zone.end.x:
			heading = PI - heading
			bounced = true
		if next.y < cyclone_zone.position.y or next.y > cyclone_zone.end.y:
			heading = -heading
			bounced = true
		if bounced:
			next = pos + Vector2.RIGHT.rotated(heading) * step_length
		next.x = clampf(next.x, cyclone_zone.position.x, cyclone_zone.end.x)
		next.y = clampf(next.y, cyclone_zone.position.y, cyclone_zone.end.y)
		points.append(next)
		pos = next
	return points


func _next_heading(heading: float) -> float:
	return heading + deg_to_rad(randf_range(-cyclone_turn_deg, cyclone_turn_deg))


## Destroys every READY crop within `CYCLONE_STEAL_RADIUS` of the storm path,
## or brings it into the barn when the farmer owns one. Returns the number of
## crops lost.
func _destroy_ripe_crops_on_path(from: Vector2, to: Vector2) -> int:
	var destroyed := 0
	var has_barn := Economy.owned_count(BARN_ASSET) > 0
	for node: Node in get_tree().get_nodes_in_group("crops"):
		var plot := node as CropPlot
		if plot == null:
			continue
		if _distance_to_segment(plot.global_position, from, to) > CYCLONE_STEAL_RADIUS:
			continue
		if has_barn:
			if plot.shelter_crop():
				_sheltered += 1
		elif plot.destroy_crop():
			destroyed += 1
	return destroyed


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(from)
	var t := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * t)


func _check_prosperity_deadline(day: int) -> void:
	if day < PROSPERITY_DEADLINE_DAY:
		return
	if Campaign.task_status("earn_100") != Campaign.TaskStatus.PENDING:
		return
	Campaign.fail_task("earn_100",
		"Délai dépassé : %s non atteints avant le jour %d"
			% [GameState.format_money(PROSPERITY_GOAL), PROSPERITY_DEADLINE_DAY])
	GameState.announce("Le délai du marché est passé : la ferme termine la génération en difficulté.")


## True when the farmer can neither plant, harvest, sell nor buy: no seed, no
## produce, nothing in the ground and not enough money for the cheapest seed.
## Without help the remaining tasks could never be resolved.
func is_destitute() -> bool:
	for crop: String in GameState.CROP_ORDER:
		if GameState.seed_count(crop) > 0 or GameState.produce_count(crop) > 0:
			return false
		if GameState.money >= int(GameState.CROPS[crop]["seed_price"]):
			return false
	for node: Node in get_tree().get_nodes_in_group("crops"):
		var plot := node as CropPlot
		if plot != null and (plot.state == CropPlot.State.GROWING
				or plot.state == CropPlot.State.READY):
			return false
	return true


func _check_relief() -> void:
	if not is_destitute():
		_relief_announced = false
		return
	if _relief_announced:
		return
	_relief_announced = true
	GameState.announce("Plus rien à planter ni à vendre : allez voir la Marchande.")
	_refresh_objective()


## What the seller says about today's prices: the crop that pays best compared
## with its usual price.
func market_tip() -> String:
	var best := ""
	var best_ratio := 0.0
	for crop: String in GameState.CROP_ORDER:
		if not GameState.prices.has(crop):
			continue
		var ratio := float(GameState.prices[crop]) / float(GameState.CROPS[crop]["base_price"])
		if ratio > best_ratio:
			best_ratio = ratio
			best = crop
	if best.is_empty():
		return ""
	var label := String(GameState.CROPS[best]["label"]).to_lower()
	var price := GameState.format_money(int(GameState.prices[best]))
	if best_ratio >= 1.0:
		return "Aujourd'hui, c'est le %s qui se vend le mieux : %s pièce." % [label, price]
	return "Les prix sont bas aujourd'hui. Le %s tient encore le mieux : %s pièce." % [label, price]


func _on_seller_talked(speaker: String, _text: String) -> void:
	if not is_destitute():
		return
	GameState.add_seeds(RELIEF_CROP, 1)
	GameState.select_seed(RELIEF_CROP)
	hud.show_dialogue(speaker,
		"Les temps sont durs pour tout le monde. Tenez, une graine de %s : vous me revaudrez ça au marché."
			% String(GameState.CROPS[RELIEF_CROP]["label"]).to_lower())
	_refresh_objective()


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
	if is_destitute():
		return "Objectif : demandez une graine à la Marchande du hameau."
	for definition: Dictionary in Campaign.TASKS[2]:
		var task_id := String(definition.get("id", ""))
		if Campaign.task_status(task_id) == Campaign.TaskStatus.PENDING:
			return "Objectif : %s" % InputHints.format(
				String(definition.get("hint", definition.get("label", ""))))
	return "Objectif : terminez les tâches de la ferme."
