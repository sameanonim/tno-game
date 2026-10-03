class_name GermanyTerminalScreen
extends PanelContainer

##
## GermanyTerminalScreen: Национальный терминал Великогерманского Рейха (GER)
## Эстетика: Мрачный янтарно-пепельный ЭЛТ-терминал Рейхсканцелярии и ОКВ.
## Управляет подсистемами Престолонаследия, Рабского труда, Карточного домика Бормана,
## Цолльферайна Шпеера, Планов Войны Гёринга и Обороны ядерных шахт Гейдриха.
##

signal closed()

const CampaignStateScript = preload("res://core/data/germany/germany_campaign_state.gd")
const ZollvereinEngineScript = preload("res://core/systems/germany/zollverein_engine.gd")
const KartenhausEngineScript = preload("res://core/systems/germany/kartenhaus_engine.gd")

# Заголовок и управление
@onready var btn_close: Button = $VBox/HeaderHBox/CloseButton
@onready var lbl_header_title: Label = $VBox/HeaderHBox/TitleLabel

# Верхний HUD показателей Рейха
@onready var lbl_fuhrer_status: Label = $VBox/TopHUD/HBox/FuhrerStatusLabel
@onready var lbl_stage_info: Label = $VBox/TopHUD/HBox/StageInfoLabel
@onready var lbl_slaves_info: Label = $VBox/TopHUD/HBox/SlavesInfoLabel
@onready var lbl_contender_info: Label = $VBox/TopHUD/HBox/ContenderInfoLabel

# Кнопки переключения вкладок
@onready var btn_tab_succession: Button = $VBox/TabBarHBox/BtnTabSuccession
@onready var btn_tab_bormann: Button = $VBox/TabBarHBox/BtnTabBormann
@onready var btn_tab_speer: Button = $VBox/TabBarHBox/BtnTabSpeer
@onready var btn_tab_warplans: Button = $VBox/TabBarHBox/BtnTabWarplans

# Секции контента
@onready var sec_succession: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionSuccession
@onready var sec_bormann: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionBormann
@onready var sec_speer: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionSpeer
@onready var sec_warplans: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionWarplans

# Элементы Вкладки 1 (Succession)
@onready var lbl_hitler_bulletin: Label = $VBox/ContentScroll/SectionsVBox/SectionSuccession/HitlerCard/BulletinLabel
@onready var btn_select_bormann: Button = $VBox/ContentScroll/SectionsVBox/SectionSuccession/ContendersHBox/CardBormann/VBox/SelectButton
@onready var btn_select_speer: Button = $VBox/ContentScroll/SectionsVBox/SectionSuccession/ContendersHBox/CardSpeer/VBox/SelectButton
@onready var btn_select_goering: Button = $VBox/ContentScroll/SectionsVBox/SectionSuccession/ContendersHBox/CardGoering/VBox/SelectButton
@onready var btn_select_heydrich: Button = $VBox/ContentScroll/SectionsVBox/SectionSuccession/ContendersHBox/CardHeydrich/VBox/SelectButton

# Элементы Вкладки 2 (Bormann / Kartenhaus)
@onready var lbl_kartenhaus_stats: Label = $VBox/ContentScroll/SectionsVBox/SectionBormann/StatsLabel
@onready var btn_secure_gauleiter: Button = $VBox/ContentScroll/SectionsVBox/SectionBormann/ActionsHBox/BtnSecureGauleiter
@onready var btn_purge_militarists: Button = $VBox/ContentScroll/SectionsVBox/SectionBormann/ActionsHBox/BtnPurgeMilitarists
@onready var btn_purge_reformers: Button = $VBox/ContentScroll/SectionsVBox/SectionBormann/ActionsHBox/BtnPurgeReformers

# Элементы Вкладки 3 (Speer / Zollverein)
@onready var lbl_regime_meter: Label = $VBox/ContentScroll/SectionsVBox/SectionSpeer/RegimeMeterLabel
@onready var lbl_zollverein_trade: Label = $VBox/ContentScroll/SectionsVBox/SectionSpeer/TradeLabel
@onready var btn_empower_erhard: Button = $VBox/ContentScroll/SectionsVBox/SectionSpeer/AdvisorsHBox/BtnErhard
@onready var btn_empower_schmidt: Button = $VBox/ContentScroll/SectionsVBox/SectionSpeer/AdvisorsHBox/BtnSchmidt
@onready var btn_empower_tresckow: Button = $VBox/ContentScroll/SectionsVBox/SectionSpeer/AdvisorsHBox/BtnTresckow

