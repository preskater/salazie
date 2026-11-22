extends Area2D
## A leafy hide spot. The player is concealed while inside; after a short delay
## the hide task is completed. Leaving early cancels the attempt.

signal hidden_completed()
signal hidden_cancelled()

@export var texture: Texture2D
@export var tint := Color.WHITE
@export var required_time := 1.5

@onready var sprite: Sprite2D = $Sprite2D
@onready var ring: Sprite2D = $Ring
@onready var label: Label = $HiddenLabel

var _player: Node2D
var _inside := false
var _completed := false
var _timer := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if texture != null:
		sprite.texture = texture
	sprite.modulate = tint
	ring.visible = false
	label.visible = false
	add_to_group("hide_spots")


func _process(delta: float) -> void:
	if not _inside or _completed or _player == null or not is_instance_valid(_player):
		return
	_timer += delta
	if _timer >= required_time:
		_completed = true
		label.text = "Caché !"
		hidden_completed.emit()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player = body
	_inside = true
	_timer = 0.0
	label.text = "Caché"
	ring.visible = true
	label.visible = true
	body.call("add_cover", self)


func _on_body_exited(body: Node2D) -> void:
	if body != _player:
		return
	_inside = false
	ring.visible = false
	label.visible = false
	# Only this bush stops covering: a cave around it still does.
	body.call("remove_cover", self)
	if not _completed:
		_timer = 0.0
		hidden_cancelled.emit()


func is_hidden_inside() -> bool:
	return _inside
