extends RefCounted
## Builds the static world of Map 1: the coast, the river, the forest, the
## gorge and the mountain pass. Gameplay nodes (player, guards, pickups, tasks)
## are added by `maroon_map.gd` at the anchors returned by `build()`.

const TILE := 48
const COLS := 72
const ROWS := 112
const SEA_ROW := 104
const BEACH_ROW := 94

const TILESET := preload("res://game_resources/tilesets/maroon_ground.tres")
const DECOR := preload("res://scripts/maroon/maroon_decor.gd")
const WATER_SHADER := preload("res://shaders/world/water_flow.gdshader")
const WATERFALL_SHADER := preload("res://shaders/world/waterfall_flow.gdshader")
const SEA_WATER_TEXTURE := preload("res://sprites/exteriors_48x48/animated/terrains/Sea_Water_Tileset_48x48.png")
const WATER_EDGE_SHADER := preload("res://shaders/world/water_edge.gdshader")

# Atlas source ids saved by `tools/build_maroon_tilesets.gd`.
const GRASS_SOURCE := 0
const FARM_DIRT_SOURCE := 1
const BEACH_SOURCE := 2
const MOUND_A_SOURCE := 3
const MOUND_B_SOURCE := 4
const SEA_WATER_SOURCE := 5

enum CellKind { WATER, SAND, DIRT, GRASS }
enum Outside { WATER, GRASS, LAND, SAND }

const GRASS_TILES: Array[Vector2i] = [
	Vector2i(1, 7), Vector2i(9, 7), Vector2i(17, 7),
]
const DIRT_TILES: Array[Vector2i] = [
	Vector2i(1, 31), Vector2i(1, 51),
]
const FARM_DIRT_TILES: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(4, 2),
]
const SAND_TILES: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(4, 3), Vector2i(9, 2), Vector2i(12, 3), Vector2i(8, 6),
]
const WATER_TILE := Vector2i(27, 5)
const WATER_EDGE_TILE := Vector2i(1, 0)

## 3x3 transition blocks in the pack sheets. Keys are edge patterns.
const DIRT_GRASS_VARIANTS := {
	"C": Vector2i(1, 1), "N": Vector2i(1, 0), "NE": Vector2i(2, 0),
	"E": Vector2i(2, 1), "SE": Vector2i(2, 2), "S": Vector2i(1, 2),
	"SW": Vector2i(0, 2), "W": Vector2i(0, 1), "NW": Vector2i(0, 0),
}
const DIRT_CORRIDOR_V := Vector2i(15, 9)
const DIRT_CORRIDOR_H := Vector2i(17, 9)
const GRASS_WATER_VARIANTS := {
	"C": Vector2i(9, 7), "N": Vector2i(9, 6), "NE": Vector2i(10, 6),
	"E": Vector2i(10, 7), "SE": Vector2i(10, 8), "S": Vector2i(9, 8),
	"SW": Vector2i(8, 8), "W": Vector2i(8, 7), "NW": Vector2i(8, 6),
}
const SAND_GRASS_VARIANTS := {
	"C": Vector2i(1, 5), "N": Vector2i(1, 4), "NE": Vector2i(2, 4),
	"E": Vector2i(2, 5), "SE": Vector2i(2, 6), "S": Vector2i(1, 6),
	"SW": Vector2i(0, 6), "W": Vector2i(0, 5), "NW": Vector2i(0, 4),
}

# (x centre, row, half width) from the mountain source to the sea.
const RIVER_POINTS: Array[Vector3] = [
	Vector3(34, 0, 3.0),
	Vector3(31, 10, 3.0),
	Vector3(34, 20, 3.2),
	Vector3(30, 30, 3.6),
	Vector3(33, 38, 4.2),
	Vector3(34, 44, 5.2),
	Vector3(30, 52, 4.2),
	Vector3(33, 60, 4.5),
	Vector3(29, 68, 5.0),
	Vector3(32, 76, 5.8),
	Vector3(36, 84, 6.8),
	Vector3(36, 92, 8.5),
	Vector3(36, 99, 13.0),
	Vector3(36, 104, 20.0),
]

const SPAWN_TILE := Vector2i(14, 101)
const RIVER_MOUTH_TILE := Vector2i(46, 84)
const FOREST_CAMP_TILE := Vector2i(42, 64)
const UPPER_CHECKPOINT_TILE := Vector2i(44, 24)
const REFUGE_TILE := Vector2i(52, 20)
const CABIN_TILE := Vector2i(52, 18)
const WATER_SPOT_TILE := Vector2i(26, 44)

const BRIDGE_ROWS: Array[int] = [84, 52, 26]
const BRIDGE_HEIGHT := 2
## Walkable part of the cliff ridge, in tiles (inclusive).
const RIDGE_LEFT := 41
const RIDGE_RIGHT := 43
const RIDGE_TOP := 30
const RIDGE_BOTTOM := 48

const FOOD_TILES: Array[Vector2i] = [
	Vector2i(10, 99),
	Vector2i(40, 74),
	Vector2i(18, 42),
	Vector2i(48, 92),
]
const HIDE_TILES: Array[Vector2i] = [
	Vector2i(38, 72),
	Vector2i(20, 50),
	Vector2i(36, 30),
	Vector2i(18, 44),
	Vector2i(26, 42),
	Vector2i(42, 40),
	Vector2i(26, 86),
	Vector2i(44, 76),
	Vector2i(22, 54),
	Vector2i(40, 20),
]
## The second one rewards the ridge route. It used to sit in the gap of the
## ridge wall, which is now closed.
const SEED_TILES: Array[Vector2i] = [
	Vector2i(18, 60),
	Vector2i(41, 38),
	Vector2i(24, 34),
]
const GUARD_TILES: Array[Vector2i] = [
	Vector2i(47, 88),
	Vector2i(44, 70),
	Vector2i(42, 58),
	Vector2i(22, 48),
	Vector2i(40, 28),
]

const TRAIL_POINTS: Array[Vector2i] = [
	Vector2i(14, 101), Vector2i(18, 96), Vector2i(22, 90), Vector2i(26, 86),
	Vector2i(28, 84), Vector2i(44, 84), Vector2i(46, 80), Vector2i(46, 74),
	Vector2i(44, 68), Vector2i(42, 64), Vector2i(44, 58), Vector2i(40, 54),
	Vector2i(36, 52), Vector2i(24, 52), Vector2i(22, 48), Vector2i(24, 44),
	Vector2i(22, 40), Vector2i(24, 36), Vector2i(26, 32), Vector2i(28, 28),
	Vector2i(28, 26), Vector2i(36, 26), Vector2i(42, 26), Vector2i(44, 22),
	Vector2i(48, 18), Vector2i(52, 20),
]
const RIDGE_TRAIL_POINTS: Array[Vector2i] = [
	Vector2i(42, 48), Vector2i(42, 44), Vector2i(42, 40),
	Vector2i(42, 36), Vector2i(42, 32), Vector2i(42, 30),
]
const CAVE_TRAIL_POINTS: Array[Vector2i] = [
	Vector2i(21, 50), Vector2i(20, 50), Vector2i(19, 50), Vector2i(18, 50),
	Vector2i(18, 48), Vector2i(18, 44), Vector2i(18, 40), Vector2i(18, 36),
	Vector2i(20, 36),
]
const ALCOVE_TRAIL_POINTS: Array[Vector2i] = [
	Vector2i(23, 42), Vector2i(24, 42), Vector2i(25, 42), Vector2i(26, 42),
]
const CLIMB_POINTS := [
	{"tile": Vector2i(39, 51), "destination": Vector2i(42, 48),
		"label": "{interact} — Grimper sur la crête"},
	{"tile": Vector2i(42, 30), "destination": Vector2i(44, 28),
		"label": "{interact} — Descendre vers la rivière"},
]
const STEALTH_ZONES := [
	{"tile": Vector2i(18, 44), "tiles": Vector2i(2, 14), "name": "la grotte",
		"conceal": true, "mute": true},
	{"tile": Vector2i(28, 41), "tiles": Vector2i(9, 4), "name": "la cascade",
		"conceal": false, "mute": true},
	{"tile": Vector2i(26, 42), "tiles": Vector2i(3, 3), "name": "l'alcôve",
		"conceal": true, "mute": true},
]

