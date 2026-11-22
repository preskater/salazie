extends Node
## Generation-aware economy: wallets, market offers and owned assets.
## Currencies, offers and the enabled flag come from an [EconomyConfig] resource.

signal generation_changed(generation_id: StringName)
signal economy_enabled_changed(enabled: bool)
signal balance_changed(currency_id: StringName, amount: int)
signal ownership_changed(asset_id: StringName, amount: int)
signal stock_changed(offer_id: StringName, remaining: int)
signal offer_purchased(offer: EconomyOffer, quantity: int)
signal offer_sold(offer: EconomyOffer, quantity: int, total: int)
signal trade_completed(give: Dictionary, receive: Dictionary)
signal transaction_failed(reason: StringName)

const CONFIG_PATH := "res://game_resources/economy/economy.tres"

var config: EconomyConfig

var _generation: EconomyGeneration
var _generation_id: StringName = &""
var _enabled := false
var _wallets: Dictionary[StringName, int] = {}
var _owned: Dictionary[StringName, int] = {}
var _stock: Dictionary[StringName, int] = {}


func _ready() -> void:
	reload_config(CONFIG_PATH)


## Loads an economy resource from disk and selects its default generation.
func reload_config(path: String) -> bool:
	var resource: Resource = load(path)
	if resource is EconomyConfig:
		config = resource as EconomyConfig
	else:
		push_error("Economy config %s is not an EconomyConfig resource." % path)
		config = EconomyConfig.new()
	return apply_config(config)


## Applies an already-built config. Tests and tools use this instead of reloading files.
func apply_config(new_config: EconomyConfig, generation_id: StringName = &"") -> bool:
	if new_config == null or new_config.generations.is_empty():
		return false
	config = new_config
	var target := generation_id if generation_id != &"" else new_config.default_generation
	return select_generation(target)


## Activates a generation and resets its wallets, stock and ownership.
func select_generation(generation_id: StringName, reset_state := true) -> bool:
	if config == null:
		return false
	var generation := config.find_generation(generation_id)
	if generation == null:
		if generation_id != &"":
			push_warning("Unknown economy generation '%s'." % generation_id)
		# A typo must not swap the running economy for the first one in the
		# file, which is the disabled one. The fallback only serves a start
		# with nothing selected yet.
		if _generation != null and config.find_generation(_generation_id) == _generation:
			return false
		generation = config.find_generation(config.default_generation)
		if generation == null:
			generation = _first_generation()
	if generation == null:
		return false
	var changed := generation.id != _generation_id
	_generation = generation
	_generation_id = generation.id
	_enabled = generation.enabled
	if reset_state:
		_reset_runtime_state()
	if changed:
		generation_changed.emit(_generation_id)
	economy_enabled_changed.emit(_enabled)
	_emit_state()
	return true


func reset() -> void:
	if _generation == null:
		return
	_enabled = _generation.enabled
	_reset_runtime_state()
	economy_enabled_changed.emit(_enabled)
	_emit_state()


## Runtime toggle. A generation disabled in the config can never be enabled.
func set_enabled(value: bool) -> void:
	var next := value and _generation != null and _generation.enabled
	if next == _enabled:
		return
	_enabled = next
	economy_enabled_changed.emit(_enabled)


func is_enabled() -> bool:
	return _enabled and _generation != null and _generation.enabled


func generation() -> EconomyGeneration:
	return _generation


func current_generation_id() -> StringName:
	return _generation_id


func currencies() -> Array[EconomyCurrency]:
	var result: Array[EconomyCurrency] = []
	if _generation == null:
		return result
	result.assign(_generation.currencies)
	return result


func currency(currency_id: StringName) -> EconomyCurrency:
	return _generation.find_currency(currency_id) if _generation != null else null


func has_currency(currency_id: StringName) -> bool:
	return currency(currency_id) != null


func has_generation(generation_id: StringName) -> bool:
	return config != null and config.find_generation(generation_id) != null


func is_currency_active(currency_id: StringName) -> bool:
	var definition := currency(currency_id)
	return definition != null and definition.enabled


