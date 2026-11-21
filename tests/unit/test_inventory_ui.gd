extends GdUnitTestSuite

const HUD_SCENE := "res://scenes/farm/farm_hud.tscn"


func before_test() -> void:
	GameState.reset()


func _spawn_hud() -> CanvasLayer:
	var hud: CanvasLayer = auto_free(load(HUD_SCENE).instantiate())
	add_child(hud)
	return hud


func test_inventory_builds_one_slot_per_crop() -> void:
	var hud := _spawn_hud()
	var seed_grid: GridContainer = hud.get_node("%SeedGrid")
	var produce_grid: GridContainer = hud.get_node("%ProduceGrid")

	assert_int(seed_grid.get_child_count()).is_equal(GameState.CROP_ORDER.size())
	assert_int(produce_grid.get_child_count()).is_equal(GameState.CROP_ORDER.size())


func test_slots_show_the_stack_count() -> void:
	var hud := _spawn_hud()
	GameState.seeds["corn"] = 3
	GameState.inventory_changed.emit()

	var slot: ItemSlot = hud.get_node("%SeedGrid").get_child(0)
	var count: Label = slot.get_node("Count")

	assert_bool(slot.visible).is_true()
	assert_str(count.text).is_equal("×3")


func test_empty_slots_are_hidden() -> void:
	var hud := _spawn_hud()
	for crop: String in GameState.CROP_ORDER:
		GameState.seeds[crop] = 0
		GameState.produce[crop] = 0
	GameState.inventory_changed.emit()

	var seed_grid: GridContainer = hud.get_node("%SeedGrid")
	var visible := 0
	for child: Node in seed_grid.get_children():
		if (child as Control).visible:
			visible += 1

	assert_int(visible).is_equal(0)
	assert_bool(seed_grid.visible).is_false()
	assert_bool((hud.get_node("%SeedEmpty") as Label).visible).is_true()


func test_pressing_a_seed_slot_selects_the_crop() -> void:
	var hud := _spawn_hud()
	var index := GameState.CROP_ORDER.find("tomato")
	var slot: ItemSlot = hud.get_node("%SeedGrid").get_child(index)

	slot.pressed.emit()

	assert_str(GameState.selected_seed).is_equal("tomato")


func test_selected_seed_slot_stays_pressed() -> void:
	var hud := _spawn_hud()

	GameState.select_seed("pumpkin")

	var index := GameState.CROP_ORDER.find("pumpkin")
	var slot: ItemSlot = hud.get_node("%SeedGrid").get_child(index)
	assert_bool(slot.button_pressed).is_true()