var size := Vector2(COLS * TILE, ROWS * TILE)

var _ground: TileMapLayer
var _water: TileMapLayer
var _terrain: Node2D
var _water_edges: Node2D
var _bridges: TileMapLayer
var _cliffs: TileMapLayer
var _bridge_deck: Node2D
var _world: Node2D
var _decor := DECOR.new()
var _rng := RandomNumberGenerator.new()
var _river_center: Array[float] = []
var _river_half: Array[float] = []
var _trail: Dictionary = {}
var _reserved: Array[Dictionary] = []
var _blocked: Array[Dictionary] = []


func build(terrain: Node2D, world: Node2D) -> Dictionary:
	_world = world
	_rng.seed = 20261121
	_build_river()
	_build_layers(terrain)
	_build_trail()
	_paint_ground()
	_add_water_edges()
	_reserve_anchors()
	_build_bridges()
	_build_collision(terrain)
	_build_waterfall()
	_build_gorge_cliffs()
	_build_mountain_crest()
	_build_cave()
	_build_ridge()
	_build_beach()
	_build_estuary_dock()
	_build_camp()
	_build_refuge()
	_scatter_trees()
	_scatter_rocks()
	_scatter_underbrush()
	_scatter_beach_details()
	_scatter_wildlife()
	_add_zone_signs()
	return {
		"size": size,
		"spawn": _tile_center(SPAWN_TILE),
		"river_mouth_checkpoint": _tile_center(RIVER_MOUTH_TILE),
		"forest_checkpoint": _tile_center(FOREST_CAMP_TILE),
		"upper_checkpoint": _tile_center(UPPER_CHECKPOINT_TILE),
		"refuge": _tile_center(REFUGE_TILE),
		"water_spot": _tile_center(WATER_SPOT_TILE),
		"food_spots": _tiles_to_points(FOOD_TILES),
		"hide_spots": _tiles_to_points(HIDE_TILES),
		"seed_spots": _tiles_to_points(SEED_TILES),
		"guards": _tiles_to_points(GUARD_TILES),
		"climb_points": _climb_specs(),
		"stealth_zones": _stealth_specs(),
	}


func _build_river() -> void:
	_river_center.resize(ROWS)
	_river_half.resize(ROWS)
	for row in ROWS:
		if row >= SEA_ROW:
			_river_center[row] = float(COLS) * 0.5
			_river_half[row] = float(COLS) * 0.5
			continue
		var center := RIVER_POINTS[0].x
		var half := RIVER_POINTS[0].z
		for index in RIVER_POINTS.size() - 1:
			var a := RIVER_POINTS[index]
			var b := RIVER_POINTS[index + 1]
			if float(row) < a.y or float(row) > b.y:
				continue
			var span := maxf(1.0, b.y - a.y)
			var t := smoothstep(0.0, 1.0, (float(row) - a.y) / span)
			center = lerpf(a.x, b.x, t)
			half = lerpf(a.z, b.z, t)
			break
		center += sin(float(row) * 0.19) * 0.8
		_river_center[row] = clampf(center, half + 4.0, float(COLS) - half - 4.0)
		_river_half[row] = half


func _build_layers(terrain: Node2D) -> void:
	_terrain = terrain
	_ground = _make_layer(terrain, "Ground")
	_water = _make_layer(terrain, "Water")
	var water_material := ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	_water.material = water_material
	_ground.z_index = -3
	_water.z_index = -2
	_water_edges = Node2D.new()
	_water_edges.name = "WaterEdges"
	_water_edges.z_index = -1
	terrain.add_child(_water_edges)
	_bridges = _make_layer(terrain, "Bridges")
	_bridges.z_index = -1
	_cliffs = _make_layer(terrain, "CliffDetails")
	_cliffs.z_index = -1
	_bridge_deck = Node2D.new()
	_bridge_deck.name = "BridgeDeck"
	terrain.add_child(_bridge_deck)


func _make_layer(parent: Node2D, layer_name: String) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = TILESET
	layer.collision_enabled = false
	parent.add_child(layer)
	return layer


