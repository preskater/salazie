extends Node
## Campaign progression for the three Salazie generations.
##
## Every map owns an ordered list of tasks. A task can be pending, done or
## failed, and the failures are kept even when the task is retried and later
## succeeds. A map is resolved once no task is pending; the next generation is
## unlocked at that point, whatever the final mix of done and failed tasks is.

signal task_status_changed(map_id: int, task_id: String, status: int)
signal map_resolved(map_id: int, summary: Dictionary)
signal map_unresolved(map_id: int)
signal map_changed(map_id: int)
signal choices_changed()
signal setback_recorded(map_id: int, count: int)

enum TaskStatus { PENDING, DONE, FAILED }

const MAP_ORDER: Array[int] = [1, 2, 3]
const BASE_START_MONEY := 30
## Setbacks are failures that belong to a map rather than to a task: being
## caught, collapsing from hunger. Only the first ones weigh on the generation
## result, so one hard section cannot decide the whole campaign.
const SETBACK_CAP := 2

const MAPS := {
	1: {
		"scene": "res://scenes/maps/maroon.tscn",
		"title": "Le marron",
		"subtitle": "Première génération",
		"next": 2,
	},
	2: {
		"scene": "res://scenes/maps/farm.tscn",
		"title": "Le cultivateur",
		"subtitle": "Deuxième génération",
		"next": 3,
	},
	3: {
		"scene": "res://scenes/maps/heir.tscn",
		"title": "L'héritier",
		"subtitle": "Troisième génération",
		"next": 0,
	},
}

## Task definitions. Hints never name a key: `{interact}` and the other action
## tokens are resolved by `InputHints.format()` when the hint is shown.
## `target` supports multi-step tasks; `critical` marks the
## task whose permanent failure makes the generation result "poor".
const TASKS := {
	1: [
		{
			"id": "follow_river",
			"label": "Trouver la rivière",
			"hint": "Quittez la plage et remontez l'estuaire jusqu'au premier pont.",
			"target": 1,
			"retryable": false,
		},
		{
			"id": "find_water",
			"label": "Boire à la rivière",
			"hint": "Buvez au bassin, sous la cascade.",
			"target": 1,
			"retryable": false,
		},
		{
			"id": "find_food",
			"label": "Rassembler des vivres",
			"hint": "Ramassez 3 coquillages, baies ou champignons sauvages.",
			"target": 3,
			"retryable": false,
		},
		{
			"id": "reach_refuge",
			"label": "Rejoindre le refuge du col",
			"hint": "Atteignez la cabane au sommet du sentier.",
			"target": 1,
			"retryable": false,
		},
		{
			"id": "gather_seeds",
			"label": "Ramasser des graines sauvages",
			"hint": "Ramassez 3 graines pour la prochaine génération (optionnel).",
			"target": 3,
			"retryable": false,
			"optional": true,
		},
	],
	2: [
		{
			"id": "prepare_plot",
			"label": "Préparer une parcelle",
			"hint": "Préparez une parcelle du potager ({interact}).",
			"target": 1,
			"retryable": false,
		},
		{
			"id": "plant_seed",
			"label": "Planter une graine",
			"hint": "Choisissez une graine ({select_seed}) puis plantez ({interact}).",
			"target": 1,
			"retryable": false,
		},
		{
			"id": "harvest_crop",
			"label": "Récolter une culture",
			"hint": "Récoltez une culture mûre ({interact}).",
			"target": 1,
			"retryable": false,
		},
		{
			"id": "sell_produce",
			"label": "Vendre au marché",
			"hint": "Vendez votre récolte au marché du hameau ({interact}).",
			"target": 1,
			"retryable": false,
		},
		{
			"id": "earn_100",
			"label": "Faire prospérer la ferme",
			"hint": "Atteignez 100 G avant le jour 6.",
			"target": 1,
			"retryable": false,
		},
	],
	3: [
		{
			"id": "listen",
			"label": "Écouter les habitants",
			"hint": "Parlez à 3 habitants du village.",
			"target": 3,
			"retryable": false,
		},
		{
			"id": "assess",
			"label": "Évaluer les zones fragiles",
			"hint": "Inspectez la berge, la forêt et le marché.",
			"target": 3,
			"retryable": false,
		},
		{
			"id": "choose_plan",
			"label": "Choisir un plan pour Salazie",
			"hint": "Prenez position au point de décision.",
			"target": 1,
			"retryable": false,
			"critical": true,
		},
		{
			"id": "become_mayor",
			"label": "Convaincre le conseil",
			"hint": "Présentez votre plan à la mairie.",
			"target": 1,
			"retryable": false,
			"critical": true,
		},
	],
}

