class_name MainMenu
extends Control

##
## MainMenu: Главный терминал управления кампанией TNO
##
## Реализует аутентичный интерфейс TNO (frontendmainview.gui):
## - Полноэкранный фоновый арт (TNO 1962 / сабмод 2WRW)
## - Верхние логотипы (Paradox / Console & TNO Last Days of Europe)
## - Центральный триптих menupics с цитатами и прямым выбором театров
## - Плеер TNO Radio с официальным саундтреком
## - Стейт-машина: TITULAR -> THEATER_SELECT -> CAMPAIGN_SETUP -> SETTINGS
##

enum MenuState {
	TITULAR,
	THEATER_SELECT,
	CAMPAIGN_SETUP,
	SETTINGS
}

const LEADER_CARD_SCENE = preload("res://ui/components/leader_card.tscn")
const LeaderCardScript = preload("res://ui/components/leader_card.gd")
const GameSessionScript = preload("res://core/systems/game_session.gd")

const BG_PATH_DEFAULT = "res://assets/gfx/interface/main_menu/mainmenu_bg.png"
const BG_PATH_SUBMOD = "res://assets/gfx/interface/main_menu/mainmenu_bg_submod.png"
const LOGO_GAME_PATH = "res://assets/gfx/interface/main_menu/logo_game.png"
const LOGO_TNO_PATH = "res://assets/gfx/interface/main_menu/logo_tno_MT.png"
const MENUPICS_PATH = "res://assets/gfx/interface/main_menu/menupics.png"

var current_state: MenuState = MenuState.TITULAR
var selected_theater_index: int = 0
var selected_tag: String = "KOM"
var config: RefCounted
var current_bg_is_submod: bool = false

signal leader_selected(leader: LeaderResource)

# --- UI Containers ---
@onready var titular_panel: Control = $TitularPanel
@onready var theater_panel: Control = $TheaterPanel
@onready var setup_panel: Control = $SetupPanel
@onready var settings_panel: Control = $SettingsPanel
@onready var crt_overlay: ColorRect = $CRTOverlay

# --- Background & Logos ---
@onready var background_texture: TextureRect = $BackgroundTexture
@onready var logo_game: TextureRect = get_node_or_null("TopBar/LogoGame")
@onready var logo_tno: TextureRect = get_node_or_null("TopBar/LogoTNO")

# --- Titular elements ---
@onready var menupics_texture: TextureRect = get_node_or_null("TitularPanel/CenterArea/MenuPicsContainer/PicsTexture")
@onready var zone_left: Button = get_node_or_null("TitularPanel/CenterArea/MenuPicsContainer/HoverZoneLeft")
@onready var zone_center: Button = get_node_or_null("TitularPanel/CenterArea/MenuPicsContainer/HoverZoneCenter")
@onready var zone_right: Button = get_node_or_null("TitularPanel/CenterArea/MenuPicsContainer/HoverZoneRight")
@onready var quote_badge: Label = get_node_or_null("TitularPanel/CenterArea/QuoteBadge")

@onready var btn_new_game: Button = get_node_or_null("TitularPanel/CenterArea/MenuButtons/NewGameButton")
@onready var btn_load_game: Button = get_node_or_null("TitularPanel/CenterArea/MenuButtons/LoadGameButton")
@onready var btn_settings: Button = get_node_or_null("TitularPanel/CenterArea/MenuButtons/SettingsButton")
@onready var btn_exit: Button = get_node_or_null("TitularPanel/CenterArea/MenuButtons/ExitButton")

@onready var btn_change_bg: Button = get_node_or_null("TitularPanel/CenterArea/UtilityHBox/ChangeBgButton")
@onready var btn_language: Button = get_node_or_null("TitularPanel/CenterArea/UtilityHBox/LanguageButton")
@onready var titular_log: Label = get_node_or_null("TitularPanel/CenterArea/UtilityHBox/StatusLabel")
@onready var lbl_tno_title: Label = get_node_or_null("TitularPanel/CenterArea/FooterHBox/TnoTitleLabel")
@onready var lbl_version: Label = get_node_or_null("TitularPanel/CenterArea/FooterHBox/VersionLabel")

# --- Radio elements ---
@onready var lbl_radio_title: Label = get_node_or_null("TitularPanel/CenterArea/RadioBar/HBox/RadioLabel")
@onready var btn_prev_track: Button = get_node_or_null("TitularPanel/CenterArea/RadioBar/HBox/PrevTrackBtn")
@onready var btn_play_pause: Button = get_node_or_null("TitularPanel/CenterArea/RadioBar/HBox/PlayPauseBtn")
@onready var btn_next_track: Button = get_node_or_null("TitularPanel/CenterArea/RadioBar/HBox/NextTrackBtn")
@onready var lbl_current_track: Label = get_node_or_null("TitularPanel/CenterArea/RadioBar/HBox/CurrentTrackLabel")

