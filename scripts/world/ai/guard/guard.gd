extends CharacterBody2D
## Map 1 patrol guard.
## Patrols a rectangular zone, hears the player running, watches a 60 degree cone
## and escalates from suspicious (orange) to alert (red) before catching the player.

signal caught

enum State { PATROL, SUSPICIOUS, ALERT, CAUGHT }

const COLOR_PATROL := Color(1.0, 1.0, 1.0, 0.05)
const COLOR_SUSPICIOUS := Color(1.0, 0.6, 0.1, 0.12)
const COLOR_ALERT := Color(0.9, 0.1, 0.1, 0.2)
const SUSPICIOUS_COLOR := Color(1.0, 0.6, 0.1)
const ALERT_COLOR := Color(0.9, 0.1, 0.1)
const ALERT_REST_Y := -110.0
const ARRIVE_DISTANCE := 10.0

@export_group("Patrol")
@export var zone_center: Node2D
@export var zone_size := Vector2(420.0, 320.0)
@export var patrol_speed := 70.0
@export var wait_min := 1.0
@export var wait_max := 2.0
## Tests disable this so movement stays deterministic without a navigation map.
@export var use_navigation := true

@export_group("Vision")
@export var vision_range := 400.0
@export var vision_angle_deg := 60.0
@export var vision_check_interval := 0.1
@export var suspicion_delay := 2.0
@export var investigate_timeout := 5.0

@export_group("Chase")
@export var chase_speed := 260.0
@export var catch_distance := 48.0
@export var give_up_delay := 3.0
@export var give_up_cooldown := 1.5
@export var leash_margin := 40.0
@export var pause_on_catch := true

var state: State = State.PATROL
var suspicion := 0.0
var facing := Vector2.DOWN
var player: Node2D = null
var last_seen_position := Vector2.ZERO

var _spawn_position := Vector2.ZERO
var _patrol_point := Vector2.ZERO
var _investigate_point := Vector2.ZERO
var _wait_timer := 0.0
var _state_timer := 0.0
var _vision_timer := 0.0
var _out_of_zone_timer := 0.0
var _ignore_timer := 0.0
var _patrol_progress_timer := 0.0
var _patrol_best_distance := INF
var _can_see := false
var _caught_emitted := false

@onready var agent: NavigationAgent2D = $NavigationAgent2D
@onready var alert: Label = $Alert
@onready var vision_ray: RayCast2D = $VisionRay
@onready var sprite: AnimatedSprite2D = $Sprite

func _ready() -> void:
	_spawn_position = global_position
	add_to_group("guards")
	player = get_tree().get_first_node_in_group("player") as Node2D
	agent.path_desired_distance = 12.0
	agent.target_desired_distance = 16.0
	_pick_patrol_point()
	alert.visible = false


func _physics_process(delta: float) -> void:
	tick(delta)
	queue_redraw()

func update_animation() -> void:
	var moving := velocity.length() > 2.0
	var prefix := "idle"
	if moving:
		prefix = "walk"

	var direction := "down"
	if absf(facing.x) > absf(facing.y):
		direction = "left" if facing.x < 0.0 else "right"
	elif facing.y < 0.0:
		direction = "up"

	var animation := "%s_%s" % [prefix, direction]
	if sprite.animation != animation:
		sprite.play(animation)

## Advances the state machine. Split from _physics_process so tests can drive it
## with an explicit delta instead of relying on the frame rate.
func tick(delta: float) -> void:
	if state == State.CAUGHT:
		return

	if _ignore_timer > 0.0:
		# Just gave up: ignore the player so it can walk back instead of
		# re-engaging every frame.
		_ignore_timer -= delta
		_can_see = false
	else:
		_vision_timer -= delta
		if _vision_timer <= 0.0:
			_vision_timer = vision_check_interval
			_can_see = _sees_player()
			if _can_see:
				last_seen_position = player.global_position

	match state:
		State.PATROL:
			_tick_patrol(delta)
			if _can_see:
				_enter_suspicious(player.global_position)
		State.SUSPICIOUS:
			_tick_suspicious(delta)
		State.ALERT:
			_tick_alert(delta)
	
	update_animation()


