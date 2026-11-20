extends AnimatedSprite2D

func _ready() -> void:
	frame = randi() % sprite_frames.get_frame_count(&"shake")
	speed_scale = randf_range(0.65, 1.25)
	play(&"shake")
