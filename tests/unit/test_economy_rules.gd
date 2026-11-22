extends GdUnitTestSuite
## Rules of the economy that the market relies on: why a transaction is refused,
## what a sale gives back, barter in both directions and what a save restores.
## Each test drives its own economy node, so the autoload is left alone.

const ECONOMY_SCRIPT := preload("res://scripts/systems/economy/economy.gd")
const SHIPPED_CONFIG := "res://game_resources/economy/economy.tres"

var _failures: Array[String] = []


func before_test() -> void:
	_failures.clear()


func _currency(id: StringName, label: String, symbol: String, start: int,
		enabled := true) -> EconomyCurrency:
	var currency := EconomyCurrency.new()
	currency.id = id
	currency.label = label
	currency.symbol = symbol
	currency.starting_balance = start
	currency.enabled = enabled
	return currency


func _offer(id: StringName, currency_id: StringName, price: int, sell_price := -1,
		stock := -1, grant_id: StringName = &"",
		kind: EconomyOffer.Kind = EconomyOffer.Kind.ITEM) -> EconomyOffer:
	var offer := EconomyOffer.new()
	offer.id = id
	offer.label = String(id).capitalize()
	offer.kind = kind
	offer.currency_id = currency_id
	offer.price = price
	offer.sell_price = sell_price
	offer.stock = stock
	offer.grant_id = grant_id
	return offer


## 100 G, 3 J and a retired currency; a barn in limited stock, land paid in
## tokens, a medal that cannot be sold back, a relic priced in the retired
## currency and a free leaflet.
func _generation(id: StringName = &"test") -> EconomyGeneration:
	var generation := EconomyGeneration.new()
	generation.id = id
	generation.label = "Test"
	var currencies: Array[EconomyCurrency] = [
		_currency(&"gourde", "Gourde", "G", 100),
		_currency(&"token", "Jeton", "J", 3),
		_currency(&"piastre", "Piastre", "P", 50, false),
	]
	generation.currencies = currencies
	var offers: Array[EconomyOffer] = [
		_offer(&"barn", &"gourde", 40, 20, 1, &"barn_asset", EconomyOffer.Kind.BUILDING),
		_offer(&"plot", &"token", 2, 1, -1, &"", EconomyOffer.Kind.SLOT),
		_offer(&"medal", &"gourde", 5),
		_offer(&"relic", &"piastre", 1, 1),
		_offer(&"leaflet", &"gourde", 0, 0),
	]
	generation.offers = offers
	return generation


func _config(generations: Array[EconomyGeneration],
		default_generation: StringName = &"test") -> EconomyConfig:
	var config := EconomyConfig.new()
	config.generations = generations
	config.default_generation = default_generation
	return config


func _bare_economy() -> Node:
	var economy: Node = auto_free(ECONOMY_SCRIPT.new())
	economy.transaction_failed.connect(
		func(reason: StringName) -> void: _failures.append(String(reason)))
	return economy


func _economy(generation: EconomyGeneration = null) -> Node:
	var economy := _bare_economy()
	var generations: Array[EconomyGeneration] = [
		generation if generation != null else _generation()]
	assert_bool(economy.apply_config(_config(generations, generations[0].id))).is_true()
	return economy


func _reasons() -> String:
	return ", ".join(PackedStringArray(_failures))


# --- Shipped data ------------------------------------------------------------

