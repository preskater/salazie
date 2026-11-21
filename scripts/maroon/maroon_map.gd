class_name MaroonMap
extends Node2D
## Map 1 — Le marron. The player escapes from the sea, follows the river
## upstream through the forest and the gorge, and reaches the mountain refuge.
## The static world is built by `maroon_layout.gd`; this script owns gameplay,
## tasks, UI and respawns.

signal climb_finished

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const GUARD_SCENE := preload("res://scenes/world/ai/guard/guard.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud/hud.tscn")
const TASK_LIST_SCENE := preload("res://scenes/ui/tasks/task_list.tscn")
const RESULT_SCENE := preload("res://scenes/ui/tasks/generation_result.tscn")
const FORAGE_SCENE := preload("res://scenes/maroon/forage_spot.tscn")
const HIDE_SCENE := preload("res://scenes/maroon/hide_spot.tscn")
const CHECKPOINT_SCENE := preload("res://scenes/maroon/checkpoint.tscn")
const CLIMB_SCENE := preload("res://scenes/maroon/climb_point.tscn")
const STEALTH_SCENE := preload("res://scenes/maroon/stealth_zone.tscn")
const MAP_EXIT_SCENE := preload("res://scenes/world/map_exit.tscn")
const LAYOUT := preload("res://scripts/maroon/maroon_layout.gd")

const FOOD_TEXTURES := [
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Brown_Shell_1_Vers_1.png",
	"res://sprites/farm_48x48/singles/Crops/Crop_Berry_Ripe_48x48.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Mushrooms_1.png",
	"res://sprites/farm_48x48/singles/Crops/Crop_Berry_Small_Basket_48x48.png",
]
const HIDE_TEXTURES := [
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_1.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_3.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_5.png",
]
## A gourd of river water is worth one sip, and the volcanic silt needs ten
## seconds to settle before the next one.
const DRINK_WATER := 10.0
const DRINK_COOLDOWN := 0.0
const DRINK_REACH_TILES := 2
const WATERFALL_TASK_RADIUS := 12.0 * 48.0

var _terrain: Node2D
var _world: Node2D
var _player: Node2D
var _layout: RefCounted
var _anchors: Dictionary
var _map_size := Vector2.ZERO
var _water_layer: TileMapLayer
var _notification_label: Label
var _prompt_label: Label
var _hint_label: Label
var _objective_bar: Node2D
var _objective_arrow: Node2D
var _objective_label: Label
var _notification_timer: Timer
var _respawn_overlay: ColorRect
var _respawn_position := Vector2.ZERO
var _respawning := false
var _climbing := false
var _target: Node = null
var _near_fresh_water := false
var _drink_cooldown := 0.0
var _food_spots: Array[Area2D] = []
var _hide_spots: Array[Area2D] = []
var _guards: Array[Dictionary] = []


func _ready() -> void:
	if not SceneRouter.is_gameplay:
		SceneRouter.is_gameplay = true
	if not GameState.playing:
		GameState.playing = true
	GameState.farm_active = false
	Campaign.ensure_map(1)
	Campaign.current_map = 1
	DayNightCycle.nights_required_for_next_map = 0
	DayNightCycle.running = true
	DayNightCycle.tint_enabled = true
	_build_world()
	_add_bounds()
	_add_player()
	_add_ui()
	_add_guards()
	_add_forage()
	_add_hide_spots()
	_add_climb_points()
	_add_stealth_zones()
	_add_checkpoints()
	_add_refuge()
	_build_navigation()
	Campaign.map_resolved.connect(_on_map_resolved)
	Campaign.task_status_changed.connect(_on_task_status_changed)
	_notify("Map 1 — Le marron : de la mer au col, remontez la rivière et rejoignez le refuge.")


func map_size() -> Vector2:
	return _map_size


func _build_world() -> void:
	_terrain = Node2D.new()
	_terrain.name = "Terrain"
	add_child(_terrain)
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	add_child(_world)
	_layout = LAYOUT.new()
	_anchors = _layout.build(_terrain, _world)
	_map_size = _anchors["size"]
	_respawn_position = _anchors["spawn"]
	_water_layer = _terrain.get_node("Water") as TileMapLayer


