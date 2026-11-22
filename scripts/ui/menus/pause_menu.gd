extends CanvasLayer
## Global pause overlay. Owns the in-game screen stack and pauses the tree.

const PENDING_MAIN_MENU := "main_menu"
const PENDING_QUIT := "quit"

@onready var root: Control = %Root
@onready var stack: Control = %MenuStack
@onready var pause_screen: Control = %PauseScreen
@onready var settings_screen: Control = %SettingsScreen
@onready var controls_screen: Control = %ControlsScreen
@onready var confirm_screen: Control = %ConfirmScreen
@onready var resume_button: Button = %ResumeButton
@onready var options_button: Button = %OptionsButton
@onready var controls_button: Button = %ControlsButton
@onready var save_button: Button = %SaveButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var quit_button: Button = %QuitButton
@onready var subtitle: Label = %Subtitle
@onready var save_status: Label = %SaveStatus
@onready var save_status_timer: Timer = %SaveStatusTimer

var _pending_action := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	root.visible = false
	stack.register("Pause", pause_screen)
	stack.register("Settings", settings_screen)
	stack.register("Controls", controls_screen)
	stack.register("Confirm", confirm_screen)
	resume_button.pressed.connect(close)
	options_button.pressed.connect(_on_options_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	save_button.pressed.connect(_on_save_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_screen.back_requested.connect(_on_sub_screen_back)
	controls_screen.back_requested.connect(_on_sub_screen_back)
	confirm_screen.confirmed.connect(_on_confirmed)
	confirm_screen.cancelled.connect(_on_cancelled)
	save_status_timer.timeout.connect(_hide_save_status)
	SceneRouter.scene_changed.connect(_on_scene_changed)
	# A browser tab cannot be quit: the canvas would just freeze.
	if OS.has_feature("web"):
		quit_button.visible = false


func open() -> void:
	if visible or not SceneRouter.is_gameplay or get_tree().paused \
			or SceneRouter.is_transitioning():
		return
	get_tree().paused = true
	visible = true
	root.visible = true
	subtitle.text = GameState.status_line()
	save_status.visible = false
	stack.reset("Pause")
	SaveGame.save_game()


func close() -> void:
	if not visible:
		return
	visible = false
	root.visible = false
	get_tree().paused = false
	get_viewport().gui_release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not SceneRouter.is_gameplay:
		return
	if visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			_handle_back()
			get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if event.is_action_pressed("pause"):
		open()
		get_viewport().set_input_as_handled()


func _handle_back() -> void:
	var current := String(stack.current_name())
	if current == "Confirm":
		_on_cancelled()
	elif current == "Pause":
		close()
	else:
		Settings.save_settings()
		stack.pop()


func _on_options_pressed() -> void:
	stack.push("Settings")


func _on_controls_pressed() -> void:
	stack.push("Controls")


func _on_save_pressed() -> void:
	var saved := SaveGame.save_game()
	save_status.text = "Partie sauvegardée." if saved else "Échec de la sauvegarde."
	save_status.visible = true
	save_status_timer.start()


func _on_main_menu_pressed() -> void:
	_open_confirmation(
		PENDING_MAIN_MENU,
		"Menu principal",
		"Revenir au menu principal ? La partie sera sauvegardée.",
		"Revenir",
		"Annuler")


func _on_quit_pressed() -> void:
	_open_confirmation(
		PENDING_QUIT,
		"Quitter",
		"Voulez-vous quitter Salazie ? La partie sera sauvegardée.",
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
		PENDING_MAIN_MENU:
			close()
			SceneRouter.go_to_main_menu()
		PENDING_QUIT:
			SceneRouter.quit_game()


func _on_cancelled() -> void:
	_pending_action = ""
	stack.pop()


func _on_scene_changed(_scene: Node) -> void:
	if not SceneRouter.is_gameplay:
		close()


func _hide_save_status() -> void:
	save_status.visible = false
