class_name PoliticsPanel
extends PanelContainer

##
## PoliticsPanel: Полноценное окно внутренней политики в стиле TNO (SG Politics)
##
## Включает:
## - Досье и фотопортрет верховного лидера в рамке pol_leader_frame
## - Круговую диаграмму баланса идеологий с оригинальным оверлеем pol_piechart_overlay
## - Иконку суб-идеологии из базы ассетов TNO
## - Сетку национальных духов режима (National Spirits)
## - Интерактивную матрицу законов и структуры общества (Societal Laws) с диалогами реформ
## - Кнопку доступа к законодательному органу (Конгресс, Рейхстаг, Верховный Совет, Парламент)
##

signal closed()
signal law_reformed(result: Dictionary)

const GEN_PARLIAMENT_SCENE = preload("res://ui/screens/general_parliament_screen.tscn")
const US_CONGRESS_SCENE = preload("res://ui/screens/usa/us_congress_screen.tscn")

@onready var btn_close: Button = $VBox/HeaderHBox/CloseButton
@onready var lbl_header_title: Label = $VBox/HeaderHBox/TitleLabel

# Досье лидера
@onready var portrait_frame: LeaderPortraitFrame = $VBox/ContentHBox/LeftCol/LeaderSection/LeaderPortraitFrame
@onready var lbl_leader_name: Label = $VBox/ContentHBox/LeftCol/LeaderSection/LeaderNameLabel
@onready var lbl_leader_title: Label = $VBox/ContentHBox/LeftCol/LeaderSection/LeaderTitleLabel

# Идеология
@onready var ideology_icon_rect: TextureRect = $VBox/ContentHBox/LeftCol/IdeologySection/HBox/IdeologyIcon
@onready var lbl_ruling_party: Label = $VBox/ContentHBox/LeftCol/IdeologySection/HBox/VBox/PartyNameLabel
@onready var lbl_sub_ideology: Label = $VBox/ContentHBox/LeftCol/IdeologySection/HBox/VBox/SubIdeologyLabel
@onready var pie_chart_control: Control = $VBox/ContentHBox/LeftCol/IdeologySection/PieChartBox/PieChartDraw
@onready var lbl_legend: RichTextLabel = $VBox/ContentHBox/LeftCol/IdeologySection/PieChartBox/LegendLabel

# Национальные духи (National Spirits)
@onready var spirits_container: HBoxContainer = $VBox/ContentHBox/RightCol/SpiritsSection/SpiritsScroll/SpiritsHBox

# Матрица законов (Societal Development)
@onready var laws_vbox: VBoxContainer = $VBox/ContentHBox/RightCol/LawsSection/LawsVBox

var current_state: CountryState = null
var btn_legislature: Button = null
var active_reform_modal: Control = null


func _ready() -> void:
	_apply_tno_styling()
	if btn_close != null:
		btn_close.pressed.connect(func():
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("window_close")
			if active_reform_modal != null and is_instance_valid(active_reform_modal):
				active_reform_modal.queue_free()
				active_reform_modal = null
			visible = false
			closed.emit()
		)
	if pie_chart_control != null:
		pie_chart_control.draw.connect(_on_pie_chart_draw)
	if portrait_frame != null:
		portrait_frame.portrait_clicked.connect(func():
			portrait_frame.play_glitch_burst(0.2, 0.25)
		)



func _tr(key: String, default_text: String) -> String:
	if is_inside_tree() and get_tree().root.has_node("LocalizationManager"):
		var loc = get_tree().root.get_node("LocalizationManager")
		return loc.tr_key(key, default_text)
	var translated = TranslationServer.translate(key)
	if translated != key and not translated.is_empty():
		return translated
	return default_text


func _apply_tno_styling() -> void:
	TNOTheme.apply_panel_style(self, TNOTheme.COLOR_BORDER_CYAN, TNOTheme.COLOR_BG_DARK)
	if btn_close != null:
		TNOTheme.apply_button_style(btn_close, TNOTheme.COLOR_BORDER_AMBER, Color(0.1, 0.05, 0.05, 0.9))


