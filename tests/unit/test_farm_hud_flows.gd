extends GdUnitTestSuite
## The farm HUD seen from the player's side: who owns the pause, what the keys
## do while a panel is open, what the market answers and where the focus goes.

const HUD_SCENE := preload("res://scenes/farm/farm_hud.tscn")

var _original_config: EconomyConfig


func before_test() -> void:
	_original_config = Economy.config
	GameState.playing = false
	GameState.farm_active = true
	GameState.reset()


func after_test() -> void:
	if get_tree() != null:
		get_tree().paused = false
	if _original_config != null:
		Economy.apply_config(_original_config, _original_config.default_generation)
	GameState.playing = false
	GameState.reset()


func _spawn_hud() -> FarmHUD:
	var hud: FarmHUD = auto_free(HUD_SCENE.instantiate())
	add_child(hud)
	return hud


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _button(hud: FarmHUD, button_name: String) -> Button:
	var rows: VBoxContainer = hud.sell_rows if button_name.begins_with("Sell_") else hud.buy_rows
	return rows.get_node_or_null(button_name) as Button


func _focus(hud: FarmHUD) -> Control:
	return hud.get_viewport().gui_get_focus_owner()


# --- Market: pause and keys --------------------------------------------------

func test_the_market_pauses_the_farm_until_it_is_closed() -> void:
	var hud := _spawn_hud()
	assert_bool(hud.market_overlay.visible).is_false()

	hud.open_market()

	assert_bool(hud.market_overlay.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_object(_focus(hud)).is_same(hud.close_button)
	assert_str(hud.market_day_label.text).contains("Jour 1").contains("Gourde")

	hud.close_button.pressed.emit()

	assert_bool(hud.market_overlay.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_the_market_and_the_inventory_never_open_together() -> void:
	var hud := _spawn_hud()

	hud.open_market()
	hud.open_inventory()
	assert_bool(hud.inventory_overlay.visible).is_false()
	# Opening the market again keeps the message of the last transaction.
	hud.market_message.text = "Vente en cours"
	hud.open_market()
	assert_str(hud.market_message.text).is_equal("Vente en cours")
	hud.close_market()
	assert_str(hud.market_message.text).is_empty()

	hud.open_inventory()
	hud.open_market()
	assert_bool(hud.inventory_overlay.visible).is_true()
	assert_bool(hud.market_overlay.visible).is_false()
	assert_bool(get_tree().paused).is_true()


func test_closing_a_panel_that_is_not_open_leaves_someone_elses_pause() -> void:
	var hud := _spawn_hud()
	get_tree().paused = true

	hud.close_market()
	hud.close_inventory()

	assert_bool(get_tree().paused).is_true()


func test_cancel_closes_the_market_and_other_keys_are_ignored() -> void:
	var hud := _spawn_hud()
	hud.open_market()

	hud._unhandled_input(_press(&"toggle_inventory"))
	hud._unhandled_input(_press(&"toggle_prices"))
	assert_bool(hud.market_overlay.visible).is_true()
	assert_bool(hud.inventory_overlay.visible).is_false()
	assert_bool(hud.prices_panel.visible).is_false()

	hud._unhandled_input(_press(&"ui_cancel"))

	assert_bool(hud.market_overlay.visible).is_false()
	assert_bool(get_tree().paused).is_false()


# --- Inventory: pause and keys -----------------------------------------------

func test_the_inventory_key_opens_and_closes_the_inventory() -> void:
	var hud := _spawn_hud()

	hud._unhandled_input(_press(&"toggle_inventory"))
	assert_bool(hud.inventory_overlay.visible).is_true()
	assert_bool(get_tree().paused).is_true()
	assert_str(hud.inventory_context.text).is_equal("Argent : 30 G · Jour 1")

	hud._unhandled_input(_press(&"toggle_prices"))
	assert_bool(hud.prices_panel.visible).is_false()
	assert_bool(hud.inventory_overlay.visible).is_true()

	hud._unhandled_input(_press(&"toggle_inventory"))
	assert_bool(hud.inventory_overlay.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_cancel_and_the_close_button_close_the_inventory() -> void:
	var hud := _spawn_hud()

	hud.open_inventory()
	hud._unhandled_input(_press(&"ui_cancel"))
	assert_bool(hud.inventory_overlay.visible).is_false()
	assert_bool(get_tree().paused).is_false()

	hud.open_inventory()
	hud.inventory_close_button.pressed.emit()
	assert_bool(hud.inventory_overlay.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_the_inventory_focuses_the_first_thing_the_farmer_owns() -> void:
	var hud := _spawn_hud()

	hud.open_inventory()
	assert_object(_focus(hud)).is_same(hud.seed_grid.get_node("Seed_corn"))
	hud.close_inventory()

	GameState.seeds["corn"] = 0
	hud.open_inventory()
	assert_object(_focus(hud)).is_same(hud.seed_grid.get_node("Seed_pumpkin"))
	hud.close_inventory()

	for crop: String in GameState.CROP_ORDER:
		GameState.seeds[crop] = 0
	GameState.add_produce("tomato", 2)
	hud.open_inventory()
	assert_object(_focus(hud)).is_same(hud.produce_grid.get_node("Produce_tomato"))
	assert_bool(hud.seed_empty.visible).is_true()
	hud.close_inventory()

	GameState.produce["tomato"] = 0
	hud.open_inventory()
	assert_object(_focus(hud)).is_same(hud.inventory_close_button)
	assert_bool(hud.produce_empty.visible).is_true()


func test_the_hud_keys_are_dead_while_another_menu_holds_the_pause() -> void:
	var hud := _spawn_hud()
	get_tree().paused = true

	hud._unhandled_input(_press(&"toggle_inventory"))
	hud._unhandled_input(_press(&"toggle_prices"))

	assert_bool(hud.inventory_overlay.visible).is_false()
	assert_bool(hud.prices_panel.visible).is_false()
	assert_bool(get_tree().paused).is_true()


# --- Prices, prompt, objective and timed messages -----------------------------

func test_the_price_key_shows_and_hides_the_price_list() -> void:
	var hud := _spawn_hud()
	assert_bool(hud.prices_panel.visible).is_false()

	hud._unhandled_input(_press(&"toggle_prices"))
	assert_bool(hud.prices_panel.visible).is_true()
	hud._unhandled_input(_press(&"interact"))
	assert_bool(hud.prices_panel.visible).is_true()

	hud._unhandled_input(_press(&"toggle_prices"))
	assert_bool(hud.prices_panel.visible).is_false()
	assert_bool(get_tree().paused).is_false()


func test_each_price_shows_whether_it_went_up_or_down() -> void:
	var hud := _spawn_hud()
	GameState.previous_prices = {"corn": 10, "pumpkin": 16, "tomato": 9, "carrot": 7}
	GameState.prices = {"corn": 12, "pumpkin": 13, "tomato": 9, "carrot": 7}

	GameState.prices_changed.emit()

	var corn: Label = hud.price_list.get_node("Price_corn")
	var pumpkin: Label = hud.price_list.get_node("Price_pumpkin")
	var tomato: Label = hud.price_list.get_node("Price_tomato")
	assert_str(corn.text).is_equal("Maïs — 12 G ▲")
	assert_str(pumpkin.text).is_equal("Potiron — 13 G ▼")
	assert_str(tomato.text).is_equal("Tomate — 9 G ·")
	assert_that(corn.get_theme_color("font_color")).is_equal(FarmHUD.POSITIVE)
	assert_that(pumpkin.get_theme_color("font_color")).is_equal(FarmHUD.NEGATIVE)
	assert_that(tomato.get_theme_color("font_color")).is_equal(FarmHUD.TEXT_DARK)


func test_the_prompt_is_hidden_when_there_is_nothing_to_do() -> void:
	var hud := _spawn_hud()

	hud.set_prompt("Récolter Maïs")
	assert_bool(hud.prompt_panel.visible).is_true()
	assert_str(hud.prompt_label.text).is_equal("Récolter Maïs")

	# The same prompt again must not undo what was hidden in between.
	hud.prompt_panel.visible = false
	hud.set_prompt("Récolter Maïs")
	assert_bool(hud.prompt_panel.visible).is_false()

	hud.set_prompt("Marché de Salazie")
	assert_bool(hud.prompt_panel.visible).is_true()
	hud.set_prompt("")
	assert_bool(hud.prompt_panel.visible).is_false()
	assert_str(hud.prompt_label.text).is_empty()


func test_the_objective_is_written_as_given() -> void:
	var hud := _spawn_hud()

	hud.set_objective("Objectif : vendez une récolte.")

	assert_str(hud.objective_label.text).is_equal("Objectif : vendez une récolte.")


func test_a_notification_disappears_after_its_delay() -> void:
	var hud := _spawn_hud()
	var timer: Timer = hud.get_node("NotificationTimer")
	timer.wait_time = 0.05

	GameState.announce("Parcelle préparée.")
	assert_bool(hud.notification_label.visible).is_true()
	assert_str(hud.notification_label.text).is_equal("Parcelle préparée.")
	assert_bool(timer.is_stopped()).is_false()

	await timer.timeout

	assert_bool(hud.notification_label.visible).is_false()


func test_a_dialogue_disappears_after_its_delay() -> void:
	var hud := _spawn_hud()
	var timer: Timer = hud.get_node("DialogueTimer")
	timer.wait_time = 0.05

	GameState.show_dialogue("Marchande", "Bienvenue à Salazie.")
	assert_bool(hud.dialogue_panel.visible).is_true()
	assert_str(hud.dialogue_speaker.text).is_equal("Marchande")
	assert_str(hud.dialogue_text.text).is_equal("Bienvenue à Salazie.")

	await timer.timeout

	assert_bool(hud.dialogue_panel.visible).is_false()


func test_a_new_day_is_announced_and_shown() -> void:
	var hud := _spawn_hud()

	GameState.day = 4
	GameState.day_changed.emit(4)

	assert_str(hud.day_label.text).is_equal("Jour 4")
	assert_str(hud.notification_label.text).contains("Jour 4")
	assert_bool(hud.notification_label.visible).is_true()


# --- Market: crops -----------------------------------------------------------

func test_selling_a_harvest_empties_the_basket_and_says_what_was_earned() -> void:
	var hud := _spawn_hud()
	GameState.add_produce("corn", 2)
	hud.open_market()
	var sell := _button(hud, "Sell_corn")
	assert_str(sell.text).is_equal("Vendre tout le maïs (2) — 20 G")
	assert_bool(sell.disabled).is_false()
	assert_bool(_button(hud, "Sell_tomato").disabled).is_true()

	sell.pressed.emit()

	assert_str(hud.market_message.text).is_equal("Vente : 2 × Maïs — +20 G")
	assert_int(GameState.money).is_equal(50)
	assert_int(GameState.produce_count("corn")).is_equal(0)
	assert_str(sell.text).is_equal("Vendre tout le maïs (0) — 0 G")
	assert_bool(sell.disabled).is_true()
	assert_str(hud.money_label.text).is_equal("Argent : 50 G")


func test_selling_an_empty_basket_says_nothing() -> void:
	var hud := _spawn_hud()
	hud.open_market()

	_button(hud, "Sell_corn").pressed.emit()

	assert_str(hud.market_message.text).is_empty()
	assert_int(GameState.money).is_equal(30)


func test_buying_a_seed_says_what_it_cost() -> void:
	var hud := _spawn_hud()
	hud.open_market()
	var buy := _button(hud, "Buy_pumpkin")
	assert_str(buy.text).is_equal("Acheter 1 graine de potiron — 6 G")

	buy.pressed.emit()

	assert_str(hud.market_message.text).is_equal("Achat : 1 graine de potiron — 6 G")
	assert_int(GameState.money).is_equal(24)
	assert_int(GameState.seed_count("pumpkin")).is_equal(2)


func test_a_seed_the_farmer_cannot_pay_is_refused() -> void:
	var hud := _spawn_hud()
	GameState.money = 5
	hud.open_market()
	var buy := _button(hud, "Buy_pumpkin")
	assert_bool(buy.disabled).is_true()
	assert_bool(_button(hud, "Buy_carrot").disabled).is_false()

	buy.pressed.emit()

	assert_str(hud.market_message.text).is_equal("Pas assez d'argent.")
	assert_int(GameState.money).is_equal(5)
	assert_int(GameState.seed_count("pumpkin")).is_equal(1)


func test_the_focus_leaves_a_button_that_just_became_useless() -> void:
	var hud := _spawn_hud()
	GameState.add_produce("corn", 1)
	GameState.add_produce("tomato", 1)
	hud.open_market()
	var sell_corn := _button(hud, "Sell_corn")
	var buy_carrot := _button(hud, "Buy_carrot")

	# Still affordable after the purchase: the focus stays where it is.
	buy_carrot.grab_focus()
	buy_carrot.pressed.emit()
	assert_object(_focus(hud)).is_same(buy_carrot)

	sell_corn.grab_focus()
	sell_corn.pressed.emit()

	assert_bool(sell_corn.disabled).is_true()
	assert_object(_focus(hud)).is_same(hud.close_button)


# --- Market: buildings, land and tools -----------------------------------------

func test_an_offer_out_of_reach_is_refused_with_a_reason() -> void:
	var hud := _spawn_hud()
	hud.open_market()
	var buy := _button(hud, "Buy_building_barn")
	assert_str(buy.text).is_equal("Acheter Grange — 60 G (reste 1)")
	assert_bool(buy.disabled).is_true()

	buy.pressed.emit()

	assert_str(hud.market_message.text).is_equal(
		"Achat impossible (fonds, stock ou économie désactivée).")
	assert_int(Economy.owned_count(&"barn")).is_equal(0)
	assert_int(GameState.money).is_equal(30)


func test_what_is_not_owned_cannot_be_sold() -> void:
	var hud := _spawn_hud()
	hud.open_market()
	var sell := _button(hud, "Sell_item_hoe")
	assert_str(sell.text).is_equal("Vendre Houe (0) — 8 G")
	assert_bool(sell.disabled).is_true()

	sell.pressed.emit()

	assert_str(hud.market_message.text).is_equal("Vente impossible.")
	assert_int(GameState.money).is_equal(30)


func test_buying_then_selling_a_tool_updates_both_columns() -> void:
	var hud := _spawn_hud()
	hud.open_market()
	var buy := _button(hud, "Buy_item_hoe")
	var sell := _button(hud, "Sell_item_hoe")

	buy.grab_focus()
	buy.pressed.emit()

	assert_str(hud.market_message.text).is_equal("Achat : Houe — 20 G")
	assert_str(buy.text).is_equal("Acheter Houe — 20 G (reste 0)")
	assert_bool(buy.disabled).is_true()
	assert_str(sell.text).is_equal("Vendre Houe (1) — 8 G")
	assert_bool(sell.disabled).is_false()
	assert_object(_focus(hud)).is_same(hud.close_button)

	sell.pressed.emit()

	assert_str(hud.market_message.text).is_equal("Vente : Houe — +8 G")
	assert_int(GameState.money).is_equal(18)
	assert_bool(buy.disabled).is_true()
	assert_str(buy.text).is_equal("Acheter Houe — 20 G (reste 1)")
	assert_bool(sell.disabled).is_true()


func test_an_unlimited_offer_shows_how_many_are_owned() -> void:
	Economy.select_generation(&"heritier")
	var hud := _spawn_hud()
	hud.open_market()
	var buy := _button(hud, "Buy_item_seedling_kit")
	assert_str(buy.text).is_equal("Acheter Jeunes plants — 15 €")

	buy.pressed.emit()
	buy.pressed.emit()

	assert_str(buy.text).is_equal("Acheter Jeunes plants — 15 € (possédé ×2)")
	assert_str(hud.money_label.text).is_equal("Argent : 90 € · 5 CV")
	assert_str(_button(hud, "Sell_item_seedling_kit").text).is_equal(
		"Vendre Jeunes plants (2) — 5 €")


func test_the_buttons_of_a_past_generation_do_nothing() -> void:
	var hud := _spawn_hud()
	hud.open_market()
	GameState.money = 200
	# The HUD was built for the farm; the economy moves on without it.
	Economy.select_generation(&"heritier")

	_button(hud, "Buy_building_barn").pressed.emit()
	_button(hud, "Sell_building_barn").pressed.emit()

	assert_str(hud.market_message.text).is_empty()
	assert_int(Economy.owned_count(&"barn")).is_equal(0)
	assert_int(Economy.balance(&"euro")).is_equal(120)


# --- Market without an economy -------------------------------------------------

func test_a_generation_without_an_economy_has_a_closed_market() -> void:
	Economy.select_generation(&"marron")
	var hud := _spawn_hud()
	GameState.add_produce("corn", 2)

	hud.open_market()

	assert_str(hud.market_day_label.text).is_equal("Économie désactivée pour cette génération.")
	assert_object(_button(hud, "Buy_building_barn")).is_null()
	for crop: String in GameState.CROP_ORDER:
		assert_bool(_button(hud, "Sell_" + crop).disabled).is_true()
		assert_bool(_button(hud, "Buy_" + crop).disabled).is_true()
	assert_int(hud.sell_rows.get_child_count()).is_equal(GameState.CROP_ORDER.size())


func test_switching_the_economy_off_closes_the_open_market() -> void:
	var hud := _spawn_hud()
	GameState.add_produce("corn", 2)
	GameState.money = 200
	hud.open_market()
	assert_bool(_button(hud, "Buy_building_barn").disabled).is_false()

	Economy.set_enabled(false)

	assert_str(hud.market_day_label.text).is_equal("Économie désactivée pour cette génération.")
	assert_bool(_button(hud, "Sell_corn").disabled).is_true()
	assert_bool(_button(hud, "Buy_corn").disabled).is_true()
	assert_bool(_button(hud, "Buy_building_barn").disabled).is_true()

	Economy.set_enabled(true)

	assert_bool(_button(hud, "Sell_corn").disabled).is_false()
	assert_bool(_button(hud, "Buy_building_barn").disabled).is_false()


func test_a_market_without_property_offers_only_lists_the_crops() -> void:
	var gourde := EconomyCurrency.new()
	gourde.id = &"gourde"
	gourde.symbol = "G"
	gourde.starting_balance = 30
	var generation := EconomyGeneration.new()
	generation.id = &"potager"
	var currencies: Array[EconomyCurrency] = [gourde]
	generation.currencies = currencies
	var config := EconomyConfig.new()
	var generations: Array[EconomyGeneration] = [generation]
	config.generations = generations
	config.default_generation = &"potager"
	assert_bool(Economy.apply_config(config)).is_true()

	var hud := _spawn_hud()
	hud.open_market()

	assert_int(hud.sell_rows.get_child_count()).is_equal(GameState.CROP_ORDER.size())
	assert_int(hud.buy_rows.get_child_count()).is_equal(GameState.CROP_ORDER.size())
	assert_bool(_button(hud, "Buy_corn").disabled).is_false()


func test_messages_arriving_together_are_each_shown() -> void:
	# Regression (#40): on day 6 the new prices, the missed deadline and the
	# cyclone were announced in one frame and only the last was ever seen.
	var hud := await _spawn_hud()
	var label: Label = hud.notification_label
	var timer: Timer = hud.get_node("NotificationTimer")

	hud.notify("Jour 6 — les prix changent")
	hud.notify("Le délai du marché est passé")
	hud.notify("Le cyclone traverse la ferme !")

	assert_str(label.text).is_equal("Jour 6 — les prix changent")
	assert_float(timer.time_left).is_less_equal(FarmHUD.MIN_NOTIFICATION_TIME)
	timer.timeout.emit()
	assert_str(label.text).is_equal("Le délai du marché est passé")
	assert_bool(label.visible).is_true()
	timer.timeout.emit()
	assert_str(label.text).is_equal("Le cyclone traverse la ferme !")
	# The last one keeps the full time.
	assert_float(timer.time_left).is_greater(FarmHUD.MIN_NOTIFICATION_TIME)
	timer.timeout.emit()
	assert_bool(label.visible).is_false()
