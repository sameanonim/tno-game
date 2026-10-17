class_name TestPhase34WRRFCampaign
extends TNOSimpleTest

"""
TestPhase34WRRFCampaign: Тестовый набор Фазы 3.4 — Западнорусский Революционный Фронт (ЗРРФ / WRS)
==============================================================================
Аудит и интеграционное тестирование кампании ЗРРФ:
1. 3.4.1 Целостность пакета данных WRS (country.json, territory.json, trees_manifest.json, 8 фокусных деревьев, портреты, события).
2. 3.4.2 Борьба за власть: механика Жукова и Тухачевского, парады, сбор досье, операция Жар-Птица, авторазрешение и смена лидера.
3. 3.4.3 Ветка Маршала Тухачевского: Секретный Арсенал (ОБТ, Ураган, Циклон, Щука, Леший, Фермент).
4. 3.4.4 Ветка Маршала Жукова: Баланс Триумвирата (Ахромеев, Рыжков, Яковлев) и сопутствующие реформы.
5. 3.4.5 Смена деревьев директив по стадиям (Начальное -> Конец бомбардировок -> Варлорд -> Регионал -> Суперрегионал).
6. 3.4.6 Стресс-тест пошагового цикла: прогон 50 ходов кампании ЗРРФ без сбоев.
==============================================================================
"""


func test_3_4_1_wrrf_data_package_integrity() -> void:
	# 1. Проверка data/countries/WRS/country.json
	var country_path := "res://data/countries/WRS/country.json"
	assert_true(FileAccess.file_exists(country_path), "Файл data/countries/WRS/country.json существует")

	var f := FileAccess.open(country_path, FileAccess.READ)
	assert_true(f != null, "Файл WRS country.json успешно открывается")
	if f != null:
		var c_data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		assert_true(c_data is Dictionary, "WRS country.json парсится в Dictionary")
		if c_data is Dictionary:
			assert_eq(str(c_data.get("tag", "")), "WRS", "Тег страны в country.json равен WRS")
			assert_true(str(c_data.get("name_text", "")).contains("Западнорусский"), "Название страны содержит Западнорусский")
			assert_eq(int(c_data.get("capital", 0)), 214, "Столица ЗРРФ — Архангельск/Плесецк (провинция 214)")
			assert_eq(str(c_data.get("ruling_party", "")), "communist", "Стартовая правящая партия — коммунисты")
			var ideas: Array = c_data.get("ideas", [])
			assert_true(ideas.has("RUS_terror_bombing"), "Присутствует стартовый нацдух террористических бомбардировок")
			assert_true(ideas.has("WRS_veterans_of_the_long_war"), "Присутствует нацдух ветеранов долгой войны")
			assert_true(ideas.has("WRS_agricultural_insecurity"), "Присутствует нацдух сельскохозяйственной нестабильности")

	# 2. Проверка data/countries/WRS/territory.json
	var territory_path := "res://data/countries/WRS/territory.json"
	assert_true(FileAccess.file_exists(territory_path), "Файл territory.json для WRS существует")
	if FileAccess.file_exists(territory_path):
		var tf := FileAccess.open(territory_path, FileAccess.READ)
		var t_data: Variant = JSON.parse_string(tf.get_as_text())
		tf.close()
		if t_data is Dictionary:
			assert_eq(int(t_data.get("provinces_count", 0)), 57, "ЗРРФ контролирует 57 провинций на старте")
			var provs: Array = t_data.get("provinces", [])
			var has_north_provinces: bool = false
			for p in provs:
				if int(p) == 312 or int(p) == 105:
					has_north_provinces = true
					break
			assert_true(has_north_provinces, "Провинции ЗРРФ содержат ключевые регионы Севера (включая Архангельск 312)")

	# 3. Проверка манифеста и всех деревьев директив
	var manifest_path := "res://data/countries/WRS/directives/trees_manifest.json"
	assert_true(FileAccess.file_exists(manifest_path), "Файл trees_manifest.json существует")
	if FileAccess.file_exists(manifest_path):
		var mf := FileAccess.open(manifest_path, FileAccess.READ)
		var m_data: Variant = JSON.parse_string(mf.get_as_text())
		mf.close()
		if m_data is Dictionary:
			assert_eq(str(m_data.get("starting_tree_id", "")), "WRS_initial", "Стартовое дерево — WRS_initial")
			var trees_dict: Dictionary = m_data.get("trees", {})
			assert_true(trees_dict.has("WRS_initial"), "В манифесте есть дерево WRS_initial")
			assert_true(trees_dict.has("WRS_bombings_end"), "В манифесте есть дерево WRS_bombings_end")
			assert_true(trees_dict.has("WRS_zhukov_warlord"), "В манифесте есть дерево WRS_zhukov_warlord")
			assert_true(trees_dict.has("WRS_tukhachevsky_warlord"), "В манифесте есть дерево WRS_tukhachevsky_warlord")
			assert_true(trees_dict.has("WRS_zhukov_regional"), "В манифесте есть дерево WRS_zhukov_regional")
			assert_true(trees_dict.has("WRS_tukhachevsky_regional"), "В манифесте есть дерево WRS_tukhachevsky_regional")

	# 4. Проверка портретов ключевых лидеров ЗРРФ
	assert_true(FileAccess.file_exists("res://assets/gfx/leaders/WRS/WRS_Georgy_Zhukov.png"), "Портрет Жукова существует")
	assert_true(FileAccess.file_exists("res://assets/gfx/leaders/WRS/WRS_Mikhail_Tukhachevsky.png"), "Портрет Тухачевского существует")
	assert_true(FileAccess.file_exists("res://assets/gfx/leaders/WRS/WRS_Alexander_Yegorov.png"), "Портрет Егорова существует")


