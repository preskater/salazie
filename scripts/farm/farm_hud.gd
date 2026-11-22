class_name FarmHUD
extends CanvasLayer

const TEXT_DARK := Color(0.22, 0.14, 0.08)
const POSITIVE := Color(0.12, 0.42, 0.16)
const NEGATIVE := Color(0.62, 0.14, 0.1)

@onready var money_label: Label = %MoneyLabel
@onready var day_label: Label = %DayLabel
@onready var prices_panel: PanelContainer = %PricesPanel
@onready var price_list: VBoxContainer = %PriceList
@onready var objective_label: Label = %ObjectiveLabel
@onready var prompt_panel: PanelContainer = %PromptPanel
@onready var prompt_label: Label = %PromptLabel
@onready var dialogue_panel: PanelContainer = %DialoguePanel
@onready var dialogue_speaker: Label = %DialogueSpeaker
@onready var dialogue_text: Label = %DialogueText
@onready var notification_label: Label = %NotificationLabel
@onready var market_overlay: Control = %MarketOverlay
@onready var market_day_label: Label = %MarketDayLabel
@onready var market_message: Label = %MarketMessage
@onready var sell_rows: VBoxContainer = %SellRows
@onready var buy_rows: VBoxContainer = %BuyRows
@onready var close_button: Button = %CloseButton
@onready var inventory_overlay: Control = %InventoryOverlay
@onready var inventory_context: Label = %InventoryContext
@onready var produce_grid: GridContainer = %ProduceGrid
@onready var produce_empty: Label = %ProduceEmpty
@onready var seed_grid: GridContainer = %SeedGrid
@onready var seed_empty: Label = %SeedEmpty
@onready var inventory_close_button: Button = %InventoryCloseButton
@onready var controls_label: Label = %ControlsLabel
@onready var inventory_hint: Label = %InventoryHint

const SLOT_SCENE := preload("res://scenes/farm/ui/item_slot.tscn")

var _price_labels := {}
const NOTIFICATION_TIME := 3.5
const MIN_NOTIFICATION_TIME := 1.6

var _sell_buttons := {}
var _buy_buttons := {}
var _extra_offers: Array[EconomyOffer] = []
var _extra_buy_buttons: Dictionary[StringName, Button] = {}
var _extra_sell_buttons: Dictionary[StringName, Button] = {}
var _seed_slots := {}
var _produce_slots := {}
var _icons := {}
var _prompt_text := ""
var _pending_notifications: Array[String] = []
var _market_open := false
var _inventory_open := false

func _ready() -> void:
	market_overlay.visible = false
	inventory_overlay.visible = false
	prices_panel.visible = false
	close_button.pressed.connect(close_market)
	inventory_close_button.pressed.connect(close_inventory)
	$NotificationTimer.timeout.connect(_hide_notification)
	$DialogueTimer.timeout.connect(_hide_dialogue)
	_build_price_rows()
	_build_market_rows()
	_build_inventory_rows()
	GameState.money_changed.connect(_on_money_changed)
	GameState.inventory_changed.connect(_refresh_inventory_popup)
	GameState.inventory_changed.connect(_refresh_market)
	GameState.prices_changed.connect(_refresh_prices)
	GameState.prices_changed.connect(_refresh_market)
	GameState.day_changed.connect(_on_day_changed)
	GameState.seed_changed.connect(_on_seed_changed)
	GameState.notification_requested.connect(notify)
	GameState.dialogue_requested.connect(show_dialogue)
	Economy.economy_enabled_changed.connect(_on_economy_enabled_changed)
	InputHints.device_changed.connect(_refresh_input_hints.unbind(1))
	_refresh_input_hints()
	_refresh_all()


## Texts that name a key or a button follow the device in use.
func _refresh_input_hints() -> void:
	controls_label.text = InputHints.format(
		"{move} · {interact} interagir · {select_seed} graines · {toggle_inventory} inventaire"
		+ " · {toggle_prices} prix · {pause} pause")
	inventory_hint.text = InputHints.format(
		"En jeu, {select_seed} choisit la graine à planter.")
	close_button.text = "Fermer (%s)" % InputHints.label(&"ui_cancel")
	inventory_close_button.text = InputHints.format("Fermer ({toggle_inventory} / %s)"
		% InputHints.label(&"ui_cancel"))

