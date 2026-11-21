class_name HeirMap
extends Node2D
## Map 3 — L'héritier. A modern valley where the player listens, assesses the
## fragile sites, chooses a plan and faces the final council vote.

const MAP_SIZE := Vector2(2400.0, 1800.0)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const TASK_LIST_SCENE := preload("res://scenes/ui/tasks/task_list.tscn")
const RESULT_SCENE := preload("res://scenes/ui/tasks/generation_result.tscn")
const DIALOGUE_SCENE := preload("res://scenes/ui/dialogue/dialogue_box.tscn")
const DECISION_SCENE := preload("res://scenes/ui/decision/decision_panel.tscn")
const FRAGILE_SCENE := preload("res://scenes/heir/fragile_site.tscn")
const DECISION_POINT_SCENE := preload("res://scenes/heir/decision_point.tscn")
const TOWN_HALL_SCENE := preload("res://scenes/heir/town_hall.tscn")
const NPC_SCENE := preload("res://scenes/farm/npc.tscn")

const TOWN_HALL_TEXTURE := "res://sprites/exteriors_48x48/singles/22_Post_Office/22_Post_Office_48x48_Building_1.png"
const HOUSE_TEXTURES := [
	"res://sprites/exteriors_48x48/singles/24_Additional_Houses/24_Additional_Houses_Modern_House_Unadorned_48x48.png",
	"res://sprites/exteriors_48x48/singles/24_Additional_Houses/24_Additional_Houses_Terraced_House_1_48x48.png",
	"res://sprites/exteriors_48x48/singles/24_Additional_Houses/24_Additional_Houses_Victorian_House_1_48x48.png",
]
const BUSH_TEXTURE := "res://sprites/exteriors_48x48/singles/3_City_Props/ME_Singles_City_Props_48x48_Flower_Bush_4.png"
const TREE_TEXTURE := "res://sprites/farm_48x48/singles/Trees/Tree_Oak_Green_Medium_48x48.png"

const SPAWN := Vector2(1200.0, 1600.0)
const TOWN_HALL_POINT := Vector2(1200.0, 700.0)
const DECISION_POINT := Vector2(1200.0, 1050.0)

var _world: Node2D
var _player: Node2D
var _dialogue: DialogueBox
var _decision_panel: DecisionPanel
var _notification_label: Label
var _prompt_label: Label
var _notification_timer: Timer
var _target: Node = null


func _ready() -> void:
	if not SceneRouter.is_gameplay:
		SceneRouter.is_gameplay = true
	if not GameState.playing:
		GameState.playing = true
	GameState.farm_active = false
	Campaign.ensure_map(3)
	Campaign.current_map = 3
	Campaign.heritage = Campaign.heritage_for_map3() if Campaign.heritage <= 0 else Campaign.heritage
	DayNightCycle.nights_required_for_next_map = 0
	DayNightCycle.running = true
	DayNightCycle.tint_enabled = true
	_build_world()
	_add_bounds()
	_add_player()
	_add_ui()
	_add_buildings()
	_add_npcs()
	_add_fragile_sites()
	_add_decision_and_town_hall()
	_notify("Map 3 — L'héritier : écoutez, évaluez et décidez de l'avenir de Salazie.")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.27, 0.34, 0.27))
	# River on the west edge.
	draw_rect(Rect2(0, 0, 250, MAP_SIZE.y), Color(0.16, 0.40, 0.62))
	draw_rect(Rect2(226, 0, 24, MAP_SIZE.y), Color(0.30, 0.58, 0.78))
	# Roads and the central square.
	draw_rect(Rect2(0, 780, MAP_SIZE.x, 150), Color(0.46, 0.44, 0.40))
	draw_rect(Rect2(1120, 0, 160, MAP_SIZE.y), Color(0.46, 0.44, 0.40))
	draw_rect(Rect2(880, 720, 640, 330), Color(0.55, 0.52, 0.46))
	draw_rect(Rect2(300, 150, 720, 520), Color(0.20, 0.38, 0.23))
	draw_rect(Rect2(1500, 150, 700, 520), Color(0.20, 0.38, 0.23))
	# Town hall forecourt.
	draw_rect(Rect2(980, 520, 440, 190), Color(0.58, 0.54, 0.46))


func _add_bounds() -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	add_child(bounds)
	_add_shape(bounds, Rect2(-32, 0, 64, MAP_SIZE.y))
	_add_shape(bounds, Rect2(MAP_SIZE.x - 32, 0, 64, MAP_SIZE.y))
	_add_shape(bounds, Rect2(0, -32, MAP_SIZE.x, 64))
	_add_shape(bounds, Rect2(0, MAP_SIZE.y - 32, MAP_SIZE.x, 64))


func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	add_child(_world)


