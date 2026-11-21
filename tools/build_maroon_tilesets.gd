extends SceneTree
## One-shot generator for Map 1 terrain tiles.
##
## The TileSet editor cannot be driven headlessly, so this script builds the
## atlas sources and saves `game_resources/tilesets/maroon_ground.tres`.
## Run after `--headless --import`:
##   godot --headless --path . --script res://tools/build_maroon_tilesets.gd

const TERRAINS := "res://sprites/exteriors_48x48/tilesets/1_Terrains_and_Fences_48x48.png"
const FARM_TERRAINS := "res://sprites/farm_48x48/tilesets/1_Terrains_48x48.png"
const BEACH := "res://sprites/exteriors_48x48/tilesets/21_Beach_48x48.png"
const SEA_WATER := "res://sprites/exteriors_48x48/animated/terrains/Sea_Water_Tileset_48x48.png"
const MOUND_1 := "res://sprites/exteriors_48x48/singles/1_Terrains_and_Fences/ME_Singles_Terrains_and_Fences_48x48_Mound_1_1.png"
const MOUND_2 := "res://sprites/exteriors_48x48/singles/1_Terrains_and_Fences/ME_Singles_Terrains_and_Fences_48x48_Mound_2_1.png"
const OUTPUT := "res://game_resources/tilesets/maroon_ground.tres"

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
	Vector2i(9, 1), Vector2i(1, 5),
]
const WATER_TILES: Array[Vector2i] = [Vector2i(27, 5)]

## 3x3 transition blocks (NW, N, NE / W, C, E / SW, S, SE).
const DIRT_GRASS_TILES: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	Vector2i(15, 9), Vector2i(17, 9),
]
const GRASS_WATER_TILES: Array[Vector2i] = [
	Vector2i(8, 6), Vector2i(9, 6), Vector2i(10, 6),
	Vector2i(8, 7), Vector2i(9, 7), Vector2i(10, 7),
	Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8),
]
const SAND_GRASS_TILES: Array[Vector2i] = [
	Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4),
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5),
	Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6),
]
const SEA_WATER_TILES: Array[Vector2i] = [Vector2i(1, 0)]


func _initialize() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(48, 48)

	var terrain_source := _atlas_source(TERRAINS)
	tile_set.add_source(terrain_source, 0)
	_create_tiles(terrain_source, GRASS_TILES)
	_create_tiles(terrain_source, DIRT_TILES)
	_create_tiles(terrain_source, WATER_TILES)
	_create_tiles(terrain_source, GRASS_WATER_TILES)

	var farm_source := _atlas_source(FARM_TERRAINS)
	tile_set.add_source(farm_source, 1)
	_create_tiles(farm_source, FARM_DIRT_TILES)
	_create_tiles(farm_source, DIRT_GRASS_TILES)
	_create_tiles(farm_source, SAND_GRASS_TILES)

	var beach_source := _atlas_source(BEACH)
	tile_set.add_source(beach_source, 2)
	_create_tiles(beach_source, SAND_TILES)

	tile_set.add_source(_single_source(MOUND_1), 3)
	tile_set.add_source(_single_source(MOUND_2), 4)
	var sea_source := _atlas_source(SEA_WATER)
	tile_set.add_source(sea_source, 5)
	_create_tiles(sea_source, SEA_WATER_TILES)

	var err := ResourceSaver.save(tile_set, OUTPUT)
	print("saved %s: %s" % [OUTPUT, error_string(err)])
	quit(0 if err == OK else 1)


func _atlas_source(path: String) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = load(path)
	source.texture_region_size = Vector2i(48, 48)
	return source


func _single_source(path: String) -> TileSetAtlasSource:
	var source := _atlas_source(path)
	source.create_tile(Vector2i.ZERO)
	return source


func _create_tiles(source: TileSetAtlasSource, coords: Array[Vector2i]) -> void:
	for coord: Vector2i in coords:
		if not source.has_tile(coord):
			source.create_tile(coord)
