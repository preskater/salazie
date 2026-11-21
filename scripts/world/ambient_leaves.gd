extends AnimatedSprite2D

func _ready() -> void:
	if sprite_frames == null or not sprite_frames.has_animation(&"fall"):
		return
	frame = randi() % sprite_frames.get_frame_count(&"fall")
	speed_scale = randf_range(0.7, 1.3)
	play(&"fall")