func primary_currency_id() -> StringName:
	return _generation.primary_currency_id() if _generation != null else &""


func balance(currency_id: StringName) -> int:
	var amount: int = _wallets.get(currency_id, 0)
	return amount


func can_afford(currency_id: StringName, amount: int) -> bool:
	return amount >= 0 and is_enabled() and is_currency_active(currency_id) \
		and balance(currency_id) >= amount


func set_balance(currency_id: StringName, amount: int) -> bool:
	if not is_enabled() or not is_currency_active(currency_id):
		return false
	_apply_balance(currency_id, maxi(0, amount))
	return true


func add_currency(currency_id: StringName, amount: int) -> bool:
	if not is_enabled() or not is_currency_active(currency_id) or amount <= 0:
		return false
	_apply_balance(currency_id, balance(currency_id) + amount)
	return true


func spend_currency(currency_id: StringName, amount: int) -> bool:
	if not is_enabled() or not is_currency_active(currency_id) or amount <= 0:
		return false
	if not can_afford(currency_id, amount):
		return false
	_apply_balance(currency_id, balance(currency_id) - amount)
	return true


func offers(kind := -1) -> Array[EconomyOffer]:
	var result: Array[EconomyOffer] = []
	if _generation == null:
		return result
	for offer: EconomyOffer in _generation.offers:
		if offer == null:
			continue
		if kind >= 0 and int(offer.kind) != kind:
			continue
		result.append(offer)
	return result


func offer(offer_id: StringName) -> EconomyOffer:
	return _generation.find_offer(offer_id) if _generation != null else null


func offer_stock(offer_id: StringName) -> int:
	var remaining: int = _stock.get(offer_id, -1)
	return remaining


func owned_count(asset_id: StringName) -> int:
	var count: int = _owned.get(asset_id, 0)
	return count


## What the owned assets of the current generation cost to buy. Money turned
## into a barn is still wealth: prosperity goals and the heritage count it.
func owned_value(currency_id: StringName = &"") -> int:
	var total := 0
	for entry: EconomyOffer in offers():
		if currency_id != &"" and entry.currency_id != currency_id:
			continue
		total += owned_count(entry.asset_id()) * maxi(0, entry.price)
	return total


func can_buy(offer_id: StringName, quantity := 1) -> bool:
	return _check_buy(offer_id, quantity) == &""


func can_sell(offer_id: StringName, quantity := 1) -> bool:
	return _check_sell(offer_id, quantity) == &""


func buy(offer_id: StringName, quantity := 1) -> bool:
	var reason := _check_buy(offer_id, quantity)
	if reason != &"":
		transaction_failed.emit(reason)
		return false
	var target := offer(offer_id)
	var total := target.price * quantity
	if total > 0:
		_apply_balance(target.currency_id, balance(target.currency_id) - total)
	if _stock.has(offer_id) and _stock[offer_id] >= 0:
		_stock[offer_id] -= quantity
		stock_changed.emit(offer_id, _stock[offer_id])
	_grant(target.asset_id(), quantity)
	offer_purchased.emit(target, quantity)
	return true


## Sells owned units back at the offer's sell price. Returns the amount earned.
func sell(offer_id: StringName, quantity := 1) -> int:
	var reason := _check_sell(offer_id, quantity)
	if reason != &"":
		transaction_failed.emit(reason)
		return 0
	var target := offer(offer_id)
	var total := target.sell_price * quantity
	_revoke(target.asset_id(), quantity)
	if total > 0:
		_apply_balance(target.currency_id, balance(target.currency_id) + total)
	if _stock.has(offer_id) and _stock[offer_id] >= 0:
		_stock[offer_id] += quantity
		stock_changed.emit(offer_id, _stock[offer_id])
	offer_sold.emit(target, quantity, total)
	return total


