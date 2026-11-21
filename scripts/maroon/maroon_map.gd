class_name MaroonMap
extends Node2D
## Map 1 — Le marron. A compact wild cirque built at runtime from the existing
## LimeZu farm/exterior props, with patrols, foraging, hiding and checkpoints.

const MAP_SIZE := Vector2(2880.0, 2160.0)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const GUARD_SCENE := preload("res://scenes/world/ai/guard/guard.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud/hud.tscn")
const TASK_LIST_SCENE := preload("res://scenes/ui/tasks/task_list.tscn")
const RESULT_SCENE := preload("res://scenes/ui/tasks/generation_result.tscn")
const FORAGE_SCENE := preload("res://scenes/maroon/forage_spot.tscn")
const HIDE_SCENE := preload("res://scenes/maroon/hide_spot.tscn")
const CHECKPOINT_SCENE := preload("res://scenes/maroon/checkpoint.tscn")
const MAP_EXIT_SCENE := preload("res://scenes/world/map_exit.tscn")

const TREE_TEXTURES := [
	"res://sprites/farm_48x48/singles/Trees/Tree_Oak_Green_Medium_48x48.png",
	"res://sprites/farm_48x48/singles/Trees/Tree_Pine_Green_Big_48x48.png",
	"res://sprites/farm_48x48/singles/Trees/Tree_Birch_Green_Medium_48x48.png",
]
const ROCK_TEXTURES := [
	"res://sprites/farm_48x48/singles/Props_and_Buildings/Rock_Big_48x48.png",
	"res://sprites/farm_48x48/singles/Props_and_Buildings/Rock_Medium_48x48.png",
]
const FOOD_TEXTURE := "res://sprites/farm_48x48/singles/Crops/Crop_Strawberry_Ripe_48x48.png"
const BUSH_TEXTURE := "res://sprites/exteriors_48x48/singles/3_City_Props/ME_Singles_City_Props_48x48_Flower_Bush_2.png"
const CABIN_TEXTURE := "res://sprites/farm_48x48/singles/Props_and_Buildings/Farmer_House_1_48x48.png"
const SIGN_TEXTURE := "res://sprites/farm_48x48/singles/Props_and_Buildings/Sign_1_48x48.png"

const SPAWN := Vector2(360.0, 1900.0)
const UPPER_CHECKPOINT := Vector2(1560.0, 520.0)
const REFUGE := Vector2(2520.0, 300.0)
const WATER_TOP := 1020.0
const WATER_HEIGHT := 180.0
const BRIDGE_LEFT := 1280.0
const BRIDGE_RIGHT := 1480.0

var _world: Node2D
var _player: Node2D
var _notification_label: Label
var _notification_timer: Timer
var _respawn_overlay: ColorRect
var _respawn_position := SPAWN
var _respawning := false
var _guards: Array[Dictionary] = []
var _blocked_points: Array[Dictionary] = []


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
	Campaign.map_resolved.connect(_on_map_resolved)
	Campaign.task_status_changed.connect(_on_task_status_changed)
	_notify("Map 1 — Le marron : survivez, cachez-vous et rejoignez le refuge.")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.16, 0.36, 0.20))
	# Dense forest floor.
	draw_rect(Rect2(0, 0, MAP_SIZE.x, 460), Color(0.10, 0.27, 0.15))
	draw_rect(Rect2(0, 0, 430, MAP_SIZE.y), Color(0.11, 0.29, 0.16))
	draw_rect(Rect2(MAP_SIZE.x - 480, 0, 480, MAP_SIZE.y), Color(0.11, 0.29, 0.16))
	# Winding path from the camp to the bridge and the refuge.
	draw_rect(Rect2(300, 1880, 1250, 70), Color(0.42, 0.32, 0.20))
	draw_rect(Rect2(1320, 560, 80, 1500), Color(0.42, 0.32, 0.20))
	draw_rect(Rect2(1360, 250, 1160, 80), Color(0.42, 0.32, 0.20))
	# River and bridge.
	draw_rect(Rect2(0, WATER_TOP, MAP_SIZE.x, WATER_HEIGHT), Color(0.16, 0.40, 0.62))
	draw_rect(Rect2(0, WATER_TOP, MAP_SIZE.x, 16), Color(0.30, 0.58, 0.78))
	draw_rect(Rect2(BRIDGE_LEFT, WATER_TOP - 16, BRIDGE_RIGHT - BRIDGE_LEFT, WATER_HEIGHT + 32),
		Color(0.46, 0.32, 0.20))
	for i in 6:
		draw_rect(Rect2(BRIDGE_LEFT + 8 + i * 30, WATER_TOP - 8, 12, WATER_HEIGHT + 16),
			Color(0.58, 0.42, 0.27))
	# Patrol clearing.
	draw_rect(Rect2(760, 570, 1260, 430), Color(0.20, 0.36, 0.20))
	# Refuge clearing.
	draw_circle(REFUGE + Vector2(0, 40), 190.0, Color(0.28, 0.42, 0.22))