# --- Theater & Leader elements ---
@onready var theater_title: Label = get_node_or_null("TheaterPanel/VBox/Title")
@onready var theater_tab_container: HBoxContainer = get_node_or_null("TheaterPanel/VBox/TheaterTabBar")
@onready var leader_cards_container: VBoxContainer = get_node_or_null("TheaterPanel/VBox/MainHBox/LeftColumn/Scroll/CardsList")
@onready var search_box: LineEdit = get_node_or_null("TheaterPanel/VBox/MainHBox/LeftColumn/SearchBox")
@onready var map_widget: CountrySelectMapWidget = get_node_or_null("TheaterPanel/VBox/MainHBox/MapColumn/CountrySelectMapWidget")
@onready var dossier_name: Label = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/HeaderHBox/MetaVBox/CountryName")
@onready var dossier_leader: Label = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/HeaderHBox/MetaVBox/LeaderName")
@onready var dossier_ideology: Label = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/HeaderHBox/MetaVBox/IdeologyLabel")
@onready var dossier_loyalty: Label = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/HeaderHBox/MetaVBox/LoyaltyLabel")
@onready var dossier_bonus: Label = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/HeaderHBox/MetaVBox/BonusLabel")
@onready var dossier_stats: Label = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/HeaderHBox/MetaVBox/StatsLabel")
@onready var dossier_traits: Label = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/HeaderHBox/MetaVBox/TraitsLabel")
@onready var focus_tree_preview: FocusTreePreviewWidget = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/FocusTreePreviewWidget")
@onready var dossier_lore: RichTextLabel = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/LoreText")
@onready var dossier_portrait_frame: LeaderPortraitFrame = get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/HeaderHBox/DossierPortraitFrame")
@onready var btn_back_to_title: Button = $TheaterPanel/VBox/BottomBar/BackToTitleButton
@onready var btn_proceed_to_setup: Button = $TheaterPanel/VBox/BottomBar/ProceedToSetupButton

# --- Setup elements ---
@onready var setup_title: Label = get_node_or_null("SetupPanel/VBox/Title")
@onready var setup_diff_label: Label = get_node_or_null("SetupPanel/VBox/DiffLabel")
@onready var btn_diff_observer: Button = $SetupPanel/VBox/DiffHBox/ObserverButton
@onready var btn_diff_strategist: Button = $SetupPanel/VBox/DiffHBox/StrategistButton
@onready var btn_diff_crisis: Button = $SetupPanel/VBox/DiffHBox/CrisisButton
@onready var setup_rules_label: Label = get_node_or_null("SetupPanel/VBox/RulesLabel")
@onready var chk_anarchy: CheckBox = $SetupPanel/VBox/RulesGrid/AnarchyCheck
@onready var chk_defcon: CheckBox = $SetupPanel/VBox/RulesGrid/DefconCheck
@onready var chk_incidents: CheckBox = $SetupPanel/VBox/RulesGrid/IncidentsCheck
@onready var chk_ironman: CheckBox = $SetupPanel/VBox/RulesGrid/IronmanCheck
@onready var btn_timestep: Button = $SetupPanel/VBox/RulesGrid/TimeStepButton
@onready var btn_back_to_leaders: Button = $SetupPanel/VBox/BottomBar/BackToLeadersButton
@onready var btn_start_game: Button = $SetupPanel/VBox/BottomBar/StartCampaignButton

# --- Settings elements ---
const SETTINGS_LANG_SCENE = preload("res://ui/screens/settings_language.tscn")
const SETTINGS_TERMINAL_SCENE = preload("res://ui/screens/settings_terminal.tscn")

@onready var settings_title: Label = get_node_or_null("SettingsPanel/VBox/Title")
@onready var lbl_curvature: Label = get_node_or_null("SettingsPanel/VBox/Grid/Label1")
@onready var slider_curvature: HSlider = $SettingsPanel/VBox/Grid/CurvatureSlider
@onready var lbl_scanlines: Label = get_node_or_null("SettingsPanel/VBox/Grid/Label2")
@onready var slider_scanlines: HSlider = $SettingsPanel/VBox/Grid/ScanlineSlider
@onready var lbl_glow: Label = get_node_or_null("SettingsPanel/VBox/Grid/Label3")
@onready var slider_glow: HSlider = $SettingsPanel/VBox/Grid/GlowSlider
@onready var lbl_aberration: Label = get_node_or_null("SettingsPanel/VBox/Grid/Label4")
@onready var slider_aberration: HSlider = $SettingsPanel/VBox/Grid/AberrationSlider
@onready var lbl_volume: Label = get_node_or_null("SettingsPanel/VBox/Grid/Label5")
@onready var slider_volume: HSlider = $SettingsPanel/VBox/Grid/VolumeSlider
@onready var btn_lang_settings: Button = $SettingsPanel/VBox/BottomBar/LangSettingsButton
@onready var btn_save_settings: Button = $SettingsPanel/VBox/BottomBar/SaveSettingsButton

var card_nodes: Array = []


func _ready() -> void:
	config = _get_session().current_config
	_load_textures()
	_connect_events()
	_setup_radio()
	_update_localized_ui()
	_populate_theater_tabs()
	_select_theater(0)
	_switch_state(MenuState.TITULAR)
	_apply_crt_to_overlay()
	_attach_audio()


func _load_textures() -> void:
	# Фоновый арт
	_set_background_texture(BG_PATH_DEFAULT)

	# Логотипы
	if logo_game != null:
		var tex_lg = _load_texture(LOGO_GAME_PATH)
		if tex_lg != null:
			logo_game.texture = tex_lg

	if logo_tno != null:
		var tex_tno = _load_texture(LOGO_TNO_PATH)
		if tex_tno != null:
			logo_tno.texture = tex_tno

	# Триптих menupics
	if menupics_texture != null:
		var tex_mp = _load_texture(MENUPICS_PATH)
		if tex_mp != null:
			menupics_texture.texture = tex_mp


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img = Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _load_image(path: String) -> Image:
	var tex = _load_texture(path)
	if tex != null:
		return tex.get_image()
	return null


func _set_background_texture(path: String) -> void:
	if background_texture != null:
		var tex = _load_texture(path)
		if tex != null:
			background_texture.texture = tex