func display_country(state: CountryState) -> void:
	current_state = state
	if current_state == null:
		return

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("window_open")

	# Гарантия наличия аутентичных законов TNO
	current_state.ensure_default_societal_laws()

	# Заголовок
	var c_name = state.country_name
	if is_inside_tree() and get_tree().root.has_node("LocalizationManager"):
		var loc = get_tree().root.get_node("LocalizationManager")
		c_name = loc.tr_key(state.country_tag, state.country_name)
	if lbl_header_title != null:
		var hdr_fmt = _tr("TNO_POL_HEADER_TITLE", "ГОСУДАРСТВЕННЫЙ АППАРАТ И ПОЛИТИКА // %s (%s)")
		lbl_header_title.text = hdr_fmt % [c_name.to_upper(), state.country_tag]

	# Лидер
	var l_name = state.leader_name if not state.leader_name.is_empty() else "UNKNOWN"
	if state.head_of_state != null and not state.head_of_state.leader_name.is_empty():
		l_name = state.head_of_state.leader_name
	if lbl_leader_name != null:
		lbl_leader_name.text = str(l_name).to_upper()

	var l_title = state.leader_title
	if state.head_of_state != null and not state.head_of_state.leader_title.is_empty():
		l_title = state.head_of_state.leader_title
	if l_title.is_empty():
		l_title = _tr("TNO_POL_DEFAULT_HEAD_TITLE", "Глава государства")
	if lbl_leader_title != null:
		lbl_leader_title.text = str(l_title)

	var party = state.ruling_party if not state.ruling_party.is_empty() else (state.ruling_ideology if not state.ruling_ideology.is_empty() else "Authoritarian Socialism")

	if portrait_frame != null:
		if state.head_of_state != null:
			portrait_frame.display_leader(state.head_of_state, state.country_tag, true)
		else:
			portrait_frame.display_leader(state, state.country_tag, true)
		var bio := ""
		if "leader_description" in state and not str(state.leader_description).is_empty():
			bio = str(state.leader_description)
		if state.head_of_state != null and "description" in state.head_of_state and not str(state.head_of_state.description).is_empty():
			bio = str(state.head_of_state.description)
		if bio.is_empty():
			var canonical = CountryDossierProvider.get_country_dossier(state.country_tag)
			bio = canonical.get("briefing", canonical.get("lore", "Верховный лидер и глава государства."))
		portrait_frame.tooltip_text = "┌── [%s // %s] ──\n│ ТИТУЛ: %s\n│ ИДЕОЛОГИЯ: %s\n├─────────────────────────────────────────\n│ БИОГРАФИЯ И СТРАТЕГИЧЕСКИЙ ПРОФИЛЬ:\n%s" % [
			l_name, state.country_tag, l_title, party, bio
		]


	# Идеология
	var ideo_key = str(party).to_lower()
	var ideo_tex = TNOTheme.get_ideology_icon(ideo_key)
	if ideology_icon_rect != null and ideo_tex != null:
		ideology_icon_rect.texture = ideo_tex

	if lbl_ruling_party != null:
		lbl_ruling_party.text = str(party).to_upper()
	var sub_ideo = state.sub_ideology if not state.sub_ideology.is_empty() else party
	if lbl_sub_ideology != null:
		lbl_sub_ideology.text = sub_ideo.to_upper()

	if pie_chart_control != null:
		pie_chart_control.queue_redraw()
	_update_pie_chart_legend()

	# Национальные духи
	_populate_national_spirits()

	# Кабинет министров
	_populate_cabinet_members()

	# Матрица законов
	_populate_societal_laws()

	# Кнопка Законодательного Органа (Парламент / Рейхстаг / Верховный Совет / Конгресс)
	_setup_legislature_button()


