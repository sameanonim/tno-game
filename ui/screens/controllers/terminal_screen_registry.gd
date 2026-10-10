class_name TerminalScreenRegistry
extends Node

##
## TerminalScreenRegistry: Контроллер регистрации и динамической загрузки национальных экранов
## ==============================================================================
## Отвечает за:
## 1. Загрузку и инстанцирование специализированных экранов держав:
##    - GCWOperationsPanel / GermanyTerminalScreen (Рейх)
##    - USCongressScreen (США)
##    - JapanTerminalScreen (Япония)
##    - ItalyTerminalScreen (Италия)
## 2. Создание кнопок переключения национальных экранов в панели MapModeHUD.
## 3. Управление видимостью вкладок и панелей в зависимости от выбранной державы.
## ==============================================================================


"""Инициализирует и привязывает все национальные терминалы и панели механик к главному терминалу.
"""
static func setup_national_screens(terminal: TerminalMain) -> void:
	if terminal == null or terminal.turn_manager == null or terminal.turn_manager.player_state == null:
		return

	var tm = terminal.turn_manager
	var p_tag = tm.player_state.country_tag.to_upper()
	var is_warlord = RussianUnificationManager.is_warlord(p_tag)
	var is_german = p_tag in ["GER", "BOR", "SPE", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]
	var is_usa = (p_tag == "USA" or p_tag.begins_with("US"))
	var is_japan = (p_tag == "JAP")
	var is_italy = (p_tag == "ITA")

	var national_container = terminal.get_node_or_null("TabContainer/WarlordRaids")

	# 1. GCW Operations Panel (Оперативный штаб дивизий Рейха)
	var gcw_scene = load("res://ui/screens/gcw_operations_panel.tscn")
	if gcw_scene != null and terminal.gcw_operations_panel == null:
		terminal.gcw_operations_panel = gcw_scene.instantiate()
		terminal.gcw_operations_panel.name = "GCWOperationsPanel"
		if national_container != null:
			national_container.add_child(terminal.gcw_operations_panel)
		else:
			terminal.add_child(terminal.gcw_operations_panel)
		if tm.german_civil_war_manager != null:
			terminal.gcw_operations_panel.setup(tm.german_civil_war_manager)
			terminal.gcw_operations_panel.proxy_aid_dispatched.connect(func(_pk, _d, _c):
				terminal._update_hud()
				if terminal.map_controller != null: terminal.map_controller.refresh_tactical_frontlines()
			)
			terminal.gcw_operations_panel.proxy_lend_lease_dispatched.connect(func(_pk, _w, _t, _c):
				terminal._update_hud()
				if terminal.map_controller != null: terminal.map_controller.refresh_tactical_frontlines()
			)
			terminal.gcw_operations_panel.proxy_theater_focus_requested.connect(func(pk, provs):
				if terminal.map_controller != null and provs.size() > 0:
					terminal.map_controller.select_province(provs[0])
					terminal.map_controller.add_combat_incident_ping(provs[0], "theater_radar")
				terminal.label_log.text = terminal._tr_str("LOG_PROXY_THEATER", {"proxy": pk.to_upper()}, "ПРОКСИ-ТЕАТР [%s]: КООРДИНАТЫ ПЕРЕДАНЫ В ОПЕРАТИВНЫЙ ШТАБ" % pk.to_upper())
			)
			terminal.gcw_operations_panel.tactical_order_clicked.connect(func(order_type, _axis):
				terminal._update_hud()
				if terminal.map_controller != null: terminal.map_controller.refresh_tactical_frontlines()
				if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1200.0)
				terminal.label_log.text = terminal._tr_str("LOG_TACTICAL_ORDER", {"order": order_type.to_upper()}, "ГЕНШТАБ: ТАКТИЧЕСКИЙ ПРИКАЗ «%s» ПЕРЕДАН ВОЙСКАМ" % order_type.to_upper())
			)
			terminal.gcw_operations_panel.intrigue_action_clicked.connect(func(act_type, contender):
				terminal._update_hud()
				if terminal.sound_fx != null: terminal.sound_fx.play_key_click(900.0)
				terminal.label_log.text = terminal._tr_str("LOG_INTRIGUE_OP", {"op": act_type.to_upper(), "target": contender.to_upper()}, "ИНТРИГА: ОПЕРАЦИЯ «%s» ПРОТИВ ФРАКЦИИ [%s] РЕАЛИЗОВАНА" % [act_type.to_upper(), contender.to_upper()])
			)

	# 2. Конгресс США (US Congress Screen)
	if is_usa and terminal.us_congress_screen == null:
		var congress_scene = load("res://ui/screens/usa/us_congress_screen.tscn")
		if congress_scene != null:
			terminal.us_congress_screen = congress_scene.instantiate()
			terminal.us_congress_screen.name = "USCongressScreen"
			if national_container != null:
				national_container.add_child(terminal.us_congress_screen)
			else:
				terminal.add_child(terminal.us_congress_screen)
			terminal.us_congress_screen.setup(tm.player_state)
			terminal.us_congress_screen.closed.connect(func():
				if terminal.tab_container != null: terminal.tab_container.current_tab = 0
			)

	# 3. Япония (Japan Terminal Screen)
	if is_japan and terminal.japan_terminal_screen == null:
		var jap_scene = load("res://ui/screens/japan/japan_terminal_screen.tscn")
		if jap_scene != null:
			terminal.japan_terminal_screen = jap_scene.instantiate()
			terminal.japan_terminal_screen.name = "JapanTerminalScreen"
			if national_container != null:
				national_container.add_child(terminal.japan_terminal_screen)
			else:
				terminal.add_child(terminal.japan_terminal_screen)
			if tm.japan_empire_manager != null:
				terminal.japan_terminal_screen.setup(tm.japan_empire_manager)

	# 4. Италия (Italy Terminal Screen)
	if is_italy and terminal.italy_terminal_screen == null:
		var ita_scene = load("res://ui/screens/italy/italy_terminal_screen.tscn")
		if ita_scene != null:
			terminal.italy_terminal_screen = ita_scene.instantiate()
			terminal.italy_terminal_screen.name = "ItalyTerminalScreen"
			if national_container != null:
				national_container.add_child(terminal.italy_terminal_screen)
			else:
				terminal.add_child(terminal.italy_terminal_screen)
			if tm.italy_empire_manager != null:
				terminal.italy_terminal_screen.setup(tm.italy_empire_manager)

	# 5. Германия / Рейхсканцелярия (Germany Terminal Screen)
	if is_german and terminal.germany_terminal_screen == null:
		var ger_scene = load("res://ui/screens/germany/germany_terminal_screen.tscn")
		if ger_scene != null:
			terminal.germany_terminal_screen = ger_scene.instantiate()
			terminal.germany_terminal_screen.name = "GermanyTerminalScreen"
			if national_container != null:
				national_container.add_child(terminal.germany_terminal_screen)
			else:
				terminal.add_child(terminal.germany_terminal_screen)
			if tm.germany_campaign_manager != null:
				terminal.germany_terminal_screen.setup(tm.germany_campaign_manager)
			terminal.germany_terminal_screen.closed.connect(func():
				if terminal.tab_container != null: terminal.tab_container.current_tab = 0
			)

	# 6. Настройка видимости национальных панелей
	if terminal.russian_smuta_panel != null:
		terminal.russian_smuta_panel.visible = is_warlord
	if terminal.germany_terminal_screen != null:
		terminal.germany_terminal_screen.visible = is_german
	if terminal.gcw_operations_panel != null:
		terminal.gcw_operations_panel.visible = false
	if terminal.us_congress_screen != null:
		terminal.us_congress_screen.visible = is_usa
	if terminal.japan_terminal_screen != null:
		terminal.japan_terminal_screen.visible = is_japan
	if terminal.italy_terminal_screen != null:
		terminal.italy_terminal_screen.visible = is_italy

	# 7. Привязка кнопок тактической карты
	_setup_map_hud_buttons(terminal, is_warlord, is_german, is_usa, is_japan, is_italy)


