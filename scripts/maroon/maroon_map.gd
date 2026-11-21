class_name MaroonMap
extends Node2D
## Map 1 — Le marron. The player escapes from the sea, follows the river
## upstream through the forest and the gorge, and reaches the mountain refuge.
## The static world is built by `maroon_layout.gd`; this script owns gameplay,
## tasks, UI and respawns.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const GUARD_SCENE := preload("res://scenes/world/ai/guard/guard.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud/hud.tscn")
const TASK_LIST_SCENE := preload("res://scenes/ui/tasks/task_list.tscn")
const RESULT_SCENE := preload("res://scenes/ui/tasks/generation_result.tscn")
const FORAGE_SCENE := preload("res://scenes/maroon/forage_spot.tscn")
const HIDE_SCENE := preload("res://scenes/maroon/hide_spot.tscn")
const CHECKPOINT_SCENE := preload("res://scenes/maroon/checkpoint.tscn")
const MAP_EXIT_SCENE := preload("res://scenes/world/map_exit.tscn")
const LAYOUT := preload("res://scripts/maroon/maroon_layout.gd")

const FOOD_TEXTURES := [
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Brown_Shell_1_Vers_1.png",
	"res://sprites/farm_48x48/singles/Crops/Crop_Berry_Ripe_48x48.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Mushrooms_1.png",
	"res://sprites/farm_48x48/singles/Crops/Crop_Berry_Small_Basket_48x48.png",
]
const WATER_TEXTURE := "res://sprites/exteriors_48x48/singles/1_Terrains_and_Fences/ME_Singles_Terrains_and_Fences_48x48_Props_Water_1.png"
const HIDE_TEXTURES := [
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_1.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_3.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_5.png",
]

var _terrain: Node2D
var _world: Node2D
var _player: Node2D
var _layout: RefCounted
var _anchors: Dictionary
var _map_size := Vector2.ZERO
var _notification_label: Label
var _notification_timer: Timer
var _clock_label: Label
var _clock_timer := 0.0
var _respawn_overlay: ColorRect
var _respawn_position := Vector2.ZERO
var _respawning := false
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
	_add_forage_and_water()
	_add_hide_spots()
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

	# Screen-space UI: a CanvasLayer keeps it fixed while the camera scrolls.
	var ui := CanvasLayer.new()
	ui.name = "MaroonUI"
	ui.layer = 9
	add_child(ui)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var hint := Label.new()
	hint.name = "ControlsHint"
	hint.text = "Déplacez-vous : WASD · Courir : Maj · Tâches : T"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 18.0
	hint.offset_top = -44.0
	hint.offset_right = 640.0
	hint.offset_bottom = -14.0
	hint.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	hint.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	hint.add_theme_constant_override("outline_size", 6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)

	_clock_label = Label.new()
	_clock_label.name = "ClockLabel"
	_clock_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clock_label.offset_left = -280.0
	_clock_label.offset_top = 14.0
	_clock_label.offset_right = -18.0
	_clock_label.offset_bottom = 42.0
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	_clock_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_clock_label.add_theme_constant_override("outline_size", 5)
	_clock_label.add_theme_font_size_override("font_size", 16)
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_clock_label)
	_update_clock()

	_notification_label = Label.new()
	_notification_label.name = "Notification"
	_notification_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_notification_label.offset_left = 240.0
	_notification_label.offset_top = -96.0
	_notification_label.offset_right = -240.0
	_notification_label.offset_bottom = -52.0
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.66))
	_notification_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_notification_label.add_theme_constant_override("outline_size", 7)
	_notification_label.add_theme_font_size_override("font_size", 22)
	_notification_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_notification_label)

	_notification_timer = Timer.new()
	_notification_timer.one_shot = true
	_notification_timer.wait_time = 4.0
	_notification_timer.timeout.connect(_hide_notification)
	add_child(_notification_timer)

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


func _process(delta: float) -> void:
	if _clock_label == null:
		return
	_clock_timer -= delta
	if _clock_timer > 0.0:
		return
	_clock_timer = 0.5
	_update_clock()


func _update_clock() -> void:
	if _clock_label == null:
		return
	var seconds := int(ceil(DayNightCycle.seconds_until_next_phase()))
	var phase := "jour" if DayNightCycle.phase == DayNightCycle.Phase.DAY else "nuit"
	_clock_label.text = "Jour %d · %s %d:%02d" % [
		DayNightCycle.day_number, phase, seconds / 60, seconds % 60]


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


func _add_forage_and_water() -> void:
	var food_points: Array = _anchors["food_spots"]
	for index in food_points.size():
		var texture: Texture2D = load(FOOD_TEXTURES[index % FOOD_TEXTURES.size()])
		_spawn_forage(food_points[index], texture, 28.0, 0.0,
			"find_food", 1, Color(1.0, 0.9, 0.75))
	var water_texture: Texture2D = load(WATER_TEXTURE)
	_spawn_forage(_anchors["water_spot"], water_texture, 0.0, 60.0,
		"find_water", 1, Color(0.55, 0.78, 1.0))
	_spawn_forage(_anchors["extra_water"], water_texture, 0.0, 40.0,
		"", 1, Color(0.55, 0.78, 1.0))


func _spawn_forage(point: Vector2, texture: Texture2D, food: float, water: float,
		task_id: String, progress: int, tint: Color) -> void:
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


func _on_forage_picked(kind: String) -> void:
	if kind == "water":
		_notify("Vous buvez au bassin de la cascade.")
	else:
		_notify("Vivres trouvés (%d/3)." % Campaign.task_progress("find_food"))


func _on_hidden_completed() -> void:
	_notify("La patrouille est passée sans vous voir.")


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
	if _respawning:
		return
	_respawning = true
	_shake_camera(0.75)
	await _flash_damage()
	var was_hidden := bool(_player.get("concealed"))
	if Campaign.task_status("cross_patrol") == Campaign.TaskStatus.PENDING:
		Campaign.fail_task("cross_patrol", "Repéré par une patrouille")
	if not was_hidden and Campaign.task_status("hide_from_patrol") == Campaign.TaskStatus.PENDING:
		Campaign.fail_task("hide_from_patrol", "Repéré avant d'avoir pu se cacher")
	_player.call("stun", 1.0)
	if _respawn_overlay != null:
		_respawn_overlay.color = Color(0.02, 0.02, 0.03, 0.0)
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


func _shake_camera(amount: float) -> void:
	var camera := _player.get_node_or_null("Camera2D")
	if camera != null and camera.has_method("add_trauma"):
		camera.call("add_trauma", amount)


func _flash_damage() -> void:
	if _respawn_overlay == null:
		return
	_respawn_overlay.color = Color(0.55, 0.05, 0.05, 0.0)
	_respawn_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(_respawn_overlay, "color:a", 0.5, 0.08)
	tween.tween_property(_respawn_overlay, "color:a", 0.0, 0.2)
	await tween.finished
	_respawn_overlay.visible = false


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
