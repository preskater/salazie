extends RefCounted
## Asset catalogue and node factory for the Map 1 world.
##
## All sprites come from the vendored LimeZu packs. Props are bottom-anchored so
## the y-sorted World draws the player correctly behind and in front of them.

const TILE := 48

const ANIMATED_SHEET := preload("res://scenes/world/animated_sheet.tscn")
const TREE_SHAKE := preload("res://scenes/world/tree_shake.tscn")
const ANIMAL_SCENE := preload("res://scenes/farm/animals/animal.tscn")
const LEAVES_SCENE := preload("res://scenes/world/ambient_leaves.tscn")
const SWAY_SCRIPT := preload("res://scripts/world/crop_sway.gd")

const FOREST_TREES := [
	"res://game_resources/animations/Tree_Oak_Green_Medium_Shake.tres",
	"res://game_resources/animations/Tree_Oak_Green_Big_Shake.tres",
	"res://game_resources/animations/Tree_Oak_Brown_Medium_Shake.tres",
	"res://game_resources/animations/Tree_Oak_Brown_Big_Shake.tres",
	"res://game_resources/animations/Tree_Birch_Green_Medium_Shake.tres",
	"res://game_resources/animations/Tree_Birch_Yellow_Medium_Shake.tres",
	"res://game_resources/animations/Tree_Birch_Brown_Medium_Shake.tres",
	"res://game_resources/animations/Tree_Oak_Green_Small_Shake.tres",
	"res://game_resources/animations/Tree_Birch_Green_Small_Shake.tres",
	"res://game_resources/animations/Tree_Birch_Yellow_Small_Shake.tres",
	"res://game_resources/animations/Fruit_Tree_Apple_Ripe_Shake.tres",
	"res://game_resources/animations/Fruit_Tree_Peach_Ripe_Shake.tres",
	"res://game_resources/animations/Fruit_Tree_Lemon_Ripe_Shake.tres",
	"res://game_resources/animations/Fruit_Tree_Orange_Ripe_Shake.tres",
]
const MOUNTAIN_TREES := [
	"res://game_resources/animations/Tree_Pine_Green_Big_Shake.tres",
	"res://game_resources/animations/Tree_Pine_Dark_Green_Big_Shake.tres",
	"res://game_resources/animations/Tree_Pine_Green_Medium_Shake.tres",
	"res://game_resources/animations/Tree_Pine_Dark_Green_Medium_Shake.tres",
	"res://game_resources/animations/Tree_Pine_Green_Small_Shake.tres",
	"res://game_resources/animations/Tree_Birch_Green_Medium_Shake.tres",
	"res://game_resources/animations/Tree_Birch_Brown_Medium_Shake.tres",
]
const LEAF_ANIMATIONS := [
	"res://game_resources/animations/Leaves_Green.tres",
	"res://game_resources/animations/Leaves_Brown.tres",
	"res://game_resources/animations/Leaves_Yellow.tres",
]

