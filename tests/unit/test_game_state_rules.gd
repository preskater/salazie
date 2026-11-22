extends GdUnitTestSuite
## The farmer's purse, seed bag and basket: what a refused purchase or an empty
## basket does, how money is written, and which save payloads are accepted.

const TEST_SAVE_PATH := "user://test_game_state_rules_save.json"

var _original_save_path := ""
var _original_config: EconomyConfig


func before_test() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	_original_config = Economy.config
	GameState.playing = false
	GameState.farm_active = true
	GameState.reset()


func after_test() -> void:
	GameState.playing = false
	if _original_config != null:
		Economy.apply_config(_original_config, _original_config.default_generation)
	GameState.reset()
	SaveGame.save_path = _original_save_path
	for path: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _valid_payload() -> Dictionary:
	return {
		"money": 12,
		"day": 2,
		"seeds": {"corn": 1},
		"produce": {"tomato": 3},
		"prices": {"corn": 14},
	}


# --- Purse -------------------------------------------------------------------

func test_the_farm_counts_in_gourdes() -> void:
	assert_str(String(GameState.currency_id())).is_equal("gourde")
	assert_str(GameState.currency_label()).is_equal("Gourde")
	assert_str(GameState.currency_symbol()).is_equal("G")
	assert_str(GameState.format_money(7)).is_equal("7 G")
	assert_str(GameState.format_wallets()).is_equal("30 G")
	assert_bool(GameState.is_economy_enabled()).is_true()


func test_the_purse_cannot_be_overspent() -> void:
	assert_bool(GameState.spend_money(31)).is_false()
	assert_int(GameState.money).is_equal(30)

	assert_bool(GameState.spend_money(30)).is_true()
	assert_int(GameState.money).is_equal(0)
	assert_bool(GameState.spend_money(1)).is_false()


func test_setting_the_purse_clamps_it_and_tells_the_hud() -> void:
	var seen: Array[int] = []
	var on_money := func(value: int) -> void: seen.append(value)
	GameState.money_changed.connect(on_money)

	GameState.set_money(-15)
	var after_negative := GameState.money
	GameState.set_money(64)

	GameState.money_changed.disconnect(on_money)
	assert_int(after_negative).is_equal(0)
	assert_int(GameState.money).is_equal(64)
	assert_int(Economy.balance(&"gourde")).is_equal(64)
	assert_int(seen[-1]).is_equal(64)
	assert_bool(seen.has(0)).is_true()


func test_a_generation_without_money_neither_earns_nor_spends() -> void:
	# The maroon's generation has no currency and a disabled economy.
	assert_bool(Economy.select_generation(&"marron")).is_true()
	GameState.money = 42
	GameState.add_produce("corn", 2)
	var seeds := GameState.seed_count("corn")
	var sales: Array[int] = []
	var on_sold := func(_crop: String, _amount: int, total: int) -> void: sales.append(total)
	GameState.produce_sold.connect(on_sold)

	GameState.add_money(10)
	var spent := GameState.spend_money(5)
	var bought := GameState.buy_seed("corn")
	var earned := GameState.sell("corn", 2)

	GameState.produce_sold.disconnect(on_sold)
	assert_bool(GameState.is_economy_enabled()).is_false()
	assert_bool(spent).is_false()
	assert_bool(bought).is_false()
	assert_int(earned).is_equal(0)
	assert_array(sales).is_empty()
	assert_int(GameState.money).is_equal(42)
	assert_int(GameState.seed_count("corn")).is_equal(seeds)
	assert_int(GameState.produce_count("corn")).is_equal(2)
	# No currency to name: amounts are bare numbers.
	assert_str(GameState.format_money(12)).is_equal("12")
	assert_str(GameState.format_wallets()).is_equal("42")
	assert_str(String(GameState.currency_id())).is_equal("gourde")


