extends Area2D
## A wild food or water pickup. It restores the player's survival bars and can
## advance a multi-step campaign task on first contact.

signal picked(kind: String)

@export var texture: Texture2D
@export var tint := Color.WHITE
@export var food_amount := 0.0
@export var water_amount := 0.0
@export var task_id := ""
@export var task_progress := 1
@export var kind := "food"

@onready var sprite: Sprite2D = $Sprite2D

var _used := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if texture != null:
		sprite.texture = texture
	sprite.modulate = tint
	add_to_group("forage_spots")


func _on_body_entered(body: Node2D) -> void:
	if _used or not body.is_in_group("player"):
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
	picked.emit(kind)
	set_deferred("monitoring", false)
	sprite.visible = false
	_spawn_pop()


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


func is_used() -> bool:
	return _used
