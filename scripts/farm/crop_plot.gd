class_name CropPlot
extends Node2D

enum State { EMPTY, TILLED, GROWING, READY }

const TILLED_TEXTURE := preload("res://sprites/farm_48x48/singles/Fences/Topsoil_48x48.png")
## Assets bought at the market (`grant_id` of the offers in economy.tres).
const FIELD_SLOT_ASSET := &"field_slot"
const HOE_ASSET := &"hoe"
## Soil worked with the hoe grows crops this much faster.
const HOE_GROWTH_BONUS := 1.25

@export var crop_type := "corn"
@export var initial_state: State = State.EMPTY
## Number of "Parcelle" slots the farmer must own before this plot can be
## worked. 0 is part of the starting garden.
@export var required_slots := 0

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
	add_to_group("crops")
	state = initial_state
	_ensure_textures()
	_sync_visual()

func _process(delta: float) -> void:
	if state != State.GROWING:
		return
	growth += delta * growth_speed()
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

## A plot beyond the starting garden stays fallow until its slot is bought.
## A crop already in the ground can still be harvested if the slot was sold.
func is_locked() -> bool:
	return Economy.owned_count(FIELD_SLOT_ASSET) < required_slots


func growth_speed() -> float:
	return HOE_GROWTH_BONUS if Economy.owned_count(HOE_ASSET) > 0 else 1.0


func get_interaction_prompt() -> String:
	if is_locked() and state != State.GROWING and state != State.READY:
		return "Terre en friche — achetez une parcelle au marché"
	match state:
		State.EMPTY:
			return InputHints.prompt(&"interact", "Préparer la parcelle")
		State.TILLED:
			var label := String(GameState.CROPS[GameState.selected_seed]["label"])
			var count := GameState.seed_count(GameState.selected_seed)
			if count <= 0:
				return "Plus de graines de %s — achetez-en au marché" % label
			return InputHints.prompt(&"interact", "Planter %s (%d graines)" % [label, count])
		State.GROWING:
			return "%s — en croissance" % String(GameState.CROPS[crop_type]["label"])
		State.READY:
			return InputHints.prompt(&"interact",
				"Récolter %s" % String(GameState.CROPS[crop_type]["label"]))
	return ""

func interact(_player: Node2D) -> void:
	if is_locked() and state != State.READY:
		if state != State.GROWING:
			GameState.announce("Cette terre n'est pas à vous : achetez une parcelle au marché.")
		return
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


func to_dict() -> Dictionary:
	return {"state": int(state), "crop": crop_type, "growth": growth}


## Restores a saved plot. An unknown crop or state leaves the plot as built.
func from_dict(data: Dictionary) -> void:
	var raw_state: Variant = data.get("state", null)
	var crop := String(data.get("crop", crop_type))
	if not (raw_state is int or raw_state is float) or not GameState.CROPS.has(crop):
		return
	var next := int(raw_state)
	if next < State.EMPTY or next > State.READY:
		return
	crop_type = crop
	state = next as State
	var raw_growth: Variant = data.get("growth", 0.0)
	growth = maxf(0.0, float(raw_growth)) if (raw_growth is int or raw_growth is float) else 0.0
	_shown_stage = -1
	_ensure_textures()
	_sync_visual()


## Brings a ripe crop under cover instead of losing it: the produce is kept and
## the plot is ready for the next seed. Used by the barn when a cyclone passes.
func shelter_crop() -> bool:
	if state != State.READY:
		return false
	GameState.add_produce(crop_type, 1)
	state = State.TILLED
	growth = 0.0
	_shown_stage = -1
	_sync_visual()
	return true


## The cyclone only takes ripe crops; the plot keeps its tilled soil.
func destroy_crop() -> bool:
	if state != State.READY:
		return false
	state = State.TILLED
	growth = 0.0
	_shown_stage = -1
	_sync_visual()
	return true

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
