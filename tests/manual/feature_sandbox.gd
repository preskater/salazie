extends Control
## Personal feature sandbox for this branch. Git-ignored.
## Covers every system available here; economy tests activate only when the
## Economy autoload exists (i.e. after merging the economy branch).

const TEST_SAVE_PATH := "user://feature_sandbox_save.json"
const TEST_SETTINGS_PATH := "user://feature_sandbox_settings.cfg"
const GUARD_SCRIPT := preload("res://scripts/world/ai/guard/guard.gd")


class Checker extends RefCounted:
	var failures: Array[String] = []

	func check(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)

	func equal_int(actual: int, expected: int, label: String) -> void:
		if actual != expected:
			failures.append("%s : attendu %d, obtenu %d" % [label, expected, actual])

	func equal_float(actual: float, expected: float, label: String, epsilon := 0.001) -> void:
		if absf(actual - expected) > epsilon:
			failures.append("%s : attendu %.3f, obtenu %.3f" % [label, expected, actual])

	func equal_str(actual: String, expected: String, label: String) -> void:
		if actual != expected:
			failures.append("%s : attendu « %s », obtenu « %s »" % [label, expected, actual])

	func equal_bool(actual: bool, expected: bool, label: String) -> void:
		if actual != expected:
			failures.append("%s : attendu %s, obtenu %s" % [label, str(expected), str(actual)])

	func ok() -> bool:
		return failures.is_empty()

	func summary() -> String:
		return "OK" if failures.is_empty() else " | ".join(failures)


var _status_label: Label
var _summary_label: Label
var _log_label: Label
var _test_result_labels: Dictionary[String, Label] = {}
var _group_summary_labels: Dictionary[String, Label] = {}
var _test_status: Dictionary[String, String] = {}
var _tests: Array[Dictionary] = []
var _snapshot: Dictionary = {}
var _temp_nodes: Array[Node] = []
var _messages: Array[String] = []
var _economy: Node
var _original_save_path := ""
var _original_settings_path := ""


func _ready() -> void:
	_original_save_path = SaveGame.save_path
	_original_settings_path = Settings.config_path
	SaveGame.save_path = TEST_SAVE_PATH
	Settings.config_path = TEST_SETTINGS_PATH
	_economy = get_node_or_null("/root/Economy")
	_tests = _test_definitions()
	_build_ui()
	_refresh_header()


func _exit_tree() -> void:
	_dispose_temp_nodes()
	SaveGame.save_path = _original_save_path
	Settings.config_path = _original_settings_path
	get_tree().paused = false


