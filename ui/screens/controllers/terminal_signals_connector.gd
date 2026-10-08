class_name TerminalSignalsConnector
extends Node

##
## TerminalSignalsConnector: Модуль централизованной коммутации сигналов TerminalMain
## ==============================================================================
## Отвечает за:
## 1. Подключение сигналов пошагового цикла TurnManager к UI терминала.
## 2. Подключение региональных менеджеров кампаний (Смута, ГВГ, США, Япония, Италия).
## 3. Подключение сигналов глобальных автолоадов (Localization, Settings, Config, Session).
## 4. Коммутацию событий интерактивной карты, директив, экономики и реформ.
## ==============================================================================


"""Подключает всю совокупность сигналов подсистем к главному терминалу.
"""
static func connect_all_signals(terminal: TerminalMain) -> void:
	if terminal == null or terminal.turn_manager == null:
		return

	var tm = terminal.turn_manager

	# 1. Сигналы базового пошагового цикла
	if terminal.btn_end_turn != null and not terminal.btn_end_turn.pressed.is_connected(terminal._on_end_turn_pressed):
		terminal.btn_end_turn.pressed.connect(terminal._on_end_turn_pressed)

	tm.turn_started.connect(terminal._on_turn_started)
	tm.turn_completed.connect(terminal._on_turn_completed)
	tm.modal_event_opened.connect(terminal._on_modal_event_opened)
	tm.super_event_requested.connect(terminal.trigger_super_event)
	tm.tech_completed.connect(terminal._on_tech_completed)
	tm.us_electoral_report_generated.connect(terminal._on_us_electoral_report_generated)
	tm.game_over.connect(terminal._on_game_over)
	tm.espionage_processed.connect(terminal._on_espionage_processed)
	tm.autosaved.connect(func(turn: int, save_path: String):
		terminal.label_log.text = terminal._tr_str("LOG_AUTOSAVE", {"turn": turn, "path": save_path}, "АВТОСОХРАНЕНИЕ: Ход %d успешно записан [%s]" % [turn, save_path])
	)
	tm.world_data_loaded.connect(func(r_count: int, c_count: int):
		print("[TerminalMain] World data synchronized: %d regions, %d countries." % [r_count, c_count])
	)

	# 2. Военные сигналы и демаркация
	tm.region_conquered.connect(terminal._on_region_conquered)
	tm.state_conquered.connect(terminal._on_state_conquered)
	if not tm.state_transferred.is_connected(terminal._on_state_transferred):
		tm.state_transferred.connect(terminal._on_state_transferred)
	tm.military_frontlines_processed.connect(terminal._on_military_frontlines_processed)
	tm.defcon_level_changed.connect(terminal._on_defcon_level_changed)
	tm.societal_evolution_completed.connect(func(rep: Dictionary):
		if not rep.is_empty():
			terminal.label_log.text = terminal._tr_str("LOG_SOCIETY_EVOLUTION", {}, "ОБЩЕСТВО: Произошли эволюционные сдвиги в социальных институтах нации.")
	)

	# 3. Таб-контейнер и навигация
	if terminal.tab_container != null and not terminal.tab_container.tab_changed.is_connected(terminal._on_tab_changed):
		terminal.tab_container.tab_changed.connect(terminal._on_tab_changed)

	_connect_subsystems(terminal, tm)
	_connect_map_and_panels(terminal, tm)
	_connect_autoloads(terminal)