func test_the_shipped_economy_is_consistent() -> void:
	var config := load(SHIPPED_CONFIG) as EconomyConfig
	assert_object(config).is_not_null()
	if config == null:
		return

	var generation_ids := {}
	for generation: EconomyGeneration in config.generations:
		assert_object(generation).is_not_null()
		assert_str(String(generation.id)).is_not_empty()
		assert_bool(generation_ids.has(generation.id)).override_failure_message(
			"Generation '%s' is declared twice" % generation.id).is_false()
		generation_ids[generation.id] = true

		var currency_ids := {}
		for currency: EconomyCurrency in generation.currencies:
			assert_object(currency).is_not_null()
			assert_str(String(currency.id)).is_not_empty()
			assert_str(currency.symbol).is_not_empty()
			assert_int(currency.starting_balance).is_greater_equal(0)
			assert_bool(currency_ids.has(currency.id)).override_failure_message(
				"Currency '%s' is declared twice in '%s'" % [currency.id, generation.id]).is_false()
			currency_ids[currency.id] = true

		var offer_ids := {}
		for offer: EconomyOffer in generation.offers:
			assert_object(offer).is_not_null()
			var where := "'%s' in '%s'" % [offer.id, generation.id]
			assert_str(String(offer.id)).is_not_empty()
			assert_str(offer.label).is_not_empty()
			assert_bool(offer_ids.has(offer.id)).override_failure_message(
				"Offer %s is declared twice" % where).is_false()
			offer_ids[offer.id] = true
			assert_bool(currency_ids.has(offer.currency_id)).override_failure_message(
				"Offer %s is priced in '%s', which the generation does not have"
					% [where, offer.currency_id]).is_true()
			assert_int(offer.price).override_failure_message(
				"Offer %s has no price" % where).is_greater(0)
			assert_int(offer.sell_price).override_failure_message(
				"Offer %s sells back for %d, not below its price of %d"
					% [where, offer.sell_price, offer.price]).is_less(offer.price)

	assert_bool(generation_ids.has(config.default_generation)).override_failure_message(
		"The default generation '%s' does not exist" % config.default_generation).is_true()


# --- Configuration -----------------------------------------------------------

func test_an_economy_without_a_generation_holds_nothing_and_refuses_everything() -> void:
	var economy := _bare_economy()
	var enabled_changes: Array[bool] = []
	economy.economy_enabled_changed.connect(
		func(enabled: bool) -> void: enabled_changes.append(enabled))

	economy.reset()
	economy.set_enabled(true)

	assert_array(enabled_changes).is_empty()
	assert_bool(economy.is_enabled()).is_false()
	assert_object(economy.generation()).is_null()
	assert_array(economy.currencies()).is_empty()
	assert_array(economy.offers()).is_empty()
	assert_object(economy.currency(&"gourde")).is_null()
	assert_object(economy.offer(&"barn")).is_null()
	assert_str(String(economy.primary_currency_id())).is_empty()
	assert_bool(economy.has_generation(&"test")).is_false()
	assert_bool(economy.select_generation(&"test")).is_false()
	assert_bool(economy.can_restore({"generation": "test"})).is_false()
	assert_bool(economy.buy(&"barn")).is_false()
	assert_int(economy.sell(&"barn")).is_equal(0)
	assert_bool(economy.trade({"currency": "gourde", "amount": 1}, {})).is_false()
	assert_str(_reasons()).is_equal("economy_disabled, economy_disabled, economy_disabled")


func test_a_config_without_a_usable_generation_is_refused() -> void:
	var economy := _economy()
	var no_generation: Array[EconomyGeneration] = []
	var only_a_hole: Array[EconomyGeneration] = [null]

	assert_bool(economy.apply_config(null)).is_false()
	assert_bool(economy.apply_config(_config(no_generation))).is_false()
	assert_str(String(economy.current_generation_id())).is_equal("test")
	assert_int(economy.balance(&"gourde")).is_equal(100)

	assert_bool(economy.apply_config(_config(only_a_hole))).is_false()
	assert_str(String(economy.current_generation_id())).is_equal("test")


func test_an_unknown_generation_falls_back_to_the_first_one() -> void:
	var economy := _bare_economy()
	var second := _generation(&"second")
	var generations: Array[EconomyGeneration] = [null, _generation(&"first"), second]
	var selected: Array[String] = []
	economy.generation_changed.connect(
		func(generation_id: StringName) -> void: selected.append(String(generation_id)))

	assert_bool(economy.apply_config(_config(generations, &""))).is_true()
	assert_str(String(economy.current_generation_id())).is_equal("first")

	assert_bool(economy.apply_config(_config(generations, &"first"), &"second")).is_true()
	assert_object(economy.generation()).is_same(second)
	assert_bool(economy.has_generation(&"second")).is_true()
	assert_bool(economy.has_generation(&"third")).is_false()

	assert_bool(economy.select_generation(&"third")).is_true()
	assert_str(String(economy.current_generation_id())).is_equal("first")
	assert_str(", ".join(PackedStringArray(selected))).is_equal("first, second, first")


