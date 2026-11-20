extends CanvasLayer
## Survival HUD: food and water bars driven by SurvivalComponent signals.
## The HUD never polls the component; it binds once and reacts to signals.

const WARN_RATIO := 0.25
const FOOD_COLOR := Color(0.93, 0.55, 0.18)
const WATER_COLOR := Color(0.28, 0.62, 0.95)
const WARN_COLOR := Color(0.90, 0.18, 0.18)

@onready var food_bar: ProgressBar = %FoodBar
@onready var water_bar: ProgressBar = %WaterBar

var _survival: Node = null
var _food_fill: StyleBoxFlat
var _water_fill: StyleBoxFlat


func _ready() -> void:
	_survival = get_tree().get_first_node_in_group("survival")
	if _survival == null:
		# The player may be instanced after the HUD: retry once on the next frame.
		await get_tree().process_frame
		_survival = get_tree().get_first_node_in_group("survival")

	if _survival == null or not _survival.active:
		visible = false
		return

	_food_fill = _duplicate_fill(food_bar, FOOD_COLOR)
	_water_fill = _duplicate_fill(water_bar, WATER_COLOR)

	_survival.food_changed.connect(_on_food_changed)
	_survival.water_changed.connect(_on_water_changed)

	# Signals do not replay: push the current state once on connect.
	_on_food_changed(_survival.food, _survival.food_max)
	_on_water_changed(_survival.water, _survival.water_max)


func _duplicate_fill(bar: ProgressBar, color: Color) -> StyleBoxFlat:
	var fill := (bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate() as StyleBoxFlat
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	return fill


func _on_food_changed(current: float, maximum: float) -> void:
	_apply(food_bar, _food_fill, current, maximum, FOOD_COLOR)


func _on_water_changed(current: float, maximum: float) -> void:
	_apply(water_bar, _water_fill, current, maximum, WATER_COLOR)


func _apply(bar: ProgressBar, fill: StyleBoxFlat, current: float, maximum: float, color: Color) -> void:
	if maximum <= 0.0:
		return
	bar.max_value = maximum
	bar.value = current
	fill.bg_color = WARN_COLOR if current / maximum < WARN_RATIO else color
