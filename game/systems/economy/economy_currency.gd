class_name EconomyCurrency
extends Resource
## One currency available during a generation.

@export var id: StringName = &""
@export var label: String = ""
@export var symbol: String = ""
@export var icon: Texture2D
@export var starting_balance: int = 0
@export var enabled := true