func _is_water(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.x >= COLS or tile.y < 0 or tile.y >= ROWS:
		return true
	if tile.y >= SEA_ROW:
		return true
	var center := _river_center[tile.y]
	var half := _river_half[tile.y]
	return absf(float(tile.x) + 0.5 - center) <= half


func _water_span(row: int) -> Vector2i:
	var start := 0
	var end := COLS - 1
	if row < SEA_ROW:
		start = int(floor(_river_center[row] - _river_half[row] - 0.5))
		end = int(ceil(_river_center[row] + _river_half[row] - 0.5))
	return Vector2i(clampi(start, 0, COLS - 1), clampi(end, 0, COLS - 1))


func _paint_ground() -> void:
	for row in ROWS:
		for column in COLS:
			var tile := Vector2i(column, row)
			var kind := _cell_kind(tile)
			if kind == CellKind.WATER:
				_water.set_cell(tile, GRASS_SOURCE, WATER_TILE, 0)
				continue
			var choice := _ground_variant(tile, kind)
			_ground.set_cell(tile, int(choice[0]), choice[1], 0)


func _add_water_edges() -> void:
	var edge_material := ShaderMaterial.new()
	edge_material.shader = WATER_EDGE_SHADER
	var north := AtlasTexture.new()
	north.atlas = SEA_WATER_TEXTURE
	north.region = Rect2(1 * TILE, 0, TILE, TILE)
	var south := AtlasTexture.new()
	south.atlas = SEA_WATER_TEXTURE
	south.region = Rect2(5 * TILE, 0, TILE, TILE)
	for row in ROWS:
		for column in COLS:
			var tile := Vector2i(column, row)
			if not _is_water(tile):
				continue
			var sides: Array[String] = []
			if _is_sand(tile + Vector2i(0, -1)) and not _is_water(tile + Vector2i(0, -1)):
				sides.append("N")
			if _is_sand(tile + Vector2i(1, 0)) and not _is_water(tile + Vector2i(1, 0)):
				sides.append("E")
			if _is_sand(tile + Vector2i(0, 1)) and not _is_water(tile + Vector2i(0, 1)):
				sides.append("S")
			if _is_sand(tile + Vector2i(-1, 0)) and not _is_water(tile + Vector2i(-1, 0)):
				sides.append("W")
			for side: String in sides:
				var edge := Sprite2D.new()
				edge.name = "WaterEdge"
				edge.texture = south if side == "S" else north
				edge.position = _tile_center(tile)
				match side:
					"E":
						edge.rotation = PI * 0.5
					"W":
						edge.rotation = -PI * 0.5
					"S":
						edge.rotation = 0.0
				_water_edges.add_child(edge)


func _cell_kind(tile: Vector2i) -> int:
	if _is_water(tile):
		return CellKind.WATER
	if _trail.has(tile):
		return CellKind.DIRT
	if _is_sand(tile):
		return CellKind.SAND
	return CellKind.GRASS


func _ground_variant(tile: Vector2i, kind: int) -> Array:
	match kind:
		CellKind.SAND:
			if _has_outside(tile, Outside.LAND):
				return [FARM_DIRT_SOURCE, SAND_GRASS_VARIANTS[_edge_pattern(tile, Outside.LAND)]]
			return [BEACH_SOURCE, SAND_TILES[_rng.randi_range(0, SAND_TILES.size() - 1)]]
		CellKind.DIRT:
			var north := _matches(tile + Vector2i(0, -1), Outside.GRASS)
			var east := _matches(tile + Vector2i(1, 0), Outside.GRASS)
			var south := _matches(tile + Vector2i(0, 1), Outside.GRASS)
			var west := _matches(tile + Vector2i(-1, 0), Outside.GRASS)
			if west and east and not north and not south:
				return [FARM_DIRT_SOURCE, DIRT_CORRIDOR_V]
			if north and south and not east and not west:
				return [FARM_DIRT_SOURCE, DIRT_CORRIDOR_H]
			if north or east or south or west:
				return [FARM_DIRT_SOURCE, DIRT_GRASS_VARIANTS[_edge_pattern(tile, Outside.GRASS)]]
			return [FARM_DIRT_SOURCE, FARM_DIRT_TILES[_rng.randi_range(0, FARM_DIRT_TILES.size() - 1)]]
		_:
			if _has_outside(tile, Outside.WATER):
				return [GRASS_SOURCE, GRASS_WATER_VARIANTS[_edge_pattern(tile, Outside.WATER)]]
			return [GRASS_SOURCE, GRASS_TILES[_rng.randi_range(0, GRASS_TILES.size() - 1)]]


func _has_outside(tile: Vector2i, outside: int) -> bool:
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			if offset_x == 0 and offset_y == 0:
				continue
			if _matches(tile + Vector2i(offset_x, offset_y), outside):
				return true
	return false


func _edge_pattern(tile: Vector2i, outside: int) -> String:
	var north := _matches(tile + Vector2i(0, -1), outside)
	var east := _matches(tile + Vector2i(1, 0), outside)
	var south := _matches(tile + Vector2i(0, 1), outside)
	var west := _matches(tile + Vector2i(-1, 0), outside)
	if north and west:
		return "NW"
	if north and east:
		return "NE"
	if south and west:
		return "SW"
	if south and east:
		return "SE"
	if north:
		return "N"
	if east:
		return "E"
	if south:
		return "S"
	if west:
		return "W"
	# The packs provide no inner-corner tile. A diagonal-only neighbour must
	# keep the centre tile instead of borrowing an outer corner and flooding
	# the cell with water or dirt.
	return "C"


func _matches(tile: Vector2i, outside: int) -> bool:
	if tile.x < 0 or tile.x >= COLS or tile.y < 0 or tile.y >= ROWS:
		return false
	match outside:
		Outside.WATER:
			return _is_water(tile)
		Outside.GRASS:
			return _cell_kind(tile) == CellKind.GRASS
		Outside.SAND:
			return _is_sand(tile) and not _is_water(tile)
		_:
			var kind := _cell_kind(tile)
			return kind == CellKind.GRASS or kind == CellKind.DIRT


func _is_sand(tile: Vector2i) -> bool:
	if tile.y >= BEACH_ROW:
		return true
	if tile.y < BEACH_ROW - 22:
		return false
	for offset_y in range(-2, 3):
		for offset_x in range(-2, 3):
			var neighbor := tile + Vector2i(offset_x, offset_y)
			if neighbor.x < 0 or neighbor.x >= COLS or neighbor.y < 0 or neighbor.y >= ROWS:
				continue
			if _is_water(neighbor):
				return true
	return false


func _build_trail() -> void:
	_paint_trail(TRAIL_POINTS)
	_paint_trail(RIDGE_TRAIL_POINTS)
	_paint_trail(CAVE_TRAIL_POINTS)
	_paint_trail(ALCOVE_TRAIL_POINTS)
	# Small dirt clearings at the camps, checkpoints and new route ends.
	_paint_clearing(RIVER_MOUTH_TILE, 1)
	_paint_clearing(FOREST_CAMP_TILE, 2)
	_paint_clearing(UPPER_CHECKPOINT_TILE, 1)
	_paint_clearing(REFUGE_TILE, 1)
	_paint_clearing(Vector2i(42, 48), 1)
	_paint_clearing(Vector2i(42, 30), 1)
	_paint_clearing(Vector2i(20, 50), 1)
	_paint_clearing(Vector2i(20, 36), 1)
	_paint_clearing(Vector2i(26, 42), 1)


func _paint_trail(points: Array[Vector2i]) -> void:
	for index in points.size() - 1:
		var from := Vector2(points[index])
		var to := Vector2(points[index + 1])
		var steps := maxi(1, int(from.distance_to(to) * 2.0))
		for step in steps + 1:
			var point := from.lerp(to, float(step) / float(steps))
			var tile := Vector2i(roundi(point.x), roundi(point.y))
			if tile.x < 1 or tile.x >= COLS - 1 or tile.y < 1 or tile.y >= ROWS - 1:
				continue
			if _is_water(tile) or _is_sand(tile):
				continue
			_trail[tile] = true


func _paint_clearing(center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var tile := Vector2i(x, y)
			if Vector2(x, y).distance_to(Vector2(center)) > float(radius):
				continue
			if _is_water(tile) or _is_sand(tile) or tile.x < 1 or tile.x >= COLS - 1 \
					or tile.y < 1 or tile.y >= ROWS - 1:
				continue
			_trail[tile] = true


func _reserve_anchors() -> void:
	_reserve(SPAWN_TILE, 5)
	_reserve(RIVER_MOUTH_TILE, 5)
	_reserve(FOREST_CAMP_TILE, 8)
	_reserve(UPPER_CHECKPOINT_TILE, 6)
	_reserve(REFUGE_TILE, 13)
	_reserve(WATER_SPOT_TILE, 3)
	for tile: Vector2i in FOOD_TILES:
		_reserve(tile, 3)
	for tile: Vector2i in HIDE_TILES:
		_reserve(tile, 3)
	for tile: Vector2i in SEED_TILES:
		_reserve(tile, 3)
	for tile: Vector2i in GUARD_TILES:
		_reserve(tile, 5)
	for spec: Dictionary in CLIMB_POINTS:
		var climb_tile: Vector2i = spec["tile"]
		var climb_destination: Vector2i = spec["destination"]
		_reserve(climb_tile, 3)
		_reserve(climb_destination, 3)
	for spec: Dictionary in STEALTH_ZONES:
		var zone_tile: Vector2i = spec["tile"]
		_reserve(zone_tile, 4)
	for row: int in BRIDGE_ROWS:
		for offset in range(-2, 4):
			_reserve(Vector2i(int(_river_center[row]), row + offset), 3)


func _reserve(tile: Vector2i, radius_tiles: int) -> void:
	_reserved.append({
		"position": _tile_center(tile),
		"radius": float(radius_tiles * TILE),
	})


func _is_free(tile: Vector2i, radius_tiles: float) -> bool:
	if tile.x < 3 or tile.x >= COLS - 3 or tile.y < 3 or tile.y >= ROWS - 3:
		return false
	if _is_water(tile):
		return false
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			if _trail.has(tile + Vector2i(offset_x, offset_y)):
				return false
	var position := _tile_center(tile)
	for entry: Dictionary in _reserved:
		if position.distance_to(entry["position"]) < float(entry["radius"]):
			return false
	var extra := maxf(0.0, radius_tiles) * TILE * 0.5
	for entry: Dictionary in _blocked:
		if position.distance_to(entry["position"]) < float(entry["radius"]) + extra:
			return false
	return true


func _block_tile(tile: Vector2i, radius_tiles: float) -> void:
	_blocked.append({
		"position": _tile_center(tile),
		"radius": float(radius_tiles * TILE),
	})


func _build_bridges() -> void:
	for row: int in BRIDGE_ROWS:
		var span := _water_span(row)
		var second_span := _water_span(row + 1)
		var left := mini(span.x, second_span.x) - 2
		var right := maxi(span.y, second_span.y) + 2
		_build_bridge(row, left, right)


func _build_collision(terrain: Node2D) -> void:
	var body := StaticBody2D.new()
	body.name = "WorldCollision"
	terrain.add_child(body)
	body.add_to_group(&"navigation_obstacles")
	var bridge_rows: Dictionary = {}
	for row: int in BRIDGE_ROWS:
		for offset in BRIDGE_HEIGHT:
			bridge_rows[row + offset] = true
	for row in ROWS:
		if bridge_rows.has(row):
			continue
		var span := _water_span(row)
		_add_shape(body, Rect2(span.x * TILE, row * TILE,
			(span.y - span.x + 1) * TILE, TILE))
	# The rocky crest is scenery, not a walkable area.
	_add_shape(body, Rect2(0.0, 0.0, size.x, 6 * TILE))


func _add_shape(body: StaticBody2D, rect: Rect2) -> void:
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	collision.shape = rectangle
	collision.position = rect.position + rect.size * 0.5
	body.add_child(collision)


func _build_bridge(row: int, left: int, right: int) -> void:
	for y in range(row, row + BRIDGE_HEIGHT):
		for x in range(left, right + 1):
			var tile := Vector2i(x, y)
			if tile.x < 0 or tile.x >= COLS or tile.y < 0 or tile.y >= ROWS:
				continue
			_bridges.set_cell(tile, FARM_DIRT_SOURCE, FARM_DIRT_TILES[_rng.randi_range(0, 1)], 0)
	_add_bridge_planks(row, left, right)
	# Rope rails along both sides, plus a post at each end.
	for offset in 2:
		var rail := Line2D.new()
		rail.name = "BridgeRail"
		rail.width = 4.0
		rail.default_color = Color(0.40, 0.26, 0.14)
		var rail_y := (row + offset * BRIDGE_HEIGHT) * TILE + (8.0 if offset == 0 else -8.0)
		rail.add_point(Vector2(left * TILE, rail_y))
		rail.add_point(Vector2((right + 1) * TILE, rail_y))
		_bridge_deck.add_child(rail)
	for x: int in [left, right]:
		_decor.add_prop(_world,
			"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Pier_Pole_1.png",
			Vector2(x * TILE + TILE / 2.0, (row + BRIDGE_HEIGHT) * TILE), 1.0)


func _add_bridge_planks(row: int, left: int, right: int) -> void:
	var plank_texture := AtlasTexture.new()
	plank_texture.atlas = load(
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Pier_4.png")
	plank_texture.region = Rect2(0, 0, 48, 96)
	for y in range(row, row + BRIDGE_HEIGHT):
		for x in range(left, right + 1, 2):
			var plank := Sprite2D.new()
			plank.name = "BridgePlank"
			plank.texture = plank_texture
			plank.rotation = PI * 0.5
			plank.position = Vector2((x + 1) * TILE, y * TILE + TILE / 2.0)
			_bridge_deck.add_child(plank)


func _build_waterfall() -> void:
	var center := _river_center[40] * TILE
	var base_y := 40 * TILE
	var waterfall := Sprite2D.new()
	waterfall.name = "Waterfall"
	waterfall.texture = load("res://sprites/custom/waterfall_gorge_288x432.png")
	waterfall.position = Vector2(center, base_y)
	waterfall.offset = Vector2(0, -216)
	waterfall.scale = Vector2.ONE
	waterfall.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var material := ShaderMaterial.new()
	material.shader = WATERFALL_SHADER
	material.set_shader_parameter("speed", 0.32)
	material.set_shader_parameter("opacity", 0.82)
	material.set_shader_parameter("tint_strength", 0.08)
	waterfall.material = material
	waterfall.modulate = Color(0.86, 0.92, 1.0, 0.92)
	_world.add_child(waterfall)
	for offset: float in [-170.0, 170.0]:
		_decor.add_prop(_world, DECOR.ROCKS[0],
			Vector2(center + offset, 31 * TILE), 2.0, Vector2(80, 30))
	_decor.add_prop(_world, DECOR.ROCKS[1],
		Vector2(center - 210.0, 32 * TILE), 2.0, Vector2(70, 26))
	_decor.add_prop(_world, DECOR.ROCKS[1],
		Vector2(center + 210.0, 32 * TILE), 2.0, Vector2(70, 26))
	var lip := Line2D.new()
	lip.name = "WaterfallLip"
	lip.width = 6.0
	lip.default_color = Color(0.88, 0.97, 1.0, 0.55)
	lip.add_point(Vector2(center - 158.0, 31 * TILE + 4.0))
	lip.add_point(Vector2(center + 158.0, 31 * TILE + 4.0))
	_world.add_child(lip)
	_decor.add_mist(_world, Vector2(center, base_y + 10.0), 1.0)
	_decor.add_mist(_world, Vector2(center - 120.0, base_y - 20.0), 0.6)
	_decor.add_mist(_world, Vector2(center + 120.0, base_y - 10.0), 0.6)
	for offset: float in [-220.0, -170.0, 170.0, 220.0]:
		_decor.add_prop(_world, DECOR.ROCKS[0],
			Vector2(center + offset, base_y + 28.0), 2.0, Vector2(90, 42))
	# The hidden alcove beside the pool.
	_decor.add_lantern(_world, _tile_base(Vector2i(25, 42)), 1.0)
	_decor.add_prop(_world, DECOR.BUSHES[4], _tile_base(Vector2i(26, 43)), 1.0)
	_decor.add_prop(_world, DECOR.GRASS_TUFTS[3], _tile_base(Vector2i(24, 43)), 1.0,
		Vector2.ZERO, true)
	# A smaller cascade at the mountain source, visible from the pass.
	var source := Sprite2D.new()
	source.name = "MountainSource"
	source.texture = load("res://sprites/custom/waterfall_144x432.png")
	source.position = Vector2(_river_center[12] * TILE, 12 * TILE)
	source.offset = Vector2(0, -216)
	source.scale = Vector2.ONE
	source.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var source_material := ShaderMaterial.new()
	source_material.shader = WATERFALL_SHADER
	source_material.set_shader_parameter("speed", 0.24)
	source.material = source_material
	_world.add_child(source)
	_decor.add_mist(_world, Vector2(_river_center[12] * TILE, 12 * TILE + 10.0), 0.6)


func _build_cave() -> void:
	# Dark floor under the west-cliff tunnel.
	var shade := Polygon2D.new()
	shade.name = "CaveShade"
	shade.color = Color(0.03, 0.04, 0.06, 0.55)
	shade.polygon = PackedVector2Array([
		Vector2(16.5 * TILE, 36.0 * TILE),
		Vector2(21.5 * TILE, 36.0 * TILE),
		Vector2(21.5 * TILE, 51.0 * TILE),
		Vector2(16.5 * TILE, 51.0 * TILE),
	])
	shade.z_index = 0
	_terrain.add_child(shade)
	for y in range(37, 50):
		for side: int in [16, 20]:
			var tile := Vector2i(side, y)
			_decor.add_prop(_world, DECOR.ROCKS[(y + side) % DECOR.ROCKS.size()],
				_tile_base(tile), 2.0, Vector2(60, 28))
			_block_tile(tile, 1.2)
	for tile: Vector2i in [Vector2i(17, 48), Vector2i(17, 44), Vector2i(17, 40),
			Vector2i(19, 38)]:
		_decor.add_lantern(_world, _tile_base(tile), 1.0)
	_decor.add_prop(_world, DECOR.ROCKS[0], _tile_base(Vector2i(18, 35)),
		2.0, Vector2(80, 30))
	_decor.add_prop(_world, DECOR.ROCKS[1], _tile_base(Vector2i(21, 35)),
		1.0, Vector2(60, 26))
	_decor.add_prop(_world, DECOR.BUSHES[2], _tile_base(Vector2i(19, 46)), 1.0)


## Tiles of the cliff ring around the ridge lane (columns 41-43, rows 30-48).
## The two climb points are the only way in or out.
func ridge_wall_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for y in range(RIDGE_TOP - 1, RIDGE_BOTTOM + 2):
		tiles.append(Vector2i(RIDGE_LEFT - 1, y))
		tiles.append(Vector2i(RIDGE_RIGHT + 1, y))
	for x in range(RIDGE_LEFT, RIDGE_RIGHT + 1):
		tiles.append(Vector2i(x, RIDGE_TOP - 1))
		tiles.append(Vector2i(x, RIDGE_BOTTOM + 1))
	return tiles


func _build_ridge() -> void:
	# The rocks are scenery: their own colliders are 28 px tall on 48 px tiles
	# and stopped two rows short of the climbs, so the lane could be walked
	# into. A full-tile collider per wall tile is what seals it.
	for tile: Vector2i in ridge_wall_tiles():
		if _is_water(tile):
			continue
		_decor.add_prop(_world, DECOR.ROCKS[(tile.y * 3 + tile.x) % DECOR.ROCKS.size()],
			_tile_base(tile), 2.0)
		# `_tile_base` sits 4 px above the tile's edge; the wall must reach it.
		_decor.add_collision(_world, _tile_center(tile) + Vector2(0, TILE / 2.0),
			Vector2(TILE, TILE), "RidgeWall")
		_block_tile(tile, 1.1)
	_decor.add_lantern(_world, _tile_base(Vector2i(43, 46)), 1.0)
	_decor.add_lantern(_world, _tile_base(Vector2i(43, 32)), 1.0)
	_decor.add_prop(_world, DECOR.GRASS_TUFTS[1], _tile_base(Vector2i(41, 44)),
		1.0, Vector2.ZERO, true)
	var rope := Line2D.new()
	rope.name = "ClimbRope"
	rope.width = 4.0
	rope.default_color = Color(0.55, 0.40, 0.22)
	rope.add_point(Vector2(39.0 * TILE + 24.0, 51.0 * TILE + 24.0))
	rope.add_point(Vector2(42.0 * TILE + 24.0, 48.0 * TILE + 24.0))
	_bridge_deck.add_child(rope)


func _build_mountain_crest() -> void:
	# Backdrop ridge. It is mostly seen from the pass and the refuge.
	for x in range(0, COLS, 2):
		var tile := Vector2i(x, 8)
		if _is_water(tile) or (x >= 44 and x <= 60):
			continue
		_decor.add_prop(_world, DECOR.ROCKS[0],
			Vector2(x * TILE + 24.0, 9 * TILE), 3.0)
		if x % 4 == 0:
			_decor.add_tree(_world, Vector2(x * TILE + 12.0, 10 * TILE),
				DECOR.MOUNTAIN_TREES[_rng.randi_range(0, DECOR.MOUNTAIN_TREES.size() - 1)],
				1.0, false)
	for x in range(2, COLS, 3):
		_decor.add_tree(_world, Vector2(x * TILE + 20.0, 12 * TILE),
			DECOR.MOUNTAIN_TREES[_rng.randi_range(0, DECOR.MOUNTAIN_TREES.size() - 1)],
			1.0, false)
	# Massif behind the cabin: rocks sort behind it and rise above the roof.
	for x in range(44, 61, 4):
		_decor.add_prop(_world, DECOR.ROCKS[0],
			Vector2(x * TILE + 24.0, 9 * TILE), 3.0)
		_cliffs.set_cell(Vector2i(x, 9), MOUND_A_SOURCE, Vector2i.ZERO, 0)
	for x in range(63, COLS - 1, 3):
		_decor.add_prop(_world, DECOR.ROCKS[_rng.randi_range(0, 2)],
			Vector2(x * TILE + 24.0, 13 * TILE), 2.0,
			Vector2(70, 30))
		_decor.add_tree(_world, Vector2(x * TILE + 10.0, 14 * TILE),
			DECOR.MOUNTAIN_TREES[0], 1.0, false)
	# Outcrops framing the pass and the cabin.
	for tile: Vector2i in [Vector2i(22, 14), Vector2i(18, 18), Vector2i(24, 20),
			Vector2i(30, 12), Vector2i(62, 12), Vector2i(66, 16),
			Vector2i(44, 12), Vector2i(38, 13)]:
		if _is_water(tile):
			continue
		_decor.add_prop(_world, DECOR.ROCKS[_rng.randi_range(0, 2)],
			_tile_base(tile), 2.0, Vector2(64, 32))
		_cliffs.set_cell(tile + Vector2i(0, 1), MOUND_A_SOURCE if tile.x % 2 == 0 else MOUND_B_SOURCE,
			Vector2i.ZERO, 0)
		_block_tile(tile, 2)
	# Loose cliff accents on the pass edges.
	for tile: Vector2i in [Vector2i(34, 12), Vector2i(42, 10),
			Vector2i(30, 16), Vector2i(62, 18), Vector2i(24, 20)]:
		_decor.add_prop(_world, DECOR.ROCKS[_rng.randi_range(0, 2)],
			_tile_base(tile), 1.0, Vector2(60, 30))
		_block_tile(tile, 2)
	for tile: Vector2i in [Vector2i(30, 9), Vector2i(36, 9), Vector2i(40, 11),
			Vector2i(28, 14), Vector2i(60, 14)]:
		if not _is_water(tile):
			_cliffs.set_cell(tile, MOUND_A_SOURCE if tile.x % 2 == 0 else MOUND_B_SOURCE,
				Vector2i.ZERO, 0)


func _build_gorge_cliffs() -> void:
	var west := [Vector2i(20, 32), Vector2i(18, 36), Vector2i(16, 40),
		Vector2i(18, 43), Vector2i(22, 34)]
	var east := [Vector2i(46, 32), Vector2i(48, 36), Vector2i(46, 40),
		Vector2i(47, 43), Vector2i(44, 34)]
	for tile: Vector2i in west + east:
		if _is_water(tile):
			continue
		_decor.add_prop(_world, DECOR.ROCKS[_rng.randi_range(0, 2)],
			_tile_base(tile), 2.0, Vector2(62, 30))
		_block_tile(tile, 2)
	for tile: Vector2i in [Vector2i(24, 34), Vector2i(24, 37), Vector2i(25, 40),
			Vector2i(41, 35), Vector2i(40, 38), Vector2i(39, 41)]:
		if not _is_water(tile):
			_cliffs.set_cell(tile, MOUND_A_SOURCE if tile.y % 2 == 0 else MOUND_B_SOURCE,
				Vector2i.ZERO, 0)


func _build_beach() -> void:
	for tile: Vector2i in [Vector2i(7, 100), Vector2i(16, 97), Vector2i(60, 99),
			Vector2i(64, 95), Vector2i(23, 94)]:
		_decor.add_prop(_world,
			"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Palm_Tree.png",
			_tile_base(tile), 1.0, Vector2(26, 18))
		_block_tile(tile, 3)
	# Wavy tide line. One line keeps the beach readable and cheap to draw.
	var foam := Line2D.new()
	foam.name = "TideFoam"
	foam.width = 5.0
	foam.default_color = Color(0.92, 0.98, 1.0, 0.55)
	for x in range(0, COLS * TILE + 1, TILE):
		foam.add_point(Vector2(x, SEA_ROW * TILE + sin(float(x) * 0.012) * 10.0))
	_world.add_child(foam)
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Broken_Arch_Sea_Rock_1_Vers_1.png",
		Vector2(8 * TILE, 105 * TILE), 1.0)
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Big_Sea_Rock_Vers_1.png",
		Vector2(68 * TILE, 104 * TILE), 1.0)
	# The maroon's wreck on the beach.
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/10_Vehicles/ME_Singles_Vehicles_48x48_Boat_1_Left_1.png",
		_tile_base(Vector2i(8, 103)), 1.0, Vector2(90, 40))
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Pier_Pole_1.png",
		_tile_base(Vector2i(9, 102)), 1.0)
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Pier_Barrel_1.png",
		_tile_base(Vector2i(7, 102)), 1.0, Vector2(30, 20))
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Fish_Crate_1.png",
		_tile_base(Vector2i(10, 103)), 1.0, Vector2(36, 20))
	var broken_hull := _decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Pier_4.png",
		_tile_base(Vector2i(11, 104)), 1.0)
	broken_hull.rotation = 0.4


