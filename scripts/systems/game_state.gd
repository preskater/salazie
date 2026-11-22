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
		"sprout": "res://sprites/farm_48x48/singles/Crops/Crop_Corn_Sprout_48x48.png",
		"stage": "res://sprites/farm_48x48/singles/Crops/Crop_Corn_Stage_1_48x48.png",
		"ripe": "res://sprites/farm_48x48/singles/Crops/Crop_Corn_Ripe_48x48.png",
		"icon": "res://sprites/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Seed_Bags_Corn.png",
		"produce_icon": "res://sprites/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Crops_Corn.png",
	},
	"pumpkin": {
		"label": "Potiron",
		"seed_price": 6,
		"base_price": 16,
		"growth": 24.0,
		"sprout": "res://sprites/farm_48x48/singles/Crops/Crop_Pumpkin_Sprout_48x48.png",
		"stage": "res://sprites/farm_48x48/singles/Crops/Crop_Pumpkin_Stage_1_48x48.png",
		"ripe": "res://sprites/farm_48x48/singles/Crops/Crop_Pumpkin_Ripe_48x48.png",
		"icon": "res://sprites/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Seed_Bags_Pumpkin.png",
		"produce_icon": "res://sprites/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Crops_Pumpkin.png",
	},
	"tomato": {
		"label": "Tomate",
		"seed_price": 4,
		"base_price": 9,
		"growth": 16.0,
		"sprout": "res://sprites/farm_48x48/singles/Crops/Crop_Tomato_Sprout_48x48.png",
		"stage": "res://sprites/farm_48x48/singles/Crops/Crop_Tomato_Stage_1_48x48.png",
		"ripe": "res://sprites/farm_48x48/singles/Crops/Crop_Tomato_Ripe_48x48.png",
		"icon": "res://sprites/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Seed_Bags_Tomato.png",
		"produce_icon": "res://sprites/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Crops_Tomato.png",
	},
	"carrot": {
		"label": "Carotte",
		"seed_price": 3,
		"base_price": 7,
		"growth": 12.0,
		"sprout": "res://sprites/farm_48x48/singles/Crops/Crop_Carrot_Sprout_48x48.png",
		"stage": "res://sprites/farm_48x48/singles/Crops/Crop_Carrot_Stage_1_48x48.png",
		"ripe": "res://sprites/farm_48x48/singles/Crops/Crop_Carrot_Ripe_1_48x48.png",
		"icon": "res://sprites/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Seed_Bags_Carrot.png",
		"produce_icon": "res://sprites/farm_48x48/icons/Icons_32x32/Singles_Icons_32x32_Crops_Carrot.png",
	},
}
const CROP_ORDER := ["corn", "pumpkin", "tomato", "carrot"]

const START_MONEY := 30
const START_DAY := 1
const FARM_GENERATION := &"cultivateur"
const START_SEEDS := {"corn": 2, "pumpkin": 1, "tomato": 2, "carrot": 1}

var _money := START_MONEY
var _currency_id: StringName = &"gourde"
var _syncing_money := false
var day := START_DAY
var day_length := 60.0
var selected_seed := "corn"
var seeds: Dictionary = START_SEEDS.duplicate(true)
var produce := {}
var prices := {}
var previous_prices := {}
var playing := false
var farm_active := true
var _day_time := 0.0

## Wallet of the active generation. Falls back to the local mirror when the
## economy is disabled, but spending is refused in that case.
var money: int:
	get:
		if _uses_economy():
			return Economy.balance(_currency_id)
		return _money
	set(value):
		_money = maxi(0, value)
		if _uses_economy():
			Economy.set_balance(_currency_id, _money)


func _ready() -> void:
	_sync_currency()
	if _uses_economy():
		_money = Economy.balance(_currency_id)
	Economy.generation_changed.connect(_on_economy_generation_changed)
	Economy.balance_changed.connect(_on_economy_balance_changed)
	Economy.economy_enabled_changed.connect(_on_economy_enabled_changed)
	_reset_market_state()

func _process(delta: float) -> void:
	if not playing or not farm_active:
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
	if not prices.has(crop) or not previous_prices.has(crop):
		return 0
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
	if not _uses_economy():
		return
	if Economy.add_currency(_currency_id, amount):
		_money = Economy.balance(_currency_id)


func spend_money(amount: int) -> bool:
	if not _uses_economy():
		return false
	if not Economy.spend_currency(_currency_id, amount):
		return false
	_money = Economy.balance(_currency_id)
	return true