# --- Perception -------------------------------------------------------------

func hear_noise(source: Vector2, radius: float) -> void:
	if state == State.ALERT or state == State.CAUGHT:
		return
	if _ignore_timer > 0.0:
		return
	if global_position.distance_to(source) > radius:
		return
	_enter_suspicious(source)


func can_see(target: Vector2) -> bool:
	var to_target := target - global_position
	var distance := to_target.length()
	if distance > vision_range or distance < 1.0:
		return false
	if absf(facing.angle_to(to_target)) > deg_to_rad(vision_angle_deg * 0.5):
		return false
	return not _is_occluded(target)


func _sees_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("set_hidden") and bool(player.get("concealed")) \
			and global_position.distance_to(player.global_position) > 32.0:
		return false
	return can_see(player.global_position)


func _is_occluded(target: Vector2) -> bool:
	vision_ray.target_position = to_local(target)
	vision_ray.force_raycast_update()
	return vision_ray.is_colliding()


# --- States -----------------------------------------------------------------

func _tick_patrol(delta: float) -> void:
	if _wait_timer > 0.0:
		_wait_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var distance := global_position.distance_to(_patrol_point)
	if distance <= ARRIVE_DISTANCE:
		_wait_timer = randf_range(wait_min, wait_max)
		_pick_patrol_point()
		return

	# Watchdog: an unreachable target (river island, stale path after a bake)
	# would otherwise leave the guard frozen forever.
	_patrol_progress_timer += delta
	if distance < _patrol_best_distance - 2.0:
		_patrol_best_distance = distance
		_patrol_progress_timer = 0.0
	elif _patrol_progress_timer > 1.5:
		_wait_timer = randf_range(wait_min, wait_max)
		_pick_patrol_point()
		return

	_move_towards(_patrol_point, patrol_speed)


func _tick_suspicious(delta: float) -> void:
	_state_timer -= delta

	if _can_see and player != null:
		suspicion += delta
		_state_timer = investigate_timeout
		_investigate_point = player.global_position
		if suspicion >= suspicion_delay:
			_enter_alert()
			return
	else:
		suspicion = maxf(0.0, suspicion - delta * 0.5)
		if _state_timer <= 0.0:
			_enter_patrol()
			return

	var target := _investigate_point
	if global_position.distance_to(target) > ARRIVE_DISTANCE:
		_move_towards(target, patrol_speed * 1.2)
	else:
		velocity = Vector2.ZERO
		move_and_slide()


