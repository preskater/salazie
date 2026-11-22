class_name GenerationResult
extends CanvasLayer
## Modal generation report shown before leaving a map. It lists every task,
## its final status and the failures kept in the generation record.

signal confirmed()

const THEME := preload("res://themes/salazie/salazie_theme.tres")
const TEXT_DARK := Color(0.22, 0.14, 0.08)
const TEXT_MUTED := Color(0.43, 0.36, 0.29)
const POSITIVE := Color(0.12, 0.42, 0.16)
const NEGATIVE := Color(0.62, 0.14, 0.1)
const ACCENT := Color(0.42, 0.22, 0.03)

var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _rows: VBoxContainer
var _footer: Label
var _continue_button: Button
var _paused_by_us := false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("generation_result")
	_build_ui()
	hide()


func show_result(summary: Dictionary, next_label := "", note := "") -> void:
	_title.text = "Map %d — %s" % [int(summary.get("map", 1)), String(summary.get("title", ""))]
	var done := int(summary.get("done", 0))
	var failed := int(summary.get("failed", 0))
	var rank := String(summary.get("rank", "partial"))
	var rank_text: String = {
		"full": "Génération accomplie",
		"partial": "Génération partielle",
		"poor": "Génération difficile",
	}.get(rank, "Génération terminée")
	_subtitle.text = "%s — %d réussie%s · %d échouée%s" % [
		rank_text,
		done, "s" if done > 1 else "",
		failed, "s" if failed > 1 else "",
	]
	for child: Node in _rows.get_children():
		child.free()
	var details: Dictionary = summary.get("tasks", {})
	var order: Array = Campaign.TASKS.get(int(summary.get("map", 1)), [])
	for definition: Dictionary in order:
		var task_id := String(definition.get("id", ""))
		if not details.has(task_id):
			continue
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 16)
		var task: Dictionary = details[task_id]
		var status := int(task.get("status", Campaign.TaskStatus.PENDING))
		var label := String(task.get("label", task_id))
		var failures := int((task.get("failures", []) as Array).size())
		if status == Campaign.TaskStatus.DONE:
			row.text = "✓ " + label
			if failures > 0:
				row.text += " (%d échec%s)" % [failures, "s" if failures > 1 else ""]
			row.add_theme_color_override("font_color", POSITIVE)
		elif status == Campaign.TaskStatus.FAILED:
			var reason := ""
			var failure_list: Array = task.get("failures", [])
			if not failure_list.is_empty():
				reason = String((failure_list[-1] as Dictionary).get("reason", ""))
			row.text = "✗ " + label
			if not reason.is_empty():
				row.text += " — " + reason
			row.add_theme_color_override("font_color", NEGATIVE)
		else:
			row.text = "○ " + label
			row.add_theme_color_override("font_color", TEXT_DARK)
		_rows.add_child(row)
	var setbacks := int((summary.get("setbacks", []) as Array).size())
	if setbacks > 0:
		var setback_row := Label.new()
		setback_row.name = "SetbackRow"
		setback_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		setback_row.add_theme_font_size_override("font_size", 16)
		setback_row.text = "✗ %d revers en chemin" % setbacks
		setback_row.add_theme_color_override("font_color", NEGATIVE)
		_rows.add_child(setback_row)
	var parts: PackedStringArray = PackedStringArray()
	if not next_label.is_empty():
		parts.append(next_label)
	if not note.is_empty():
		parts.append(note)
	_footer.text = "\n".join(parts)
	show()
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true
	_continue_button.grab_focus()


func close() -> void:
	if _paused_by_us:
		get_tree().paused = false
		_paused_by_us = false
	hide()


func get_title_text() -> String:
	return _title.text if _title != null else ""


func get_row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	if _rows == null:
		return texts
	for child: Node in _rows.get_children():
		if child is Label:
			texts.append((child as Label).text)
	return texts


func _build_ui() -> void:
	var root := Control.new()
	root.name = "ResultRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = THEME
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.02, 0.03, 0.05, 0.72)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(760, 460)
	_panel.theme_type_variation = &"HudPanel"
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", ACCENT)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 18)
	_subtitle.add_theme_color_override("font_color", TEXT_MUTED)
	column.add_child(_subtitle)

	var separator := HSeparator.new()
	column.add_child(separator)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 5)
	column.add_child(_rows)

	_footer = Label.new()
	_footer.name = "Footer"
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.add_theme_font_size_override("font_size", 16)
	_footer.add_theme_color_override("font_color", ACCENT)
	column.add_child(_footer)

	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.text = "Continuer"
	_continue_button.custom_minimum_size = Vector2(220, 46)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.pressed.connect(_on_continue_pressed)
	column.add_child(_continue_button)


func _on_continue_pressed() -> void:
	close()
	confirmed.emit()
