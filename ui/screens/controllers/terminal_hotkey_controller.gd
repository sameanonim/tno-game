class_name TerminalHotkeyController
extends Node

##
## TerminalHotkeyController: Централизованный диспетчер горячих клавиш терминала
## ==============================================================================
## Обрабатывает глобальные клавиатурные сокращения командного бункера:
## - F5: Быстрое сохранение (Quick Save)
## - F9: Быстрая загрузка (Quick Load)
## - Space: Передача хода (End Turn)
## - Tab / Shift+Tab: Циклическое переключение закладок терминала
## - T: Переключение тактического оверлея карты
## - Escape: Закрытие активных модальных панелей (инспектор, управление, набеги)
## ==============================================================================

signal quick_save_requested()
signal quick_load_requested()
signal end_turn_requested()
signal toggle_tactical_requested()
signal cycle_tab_requested(reverse: bool)
signal open_parliament_requested()
signal toggle_research_requested()
signal escape_pressed()

@export var enabled: bool = true


func handle_input_event(event: InputEvent) -> bool:
	if not enabled:
		return false

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F5 or (event.keycode == KEY_S and event.ctrl_pressed):
			quick_save_requested.emit()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return true
		elif event.keycode == KEY_F9:
			quick_load_requested.emit()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return true
		elif event.keycode == KEY_SPACE:
			end_turn_requested.emit()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return true
		elif event.keycode == KEY_TAB:
			cycle_tab_requested.emit(event.shift_pressed)
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return true
		elif event.keycode == KEY_T:
			toggle_tactical_requested.emit()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return true
		elif event.keycode == KEY_C:
			open_parliament_requested.emit()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return true
		elif event.keycode == KEY_R:
			toggle_research_requested.emit()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return true
		elif event.keycode == KEY_ESCAPE:
			escape_pressed.emit()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return true

	return false


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not is_inside_tree():
		return
	handle_input_event(event)
