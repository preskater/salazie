extends Node2D
## A storm funnel: it pulls bodies towards its eye, swirls them and throws them
## out. Whoever owns it decides when it is `active`; an idle cyclone is hidden
## and pulls nothing.

signal body_ejected(body: Node2D)

@onready var field: Area2D = $Area2D
@export_range(0.2, 3.0, 0.05) var falloff_power := 0.7

@export_group("Pull")
@export var pull_radius := 70.0        # reach of the wind
@export var pull_speed := 380.0        # px/s towards the eye, at most
@export var swirl_speed := 300.0       # px/s along the tangent
@export var spin := 1.0                # 1 = clockwise on screen, -1 = the other way

@export_group("Ejection")
@export var eject_radius := 14.0       # radius of the eye
@export var eject_speed := 330.0
@export var eject_spin := 0.5          # share of tangent in the throw
@export var eject_cooldown := 1.2
@export var eject_grace := 0.6

var active := true

var _cooldown := {}                    # body -> seconds left
var _grace := {}                       # body -> seconds left

func _ready() -> void:
	add_to_group("cyclones")


## Shows or hides the storm and switches its wind with it.
func set_active(value: bool) -> void:
	active = value
	visible = value
	set_physics_process(value)
	field.set_deferred("monitoring", value)
	if not value:
		_cooldown.clear()
		_grace.clear()

func get_wind_at(pos: Vector2) -> Vector2:
	var to_center := global_position - pos
	var d := to_center.length()
	if not active or d > pull_radius or d < 0.001:
		return Vector2.ZERO

	var dir := to_center / d
	var t := clampf(d / pull_radius, 0.0, 1.0)
	var f := pow(1.0 - t, falloff_power)

	return dir * pull_speed * f \
		+ dir.rotated(PI * 0.5 * spin) * swirl_speed * f


func _physics_process(delta: float) -> void:
	_tick(_cooldown, delta)
	_tick(_grace, delta)

	for body in field.get_overlapping_bodies():
		
		if not body is Node2D:
			continue
	
		var d := global_position.distance_to(body.global_position)
	
		if d <= eject_radius and _cooldown.get(body, 0.0) <= 0.0:
			_eject(body)
		elif _grace.get(body, 0.0) <= 0.0 and body.has_method("add_wind"):
			body.add_wind(get_wind_at(body.global_position))

func _tick(d: Dictionary, delta: float) -> void:
	for k in d.keys():          # keys() is a copy, so erase() is safe
		d[k] -= delta
		if d[k] <= 0.0:
			d.erase(k)

func _eject(body: Node2D) -> void:
	var away := body.global_position - global_position
	if away.length() < 0.001:
		away = Vector2.DOWN
	away = away.normalized()

	var impulse := away * eject_speed \
		+ away.rotated(PI * 0.5 * spin) * eject_speed * eject_spin

	_cooldown[body] = eject_cooldown
	_grace[body] = eject_grace

	if body.has_method("apply_knockback"):
		body.apply_knockback(impulse)
	if body.has_method("stun"):
		body.stun(0.25)

	body_ejected.emit(body)