func _build_navigation() -> void:
	var region := NavigationRegion2D.new()
	region.name = "Navigation"
	add_child(region)

	var polygon := NavigationPolygon.new()
	polygon.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	polygon.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	polygon.source_geometry_group_name = &"navigation_obstacles"
	polygon.agent_radius = 20.0
	polygon.cell_size = float(
		ProjectSettings.get_setting("navigation/2d/default_cell_size", 1.0))
	polygon.add_outline(PackedVector2Array([
		Vector2(24.0, 24.0),
		Vector2(_map_size.x - 24.0, 24.0),
		Vector2(_map_size.x - 24.0, _map_size.y - 24.0),
		Vector2(24.0, _map_size.y - 24.0),
	]))
	region.navigation_polygon = polygon

	# StaticBody shapes must be registered before the source geometry is parsed.
	await get_tree().physics_frame
	region.bake_navigation_polygon()


func _add_bounds() -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	add_child(bounds)
	_add_shape(bounds, Rect2(-32, 0, 64, _map_size.y))
	_add_shape(bounds, Rect2(_map_size.x - 32, 0, 64, _map_size.y))
	_add_shape(bounds, Rect2(0, -32, _map_size.x, 64))
	_add_shape(bounds, Rect2(0, _map_size.y - 32, _map_size.x, 64))


func _add_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	_player.name = "Player"
	_player.position = _anchors["spawn"]
	_player.set("camera_limits", Rect2i(0, 0, int(_map_size.x), int(_map_size.y)))
	_world.add_child(_player)
	var survival := _player.get_node_or_null("Survival")
	if survival != null:
		survival.set("food_drain", 0.35)
		survival.set("water_drain", 0.55)


func _add_ui() -> void:
	var hud: CanvasLayer = HUD_SCENE.instantiate()
	hud.name = "SurvivalHUD"
	add_child(hud)
	var tasks: CanvasLayer = TASK_LIST_SCENE.instantiate()
	tasks.name = "TaskList"
	add_child(tasks)
	var result: CanvasLayer = RESULT_SCENE.instantiate()
	result.name = "GenerationResult"
	add_child(result)

	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 5
	add_child(overlay)

	_hint_label = Label.new()
	_hint_label.name = "ControlsHint"
	_hint_label.text = "WASD · Maj courir · E grimper · T tâches"
	_hint_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_hint_label.add_theme_constant_override("outline_size", 6)
	overlay.add_child(_hint_label)

	_notification_label = Label.new()
	_notification_label.name = "Notification"
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.66))
	_notification_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_notification_label.add_theme_constant_override("outline_size", 7)
	_notification_label.add_theme_font_size_override("font_size", 22)
	overlay.add_child(_notification_label)

	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.74))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.add_theme_font_size_override("font_size", 19)
	overlay.add_child(_prompt_label)

	_objective_bar = Node2D.new()
	_objective_bar.name = "ObjectiveBar"
	overlay.add_child(_objective_bar)

	_objective_arrow = Node2D.new()
	_objective_arrow.name = "Arrow"
	_objective_bar.add_child(_objective_arrow)
	var arrow_outline := Polygon2D.new()
	arrow_outline.polygon = PackedVector2Array([
		Vector2(-13, -11), Vector2(13, 0), Vector2(-13, 11)])
	arrow_outline.color = Color(0.08, 0.06, 0.04, 0.9)
	_objective_arrow.add_child(arrow_outline)
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([
		Vector2(-10, -8), Vector2(10, 0), Vector2(-10, 8)])
	arrow.color = Color(0.98, 0.84, 0.35)
	_objective_arrow.add_child(arrow)

	_objective_label = Label.new()
	_objective_label.name = "ObjectiveLabel"
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.position = Vector2(-300, 14)
	_objective_label.size = Vector2(600, 30)
	_objective_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.62))
	_objective_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_objective_label.add_theme_constant_override("outline_size", 6)
	_objective_label.add_theme_font_size_override("font_size", 20)
	_objective_bar.add_child(_objective_label)

	_notification_timer = Timer.new()
	_notification_timer.one_shot = true
	_notification_timer.wait_time = 4.0
	_notification_timer.timeout.connect(_hide_notification)
	overlay.add_child(_notification_timer)

	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()

	var respawn_layer := CanvasLayer.new()
	respawn_layer.name = "RespawnFade"
	respawn_layer.layer = 60
	add_child(respawn_layer)
	_respawn_overlay = ColorRect.new()
	_respawn_overlay.color = Color(0.02, 0.02, 0.03, 0.0)
	_respawn_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_respawn_overlay.visible = false
	_respawn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	respawn_layer.add_child(_respawn_overlay)


func _layout_hud() -> void:
	var screen := get_viewport_rect().size
	_hint_label.position = Vector2(18, screen.y - 42)
	_notification_label.position = Vector2(240, screen.y - 92)
	_notification_label.size = Vector2(screen.x - 480, 44)
	_prompt_label.position = Vector2(240, screen.y - 144)
	_prompt_label.size = Vector2(screen.x - 480, 40)
	_objective_bar.position = Vector2(screen.x * 0.5, 26)


