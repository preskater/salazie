extends GdUnitTestSuite

const SHIPPED_CONFIG := "res://game/systems/economy/config/economy.tres"
const HUD_SCENE := "res://game/farm/farm_hud.tscn"

var _original_config: EconomyConfig


func before_test() -> void:
	_original_config = Economy.config
	GameState.playing = false


func after_test() -> void:
	if _original_config != null:
		Economy.apply_config(_original_config, _original_config.default_generation)
	GameState.playing = false
	GameState.reset()
	if get_tree() != null:
		get_tree().paused = false


func _build_config(disabled := false) -> EconomyConfig:
	var gourde := EconomyCurrency.new()
	gourde.id = &"gourde"
	gourde.label = "Gourde"
	gourde.symbol = "G"
	gourde.starting_balance = 100

	var token := EconomyCurrency.new()
	token.id = &"token"
	token.label = "Jeton"
	token.symbol = "J"
	token.starting_balance = 3

	var barn := EconomyOffer.new()
	barn.id = &"barn"
	barn.label = "Grange"
	barn.kind = EconomyOffer.Kind.BUILDING
	barn.currency_id = &"gourde"
	barn.price = 40
	barn.sell_price = 20
	barn.stock = 1
	barn.grant_id = &"barn"

	var plot := EconomyOffer.new()
	plot.id = &"plot"
	plot.label = "Parcelle"
	plot.kind = EconomyOffer.Kind.SLOT
	plot.currency_id = &"token"
	plot.price = 2
	plot.sell_price = 1

	var hoe := EconomyOffer.new()
	hoe.id = &"hoe"
	hoe.label = "Houe"
	hoe.kind = EconomyOffer.Kind.ITEM
	hoe.currency_id = &"gourde"
	hoe.price = 10
	hoe.sell_price = 4

	var generation := EconomyGeneration.new()
	generation.id = &"test"
	generation.label = "Test"
	generation.enabled = not disabled
	var currencies: Array[EconomyCurrency] = [gourde, token]
	generation.currencies = currencies
	var offers: Array[EconomyOffer] = [barn, plot, hoe]
	generation.offers = offers

	var config := EconomyConfig.new()
	var generations: Array[EconomyGeneration] = [generation]
	config.generations = generations
	config.default_generation = &"test"
	return config


func _activate(disabled := false) -> void:
	assert_bool(Economy.apply_config(_build_config(disabled), &"test")).is_true()


func test_shipped_config_declares_one_economy_per_generation() -> void:
	var config := load(SHIPPED_CONFIG) as EconomyConfig

	assert_object(config).is_not_null()
	if config == null:
		return
	assert_int(config.generations.size()).is_equal(3)
	assert_str(String(config.default_generation)).is_equal("cultivateur")

	var marron := config.find_generation(&"marron")
	assert_object(marron).is_not_null()
	if marron != null:
		assert_bool(marron.enabled).is_false()
		assert_int(marron.currencies.size()).is_equal(0)

	var cultivateur := config.find_generation(&"cultivateur")
	assert_object(cultivateur).is_not_null()
	if cultivateur != null:
		assert_str(String(cultivateur.primary_currency_id())).is_equal("gourde")
		var gourde := cultivateur.find_currency(&"gourde")
		assert_object(gourde).is_not_null()
		if gourde != null:
			assert_int(gourde.starting_balance).is_equal(30)

	var heritier := config.find_generation(&"heritier")
	assert_object(heritier).is_not_null()
	if heritier != null:
		assert_int(heritier.currencies.size()).is_equal(2)
		assert_str(String(heritier.primary_currency_id())).is_equal("euro")


func test_generation_starts_with_configured_wallets() -> void:
	_activate()

	assert_bool(Economy.is_enabled()).is_true()
	assert_int(Economy.balance(&"gourde")).is_equal(100)
	assert_int(Economy.balance(&"token")).is_equal(3)
	assert_str(String(Economy.primary_currency_id())).is_equal("gourde")


