extends CanvasLayer

## Plays a short fade-to-black transition between two scenes. The title and
## subtitle shown while the screen is covered are configurable per transition,
## so each map change can announce its own chapter.

signal transition_started
signal scene_changed(scene_path: String)
signal transition_finished

@export_group("Timing")
@export_range(0.0, 10.0, 0.05) var fade_out_duration := 0.5
@export_range(0.0, 10.0, 0.05) var hold_duration := 1.2
@export_range(0.0, 10.0, 0.05) var fade_in_duration := 0.5

@export_group("Look")
@export var fade_color := Color.BLACK
@export var title_color := Color.WHITE
@export var subtitle_color := Color(0.85, 0.85, 0.9)

@export_group("Default text")
@export var default_title := ""
@export_multiline var default_subtitle := ""

var is_transitioning := false

@onready var _backdrop: ColorRect = $Backdrop
@onready var _text: CenterContainer = $Text
@onready var _title_label: Label = $Text/Layout/Title
@onready var _subtitle_label: Label = $Text/Layout/Subtitle

func _ready() -> void:
	_apply_style()
	_apply_alpha(0.0)

## Fades out, displays `title` and `subtitle` over the black screen, swaps to
## `scene_path`, then fades back in. Callers that need to wait can `await` it.
func change_scene(scene_path: String, title := default_title, subtitle := default_subtitle) -> void:
	if is_transitioning:
		return
	if not ResourceLoader.exists(scene_path):
		push_error("SceneTransition: scene not found: %s" % scene_path)
		return
	await cover(title, subtitle)
	await _hold()
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("SceneTransition: failed to load %s (error %d)" % [scene_path, error])
		await reveal()
		return
	scene_changed.emit(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	await reveal()

## Fades to black and shows the given text. Exposed for scripted transitions
## and tests; `reveal()` ends it.
func cover(title := default_title, subtitle := default_subtitle) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_apply_style()
	_title_label.text = title
	_title_label.visible = not title.is_empty()
	_subtitle_label.text = subtitle
	_subtitle_label.visible = not subtitle.is_empty()
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	transition_started.emit()
	await _fade_to(1.0, fade_out_duration)

## Fades back to the game. Exposed for scripted transitions and tests.
func reveal() -> void:
	if not is_transitioning:
		return
	await _fade_to(0.0, fade_in_duration)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
	transition_finished.emit()

func _hold() -> void:
	if hold_duration <= 0.0:
		return
	await get_tree().create_timer(hold_duration).timeout

func _fade_to(alpha: float, duration: float) -> void:
	if duration <= 0.0:
		_apply_alpha(alpha)
		return
	var tween := create_tween()
	tween.tween_method(_apply_alpha, _backdrop.color.a, alpha, duration)
	await tween.finished

func _apply_alpha(alpha: float) -> void:
	_backdrop.color = Color(fade_color, alpha)
	_text.modulate.a = alpha

func _apply_style() -> void:
	_title_label.add_theme_color_override("font_color", title_color)
	_subtitle_label.add_theme_color_override("font_color", subtitle_color)