func test_3_4_2_wrrf_power_struggle_mechanics() -> void:
	var mgr := WRRFMechanicsManager.new()
	var state := CountryState.new()
	state.country_tag = "WRS"
	state.country_name = "Западнорусский Революционный Фронт"
	state.infantry_weapons_stockpile = 5000
	state.army_readiness = 40.0
	state.war_support_percent = 50.0
	state.legitimacy = 60.0
	state.stability = 0.5
	mgr.setup(state)

	# 1. Стартовые показатели баланса
	assert_eq(mgr.state.zhukov_influence, 50.0, "Стартовое влияние Жукова — 50%")
	assert_eq(mgr.state.tukhachevsky_influence, 50.0, "Стартовое влияние Тухачевского — 50%")
	assert_true(not mgr.state.power_struggle_resolved, "Борьба за власть изначально не разрешена")

	# 2. Действия в пользу Жукова
	mgr.execute_decision_action("WRS_appease_zhukov")
	assert_true(mgr.state.zhukov_influence > 50.0, "Влияние Жукова выросло после уступок")

	mgr.execute_decision_action("WRS_zhukov_military_parade")
	assert_true(state.infantry_weapons_stockpile < 5000, "Винтовки израсходованы на проведение парада")
	assert_true(mgr.state.veterans_support_zhukov > 58.0, "Поддержка ветеранов для Жукова выросла")

	mgr.execute_decision_action("WRS_zhukov_compile_evidence")
	assert_true(mgr.state.evidence_compiled_against_tukha, "Досье на Тухачевского собрано")
	assert_true(state.has_flag("wrs_zhukov_evidence_compiled"), "Флаг сбора досье установлен в CountryState")

	# 3. Разрешение борьбы за власть в пользу Жукова
	var winner_id = mgr.resolve_power_struggle(WRRFCampaignState.Successor.ZHUKOV)
	assert_eq(winner_id, WRRFMechanicsManager.LEADER_ZHUKOV_ID, "Победителем утвержден Георгий Жуков")
	assert_true(mgr.state.power_struggle_resolved, "Борьба за власть помечена как завершенная")
	assert_true(state.has_flag("wrs_zhukov_chosen"), "Установлен флаг wrs_zhukov_chosen")
	assert_eq(state.leader_name, "Георгий Жуков", "Имя лидера изменено на Георгий Жуков")


