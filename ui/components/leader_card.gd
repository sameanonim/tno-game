class_name LeaderCard
extends PanelContainer

##
## LeaderCard: Интерактивная карточка досье лидера в ретро-стиле CRT
##
## Отображает мини-портрет в ЭЛТ-рамке, тег нации, лидера, идеологию,
## псевдографические шкалы промышленного потенциала (IC) и стабильности.
##

signal card_selected(data: Dictionary)
signal card_hovered(data: Dictionary)

var leader_data: Dictionary = {}
var is_selected: bool = false

@onready var btn_click: Button = $Button
@onready var portrait_frame: LeaderPortraitFrame = get_node_or_null("Margin/HBox/PortraitFrame")
@onready var lbl_header: Label = $Margin/HBox/VBox/HeaderLabel
@onready var lbl_sub: Label = $Margin/HBox/VBox/SubLabel
@onready var lbl_bars: Label = $Margin/HBox/VBox/BarsLabel
@onready var lbl_diff: Label = $Margin/HBox/VBox/DiffLabel


func setup(data: Dictionary, selected: bool = false) -> void:
	leader_data = data
	is_selected = selected
	_render_ui()


func _ready() -> void:
	if btn_click != null:
		btn_click.pressed.connect(_on_card_pressed)
		btn_click.mouse_entered.connect(_on_card_hovered)
	_render_ui()


func set_selected(selected: bool) -> void:
	is_selected = selected
	if portrait_frame != null:
		portrait_frame.set_selected(selected)
	_update_style()


func _render_ui() -> void:
	if leader_data.is_empty() or lbl_header == null:
		return

	var tag = leader_data.get("tag", "UNK")
	var leader = leader_data.get("leader_name", "UNKNOWN")
	var sub_ideo = leader_data.get("sub_ideology", leader_data.get("ideology", "MILITARY"))
	var ic = leader_data.get("starting_factories", 20)
	var diff = leader_data.get("difficulty_rating", "●●●○○")

	var loc = get_node_or_null("/root/LocalizationManager")
	var stab_str = "СТАБ" if loc == null else loc.tr_key("HUD_STABILITY_LABEL", "СТАБ")
	var diff_str = "СЛОЖНОСТЬ" if loc == null else loc.tr_key("DOSSIER_DIFFICULTY", "СЛОЖНОСТЬ")
	if loc != null:
		var lead_id = str(leader_data.get("primary_leader_id", ""))
		if not lead_id.is_empty():
			leader = loc.tr_key(lead_id, leader)
		sub_ideo = loc.tr_key(sub_ideo, sub_ideo)

	lbl_header.text = "┌─ [%s] %s" % [tag, leader.to_upper()]
	lbl_sub.text = "│ %s" % sub_ideo
	lbl_bars.text = "│ IC: %s (%d) | %s: 65%%" % [_make_ascii_bar(ic, 80), ic, stab_str]
	lbl_diff.text = "└─ %s: %s" % [diff_str, diff]


	if portrait_frame != null:
		portrait_frame.mode = LeaderPortraitFrame.FrameMode.THUMBNAIL
		portrait_frame.display_leader(leader_data, tag, false)
		portrait_frame.set_selected(is_selected)

	_update_style()


func _update_style() -> void:
	var bg_col = Color(0.03, 0.06, 0.05, 0.95)
	var border_col = Color(0.18, 0.45, 0.38, 0.7)

	if is_selected:
		bg_col = Color(0.05, 0.16, 0.12, 0.98)
		border_col = Color(0.25, 0.95, 0.85, 0.95)
		if lbl_header != null:
			lbl_header.add_theme_color_override("font_color", Color(0.3, 1.0, 0.9))
	else:
		if lbl_header != null:
			lbl_header.add_theme_color_override("font_color", Color(0.25, 0.85, 0.55))

	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	add_theme_stylebox_override("panel", sb)


func _make_ascii_bar(value: int, max_val: int) -> String:
	var slots = 5
	var filled = clampi(int(round((float(value) / float(max_val)) * slots)), 0, slots)
	var s = "["
	for i in range(slots):
		s += "█" if i < filled else "░"
	s += "]"
	return s


func _on_card_pressed() -> void:
	card_selected.emit(leader_data)


func _on_card_hovered() -> void:
	if portrait_frame != null:
		portrait_frame.play_glitch_burst(0.12, 0.15)
	card_hovered.emit(leader_data)