## Atomic barter: each side is `{"currency": id, "amount": n}` or
## `{"asset": id, "amount": n}`. Nothing changes when one side is invalid.
func trade(give: Dictionary, receive: Dictionary) -> bool:
	if not is_enabled():
		transaction_failed.emit(&"economy_disabled")
		return false
	if _generation == null or not _generation.allow_trade:
		transaction_failed.emit(&"trade_disabled")
		return false
	# A trade has two sides: with only a "receive" it would hand out money or
	# assets for nothing.
	if give.is_empty() or receive.is_empty():
		transaction_failed.emit(&"empty_trade")
		return false
	var verdict := _check_side(give, true)
	if verdict == &"":
		verdict = _check_side(receive, false)
	if verdict != &"":
		transaction_failed.emit(verdict)
		return false
	_apply_side(give, true)
	_apply_side(receive, false)
	trade_completed.emit(give.duplicate(), receive.duplicate())
	return true


func currency_symbol(currency_id: StringName) -> String:
	var definition := currency(currency_id)
	if definition == null or definition.symbol.is_empty():
		return String(currency_id)
	return definition.symbol


func currency_label(currency_id: StringName) -> String:
	var definition := currency(currency_id)
	if definition == null or definition.label.is_empty():
		return String(currency_id)
	return definition.label


func format_amount(currency_id: StringName, amount: int) -> String:
	return "%d %s" % [amount, currency_symbol(currency_id)]


## Plain data only: no resources or engine objects.
func to_dict() -> Dictionary:
	return {
		"generation": String(_generation_id),
		"enabled": _enabled,
		"wallets": _to_string_keys(_wallets),
		"owned": _to_string_keys(_owned),
		"stock": _to_string_keys(_stock),
	}


func can_restore(data: Dictionary) -> bool:
	if not data.has("generation"):
		return false
	var generation_id := StringName(String(data.get("generation", "")))
	if config == null or config.find_generation(generation_id) == null:
		return false
	for key: String in ["wallets", "owned", "stock"]:
		if data.has(key) and not (data[key] is Dictionary):
			return false
	return true


## Applies a save payload. Returns false and leaves the state untouched when invalid.
func from_dict(data: Dictionary) -> bool:
	if not can_restore(data):
		return false
	select_generation(StringName(String(data["generation"])), true)
	if data.has("enabled"):
		set_enabled(bool(data["enabled"]))
	var wallets: Variant = data.get("wallets", {})
	if wallets is Dictionary:
		for key: Variant in (wallets as Dictionary):
			var currency_id := StringName(String(key))
			if has_currency(currency_id):
				_wallets[currency_id] = maxi(0, int((wallets as Dictionary)[key]))
	var owned: Variant = data.get("owned", {})
	if owned is Dictionary:
		for key: Variant in (owned as Dictionary):
			var asset_id := StringName(String(key))
			var count: Variant = (owned as Dictionary)[key]
			if _is_known_asset(asset_id) and (count is int or count is float):
				_owned[asset_id] = maxi(0, int(count))
	var stock: Variant = data.get("stock", {})
	if stock is Dictionary:
		for key: Variant in (stock as Dictionary):
			var offer_id := StringName(String(key))
			if offer(offer_id) != null:
				_stock[offer_id] = maxi(-1, int((stock as Dictionary)[key]))
	_emit_state()
	return true


func _first_generation() -> EconomyGeneration:
	for generation: EconomyGeneration in config.generations:
		if generation != null:
			return generation
	return null


func _reset_runtime_state() -> void:
	_wallets.clear()
	_owned.clear()
	_stock.clear()
	for currency_definition: EconomyCurrency in _generation.currencies:
		if currency_definition == null or currency_definition.id == &"":
			continue
		_wallets[currency_definition.id] = maxi(0, currency_definition.starting_balance)
	for market_offer: EconomyOffer in _generation.offers:
		if market_offer == null or market_offer.id == &"":
			continue
		_stock[market_offer.id] = market_offer.stock


func _emit_state() -> void:
	for currency_id: StringName in _wallets:
		balance_changed.emit(currency_id, _wallets[currency_id])
	for asset_id: StringName in _owned:
		ownership_changed.emit(asset_id, _owned[asset_id])
	for offer_id: StringName in _stock:
		stock_changed.emit(offer_id, _stock[offer_id])


