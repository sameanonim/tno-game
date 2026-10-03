class_name FocusTreePreviewWidget
extends PanelContainer

##
## FocusTreePreviewWidget: Превью древа национальных директив TNO
##
## Отображает метаданные фокусного древа выбранной страны:
## - Заголовок и статус древа (число директив, категории)
## - Карточки стартовых национальных директив
## - Сюжетный брифинг в стиле военного терминала 1960-х
##

@onready var lbl_header: Label = $VBox/HeaderHBox/TreeTitle
@onready var lbl_badge: Label = $VBox/HeaderHBox/DirectivesBadge
@onready var categories_container: HBoxContainer = $VBox/CategoriesHBox
@onready var starters_container: VBoxContainer = $VBox/StartersList
@onready var empty_state_label: Label = $VBox/EmptyStateLabel

var current_tag: String = ""


func _ready() -> void:
	if has_node("/root/LocalizationManager"):
		var loc = get_node("/root/LocalizationManager")
		if not loc.locale_changed.is_connected(_on_locale_changed):
			loc.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_loc: String) -> void:
	if not current_tag.is_empty():
		display_focus_tree(current_tag)


##
## Загружает и визуализирует резюме древа директив для указанного тега
##
func display_focus_tree(country_tag: String) -> void:
	current_tag = country_tag.to_upper().strip_edges()

	var session = null
	if has_node("/root/GameSession"):
		session = get_node("/root/GameSession")

	var summary := {}
	if session != null and session.has_method("get_focus_tree_summary"):
		summary = session.get_focus_tree_summary(current_tag)

	var has_tree = summary.get("has_tree", false)

	if not has_tree:
		_show_empty_state()
		return

	empty_state_label.visible = false
	lbl_header.visible = true
	lbl_badge.visible = true
	categories_container.visible = true
	starters_container.visible = true

	var loc = get_node_or_null("/root/LocalizationManager")
	var l_directives = loc.tr_key("UNIT_DIRECTIVES", "директив") if loc != null else "директив"
	var l_tree = loc.tr_key("FOCUS_TREE", "НАЦИОНАЛЬНЫЕ ДИРЕКТИВЫ") if loc != null else "НАЦИОНАЛЬНЫЕ ДИРЕКТИВЫ"

	var title = summary.get("tree_title", l_tree)
	if loc != null:
		title = loc.tr_key(title, title)
	lbl_header.text = "⚡ %s" % title.to_upper()

	var total_dirs = summary.get("total_directives", 0)
	lbl_badge.text = "[ %d %s ]" % [total_dirs, l_directives]

	# Категории
	for c in categories_container.get_children():
		c.queue_free()

	var cats = summary.get("categories", [])
	for cat in cats:
		var cat_lbl := Label.new()
		var cat_name = str(cat).to_upper()
		if loc != null:
			cat_name = loc.tr_key("CAT_" + cat_name, cat_name)
		cat_lbl.text = "[%s]" % cat_name
		cat_lbl.add_theme_color_override("font_color", Color(0.3, 0.85, 0.75, 1.0))
		cat_lbl.add_theme_font_size_override("font_size", 10)
		categories_container.add_child(cat_lbl)

	# Стартовые директивы
	for c in starters_container.get_children():
		c.queue_free()

	var starters = summary.get("starting_directives", [])
	if starters.is_empty():
		var no_starters := Label.new()
		no_starters.text = tr("└─ Стартовые директивы инициализируются на 1 ходу")
		no_starters.add_theme_color_override("font_color", Color(0.4, 0.65, 0.55))
		no_starters.add_theme_font_size_override("font_size", 10)
		starters_container.add_child(no_starters)
	else:
		for d in starters:
			var card = _create_mini_directive_card(d)
			starters_container.add_child(card)


func _create_mini_directive_card(d: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.08, 0.85)
	style.border_width_left = 2
	style.border_color = Color(0.20, 0.85, 0.65, 0.9)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var top_row := HBoxContainer.new()
	var symbol_lbl := Label.new()
	symbol_lbl.text = d.get("icon_symbol", "[★]")
	symbol_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35, 1.0))
	symbol_lbl.add_theme_font_size_override("font_size", 11)
	top_row.add_child(symbol_lbl)

	var loc = get_node_or_null("/root/LocalizationManager")
	var d_title = d.get("title", "")
	if loc != null and not d_title.is_empty():
		d_title = loc.tr_key(d_title, d_title)

	var title_lbl := Label.new()
	title_lbl.text = " " + d_title
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 0.90, 1.0))
	title_lbl.add_theme_font_size_override("font_size", 11)
	top_row.add_child(title_lbl)

	var turns = d.get("turns_required", 1)
	var turns_lbl := Label.new()
	var l_turn = loc.tr_key("TURN_UNIT", "ход") if loc != null else "ход"
	turns_lbl.text = "%d %s" % [turns, l_turn]
	turns_lbl.add_theme_color_override("font_color", Color(0.4, 0.75, 0.65))
	turns_lbl.add_theme_font_size_override("font_size", 10)
	top_row.add_child(turns_lbl)

	vbox.add_child(top_row)

	var desc = d.get("description", "")
	if not desc.is_empty():
		if loc != null:
			desc = loc.tr_key(desc, desc)
		var desc_lbl := Label.new()
		var short_desc = desc.split("\n")[0]
		if short_desc.length() > 95:
			short_desc = short_desc.substr(0, 92) + "..."
		desc_lbl.text = short_desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_color_override("font_color", Color(0.45, 0.65, 0.58))
		desc_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(desc_lbl)

	panel.add_child(vbox)
	return panel


func _show_empty_state() -> void:
	empty_state_label.visible = true
	lbl_header.visible = false
	lbl_badge.visible = false
	categories_container.visible = false
	starters_container.visible = false

	var loc = get_node_or_null("/root/LocalizationManager")
	if loc != null:
		empty_state_label.text = loc.tr_key("NO_FOCUS_TREE_NOTICE", "[!] УНИКАЛЬНОЕ ДРЕВО ДИРЕКТИВ ОТСУТСТВУЕТ // СТАНДАРТНЫЙ ПРОФИЛЬ УПРАВЛЕНИЯ")
	else:
		empty_state_label.text = tr("[!] УНИКАЛЬНОЕ ДРЕВО ДИРЕКТИВ ОТСУТСТВУЕТ // СТАНДАРТНЫЙ ПРОФИЛЬ УПРАВЛЕНИЯ")