func set_prompt(text: String) -> void:
	if text == _prompt_text:
		return
	_prompt_text = text
	prompt_label.text = text
	prompt_panel.visible = not text.is_empty()

func set_objective(text: String) -> void:
	objective_label.text = text

## Shows a message. When several arrive together (day 6 brings the new prices,
## the missed deadline and the cyclone in one frame) each one gets
## `MIN_NOTIFICATION_TIME` on screen instead of only the last being seen.
func notify(text: String) -> void:
	var timer: Timer = $NotificationTimer
	if notification_label.visible and not timer.is_stopped():
		_pending_notifications.append(text)
		var shown_for := timer.wait_time - timer.time_left
		timer.start(maxf(0.05, MIN_NOTIFICATION_TIME - shown_for))
		return
	_show_notification(text)


func _show_notification(text: String) -> void:
	notification_label.text = text
	notification_label.visible = true
	$NotificationTimer.start(MIN_NOTIFICATION_TIME if not _pending_notifications.is_empty()
		else NOTIFICATION_TIME)

func show_dialogue(speaker: String, text: String) -> void:
	dialogue_speaker.text = speaker
	dialogue_text.text = text
	dialogue_panel.visible = true
	$DialogueTimer.start()

func open_market() -> void:
	if _market_open or _inventory_open:
		return
	_market_open = true
	market_message.text = ""
	_refresh_market()
	market_overlay.visible = true
	get_tree().paused = true
	close_button.grab_focus()

func close_market() -> void:
	if not _market_open:
		return
	_market_open = false
	market_overlay.visible = false
	market_message.text = ""
	get_tree().paused = false

func open_inventory() -> void:
	if _inventory_open or _market_open:
		return
	_inventory_open = true
	_refresh_inventory_popup()
	inventory_overlay.visible = true
	get_tree().paused = true
	var first: Control = _first_visible_slot(seed_grid)
	if first == null:
		first = _first_visible_slot(produce_grid)
	if first == null:
		first = inventory_close_button
	first.grab_focus()


func _first_visible_slot(grid: Container) -> Control:
	for child: Node in grid.get_children():
		var control := child as Control
		if control != null and control.visible:
			return control
	return null

func close_inventory() -> void:
	if not _inventory_open:
		return
	_inventory_open = false
	inventory_overlay.visible = false
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	# Another system (the pause menu) owns the paused tree: keep HUD toggles closed.
	if get_tree().paused and not _market_open and not _inventory_open:
		return
	if _market_open:
		if event.is_action_pressed("ui_cancel"):
			close_market()
			get_viewport().set_input_as_handled()
		return
	if _inventory_open:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_inventory"):
			close_inventory()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_inventory"):
		open_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_prices"):
		prices_panel.visible = not prices_panel.visible
		get_viewport().set_input_as_handled()

func _hide_notification() -> void:
	if not _pending_notifications.is_empty():
		_show_notification(_pending_notifications.pop_front())
		return
	notification_label.visible = false

func _hide_dialogue() -> void:
	dialogue_panel.visible = false

func _build_price_rows() -> void:
	for crop: String in GameState.CROP_ORDER:
		var row := Label.new()
		row.name = "Price_" + crop
		price_list.add_child(row)
		_price_labels[crop] = row

func _build_market_rows() -> void:
	for crop: String in GameState.CROP_ORDER:
		var sell := Button.new()
		sell.name = "Sell_" + crop
		sell.custom_minimum_size = Vector2(0, 38)
		sell.pressed.connect(_on_sell.bind(crop))
		sell_rows.add_child(sell)
		_sell_buttons[crop] = sell
		var buy := Button.new()
		buy.name = "Buy_" + crop
		buy.custom_minimum_size = Vector2(0, 38)
		buy.pressed.connect(_on_buy.bind(crop))
		buy_rows.add_child(buy)
		_buy_buttons[crop] = buy
	_build_extra_rows()


