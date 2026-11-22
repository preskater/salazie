extends Node
## Single-slot save file: versioned JSON, atomic write and a .bak fallback.
##
## Three blocks are stored: the game state (`GameState`), the campaign
## (`Campaign`) and the *world* of the map being played. The world is whatever
## the map scene needs to come back as it was left: plots, player position,
## pickups already taken. A map registers a provider with `register_world()`
## and receives the saved block, if any, in return.

const SAVE_VERSION := 3
const SAVE_PATH := "user://savegame.json"

var save_path := SAVE_PATH
## World block waiting to be handed to its map, keyed by map id.
var world: Dictionary = {}

var _world_map := 0
var _world_provider := Callable()


func _ready() -> void:
	GameState.day_advanced.connect(_on_day_advanced)
	Campaign.task_status_changed.connect(
		func(_map_id: int, _task_id: String, _status: int) -> void: _on_campaign_changed())
	Campaign.map_resolved.connect(
		func(_map_id: int, _summary: Dictionary) -> void: _on_campaign_changed())
	Campaign.choices_changed.connect(_on_campaign_changed)


func has_valid_save() -> bool:
	return not _read_valid_data().is_empty()


func read_metadata() -> Dictionary:
	var data := _read_valid_data()
	if data.is_empty():
		return {}
	var campaign: Dictionary = {}
	var raw_campaign: Variant = data.get("campaign", {})
	if raw_campaign is Dictionary:
		campaign = raw_campaign as Dictionary
	return {
		"day": int(data.get("day", 1)),
		"money": int(data.get("money", 0)),
		"map": clampi(int(campaign.get("current_map", 2)), 1, 3),
		"finished": bool(campaign.get("finished", false)),
		"saved_at": String(data.get("saved_at", "")),
	}


## Called by a map once it is built. `provider` returns the dictionary to
## store; the return value is the block saved for that map, or an empty
## dictionary on a fresh visit. The block is handed over once.
func register_world(map_id: int, provider: Callable) -> Dictionary:
	_world_map = map_id
	_world_provider = provider
	var pending: Variant = world.get(map_id, {})
	world.erase(map_id)
	return (pending as Dictionary).duplicate(true) if pending is Dictionary else {}


func unregister_world(map_id: int) -> void:
	if _world_map == map_id:
		_world_map = 0
		_world_provider = Callable()


func clear_world() -> void:
	world = {}


## Only the map being played has a world worth keeping: a generation that was
## left is over, and the next one starts fresh. The live map is asked first; a
## block that was loaded but not claimed yet is written back unchanged.
func _collect_world() -> Dictionary:
	var current := Campaign.current_map
	var state: Variant = null
	if _world_map == current and _world_provider.is_valid():
		state = _world_provider.call()
	elif world.has(current):
		state = world[current]
	for map_id: Variant in world.keys():
		if map_id != current:
			world.erase(map_id)
	if not (state is Dictionary) or (state as Dictionary).is_empty():
		return {}
	return {"map": current, "state": (state as Dictionary).duplicate(true)}


func _read_world(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var block := raw as Dictionary
	var state: Variant = block.get("state", null)
	var map_id := int(block.get("map", 0)) if _is_number(block.get("map", null)) else 0
	if map_id < 1 or map_id > 3 or not (state is Dictionary):
		return {}
	return {map_id: (state as Dictionary).duplicate(true)}


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func save_game() -> bool:
	if not GameState.playing:
		return false
	var data := GameState.to_dict()
	data["campaign"] = Campaign.to_dict()
	data["world"] = _collect_world()
	data["cycle"] = DayNightCycle.to_dict()
	data["version"] = SAVE_VERSION
	data["saved_at"] = Time.get_datetime_string_from_system()
	return _write_atomic(save_path, data)


func load_game() -> bool:
	var data := _read_valid_data()
	if data.is_empty():
		return false
	data = _migrate(data)
	if not GameState.from_dict(data):
		push_warning("Save file %s contains an invalid game state." % save_path)
		return false
	var raw_campaign: Variant = data.get("campaign", {})
	if not (raw_campaign is Dictionary) or not Campaign.from_dict(raw_campaign as Dictionary):
		push_warning("Save file %s contains an invalid campaign state." % save_path)
		return false
	world = _read_world(data.get("world", {}))
	# A world saved for another generation than the one resumed is stale.
	if not world.has(Campaign.current_map):
		world = {}
	return true


## Day/night block of the last loaded or written save; `SceneRouter` applies it
## after it has reset the cycle for the map.
func read_cycle() -> Dictionary:
	var data := _read_valid_data()
	var raw: Variant = data.get("cycle", {})
	return raw as Dictionary if raw is Dictionary else {}


func delete_save() -> void:
	clear_world()
	_remove(save_path)
	_remove(save_path + ".bak")
	_remove(save_path + ".tmp")


func _on_day_advanced(_day: int) -> void:
	if GameState.playing:
		save_game()


func _on_campaign_changed() -> void:
	if GameState.playing:
		save_game()


func _write_atomic(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("Could not open %s for writing (error %d)." % [tmp, FileAccess.get_open_error()])
		return false
	var stored := file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if not stored:
		push_error("Could not write the save data to %s." % tmp)
		return false
	if FileAccess.file_exists(path):
		var backup := path + ".bak"
		_remove(backup)
		var backup_err := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
		if backup_err != OK:
			push_warning("Could not rotate the previous save to %s (error %d)." % [backup, backup_err])
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Could not move the temporary save into %s (error %d)." % [path, err])
		return false
	return true


func _read_valid_data() -> Dictionary:
	for path: String in [save_path, save_path + ".bak"]:
		var data := _read_candidate(path)
		if not data.is_empty() and _is_valid_payload(data):
			return data
	return {}


func _read_candidate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("Could not parse save file %s: %s" % [path, json.get_error_message()])
		return {}
	var data: Variant = json.data
	if not (data is Dictionary):
		return {}
	var result := data as Dictionary
	if result.has("version"):
		result["version"] = int(result["version"])
	return result


func _is_valid_payload(data: Dictionary) -> bool:
	if not data.has("version"):
		return false
	var version := int(data["version"])
	if version < 1 or version > SAVE_VERSION:
		return false
	for key: String in ["money", "day", "seeds", "produce", "prices"]:
		if not data.has(key):
			return false
	if version >= 2 and not (data.get("campaign", null) is Dictionary):
		return false
	return true


func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	while version < SAVE_VERSION:
		data = _migrate_step(data, version)
		version += 1
		data["version"] = version
	return data


func _migrate_step(data: Dictionary, from_version: int) -> Dictionary:
	if from_version == 1:
		# Version 1 only knew the farm. Keep the farm state, unlock Map 3 from
		# Map 2, and treat the escape as already completed.
		data["campaign"] = {
			"legacy_v1": true,
			"current_map": 2,
		}
	elif from_version == 2:
		# Version 2 saved no map state: the map restarts as it always did.
		data["world"] = {}
		data["cycle"] = {}
	return data


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
