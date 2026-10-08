class_name CountrySelectScreen
extends Control

##
## CountrySelectScreen: Каноничный терминал выбора страны TNO (Godot 4)
##
## Полностью воссоздает атмосферу и UI/UX оригинального мода The New Order:
## 1. Полноэкранная темная интерактивная карта мира с зумом, панорамированием и кликами по регионам
## 2. CRT-постобработка: сканлайны, виньетирование, аналоговый люминофор и хроматические аберрации
## 3. Верхняя панель закладок ключевых театров военных действий (Bookmarks / Theaters)
## 4. Горизонтальная карусель карточек рекомендованных наций с флагами, статусом контента и лидерами
## 5. Массивное тактическое досье выбранной державы:
##    - Официальное название, флаг с аутентичной рамкой, идеология и геополитический блок
##    - Портрет лидера 156x210 (TNO-стандарт), ФИО, титул и черты характера
##    - Круговая диаграмма распределения сил в парламенте (Pie Chart) и шкалы стабильности
##    - Стартовая нарративная сводка на 1 января 1962 года (Lore Briefing)
##    - Сетка стартовых национальных духов и кризисов (National Spirits) с подробными тултипами
##    - Массивная контрастная кнопка запуска кампании («ВСТУПИТЬ В ИГРУ»)
## 6. Звуковой контроллер ретро-переключателей, треска ЭЛТ и телетайпа
##

signal campaign_launched(config: RefCounted)
signal returned_to_main_menu()

const RECOMMENDED_CARD_SCENE = preload("res://ui/components/recommended_nation_card.tscn")
const RECOMMENDED_CARD_SCRIPT = preload("res://ui/components/recommended_nation_card.gd")
const LEADER_PORTRAIT_FRAME_SCENE = preload("res://ui/components/leader_portrait_frame.tscn")
const GAME_SESSION_SCRIPT = preload("res://core/systems/game_session.gd")

# Ноды в соответствии с требуемой иерархией
@onready var map_background: CountrySelectMapWidget = $MapBackground
@onready var crt_post_process: ColorRect = $CRTPostProcess

# Верхняя панель закладок (TopBookmarkBar)
@onready var top_bookmark_bar: PanelContainer = $TopBookmarkBar
@onready var bookmark_container: HBoxContainer = $TopBookmarkBar/HBox/BookmarkButtonGroup
@onready var btn_exit: Button = $TopBookmarkBar/HBox/ExitButton
@onready var btn_filter_focus: Button = get_node_or_null("TopBookmarkBar/HBox/FilterFocusButton")

# Карусель рекомендованных наций (MajorNationsCarousel)
@onready var major_nations_carousel: ScrollContainer = $MajorNationsCarousel
@onready var carousel_cards_container: HBoxContainer = $MajorNationsCarousel/CardsHBox

# Панель-досье нации (DossierPanel)
@onready var dossier_panel: PanelContainer = $DossierPanel
@onready var flag_rect: TextureRect = $DossierPanel/Margin/VBox/Header/HeaderHBox/FlagBox/FlagRect
@onready var flag_overlay: TextureRect = $DossierPanel/Margin/VBox/Header/HeaderHBox/FlagBox/FlagOverlay
@onready var lbl_country_name: Label = $DossierPanel/Margin/VBox/Header/CountryNameLabel
@onready var ideology_icon_rect: TextureRect = $DossierPanel/Margin/VBox/Header/HeaderHBox/MetaVBox/IdeologyHBox/IdeologyIcon
@onready var lbl_ideology: Label = $DossierPanel/Margin/VBox/Header/HeaderHBox/MetaVBox/IdeologyHBox/IdeologyLabel
@onready var lbl_bloc_badge: Label = $DossierPanel/Margin/VBox/Header/HeaderHBox/MetaVBox/IdeologyHBox/BlocBadge

# Секция лидера
@onready var leader_portrait_frame: LeaderPortraitFrame = $DossierPanel/Margin/VBox/LeaderSection/PortraitFrame
@onready var lbl_leader_name: Label = $DossierPanel/Margin/VBox/LeaderSection/LeaderMetaVBox/LeaderNameLabel
@onready var lbl_leader_title: Label = $DossierPanel/Margin/VBox/LeaderSection/LeaderMetaVBox/LeaderTitleLabel
@onready var traits_container: VBoxContainer = $DossierPanel/Margin/VBox/LeaderSection/LeaderMetaVBox/TraitsContainer
@onready var lbl_macro_stats: Label = $DossierPanel/Margin/VBox/LeaderSection/LeaderMetaVBox/MacroStatsLabel

# Сводка политики и диаграмма
@onready var pie_chart_control: Control = $DossierPanel/Margin/VBox/PoliticsSummary/HBox/PieChartDraw
@onready var pie_chart_overlay: TextureRect = $DossierPanel/Margin/VBox/PoliticsSummary/HBox/PieChartDraw/PieChartOverlay
@onready var lbl_ruling_party: Label = $DossierPanel/Margin/VBox/PoliticsSummary/HBox/PolMetaVBox/RulingPartyLabel
@onready var lbl_stability_bar: Label = $DossierPanel/Margin/VBox/PoliticsSummary/HBox/PolMetaVBox/StabilityLabel
@onready var lbl_war_support_bar: Label = $DossierPanel/Margin/VBox/PoliticsSummary/HBox/PolMetaVBox/WarSupportLabel
@onready var lbl_pol_cap_rate: Label = $DossierPanel/Margin/VBox/PoliticsSummary/HBox/PolMetaVBox/PolCapLabel
@onready var party_legend_container: HFlowContainer = get_node_or_null("DossierPanel/Margin/VBox/PoliticsSummary/PartyLegendContainer")
@onready var ministers_title: Label = get_node_or_null("DossierPanel/Margin/VBox/MinistersTitle")
@onready var ministers_grid: HBoxContainer = get_node_or_null("DossierPanel/Margin/VBox/MinistersGrid")

# Лор и нарратив
@onready var lore_scroll: ScrollContainer = $DossierPanel/Margin/VBox/LoreScroll
@onready var lore_text: RichTextLabel = $DossierPanel/Margin/VBox/LoreScroll/LoreText

# Сетка национальных духов
@onready var spirits_grid: GridContainer = $DossierPanel/Margin/VBox/NationalSpiritsGrid

# Кнопка старта кампании и опции
@onready var btn_start_campaign: Button = $DossierPanel/Margin/VBox/ActionHBox/StartCampaignButton
@onready var btn_scenario_options: Button = $DossierPanel/Margin/VBox/ActionHBox/ScenarioOptionsButton

# Аудиоконтроллер
@onready var audio_controller: Node = $AudioController

# Состояние экрана
var selected_tag: String = "KOM"
var current_dossier: Dictionary = {}
var current_theater_index: int = 0
var theater_buttons: Array[Button] = []
var recommended_cards: Array = []
var current_parties_breakdown: Array[Dictionary] = []
var current_config: RefCounted = null

# Модальное окно параметров сценария
var options_modal: Control = null

# Каноничные театры TNO
var theaters_data: Array[Dictionary] = []


func _ready() -> void:
	_init_config()
	_apply_styles()
	_setup_audio_controller()
	_setup_theaters_data()
	_init_top_bookmark_bar()
	_connect_map_signals()
	_connect_action_signals()
	_register_crt_settings()

	if pie_chart_control != null:
		pie_chart_control.draw.connect(_on_pie_chart_draw)

	# Стартовый выбор театра «РУССКАЯ СМУТА»
	_select_theater(0)

	# Озвучка включения кинескопа
	_play_sfx_warmup()


func _init_config() -> void:
	var session = _get_session()
	if session != null and session.current_config != null:
		current_config = session.current_config
	else:
		current_config = GAME_SESSION_SCRIPT.GameStartConfig.new()
		current_config.selected_country_tag = "KOM"


