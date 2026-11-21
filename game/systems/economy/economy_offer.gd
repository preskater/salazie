class_name EconomyOffer
extends Resource
## A purchasable item, building or slot in a generation's market.

enum Kind { ITEM, BUILDING, SLOT }

@export var id: StringName = &""
@export var label: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.ITEM
@export var currency_id: StringName = &""
@export var price: int = 0
## Negative means the offer cannot be sold back.
@export var sell_price: int = -1
## Negative means unlimited stock.
@export var stock: int = -1
## Ownership key; defaults to the offer id.
@export var grant_id: StringName = &""


func asset_id() -> StringName:
	return grant_id if grant_id != &"" else id


func is_sellable() -> bool:
	return sell_price >= 0