func _process(delta: float) -> void:
	_drink_cooldown = maxf(0.0, _drink_cooldown - delta)
	_update_objective_bar()
	if _respawning or _climbing:
		return
	_near_fresh_water = _is_near_fresh_water()
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
	elif _near_fresh_water:
		if _drink_cooldown > 0.0:
			_set_prompt("L'eau se décante — %d s" % ceili(_drink_cooldown))
		else:
			_set_prompt("E — Boire (+10 eau)")
	else:
		_set_prompt("")


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or _respawning or _climbing:
		return
	if event.is_action_pressed("interact"):
		if _target != null and _target.has_method("interact"):
			_target.call("interact", _player)
			get_viewport().set_input_as_handled()
		elif _near_fresh_water:
			_drink()
			get_viewport().set_input_as_handled()


func _is_near_fresh_water() -> bool:
	if _water_layer == null or _player == null:
		return false
	var center := _water_layer.local_to_map(
		_water_layer.to_local(_player.global_position))
	for y in range(center.y - DRINK_REACH_TILES, center.y + DRINK_REACH_TILES + 1):
		for x in range(center.x - DRINK_REACH_TILES, center.x + DRINK_REACH_TILES + 1):
			if y >= LAYOUT.SEA_ROW:
				continue
			if _water_layer.get_cell_source_id(Vector2i(x, y)) != -1:
				return true
	return false


func _drink() -> void:
	if _drink_cooldown > 0.0:
		_notify("L'eau est encore trouble : laissez la vase se déposer (%d s)." % ceili(_drink_cooldown))
		return
	var survival := _player.get_node_or_null("Survival")
	if survival != null:
		survival.call("add_water", DRINK_WATER)
	_drink_cooldown = DRINK_COOLDOWN
	if _player.global_position.distance_to(_anchors["water_spot"]) <= WATERFALL_TASK_RADIUS:
		Campaign.complete_task("find_water")
		_notify("Vous buvez au bassin (+10 eau). La vase doit se décanter.")
	else:
		_notify("Vous buvez à la rivière (+10 eau). La vase doit se décanter.")


func _update_objective_bar() -> void:
	if _objective_bar == null or _player == null:
		return
	var task := _current_task()
	if task.is_empty():
		_objective_bar.visible = false
		return
	var task_id := String(task["id"])
	var target: Vector2 = _objective_target(task_id)
	if target == Vector2.ZERO:
		_objective_bar.visible = false
		return
	_objective_bar.visible = true
	var offset := target - _player.global_position
	_objective_arrow.rotation = offset.angle()
	var text := "Objectif : %s" % String(task["label"])
	if task_id == "find_food":
		text += " (%d/3)" % Campaign.task_progress("find_food")
	text += " — %d m" % maxi(0, roundi(offset.length() / 48.0))
	if _objective_label.text != text:
		_objective_label.text = text


func _current_task() -> Dictionary:
	for definition: Dictionary in Campaign.TASKS[1]:
		if Campaign.task_status(String(definition["id"])) != Campaign.TaskStatus.DONE:
			return definition
	return {}


func _objective_target(task_id: String) -> Vector2:
	match task_id:
		"follow_river":
			var mouth: Vector2 = _anchors["river_mouth_checkpoint"]
			return mouth
		"find_water":
			var water: Vector2 = _anchors["water_spot"]
			return water
		"find_food":
			return _nearest_spot(_food_spots)
		"hide_from_patrol":
			return _nearest_spot(_hide_spots)
		"cross_patrol":
			var upper: Vector2 = _anchors["upper_checkpoint"]
			return upper
		"reach_refuge":
			var refuge: Vector2 = _anchors["refuge"]
			return refuge
	return Vector2.ZERO


func _nearest_spot(spots: Array[Area2D]) -> Vector2:
	var best := Vector2.ZERO
	var best_distance := INF
	for spot: Area2D in spots:
		if not is_instance_valid(spot):
			continue
		if spot.has_method("is_used") and bool(spot.call("is_used")):
			continue
		var distance := _player.global_position.distance_squared_to(spot.global_position)
		if distance < best_distance:
			best_distance = distance
			best = spot.global_position
	return best


func _set_prompt(text: String) -> void:
	if _prompt_label == null:
		return
	_prompt_label.text = text
	_prompt_label.visible = not text.is_empty()


