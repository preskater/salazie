class_name CropPlot
extends Node2D

enum State { EMPTY, TILLED, GROWING, READY }

const TILLED_TEXTURE := preload("res://assets/farm_48x48/singles/Fences/Topsoil_48x48.png")

@export var crop_type := "corn"
@export var initial_state: State = State.EMPTY

var state: State = State.EMPTY
var growth := 0.0

var _soil: Sprite2D
var _crop: Sprite2D
var _textures := {}
var _shown_stage := -1

func _ready() -> void:
	_soil = $Soil
	_crop = $Sprite
	add_to_group("interactable")
	state = initial_state
	_ensure_textures()
	_sync_visual()

func _process(delta: float) -> void:
	if state != State.GROWING:
		return
	growth += delta
	var total := float(GameState.CROPS[crop_type]["growth"])
	if growth >= total:
		state = State.READY
		_shown_stage = -1
		_sync_visual()
		return
	var stage := 1 if growth >= total * 0.5 else 0
	if stage != _shown_stage:
		_shown_stage = stage
		_sync_visual()

func get_interaction_prompt() -> String:
	match state:
		State.EMPTY:
			return "E — Préparer la parcelle"
		State.TILLED:
			var label := String(GameState.CROPS[GameState.selected_seed]["label"])
			var count := GameState.seed_count(GameState.selected_seed)
			if count <= 0:
				return "Plus de graines de %s — achetez-en au marché" % label
			return "E — Planter %s (%d graines)" % [label, count]
		State.GROWING:
			return "%s — en croissance" % String(GameState.CROPS[crop_type]["label"])
		State.READY:
			return "E — Récolter %s" % String(GameState.CROPS[crop_type]["label"])
	return ""

func interact(_player: Node2D) -> void:
	match state:
		State.EMPTY:
			state = State.TILLED
			_sync_visual()
			GameState.notify_plot_prepared()
			GameState.announce("Parcelle préparée.")
		State.TILLED:
			_plant()
		State.READY:
			_harvest()

func _plant() -> void:
	var seed := GameState.selected_seed
	if not GameState.consume_seed(seed):
		var label := String(GameState.CROPS[seed]["label"])
		GameState.announce("Plus de graines de %s — achetez-en au marché." % label)
		return
	crop_type = seed
	state = State.GROWING
	growth = 0.0
	_shown_stage = -1
	_ensure_textures()
	_sync_visual()
	GameState.notify_crop_planted(crop_type)
	GameState.announce("Graine plantée : %s." % String(GameState.CROPS[crop_type]["label"]))

func _harvest() -> void:
	var label := String(GameState.CROPS[crop_type]["label"])
	GameState.add_produce(crop_type, 1)
	GameState.notify_crop_harvested(crop_type, 1)
	GameState.announce("Récolte : +1 %s." % label)
	state = State.TILLED
	_sync_visual()

func _ensure_textures() -> void:
	if _textures.has(crop_type):
		return
	var data: Dictionary = GameState.CROPS[crop_type]
	_textures[crop_type] = {
		"sprout": load(String(data["sprout"])),
		"stage": load(String(data["stage"])),
		"ripe": load(String(data["ripe"])),
	}

func _sync_visual() -> void:
	if state == State.EMPTY:
		_soil.visible = false
		_crop.visible = false
		return

	# The tilled ground is flat: it lives at z_index -1 (relative to World)
	# so it can never cover the player.
	_set_texture(_soil, TILLED_TEXTURE)

	match state:
		State.TILLED:
			_crop.visible = false
		State.GROWING:
			var stage := 1 if growth >= float(GameState.CROPS[crop_type]["growth"]) * 0.5 else 0
			var tex: Texture2D = _textures[crop_type]["sprout"] if stage == 0 else _textures[crop_type]["stage"]
			_set_texture(_crop, tex)
		State.READY:
			_set_texture(_crop, _textures[crop_type]["ripe"])

func _set_texture(target: Sprite2D, texture: Texture2D) -> void:
	target.texture = texture
	target.visible = true
	target.offset = Vector2(0, -texture.get_height() / 2.0)
