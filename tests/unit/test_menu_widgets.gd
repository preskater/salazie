extends GdUnitTestSuite
## Reusable menu pieces: the screen stack, the confirmation and credits
## screens, the survival HUD and the family portrait.

const STACK_SCRIPT := preload("res://scripts/ui/menus/menu_stack.gd")
const CONFIRM_SCENE := "res://scenes/ui/menus/screens/confirm_screen.tscn"
const CREDITS_SCENE := "res://scenes/ui/menus/screens/credits_screen.tscn"
const HUD_SCENE := "res://scenes/ui/hud/hud.tscn"
const SURVIVAL_SCRIPT := preload("res://scripts/systems/survival/survival_component.gd")
const PORTRAIT_SCENE := "res://scenes/ui/menus/family_portrait.tscn"

## A screen that counts how often the stack told it that it is shown, without
## taking the focus itself.
const COUNTING_SCREEN_SOURCE := """extends Control
var shown := 0
func on_shown() -> void:
	shown += 1
"""

var _changed: Array[Control] = []


func _spawn_stack() -> Control:
	var stack: Control = auto_free(STACK_SCRIPT.new())
	add_child(stack)
	_changed = []
	stack.connect("screen_changed", func(screen: Control) -> void: _changed.append(screen))
	return stack


## A plain screen holding one button per name; "!" in front disables it.
func _add_screen(stack: Control, screen_name: String, buttons: Array, script: GDScript = null) -> Control:
	var screen := Control.new()
	if script != null:
		screen.set_script(script)
	screen.name = screen_name
	var box := VBoxContainer.new()
	screen.add_child(box)
	for button_name: String in buttons:
		var button := Button.new()
		button.disabled = button_name.begins_with("!")
		button.name = button_name.trim_prefix("!")
		button.text = button.name
		box.add_child(button)
	stack.add_child(screen)
	stack.call("register", screen_name, screen)
	return screen


func _counting_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = COUNTING_SCREEN_SOURCE
	assert_int(script.reload()).is_equal(OK)
	return script


func _button(screen: Control, button_name: String) -> Button:
	return screen.find_child(button_name, true, false) as Button


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


# --- Menu stack ----------------------------------------------------------------

func test_an_empty_stack_has_no_current_screen() -> void:
	var stack := _spawn_stack()

	assert_str(String(stack.call("current_name"))).is_equal("")
	assert_object(stack.call("current_screen")).is_null()
	assert_bool(bool(stack.call("pop"))).is_false()