func _build_estuary_dock() -> void:
	_reserve(Vector2i(60, 101), 5)
	# One complete platform at the water edge: the art already includes the posts.
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Pier_Bridge_1.png",
		_tile_base(Vector2i(60, 104)), 1.0)
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Pier_Bridge_1.png",
		_tile_base(Vector2i(61, 104)), 1.0)
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Pier_Barrel_1.png",
		_tile_base(Vector2i(59, 101)), 1.0, Vector2(30, 20))
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Fish_Crate_1.png",
		_tile_base(Vector2i(62, 101)), 1.0, Vector2(36, 20))
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Fish_Bucket_1.png",
		_tile_base(Vector2i(59, 100)), 1.0)
	_decor.add_sheet(_world,
		"res://sprites/exteriors_48x48/animated/sheets/Fishing_Boat_right_48x48.png",
		_tile_base(Vector2i(56, 107)), Vector2i(240, 96), 0, 8, 8.0, 1.0, false)
	_decor.add_sheet(_world,
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Water_Buoy_1_48x48.png",
		_tile_base(Vector2i(22, 108)), Vector2i(96, 96), 0, 8, 8.0, 1.0, true)
	_decor.add_sheet(_world,
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Water_Buoy_2_48x48.png",
		_tile_base(Vector2i(54, 109)), Vector2i(96, 96), 0, 8, 8.0, 1.0, true)
	_decor.add_sheet(_world,
		"res://sprites/custom/fishes_2.png",
		_tile_center(Vector2i(int(_river_center[96]), 96)), Vector2i(48, 48), 0, 14, 8.0,
		1.0, true, Color.WHITE, false)
	_decor.add_sheet(_world,
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Seagull_Idle_Left_48x48.png",
		_tile_base(Vector2i(9, 100)), Vector2i(96, 48), 0, 6, 6.0, 1.0, true)
	_decor.add_sheet(_world,
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Seagull_Idle_Down_48x48.png",
		_tile_base(Vector2i(20, 101)), Vector2i(48, 48), 0, 6, 5.0, 1.0, true)
	_decor.add_sheet(_world,
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Seagull_Idle_Right_48x48.png",
		_tile_base(Vector2i(58, 100)), Vector2i(96, 48), 0, 6, 6.5, 1.0, true)