func _connect_events() -> void:
	# Titular кнопки
	if btn_new_game != null:
		btn_new_game.pressed.connect(func(): _switch_state(MenuState.THEATER_SELECT))
	if btn_load_game != null:
		btn_load_game.pressed.connect(_on_load_game_pressed)
	if btn_settings != null:
		btn_settings.pressed.connect(_on_open_system_settings)
	if btn_exit != null:
		btn_exit.pressed.connect(func(): get_tree().quit())
	if btn_language != null:
		btn_language.pressed.connect(_on_open_language_settings)
	if btn_change_bg != null:
		btn_change_bg.pressed.connect(_on_toggle_background)

	# Menupics интерактивные зоны
	if zone_left != null:
		zone_left.mouse_entered.connect(func(): _on_menupic_hover(1))
		zone_left.pressed.connect(func(): _on_menupic_click("theater_gcw"))
	if zone_center != null:
		zone_center.mouse_entered.connect(func(): _on_menupic_hover(2))
		zone_center.pressed.connect(func(): _on_menupic_click("theater_smuta"))
	if zone_right != null:
		zone_right.mouse_entered.connect(func(): _on_menupic_hover(3))
		zone_right.pressed.connect(func(): _on_menupic_click("theater_superpowers"))

	# Radio кнопки
	if btn_prev_track != null:
		btn_prev_track.pressed.connect(_on_prev_track_pressed)
	if btn_play_pause != null:
		btn_play_pause.pressed.connect(_on_play_pause_pressed)
	if btn_next_track != null:
		btn_next_track.pressed.connect(_on_next_track_pressed)

	# Theater
	btn_back_to_title.pressed.connect(func(): _switch_state(MenuState.TITULAR))
	btn_proceed_to_setup.pressed.connect(func(): _switch_state(MenuState.CAMPAIGN_SETUP))
	if map_widget != null:
		map_widget.country_selected.connect(_on_map_country_selected)
	if search_box != null:
		search_box.text_changed.connect(_on_search_text_changed)

	# Setup
	btn_diff_observer.pressed.connect(func(): _set_difficulty(GameSessionScript.Difficulty.OBSERVER))
	btn_diff_strategist.pressed.connect(func(): _set_difficulty(GameSessionScript.Difficulty.STRATEGIST))
	btn_diff_crisis.pressed.connect(func(): _set_difficulty(GameSessionScript.Difficulty.CRISIS))
	btn_timestep.pressed.connect(_toggle_timestep)

	btn_back_to_leaders.pressed.connect(func(): _switch_state(MenuState.THEATER_SELECT))
	btn_start_game.pressed.connect(_on_launch_campaign)

	# Settings
	slider_curvature.value_changed.connect(func(v): _update_crt_param("curvature", v))
	slider_scanlines.value_changed.connect(func(v): _update_crt_param("scanline_intensity", v))
	slider_glow.value_changed.connect(func(v): _update_crt_param("brightness_boost", v))
	slider_aberration.value_changed.connect(func(v): _update_crt_param("chromatic_aberration", v))
	slider_volume.value_changed.connect(func(v): AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(v)))
	btn_lang_settings.pressed.connect(_on_open_system_settings)
	btn_save_settings.pressed.connect(func(): _switch_state(MenuState.TITULAR))

	# Localization
	if has_node("/root/LocalizationManager"):
		var loc = get_node("/root/LocalizationManager")
		if not loc.locale_changed.is_connected(_on_locale_changed):
			loc.locale_changed.connect(_on_locale_changed)


func _attach_audio() -> void:
	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		am.attach_ui_sounds(self)


func _setup_radio() -> void:
	if not has_node("/root/AudioManager"):
		return
	var am = get_node("/root/AudioManager")

	if not am.track_changed.is_connected(_on_radio_track_changed):
		am.track_changed.connect(_on_radio_track_changed)
	if not am.playback_state_changed.is_connected(_on_radio_playback_changed):
		am.playback_state_changed.connect(_on_radio_playback_changed)

	# Запуск заглавной темы TNO при старте
	am.play_music(0, false)
	_update_radio_ui(am.get_current_track_title(), not am.is_music_paused)


func _on_prev_track_pressed() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").prev_track()


func _on_play_pause_pressed() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").toggle_pause()


func _on_next_track_pressed() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").next_track()


func _on_radio_track_changed(_idx: int, title: String) -> void:
	_update_radio_ui(title, true)


func _on_radio_playback_changed(is_playing: bool) -> void:
	if btn_play_pause != null:
		btn_play_pause.text = "❚❚" if is_playing else "▶"


func _update_radio_ui(title: String, is_playing: bool) -> void:
	if lbl_current_track != null:
		lbl_current_track.text = title
	if btn_play_pause != null:
		btn_play_pause.text = "❚❚" if is_playing else "▶"


func _on_toggle_background() -> void:
	current_bg_is_submod = not current_bg_is_submod
	var path = BG_PATH_SUBMOD if current_bg_is_submod else BG_PATH_DEFAULT
	_set_background_texture(path)
	if btn_change_bg != null and has_node("/root/LocalizationManager"):
		var loc = get_node("/root/LocalizationManager")
		var mode_name = "2WRW" if current_bg_is_submod else "1962"
		btn_change_bg.text = "[ 🖼 %s: %s ]" % [loc.tr_key("BTN_CHANGE_BG", "ФОН"), mode_name]


