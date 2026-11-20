extends Node2D

@onready var field: Area2D = $Area2D
@export_range(0.2, 3.0, 0.05) var falloff_power := 0.7  

@export_group("Aspiration")
@export var pull_radius := 70.0        # portée du vent
@export var pull_speed := 380.0        # px/s vers le centre, au maximum
@export var swirl_speed := 300.0       # px/s tangent (la rotation)
@export var spin := 1.0                # 1 = sens horaire à l'écran, -1 = antihoraire

@export_group("Éjection")
@export var eject_radius := 14.0       # rayon du "cœur" (l'œil)
@export var eject_speed := 330.0
@export var eject_spin := 0.5          # part de tangent dans l'éjection
@export var eject_cooldown := 1.2
@export var eject_grace := 0.6

signal body_ejected(body: Node2D)

var _cooldown := {}                    # body -> temps restant
var _grace := {}                       # body -> temps restant

func _ready() -> void:
	add_to_group("cyclones")

func get_wind_at(pos: Vector2) -> Vector2:
	var to_center := global_position - pos
	var d := to_center.length()
	if d > pull_radius or d < 0.001:
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
	for k in d.keys():          # keys() renvoie une copie → erase() est sûr
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