func test_registered_screens_stay_hidden_until_shown() -> void:
	var stack := _spawn_stack()
	var home := _add_screen(stack, "Home", ["Play"])

	assert_bool(home.visible).is_false()
	assert_int(home.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_array(_changed).is_empty()


func test_reset_shows_one_screen_and_focuses_its_first_usable_button() -> void:
	var stack := _spawn_stack()
	var home := _add_screen(stack, "Home", ["!Continue", "Play", "Quit"])
	var other := _add_screen(stack, "Other", ["Back"])
	other.visible = true

	stack.call("reset", "Home")

	assert_bool(home.visible).is_true()
	assert_bool(other.visible).is_false()
	assert_str(String(stack.call("current_name"))).is_equal("Home")
	assert_object(stack.call("current_screen")).is_same(home)
	# The disabled button is skipped.
	assert_object(_focus()).is_same(_button(home, "Play"))
	assert_array(_changed).is_equal([home])


func test_reset_to_an_unknown_screen_changes_nothing() -> void:
	var stack := _spawn_stack()
	var home := _add_screen(stack, "Home", ["Play"])
	stack.call("reset", "Home")
	_changed.clear()

	stack.call("reset", "Nowhere")

	assert_str(String(stack.call("current_name"))).is_equal("Home")
	assert_bool(home.visible).is_true()
	assert_array(_changed).is_empty()


func test_pushing_an_unknown_screen_is_refused() -> void:
	var stack := _spawn_stack()
	var home := _add_screen(stack, "Home", ["Play"])
	stack.call("reset", "Home")
	_changed.clear()

	assert_bool(bool(stack.call("push", "Nowhere"))).is_false()

	assert_str(String(stack.call("current_name"))).is_equal("Home")
	assert_bool(home.visible).is_true()
	assert_array(_changed).is_empty()


func test_push_hides_the_screen_underneath_and_pop_brings_it_back() -> void:
	var stack := _spawn_stack()
	var home := _add_screen(stack, "Home", ["Play", "Options"])
	var options := _add_screen(stack, "Options", ["Back"])
	stack.call("reset", "Home")

	assert_bool(bool(stack.call("push", "Options"))).is_true()

	assert_bool(home.visible).is_false()
	assert_bool(options.visible).is_true()
	assert_object(stack.call("current_screen")).is_same(options)
	assert_object(_focus()).is_same(_button(options, "Back"))

	assert_bool(bool(stack.call("pop"))).is_true()

	assert_bool(home.visible).is_true()
	assert_bool(options.visible).is_false()
	assert_str(String(stack.call("current_name"))).is_equal("Home")
	assert_array(_changed).is_equal([home, options, home])


func test_pop_gives_the_focus_back_to_the_button_that_opened_the_screen() -> void:
	var stack := _spawn_stack()
	var home := _add_screen(stack, "Home", ["Play", "Options"])
	_add_screen(stack, "Options", ["Back"])
	stack.call("reset", "Home")
	_button(home, "Options").grab_focus()
	stack.call("push", "Options")

	stack.call("pop")

	assert_object(_focus()).is_same(_button(home, "Options"))


func test_pop_falls_back_to_the_first_button_when_the_remembered_one_is_gone() -> void:
	var stack := _spawn_stack()
	var home := _add_screen(stack, "Home", ["Play", "Options"])
	_add_screen(stack, "Options", ["Back"])
	stack.call("reset", "Home")
	_button(home, "Options").grab_focus()
	stack.call("push", "Options")
	_button(home, "Options").visible = false

	stack.call("pop")

	assert_object(_focus()).is_same(_button(home, "Play"))


func test_the_last_screen_cannot_be_popped() -> void:
	var stack := _spawn_stack()
	var home := _add_screen(stack, "Home", ["Play"])
	stack.call("reset", "Home")
	_changed.clear()

	assert_bool(bool(stack.call("pop"))).is_false()

	assert_bool(home.visible).is_true()
	assert_str(String(stack.call("current_name"))).is_equal("Home")
	assert_array(_changed).is_empty()


func test_reset_forgets_the_screens_that_were_pushed() -> void:
	var stack := _spawn_stack()
	_add_screen(stack, "Home", ["Play"])
	_add_screen(stack, "Options", ["Back"])
	stack.call("reset", "Home")
	stack.call("push", "Options")

	stack.call("reset", "Home")

	assert_str(String(stack.call("current_name"))).is_equal("Home")
	assert_bool(bool(stack.call("pop"))).is_false()


func test_a_screen_is_told_each_time_it_is_shown() -> void:
	var stack := _spawn_stack()
	var script := _counting_script()
	var home := _add_screen(stack, "Home", ["Play"], script)
	_add_screen(stack, "Options", ["Back"], script)

	stack.call("reset", "Home")
	assert_int(int(home.get("shown"))).is_equal(1)

	stack.call("push", "Options")
	stack.call("pop")

	assert_int(int(home.get("shown"))).is_equal(2)


func test_a_screen_that_takes_no_focus_itself_still_gets_one() -> void:
	var stack := _spawn_stack()
	var home := _add_screen(stack, "Home", ["Play"], _counting_script())
	get_viewport().gui_release_focus()

	stack.call("reset", "Home")

	assert_object(_focus()).is_same(_button(home, "Play"))


func test_a_screen_without_anything_to_focus_is_still_shown() -> void:
	var stack := _spawn_stack()
	var empty := _add_screen(stack, "Empty", ["!Disabled"])
	empty.add_child(Label.new())
	get_viewport().gui_release_focus()

	stack.call("reset", "Empty")

	assert_bool(empty.visible).is_true()
	assert_object(_focus()).is_null()


# --- Confirmation screen -------------------------------------------------------

func test_confirmation_shows_its_texts_with_default_button_labels() -> void:
	var confirm: Control = auto_free(load(CONFIRM_SCENE).instantiate())
	add_child(confirm)

	confirm.call("show_confirmation", "Supprimer", "Vraiment ?")

	assert_str((confirm.get_node("%TitleLabel") as Label).text).is_equal("Supprimer")
	assert_str((confirm.get_node("%MessageLabel") as Label).text).is_equal("Vraiment ?")
	assert_str((confirm.get_node("%ConfirmButton") as Button).text).is_equal("Confirmer")
	assert_str((confirm.get_node("%CancelButton") as Button).text).is_equal("Annuler")


func test_confirmation_focuses_cancel_so_a_stray_press_is_harmless() -> void:
	var confirm: Control = auto_free(load(CONFIRM_SCENE).instantiate())
	add_child(confirm)

	confirm.call("on_shown")

	assert_object(_focus()).is_same(confirm.get_node("%CancelButton"))


func test_confirmation_buttons_report_the_answer() -> void:
	var confirm: Control = auto_free(load(CONFIRM_SCENE).instantiate())
	add_child(confirm)
	var answers: Array[String] = []
	confirm.connect("confirmed", func() -> void: answers.append("yes"))
	confirm.connect("cancelled", func() -> void: answers.append("no"))

	(confirm.get_node("%CancelButton") as Button).pressed.emit()
	(confirm.get_node("%ConfirmButton") as Button).pressed.emit()

	assert_array(answers).is_equal(["no", "yes"])


# --- Credits screen ------------------------------------------------------------

func test_credits_back_button_asks_to_go_back_and_takes_the_focus() -> void:
	var credits: Control = auto_free(load(CREDITS_SCENE).instantiate())
	add_child(credits)
	var requests: Array[bool] = []
	credits.connect("back_requested", func() -> void: requests.append(true))

	credits.call("on_shown")
	assert_object(_focus()).is_same(credits.get_node("%BackButton"))

	(credits.get_node("%BackButton") as Button).pressed.emit()

	assert_int(requests.size()).is_equal(1)


func test_credits_link_is_wired_to_the_screen() -> void:
	var credits: Control = auto_free(load(CREDITS_SCENE).instantiate())
	add_child(credits)
	var link: LinkButton = credits.get_node("%LimezuLink")

	# The link is not pressed: it would open the player's browser.
	# `Audio` also listens to every button for its click sound.
	var targets := link.pressed.get_connections().map(
		func(entry: Dictionary) -> Object: return (entry["callable"] as Callable).get_object())
	assert_bool(targets.has(credits)).is_true()


# --- Survival HUD --------------------------------------------------------------

func _spawn_survival(active: bool) -> Node:
	var survival: Node = auto_free(SURVIVAL_SCRIPT.new())
	survival.set("active", active)
	add_child(survival)
	# No drain between two assertions: the bars are driven by hand.
	survival.set_process(false)
	return survival


func _spawn_hud() -> CanvasLayer:
	var hud: CanvasLayer = auto_free(load(HUD_SCENE).instantiate())
	add_child(hud)
	return hud


func _fill_color(bar: ProgressBar) -> Color:
	return (bar.get_theme_stylebox("fill") as StyleBoxTexture).modulate_color


func test_hud_hides_itself_when_nothing_tracks_survival() -> void:
	assert_object(get_tree().get_first_node_in_group("survival")).is_null()
	var hud := _spawn_hud()

	await get_tree().process_frame
	await get_tree().process_frame

	assert_bool(hud.visible).is_false()


func test_hud_hides_itself_when_survival_is_switched_off() -> void:
	_spawn_survival(false)
	var hud := _spawn_hud()

	await get_tree().process_frame

	assert_bool(hud.visible).is_false()


func test_hud_binds_to_a_player_that_arrives_just_after_it() -> void:
	var hud := _spawn_hud()
	var survival := _spawn_survival(true)

	await get_tree().process_frame
	await get_tree().process_frame

	assert_bool(hud.visible).is_true()
	var food_bar: ProgressBar = hud.get_node("%FoodBar")
	var water_bar: ProgressBar = hud.get_node("%WaterBar")
	assert_float(food_bar.max_value).is_equal(float(survival.get("food_max")))
	# The bars round to their step, hence the tolerance.
	assert_float(food_bar.value).is_equal_approx(float(survival.get("food")), 0.02)
	assert_float(water_bar.value).is_equal_approx(float(survival.get("water")), 0.02)

	survival.call("add_food", -40.0)

	assert_float(food_bar.value).is_equal_approx(float(survival.get("food")), 0.02)
	assert_float(food_bar.value).is_less(float(survival.get("food_max")) - 39.0)
	assert_float(water_bar.value).is_equal_approx(float(survival.get("water")), 0.02)


func test_hud_bars_turn_red_when_running_low_and_recover() -> void:
	var survival := _spawn_survival(true)
	var hud := _spawn_hud()
	await get_tree().process_frame
	var food_bar: ProgressBar = hud.get_node("%FoodBar")
	var water_bar: ProgressBar = hud.get_node("%WaterBar")
	var food_color := _fill_color(food_bar)
	var water_color := _fill_color(water_bar)
	assert_that(food_color).is_not_equal(water_color)

	survival.emit_signal("food_changed", 20.0, 100.0)
	survival.emit_signal("water_changed", 24.0, 100.0)

	assert_that(_fill_color(food_bar)).is_not_equal(food_color)
	assert_that(_fill_color(food_bar)).is_equal(_fill_color(water_bar))

	survival.emit_signal("food_changed", 25.0, 100.0)
	survival.emit_signal("water_changed", 90.0, 100.0)

	assert_that(_fill_color(food_bar)).is_equal(food_color)
	assert_that(_fill_color(water_bar)).is_equal(water_color)


func test_hud_ignores_a_reading_without_a_maximum() -> void:
	var survival := _spawn_survival(true)
	var hud := _spawn_hud()
	await get_tree().process_frame
	var food_bar: ProgressBar = hud.get_node("%FoodBar")
	survival.emit_signal("food_changed", 60.0, 100.0)
	var color := _fill_color(food_bar)

	survival.emit_signal("food_changed", 5.0, 0.0)

	assert_float(food_bar.value).is_equal(60.0)
	assert_float(food_bar.max_value).is_equal(100.0)
	assert_that(_fill_color(food_bar)).is_equal(color)


# --- Family portrait -----------------------------------------------------------

func _spawn_portrait(layers: Dictionary, region: Variant = null) -> Control:
	var portrait: Control = auto_free(load(PORTRAIT_SCENE).instantiate())
	for layer_name: String in ["skin", "eyes", "hair", "accessory"]:
		portrait.set(layer_name, layers.get(layer_name, null))
	if region != null:
		portrait.set("region", region)
	add_child(portrait)
	return portrait


func _texture() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(96, 96, false, Image.FORMAT_RGBA8))


