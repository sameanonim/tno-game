extends SceneTree

#
# test_gameplay_simulation.gd
# Комплексный аудит игрового цикла: симуляция 15 ходов для KOM, GER, USA
#

const GameSessionScript = preload("res://core/systems/game_session.gd")

func _init() -> void:
	print("================================================================================")
	print(" ЗАПУСК СИМУЛЯЦИИ ИГРОВОГО ЦИКЛА (GAMEPLAY LOOP AUDIT)")
	print("================================================================================")
	
	var tags_to_test = ["KOM", "GER", "USA"]
	var total_errors = 0
	
	for tag in tags_to_test:
		print("\n--------------------------------------------------------------------------------")
		print(">>> СИМУЛЯЦИЯ КАМПАНИИ ДЛЯ НАЦИИ: [%s]" % tag)
		print("--------------------------------------------------------------------------------")
		
		var config = GameSessionScript.GameStartConfig.new()
		config.selected_country_tag = tag
		config.difficulty = GameSessionScript.Difficulty.STRATEGIST
		
		var session = root.get_node_or_null("GameSession")
		if session == null:
			session = GameSessionScript.new()
			session.name = "GameSession"
			root.add_child(session)
		
		# Запуск bootstrap
		var dossier = session.get_country_dossier(tag)
		var state = CountryState.new()
		state.country_tag = dossier.get("tag", tag)
		state.country_name = dossier.get("name", tag)
		state.leader_name = dossier.get("leader_name", "Лидер")
		state.ruling_ideology = dossier.get("ideology", "Деспотизм")
		state.sub_ideology = dossier.get("sub_ideology", "")
		state.country_color = dossier.get("color", Color.WHITE)
		state.gdp_billions = dossier.get("starting_gdp", 20.0)
		state.manpower_pool = dossier.get("starting_manpower", 75000)
		state.military_factories = int(dossier.get("starting_factories", 30) * 0.6)
		state.civilian_factories = int(dossier.get("starting_factories", 30) * 0.4)
		state.political_capital = 100.0
		state.current_cap = 5
		state.max_cap = 5
		session.active_player_state = state
		
		# Создаем TurnManager
		var tm = TurnManager.new()
		tm.name = "TurnManager_%s" % tag
		root.add_child(tm)
		tm.player_state = state
		tm.load_world_data()
		
		# Инициализация военных театров
		MilitaryEngine.deploy_starting_theater(state, tm.countries_world_state)
		
		# Инициализация FocusStageController
		if tm.focus_stage_controller != null:
			tm.focus_stage_controller.setup(state, tm.directive_manager, tm, tm.event_manager)
		
		# Загрузка ивентов
		if tm.event_manager != null:
			tm.event_manager.load_country_events(tag)
		
		print("  -> Стартовое состояние инициализировано:")
		print("     ВВП: $%.2fB, Склады: %d, Рекруты: %d, Капитал: %.1f PC" % [
			state.gdp_billions, state.infantry_weapons_stockpile, state.manpower_pool, state.political_capital
		])
		print("     Активное древо: [%s], Доступных директив: %d" % [
			tm.focus_stage_controller.current_tree_id if tm.focus_stage_controller != null else "NONE",
			tm.directive_manager.all_directives.size() if tm.directive_manager != null else 0
		])
		
		# Подключаем авто-разрешение модальных событий
		tm.modal_event_opened.connect(func(ev: GameEvent):
			print("     [Ход %d] СИГНАЛ МОДАЛЬНОГО СОБЫТИЯ: [%s] «%s» (Вариантов: %d)" % [
				tm.current_turn, ev.event_id, ev.title, ev.options.size()
			])
			# Выбираем вариант 0
			tm.resolve_modal_event_choice(ev, 0)
		)
		
		# Симуляция 15 ходов
		var turns_to_run = 15
		for t in range(1, turns_to_run + 1):
			# Если нет активной директивы — пытаемся взять первую доступную
			if tm.player_state.active_directives.is_empty() and tm.directive_manager != null:
				for d_id in tm.directive_manager.all_directives.keys():
					var d = tm.directive_manager.all_directives[d_id]
					if tm.directive_manager.can_start_directive(d, state):
						var ok = tm.start_directive(d)
						if ok:
							print("     [Ход %d] Начата директива: «%s» (%s)" % [t, d.title, d_id])
							break
			
			# Эмуляция завершения хода
			tm.end_turn()
			
			if t % 5 == 0 or t == turns_to_run:
				print("  -> Ход %d/%d завершен. ВВП: $%.2fB, Долг: $%.2fB, Резервы: $%.2fB, Инфляция: %.2f%%, Завершено директив: %d" % [
					tm.current_turn, turns_to_run,
					state.gdp_billions, state.national_debt_billions, state.liquid_reserves_billions,
					state.inflation_rate * 100.0, state.completed_directives.size()
				])
		
		print("  -> Завершена симуляция для [%s]. Итог: Стабильность=%.1f%%, Легитимность=%.1f%%" % [
			tag, state.get_stability_index() * 100.0, state.legitimacy
		])
		
		tm.queue_free()
	
	print("\n================================================================================")
	print(" СИМУЛЯЦИЯ ЗАВЕРШЕНА. ОШИБОК: %d" % total_errors)
	print("================================================================================")
	quit(total_errors)