"""Подключает специализированные менеджеры подсистем (Смута, ГВГ, Фокусы, События, Разведка).
"""
static func _connect_subsystems(terminal: TerminalMain, tm: TurnManager) -> void:
	if tm.focus_stage_controller != null:
		tm.focus_stage_controller.stage_transition_requested.connect(func(target_tree_id: String, reason: String):
			terminal.label_log.text = terminal._tr_str("LOG_STAGE_TRANSITION", {"tree": target_tree_id, "reason": reason}, "СМЕНА ЭПОХИ: Переход на стадию директив [%s] (%s)" % [target_tree_id, reason])
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1500.0)
		)

	if tm.event_manager != null:
		tm.event_manager.event_triggered.connect(func(ev: GameEvent):
			if not ev.is_modal:
				terminal.label_log.text = "ДЕПЕША: [%s] %s" % [ev.title, ev.description.substr(0, 80)]
				if terminal.sound_fx != null: terminal.sound_fx.play_teletype_burst(4)
		)

	if tm.russian_unification_manager != null:
		tm.russian_unification_manager.operational_log_entry.connect(func(txt: String):
			terminal.label_log.text = terminal._tr_str("LOG_SMUTA_OP", {"text": txt}, "СМУТА: %s" % txt)
		)
		tm.russian_unification_manager.regional_triumph_achieved.connect(func(tag: String, macro_region: String, title: String):
			terminal.label_log.text = terminal._tr_str("LOG_REGIONAL_TRIUMPH", {"tag": tag, "region": macro_region, "title": title}, "РЕГИОНАЛЬНЫЙ ТРИУМФ: %s объединил %s (%s)!" % [tag, macro_region, title])
		)
		tm.russian_unification_manager.superregional_triumph_achieved.connect(func(tag: String, super_region: String, title: String):
			terminal.label_log.text = terminal._tr_str("LOG_SUPERREGIONAL_TRIUMPH", {"tag": tag, "region": super_region, "title": title}, "СУПЕРРЕГИОНАЛЬНЫЙ ТРИУМФ: %s объединил %s (%s)!" % [tag, super_region, title])
		)

	if tm.german_civil_war_manager != null:
		tm.german_civil_war_manager.gcw_concluded.connect(func(victor: String):
			terminal.label_log.text = terminal._tr_str("LOG_GCW_VICTORY", {"victor": victor}, "GCW: Гражданская война в Германии окончена победой %s" % victor)
		)
		tm.german_civil_war_manager.berlin_captured.connect(func(tag: String):
			if terminal.sound_fx != null: terminal.sound_fx.play_alarm_buzz(350.0, 0.4)
			terminal.label_log.text = terminal._tr_str("LOG_BERLIN_CAPTURED", {"tag": tag.to_upper()}, "ЭКСТРЕННОЕ СООБЩЕНИЕ: БЕРЛИН ВЗЯТ ШТУРМОМ СИЛАМИ [%s]!" % tag.to_upper())
			terminal._update_hud()
		)
		tm.german_civil_war_manager.goebbels_crisis_triggered.connect(func():
			if terminal.sound_fx != null: terminal.sound_fx.play_alarm_buzz(300.0, 0.5)
			terminal.label_log.text = terminal._tr_str("LOG_GOEBBELS_CRISIS", {}, "КРАСНАЯ ТРЕВОГА: НАЧАЛАСЬ ФАЗА ВТОРОЙ ГРАЖДАНСКОЙ ВОЙНЫ / КРИЗИС ГЁББЕЛЬСА!")
			terminal._update_hud()
		)
		tm.german_civil_war_manager.red_anarchy_triggered.connect(func():
			if terminal.sound_fx != null: terminal.sound_fx.play_alarm_buzz(250.0, 0.6)
			terminal.label_log.text = terminal._tr_str("LOG_RED_ANARCHY", {}, "КАТАСТРОФА: КРАСНАЯ АНАРХИЯ ОХВАТИЛА ГЕРМАНИЮ! РАСПАД ЦЕНТРАЛЬНОЙ ВЛАСТИ.")
			terminal._update_hud()
		)
		tm.german_civil_war_manager.proxy_lend_lease_delivered.connect(func(proxy_key: String, _w: int, _t: int, _cash: float):
			terminal.label_log.text = terminal._tr_str("LOG_LEND_LEASE", {"proxy": proxy_key.to_upper()}, "ПОСТАВКИ: Ленд-лиз успешно доставлен на ТВД [%s]" % proxy_key.to_upper())
			terminal._update_hud()
		)
		if not tm.german_civil_war_manager.focus_tree_switch_requested.is_connected(terminal._on_focus_tree_switch_requested):
			tm.german_civil_war_manager.focus_tree_switch_requested.connect(terminal._on_focus_tree_switch_requested)

	if tm.boundary_manager != null:
		tm.boundary_manager.enclave_detected.connect(func(state_id: int, owner_tag: String, surrounded_by: String):
			if tm.player_state != null and owner_tag == tm.player_state.country_tag:
				terminal.label_log.text = terminal._tr_str("LOG_ENCLAVE_ALERT", {"state": state_id, "tag": surrounded_by}, "ТРЕВОГА: Регион #%d окружен войсками [%s]! Линии снабжения перерезаны." % [state_id, surrounded_by])
				if terminal.sound_fx != null: terminal.sound_fx.play_alarm_buzz(320.0, 0.4)
		)
		tm.boundary_manager.territory_transferred.connect(func(state_id: int, _old_owner: String, new_owner: String, _is_enclave: bool):
			if terminal.map_controller != null and terminal.map_controller.has_method("set_state_owner"):
				terminal.map_controller.set_state_owner(state_id, new_owner)
		)

	if tm.japan_empire_manager != null:
		if not tm.japan_empire_manager.prime_minister_elected.is_connected(terminal._on_japan_prime_minister_elected):
			tm.japan_empire_manager.prime_minister_elected.connect(terminal._on_japan_prime_minister_elected)
		tm.japan_empire_manager.yasuda_crisis_triggered.connect(func(tse: float):
			terminal.label_log.text = terminal._tr_str("LOG_YASUDA_CRASH", {"tse": "%.0f" % tse}, "ТОКИЙСКАЯ БИРЖА: Крах Ясуда! Индекс TSE упал до %.0f!" % tse)
		)
		tm.japan_empire_manager.sphere_incident_reported.connect(func(member_tag: String, message: String):
			terminal.label_log.text = terminal._tr_str("LOG_SPHERE_INCIDENT", {"tag": member_tag, "msg": message}, "СФЕРА СОПРОЦВЕТАНИЯ (%s): %s" % [member_tag, message])
		)

	if tm.italy_empire_manager != null:
		if not tm.italy_empire_manager.ideology_path_chosen.is_connected(terminal._on_italy_ideology_path_chosen):
			tm.italy_empire_manager.ideology_path_chosen.connect(terminal._on_italy_ideology_path_chosen)
		tm.italy_empire_manager.council_power_shifted.connect(func(balance: float):
			terminal.label_log.text = terminal._tr_str("LOG_COUNCIL_POWER", {"balance": "%.0f" % balance}, "ВЕЛИКИЙ СОВЕТ: Баланс сил сместился: %.0f" % balance)
		)

	if tm.research_manager != null:
		tm.research_manager.research_started.connect(func(t_id: String, _turns: int):
			terminal.label_log.text = terminal._tr_str("LOG_RND_STARTED", {"tech": t_id}, "НИОКР: Начат исследовательский проект %s" % t_id)
		)
		tm.research_manager.research_cancelled.connect(func(t_id: String):
			terminal.label_log.text = terminal._tr_str("LOG_RND_CANCELLED", {"tech": t_id}, "НИОКР: Проект %s отменен" % t_id)
		)