const ROCKS := [
	"res://sprites/farm_48x48/singles/Props_and_Buildings/Rock_Big_48x48.png",
	"res://sprites/farm_48x48/singles/Props_and_Buildings/Rock_Medium_48x48.png",
	"res://sprites/farm_48x48/singles/Props_and_Buildings/Rock_Small_48x48.png",
	"res://sprites/farm_48x48/singles/Props_and_Buildings/Rock_Big_Blue_Stone_48x48.png",
	"res://sprites/farm_48x48/singles/Props_and_Buildings/Rock_Medium_Gold_Stone_48x48.png",
	"res://sprites/farm_48x48/singles/Props_and_Buildings/Rock_Small_Silver_Stone_48x48.png",
]
const SEA_ROCKS := [
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Big_Sea_Rock_Vers_1.png",
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Medium_Sea_Rock_1_Vers_1.png",
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Medium_Sea_Rock_2_Vers_1.png",
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Small_Sea_Rock_1_Vers_1.png",
]
const SHELLS := [
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Brown_Shell_1_Vers_1.png",
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Grey_Shell_2_Vers_1.png",
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Blue_Big_Starfish.png",
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Green_Small_Starfish.png",
	"res://sprites/exteriors_48x48/singles/21_Beach/21_Beach_48x48_Pink_Shell_3.png",
]
const BUSHES := [
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_1.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_2.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_3.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_4.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Bush_5.png",
]
const GRASS_TUFTS := [
	"res://sprites/exteriors_48x48/singles/1_Terrains_and_Fences/ME_Singles_Terrains_and_Fences_48x48_Props_Grass_1.png",
	"res://sprites/exteriors_48x48/singles/1_Terrains_and_Fences/ME_Singles_Terrains_and_Fences_48x48_Props_Grass_2.png",
	"res://sprites/exteriors_48x48/singles/1_Terrains_and_Fences/ME_Singles_Terrains_and_Fences_48x48_Props_Grass_3.png",
	"res://sprites/exteriors_48x48/singles/1_Terrains_and_Fences/ME_Singles_Terrains_and_Fences_48x48_Props_Grass_4.png",
	"res://sprites/exteriors_48x48/singles/1_Terrains_and_Fences/ME_Singles_Terrains_and_Fences_48x48_Props_Grass_5.png",
	"res://sprites/exteriors_48x48/singles/1_Terrains_and_Fences/ME_Singles_Terrains_and_Fences_48x48_Props_Grass_6.png",
]
const BIG_FLOWERS := [
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Big_Pink_Flower.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Big_Red_Flower.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Big_White_Flower.png",
	"res://sprites/exteriors_48x48/singles/17_Garden/ME_Singles_Garden_48x48_Big_Sunflower.png",
]
const MUSHROOMS := [
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Mushrooms_1.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Mushrooms_2.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Mushrooms_3.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Mushrooms_4.png",
]
const WOOD := [
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Cut_Wood_1.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Cut_Wood_2.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Cut_Wood_3.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Floating_Wood_1.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Floating_Wood_2.png",
]
const TENTS := [
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Tent_1.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Tent_2.png",
	"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Tent_4.png",
]
const FENCES := [
	"res://sprites/farm_48x48/singles/Fences/Wooden_Fence_Type_1_Brown_1_48x48.png",
	"res://sprites/farm_48x48/singles/Fences/Wooden_Fence_Type_1_Brown_2_48x48.png",
	"res://sprites/farm_48x48/singles/Fences/Wooden_Fence_Type_1_Brown_3_48x48.png",
	"res://sprites/farm_48x48/singles/Fences/Wooden_Fence_Type_1_Brown_4_48x48.png",
]
const ROPE_RAIL := "res://sprites/farm_48x48/singles/Fences/Rod_Rope_Horizontal_1_48x48.png"


func add_prop(parent: Node2D, path: String, position: Vector2, scale := 1.0,
		collision := Vector2.ZERO, sway := false,
		modulate := Color.WHITE) -> Sprite2D:
	var texture: Texture2D = load(path)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = position
	sprite.scale = Vector2.ONE * scale
	sprite.modulate = modulate
	sprite.offset = Vector2(0, -texture.get_height() / 2.0)
	if sway:
		sprite.set_script(SWAY_SCRIPT)
	parent.add_child(sprite)
	if collision != Vector2.ZERO:
		add_collision(parent, position, collision)
	return sprite


func add_collision(parent: Node2D, position: Vector2, size: Vector2,
		name_hint := "PropCollision") -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = name_hint
	body.position = position
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	shape.position = Vector2(0, -size.y / 2.0)
	body.add_child(shape)
	parent.add_child(body)
	body.add_to_group(&"navigation_obstacles")
	return body