# ==============================================================================
# ЗАКОНОДАТЕЛЬНЫЙ ОРГАН (LEGISLATURE BUTTON)
# ==============================================================================

func _setup_legislature_button() -> void:
	if current_state == null:
		if btn_legislature != null: btn_legislature.visible = false
		return

	var tag = current_state.country_tag.to_upper()
	var btn_title = _tr("TNO_POL_BTN_PARLIAMENT", "[ 🏛 ПАРЛАМЕНТ ]")
	if tag == "USA":
		btn_title = _tr("TNO_POL_BTN_US_CONGRESS", "[ 🏛 КОНГРЕСС И ВЫБОРЫ США ]")
	elif tag in ["GER", "SPE", "BOR", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]:
		btn_title = _tr("TNO_POL_BTN_REICHSTAG", "[ 🏛 РЕЙХСТАГ ВЕЛИКОЙ ГЕРМАНИИ ]")
	elif RussianUnificationManager.is_warlord(tag) or tag in ["RUS", "SOV", "WRS", "KOM", "SAM", "VYT", "OMS", "IRK"]:
		btn_title = _tr("TNO_POL_BTN_SOVIET", "[ 🏛 ВЕРХОВНЫЙ СОВЕТ / ДУМА ]")

	if btn_legislature == null:
		btn_legislature = Button.new()
		btn_legislature.custom_minimum_size = Vector2(250, 28)
		TNOTheme.apply_button_style(btn_legislature, TNOTheme.COLOR_BORDER_CYAN, Color(0.05, 0.15, 0.15, 0.95))
		btn_legislature.pressed.connect(_on_open_legislature)
		var header = get_node_or_null("VBox/HeaderHBox")
		if header != null:
			header.add_child(btn_legislature)
			header.move_child(btn_legislature, header.get_child_count() - 2)

	btn_legislature.text = btn_title
	btn_legislature.visible = true


func _on_open_legislature() -> void:
	if current_state == null:
		return
	var tag = current_state.country_tag.to_upper()
	if tag == "USA":
		var cong = US_CONGRESS_SCENE.instantiate()
		get_tree().root.add_child(cong)
		cong.setup(current_state)
		cong.closed.connect(func():
			cong.queue_free()
			if current_state != null:
				display_country(current_state)
		)
	else:
		var parl = GEN_PARLIAMENT_SCENE.instantiate()
		get_tree().root.add_child(parl)
		parl.setup(current_state)
		parl.vote_passed.connect(func(_bill_id: String, _effects: Dictionary):
			if current_state != null:
				display_country(current_state)
		)
		parl.closed.connect(func():
			parl.queue_free()
			if current_state != null:
				display_country(current_state)
		)


func _update_pie_chart_legend() -> void:
	if lbl_legend == null or current_state == null:
		return
		
	var text := ""
	for p in current_state.initial_parties:
		var hex = p.color.to_html(false)
		text += "[color=#%s]■[/color] %s (%.1f%%)\n" % [hex, p.party_name, p.popularity]
		
	lbl_legend.bbcode_enabled = true
	lbl_legend.text = text


func _populate_national_spirits() -> void:
	if spirits_container == null:
		return
	for c in spirits_container.get_children():
		spirits_container.remove_child(c)
		c.queue_free()

	if current_state == null:
		return

	var spirits = current_state.national_spirits
	for sp in spirits:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(170, 70)
		var sp_name = str(sp.get("name", _tr("TNO_POL_SPIRIT_DEFAULT", "Национальный дух")))
		var sp_desc = str(sp.get("desc", ""))
		panel.tooltip_text = "%s\n\n%s" % [sp_name, sp_desc]
		
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.09, 0.12, 0.95)
		sb.border_color = TNOTheme.COLOR_BORDER_DIM
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(1)
		panel.add_theme_stylebox_override("panel", sb)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		panel.add_child(hbox)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_path: String = str(sp.get("icon", ""))
		var sp_id: String = str(sp.get("id", ""))
		var tex: Texture2D = null
		if has_node("/root/AssetRegistry"):
			var ar = get_node("/root/AssetRegistry")
			if not sp_id.is_empty():
				tex = ar.get_idea_icon(sp_id)
			if tex == null and not icon_path.is_empty():
				tex = ar.get_texture(icon_path)
		if tex == null:
			tex = TNOTheme.get_texture(icon_path if not icon_path.is_empty() else "res://assets/gfx/interface/war_support_icon.png")
		icon.texture = tex
		hbox.add_child(icon)

		var lbl := Label.new()
		lbl.text = sp_name
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_PRIMARY)
		hbox.add_child(lbl)

		spirits_container.add_child(panel)


