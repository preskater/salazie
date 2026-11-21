class_name EconomyGeneration
extends Resource
## Economy rules and market catalogue for one generation.

@export var id: StringName = &""
@export var label: String = ""
## Disabled generations keep their data but refuse every transaction.
@export var enabled := true
@export var allow_buy := true
@export var allow_sell := true
@export var allow_trade := true
@export var currencies: Array[EconomyCurrency] = []
@export var offers: Array[EconomyOffer] = []


func primary_currency_id() -> StringName:
	for currency: EconomyCurrency in currencies:
		if currency != null and currency.enabled and currency.id != &"":
			return currency.id
	return &""


func find_currency(currency_id: StringName) -> EconomyCurrency:
	for currency: EconomyCurrency in currencies:
		if currency != null and currency.id == currency_id:
			return currency
	return null


func find_offer(offer_id: StringName) -> EconomyOffer:
	for offer: EconomyOffer in offers:
		if offer != null and offer.id == offer_id:
			return offer
	return null
