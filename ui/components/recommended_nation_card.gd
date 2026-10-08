class_name RecommendedNationCard
extends PanelContainer

##
## RecommendedNationCard: Карточка рекомендованной нации для карусели выбора театра TNO
##
## Отображает:
## - Флаг нации с металлизированной рамкой TNO
## - Тег и локализованное название державы
## - Миниатюру портрета стартового лидера в CRT-рамке
## - ФИО лидера и правящую идеологию
## - Статус контента («10 ЛЕТ КОНТЕНТА», «РЕГИОНАЛЬНЫЙ», «SKELETON» и др.)
## - Рейтинг сложности
##

signal card_selected(dossier: Dictionary)
signal card_hovered(dossier: Dictionary)

var dossier_data: Dictionary = {}
var is_selected: bool = false

@onready var btn_click: Button = $ClickButton
@onready var flag_rect: TextureRect = $Margin/VBox/HeaderHBox/FlagContainer/FlagRect
@onready var flag_overlay: TextureRect = $Margin/VBox/HeaderHBox/FlagContainer/FlagOverlay
@onready var lbl_country_name: Label = $Margin/VBox/HeaderHBox/CountryNameLabel
@onready var portrait_frame: LeaderPortraitFrame = $Margin/VBox/BodyHBox/PortraitFrame
@onready var lbl_leader_name: Label = $Margin/VBox/BodyHBox/MetaVBox/LeaderNameLabel
@onready var lbl_ideology: Label = $Margin/VBox/BodyHBox/MetaVBox/IdeologyLabel
@onready var lbl_status_badge: Label = $Margin/VBox/FooterHBox/StatusBadge
@onready var lbl_difficulty: Label = $Margin/VBox/FooterHBox/DifficultyLabel


func _ready() -> void:
	if btn_click != null:
		btn_click.pressed.connect(_on_card_pressed)
		btn_click.mouse_entered.connect(_on_card_hovered)
	_render_card()


func setup(data: Dictionary, selected: bool = false) -> void:
	dossier_data = data
	is_selected = selected
	_render_card()


func set_selected(selected: bool) -> void:
	is_selected = selected
	if portrait_frame != null:
		portrait_frame.set_selected(selected)
	_update_card_style()


func _render_card() -> void:
	if dossier_data.is_empty() or lbl_country_name == null:
		return

	var tag: String = str(dossier_data.get("tag", "UNK")).to_upper()
	var raw_name: String = str(dossier_data.get("name", tag))
	var leader_name: String = str(dossier_data.get("leader_name", "UNKNOWN"))
	var sub_ideo: String = str(dossier_data.get("sub_ideology", dossier_data.get("ideology", "DESPOTISM")))
	var diff: String = str(dossier_data.get("difficulty_rating", "●●●○○"))

	# Локализация
	var loc = get_node_or_null("/root/LocalizationManager")
	var loc_name := raw_name
	if loc != null:
		loc_name = loc.tr_key(tag, raw_name)
		var lead_id = str(dossier_data.get("primary_leader_id", ""))
		if not lead_id.is_empty():
			leader_name = loc.tr_key(lead_id, leader_name)
		else:
			leader_name = loc.tr_key(leader_name, leader_name)
		sub_ideo = loc.tr_key(sub_ideo, sub_ideo)

	# Заполнение текстовых полей
	lbl_country_name.text = "[%s] %s" % [tag, loc_name.to_upper()]
	lbl_leader_name.text = "► %s" % leader_name
	lbl_ideology.text = "│ %s" % sub_ideo.to_upper()
	lbl_difficulty.text = diff

	# Статус контента в TNO
	var content_status = _determine_content_status(tag, dossier_data)
	lbl_status_badge.text = "[ %s ]" % content_status

	# Флаг державы
	var flag_tex = TNOTheme.get_flag_texture(tag)
	if flag_rect != null and flag_tex != null:
		flag_rect.texture = flag_tex

	# Металлизированная гранжевая рамка флага
	if flag_overlay != null:
		var overlay_tex = TNOTheme.get_texture("res://assets/gfx/interface/flag_overlay_tno.png")
		if overlay_tex == null:
			overlay_tex = TNOTheme.get_texture("res://assets/gfx/interface/flag_overlay.png")
		if overlay_tex != null:
			flag_overlay.texture = overlay_tex

	# Портрет лидера в режиме миниатюры
	if portrait_frame != null:
		portrait_frame.mode = LeaderPortraitFrame.FrameMode.THUMBNAIL
		portrait_frame.display_leader(dossier_data, tag, false)
		portrait_frame.set_selected(is_selected)

	_update_card_style()


func _determine_content_status(tag: String, data: Dictionary) -> String:
	# Каноничные статусы контента оригинального TNO
	if tag in ["USA", "GER", "JAP", "ITA", "IBR", "ENG", "BRG", "GNG"]:
		return "10 YEARS CONTENT"
	if tag in ["SPE", "BOR", "GOR", "HEY"]:
		return "GCW CONTENDER"
	if tag in ["KOM", "OMS", "WRS", "SVR", "TOM", "NOV", "SBA", "BRY", "MAG", "VYT"]:
		return "10 YEARS CONTENT"
	if tag in ["SAM", "TYU", "IRK", "CHT", "KEM", "AMR", "PRM"]:
		return "REGIONAL CONTENT"
	if data.get("has_focus_tree", false):
		return "UNIQUE FOCUS TREE"
	return "SKELETON CONTENT"


func _update_card_style() -> void:
	var bg_col := Color(0.04, 0.07, 0.09, 0.94)
	var border_col := Color(0.14, 0.38, 0.36, 0.85)
	var status_col := Color(0.35, 0.85, 0.75)

	if is_selected:
		bg_col = Color(0.06, 0.18, 0.16, 0.98)
		border_col = Color(0.25, 0.98, 0.88, 1.0)
		status_col = Color(0.3, 1.0, 0.9)
		if lbl_country_name != null:
			lbl_country_name.add_theme_color_override("font_color", Color(0.35, 1.0, 0.95))
		if lbl_leader_name != null:
			lbl_leader_name.add_theme_color_override("font_color", Color(1.0, 0.90, 0.40))
	else:
		if lbl_country_name != null:
			lbl_country_name.add_theme_color_override("font_color", Color(0.85, 0.95, 0.95))
		if lbl_leader_name != null:
			lbl_leader_name.add_theme_color_override("font_color", Color(0.85, 0.80, 0.45))

	if lbl_status_badge != null:
		var st_text = lbl_status_badge.text
		if "10 YEARS" in st_text:
			status_col = Color(0.2, 0.95, 0.85)
		elif "GCW" in st_text:
			status_col = Color(1.0, 0.75, 0.25)
		elif "REGIONAL" in st_text:
			status_col = Color(0.4, 0.95, 0.6)
		else:
			status_col = Color(0.55, 0.65, 0.7)
		lbl_status_badge.add_theme_color_override("font_color", status_col)

	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.border_width_left = 2 if is_selected else 1
	sb.border_width_top = 2 if is_selected else 1
	sb.border_width_right = 2 if is_selected else 1
	sb.border_width_bottom = 2 if is_selected else 1
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	add_theme_stylebox_override("panel", sb)


func _on_card_pressed() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("click_default")
	card_selected.emit(dossier_data)


func _on_card_hovered() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_menu_over")
	card_hovered.emit(dossier_data)