func _on_menupic_hover(zone_idx: int) -> void:
	if quote_badge == null:
		return
	var loc = get_node_or_null("/root/LocalizationManager")
	var key = "TNO_MENUPIC_TOOLTIP_%d" % zone_idx
	var fallback = "«Я знаю, чего хочу и как этого добиться.»"
	if zone_idx == 2:
		fallback = "«Наша боль не мешает нам сохранять спокойствие...»"
	elif zone_idx == 3:
		fallback = "«Кто хочет жить в покое, пусть прячется...»"
	quote_badge.text = loc.tr_key(key, fallback) if loc != null else fallback


func _on_menupic_click(theater_id: String) -> void:
	_select_theater_by_id(theater_id)
	_switch_state(MenuState.THEATER_SELECT)


func _select_theater_by_id(target_id: String) -> void:
	var theaters = _get_session().get_theaters()
	for i in range(theaters.size()):
		var t_id = str(theaters[i].get("id", ""))
		if t_id == target_id:
			_select_theater(i)
			return
	_select_theater(0)


func _on_open_system_settings() -> void:
	if crt_overlay != null:
		crt_overlay.visible = false
	if titular_panel != null:
		titular_panel.visible = false
	var term = SETTINGS_TERMINAL_SCENE.instantiate()
	add_child(term)
	var prev_state = current_state
	term.closed.connect(func():
		term.queue_free()
		if titular_panel != null:
			titular_panel.visible = true
		if crt_overlay != null:
			crt_overlay.visible = true
		_switch_state(prev_state)
		_update_localized_ui()
		_apply_crt_to_overlay()
	)


func _on_open_language_settings() -> void:
	if crt_overlay != null:
		crt_overlay.visible = false
	if titular_panel != null:
		titular_panel.visible = false
	var lang_screen = SETTINGS_LANG_SCENE.instantiate()
	add_child(lang_screen)
	var prev_state = current_state
	lang_screen.closed.connect(func():
		lang_screen.queue_free()
		if titular_panel != null:
			titular_panel.visible = true
		if crt_overlay != null:
			crt_overlay.visible = true
		_switch_state(prev_state)
		_update_localized_ui()
		_apply_crt_to_overlay()
	)


func _on_locale_changed(_locale_code: String) -> void:
	_update_localized_ui()


