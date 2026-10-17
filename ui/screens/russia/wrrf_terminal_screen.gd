class_name WRRFTerminalScreen
extends PanelContainer

"""
WRRFTerminalScreen: Главный ситуационный терминал Западнорусского Революционного Фронта (ЗРРФ)
Эстетика: Суровый ало-золотой советский военный ЭЛТ-терминал штаба в Архангельске/Плесецке.
Управляет:
1. Борьбой за власть между Жуковым и Тухачевским.
2. Программой секретных военных проектов Тухачевского (ОБТ, Ураган, Циклон, Щука, Леший, Фермент).
3. Балансом триумвирата Жукова (Ахромеев, Рыжков, Яковлев).
4. Подготовкой фронта, пактом с Коми, рейдами против Онеги и интеграцией бригады Горького.
"""

signal closed()

var wrrf_manager: WRRFMechanicsManager = null
var current_tab: String = "struggle"

# Заголовок и управление
@onready var btn_close: Button = $VBox/HeaderHBox/CloseButton
@onready var lbl_header_title: Label = $VBox/HeaderHBox/TitleLabel

# Верхний HUD
@onready var lbl_leader_status: Label = $VBox/TopHUD/HBox/LeaderStatusLabel
@onready var lbl_stage_info: Label = $VBox/TopHUD/HBox/StageInfoLabel
@onready var lbl_supply_info: Label = $VBox/TopHUD/HBox/SupplyInfoLabel
@onready var lbl_bombing_info: Label = $VBox/TopHUD/HBox/BombingInfoLabel

# Таб-бар
@onready var btn_tab_struggle: Button = $VBox/TabBarHBox/BtnTabStruggle
@onready var btn_tab_arsenal: Button = $VBox/TabBarHBox/BtnTabArsenal
@onready var btn_tab_triumvirate: Button = $VBox/TabBarHBox/BtnTabTriumvirate
@onready var btn_tab_front: Button = $VBox/TabBarHBox/BtnTabFront

# Секции контента
@onready var sec_struggle: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionStruggle
@onready var sec_arsenal: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionArsenal
@onready var sec_triumvirate: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate
@onready var sec_front: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionFront

# Элементы Вкладки 1: Борьба за власть
@onready var lbl_zhukov_meter: Label = $VBox/ContentScroll/SectionsVBox/SectionStruggle/StruggleMeters/ZhukovBox/ZhukovMeterLabel
@onready var bar_zhukov: ProgressBar = $VBox/ContentScroll/SectionsVBox/SectionStruggle/StruggleMeters/ZhukovBox/ZhukovBar
@onready var lbl_tukha_meter: Label = $VBox/ContentScroll/SectionsVBox/SectionStruggle/StruggleMeters/TukhaBox/TukhaMeterLabel
@onready var bar_tukha: ProgressBar = $VBox/ContentScroll/SectionsVBox/SectionStruggle/StruggleMeters/TukhaBox/TukhaBar
@onready var lbl_struggle_status: Label = $VBox/ContentScroll/SectionsVBox/SectionStruggle/StatusCard/StatusLabel
@onready var btn_appease_zhukov: Button = $VBox/ContentScroll/SectionsVBox/SectionStruggle/ActionsHBox/BtnAppeaseZhukov
@onready var btn_appease_tukha: Button = $VBox/ContentScroll/SectionsVBox/SectionStruggle/ActionsHBox/BtnAppeaseTukha
@onready var btn_parade_zhukov: Button = $VBox/ContentScroll/SectionsVBox/SectionStruggle/ActionsHBox2/BtnParadeZhukov
@onready var btn_parade_tukha: Button = $VBox/ContentScroll/SectionsVBox/SectionStruggle/ActionsHBox2/BtnParadeTukha
@onready var btn_evidence_zhukov: Button = $VBox/ContentScroll/SectionsVBox/SectionStruggle/SpecialActionsHBox/BtnEvidenceZhukov
@onready var btn_firebird_tukha: Button = $VBox/ContentScroll/SectionsVBox/SectionStruggle/SpecialActionsHBox/BtnFirebirdTukha
@onready var btn_resolve_struggle: Button = $VBox/ContentScroll/SectionsVBox/SectionStruggle/ResolveHBox/BtnResolveStruggle

