extends SceneTree
## Development helper: renders Map 1 at several anchors so the layout can be
## inspected without playing. Run windowed (not headless):
##   godot --path . --script res://tools/preview_maroon.gd

const SHOTS := [
	{"name": "01_beach", "tile": Vector2(14, 101), "zoom": 1.0},
	{"name": "02_estuary", "tile": Vector2(42, 88), "zoom": 1.0},
	{"name": "03_forest", "tile": Vector2(42, 64), "zoom": 1.0},
	{"name": "04_waterfall", "tile": Vector2(26, 44), "zoom": 1.0},
	{"name": "05_pass", "tile": Vector2(44, 24), "zoom": 1.0},
	{"name": "06_refuge", "tile": Vector2(52, 20), "zoom": 1.0},
	{"name": "07_coast_overview", "tile": Vector2(36, 88), "zoom": 0.35},
	{"name": "08_mountain_overview", "tile": Vector2(36, 30), "zoom": 0.35},
	{"name": "09_shore_close", "tile": Vector2(18, 101), "zoom": 4.0},
	{"name": "10_path_close", "tile": Vector2(22, 40), "zoom": 4.0},
	{"name": "11_dock", "tile": Vector2(60, 101), "zoom": 2.0},
	{"name": "12_goats", "tile": Vector2(46, 29), "zoom": 2.5},
	{"name": "13_rabbits", "tile": Vector2(24, 60), "zoom": 2.5},
	{"name": "14_sea", "tile": Vector2(50, 108), "zoom": 2.0},
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
		for frame in 4:
			await process_frame
		var image := root.get_viewport().get_texture().get_image()
		var path := "user://maroon_preview_%s.png" % shot["name"]
		image.save_png(path)
		print("saved ", ProjectSettings.globalize_path(path))
	quit()