# Элементы Вкладки 4 (War Plans / Nuclear)
@onready var lbl_warplans_info: Label = $VBox/ContentScroll/SectionsVBox/SectionWarplans/WarplansLabel
@onready var lbl_nuclear_info: Label = $VBox/ContentScroll/SectionsVBox/SectionWarplans/NuclearLabel
@onready var btn_execute_campaign: Button = $VBox/ContentScroll/SectionsVBox/SectionWarplans/ActionsHBox/BtnExecuteCampaign
@onready var btn_secure_silo: Button = $VBox/ContentScroll/SectionsVBox/SectionWarplans/ActionsHBox/BtnSecureSilo

# Лог терминала внизу
@onready var lbl_status_log: Label = $VBox/BottomBar/StatusLogLabel

var campaign_manager: Node = null
var current_tab: String = "succession"


func _ready() -> void:
	_apply_styling()
	_connect_signals()
	_switch_tab("succession")


func setup(manager: Node) -> void:
	campaign_manager = manager
	if campaign_manager != null:
		if not campaign_manager.germany_state_updated.is_connected(_on_manager_updated):
			campaign_manager.germany_state_updated.connect(_on_manager_updated)
		if not campaign_manager.log_message_generated.is_connected(_on_log_message):
			campaign_manager.log_message_generated.connect(_on_log_message)
		_refresh_ui()


func _tr_str(key: String, default_text: String) -> String:
	var loc_mgr = get_node_or_null("/root/LocalizationManager")
	if loc_mgr != null and loc_mgr.has_method("translate_text"):
		return str(loc_mgr.translate_text(key, default_text))
	return default_text


func _apply_styling() -> void:
	var amber_title: Color = Color(1.0, 0.72, 0.1, 1.0)
	lbl_header_title.add_theme_color_override("font_color", amber_title)
	lbl_header_title.text = _tr_str("UI_GER_TERMINAL_TITLE", "=== REICHSKANZLEI // ГЛАВНЫЙ СИТУАЦИОННЫЙ ТЕРМИНАЛ РЕЙХА ===")
	btn_close.text = _tr_str("UI_CLOSE", "[ ✕ ЗАКРЫТЬ ]")


func _connect_signals() -> void:
	if not btn_close.pressed.is_connected(_on_close_pressed):
		btn_close.pressed.connect(_on_close_pressed)
		
	btn_tab_succession.pressed.connect(func(): _switch_tab("succession"))
	btn_tab_bormann.pressed.connect(func(): _switch_tab("bormann"))
	btn_tab_speer.pressed.connect(func(): _switch_tab("speer"))
	btn_tab_warplans.pressed.connect(func(): _switch_tab("warplans"))
	
	btn_select_bormann.pressed.connect(func(): _select_contender("BOR"))
	btn_select_speer.pressed.connect(func(): _select_contender("SPE"))
	btn_select_goering.pressed.connect(func(): _select_contender("GOR"))
	btn_select_heydrich.pressed.connect(func(): _select_contender("HEY"))
	
	btn_secure_gauleiter.pressed.connect(_on_secure_gauleiter_pressed)
	btn_purge_militarists.pressed.connect(func(): _purge_faction("militarists"))
	btn_purge_reformers.pressed.connect(func(): _purge_faction("reformers"))
	
	btn_empower_erhard.pressed.connect(func(): _empower_advisor("erhard"))
	btn_empower_schmidt.pressed.connect(func(): _empower_advisor("schmidt"))
	btn_empower_tresckow.pressed.connect(func(): _empower_advisor("tresckow"))
	
	btn_execute_campaign.pressed.connect(_on_execute_campaign_pressed)
	btn_secure_silo.pressed.connect(_on_secure_silo_pressed)