func test_only_usable_wallets_are_shown() -> void:
	var gourde := EconomyCurrency.new()
	gourde.id = &"gourde"
	gourde.symbol = "G"
	gourde.starting_balance = 10
	var retired := EconomyCurrency.new()
	retired.id = &"piastre"
	retired.symbol = "P"
	retired.starting_balance = 5
	retired.enabled = false
	var token := EconomyCurrency.new()
	token.id = &"token"
	token.symbol = "J"
	token.starting_balance = 2
	var generation := EconomyGeneration.new()
	generation.id = &"troc"
	var currencies: Array[EconomyCurrency] = [retired, gourde, null, token]
	generation.currencies = currencies
	var config := EconomyConfig.new()
	var generations: Array[EconomyGeneration] = [generation]
	config.generations = generations
	config.default_generation = &"troc"

	assert_bool(Economy.apply_config(config)).is_true()

	assert_str(String(GameState.currency_id())).is_equal("gourde")
	assert_int(GameState.money).is_equal(10)
	assert_str(GameState.format_wallets()).is_equal("10 G · 2 J")


# --- Seeds and basket --------------------------------------------------------

func test_buying_a_seed_takes_its_price_from_the_purse() -> void:
	var changes: Array[int] = [0]
	var on_inventory := func() -> void: changes[0] += 1
	GameState.inventory_changed.connect(on_inventory)
	var seeds := GameState.seed_count("pumpkin")

	var bought := GameState.buy_seed("pumpkin")

	GameState.inventory_changed.disconnect(on_inventory)
	assert_bool(bought).is_true()
	assert_int(GameState.seed_count("pumpkin")).is_equal(seeds + 1)
	assert_int(GameState.money).is_equal(
		GameState.START_MONEY - int(GameState.CROPS["pumpkin"]["seed_price"]))
	assert_int(changes[0]).is_equal(1)


func test_a_seed_that_cannot_be_paid_or_does_not_exist_is_not_bought() -> void:
	GameState.money = 2
	var seeds: Dictionary = GameState.seeds.duplicate(true)

	assert_bool(GameState.buy_seed("carrot")).is_false()
	assert_bool(GameState.buy_seed("manioc")).is_false()

	assert_int(GameState.money).is_equal(2)
	assert_dict(GameState.seeds).is_equal(seeds)


func test_a_seed_bag_can_run_out() -> void:
	GameState.seeds["carrot"] = 1

	assert_bool(GameState.consume_seed("carrot")).is_true()
	assert_bool(GameState.consume_seed("carrot")).is_false()
	assert_bool(GameState.consume_seed("manioc")).is_false()

	assert_int(GameState.seed_count("carrot")).is_equal(0)
	assert_int(GameState.seed_count("manioc")).is_equal(0)


func test_selling_pays_the_price_of_the_day_for_what_is_in_the_basket() -> void:
	GameState.add_produce("tomato", 3)
	GameState.prices["tomato"] = 11
	var sales: Array[String] = []
	var on_sold := func(crop: String, amount: int, total: int) -> void:
		sales.append("%s %d %d" % [crop, amount, total])
	GameState.produce_sold.connect(on_sold)

	# Asking for more than the basket holds sells the basket.
	var earned := GameState.sell("tomato", 5)
	var nothing_left := GameState.sell("tomato", 1)
	var never_had := GameState.sell("corn", 1)
	var negative := GameState.sell("pumpkin", -2)

	GameState.produce_sold.disconnect(on_sold)
	assert_int(earned).is_equal(33)
	assert_int(nothing_left).is_equal(0)
	assert_int(never_had).is_equal(0)
	assert_int(negative).is_equal(0)
	assert_int(GameState.money).is_equal(GameState.START_MONEY + 33)
	assert_int(GameState.produce_count("tomato")).is_equal(0)
	assert_array(sales).is_equal(["tomato 3 33"])


func test_only_known_seeds_can_be_selected() -> void:
	var selected: Array[String] = []
	var on_seed := func(crop: String) -> void: selected.append(crop)
	GameState.seed_changed.connect(on_seed)

	GameState.select_seed("manioc")
	GameState.select_seed("corn")
	GameState.select_seed("carrot")

	GameState.seed_changed.disconnect(on_seed)
	assert_str(GameState.selected_seed).is_equal("carrot")
	assert_array(selected).is_equal(["carrot"])


