extends Node

## Tracks the day/night cycle of the current map and counts the nights spent
## there. Once `nights_required_for_next_map` nights have been fully spent,
## `ready_for_next_map` is emitted and `is_ready_for_next_map()` stays true
## until the map transition calls `reset_for_new_map()`.

signal phase_changed(phase: Phase)
signal day_started(day_number: int)
signal night_started(day_number: int)
signal night_completed(nights_spent: int)
signal ready_for_next_map

enum Phase { DAY, NIGHT }

const MIN_PHASE_DURATION := 0.01
const TRANSITION_RATIO := 0.2

@export_group("Cycle")
@export_range(1.0, 3600.0, 1.0, "or_greater") var day_duration := 120.0
@export_range(1.0, 3600.0, 1.0, "or_greater") var night_duration := 60.0
## Number of fully spent nights required before the map is ready to be left.
@export var nights_required_for_next_map := 2:
	set(value):
		nights_required_for_next_map = maxi(0, value)
		_update_ready_state()
@export var start_at_night := false

@export_group("Tint")
@export var tint_enabled := true:
	set(value):
		tint_enabled = value
		_apply_tint()
@export var day_color := Color.WHITE
@export var dusk_color := Color(1.0, 0.66, 0.45)
@export var night_color := Color(0.18, 0.22, 0.42)
@export var dawn_color := Color(0.78, 0.68, 0.78)

var phase: Phase = Phase.DAY
var day_number := 1
var nights_spent := 0
var time_left := 0.0
var running := true

var _ready_announced := false
var _tint: CanvasModulate

func _ready() -> void:
	_tint = CanvasModulate.new()
	_tint.name = "Tint"
	add_child(_tint)
	day_number = 1
	phase = Phase.NIGHT if start_at_night else Phase.DAY
	time_left = _current_phase_duration()
	_apply_tint()
	_update_ready_state()

func _process(delta: float) -> void:
	advance(delta)

## Advances the cycle by `delta` seconds. Exposed so tests and time skips do not
## depend on the frame rate.
func advance(delta: float) -> void:
	if not running or delta <= 0.0:
		return
	time_left -= delta
	while time_left <= 0.0:
		var overflow := -time_left
		_complete_phase()
		time_left = _current_phase_duration() - overflow
	_apply_tint()

## Restarts the cycle for a new map. Call this from the map transition once
## `ready_for_next_map` has been acted upon. It stays silent: the caller already
## owns the transition.
func reset_for_new_map(required_nights := nights_required_for_next_map, begin_at_night := false) -> void:
	nights_spent = 0
	# Marked as announced first: the setter below checks the state, and with no
	# night required it would emit `ready_for_next_map` from a reset that is
	# documented as silent.
	_ready_announced = true
	nights_required_for_next_map = maxi(0, required_nights)
	_ready_announced = is_ready_for_next_map()
	day_number = 1
	phase = Phase.NIGHT if begin_at_night else Phase.DAY
	time_left = _current_phase_duration()
	_apply_tint()

func to_dict() -> Dictionary:
	return {
		"day_number": day_number,
		"phase": int(phase),
		"time_left": time_left,
	}


## Restores a saved cycle. Anything missing or out of range keeps the current
## value, so an old save simply resumes at dawn.
func from_dict(data: Dictionary) -> void:
	var raw_day: Variant = data.get("day_number", null)
	if raw_day is int or raw_day is float:
		day_number = maxi(1, int(raw_day))
	var raw_phase: Variant = data.get("phase", null)
	if raw_phase is int or raw_phase is float:
		phase = Phase.NIGHT if int(raw_phase) == Phase.NIGHT else Phase.DAY
	var raw_time: Variant = data.get("time_left", null)
	if raw_time is int or raw_time is float:
		time_left = clampf(float(raw_time), MIN_PHASE_DURATION, _current_phase_duration())
	else:
		time_left = _current_phase_duration()
	_apply_tint()


## Puts the cycle at `fraction` (0 to 1) of day `day`, for a map that keeps its
## own clock. The farm counts its days in `GameState`: it drives the sky with
## this instead of letting a second clock run beside it at another pace.
func set_progress(day: int, fraction: float) -> void:
	var total := maxf(day_duration, MIN_PHASE_DURATION) + maxf(night_duration, MIN_PHASE_DURATION)
	var elapsed := clampf(fraction, 0.0, 1.0) * total
	var next_phase := Phase.DAY if elapsed < day_duration else Phase.NIGHT
	day_number = maxi(1, day)
	if next_phase != phase:
		phase = next_phase
		phase_changed.emit(phase)
		if phase == Phase.NIGHT:
			night_started.emit(day_number)
		else:
			day_started.emit(day_number)
	var into_phase := elapsed if phase == Phase.DAY else elapsed - day_duration
	time_left = maxf(0.0, _current_phase_duration() - into_phase)
	_apply_tint()


func is_night() -> bool:
	return phase == Phase.NIGHT

func is_ready_for_next_map() -> bool:
	return nights_spent >= nights_required_for_next_map

func nights_remaining() -> int:
	return maxi(0, nights_required_for_next_map - nights_spent)

func seconds_until_next_phase() -> float:
	return maxf(time_left, 0.0)

func _complete_phase() -> void:
	if phase == Phase.DAY:
		phase = Phase.NIGHT
		phase_changed.emit(phase)
		night_started.emit(day_number)
		return
	nights_spent += 1
	night_completed.emit(nights_spent)
	_update_ready_state()
	phase = Phase.DAY
	day_number += 1
	phase_changed.emit(phase)
	day_started.emit(day_number)

func _update_ready_state() -> void:
	if not is_ready_for_next_map():
		_ready_announced = false
		return
	if _ready_announced:
		return
	_ready_announced = true
	ready_for_next_map.emit()

func _current_phase_duration() -> float:
	var duration := night_duration if phase == Phase.NIGHT else day_duration
	return maxf(duration, MIN_PHASE_DURATION)

func _phase_progress() -> float:
	return clampf(1.0 - time_left / _current_phase_duration(), 0.0, 1.0)

func _apply_tint() -> void:
	if _tint == null:
		return
	_tint.visible = tint_enabled
	if tint_enabled:
		_tint.color = _current_tint()

func _current_tint() -> Color:
	var progress := _phase_progress()
	if phase == Phase.DAY:
		if progress < TRANSITION_RATIO:
			return dawn_color.lerp(day_color, smoothstep(0.0, TRANSITION_RATIO, progress))
		if progress > 1.0 - TRANSITION_RATIO:
			return day_color.lerp(dusk_color, smoothstep(1.0 - TRANSITION_RATIO, 1.0, progress))
		return day_color
	if progress < TRANSITION_RATIO:
		return dusk_color.lerp(night_color, smoothstep(0.0, TRANSITION_RATIO, progress))
	if progress > 1.0 - TRANSITION_RATIO:
		return night_color.lerp(dawn_color, smoothstep(1.0 - TRANSITION_RATIO, 1.0, progress))
	return night_color