func test_selecting_the_active_generation_again_resets_it_without_announcing_a_change() -> void:
	var economy := _economy()
	var selected: Array[String] = []
	economy.generation_changed.connect(
		func(generation_id: StringName) -> void: selected.append(String(generation_id)))
	economy.buy(&"barn")

	assert_bool(economy.select_generation(&"test", false)).is_true()
	assert_int(economy.owned_count(&"barn_asset")).is_equal(1)
	assert_int(economy.balance(&"gourde")).is_equal(60)

	assert_bool(economy.select_generation(&"test")).is_true()
	assert_int(economy.owned_count(&"barn_asset")).is_equal(0)
	assert_int(economy.balance(&"gourde")).is_equal(100)
	assert_int(economy.offer_stock(&"barn")).is_equal(1)
	assert_array(selected).is_empty()


func test_entries_without_an_id_get_no_wallet_and_no_stock() -> void:
	var generation := _generation()
	generation.currencies.append(null)
	generation.currencies.append(_currency(&"", "Sans nom", "?", 10))
	generation.offers.append(null)
	generation.offers.append(_offer(&"", &"gourde", 1, -1, 4))
	var economy := _economy(generation)

	var saved: Dictionary = economy.to_dict()

	assert_array((saved["wallets"] as Dictionary).keys()).contains_exactly_in_any_order(
		["gourde", "token", "piastre"])
	assert_array((saved["stock"] as Dictionary).keys()).contains_exactly_in_any_order(
		["barn", "plot", "medal", "relic", "leaflet"])
	# The hole in the catalogue is not listed either.
	assert_int(economy.offers().size()).is_equal(6)
	assert_int(economy.currencies().size()).is_equal(5)


func test_reset_gives_back_the_starting_purse_and_stock() -> void:
	var economy := _economy()
	economy.buy(&"barn")
	economy.set_enabled(false)
	var balances := {}
	economy.balance_changed.connect(
		func(currency_id: StringName, amount: int) -> void: balances[String(currency_id)] = amount)

	economy.reset()

	assert_bool(economy.is_enabled()).is_true()
	assert_int(economy.balance(&"gourde")).is_equal(100)
	assert_int(economy.owned_count(&"barn_asset")).is_equal(0)
	assert_int(economy.offer_stock(&"barn")).is_equal(1)
	assert_int(int(balances.get("gourde", -1))).is_equal(100)
	assert_int(int(balances.get("token", -1))).is_equal(3)


# --- Currencies --------------------------------------------------------------

func test_the_first_enabled_currency_is_the_primary_one() -> void:
	var generation := _generation()
	generation.currencies[0].enabled = false
	var economy := _economy(generation)

	assert_str(String(economy.primary_currency_id())).is_equal("token")

	generation.currencies[1].enabled = false
	assert_str(String(economy.primary_currency_id())).is_empty()


func test_a_retired_currency_cannot_be_used() -> void:
	var economy := _economy()

	assert_bool(economy.has_currency(&"piastre")).is_true()
	assert_bool(economy.is_currency_active(&"piastre")).is_false()
	assert_bool(economy.is_currency_active(&"franc")).is_false()
	assert_bool(economy.can_afford(&"piastre", 1)).is_false()
	assert_bool(economy.set_balance(&"piastre", 10)).is_false()
	assert_bool(economy.add_currency(&"piastre", 10)).is_false()
	assert_bool(economy.spend_currency(&"piastre", 10)).is_false()
	assert_bool(economy.set_balance(&"franc", 10)).is_false()
	assert_int(economy.balance(&"piastre")).is_equal(50)
	assert_int(economy.balance(&"franc")).is_equal(0)


