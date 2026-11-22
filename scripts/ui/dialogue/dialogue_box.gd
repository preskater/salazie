class_name DialogueBox
extends CanvasLayer
## Lightweight NPC dialogue panel used by Map 3. It never pauses the game. A
## line stays long enough to be read (the delay grows with its length) and can
## be dismissed at once with `interact` or `ui_accept`.

signal closed()

const MIN_DURATION := 3.0
const SECONDS_PER_CHARACTER := 0.06
const MAX_DURATION := 14.0

const THEME := preload("res://themes/salazie/salazie_theme.tres")
const TEXT_DARK := Color(0.22, 0.14, 0.08)

var _panel: PanelContainer
var _speaker: Label
var _text: Label
var _timer: Timer


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()


func show_line(speaker: String, text: String) -> void:
	_speaker.text = speaker
	_text.text = text
	show()
	_timer.start(reading_time(text))


## How long a line stays without input: about 16 characters a second, which is
## a comfortable reading pace, within sensible bounds.
func reading_time(text: String) -> float:
	return clampf(text.length() * SECONDS_PER_CHARACTER, MIN_DURATION, MAX_DURATION)


func hide_line() -> void:
	if not visible:
		return
	_timer.stop()
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		hide_line()
		# The same press must not also talk to whoever stands in front.
		get_viewport().set_input_as_handled()


func get_text() -> String:
	return _text.text if _text != null else ""


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = THEME
	add_child(root)

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"HudPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -460.0
	_panel.offset_right = 460.0
	_panel.offset_top = -176.0
	_panel.offset_bottom = -24.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 20)
	_speaker.add_theme_color_override("font_color", Color(0.42, 0.22, 0.03))
	column.add_child(_speaker)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 17)
	_text.add_theme_color_override("font_color", TEXT_DARK)
	column.add_child(_text)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide_line)
	add_child(_timer)