func test_3_4_3_tukhachevsky_path_and_arsenal() -> void:
	var mgr := WRRFMechanicsManager.new()
	var state := CountryState.new()
	state.country_tag = "WRS"
	state.infantry_weapons_stockpile = 3000
	state.heavy_equipment_stockpile = 50
	state.army_readiness = 45.0
	mgr.setup(state)

	# 1. Действия в пользу Тухачевского
	mgr.execute_decision_action("WRS_appease_tukha")
	mgr.execute_decision_action("WRS_tukha_operation_firebird")
	assert_true(mgr.state.operation_firebird_executed, "Операция Жар-Птица выполнена")
	assert_true(state.has_flag("wrs_tukha_firebird_done"), "Флаг операции Жар-Птица установлен")

	# 2. Утверждение Тухачевского
	var winner_id = mgr.resolve_power_struggle(WRRFCampaignState.Successor.TUKHACHEVSKY)
	assert_eq(winner_id, WRRFMechanicsManager.LEADER_TUKHA_ID, "Победителем утвержден Михаил Тухачевский")
	assert_true(state.has_flag("wrs_tukhachevsky_chosen"), "Установлен флаг wrs_tukhachevsky_chosen")
	assert_eq(state.leader_name, "Михаил Тухачевский", "Имя лидера — Михаил Тухачевский")

	# 3. Секретный арсенал: Программа ОБТ
	assert_true(not mgr.state.obt_completed, "ОБТ изначально не завершен")
	mgr.advance_obt_program(50.0)
	assert_eq(mgr.state.obt_progress, 50.0, "Прогресс ОБТ равен 50%")
	mgr.advance_obt_program(50.0)
	assert_true(mgr.state.obt_completed, "ОБТ успешно разработан на 100%")
	assert_true(state.has_flag("wrs_obt_completed"), "Установлен флаг wrs_obt_completed")
	assert_true(state.heavy_equipment_stockpile > 50, "Тяжелая техника поступила на склады")

	# 4. Активация проектов Ураган, Циклон, Щука, Леший, Фермент, Ижевск
	mgr.execute_decision_action("WRS_project_uragan")
	assert_true(mgr.state.uragan_active, "Проект Ураган активирован")

	mgr.execute_decision_action("WRS_project_tsysklon")
	assert_true(mgr.state.tsysklon_active, "Проект Циклон активирован")

	mgr.execute_decision_action("WRS_project_shchuka")
	assert_true(mgr.state.shchuka_active, "Проект Щука активирован")

	mgr.execute_decision_action("WRS_project_leshiy")
	assert_true(mgr.state.leshiy_active, "Проект Леший активирован")

	mgr.execute_decision_action("WRS_project_ferment")
	assert_true(mgr.state.ferment_chemical_stockpile > 0, "Химический арсенал пополнен")

	mgr.execute_decision_action("WRS_izhevsk_experimental_constructor_works")
	assert_true(mgr.state.izhevsk_works_expanded, "Ижевский опытный завод расширен")


func test_3_4_4_zhukov_triumvirate_balancing() -> void:
	var mgr := WRRFMechanicsManager.new()
	var state := CountryState.new()
	state.country_tag = "WRS"
	state.gdp_billions = 2.5
	state.legitimacy = 60.0
	state.radicalization = 30.0
	mgr.setup(state)

	# 1. Смещение в пользу Ахромеева
	mgr.execute_decision_action("WRS_appease_akhromeyev")
	assert_true(mgr.state.akhromeyev_influence > 33.3, "Влияние Ахромеева возросло")

	mgr.execute_decision_action("WRS_akhromeyev_draw_closer_to_USA")
	assert_true(mgr.state.us_equipment_imported, "Техника из США закуплена")
	assert_true(state.has_flag("wrs_us_supplies_received"), "Флаг помощи США установлен")

	# 2. Смещение в пользу Рыжкова
	mgr.execute_decision_action("WRS_appease_ryzhkov")
	mgr.execute_decision_action("WRS_ryzhkov_agricultural_mechanization")
	assert_true(mgr.state.agricultural_mechanization_done, "Сельское хозяйство механизировано")
	assert_true(state.gdp_billions > 2.5, "ВВП вырос от механизации сельского хозяйства")

	mgr.execute_decision_action("WRS_ryzhkov_establish_the_kgb")
	assert_true(mgr.state.kgb_established, "КГБ учрежден")

	# 3. Смещение в пользу Яковлева
	mgr.execute_decision_action("WRS_appease_yakovlev")
	mgr.execute_decision_action("WRS_yakovlev_eliminate_ofn_tariffs")
	assert_true(mgr.state.ofn_tariffs_eliminated, "Тарифы ОФН устранены")

	mgr.execute_decision_action("WRS_yakovlev_abolish_gulag")
	assert_true(mgr.state.gulag_system_abolished, "ГУЛАГ ликвидирован")
	assert_true(state.radicalization < 30.0, "Радикализация трудящихся снизилась")