"""Создает и стилизует контекстные кнопки национальных механик в заголовке карты.
"""
static func _setup_map_hud_buttons(
	terminal: TerminalMain,
	is_warlord: bool,
	is_german: bool,
	is_usa: bool,
	is_japan: bool,
	is_italy: bool
) -> void:
	var map_hud_hbox = terminal.get_node_or_null("TabContainer/TacticalMap/MapModeHUD/HBox")
	if map_hud_hbox == null:
		return

	# Кнопка законодательного органа
	if terminal.btn_parliament_toggle == null:
		terminal.btn_parliament_toggle = Button.new()
		var p_label := "[ 🏛 ПАРЛАМЕНТ ]"
		if is_usa: p_label = "[ 🏛 КОНГРЕСС ]"
		elif is_german: p_label = "[ 🏛 РЕЙХСТАГ ]"
		elif is_warlord: p_label = "[ 🏛 ВЕРХОВНЫЙ СОВЕТ ]"
		elif is_japan: p_label = "[ 🏯 ПАЛАТА ПЭРОВ ]"
		elif is_italy: p_label = "[ 🏛 ВЕЛИКИЙ СОВЕТ ]"
		terminal.btn_parliament_toggle.text = p_label
		TNOTheme.apply_button_style(terminal.btn_parliament_toggle, TNOTheme.COLOR_BORDER_CYAN, Color(0.06, 0.12, 0.15, 0.95))
		terminal.btn_parliament_toggle.pressed.connect(func():
			terminal._open_legislature_screen()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1100.0)
		)
		map_hud_hbox.add_child(terminal.btn_parliament_toggle)

	# Кнопка Рейхсканцелярии
	if terminal.btn_gcw_toggle == null:
		terminal.btn_gcw_toggle = Button.new()
		terminal.btn_gcw_toggle.text = terminal.tr("[ ⚡ РЕЙХСКАНЦЕЛЯРИЯ ]")
		TNOTheme.apply_button_style(terminal.btn_gcw_toggle, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.08, 0.04, 0.95))
		terminal.btn_gcw_toggle.pressed.connect(func():
			if terminal.tab_container != null and terminal.tab_container.get_tab_count() > 3 and not terminal.tab_container.is_tab_hidden(3):
				terminal.tab_container.current_tab = 3
				if terminal.germany_terminal_screen != null:
					terminal.germany_terminal_screen.visible = true
					terminal.germany_terminal_screen._refresh_ui()
				if terminal.gcw_operations_panel != null:
					terminal.gcw_operations_panel.visible = false
			elif terminal.germany_terminal_screen != null:
				terminal.germany_terminal_screen.visible = not terminal.germany_terminal_screen.visible
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1250.0)
			terminal.label_log.text = terminal._tr_str("LOG_REICH_TERMINAL", {}, "РЕЙХСКАНЦЕЛЯРИЯ: СИТУАЦИОННЫЙ ТЕРМИНАЛ АКТИВИРОВАН")
		)
		map_hud_hbox.add_child(terminal.btn_gcw_toggle)
	if terminal.btn_gcw_toggle != null:
		terminal.btn_gcw_toggle.visible = is_german

	# Кнопка оперативного штаба Рейха (ОКВ / GCW)
	if terminal.btn_okw_toggle == null:
		terminal.btn_okw_toggle = Button.new()
		terminal.btn_okw_toggle.text = terminal.tr("[ ⚔ ШТАБ РЕЙХА ]")
		TNOTheme.apply_button_style(terminal.btn_okw_toggle, TNOTheme.COLOR_BORDER_CYAN, Color(0.06, 0.12, 0.15, 0.95))
		terminal.btn_okw_toggle.pressed.connect(func():
			if terminal.tab_container != null and terminal.tab_container.get_tab_count() > 3 and not terminal.tab_container.is_tab_hidden(3):
				terminal.tab_container.current_tab = 3
				if terminal.gcw_operations_panel != null:
					terminal.gcw_operations_panel.visible = true
					terminal.gcw_operations_panel.refresh_ui()
				if terminal.germany_terminal_screen != null:
					terminal.germany_terminal_screen.visible = false
			elif terminal.gcw_operations_panel != null:
				terminal.gcw_operations_panel.visible = not terminal.gcw_operations_panel.visible
				if terminal.gcw_operations_panel.visible:
					terminal.gcw_operations_panel.refresh_ui()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1250.0)
			terminal.label_log.text = terminal._tr_str("LOG_OKW_TERMINAL", {}, "ОПЕРАТИВНЫЙ ШТАБ РЕЙХА: АКТИВИРОВАН")
		)
		map_hud_hbox.add_child(terminal.btn_okw_toggle)
	if terminal.btn_okw_toggle != null:
		terminal.btn_okw_toggle.visible = is_german

	# Кнопка Японии / Дзайбацу
	if terminal.btn_japan_toggle == null:
		terminal.btn_japan_toggle = Button.new()
		terminal.btn_japan_toggle.text = terminal.tr("[ 🏯 ДЗАЙБАЦУ ]")
		TNOTheme.apply_button_style(terminal.btn_japan_toggle, TNOTheme.COLOR_BORDER_CYAN, Color(0.06, 0.12, 0.15, 0.95))
		terminal.btn_japan_toggle.pressed.connect(func():
			if terminal.tab_container != null and terminal.tab_container.get_tab_count() > 3 and not terminal.tab_container.is_tab_hidden(3):
				terminal.tab_container.current_tab = 3
				if terminal.japan_terminal_screen != null:
					terminal.japan_terminal_screen.refresh_ui()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1250.0)
			terminal.label_log.text = terminal._tr_str("LOG_JAPAN_TERMINAL", {}, "ТЕРМИНАЛ ИМПЕРИИ ЯПОНИЯ: АКТИВИРОВАН")
		)
		map_hud_hbox.add_child(terminal.btn_japan_toggle)
	if terminal.btn_japan_toggle != null:
		terminal.btn_japan_toggle.visible = is_japan

	# Кнопка Италии / Триумвират
	if terminal.btn_italy_toggle == null:
		terminal.btn_italy_toggle = Button.new()
		terminal.btn_italy_toggle.text = terminal.tr("[ 🏛 ТРИУМВИРАТ ]")
		TNOTheme.apply_button_style(terminal.btn_italy_toggle, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.08, 0.04, 0.95))
		terminal.btn_italy_toggle.pressed.connect(func():
			if terminal.tab_container != null and terminal.tab_container.get_tab_count() > 3 and not terminal.tab_container.is_tab_hidden(3):
				terminal.tab_container.current_tab = 3
				if terminal.italy_terminal_screen != null:
					terminal.italy_terminal_screen.refresh_ui()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1250.0)
			terminal.label_log.text = terminal._tr_str("LOG_ITALY_TERMINAL", {}, "ТЕРМИНАЛ ИМПЕРИИ ИТАЛИЯ: АКТИВИРОВАН")
		)
		map_hud_hbox.add_child(terminal.btn_italy_toggle)
	if terminal.btn_italy_toggle != null:
		terminal.btn_italy_toggle.visible = is_italy

	# Кнопка НИОКР
	if terminal.btn_research_toggle == null:
		terminal.btn_research_toggle = Button.new()
		terminal.btn_research_toggle.text = terminal.tr("[ 🔬 НИОКР ]")
		TNOTheme.apply_button_style(terminal.btn_research_toggle, TNOTheme.COLOR_BORDER_CYAN, Color(0.06, 0.12, 0.15, 0.95))
		terminal.btn_research_toggle.pressed.connect(func():
			terminal._toggle_research_screen()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1250.0)
		)
		map_hud_hbox.add_child(terminal.btn_research_toggle)