var current_map := 1
var tasks: Dictionary = {}
var results: Dictionary = {}
var choices: Dictionary = {}
var bonus_seeds: Dictionary = {}
var setbacks: Dictionary = {}
var heritage := 0
var finished := false

var _resolved_announced: Dictionary = {}


func _ready() -> void:
	reset()


## Restarts the campaign at Map 1 with every task pending.
func reset() -> void:
	current_map = 1
	heritage = 0
	finished = false
	choices = {}
	results = {}
	bonus_seeds = {}
	setbacks = {}
	_resolved_announced = {}
	tasks = {}
	for map_id: int in MAP_ORDER:
		tasks[map_id] = _default_tasks(map_id)
	choices_changed.emit()


func ensure_map(map_id: int) -> void:
	if not tasks.has(map_id):
		tasks[map_id] = _default_tasks(map_id)


func map_definition(map_id: int = -1) -> Dictionary:
	var id := _active_map(map_id)
	return MAPS.get(id, {})


func current_scene_path() -> String:
	return String(map_definition(current_map).get("scene", ""))


func map_title(map_id: int = -1) -> String:
	return String(map_definition(map_id).get("title", "Salazie"))


func map_subtitle(map_id: int = -1) -> String:
	return String(map_definition(map_id).get("subtitle", ""))


func next_map_id(map_id: int = -1) -> int:
	return int(map_definition(map_id).get("next", 0))


func task_definition(task_id: String, map_id: int = -1) -> Dictionary:
	var id := _active_map(map_id)
	for definition: Dictionary in TASKS.get(id, []):
		if String(definition.get("id", "")) == task_id:
			return definition
	return {}


func task_status(task_id: String, map_id: int = -1) -> int:
	var state := _task_state(task_id, map_id)
	return int(state.get("status", TaskStatus.PENDING))


func task_progress(task_id: String, map_id: int = -1) -> int:
	return int(_task_state(task_id, map_id).get("progress", 0))


func task_target(task_id: String, map_id: int = -1) -> int:
	return maxi(1, int(task_definition(task_id, map_id).get("target", 1)))


func task_attempts(task_id: String, map_id: int = -1) -> int:
	return int(_task_state(task_id, map_id).get("attempts", 0))


func task_failures(task_id: String, map_id: int = -1) -> Array:
	return _task_state(task_id, map_id).get("failures", []).duplicate(true)


func task_failure_count(task_id: String, map_id: int = -1) -> int:
	return task_failures(task_id, map_id).size()


func task_last_failure(task_id: String, map_id: int = -1) -> String:
	var failures := task_failures(task_id, map_id)
	if failures.is_empty():
		return ""
	return String((failures[-1] as Dictionary).get("reason", ""))


func task_retryable(task_id: String, map_id: int = -1) -> bool:
	return bool(task_definition(task_id, map_id).get("retryable", false))


## Marks a task as done. A task that is already done is left untouched.
func complete_task(task_id: String, map_id: int = -1) -> bool:
	var id := _active_map(map_id)
	ensure_map(id)
	var state := _task_state(task_id, id)
	if state.is_empty():
		return false
	if int(state.get("status", TaskStatus.PENDING)) == TaskStatus.DONE:
		return false
	var target := task_target(task_id, id)
	state["status"] = TaskStatus.DONE
	state["progress"] = target
	state["attempts"] = int(state.get("attempts", 0)) + 1
	tasks[id][task_id] = state
	task_status_changed.emit(id, task_id, TaskStatus.DONE)
	_refresh_result(id)
	return true


## Adds progress to a multi-step task and completes it when the target is met.
func add_task_progress(task_id: String, amount: int = 1, map_id: int = -1) -> bool:
	var id := _active_map(map_id)
	ensure_map(id)
	var state := _task_state(task_id, id)
	if state.is_empty():
		return false
	if int(state.get("status", TaskStatus.PENDING)) != TaskStatus.PENDING:
		return false
	var target := task_target(task_id, id)
	var progress := mini(target, int(state.get("progress", 0)) + maxi(0, amount))
	state["progress"] = progress
	tasks[id][task_id] = state
	if progress >= target:
		return complete_task(task_id, id)
	task_status_changed.emit(id, task_id, TaskStatus.PENDING)
	return false