"""Подключает сигналы элементов карты, панелей директив, экономики и решений.
"""
static func _connect_map_and_panels(terminal: TerminalMain, tm: TurnManager) -> void:
	if terminal.super_event_modal != null and not terminal.super_event_modal.option_selected.is_connected(terminal._on_super_event_closed):
		terminal.super_event_modal.option_selected.connect(terminal._on_super_event_closed)

	if terminal.tno_topbar != null:
		terminal.tno_topbar.end_turn_requested.connect(terminal._on_end_turn_pressed)
		terminal.tno_topbar.country_flag_clicked.connect(terminal._on_country_flag_clicked)
		terminal.tno_topbar.defcon_clicked.connect(terminal._on_defcon_clicked)
		terminal.tno_topbar.directive_clicked.connect(terminal._on_topbar_directive_clicked)

	if terminal.directive_tree_view != null:
		terminal.directive_tree_view.directive_initiated.connect(func(d: DirectiveResource):
			terminal._update_hud()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1200.0)
			terminal.label_log.text = "DIRECTIVE INITIATED: %s" % d.title
		)
		terminal.directive_tree_view.directive_selected.connect(func(_d: DirectiveResource):
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(850.0)
		)
		terminal.directive_tree_view.directive_hovered.connect(func(_d: DirectiveResource):
			if terminal.sound_fx != null and terminal.sound_fx.has_method("play_switch_click"):
				terminal.sound_fx.play_switch_click(1600.0)
		)

	if terminal.politics_panel != null:
		terminal.politics_panel.law_reformed.connect(func(law_id: String, tier: int):
			terminal._update_hud()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1400.0)
			terminal.label_log.text = terminal._tr_str("LOG_LAW_REFORMED", {"law": law_id, "tier": tier}, "РЕФОРМА: Закон «%s» изменен (уровень %d)" % [law_id, tier])
		)

	if terminal.espionage_terminal_view != null:
		terminal.espionage_terminal_view.operation_launched.connect(func(op: CovertOperationResource):
			terminal._update_hud()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1250.0)
			terminal.label_log.text = terminal._tr_str("LOG_ESPIONAGE_LAUNCHED", {"title": op.title}, "РАЗВЕДКА: Начата спецоперация «%s»" % op.title)
		)
		terminal.espionage_terminal_view.operation_aborted.connect(func(op: CovertOperationResource):
			terminal._update_hud()
			if terminal.sound_fx != null: terminal.sound_fx.play_alarm_buzz(450.0, 0.2)
			terminal.label_log.text = terminal._tr_str("LOG_ESPIONAGE_ABORTED", {"title": op.title}, "РАЗВЕДКА: Прервана спецоперация «%s»" % op.title)
		)
		terminal.espionage_terminal_view.agent_assigned.connect(func(agent_id: String, _slot: int):
			terminal._update_hud()
			terminal.label_log.text = terminal._tr_str("LOG_AGENT_ASSIGNED", {"agent": agent_id}, "РАЗВЕДКА: Агент %s задействован на задании" % agent_id)
		)
		terminal.espionage_terminal_view.agent_recalled.connect(func(agent_id: String):
			terminal._update_hud()
			terminal.label_log.text = terminal._tr_str("LOG_AGENT_RECALLED", {"agent": agent_id}, "РАЗВЕДКА: Агент %s отозван в резерв" % agent_id)
		)

	if terminal.map_controller != null:
		terminal.map_controller.map_mode_changed.connect(func(new_mode: int):
			var mode_names = [
				"ПОЛИТИЧЕСКАЯ КАРТА (СУВЕРЕНИТЕТ)",
				"КАРТА ПРОИЗВОДСТВЕННОГО ПОТЕНЦИАЛА (IC)",
				"КАРТА ОБЩЕСТВЕННОГО НЕДОВОЛЬСТВА (UNREST)",
				"КАРТА ГЕОПОЛИТИЧЕСКИХ СФЕР ВЛИЯНИЯ (SPHERES)"
			]
			var m_name = mode_names[new_mode] if new_mode < mode_names.size() else "КАРТА"
			terminal.label_log.text = terminal._tr_str("LOG_MAP_MODE", {"mode": m_name}, "РЕЖИМ КАРТЫ: %s" % m_name)
		)
		terminal.map_controller.province_hovered.connect(func(pid, data):
			var feat = terminal.map_controller.get_province_features(pid)
			var c_name = feat.get("city_name_ru", "")
			if c_name.is_empty(): c_name = feat.get("city_name_en", "")
			var loc_name = c_name if not c_name.is_empty() else data.get("name", "Регион #%d" % pid)
			var vp_str = (" [★ %d VP]" % feat.get("vp")) if feat.get("vp", 0) > 0 else ""
			terminal.label_log.text = "LOC: %s (PID: %d)%s | OWNER: %s" % [loc_name, pid, vp_str, data.get("owner", "WRRF")]
		)
		terminal.map_controller.province_unhovered.connect(func(_pid: int):
			if terminal.label_log != null: terminal.label_log.text = ""
		)
		terminal.map_controller.province_clicked.connect(func(pid, data, btn):
			if btn == MOUSE_BUTTON_LEFT and terminal.map_hud_controller != null:
				terminal.map_hud_controller.handle_province_click(pid, data)
		)
		terminal.map_controller.province_selected.connect(func(pid: int, _data: Dictionary):
			if terminal.province_inspector_panel != null:
				var reg_obj: RegionData = tm.regions_world_state.get(pid, null)
				terminal.province_inspector_panel.inspect_province(pid, terminal.map_controller.province_features_data, tm.player_state.country_tag, reg_obj)
		)
		terminal.map_controller.tactical_view_toggled.connect(func(is_tactical: bool):
			if terminal.sound_fx != null and terminal.sound_fx.has_method("play_switch_click"):
				terminal.sound_fx.play_switch_click(1200.0 if is_tactical else 600.0)
		)

	if terminal.tno_economy_screen != null:
		terminal.tno_economy_screen.setup(tm.player_state)
		terminal.tno_economy_screen.state_modified.connect(terminal._update_hud)

	if terminal.russian_smuta_panel != null:
		terminal.russian_smuta_panel.setup(tm.player_state, tm)
		terminal.russian_smuta_panel.raid_requested.connect(terminal._launch_raid)
		terminal.russian_smuta_panel.proclamation_requested.connect(func():
			terminal._update_hud()
			if terminal.sound_fx != null: terminal.sound_fx.play_alarm_buzz(580.0, 0.3)
		)
		terminal.russian_smuta_panel.stage_advance_requested.connect(func():
			terminal._update_hud()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1400.0)
			terminal.label_log.text = terminal._tr_str("LOG_SMUTA_STAGE_ADVANCE", {}, "СМУТА: Инициирован переход на следующую стадию объединения.")
		)
		terminal.russian_smuta_panel.diplomatic_summit_requested.connect(func(target_tag: String):
			if tm.russian_unification_manager != null:
				var res = tm.russian_unification_manager.execute_diplomatic_summit(target_tag, tm)
				var success = res.get("success", false)
				terminal.label_log.text = terminal._tr_str("LOG_DIPLOMACY", {"msg": res.get("message", "")}, "ДИПЛОМАТИЯ: %s" % res.get("message", ""))
				if terminal.sound_fx != null:
					if success: terminal.sound_fx.play_switch_click(1300.0)
					else: terminal.sound_fx.play_alarm_buzz(450.0, 0.3)
				terminal._update_hud()
				terminal.russian_smuta_panel.refresh_ui()
		)

	if terminal.decisions_panel != null:
		terminal.decisions_panel.setup(tm.player_state, tm)
		terminal.decisions_panel.decision_executed.connect(func(_dec_id: String, effects: Dictionary):
			terminal._update_hud()
			if terminal.sound_fx != null: terminal.sound_fx.play_switch_click(1300.0)
			var log_str = effects.get("log", "Инициатива утверждена.")
			terminal.label_log.text = terminal._tr_str("LOG_DECREE", {"msg": log_str}, "ДЕКРЕТ: %s" % log_str)
		)