func _build_camp() -> void:
	var center := FOREST_CAMP_TILE
	_decor.add_prop(_world, DECOR.TENTS[0], _tile_base(center + Vector2i(-3, -1)),
		1.0, Vector2(70, 34))
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Sleeping_Bag_1.png",
		_tile_base(center + Vector2i(0, -2)), 1.0)
	_decor.add_campfire(_world, _tile_base(center + Vector2i(1, 0)), 1.0)
	_decor.add_smoke(_world, _tile_base(center + Vector2i(1, 0)))
	_decor.add_lantern(_world, _tile_base(center + Vector2i(-2, 1)), 1.0)
	for offset: Vector2i in [Vector2i(-1, 2), Vector2i(2, 2), Vector2i(-3, 2)]:
		_decor.add_prop(_world, DECOR.WOOD[_rng.randi_range(0, 2)],
			_tile_base(center + offset), 1.0)
	_decor.add_prop(_world, DECOR.TENTS[1], _tile_base(center + Vector2i(4, -2)),
		1.0, Vector2(60, 30))
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Backpack_1.png",
		_tile_base(center + Vector2i(-2, -1)), 1.0)
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Cut_Wood_Bench_1.png",
		_tile_base(center + Vector2i(3, 2)), 1.0, Vector2(44, 18))
	_add_fence_line(center + Vector2i(-6, 2), 4, true)
	_add_fence_line(center + Vector2i(7, 2), 4, true)
	_decor.add_prop(_world, DECOR.BIG_FLOWERS[1],
		_tile_base(center + Vector2i(-5, -2)), 1.0)
	_decor.add_prop(_world, DECOR.BIG_FLOWERS[0],
		_tile_base(center + Vector2i(5, -1)), 1.0)


