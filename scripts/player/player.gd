extends CharacterBody2D

@onready var ANIMATIONS = $Sprite2D
@onready var camera: Camera2D = $Camera2D

@export var SPEED = 300.0
@export var KNOCKBACK_DECAY := 900.0 
@export var camera_zoom := 1.0
@export var camera_limits := Rect2i()      # vide = pas de limite
@export var sprite_scale := 1.0      # 1 = monde 16px, 3 = monde 48px

@export_group("Footsteps")
@export var STEP_INTERVAL := 0.34
@export var RUN_STEP_INTERVAL := 0.22

@export_group("Running")
@export var RUN_MULTIPLIER := 1.7
@export var RUN_NOISE_RADIUS := 260.0
@export var NOISE_INTERVAL := 0.3

var knockback := Vector2.ZERO
var control_lock := 0.0

var last_direction := Vector2.DOWN
var wind := Vector2.ZERO
var is_running := false
var concealed := false
var noise_muted := false
## Multiplies walking and running speed; an exhausted survivor drags along.
var speed_scale := 1.0

var _noise_timer := 0.0
var _step_timer := 0.0
## Everything that currently conceals the player or masks their steps. Several
## sources overlap (a bush inside a cave), so each one is counted on its own.
var _cover_sources: Dictionary = {}
var _quiet_sources: Dictionary = {}

func _ready() -> void:
	add_to_group("player")
	ANIMATIONS.scale = Vector2.ONE * sprite_scale
	ANIMATIONS.position = Vector2(0, -16.0 * sprite_scale)
	camera.position = Vector2(0, -16.0 * sprite_scale)
	
	camera.zoom = Vector2.ONE * camera_zoom
	if camera_limits.size != Vector2i.ZERO:
		camera.limit_left   = camera_limits.position.x
		camera.limit_top    = camera_limits.position.y
		camera.limit_right  = camera_limits.end.x
		camera.limit_bottom = camera_limits.end.y

func _physics_process(delta: float) -> void:
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	knockback = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)

	is_running = control_lock <= 0.0 and input_dir != Vector2.ZERO and Input.is_action_pressed("run")
	
	if control_lock > 0.0:
		control_lock -= delta
		velocity = wind + knockback
	else:
		velocity = input_dir * get_current_speed() + wind + knockback
	
	if input_dir.length() > 0:
		last_direction = input_dir
		play_walk_animation(input_dir)
	else:
		play_idle_animation(last_direction)
	
	move_and_slide()
	
	wind = Vector2.ZERO
	_tick_noise(delta)
	_tick_steps(delta, control_lock <= 0.0 and input_dir != Vector2.ZERO)

func get_current_speed() -> float:
	return SPEED * (RUN_MULTIPLIER if is_running else 1.0) * speed_scale

func _tick_noise(delta: float) -> void:
	if not is_running:
		_noise_timer = 0.0
		return
	_noise_timer -= delta
	if _noise_timer <= 0.0:
		_noise_timer = NOISE_INTERVAL
		emit_noise()

## One footstep per stride while the player walks under their own control.
func _tick_steps(delta: float, walking: bool) -> void:
	if not walking:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = RUN_STEP_INTERVAL if is_running else STEP_INTERVAL
		Audio.play_sfx(&"step", -14.0 if not is_running else -9.0, 0.12)


## Tells every guard in range that the player is being noisy.
func emit_noise() -> void:
	if noise_muted:
		return
	get_tree().call_group("guards", "hear_noise", global_position, RUN_NOISE_RADIUS)

## Direct switch, counted as one more source next to the zones.
func set_noise_muted(value: bool) -> void:
	_set_source(_quiet_sources, self, value)


## A zone starts or stops masking the player's steps.
func add_quiet(source: Object) -> void:
	_set_source(_quiet_sources, source, true)


func remove_quiet(source: Object) -> void:
	_set_source(_quiet_sources, source, false)


## A hide spot or a stealth zone starts or stops concealing the player.
func add_cover(source: Object) -> void:
	_set_source(_cover_sources, source, true)


func remove_cover(source: Object) -> void:
	_set_source(_cover_sources, source, false)


func _set_source(sources: Dictionary, source: Object, active: bool) -> void:
	if active:
		sources[source.get_instance_id()] = true
	else:
		sources.erase(source.get_instance_id())
	# A zone freed with the player inside can never say it stopped covering.
	for id: int in sources.keys():
		if not is_instance_id_valid(id):
			sources.erase(id)
	noise_muted = not _quiet_sources.is_empty()
	concealed = not _cover_sources.is_empty()
	if ANIMATIONS != null:
		ANIMATIONS.modulate.a = 0.55 if concealed else 1.0

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


## Direct switch, counted as one more source next to the hide spots and zones.
## Guards ignore a concealed player unless the player makes noise or stands
## almost on top of them.
func set_hidden(value: bool) -> void:
	_set_source(_cover_sources, self, value)
