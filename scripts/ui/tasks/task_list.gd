class_name TaskList
extends CanvasLayer
## Per-generation task list. The compact panel stays visible; `T` (or the
## gamepad Back button) expands the full list, including failures and the
## generation result once the map is resolved.

const THEME := preload("res://themes/salazie/salazie_theme.tres")
const TEXT_DARK := Color(0.22, 0.14, 0.08)
const TEXT_MUTED := Color(0.43, 0.36, 0.29)
const POSITIVE := Color(0.12, 0.42, 0.16)
const NEGATIVE := Color(0.62, 0.14, 0.1)
const ACCENT := Color(0.42, 0.22, 0.03)

var _panel: PanelContainer
var _compact_label: Label
var _expanded_box: VBoxContainer
var _rows_box: VBoxContainer
var _result_label: Label
var _expanded := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	Campaign.task_status_changed.connect(_on_task_status_changed)
	Campaign.map_resolved.connect(_on_map_resolved)
	Campaign.map_unresolved.connect(_on_map_unresolved)
	Campaign.map_changed.connect(_on_map_changed)
	Campaign.choices_changed.connect(_on_choices_changed)
	refresh()
	if Campaign.is_map_resolved():
		_expanded = true
		_apply_expanded()


func refresh() -> void:
	if _compact_label == null:
		return
	var summary := Campaign.map_summary()
	var done := int(summary.get("done", 0))
	var failed := int(summary.get("failed", 0))
	var pending := int(summary.get("pending", 0))
	if pending == 0:
		_compact_label.text = "Tâches — %d réussies · %d échouées · carte terminée (%s)" % [
			done, failed, InputHints.label(&"toggle_tasks")]
	else:
		_compact_label.text = "Tâches — %d faites · %d échouées · %d en cours (%s)" % [
			done, failed, pending, InputHints.label(&"toggle_tasks")]
	_rebuild_rows(summary)
	_update_result(summary)
	_apply_expanded()


func is_expanded() -> bool:
	return _expanded


func get_compact_text() -> String:
	return _compact_label.text if _compact_label != null else ""


func get_result_text() -> String:
	return _result_label.text if _result_label != null else ""


func set_expanded(value: bool) -> void:
	_expanded = value
	_apply_expanded()


func get_row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	if _rows_box == null:
		return texts
	for child: Node in _rows_box.get_children():
		if child is Label:
			texts.append((child as Label).text)
	return texts


func _build_ui() -> void:
	var root := Control.new()
	root.name = "TaskListRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = THEME
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "TaskPanel"
	_panel.theme_type_variation = &"HudPanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -560.0
	_panel.offset_right = -16.0
	_panel.offset_top = 100.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	_compact_label = Label.new()
	_compact_label.name = "CompactLabel"
	_compact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compact_label.add_theme_color_override("font_color", TEXT_DARK)
	_compact_label.add_theme_font_size_override("font_size", 17)
	column.add_child(_compact_label)

	_expanded_box = VBoxContainer.new()
	_expanded_box.name = "ExpandedBox"
	_expanded_box.add_theme_constant_override("separation", 4)
	_expanded_box.visible = false
	column.add_child(_expanded_box)

	var separator := HSeparator.new()
	_expanded_box.add_child(separator)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.add_theme_constant_override("separation", 3)
	_expanded_box.add_child(_rows_box)

	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.add_theme_color_override("font_color", ACCENT)
	_result_label.add_theme_font_size_override("font_size", 16)
	_expanded_box.add_child(_result_label)


func _rebuild_rows(summary: Dictionary) -> void:
	if _rows_box == null:
		return
	for child: Node in _rows_box.get_children():
		child.free()
	var tasks: Dictionary = summary.get("tasks", {})
	var order: Array = Campaign.TASKS.get(Campaign.current_map, [])
	for definition: Dictionary in order:
		var task_id := String(definition.get("id", ""))
		if not tasks.has(task_id):
			continue
		var details: Dictionary = tasks[task_id]
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 15)
		var status := int(details.get("status", Campaign.TaskStatus.PENDING))
		var label := String(details.get("label", task_id))
		var optional := bool(details.get("optional", false))
		var failures := int((details.get("failures", []) as Array).size())
		match status:
			Campaign.TaskStatus.DONE:
				row.text = "✓ " + label
				if failures > 0:
					row.text += " (%d échec%s)" % [failures, "s" if failures > 1 else ""]
				row.add_theme_color_override("font_color", POSITIVE)
			Campaign.TaskStatus.FAILED:
				var reason := ""
				var failure_list: Array = details.get("failures", [])
				if not failure_list.is_empty():
					reason = String((failure_list[-1] as Dictionary).get("reason", ""))
				row.text = "✗ " + label
				if not reason.is_empty():
					row.text += " — " + reason
				if bool(details.get("retryable", false)):
					row.text += " [Réessayer]"
				row.add_theme_color_override("font_color", NEGATIVE)
			_:
				var progress := int(details.get("progress", 0))
				var target := int(details.get("target", 1))
				row.text = "○ " + label
				if target > 1:
					row.text += " (%d/%d)" % [progress, target]
				row.add_theme_color_override("font_color", TEXT_DARK)
		if optional:
			row.text += " (optionnel)"
		_rows_box.add_child(row)


func _update_result(summary: Dictionary) -> void:
	if _result_label == null:
		return
	if int(summary.get("pending", 0)) > 0:
		_result_label.text = "Objectif en cours : %s" % _current_hint(summary)
		_result_label.add_theme_color_override("font_color", TEXT_MUTED)
		return
	var done := int(summary.get("done", 0))
	var failed := int(summary.get("failed", 0))
	var rank := String(summary.get("rank", "partial"))
	var rank_text: String = {
		"full": "Génération accomplie",
		"partial": "Génération partielle",
		"poor": "Génération difficile",
	}.get(rank, "Génération terminée")
	_result_label.text = "%s — %d réussie%s · %d échouée%s\n%s" % [
		rank_text,
		done, "s" if done > 1 else "",
		failed, "s" if failed > 1 else "",
		Campaign.next_map_label(),
	]
	_result_label.add_theme_color_override("font_color", ACCENT)


func _current_hint(summary: Dictionary) -> String:
	var tasks: Dictionary = summary.get("tasks", {})
	var order: Array = Campaign.TASKS.get(Campaign.current_map, [])
	for definition: Dictionary in order:
		var task_id := String(definition.get("id", ""))
		if not tasks.has(task_id):
			continue
		if int((tasks[task_id] as Dictionary).get("status", 0)) == Campaign.TaskStatus.PENDING:
			return InputHints.format(String(definition.get("hint", definition.get("label", ""))))
	return "Terminez les tâches restantes."


func _apply_expanded() -> void:
	if _expanded_box != null:
		_expanded_box.visible = _expanded


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("toggle_tasks"):
		_expanded = not _expanded
		_apply_expanded()
		get_viewport().set_input_as_handled()


func _on_task_status_changed(_map_id: int, _task_id: String, _status: int) -> void:
	refresh()


func _on_map_resolved(map_id: int, _summary: Dictionary) -> void:
	if map_id != Campaign.current_map:
		return
	_expanded = true
	refresh()


func _on_map_unresolved(map_id: int) -> void:
	if map_id != Campaign.current_map:
		return
	refresh()


func _on_map_changed(_map_id: int) -> void:
	_expanded = false
	refresh()


func _on_choices_changed() -> void:
	refresh()
