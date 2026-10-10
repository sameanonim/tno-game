class_name TestDraggableWindow
extends TNOSimpleTest

##
## TestDraggableWindow: Тестирование базового компонента перемещения окон и EventPopup
##

var window: DraggableWindow = null
var popup: EventPopup = null


func setup() -> void:
	window = DraggableWindow.new()
	popup = EventPopup.new()


func teardown() -> void:
	if window != null and is_instance_valid(window):
		window.free()
		window = null
	if popup != null and is_instance_valid(popup):
		popup.free()
		popup = null


func test_draggable_window_initialization() -> void:
	assert_true(window != null, "DraggableWindow должен успешно создаваться")
	assert_true(window.clamp_to_viewport, "clamp_to_viewport по умолчанию должен быть включен")
	assert_true(window.double_click_center, "double_click_center по умолчанию должен быть включен")
	assert_false(window.is_dragging, "is_dragging изначально false")


func test_custom_drag_handle_binding() -> void:
	var handle := Control.new()
	handle.name = "CustomHeader"
	window.add_child(handle)
	window.set_drag_handle(handle)
	
	assert_eq(window.drag_handle, handle, "Кастомный драг-хэндл должен быть корректно привязан")
	assert_eq(handle.mouse_filter, Control.MOUSE_FILTER_STOP, "mouse_filter на драг-хэндле должен блокировать провал клика")


func test_viewport_clamping_math() -> void:
	window.size = Vector2(400, 300)
	# Тестируем метод _clamp_to_viewport
	var clamped_pos = window._clamp_to_viewport(Vector2(-1000, -500))
	assert_true(clamped_pos.x >= -400.0 + DraggableWindow.MIN_VISIBLE_BORDER, "Окно не должно улетать слишком далеко влево")
	assert_true(clamped_pos.y >= 0.0, "Окно не должно улетать выше экрана")


func test_event_popup_toggle_minimize() -> void:
	assert_true(popup != null, "EventPopup должен успешно инстанцироваться")
	assert_false(popup.is_minimized, "EventPopup изначально развернут")
	
	var signal_emitted: Array = []
	popup.minimized_changed.connect(func(min_state: bool):
		signal_emitted.append(min_state)
	)
	
	popup.toggle_minimize()
	assert_true(popup.is_minimized, "Окно должно стать свернутым")
	assert_eq(signal_emitted.size(), 1, "Сигнал minimized_changed должен испускаться")
	assert_true(signal_emitted[0], "Состояние свернутости в сигнале должно быть true")
	
	popup.toggle_minimize()
	assert_false(popup.is_minimized, "Окно должно развернуться обратно")
	assert_eq(signal_emitted.size(), 2, "Сигнал должен испуститься повторно")
	assert_false(signal_emitted[1], "Состояние свернутости в сигнале должно быть false")


func test_event_popup_option_chosen_signal() -> void:
	var chosen_idx: int = -1
	popup.option_chosen.connect(func(idx: int):
		chosen_idx = idx
	)
	
	popup._on_option_pressed(2)
	assert_eq(chosen_idx, 2, "option_chosen должен передавать правильный индекс опции")
	assert_false(popup.visible, "Окно должно скрываться после выбора опции")