func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	add_child(_world)

	_blocked_points.append({"point": SPAWN, "radius": 260.0})
	_blocked_points.append({"point": UPPER_CHECKPOINT, "radius": 180.0})
	_blocked_points.append({"point": REFUGE, "radius": 260.0})
	_blocked_points.append({"point": Vector2(1360, 1120), "radius": 120.0})
	for point: Vector2 in [
		Vector2(560, 1650), Vector2(980, 1480), Vector2(2140, 1580), Vector2(2320, 1880),
		Vector2(1120, 980), Vector2(1720, 980), Vector2(560, 780),
	]:
		_blocked_points.append({"point": point, "radius": 100.0})

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121
	var placed := 0
	var attempts := 0
	while placed < 88 and attempts < 900:
		attempts += 1
		var point := Vector2(
			rng.randf_range(90.0, MAP_SIZE.x - 90.0),
			rng.randf_range(90.0, MAP_SIZE.y - 90.0))
		if not _can_place(point):
			continue
		var texture_path: String = TREE_TEXTURES[rng.randi_range(0, TREE_TEXTURES.size() - 1)]
		_add_prop(texture_path, point, rng.randf_range(0.85, 1.3), Vector2(44, 26))
		placed += 1
	for i in 26:
		var point := Vector2(
			rng.randf_range(80.0, MAP_SIZE.x - 80.0),
			rng.randf_range(80.0, MAP_SIZE.y - 80.0))
		if not _can_place(point):
			continue
		var rock_path: String = ROCK_TEXTURES[i % ROCK_TEXTURES.size()]
		_add_prop(rock_path, point, rng.randf_range(0.8, 1.25), Vector2(54, 30))

	# Water blocks movement except on the bridge.
	_add_rect_body(Rect2(0, WATER_TOP, BRIDGE_LEFT, WATER_HEIGHT))
	_add_rect_body(Rect2(BRIDGE_RIGHT, WATER_TOP, MAP_SIZE.x - BRIDGE_RIGHT, WATER_HEIGHT))


func _add_bounds() -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	add_child(bounds)
	_add_shape(bounds, Rect2(-32, 0, 64, MAP_SIZE.y))
	_add_shape(bounds, Rect2(MAP_SIZE.x - 32, 0, 64, MAP_SIZE.y))
	_add_shape(bounds, Rect2(0, -32, MAP_SIZE.x, 64))
	_add_shape(bounds, Rect2(0, MAP_SIZE.y - 32, MAP_SIZE.x, 64))


func _add_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	_player.name = "Player"
	_player.position = SPAWN
	_player.set("camera_limits", Rect2i(0, 0, int(MAP_SIZE.x), int(MAP_SIZE.y)))
	_world.add_child(_player)
	var survival := _player.get_node_or_null("Survival")
	if survival != null:
		survival.set("food_drain", 0.35)
		survival.set("water_drain", 0.55)
	_blocked_points.append({"point": SPAWN, "radius": 220.0})


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

	var hint := Label.new()
	hint.name = "ControlsHint"
	hint.text = "Déplacez-vous : WASD · Courir : Maj · Tâches : T"
	hint.position = Vector2(18, MAP_SIZE.y - 42)
	hint.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	hint.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	hint.add_theme_constant_override("outline_size", 6)
	add_child(hint)

	_notification_label = Label.new()
	_notification_label.name = "Notification"
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.position = Vector2(240, MAP_SIZE.y - 92)
	_notification_label.size = Vector2(MAP_SIZE.x - 480, 44)
	_notification_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.66))
	_notification_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_notification_label.add_theme_constant_override("outline_size", 7)
	_notification_label.add_theme_font_size_override("font_size", 22)
	add_child(_notification_label)

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


func _add_guards() -> void:
	var positions := [
		Vector2(900, 850), Vector2(1250, 700), Vector2(1600, 820),
		Vector2(1920, 920), Vector2(1450, 1000),
	]
	for i in positions.size():
		var spawn: Vector2 = positions[i]
		var guard: CharacterBody2D = GUARD_SCENE.instantiate()
		guard.name = "Guard%d" % (i + 1)
		guard.position = spawn
		guard.set("zone_size", Vector2(430, 300))
		guard.set("vision_range", 330.0)
		guard.set("use_navigation", false)
		guard.set("pause_on_catch", false)
		_world.add_child(guard)
		guard.caught.connect(_on_caught.bind(guard))
		var sprite := guard.get_node_or_null("Sprite") as AnimatedSprite2D
		if sprite != null:
			sprite.modulate = Color(0.92, 0.62, 0.55)
		_guards.append({"guard": guard, "spawn": spawn})
		_blocked_points.append({"point": spawn, "radius": 120.0})