func test_dialogue_requests_reach_the_listeners() -> void:
	var heard: Array[String] = []
	var on_dialogue := func(speaker: String, text: String) -> void:
		heard.append("%s: %s" % [speaker, text])
	GameState.dialogue_requested.connect(on_dialogue)

	GameState.show_dialogue("Marchande", "Bonjour.")

	GameState.dialogue_requested.disconnect(on_dialogue)
	assert_array(heard).is_equal(["Marchande: Bonjour."])


# --- Save payload ------------------------------------------------------------

func test_a_minimal_save_is_completed_with_defaults() -> void:
	GameState.day = 9
	GameState.select_seed("tomato")
	var payload := _valid_payload()
	payload["selected_seed"] = "manioc"

	assert_bool(GameState.can_restore(payload)).is_true()
	assert_bool(GameState.from_dict(payload)).is_true()

	assert_int(GameState.money).is_equal(12)
	assert_int(GameState.day).is_equal(2)
	assert_float(float(GameState.to_dict()["day_time"])).is_equal(0.0)
	assert_str(GameState.selected_seed).is_equal("corn")
	assert_int(GameState.seed_count("corn")).is_equal(1)
	assert_int(GameState.seed_count("carrot")).is_equal(0)
	assert_int(GameState.produce_count("tomato")).is_equal(3)
	assert_int(GameState.produce_count("corn")).is_equal(0)
	assert_int(int(GameState.prices["corn"])).is_equal(14)
	assert_int(int(GameState.prices["carrot"])).is_equal(
		int(GameState.CROPS["carrot"]["base_price"]))
	# Without yesterday's prices no crop shows a trend.
	for crop: String in GameState.CROP_ORDER:
		assert_int(GameState.price_trend(crop)).is_equal(0)
	assert_str(String(Economy.current_generation_id())).is_equal("cultivateur")


func test_a_save_clamps_what_cannot_be() -> void:
	var payload := _valid_payload()
	payload["money"] = -40
	payload["day"] = -3
	payload["day_time"] = 99999.0
	payload["seeds"] = {"corn": -2, "pumpkin": "many"}
	payload["prices"] = {"corn": 0, "tomato": -5}
	payload["previous_prices"] = {"corn": 20}

	assert_bool(GameState.from_dict(payload)).is_true()

	assert_int(GameState.money).is_equal(0)
	assert_int(GameState.day).is_equal(1)
	assert_float(float(GameState.to_dict()["day_time"])).is_equal(GameState.day_length)
	assert_int(GameState.seed_count("corn")).is_equal(0)
	assert_int(GameState.seed_count("pumpkin")).is_equal(0)
	assert_int(int(GameState.prices["corn"])).is_equal(1)
	assert_int(int(GameState.prices["tomato"])).is_equal(1)
	assert_int(GameState.price_trend("corn")).is_equal(-1)


func test_a_malformed_save_is_refused_whole() -> void:
	GameState.money = 77
	GameState.day = 5
	var broken: Dictionary[String, Variant] = {
		"day": "tomorrow",
		"day_time": "noon",
		"selected_seed": 3,
		"seeds": [],
		"produce": null,
		"prices": "cheap",
		"previous_prices": [1, 2],
		"economy": "rich",
	}
	for key: String in broken:
		var payload := _valid_payload()
		payload[key] = broken[key]
		assert_bool(GameState.can_restore(payload)).override_failure_message(
			"A save with %s = %s must be refused" % [key, broken[key]]).is_false()
		assert_bool(GameState.from_dict(payload)).is_false()
	for key: String in ["money", "day", "seeds", "produce", "prices"]:
		var payload := _valid_payload()
		payload.erase(key)
		assert_bool(GameState.can_restore(payload)).override_failure_message(
			"A save without %s must be refused" % key).is_false()
	var unknown_economy := _valid_payload()
	unknown_economy["economy"] = {"generation": "pirate"}
	assert_bool(GameState.from_dict(unknown_economy)).is_false()

	assert_int(GameState.money).is_equal(77)
	assert_int(GameState.day).is_equal(5)


func test_a_save_accepts_a_seed_name_of_either_string_type() -> void:
	var payload := _valid_payload()
	payload["selected_seed"] = &"pumpkin"

	assert_bool(GameState.from_dict(payload)).is_true()

	assert_str(GameState.selected_seed).is_equal("pumpkin")