## Records a failure. The task stays FAILED until `retry_task()` is called or
## the map is left; the failure itself is never erased.
func fail_task(task_id: String, reason: String = "", map_id: int = -1) -> bool:
	var id := _active_map(map_id)
	ensure_map(id)
	var state := _task_state(task_id, id)
	if state.is_empty():
		return false
	var current_status := int(state.get("status", TaskStatus.PENDING))
	if current_status == TaskStatus.FAILED or current_status == TaskStatus.DONE:
		return false
	state["status"] = TaskStatus.FAILED
	state["attempts"] = int(state.get("attempts", 0)) + 1
	var failures: Array = state.get("failures", [])
	failures.append({
		"reason": reason,
		"at": Time.get_datetime_string_from_system(),
	})
	state["failures"] = failures
	tasks[id][task_id] = state
	task_status_changed.emit(id, task_id, TaskStatus.FAILED)
	_refresh_result(id)
	return true


## Puts a retryable failed task back in the pending pool. The failure history
## stays in the generation result.
func retry_task(task_id: String, map_id: int = -1) -> bool:
	var id := _active_map(map_id)
	if not task_retryable(task_id, id):
		return false
	var state := _task_state(task_id, id)
	if int(state.get("status", TaskStatus.PENDING)) != TaskStatus.FAILED:
		return false
	state["status"] = TaskStatus.PENDING
	state["progress"] = 0
	tasks[id][task_id] = state
	task_status_changed.emit(id, task_id, TaskStatus.PENDING)
	_refresh_result(id)
	return true


## Records a failure that is not tied to a task. Returns the number of
## setbacks the map now holds.
func record_setback(reason: String, map_id: int = -1) -> int:
	var id := _active_map(map_id)
	var entries: Array = setbacks.get(id, [])
	entries.append({
		"reason": reason,
		"at": Time.get_datetime_string_from_system(),
	})
	setbacks[id] = entries
	setback_recorded.emit(id, entries.size())
	if results.has(id):
		results[id] = map_summary(id).duplicate(true)
	return entries.size()


func setbacks_for_map(map_id: int = -1) -> int:
	return (setbacks.get(_active_map(map_id), []) as Array).size()


func is_map_resolved(map_id: int = -1) -> bool:
	return int(map_summary(map_id).get("pending", 0)) == 0


func is_map_complete(map_id: int = -1) -> bool:
	return is_map_resolved(map_id)


func can_leave_map(map_id: int = -1) -> bool:
	return is_map_resolved(map_id)


func map_summary(map_id: int = -1) -> Dictionary:
	var id := _active_map(map_id)
	ensure_map(id)
	var done := 0
	var failed := 0
	var pending := 0
	var optional_pending := 0
	var failure_events := 0
	var critical_failed := false
	var details: Dictionary = {}
	for definition: Dictionary in TASKS.get(id, []):
		var task_id := String(definition.get("id", ""))
		var is_optional := bool(definition.get("optional", false))
		var state := _task_state(task_id, id)
		var status := int(state.get("status", TaskStatus.PENDING))
		var failures: Array = state.get("failures", [])
		failure_events += failures.size()
		match status:
			TaskStatus.DONE:
				done += 1
			TaskStatus.FAILED:
				failed += 1
				if bool(definition.get("critical", false)):
					critical_failed = true
			_:
				if is_optional:
					optional_pending += 1
				else:
					pending += 1
		details[task_id] = {
			"id": task_id,
			"label": String(definition.get("label", task_id)),
			"status": status,
			"progress": int(state.get("progress", 0)),
			"target": maxi(1, int(definition.get("target", 1))),
			"attempts": int(state.get("attempts", 0)),
			"failures": failures.duplicate(true),
			"retryable": bool(definition.get("retryable", false)),
			"critical": bool(definition.get("critical", false)),
			"optional": is_optional,
		}
	var setback_list: Array = setbacks.get(id, [])
	failure_events += mini(setback_list.size(), SETBACK_CAP)
	var rank := "pending"
	if pending == 0:
		if critical_failed:
			rank = "poor"
		elif failure_events > 0 or failed > 0:
			rank = "partial"
		else:
			rank = "full"
	return {
		"map": id,
		"title": map_title(id),
		"done": done,
		"failed": failed,
		"pending": pending,
		"optional_pending": optional_pending,
		"failure_events": failure_events,
		"setbacks": setback_list.duplicate(true),
		"rank": rank,
		"tasks": details,
	}