func _add_forage_and_water() -> void:
	var food_texture: Texture2D = load(FOOD_TEXTURE)
	var spots := [
		Vector2(560, 1650), Vector2(980, 1480), Vector2(2140, 1580), Vector2(2320, 1880),
	]
	for point: Vector2 in spots:
		_spawn_forage(point, food_texture, 28.0, 0.0, "find_food", 1, Color(1.0, 0.9, 0.75))
		_blocked_points.append({"point": point, "radius": 90.0})
	_spawn_forage(Vector2(1360, 1120), food_texture, 0.0, 60.0,
		"find_water", 1, Color(0.55, 0.78, 1.0))
	_blocked_points.append({"point": Vector2(1360, 1120), "radius": 90.0})


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
	var bush: Texture2D = load(BUSH_TEXTURE)
	var spots := [Vector2(1120, 980), Vector2(1720, 980), Vector2(560, 780)]
	for point: Vector2 in spots:
		var spot: Area2D = HIDE_SCENE.instantiate()
		spot.name = "Hide_%d_%d" % [int(point.x), int(point.y)]
		spot.position = point
		spot.set("texture", bush)
		spot.set("tint", Color(0.65, 0.95, 0.55))
		spot.hidden_completed.connect(_on_hidden_completed)
		_world.add_child(spot)
		_blocked_points.append({"point": point, "radius": 90.0})


func _add_checkpoints() -> void:
	var start: Area2D = CHECKPOINT_SCENE.instantiate()
	start.name = "StartCheckpoint"
	start.position = SPAWN
	start.set("checkpoint_name", "Camp")
	start.reached.connect(_on_checkpoint_reached)
	_world.add_child(start)

	var upper: Area2D = CHECKPOINT_SCENE.instantiate()
	upper.name = "UpperCheckpoint"
	upper.position = UPPER_CHECKPOINT
	upper.set("task_id", "cross_patrol")
	upper.set("checkpoint_name", "Passage nord")
	upper.reached.connect(_on_checkpoint_reached)
	_world.add_child(upper)
	_add_sign(UPPER_CHECKPOINT + Vector2(0, -40), "Checkpoint")


func _add_refuge() -> void:
	var cabin := Sprite2D.new()
	cabin.name = "RefugeCabin"
	cabin.texture = load(CABIN_TEXTURE)
	cabin.position = REFUGE + Vector2(0, -30)
	cabin.scale = Vector2(1.4, 1.4)
	_world.add_child(cabin)
	_add_rect_body(Rect2(REFUGE.x - 70, REFUGE.y - 10, 140, 60))

	var exit: Area2D = MAP_EXIT_SCENE.instantiate()
	exit.name = "RefugeExit"
	exit.position = REFUGE
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
	_add_sign(REFUGE + Vector2(0, -180), "Refuge")


func _add_sign(point: Vector2, text: String) -> void:
	var sign_sprite := Sprite2D.new()
	sign_sprite.texture = load(SIGN_TEXTURE)
	sign_sprite.position = point
	sign_sprite.scale = Vector2(1.3, 1.3)
	_world.add_child(sign_sprite)
	var label := Label.new()
	label.text = text
	label.position = point + Vector2(-60, -44)
	label.add_theme_color_override("font_color", Color(0.96, 0.88, 0.68))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	label.add_theme_constant_override("outline_size", 6)
	_world.add_child(label)


func _add_prop(texture_path: String, point: Vector2, prop_scale: float, collision: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(texture_path)
	sprite.position = point
	sprite.scale = Vector2(prop_scale, prop_scale)
	_world.add_child(sprite)
	if collision != Vector2.ZERO:
		var body := StaticBody2D.new()
		body.position = point
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = collision
		shape.shape = rect
		shape.position = Vector2(0, 26)
		body.add_child(shape)
		_world.add_child(body)


func _add_rect_body(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	add_child(body)
	_add_shape(body, rect)


func _add_shape(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect.size
	shape.shape = rect_shape
	shape.position = rect.position + rect.size * 0.5
	body.add_child(shape)


func _can_place(point: Vector2) -> bool:
	if point.y > WATER_TOP - 60.0 and point.y < WATER_TOP + WATER_HEIGHT + 60.0:
		return false
	if point.x > BRIDGE_LEFT - 80.0 and point.x < BRIDGE_RIGHT + 80.0 \
			and point.y > WATER_TOP - 80.0 and point.y < WATER_TOP + WATER_HEIGHT + 80.0:
		return false
	if point.distance_to(REFUGE) < 260.0:
		return false
	if Rect2(760, 570, 1260, 430).has_point(point):
		return false
	for path_rect: Rect2 in [
		Rect2(300, 1880, 1250, 70),
		Rect2(1320, 560, 80, 1500),
		Rect2(1360, 250, 1160, 80),
	]:
		if path_rect.grow(40.0).has_point(point):
			return false
	for entry: Dictionary in _blocked_points:
		if point.distance_to(entry["point"]) < float(entry["radius"]):
			return false
	return true


func _on_forage_picked(kind: String) -> void:
	if kind == "water":
		_notify("Vous buvez à la rivière.")
	else:
		_notify("Nourriture trouvée (%d/3)." % Campaign.task_progress("find_food"))


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
	_notify("Map 1 résolue — rejoignez le refuge au nord-est.")


func _on_caught(_guard: CharacterBody2D) -> void:
	if _respawning:
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
