extends Node
## Owns scene transitions and the game lifecycle (new game, continue, quit).
## Kept in the tree for the whole session so menus and gameplay share one route.

signal scene_changed(scene: Node)
signal transition_finished()

const MAIN_MENU_SCENE := "res://game/ui/menus/main_menu.tscn"
const GAME_SCENE := "res://game/world/maps/Farm.tscn"
const FADE_TIME := 0.25

var is_gameplay := false

var _transitioning := false
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_fade()
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_on_close_requested)


func start_new_game() -> void:
	if _transitioning:
		return
	GameState.reset()
	GameState.playing = true
	is_gameplay = true
	var ok := await _change_scene(GAME_SCENE)
	if not ok:
		GameState.playing = false
		is_gameplay = false
		return
	SaveGame.save_game()


func continue_game() -> void:
	if _transitioning:
		return
	if not SaveGame.load_game():
		return
	GameState.playing = true
	is_gameplay = true
	var ok := await _change_scene(GAME_SCENE)
	if not ok:
		GameState.playing = false
		is_gameplay = false


func go_to_main_menu() -> void:
	if _transitioning:
		return
	if is_gameplay:
		SaveGame.save_game()
	GameState.playing = false
	is_gameplay = false
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


func _on_close_requested() -> void:
	Settings.save_settings()
	if is_gameplay:
		SaveGame.save_game()
	get_tree().quit()


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FadeLayer"
	_fade_layer.layer = 120
	_fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fade_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.color = Color(0.02, 0.03, 0.05, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