func test_portrait_crops_each_given_layer_to_the_head() -> void:
	var skin := _texture()
	var hair := _texture()
	var portrait := _spawn_portrait({"skin": skin, "hair": hair})

	var skin_rect: TextureRect = portrait.get_node("%Skin")
	var hair_rect: TextureRect = portrait.get_node("%Hair")
	assert_bool(skin_rect.visible).is_true()
	assert_object((skin_rect.texture as AtlasTexture).atlas).is_same(skin)
	assert_object((hair_rect.texture as AtlasTexture).atlas).is_same(hair)
	assert_that((skin_rect.texture as AtlasTexture).region).is_equal(Rect2(16, 12, 56, 56))


func test_portrait_hides_the_layers_it_was_not_given() -> void:
	var portrait := _spawn_portrait({"skin": _texture()})

	assert_bool((portrait.get_node("%Skin") as TextureRect).visible).is_true()
	assert_bool((portrait.get_node("%Eyes") as TextureRect).visible).is_false()
	assert_bool((portrait.get_node("%Hair") as TextureRect).visible).is_false()
	assert_bool((portrait.get_node("%Accessory") as TextureRect).visible).is_false()


func test_portrait_uses_a_custom_region() -> void:
	var portrait := _spawn_portrait({"eyes": _texture()}, Rect2(0, 0, 96, 96))

	var eyes_rect: TextureRect = portrait.get_node("%Eyes")
	assert_that((eyes_rect.texture as AtlasTexture).region).is_equal(Rect2(0, 0, 96, 96))