func _populate_cabinet_members() -> void:
	if current_state == null:
		return

	var right_col = get_node_or_null("VBox/ContentHBox/RightCol")
	if right_col == null:
		return

	var cabinet_section = right_col.get_node_or_null("CabinetSection")
	if cabinet_section == null:
		cabinet_section = VBoxContainer.new()
		cabinet_section.name = "CabinetSection"
		cabinet_section.add_theme_constant_override("separation", 6)
		var laws_sec = right_col.get_node_or_null("LawsSection")
		if laws_sec != null:
			right_col.add_child(cabinet_section)
			right_col.move_child(cabinet_section, laws_sec.get_index())
		else:
			right_col.add_child(cabinet_section)

	for c in cabinet_section.get_children():
		cabinet_section.remove_child(c)
		c.queue_free()

	var title_lbl := Label.new()
	title_lbl.text = _tr("TNO_POL_CABINET_TITLE", "КАБИНЕТ МИНИСТРОВ И СОВЕТНИКИ")
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_CYAN)
	cabinet_section.add_child(title_lbl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 92)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cabinet_section.add_child(scroll)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	scroll.add_child(hbox)

	var members = current_state.cabinet_members
	if members.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = _tr("TNO_POL_CABINET_EMPTY", "[ КАБИНЕТ НЕ СФОРМИРОВАН / ВАКАНТНО ]")
		empty_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_MUTED)
		empty_lbl.add_theme_font_size_override("font_size", 11)
		hbox.add_child(empty_lbl)
		return

	var fallback_tex = preload("res://icon.svg")

	for m in members:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(210, 80)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.08, 0.09, 0.95)
		sb.border_color = TNOTheme.COLOR_BORDER_DIM
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		card.add_theme_stylebox_override("panel", sb)

		var chbox := HBoxContainer.new()
		chbox.add_theme_constant_override("separation", 8)
		card.add_child(chbox)

		# Портрет министра в рамке
		var port_tex: Texture2D = null
		if not m.portrait_path.is_empty() and m.portrait_path != "res://icon.svg":
			port_tex = TNOTheme.get_texture(m.portrait_path)

		var img_rect := TextureRect.new()
		img_rect.custom_minimum_size = Vector2(50, 68)
		img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img_rect.texture = port_tex if port_tex != null else fallback_tex
		chbox.add_child(img_rect)

		var mvbox := VBoxContainer.new()
		mvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mvbox.add_theme_constant_override("separation", 2)
		chbox.add_child(mvbox)

		var m_role_lbl := Label.new()
		m_role_lbl.text = m.title.to_upper() if not m.title.is_empty() else "МИНИСТР"
		m_role_lbl.add_theme_font_size_override("font_size", 9)
		m_role_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_AMBER)
		mvbox.add_child(m_role_lbl)

		var m_name_lbl := Label.new()
		m_name_lbl.text = m.leader_name
		m_name_lbl.add_theme_font_size_override("font_size", 11)
		m_name_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_PRIMARY)
		m_name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mvbox.add_child(m_name_lbl)

		var m_stat_lbl := Label.new()
		var loc = get_node_or_null("/root/LocalizationManager")
		var stat_tmpl = loc.tr_key("POL_CABINET_STAT", "Влияние: %d%% | Лоял: %d%%") if loc != null else "Влияние: %d%% | Лоял: %d%%"
		m_stat_lbl.text = stat_tmpl % [int(m.cabinet_influence), int(m.loyalty)]
		m_stat_lbl.add_theme_font_size_override("font_size", 9)
		m_stat_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_MUTED)
		mvbox.add_child(m_stat_lbl)

		card.tooltip_text = "┌── [ЧЛЕН КАБИНЕТА // CABINET MEMBER] ──\n│ ДОЛЖНОСТЬ: %s\n│ МИНИСТР: %s\n│ ВЛИЯНИЕ: %d%% | ЛОЯЛЬНОСТЬ: %d%%\n├─────────────────────────────────────────\n│ СТРАТЕГИЧЕСКИЙ ПРОФИЛЬ:\n%s" % [
			m.title if not m.title.is_empty() else m.role_type,
			m.leader_name,
			int(m.cabinet_influence),
			int(m.loyalty),
			m.description if not m.description.is_empty() else "Исполняет ключевые обязанности в правительстве."
		]

		hbox.add_child(card)


