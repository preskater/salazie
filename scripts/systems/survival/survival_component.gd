class_name SurvivalComponent
extends Node
## Tracks food and water while the player is in a survival scenario.
## Emits signals instead of being polled by the HUD.

signal food_changed(current: float, maximum: float)
signal water_changed(current: float, maximum: float)
signal depleted(kind: StringName)

@export var active := true
@export var food_max := 100.0
@export var water_max := 100.0
@export var food_drain := 1.0
@export var water_drain := 1.5

var food: float = 0.0
var water: float = 0.0

var _food_depleted := false
var _water_depleted := false


func _ready() -> void:
	food = food_max
	water = water_max
	add_to_group("survival")


func _process(delta: float) -> void:
	tick(delta)


## Advances the simulation. Kept separate from _process so tests can call it
## with an explicit delta instead of depending on the frame rate.
func tick(delta: float) -> void:
	if not active:
		return
	_set_food(food - food_drain * delta)
	_set_water(water - water_drain * delta)


func add_food(amount: float) -> void:
	_set_food(food + amount)


func add_water(amount: float) -> void:
	_set_water(water + amount)


func _set_food(value: float) -> void:
	var clamped := clampf(value, 0.0, food_max)
	# Exact comparison on purpose: `is_equal_approx` swallowed the tiny drain of
	# a single frame above ~350 fps, and the bar never went down.
	if clamped == food:
		return
	food = clamped
	food_changed.emit(food, food_max)

	if food <= 0.0 and not _food_depleted:
		_food_depleted = true
		depleted.emit(&"food")
	elif food > 0.0:
		_food_depleted = false


func _set_water(value: float) -> void:
	var clamped := clampf(value, 0.0, water_max)
	if clamped == water:
		return
	water = clamped
	water_changed.emit(water, water_max)

	if water <= 0.0 and not _water_depleted:
		_water_depleted = true
		depleted.emit(&"water")
	elif water > 0.0:
		_water_depleted = false