func test_3_4_5_wrrf_unification_tree_transitions() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "WRS"
	state.country_name = "Западнорусский Революционный Фронт"
	state.leader_name = "Александр Егоров"
	state.political_capital = 100.0
	state.legitimacy = 65.0
	state.radicalization = 20.0
	tm.set_player_state(state)

	var fsc := tm.focus_stage_controller
	assert_true(fsc != null, "FocusStageController инициализирован в TurnManager")

	# 1. Стартовое дерево - WRS_initial
	assert_true(fsc.current_tree_id == "WRS_initial", "Стартовое дерево ЗРРФ — WRS_initial")

	# 2. Окончание бомбардировок Рейха
	state.set_flag("bombings_ended", true)
	fsc.process_turn(1, state)
	assert_true(fsc.current_tree_id == "WRS_bombings_end", "Переход на WRS_bombings_end после окончания бомбардировок")

	# 3. Утверждение Жукова в период Смуты
	state.set_flag("smuta_active", true)
	state.set_flag("wrs_zhukov_chosen", true)
	state.leader_name = "Георгий Жуков"
	fsc.process_turn(2, state)
	assert_true(fsc.current_tree_id == "WRS_zhukov_warlord", "Переход на WRS_zhukov_warlord после утверждения Жукова")

	# 4. Региональное объединение Западной России
	state.set_flag("is_regional_unifier", true)
	fsc.process_turn(3, state)
	assert_true(fsc.current_tree_id == "WRS_zhukov_regional", "Переход на WRS_zhukov_regional после покорения региона")

	# 5. Суперрегиональное объединение Европейской России
	state.set_flag("is_superregional_unifier", true)
	fsc.process_turn(4, state)
	assert_true(fsc.current_tree_id == "WRS_zhukov_superregional", "Переход на WRS_zhukov_superregional")


func test_3_4_6_wrrf_50_turns_stress_cycle() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "WRS"
	state.country_name = "Западнорусский Революционный Фронт"
	state.leader_name = "Александр Егоров"
	state.political_capital = 150.0
	state.legitimacy = 70.0
	state.radicalization = 20.0
	state.gdp_billions = 3.2
	state.liquid_reserves_billions = 0.5
	tm.set_player_state(state)

	# Симулируем 50 ходов кампании ЗРРФ
	for i in range(50):
		state.legitimacy = maxf(state.legitimacy, 60.0)
		state.radicalization = minf(state.radicalization, 30.0)

		# Разрешаем модальные окна если появились
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

		# На 10 ходе моделируем разрешение борьбы за власть
		if tm.current_turn == 10:
			var rum = tm.russian_unification_manager
			if rum != null and rum.warlord_mechanics != null and rum.warlord_mechanics.wrrf_manager != null:
				rum.warlord_mechanics.wrrf_manager.resolve_power_struggle(WRRFCampaignState.Successor.ZHUKOV)

		tm.advance_turn()

		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

	assert_true(tm.current_turn >= 50, "Кампания ЗРРФ успешно отработала 50 ходов")
	assert_true(state.gdp_billions > 0.0, "Экономика ЗРРФ сохранила жизнеспособность после 50 ходов")