func _apply_balance(currency_id: StringName, amount: int) -> void:
	_wallets[currency_id] = maxi(0, amount)
	balance_changed.emit(currency_id, _wallets[currency_id])


func _grant(asset_id: StringName, quantity: int) -> void:
	if asset_id == &"" or quantity <= 0:
		return
	var next := owned_count(asset_id) + quantity
	_owned[asset_id] = next
	ownership_changed.emit(asset_id, next)


func _revoke(asset_id: StringName, quantity: int) -> bool:
	if quantity <= 0 or owned_count(asset_id) < quantity:
		return false
	var next := owned_count(asset_id) - quantity
	if next <= 0:
		_owned.erase(asset_id)
	else:
		_owned[asset_id] = next
	ownership_changed.emit(asset_id, next)
	return true


func _check_buy(offer_id: StringName, quantity: int) -> StringName:
	if not is_enabled():
		return &"economy_disabled"
	if _generation == null or not _generation.allow_buy:
		return &"buy_disabled"
	if quantity <= 0:
		return &"invalid_quantity"
	# An offer without an id has no stock entry and grants nothing: it would
	# charge the price on every call.
	if offer_id == &"":
		return &"unknown_offer"
	var target := offer(offer_id)
	if target == null:
		return &"unknown_offer"
	if not is_currency_active(target.currency_id):
		return &"unknown_currency"
	var remaining := offer_stock(offer_id)
	if remaining >= 0 and remaining < quantity:
		return &"out_of_stock"
	if target.price > 0 and balance(target.currency_id) < target.price * quantity:
		return &"insufficient_funds"
	return &""


func _check_sell(offer_id: StringName, quantity: int) -> StringName:
	if not is_enabled():
		return &"economy_disabled"
	if _generation == null or not _generation.allow_sell:
		return &"sell_disabled"
	if quantity <= 0:
		return &"invalid_quantity"
	# An offer without an id has no stock entry and grants nothing: it would
	# charge the price on every call.
	if offer_id == &"":
		return &"unknown_offer"
	var target := offer(offer_id)
	if target == null:
		return &"unknown_offer"
	if not target.is_sellable():
		return &"not_sellable"
	if not is_currency_active(target.currency_id):
		return &"unknown_currency"
	if owned_count(target.asset_id()) < quantity:
		return &"not_owned"
	return &""


func _check_side(side: Dictionary, giving: bool) -> StringName:
	if side.is_empty():
		return &""
	if not side.has("amount") or side.has("currency") == side.has("asset"):
		return &"invalid_trade_entry"
	var amount := int(side["amount"])
	if amount <= 0:
		return &"invalid_trade_entry"
	if side.has("currency"):
		var currency_id := StringName(String(side["currency"]))
		if not is_currency_active(currency_id):
			return &"unknown_currency"
		if giving and balance(currency_id) < amount:
			return &"insufficient_funds"
		return &""
	var asset_id := StringName(String(side["asset"]))
	if asset_id == &"":
		return &"invalid_trade_entry"
	if giving and owned_count(asset_id) < amount:
		return &"not_owned"
	if not giving and not _is_known_asset(asset_id):
		return &"unknown_offer"
	return &""


## An asset exists when an offer of the current generation grants it.
func _is_known_asset(asset_id: StringName) -> bool:
	for entry: EconomyOffer in offers():
		if entry.asset_id() == asset_id:
			return true
	return false


func _apply_side(side: Dictionary, giving: bool) -> void:
	if side.is_empty():
		return
	var amount := int(side["amount"])
	if side.has("currency"):
		var currency_id := StringName(String(side["currency"]))
		var delta := -amount if giving else amount
		_apply_balance(currency_id, balance(currency_id) + delta)
		return
	var asset_id := StringName(String(side["asset"]))
	if giving:
		_revoke(asset_id, amount)
	else:
		_grant(asset_id, amount)


func _to_string_keys(source: Dictionary[StringName, int]) -> Dictionary:
	var result := {}
	for key: StringName in source:
		result[String(key)] = source[key]
	return result