func add_tree(parent: Node2D, position: Vector2, frames_path: String,
		scale := 1.0, collision := true) -> AnimatedSprite2D:
	var frames: SpriteFrames = load(frames_path)
	if frames == null:
		return null
	var tree: AnimatedSprite2D = TREE_SHAKE.instantiate()
	tree.sprite_frames = frames
	var first: Texture2D = frames.get_frame_texture(&"shake", 0)
	tree.offset = Vector2(0, -first.get_height() / 2.0)
	tree.position = position
	tree.scale = Vector2.ONE * scale
	parent.add_child(tree)
	if collision:
		add_collision(parent, position, Vector2(26, 18), "TreeCollision")
	return tree


func add_sheet(parent: Node2D, path: String, position: Vector2,
		cell: Vector2i, row: int, frames: int, fps: float,
		scale := 1.0, allow_random_start := true,
		modulate := Color.WHITE, bottom_anchor := true) -> AnimatedSprite2D:
	var sprite: AnimatedSprite2D = ANIMATED_SHEET.instantiate()
	sprite.set("sheet", load(path))
	sprite.set("cell_size", cell)
	sprite.set("row", row)
	sprite.set("frame_count", frames)
	sprite.set("fps", fps)
	sprite.set("random_start", allow_random_start)
	sprite.set("bottom_anchor", bottom_anchor)
	sprite.position = position
	sprite.scale = Vector2.ONE * scale
	sprite.modulate = modulate
	parent.add_child(sprite)
	return sprite


func add_animal(parent: Node2D, path: String, position: Vector2,
		roam_rect: Rect2, speed := 26.0, cell := Vector2i(96, 144)) -> Node2D:
	var animal: Node2D = ANIMAL_SCENE.instantiate()
	animal.set("sheet", load(path))
	animal.set("position", position)
	animal.set("move_speed", speed)
	animal.set("roam_rect", roam_rect)
	animal.set("cell_size", cell)
	animal.set("walk_row", 2)
	animal.set("graze_row", 3)
	animal.set("graze_time", Vector2(2.5, 6.0))
	animal.set("walk_time", Vector2(1.5, 3.5))
	parent.add_child(animal)
	animal.add_to_group("wildlife")
	return animal


func add_leaves(parent: Node2D, position: Vector2, frames_path: String,
		scale := 1.0) -> AnimatedSprite2D:
	var leaves: AnimatedSprite2D = LEAVES_SCENE.instantiate()
	leaves.sprite_frames = load(frames_path)
	leaves.position = position
	leaves.scale = Vector2.ONE * scale
	parent.add_child(leaves)
	return leaves


func add_mist(parent: Node2D, position: Vector2, scale := 1.0) -> AnimatedSprite2D:
	# The fog sheet is 6 frames of 288 x 48, not 36 cells of 48 x 48.
	return add_sheet(parent,
		"res://sprites/exteriors_48x48/animated/sheets/Beach_Stage_Fog_Machine_Fog_Only_Loop_48x48.png",
		position, Vector2i(288, 48), 1, 6, 5.0, scale, true,
		Color(1.0, 1.0, 1.0, 0.35), false)


func add_campfire(parent: Node2D, position: Vector2, scale := 1.0) -> AnimatedSprite2D:
	return add_sheet(parent,
		"res://sprites/exteriors_48x48/animated/sheets/Campfire_48x48.png",
		position, Vector2i(48, 48), 1, 6, 9.0, scale, true)


func add_lantern(parent: Node2D, position: Vector2, scale := 1.0) -> Sprite2D:
	return add_prop(parent,
		"res://sprites/exteriors_48x48/singles/11_Camping/ME_Singles_Camping_48x48_Lantern_1.png",
		position, scale)


func add_smoke(parent: Node2D, position: Vector2) -> AnimatedSprite2D:
	return add_sheet(parent,
		"res://sprites/farm_48x48/animated/Stone_Oven_Smoke_Effect_48x48.png",
		position, Vector2i(144, 192), 0, 8, 6.0, 1.0, true,
		Color(0.85, 0.85, 0.82, 0.45))
