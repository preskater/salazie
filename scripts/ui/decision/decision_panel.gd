class_name DecisionPanel
extends CanvasLayer
## Final-generation decision. Choosing a plan is permanent for the save and
## completes the `choose_plan` task.

signal plan_chosen(plan_id: String)

const THEME := preload("res://themes/salazie/salazie_theme.tres")
const TEXT_MUTED := Color(0.43, 0.36, 0.29)
const ACCENT := Color(0.42, 0.22, 0.03)

const PLANS := [
	{
		"id": "forest",
		"label": "Protéger la forêt et la rivière",
		"description": "Refuser les coupes, restaurer les berges et préserver l'eau du cirque.",
	},
	{
		"id": "tourism",
		"label": "Développer un tourisme durable",
		"description": "Ouvrir des sentiers et des gîtes, avec des règles strictes pour la nature.",
	},
	{
		"id": "farms",
		"label": "Soutenir les familles paysannes",
		"description": "Aider les fermes, les marchés et les transports de la vallée.",
	},
]

var _panel: PanelContainer
var _buttons: VBoxContainer
var _paused_by_us := false


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()


func open() -> void:
	show()
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true
	var first_buttons := _buttons.find_children("*", "Button", true, false)
	if not first_buttons.is_empty():
		(first_buttons[0] as Button).grab_focus()


func choose_plan(plan_id: String) -> void:
	if Campaign.task_status("choose_plan") == Campaign.TaskStatus.DONE:
		# Never leave the game paused on a panel that cannot answer.
		close()
		return
	var valid := false
	for plan: Dictionary in PLANS:
		if String(plan.get("id", "")) == plan_id:
			valid = true
			break
	if not valid:
		return
	Campaign.set_choice("map3_plan", plan_id)
	Campaign.complete_task("choose_plan")
	close()
	plan_chosen.emit(plan_id)


func close() -> void:
	if _paused_by_us:
		get_tree().paused = false
		_paused_by_us = false
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		# `pause` shares the Escape key: without this the pause menu would open
		# on the same press.
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = THEME
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(880, 520)
	_panel.theme_type_variation = &"HudPanel"
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "L'avenir de Salazie"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", ACCENT)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choisissez le plan que vous défendrez devant le conseil."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", TEXT_MUTED)
	column.add_child(subtitle)

	var separator := HSeparator.new()
	column.add_child(separator)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	column.add_child(_buttons)

	for plan: Dictionary in PLANS:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var button := Button.new()
		button.name = "Plan_%s" % String(plan.get("id", ""))
		button.custom_minimum_size = Vector2(0, 46)
		button.text = String(plan.get("label", ""))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(choose_plan.bind(String(plan.get("id", ""))))
		box.add_child(button)
		var description := Label.new()
		description.text = String(plan.get("description", ""))
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 15)
		description.add_theme_color_override("font_color", TEXT_MUTED)
		box.add_child(description)
		_buttons.add_child(box)
