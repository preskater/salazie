extends Node2D
## Village shuttle. The map controller drives it between the two stops.

const SPEED := 800.0

@onready var sprite: AnimatedSprite2D = $Sprite

var _moving := false
var _bob := 0.0


func _ready() -> void:
	_apply_direction("up")


func drive_to(point: Vector2) -> void:
	var delta := point - position
	var direction := "up"
	if absf(delta.x) > absf(delta.y):
		direction = "right" if delta.x > 0.0 else "left"
	else:
		direction = "down" if delta.y > 0.0 else "up"
	_apply_direction(direction)
	_moving = true
	var duration := maxf(0.35, position.distance_to(point) / SPEED)
	var tween := create_tween()
	tween.tween_property(self, "position", point, duration)
	await tween.finished
	_moving = false
	sprite.position.y = 0.0


func _process(delta: float) -> void:
	if not _moving:
		return
	_bob += delta
	sprite.position.y = sin(_bob * 22.0) * 1.5


func _apply_direction(direction: String) -> void:
	sprite.animation = StringName("bus_" + direction)
	sprite.play()
	var frame := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	if frame != null:
		sprite.offset = Vector2(0, -frame.get_height() / 2.0)
