extends SceneTree
## Development helper: captures Map 1 animation close-ups after a short delay so
## animations have advanced past their random start frame.
##   godot --path . --script res://tools/preview_maroon_anim.gd

const SHOTS := [
	{"name": "sea", "tile": Vector2(40, 101), "zoom": 1.0},
	{"name": "boat", "tile": Vector2(52, 105), "zoom": 2.0},
	{"name": "buoy_west", "tile": Vector2(22, 108), "zoom": 2.5},
	{"name": "buoy_east", "tile": Vector2(54, 109), "zoom": 2.5},
	{"name": "fish_estuary", "tile": Vector2(35, 96), "zoom": 3.0},
	{"name": "pool_fish_mist", "tile": Vector2(31, 42), "zoom": 1.5},
	{"name": "river_fish", "tile": Vector2(32, 62), "zoom": 3.0},
	{"name": "camp_smoke", "tile": Vector2(42, 63), "zoom": 1.5},
	{"name": "refuge_smoke", "tile": Vector2(50, 20), "zoom": 1.5},
	{"name": "goats", "tile": Vector2(46, 29), "zoom": 2.0},
	{"name": "rabbits", "tile": Vector2(24, 60), "zoom": 2.0},
	{"name": "ducks", "tile": Vector2(44, 96), "zoom": 2.5},
	{"name": "seagulls", "tile": Vector2(14, 101), "zoom": 3.0},
	{"name": "crow", "tile": Vector2(22, 20), "zoom": 1.5},
]


func _initialize() -> void:
	_run()


func _run() -> void:
	var map: Node = load("res://scenes/maps/maroon.tscn").instantiate()
	root.add_child(map)
	await process_frame
	await process_frame
	var player: Node2D = map.get_node("World/Player")
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	for shot: Dictionary in SHOTS:
		var tile: Vector2 = shot["tile"]
		player.global_position = Vector2(tile.x * 48.0 + 24.0, tile.y * 48.0 + 24.0)
		camera.zoom = Vector2.ONE * float(shot["zoom"])
		camera.reset_smoothing()
		await create_timer(0.9).timeout
		var image := root.get_viewport().get_texture().get_image()
		var path := "user://maroon_anim_%s.png" % shot["name"]
		image.save_png(path)
		print("saved ", ProjectSettings.globalize_path(path))
	quit()
