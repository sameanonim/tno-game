class_name FocusNodeWidget
extends Control

"""
FocusNodeWidget: Interactive UI component for a single focus in the TNO tree.
Displays focus icon, title, cost, running neon border shader when active,
and builds an rich BBCode tooltip containing requirements, description, and rewards.
"""

signal focus_selected(focus_id: StringName)

@export var node_data: FocusNodeData = null
@export var manager: FocusTreeManager = null

# Child UI Nodes
var bg_panel: ColorRect = null
var icon_rect: TextureRect = null
var title_label: Label = null
var progress_bar: ProgressBar = null
var cost_label: Label = null
var shader_mat: ShaderMaterial = null

# Visual State
var is_active: bool = false
var is_completed: bool = false
var is_available: bool = false
var is_locked: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(130, 110)
	size = custom_minimum_size
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND

	if title_label == null:
		_build_ui()
	if node_data:
		setup(node_data, manager)


func _build_ui() -> void:
	# Shader Material
	var shader = load("res://shaders/focus_perimeter_glow.gdshader") as Shader
	if shader:
		shader_mat = ShaderMaterial.new()
		shader_mat.shader = shader

	# Background Panel
	bg_panel = ColorRect.new()
	bg_panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg_panel.mouse_filter = MOUSE_FILTER_IGNORE
	if shader_mat:
		bg_panel.material = shader_mat
	else:
		bg_panel.color = Color(0.04, 0.08, 0.05, 0.9)
	add_child(bg_panel)

	# Main layout
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	vbox.offset_left = 6
	vbox.offset_right = -6
	vbox.offset_top = 4
	vbox.offset_bottom = -4
	vbox.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	# Icon
	icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(56, 56)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(icon_rect)

	# Title
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.max_lines_visible = 2
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.5, 1.0))
	title_label.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(title_label)

	# Progress Bar (visible only when active)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 4)
	progress_bar.show_percentage = false
	progress_bar.visible = false
	progress_bar.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(progress_bar)

	# Cost / Days Label
	cost_label = Label.new()
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 9)
	cost_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.5, 0.8))
	cost_label.mouse_filter = MOUSE_FILTER_IGNORE
	vbox.add_child(cost_label)


"""Initializes the widget with data and binds to manager."""
func setup(p_data: FocusNodeData, p_manager: FocusTreeManager) -> void:
	if title_label == null:
		_build_ui()

	node_data = p_data
	manager = p_manager

	if not node_data:
		return

	# Set texts
	var raw_title = String(node_data.text_id)
	var localized_title = tr(raw_title)
	if localized_title == raw_title and has_node("/root/LocalizationManager"):
		var lm = get_node("/root/LocalizationManager")
		if lm.has_method("get_text"):
			var custom_loc = lm.get_text(raw_title)
			if not custom_loc.is_empty():
				localized_title = custom_loc
	if localized_title != raw_title:
		title_label.text = localized_title
	else:
		title_label.text = raw_title.replace("_", " ").capitalize()
	cost_label.text = "%d Days" % int(node_data.cost)

	# Load icon
	var icon_tex: Texture2D = null
	if not node_data.icon_path.is_empty():
		if ResourceLoader.exists(node_data.icon_path):
			icon_tex = load(node_data.icon_path) as Texture2D
		elif has_node("/root/AssetRegistry"):
			icon_tex = get_node("/root/AssetRegistry").get_texture(node_data.icon_path)

	if icon_tex == null and has_node("/root/AssetRegistry"):
		var ar = get_node("/root/AssetRegistry")
		var candidates: Array[String] = [
			String(node_data.id),
			"GFX_" + String(node_data.id),
			"GFX_goal_" + String(node_data.id),
			"GFX_focus_" + String(node_data.id),
			String(node_data.text_id),
			"GFX_" + String(node_data.text_id)
		]
		for c in candidates:
			var t = ar.get_texture(c)
			if t != null:
				icon_tex = t
				break

	if icon_tex != null:
		icon_rect.texture = icon_tex
	else:
		var default_icon = load("res://icon.svg") as Texture2D
		if default_icon:
			icon_rect.texture = default_icon

	update_state()