func _update_localized_ui() -> void:
	if not has_node("/root/LocalizationManager"):
		return
	var loc = get_node("/root/LocalizationManager")

	# 1. Titular Panel
	if btn_new_game != null:
		btn_new_game.text = "[ 1. %s ]" % loc.tr_key("MENU_NEW_CAMPAIGN", "НОВАЯ КАМПАНИЯ")
	if btn_load_game != null:
		btn_load_game.text = "[ 2. %s ]" % loc.tr_key("MENU_LOAD_ARCHIVE", "ЗАГРУЗИТЬ АРХИВ")
	if btn_settings != null:
		btn_settings.text = "[ 3. %s ]" % loc.tr_key("MENU_CONFIG", "НАСТРОЙКИ")
	if btn_exit != null:
		btn_exit.text = "[ 4. %s ]" % loc.tr_key("MENU_EXIT", "ВЫХОД")

	if btn_change_bg != null:
		var mode_name = "2WRW" if current_bg_is_submod else "1962"
		btn_change_bg.text = "[ 🖼 %s: %s ]" % [loc.tr_key("BTN_CHANGE_BG", "ФОН"), mode_name]
	if btn_language != null:
		var cur_loc = loc.current_locale.to_upper()
		btn_language.text = "[ 🌐 %s: %s ]" % [loc.tr_key("SETTINGS_TAB_LANGUAGE", "ЯЗЫК").trim_prefix("4. "), cur_loc]

	if lbl_radio_title != null:
		lbl_radio_title.text = loc.tr_key("RADIO_HEADER", "РАДИОСТАНЦИЯ TNO // В ЭФИРЕ:")
	if quote_badge != null:
		quote_badge.text = loc.tr_key("TNO_MENUPIC_TOOLTIP_1", "«Я знаю, чего хочу и как этого добиться.»")

	if titular_log != null:
		titular_log.text = loc.tr_key("SYS_STATUS_READY", "СИСТЕМА: ГОТОВА К АВТОРИЗАЦИИ // УРОВЕНЬ ДОСТУПА: ВЫСШИЙ")
	if lbl_tno_title != null:
		lbl_tno_title.text = loc.tr_key("TNO_TITLE", "THE NEW ORDER // LAST DAYS OF EUROPE")

	if has_node("/root/AudioManager"):
		var am = get_node("/root/AudioManager")
		_update_radio_ui(am.get_current_track_title(), not am.is_music_paused)

	# 2. Theater Panel
	if theater_title != null:
		theater_title.text = loc.tr_key("MENU_THEATER_TITLE", "=== ТЕАТРЫ ВОЕННЫХ ДЕЙСТВИЙ И ДОСЬЕ ПРЕТЕНДЕНТОВ ===")
	btn_back_to_title.text = "[ < %s ]" % loc.tr_key("BTN_BACK_TO_TITLE", "В ГЛАВНОЕ МЕНЮ")
	btn_proceed_to_setup.text = "[ %s > ]" % loc.tr_key("BTN_PROCEED_TO_SETUP", "ПЕРЕЙТИ К НАСТРОЙКЕ")
	_populate_theater_tabs()

	# 3. Setup Panel
	if setup_title != null:
		setup_title.text = loc.tr_key("SETUP_TITLE", "=== ПАРАМЕТРЫ КАМПАНИИ И ПРАВИЛА МИРА ===")
	if setup_diff_label != null:
		setup_diff_label.text = loc.tr_key("SETUP_DIFF_HEADER", "УРОВЕНЬ СЛОЖНОСТИ СИМУЛЯЦИИ:")
	btn_diff_observer.text = "[ %s ]" % loc.tr_key("DIFF_OBSERVER", "НАБЛЮДАТЕЛЬ (ИСТОРИЯ)")
	btn_diff_strategist.text = "[ %s ]" % loc.tr_key("DIFF_STRATEGIST", "СТРАТЕГ (КАНОН)")
	btn_diff_crisis.text = "[ %s ]" % loc.tr_key("DIFF_CRISIS", "КРИЗИС (IRONMAN)")
	if setup_rules_label != null:
		setup_rules_label.text = loc.tr_key("SETUP_RULES_HEADER", "ГЛОБАЛЬНЫЕ КРИЗИСНЫЕ ПРОТОКОЛЫ:")
	chk_anarchy.text = loc.tr_key("RULE_ANARCHY", "ТАЙМЕР НЕМЕЦКОЙ АНАРХИИ (GCW)")
	chk_defcon.text = loc.tr_key("RULE_DEFCON", "ДИНАМИЧЕСКИЙ DEFCON И ЯДЕРНАЯ УГРОЗА")
	chk_incidents.text = loc.tr_key("RULE_INCIDENTS", "ПОГРАНИЧНЫЕ ИНЦИДЕНТЫ И ЭСКАЛАЦИЯ")
	chk_ironman.text = loc.tr_key("RULE_IRONMAN", "РЕЖИМ ЖЕЛЕЗНАЯ ВОЛЯ (IRONMAN)")
	if btn_timestep != null:
		var step_str = (loc.tr_key("TIMESTEP_WEEKLY", "1 ХОД = 1 НЕДЕЛЯ") if loc != null else "1 ХОД = 1 НЕДЕЛЯ") if config.time_step_mode == "weekly" else (loc.tr_key("TIMESTEP_MONTHLY", "1 ХОД = 1 МЕСЯЦ") if loc != null else "1 ХОД = 1 МЕСЯЦ")
		var step_title = loc.tr_key("TIMESTEP_HEADER", "ШАГ ВРЕМЕНИ") if loc != null else "ШАГ ВРЕМЕНИ"
		btn_timestep.text = "%s: [ %s ]" % [step_title, step_str]
	btn_back_to_leaders.text = "[ < %s ]" % loc.tr_key("BTN_BACK_TO_LEADERS", "НАЗАД К ЛИДЕРАМ")
	btn_start_game.text = "[ %s >> ]" % loc.tr_key("BTN_START_CAMPAIGN", "ЗАПУСК КАМПАНИИ")

	# 4. Settings Panel
	if settings_title != null:
		settings_title.text = loc.tr_key("SETTINGS_TITLE", "=== КОНФИГУРАЦИЯ ЭЛТ-МОНИТОРА И АУДИОТРАКТА ===")
	if lbl_curvature != null:
		lbl_curvature.text = loc.tr_key("CRT_CURVATURE", "КРИВИЗНА ЛИНЗЫ ЭЛТ:")
	if lbl_scanlines != null:
		lbl_scanlines.text = loc.tr_key("CRT_SCANLINES", "ПЛОТНОСТЬ СКАНЛАЙНОВ:")
	if lbl_glow != null:
		lbl_glow.text = loc.tr_key("CRT_GLOW", "СВЕЧЕНИЕ ФОСФОРА (ЯРКОСТЬ):")
	if lbl_aberration != null:
		lbl_aberration.text = loc.tr_key("CRT_ABERRATION", "ХРОМАТИЧЕСКАЯ АБЕРРАЦИЯ:")
	if lbl_volume != null:
		lbl_volume.text = loc.tr_key("AUDIO_VOLUME", "ГРОМКОСТЬ ТЕРМИНАЛА:")
	btn_lang_settings.text = "[ %s ]" % loc.tr_key("MENU_LANGUAGE", "ЯЗЫКОВОЙ ПАКЕТ")
	btn_save_settings.text = "[ %s ]" % loc.tr_key("BTN_SAVE_AND_EXIT", "СОХРАНИТЬ И ВЕРНУТЬСЯ")

	_refresh_setup_ui()
	_update_dossier_panel(_get_session().get_country_dossier(selected_tag))


# ==============================================================================
# ПЕРЕКЛЮЧЕНИЕ СОСТОЯНИЙ (STATE MACHINE)
# ==============================================================================

func _switch_state(new_state: MenuState) -> void:
	current_state = new_state
	titular_panel.visible = (new_state == MenuState.TITULAR)
	theater_panel.visible = (new_state == MenuState.THEATER_SELECT)
	setup_panel.visible = (new_state == MenuState.CAMPAIGN_SETUP)
	settings_panel.visible = (new_state == MenuState.SETTINGS)

	match new_state:
		MenuState.TITULAR:
			if titular_log != null:
				if has_node("/root/LocalizationManager"):
					var loc = get_node("/root/LocalizationManager")
					titular_log.text = loc.tr_key("SYS_STATUS_READY", "СИСТЕМА: ГОТОВА К АВТОРИЗАЦИИ // УРОВЕНЬ ДОСТУПА: ВЫСШИЙ")
				else:
					titular_log.text = "СИСТЕМА: ГОТОВА К АВТОРИЗАЦИИ // УРОВЕНЬ ДОСТУПА: ВЫСШИЙ"
		MenuState.THEATER_SELECT:
			_select_theater(selected_theater_index)
		MenuState.CAMPAIGN_SETUP:
			_refresh_setup_ui()
		MenuState.SETTINGS:
			_refresh_settings_ui()


# ==============================================================================
# ВЫБОР ТЕАТРА И ДОСЬЕ ЛИДЕРА
# ==============================================================================