# Элементы Вкладки 2: Красный Арсенал
@onready var bar_obt: ProgressBar = $VBox/ContentScroll/SectionsVBox/SectionArsenal/OBTCard/OBTBar
@onready var lbl_obt_status: Label = $VBox/ContentScroll/SectionsVBox/SectionArsenal/OBTCard/OBTStatusLabel
@onready var btn_advance_obt: Button = $VBox/ContentScroll/SectionsVBox/SectionArsenal/OBTCard/BtnAdvanceOBT
@onready var btn_proj_uragan: Button = $VBox/ContentScroll/SectionsVBox/SectionArsenal/ProjectsGrid/BtnProjectUragan
@onready var btn_proj_tsysklon: Button = $VBox/ContentScroll/SectionsVBox/SectionArsenal/ProjectsGrid/BtnProjectTsysklon
@onready var btn_proj_shchuka: Button = $VBox/ContentScroll/SectionsVBox/SectionArsenal/ProjectsGrid/BtnProjectShchuka
@onready var btn_proj_leshiy: Button = $VBox/ContentScroll/SectionsVBox/SectionArsenal/ProjectsGrid/BtnProjectLeshiy
@onready var btn_proj_ferment: Button = $VBox/ContentScroll/SectionsVBox/SectionArsenal/ProjectsGrid/BtnProjectFerment
@onready var btn_izhevsk: Button = $VBox/ContentScroll/SectionsVBox/SectionArsenal/ProjectsGrid/BtnIzhevskWorks

# Элементы Вкладки 3: Триумвират Жукова
@onready var bar_akhromeyev: ProgressBar = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/BalanceGrid/AkhromeyevBox/AkhromeyevBar
@onready var lbl_akhromeyev: Label = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/BalanceGrid/AkhromeyevBox/AkhromeyevLabel
@onready var bar_ryzhkov: ProgressBar = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/BalanceGrid/RyzhkovBox/RyzhkovBar
@onready var lbl_ryzhkov: Label = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/BalanceGrid/RyzhkovBox/RyzhkovLabel
@onready var bar_yakovlev: ProgressBar = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/BalanceGrid/YakovlevBox/YakovlevBar
@onready var lbl_yakovlev: Label = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/BalanceGrid/YakovlevBox/YakovlevLabel
@onready var btn_trium_akhromeyev: Button = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/AppeaseHBox/BtnAppeaseAkhromeyev
@onready var btn_trium_ryzhkov: Button = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/AppeaseHBox/BtnAppeaseRyzhkov
@onready var btn_trium_yakovlev: Button = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/AppeaseHBox/BtnAppeaseYakovlev
@onready var btn_usa_supplies: Button = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/PoliciesGrid/BtnUSASupplies
@onready var btn_smersh: Button = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/PoliciesGrid/BtnSmersh
@onready var btn_agriculture: Button = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/PoliciesGrid/BtnAgriculture
@onready var btn_kgb: Button = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/PoliciesGrid/BtnKGB
@onready var btn_ofn_trade: Button = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/PoliciesGrid/BtnOFNTrade
@onready var btn_abolish_gulag: Button = $VBox/ContentScroll/SectionsVBox/SectionTriumvirate/PoliciesGrid/BtnAbolishGulag

# Элементы Вкладки 4: Фронт и Смута
@onready var lbl_front_summary: Label = $VBox/ContentScroll/SectionsVBox/SectionFront/FrontCard/SummaryLabel
@onready var btn_komi_nap: Button = $VBox/ContentScroll/SectionsVBox/SectionFront/DiploGrid/BtnKomiNAP
@onready var btn_gorky_brigade: Button = $VBox/ContentScroll/SectionsVBox/SectionFront/DiploGrid/BtnGorkyBrigade
@onready var btn_oil_quotas: Button = $VBox/ContentScroll/SectionsVBox/SectionFront/DiploGrid/BtnOilQuotas
@onready var btn_labour_battalions: Button = $VBox/ContentScroll/SectionsVBox/SectionFront/DiploGrid/BtnLabourBattalions


