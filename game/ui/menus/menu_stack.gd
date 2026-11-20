extends Control
## Minimal screen stack for menus. One screen is visible at a time so focus and
## mouse input cannot reach the screen underneath.

signal screen_changed(screen: Control)

var _screens: Dictionary = {}
var _history: Array[String] = []
var _focus_by_screen: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func register(screen_name: String, screen: Control) -> void:
	_screens[screen_name] = screen
	screen.visible = false
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func reset(screen_name: String) -> void:
	if not _screens.has(screen_name):
		return
	for value: Variant in _screens.values():
		(value as Control).visible = false
	_history.clear()
	_focus_by_screen.clear()
	_history.push_back(screen_name)
	var screen: Control = _screens[screen_name]
	screen.visible = true
	if _call_shown(screen):
		_ensure_focus(screen)
	else:
		_focus_first(screen)
	screen_changed.emit(screen)


func push(screen_name: String) -> bool:
	if not _screens.has(screen_name):
		return false
	var current := current_name()
	if current != "":
		_focus_by_screen[current] = get_viewport().gui_get_focus_owner()
		(_screens[current] as Control).visible = false
	_history.push_back(screen_name)
	var screen: Control = _screens[screen_name]
	screen.visible = true
	if _call_shown(screen):
		_ensure_focus(screen)
	else:
		_focus_first(screen)
	screen_changed.emit(screen)
	return true


func pop() -> bool:
	if _history.size() <= 1:
		return false
	var current: String = _history.pop_back()
	(_screens[current] as Control).visible = false
	var previous_name: String = _history.back()
	var previous: Control = _screens[previous_name]
	previous.visible = true
	_call_shown(previous)
	screen_changed.emit(previous)
	_restore_focus(previous_name)
	return true


func current_name() -> String:
	if _history.is_empty():
		return ""
	return _history.back()


func current_screen() -> Control:
	var screen_name := current_name()
	if screen_name == "":
		return null
	return _screens[screen_name] as Control


func _call_shown(screen: Control) -> bool:
	if screen.has_method("on_shown"):
		screen.call("on_shown")
		return true
	return false


func _ensure_focus(screen: Control) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not focus.is_visible_in_tree():
		_focus_first(screen)


func _restore_focus(screen_name: String) -> void:
	var remembered: Variant = _focus_by_screen.get(screen_name)
	if remembered is Control:
		var control := remembered as Control
		if is_instance_valid(control) and control.is_inside_tree() \
				and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
			return
	_focus_first(_screens[screen_name] as Control)


func _focus_first(screen: Control) -> void:
	var target := _find_focusable(screen)
	if target != null:
		target.grab_focus()


func _find_focusable(node: Node) -> Control:
	for child: Node in node.get_children():
		if child is Control:
			var control := child as Control
			if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
				if control is BaseButton and (control as BaseButton).disabled:
					continue
				if control is BaseButton or control is Range \
						or control is LineEdit or control is TextEdit or control is TabBar:
					return control
		var nested := _find_focusable(child)
		if nested != null:
			return nested
	return null