# ==============================================================================
# МАТРИЦА ЗАКОНОВ И ИНТЕРАКТИВНЫЕ РЕФОРМЫ
# ==============================================================================

func _populate_societal_laws() -> void:
	if laws_vbox == null:
		return
	for c in laws_vbox.get_children():
		laws_vbox.remove_child(c)
		c.queue_free()

	if current_state == null:
		return

	var laws = current_state.societal_laws
	for law_idx in range(laws.size()):
		var law = laws[law_idx]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var max_t = float(law.get("max_tier", 5))
		var cur_t = float(law.get("tier", 1))

		# Интерактивная плашка закона: клик открывает диалог реформы
		var btn_law_card := Button.new()
		var law_fmt = _tr("TNO_POL_LAW_FMT", "⚖ %s: %s [Ур. %d/%d]")
		btn_law_card.text = law_fmt % [str(law.get("name")), str(law.get("value")), int(cur_t), int(max_t)]
		btn_law_card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn_law_card.custom_minimum_size = Vector2(280, 24)
		btn_law_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_law_card.tooltip_text = _tr("TNO_POL_LAW_TOOLTIP", "Нажмите для подробного досье закона и выбора ветки реформ.")
		TNOTheme.apply_button_style(btn_law_card, TNOTheme.COLOR_BORDER_CYAN, Color(0.05, 0.08, 0.10, 0.90))
		var c_idx = law_idx
		btn_law_card.pressed.connect(func():
			_open_law_reform_dialog(c_idx)
		)
		row.add_child(btn_law_card)

		# Шкала прогресса
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(75, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.min_value = 0
		bar.max_value = max_t
		bar.value = cur_t
		bar.show_percentage = false

		var sb_fill = StyleBoxFlat.new()
		sb_fill.bg_color = TNOTheme.COLOR_BORDER_CYAN
		bar.add_theme_stylebox_override("fill", sb_fill)

		var sb_bg = StyleBoxFlat.new()
		sb_bg.bg_color = Color(0.04, 0.06, 0.08, 0.9)
		sb_bg.border_color = TNOTheme.COLOR_BORDER_DIM
		sb_bg.set_border_width_all(1)
		bar.add_theme_stylebox_override("background", sb_bg)
		row.add_child(bar)

		# Кнопка повышения уровня (Реформа)
		var btn_up := Button.new()
		btn_up.text = _tr("TNO_POL_BTN_REFORM", "▲ РЕФОРМА")
		btn_up.custom_minimum_size = Vector2(95, 24)
		btn_up.tooltip_text = _tr("TNO_POL_BTN_REFORM_TIP", "Инициировать государственную реформу закона.\nСтоимость: 20 PC, 1 CAP.")
		var can_up = (cur_t < max_t) and (current_state.political_capital >= 20.0) and (current_state.current_cap >= 1)
		btn_up.disabled = not can_up
		TNOTheme.apply_button_style(btn_up, TNOTheme.COLOR_BORDER_CYAN, Color(0.05, 0.14, 0.16, 0.95))
		btn_up.pressed.connect(func():
			var res = SocietalLawsManager.enact_law_reform(current_state, c_idx, 1, 20.0, 1)
			if res.get("success", false):
				law_reformed.emit(res)
				display_country(current_state)
		)
		row.add_child(btn_up)

		# Кнопка отката
		var btn_down := Button.new()
		btn_down.text = "▼"
		btn_down.custom_minimum_size = Vector2(26, 24)
		btn_down.tooltip_text = _tr("TNO_POL_BTN_ROLLBACK_TIP", "Свернуть реформу / сократить расходы.\nСтоимость: 15 PC, 1 CAP.")
		var can_down = (cur_t > 1) and (current_state.political_capital >= 15.0) and (current_state.current_cap >= 1)
		btn_down.disabled = not can_down
		TNOTheme.apply_button_style(btn_down, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.08, 0.05, 0.9))
		btn_down.pressed.connect(func():
			var res = SocietalLawsManager.enact_law_reform(current_state, c_idx, -1, 15.0, 1)
			if res.get("success", false):
				law_reformed.emit(res)
				display_country(current_state)
		)
		row.add_child(btn_down)

		laws_vbox.add_child(row)


