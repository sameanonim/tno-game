class_name FocusTreeCanvas
extends Control

"""
FocusTreeCanvas: Infinite pan/zoom canvas for rendering TNO national focus trees.
Features:
- Pan (Middle click or Space+LMB drag)
- Zoom (0.3x - 1.5x centered on cursor)
- Manhattan orthogonal connection routing in _draw() (down -> horizontal -> down)
- Dynamic line styling (green/gold for available/completed, grey for locked, dashed red for mutually exclusive)
- Viewport culling for performance optimization with large trees
"""

signal focus_clicked(focus_id: StringName)

@export var manager: FocusTreeManager = null
@export var grid_cell_size: Vector2 = Vector2(145.0, 140.0)
@export var grid_origin: Vector2 = Vector2(100.0, 80.0)

# Pan & Zoom State
var pan_offset: Vector2 = Vector2.ZERO
var zoom_scale: float = 1.0
const MIN_ZOOM: float = 0.3
const MAX_ZOOM: float = 1.5

# Dragging State
var is_dragging: bool = false
var drag_start_mouse_pos: Vector2 = Vector2.ZERO
var drag_start_pan_offset: Vector2 = Vector2.ZERO
var is_space_pressed: bool = false

# Nodes & Widgets
var content_container: Control = null
var widget_map: Dictionary = {} ## Dictionary[StringName, FocusNodeWidget]
var node_positions: Dictionary = {} ## Dictionary[StringName, Vector2] (center positions)


func _init() -> void:
	content_container = Control.new()
	content_container.name = "CanvasContent"
	content_container.mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP

	_ensure_content_container()
	if manager:
		bind_manager(manager)


func _ensure_content_container() -> void:
	if content_container == null:
		content_container = Control.new()
		content_container.name = "CanvasContent"
		content_container.mouse_filter = MOUSE_FILTER_IGNORE
	if not content_container.is_inside_tree() and is_inside_tree():
		add_child(content_container)
	elif content_container.get_parent() == null:
		add_child(content_container)


"""Binds the canvas to a FocusTreeManager and loads its tree."""
func bind_manager(p_manager: FocusTreeManager) -> void:
	manager = p_manager
	if not manager.focus_progress_updated.is_connected(Callable(self, "_on_focus_progress")):
		manager.focus_progress_updated.connect(Callable(self, "_on_focus_progress"))
	if not manager.focus_completed.is_connected(Callable(self, "_on_focus_state_changed")):
		manager.focus_completed.connect(Callable(self, "_on_focus_state_changed"))
	if not manager.focus_started.is_connected(Callable(self, "_on_focus_state_changed")):
		manager.focus_started.connect(Callable(self, "_on_focus_state_changed"))
	if not manager.focus_cancelled.is_connected(Callable(self, "_on_focus_cancelled")):
		manager.focus_cancelled.connect(Callable(self, "_on_focus_cancelled"))
	if not manager.focus_paused.is_connected(Callable(self, "_on_focus_pause_changed")):
		manager.focus_paused.connect(Callable(self, "_on_focus_pause_changed"))
	if not manager.focus_resumed.is_connected(Callable(self, "_on_focus_pause_changed")):
		manager.focus_resumed.connect(Callable(self, "_on_focus_pause_changed"))
	if not manager.tree_swapped.is_connected(Callable(self, "_on_tree_swapped")):
		manager.tree_swapped.connect(Callable(self, "_on_tree_swapped"))
	if not manager.branch_replaced.is_connected(Callable(self, "_on_branch_replaced")):
		manager.branch_replaced.connect(Callable(self, "_on_branch_replaced"))
	if not manager.focus_bypassed.is_connected(Callable(self, "_on_focus_state_changed")):
		manager.focus_bypassed.connect(Callable(self, "_on_focus_state_changed"))
	if not manager.focus_midway_triggered.is_connected(Callable(self, "_on_focus_midway_triggered")):
		manager.focus_midway_triggered.connect(Callable(self, "_on_focus_midway_triggered"))

	if manager.current_tree:
		load_tree(manager.current_tree)


