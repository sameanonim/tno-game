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
