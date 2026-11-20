class_name ItemSlot
extends Button
## Inventory slot: one item icon and its count, bottom-right.
## Empty slots are hidden by the owner so the grid only shows owned items.

@onready var icon_rect: TextureRect = $Icon
@onready var count_label: Label = $Count


func setup(icon: Texture2D, count: int, is_selected := false, description := "") -> void:
	icon_rect.texture = icon
	icon_rect.modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.35)
	count_label.text = "×%d" % count
	button_pressed = is_selected
	tooltip_text = description