func _open_law_reform_dialog(law_idx: int) -> void:
	if current_state == null or law_idx < 0 or law_idx >= current_state.societal_laws.size():
		return

	if active_reform_modal != null and is_instance_valid(active_reform_modal):
		active_reform_modal.queue_free()
		active_reform_modal = null

	var law = current_state.societal_laws[law_idx]
	var law_name = str(law.get("name", _tr("TNO_POL_DEFAULT_LAW_NAME", "Закон")))
	var cur_tier = int(law.get("tier", 1))
	var max_tier = int(law.get("max_tier", 5))

	var modal := PanelContainer.new()
	modal.custom_minimum_size = Vector2(440, 320)
	modal.anchors_preset = Control.PRESET_CENTER
	modal.offset_left = -220
	modal.offset_top = -160
	modal.offset_right = 220
	modal.offset_bottom = 160
	TNOTheme.apply_panel_style(modal, TNOTheme.COLOR_BORDER_CYAN, Color(0.04, 0.07, 0.09, 0.98))

	var mvbox := VBoxContainer.new()
	mvbox.add_theme_constant_override("separation", 10)
	modal.add_child(mvbox)

	# Заголовок модала
	var mh_box := HBoxContainer.new()
	var mtitle := Label.new()
	mtitle.text = _tr("TNO_POL_REFORM_TITLE_PREFIX", "РЕФОРМА: ") + law_name.to_upper()
	mtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mtitle.add_theme_font_size_override("font_size", 13)
	mtitle.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_CYAN)
	mh_box.add_child(mtitle)

	var btn_mclose := Button.new()
	btn_mclose.text = "✕"
	btn_mclose.custom_minimum_size = Vector2(26, 26)
	TNOTheme.apply_button_style(btn_mclose, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.05, 0.05, 0.9))
	btn_mclose.pressed.connect(func():
		modal.queue_free()
	)
	mh_box.add_child(btn_mclose)
	mvbox.add_child(mh_box)

	# Текущее состояние и шкала
	var cur_status_lbl := Label.new()
	var status_fmt = _tr("TNO_POL_CUR_STATUS_FMT", "ТЕКУЩИЙ СТАТУС: УРОВЕНЬ %d ИЗ %d // %s")
	cur_status_lbl.text = status_fmt % [cur_tier, max_tier, str(law.get("value"))]
	cur_status_lbl.add_theme_font_size_override("font_size", 11)
	cur_status_lbl.add_theme_color_override("font_color", TNOTheme.COLOR_BORDER_AMBER)
	mvbox.add_child(cur_status_lbl)

	# Справочник ступеней закона (Специфика TNO)
	var tiers_desc := RichTextLabel.new()
	tiers_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tiers_desc.bbcode_enabled = true
	tiers_desc.text = _generate_law_tiers_bbcode(law_name, cur_tier)
	mvbox.add_child(tiers_desc)

	# Информация о цене и эффектах
	var meta_cost := Label.new()
	meta_cost.text = _tr("TNO_POL_REFORM_COST_INFO", "СТОИМОСТЬ РЕФОРМЫ: 20 PC, 1 CAP | ЭФФЕКТ: +2.5 Легитимность, -3.0 Радикализация, +12 Институты")
	meta_cost.add_theme_font_size_override("font_size", 10)
	meta_cost.add_theme_color_override("font_color", TNOTheme.COLOR_TEXT_MUTED)
	mvbox.add_child(meta_cost)

	# Кнопки действий
	var act_hbox := HBoxContainer.new()
	act_hbox.add_theme_constant_override("separation", 10)

	var b_enact := Button.new()
	b_enact.text = _tr("TNO_POL_BTN_ENACT_REFORM", "[ ▲ ПРИНЯТЬ РЕФОРМУ ЗАКОНА ]")
	b_enact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_enact.custom_minimum_size = Vector2(0, 30)
	var can_e = (cur_tier < max_tier) and (current_state.political_capital >= 20.0) and (current_state.current_cap >= 1)
	b_enact.disabled = not can_e
	TNOTheme.apply_button_style(b_enact, TNOTheme.COLOR_BORDER_CYAN, Color(0.06, 0.14, 0.16, 0.95))
	b_enact.pressed.connect(func():
		var res = SocietalLawsManager.enact_law_reform(current_state, law_idx, 1, 20.0, 1)
		modal.queue_free()
		if res.get("success", false):
			law_reformed.emit(res)
			display_country(current_state)
	)
	act_hbox.add_child(b_enact)

	var b_rollback := Button.new()
	b_rollback.text = _tr("TNO_POL_BTN_DEREGULATION", "[ ▼ ДЕРЕГУЛЯЦИЯ ]")
	b_rollback.custom_minimum_size = Vector2(140, 30)
	var can_r = (cur_tier > 1) and (current_state.political_capital >= 15.0) and (current_state.current_cap >= 1)
	b_rollback.disabled = not can_r
	TNOTheme.apply_button_style(b_rollback, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.08, 0.04, 0.95))
	b_rollback.pressed.connect(func():
		var res = SocietalLawsManager.enact_law_reform(current_state, law_idx, -1, 15.0, 1)
		modal.queue_free()
		if res.get("success", false):
			law_reformed.emit(res)
			display_country(current_state)
	)
	act_hbox.add_child(b_rollback)

	mvbox.add_child(act_hbox)

	add_child(modal)
	active_reform_modal = modal


