extends Control
## Four-layer pixel portrait assembled from the LimeZu portrait generator sheets.
## The default region crops the 96x96 cell down to the head and scales it 3x.

@export var skin: Texture2D
@export var eyes: Texture2D
@export var hair: Texture2D
@export var accessory: Texture2D
@export var region := Rect2(16, 12, 56, 56)

@onready var skin_rect: TextureRect = %Skin
@onready var eyes_rect: TextureRect = %Eyes
@onready var hair_rect: TextureRect = %Hair
@onready var accessory_rect: TextureRect = %Accessory


func _ready() -> void:
	_apply(skin_rect, skin)
	_apply(eyes_rect, eyes)
	_apply(hair_rect, hair)
	_apply(accessory_rect, accessory)


func _apply(target: TextureRect, source: Texture2D) -> void:
	if source == null:
		target.visible = false
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	target.texture = atlas
	target.visible = true
