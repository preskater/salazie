extends CharacterBody2D

@onready var ANIMATIONS = $Sprite2D

@export var SPEED = 300.0
@export var KNOCKBACK_DECAY := 900.0 

var knockback := Vector2.ZERO
var control_lock := 0.0

const JUMP_VELOCITY = -400.0
var last_direction := Vector2.DOWN
var wind := Vector2.ZERO

func _physics_process(delta: float) -> void:
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	
	if control_lock > 0.0:
		control_lock -= delta
		velocity = wind + knockback
	else:
		velocity = input_dir * SPEED + wind + knockback
	
	if input_dir.length() > 0:
		last_direction = input_dir
		play_walk_animation(input_dir)
	else:
		play_idle_animation(last_direction)
	
	move_and_slide()
	
	wind = Vector2.ZERO

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

func apply_knockback(v: Vector2) -> void:
	knockback += v

func stun(duration: float) -> void:
	control_lock = maxf(control_lock, duration)

func add_wind(v: Vector2) -> void:
	wind += v