func test_wallets_never_go_below_zero() -> void:
	var economy := _economy()

	assert_bool(economy.add_currency(&"gourde", 0)).is_false()
	assert_bool(economy.add_currency(&"gourde", -5)).is_false()
	assert_bool(economy.spend_currency(&"gourde", 0)).is_false()
	assert_bool(economy.spend_currency(&"gourde", 101)).is_false()
	assert_int(economy.balance(&"gourde")).is_equal(100)

	assert_bool(economy.spend_currency(&"gourde", 100)).is_true()
	assert_int(economy.balance(&"gourde")).is_equal(0)
	assert_bool(economy.add_currency(&"gourde", 7)).is_true()
	assert_int(economy.balance(&"gourde")).is_equal(7)
	assert_bool(economy.set_balance(&"gourde", -30)).is_true()
	assert_int(economy.balance(&"gourde")).is_equal(0)
	assert_bool(economy.can_afford(&"gourde", 0)).is_true()
	assert_bool(economy.can_afford(&"gourde", 1)).is_false()


func test_a_switched_off_economy_freezes_the_wallets() -> void:
	var economy := _economy()
	var enabled_changes: Array[bool] = []
	economy.economy_enabled_changed.connect(
		func(enabled: bool) -> void: enabled_changes.append(enabled))

	economy.set_enabled(true)
	assert_array(enabled_changes).is_empty()

	economy.set_enabled(false)
	assert_bool(economy.set_balance(&"gourde", 5)).is_false()
	assert_bool(economy.add_currency(&"gourde", 5)).is_false()
	assert_bool(economy.spend_currency(&"gourde", 5)).is_false()
	assert_bool(economy.can_afford(&"gourde", 5)).is_false()
	assert_int(economy.balance(&"gourde")).is_equal(100)

	economy.set_enabled(true)
	assert_bool(economy.spend_currency(&"gourde", 5)).is_true()
	assert_array(enabled_changes).is_equal([false, true])


func test_amounts_are_written_with_the_currency_symbol() -> void:
	var generation := _generation()
	generation.currencies.append(_currency(&"troc", "", "", 0))
	var economy := _economy(generation)

	assert_str(economy.format_amount(&"gourde", 12)).is_equal("12 G")
	assert_str(economy.currency_label(&"gourde")).is_equal("Gourde")
	# A currency without a symbol or a label, or an unknown one, shows its id.
	assert_str(economy.format_amount(&"troc", 3)).is_equal("3 troc")
	assert_str(economy.currency_label(&"troc")).is_equal("troc")
	assert_str(economy.currency_symbol(&"franc")).is_equal("franc")
	assert_str(economy.currency_label(&"franc")).is_equal("franc")


# --- Market ------------------------------------------------------------------

func test_the_catalogue_can_be_listed_by_kind() -> void:
	var economy := _economy()

	assert_int(economy.offers().size()).is_equal(5)
	var buildings: Array[EconomyOffer] = economy.offers(EconomyOffer.Kind.BUILDING)
	var slots: Array[EconomyOffer] = economy.offers(EconomyOffer.Kind.SLOT)
	assert_int(buildings.size()).is_equal(1)
	assert_str(String(buildings[0].id)).is_equal("barn")
	assert_int(slots.size()).is_equal(1)
	assert_str(String(slots[0].id)).is_equal("plot")
	assert_int(economy.offers(EconomyOffer.Kind.ITEM).size()).is_equal(3)