func _switch_tab(tab_name: String) -> void:
	current_tab = tab_name
	sec_succession.visible = (tab_name == "succession")
	sec_bormann.visible = (tab_name == "bormann")
	sec_speer.visible = (tab_name == "speer")
	sec_warplans.visible = (tab_name == "warplans")
	
	# Подсветка кнопок
	var amber: Color = Color(1.0, 0.72, 0.1, 1.0)
	var dim: Color = Color(0.65, 0.55, 0.45, 1.0)
	btn_tab_succession.add_theme_color_override("font_color", amber if tab_name == "succession" else dim)
	btn_tab_bormann.add_theme_color_override("font_color", amber if tab_name == "bormann" else dim)
	btn_tab_speer.add_theme_color_override("font_color", amber if tab_name == "speer" else dim)
	btn_tab_warplans.add_theme_color_override("font_color", amber if tab_name == "warplans" else dim)


func _on_manager_updated(_state: Resource) -> void:
	_refresh_ui()


func _refresh_ui() -> void:
	if campaign_manager == null or campaign_manager.campaign_state == null:
		return
	var st = campaign_manager.campaign_state
	
	# 1. Top HUD
	if st.hitler_is_alive:
		lbl_fuhrer_status.text = _tr_str("UI_GER_FUHRER_ALIVE", "ФЮРЕР: ЖИВ (%0.1f%%)" % st.hitler_health)
		lbl_fuhrer_status.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2, 1.0))
	else:
		lbl_fuhrer_status.text = _tr_str("UI_GER_FUHRER_DEAD", "ФЮРЕР: СКОНЧАЛСЯ [МЁРТВ]")
		lbl_fuhrer_status.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25, 1.0))
		
	var stage_name: String = "ПРЕЛЮДИЯ 1962"
	match st.current_stage:
		CampaignStateScript.CampaignStage.STAGE_POWER_STRUGGLE:
			stage_name = "СХВАТКА ЗА ВЛАСТЬ // КРИЗИС"
		CampaignStateScript.CampaignStage.STAGE_SUCCESSOR_RULE:
			stage_name = "ПРАВЛЕНИЕ НОВОГО ПРАВИТЕЛЯ"
		CampaignStateScript.CampaignStage.STAGE_COLLAPSE:
			stage_name = "АНАРХИЯ И КОЛЛАПС РЕЙХА"
	lbl_stage_info.text = _tr_str("UI_GER_STAGE_INFO", "ЭТАП: %s" % stage_name)
	
	lbl_slaves_info.text = _tr_str("UI_GER_SLAVES_INFO", "РАБСКИЙ ТРУД: %0.1f МЛН [РИСК СТАЧКИ: %0.0f%%]" % [st.slaves_count_millions, st.slave_unrest * 100.0])
	lbl_contender_info.text = _tr_str("UI_GER_CONTENDER_INFO", "ВЫБРАННЫЙ ПРЕТЕНДЕНТ: [%s]" % st.chosen_contender_tag)
	
	# 2. Succession Tab
	lbl_hitler_bulletin.text = _tr_str(
		"UI_GER_HITLER_BULLETIN",
		"Здоровье вождя: %0.1f%%. Влияние в Рейхстаге:\nБорман: %0.1f%% | Шпеер: %0.1f%% | Гёринг: %0.1f%% | Гейдрих: %0.1f%%" % [
			st.hitler_health,
			st.faction_influence_bormann,
			st.faction_influence_speer,
			st.faction_influence_goering,
			st.faction_influence_heydrich
		]
	)
	
	# 3. Bormann Tab
	var kd: Dictionary = st.kartenhaus_data
	lbl_kartenhaus_stats.text = _tr_str(
		"UI_GER_KARTENHAUS_STATS",
		"КАРТОЧНЫЙ ДОМИК:\nКонтроль гауляйтеров: %d / %d округов\nЛояльность партийного аппарата: %0.1f%%\nВлияние оппозиционных милитаристов: %0.1f%%\nВлияние оппозиционных реформаторов: %0.1f%%" % [
			int(kd.get("districts_secured", 12)),
			int(kd.get("total_districts", 24)),
			float(kd.get("bureaucrats_control", 65.0)),
			float(kd.get("militarists_control", 45.0)),
			float(kd.get("reformers_control", 35.0))
		]
	)
	
	# 4. Speer Tab
	var zd: Dictionary = st.zollverein_data
	var go4: Dictionary = zd.get("gang_of_four_influence", {})
	lbl_regime_meter.text = _tr_str(
		"UI_GER_REGIME_METER",
		"СЧЕТЧИК РЕЖИМА: %0.1f [%s]" % [
			st.speer_regime_meter,
			ZollvereinEngineScript.get_alignment_title(st.speer_regime_meter)
		]
	)
	lbl_zollverein_trade.text = _tr_str(
		"UI_GER_ZOLLVEREIN_TRADE",
		"ЦОЛЛЬФЕРАЙН: Объём торговли: $%0.1f млрд | Члены: %s\nСоветники Четвёрки: Эрхард: %0.0f%% | Шмидт: %0.0f%% | Тресков: %0.0f%%" % [
			float(zd.get("trade_volume_billions", 48.5)),
			", ".join(zd.get("pakt_members", [])),
			float(go4.get("erhard", 50.0)),
			float(go4.get("schmidt", 50.0)),
			float(go4.get("tresckow", 50.0))
		]
	)
	
	# 5. Warplans & Nuclear Tab
	var wpd: Dictionary = st.goering_warplans_data
	lbl_warplans_info.text = _tr_str(
		"UI_GER_WARPLANS_INFO",
		"ВЕРМАХТ (ГЁРИНГ): План Войны: [%s] | Цель: %s | Напряженность милитаристов: %0.1f%% | Награблено: $%0.1f млрд" % [
			str(wpd.get("current_plan", "A")),
			str(wpd.get("target_country_tag", "SWI")),
			float(wpd.get("militarist_tension", 30.0)),
			float(wpd.get("plundered_gold_billions", 0.0))
		]
	)
	var nd: Dictionary = st.heydrich_nuclear_data
	lbl_nuclear_info.text = _tr_str(
		"UI_GER_NUCLEAR_INFO",
		"СС И ЯДЕРНЫЙ АРСЕНАЛ (ГЕЙДРИХ): Защищено шахт: %d / %d | Диверсантов Бургундии: %d\nТАЙМЕР СУДНОГО ДНЯ: %0.1f%%" % [
			int(nd.get("secured_silos", 14)),
			int(nd.get("total_silos", 28)),
			int(nd.get("burgundian_infiltrated_silos", 8)),
			float(nd.get("apocalypse_clock_percent", 25.0))
		]
	)