"""Обновляет заголовки вкладок и локализованный текст кнопок интерфейса терминала.
"""
static func update_localized_ui(terminal: TerminalMain) -> void:
	if terminal == null:
		return
	var tc: TabContainer = terminal.tab_container
	if tc == null:
		tc = terminal.get_node_or_null("TabContainer")
	if tc == null:
		return

	var loc: Node = terminal._get_localization_manager()

	var tab_map: String = loc.tr_key("TAB_MAP", "ТАКТИЧЕСКАЯ КАРТА") if loc != null else "ТАКТИЧЕСКАЯ КАРТА"
	var tab_dir: String = loc.tr_key("TAB_DIRECTIVES", "НАЦИОНАЛЬНЫЕ ДИРЕКТИВЫ") if loc != null else "НАЦИОНАЛЬНЫЕ ДИРЕКТИВЫ"
	var tab_econ: String = loc.tr_key("TAB_ECONOMICS", "ГОСУДАРСТВЕННАЯ ЭКОНОМИКА") if loc != null else "ГОСУДАРСТВЕННАЯ ЭКОНОМИКА"

	var tab_smuta: String = "РУССКАЯ СМУТА // ВОССОЕДИНЕНИЕ"
	var is_warlord: bool = false
	var is_german: bool = false
	var is_usa: bool = false
	var is_japan: bool = false
	var is_italy: bool = false
	if terminal.turn_manager != null and terminal.turn_manager.player_state != null:
		var p_tag: String = terminal.turn_manager.player_state.country_tag.to_upper()
		is_warlord = RussianUnificationManager.is_warlord(p_tag)
		is_german = p_tag in ["GER", "BOR", "SPE", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]
		is_usa = (p_tag == "USA")
		is_japan = (p_tag == "JAP")
		is_italy = (p_tag == "ITA")

		if is_usa:
			tab_smuta = loc.tr_key("TAB_USA_CONGRESS", "КАПИТОЛИЙ // КОНГРЕСС США") if loc != null else "КАПИТОЛИЙ // КОНГРЕСС США"
		elif is_german:
			tab_smuta = loc.tr_key("TAB_GCW", "ШТАБ РЕЙХА // ГРАЖДАНСКАЯ ВОЙНА") if loc != null else "ШТАБ РЕЙХА // ГРАЖДАНСКАЯ ВОЙНА"
		elif is_japan:
			tab_smuta = loc.tr_key("TAB_JAPAN", "ИМПЕРИЯ // ДАЙЭТ И ДЗАЙБАЦУ") if loc != null else "ИМПЕРИЯ // ДАЙЭТ И ДЗАЙБАЦУ"
		elif is_italy:
			tab_smuta = loc.tr_key("TAB_ITALY", "РИМ // ВЕЛИКИЙ ФАШИСТСКИЙ СОВЕТ") if loc != null else "РИМ // ВЕЛИКИЙ ФАШИСТСКИЙ СОВЕТ"
		elif loc != null:
			tab_smuta = loc.tr_key("TAB_SMUTA", "РУССКАЯ СМУТА // ВОССОЕДИНЕНИЕ")

	var tab_dec: String = loc.tr_key("TAB_DECISIONS", "РЕШЕНИЯ И ДЕКРЕТЫ") if loc != null else "РЕШЕНИЯ И ДЕКРЕТЫ"

	if tc.get_tab_count() > 0:
		tc.set_tab_title(0, tab_map)
	if tc.get_tab_count() > 1:
		tc.set_tab_title(1, tab_dir)
	if tc.get_tab_count() > 2:
		tc.set_tab_title(2, tab_econ)
	if tc.get_tab_count() > 3:
		tc.set_tab_title(3, tab_smuta)
	if tc.get_tab_count() > 4:
		tc.set_tab_title(4, tab_dec)

	var has_national_tab: bool = is_warlord or is_german or is_usa or is_japan or is_italy
	if tc.get_tab_count() > 3:
		tc.set_tab_hidden(3, not has_national_tab)
		if not has_national_tab and tc.current_tab == 3:
			tc.current_tab = 0

	if tc.get_tab_count() > 5:
		var tab_esp: String = loc.tr_key("TAB_ESPIONAGE", "ШПИОНАЖ") if loc != null else "ШПИОНАЖ"
		tc.set_tab_title(5, tab_esp)
	if tc.get_tab_count() > 6:
		var tab_rnd: String = loc.tr_key("TAB_RESEARCH", "🔬 НИОКР // R&D") if loc != null else "🔬 НИОКР // R&D"
		tc.set_tab_title(6, tab_rnd)

	if terminal.btn_map_pol != null: terminal.btn_map_pol.text = loc.tr_key("MAP_MODE_POL", "ПОЛИТИЧЕСКАЯ") if loc != null else "ПОЛИТИЧЕСКАЯ"
	if terminal.btn_map_econ != null: terminal.btn_map_econ.text = loc.tr_key("MAP_MODE_ECON", "ЭКОНОМИКА") if loc != null else "ЭКОНОМИКА"
	if terminal.btn_map_unrest != null: terminal.btn_map_unrest.text = loc.tr_key("MAP_MODE_UNREST", "БЕСПОРЯДКИ") if loc != null else "БЕСПОРЯДКИ"
	if terminal.btn_map_diplo != null: terminal.btn_map_diplo.text = loc.tr_key("MAP_MODE_DIPLO", "ДИПЛОМАТИЯ") if loc != null else "ДИПЛОМАТИЯ"
	if terminal.btn_end_turn != null: terminal.btn_end_turn.text = loc.tr_key("BTN_END_TURN", "ЗАВЕРШИТЬ ХОД >>") if loc != null else "ЗАВЕРШИТЬ ХОД >>"
	if terminal.btn_save_game != null: terminal.btn_save_game.text = loc.tr_key("BTN_SAVE_GAME", "СОХРАНИТЬ (F5)") if loc != null else "СОХРАНИТЬ (F5)"
	if terminal.btn_load_game != null: terminal.btn_load_game.text = loc.tr_key("BTN_LOAD_GAME", "ЗАГРУЗИТЬ (F9)") if loc != null else "ЗАГРУЗИТЬ (F9)"
	if terminal.btn_ruler_focus != null:
		var r_act: String = loc.tr_key("BTN_RULER_ACTIVE", "[ ПРАВИТЕЛЬ: АКТИВЕН ]") if loc != null else "[ ПРАВИТЕЛЬ: АКТИВЕН ]"
		var r_inact: String = loc.tr_key("BTN_RULER_INACTIVE", "СТАВКА ВЕРХОВНОГО") if loc != null else "СТАВКА ВЕРХОВНОГО"
		terminal.btn_ruler_focus.text = r_act if (terminal.map_controller != null and terminal.map_controller.is_ruler_domain_focus) else r_inact
	if terminal.btn_raid_toggle != null:
		var rd_act: String = loc.tr_key("BTN_RAID_ACTIVE", "[ ПЛАНИРОВАНИЕ НАБЕГА ]") if loc != null else "[ ПЛАНИРОВАНИЕ НАБЕГА ]"
		var rd_inact: String = loc.tr_key("BTN_RAID_INACTIVE", "РЕЙДОВЫЕ ОПЕРАЦИИ") if loc != null else "РЕЙДОВЫЕ ОПЕРАЦИИ"
		terminal.btn_raid_toggle.text = rd_act if terminal.is_raid_mode_active else rd_inact


