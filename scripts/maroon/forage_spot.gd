extends Area2D
## A wild food, water or seed pickup. Food is collected on contact; water and
## seeds wait for `interact` so drinking and gathering stay deliberate.
## It can advance a multi-step campaign task and store seed bonuses for Map 2.

signal picked(kind: String, message: String)

@export var texture: Texture2D
@export var tint := Color.WHITE
@export var food_amount := 0.0
@export var water_amount := 0.0
@export var task_id := ""
@export var task_progress := 1
@export var kind := "food"
## Message shown after the pickup. `%d` is replaced by the task progress and
## `%d/%d` by progress and target.
@export var pickup_message := ""
## When false the pickup waits for `interact` instead of body contact.
@export var auto_pickup := true
## When set, the pickup also stores a seed bonus for the next generation.
@export var seed_crop := ""
@export var seed_amount := 1

@onready var sprite: Sprite2D = $Sprite2D

var _used := false


func _ready() -> void:
	if auto_pickup:
		body_entered.connect(_on_body_entered)
	if texture != null:
		sprite.texture = texture
	sprite.modulate = tint
	add_to_group("forage_spots")
	add_to_group("interactable")


func get_interaction_prompt() -> String:
	if _used:
		return ""
	if water_amount > 0.0:
		return InputHints.prompt(&"interact", "Boire")
	if not seed_crop.is_empty():
		return InputHints.prompt(&"interact", "Ramasser des graines")
	return InputHints.prompt(&"interact", "Ramasser")


func interact(player: Node2D) -> void:
	_pick_up(player)


func _on_body_entered(body: Node2D) -> void:
	if not auto_pickup or not body.is_in_group("player"):
		return
	_pick_up(body)


func _pick_up(body: Node2D) -> void:
	if _used:
		return
	_used = true
	var survival := body.get_node_or_null("Survival")
	if survival != null:
		if food_amount > 0.0:
			survival.call("add_food", food_amount)
		if water_amount > 0.0:
			survival.call("add_water", water_amount)
	if not task_id.is_empty():
		Campaign.add_task_progress(task_id, task_progress)
	if not seed_crop.is_empty():
		Campaign.add_bonus_seed(seed_crop, seed_amount)
	picked.emit(kind, _compose_message())
	set_deferred("monitoring", false)
	sprite.visible = false
	_spawn_pop()


func _compose_message() -> String:
	var text := pickup_message
	if text.is_empty():
		if water_amount > 0.0:
			return "Vous buvez."
		if not seed_crop.is_empty():
			return "Graines ramassées."
		return "Vivres trouvés."
	if task_id.is_empty():
		return text
	if text.contains("%d/%d"):
		return text % [Campaign.task_progress(task_id), Campaign.task_target(task_id)]
	if text.contains("%d"):
		return text % Campaign.task_progress(task_id)
	return text


func is_used() -> bool:
	return _used


## Restores a pickup taken before the game was saved: no reward, no message.
func mark_used() -> void:
	_used = true
	set_deferred("monitoring", false)
	sprite.visible = false


func _spawn_pop() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var pop := Sprite2D.new()
	pop.name = "PickupPop"
	pop.texture = sprite.texture
	pop.modulate = sprite.modulate
	pop.offset = sprite.offset
	parent.add_child(pop)
	pop.global_position = global_position
	pop.scale = sprite.scale

	var tween := pop.create_tween().set_parallel(true)
	tween.tween_property(pop, "scale", pop.scale * 1.6, 0.28)
	tween.tween_property(pop, "modulate:a", 0.0, 0.28)
	tween.tween_property(pop, "position:y", pop.position.y - 30.0, 0.28)
	tween.chain().tween_callback(pop.queue_free)