func _build_refuge() -> void:
	_decor.add_prop(_world,
		"res://sprites/farm_48x48/singles/Props_and_Buildings/Farmer_House_1_48x48.png",
		Vector2(CABIN_TILE.x * TILE + TILE / 2.0, (CABIN_TILE.y + 1) * TILE),
		1.0, Vector2(250, 90))
	_decor.add_campfire(_world, _tile_base(REFUGE_TILE + Vector2i(-3, 1)), 1.0)
	_decor.add_smoke(_world, _tile_base(REFUGE_TILE + Vector2i(-3, 1)))
	_decor.add_lantern(_world, _tile_base(REFUGE_TILE + Vector2i(-1, 2)), 1.0)
	_decor.add_lantern(_world, _tile_base(REFUGE_TILE + Vector2i(3, 2)), 1.0)
	_add_fence_line(REFUGE_TILE + Vector2i(-7, 4), 5, true)
	_add_fence_line(REFUGE_TILE + Vector2i(4, 4), 4, true)
	_decor.add_prop(_world, DECOR.BIG_FLOWERS[0],
		_tile_base(REFUGE_TILE + Vector2i(-5, 0)), 1.0)
	_decor.add_prop(_world, DECOR.BIG_FLOWERS[2],
		_tile_base(REFUGE_TILE + Vector2i(5, 0)), 1.0)
	_decor.add_prop(_world, DECOR.WOOD[2], _tile_base(REFUGE_TILE + Vector2i(4, 1)),
		1.0, Vector2(40, 20))
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Backpack_2.png",
		_tile_base(REFUGE_TILE + Vector2i(-2, 1)), 1.0)
	_decor.add_prop(_world,
		"res://sprites/farm_48x48/singles/Props_and_Buildings/Well_Usable_48x48.png",
		_tile_base(Vector2i(46, 23)), 1.0, Vector2(46, 22))
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Benched_Table_1.png",
		_tile_base(Vector2i(57, 22)), 1.0, Vector2(62, 20))
	_decor.add_prop(_world,
		"res://sprites/farm_48x48/singles/Props_and_Buildings/Crate_Brown_Empty_48x48.png",
		_tile_base(Vector2i(56, 24)), 1.0)
	_decor.add_prop(_world,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Pier_Barrel_2.png",
		_tile_base(Vector2i(45, 21)), 1.0, Vector2(30, 18))


