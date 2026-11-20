extends GdUnitTestSuite

const UI_SCENES := [
	"res://game/ui/menus/main_menu.tscn",
	"res://game/ui/menus/pause_menu.tscn",
	"res://game/ui/menus/family_portrait.tscn",
	"res://game/ui/menus/screens/settings_screen.tscn",
	"res://game/ui/menus/screens/controls_screen.tscn",
	"res://game/ui/menus/screens/credits_screen.tscn",
	"res://game/ui/menus/screens/confirm_screen.tscn",
	"res://game/ui/hud/hud.tscn",
	"res://game/farm/farm_hud.tscn",
	"res://game/ui/theme/salazie_theme.tres",
]

const ICON_DIR := "res://game/ui/theme/icons"


func test_ui_scenes_only_reference_the_ui_pack() -> void:
	var files := UI_SCENES.duplicate()
	for file_name: String in DirAccess.get_files_at(ICON_DIR):
		if file_name.ends_with(".tres"):
			files.append(ICON_DIR.path_join(file_name))

	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		assert_bool(text.is_empty()).override_failure_message("Could not read %s" % path).is_false()
		assert_bool(text.contains("res://assets/farm_48x48")).override_failure_message(
			"%s references a farm texture; menus and HUD must stay on the UI pack" % path).is_false()
		for line: String in text.split("\n"):
			if not line.contains('type="Texture2D"') or not line.contains('path="res://assets/'):
				continue
			var texture_path := line.get_slice('path="', 1).get_slice('"', 0)
			assert_bool(texture_path.begins_with("res://assets/ui_48x48/")).override_failure_message(
				"%s references %s outside assets/ui_48x48" % [path, texture_path]).is_true()


func test_family_portrait_stacks_four_layers() -> void:
	var portrait: Control = load("res://game/ui/menus/family_portrait.tscn").instantiate()
	var skin_texture: Texture2D = load("res://assets/ui_48x48/portrait_generator/skins/PG_Skin_48x48_1.png")
	portrait.set("skin", skin_texture)
	portrait.set("eyes", skin_texture)
	portrait.set("hair", skin_texture)
	add_child(portrait)
	auto_free(portrait)
	await get_tree().process_frame

	for layer_name: String in ["Skin", "Eyes", "Hair"]:
		var rect: TextureRect = portrait.get_node(layer_name)
		assert_bool(rect.visible).override_failure_message("%s layer is hidden" % layer_name).is_true()
		assert_object(rect.texture).override_failure_message("%s layer has no texture" % layer_name).is_not_null()
		var atlas := rect.texture as AtlasTexture
		assert_object(atlas).override_failure_message("%s layer is not an AtlasTexture" % layer_name).is_not_null()
		if atlas != null:
			assert_vector(atlas.region.position).is_equal(Vector2(16, 12))
			assert_vector(atlas.region.size).is_equal(Vector2(56, 56))

	var accessory: TextureRect = portrait.get_node("Accessory")
	assert_bool(accessory.visible).override_failure_message("Empty accessory layer should be hidden").is_false()


func test_survival_hud_uses_ui_pack_icons_and_bars() -> void:
	var survival: Node = preload("res://game/systems/survival/survival_component.gd").new()
	survival.active = true
	add_child(survival)
	auto_free(survival)
	await get_tree().process_frame

	var hud: CanvasLayer = load("res://game/ui/hud/hud.tscn").instantiate()
	add_child(hud)
	auto_free(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var food_bar: ProgressBar = hud.get_node("%FoodBar")
	var water_bar: ProgressBar = hud.get_node("%WaterBar")
	assert_bool(food_bar.visible).is_true()
	assert_bool(water_bar.visible).is_true()
	assert_bool(food_bar.get_theme_stylebox("fill") is StyleBoxTexture).is_true()
	assert_bool(water_bar.get_theme_stylebox("fill") is StyleBoxTexture).is_true()

	var food_icon: TextureRect = hud.get_node("Root/Margin/Bars/FoodRow/Icon")
	var water_icon: TextureRect = hud.get_node("Root/Margin/Bars/WaterRow/Icon")
	assert_object(food_icon.texture).is_not_null()
	assert_object(water_icon.texture).is_not_null()


func test_main_menu_has_the_family_trio() -> void:
	var menu: Control = load("res://game/ui/menus/main_menu.tscn").instantiate()
	add_child(menu)
	auto_free(menu)
	await get_tree().process_frame

	for slot_name: String in ["MarronSlot", "CultivateurSlot", "HeritierSlot"]:
		var slot: Node = menu.get_node(
			"MenuStack/HomeScreen/Center/Layout/FamilyPanel/Portraits/%s" % slot_name)
		var portrait: Node = slot.get_node("Frame/Portrait")
		assert_object(portrait).override_failure_message("Missing portrait in %s" % slot_name).is_not_null()
		if portrait != null:
			assert_object(portrait.get("skin")).override_failure_message(
				"Missing skin in %s" % slot_name).is_not_null()
			assert_object(portrait.get("hair")).override_failure_message(
				"Missing hair in %s" % slot_name).is_not_null()