"""Updates the widget visual presentation based on manager state."""
func update_state() -> void:
	if not node_data or not manager:
		return

	is_completed = manager.is_focus_completed(node_data.id)
	is_active = manager.is_focus_active(node_data.id)
	is_available = manager.can_start_focus(node_data.id)
	is_locked = not is_completed and not is_active and not is_available

	# Update Shader Uniforms
	if shader_mat:
		shader_mat.set_shader_parameter("is_active", is_active)
		shader_mat.set_shader_parameter("is_completed", is_completed)
		if is_completed:
			shader_mat.set_shader_parameter("border_color", Color(0.9, 0.75, 0.2, 1.0)) # Gold
		elif is_active:
			shader_mat.set_shader_parameter("border_color", Color(0.2, 0.9, 0.5, 1.0)) # Neon green
		elif is_available:
			shader_mat.set_shader_parameter("border_color", Color(0.3, 0.7, 0.8, 0.9)) # Cyan/blue
		else:
			shader_mat.set_shader_parameter("border_color", Color(0.3, 0.35, 0.3, 0.5)) # Dim grey

	# Progress Bar & Pause State
	if is_active and manager.active_focus_id == node_data.id:
		progress_bar.visible = true
		var ratio = manager.current_focus_progress_days / maxf(node_data.cost, 1.0)
		progress_bar.value = ratio * 100.0
		if manager.is_paused:
			cost_label.text = "[PAUSED] %d / %d Days" % [int(manager.current_focus_progress_days), int(node_data.cost)]
			cost_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1, 1.0))
			if shader_mat:
				shader_mat.set_shader_parameter("border_color", Color(1.0, 0.6, 0.1, 1.0))
		else:
			cost_label.text = "%d / %d Days" % [int(manager.current_focus_progress_days), int(node_data.cost)]
			cost_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.5, 0.8))
	else:
		progress_bar.visible = false
		cost_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.5, 0.8))
		if is_completed:
			cost_label.text = "COMPLETED"
		else:
			cost_label.text = "%d Days" % int(node_data.cost)

	# Label colors
	if is_completed:
		title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	elif is_active:
		if manager and manager.is_paused:
			title_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2, 1.0))
		else:
			title_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5, 1.0))
	elif is_available:
		title_label.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0, 1.0))
	else:
		title_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.5, 0.6))

	# Build Tooltip
	tooltip_text = build_rich_tooltip()


"""Generates rich BBCode formatted tooltip text."""
func build_rich_tooltip() -> String:
	if not node_data:
		return ""

	var b := []
	var title = String(node_data.text_id).replace("_", " ").capitalize()
	b.append("[b][color=yellow]%s[/color][/b]" % title)
	b.append("[color=gray]Duration: %d days[/color]\n" % int(node_data.cost))

	var desc = String(node_data.desc_id)
	if not desc.is_empty():
		b.append("[color=white]%s[/color]\n" % desc)

	# Point of No Return Warning
	if manager and manager.is_point_of_no_return(node_data.id):
		var pnr_warning = manager.get_point_of_no_return_warning(node_data.id)
		b.append("[b][color=red]⚠ POINT OF NO RETURN[/color][/b]")
		if not pnr_warning.is_empty():
			b.append("[color=orange]%s[/color]\n" % pnr_warning)
		else:
			b.append("[color=orange]Selecting this path locks out mutually exclusive alternatives permanently.[/color]\n")

	# Prerequisites
	if not node_data.prerequisites.is_empty():
		b.append("[b][color=cyan]Prerequisites:[/color][/b]")
		for group in node_data.prerequisites:
			var group_names := []
			var any_done := false
			for req_id in group:
				var is_done = manager and manager.is_focus_completed(StringName(req_id))
				if is_done:
					any_done = true
					group_names.append("[color=green]✔ %s[/color]" % String(req_id))
				else:
					group_names.append("[color=red]✘ %s[/color]" % String(req_id))
			b.append("  • " + " [color=gray]OR[/color] ".join(group_names))
		b.append("")

	# Mutually Exclusive
	if not node_data.mutually_exclusive.is_empty():
		b.append("[b][color=red]Mutually Exclusive with:[/color][/b]")
		for mut in node_data.mutually_exclusive:
			b.append("  • [color=orange]%s[/color]" % String(mut))
		b.append("")

	# Start Effects (Immediate)
	if not node_data.on_start_effects.is_empty():
		b.append("[b][color=orange]Start Effects (Immediate):[/color][/b]")
		for eff in node_data.on_start_effects:
			if eff:
				b.append("  • [color=yellow]%s[/color]: %s" % [String(eff.command), str(eff.args)])
		b.append("")

	# Rewards
	if not node_data.on_completion_effects.is_empty():
		b.append("[b][color=green]Completion Rewards:[/color][/b]")
		for eff in node_data.on_completion_effects:
			if eff:
				b.append("  • [color=yellow]%s[/color]: %s" % [String(eff.command), str(eff.args)])

	# Midway Rewards (TNO)
	if not node_data.tno_midway_effects.is_empty():
		b.append("[b][color=light_blue]Midway Rewards (50%):[/color][/b]")
		for th in node_data.tno_midway_effects.keys():
			var effs = node_data.tno_midway_effects[th]
			for eff in effs:
				if eff is ClausewitzInstruction:
					b.append("  • [color=yellow]%s[/color]: %s" % [String(eff.command), str(eff.args)])

	return "\n".join(b)



func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			focus_selected.emit(node_data.id)
			if manager and is_available and not is_active:
				manager.start_focus(node_data.id)
				update_state()
				accept_event()
