class_name ShakeCamera2D
extends Camera2D
## Trauma-based camera shake. The intensity is `trauma * trauma`, it decays in
## real time and the base offset is restored when it stops, so the view never
## drifts. Samples summed sines instead of random per-frame values, which would
## buzz like static.

@export var decay := 2.2
@export var max_offset := Vector2(10.0, 8.0)
@export var max_roll := 0.02

var trauma := 0.0

var _base_offset := Vector2.ZERO
var _base_rotation := 0.0


func _ready() -> void:
	_base_offset = offset
	_base_rotation = rotation
	# Camera2D ignores its own rotation by default: without this the roll is
	# computed and never seen.
	ignore_rotation = false
	Settings.settings_changed.connect(_on_settings_changed)


## Turning the comfort option on stops a shake already running.
func _on_settings_changed() -> void:
	if Settings.reduced_shake:
		trauma = 0.0


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if trauma <= 0.0:
		if offset != _base_offset or rotation != _base_rotation:
			offset = _base_offset
			rotation = _base_rotation
		return

	trauma = maxf(0.0, trauma - decay * delta)
	var amount := trauma * trauma * Settings.shake_share()
	var t := Time.get_ticks_msec() * 0.001
	offset = _base_offset + Vector2(sin(t * 47.0), cos(t * 53.0)) * max_offset * amount
	rotation = _base_rotation + sin(t * 31.0) * max_roll * amount