func _add_player() -> void:
	_player = PLAYER_SCENE.instantiate()
	_player.name = "Player"
	_player.position = SPAWN
	_player.set("camera_limits", Rect2i(0, 0, int(MAP_SIZE.x), int(MAP_SIZE.y)))
	_world.add_child(_player)
	var survival := _player.get_node_or_null("Survival")
	if survival != null:
		survival.set("active", false)


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

	var heritage := Label.new()
	heritage.name = "HeritageLabel"
	heritage.text = "Héritage familial : %d G" % Campaign.heritage
	heritage.position = Vector2(22, 18)
	heritage.add_theme_color_override("font_color", Color(0.95, 0.90, 0.78))
	heritage.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	heritage.add_theme_constant_override("outline_size", 6)
	heritage.add_theme_font_size_override("font_size", 20)
	add_child(heritage)

	var hint := Label.new()
	hint.text = "Déplacez-vous : WASD · Interagir : E · Tâches : T"
	hint.position = Vector2(18, MAP_SIZE.y - 42)
	hint.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	hint.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	hint.add_theme_constant_override("outline_size", 6)
	add_child(hint)

	_notification_label = Label.new()
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

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(240, MAP_SIZE.y - 144)
	_prompt_label.size = Vector2(MAP_SIZE.x - 480, 40)
	_prompt_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.74))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.add_theme_font_size_override("font_size", 19)
	add_child(_prompt_label)


func _add_buildings() -> void:
	_add_building(TOWN_HALL_TEXTURE, Vector2(1200, 260), 1.2, Vector2(220, 60))
	_add_label(Vector2(1090, 70), "Mairie")
	var house_positions := [
		Vector2(400, 300), Vector2(2080, 320), Vector2(340, 1280), Vector2(2000, 1280),
	]
	for i in house_positions.size():
		var texture_path: String = HOUSE_TEXTURES[i % HOUSE_TEXTURES.size()]
		_add_building(texture_path, house_positions[i], 0.7, Vector2(150, 50))
	# Park trees and bushes.
	for point: Vector2 in [
		Vector2(500, 250), Vector2(720, 420), Vector2(900, 260),
		Vector2(1650, 300), Vector2(1880, 420), Vector2(2040, 240),
		Vector2(620, 600), Vector2(1800, 620),
	]:
		_add_prop(TREE_TEXTURE, point, 1.1, Vector2(46, 26))
	for point: Vector2 in [
		Vector2(860, 640), Vector2(1520, 640), Vector2(960, 1120), Vector2(1500, 1120),
	]:
		_add_prop(BUSH_TEXTURE, point, 1.0, Vector2.ZERO)


func _add_npcs() -> void:
	var npcs := [
		{"id": "payet", "speaker": "Mme Payet", "pos": Vector2(820, 900),
			"tint": Color(0.95, 0.82, 0.92),
			"lines": ["La rivière monte chaque année un peu plus.", "Les jeunes partent, mais ils reviennent quand le marché vit."]},
		{"id": "pecheur", "speaker": "Le pêcheur", "pos": Vector2(330, 760),
			"tint": Color(0.76, 0.88, 0.96),
			"lines": ["Il y a vingt ans, on voyait le fond de l'eau depuis la berge.", "Les crevettes ont presque disparu du bras nord."]},
		{"id": "marchande", "speaker": "La marchande", "pos": Vector2(1520, 920),
			"tint": Color(0.98, 0.86, 0.70),
			"lines": ["Le marché inonde dès qu'il pleut fort.", "Si les fermes tiennent, le village tient."]},
		{"id": "instituteur", "speaker": "L'instituteur", "pos": Vector2(1020, 620),
			"tint": Color(0.80, 0.92, 0.80),
			"lines": ["Les enfants apprennent Salazie dans les livres, pas dans la forêt.", "Il faudrait les emmener sur les sentiers."]},
		{"id": "garde", "speaker": "Le garde forestier", "pos": Vector2(1900, 720),
			"tint": Color(0.86, 0.78, 0.64),
			"lines": ["La forêt du cirque n'a jamais été aussi fragile.", "Une coupe mal placée et c'est toute la pente qui glisse."]},
	]
	for data: Dictionary in npcs:
		var npc: Node2D = NPC_SCENE.instantiate()
		npc.name = "NPC_%s" % String(data["id"])
		npc.position = data["pos"]
		npc.set("speaker", data["speaker"])
		npc.set("lines", PackedStringArray(data["lines"]))
		npc.set("tint", data["tint"])
		npc.set("player", _player)
		_world.add_child(npc)
		npc.dialogue_requested.connect(_on_npc_dialogue.bind(String(data["id"])))