func _on_log_message(msg: String, is_alert: bool) -> void:
	lbl_status_log.text = msg
	lbl_status_log.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0) if is_alert else Color(0.9, 0.75, 0.4, 1.0))


func _select_contender(tag: String) -> void:
	if campaign_manager != null:
		campaign_manager.select_player_contender(tag)
		_on_log_message("Ставка сделана: Вы поддержали фракцию [%s] в борьбе за корону Рейха." % tag, false)


func _on_secure_gauleiter_pressed() -> void:
	if campaign_manager != null:
		var ok: bool = campaign_manager.execute_bormann_secure_district("GAU_BERLIN")
		if ok:
			_on_log_message("Успех: Новый гауляйтер приведен к присяге партийной канцелярии!", false)
		else:
			_on_log_message("Неудача: Попытка подкупа провалилась из-за сопротивления оппозиции!", true)


func _purge_faction(faction_key: String) -> void:
	if campaign_manager != null and campaign_manager.campaign_state != null:
		var res: Dictionary = KartenhausEngineScript.purge_faction(campaign_manager.campaign_state, faction_key)
		if res.get("success", false):
			_on_log_message("Чистка завершена: Фракция [%s] разгромлена и лишена влияния!" % faction_key, false)
			_refresh_ui()


func _empower_advisor(advisor_key: String) -> void:
	if campaign_manager != null:
		campaign_manager.execute_speer_empower_advisor(advisor_key, 10.0)
		_on_log_message("Влияние советника [%s] расширено. Реформы продвигаются." % advisor_key, false)


func _on_execute_campaign_pressed() -> void:
	if campaign_manager != null:
		var res: Dictionary = campaign_manager.execute_goering_campaign_victory("SWI")
		if res.get("success", false):
			_on_log_message("Победа Вермахта! Захвачено $%0.1f млрд золота, напряжение генералов снижено." % res.get("gold_plundered", 0.0), false)


func _on_secure_silo_pressed() -> void:
	if campaign_manager != null:
		var ok: bool = campaign_manager.execute_heydrich_secure_silo()
		if ok:
			_on_log_message("Спецназ СС отбил ракетную шахту у бургундских диверсантов!", false)
		else:
			_on_log_message("Опасность: Бургундские агенты оказали ожесточенное сопротивление!", true)


func _on_close_pressed() -> void:
	emit_signal("closed")
	visible = false
