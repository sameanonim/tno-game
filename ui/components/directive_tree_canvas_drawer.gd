class_name DirectiveTreeCanvasDrawer
extends Node

##
## DirectiveTreeCanvasDrawer: Процедурная отрисовка ортогональных шин и связей взаимоисключения
## ==============================================================================
## Отвечает за:
## 1. Рекурсивный обход и динамическую трассировку видимых пререквизитов.
## 2. Отрисовку ортогональных шин (orthogonal buses) со стрелками и контактными терминалами.
## 3. Отрисовку взаимоисключающих связей (красный пунктир с бейджем [X]).
## ==============================================================================


"""Отрисовывает все ортогональные шины и связи взаимоисключения на холсте графа.
"""
static func draw_canvas_content(
	canvas: Control,
	all_directives: Dictionary,
	node_controls: Dictionary,
	node_size: Vector2,
	player_state: CountryState,
	turn_manager: TurnManager,
	color_dim: Color,
	color_cyan: Color,
	color_amber: Color,
	color_green: Color,
	color_exclusion: Color
) -> void:
	if canvas == null:
		return

	for dir_id in all_directives.keys():
		var dir: DirectiveResource = all_directives[dir_id]
		if not node_controls.has(dir_id):
			continue

		var child_ctrl: Control = node_controls[dir_id]
		if not child_ctrl.visible:
			continue

		var child_rect := Rect2(child_ctrl.position, node_size)
		var child_entry := Vector2(child_rect.position.x + child_rect.size.x * 0.5, child_rect.position.y)

		# 1. Отрисовка направленных ортогональных шин пререквизитов с динамическим обходом скрытых нод
		var visible_prereqs = find_visible_prerequisites(dir_id, all_directives, node_controls)
		for prereq_id in visible_prereqs:
			if not node_controls.has(prereq_id):
				continue

			var parent_ctrl: Control = node_controls[prereq_id]
			if not parent_ctrl.visible:
				continue

			var parent_rect := Rect2(parent_ctrl.position, node_size)
			var parent_exit := Vector2(parent_rect.position.x + parent_rect.size.x * 0.5, parent_rect.position.y + parent_rect.size.y)

			var line_col = color_dim
			var line_width := 1.5

			var is_p_done = player_state != null and player_state.completed_directives.has(prereq_id)
			var is_c_done = player_state != null and player_state.completed_directives.has(dir_id)
			var is_c_active = (turn_manager != null and "active_directive" in turn_manager and turn_manager.active_directive != null and turn_manager.active_directive.id == dir_id) \
				or (player_state != null and player_state.active_directives.has(dir_id))

			if is_c_done:
				line_col = color_cyan
				line_width = 2.5
			elif is_c_active:
				line_col = color_amber
				line_width = 2.5
			elif is_p_done:
				line_col = color_green
				line_width = 2.0

			draw_orthogonal_bus(canvas, parent_exit, child_entry, line_col, line_width)

		# 2. Отрисовка взаимоисключающих связей (красный пунктир [X])
		for excl_id in dir.mutually_exclusive:
			if not node_controls.has(excl_id) or dir_id > excl_id:
				continue

			var excl_ctrl: Control = node_controls[excl_id]
			# Если один из узлов скрыт по allow_branch — линия исключения не рисуется
			if not excl_ctrl.visible or not child_ctrl.visible:
				continue

			var a_pos = child_ctrl.position + (node_size * 0.5)
			var b_pos = excl_ctrl.position + (node_size * 0.5)
			draw_exclusive_link(canvas, a_pos, b_pos, color_exclusion)


"""Рекурсивный поиск ближайших видимых предков (если промежуточный узел скрыт директивой allow_branch).
"""
static func find_visible_prerequisites(
	dir_id: String,
	all_directives: Dictionary,
	node_controls: Dictionary,
	visited: Array[String] = []
) -> Array[String]:
	var result: Array[String] = []
	if not all_directives.has(dir_id) or visited.has(dir_id):
		return result
	visited.append(dir_id)

	var dir: DirectiveResource = all_directives[dir_id]
	var all_prereqs = get_all_prereq_ids(dir)
	for prereq_id in all_prereqs:
		if node_controls.has(prereq_id) and node_controls[prereq_id].visible:
			if not result.has(prereq_id):
				result.append(prereq_id)
		elif all_directives.has(prereq_id):
			var ancestor_visible = find_visible_prerequisites(prereq_id, all_directives, node_controls, visited)
			for a_id in ancestor_visible:
				if not result.has(a_id):
					result.append(a_id)

	return result


"""Извлечение всех ID пререквизитов (как плоского списка, так и логических групп).
"""
static func get_all_prereq_ids(dir: DirectiveResource) -> Array[String]:
	var ids: Array[String] = []
	if dir == null:
		return ids
	for p in dir.prerequisites:
		var p_str = str(p)
		if not ids.has(p_str):
			ids.append(p_str)
	for grp in dir.prerequisites_groups:
		if grp is Array:
			for elem in grp:
				var elem_str = str(elem)
				if not ids.has(elem_str):
					ids.append(elem_str)
	return ids


"""Отрисовывает ортогональную шину (Z-образную линию с контактными точками и стрелкой).
"""
static func draw_orthogonal_bus(canvas: Control, from: Vector2, to: Vector2, col: Color, width: float) -> void:
	var mid_y = from.y + (to.y - from.y) * 0.5
	var p1 = from
	var p2 := Vector2(from.x, mid_y)
	var p3 := Vector2(to.x, mid_y)
	var p4 = to

	canvas.draw_line(p1, p2, col, width)
	canvas.draw_line(p2, p3, col, width)
	canvas.draw_line(p3, p4, col, width)

	# Контактные терминальные площадки
	canvas.draw_circle(p1, width * 1.3, col)
	canvas.draw_circle(p4, width * 1.3, col)

	# Направленная стрелка на входе в дочерний узел
	var arrow_size := 4.0
	var arrow_p1 = p4
	var arrow_p2 = p4 + Vector2(-arrow_size, -arrow_size * 1.5)
	var arrow_p3 = p4 + Vector2(arrow_size, -arrow_size * 1.5)
	canvas.draw_colored_polygon(PackedVector2Array([arrow_p1, arrow_p2, arrow_p3]), col)


"""Отрисовывает линию взаимоисключения с бейджем [X].
"""
static func draw_exclusive_link(canvas: Control, a: Vector2, b: Vector2, color_exclusion: Color) -> void:
	canvas.draw_dashed_line(a, b, color_exclusion, 2.5, 8.0)

	var mid = (a + b) * 0.5
	# Круглый терминальный бейдж с крестом [X]
	canvas.draw_circle(mid, 9.0, Color(0.18, 0.02, 0.02, 0.98))
	canvas.draw_arc(mid, 9.0, 0, TAU, 16, color_exclusion, 1.8)
	canvas.draw_line(mid + Vector2(-5, -5), mid + Vector2(5, 5), color_exclusion, 2.0)
	canvas.draw_line(mid + Vector2(-5, 5), mid + Vector2(5, -5), color_exclusion, 2.0)