func _build_extra_rows() -> void:
	_extra_offers.clear()
	if Economy.generation() == null or not Economy.is_enabled():
		return
	for offer: EconomyOffer in Economy.offers():
		_extra_offers.append(offer)
	if _extra_offers.is_empty():
		return
	_add_section_label(sell_rows, "OBJETS & PROPRIÉTÉS")
	_add_section_label(buy_rows, "OBJETS & PROPRIÉTÉS")
	for offer: EconomyOffer in _extra_offers:
		var buy := Button.new()
		buy.name = "Buy_" + String(offer.id)
		buy.custom_minimum_size = Vector2(0, 38)
		buy.pressed.connect(_on_buy_extra.bind(offer.id))
		buy_rows.add_child(buy)
		_extra_buy_buttons[offer.id] = buy
		if offer.is_sellable():
			var sell := Button.new()
			sell.name = "Sell_" + String(offer.id)
			sell.custom_minimum_size = Vector2(0, 38)
			sell.pressed.connect(_on_sell_extra.bind(offer.id))
			sell_rows.add_child(sell)
			_extra_sell_buttons[offer.id] = sell


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.42, 0.22, 0.03, 1))
	parent.add_child(label)

func _build_inventory_rows() -> void:
	for crop: String in GameState.CROP_ORDER:
		var data: Dictionary = GameState.CROPS[crop]
		_icons[crop] = {
			"seed": load(String(data["icon"])),
			"produce": load(String(data["produce_icon"])),
		}

		var produce: ItemSlot = SLOT_SCENE.instantiate()
		produce.name = "Produce_" + crop
		produce_grid.add_child(produce)
		_produce_slots[crop] = produce

		var seed: ItemSlot = SLOT_SCENE.instantiate()
		seed.name = "Seed_" + crop
		seed.pressed.connect(_on_inventory_seed.bind(crop))
		seed_grid.add_child(seed)
		_seed_slots[crop] = seed

func _refresh_all() -> void:
	_on_money_changed(GameState.money)
	day_label.text = "Jour %d" % GameState.day
	_refresh_prices()
	_refresh_inventory_popup()
	_refresh_market()

func _on_money_changed(_value: int) -> void:
	money_label.text = "Argent : %s" % GameState.format_wallets()
	_refresh_inventory_popup()
	_refresh_market()


func _on_economy_enabled_changed(_enabled: bool) -> void:
	_on_money_changed(GameState.money)

func _on_day_changed(day: int) -> void:
	day_label.text = "Jour %d" % day
	GameState.announce("Jour %d — les prix du marché changent." % day)
	_refresh_prices()
	_refresh_inventory_popup()
	_refresh_market()

func _on_seed_changed(_crop: String) -> void:
	_refresh_inventory_popup()

func _refresh_inventory_popup() -> void:
	inventory_context.text = "Argent : %s · Jour %d" % [
		GameState.format_wallets(), GameState.day]

	var produce_visible := 0
	var seed_visible := 0
	for crop: String in GameState.CROP_ORDER:
		var data: Dictionary = GameState.CROPS[crop]
		var label := String(data["label"])
		var icons: Dictionary = _icons[crop]

		var produce_count := GameState.produce_count(crop)
		var produce_slot: ItemSlot = _produce_slots[crop]
		produce_slot.setup(icons["produce"], produce_count, false,
			"%s — %d dans le panier" % [label, produce_count])
		produce_slot.visible = produce_count > 0
		if produce_slot.visible:
			produce_visible += 1

		var seed_count := GameState.seed_count(crop)
		var seed_slot: ItemSlot = _seed_slots[crop]
		seed_slot.setup(icons["seed"], seed_count, crop == GameState.selected_seed,
			"%s — %d graines" % [label, seed_count])
		seed_slot.visible = seed_count > 0
		if seed_slot.visible:
			seed_visible += 1

	produce_grid.visible = produce_visible > 0
	produce_empty.visible = produce_visible == 0
	seed_grid.visible = seed_visible > 0
	seed_empty.visible = seed_visible == 0

func _on_inventory_seed(crop: String) -> void:
	GameState.select_seed(crop)
	_refresh_inventory_popup()

func _refresh_prices() -> void:
	for crop: String in GameState.CROP_ORDER:
		var label := String(GameState.CROPS[crop]["label"])
		var price := int(GameState.prices[crop])
		var trend := GameState.price_trend(crop)
		var arrow := "·"
		var color := TEXT_DARK
		if trend > 0:
			arrow = "▲"
			color = POSITIVE
		elif trend < 0:
			arrow = "▼"
			color = NEGATIVE
		var row: Label = _price_labels[crop]
		row.text = "%s — %s %s" % [label, GameState.format_money(price), arrow]
		row.add_theme_color_override("font_color", color)

