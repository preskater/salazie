extends Node

signal money_changed(money: int)
signal inventory_changed()
signal prices_changed()
signal day_changed(day: int)
signal day_advanced(day: int)
signal seed_changed(crop: String)
signal plot_prepared()
signal crop_planted(crop: String)
signal crop_harvested(crop: String, amount: int)
signal produce_sold(crop: String, amount: int, total: int)
signal dialogue_requested(speaker: String, text: String)
signal notification_requested(text: String)

const CROPS := {
	"corn": {
		"label": "Maïs",
		"seed_price": 4,
		"base_price": 10,
		"growth": 18.0,
		"sprout": "res://assets/farm_48x48/singles/Crops/Crop_Corn_Sprout_48x48.png",
		"stage": "res://assets/farm_48x48/singles/Crops/Crop_Corn_Stage_1_48x48.png",
		"ripe": "res://assets/farm_48x48/singles/Crops/Crop_Corn_Ripe_48x48.png",
		"icon": "res://assets/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Seed_Bags_Corn.png",
		"produce_icon": "res://assets/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Crops_Corn.png",
	},
	"pumpkin": {
		"label": "Potiron",
		"seed_price": 6,
		"base_price": 16,
		"growth": 24.0,
		"sprout": "res://assets/farm_48x48/singles/Crops/Crop_Pumpkin_Sprout_48x48.png",
		"stage": "res://assets/farm_48x48/singles/Crops/Crop_Pumpkin_Stage_1_48x48.png",
		"ripe": "res://assets/farm_48x48/singles/Crops/Crop_Pumpkin_Ripe_48x48.png",
		"icon": "res://assets/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Seed_Bags_Pumpkin.png",
		"produce_icon": "res://assets/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Crops_Pumpkin.png",
	},
	"tomato": {
		"label": "Tomate",
		"seed_price": 4,
		"base_price": 9,
		"growth": 16.0,
		"sprout": "res://assets/farm_48x48/singles/Crops/Crop_Tomato_Sprout_48x48.png",
		"stage": "res://assets/farm_48x48/singles/Crops/Crop_Tomato_Stage_1_48x48.png",
		"ripe": "res://assets/farm_48x48/singles/Crops/Crop_Tomato_Ripe_48x48.png",
		"icon": "res://assets/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Seed_Bags_Tomato.png",
		"produce_icon": "res://assets/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Crops_Tomato.png",
	},
	"carrot": {
		"label": "Carotte",
		"seed_price": 3,
		"base_price": 7,
		"growth": 12.0,
		"sprout": "res://assets/farm_48x48/singles/Crops/Crop_Carrot_Sprout_48x48.png",
		"stage": "res://assets/farm_48x48/singles/Crops/Crop_Carrot_Stage_1_48x48.png",
		"ripe": "res://assets/farm_48x48/singles/Crops/Crop_Carrot_Ripe_1_48x48.png",
		"icon": "res://assets/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Seed_Bags_Carrot.png",
		"produce_icon": "res://assets/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Crops_Carrot.png",
	},
}
const CROP_ORDER := ["corn", "pumpkin", "tomato", "carrot"]

const START_MONEY := 30
const START_DAY := 1
const START_SEEDS := {"corn": 2, "pumpkin": 1, "tomato": 2, "carrot": 1}

var money := START_MONEY
var day := START_DAY
var day_length := 60.0
var selected_seed := "corn"
var seeds: Dictionary = START_SEEDS.duplicate(true)
var produce := {}
var prices := {}
var previous_prices := {}
var playing := false
var _day_time := 0.0

func _ready() -> void:
	_reset_market_state()

func _process(delta: float) -> void:
	if not playing:
		return
	_day_time += delta
	if _day_time >= day_length:
		_day_time -= day_length
		_advance_day()

func _advance_day() -> void:
	day += 1
	previous_prices = prices.duplicate()
	for crop: String in CROP_ORDER:
		var base := float(CROPS[crop]["base_price"])
		var change := randf_range(-0.25, 0.25)
		prices[crop] = maxi(1, roundi(base * (1.0 + change)))
	prices_changed.emit()
	day_changed.emit(day)
	day_advanced.emit(day)

func price_trend(crop: String) -> int:
	return signi(int(prices[crop]) - int(previous_prices[crop]))

func select_seed(crop: String) -> void:
	if not CROPS.has(crop) or selected_seed == crop:
		return
	selected_seed = crop
	seed_changed.emit(crop)

func seed_count(crop: String) -> int:
	return int(seeds.get(crop, 0))

func produce_count(crop: String) -> int:
	return int(produce.get(crop, 0))

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true

func add_seeds(crop: String, amount: int) -> void:
	seeds[crop] = seed_count(crop) + amount
	inventory_changed.emit()

func consume_seed(crop: String) -> bool:
	if seed_count(crop) <= 0:
		return false
	seeds[crop] = seed_count(crop) - 1
	inventory_changed.emit()
	return true

