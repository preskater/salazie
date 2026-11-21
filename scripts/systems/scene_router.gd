extends Node
## Owns scene transitions and the game lifecycle (new game, continue, quit).
## Kept in the tree for the whole session so menus and gameplay share one route.

signal scene_changed(scene: Node)
signal transition_finished()

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const GAME_SCENE := "res://scenes/maps/maroon.tscn"
const FARM_SCENE := "res://scenes/maps/farm.tscn"
const HEIR_SCENE := "res://scenes/maps/heir.tscn"
const ENDING_SCENE := "res://scenes/ui/ending/ending_screen.tscn"
const FADE_TIME := 0.25

var is_gameplay := false

var _transitioning := false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_fade()
	_set_day_night_active(false)
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_on_close_requested)


func start_new_game() -> void:
	if _transitioning:
		return
	Campaign.reset()
	GameState.reset(Campaign.starting_money_for_map(1))
	GameState.farm_active = false
	GameState.playing = true
	is_gameplay = true
	_set_day_night_active(true, true)
	var ok := await _change_scene(Campaign.current_scene_path())
	if not ok:
		GameState.playing = false
		is_gameplay = false
		_set_day_night_active(false)
		return
	SaveGame.save_game()


func continue_game() -> void:
	if _transitioning:
		return
	if not SaveGame.load_game():
		return
	GameState.playing = true
	GameState.farm_active = Campaign.current_map == 2
	is_gameplay = true
	_set_day_night_active(true, true)
	var ok := await _change_scene(Campaign.current_scene_path())
	if not ok:
		GameState.playing = false
		is_gameplay = false
		_set_day_night_active(false)


## Leaves the current map for the next generation. The caller must have
## resolved every task; failed tasks are allowed and recorded in the result.
func go_to_next_map() -> bool:
	if _transitioning or SceneTransition.is_transitioning:
		return false
	if not Campaign.can_leave_map():
		return false
	var summary := Campaign.finalize_map()
	var previous_map := Campaign.current_map
	if not Campaign.advance_to_next_map():
		await go_to_ending()
		return true
	_prepare_map_entry(Campaign.current_map)
	SaveGame.save_game()
	_transitioning = true
	get_tree().paused = false
	var subtitle := "%s · %d réussies · %d échouées" % [
		Campaign.map_subtitle(),
		int(summary.get("done", 0)),
		int(summary.get("failed", 0)),
	]
	await SceneTransition.change_scene(
		Campaign.current_scene_path(), Campaign.map_title(), subtitle)
	_transitioning = false
	is_gameplay = true
	scene_changed.emit(get_tree().current_scene)
	transition_finished.emit()
	return Campaign.current_map != previous_map


func go_to_ending() -> void:
	if _transitioning or SceneTransition.is_transitioning:
		return
	Campaign.finalize_map()
	Campaign.finished = true
	if GameState.playing:
		SaveGame.save_game()
	GameState.playing = false
	is_gameplay = false
	_set_day_night_active(false)
	await _change_scene(ENDING_SCENE)


func go_to_main_menu() -> void:
	if _transitioning:
		return
	if is_gameplay:
		SaveGame.save_game()
	GameState.playing = false
	is_gameplay = false
	_set_day_night_active(false)
	await _change_scene(MAIN_MENU_SCENE)


func quit_game() -> void:
	Settings.save_settings()
	if is_gameplay:
		SaveGame.save_game()
	get_tree().quit()


func _change_scene(path: String) -> bool:
	if _transitioning:
		return false
	_transitioning = true
	get_tree().paused = false
	await _fade(1.0)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Could not change scene to %s (error %d)." % [path, err])
		await _fade(0.0)
		_transitioning = false
		transition_finished.emit()
		return false
	await get_tree().process_frame
	await get_tree().process_frame
	scene_changed.emit(get_tree().current_scene)
	await _fade(0.0)
	_transitioning = false
	transition_finished.emit()
	return true


func _prepare_map_entry(map_id: int) -> void:
	GameState.playing = true
	GameState.farm_active = map_id == 2
	if map_id == 2:
		GameState.reset(Campaign.starting_money_for_map(2))
		for crop: String in Campaign.bonus_seeds:
			GameState.add_seeds(crop, int(Campaign.bonus_seeds[crop]))
	elif map_id == 3:
		Campaign.heritage = Campaign.heritage_for_map3()
	_set_day_night_active(true, true)
	DayNightCycle.nights_required_for_next_map = 0


func _on_close_requested() -> void:
	Settings.save_settings()
	if is_gameplay:
		SaveGame.save_game()
	get_tree().quit()


func _set_day_night_active(active: bool, reset_cycle := false) -> void:
	if reset_cycle:
		DayNightCycle.reset_for_new_map(0)
	DayNightCycle.running = active
	DayNightCycle.tint_enabled = active


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FadeLayer"
	_fade_layer.layer = 120
	_fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color(0.02, 0.03, 0.05, 1.0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	_fade_layer.add_child(_fade_rect)


func _fade(target_alpha: float) -> void:
	if _fade_rect == null:
		return
	_fade_rect.visible = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade_rect, "modulate:a", target_alpha, FADE_TIME)
	await tween.finished
	if target_alpha <= 0.001:
		_fade_rect.visible = false
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