## Stores the result when a map becomes resolved and announces it once.
func finalize_map(map_id: int = -1) -> Dictionary:
	var id := _active_map(map_id)
	var summary := map_summary(id)
	if int(summary.get("pending", 0)) > 0:
		return {}
	results[id] = summary.duplicate(true)
	if not bool(_resolved_announced.get(id, false)):
		_resolved_announced[id] = true
		map_resolved.emit(id, summary)
	return summary


func advance_to_next_map() -> bool:
	finalize_map(current_map)
	var next := next_map_id(current_map)
	if next == 0:
		finished = true
		map_changed.emit(current_map)
		return false
	current_map = next
	ensure_map(current_map)
	map_changed.emit(current_map)
	return true


func set_choice(key: String, value: String) -> void:
	choices[key] = value
	choices_changed.emit()


## Stores seeds collected on Map 1 so the farmer starts with them.
func add_bonus_seed(crop: String, amount := 1) -> void:
	if not GameState.CROPS.has(crop) or amount <= 0:
		return
	bonus_seeds[crop] = int(bonus_seeds.get(crop, 0)) + amount


func _read_bonus_seeds(raw: Variant) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		return result
	var source := raw as Dictionary
	for crop_key: Variant in source:
		var crop := String(crop_key)
		if not GameState.CROPS.has(crop):
			continue
		result[crop] = maxi(0, int(source[crop_key]))
	return result


func get_choice(key: String, fallback: String = "") -> String:
	return String(choices.get(key, fallback))


func total_failure_events() -> int:
	var total := 0
	for map_id: int in MAP_ORDER:
		total += int(map_summary(map_id).get("failure_events", 0))
	return total


func failure_events_for_map(map_id: int = -1) -> int:
	return int(map_summary(map_id).get("failure_events", 0))


## Support score for the final council vote. Every failure across the three
## generations costs one point out of six.
func mayor_support() -> int:
	return maxi(0, 6 - total_failure_events())


func has_mayor_support() -> bool:
	return mayor_support() >= 4


## Money the next farmer starts with after the escape from Map 1.
func starting_money_for_map(map_id: int) -> int:
	if map_id <= 1:
		return BASE_START_MONEY
	var failures := failure_events_for_map(1)
	return maxi(15, BASE_START_MONEY - mini(15, failures * 5))


## Family heritage handed from the farm to the heir.
func heritage_for_map3() -> int:
	var failures := failure_events_for_map(2)
	var money := int(GameState.money)
	return maxi(0, int(floor(float(money) * (1.0 - 0.1 * float(failures)))))


func next_map_label() -> String:
	var next := next_map_id(current_map)
	if next == 0:
		return "Épilogue de Salazie"
	return "Prochaine génération : %s" % map_title(next)


func to_dict() -> Dictionary:
	return {
		"current_map": current_map,
		"tasks": tasks.duplicate(true),
		"results": results.duplicate(true),
		"choices": choices.duplicate(true),
		"bonus_seeds": bonus_seeds.duplicate(true),
		"setbacks": setbacks.duplicate(true),
		"heritage": heritage,
		"finished": finished,
	}


