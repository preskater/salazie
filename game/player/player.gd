extends CharacterBody2D

@onready var ANIMATIONS = $Sprite2D

const SPEED = 300.0
const JUMP_VELOCITY = -400.0
var last_direction := Vector2.DOWN

func _physics_process(delta: float) -> void:
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	velocity = direction * SPEED * delta

	if direction.length() > 0:
		last_direction = direction
		play_walk_animation(direction)
	else:
		play_idle_animation(last_direction)

	move_and_slide()

func play_walk_animation(direction):
	if direction.x  > 0:
		ANIMATIONS.play("walk_right")
	elif direction.x < 0:
		ANIMATIONS.play("walk_left")
	elif  direction.y > 0:
		ANIMATIONS.play("walk_down")
	elif direction.y < 0:
		ANIMATIONS.play("walk_up")

func play_idle_animation(direction):
	if direction.x  > 0:
		ANIMATIONS.play("idle_right")
	elif direction.x < 0:
		ANIMATIONS.play("idle_left")
	elif  direction.y > 0:
		ANIMATIONS.play("idle_down")
	elif direction.y < 0:
		ANIMATIONS.play("idle_up")