func _setup_theaters_data() -> void:
	theaters_data = [
		{
			"id": "theater_smuta",
			"name": "РУССКАЯ СМУТА",
			"subname": "THE RUIN OF THE BEAR",
			"preset": "RUSSIA",
			"tags": ["KOM", "WRS", "OMS", "SVR", "TOM", "NOV", "BRY", "SBA", "SAM", "TYU", "VYT", "IRK", "MAG", "AMR", "CHT", "KEM"]
		},
		{
			"id": "theater_gcw",
			"name": "КРИЗИС РЕЙХА",
			"subname": "THE REICH'S AGONY",
			"preset": "EUROPE",
			"tags": ["SPE", "BOR", "GOR", "HEY", "GER"]
		},
		{
			"id": "theater_superpowers",
			"name": "СВЕРХДЕРЖАВЫ",
			"subname": "THE COLD WAR",
			"preset": "WORLD",
			"tags": ["USA", "GER", "JAP", "ITA"]
		},
		{
			"id": "theater_sphere",
			"name": "СФЕРА И АЗИЯ",
			"subname": "THE SUN IN THE EAST",
			"preset": "ASIA",
			"tags": ["GNG", "CHI", "MAN", "THA", "YUN"]
		},
		{
			"id": "theater_europe",
			"name": "СРЕДИЗЕМНОМОРЬЕ",
			"subname": "THE TRIUMVIRATE",
			"preset": "EUROPE",
			"tags": ["ITA", "IBR", "ENG", "BRG", "TUR"]
		},
		{
			"id": "theater_world",
			"name": "КАРТА МИРА",
			"subname": "ALL NATIONS",
			"preset": "WORLD",
			"tags": ["USA", "GER", "JAP", "KOM", "OMS", "SPE", "BOR", "ITA", "IBR", "ENG", "GNG", "CHI"]
		}
	]


func _apply_styles() -> void:
	# Стилизация TopBookmarkBar
	if top_bookmark_bar != null:
		TNOTheme.apply_panel_style(top_bookmark_bar, TNOTheme.COLOR_BORDER_CYAN, TNOTheme.COLOR_BG_DARK, 2, 4)

	# Стилизация DossierPanel
	if dossier_panel != null:
		TNOTheme.apply_panel_style(dossier_panel, TNOTheme.COLOR_BORDER_CYAN, TNOTheme.COLOR_BG_DARK, 2, 4)

	# Кнопка возврата в меню
	if btn_exit != null:
		TNOTheme.apply_button_style(btn_exit, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.05, 0.05, 0.95))

	# Кнопка фильтрации фокусов
	if btn_filter_focus != null:
		TNOTheme.apply_button_style(btn_filter_focus, TNOTheme.COLOR_BORDER_CYAN, Color(0.04, 0.12, 0.12, 0.95))

	# Массивная кнопка запуска кампании
	if btn_start_campaign != null:
		TNOTheme.apply_button_style(btn_start_campaign, TNOTheme.COLOR_BORDER_AMBER, Color(0.18, 0.14, 0.04, 0.98))

	# Кнопка опций сценария
	if btn_scenario_options != null:
		TNOTheme.apply_button_style(btn_scenario_options, TNOTheme.COLOR_BORDER_CYAN, Color(0.05, 0.12, 0.14, 0.95))

	# Скрыть дефолтный маленький HUD карты, чтобы не конфликтовал с нашим интерфейсом
	if map_background != null:
		var old_hud = map_background.get_node_or_null("HUD")
		if old_hud != null:
			old_hud.visible = false


func _setup_audio_controller() -> void:
	if audio_controller != null and not audio_controller.has_node("TerminalSoundFx"):
		var sfx = TerminalSoundFx.new()
		sfx.name = "TerminalSoundFx"
		audio_controller.add_child(sfx)
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").attach_ui_sounds(self)


func _register_crt_settings() -> void:
	if crt_post_process == null:
		return
	if has_node("/root/SettingsManager"):
		var sm = get_node("/root/SettingsManager")
		sm.register_crt_overlay(crt_post_process)
		sm.apply_crt_to_overlay(crt_post_process)
	elif crt_post_process.material is ShaderMaterial:
		var mat = crt_post_process.material as ShaderMaterial
		mat.set_shader_parameter("scanline_count", 540.0)
		mat.set_shader_parameter("scanline_intensity", 0.16)
		mat.set_shader_parameter("curvature", 0.025)
		mat.set_shader_parameter("vignette_strength", 0.85)


func _connect_map_signals() -> void:
	if map_background != null:
		map_background.country_selected.connect(_on_map_country_selected)
		map_background.country_hovered.connect(_on_map_country_hovered)


func _connect_action_signals() -> void:
	if btn_exit != null:
		btn_exit.pressed.connect(_on_exit_pressed)

	if btn_filter_focus != null:
		btn_filter_focus.pressed.connect(_on_toggle_focus_filter)

	if btn_start_campaign != null:
		btn_start_campaign.pressed.connect(_on_start_campaign_pressed)

	if btn_scenario_options != null:
		btn_scenario_options.pressed.connect(_on_scenario_options_pressed)


# ==============================================================================
# 1. ВЕРХНЯЯ ПАНЕЛЬ ТЕАТРОВ ВОЕННЫХ ДЕЙСТВИЙ (BOOKMARKS)
# ==============================================================================