func buy_seed(crop: String) -> bool:
	if not CROPS.has(crop):
		return false
	var cost := int(CROPS[crop]["seed_price"])
	if not spend_money(cost):
		return false
	add_seeds(crop, 1)
	return true

func add_produce(crop: String, amount: int) -> void:
	produce[crop] = produce_count(crop) + amount
	inventory_changed.emit()

func sell(crop: String, amount: int) -> int:
	var have := produce_count(crop)
	amount = mini(amount, have)
	if amount <= 0:
		return 0
	produce[crop] = have - amount
	var total := int(prices[crop]) * amount
	add_money(total)
	inventory_changed.emit()
	produce_sold.emit(crop, amount, total)
	return total

func notify_plot_prepared() -> void:
	plot_prepared.emit()

func notify_crop_planted(crop: String) -> void:
	crop_planted.emit(crop)

func notify_crop_harvested(crop: String, amount: int) -> void:
	crop_harvested.emit(crop, amount)

func announce(text: String) -> void:
	notification_requested.emit(text)

func show_dialogue(speaker: String, text: String) -> void:
	dialogue_requested.emit(speaker, text)


## Restarts the farm economy from its initial values without reloading the scene.
func reset() -> void:
	money = START_MONEY
	day = START_DAY
	selected_seed = "corn"
	seeds = START_SEEDS.duplicate(true)
	_day_time = 0.0
	_reset_market_state()
	_emit_state_changed()


## Plain data only: no nodes, resources or engine objects.
func to_dict() -> Dictionary:
	return {
		"money": money,
		"day": day,
		"day_time": _day_time,
		"selected_seed": selected_seed,
		"seeds": seeds.duplicate(true),
		"produce": produce.duplicate(true),
		"prices": prices.duplicate(true),
		"previous_prices": previous_prices.duplicate(true),
	}


## Applies a save payload. Returns false and leaves the state untouched when invalid.
func from_dict(data: Dictionary) -> bool:
	if not _is_valid_state(data):
		return false
	money = maxi(0, _to_int(data.get("money"), START_MONEY))
	day = maxi(1, _to_int(data.get("day"), START_DAY))
	_day_time = clampf(_to_float(data.get("day_time"), 0.0), 0.0, day_length)
	var saved_seed := String(data.get("selected_seed", "corn"))
	selected_seed = saved_seed if CROPS.has(saved_seed) else "corn"
	seeds = _read_counts(data.get("seeds", {}))
	produce = _read_counts(data.get("produce", {}))
	prices = _read_prices(data.get("prices", {}))
	previous_prices = _read_prices(data.get("previous_prices", prices))
	_emit_state_changed()
	return true


func _reset_market_state() -> void:
	produce = _default_counts()
	prices = _default_prices()
	previous_prices = prices.duplicate()


func _default_counts() -> Dictionary:
	var result := {}
	for crop: String in CROP_ORDER:
		result[crop] = 0
	return result


func _default_prices() -> Dictionary:
	var result := {}
	for crop: String in CROP_ORDER:
		result[crop] = int(CROPS[crop]["base_price"])
	return result


func _read_counts(raw: Variant) -> Dictionary:
	var result := _default_counts()
	if not (raw is Dictionary):
		return result
	var source := raw as Dictionary
	for crop: String in CROP_ORDER:
		result[crop] = maxi(0, _to_int(source.get(crop), 0))
	return result


func _read_prices(raw: Variant) -> Dictionary:
	var result := _default_prices()
	if not (raw is Dictionary):
		return result
	var source := raw as Dictionary
	for crop: String in CROP_ORDER:
		result[crop] = maxi(1, _to_int(source.get(crop), int(CROPS[crop]["base_price"])))
	return result


func _emit_state_changed() -> void:
	money_changed.emit(money)
	inventory_changed.emit()
	prices_changed.emit()
	day_changed.emit(day)
	seed_changed.emit(selected_seed)


func _is_valid_state(data: Dictionary) -> bool:
	if not data.has("money") or not _is_number(data["money"]):
		return false
	if not data.has("day") or not _is_number(data["day"]):
		return false
	if data.has("day_time") and not _is_number(data["day_time"]):
		return false
	if data.has("selected_seed"):
		var seed_type := typeof(data["selected_seed"])
		if seed_type != TYPE_STRING and seed_type != TYPE_STRING_NAME:
			return false
	for key: String in ["seeds", "produce", "prices"]:
		if not data.has(key) or not (data[key] is Dictionary):
			return false
	if data.has("previous_prices") and not (data["previous_prices"] is Dictionary):
		return false
	return true


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _to_int(value: Variant, fallback: int) -> int:
	if _is_number(value):
		return int(value)
	return fallback


func _to_float(value: Variant, fallback: float) -> float:
	if _is_number(value):
		return float(value)
	return fallback
