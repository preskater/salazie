extends Area2D
## A stealth zone: a cave, a waterfall alcove or any place that covers the player.
## The map creates these from the layout anchors.

signal entered(zone_name: String)
signal exited(zone_name: String)

@export var zone_name := "Zone"
@export var conceal_player := true
@export var mute_noise := false

var _player: Node2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	add_to_group("stealth_zones")


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player = body
	if conceal_player:
		body.call("set_hidden", true)
	if mute_noise:
		body.call("set_noise_muted", true)
	entered.emit(zone_name)


func _on_body_exited(body: Node2D) -> void:
	if body != _player:
		return
	# Zones can nest (the alcove sits inside the waterfall spray).
	if conceal_player and not _other_zone_covers(body, "conceal_player"):
		body.call("set_hidden", false)
	if mute_noise and not _other_zone_covers(body, "mute_noise"):
		body.call("set_noise_muted", false)
	_player = null
	exited.emit(zone_name)


func _other_zone_covers(body: Node2D, property: String) -> bool:
	for zone: Node in get_tree().get_nodes_in_group("stealth_zones"):
		if zone == self or not (zone is Area2D):
			continue
		if bool(zone.get(property)) and (zone as Area2D).overlaps_body(body):
			return true
	return false
