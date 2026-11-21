extends SceneTree
## Development helper: checks that the player can actually cross every bridge.
##   godot --headless --path . --script res://tools/check_maroon_paths.gd

const BRIDGES := [
	{"row": 85, "start": Vector2(26, 85), "target": 45.0},
	{"row": 53, "start": Vector2(37, 53), "target": 25.0},
	{"row": 27, "start": Vector2(27, 27), "target": 42.0},
	{"row": 80, "start": Vector2(25, 80), "target": 28.0, "blocked": true},
]


func _initialize() -> void:
	_run()


func _run() -> void:
	var map: Node = load("res://scenes/maps/maroon.tscn").instantiate()
	root.add_child(map)
	await physics_frame
	await physics_frame
	var player: Node2D = map.get_node("World/Player")
	for bridge: Dictionary in BRIDGES:
		var start_tile: Vector2 = bridge["start"]
		player.global_position = Vector2(start_tile.x * 48.0 + 24.0, start_tile.y * 48.0 + 24.0)
		player.set("velocity", Vector2.ZERO)
		Input.action_press("move_right" if float(bridge["target"]) > start_tile.x else "move_left")
		for frame in 240:
			await physics_frame
		Input.action_release("move_right")
		Input.action_release("move_left")
		print("bridge row %d: x=%.1f tile=%.1f target=%.1f blocked=%s" % [
			int(bridge["row"]), player.global_position.x,
			(player.global_position.x - 24.0) / 48.0, float(bridge["target"]),
			bool(bridge.get("blocked", false))])
	quit()
