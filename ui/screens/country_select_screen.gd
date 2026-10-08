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
const CountrySelectDossierBuilderScript = preload("res://ui/screens/controllers/country_select_dossier_builder.gd")

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
	CountrySelectDossierBuilderScript.build_parties_breakdown(self, tag, current_parties_breakdown, party_legend_container)


func _on_pie_chart_draw() -> void:
	CountrySelectDossierBuilderScript.draw_pie_chart(pie_chart_control, current_parties_breakdown)


# ==============================================================================
# 5. КАБИНЕТ МИНИСТРОВ (CABINET OF MINISTERS)
# ==============================================================================

func _populate_cabinet_ministers(tag: String, dossier: Dictionary) -> void:
	CountrySelectDossierBuilderScript.populate_cabinet_ministers(ministers_grid, tag, dossier)



# ==============================================================================
# 6. НАЦИОНАЛЬНЫЕ ДУХИ И КРИЗИСЫ (NATIONAL SPIRITS GRID)
# ==============================================================================

func _populate_national_spirits_grid(tag: String, dossier: Dictionary) -> void:
	CountrySelectDossierBuilderScript.populate_national_spirits_grid(spirits_grid, tag, dossier)

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