func test_a_refused_purchase_says_why_and_changes_nothing() -> void:
	var generation := _generation()
	var economy := _economy(generation)

	assert_bool(economy.buy(&"barn", 0)).is_false()
	assert_bool(economy.buy(&"ghost")).is_false()
	assert_bool(economy.buy(&"relic")).is_false()
	assert_bool(economy.buy(&"barn", 2)).is_false()
	assert_bool(economy.buy(&"plot", 2)).is_false()
	generation.allow_buy = false
	assert_bool(economy.can_buy(&"barn")).is_false()
	assert_bool(economy.buy(&"barn")).is_false()
	generation.allow_buy = true
	economy.set_enabled(false)
	assert_bool(economy.buy(&"barn")).is_false()

	assert_str(_reasons()).is_equal("invalid_quantity, unknown_offer, unknown_currency, "
		+ "out_of_stock, insufficient_funds, buy_disabled, economy_disabled")
	assert_int(economy.balance(&"gourde")).is_equal(100)
	assert_int(economy.balance(&"token")).is_equal(3)
	assert_int(economy.offer_stock(&"barn")).is_equal(1)
	assert_int(economy.owned_count(&"barn_asset")).is_equal(0)


func test_a_purchase_announces_the_money_the_stock_and_the_asset() -> void:
	var economy := _economy()
	var events: Array[String] = []
	economy.balance_changed.connect(func(currency_id: StringName, amount: int) -> void:
		events.append("balance %s %d" % [currency_id, amount]))
	economy.stock_changed.connect(func(offer_id: StringName, remaining: int) -> void:
		events.append("stock %s %d" % [offer_id, remaining]))
	economy.ownership_changed.connect(func(asset_id: StringName, amount: int) -> void:
		events.append("owned %s %d" % [asset_id, amount]))
	economy.offer_purchased.connect(func(offer: EconomyOffer, quantity: int) -> void:
		events.append("purchased %s %d" % [offer.id, quantity]))

	assert_bool(economy.buy(&"barn")).is_true()

	assert_str(" | ".join(PackedStringArray(events))).is_equal(
		"balance gourde 60 | stock barn 0 | owned barn_asset 1 | purchased barn 1")
	assert_bool(economy.can_buy(&"barn")).is_false()


func test_an_offer_without_a_grant_is_owned_under_its_own_id() -> void:
	var economy := _economy()
	economy.set_balance(&"token", 10)
	var stock_events: Array[String] = []
	economy.stock_changed.connect(func(offer_id: StringName, _remaining: int) -> void:
		stock_events.append(String(offer_id)))

	assert_bool(economy.buy(&"plot", 3)).is_true()

	assert_int(economy.owned_count(&"plot")).is_equal(3)
	assert_int(economy.balance(&"token")).is_equal(4)
	# Unlimited stock stays unlimited and is not announced.
	assert_int(economy.offer_stock(&"plot")).is_equal(-1)
	assert_array(stock_events).is_empty()
	assert_int(economy.owned_value(&"token")).is_equal(6)
	assert_int(economy.owned_value(&"gourde")).is_equal(0)
	assert_int(economy.owned_value()).is_equal(6)


func test_a_free_offer_costs_nothing_and_sells_for_nothing() -> void:
	var economy := _economy()
	economy.set_balance(&"gourde", 0)
	var sold: Array[int] = []
	economy.offer_sold.connect(func(_offer: EconomyOffer, _quantity: int, total: int) -> void:
		sold.append(total))

	assert_bool(economy.buy(&"leaflet")).is_true()
	assert_int(economy.owned_count(&"leaflet")).is_equal(1)
	assert_int(economy.balance(&"gourde")).is_equal(0)

	assert_bool(economy.can_sell(&"leaflet")).is_true()
	assert_int(economy.sell(&"leaflet")).is_equal(0)
	assert_int(economy.owned_count(&"leaflet")).is_equal(0)
	assert_int(economy.balance(&"gourde")).is_equal(0)
	assert_array(sold).is_equal([0])


