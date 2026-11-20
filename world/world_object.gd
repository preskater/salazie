@tool
extends StaticBody2D

@export var sprite_texture: Texture2D:
	set(value):
		sprite_texture = value
		_refresh()

@export var collision_size := Vector2(48, 24):
	set(value):
		collision_size = value
		_refresh()

@export var hframes := 1:
	set(value):
		hframes = maxi(1, value)
		_refresh()

@export var vframes := 1:
	set(value):
		vframes = maxi(1, value)
		_refresh()

@export var frame := 0:
	set(value):
		frame = value
		_refresh()

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	if not is_node_ready():
		return
	var sprite: Sprite2D = $Sprite
	sprite.texture = sprite_texture
	if sprite_texture:
		sprite.hframes = hframes
		sprite.vframes = vframes
		sprite.frame = frame
		var frame_size: Vector2 = sprite_texture.get_size() / Vector2(hframes, vframes)
		sprite.offset = Vector2(0, -frame_size.y / 2.0)
	var shape := RectangleShape2D.new()
	shape.size = collision_size
	var collider: CollisionShape2D = $CollisionShape2D
	collider.shape = shape
	collider.position = Vector2(0, -collision_size.y / 2.0)
