extends Area2D
## A fragile place in the modern valley. Inspecting it is an `assess` task step;
## once inspected, the heir can pay for its protection, which wins support.

signal inspected(site_id: String, title: String, description: String)
signal funding_requested(site_id: String, offer_id: StringName)

@export var site_id := ""
@export var title := "Zone fragile"
@export_multiline var description := ""
@export var texture: Texture2D
@export var tint := Color.WHITE
## Offer of the heir's economy that protects this site. Empty: nothing to fund.
@export var fund_offer: StringName = &""

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("fragile_sites")
	if texture != null:
		sprite.texture = texture
	sprite.modulate = tint


func is_assessed() -> bool:
	return Campaign.get_choice("assessed_" + site_id) == "1"


func is_funded() -> bool:
	return Campaign.get_choice("funded_" + site_id) == "1"


func can_be_funded() -> bool:
	return is_assessed() and not is_funded() and Economy.offer(fund_offer) != null


func get_interaction_prompt() -> String:
	if can_be_funded():
		var offer := Economy.offer(fund_offer)
		return InputHints.prompt(&"interact", "Financer : %s (%s)" % [
			offer.label, Economy.format_amount(offer.currency_id, offer.price)])
	if is_funded():
		return "%s — protégée" % title
	return InputHints.prompt(&"interact", "Inspecter %s" % title)


func interact(_player: Node2D) -> void:
	if can_be_funded():
		funding_requested.emit(site_id, fund_offer)
	elif not is_funded():
		inspected.emit(site_id, title, description)