func _add_fence_line(start: Vector2i, count: int, horizontal: bool) -> void:
	if not horizontal:
		return
	for index in count:
		_decor.add_prop(_world, DECOR.ROPE_RAIL,
			_tile_base(start + Vector2i(index, 0)), 1.0)
	_decor.add_prop(_world, DECOR.FENCES[0],
		_tile_base(start + Vector2i(count, 0)), 1.0)


func _scatter_trees() -> void:
	var placed := 0
	var attempts := 0
	while placed < 150 and attempts < 1600:
		attempts += 1
		var tile := Vector2i(_rng.randi_range(4, COLS - 5), _rng.randi_range(8, BEACH_ROW - 1))
		if _is_sand(tile) or not _is_free(tile, 1.6):
			continue
		var frames: String
		if tile.y < 46:
			frames = DECOR.MOUNTAIN_TREES[_rng.randi_range(0, DECOR.MOUNTAIN_TREES.size() - 1)]
		else:
			frames = DECOR.FOREST_TREES[_rng.randi_range(0, DECOR.FOREST_TREES.size() - 1)]
		var scale := 1.0
		_decor.add_tree(_world, _tile_base(tile), frames, scale)
		_block_tile(tile, 1.5)
		placed += 1


func _scatter_rocks() -> void:
	for index in 55:
		var tile := Vector2i(_rng.randi_range(4, COLS - 5), _rng.randi_range(10, 99))
		if not _is_free(tile, 1.4):
			continue
		var path: String = DECOR.ROCKS[_rng.randi_range(0, DECOR.ROCKS.size() - 1)]
		var scale := 1.0
		_decor.add_prop(_world, path, _tile_base(tile), scale, Vector2(52, 26))
		_block_tile(tile, 1.3)
	for index in 12:
		var tile := Vector2i(_rng.randi_range(2, COLS - 3), _rng.randi_range(95, 103))
		if _is_water(tile) or not _is_free(tile, 0.8):
			continue
		_decor.add_prop(_world, DECOR.SEA_ROCKS[index % DECOR.SEA_ROCKS.size()],
			_tile_base(tile), 1.0,
			Vector2(50, 22) if index % 2 == 0 else Vector2.ZERO)


func _scatter_underbrush() -> void:
	for index in 110:
		var tile := Vector2i(_rng.randi_range(3, COLS - 4), _rng.randi_range(8, 100))
		if _is_sand(tile) or not _is_free(tile, 0.7):
			continue
		if _rng.randf() < 0.55:
			_decor.add_prop(_world, DECOR.BUSHES[_rng.randi_range(0, DECOR.BUSHES.size() - 1)],
				_tile_base(tile), 1.0)
		else:
			_decor.add_prop(_world, DECOR.GRASS_TUFTS[_rng.randi_range(0, DECOR.GRASS_TUFTS.size() - 1)],
				_tile_base(tile), 1.0, Vector2.ZERO, true)
	for index in 34:
		var tile := Vector2i(_rng.randi_range(3, COLS - 4), _rng.randi_range(18, 96))
		if _is_sand(tile) or not _is_free(tile, 0.6):
			continue
		if _rng.randf() < 0.5:
			_decor.add_prop(_world, DECOR.BUSHES[_rng.randi_range(0, DECOR.BUSHES.size() - 1)],
				_tile_base(tile), 1.0)
		else:
			_decor.add_prop(_world, DECOR.GRASS_TUFTS[_rng.randi_range(0, DECOR.GRASS_TUFTS.size() - 1)],
				_tile_base(tile), 1.0, Vector2.ZERO, true)
	for index in 26:
		var tile := Vector2i(_rng.randi_range(4, COLS - 5), _rng.randi_range(12, 82))
		if _is_sand(tile) or not _is_free(tile, 0.6):
			continue
		_decor.add_prop(_world, DECOR.MUSHROOMS[_rng.randi_range(0, DECOR.MUSHROOMS.size() - 1)],
			_tile_base(tile), 1.0)
	for index in 6:
		var tile := Vector2i(_rng.randi_range(6, COLS - 7), _rng.randi_range(16, 88))
		if _is_sand(tile) or not _is_free(tile, 1.0):
			continue
		_decor.add_leaves(_world, _tile_center(tile),
			DECOR.LEAF_ANIMATIONS[index % DECOR.LEAF_ANIMATIONS.size()],
			1.0)
	# Soften the trail edges with tufts and flowers on the grass side.
	var trail_cells: Array = _trail.keys()
	for index in 70:
		if trail_cells.is_empty():
			break
		var tile: Vector2i = trail_cells[_rng.randi_range(0, trail_cells.size() - 1)]
		tile += Vector2i(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1))
		if _is_water(tile) or _trail.has(tile):
			continue
		if _is_sand(tile):
			continue
		if _rng.randf() < 0.6:
			_decor.add_prop(_world, DECOR.GRASS_TUFTS[_rng.randi_range(0, DECOR.GRASS_TUFTS.size() - 1)],
				_tile_base(tile), 1.0, Vector2.ZERO, true)
		else:
			_decor.add_prop(_world, DECOR.GRASS_TUFTS[_rng.randi_range(0, DECOR.GRASS_TUFTS.size() - 1)],
				_tile_base(tile), 1.0, Vector2.ZERO, true)


