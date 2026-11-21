@tool
class_name FarmAnimal
extends Node2D

const DIRECTIONS := ["right", "up", "left", "down"]

@export var sheet: Texture2D
@export var cell_size := Vector2i(48, 48)
@export var walk_row := 1
@export var graze_row := 3
## Frames per direction in each row. Chicken and rooster sheets only have two
## frames in the eat row, so reading six slices empty cells and the animal
## disappears.
@export var walk_frames := 6
@export var graze_frames := 6
@export var move_speed := 24.0
@export var roam_rect := Rect2()
@export var graze_time := Vector2(2.5, 6.0)
@export var walk_time := Vector2(1.5, 4.0)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

static var _frame_cache := {}

var _state := "graze"
var _timer := 0.0
var _target := Vector2.ZERO
var _facing := "down"
var _anim := ""

func _ready() -> void:
	if sheet:
		sprite.sprite_frames = _frames()
		sprite.offset = Vector2(0, -cell_size.y / 2.0)
		_timer = randf_range(graze_time.x, graze_time.y)
		_play("graze_down")
	set_physics_process(not Engine.is_editor_hint())

func _physics_process(delta: float) -> void:
	if roam_rect.size == Vector2.ZERO:
		return
	_timer -= delta
	if _state == "graze":
		if _timer <= 0.0:
			_pick_target()
		return
	var to := _target - position
	if to.length() <= 4.0 or _timer <= 0.0:
		_start_graze()
		return
	position += to.normalized() * minf(move_speed * delta, to.length())

func _pick_target() -> void:
	_target = Vector2(
		randf_range(roam_rect.position.x + 12.0, roam_rect.end.x - 12.0),
		randf_range(roam_rect.position.y + 12.0, roam_rect.end.y - 12.0))
	_state = "walk"
	_timer = randf_range(walk_time.x, walk_time.y)
	_face(_target - position)
	_play("walk_" + _facing)

func _start_graze() -> void:
	_state = "graze"
	_timer = randf_range(graze_time.x, graze_time.y)
	_play("graze_" + _facing)

func _face(v: Vector2) -> void:
	if absf(v.x) >= absf(v.y):
		_facing = "right" if v.x > 0.0 else "left"
	else:
		_facing = "down" if v.y > 0.0 else "up"

func _play(anim: String) -> void:
	if anim == _anim:
		return
	_anim = anim
	sprite.play(anim)

func _frames() -> SpriteFrames:
	var key := "%s|%d|%d|%d|%d|%d|%d" % [
		sheet.resource_path, cell_size.x, cell_size.y,
		walk_row, graze_row, walk_frames, graze_frames]
	if _frame_cache.has(key):
		return _frame_cache[key]

	var frames := SpriteFrames.new()
	_add_directional_animation(frames, "walk", walk_row, walk_frames, 10.0)
	_add_directional_animation(frames, "graze", graze_row, graze_frames, 5.0)
	frames.remove_animation("default")
	_frame_cache[key] = frames
	return frames


func _add_directional_animation(
		frames: SpriteFrames, prefix: String, row: int, frame_count: int, speed: float) -> void:
	var count := maxi(1, frame_count)
	for d in DIRECTIONS.size():
		var anim := "%s_%s" % [prefix, DIRECTIONS[d]]
		frames.add_animation(anim)
		frames.set_animation_loop(anim, true)
		frames.set_animation_speed(anim, speed)
		for i in count:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(
				(d * count + i) * cell_size.x,
				row * cell_size.y,
				cell_size.x,
				cell_size.y)
			frames.add_frame(anim, atlas)
