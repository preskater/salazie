extends Sprite2D

var _phase := 0.0
var _amplitude := 0.0

func _ready() -> void:
	_phase = randf() * TAU
	_amplitude = deg_to_rad(randf_range(0.8, 1.6))

func _process(delta: float) -> void:
	_phase += delta * 1.4
	rotation = sin(_phase) * _amplitude