func _init_top_bookmark_bar() -> void:
	if bookmark_container == null:
		return

	for c in bookmark_container.get_children():
		c.queue_free()
	theater_buttons.clear()

	var loc = get_node_or_null("/root/LocalizationManager")

	for i in range(theaters_data.size()):
		var t = theaters_data[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var t_name: String = t["name"]
		if loc != null:
			t_name = loc.tr_key("THEATER_" + t["id"].to_upper() + "_NAME", t_name)

		btn.text = "[ %s ]" % t_name
		btn.add_theme_font_size_override("font_size", 11)

		var captured_idx = i
		btn.pressed.connect(func(): _select_theater(captured_idx))
		bookmark_container.add_child(btn)
		theater_buttons.append(btn)

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").attach_ui_sounds(bookmark_container)


func _select_theater(idx: int) -> void:
	if idx < 0 or idx >= theaters_data.size():
		return

	current_theater_index = idx
	var active_theater = theaters_data[idx]

	_play_sfx_switch()

	# Обновление визуального состояния кнопок закладок
	for i in range(theater_buttons.size()):
		var b = theater_buttons[i]
		var is_active = (i == idx)
		var t_info = theaters_data[i]
		var t_name: String = t_info["name"]
		var loc = get_node_or_null("/root/LocalizationManager")
		if loc != null:
			t_name = loc.tr_key("THEATER_" + t_info["id"].to_upper() + "_NAME", t_name)

		if is_active:
			b.text = "► %s ◄" % t_name
			TNOTheme.apply_button_style(b, TNOTheme.COLOR_BORDER_CYAN, Color(0.08, 0.20, 0.18, 0.98))
			b.add_theme_color_override("font_color", Color(0.3, 1.0, 0.9))
		else:
			b.text = "[ %s ]" % t_name
			TNOTheme.apply_button_style(b, TNOTheme.COLOR_BORDER_AMBER, Color(0.04, 0.07, 0.08, 0.88))
			b.add_theme_color_override("font_color", Color(0.7, 0.8, 0.85))

	# Фокусировка камеры карты на выбранном ТВД
	var preset_key: String = active_theater.get("preset", "WORLD")
	if map_background != null:
		map_background.focus_preset(preset_key, false)

	# Заполнение горизонтальной карусели рекомендованных наций
	_populate_major_nations_carousel(active_theater["tags"])

	# Выбор стартовой страны выбранного театра
	var tags: Array = active_theater["tags"]
	var target_tag = tags[0] if not tags.is_empty() else "KOM"
	_select_country(target_tag, false)


# ==============================================================================
# 2. ГОРИЗОНТАЛЬНАЯ КАРУСЕЛЬ РЕКОМЕНДОВАННЫХ НАЦИЙ (MAJOR NATIONS CAROUSEL)
# ==============================================================================

func _populate_major_nations_carousel(tags: Array) -> void:
	if carousel_cards_container == null:
		return

	for c in carousel_cards_container.get_children():
		c.queue_free()
	recommended_cards.clear()

	var session = _get_session()

	for tag_var in tags:
		var tag = str(tag_var).to_upper()
		var dossier = session.get_country_dossier(tag) if session != null else {}

		var card = RECOMMENDED_CARD_SCENE.instantiate()
		carousel_cards_container.add_child(card)
		recommended_cards.append(card)

		var is_selected_nation = (tag == selected_tag)
		card.setup(dossier, is_selected_nation)
		card.card_selected.connect(_on_carousel_card_selected)
		card.card_hovered.connect(_on_carousel_card_hovered)

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").attach_ui_sounds(carousel_cards_container)


func _on_carousel_card_selected(dossier: Dictionary) -> void:
	var tag = str(dossier.get("tag", "KOM")).to_upper()
	_select_country(tag, true)


func _on_carousel_card_hovered(dossier: Dictionary) -> void:
	_play_sfx_hover()


func _highlight_selected_card() -> void:
	for card in recommended_cards:
		var c_tag = str(card.dossier_data.get("tag", "")).to_upper()
		card.set_selected(c_tag == selected_tag)


# ==============================================================================
# 3. ВЫБОР И ИНСПЕКЦИЯ СТРАНЫ (COUNTRY SELECTION & DOSSIER PANEL)
# ==============================================================================

func _on_map_country_selected(tag: String, dossier: Dictionary) -> void:
	if selected_tag == tag and not current_dossier.is_empty():
		return
	_select_country(tag, false, false, dossier)


func _on_map_country_hovered(_tag: String, _data: Dictionary) -> void:
	# Мягкий отклик при наведении на провинции карты
	pass


func _select_country(tag: String, center_camera: bool = true, notify_map: bool = true, direct_dossier: Dictionary = {}) -> void:
	var clean_tag = tag.to_upper().strip_edges()
	var tag_changed = (selected_tag != clean_tag)
	selected_tag = clean_tag
	if current_config != null:
		current_config.selected_country_tag = selected_tag

	var session = _get_session()
	if not direct_dossier.is_empty():
		current_dossier = direct_dossier
	elif session != null:
		current_dossier = session.get_country_dossier(selected_tag)
	else:
		current_dossier = {}

	# Обновить карту
	if notify_map and map_background != null:
		map_background.select_country(selected_tag, center_camera)

	# Обновить подсветку карточки в карусели
	_highlight_selected_card()

	# Обновить содержимое досье-панели
	_update_dossier_panel(current_dossier)

	# Звук выбора
	if tag_changed:
		_play_sfx_click()


func _update_dossier_panel(d: Dictionary) -> void:
	if dossier_panel == null or d.is_empty():
		return

	var loc = get_node_or_null("/root/LocalizationManager")
	var tag = str(d.get("tag", "UNK")).to_upper()
	var raw_name = str(d.get("name", tag))
	var loc_name = loc.tr_key(tag, raw_name) if loc != null else raw_name

	# 1. Заголовок и флаг
	if lbl_country_name != null:
		lbl_country_name.text = "┌── [%s] %s ──" % [tag, loc_name.to_upper()]

	var flag_tex = TNOTheme.get_flag_texture(tag)
	if flag_rect != null and flag_tex != null:
		flag_rect.texture = flag_tex

	if flag_overlay != null:
		var overlay_tex = TNOTheme.get_texture("res://assets/gfx/interface/flag_overlay_tno.png")
		if overlay_tex == null:
			overlay_tex = TNOTheme.get_texture("res://assets/gfx/interface/flag_overlay.png")
		if overlay_tex != null:
			flag_overlay.texture = overlay_tex

	# Идеология и альянс
	var ideo = str(d.get("ideology", "Despotism"))
	var sub_ideo = str(d.get("sub_ideology", ideo))
	if loc != null:
		ideo = loc.tr_key(ideo, ideo)
		sub_ideo = loc.tr_key(sub_ideo, sub_ideo)

	if lbl_ideology != null:
		lbl_ideology.text = "│ %s // %s" % [ideo.to_upper(), sub_ideo.to_upper()]

	var ideo_icon = TNOTheme.get_ideology_icon(d.get("sub_ideology", d.get("ideology", "")))
	if ideology_icon_rect != null and ideo_icon != null:
		ideology_icon_rect.texture = ideo_icon

	var bloc = str(d.get("geopolitical_bloc", "Non-Aligned"))
	if lbl_bloc_badge != null:
		lbl_bloc_badge.text = "[★ %s]" % bloc.to_upper()
		if "OFN" in bloc or "ОФН" in bloc:
			lbl_bloc_badge.add_theme_color_override("font_color", Color(0.2, 0.95, 0.85))
		elif "PAKT" in bloc or "ПАКТ" in bloc:
			lbl_bloc_badge.add_theme_color_override("font_color", Color(0.95, 0.35, 0.3))
		elif "SPHERE" in bloc or "СФЕРА" in bloc:
			lbl_bloc_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		else:
			lbl_bloc_badge.add_theme_color_override("font_color", Color(0.6, 0.7, 0.75))

	# 2. Лидер (стандартный размер TNO 156x210)
	var leader_name = str(d.get("leader_name", "UNKNOWN"))
	var leader_title = str(d.get("leader_title", "Глава государства"))
	if loc != null:
		leader_name = loc.tr_key(leader_name, leader_name)
		leader_title = loc.tr_key(leader_title, leader_title)

	if lbl_leader_name != null:
		lbl_leader_name.text = "► %s" % leader_name.to_upper()
	if lbl_leader_title != null:
		lbl_leader_title.text = "│ %s" % leader_title

	if leader_portrait_frame != null:
		leader_portrait_frame.mode = LeaderPortraitFrame.FrameMode.DOSSIER
		leader_portrait_frame.display_leader(d, tag, true)

	# Черты лидера и национальные особенности
	if traits_container != null:
		for c in traits_container.get_children():
			c.queue_free()

		var traits: Array = d.get("traits", [])
		if traits.is_empty():
			traits = ["Стандартный оперативный профиль", "Региональная легитимность"]

		for tr_item in traits:
			var t_lbl := Label.new()
			t_lbl.text = "★ %s" % str(tr_item)
			t_lbl.add_theme_font_size_override("font_size", 10)
			t_lbl.add_theme_color_override("font_color", Color(0.3, 0.95, 0.85))
			traits_container.add_child(t_lbl)

	# Макропоказатели
	var gdp = float(d.get("starting_gdp", 18.5))
	var manpower = int(d.get("starting_manpower", 65000))
	var factories = int(d.get("starting_factories", 25))
	if lbl_macro_stats != null:
		lbl_macro_stats.text = _tr("LOBBY_MACRO_STATS", "ВВП: $%0.1f млрд | Резерв: %d тыс. | Фабрик: %d") % [gdp, int(manpower / 1000.0), factories]

	# 3. Политика и круговая диаграмма партий
	_build_parties_breakdown(tag, d)
	if pie_chart_control != null:
		pie_chart_control.queue_redraw()

	if lbl_ruling_party != null:
		var ruling_party_name = d.get("ruling_party_name", sub_ideo)
		lbl_ruling_party.text = _tr("LOBBY_RULING_PARTY", "ПРАВЯЩАЯ СИЛА: %s") % ruling_party_name.to_upper()

	var stab = int(d.get("stability_percent", 75))
	var war_sup = int(d.get("war_support_percent", 65))
	if lbl_stability_bar != null:
		lbl_stability_bar.text = _tr("LOBBY_STABILITY", "СТАБИЛЬНОСТЬ: %s %d%%") % [_make_ascii_bar(stab, 100), stab]
	if lbl_war_support_bar != null:
		lbl_war_support_bar.text = _tr("LOBBY_WAR_SUPPORT", "ПОДДЕРЖКА ВОЙНЫ: %s %d%%") % [_make_ascii_bar(war_sup, 100), war_sup]
	if lbl_pol_cap_rate != null:
		lbl_pol_cap_rate.text = _tr("LOBBY_POL_CAP", "ПОЛИТ. КАПИТАЛ: +1.50/ход | ЛЕГИТИМНОСТЬ: ВЫСОКАЯ")

	# 4. Кабинет министров правительства
	_populate_cabinet_ministers(tag, d)

	# 5. Лор и вводная историческая справка на 1 января 1962 г.
	if lore_text != null:
		var l_content = str(d.get("lore", ""))
		if l_content.is_empty() and loc != null:
			l_content = loc.tr_key(tag + "_lore", loc.tr_key(tag + "_THENEWORDER_DESC", ""))
		if l_content.is_empty():
			l_content = "Начало 1962 года застает державу перед лицом глобальных потрясений эпохи Холодной Войны. Старый миропорядок рушится, приближая развязку противостояния сверхдержав."

		lore_text.text = _format_lore_bbcode(l_content)

	# 6. Сетка национальных духов
	_populate_national_spirits_grid(tag, d)


func _format_lore_bbcode(text_in: String) -> String:
	var clean = text_in.strip_edges()
	clean = clean.replace("\\n", "\n")
	# Подсветка ключевых сущностей палитрой TNO
	var result = "[color=#d8f5ef]%s[/color]" % clean
	result = result.replace("1962", "[color=#ffb826]1962[/color]")
	result = result.replace("Гитлер", "[color=#ff594d]Гитлер[/color]")
	result = result.replace("Рейх", "[color=#ff594d]Рейх[/color]")
	result = result.replace("ОФН", "[color=#2ee5d6]ОФН[/color]")
	result = result.replace("OFN", "[color=#2ee5d6]OFN[/color]")
	result = result.replace("СССР", "[color=#59f299]СССР[/color]")
	result = result.replace("России", "[color=#59f299]России[/color]")
	return result


func _make_ascii_bar(val: int, max_val: int) -> String:
	var total_ticks := 8
	var filled = clampi(int(round((float(val) / float(max_val)) * total_ticks)), 0, total_ticks)
	var bar := "["
	for i in range(total_ticks):
		bar += "█" if i < filled else "░"
	bar += "]"
	return bar


# ==============================================================================
# 4. ПОЛИТИЧЕСКАЯ ДИАГРАММА (PIE CHART DRAW) И РАСПРЕДЕЛЕНИЕ ПАРТИЙ
# ==============================================================================

func _build_parties_breakdown(tag: String, _d: Dictionary) -> void:
	current_parties_breakdown.clear()
	if party_legend_container != null:
		for c in party_legend_container.get_children():
			c.queue_free()

	var pop_dict: Dictionary = {}

	# 1. Попытка чтения из country.json
	var c_path = "res://data/countries/%s/country.json" % tag
	if FileAccess.file_exists(c_path):
		var f = FileAccess.open(c_path, FileAccess.READ)
		if f != null:
			var json = JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				var c_data = json.data as Dictionary
				if c_data.has("popularities") and c_data["popularities"] is Dictionary:
					pop_dict = c_data["popularities"]
			f.close()

	# 2. Если пусто, попытка из CountryDataImporter
	if pop_dict.is_empty():
		var state = CountryDataImporter.load_country(tag)
		if state != null and not state.initial_parties.is_empty():
			for p in state.initial_parties:
				pop_dict[p.party_name] = p.popularity

	# 3. Базовый идеологический справочник TNO
	var ideo_meta = {
		"national_socialism": {
			"name": "НСДАП (Ортодоксы)",
			"color": Color(0.48, 0.28, 0.18),
			"desc": "Ортодоксальное крыло национал-социализма. Опирается на партийный аппарат, старую гвардию и культ фюрера."
		},
		"national_socialism_2": {
			"name": "Партократы Бормана",
			"color": Color(0.62, 0.38, 0.22),
			"desc": "Консервативная партийная номенклатура Рейха, стремящаяся законсервировать статус-кво."
		},
		"burgundian_system": {
			"name": "Черный Орден СС",
			"color": Color(0.18, 0.18, 0.26),
			"desc": "Тоталитарно-спартанский эзотерический культ Генриха Гиммлера. Цель — очистительный ядерный армагеддон."
		},
		"ultranationalism": {
			"name": "Ультранационалисты",
			"color": Color(0.32, 0.32, 0.36),
			"desc": "Радикальные милитаристы и фанатики реванша. Полное подчинение общества подготовке к тотальной войне."
		},
		"fascism": {
			"name": "Фашисты",
			"color": Color(0.55, 0.40, 0.20),
			"desc": "Корпоративистский авторитарный режим, жесткая государственная иерархия и культ нации."
		},
		"despotism": {
			"name": "Милитаристы / Деспотия",
			"color": Color(0.42, 0.45, 0.50),
			"desc": "Генеральская хунта и военные прагматики. Управление через армейские приказы и силу оружия."
		},
		"paternalism": {
			"name": "Авторитарные Консерваторы",
			"color": Color(0.20, 0.45, 0.65),
			"desc": "Традиционная элита, монархисты и правые популисты, стремящиеся к порядку и сильной руке."
		},
		"conservatism": {
			"name": "Консерваторы",
			"color": Color(0.20, 0.55, 0.85),
			"desc": "Парламентский консерватизм, рыночная стабильность, верховенство закона и традиционные институты."
		},
		"liberalism": {
			"name": "Либеральные Демократы",
			"color": Color(0.90, 0.65, 0.20),
			"desc": "Гражданские свободы, рыночные реформы, разделение властей и главенство конституции."
		},
		"progressivism": {
			"name": "Прогрессивисты",
			"color": Color(0.20, 0.80, 0.70),
			"desc": "Социальные реформы, гражданское равноправие, борьба с дискриминацией и поддержка трудящихся."
		},
		"socialist": {
			"name": "Демократические Социалисты",
			"color": Color(0.85, 0.30, 0.25),
			"desc": "Рабочая демократия, национализация ключевых монополий и народный суверенитет."
		},
		"communist": {
			"name": "Коммунисты",
			"color": Color(0.70, 0.12, 0.12),
			"desc": "Авангард пролетариата, марксистско-ленинская диктатура и централизованное планирование."
		}
	}

	# Специальные партийные имена для держав
	var specific_party_names = {
		"USA": {
			"liberalism": "Демократы (R-D)",
			"conservatism": "Республиканцы (R-D)",
			"paternalism": "Правые патриоты (NPP-FR)",
			"progressivism": "Прогрессивисты (NPP-C)"
		},
		"GER": {
			"national_socialism": "НСДАП (Ортодоксы Гитлера)",
			"national_socialism_2": "Партократы Бормана",
			"despotism": "Милитаристы Вермахта",
			"liberalism": "Реформаторы Шпеера",
			"paternalism": "Имперские Консерваторы"
		},
		"OMS": {
			"ultranationalism": "Черная Лига (Великий Суд)",
			"despotism": "Военный штаб Лиги",
			"communist": "Подпольные советы"
		},
		"WRS": {
			"socialist": "Революционный Военсовет",
			"communist": "Политсовет РККА",
			"despotism": "Штаб фронта"
		},
		"SVR": {
			"paternalism": "Уральская Администрация",
			"despotism": "Генералитет Батова",
			"conservatism": "Гражданские инженеры"
		},
		"JAP": {
			"fascism": "Ассоциация Помощи Трону",
			"paternalism": "Бюрократическая фракция",
			"despotism": "Императорская Армия"
		},
		"ITA": {
			"fascism": "Фашистская Партия (PNF)",
			"paternalism": "Монархисты и Сенат",
			"conservatism": "Христианские демократы"
		},
		"TOM": {
			"liberalism": "Салон Декабристов",
			"conservatism": "Салон Модернистов",
			"progressivism": "Салон Бастурмы",
			"paternalism": "Салон Евразийцев"
		}
	}

	var party_items: Array[Dictionary] = []
	for k in pop_dict:
		var val = float(pop_dict[k])
		if val <= 0.001:
			continue
		var base_info = ideo_meta.get(k, {
			"name": k.capitalize(),
			"color": Color(0.5, 0.5, 0.5),
			"desc": "Политическая фракция державы."
		})
		var p_name = str(base_info["name"])
		if specific_party_names.has(tag) and specific_party_names[tag].has(k):
			p_name = specific_party_names[tag][k]

		party_items.append({
			"id": k,
			"name": p_name,
			"popularity": val,
			"color": base_info["color"],
			"desc": base_info["desc"]
		})

	# Сортировка по убыванию популярности
	party_items.sort_custom(func(a, b): return a["popularity"] > b["popularity"])

	if party_items.is_empty():
		party_items = [
			{"id": "ruling", "name": "Правящая партия", "popularity": 62.0, "color": Color(0.2, 0.85, 0.75), "desc": "Основная политическая опора действующего режима."},
			{"id": "opposition", "name": "Лояльная оппозиция", "popularity": 24.0, "color": Color(0.35, 0.60, 0.75), "desc": "Легальные фракции, участвующие в распределении мандатов."},
			{"id": "radicals", "name": "Радикальные диссиденты", "popularity": 14.0, "color": Color(0.75, 0.35, 0.35), "desc": "Внесистемные движения и подпольные ячейки."}
		]

	for item in party_items:
		current_parties_breakdown.append(item)

		if party_legend_container != null:
			var chip := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.04, 0.08, 0.10, 0.90)
			sb.border_color = Color(item["color"].r * 0.7, item["color"].g * 0.7, item["color"].b * 0.7, 0.8)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.corner_radius_top_left = 2
			sb.corner_radius_top_right = 2
			sb.corner_radius_bottom_left = 2
			sb.corner_radius_bottom_right = 2
			chip.add_theme_stylebox_override("panel", sb)

			var hbox := HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 5)

			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(8, 8)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.color = item["color"]
			hbox.add_child(dot)

			var lbl := Label.new()
			lbl.text = "%s: %0.1f%%" % [item["name"], item["popularity"]]
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 0.9))
			hbox.add_child(lbl)

			chip.add_child(hbox)
			chip.tooltip_text = "┌── [ПОЛИТИЧЕСКАЯ СИЛА // POLITICAL PARTY] ──\n│ Партия: %s\n│ Доля влияния: %0.1f%%\n├─────────────────────────────────────────\n│ Платформа и идеология:\n│ %s" % [item["name"], item["popularity"], item["desc"]]
			party_legend_container.add_child(chip)