## Money plus the purchase value of what was bought with it.
func net_worth() -> int:
	if not _uses_economy():
		return money
	return money + Economy.owned_value(_currency_id)


func currency_id() -> StringName:
	return _currency_id


func currency_label() -> String:
	return Economy.currency_label(_currency_id)


func currency_symbol() -> String:
	return Economy.currency_symbol(_currency_id)


func format_money(amount: int) -> String:
	if not Economy.has_currency(_currency_id):
		return str(amount)
	return Economy.format_amount(_currency_id, amount)


## Every enabled wallet of the generation, for the HUD.
func format_wallets() -> String:
	var parts: PackedStringArray = []
	for definition: EconomyCurrency in Economy.currencies():
		if definition == null or not definition.enabled:
			continue
		parts.append(Economy.format_amount(definition.id, Economy.balance(definition.id)))
	if parts.is_empty():
		return format_money(money)
	return " · ".join(parts)


## One line for the pause menu and the Continue entry: where the player is and
## what they hold. The farm counts its own days; a generation without an
## economy (the maroon) shows no money at all.
func status_line() -> String:
	var parts: PackedStringArray = [Campaign.map_title()]
	if Campaign.current_map == 2:
		parts.append("Jour %d" % day)
	if is_economy_enabled():
		parts.append(format_wallets())
	return " · ".join(parts)


func is_economy_enabled() -> bool:
	return _uses_economy()

func add_seeds(crop: String, amount: int) -> void:
	if not CROPS.has(crop) or amount <= 0:
		return
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
	if not _uses_economy():
		return 0
	if not prices.has(crop):
		return 0
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
## A negative `starting_money` keeps the active generation's starting purse.
func reset(starting_money := -1) -> void:
	_syncing_money = true
	if Economy.has_generation(FARM_GENERATION):
		Economy.select_generation(FARM_GENERATION, false)
	Economy.reset()
	_sync_currency()
	if _uses_economy():
		if starting_money >= 0:
			money = starting_money
		_money = Economy.balance(_currency_id)
	else:
		money = START_MONEY if starting_money < 0 else maxi(0, starting_money)
	_syncing_money = false
	day = START_DAY
	selected_seed = "corn"
	seeds = START_SEEDS.duplicate(true)
	_day_time = 0.0
	_reset_market_state()
	_emit_state_changed()


## Replaces the purse without resetting the rest of the farm state.
func set_money(value: int) -> void:
	money = maxi(0, value)
	# With the economy on, the wallet already announced the new balance.
	if not _uses_economy():
		money_changed.emit(money)


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
		"economy": Economy.to_dict(),
	}


## Applies a save payload. Returns false and leaves the state untouched when invalid.
func from_dict(data: Dictionary) -> bool:
	if not _is_valid_state(data):
		return false
	_syncing_money = true
	if data.has("economy"):
		Economy.from_dict(data["economy"] as Dictionary)
	elif Economy.has_generation(FARM_GENERATION):
		Economy.select_generation(FARM_GENERATION, true)
	_sync_currency()
	money = maxi(0, _to_int(data.get("money"), START_MONEY))
	_syncing_money = false
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


## True when `from_dict()` would accept the payload. Lets the save system check
## every block before it applies any of them.
func can_restore(data: Dictionary) -> bool:
	return _is_valid_state(data)


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
	if data.has("economy"):
		if not (data["economy"] is Dictionary):
			return false
		if not Economy.can_restore(data["economy"] as Dictionary):
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


func _uses_economy() -> bool:
	return Economy.is_enabled() and Economy.has_currency(_currency_id)


func _sync_currency() -> void:
	var primary := Economy.primary_currency_id()
	_currency_id = primary if primary != &"" else &"gourde"


func _on_economy_generation_changed(_generation_id: StringName) -> void:
	var was_syncing := _syncing_money
	_syncing_money = true
	_sync_currency()
	_money = Economy.balance(_currency_id) if _uses_economy() else _money
	_syncing_money = was_syncing
	if not was_syncing:
		_emit_state_changed()


func _on_economy_balance_changed(currency_id: StringName, _amount: int) -> void:
	if currency_id != _currency_id or _syncing_money:
		return
	_money = Economy.balance(_currency_id)
	money_changed.emit(_money)


func _on_economy_enabled_changed(_enabled: bool) -> void:
	if _syncing_money:
		return
	money_changed.emit(money)