func _refresh_market() -> void:
	if not _market_open:
		return
	var economy_on := GameState.is_economy_enabled()
	if economy_on:
		market_day_label.text = "Jour %d — %s. Les prix changent chaque jour." % [
			GameState.day, GameState.currency_label()]
	else:
		market_day_label.text = "Économie désactivée pour cette génération."
	for crop: String in GameState.CROP_ORDER:
		var label := String(GameState.CROPS[crop]["label"]).to_lower()
		var count := GameState.produce_count(crop)
		var price := int(GameState.prices[crop])
		var sell: Button = _sell_buttons[crop]
		sell.text = "Vendre tout le %s (%d) — %s" % [
			label, count, GameState.format_money(price * count)]
		sell.disabled = not economy_on or count <= 0
		var seed_price := int(GameState.CROPS[crop]["seed_price"])
		var buy: Button = _buy_buttons[crop]
		buy.text = "Acheter 1 graine de %s — %s" % [
			label, GameState.format_money(seed_price)]
		buy.disabled = not economy_on or GameState.money < seed_price
	_refresh_extra_rows()


func _refresh_extra_rows() -> void:
	for offer: EconomyOffer in _extra_offers:
		var buy: Button = _extra_buy_buttons.get(offer.id)
		if buy != null:
			var suffix := ""
			var stock := Economy.offer_stock(offer.id)
			if stock >= 0:
				suffix = " (reste %d)" % stock
			elif Economy.owned_count(offer.asset_id()) > 0:
				suffix = " (possédé ×%d)" % Economy.owned_count(offer.asset_id())
			buy.text = "Acheter %s — %s%s" % [
				offer.label, Economy.format_amount(offer.currency_id, offer.price), suffix]
			buy.disabled = not Economy.can_buy(offer.id)
		var sell: Button = _extra_sell_buttons.get(offer.id)
		if sell != null:
			var count := Economy.owned_count(offer.asset_id())
			sell.text = "Vendre %s (%d) — %s" % [
				offer.label, count, Economy.format_amount(offer.currency_id, offer.sell_price)]
			sell.disabled = not Economy.can_sell(offer.id)

func _on_sell(crop: String) -> void:
	var count := GameState.produce_count(crop)
	if count <= 0:
		return
	var label := String(GameState.CROPS[crop]["label"])
	var total := GameState.sell(crop, count)
	market_message.text = "Vente : %d × %s — +%s" % [
		count, label, GameState.format_money(total)]
	_refresh_market()
	_keep_focus_valid()

func _on_buy(crop: String) -> void:
	var label := String(GameState.CROPS[crop]["label"])
	var seed_price := int(GameState.CROPS[crop]["seed_price"])
	if GameState.buy_seed(crop):
		market_message.text = "Achat : 1 graine de %s — %s" % [
			label.to_lower(), GameState.format_money(seed_price)]
	else:
		market_message.text = "Pas assez d'argent."
	_refresh_market()
	_keep_focus_valid()


func _on_buy_extra(offer_id: StringName) -> void:
	var target := Economy.offer(offer_id)
	if target == null:
		return
	if Economy.buy(offer_id):
		market_message.text = "Achat : %s — %s" % [
			target.label, Economy.format_amount(target.currency_id, target.price)]
	else:
		market_message.text = "Achat impossible (fonds, stock ou économie désactivée)."
	_refresh_market()
	_keep_focus_valid()


func _on_sell_extra(offer_id: StringName) -> void:
	var target := Economy.offer(offer_id)
	if target == null:
		return
	if not Economy.can_sell(offer_id):
		market_message.text = "Vente impossible."
		_refresh_market()
		_keep_focus_valid()
		return
	var total := Economy.sell(offer_id)
	market_message.text = "Vente : %s — +%s" % [
		target.label, Economy.format_amount(target.currency_id, total)]
	_refresh_market()
	_keep_focus_valid()

func _keep_focus_valid() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is Button and (focus as Button).disabled:
		close_button.grab_focus()
