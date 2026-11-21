extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	var map: Node = load("res://scenes/maps/farm.tscn").instantiate()
	root.add_child(map)
	await process_frame
	var ground: TileMapLayer = map.get_node("Ground")
	var counts: Dictionary = {}
	for cell: Vector2i in ground.get_used_cells():
		var key := "%d/%s" % [ground.get_cell_source_id(cell), ground.get_cell_atlas_coords(cell)]
		counts[key] = int(counts.get(key, 0)) + 1
	var arr: Array = []
	for k: String in counts: arr.append([counts[k], k])
	arr.sort_custom(func(a,b): return a[0] > b[0])
	for i in mini(30, arr.size()): print(arr[i][1], " ", arr[i][0])
	quit()