func _on_pie_chart_draw() -> void:
	if pie_chart_control == null or current_parties_breakdown.is_empty():
		return

	var center = pie_chart_control.size / 2.0
	var radius = minf(center.x, center.y) - 2.0
	var start_angle = -PI / 2.0

	for p in current_parties_breakdown:
		var share = float(p.get("popularity", 0.0)) / 100.0
		if share <= 0.001:
			continue

		var end_angle = start_angle + (share * TAU)
		var points = PackedVector2Array([center])
		var segments = maxi(8, int(share * 36))
		for i in range(segments + 1):
			var a = start_angle + (float(i) / segments) * (end_angle - start_angle)
			points.append(center + Vector2(cos(a), sin(a)) * radius)

		var col: Color = p.get("color", Color.WHITE)
		pie_chart_control.draw_colored_polygon(points, col)
		start_angle = end_angle

	# Тонкий внутренний контур
	pie_chart_control.draw_arc(center, radius, 0.0, TAU, 48, Color(0.1, 0.2, 0.25, 0.8), 1.0)


# ==============================================================================
# 5. КАБИНЕТ МИНИСТРОВ (CABINET OF MINISTERS)
# ==============================================================================

func _populate_cabinet_ministers(tag: String, _dossier: Dictionary) -> void:
	if ministers_grid == null:
		return

	for c in ministers_grid.get_children():
		c.queue_free()

	# Извлечение идей министров из country.json
	var c_path = "res://data/countries/%s/country.json" % tag
	var found_ideas: Array = []
	if FileAccess.file_exists(c_path):
		var f = FileAccess.open(c_path, FileAccess.READ)
		if f != null:
			var json = JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				var c_data = json.data as Dictionary
				found_ideas = c_data.get("ideas", [])
			f.close()

	var role_meta = {
		"hog": {
			"abbr": "[ГЛАВА ПРАВ.]",
			"full": "Глава правительства",
			"dep": "Исполнительная канцелярия",
			"icon": "res://assets/gfx/interface/pol_power_icon.png",
			"effects": "• Прирост политического капитала: +0.25/ход\n• Стабильность режима: +5.0%\n• Эффективность решений: +10.0%"
		},
		"for": {
			"abbr": "[МИД]",
			"full": "Министр иностранных дел",
			"dep": "Министерство иностранных дел",
			"icon": "res://assets/gfx/interface/ideologies/paternalism_transitioning_democracy_subtype.png",
			"effects": "• Дипломатический вес державы: +15.0%\n• Международная легитимность: +10.0%\n• Скорость торговых сделок: +20.0%"
		},
		"eco": {
			"abbr": "[ЭКОНОМИКА]",
			"full": "Министр экономики",
			"dep": "Министерство финансов и промышленности",
			"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
			"effects": "• Производительность фабрик: +10.0%\n• Рост ВВП за ход: +0.3%\n• Затраты на потребительские нужды: -5.0%"
		},
		"sec": {
			"abbr": "[БЕЗОПАСНОСТЬ]",
			"full": "Министр безопасности",
			"dep": "Оборонное ведомство и органы безопасности",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"effects": "• Поддержка войны: +10.0%\n• Сопротивление в провинциях: -15.0%\n• Скорость мобилизации резервов: +12.0%"
		}
	}

	var known_names = {
		"Martin_Bormann": "Мартин Борман",
		"Albert_Speer": "Альберт Шпеер",
		"Walther_Hewel": "Вальтер Хевель",
		"Hermann_Goring": "Герман Геринг",
		"John_F_Kennedy": "Джон Ф. Кеннеди",
		"William_P_Rogers": "Уильям Роджерс",
		"Robert_McNamara": "Роберт Макнамара",
		"Melvin_Laird": "Мелвин Лэйрд",
		"Dmitry_Yazov": "Дмитрий Язов",
		"Viktor_Abakumov": "Виктор Абакумов",
		"Alexander_Kharkhardin": "Александр Хархардин",
		"Konstantin_Valukhin": "Константин Валухин",
		"Semyon_Timoshenko": "Семён Тимошенко",
		"Nikolay_Baibakov": "Николай Байбаков",
		"Andrey_Grechko": "Андрей Гречко",
		"Alexander_Altunin": "Александр Алтунин",
		"Mikhail_Rodionov": "Михаил Родионов",
		"Vyacheslav_Malyshev": "Вячеслав Малышев",
		"Yegor_Ligachev": "Егор Лигачев",
		"Leonid_Kantorovich": "Леонид Канторович",
		"Pavel_Batov": "Павел Батов",
		"Anatoly_Dobrynin": "Анатолий Добрынин",
		"Farman_Salmanov": "Фарман Салманов",
		"Ivan_Bagramyan": "Иван Баграмян",
		"Carlo_Scorza": "Карло Скорца",
		"Dino_Grandi": "Дино Гранди",
		"Giacomo_Acerbo": "Джакомо Ачербо",
		"Giovanni_De_Lorenzo": "Джованни Де Лоренцо",
		"Ikeda_Hayato": "Хаято Икэда",
		"Fujiyama_Aiichiro": "Аиитиро Фудзияма",
		"Kanemaru_Shin": "Син Канэмару",
		"Masanosuke_Ikeda": "Масаносукэ Икэда"
	}

	var roles = ["hog", "for", "eco", "sec"]
	for r in roles:
		var r_data = role_meta[r]
		var found_name := ""
		var found_id := ""
		var minister_portrait_tex: Texture2D = null

		for id_item in found_ideas:
			var sid = str(id_item)
			if sid.ends_with("_" + r):
				found_id = sid
				var parts = sid.split("_")
				if parts.size() >= 3:
					var raw_name = sid.substr(parts[0].length() + 1, sid.length() - parts[0].length() - parts[parts.size() - 1].length() - 2)
					found_name = known_names.get(raw_name, raw_name.replace("_", " "))

					var target_lower = ("%s_%s.png" % [tag, raw_name]).to_lower()
					var alt_lower = ("%s.png" % raw_name).to_lower()
					var tag_dir = "res://assets/gfx/leaders/%s" % tag
					if DirAccess.dir_exists_absolute(tag_dir):
						var da = DirAccess.open(tag_dir)
						if da != null:
							da.list_dir_begin()
							var fn = da.get_next()
							while not fn.is_empty():
								if not da.current_is_dir() and fn.ends_with(".png"):
									var fn_l = fn.to_lower()
									if fn_l == target_lower or fn_l == alt_lower:
										var exact_p = tag_dir.path_join(fn)
										var res = load(exact_p)
										if res is Texture2D:
											minister_portrait_tex = res
											break
								fn = da.get_next()
							da.list_dir_end()
				break

		if found_name.is_empty():
			found_name = "Штабной специалист"
			found_id = "%s_generic_%s" % [tag, r]

		if minister_portrait_tex == null:
			minister_portrait_tex = TNOTheme.get_texture(r_data["icon"])

		# Создание карточки министра
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 44)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.08, 0.10, 0.92)
		sb.border_color = Color(0.20, 0.55, 0.50, 0.85)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_left = 2
		sb.corner_radius_bottom_right = 2
		card.add_theme_stylebox_override("panel", sb)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		card.add_child(hbox)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(26, 34)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = minister_portrait_tex
		hbox.add_child(icon_rect)

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 1)

		var lbl_role := Label.new()
		lbl_role.text = r_data["abbr"]
		lbl_role.add_theme_font_size_override("font_size", 8)
		lbl_role.add_theme_color_override("font_color", Color(0.3, 0.95, 0.85))
		vbox.add_child(lbl_role)

		var lbl_name := Label.new()
		lbl_name.text = found_name
		lbl_name.add_theme_font_size_override("font_size", 9)
		lbl_name.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
		lbl_name.clip_text = true
		vbox.add_child(lbl_name)

		hbox.add_child(vbox)

		card.tooltip_text = "┌── [КАБИНЕТ МИНИСТРОВ // CABINET OF MINISTERS] ──\n│ ДОЛЖНОСТЬ: %s\n│ МИНИСТР: %s\n│ ВЕДОМСТВО: %s\n├─────────────────────────────────────────\n│ СТРАТЕГИЧЕСКИЕ ЭФФЕКТЫ ВЕДОМСТВА:\n%s" % [r_data["full"], found_name, r_data["dep"], r_data["effects"]]
		ministers_grid.add_child(card)


