class_name StealthZone
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
		body.call("add_cover", self)
	if mute_noise:
		body.call("add_quiet", self)
	entered.emit(zone_name)


func _on_body_exited(body: Node2D) -> void:
	if body != _player:
		return
	# Zones nest (the alcove sits inside the waterfall spray, a bush inside the
	# cave): the player counts its sources, so only this one is withdrawn.
	if conceal_player:
		body.call("remove_cover", self)
	if mute_noise:
		body.call("remove_quiet", self)
	_player = null
	exited.emit(zone_name)