func _generate_law_tiers_bbcode(law_name: String, cur_tier: int) -> String:
	var n = law_name.to_lower()
	var tag = current_state.country_tag.to_upper() if current_state != null else ""
	var is_german = tag in ["GER", "SPE", "BOR", "GOR", "HEY"]

	var tiers := []
	if "труд" in n and is_german:
		tiers = [
			"Ур. 1: [b]Подневольный / рабский труд (Sklaverei)[/b] — тотальная эксплуатация миллионов остарбайтеров.",
			"Ур. 2: [b]Трудовые лагеря под контролем концернов[/b] — частичное нормирование и рационы.",
			"Ур. 3: [b]Государственная трудовая повинность[/b] — перевод на контрактную систему (реформа Шпеера).",
			"Ур. 4: [b]Нормированный рабочий день[/b] — цеховой контроль и ликвидация рабских бараков.",
			"Ур. 5: [b]Свободный найм и профсоюзные комитеты[/b] — европейский стандарт охраны труда."
		]
	elif "труд" in n or "мобилиз" in n:
		tiers = [
			"Ур. 1: [b]Принудительный каторжный труд[/b] — нормы военного времени и штрафбаты.",
			"Ур. 2: [b]Фронтовая трудовая повинность[/b] — мобилизация рабочих смен и снабжение пайками.",
			"Ур. 3: [b]Стахановские нормы и госзаказ[/b] — премиальная система и тарифная сетка.",
			"Ур. 4: [b]Фабричные комитеты и профсоюзы[/b] — защита условий труда и нормирование смен.",
			"Ур. 5: [b]Трудовой кодекс мирного времени[/b] — социальное страхование и 40-часовая неделя."
		]
	elif "печат" in n:
		tiers = [
			"Ур. 1: [b]Тотальная цензура и агитпроп[/b] — единая государственная печать.",
			"Ур. 2: [b]Строгий военный надзор[/b] — запрет оппозиционных листовок и радиопередач.",
			"Ур. 3: [b]Государственная лицензия прессы[/b] — ограниченная критика местных органов.",
			"Ур. 4: [b]Ведомственная автономия[/b] — разнообразие партийных и академических изданий.",
			"Ур. 5: [b]Свобода слова и независимая пресса[/b] — отмена предварительной цензуры."
		]
	elif "полит" in n:
		tiers = [
			"Ур. 1: [b]Однопартийная диктатура / Хунта[/b] — абсолютная монополия режима.",
			"Ур. 2: [b]Авторитарный патриотический фронт[/b] — коалиция лояльных фракций.",
			"Ур. 3: [b]Ограниченный парламентаризм[/b] — цензовые выборы и фракционная борьба.",
			"Ур. 4: [b]Многопартийный представительный строй[/b] — открытые парламентские сессии.",
			"Ур. 5: [b]Конституционная плюралистическая демократия[/b] — верховенство права и выборы."
		]
	else:
		tiers = [
			"Ур. 1: [b]Чрезвычайный архаичный режим[/b] — минимум гарантий и государственного участия.",
			"Ур. 2: [b]Базовые защитные меры[/b] — фрагментарное целевое обеспечение.",
			"Ур. 3: [b]Регулярная государственная служба[/b] — нормативно-правовой контроль.",
			"Ур. 4: [b]Развитая институциональная система[/b] — постоянное бюджетное финансирование.",
			"Ур. 5: [b]Передовой стандарт TNO[/b] — максимальная сплоченность и легитимность институтов."
		]

	var res := ""
	var tag_cur = _tr("TNO_POL_TIER_CURRENT", "ТЕКУЩИЙ")
	var tag_next = _tr("TNO_POL_TIER_NEXT", "СЛЕДУЮЩИЙ")
	for i in range(tiers.size()):
		var t_num = i + 1
		if t_num == cur_tier:
			res += "[color=#20dfaa]▶ %s [%s][/color]\n" % [tiers[i], tag_cur]
		elif t_num == cur_tier + 1:
			res += "[color=#f0d040]★ %s [%s][/color]\n" % [tiers[i], tag_next]
		else:
			res += "[color=#708595]%s[/color]\n" % [tiers[i]]
	return res


func _on_pie_chart_draw() -> void:
	if pie_chart_control == null or current_state == null or current_state.initial_parties.is_empty():
		return
	var center = pie_chart_control.size / 2.0
	var radius = minf(center.x, center.y) - 2.0

	var start_angle = -PI / 2.0
	for p in current_state.initial_parties:
		var share = p.popularity / 100.0
		if share <= 0.001:
			continue
			
		var end_angle = start_angle + (share * TAU)
		var points = PackedVector2Array([center])
		var segments = maxi(8, int(share * 32))
		for i in range(segments + 1):
			var a = start_angle + (float(i) / segments) * (end_angle - start_angle)
			points.append(center + Vector2(cos(a), sin(a)) * radius)
		pie_chart_control.draw_colored_polygon(points, p.color)
		start_angle = end_angle