func _populate_theater_tabs() -> void:
	if theater_tab_container == null:
		return
	for c in theater_tab_container.get_children():
		c.queue_free()

	var loc = get_node_or_null("/root/LocalizationManager")
	var theaters = _get_session().get_theaters()
	for i in range(theaters.size()):
		var t_data = theaters[i]
		var btn = Button.new()
		var t_id = str(t_data.get("id", str(i))).to_upper()
		var default_name = t_data.get("name", "")
		var loc_name = default_name
		if loc != null:
			loc_name = loc.tr_key("THEATER_" + t_id + "_NAME", loc.tr_key("THEATER_" + str(t_data.get("id", "")) + "_NAME", default_name))
		
		var is_active = (i == selected_theater_index)
		btn.text = "► %s ◄" % loc_name if is_active else "[ %s ]" % loc_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)
		if is_active:
			TNOTheme.apply_button_style(btn, TNOTheme.COLOR_BORDER_CYAN, Color(0.08, 0.18, 0.16, 0.95))
		else:
			TNOTheme.apply_button_style(btn, TNOTheme.COLOR_BORDER_AMBER, Color(0.05, 0.08, 0.08, 0.85))

		var captured_idx = i
		btn.pressed.connect(func(): _select_theater(captured_idx))
		theater_tab_container.add_child(btn)

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").attach_ui_sounds(theater_tab_container)


func _select_theater(theater_idx: int) -> void:
	selected_theater_index = theater_idx
	var theaters = _get_session().get_theaters()
	if theater_idx < 0 or theater_idx >= theaters.size():
		return

	# Обновить подсветку табов
	if theater_tab_container != null:
		var tab_children = theater_tab_container.get_children()
		for i in range(tab_children.size()):
			if tab_children[i] is Button:
				var t_btn: Button = tab_children[i]
				var t_data = theaters[i] if i < theaters.size() else {}
				var default_name = t_data.get("name", "")
				var loc = get_node_or_null("/root/LocalizationManager")
				var t_id = str(t_data.get("id", str(i))).to_upper()
				var loc_name = default_name
				if loc != null:
					loc_name = loc.tr_key("THEATER_" + t_id + "_NAME", default_name)
				var is_active = (i == selected_theater_index)
				t_btn.text = "► %s ◄" % loc_name if is_active else "[ %s ]" % loc_name
				if is_active:
					TNOTheme.apply_button_style(t_btn, TNOTheme.COLOR_BORDER_CYAN, Color(0.08, 0.18, 0.16, 0.95))
				else:
					TNOTheme.apply_button_style(t_btn, TNOTheme.COLOR_BORDER_AMBER, Color(0.05, 0.08, 0.08, 0.85))

	var active_theater = theaters[theater_idx]
	var tags = active_theater["tags"]
	var t_id = str(active_theater.get("id", ""))
	if map_widget != null:
		if t_id == "theater_smuta":
			map_widget.focus_preset("RUSSIA")
		elif t_id == "theater_gcw" or t_id == "theater_europe":
			map_widget.focus_preset("EUROPE")
		elif t_id == "theater_sphere":
			map_widget.focus_preset("ASIA")
		elif t_id == "theater_superpowers":
			map_widget.focus_preset("WORLD")
		else:
			map_widget.focus_preset("WORLD")

	if leader_cards_container == null:
		return

	# Очистить старые карточки
	for c in leader_cards_container.get_children():
		c.queue_free()
	card_nodes.clear()

	# Создать карточки лидеров
	for tag in tags:
		var dossier = _get_session().get_country_dossier(tag)
		var card = LEADER_CARD_SCENE.instantiate()
		leader_cards_container.add_child(card)
		card_nodes.append(card)

		var is_sel = (tag == selected_tag)
		card.setup(dossier, is_sel)
		card.card_selected.connect(_on_leader_card_clicked)
		card.card_hovered.connect(_on_leader_card_hovered)

	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").attach_ui_sounds(leader_cards_container)

	if not tags.has(selected_tag) and not tags.is_empty():
		selected_tag = tags[0]

	_update_dossier_panel(_get_session().get_country_dossier(selected_tag))
	_highlight_selected_card()
	if map_widget != null:
		map_widget.select_country(selected_tag, false)


func _on_leader_card_clicked(data: Dictionary) -> void:
	selected_tag = data.get("tag", "KOM")
	_update_dossier_panel(data)
	_highlight_selected_card()
	if map_widget != null:
		map_widget.select_country(selected_tag, true)

	var leader_res: LeaderResource = null
	if data.get("primary_leader_res") is LeaderResource:
		leader_res = data["primary_leader_res"]
	else:
		leader_res = LeaderResource.from_dict(data)
	leader_selected.emit(leader_res)


func _on_map_country_selected(tag: String, dossier: Dictionary) -> void:
	selected_tag = tag
	_update_dossier_panel(dossier)
	_highlight_selected_card()
	_ensure_selected_card_visible()
	var leader_res: LeaderResource = null
	if dossier.get("primary_leader_res") is LeaderResource:
		leader_res = dossier["primary_leader_res"]
	else:
		leader_res = LeaderResource.from_dict(dossier)
	leader_selected.emit(leader_res)


func _on_leader_card_hovered(data: Dictionary) -> void:
	if dossier_portrait_frame != null and dossier_portrait_frame._current_leader_id != str(data.get("leader_id", data.get("tag", ""))):
		_update_dossier_panel(data)


func _highlight_selected_card() -> void:
	for card in card_nodes:
		card.set_selected(card.leader_data.get("tag", "") == selected_tag)