"""Подключает глобальные автолоады (локализация, настройки, конфигурация).
"""
static func _connect_autoloads(terminal: TerminalMain) -> void:
	if terminal.has_node("/root/LocalizationManager"):
		var loc = terminal.get_node("/root/LocalizationManager")
		if not loc.locale_changed.is_connected(terminal._on_locale_changed):
			loc.locale_changed.connect(terminal._on_locale_changed)
		if not loc.locale_updated.is_connected(terminal._on_locale_changed):
			loc.locale_updated.connect(terminal._on_locale_changed)

	var sm = terminal._get_settings_manager()
	if sm != null:
		if not sm.crt_param_changed.is_connected(terminal._on_crt_param_changed):
			sm.crt_param_changed.connect(terminal._on_crt_param_changed)
		if not sm.crt_enabled_changed.is_connected(terminal._on_crt_enabled_changed):
			sm.crt_enabled_changed.connect(terminal._on_crt_enabled_changed)
		if not sm.ui_scale_changed.is_connected(terminal._on_ui_scale_changed):
			sm.ui_scale_changed.connect(terminal._on_ui_scale_changed)

	if terminal.has_node("/root/ConfigManager"):
		var cfg = terminal.get_node("/root/ConfigManager")
		if not cfg.constants_reloaded.is_connected(func(): terminal._update_hud()):
			cfg.constants_reloaded.connect(func(): terminal._update_hud())

	if terminal.has_node("/root/GameSession"):
		var gs = terminal.get_node("/root/GameSession")
		if not gs.session_bootstrapped.is_connected(func(_c): print("[TerminalMain] Session bootstrapped")):
			gs.session_bootstrapped.connect(func(_c): print("[TerminalMain] Session bootstrapped"))
		if not gs.crt_settings_updated.is_connected(func(_s): terminal._apply_crt_to_overlay()):
			gs.crt_settings_updated.connect(func(_s): terminal._apply_crt_to_overlay())