"""Инициализирует первичное состояние глобальной карты, сессии и театров.
"""
static func setup_initial_game_state(terminal: TerminalMain) -> void:
	if terminal == null or terminal.turn_manager == null:
		return

	var tm: TurnManager = terminal.turn_manager
	tm.load_world_data()

	var session_node: Node = terminal.get_node_or_null("/root/GameSession")
	var is_loading: bool = session_node != null and bool(session_node.get("is_loading_saved_game"))
	if is_loading:
		session_node.set("is_loading_saved_game", false)
		var loaded_ok: bool = tm.load_game("user://savegame.json")
		if loaded_ok:
			if terminal.map_controller != null:
				terminal.map_controller.populate_data_lut_from_regions(tm.regions_world_state, tm.player_state.country_tag)
				terminal.map_controller.refresh_tactical_frontlines()
			terminal.label_log.text = terminal._tr_str("UI_LOG_LOAD_SUCCESS", {"turn": tm.current_turn}, "СИСТЕМА: ИГРА УСПЕШНО ЗАГРУЖЕНА [user://savegame.json] (ХОД {turn})")
	elif session_node != null and session_node.get("active_player_state") != null:
		tm.set_player_state(session_node.get("active_player_state"))
	else:
		tm.player_state.turn_count = tm.current_turn
		tm.player_state.set_flag("turn_count", tm.current_turn)

	var crt_rect: CanvasItem = terminal._get_crt_node()
	var sm_node: Node = terminal._get_settings_manager()
	if crt_rect != null and sm_node != null and sm_node.has_method("register_crt_overlay"):
		sm_node.register_crt_overlay(crt_rect)
	elif crt_rect != null and session_node != null and crt_rect.material is ShaderMaterial and session_node.has_method("apply_crt_to_material"):
		session_node.apply_crt_to_material(crt_rect.material as ShaderMaterial)

	terminal.event_overlay.visible = false
	if terminal.tno_economy_screen != null:
		terminal.tno_economy_screen.setup(tm.player_state)

	var p_tag: String = tm.player_state.country_tag.to_upper()
	var is_warlord: bool = RussianUnificationManager.is_warlord(p_tag)
	var is_german: bool = p_tag in ["GER", "BOR", "SPE", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"]

	# Инициализация динамического стратегического театра военных действий под державу игрока
	if tm.player_state != null:
		MilitaryEngine.deploy_starting_theater(tm.player_state, tm.countries_world_state)

	# Инициализация модуля Германии и Немецкой Гражданской Войны
	if tm.german_civil_war_manager != null:
		tm.german_civil_war_manager.initialize(tm, terminal.map_controller, tm.player_state)

	# Регистрация и динамическая загрузка национальных экранов и кнопок карты
	setup_national_screens(terminal)

	# Стартовая резидентура разведки для погружения в сеттинг
	if tm.player_state != null and tm.player_state.active_agents.is_empty():
		var target_rival: String = "ONG" if is_warlord else ("SPE" if is_german else "GER")
		var ag1 = EspionageEngine.recruit_agent("Спектр", 3, target_rival, 0.6)
		var ag2 = EspionageEngine.recruit_agent("Сокол", 4, "", 0.8)
		tm.player_state.add_agent(ag1)
		tm.player_state.add_agent(ag2)
		tm.player_state.set_infiltration_level(target_rival, 25.0, "ESTABLISHING")
		tm.player_state.set_infiltration_level("GER" if target_rival != "GER" else "USA", 10.0, "ESTABLISHING")

	# Синхронизация данных карты и тактического оверлея
	terminal.map_controller.populate_data_lut_from_regions(tm.regions_world_state, tm.player_state.country_tag)
	terminal.map_controller.refresh_tactical_frontlines()