func test_a_refused_sale_says_why_and_changes_nothing() -> void:
	var generation := _generation()
	var economy := _economy(generation)
	economy.buy(&"medal")
	economy.buy(&"barn")
	economy.trade({}, {"asset": "relic", "amount": 1})

	assert_int(economy.sell(&"barn", 0)).is_equal(0)
	assert_int(economy.sell(&"ghost")).is_equal(0)
	assert_int(economy.sell(&"medal")).is_equal(0)
	assert_int(economy.sell(&"relic")).is_equal(0)
	assert_int(economy.sell(&"barn", 2)).is_equal(0)
	assert_int(economy.sell(&"plot")).is_equal(0)
	generation.allow_sell = false
	assert_bool(economy.can_sell(&"barn")).is_false()
	assert_int(economy.sell(&"barn")).is_equal(0)
	generation.allow_sell = true
	economy.set_enabled(false)
	assert_int(economy.sell(&"barn")).is_equal(0)

	assert_str(_reasons()).is_equal("invalid_quantity, unknown_offer, not_sellable, "
		+ "unknown_currency, not_owned, not_owned, sell_disabled, economy_disabled")
	assert_int(economy.balance(&"gourde")).is_equal(55)
	assert_int(economy.owned_count(&"barn_asset")).is_equal(1)
	assert_int(economy.owned_count(&"medal")).is_equal(1)
	assert_int(economy.owned_count(&"relic")).is_equal(1)


func test_selling_back_puts_the_unit_on_the_shelf_again() -> void:
	var economy := _economy()
	economy.buy(&"barn")
	var events: Array[String] = []
	economy.stock_changed.connect(func(offer_id: StringName, remaining: int) -> void:
		events.append("stock %s %d" % [offer_id, remaining]))
	economy.ownership_changed.connect(func(asset_id: StringName, amount: int) -> void:
		events.append("owned %s %d" % [asset_id, amount]))
	economy.offer_sold.connect(func(offer: EconomyOffer, quantity: int, total: int) -> void:
		events.append("sold %s %d %d" % [offer.id, quantity, total]))

	assert_int(economy.sell(&"barn")).is_equal(20)

	assert_str(" | ".join(PackedStringArray(events))).is_equal(
		"owned barn_asset 0 | stock barn 1 | sold barn 1 20")
	assert_int(economy.balance(&"gourde")).is_equal(80)
	assert_int(economy.offer_stock(&"barn")).is_equal(1)
	assert_bool(economy.to_dict()["owned"].has("barn_asset")).is_false()
	assert_bool(economy.buy(&"barn")).is_true()


func test_selling_part_of_a_stack_keeps_the_rest() -> void:
	var economy := _economy()
	economy.set_balance(&"token", 6)
	economy.buy(&"plot", 3)

	assert_int(economy.sell(&"plot", 2)).is_equal(2)

	assert_int(economy.owned_count(&"plot")).is_equal(1)
	assert_int(economy.balance(&"token")).is_equal(2)
	assert_bool(economy.can_sell(&"plot")).is_true()
	assert_bool(economy.can_sell(&"plot", 2)).is_false()


# --- Barter ------------------------------------------------------------------

func test_a_refused_trade_says_why_and_changes_nothing() -> void:
	var generation := _generation()
	var economy := _economy(generation)
	var completed: Array[Dictionary] = []
	economy.trade_completed.connect(
		func(give: Dictionary, _receive: Dictionary) -> void: completed.append(give))
	var coin := {"currency": "gourde", "amount": 10}

	assert_bool(economy.trade({}, {})).is_false()
	assert_bool(economy.trade({"currency": "gourde"}, coin)).is_false()
	assert_bool(economy.trade({"currency": "gourde", "asset": "hen", "amount": 1}, coin)).is_false()
	assert_bool(economy.trade({"amount": 1}, coin)).is_false()
	assert_bool(economy.trade({"currency": "gourde", "amount": 0}, coin)).is_false()
	assert_bool(economy.trade(coin, {"asset": "", "amount": 1})).is_false()
	assert_bool(economy.trade({"currency": "piastre", "amount": 1}, coin)).is_false()
	assert_bool(economy.trade(coin, {"currency": "franc", "amount": 1})).is_false()
	assert_bool(economy.trade({"currency": "gourde", "amount": 101}, coin)).is_false()
	assert_bool(economy.trade({"asset": "hen", "amount": 1}, coin)).is_false()
	generation.allow_trade = false
	assert_bool(economy.trade(coin, {"asset": "hen", "amount": 1})).is_false()
	generation.allow_trade = true
	economy.set_enabled(false)
	assert_bool(economy.trade(coin, {"asset": "hen", "amount": 1})).is_false()

	assert_str(_reasons()).is_equal("empty_trade, invalid_trade_entry, invalid_trade_entry, "
		+ "invalid_trade_entry, invalid_trade_entry, invalid_trade_entry, unknown_currency, "
		+ "unknown_currency, insufficient_funds, not_owned, trade_disabled, economy_disabled")
	assert_array(completed).is_empty()
	assert_int(economy.balance(&"gourde")).is_equal(100)
	assert_int(economy.owned_count(&"hen")).is_equal(0)


