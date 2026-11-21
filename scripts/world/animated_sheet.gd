extends AnimatedSprite2D
## Plays a row of a sprite sheet without authoring one SpriteFrames resource per
## effect. Used by Map 1 for seagulls, boats, buoys, fish, campfires and mist.
##
## The sheet is sliced into `frame_count` frames of `cell_size`, starting at
## `row` and column 0. One animation named `play` is generated.

@export var sheet: Texture2D
@export var cell_size := Vector2i(48, 48)
@export var row := 0
@export var frame_count := 1
@export var columns := 0
@export var fps := 8.0
@export var loop := true
@export var random_start := false
@export var bottom_anchor := true


func _ready() -> void:
	if sheet != null and sprite_frames == null:
		sprite_frames = _build_frames()
	if sprite_frames == null or sprite_frames.get_animation_names().is_empty():
		return
	if bottom_anchor:
		offset = Vector2(0, -cell_size.y / 2.0)
	play(&"play")
	if random_start and frame_count > 1:
		frame = randi() % mini(frame_count, sprite_frames.get_frame_count(&"play"))


func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	var count := maxi(1, frame_count)
	var column_count := columns if columns > 0 else count
	frames.add_animation(&"play")
	frames.set_animation_loop(&"play", loop)
	frames.set_animation_speed(&"play", fps)
	for index in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(
			(index % column_count) * cell_size.x,
			(row + index / column_count) * cell_size.y,
			cell_size.x, cell_size.y)
		frames.add_frame(&"play", atlas)
	frames.remove_animation(&"default")
	return frames