func _add_guards() -> void:
	var positions: Array = _anchors["guards"]
	for index in positions.size():
		var spawn: Vector2 = positions[index]
		var guard: CharacterBody2D = GUARD_SCENE.instantiate()
		guard.name = "Guard%d" % (index + 1)
		guard.position = spawn
		guard.set("zone_size", Vector2(360, 260))
		guard.set("vision_range", 300.0)
		guard.set("use_navigation", true)
		guard.set("pause_on_catch", false)
		_world.add_child(guard)
		guard.caught.connect(_on_caught.bind(guard))
		var sprite := guard.get_node_or_null("Sprite") as AnimatedSprite2D
		if sprite != null:
			sprite.modulate = Color(0.92, 0.62, 0.55)
		_guards.append({"guard": guard, "spawn": spawn})


func _add_forage() -> void:
	var food_points: Array = _anchors["food_spots"]
	for index in food_points.size():
		var texture: Texture2D = load(FOOD_TEXTURES[index % FOOD_TEXTURES.size()])
		_food_spots.append(_spawn_forage(food_points[index], texture, 28.0, 0.0,
			"find_food", 1, Color(1.0, 0.9, 0.75)))


func _spawn_forage(point: Vector2, texture: Texture2D, food: float, water: float,
		task_id: String, progress: int, tint: Color) -> Area2D:
	var spot: Area2D = FORAGE_SCENE.instantiate()
	spot.name = "Forage_%d_%d" % [int(point.x), int(point.y)]
	spot.position = point
	spot.set("texture", texture)
	spot.set("food_amount", food)
	spot.set("water_amount", water)
	spot.set("task_id", task_id)
	spot.set("task_progress", progress)
	spot.set("tint", tint)
	spot.set("kind", "water" if water > 0.0 else "food")
	spot.picked.connect(_on_forage_picked)
	_world.add_child(spot)
	return spot


func _add_hide_spots() -> void:
	var points: Array = _anchors["hide_spots"]
	for index in points.size():
		var spot: Area2D = HIDE_SCENE.instantiate()
		spot.name = "Hide_%d_%d" % [int(points[index].x), int(points[index].y)]
		spot.position = points[index]
		spot.set("texture", load(HIDE_TEXTURES[index % HIDE_TEXTURES.size()]))
		spot.set("tint", Color(0.72, 0.95, 0.70))
		spot.hidden_completed.connect(_on_hidden_completed)
		_world.add_child(spot)
		_hide_spots.append(spot)


func _add_climb_points() -> void:
	var climb_points: Array = _anchors["climb_points"]
	for spec: Dictionary in climb_points:
		var point: Area2D = CLIMB_SCENE.instantiate()
		point.name = "Climb_%d_%d" % [int(spec["position"].x), int(spec["position"].y)]
		point.position = spec["position"]
		point.set("label", spec["label"])
		point.set("destination", spec["destination"])
		point.climb_requested.connect(_on_climb_requested)
		_world.add_child(point)


func _add_stealth_zones() -> void:
	var stealth_zones: Array = _anchors["stealth_zones"]
	for spec: Dictionary in stealth_zones:
		var zone: Area2D = STEALTH_SCENE.instantiate()
		zone.name = "Stealth_%d_%d" % [int(spec["position"].x), int(spec["position"].y)]
		zone.position = spec["position"]
		zone.set("zone_name", spec["name"])
		zone.set("conceal_player", spec["conceal"])
		zone.set("mute_noise", spec["mute"])
		var collision := zone.get_node("CollisionShape2D") as CollisionShape2D
		var rectangle := collision.shape.duplicate() as RectangleShape2D
		rectangle.size = spec["size"]
		collision.shape = rectangle
		zone.entered.connect(_on_stealth_entered.bind(spec))
		zone.exited.connect(_on_stealth_exited.bind(spec))
		_world.add_child(zone)


func _add_checkpoints() -> void:
	var start: Area2D = CHECKPOINT_SCENE.instantiate()
	start.name = "StartCheckpoint"
	start.position = _anchors["spawn"]
	start.set("checkpoint_name", "Plage")
	start.reached.connect(_on_checkpoint_reached)
	_world.add_child(start)

	var mouth: Area2D = CHECKPOINT_SCENE.instantiate()
	mouth.name = "RiverMouthCheckpoint"
	mouth.position = _anchors["river_mouth_checkpoint"]
	mouth.set("task_id", "follow_river")
	mouth.set("checkpoint_name", "Embouchure")
	mouth.reached.connect(_on_checkpoint_reached)
	_world.add_child(mouth)

	var forest: Area2D = CHECKPOINT_SCENE.instantiate()
	forest.name = "ForestCheckpoint"
	forest.position = _anchors["forest_checkpoint"]
	forest.set("checkpoint_name", "Camp forestier")
	forest.reached.connect(_on_checkpoint_reached)
	_world.add_child(forest)

	var upper: Area2D = CHECKPOINT_SCENE.instantiate()
	upper.name = "UpperCheckpoint"
	upper.position = _anchors["upper_checkpoint"]
	upper.set("task_id", "cross_patrol")
	upper.set("checkpoint_name", "Passage nord")
	upper.reached.connect(_on_checkpoint_reached)
	_world.add_child(upper)