func _ready() -> void:
	_apply_styling()
	_connect_signals()
	_switch_tab("struggle")


"""Настраивает терминал с передачей менеджера механик ЗРРФ."""
func setup(manager: WRRFMechanicsManager, country_state: CountryState = null) -> void:
	wrrf_manager = manager
	if wrrf_manager != null:
		if country_state != null and wrrf_manager.player_state == null:
			wrrf_manager.setup(country_state)
		if not wrrf_manager.power_struggle_updated.is_connected(_on_power_struggle_updated):
			wrrf_manager.power_struggle_updated.connect(_on_power_struggle_updated)
		if not wrrf_manager.successor_chosen.is_connected(_on_successor_chosen):
			wrrf_manager.successor_chosen.connect(_on_successor_chosen)
		if not wrrf_manager.secret_project_progressed.is_connected(_on_secret_project_progressed):
			wrrf_manager.secret_project_progressed.connect(_on_secret_project_progressed)
		if not wrrf_manager.triumvirate_balance_shifted.is_connected(_on_triumvirate_balance_shifted):
			wrrf_manager.triumvirate_balance_shifted.connect(_on_triumvirate_balance_shifted)
		if not wrrf_manager.terror_bombings_lifted.is_connected(_on_terror_bombings_lifted):
			wrrf_manager.terror_bombings_lifted.connect(_on_terror_bombings_lifted)

	_refresh_ui()


func _apply_styling() -> void:
	var soviet_red := Color(0.95, 0.25, 0.25, 1.0)
	var star_gold := Color(1.0, 0.85, 0.2, 1.0)
	lbl_header_title.add_theme_color_override("font_color", star_gold)
	lbl_header_title.text = "★ ВОЕННО-РЕВОЛЮЦИОННЫЙ СОВЕТ ЗРРФ // ШТАБНОЙ ТЕРМИНАЛ (АРХАНГЕЛЬСК) ★"
	btn_close.text = "[ ✕ ЗАКРЫТЬ ]"
	btn_close.add_theme_color_override("font_color", soviet_red)