func test_money_buys_an_asset_and_the_asset_buys_money_back() -> void:
	var economy := _economy()
	var trades: Array[String] = []
	economy.trade_completed.connect(func(give: Dictionary, receive: Dictionary) -> void:
		trades.append("%s -> %s" % [give.get("amount", 0), receive.get("amount", 0)]))

	assert_bool(economy.trade(
		{"currency": "gourde", "amount": 30}, {"asset": "hen", "amount": 2})).is_true()
	assert_int(economy.balance(&"gourde")).is_equal(70)
	assert_int(economy.owned_count(&"hen")).is_equal(2)

	assert_bool(economy.trade(
		{"asset": "hen", "amount": 1}, {"currency": "token", "amount": 4})).is_true()
	assert_int(economy.owned_count(&"hen")).is_equal(1)
	assert_int(economy.balance(&"token")).is_equal(7)

	# Receiving more than was ever owned is fine; giving it is not.
	assert_bool(economy.trade(
		{"asset": "hen", "amount": 2}, {"currency": "token", "amount": 4})).is_false()
	assert_int(economy.owned_count(&"hen")).is_equal(1)
	assert_str(", ".join(PackedStringArray(trades))).is_equal("30 -> 2, 1 -> 4")


func test_a_trade_can_be_a_gift_or_a_tribute() -> void:
	var economy := _economy()

	assert_bool(economy.trade({}, {"currency": "gourde", "amount": 15})).is_true()
	assert_int(economy.balance(&"gourde")).is_equal(115)

	assert_bool(economy.trade({"currency": "gourde", "amount": 115}, {})).is_true()
	assert_int(economy.balance(&"gourde")).is_equal(0)

	assert_bool(economy.trade({}, {"asset": "hen", "amount": 1})).is_true()
	assert_bool(economy.trade({"asset": "hen", "amount": 1}, {})).is_true()
	assert_int(economy.owned_count(&"hen")).is_equal(0)
	assert_str(_reasons()).is_empty()


# --- Save payload ------------------------------------------------------------

func test_a_save_must_name_a_known_generation_and_hold_dictionaries() -> void:
	var economy := _economy()

	assert_bool(economy.can_restore({})).is_false()
	assert_bool(economy.can_restore({"generation": "ghost"})).is_false()
	assert_bool(economy.can_restore({"generation": "test", "wallets": []})).is_false()
	assert_bool(economy.can_restore({"generation": "test", "owned": "barn"})).is_false()
	assert_bool(economy.can_restore({"generation": "test", "stock": 3})).is_false()
	assert_bool(economy.can_restore({"generation": "test"})).is_true()
	assert_bool(economy.can_restore(
		{"generation": "test", "wallets": {}, "owned": {}, "stock": {}})).is_true()


func test_an_invalid_save_leaves_the_economy_untouched() -> void:
	var economy := _economy()
	economy.buy(&"barn")

	assert_bool(economy.from_dict({"generation": "ghost", "wallets": {"gourde": 1}})).is_false()
	assert_bool(economy.from_dict({"generation": "test", "wallets": 12})).is_false()

	assert_int(economy.balance(&"gourde")).is_equal(60)
	assert_int(economy.owned_count(&"barn_asset")).is_equal(1)
	assert_int(economy.offer_stock(&"barn")).is_equal(0)