# ==============================================================================
# 6. НАЦИОНАЛЬНЫЕ ДУХИ И КРИЗИСЫ (NATIONAL SPIRITS GRID)
# ==============================================================================

func _populate_national_spirits_grid(tag: String, _dossier: Dictionary) -> void:
	if spirits_grid == null:
		return

	for c in spirits_grid.get_children():
		c.queue_free()

	# 1. Извлечение идей из country.json
	var c_path = "res://data/countries/%s/country.json" % tag
	var raw_ideas: Array = []
	if FileAccess.file_exists(c_path):
		var f = FileAccess.open(c_path, FileAccess.READ)
		if f != null:
			var json = JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				var c_data = json.data as Dictionary
				raw_ideas = c_data.get("ideas", [])
			f.close()

	# Фильтрация: исключить министров (_hog, _for, etc.) и законы (tno_*)
	var spirit_ids: Array[String] = []
	for id_item in raw_ideas:
		var sid = str(id_item)
		if sid.ends_with("_hog") or sid.ends_with("_for") or sid.ends_with("_eco") or sid.ends_with("_sec"):
			continue
		if sid.ends_with("_high_command") or sid.ends_with("_army_chief") or sid.ends_with("_navy_chief") or sid.ends_with("_air_chief") or sid.ends_with("_theorist"):
			continue
		if sid.begins_with("tno_"):
			continue
		spirit_ids.append(sid)

	# Справочник каноничных национальных духов TNO
	var spirits_registry = {
		# Германия
		"Pakt_Leader": {
			"name": "Лидер Единства Пакта",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_common_goal.png",
			"desc": "Великогерманский Рейх возглавляет военный блок в Европе, подавляя неповиновение в рейхскомиссариатах.",
			"effects": "• Приток политического влияния: +15.0%\n• Эффективность торговли с Пактом: +25.0%\n• Напряженность в колониях: Растущая"
		},
		"to_banish_want": {
			"name": "Искоренить нужду",
			"icon": "res://assets/gfx/interface/goals/focus_GER_bormann_army.png",
			"desc": "Огромные инфраструктурные мегапроекты и рабский труд сковывают реальную модернизацию экономики Рейха.",
			"effects": "• Потребление товаров: -10.0%\n• Затраты на рабочую силу: Минимальные\n• Технологическая инерция: -15.0%"
		},
		"the_two_principles": {
			"name": "Два принципа",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Раскол и подозрительность между прусским генералитетом Вермахта и идеологическими фанатиками НСДАП.",
			"effects": "• Стоимость армейских директив: +10.0%\n• Боеготовность дивизий: 80.0%\n• Политическое влияние армии: Высокое"
		},
		"endsieg": {
			"name": "Окончательная победа (Endsieg)",
			"icon": "res://assets/gfx/interface/goals/focus_GER_the_second_bormann_ausschuss.png",
			"desc": "Государственная пропаганда твердит о непоколебимом триумфе, пока общество скатывается к гражданской войне.",
			"effects": "• Поддержка войны: +15.0%\n• Общественная стабильность: Хрупкая\n• Смертельный кризис престолонаследия"
		},
		"gone_over": {
			"name": "Тень рабского труда",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_clean_wehrmacht.png",
			"desc": "Миллионы подневольных рабочих из Восточной Европы лишены базовых прав, порождая постоянную угрозу бунтов.",
			"effects": "• Общественное недовольство: +15.0%\n• Риск забастовок: Критический"
		},

		# США
		"OFN_Leader_of_The_Free_World": {
			"name": "Лидер Свободного Мира (ОФН)",
			"icon": "res://assets/gfx/interface/goals/focus_ENG_a_long_awaited_prime_minister.png",
			"desc": "Соединенные Штаты стоят во главе Организации Свободных Наций в глобальном противостоянии с фашизмом.",
			"effects": "• Легитимность альянса: 90.0%\n• Дипломатическое влияние: +20.0%\n• Глобальные базы ОФН"
		},
		"USA_last_bastion_of_liberty": {
			"name": "Последний оплот свободы",
			"icon": "res://assets/gfx/interface/goals/focus_ENG_OLD_the_prime_minister_speaks.png",
			"desc": "Американская мечта выдержала поражение в мировой войне, но требует решительной защиты.",
			"effects": "• Стабильность: +10.0%\n• Прирост политического капитала: +1.0/ход"
		},
		"USA_the_american_depression_4": {
			"name": "Затяжная экономическая депрессия",
			"icon": "res://assets/gfx/interface/consumer_goods_icon.png",
			"desc": "Экономика США медленно оправляется от послевоенного спада и потери ключевых тихоокеанских рынков.",
			"effects": "• Затраты на потребительские товары: +12.0%\n• Рост ВВП: Ограничен\n• Инфляция: 3.5%"
		},
		"USA_jim_crow": {
			"name": "Законы Джима Кроу и сегрегация",
			"icon": "res://assets/gfx/interface/ideologies/paternalism_right_wing_populism_subtype.png",
			"desc": "Глубокий общественный раскол на юге США. Борьба за гражданские права грозит разорвать нацию.",
			"effects": "• Общественная радикализация: +20.0%\n• Риск расовых беспорядков: Высокий"
		},
		"USA_OFN_Buffs_4": {
			"name": "Глобальное проецирование силы",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_display_of_force.png",
			"desc": "Флот и экспедиционные корпуса готовы к переброске в Африку и Южную Азию.",
			"effects": "• Эффективность интервенций: +25.0%\n• Дистанция морского снабжения: Максимальная"
		},

		# Омск
		"OMS_karbyshev_figurehead": {
			"name": "Генерал в заточении",
			"icon": "res://assets/gfx/interface/goals/focus_OMS_against_the_old_guard.png",
			"desc": "Дмитрий Карбышев остается почитаемым символом, но реальные рычаги власти захватил Дмитрий Язов.",
			"effects": "• Стабильность Лиги: +15.0%\n• Контроль спецслужб: Абсолютный"
		},
		"OMS_fueled_by_revenge": {
			"name": "Одержимость возмездием",
			"icon": "res://assets/gfx/interface/goals/focus_OMS_a_grip_of_cold_iron.png",
			"desc": "Все ресурсы Черной Лиги подчинены одной цели — тотальному уничтожению Германии во Втором Суде.",
			"effects": "• Затраты на военное производство: -20.0%\n• Поддержка войны: 100.0%\n• Бункерная фанатичность"
		},
		"OMS_nothing_left_to_lose": {
			"name": "Нечего терять",
			"icon": "res://assets/gfx/interface/goals/focus_OMS_a_quiet_war.png",
			"desc": "Бойцы Черной Лиги не признают капитуляции и готовы принять ядерный пепел ради победы.",
			"effects": "• Организация дивизий: +15.0%\n• Стойкость в обороне: +25.0%"
		},
		"PRC_savy_army": {
			"name": "Армия выживших",
			"icon": "res://assets/gfx/interface/manpower_icon.png",
			"desc": "Железная спартанская выучка в сибирских гарнизонах и подземных лагерях подготовки.",
			"effects": "• Опыт новобранцев: +20.0%\n• Скорость тренировки: +15.0%"
		},

		# Япония
		"Sphere_Leader": {
			"name": "Сердце Сферы Сопроцветания",
			"icon": "res://assets/gfx/interface/ideologies/fascism_group.png",
			"desc": "Японская империя доминирует в Азии и на Тихом океане через сеть колоний и марионеток.",
			"effects": "• Поступление ресурсов из колоний: +30.0%\n• Затраты на гарнизоны: Высокие"
		},
		"JAP_showa_emperor": {
			"name": "Император Сёва (Хирохито)",
			"icon": "res://assets/gfx/interface/goals/focus_KEM_prince_yuriys_ideals.png",
			"desc": "Божественный авторитет Тэнно объединяет нацию перед лицом внешних угроз.",
			"effects": "• Легитимность режима: 95.0%\n• Стабильность: +15.0%"
		},
		"JAP_zaibatsu_question": {
			"name": "Кризис корпораций Дзайбацу",
			"icon": "res://assets/gfx/interface/gdp_icon.png",
			"desc": "Олигархические конгломераты Ясуда и Мицуи сковывают экономику и подкупают политиков.",
			"effects": "• Коррупция в правительстве: +20.0%\n• Рост ВВП: Под угрозой краха"
		},
		"JAP_legacy_guarded_pearl_exercises": {
			"name": "Триумф Императорского Флота",
			"icon": "res://assets/gfx/interface/dockyard_icon.png",
			"desc": "IJN сохраняет господство на море, ведя яростную борьбу за бюджет с армией (IJA).",
			"effects": "• Скорость постройки кораблей: +15.0%\n• Соперничество армии и флота: Острое"
		},

		# Италия
		"TRI_Founder_IT": {
			"name": "Основатель Триумвирата",
			"icon": "res://assets/gfx/interface/goals/focus_ITA_OLD_christian_ideals_in_a_secular_state.png",
			"desc": "Рим возглавляет Средиземноморский союз с Испанией и Турцией.",
			"effects": "• Региональное господство: +20.0%\n• Дипломатический вес: Высокий"
		},
		"ITA_declining_trade": {
			"name": "Рана Атлантропы и застой торговли",
			"icon": "res://assets/gfx/interface/gdp_icon.png",
			"desc": "Осушение Средиземноморья разорило итальянские порты и вызвало песчаные бури на юге.",
			"effects": "• Доходы от морской торговли: -25.0%\n• Сельское хозяйство: В упадке"
		},
		"ITA_fading_fascism": {
			"name": "Угасающий фашизм",
			"icon": "res://assets/gfx/interface/ideologies/paternalism_transitioning_democracy_subtype.png",
			"desc": "Стареющая партия расколота между ортодоксами Скорцы и реформаторами Чиано.",
			"effects": "• Политический капитал: -10.0%\n• Нестабильность Великого Совета"
		},
		"ITA_navy_strengthened": {
			"name": "Мощь Реджиа Марина",
			"icon": "res://assets/gfx/interface/dockyard_icon.png",
			"desc": "Гордость дуче — современный средиземноморский флот линкоров и эсминцев.",
			"effects": "• Превосходство на море: +25.0%\n• Расход топлива: +15.0%"
		},

		# Российские варлорды
		"SIB_terror_bombing": {
			"name": "Шрамы налетов Люфтваффе",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Немецкие бомбардировки с рейхскомиссариатов выжгли сибирские города, породив жажду мести.",
			"effects": "• Эффективность фабрик: -15.0%\n• Опыт ополчения: +10.0%"
		},
		"RUS_terror_bombing": {
			"name": "Шрамы налетов Люфтваффе",
			"icon": "res://assets/gfx/interface/war_support_icon.png",
			"desc": "Немецкие бомбардировки с рейхскомиссариатов терроризируют население Западной России.",
			"effects": "• Эффективность фабрик: -15.0%\n• Стойкость защитников: +10.0%"
		},
		"RUS_warlord_manpower": {
			"name": "Призыв варлордов",
			"icon": "res://assets/gfx/interface/manpower_icon.png",
			"desc": "Суровые условия смуты заставляют ставить под ружье каждого способного держать оружие.",
			"effects": "• Призывной контингент: +3.0%\n• Мобилизация: Мгновенная"
		},
		"RUS_warlord_econ": {
			"name": "Военно-полевая экономика",
			"icon": "res://assets/gfx/interface/industrial_capacity_icon.png",
			"desc": "Кустарные мастерские, переплавка танкового лома и рейды за ресурсами к соседям.",
			"effects": "• Доступ к рейдам за добычей\n• Стоимость снаряжения: -15.0%"
		},
		"WRS_veterans_of_the_long_war": {
			"name": "Ветераны Великой Войны",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_german_wehrmacht.png",
			"desc": "Кадровый костяк генералов Тухачевского, закаленный в Первой Западнорусской войне.",
			"effects": "• Атака дивизий: +15.0%\n• Опыт командиров: +25.0%"
		},
		"WRS_agricultural_insecurity": {
			"name": "Продовольственный кризис",
			"icon": "res://assets/gfx/interface/consumer_goods_icon.png",
			"desc": "Северные леса и болота не могут прокормить армию без постоянных поставок из Поволжья.",
			"effects": "• Потребление припасов: +15.0%\n• Стабильность: -5.0%"
		},
		"KOM_syvtyvkartsi": {
			"name": "Сыктывкарский эксперимент",
			"icon": "res://assets/gfx/interface/ideologies/progressivism_reformist_socialism_subtype.png",
			"desc": "Остров демократии и плюрализма посреди охваченной анархией русской земли.",
			"effects": "• Политический плюрализм: 100.0%\n• Скорость исследований: +10.0%"
		},
		"KOM_clash_of_shadows_c_1": {
			"name": "Битва в тенях",
			"icon": "res://assets/gfx/interface/goals/focus_OMS_a_quiet_war.png",
			"desc": "Ожесточенная подковерная война между демократами, коммунистами и фашистами в парламенте.",
			"effects": "• Стабильность: -15.0%\n• Риск военного переворота"
		},
		"RUS_syktyvkar_arsenal": {
			"name": "Сыктывкарский арсенал",
			"icon": "res://assets/gfx/interface/military_factory_icon.png",
			"desc": "Эвакуированные заводы обеспечивают регулярный выпуск стрелкового вооружения.",
			"effects": "• Производство пехотного снаряжения: +20.0%"
		},
		"SVR_notso_redarmy": {
			"name": "Не совсем Красная Армия",
			"icon": "res://assets/gfx/interface/goals/focus_GER_a_clean_wehrmacht.png",
			"desc": "Прагматичный офицерский корпус генерала Батова отверг комиссаров ради военной дисциплины.",
			"effects": "• Организация дивизий: +10.0%\n• Скорость восстановления боеспособности: +15.0%"
		},
		"SVR_black_league_influence_tier_1": {
			"name": "Агенты Черной Лиги",
			"icon": "res://assets/gfx/interface/goals/focus_OMS_a_grip_of_cold_iron.png",
			"desc": "Лазутчики из Омска агитируют среди уральских офицеров за беспощадное возмездие.",
			"effects": "• Поддержка ультранационализма: Растущая"
		}
	}

	# Если список духов пуст, используем стандартные духи для тега
	if spirit_ids.is_empty():
		if tag in ["GER", "SPE", "BOR", "GOR", "HEY"]:
			spirit_ids = ["Pakt_Leader", "to_banish_want", "the_two_principles", "endsieg", "gone_over"]
		elif tag == "USA":
			spirit_ids = ["OFN_Leader_of_The_Free_World", "USA_last_bastion_of_liberty", "USA_the_american_depression_4", "USA_jim_crow", "USA_OFN_Buffs_4"]
		elif tag == "OMS":
			spirit_ids = ["OMS_karbyshev_figurehead", "OMS_fueled_by_revenge", "OMS_nothing_left_to_lose", "SIB_terror_bombing", "PRC_savy_army"]
		elif tag == "JAP":
			spirit_ids = ["Sphere_Leader", "JAP_showa_emperor", "JAP_zaibatsu_question", "JAP_legacy_guarded_pearl_exercises"]
		elif tag == "ITA":
			spirit_ids = ["TRI_Founder_IT", "ITA_declining_trade", "ITA_fading_fascism", "ITA_navy_strengthened"]
		elif tag == "WRS":
			spirit_ids = ["RUS_terror_bombing", "WRS_veterans_of_the_long_war", "WRS_agricultural_insecurity", "RUS_warlord_manpower", "RUS_warlord_econ"]
		elif tag == "KOM":
			spirit_ids = ["RUS_terror_bombing", "KOM_syvtyvkartsi", "KOM_clash_of_shadows_c_1", "RUS_syktyvkar_arsenal", "RUS_warlord_manpower"]
		elif tag == "SVR":
			spirit_ids = ["SIB_terror_bombing", "SVR_notso_redarmy", "SVR_black_league_influence_tier_1", "RUS_warlord_manpower", "RUS_warlord_econ"]
		else:
			spirit_ids = ["SIB_terror_bombing", "RUS_warlord_manpower", "RUS_warlord_econ"]

	# Построение карточек духов
	for s_id in spirit_ids:
		var s_data = spirits_registry.get(s_id, null)
		var sp_name := ""
		var sp_icon := ""
		var sp_desc := ""
		var sp_effects := ""

		if s_data != null:
			sp_name = s_data["name"]
			sp_icon = s_data["icon"]
			sp_desc = s_data["desc"]
			sp_effects = s_data["effects"]
		else:
			sp_name = s_id.replace("_", " ").capitalize()
			sp_icon = "res://assets/gfx/interface/war_support_icon.png"
			sp_desc = "Национальный дух и системный фактор, формирующий положение державы."
			sp_effects = "• Влияние на боеспособность и экономику нации."

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(46, 46)

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.08, 0.10, 0.90)
		sb.border_color = Color(0.18, 0.50, 0.45, 0.85)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_left = 2
		sb.corner_radius_bottom_right = 2
		card.add_theme_stylebox_override("panel", sb)

		var icon_rect := TextureRect.new()
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(36, 36)

		var tex = TNOTheme.get_texture(sp_icon)
		if tex == null:
			tex = TNOTheme.get_texture("res://assets/gfx/interface/war_support_icon.png")
		icon_rect.texture = tex

		card.add_child(icon_rect)
		card.tooltip_text = "┌── [%s] ──\n│ ТИП: Стартовый национальный дух // Кризис\n│ СТАТУС: Действует с 1 января 1962 г.\n├─────────────────────────────────────────\n│ ОПИСАНИЕ:\n│ %s\n├─────────────────────────────────────────\n│ СТРАТЕГИЧЕСКИЕ ЭФФЕКТЫ:\n%s" % [sp_name, sp_desc, sp_effects]

		spirits_grid.add_child(card)