func _tick_alert(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		_enter_patrol()
		return

	if _can_see:
		last_seen_position = player.global_position
		_state_timer = give_up_delay
		_out_of_zone_timer = 0.0

	if global_position.distance_to(player.global_position) <= catch_distance:
		_catch()
		return

	# Give up after `give_up_delay` seconds without seeing the player.
	_state_timer -= delta
	if _state_timer <= 0.0:
		_give_up()
		return

	# Leash: if the player stays outside the patrol zone, stop following.
	if not _zone_rect().grow(leash_margin).has_point(player.global_position):
		_out_of_zone_timer += delta
		if _out_of_zone_timer >= give_up_delay:
			_give_up()
			return

	_move_towards(last_seen_position, chase_speed)


# --- Transitions ------------------------------------------------------------

func _enter_patrol() -> void:
	state = State.PATROL
	suspicion = 0.0
	_wait_timer = 0.0
	_out_of_zone_timer = 0.0
	alert.visible = false
	_pick_patrol_point()


func _enter_suspicious(point: Vector2) -> void:
	state = State.SUSPICIOUS
	_investigate_point = point
	_state_timer = investigate_timeout
	_out_of_zone_timer = 0.0
	_show_alert(SUSPICIOUS_COLOR)


func _enter_alert() -> void:
	if state != State.ALERT:
		Audio.play_sfx(&"alert")
	state = State.ALERT
	suspicion = suspicion_delay
	_state_timer = give_up_delay
	_out_of_zone_timer = 0.0
	if player != null:
		last_seen_position = player.global_position
	_show_alert(ALERT_COLOR)


func _give_up() -> void:
	_ignore_timer = give_up_cooldown
	_enter_patrol()


func _catch() -> void:
	if _caught_emitted:
		return
	_caught_emitted = true
	state = State.CAUGHT
	velocity = Vector2.ZERO
	_can_see = false
	queue_redraw()

	caught.emit()
	print("GAME OVER")
	if pause_on_catch:
		get_tree().paused = true


## Puts a guard back on patrol after the player respawns at a checkpoint.
func reset_after_catch(at := _spawn_position) -> void:
	global_position = at
	_caught_emitted = false
	state = State.PATROL
	suspicion = 0.0
	velocity = Vector2.ZERO
	_can_see = false
	_ignore_timer = give_up_cooldown
	alert.visible = false
	_pick_patrol_point()
	queue_redraw()


# --- Helpers ----------------------------------------------------------------

func _show_alert(color: Color) -> void:
	var was_visible := alert.visible
	alert.visible = true
	alert.modulate = Color(color, 1.0)
	if not was_visible:
		alert.position.y = ALERT_REST_Y + 8.0
		alert.modulate.a = 0.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(alert, "modulate:a", 1.0, 0.12)
		tween.tween_property(alert, "position:y", ALERT_REST_Y, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pick_patrol_point() -> void:
	var center := _spawn_position
	if zone_center != null:
		center = zone_center.global_position

	_patrol_progress_timer = 0.0
	_patrol_best_distance = INF
	_patrol_point = _random_patrol_point(center)

	if not use_navigation or not _has_navigation_map():
		return

	# Snap to the navmesh and keep looking until a path exists, otherwise the
	# guard would freeze on a point across the river or inside a tree.
	var nav_map := agent.get_navigation_map()
	for _attempt in 6:
		var candidate := NavigationServer2D.map_get_closest_point(nav_map, _patrol_point)
		if NavigationServer2D.map_get_path(
				nav_map, global_position, candidate, true).size() > 1:
			_patrol_point = candidate
			return
		_patrol_point = _random_patrol_point(center)

	_patrol_point = NavigationServer2D.map_get_closest_point(nav_map, _patrol_point)


func _random_patrol_point(center: Vector2) -> Vector2:
	return center + Vector2(
		randf_range(-zone_size.x * 0.5, zone_size.x * 0.5),
		randf_range(-zone_size.y * 0.5, zone_size.y * 0.5)
	)


## Patrol area in world space.
func _zone_rect() -> Rect2:
	var center := _spawn_position
	if zone_center != null:
		center = zone_center.global_position
	return Rect2(center - zone_size * 0.5, zone_size)


func _move_towards(target: Vector2, speed: float) -> void:
	var next := target

	if use_navigation:
		agent.target_position = target
		if _has_navigation_map():
			if not agent.is_target_reachable():
				# Unreachable target: head to the closest navigable point.
				next = agent.get_final_position()
				if next.distance_to(global_position) < 1.0:
					velocity = Vector2.ZERO
					move_and_slide()
					return
			elif agent.is_navigation_finished():
				velocity = Vector2.ZERO
				move_and_slide()
				return
			else:
				next = agent.get_next_path_position()

	var direction := global_position.direction_to(next)
	velocity = direction * speed
	move_and_slide()

	if direction.length() > 0.01:
		facing = direction


func _has_navigation_map() -> bool:
	return NavigationServer2D.map_get_iteration_id(agent.get_navigation_map()) > 0


func _draw() -> void:
	var rect := _zone_rect()
	draw_rect(Rect2(to_local(rect.position), rect.size), Color(0.4, 0.8, 1.0, 0.15), false, 1.0)

	if state == State.CAUGHT:
		return

	var color := COLOR_PATROL
	if state == State.SUSPICIOUS:
		color = COLOR_SUSPICIOUS
	elif state == State.ALERT:
		color = COLOR_ALERT

	var half := deg_to_rad(vision_angle_deg * 0.5)
	var steps := 12
	var points := PackedVector2Array([Vector2.ZERO])
	for i in range(steps + 1):
		var angle := facing.angle() - half + 2.0 * half * (float(i) / float(steps))
		points.append(Vector2.from_angle(angle) * vision_range)
	draw_colored_polygon(points, color)
