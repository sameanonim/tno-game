class_name DraggableWindow
extends PanelContainer

##
## DraggableWindow: Базовый компонент перетаскиваемого окна для UI TNO
## ==============================================================================
## Позволяет свободно перемещать окно мышью за область заголовка (Drag & Drop),
## автоматически поднимает окно на передний план (Z-index фокус), удерживает его
## в пределах экрана (Viewport clamping) и поддерживает центрирование по дабл-клику.
## ==============================================================================

signal drag_started()
signal drag_ended()
signal window_focused()
signal window_closed()

@export var drag_handle_path: NodePath = NodePath("")
@export var clamp_to_viewport: bool = true
@export var double_click_center: bool = true

var drag_handle: Control = null
var is_dragging: bool = false
var drag_mouse_start_pos: Vector2 = Vector2.ZERO
var drag_window_start_pos: Vector2 = Vector2.ZERO

const MIN_VISIBLE_BORDER: float = 32.0


func _ready() -> void:
	_setup_drag_handle()
	mouse_filter = Control.MOUSE_FILTER_STOP


"""Подключает перехват событий мыши на драг-хэндле (области заголовка).
"""
func _setup_drag_handle() -> void:
	if not drag_handle_path.is_empty():
		drag_handle = get_node_or_null(drag_handle_path) as Control
	
	if drag_handle == null:
		# Пытаемся найти типичные имена узлов заголовка
		for candidate_name in ["HeaderBar", "HeaderHBox", "TitleBar", "VBox/HeaderHBox", "VBox/HeaderBar"]:
			var node := get_node_or_null(candidate_name) as Control
			if node != null:
				drag_handle = node
				break
	
	if drag_handle != null:
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		if not drag_handle.gui_input.is_connected(_on_drag_handle_gui_input):
			drag_handle.gui_input.connect(_on_drag_handle_gui_input)


"""Назначает кастомный управляющий узел заголовка для перетаскивания.
"""
func set_drag_handle(handle: Control) -> void:
	if drag_handle != null and drag_handle.gui_input.is_connected(_on_drag_handle_gui_input):
		drag_handle.gui_input.disconnect(_on_drag_handle_gui_input)
	drag_handle = handle
	if drag_handle != null:
		drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
		if not drag_handle.gui_input.is_connected(_on_drag_handle_gui_input):
			drag_handle.gui_input.connect(_on_drag_handle_gui_input)


"""Обработчик ввода мыши на области заголовка.
"""
func _on_drag_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				bring_to_front()
				if double_click_center and mb.double_click:
					center_in_viewport()
					is_dragging = false
					drag_ended.emit()
					return
				
				is_dragging = true
				drag_mouse_start_pos = mb.global_position
				drag_window_start_pos = global_position
				drag_started.emit()
			else:
				if is_dragging:
					is_dragging = false
					drag_ended.emit()
	
	elif event is InputEventMouseMotion and is_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var delta: Vector2 = mm.global_position - drag_mouse_start_pos
		var target_pos: Vector2 = drag_window_start_pos + delta
		
		if clamp_to_viewport:
			target_pos = _clamp_to_viewport(target_pos)
		
		global_position = target_pos


"""Глобальный перехват завершения перетаскивания, если мышь отпустили за пределами хэндла.
"""
func _unhandled_input(event: InputEvent) -> void:
	if is_dragging and event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			is_dragging = false
			drag_ended.emit()


"""Ограничивает координаты окна видимой областью вьюпорта.
"""
func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var vp_rect := get_viewport_rect()
	var min_x: float = -size.x + MIN_VISIBLE_BORDER
	var max_x: float = vp_rect.size.x - MIN_VISIBLE_BORDER
	var min_y: float = 0.0
	var max_y: float = vp_rect.size.y - MIN_VISIBLE_BORDER
	
	return Vector2(
		clampf(pos.x, min_x, max_x),
		clampf(pos.y, min_y, max_y)
	)


"""Поднимает окно на передний план среди соседей.
"""
func bring_to_front() -> void:
	move_to_front()
	window_focused.emit()


"""Центрирует окно относительно текущего вьюпорта.
"""
func center_in_viewport() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	var target_x: float = (vp_size.x - size.x) * 0.5
	var target_y: float = (vp_size.y - size.y) * 0.5
	
	# Сбрасываем якоря в TOP_LEFT для абсолютного свободного позиционирования
	layout_mode = 0
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	global_position = Vector2(target_x, target_y)


"""Закрывает окно с испусканием соответствующего сигнала.
"""
func close_window() -> void:
	visible = false
	is_dragging = false
	window_closed.emit()
