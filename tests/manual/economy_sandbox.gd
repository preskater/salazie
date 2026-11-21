extends Control
## Personal economy sandbox for manual testing. This file is git-ignored.
## Open the scene and press F6, or run:
## godot --path . --scene res://tests/manual/economy_sandbox.tscn

const TEST_SAVE_PATH := "user://economy_sandbox_save.json"

var _status_label: Label
var _wallet_label: Label
var _log_label: Label
var _save_label: Label
var _offer_grid: GridContainer
var _generation_buttons: Dictionary[StringName, Button] = {}
var _toggle_button: Button
var _add_button: Button
var _trade_currency_button: Button
var _trade_asset_button: Button
var _messages: Array[String] = []
var _refresh_pending := false
var _original_save_path := ""


func _ready() -> void:
	_original_save_path = SaveGame.save_path
	SaveGame.save_path = TEST_SAVE_PATH
	_build_ui()
	_connect_economy()
	_refresh()


func _exit_tree() -> void:
	SaveGame.save_path = _original_save_path


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.93, 0.87, 0.74)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Économie — bac à sable"
	title.add_theme_font_size_override("font_size", 28)
	outer.add_child(title)

	var note := Label.new()
	note.text = "Scène personnelle, non versionnée (voir .gitignore)."
	note.add_theme_font_size_override("font_size", 14)
	outer.add_child(note)

	_status_label = Label.new()
	outer.add_child(_status_label)
	_wallet_label = Label.new()
	outer.add_child(_wallet_label)

	var generation_row := HBoxContainer.new()
	generation_row.add_theme_constant_override("separation", 8)
	outer.add_child(generation_row)
	for generation: EconomyGeneration in _available_generations():
		var button := Button.new()
		button.name = "Generation_" + String(generation.id)
		button.text = generation.label if generation.label != "" else String(generation.id)
		button.pressed.connect(_on_generation_pressed.bind(generation.id))
		generation_row.add_child(button)
		_generation_buttons[generation.id] = button

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	outer.add_child(action_row)
	_toggle_button = _make_button(action_row, "ToggleEconomy", "Désactiver", _on_toggle_pressed)
	_add_button = _make_button(action_row, "AddPrimary", "Ajouter 100", _on_add_pressed)
	_make_button(action_row, "ResetEconomy", "Réinitialiser", _on_reset_pressed)

	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var offers_box := VBoxContainer.new()
	offers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_box.add_theme_constant_override("separation", 6)
	scroll.add_child(offers_box)

	var offers_title := Label.new()
	offers_title.text = "Marché — objets, bâtiments et emplacements"
	offers_title.add_theme_font_size_override("font_size", 20)
	offers_box.add_child(offers_title)

	_offer_grid = GridContainer.new()
	_offer_grid.name = "OfferGrid"
	_offer_grid.columns = 7
	_offer_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_box.add_child(_offer_grid)

	offers_box.add_child(HSeparator.new())
	var log_title := Label.new()
	log_title.text = "Journal"
	log_title.add_theme_font_size_override("font_size", 18)
	offers_box.add_child(log_title)
	_log_label = Label.new()
	_log_label.name = "Journal"
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.add_theme_font_size_override("font_size", 14)
	offers_box.add_child(_log_label)

	outer.add_child(HSeparator.new())

	var trade_row := HBoxContainer.new()
	trade_row.add_theme_constant_override("separation", 8)
	outer.add_child(trade_row)
	_trade_currency_button = _make_button(
		trade_row, "TradeCurrencies", "Échanger", _on_trade_currencies)
	_trade_asset_button = _make_button(trade_row, "TradeAsset", "Échanger", _on_trade_asset)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	outer.add_child(save_row)
	_make_button(save_row, "SaveButton", "Sauvegarder", _on_save)
	_make_button(save_row, "LoadButton", "Charger", _on_load)
	_make_button(save_row, "DeleteSaveButton", "Supprimer la sauvegarde", _on_delete_save)

	_save_label = Label.new()
	outer.add_child(_save_label)