func _ensure_selected_card_visible() -> void:
	for card in card_nodes:
		if card.leader_data.get("tag", "") == selected_tag:
			card.visible = true


func _on_search_text_changed(query: String) -> void:
	var clean = query.strip_edges().to_lower()
	for card in card_nodes:
		var d = card.leader_data
		var c_tag = d.get("tag", "").to_lower()
		var c_name = d.get("name", "").to_lower()
		var c_name_ru = d.get("name_ru", "").to_lower()
		var l_name = d.get("leader_name", "").to_lower()
		var ideo = d.get("ideology", "").to_lower()
		var matches = clean.is_empty() or clean in c_tag or clean in c_name or clean in c_name_ru or clean in l_name or clean in ideo
		card.visible = matches


func _update_dossier_panel(d: Dictionary) -> void:
	var loc = get_node_or_null("/root/LocalizationManager")
	var l_unknown = loc.tr_key("UNKNOWN", "НЕИЗВЕСТНО") if loc != null else "НЕИЗВЕСТНО"
	var l_leader = loc.tr_key("LEADER", "ЛИДЕР") if loc != null else "ЛИДЕР"
	var l_ideology = loc.tr_key("DOSSIER_IDEOLOGY", "ИДЕОЛОГИЯ") if loc != null else "ИДЕОЛОГИЯ"
	var l_loyalty = loc.tr_key("DOSSIER_POPULARITY", "ЛОЯЛЬНОСТЬ") if loc != null else "ЛОЯЛЬНОСТЬ"
	var l_cabinet = loc.tr_key("DOSSIER_INFLUENCE", "КАБИНЕТ") if loc != null else "КАБИНЕТ"
	var l_bonus = loc.tr_key("DOSSIER_POWER_BONUS", "БОНУС К ВЛАСТИ") if loc != null else "БОНУС К ВЛАСТИ"
	var l_gdp = loc.tr_key("DOSSIER_GDP", "ВВП") if loc != null else "ВВП"
	var l_res = loc.tr_key("DOSSIER_MANPOWER", "РЕЗЕРВ") if loc != null else "РЕЗЕРВ"
	var l_ind = loc.tr_key("DOSSIER_INDUSTRY", "ПРОМЫШЛЕННОСТЬ") if loc != null else "ПРОМЫШЛЕННОСТЬ"
	var l_traits = loc.tr_key("DOSSIER_TRAITS", "ЧЕРТЫ") if loc != null else "ЧЕРТЫ"
	var unit_b = loc.tr_key("UNIT_BILLION", "млрд") if loc != null else "млрд"
	var unit_men = loc.tr_key("UNIT_MANPOWER", "чел.") if loc != null else "чел."
	var unit_fac = loc.tr_key("UNIT_FACTORIES", "фабрик") if loc != null else "фабрик"
	var turn_unit = loc.tr_key("TURN_UNIT", "ход") if loc != null else "ход"
	var pc_unit = loc.tr_key("POLITICAL_CAPITAL_SHORT", "Полит. капитал (PC)") if loc != null else "Полит. капитал (PC)"
	var default_traits = loc.tr_key("STANDARD_PROFILE", "[СТАНДАРТНЫЙ ПРОФИЛЬ]") if loc != null else "[СТАНДАРТНЫЙ ПРОФИЛЬ]"

	var tag = d.get("tag", "")
	var c_name = d.get("name", l_unknown)
	if loc != null and not tag.is_empty():
		c_name = loc.tr_key(tag, c_name)
	if dossier_name != null:
		dossier_name.text = "┌── %s ──" % c_name.to_upper()

	var leader_name = d.get("leader_name", "UNKNOWN")
	var leader_title = d.get("leader_title", "")
	if loc != null:
		leader_name = loc.tr_key(leader_name, leader_name)
		leader_title = loc.tr_key(leader_title, leader_title)
	var l_full = leader_name
	if not leader_title.is_empty():
		l_full += " (%s)" % leader_title
	if dossier_leader != null:
		dossier_leader.text = "│ %s: %s" % [l_leader, l_full]

	var ideo = d.get("ideology", "")
	var sub_ideo = d.get("sub_ideology", "")
	if loc != null:
		ideo = loc.tr_key(ideo, ideo)
		sub_ideo = loc.tr_key(sub_ideo, sub_ideo)
	if dossier_ideology != null:
		dossier_ideology.text = "│ %s: %s // %s" % [l_ideology, ideo, sub_ideo]

	var pop = float(d.get("popularity", 65.0))
	var infl = float(d.get("cabinet_influence", 70.0))
	if dossier_loyalty != null:
		dossier_loyalty.text = "│ %s: %s %d%% | %s: %d%%" % [l_loyalty, _make_ascii_bar(int(pop), 100), int(pop), l_cabinet, int(infl)]

	var cap_bonus = 1.0 + (infl / 100.0) * 1.5
	var pc_bonus = int(round((pop - 50.0) * 0.4))
	if dossier_bonus != null:
		dossier_bonus.text = "│ %s: +%0.1f CAP/%s | %+d%% %s" % [l_bonus, cap_bonus, turn_unit, pc_bonus, pc_unit]

	var gdp = d.get("starting_gdp", 15.0)
	var mp = d.get("starting_manpower", 50000)
	var ic = d.get("starting_factories", 25)
	if dossier_stats != null:
		dossier_stats.text = "│ %s: $%0.1f %s | %s: %d %s | %s: %d %s" % [l_gdp, gdp, unit_b, l_res, mp, unit_men, l_ind, ic, unit_fac]

	var traits_str = ""
	for t in d.get("traits", []):
		var t_trans = loc.tr_key(str(t), str(t)) if loc != null else str(t)
		traits_str += "[%s]  " % t_trans
	if dossier_traits != null:
		dossier_traits.text = "└─ %s: %s" % [l_traits, traits_str if not traits_str.is_empty() else default_traits]

	if dossier_lore != null:
		var lore_text = d.get("lore", "")
		if loc != null and not tag.is_empty():
			lore_text = loc.tr_key(tag + "_lore", lore_text)
		dossier_lore.text = "[color=#a0ccb8]%s[/color]" % lore_text

	if dossier_portrait_frame != null:
		var is_tag_change = (dossier_portrait_frame._current_leader_id != str(d.get("leader_id", d.get("tag", ""))))
		dossier_portrait_frame.display_leader(d, selected_tag, is_tag_change)

	if focus_tree_preview != null:
		focus_tree_preview.display_focus_tree(selected_tag)