func _connect_signals() -> void:
	if not btn_close.pressed.is_connected(_on_close_pressed):
		btn_close.pressed.connect(_on_close_pressed)

	btn_tab_struggle.pressed.connect(func(): _switch_tab("struggle"))
	btn_tab_arsenal.pressed.connect(func(): _switch_tab("arsenal"))
	btn_tab_triumvirate.pressed.connect(func(): _switch_tab("triumvirate"))
	btn_tab_front.pressed.connect(func(): _switch_tab("front"))

	# Вкладка 1
	btn_appease_zhukov.pressed.connect(func(): _exec_action("WRS_appease_zhukov"))
	btn_appease_tukha.pressed.connect(func(): _exec_action("WRS_appease_tukha"))
	btn_parade_zhukov.pressed.connect(func(): _exec_action("WRS_zhukov_military_parade"))
	btn_parade_tukha.pressed.connect(func(): _exec_action("WRS_tukha_military_parade"))
	btn_evidence_zhukov.pressed.connect(func(): _exec_action("WRS_zhukov_compile_evidence"))
	btn_firebird_tukha.pressed.connect(func(): _exec_action("WRS_tukha_operation_firebird"))
	btn_resolve_struggle.pressed.connect(_on_resolve_struggle_pressed)

	# Вкладка 2
	btn_advance_obt.pressed.connect(func(): _exec_action("WRS_OBT_program"))
	btn_proj_uragan.pressed.connect(func(): _exec_action("WRS_project_uragan"))
	btn_proj_tsysklon.pressed.connect(func(): _exec_action("WRS_project_tsysklon"))
	btn_proj_shchuka.pressed.connect(func(): _exec_action("WRS_project_shchuka"))
	btn_proj_leshiy.pressed.connect(func(): _exec_action("WRS_project_leshiy"))
	btn_proj_ferment.pressed.connect(func(): _exec_action("WRS_project_ferment"))
	btn_izhevsk.pressed.connect(func(): _exec_action("WRS_izhevsk_experimental_constructor_works"))

	# Вкладка 3
	btn_trium_akhromeyev.pressed.connect(func(): _exec_action("WRS_appease_akhromeyev"))
	btn_trium_ryzhkov.pressed.connect(func(): _exec_action("WRS_appease_ryzhkov"))
	btn_trium_yakovlev.pressed.connect(func(): _exec_action("WRS_appease_yakovlev"))
	btn_usa_supplies.pressed.connect(func(): _exec_action("WRS_akhromeyev_draw_closer_to_USA"))
	btn_smersh.pressed.connect(func(): _exec_action("WRS_akhromeyev_widen_smersh_powers"))
	btn_agriculture.pressed.connect(func(): _exec_action("WRS_ryzhkov_agricultural_mechanization"))
	btn_kgb.pressed.connect(func(): _exec_action("WRS_ryzhkov_establish_the_kgb"))
	btn_ofn_trade.pressed.connect(func(): _exec_action("WRS_yakovlev_eliminate_ofn_tariffs"))
	btn_abolish_gulag.pressed.connect(func(): _exec_action("WRS_yakovlev_abolish_gulag"))

	# Вкладка 4
	btn_komi_nap.pressed.connect(func(): _exec_action("RUS_Decision_Smuta_Expansion_KOM_WRS_Establish_NAP"))
	btn_gorky_brigade.pressed.connect(func(): _exec_action("RUS_Decision_Smuta_Expansion_GOR_WRS_NyomNyomNyom"))
	btn_oil_quotas.pressed.connect(func(): _exec_action("WRS_zhukov_increase_oil_quotas"))
	btn_labour_battalions.pressed.connect(func(): _exec_action("WRS_zhukov_deploy_red_army_labour_battalions"))


func _switch_tab(tab_name: String) -> void:
	current_tab = tab_name
	sec_struggle.visible = (tab_name == "struggle")
	sec_arsenal.visible = (tab_name == "arsenal")
	sec_triumvirate.visible = (tab_name == "triumvirate")
	sec_front.visible = (tab_name == "front")

	var active_color := Color(1.0, 0.85, 0.2, 1.0)
	var inactive_color := Color(0.7, 0.7, 0.7, 1.0)
	btn_tab_struggle.add_theme_color_override("font_color", active_color if tab_name == "struggle" else inactive_color)
	btn_tab_arsenal.add_theme_color_override("font_color", active_color if tab_name == "arsenal" else inactive_color)
	btn_tab_triumvirate.add_theme_color_override("font_color", active_color if tab_name == "triumvirate" else inactive_color)
	btn_tab_front.add_theme_color_override("font_color", active_color if tab_name == "front" else inactive_color)


func _exec_action(action_id: String) -> void:
	if wrrf_manager != null:
		wrrf_manager.execute_decision_action(action_id)
		_refresh_ui()


func _on_resolve_struggle_pressed() -> void:
	if wrrf_manager != null:
		wrrf_manager.resolve_power_struggle()
		_refresh_ui()