func _make_button(
		parent: Node, button_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _connect_economy() -> void:
	Economy.generation_changed.connect(_on_generation_changed)
	Economy.economy_enabled_changed.connect(_on_enabled_changed)
	Economy.offer_purchased.connect(_on_offer_purchased)
	Economy.offer_sold.connect(_on_offer_sold)
	Economy.trade_completed.connect(_on_trade_completed)
	Economy.transaction_failed.connect(_on_transaction_failed)


func _available_generations() -> Array[EconomyGeneration]:
	var result: Array[EconomyGeneration] = []
	if Economy.config == null:
		return result
	for generation: EconomyGeneration in Economy.config.generations:
		if generation != null:
			result.append(generation)
	return result


func _schedule_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_refresh")


func _refresh() -> void:
	_refresh_pending = false
	if _status_label == null:
		return
	var generation := Economy.generation()
	var generation_label := generation.label if generation != null else "—"
	_status_label.text = "Génération : %s — économie %s" % [
		generation_label, "active" if Economy.is_enabled() else "désactivée"]
	_wallet_label.text = ("Portefeuilles : %s" % GameState.format_wallets()) \
		if Economy.is_enabled() else "Économie désactivée pour cette génération."
	_toggle_button.text = "Désactiver" if Economy.is_enabled() else "Activer"
	_toggle_button.disabled = generation == null or not generation.enabled
	var primary := Economy.primary_currency_id()
	_add_button.text = ("Ajouter 100 %s" % Economy.currency_symbol(primary)) \
		if primary != &"" else "Ajouter 100"
	_add_button.disabled = not Economy.is_enabled() or primary == &""
	for generation_id: StringName in _generation_buttons:
		var button: Button = _generation_buttons[generation_id]
		button.disabled = generation_id == Economy.current_generation_id()
	_refresh_offers()
	_refresh_trade()


func _refresh_offers() -> void:
	for child: Node in _offer_grid.get_children():
		_offer_grid.remove_child(child)
		child.queue_free()
	if not Economy.is_enabled():
		_add_grid_label("Économie désactivée.", true)
		return
	var offers := Economy.offers()
	if offers.is_empty():
		_add_grid_label("Aucune offre pour cette génération.", true)
		return
	for header: String in ["Type", "Offre", "Prix", "Stock", "Possédé", "Acheter", "Vendre"]:
		_add_grid_label(header)
	for offer: EconomyOffer in offers:
		_add_grid_label(_kind_label(offer.kind))
		_add_grid_label(offer.label)
		_add_grid_label(Economy.format_amount(offer.currency_id, offer.price))
		var stock := Economy.offer_stock(offer.id)
		_add_grid_label("∞" if stock < 0 else str(stock))
		_add_grid_label(str(Economy.owned_count(offer.asset_id())))

		var buy := Button.new()
		buy.name = "Buy_" + String(offer.id)
		buy.text = "Acheter"
		buy.disabled = not Economy.can_buy(offer.id)
		buy.pressed.connect(_on_buy_offer.bind(offer.id))
		_offer_grid.add_child(buy)

		var sell := Button.new()
		sell.name = "Sell_" + String(offer.id)
		sell.text = "Vendre" if offer.is_sellable() else "—"
		sell.disabled = not Economy.can_sell(offer.id)
		sell.pressed.connect(_on_sell_offer.bind(offer.id))
		_offer_grid.add_child(sell)


func _add_grid_label(text: String, expand := false) -> void:
	var label := Label.new()
	label.text = text
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offer_grid.add_child(label)


func _refresh_trade() -> void:
	var primary := Economy.primary_currency_id()
	var secondary := _secondary_currency_id()
	_trade_currency_button.visible = primary != &"" and secondary != &""
	_trade_currency_button.disabled = not Economy.is_enabled()
	if _trade_currency_button.visible:
		_trade_currency_button.text = "Échanger 10 %s → 1 %s" % [
			Economy.currency_symbol(primary), Economy.currency_symbol(secondary)]
		_trade_currency_button.disabled = not Economy.is_enabled() or Economy.balance(primary) < 10

	var target := _trade_asset_offer()
	_trade_asset_button.visible = primary != &"" and target != null
	if _trade_asset_button.visible:
		_trade_asset_button.text = "Échanger 5 %s → 1 %s" % [
			Economy.currency_symbol(primary), target.label]
		_trade_asset_button.disabled = not Economy.is_enabled() or Economy.balance(primary) < 5


func _trade_asset_offer() -> EconomyOffer:
	var offers := Economy.offers()
	for offer: EconomyOffer in offers:
		if offer.kind == EconomyOffer.Kind.ITEM:
			return offer
	return offers[0] if not offers.is_empty() else null


func _secondary_currency_id() -> StringName:
	var primary := Economy.primary_currency_id()
	for definition: EconomyCurrency in Economy.currencies():
		if definition != null and definition.enabled and definition.id != primary:
			return definition.id
	return &""


func _kind_label(kind: int) -> String:
	match kind:
		EconomyOffer.Kind.ITEM:
			return "Objet"
		EconomyOffer.Kind.BUILDING:
			return "Bâtiment"
		EconomyOffer.Kind.SLOT:
			return "Emplacement"
	return "—"


func _on_generation_pressed(generation_id: StringName) -> void:
	Economy.select_generation(generation_id)
	_log("Génération active : %s" % generation_id)
	_schedule_refresh()


func _on_toggle_pressed() -> void:
	Economy.set_enabled(not Economy.is_enabled())
	_log("Économie %s" % ("activée" if Economy.is_enabled() else "désactivée"))
	_schedule_refresh()


func _on_add_pressed() -> void:
	var primary := Economy.primary_currency_id()
	if Economy.add_currency(primary, 100):
		_log("+100 %s" % Economy.currency_symbol(primary))
	else:
		_log("Impossible d'ajouter de la monnaie.")
	_schedule_refresh()


func _on_reset_pressed() -> void:
	Economy.reset()
	_log("Génération réinitialisée.")
	_schedule_refresh()


func _on_buy_offer(offer_id: StringName) -> void:
	if not Economy.buy(offer_id):
		_log("Achat refusé : %s" % offer_id)
	_schedule_refresh()


func _on_sell_offer(offer_id: StringName) -> void:
	if not Economy.can_sell(offer_id):
		_log("Vente refusée : %s" % offer_id)
	else:
		Economy.sell(offer_id)
	_schedule_refresh()


func _on_trade_currencies() -> void:
	var primary := Economy.primary_currency_id()
	var secondary := _secondary_currency_id()
	if secondary == &"":
		return
	if not Economy.trade(
			{"currency": primary, "amount": 10},
			{"currency": secondary, "amount": 1}):
		_log("Échange de monnaies refusé.")
	_schedule_refresh()


func _on_trade_asset() -> void:
	var target := _trade_asset_offer()
	if target == null:
		return
	if not Economy.trade(
			{"currency": Economy.primary_currency_id(), "amount": 5},
			{"asset": target.asset_id(), "amount": 1}):
		_log("Échange contre un bien refusé.")
	_schedule_refresh()


func _on_save() -> void:
	var was_playing := GameState.playing
	GameState.playing = true
	var ok := SaveGame.save_game()
	GameState.playing = was_playing
	_save_label.text = ("Sauvegardé : %s" % SaveGame.save_path) if ok \
		else "Échec de la sauvegarde."
	_log(_save_label.text)


func _on_load() -> void:
	var ok := SaveGame.load_game()
	_save_label.text = "Partie chargée." if ok else "Aucune sauvegarde valide."
	_log(_save_label.text)
	_schedule_refresh()


func _on_delete_save() -> void:
	SaveGame.delete_save()
	_save_label.text = "Sauvegarde supprimée."
	_log(_save_label.text)


func _on_generation_changed(generation_id: StringName) -> void:
	_log("Signal generation_changed : %s" % generation_id)
	_schedule_refresh()


func _on_enabled_changed(enabled: bool) -> void:
	_log("Signal economy_enabled_changed : %s" % enabled)
	_schedule_refresh()


func _on_offer_purchased(offer: EconomyOffer, quantity: int) -> void:
	_log("Achat : %s ×%d" % [offer.label, quantity])


func _on_offer_sold(offer: EconomyOffer, quantity: int, total: int) -> void:
	_log("Vente : %s ×%d (+%s)" % [
		offer.label, quantity, Economy.format_amount(offer.currency_id, total)])


func _on_trade_completed(give: Dictionary, receive: Dictionary) -> void:
	_log("Échange : %s → %s" % [give, receive])


func _on_transaction_failed(reason: StringName) -> void:
	_log("Transaction refusée : %s" % reason)


func _log(message: String) -> void:
	_messages.push_front(message)
	if _messages.size() > 10:
		_messages.resize(10)
	if _log_label != null:
		var lines := PackedStringArray()
		for entry: String in _messages:
			lines.append(entry)
		_log_label.text = "\n".join(lines)