## Applies a save payload. Returns false and leaves the campaign untouched when
## the payload is not a dictionary.
func from_dict(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var next_tasks: Dictionary = {}
	for map_id: int in MAP_ORDER:
		next_tasks[map_id] = _default_tasks(map_id)
	var raw_tasks: Variant = data.get("tasks", {})
	if raw_tasks is Dictionary:
		for map_key: Variant in (raw_tasks as Dictionary):
			var map_id := int(map_key)
			if not next_tasks.has(map_id):
				continue
			var raw_map: Variant = (raw_tasks as Dictionary)[map_key]
			if not (raw_map is Dictionary):
				continue
			for task_key: Variant in (raw_map as Dictionary):
				var task_id := String(task_key)
				if not next_tasks[map_id].has(task_id):
					continue
				var raw_state: Variant = (raw_map as Dictionary)[task_key]
				if raw_state is Dictionary:
					next_tasks[map_id][task_id] = _sanitize_state(
						next_tasks[map_id][task_id], raw_state as Dictionary)
	var next_current := clampi(int(data.get("current_map", 1)), 1, 3)
	if bool(data.get("legacy_v1", false)):
		_mark_map_one_done(next_tasks)
		var earn_state: Dictionary = next_tasks[2].get("earn_100", {})
		if int(GameState.money) >= 100:
			earn_state["status"] = TaskStatus.DONE
			earn_state["progress"] = 1
			next_tasks[2]["earn_100"] = earn_state
	tasks = next_tasks
	current_map = next_current
	# A save written before the river task existed is already past Map 1.
	if current_map > 1:
		var river_state: Dictionary = tasks[1].get("follow_river", {})
		if int(river_state.get("status", TaskStatus.PENDING)) == TaskStatus.PENDING:
			river_state["status"] = TaskStatus.DONE
			river_state["progress"] = maxi(1, int(river_state.get("progress", 0)))
			tasks[1]["follow_river"] = river_state
	var raw_results: Variant = data.get("results", {})
	results = (raw_results as Dictionary).duplicate(true) if raw_results is Dictionary else {}
	var raw_choices: Variant = data.get("choices", {})
	choices = (raw_choices as Dictionary).duplicate(true) if raw_choices is Dictionary else {}
	bonus_seeds = _read_bonus_seeds(data.get("bonus_seeds", {}))
	setbacks = _read_setbacks(data.get("setbacks", {}))
	heritage = maxi(0, int(data.get("heritage", 0)))
	finished = bool(data.get("finished", false))
	_resolved_announced = {}
	for map_id: int in MAP_ORDER:
		if is_map_resolved(map_id):
			_resolved_announced[map_id] = true
	return true


func _default_tasks(map_id: int) -> Dictionary:
	var result := {}
	for definition: Dictionary in TASKS.get(map_id, []):
		result[String(definition.get("id", ""))] = {
			"status": TaskStatus.PENDING,
			"progress": 0,
			"attempts": 0,
			"failures": [],
		}
	return result


func _task_state(task_id: String, map_id: int = -1) -> Dictionary:
	var id := _active_map(map_id)
	if not tasks.has(id):
		return {}
	return tasks[id].get(task_id, {})


func _refresh_result(map_id: int) -> void:
	var summary := map_summary(map_id)
	if int(summary.get("pending", 0)) > 0:
		results.erase(map_id)
		if bool(_resolved_announced.get(map_id, false)):
			_resolved_announced[map_id] = false
			map_unresolved.emit(map_id)
		return
	results[map_id] = summary.duplicate(true)
	if not bool(_resolved_announced.get(map_id, false)):
		_resolved_announced[map_id] = true
		map_resolved.emit(map_id, summary)


func _active_map(map_id: int) -> int:
	return current_map if map_id < 0 else clampi(map_id, 1, 3)


func _sanitize_state(_default_state: Dictionary, raw: Dictionary) -> Dictionary:
	var status := clampi(int(raw.get("status", TaskStatus.PENDING)), 0, 2)
	var failures: Array = []
	var raw_failures: Variant = raw.get("failures", [])
	if raw_failures is Array:
		for entry: Variant in (raw_failures as Array):
			if entry is Dictionary:
				var failure := entry as Dictionary
				failures.append({
					"reason": String(failure.get("reason", "")),
					"at": String(failure.get("at", "")),
				})
	return {
		"status": status,
		"progress": maxi(0, int(raw.get("progress", 0))),
		"attempts": maxi(0, int(raw.get("attempts", 0))),
		"failures": failures,
	}


func _read_setbacks(raw: Variant) -> Dictionary:
	var result := {}
	if not (raw is Dictionary):
		return result
	for map_key: Variant in (raw as Dictionary):
		# JSON turns the integer map ids into strings.
		var map_id := int(String(map_key)) if String(map_key).is_valid_int() else 0
		var raw_entries: Variant = (raw as Dictionary)[map_key]
		if not MAP_ORDER.has(map_id) or not (raw_entries is Array):
			continue
		var entries: Array = []
		for entry: Variant in (raw_entries as Array):
			if entry is Dictionary:
				entries.append({
					"reason": String((entry as Dictionary).get("reason", "")),
					"at": String((entry as Dictionary).get("at", "")),
				})
		if not entries.is_empty():
			result[map_id] = entries
	return result


func _mark_map_one_done(next_tasks: Dictionary) -> void:
	for definition: Dictionary in TASKS[1]:
		var task_id := String(definition.get("id", ""))
		var state: Dictionary = next_tasks[1][task_id]
		state["status"] = TaskStatus.DONE
		state["progress"] = maxi(1, int(definition.get("target", 1)))
		next_tasks[1][task_id] = state