"""Обновляет все показатели интерфейса терминала ЗРРФ."""
func _refresh_ui() -> void:
	if wrrf_manager == null:
		return

	var s: WRRFCampaignState = wrrf_manager.state
	var p: CountryState = wrrf_manager.player_state

	# Верхний HUD
	var leader_title: String = "А. Егоров (Маршал Фронта)"
	if s.power_struggle_resolved:
		leader_title = "Маршал Г. Жуков" if s.chosen_successor == WRRFCampaignState.Successor.ZHUKOV else "Маршал М. Тухачевский"
	elif p != null and not p.leader_name.is_empty():
		leader_title = p.leader_name
	lbl_leader_status.text = "ЛИДЕР: %s" % leader_title

	var stage_str: String = "ПРОЛОГ (1962)"
	match s.current_stage:
		WRRFCampaignState.FrontStage.WARLORD_SMUTA: stage_str = "СМУТА (ВАРЛОРД)"
		WRRFCampaignState.FrontStage.REGIONAL: stage_str = "РЕГИОНАЛЬНЫЙ ЭТАП"
		WRRFCampaignState.FrontStage.SUPERREGIONAL: stage_str = "СУПЕРРЕГИОНАЛ"
		WRRFCampaignState.FrontStage.UNIFIED: stage_str = "СССР ВОССОЗДАН"
		WRRFCampaignState.FrontStage.SECOND_WEST_RUSSIAN_WAR: stage_str = "2-Я ЗАПАДНОРУССКАЯ ВОЙНА"
	lbl_stage_info.text = "ЭТАП: %s" % stage_str

	lbl_supply_info.text = "СНАБЖЕНИЕ ФРОНТА: %d%%" % int(s.front_supply_stockpile)

	if s.terror_bombings_active:
		lbl_bombing_info.text = "НАЛЕТЫ ЛЮФТВАФФЕ: АКТИВНЫ"
		lbl_bombing_info.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	else:
		lbl_bombing_info.text = "НАЛЕТЫ ЛЮФТВАФФЕ: ПРЕКРАЩЕНЫ"
		lbl_bombing_info.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 1.0))

	# Вкладка 1: Борьба за власть
	bar_zhukov.value = s.zhukov_influence
	lbl_zhukov_meter.text = "ВЛИЯНИЕ ЖУКОВА: %d%% (Ветераны: %d%%)" % [int(s.zhukov_influence), int(s.veterans_support_zhukov)]

	bar_tukha.value = s.tukhachevsky_influence
	lbl_tukha_meter.text = "ВЛИЯНИЕ ТУХАЧЕВСКОГО: %d%% (Офицеры: %d%%)" % [int(s.tukhachevsky_influence), int(s.officers_support_tukha)]

	if s.power_struggle_resolved:
		var succ_name: String = "Георгий Жуков" if s.chosen_successor == WRRFCampaignState.Successor.ZHUKOV else "Михаил Тухачевский"
		lbl_struggle_status.text = "БОРЬБА ЗА ВЛАСТЬ ЗАВЕРШЕНА: ВЕРХОВНЫЙ МАРШАЛ — %s!" % succ_name.to_upper()
		btn_resolve_struggle.disabled = true
		btn_resolve_struggle.text = "ПРЕЕМНИК УТВЕРЖДЕН"
	else:
		lbl_struggle_status.text = "ИДЕТ БОРЬБА ЗА ВЛАСТЬ. Здоровье Маршала Егорова: %d%%" % int(s.marshal_yegorov_health)
		btn_resolve_struggle.disabled = false
		btn_resolve_struggle.text = "[ УТВЕРДИТЬ ВЕРХОВНОГО МАРШАЛА ФРОНТА ]"

	# Вкладка 2: Красный Арсенал
	bar_obt.value = s.obt_progress
	lbl_obt_status.text = "ПРОГРАММА ОБТ: %s (%d%%)" % [("ЗАВЕРШЕНА" if s.obt_completed else "В РАЗРАБОТКЕ"), int(s.obt_progress)]
	btn_advance_obt.disabled = s.obt_completed

	btn_proj_uragan.text = "УРАГАН (РСЗО): %s" % ("РАЗВЕРНУТ" if s.uragan_active else "[ РАЗВЕРНУТЬ ]")
	btn_proj_tsysklon.text = "ЦИКЛОН (РАКЕТЫ): %s" % ("РАЗВЕРНУТ" if s.tsysklon_active else "[ РАЗВЕРНУТЬ ]")
	btn_proj_shchuka.text = "ЩУКА (ПОДПЛАВ): %s" % ("АКТИВЕН" if s.shchuka_active else "[ СФОРМИРОВАТЬ ]")
	btn_proj_leshiy.text = "ЛЕШИЙ (СПЕЦНАЗ): %s" % ("РАЗВЕРНУТ" if s.leshiy_active else "[ ПОДГОТОВИТЬ ]")
	btn_proj_ferment.text = "ФЕРМЕНТ (ХИМОРУЖИЕ): %d ТОНН" % s.ferment_chemical_stockpile
	btn_izhevsk.text = "ИЖЕВСКИЙ ЗАВОД: %s" % ("МОДЕРНИЗИРОВАН" if s.izhevsk_works_expanded else "[ РАСШИРИТЬ ]")

	# Вкладка 3: Триумвират
	bar_akhromeyev.value = s.akhromeyev_influence
	lbl_akhromeyev.text = "С. Ахромеев (Армейцы): %d%%" % int(s.akhromeyev_influence)

	bar_ryzhkov.value = s.ryzhkov_influence
	lbl_ryzhkov.text = "Н. Рыжков (Госплан): %d%%" % int(s.ryzhkov_influence)

	bar_yakovlev.value = s.yakovlev_influence
	lbl_yakovlev.text = "А. Яковлев (Реформаторы): %d%%" % int(s.yakovlev_influence)

	btn_usa_supplies.text = "ТЕХНИКА США: %s" % ("ПОЛУЧЕНА" if s.us_equipment_imported else "[ ЗАПРОСИТЬ ]")
	btn_smersh.text = "ЮРИСДИКЦИЯ СМЕРШ: %s" % ("РАСШИРЕНА" if s.smersh_jurisdiction_expanded else "[ РАСШИРИТЬ ]")
	btn_agriculture.text = "МЕХАНИЗАЦИЯ СЕЛА: %s" % ("ВЫПОЛНЕНА" if s.agricultural_mechanization_done else "[ ВНЕДРИТЬ ]")
	btn_kgb.text = "СОЗДАНИЕ КГБ: %s" % ("СОЗДАН" if s.kgb_established else "[ УЧРЕДИТЬ ]")
	btn_ofn_trade.text = "ТАРИФЫ ОФН: %s" % ("СНЯТЫ" if s.ofn_tariffs_eliminated else "[ ОТМЕНИТЬ ]")
	btn_abolish_gulag.text = "ЛИКВИДАЦИЯ ГУЛАГА: %s" % ("ЛИКВИДИРОВАН" if s.gulag_system_abolished else "[ ЛИКВИДИРОВАТЬ ]")

	# Вкладка 4: Фронт и Смута
	var komi_nap_active: bool = p.has_flag("wrs_komi_nap_active") if p != null else false
	var gorky_done: bool = p.has_flag("wrs_gorky_integrated") if p != null else false

	lbl_front_summary.text = "Готовность к броску на Онегу: %d%%\nВетеранский корпус РККА: %d бойцов\nФронтовой резерв: %s" % [
		int(s.onega_raid_readiness),
		s.red_army_veterans_corps,
		("ВЫСОКИЙ" if s.front_supply_stockpile >= 50.0 else "ДЕФИЦИТ")
	]

	btn_komi_nap.text = "ПАКТ С КОМИ: %s" % ("ЗАКЛЮЧЕН" if komi_nap_active else "[ ПОДПИСАТЬ ]")
	btn_gorky_brigade.text = "БРИГАДА ГОРЬКОГО: %s" % ("В СТРОЮ" if gorky_done else "[ ИНТЕГРИРОВАТЬ ]")


func _on_power_struggle_updated(_z: float, _t: float) -> void:
	_refresh_ui()


func _on_successor_chosen(_title: String, _id: String) -> void:
	_refresh_ui()


func _on_secret_project_progressed(_id: String, _prog: float, _done: bool) -> void:
	_refresh_ui()


func _on_triumvirate_balance_shifted(_a: float, _r: float, _y: float) -> void:
	_refresh_ui()


func _on_terror_bombings_lifted() -> void:
	_refresh_ui()


func _on_close_pressed() -> void:
	closed.emit()
	hide()
