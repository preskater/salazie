extends Control
## Epilogue of Salazie. The text depends on the Map 3 plan and on the final
## council vote, which itself reflects the failures accumulated across the
## three generations.

const THEME := preload("res://themes/salazie/salazie_theme.tres")
const CREAM := Color(0.95, 0.90, 0.78)
const GOLD := Color(0.92, 0.72, 0.32)
const MUTED := Color(0.78, 0.74, 0.66)

var _title: Label
var _body: Label
var _stats: Label
var _button: Button


func _ready() -> void:
	# The ending is the last screen: whatever paused the tree on the way here,
	# the button back to the menu must answer.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	theme = THEME
	_build_ui()
	_title.text = "Salazie — Trois générations"
	_body.text = get_epilogue_text()
	_stats.text = get_stats_text()
	_button.grab_focus()


func get_epilogue_text() -> String:
	var plan := Campaign.get_choice("map3_plan", "farms")
	var mayor_ok := Campaign.task_status("become_mayor") == Campaign.TaskStatus.DONE
	var failures := Campaign.total_failure_events()
	var plan_text: String = {
		"forest": "Vous avez choisi de protéger la forêt et la rivière. Les sentiers se sont refermés sur les coupes, et l'eau du cirque a retrouvé sa clarté.",
		"tourism": "Vous avez choisi un tourisme durable. Les visiteurs viennent, mais les règles protègent les zones fragiles et les habitants gardent la maîtrise de leur vallée.",
		"farms": "Vous avez choisi de soutenir les familles paysannes. Les marchés de Salazie vivent à nouveau, et les récoltes nourrissent plusieurs générations.",
	}.get(plan, "Vous avez choisi de soutenir les familles paysannes.")
	var vote_text := ""
	if mayor_ok:
		vote_text = "Le conseil vous suit : vous devenez maire de Salazie. Votre nom rejoint celui des fondateurs, mais votre héritage sera jugé sur ce que vous laissez à la vallée."
	else:
		vote_text = "Le conseil ne vous suit pas. Vous restez simple citoyen, mais votre travail sur le terrain continue de porter ses fruits."
	var legacy_text := ""
	if failures == 0:
		legacy_text = "Trois générations sans faute : le chemin a été rude, mais votre famille a traversé le siècle sans rien perdre de sa dignité."
	elif failures <= 2:
		legacy_text = "Quelques échecs ont marqué le chemin, sans effacer ce qui a été construit. Salazie se souvient surtout de ce que vous avez réussi à préserver."
	else:
		legacy_text = "Les échecs se sont accumulés. Salazie est toujours debout, mais chaque génération a payé le prix des décisions prises avant elle."
	return "%s\n\n%s\n\n%s" % [plan_text, vote_text, legacy_text]


func get_stats_text() -> String:
	return "Héritage familial : %d G · Échecs enregistrés : %d" % [
		Campaign.heritage, Campaign.total_failure_events()]


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.06, 0.05, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 560)
	panel.theme_type_variation = &"HudPanel"
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", GOLD)
	column.add_child(_title)

	var separator := HSeparator.new()
	column.add_child(separator)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 18)
	_body.add_theme_color_override("font_color", CREAM)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)

	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.add_theme_font_size_override("font_size", 16)
	_stats.add_theme_color_override("font_color", MUTED)
	column.add_child(_stats)

	_button = Button.new()
	_button.text = "Retour au menu"
	_button.custom_minimum_size = Vector2(240, 48)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.pressed.connect(_on_return_pressed)
	column.add_child(_button)


func _on_return_pressed() -> void:
	SceneRouter.go_to_main_menu()