func test_a_save_restores_only_what_the_generation_knows() -> void:
	var economy := _economy()
	var owned_events := {}
	economy.ownership_changed.connect(func(asset_id: StringName, amount: int) -> void:
		owned_events[String(asset_id)] = amount)

	assert_bool(economy.from_dict({
		"generation": "test",
		"enabled": false,
		"wallets": {"gourde": 12.0, "token": -4, "franc": 99},
		"owned": {"barn_asset": 1, "hen": -2, "": 5},
		"stock": {"barn": 0, "plot": -7, "ghost": 3},
	})).is_true()

	assert_bool(economy.is_enabled()).is_false()
	assert_int(economy.balance(&"gourde")).is_equal(12)
	assert_int(economy.balance(&"token")).is_equal(0)
	assert_int(economy.balance(&"franc")).is_equal(0)
	assert_int(economy.owned_count(&"barn_asset")).is_equal(1)
	assert_int(economy.owned_count(&"hen")).is_equal(0)
	assert_int(economy.owned_count(&"")).is_equal(0)
	assert_int(economy.offer_stock(&"barn")).is_equal(0)
	assert_int(economy.offer_stock(&"plot")).is_equal(-1)
	assert_int(economy.offer_stock(&"ghost")).is_equal(-1)
	# The map listens to this to count what was bought before the save.
	assert_int(int(owned_events.get("barn_asset", 0))).is_equal(1)
	var saved: Dictionary = economy.to_dict()
	assert_bool((saved["wallets"] as Dictionary).has("franc")).is_false()
	assert_bool((saved["stock"] as Dictionary).has("ghost")).is_false()


func test_a_save_without_details_restarts_the_generation() -> void:
	var economy := _economy()
	economy.buy(&"barn")

	assert_bool(economy.from_dict({"generation": "test"})).is_true()

	assert_bool(economy.is_enabled()).is_true()
	assert_int(economy.balance(&"gourde")).is_equal(100)
	assert_int(economy.owned_count(&"barn_asset")).is_equal(0)
	assert_int(economy.offer_stock(&"barn")).is_equal(1)


func test_a_save_round_trip_keeps_wallets_stock_and_assets() -> void:
	var economy := _economy()
	economy.buy(&"barn")
	economy.buy(&"plot")
	economy.trade({}, {"asset": "hen", "amount": 3})
	var saved: Dictionary = economy.to_dict()
	var other := _economy()

	assert_bool(other.from_dict(JSON.parse_string(JSON.stringify(saved)) as Dictionary)).is_true()

	assert_dict(other.to_dict()).is_equal(saved)
	assert_str(String(saved["generation"])).is_equal("test")
	assert_int(other.owned_count(&"hen")).is_equal(3)
	assert_int(other.balance(&"token")).is_equal(1)


func test_a_file_that_is_not_an_economy_is_refused() -> void:
	var economy := _bare_economy()

	# The error is logged; the economy keeps running on an empty config.
	assert_bool(economy.reload_config("res://game_resources/fx/base_material.tres")).is_false()
	assert_object(economy.generation()).is_null()
	assert_bool(economy.is_enabled()).is_false()

	assert_bool(economy.reload_config(SHIPPED_CONFIG)).is_true()
	assert_str(String(economy.current_generation_id())).is_equal("cultivateur")
	assert_int(economy.balance(&"gourde")).is_equal(30)


func test_an_offer_without_an_id_cannot_be_bought() -> void:
	# Regression: it charged its price on every call, ignored its stock and
	# granted nothing.
	var generation := _generation()
	var offers: Array[EconomyOffer] = generation.offers.duplicate()
	offers.append(_offer(&"", &"gourde", 40, 20))
	generation.offers = offers
	var economy := _economy(generation)
	var before: int = economy.balance(&"gourde")

	assert_bool(economy.buy(&"")).is_false()
	assert_int(economy.sell(&"")).is_equal(0)

	assert_int(economy.balance(&"gourde")).is_equal(before)
	assert_str(_reasons()).contains("unknown_offer")