func _scatter_beach_details() -> void:
	var sprouts := [
		"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Big_Sprout_Vers_1.png",
		"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Big_Sprout_Vers_2.png",
		"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Small_Sprout_Vers_1_Sand_Mountain.png",
	]
	for index in 22:
		var tile := Vector2i(_rng.randi_range(4, COLS - 5), _rng.randi_range(73, 103))
		if not _is_sand(tile) or _is_water(tile) or not _is_free(tile, 0.4):
			continue
		_decor.add_prop(_world, sprouts[index % sprouts.size()], _tile_base(tile),
			1.0)
	for index in 22:
		var tile := Vector2i(_rng.randi_range(4, COLS - 5), _rng.randi_range(95, 103))
		if _is_water(tile) or not _is_free(tile, 0.4):
			continue
		_decor.add_prop(_world, DECOR.SHELLS[_rng.randi_range(0, DECOR.SHELLS.size() - 1)],
			_tile_base(tile), 1.0)
	for index in 9:
		var tile := Vector2i(_rng.randi_range(4, COLS - 5), _rng.randi_range(94, 103))
		if _is_water(tile) or not _is_free(tile, 0.4):
			continue
		_decor.add_prop(_world, DECOR.WOOD[3 + index % 2], _tile_base(tile),
			1.0)


func _scatter_wildlife() -> void:
	_decor.add_animal(_world,
		"res://sprites/farm_48x48/animals/Goats_48x48/Goat_Brown_48x48.png",
		_tile_center(Vector2i(44, 28)), Rect2(40 * TILE, 24 * TILE, 10 * TILE, 6 * TILE), 24.0)
	_decor.add_animal(_world,
		"res://sprites/farm_48x48/animals/Goats_48x48/Goat_Baby_White_48x48.png",
		_tile_center(Vector2i(48, 31)), Rect2(42 * TILE, 26 * TILE, 12 * TILE, 8 * TILE), 30.0,
		Vector2i(96, 96))
	_decor.add_animal(_world,
		"res://sprites/farm_48x48/animals/Rabbits_48x48/Rabbit_Brown_48x48.png",
		_tile_center(Vector2i(24, 60)), Rect2(20 * TILE, 56 * TILE, 8 * TILE, 7 * TILE), 28.0,
		Vector2i(96, 96))
	_decor.add_animal(_world,
		"res://sprites/farm_48x48/animals/Rabbits_48x48/Rabbit_White_48x48.png",
		_tile_center(Vector2i(50, 76)), Rect2(46 * TILE, 72 * TILE, 8 * TILE, 8 * TILE), 30.0,
		Vector2i(96, 96))
	_decor.add_animal(_world,
		"res://sprites/farm_48x48/animals/Ducks_48x48/Duck_White_48x48.png",
		_tile_center(Vector2i(44, 96)), Rect2(40 * TILE, 92 * TILE, 8 * TILE, 6 * TILE), 22.0,
		Vector2i(96, 96))
	_decor.add_sheet(_world,
		"res://sprites/custom/fishes_1.png",
		_tile_center(Vector2i(int(_river_center[44]), 44)), Vector2i(48, 48), 0, 12, 7.0,
		1.0, true, Color.WHITE, false)
	_decor.add_sheet(_world,
		"res://sprites/custom/fishes_3.png",
		_tile_center(Vector2i(int(_river_center[62]), 62)), Vector2i(48, 48), 0, 14, 7.0,
		1.0, true, Color.WHITE, false)
	_add_crow(Vector2(20, 18), 620.0, false)
	_add_crow(Vector2(48, 37), 520.0, true)


func _add_crow(tile: Vector2, travel: float, flip: bool) -> void:
	var crow := _decor.add_sheet(_world,
		"res://sprites/exteriors_48x48/animated/sheets/Crow_Flap_Right_48x48.png",
		_tile_center(Vector2i(int(tile.x), int(tile.y))), Vector2i(96, 96), 0, 6, 9.0,
		1.0, false, Color.WHITE, false)
	crow.flip_h = flip
	var start_x := crow.position.x
	var target_x := start_x - travel if flip else start_x + travel
	var tween := crow.create_tween().set_loops()
	tween.tween_property(crow, "position:x", target_x, 18.0)
	tween.tween_callback(func() -> void: crow.position.x = start_x)


func _add_zone_signs() -> void:
	_add_sign(Vector2i(12, 98), "La mer")
	_add_sign(Vector2i(49, 86), "L'estuaire")
	_add_sign(Vector2i(38, 66), "La forêt")
	_add_sign(Vector2i(20, 46), "Les gorges")
	_add_sign(Vector2i(16, 52), "La grotte")
	_add_sign(Vector2i(41, 53), "La crête")
	_add_sign(Vector2i(25, 41), "La cascade")
	_add_sign(Vector2i(40, 22), "Le col")
	_add_sign(Vector2i(49, 22), "Refuge")


func _add_sign(tile: Vector2i, text: String,
		texture_path: String = "res://sprites/farm_48x48/singles/Props_and_Buildings/Sign_1_48x48.png") -> void:
	_decor.add_prop(_world, texture_path, _tile_base(tile), 1.0)
	var label := Label.new()
	label.name = "ZoneLabel"
	label.text = text
	label.position = _tile_center(tile) + Vector2(-60.0, -62.0)
	label.add_theme_color_override("font_color", Color(0.98, 0.90, 0.70))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 18)
	_world.add_child(label)


func _tiles_to_points(tiles: Array[Vector2i]) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for tile: Vector2i in tiles:
		points.append(_tile_center(tile))
	return points


func _climb_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec: Dictionary in CLIMB_POINTS:
		var tile: Vector2i = spec["tile"]
		var destination: Vector2i = spec["destination"]
		result.append({
			"position": _tile_center(tile),
			"destination": _tile_center(destination),
			"label": String(spec["label"]),
		})
	return result


func _stealth_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec: Dictionary in STEALTH_ZONES:
		var tile: Vector2i = spec["tile"]
		var tiles: Vector2i = spec["tiles"]
		result.append({
			"position": _tile_center(tile),
			"size": Vector2(tiles.x * TILE, tiles.y * TILE),
			"name": String(spec["name"]),
			"conceal": bool(spec["conceal"]),
			"mute": bool(spec["mute"]),
		})
	return result


func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE + TILE / 2.0, tile.y * TILE + TILE / 2.0)


func _tile_base(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE + TILE / 2.0, (tile.y + 1) * TILE - 4.0)