func _add_refuge() -> void:
	var exit: Area2D = MAP_EXIT_SCENE.instantiate()
	exit.name = "RefugeExit"
	exit.position = _anchors["refuge"]
	exit.next_scene_path = SceneRouter.FARM_SCENE
	exit.title = "Le cultivateur"
	exit.subtitle = "Deuxième génération"
	exit.requires_map_ready = false
	exit.requires_map_complete = true
	exit.complete_task_on_enter = "reach_refuge"
	exit.show_result = true
	var shape := (exit.get_node("CollisionShape2D") as CollisionShape2D).shape.duplicate()
	shape.size = Vector2(150, 150)
	(exit.get_node("CollisionShape2D") as CollisionShape2D).shape = shape
	exit.blocked.connect(_on_refuge_blocked)
	add_child(exit)


func _add_shape(body: StaticBody2D, rect: Rect2) -> void:
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	collision.shape = rectangle
	collision.position = rect.position + rect.size * 0.5
	body.add_child(collision)


func _on_forage_picked(_kind: String) -> void:
	_notify("Vivres trouvés (%d/3)." % Campaign.task_progress("find_food"))


func _on_hidden_completed() -> void:
	_notify("La patrouille est passée sans vous voir.")


func _on_climb_requested(destination: Vector2) -> void:
	if _climbing or _respawning:
		return
	_climbing = true
	_set_prompt("")
	await _fade_respawn(1.0)
	_player.global_position = destination
	await get_tree().physics_frame
	await _fade_respawn(0.0)
	_climbing = false
	climb_finished.emit()


func _on_stealth_entered(zone_name: String, spec: Dictionary) -> void:
	if bool(spec["conceal"]):
		_notify("Vous vous fondez dans %s." % zone_name)
	else:
		_notify("Le grondement de %s couvre vos pas." % zone_name)


func _on_stealth_exited(zone_name: String, _spec: Dictionary) -> void:
	_notify("Vous quittez %s." % zone_name)


func _on_checkpoint_reached(point: Vector2) -> void:
	_respawn_position = point
	_notify("Checkpoint atteint.")


func _on_refuge_blocked() -> void:
	_notify("Le refuge est proche, mais des tâches restent à accomplir.")


func _on_task_status_changed(_map_id: int, _task_id: String, _status: int) -> void:
	if Campaign.is_map_resolved():
		_notify("Toutes les tâches sont résolues — le refuge est ouvert.")


func _on_map_resolved(_map_id: int, _summary: Dictionary) -> void:
	_notify("Map 1 résolue — rejoignez la cabane du col.")


func _on_caught(_guard: CharacterBody2D) -> void:
	if _respawning or _climbing:
		return
	_respawning = true
	var was_hidden := bool(_player.get("concealed"))
	if Campaign.task_status("cross_patrol") == Campaign.TaskStatus.PENDING:
		Campaign.fail_task("cross_patrol", "Repéré par une patrouille")
	if not was_hidden and Campaign.task_status("hide_from_patrol") == Campaign.TaskStatus.PENDING:
		Campaign.fail_task("hide_from_patrol", "Repéré avant d'avoir pu se cacher")
	_player.call("stun", 1.0)
	await _fade_respawn(1.0)
	_player.global_position = _respawn_position
	_player.call("set_hidden", false)
	var survival := _player.get_node_or_null("Survival")
	if survival != null:
		survival.call("add_food", 20.0)
		survival.call("add_water", 20.0)
	for entry: Dictionary in _guards:
		var other: CharacterBody2D = entry["guard"]
		if is_instance_valid(other):
			other.call("reset_after_catch", entry["spawn"])
	Campaign.retry_task("cross_patrol")
	Campaign.retry_task("hide_from_patrol")
	_notify("Repéré ! Retour au dernier checkpoint.")
	await _fade_respawn(0.0)
	_respawning = false


func _fade_respawn(alpha: float) -> void:
	if _respawn_overlay == null:
		return
	_respawn_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(_respawn_overlay, "color:a", alpha, 0.22)
	await tween.finished
	if alpha <= 0.001:
		_respawn_overlay.visible = false


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
