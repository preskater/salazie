class_name FarmHUD
extends CanvasLayer

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
@onready var produce_list: VBoxContainer = %ProduceList
@onready var seed_list: VBoxContainer = %SeedList
@onready var inventory_close_button: Button = %InventoryCloseButton

var _price_labels := {}
var _sell_buttons := {}
var _buy_buttons := {}
var _produce_labels := {}
var _seed_buttons := {}
var _prompt_text := ""
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
	_refresh_all()

func set_prompt(text: String) -> void:
	if text == _prompt_text:
		return
	_prompt_text = text
	prompt_label.text = text
	prompt_panel.visible = not text.is_empty()

func set_objective(text: String) -> void:
	objective_label.text = text

func notify(text: String) -> void:
	notification_label.text = text
	notification_label.visible = true
	$NotificationTimer.start()

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
	inventory_close_button.grab_focus()

func close_inventory() -> void:
	if not _inventory_open:
		return
	_inventory_open = false
	inventory_overlay.visible = false
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
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

func _build_inventory_rows() -> void:
	for crop: String in GameState.CROP_ORDER:
		var produce := Label.new()
		produce.name = "Produce_" + crop
		produce_list.add_child(produce)
		_produce_labels[crop] = produce
		var seed_button := Button.new()
		seed_button.name = "Seed_" + crop
		seed_button.custom_minimum_size = Vector2(0, 38)
		seed_button.pressed.connect(_on_inventory_seed.bind(crop))
		seed_list.add_child(seed_button)
		_seed_buttons[crop] = seed_button

func _refresh_all() -> void:
	_on_money_changed(GameState.money)
	day_label.text = "Jour %d" % GameState.day
	_refresh_prices()
	_refresh_inventory_popup()
	_refresh_market()

func _on_money_changed(value: int) -> void:
	money_label.text = "Argent : %d G" % value
	_refresh_inventory_popup()
	_refresh_market()

func _on_day_changed(day: int) -> void:
	day_label.text = "Jour %d" % day
	GameState.announce("Jour %d — les prix du marché changent." % day)
	_refresh_prices()
	_refresh_inventory_popup()
	_refresh_market()

func _on_seed_changed(_crop: String) -> void:
	_refresh_inventory_popup()

func _refresh_inventory_popup() -> void:
	inventory_context.text = "Argent : %d G · Jour %d" % [GameState.money, GameState.day]
	for crop: String in GameState.CROP_ORDER:
		var name := String(GameState.CROPS[crop]["label"])
		var count := GameState.produce_count(crop)
		var produce: Label = _produce_labels[crop]
		produce.text = "%s : %d" % [name, count]
		produce.add_theme_color_override("font_color",
			Color(0.94, 0.92, 0.84) if count > 0 else Color(0.5, 0.5, 0.46))
		var seeds := GameState.seed_count(crop)
		var selected := crop == GameState.selected_seed
		var plural := "graines" if seeds > 1 else "graine"
		var button: Button = _seed_buttons[crop]
		button.text = "%s%s — %d %s" % ["▶ " if selected else "", name, seeds, plural]
		button.add_theme_color_override("font_color",
			Color(1.0, 0.93, 0.66) if selected else Color(0.94, 0.92, 0.84))

func _on_inventory_seed(crop: String) -> void:
	GameState.select_seed(crop)
	_refresh_inventory_popup()

func _refresh_prices() -> void:
	for crop: String in GameState.CROP_ORDER:
		var label := String(GameState.CROPS[crop]["label"])
		var price := int(GameState.prices[crop])
		var trend := GameState.price_trend(crop)
		var arrow := "·"
		var color := Color(0.94, 0.92, 0.84)
		if trend > 0:
			arrow = "▲"
			color = Color(0.6, 0.95, 0.6)
		elif trend < 0:
			arrow = "▼"
			color = Color(1.0, 0.58, 0.52)
		var row: Label = _price_labels[crop]
		row.text = "%s — %d G %s" % [label, price, arrow]
		row.add_theme_color_override("font_color", color)

func _refresh_market() -> void:
	if not _market_open:
		return
	market_day_label.text = "Jour %d — les prix changent chaque jour." % GameState.day
	for crop: String in GameState.CROP_ORDER:
		var label := String(GameState.CROPS[crop]["label"]).to_lower()
		var count := GameState.produce_count(crop)
		var price := int(GameState.prices[crop])
		var sell: Button = _sell_buttons[crop]
		sell.text = "Vendre tout le %s (%d) — %d G" % [label, count, price * count]
		sell.disabled = count <= 0
		var seed_price := int(GameState.CROPS[crop]["seed_price"])
		var buy: Button = _buy_buttons[crop]
		buy.text = "Acheter 1 graine de %s — %d G" % [label, seed_price]
		buy.disabled = GameState.money < seed_price

func _on_sell(crop: String) -> void:
	var count := GameState.produce_count(crop)
	if count <= 0:
		return
	var label := String(GameState.CROPS[crop]["label"])
	var total := GameState.sell(crop, count)
	market_message.text = "Vente : %d × %s — +%d G" % [count, label, total]
	_refresh_market()
	_keep_focus_valid()

func _on_buy(crop: String) -> void:
	var label := String(GameState.CROPS[crop]["label"])
	var seed_price := int(GameState.CROPS[crop]["seed_price"])
	if GameState.buy_seed(crop):
		market_message.text = "Achat : 1 graine de %s — %d G" % [label.to_lower(), seed_price]
	else:
		market_message.text = "Pas assez d'argent."
	_refresh_market()
	_keep_focus_valid()

func _keep_focus_valid() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is Button and (focus as Button).disabled:
		close_button.grab_focus()
