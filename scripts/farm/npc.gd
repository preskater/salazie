class_name FarmNPC
extends Node2D

signal dialogue_requested(speaker: String, text: String)

@export var speaker := "Habitant"
@export var lines: PackedStringArray = PackedStringArray()
@export var tint := Color.WHITE
@export var talk_prompt := ""
@export var patrol_radius := 18.0
@export var walk_speed := 26.0
@export var sprite_frames: SpriteFrames
@export var sprite_scale := 1.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var player: Node2D

var _home := Vector2.ZERO
var _target := Vector2.ZERO
var _idle_timer := 0.0
var _walking := false
var _facing := "down"
var _anim := ""

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npc")
	sprite.modulate = tint
	if sprite_frames != null:
		sprite.sprite_frames = sprite_frames
		sprite.scale = Vector2(sprite_scale, sprite_scale)
		var frame := sprite.sprite_frames.get_frame_texture(&"idle_down", 0)
		if frame != null:
			sprite.offset = Vector2(0, -frame.get_height() / 2.0)
	_home = position
	_idle_timer = randf_range(2.0, 5.0)
	_play("idle_down")

func _physics_process(delta: float) -> void:
	if player and is_instance_valid(player) \
			and global_position.distance_to(player.global_position) < 96.0:
		_walking = false
		_face_towards(player.global_position - global_position)
		_play("idle_" + _facing)
		return
	if _walking:
		var to := _target - position
		if to.length() <= 2.0:
			_walking = false
			_idle_timer = randf_range(3.0, 6.0)
			_play("idle_" + _facing)
			return
		position += to.normalized() * minf(walk_speed * delta, to.length())
		_play("walk_" + _facing)
		return
	_idle_timer -= delta
	if _idle_timer > 0.0:
		return
	var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if offset.length_squared() < 0.01:
		offset = Vector2.RIGHT
	offset = offset.normalized() * randf_range(6.0, patrol_radius)
	_target = _home + offset
	_walking = true
	_face_towards(offset)
	_play("walk_" + _facing)

func get_interaction_prompt() -> String:
	if not talk_prompt.is_empty():
		return InputHints.format(talk_prompt)
	return InputHints.prompt(&"interact", "Parler à %s" % speaker)

func interact(_player: Node2D) -> void:
	var text := "Bienvenue à Salazie."
	if not lines.is_empty():
		text = lines[randi() % lines.size()]
	dialogue_requested.emit(speaker, text)

func _face_towards(v: Vector2) -> void:
	if absf(v.x) >= absf(v.y):
		_facing = "right" if v.x > 0.0 else "left"
	else:
		_facing = "down" if v.y > 0.0 else "up"

func _play(anim: String) -> void:
	if anim == _anim:
		return
	_anim = anim
	sprite.play(anim)