"""Rebuilds the visual tree layout for a FocusTreeData resource."""
func load_tree(tree: FocusTreeData) -> void:
	_ensure_content_container()
	# Clear previous widgets
	for w in widget_map.values():
		if is_instance_valid(w):
			w.queue_free()
	widget_map.clear()
	node_positions.clear()

	if tree == null:
		queue_redraw()
		return

	# Calculate positions and spawn widgets
	for nid in tree.nodes.keys():
		var node: FocusNodeData = tree.nodes[nid]
		if not node or node.is_hidden:
			continue

		var local_pos = grid_origin + Vector2(node.grid_coord.x * grid_cell_size.x, node.grid_coord.y * grid_cell_size.y)
		var widget := FocusNodeWidget.new()
		widget.position = local_pos
		widget.setup(node, manager)
		widget.focus_selected.connect(Callable(self, "_on_widget_selected"))

		content_container.add_child(widget)
		widget_map[node.id] = widget

		# Store center position of the widget
		var widget_size = widget.custom_minimum_size
		node_positions[node.id] = local_pos + (widget_size * 0.5)

	_apply_transform()
	queue_redraw()


func _apply_transform() -> void:
	if content_container:
		content_container.position = pan_offset
		content_container.scale = Vector2(zoom_scale, zoom_scale)
	queue_redraw()


# ==============================================================================
# INPUT, PAN & ZOOM
# ==============================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke = event as InputEventKey
		if ke.keycode == KEY_SPACE:
			is_space_pressed = ke.pressed

	elif event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		# Middle click OR Space+Left Click for Pan
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and is_space_pressed):
			if mb.pressed:
				is_dragging = true
				drag_start_mouse_pos = mb.position
				drag_start_pan_offset = pan_offset
			else:
				is_dragging = false
			accept_event()

		# Zoom in / out centered on cursor
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 0.9)
			accept_event()

	elif event is InputEventMouseMotion:
		if is_dragging:
			var mm = event as InputEventMouseMotion
			pan_offset = drag_start_pan_offset + (mm.position - drag_start_mouse_pos)
			_apply_transform()
			accept_event()


