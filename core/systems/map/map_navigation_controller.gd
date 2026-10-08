class_name MapNavigationController
extends RefCounted

##
## MapNavigationController: Управление камерой, панорамированием, масштабированием и границами карты
## ==============================================================================
## Отвечает за:
## 1. Обработку клавиш перемещения (WASD / Arrows) с учетом масштаба и скорости.
## 2. Мышиный драг (СКМ / ПКМ) и зум к курсору (колесо мыши).
## 3. Ограничение перемещения карты (Clamp Position).
## 4. Синхронизацию лимитов целевой Camera2D.
## ==============================================================================


"""Обработка непрерывного перемещения клавиатурой (WASD / стрелки).
"""
static func process_keyboard_pan(
	map_node: Node2D,
	delta: float,
	pan_speed: float,
	base_position: Vector2,
	map_size: Vector2i,
	target_camera: Camera2D
) -> void:
	if map_node == null:
		return

	var move_vec := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move_vec.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move_vec.y -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move_vec.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move_vec.x -= 1.0

	if move_vec != Vector2.ZERO:
		map_node.position += move_vec.normalized() * (pan_speed * delta)
		clamp_map_position(map_node, base_position, map_size, target_camera)


"""Плавный расчет масштабирования к экранной точке курсора (зум-пивот).
Возвращает новый уровень зума.
"""
static func adjust_zoom(
	map_node: Node2D,
	current_zoom: float,
	factor: float,
	min_zoom: float,
	max_zoom: float,
	pivot_screen_pos: Vector2,
	base_position: Vector2,
	map_size: Vector2i,
	target_camera: Camera2D
) -> float:
	if map_node == null:
		return current_zoom

	var new_zoom = clampf(current_zoom * factor, min_zoom, max_zoom)
	if is_equal_approx(new_zoom, current_zoom):
		return current_zoom

	var local_pivot = map_node.to_local(pivot_screen_pos)
	map_node.scale = Vector2(new_zoom, new_zoom)
	map_node.position += (local_pivot * (current_zoom - new_zoom))
	clamp_map_position(map_node, base_position, map_size, target_camera)
	return new_zoom


"""Ограничение перемещения карты в границах видимости с буферным отступом.
"""
static func clamp_map_position(
	map_node: Node2D,
	base_position: Vector2,
	map_size: Vector2i,
	target_camera: Camera2D
) -> void:
	if map_node == null:
		return

	var scaled_half = (Vector2(map_size) * map_node.scale) * 0.5
	var margin := Vector2(300.0, 300.0)
	map_node.position.x = clampf(map_node.position.x, base_position.x - scaled_half.x - margin.x, base_position.x + scaled_half.x + margin.x)
	map_node.position.y = clampf(map_node.position.y, base_position.y - scaled_half.y - margin.y, base_position.y + scaled_half.y + margin.y)
	update_camera_limits(map_node, base_position, map_size, target_camera)


"""Синхронизация физических лимитов Target Camera2D.
"""
static func update_camera_limits(
	map_node: Node2D,
	base_position: Vector2,
	map_size: Vector2i,
	target_camera: Camera2D
) -> void:
	if target_camera == null or map_size == Vector2i.ZERO or map_node == null:
		return
	var half_size = Vector2(map_size) * 0.5 * map_node.scale.x
	target_camera.limit_left = int(base_position.x - half_size.x - 300)
	target_camera.limit_top = int(base_position.y - half_size.y - 300)
	target_camera.limit_right = int(base_position.x + half_size.x + 300)
	target_camera.limit_bottom = int(base_position.y + half_size.y + 300)