func _make_ascii_bar(value: int, max_val: int) -> String:
	var slots = 5
	var filled = clampi(int(round((float(value) / float(max_val)) * slots)), 0, slots)
	var s = "["
	for i in range(slots):
		s += "█" if i < filled else "░"
	s += "]"
	return s


# ==============================================================================
# НАСТРОЙКИ КАМПАНИИ
# ==============================================================================

func _set_difficulty(diff: int) -> void:
	config.difficulty = diff
	_refresh_setup_ui()


func _toggle_timestep() -> void:
	if config.time_step_mode == "weekly":
		config.time_step_mode = "monthly"
	else:
		config.time_step_mode = "weekly"
	_refresh_setup_ui()


func _refresh_setup_ui() -> void:
	btn_diff_observer.add_theme_color_override("font_color", Color(0.4, 0.6, 0.5))
	btn_diff_strategist.add_theme_color_override("font_color", Color(0.4, 0.6, 0.5))
	btn_diff_crisis.add_theme_color_override("font_color", Color(0.4, 0.6, 0.5))

	match config.difficulty:
		GameSessionScript.Difficulty.OBSERVER:
			btn_diff_observer.add_theme_color_override("font_color", Color(0.2, 0.95, 0.85))
		GameSessionScript.Difficulty.STRATEGIST:
			btn_diff_strategist.add_theme_color_override("font_color", Color(0.25, 0.85, 0.45))
		GameSessionScript.Difficulty.CRISIS:
			btn_diff_crisis.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))

	var loc = get_node_or_null("/root/LocalizationManager")
	var step_str = (loc.tr_key("TIMESTEP_WEEKLY", "1 ХОД = 1 НЕДЕЛЯ") if loc != null else "1 ХОД = 1 НЕДЕЛЯ") if config.time_step_mode == "weekly" else (loc.tr_key("TIMESTEP_MONTHLY", "1 ХОД = 1 МЕСЯЦ") if loc != null else "1 ХОД = 1 МЕСЯЦ")
	var step_title = loc.tr_key("TIMESTEP_HEADER", "ШАГ ВРЕМЕНИ") if loc != null else "ШАГ ВРЕМЕНИ"
	btn_timestep.text = "%s: [ %s ]" % [step_title, step_str]
	chk_anarchy.button_pressed = config.rules.get("german_anarchy_timer", true)
	chk_defcon.button_pressed = config.rules.get("dynamic_nuclear_defcon", true)
	chk_incidents.button_pressed = config.rules.get("battlefield_incidents", true)
	chk_ironman.button_pressed = config.ironman_mode


func _on_launch_campaign() -> void:
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("start_game_01")

	config.selected_country_tag = selected_tag
	config.ironman_mode = chk_ironman.button_pressed
	config.rules["german_anarchy_timer"] = chk_anarchy.button_pressed
	config.rules["dynamic_nuclear_defcon"] = chk_defcon.button_pressed
	config.rules["battlefield_incidents"] = chk_incidents.button_pressed

	# Инициализация мира через глобальный синглтон сессии
	_get_session().bootstrap_new_game(config)


func _on_load_game_pressed() -> void:
	var path = "user://savegame.json"
	if FileAccess.file_exists(path):
		var state = CountryState.load_from_json_file(path)
		if state != null:
			var session = _get_session()
			session.active_player_state = state
			session.is_loading_saved_game = true
			get_tree().change_scene_to_file("res://ui/screens/terminal_main.tscn")
			return
	if titular_log != null:
		titular_log.text = "ОШИБКА: АРХИВ [user://savegame.json] НЕ НАЙДЕН!"


# ==============================================================================
# НАСТРОЙКИ CRT И АУДИО
# ==============================================================================

func _refresh_settings_ui() -> void:
	var s = _get_session().crt_settings
	slider_curvature.value = s.get("curvature", 0.03)
	slider_scanlines.value = s.get("scanline_intensity", 0.16)
	slider_glow.value = s.get("brightness_boost", 1.05)
	slider_aberration.value = s.get("chromatic_aberration", 0.002)


func _update_crt_param(param_name: String, val: float) -> void:
	_get_session().crt_settings[param_name] = val
	_apply_crt_to_overlay()


func _apply_crt_to_overlay() -> void:
	if crt_overlay != null and crt_overlay.material is ShaderMaterial:
		_get_session().apply_crt_to_material(crt_overlay.material as ShaderMaterial)


func _get_session() -> Node:
	if has_node("/root/GameSession"):
		return get_node("/root/GameSession")
	var fallback = get_tree().root.get_node_or_null("GameSession")
	if fallback != null:
		return fallback
	var s = GameSessionScript.new()
	s.name = "GameSession"
	get_tree().root.call_deferred("add_child", s)
	return s
