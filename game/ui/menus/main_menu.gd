extends Control
## Main menu: new game, continue, options, credits, quit.

const PENDING_NEW_GAME := "new_game"
const PENDING_QUIT := "quit"

@onready var stack: Control = %MenuStack
@onready var home_screen: Control = %HomeScreen
@onready var settings_screen: Control = %SettingsScreen
@onready var credits_screen: Control = %CreditsScreen
@onready var confirm_screen: Control = %ConfirmScreen
@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var continue_info: Label = %ContinueInfo
@onready var options_button: Button = %OptionsButton
@onready var credits_button: Button = %CreditsButton
@onready var quit_button: Button = %QuitButton
@onready var version_label: Label = %VersionLabel

var _pending_action := ""


func _ready() -> void:
	stack.register("Home", home_screen)
	stack.register("Settings", settings_screen)
	stack.register("Credits", credits_screen)
	stack.register("Confirm", confirm_screen)
	stack.reset("Home")

	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	options_button.pressed.connect(_on_options_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_screen.back_requested.connect(_on_sub_screen_back)
	credits_screen.back_requested.connect(_on_sub_screen_back)
	confirm_screen.confirmed.connect(_on_confirmed)
	confirm_screen.cancelled.connect(_on_cancelled)

	if OS.has_feature("web"):
		quit_button.visible = false
	version_label.text = "v%s" % String(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	_refresh_continue()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and _handle_back():
		get_viewport().set_input_as_handled()


func _handle_back() -> bool:
	var current := String(stack.current_name())
	if current == "Confirm":
		_on_cancelled()
		return true
	if current == "Settings" or current == "Credits":
		Settings.save_settings()
		stack.pop()
		return true
	return false


func _refresh_continue() -> void:
	var metadata := SaveGame.read_metadata()
	var has_save := not metadata.is_empty()
	continue_button.disabled = not has_save
	if has_save:
		continue_info.text = "Jour %d · %d G" % [int(metadata["day"]), int(metadata["money"])]
	else:
		continue_info.text = "Aucune sauvegarde"


func _on_new_game_pressed() -> void:
	if SaveGame.has_valid_save():
		_open_confirmation(
			PENDING_NEW_GAME,
			"Nouvelle partie",
			"Une sauvegarde existe déjà. Voulez-vous la remplacer ?",
			"Remplacer",
			"Annuler")
		return
	SceneRouter.start_new_game()


func _on_continue_pressed() -> void:
	if not SaveGame.has_valid_save():
		_refresh_continue()
		return
	SceneRouter.continue_game()


func _on_options_pressed() -> void:
	stack.push("Settings")


func _on_credits_pressed() -> void:
	stack.push("Credits")


func _on_quit_pressed() -> void:
	_open_confirmation(
		PENDING_QUIT,
		"Quitter",
		"Voulez-vous quitter Salazie ?",
		"Quitter",
		"Annuler")


func _open_confirmation(action: String, title: String, message: String, confirm_text: String, cancel_text: String) -> void:
	_pending_action = action
	confirm_screen.show_confirmation(title, message, confirm_text, cancel_text)
	stack.push("Confirm")


func _on_sub_screen_back() -> void:
	stack.pop()


func _on_confirmed() -> void:
	var action := _pending_action
	_pending_action = ""
	stack.pop()
	match action:
		PENDING_NEW_GAME:
			SceneRouter.start_new_game()
		PENDING_QUIT:
			SceneRouter.quit_game()


func _on_cancelled() -> void:
	_pending_action = ""
	stack.pop()
