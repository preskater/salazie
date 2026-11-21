extends SceneTree
## Development helper: verifies that every task anchor and checkpoint is on
## free ground and not inside a rock, the cabin or the water collision.
##   godot --headless --path . --script res://tools/check_maroon_anchors.gd


func _initialize() -> void:
	_run()


func _run() -> void:
	var map: Node = load("res://scenes/maps/maroon.tscn").instantiate()
	root.add_child(map)
	await physics_frame
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState2D = map.get_world_2d().direct_space_state
	var checked := 0
	var blocked := 0
	for group: String in ["forage_spots", "hide_spots", "checkpoints"]:
		for node: Node in get_nodes_in_group(group):
			var body := node as Node2D
			checked += 1
			var params := PhysicsPointQueryParameters2D.new()
			params.position = body.global_position
			params.collision_mask = 1
			params.collide_with_areas = false
			var hits: Array[Dictionary] = space.intersect_point(params)
			if not hits.is_empty():
				blocked += 1
				print("blocked %s at %s (%d hits)" % [node.name, body.global_position, hits.size()])
	var exit: Node2D = map.get_node("RefugeExit")
	checked += 1
	var exit_params := PhysicsPointQueryParameters2D.new()
	exit_params.position = exit.global_position
	exit_params.collision_mask = 1
	var exit_hits: Array[Dictionary] = space.intersect_point(exit_params)
	if not exit_hits.is_empty():
		blocked += 1
		print("blocked RefugeExit at %s" % exit.global_position)
	print("checked %d anchors, blocked %d" % [checked, blocked])
	quit(1 if blocked > 0 else 0)
