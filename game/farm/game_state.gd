extends Node

signal money_changed(money: int)
signal inventory_changed()
signal prices_changed()
signal day_changed(day: int)
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
	},
	"pumpkin": {
		"label": "Potiron",
		"seed_price": 6,
		"base_price": 16,
		"growth": 24.0,
		"sprout": "res://assets/farm_48x48/singles/Crops/Crop_Pumpkin_Sprout_48x48.png",
		"stage": "res://assets/farm_48x48/singles/Crops/Crop_Pumpkin_Stage_1_48x48.png",
		"ripe": "res://assets/farm_48x48/singles/Crops/Crop_Pumpkin_Ripe_48x48.png",
	},
	"tomato": {
		"label": "Tomate",
		"seed_price": 4,
		"base_price": 9,
		"growth": 16.0,
		"sprout": "res://assets/farm_48x48/singles/Crops/Crop_Tomato_Sprout_48x48.png",
		"stage": "res://assets/farm_48x48/singles/Crops/Crop_Tomato_Stage_1_48x48.png",
		"ripe": "res://assets/farm_48x48/singles/Crops/Crop_Tomato_Ripe_48x48.png",
	},
	"carrot": {
		"label": "Carotte",
		"seed_price": 3,
		"base_price": 7,
		"growth": 12.0,
		"sprout": "res://assets/farm_48x48/singles/Crops/Crop_Carrot_Sprout_48x48.png",
		"stage": "res://assets/farm_48x48/singles/Crops/Crop_Carrot_Stage_1_48x48.png",
		"ripe": "res://assets/farm_48x48/singles/Crops/Crop_Carrot_Ripe_1_48x48.png",
	},
}
const CROP_ORDER := ["corn", "pumpkin", "tomato", "carrot"]

var money := 30
var day := 1
var day_length := 60.0
var selected_seed := "corn"
var seeds := {"corn": 2, "pumpkin": 1, "tomato": 2, "carrot": 1}
var produce := {}
var prices := {}
var previous_prices := {}
var _day_time := 0.0

func _ready() -> void:
	for crop: String in CROP_ORDER:
		prices[crop] = int(CROPS[crop]["base_price"])
		previous_prices[crop] = prices[crop]
		produce[crop] = 0

func _process(delta: float) -> void:
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