# ==============================================================================
# 6. КНОПКИ ДЕЙСТВИЙ И ЗАПУСК КАМПАНИИ
# ==============================================================================

func _on_toggle_focus_filter() -> void:
	if map_background != null:
		var new_state = not map_background.is_focus_filter_active
		map_background.apply_focus_highlight(new_state)
		if btn_filter_focus != null:
			btn_filter_focus.text = _tr("LOBBY_FILTER_FOCUS_ON", "[ ★ ТОЛЬКО С ФОКУСАМИ: ВКЛ ]") if new_state else _tr("LOBBY_FILTER_FOCUS_OFF", "[ ★ ТОЛЬКО С ФОКУСАМИ: ВЫКЛ ]")
			btn_filter_focus.add_theme_color_override("font_color", Color(0.2, 0.95, 0.85) if new_state else Color(0.5, 0.6, 0.65))
	_play_sfx_click()


func _on_exit_pressed() -> void:
	_play_sfx_click()
	returned_to_main_menu.emit()
	if get_tree() != null:
		get_tree().change_scene_to_file("res://ui/screens/main_menu.tscn")


func _on_scenario_options_pressed() -> void:
	_play_sfx_click()
	_open_scenario_options_modal()


func _open_scenario_options_modal() -> void:
	if options_modal != null and is_instance_valid(options_modal):
		options_modal.queue_free()

	options_modal = PanelContainer.new()
	options_modal.custom_minimum_size = Vector2(420, 360)
	options_modal.anchors_preset = Control.PRESET_CENTER
	options_modal.position = (size - Vector2(420, 360)) * 0.5
	TNOTheme.apply_panel_style(options_modal, TNOTheme.COLOR_BORDER_AMBER, Color(0.05, 0.08, 0.10, 0.98), 2, 4)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	options_modal.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = _tr("LOBBY_SCENARIO_OPTIONS_TITLE", "=== ПАРАМЕТРЫ СЦЕНАРИЯ TNO ===")
	title.add_theme_color_override("font_color", Color(1.0, 0.80, 0.25))
	title.add_theme_font_size_override("font_size", 13)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Сложность
	var diff_label := Label.new()
	diff_label.text = _tr("LOBBY_DIFFICULTY_LEVEL", "УРОВЕНЬ СЛОЖНОСТИ:")
	diff_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.85))
	vbox.add_child(diff_label)

	var diff_hbox := HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(diff_hbox)

	var b_obs := Button.new()
	b_obs.text = _tr("LOBBY_DIFF_OBSERVER", "НАБЛЮДАТЕЛЬ")
	b_obs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TNOTheme.apply_button_style(b_obs, TNOTheme.COLOR_BORDER_CYAN if current_config.difficulty == GAME_SESSION_SCRIPT.Difficulty.OBSERVER else TNOTheme.COLOR_BORDER_DIM)
	b_obs.pressed.connect(func():
		current_config.difficulty = GAME_SESSION_SCRIPT.Difficulty.OBSERVER
		_open_scenario_options_modal()
	)
	diff_hbox.add_child(b_obs)

	var b_strat := Button.new()
	b_strat.text = _tr("LOBBY_DIFF_STRATEGIST", "СТРАТЕГ")
	b_strat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TNOTheme.apply_button_style(b_strat, TNOTheme.COLOR_BORDER_AMBER if current_config.difficulty == GAME_SESSION_SCRIPT.Difficulty.STRATEGIST else TNOTheme.COLOR_BORDER_DIM)
	b_strat.pressed.connect(func():
		current_config.difficulty = GAME_SESSION_SCRIPT.Difficulty.STRATEGIST
		_open_scenario_options_modal()
	)
	diff_hbox.add_child(b_strat)

	var b_crisis := Button.new()
	b_crisis.text = _tr("LOBBY_DIFF_CRISIS", "КРИЗИС")
	b_crisis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TNOTheme.apply_button_style(b_crisis, TNOTheme.COLOR_BORDER_RED if current_config.difficulty == GAME_SESSION_SCRIPT.Difficulty.CRISIS else TNOTheme.COLOR_BORDER_DIM)
	b_crisis.pressed.connect(func():
		current_config.difficulty = GAME_SESSION_SCRIPT.Difficulty.CRISIS
		_open_scenario_options_modal()
	)
	diff_hbox.add_child(b_crisis)

	# Чекбоксы правил
	var chk_anarchy := CheckBox.new()
	chk_anarchy.text = _tr("LOBBY_OPT_ANARCHY", "Таймер анархии в Германии")
	chk_anarchy.button_pressed = current_config.rules.get("german_anarchy_timer", true)
	chk_anarchy.toggled.connect(func(v: bool): current_config.rules["german_anarchy_timer"] = v)
	TNOTheme.apply_checkbox_style(chk_anarchy, TNOTheme.COLOR_BORDER_CYAN)
	vbox.add_child(chk_anarchy)

	var chk_defcon := CheckBox.new()
	chk_defcon.text = _tr("LOBBY_OPT_DEFCON", "Динамическая ядерная шкала DEFCON")
	chk_defcon.button_pressed = current_config.rules.get("dynamic_nuclear_defcon", true)
	chk_defcon.toggled.connect(func(v: bool): current_config.rules["dynamic_nuclear_defcon"] = v)
	TNOTheme.apply_checkbox_style(chk_defcon, TNOTheme.COLOR_BORDER_CYAN)
	vbox.add_child(chk_defcon)

	var chk_ironman := CheckBox.new()
	chk_ironman.text = _tr("LOBBY_OPT_IRONMAN", "Режим «Железная воля» (Ironman)")
	chk_ironman.button_pressed = current_config.ironman_mode
	chk_ironman.toggled.connect(func(v: bool): current_config.ironman_mode = v)
	TNOTheme.apply_checkbox_style(chk_ironman, TNOTheme.COLOR_BORDER_AMBER)
	vbox.add_child(chk_ironman)

	# Кнопка закрытия
	var b_close := Button.new()
	b_close.text = _tr("LOBBY_OPT_CLOSE", "[ ПРИМЕНИТЬ И ЗАКРЫТЬ ]")
	b_close.custom_minimum_size = Vector2(0, 36)
	TNOTheme.apply_button_style(b_close, TNOTheme.COLOR_BORDER_CYAN, Color(0.08, 0.18, 0.16, 0.95))
	b_close.pressed.connect(func():
		options_modal.queue_free()
		options_modal = null
	)
	vbox.add_child(b_close)

	add_child(options_modal)