func test_disabled_generation_refuses_buy_sell_and_trade() -> void:
	_activate(true)

	assert_bool(Economy.is_enabled()).is_false()
	assert_bool(Economy.buy(&"barn")).is_false()
	assert_bool(Economy.add_currency(&"gourde", 10)).is_false()
	assert_bool(Economy.trade(
		{"currency": &"gourde", "amount": 1},
		{"asset": &"plot", "amount": 1})).is_false()
	assert_int(Economy.owned_count(&"barn")).is_equal(0)


func test_buying_a_building_debits_currency_and_grants_ownership() -> void:
	_activate()
	var purchased: Array[EconomyOffer] = []
	var callback := func(offer: EconomyOffer, _quantity: int) -> void:
		purchased.append(offer)
	Economy.offer_purchased.connect(callback)

	assert_bool(Economy.buy(&"barn")).is_true()

	Economy.offer_purchased.disconnect(callback)
	assert_int(Economy.balance(&"gourde")).is_equal(60)
	assert_int(Economy.owned_count(&"barn")).is_equal(1)
	assert_int(Economy.offer_stock(&"barn")).is_equal(0)
	assert_bool(Economy.can_buy(&"barn")).is_false()
	assert_int(purchased.size()).is_equal(1)


func test_buy_without_funds_leaves_state_unchanged() -> void:
	_activate()
	Economy.set_balance(&"gourde", 10)
	var failures: Array[StringName] = []
	var callback := func(reason: StringName) -> void:
		failures.append(reason)
	Economy.transaction_failed.connect(callback)

	assert_bool(Economy.buy(&"barn")).is_false()

	Economy.transaction_failed.disconnect(callback)
	assert_int(Economy.balance(&"gourde")).is_equal(10)
	assert_int(Economy.owned_count(&"barn")).is_equal(0)
	assert_int(Economy.offer_stock(&"barn")).is_equal(1)
	assert_int(failures.size()).is_equal(1)
	if not failures.is_empty():
		assert_str(String(failures[0])).is_equal("insufficient_funds")


func test_selling_an_owned_slot_returns_its_sell_price() -> void:
	_activate()

	assert_bool(Economy.buy(&"plot")).is_true()
	assert_int(Economy.balance(&"token")).is_equal(1)
	assert_int(Economy.owned_count(&"plot")).is_equal(1)

	assert_int(Economy.sell(&"plot")).is_equal(1)

	assert_int(Economy.balance(&"token")).is_equal(2)
	assert_int(Economy.owned_count(&"plot")).is_equal(0)
	assert_int(Economy.sell(&"plot")).is_equal(0)


func test_trade_swaps_currency_and_asset_atomically() -> void:
	_activate()
	Economy.set_balance(&"gourde", 20)

	assert_bool(Economy.trade(
		{"currency": &"gourde", "amount": 20},
		{"asset": &"plot", "amount": 2})).is_true()

	assert_int(Economy.balance(&"gourde")).is_equal(0)
	assert_int(Economy.owned_count(&"plot")).is_equal(2)

	assert_bool(Economy.trade(
		{"currency": &"gourde", "amount": 5},
		{"asset": &"barn", "amount": 1})).is_false()
	assert_int(Economy.balance(&"gourde")).is_equal(0)
	assert_int(Economy.owned_count(&"barn")).is_equal(0)


func test_state_round_trip_restores_wallets_stock_and_ownership() -> void:
	_activate()
	assert_bool(Economy.buy(&"barn")).is_true()
	Economy.set_balance(&"token", 7)
	var state := Economy.to_dict()

	Economy.reset()
	assert_int(Economy.balance(&"gourde")).is_equal(100)
	assert_int(Economy.owned_count(&"barn")).is_equal(0)

	assert_bool(Economy.from_dict(state)).is_true()
	assert_int(Economy.balance(&"gourde")).is_equal(60)
	assert_int(Economy.balance(&"token")).is_equal(7)
	assert_int(Economy.owned_count(&"barn")).is_equal(1)
	assert_int(Economy.offer_stock(&"barn")).is_equal(0)


func test_game_state_money_uses_the_active_generation_wallet() -> void:
	_activate()
	GameState.reset()

	assert_int(GameState.money).is_equal(100)
	assert_int(Economy.balance(&"gourde")).is_equal(100)
	assert_str(GameState.format_wallets()).is_equal("100 G · 3 J")

	GameState.money = 77
	assert_int(Economy.balance(&"gourde")).is_equal(77)
	assert_str(GameState.format_wallets()).is_equal("77 G · 3 J")

	assert_bool(GameState.spend_money(7)).is_true()
	assert_int(Economy.balance(&"gourde")).is_equal(70)
	assert_int(GameState.money).is_equal(70)


