extends CharacterBody2D

@export var speed := 220.0
@export var camera_limits := Rect2i(0, 0, 2304, 1632)
@export var camera_zoom := 1.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D

var facing := "down"

func _ready() -> void:
	camera.limit_left = camera_limits.position.x
	camera.limit_top = camera_limits.position.y
	camera.limit_right = camera_limits.end.x
	camera.limit_bottom = camera_limits.end.y
	camera.zoom = Vector2(camera_zoom, camera_zoom)
	sprite.play("idle_" + facing)

func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * speed
	move_and_slide()

	if input.length() > 0.01:
		facing = _direction(input)
		if sprite.animation != "walk_" + facing:
			sprite.play("walk_" + facing)
	elif sprite.animation != "idle_" + facing:
		sprite.play("idle_" + facing)

func _direction(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0.0 else "left"
	return "down" if v.y > 0.0 else "up"