func _add_fragile_sites() -> void:
	var sites := [
		{"id": "berge", "title": "La berge érodée", "pos": Vector2(300, 680),
			"texture": BUSH_TEXTURE, "tint": Color(0.65, 0.82, 1.0),
			"text": "La rivière ronge la berge. Sans végétation, le sol part avec chaque crue."},
		{"id": "foret", "title": "La forêt fragilisée", "pos": Vector2(2040, 520),
			"texture": TREE_TEXTURE, "tint": Color(0.80, 0.72, 0.52),
			"text": "Des arbres malades laissent la pente à nu. La prochaine pluie emportera la terre."},
		{"id": "marche", "title": "Le marché inondable", "pos": Vector2(1360, 1180),
			"texture": BUSH_TEXTURE, "tint": Color(0.72, 0.80, 0.92),
			"text": "Les étals sont installés dans le lit ancien de la rivière. Chaque orage les noie."},
	]
	for data: Dictionary in sites:
		var site: Area2D = FRAGILE_SCENE.instantiate()
		site.name = "Site_%s" % String(data["id"])
		site.position = data["pos"]
		site.set("site_id", data["id"])
		site.set("title", data["title"])
		site.set("description", data["text"])
		site.set("texture", load(String(data["texture"])))
		site.set("tint", data["tint"])
		site.inspected.connect(_on_site_inspected)
		_world.add_child(site)
		_add_label(data["pos"] + Vector2(-70, -54), String(data["title"]))


func _add_decision_and_town_hall() -> void:
	var point: Area2D = DECISION_POINT_SCENE.instantiate()
	point.name = "DecisionPoint"
	point.position = DECISION_POINT
	point.requested.connect(_on_decision_requested)
	_world.add_child(point)
	_add_label(DECISION_POINT + Vector2(-70, -54), "Conseil du village")

	var hall: Area2D = TOWN_HALL_SCENE.instantiate()
	hall.name = "TownHall"
	hall.position = TOWN_HALL_POINT
	hall.requested.connect(_on_town_hall_requested)
	_world.add_child(hall)


func _add_building(texture_path: String, point: Vector2, prop_scale: float, collision: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(texture_path)
	sprite.position = point
	sprite.scale = Vector2(prop_scale, prop_scale)
	_world.add_child(sprite)
	var body := StaticBody2D.new()
	body.position = point
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = collision
	shape.shape = rect
	shape.position = Vector2(0, sprite.texture.get_height() * prop_scale * 0.5 - collision.y * 0.5)
	body.add_child(shape)
	_world.add_child(body)


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
		shape.position = Vector2(0, sprite.texture.get_height() * prop_scale * 0.5 - collision.y * 0.5)
		body.add_child(shape)
		_world.add_child(body)


func _add_label(point: Vector2, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_color_override("font_color", Color(0.96, 0.90, 0.76))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	label.add_theme_constant_override("outline_size", 6)
	_world.add_child(label)


func _add_shape(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect.size
	shape.shape = rect_shape
	shape.position = rect.position + rect.size * 0.5
	body.add_child(shape)


func _process(_delta: float) -> void:
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
	if get_tree().paused:
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
		_notify("Vous écoutez %s (%d/3)." % [speaker, Campaign.task_progress("listen")])


func _on_site_inspected(site_id: String, title: String, description: String) -> void:
	_dialogue.show_line(title, description)
	if Campaign.get_choice("assessed_" + site_id) != "1":
		Campaign.set_choice("assessed_" + site_id, "1")
		Campaign.add_task_progress("assess", 1)
		_notify("Zone évaluée : %s (%d/3)." % [title, Campaign.task_progress("assess")])


func _on_decision_requested() -> void:
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
	if Campaign.task_status("choose_plan") != Campaign.TaskStatus.DONE:
		_notify("Choisissez d'abord un plan au conseil du village.")
		return
	if Campaign.task_status("listen") != Campaign.TaskStatus.DONE \
			or Campaign.task_status("assess") != Campaign.TaskStatus.DONE:
		_notify("Le conseil veut savoir ce que vous avez appris du terrain.")
		return
	var support := Campaign.mayor_support()
	if Campaign.has_mayor_support():
		Campaign.complete_task("become_mayor")
		_dialogue.show_line("Le conseil", "Votre plan est adopté. Salazie vous confie son avenir.")
	else:
		Campaign.fail_task("become_mayor",
			"Le conseil a rejeté votre plan (soutien %d/6)" % support)
		_dialogue.show_line("Le conseil", "Votre plan est refusé. Le village se divisera, mais la vallée continuera.")
	await _show_result_and_end()


func _show_result_and_end() -> void:
	var overlay := get_tree().get_first_node_in_group("generation_result") as GenerationResult
	if overlay != null:
		overlay.show_result(Campaign.map_summary(), "Épilogue de Salazie",
			"Héritage familial : %d G" % Campaign.heritage)
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