func test_disabled_generation_blocks_game_state_spending() -> void:
	_activate(true)
	GameState.reset()

	assert_bool(GameState.is_economy_enabled()).is_false()
	assert_bool(GameState.spend_money(5)).is_false()
	assert_int(GameState.money).is_equal(GameState.START_MONEY)


func test_config_disabled_generation_cannot_be_enabled_at_runtime() -> void:
	_activate(true)

	Economy.set_enabled(true)

	assert_bool(Economy.is_enabled()).is_false()


func test_runtime_toggle_blocks_then_restores_transactions() -> void:
	_activate()

	Economy.set_enabled(false)
	assert_bool(Economy.is_enabled()).is_false()
	assert_bool(Economy.buy(&"barn")).is_false()

	Economy.set_enabled(true)
	assert_bool(Economy.is_enabled()).is_true()
	assert_bool(Economy.buy(&"barn")).is_true()


func test_disabled_currency_blocks_its_offers() -> void:
	var config := _build_config()
	var token := config.find_generation(&"test").find_currency(&"token")
	assert_object(token).is_not_null()
	if token == null:
		return
	token.enabled = false

	assert_bool(Economy.apply_config(config, &"test")).is_true()
	assert_bool(Economy.can_buy(&"plot")).is_false()
	assert_bool(Economy.set_balance(&"token", 10)).is_false()


func test_reset_returns_to_the_farm_generation() -> void:
	if _original_config == null or _original_config.find_generation(&"heritier") == null:
		return
	assert_bool(Economy.apply_config(_original_config, &"heritier")).is_true()

	GameState.reset()

	assert_str(String(Economy.current_generation_id())).is_equal("cultivateur")
	assert_str(String(GameState.currency_id())).is_equal("gourde")


func test_shipped_heritier_shows_both_wallets() -> void:
	if _original_config == null or _original_config.find_generation(&"heritier") == null:
		return

	assert_bool(Economy.apply_config(_original_config, &"heritier")).is_true()

	assert_str(GameState.format_wallets()).is_equal("120 € · 5 CV")


func test_version_1_payload_restores_the_farm_generation() -> void:
	if _original_config == null or _original_config.find_generation(&"heritier") == null:
		return
	Economy.apply_config(_original_config, &"heritier")
	var payload := GameState.to_dict()
	payload.erase("economy")
	payload["money"] = 55

	assert_bool(GameState.from_dict(payload)).is_true()

	assert_str(String(Economy.current_generation_id())).is_equal("cultivateur")
	assert_int(GameState.money).is_equal(55)
	assert_int(Economy.balance(&"gourde")).is_equal(55)


func test_market_lists_and_sells_generation_property_offers() -> void:
	_activate()
	var hud: FarmHUD = auto_free(load(HUD_SCENE).instantiate())
	add_child(hud)
	await get_tree().process_frame
	hud.open_market()
	await get_tree().process_frame

	var buy_button := hud.get_node("%BuyRows").get_node_or_null("Buy_barn") as Button
	var sell_button := hud.get_node("%SellRows").get_node_or_null("Sell_barn") as Button
	var item_button := hud.get_node("%BuyRows").get_node_or_null("Buy_hoe") as Button
	assert_object(buy_button).is_not_null()
	assert_object(sell_button).is_not_null()
	assert_object(item_button).is_not_null()
	if buy_button == null or sell_button == null:
		return
	assert_bool(buy_button.disabled).is_false()

	buy_button.pressed.emit()
	await get_tree().process_frame
	assert_int(Economy.owned_count(&"barn")).is_equal(1)
	assert_int(Economy.balance(&"gourde")).is_equal(60)
	assert_bool(sell_button.disabled).is_false()

	sell_button.pressed.emit()
	await get_tree().process_frame
	assert_int(Economy.owned_count(&"barn")).is_equal(0)
	assert_int(Economy.balance(&"gourde")).is_equal(80)

	hud.close_market()
	get_tree().paused = false