# --- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.93, 0.87, 0.74)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Bac à sable — toutes les fonctionnalités"
	title.add_theme_font_size_override("font_size", 28)
	outer.add_child(title)

	var note := Label.new()
	note.text = "Scène personnelle, non versionnée (voir .gitignore)."
	note.add_theme_font_size_override("font_size", 14)
	outer.add_child(note)

	_status_label = Label.new()
	outer.add_child(_status_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	outer.add_child(actions)
	_make_button(actions, "RunAllTests", "Lancer tous les tests", _run_all_tests)
	_make_button(actions, "CleanupFiles", "Nettoyer les fichiers de test", _cleanup_files)

	_summary_label = Label.new()
	_summary_label.text = "Aucun test exécuté."
	outer.add_child(_summary_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	for group: String in _group_names():
		content.add_child(HSeparator.new())
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 10)
		content.add_child(header)
		var group_title := Label.new()
		group_title.text = group
		group_title.add_theme_font_size_override("font_size", 20)
		group_title.custom_minimum_size.x = 260
		header.add_child(group_title)
		var run_group := Button.new()
		run_group.name = "RunGroup_" + group.replace(" ", "_").replace("/", "_")
		run_group.text = "Lancer le groupe"
		run_group.pressed.connect(_run_group.bind(group))
		header.add_child(run_group)
		var group_summary := Label.new()
		group_summary.text = "—"
		group_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(group_summary)
		_group_summary_labels[group] = group_summary

		for test: Dictionary in _tests:
			if String(test["group"]) != group:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			content.add_child(row)
			var test_name := Label.new()
			test_name.text = String(test["name"])
			test_name.custom_minimum_size.x = 320
			row.add_child(test_name)
			var run_button := Button.new()
			run_button.name = "Run_" + _test_key(test).replace(" ", "_").replace(":", "_").replace("/", "_")
			run_button.text = "Lancer"
			run_button.pressed.connect(_run_one.bind(test))
			row.add_child(run_button)
			var result := Label.new()
			result.text = "—"
			result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(result)
			_test_result_labels[_test_key(test)] = result

	content.add_child(HSeparator.new())
	var log_title := Label.new()
	log_title.text = "Journal"
	log_title.add_theme_font_size_override("font_size", 18)
	content.add_child(log_title)
	_log_label = Label.new()
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.add_theme_font_size_override("font_size", 14)
	content.add_child(_log_label)


func _make_button(parent: Node, button_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _refresh_header() -> void:
	var systems: Array[String] = [
		"Joueur", "Survie", "Jour / nuit", "Ferme", "Inventaire / marché",
		"Sauvegarde / réglages", "Menus", "Garde", "Transition / sortie",
	]
	if _economy != null:
		systems.append("Économie")
	_status_label.text = "Systèmes détectés : %s" % ", ".join(systems)


# --- Test execution ---------------------------------------------------------

func _test_key(test: Dictionary) -> String:
	return "%s::%s" % [String(test["group"]), String(test["name"])]


func _group_names() -> Array[String]:
	var names: Array[String] = []
	for test: Dictionary in _tests:
		var group := String(test["group"])
		if not names.has(group):
			names.append(group)
	return names


func _run_all_tests() -> void:
	var ok := 0
	var failed := 0
	var skipped := 0
	for test: Dictionary in _tests:
		var status := _run_one(test)
		if status == "ok":
			ok += 1
		elif status == "skip":
			skipped += 1
		else:
			failed += 1
	for group: String in _group_names():
		_update_group_summary(group)
	_summary_label.text = "%d OK · %d échec(s) · %d ignoré(s)" % [ok, failed, skipped]
	_log("Résumé global : %s" % _summary_label.text)


func _run_group(group: String) -> void:
	var ok := 0
	var failed := 0
	var skipped := 0
	for test: Dictionary in _tests:
		if String(test["group"]) != group:
			continue
		var status := _run_one(test)
		if status == "ok":
			ok += 1
		elif status == "skip":
			skipped += 1
		else:
			failed += 1
	_update_group_summary(group)
	_summary_label.text = "%s : %d OK · %d échec(s) · %d ignoré(s)" % [group, ok, failed, skipped]
	_log(_summary_label.text)


func _run_one(test: Dictionary) -> String:
	var key := _test_key(test)
	if bool(test.get("requires_economy", false)) and _economy == null:
		_set_test_result(key, "skip", "Ignoré : économie absente sur cette branche.")
		return "skip"
	get_tree().paused = false
	_take_snapshot()
	var check := Checker.new()
	var callback: Callable = test["run"]
	callback.call(check)
	_dispose_temp_nodes()
	_restore_snapshot()
	var status := "ok" if check.ok() else "fail"
	_set_test_result(key, status, check.summary())
	_log("%s — %s" % [String(test["name"]), check.summary()])
	return status


func _set_test_result(key: String, status: String, message: String) -> void:
	_test_status[key] = status
	var label: Label = _test_result_labels.get(key)
	if label == null:
		return
	label.text = message
	var color := Color(0.12, 0.42, 0.16)
	if status == "fail":
		color = Color(0.62, 0.14, 0.1)
	elif status == "skip":
		color = Color(0.42, 0.32, 0.2)
	label.add_theme_color_override("font_color", color)


func _update_group_summary(group: String) -> void:
	var ok := 0
	var failed := 0
	var skipped := 0
	for test: Dictionary in _tests:
		if String(test["group"]) != group:
			continue
		var status: String = _test_status.get(_test_key(test), "")
		if status == "ok":
			ok += 1
		elif status == "fail":
			failed += 1
		elif status == "skip":
			skipped += 1
	var label: Label = _group_summary_labels.get(group)
	if label != null:
		label.text = "%d OK · %d échec(s) · %d ignoré(s)" % [ok, failed, skipped]


func _cleanup_files() -> void:
	SaveGame.delete_save()
	_remove_file(TEST_SETTINGS_PATH)
	_remove_file(TEST_SAVE_PATH)
	_remove_file(TEST_SAVE_PATH + ".bak")
	_remove_file(TEST_SAVE_PATH + ".tmp")
	_log("Fichiers de test supprimés.")


func _log(message: String) -> void:
	_messages.push_front(message)
	if _messages.size() > 12:
		_messages.resize(12)
	if _log_label != null:
		var lines := PackedStringArray()
		for entry: String in _messages:
			lines.append(entry)
		_log_label.text = "\n".join(lines)


# --- Snapshot / restore -----------------------------------------------------

func _take_snapshot() -> void:
	_snapshot = {
		"game": GameState.to_dict(),
		"playing": GameState.playing,
		"day": {
			"phase": DayNightCycle.phase,
			"day_number": DayNightCycle.day_number,
			"nights_spent": DayNightCycle.nights_spent,
			"required": DayNightCycle.nights_required_for_next_map,
			"time_left": DayNightCycle.time_left,
			"running": DayNightCycle.running,
			"tint": DayNightCycle.tint_enabled,
		},
		"settings": {
			"master": Settings.master_volume,
			"music": Settings.music_volume,
			"sfx": Settings.sfx_volume,
			"window": Settings.window_mode,
			"resolution": Settings.resolution,
			"vsync": Settings.vsync_enabled,
			"path": Settings.config_path,
		},
		"save_path": SaveGame.save_path,
		"is_gameplay": SceneRouter.is_gameplay,
	}
	if _economy != null:
		_snapshot["economy_config"] = _economy.get("config")
		_snapshot["economy_state"] = _economy.call("to_dict")


func _restore_snapshot() -> void:
	get_tree().paused = false
	SaveGame.save_path = String(_snapshot.get("save_path", TEST_SAVE_PATH))
	var settings: Dictionary = _snapshot.get("settings", {})
	Settings.config_path = String(settings.get("path", TEST_SETTINGS_PATH))
	Settings.master_volume = float(settings.get("master", 0.8))
	Settings.music_volume = float(settings.get("music", 0.7))
	Settings.sfx_volume = float(settings.get("sfx", 0.8))
	Settings.window_mode = int(settings.get("window", Settings.WINDOWED))
	var resolution: Vector2i = settings.get("resolution", Vector2i(1280, 720))
	Settings.resolution = resolution
	Settings.vsync_enabled = bool(settings.get("vsync", true))
	Settings.apply_audio()
	Settings.apply_display()
	if _economy != null:
		var config: Resource = _snapshot.get("economy_config")
		var state: Dictionary = _snapshot.get("economy_state", {})
		if config != null:
			_economy.call("apply_config", config,
				StringName(String(state.get("generation", ""))))
		if not state.is_empty():
			_economy.call("from_dict", state)
	GameState.from_dict(_snapshot.get("game", {}) as Dictionary)
	GameState.playing = bool(_snapshot.get("playing", false))
	var day: Dictionary = _snapshot.get("day", {})
	DayNightCycle.phase = int(day.get("phase", 0))
	DayNightCycle.day_number = int(day.get("day_number", 1))
	DayNightCycle.nights_spent = int(day.get("nights_spent", 0))
	DayNightCycle.nights_required_for_next_map = int(day.get("required", 2))
	DayNightCycle.time_left = float(day.get("time_left", 120.0))
	DayNightCycle.running = bool(day.get("running", true))
	DayNightCycle.tint_enabled = bool(day.get("tint", true))
	SceneRouter.is_gameplay = bool(_snapshot.get("is_gameplay", false))


# --- Temporary nodes --------------------------------------------------------

func _spawn_scene(path: String) -> Node:
	var node: Node = load(path).instantiate()
	add_child(node)
	_temp_nodes.append(node)
	return node


func _spawn_script(path: String) -> Node:
	var script: Script = load(path)
	var node: Node = script.new()
	add_child(node)
	_temp_nodes.append(node)
	return node


func _track(node: Node) -> Node:
	add_child(node)
	_temp_nodes.append(node)
	return node


func _dispose_temp_nodes() -> void:
	for node: Node in _temp_nodes:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_temp_nodes.clear()


func _spawn_player() -> Node:
	var player := _spawn_scene("res://scenes/player/player.tscn")
	player.set_physics_process(false)
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = false
	return player


func _spawn_guard() -> Node:
	var guard := _spawn_scene("res://scenes/world/ai/guard/guard.tscn")
	guard.set_physics_process(false)
	guard.set("collision_layer", 0)
	guard.set("collision_mask", 0)
	guard.set("use_navigation", false)
	guard.set("patrol_speed", 0.0)
	guard.set("chase_speed", 0.0)
	guard.set("facing", Vector2.RIGHT)
	return guard


func _spawn_target(position: Vector2) -> Node2D:
	var target := Node2D.new()
	_track(target)
	target.global_position = position
	return target


func _spawn_cycle() -> Node:
	var cycle := _spawn_script("res://scripts/world/day_night_cycle.gd")
	cycle.set_process(false)
	cycle.set("day_duration", 10.0)
	cycle.set("night_duration", 4.0)
	cycle.call("reset_for_new_map", 2, false)
	return cycle


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Test catalogue ---------------------------------------------------------

func _test_definitions() -> Array[Dictionary]:
	var tests: Array[Dictionary] = [
		{"group": "Joueur", "name": "Scène et animations", "run": _test_player_structure},
		{"group": "Joueur", "name": "Animations directionnelles", "run": _test_player_animations},
		{"group": "Joueur", "name": "Course et bruit", "run": _test_player_run_noise},

		{"group": "Survie", "name": "Démarrage et drains", "run": _test_survival_start},
		{"group": "Survie", "name": "Bornes et remplissage", "run": _test_survival_bounds},
		{"group": "Survie", "name": "Signal de dépletion", "run": _test_survival_signal},

		{"group": "Jour / nuit", "name": "Phases jour et nuit", "run": _test_day_night_phases},
		{"group": "Jour / nuit", "name": "Nuits requises et reset", "run": _test_day_night_ready},
		{"group": "Jour / nuit", "name": "Teinte du monde", "run": _test_day_night_tint},

		{"group": "Ferme", "name": "Argent, graines et prix", "run": _test_game_state},
		{"group": "Ferme", "name": "Cycle d'une parcelle", "run": _test_crop_plot},
		{"group": "Ferme", "name": "Changement de jour", "run": _test_day_advance},

		{"group": "Inventaire / marché", "name": "Cases d'inventaire", "run": _test_inventory_slots},
		{"group": "Inventaire / marché", "name": "Ouverture du marché", "run": _test_market_overlay},
		{"group": "Inventaire / marché", "name": "Ouverture de l'inventaire", "run": _test_inventory_overlay},

		{"group": "Sauvegarde / réglages", "name": "Sauvegarde et chargement", "run": _test_save_round_trip},
		{"group": "Sauvegarde / réglages", "name": "Métadonnées de sauvegarde", "run": _test_save_metadata},
		{"group": "Sauvegarde / réglages", "name": "Réglages et bus audio", "run": _test_settings},

		{"group": "Menus", "name": "Menu principal", "run": _test_main_menu},
		{"group": "Menus", "name": "Pause et reprise", "run": _test_pause_menu},
		{"group": "Menus", "name": "Navigation des options", "run": _test_pause_options},

		{"group": "Garde", "name": "Cône de vision", "run": _test_guard_vision},
		{"group": "Garde", "name": "Bruit et alerte", "run": _test_guard_alert},
		{"group": "Garde", "name": "Attrape le joueur", "run": _test_guard_catch},

		{"group": "Transition / sortie", "name": "Scène de transition", "run": _test_transition},
		{"group": "Transition / sortie", "name": "Condition de sortie", "run": _test_map_exit},

		{"group": "Économie", "name": "Générations et monnaies", "run": _test_economy_generations, "requires_economy": true},
		{"group": "Économie", "name": "Activation / désactivation", "run": _test_economy_disable, "requires_economy": true},
		{"group": "Économie", "name": "Achat d'un objet", "run": _test_economy_buy_item, "requires_economy": true},
		{"group": "Économie", "name": "Achat bâtiment et emplacement", "run": _test_economy_buy_property, "requires_economy": true},
		{"group": "Économie", "name": "Vente", "run": _test_economy_sell, "requires_economy": true},
		{"group": "Économie", "name": "Échanges monnaie / bien", "run": _test_economy_trade, "requires_economy": true},
		{"group": "Économie", "name": "Sauvegarde de l'état", "run": _test_economy_state, "requires_economy": true},
		{"group": "Économie", "name": "Intégration GameState", "run": _test_economy_game_state, "requires_economy": true},
	]
	return tests


# --- Player -----------------------------------------------------------------

func _test_player_structure(check: Checker) -> void:
	var player := _spawn_player()
	check.check(player is CharacterBody2D, "CharacterBody2D")
	check.check(player.get_node_or_null("Sprite2D") != null, "Sprite2D")
	check.check(player.get_node_or_null("CollisionShape2D") != null, "CollisionShape2D")
	var sprite := player.get_node_or_null("Sprite2D") as AnimatedSprite2D
	if sprite == null:
		return
	for direction: String in ["right", "left", "up", "down"]:
		check.check(sprite.sprite_frames.has_animation("walk_" + direction),
			"animation walk_" + direction)
		check.check(sprite.sprite_frames.has_animation("idle_" + direction),
			"animation idle_" + direction)


func _test_player_animations(check: Checker) -> void:
	var player := _spawn_player()
	var sprite := player.get_node("Sprite2D") as AnimatedSprite2D
	var directions := {
		"right": Vector2.RIGHT,
		"left": Vector2.LEFT,
		"up": Vector2.UP,
		"down": Vector2.DOWN,
	}
	for direction_name: String in directions:
		player.call("play_walk_animation", directions[direction_name])
		check.equal_str(String(sprite.animation), "walk_" + direction_name,
			"marche " + direction_name)
		player.call("play_idle_animation", directions[direction_name])
		check.equal_str(String(sprite.animation), "idle_" + direction_name,
			"immobile " + direction_name)


func _test_player_run_noise(check: Checker) -> void:
	var player := _spawn_player()
	player.set("is_running", false)
	check.equal_float(float(player.call("get_current_speed")), 300.0, "vitesse normale")
	player.set("is_running", true)
	check.equal_float(float(player.call("get_current_speed")), 510.0, "vitesse de course")
	var guard := _spawn_guard()
	player.global_position = Vector2(40, 0)
	guard.global_position = Vector2.ZERO
	player.call("emit_noise")
	check.equal_int(int(guard.get("state")), GUARD_SCRIPT.State.SUSPICIOUS,
		"garde alertée par le bruit")


# --- Survival ---------------------------------------------------------------

func _test_survival_start(check: Checker) -> void:
	var survival := _spawn_script("res://scripts/systems/survival/survival_component.gd")
	check.equal_float(float(survival.get("food")), 100.0, "nourriture initiale")
	check.equal_float(float(survival.get("water")), 100.0, "eau initiale")
	survival.call("tick", 1.0)
	check.equal_float(float(survival.get("food")), 99.0, "drain nourriture")
	check.equal_float(float(survival.get("water")), 98.5, "drain eau")


func _test_survival_bounds(check: Checker) -> void:
	var survival := _spawn_script("res://scripts/systems/survival/survival_component.gd")
	survival.call("add_food", 500.0)
	check.equal_float(float(survival.get("food")), 100.0, "plafond nourriture")
	survival.call("tick", 1000.0)
	check.equal_float(float(survival.get("food")), 0.0, "nourriture vide")
	check.equal_float(float(survival.get("water")), 0.0, "eau vide")
	survival.call("add_water", 50.0)
	check.equal_float(float(survival.get("water")), 50.0, "remplissage eau")


func _test_survival_signal(check: Checker) -> void:
	var survival := _spawn_script("res://scripts/systems/survival/survival_component.gd")
	var kinds: Array[StringName] = []
	survival.connect("depleted", func(kind: StringName) -> void: kinds.append(kind))
	survival.call("tick", 1000.0)
	check.equal_int(kinds.size(), 2, "deux dépletions")
	check.check(kinds.has(&"food") and kinds.has(&"water"), "ressources signalées")


# --- Day / night ------------------------------------------------------------

func _test_day_night_phases(check: Checker) -> void:
	var cycle := _spawn_cycle()
	check.check(not cycle.call("is_night"), "commence de jour")
	cycle.call("advance", 10.0)
	check.check(cycle.call("is_night"), "devient nuit")
	cycle.call("advance", 4.0)
	check.equal_int(int(cycle.get("nights_spent")), 1, "nuit comptée")
	check.equal_int(int(cycle.get("day_number")), 2, "nouveau jour")


func _test_day_night_ready(check: Checker) -> void:
	var cycle := _spawn_cycle()
	var ready := [0]
	cycle.connect("ready_for_next_map", func() -> void: ready[0] += 1)
	cycle.call("advance", 10.0)
	cycle.call("advance", 4.0)
	check.check(not cycle.call("is_ready_for_next_map"), "pas prêt après une nuit")
	cycle.call("advance", 10.0)
	cycle.call("advance", 4.0)
	check.check(cycle.call("is_ready_for_next_map"), "prêt après deux nuits")
	check.equal_int(ready[0], 1, "signal ready unique")
	cycle.call("reset_for_new_map", 2, false)
	check.equal_int(int(cycle.get("nights_spent")), 0, "progression réinitialisée")


func _test_day_night_tint(check: Checker) -> void:
	var cycle := _spawn_cycle()
	var tint := cycle.get_node_or_null("Tint") as CanvasModulate
	check.check(tint != null, "CanvasModulate")
	if tint == null:
		return
	cycle.set("tint_enabled", false)
	check.check(not tint.visible, "teinte désactivée")
	cycle.set("tint_enabled", true)
	check.check(tint.visible, "teinte activée")


# --- Farm -------------------------------------------------------------------

func _test_game_state(check: Checker) -> void:
	GameState.reset()
	check.equal_int(GameState.money, GameState.START_MONEY, "argent initial")
	check.equal_int(GameState.day, GameState.START_DAY, "jour initial")
	check.equal_int(GameState.seed_count("corn"), 2, "graines de maïs")
	check.equal_int(int(GameState.prices["corn"]), 10, "prix du maïs")
	GameState.add_money(5)
	check.equal_int(GameState.money, GameState.START_MONEY + 5, "ajout d'argent")
	check.check(GameState.spend_money(5), "dépense acceptée")
	check.check(not GameState.spend_money(9999), "dépense refusée")
	GameState.select_seed("pumpkin")
	check.equal_str(GameState.selected_seed, "pumpkin", "graine sélectionnée")
	check.check(GameState.buy_seed("pumpkin"), "achat d'une graine")
	check.equal_int(GameState.seed_count("pumpkin"), 2, "graine achetée")
	GameState.add_produce("corn", 1)
	var earned := GameState.sell("corn", 1)
	check.equal_int(earned, int(GameState.prices["corn"]), "vente au prix du jour")


func _test_crop_plot(check: Checker) -> void:
	GameState.reset()
	var plot := _spawn_scene("res://scenes/farm/crop_plot.tscn")
	check.equal_int(int(plot.get("state")), 0, "parcelle vide")
	plot.call("interact", null)
	check.equal_int(int(plot.get("state")), 1, "parcelle labourée")
	GameState.select_seed("corn")
	plot.call("interact", null)
	check.equal_int(int(plot.get("state")), 2, "culture plantée")
	plot.call("_process", 100.0)
	check.equal_int(int(plot.get("state")), 3, "culture mûre")
	var before := GameState.produce_count("corn")
	plot.call("interact", null)
	check.equal_int(GameState.produce_count("corn"), before + 1, "récolte ajoutée")
	check.equal_int(int(plot.get("state")), 1, "retour au sol labouré")


func _test_day_advance(check: Checker) -> void:
	GameState.reset()
	var previous := GameState.prices.duplicate()
	GameState.playing = true
	GameState.set("_day_time", 59.0)
	GameState.call("_process", 2.0)
	check.equal_int(GameState.day, 2, "jour avancé")
	check.equal_int(GameState.prices.size(), 4, "quatre prix")
	for crop: String in GameState.CROP_ORDER:
		check.equal_int(int(GameState.previous_prices[crop]), int(previous[crop]),
			"ancien prix " + crop)


# --- Inventory / market -----------------------------------------------------

func _test_inventory_slots(check: Checker) -> void:
	GameState.reset()
	var hud := _spawn_scene("res://scenes/farm/farm_hud.tscn")
	var seed_grid := hud.get_node_or_null("%SeedGrid") as GridContainer
	var produce_grid := hud.get_node_or_null("%ProduceGrid") as GridContainer
	check.check(seed_grid != null, "grille de graines")
	check.check(produce_grid != null, "grille de récoltes")
	if seed_grid == null or produce_grid == null:
		return
	check.equal_int(seed_grid.get_child_count(), GameState.CROP_ORDER.size(),
		"une case par graine")
	check.equal_int(produce_grid.get_child_count(), GameState.CROP_ORDER.size(),
		"une case par récolte")
	GameState.seeds["corn"] = 3
	GameState.inventory_changed.emit()
	var index := GameState.CROP_ORDER.find("corn")
	var slot := seed_grid.get_child(index) as Button
	var count := slot.get_node_or_null("Count") as Label
	check.check(count != null, "compteur de graines")
	if count != null:
		check.equal_str(count.text, "×3", "compteur de maïs")
	var tomato := GameState.CROP_ORDER.find("tomato")
	(seed_grid.get_child(tomato) as Button).pressed.emit()
	check.equal_str(GameState.selected_seed, "tomato", "sélection de tomate")


func _test_market_overlay(check: Checker) -> void:
	GameState.reset()
	var hud := _spawn_scene("res://scenes/farm/farm_hud.tscn")
	hud.call("open_market")
	var overlay := hud.get_node_or_null("%MarketOverlay") as Control
	check.check(overlay != null and overlay.visible, "marché visible")
	check.check(get_tree().paused, "jeu en pause")
	var buy := hud.get_node("%BuyRows").get_node_or_null("Buy_corn") as Button
	check.check(buy != null, "bouton d'achat")
	if buy != null:
		check.check(buy.text.begins_with("Acheter"), "libellé d'achat")
	var sell := hud.get_node("%SellRows").get_node_or_null("Sell_corn") as Button
	check.check(sell != null, "bouton de vente")
	hud.call("close_market")
	check.check(not get_tree().paused, "jeu repris")


func _test_inventory_overlay(check: Checker) -> void:
	GameState.reset()
	var hud := _spawn_scene("res://scenes/farm/farm_hud.tscn")
	hud.call("open_inventory")
	var overlay := hud.get_node_or_null("%InventoryOverlay") as Control
	check.check(overlay != null and overlay.visible, "inventaire visible")
	check.check(get_tree().paused, "jeu en pause")
	hud.call("close_inventory")
	check.check(overlay != null and not overlay.visible, "inventaire masqué")
	check.check(not get_tree().paused, "jeu repris")


# --- Save / settings --------------------------------------------------------

func _test_save_round_trip(check: Checker) -> void:
	SaveGame.delete_save()
	GameState.playing = true
	GameState.reset()
	GameState.money = 123
	GameState.day = 4
	GameState.seeds["corn"] = 7
	check.check(SaveGame.save_game(), "sauvegarde")
	GameState.money = 0
	GameState.day = 1
	GameState.seeds["corn"] = 0
	check.check(SaveGame.load_game(), "chargement")
	check.equal_int(GameState.money, 123, "argent restauré")
	check.equal_int(GameState.day, 4, "jour restauré")
	check.equal_int(GameState.seed_count("corn"), 7, "graines restaurées")
	SaveGame.delete_save()


func _test_save_metadata(check: Checker) -> void:
	SaveGame.delete_save()
	GameState.playing = true
	GameState.reset()
	GameState.money = 88
	GameState.day = 6
	check.check(SaveGame.save_game(), "sauvegarde")
	var metadata := SaveGame.read_metadata()
	check.equal_int(int(metadata.get("money", -1)), 88, "argent metadata")
	check.equal_int(int(metadata.get("day", -1)), 6, "jour metadata")
	SaveGame.delete_save()


func _test_settings(check: Checker) -> void:
	Settings.reset_defaults()
	check.equal_float(Settings.master_volume, 0.8, "volume par défaut")
	Settings.master_volume = 0.42
	Settings.music_volume = 0.33
	Settings.sfx_volume = 0.21
	Settings.window_mode = Settings.FULLSCREEN
	Settings.resolution = Vector2i(1600, 900)
	Settings.vsync_enabled = false
	Settings.save_settings()
	Settings.master_volume = 1.0
	Settings.music_volume = 1.0
	Settings.sfx_volume = 1.0
	Settings.window_mode = Settings.WINDOWED
	Settings.resolution = Vector2i(1280, 720)
	Settings.vsync_enabled = true
	Settings.load_settings()
	check.equal_float(Settings.master_volume, 0.42, "volume restauré")
	check.equal_float(Settings.music_volume, 0.33, "musique restaurée")
	check.equal_float(Settings.sfx_volume, 0.21, "effets restaurés")
	check.equal_int(Settings.window_mode, Settings.FULLSCREEN, "plein écran restauré")
	check.equal_int(Settings.resolution.x, 1600, "largeur restaurée")
	check.equal_int(Settings.resolution.y, 900, "hauteur restaurée")
	check.check(not Settings.vsync_enabled, "vsync restaurée")
	Settings.set_master_volume(2.0)
	check.equal_float(Settings.master_volume, 1.0, "volume plafonné")
	Settings.set_music_volume(-1.0)
	check.equal_float(Settings.music_volume, 0.0, "volume plancher")
	check.check(AudioServer.get_bus_index("Master") >= 0, "bus Master")
	check.check(AudioServer.get_bus_index("Music") >= 0, "bus Music")
	check.check(AudioServer.get_bus_index("SFX") >= 0, "bus SFX")
	Settings.reset_defaults()
	_remove_file(TEST_SETTINGS_PATH)


# --- Menus ------------------------------------------------------------------

func _test_main_menu(check: Checker) -> void:
	SaveGame.delete_save()
	var menu := _spawn_scene("res://scenes/ui/menus/main_menu.tscn")
	for node_name: String in [
		"%NewGameButton", "%ContinueButton", "%OptionsButton",
		"%CreditsButton", "%QuitButton", "%VersionLabel",
	]:
		check.check(menu.get_node_or_null(node_name) != null, "nœud " + node_name)
	var stack := menu.get_node_or_null("%MenuStack")
	check.check(stack != null, "pile de menus")
	if stack == null:
		return
	check.equal_str(String(stack.call("current_name")), "Home", "écran d'accueil")
	var continue_button := menu.get_node_or_null("%ContinueButton") as Button
	check.check(continue_button != null and continue_button.disabled,
		"continuer désactivé sans sauvegarde")
	var options := menu.get_node_or_null("%OptionsButton") as Button
	check.check(options != null, "bouton options")
	if options == null:
		return
	options.pressed.emit()
	check.equal_str(String(stack.call("current_name")), "Settings", "écran options")
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	menu.call("_unhandled_input", event)
	check.equal_str(String(stack.call("current_name")), "Home", "retour accueil")


func _test_pause_menu(check: Checker) -> void:
	var pause := _spawn_scene("res://scenes/preloads/pause_menu.tscn")
	GameState.playing = true
	SceneRouter.is_gameplay = true
	GameState.reset()
	pause.call("open")
	check.check((pause as CanvasLayer).visible, "pause visible")
	check.check(get_tree().paused, "arbre en pause")
	pause.call("close")
	check.check(not (pause as CanvasLayer).visible, "pause masquée")
	check.check(not get_tree().paused, "arbre repris")


func _test_pause_options(check: Checker) -> void:
	var pause := _spawn_scene("res://scenes/preloads/pause_menu.tscn")
	GameState.playing = true
	SceneRouter.is_gameplay = true
	GameState.reset()
	pause.call("open")
	var options := pause.get_node_or_null("%OptionsButton") as Button
	check.check(options != null, "bouton options pause")
	if options == null:
		pause.call("close")
		return
	options.pressed.emit()
	var stack := pause.get_node_or_null("%MenuStack")
	check.check(stack != null, "pile de menus pause")
	if stack != null:
		check.equal_str(String(stack.call("current_name")), "Settings", "options pause")
		stack.call("pop")
		check.equal_str(String(stack.call("current_name")), "Pause", "retour pause")
	pause.call("close")


# --- Guard ------------------------------------------------------------------

func _test_guard_vision(check: Checker) -> void:
	var guard := _spawn_guard()
	guard.global_position = Vector2.ZERO
	check.check(guard.call("can_see", Vector2(100, 0)), "cible dans le cône")
	check.check(not guard.call("can_see", Vector2(100, 100)), "hors du cône")
	check.check(not guard.call("can_see", Vector2(500, 0)), "hors portée")


func _test_guard_alert(check: Checker) -> void:
	var guard := _spawn_guard()
	var target := _spawn_target(Vector2(100, 0))
	guard.set("player", target)
	guard.call("hear_noise", target.global_position, 9999.0)
	for i in 25:
		guard.call("tick", 0.1)
	check.equal_int(int(guard.get("state")), GUARD_SCRIPT.State.ALERT, "état alerte")
	target.global_position = Vector2(0, 150)
	for i in 35:
		guard.call("tick", 0.1)
	check.equal_int(int(guard.get("state")), GUARD_SCRIPT.State.PATROL,
		"retour en patrouille")


func _test_guard_catch(check: Checker) -> void:
	var guard := _spawn_guard()
	guard.set("pause_on_catch", false)
	guard.set("catch_distance", 48.0)
	var target := _spawn_target(Vector2(12, 0))
	guard.set("player", target)
	var caught := [0]
	guard.connect("caught", func() -> void: caught[0] += 1)
	guard.call("hear_noise", target.global_position, 9999.0)
	for i in 30:
		guard.call("tick", 0.1)
	check.equal_int(caught[0], 1, "attrapé une fois")
	check.equal_int(int(guard.get("state")), GUARD_SCRIPT.State.CAUGHT, "état attrapé")


# --- Transition / map exit --------------------------------------------------

func _test_transition(check: Checker) -> void:
	var transition := _spawn_scene("res://scenes/preloads/scene_transition.tscn")
	check.check(transition.get_node_or_null("Backdrop") != null, "fond")
	check.check(transition.get_node_or_null("Text/Layout/Title") != null, "titre")
	check.check(not bool(transition.get("is_transitioning")), "hors transition")
	var backdrop := transition.get_node_or_null("Backdrop") as ColorRect
	check.check(backdrop != null, "ColorRect du fond")
	if backdrop != null:
		check.equal_float(backdrop.color.a, 0.0, "fondu initial invisible")


func _test_map_exit(check: Checker) -> void:
	var exit := _spawn_scene("res://scenes/world/map_exit.tscn")
	exit.set("next_scene_path", "res://scenes/maps/farm.tscn")
	exit.set("requires_map_ready", true)
	DayNightCycle.nights_required_for_next_map = 2
	DayNightCycle.nights_spent = 0
	check.check(not exit.call("can_leave"), "sortie bloquée")
	DayNightCycle.nights_spent = 2
	check.check(exit.call("can_leave"), "sortie autorisée")
	exit.set("requires_map_ready", false)
	DayNightCycle.nights_spent = 0
	check.check(exit.call("can_leave"), "sortie libre")


# --- Economy (optional) -----------------------------------------------------

func _econ_config() -> Resource:
	if _economy == null:
		return null
	return _economy.get("config") as Resource


func _econ_apply(generation: StringName) -> void:
	_economy.call("apply_config", _econ_config(), generation)


func _econ_balance(currency_id: StringName) -> int:
	return int(_economy.call("balance", currency_id))


func _econ_owned(asset_id: StringName) -> int:
	return int(_economy.call("owned_count", asset_id))


func _econ_stock(offer_id: StringName) -> int:
	return int(_economy.call("offer_stock", offer_id))


func _test_economy_generations(check: Checker) -> void:
	check.check(_econ_config() != null, "configuration d'économie")
	if _econ_config() == null:
		return
	_econ_apply(&"cultivateur")
	check.equal_str(String(_economy.call("current_generation_id")), "cultivateur",
		"génération cultivateur")
	check.equal_int(_econ_balance(&"gourde"), 30, "solde gourde")
	check.equal_str(String(_economy.call("primary_currency_id")), "gourde",
		"monnaie principale")
	check.equal_int((_economy.call("currencies") as Array).size(), 1, "une monnaie")
	_econ_apply(&"heritier")
	check.equal_int((_economy.call("currencies") as Array).size(), 2, "deux monnaies")
	check.equal_int(_econ_balance(&"euro"), 120, "solde euro")
	check.equal_int(_econ_balance(&"credit_vert"), 5, "solde crédit vert")
	_econ_apply(&"marron")
	check.check(not bool(_economy.call("is_enabled")), "marron désactivé")


func _test_economy_disable(check: Checker) -> void:
	_econ_apply(&"cultivateur")
	check.check(bool(_economy.call("is_enabled")), "économie active")
	_economy.call("set_enabled", false)
	check.check(not bool(_economy.call("is_enabled")), "économie désactivée")
	check.check(not bool(_economy.call("add_currency", &"gourde", 10)),
		"ajout refusé hors ligne")
	_economy.call("set_enabled", true)
	check.check(bool(_economy.call("add_currency", &"gourde", 10)), "ajout accepté")
	_econ_apply(&"marron")
	_economy.call("set_enabled", true)
	check.check(not bool(_economy.call("is_enabled")),
		"génération désactivée non réactivable")


func _test_economy_buy_item(check: Checker) -> void:
	_econ_apply(&"cultivateur")
	_economy.call("set_balance", &"gourde", 20)
	check.check(bool(_economy.call("can_buy", &"item_hoe")), "achat possible")
	check.check(bool(_economy.call("buy", &"item_hoe")), "achat de l'objet")
	check.equal_int(_econ_balance(&"gourde"), 0, "débit de l'objet")
	check.equal_int(_econ_owned(&"hoe"), 1, "objet possédé")
	check.equal_int(_econ_stock(&"item_hoe"), 0, "stock décrémenté")


func _test_economy_buy_property(check: Checker) -> void:
	_econ_apply(&"cultivateur")
	_economy.call("set_balance", &"gourde", 100)
	check.check(bool(_economy.call("buy", &"building_barn")), "achat du bâtiment")
	check.equal_int(_econ_balance(&"gourde"), 40, "débit du bâtiment")
	check.equal_int(_econ_owned(&"barn"), 1, "bâtiment possédé")
	check.equal_int(_econ_stock(&"building_barn"), 0, "stock du bâtiment")
	_economy.call("set_balance", &"gourde", 100)
	check.check(bool(_economy.call("buy", &"slot_field")), "achat emplacement 1")
	check.check(bool(_economy.call("buy", &"slot_field")), "achat emplacement 2")
	check.equal_int(_econ_balance(&"gourde"), 30, "débit des emplacements")
	check.equal_int(_econ_owned(&"field_slot"), 2, "deux emplacements")
	check.equal_int(_econ_stock(&"slot_field"), 0, "stock épuisé")
	check.check(not bool(_economy.call("buy", &"slot_field")), "achat refusé")


func _test_economy_sell(check: Checker) -> void:
	_econ_apply(&"cultivateur")
	_economy.call("set_balance", &"gourde", 100)
	_economy.call("buy", &"building_barn")
	var earned := int(_economy.call("sell", &"building_barn"))
	check.equal_int(earned, 30, "prix de vente du bâtiment")
	check.equal_int(_econ_balance(&"gourde"), 70, "crédit du bâtiment")
	check.equal_int(_econ_owned(&"barn"), 0, "bâtiment vendu")
	check.equal_int(_econ_stock(&"building_barn"), 1, "stock restitué")
	_economy.call("set_balance", &"gourde", 100)
	_economy.call("buy", &"slot_field")
	earned = int(_economy.call("sell", &"slot_field"))
	check.equal_int(earned, 17, "prix de vente de l'emplacement")
	check.equal_int(_econ_balance(&"gourde"), 82, "crédit de l'emplacement")
	check.equal_int(_econ_owned(&"field_slot"), 0, "emplacement vendu")


func _test_economy_trade(check: Checker) -> void:
	_econ_apply(&"heritier")
	check.check(bool(_economy.call("trade",
		{"currency": &"euro", "amount": 10},
		{"currency": &"credit_vert", "amount": 4})), "échange de monnaies")
	check.equal_int(_econ_balance(&"euro"), 110, "euros débités")
	check.equal_int(_econ_balance(&"credit_vert"), 9, "crédits crédités")
	check.check(not bool(_economy.call("trade",
		{"currency": &"euro", "amount": 999},
		{"currency": &"credit_vert", "amount": 1})), "échange refusé")
	_econ_apply(&"cultivateur")
	_economy.call("set_balance", &"gourde", 30)
	check.check(bool(_economy.call("trade",
		{"currency": &"gourde", "amount": 5},
		{"asset": &"hoe", "amount": 1})), "échange contre un bien")
	check.equal_int(_econ_balance(&"gourde"), 25, "débit de l'échange")
	check.equal_int(_econ_owned(&"hoe"), 1, "bien reçu")


func _test_economy_state(check: Checker) -> void:
	_econ_apply(&"cultivateur")
	_economy.call("set_balance", &"gourde", 100)
	_economy.call("buy", &"building_barn")
	_economy.call("set_enabled", false)
	var state: Dictionary = _economy.call("to_dict")
	_economy.call("reset")
	check.equal_int(_econ_balance(&"gourde"), 30, "état réinitialisé")
	check.check(bool(_economy.call("from_dict", state)), "restauration acceptée")
	check.equal_int(_econ_balance(&"gourde"), 40, "portefeuille restauré")
	check.equal_int(_econ_owned(&"barn"), 1, "propriété restaurée")
	check.equal_int(_econ_stock(&"building_barn"), 0, "stock restauré")
	check.check(not bool(_economy.call("is_enabled")), "désactivation restaurée")


func _test_economy_game_state(check: Checker) -> void:
	if not GameState.has_method("format_wallets"):
		check.check(false, "GameState sans intégration économie")
		return
	_econ_apply(&"cultivateur")
	GameState.reset()
	check.equal_int(GameState.money, 30, "GameState aligné sur le portefeuille")
	GameState.money = 77
	check.equal_int(_econ_balance(&"gourde"), 77, "écriture dans le portefeuille")
	check.check(GameState.spend_money(7), "dépense GameState")
	check.equal_int(_econ_balance(&"gourde"), 70, "solde Economie")
	check.equal_str(String(GameState.call("format_wallets")), "70 G", "portefeuilles affichés")