func _zoom_at(cursor_pos: Vector2, factor: float) -> void:
	var old_zoom = zoom_scale
	var new_zoom = clampf(zoom_scale * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(old_zoom, new_zoom):
		return

	# Zoom centered on cursor position:
	# canvas_pos = (cursor_pos - pan_offset) / old_zoom
	# new_pan_offset = cursor_pos - canvas_pos * new_zoom
	var canvas_pos = (cursor_pos - pan_offset) / old_zoom
	zoom_scale = new_zoom
	pan_offset = cursor_pos - (canvas_pos * zoom_scale)
	_apply_transform()


# ==============================================================================
# ORTHOGONAL MANHATTAN DRAWING & CULLING
# ==============================================================================

func _draw() -> void:
	if manager == null or manager.current_tree == null:
		return

	var tree = manager.current_tree
	var visible_rect := _get_visible_canvas_rect()

	# Draw connections
	for nid in tree.nodes.keys():
		var child_node: FocusNodeData = tree.nodes[nid]
		if not child_node or child_node.is_hidden or child_node.prerequisites.is_empty():
			continue

		var child_pos = node_positions.get(child_node.id, Vector2.ZERO)
		var child_widget: FocusNodeWidget = widget_map.get(child_node.id, null)
		var child_size = child_widget.size if child_widget else Vector2(160, 90)

		# Top anchor of child
		var child_top := Vector2(child_pos.x, child_pos.y - child_size.y * 0.5)

		for and_group in child_node.prerequisites:
			for p_id in and_group:
				var parent_id = StringName(p_id)
				if not node_positions.has(parent_id):
					continue

				var parent_pos = node_positions[parent_id]
				var parent_widget: FocusNodeWidget = widget_map.get(parent_id, null)
				var parent_size = parent_widget.size if parent_widget else Vector2(160, 90)

				# Bottom anchor of parent
				var parent_bottom := Vector2(parent_pos.x, parent_pos.y + parent_size.y * 0.5)

				# Culling: skip if both parent and child bounding boxes are outside visible rect
				var segment_rect := Rect2(parent_bottom, Vector2.ZERO).expand(child_top)
				if not visible_rect.intersects(segment_rect):
					continue

				# Line styling
				var is_parent_done = manager.is_focus_completed(parent_id)
				var is_child_done = manager.is_focus_completed(child_node.id)
				var is_child_avail = manager.can_start_focus(child_node.id)

				var line_color := Color(0.35, 0.4, 0.45, 0.5) # Locked default grey
				var line_width := 2.0

				if is_parent_done and is_child_done:
					line_color = Color(0.9, 0.75, 0.2, 0.95) # Gold completed
					line_width = 3.0
				elif is_parent_done and is_child_avail:
					line_color = Color(0.2, 0.9, 0.4, 0.95) # Neon green available
					line_width = 3.0

				# Transform points from canvas space to screen space
				var p_screen = (parent_bottom * zoom_scale) + pan_offset
				var c_screen = (child_top * zoom_scale) + pan_offset

				_draw_manhattan_path(p_screen, c_screen, line_color, line_width)

		# Draw Mutually Exclusive connections
		if not child_node.mutually_exclusive.is_empty():
			for m_id in child_node.mutually_exclusive:
				var mut_id = StringName(m_id)
				var other_node: FocusNodeData = tree.nodes.get(mut_id, null)
				if other_node and other_node.is_hidden:
					continue
				if String(child_node.id) < String(mut_id) and node_positions.has(mut_id):
					var other_pos = node_positions[mut_id]
					var p1_screen = (child_pos * zoom_scale) + pan_offset
					var p2_screen = (other_pos * zoom_scale) + pan_offset
					_draw_dashed_line(p1_screen, p2_screen, Color(0.95, 0.2, 0.2, 0.8), 2.0, 6.0)


"""
Draws orthogonal Manhattan lines:
1. Down from parent to horizontal split level
2. Across to child X
3. Down to child top anchor
"""
func _draw_manhattan_path(start: Vector2, end: Vector2, color: Color, width: float) -> void:
	var mid_y = start.y + (end.y - start.y) * 0.5
	var p1 = start
	var p2 := Vector2(start.x, mid_y)
	var p3 := Vector2(end.x, mid_y)
	var p4 = end

	# Step 1: Vertical down
	draw_line(p1, p2, color, width, true)
	# Step 2: Horizontal across
	draw_line(p2, p3, color, width, true)
	# Step 3: Vertical down to target
	draw_line(p3, p4, color, width, true)

	# Small neon terminal arrow or dot at destination
	draw_circle(p4, width * 1.5, color)


"""Draws a dashed line for mutually exclusive connections."""
func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash_len: float) -> void:
	var dir = (to - from).normalized()
	var dist = from.distance_to(to)
	var cur := 0.0
	var drawing := true

	while cur < dist:
		var next_cur = minf(cur + dash_len, dist)
		if drawing:
			draw_line(from + dir * cur, from + dir * next_cur, color, width)
		drawing = not drawing
		cur = next_cur


"""Calculates visible canvas Rect2 for viewport culling."""
func _get_visible_canvas_rect() -> Rect2:
	var top_left = (Vector2.ZERO - pan_offset) / zoom_scale
	var bottom_right = (size - pan_offset) / zoom_scale
	return Rect2(top_left, bottom_right - top_left)


# ==============================================================================
# EVENT LISTENERS
# ==============================================================================

func _on_widget_selected(focus_id: StringName) -> void:
	focus_clicked.emit(focus_id)
	_update_all_widgets()
	queue_redraw()


func _on_focus_progress(_id: StringName, _cur: float, _tot: float, _ratio: float) -> void:
	var w: FocusNodeWidget = widget_map.get(_id, null)
	if w:
		w.update_state()


func _on_focus_state_changed(_id: StringName) -> void:
	_update_all_widgets()
	queue_redraw()


func _on_focus_cancelled(_id: StringName, _reason: String) -> void:
	_update_all_widgets()
	queue_redraw()


func _on_focus_midway_triggered(_id: StringName, _threshold: float) -> void:
	_update_all_widgets()
	queue_redraw()


func _on_focus_pause_changed(_id: StringName, _reason: String = "") -> void:
	_update_all_widgets()


func _on_branch_replaced(_root_id: StringName) -> void:
	if manager and manager.current_tree:
		load_tree(manager.current_tree)


func _on_tree_swapped(_old: StringName, new_tree_id: StringName) -> void:
	if manager and manager.tree_registry.has(new_tree_id):
		load_tree(manager.tree_registry[new_tree_id])


func _update_all_widgets() -> void:
	for w in widget_map.values():
		if is_instance_valid(w):
			w.update_state()