func _on_start_campaign_pressed() -> void:
	_play_sfx_launch()

	current_config.selected_country_tag = selected_tag

	var session = _get_session()
	if session != null:
		session.bootstrap_new_game(current_config)
	elif get_tree() != null:
		get_tree().change_scene_to_file("res://ui/screens/terminal_main.tscn")

	campaign_launched.emit(current_config)


# ==============================================================================
# 7. ЗВУКОВЫЕ ЭФФЕКТЫ (AUDIO CONTROLLER HELPERS)
# ==============================================================================

func _play_sfx_click() -> void:
	var sfx = _get_terminal_sfx()
	if sfx != null:
		sfx.play_switch_click(950.0, 0.035)
	elif has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("click_default")


func _play_sfx_switch() -> void:
	var sfx = _get_terminal_sfx()
	if sfx != null:
		sfx.play_switch_click(720.0, 0.045)
	elif has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("click_default")


func _play_sfx_hover() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_menu_over")


func _play_sfx_warmup() -> void:
	var sfx = _get_terminal_sfx()
	if sfx != null:
		sfx.play_crt_warmup()


func _play_sfx_launch() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("start_game_01")
	var sfx = _get_terminal_sfx()
	if sfx != null:
		sfx.play_telegraph_chirp()


func _get_terminal_sfx() -> TerminalSoundFx:
	if audio_controller != null:
		return audio_controller.get_node_or_null("TerminalSoundFx") as TerminalSoundFx
	return null


func _get_session() -> Node:
	if has_node("/root/GameSession"):
		return get_node("/root/GameSession")
	var fallback = get_tree().root.get_node_or_null("GameSession") if get_tree() != null else null
	return fallback


func _tr(key: String, fallback: String) -> String:
	var loc = get_node_or_null("/root/LocalizationManager")
	if loc != null:
		return loc.tr_key(key, fallback)
	return fallback
