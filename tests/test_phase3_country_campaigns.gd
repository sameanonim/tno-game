class_name TestPhase3CountryCampaigns
extends TNOSimpleTest

##
## TestPhase3CountryCampaigns: Интеграционный тестовый набор Фазы 3
## ==============================================================================
## Тестирует сквозные страновые кампании ключевых наций:
## 1. 🇷🇺 Республика Коми (KOM) — стартовое дерево, выборы, перевороты, Смута, 50 ходов
## 2. 🇩🇪 Великогерманский Рейх (GER) — смерть Гитлера, гражданская война, выбор преемника, пост-GCW
## 3. 🇺🇸 США (USA) — старт Никсона, избирательная система USElectoralEngine, выборы 1964/1968
## ==============================================================================


func test_komi_campaign_lifecycle() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "KOM"
	state.country_name = "Республика Коми"
	state.political_capital = 100.0
	state.legitimacy = 70.0
	state.radicalization = 25.0
	tm.set_player_state(state)

	var fsc := tm.focus_stage_controller
	assert_true(fsc != null, "FocusStageController initialized in TurnManager")

	# 1. Стартовое дерево - KOM_pre_election
	assert_true(fsc.current_tree_id == "KOM_pre_election", "Starting tree for KOM is KOM_pre_election")

	# 2. Выборы: победа левых/демократов (DSNP Вознесенского)
	state.set_flag("komi_election_winner_dsnp", true)
	fsc.process_turn(1, state)
	assert_true(fsc.current_tree_id == "KOM_voznesensky_elected", "Transitioned to KOM_voznesensky_elected on DSNP victory")

	# 3. Политический переворот: левый путч (Суслов / Бухарина)
	state.set_flag("komi_left_coup_active", true)
	fsc.process_turn(1, state)
	assert_true(fsc.current_tree_id == "KOM_lcoup", "Transitioned to KOM_lcoup on left coup")

	# 4. Начало Смуты для левой фракции
	state.set_flag("smuta_active", true)
	state.set_flag("komi_faction_left", true)
	fsc.process_turn(1, state)
	assert_true(fsc.current_tree_id == "KOM_communist_smuta", "Transitioned to KOM_communist_smuta on Smuta begin")

	# 5. Стресс-тест пошагового цикла: прогон 50 ходов кампании Коми
	for i in range(50):
		state.legitimacy = maxf(state.legitimacy, 60.0) # поддерживаем жизнеспособность
		state.radicalization = minf(state.radicalization, 30.0)
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()
		tm.advance_turn()
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

	assert_true(tm.current_turn >= 50, "Successfully executed 50+ turns for KOM campaign without crash")
	assert_true(state.gdp_billions > 0.0, "State economy remained active after 50 turns")

	tm.free()


func test_germany_campaign_lifecycle() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "GER"
	state.country_name = "Великогерманский Рейх"
	state.political_capital = 120.0
	state.legitimacy = 80.0
	state.radicalization = 20.0
	tm.set_player_state(state)

	var fsc := tm.focus_stage_controller
	assert_true(fsc != null, "FocusStageController initialized for GER")
	assert_true(fsc.current_tree_id == "GER_game_start_tree", "Starting tree for GER is GER_game_start_tree")

	# 1. Агония и смерть Гитлера -> начало GCW
	var gcw := tm.german_civil_war_manager
	assert_true(gcw != null, "GermanCivilWarManager initialized")

	state.set_flag("gcw_active", true)
	state.set_flag("successor_speer", true)
	fsc.process_turn(1, state)
	assert_true(fsc.current_tree_id == "tno_speer_civil_war", "Speer GCW tree activated")

	# 2. Окончание GCW победой Шпеера -> переход на пост-GCW дерево
	state.story_flags.erase("gcw_active")
	state.set_flag("gcw_victor", "SPE")
	state.set_flag("germany_unified", true)
	fsc.process_turn(1, state)
	assert_true(fsc.current_tree_id == "GER_speer_post_cw_tree", "Speer post-GCW tree activated on unification")

	# 3. Прогон 25 ходов пост-военного развития Рейха
	for i in range(25):
		state.legitimacy = maxf(state.legitimacy, 60.0)
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()
		tm.advance_turn()
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

	assert_true(tm.current_turn >= 25, "Successfully executed 25+ turns for GER campaign")
	assert_true(state.military_factories > 0, "German industrial base intact")

	tm.free()


func test_usa_campaign_lifecycle() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "USA"
	state.country_name = "Соединенные Штаты Америки"
	state.political_capital = 150.0
	state.legitimacy = 80.0
	state.radicalization = 15.0
	state.gdp_billions = 280.0
	tm.set_player_state(state)

	var fsc := tm.focus_stage_controller
	assert_true(fsc != null, "FocusStageController initialized for USA")
	assert_true(fsc.current_tree_id == "USA_initial_tree", "Starting tree for USA is USA_initial_tree")

	# 1. Проверка электорального движка США
	var elect := tm.us_electoral_engine
	assert_true(elect != null, "USElectoralEngine initialized")

	# 2. Выборы 1964 года: победа Линдона Джонсона (LBJ)
	state.set_flag("president_lbj", true)
	fsc.process_turn(1, state)
	assert_true(fsc.current_tree_id == "USA_LBJ_64", "LBJ 1964 focus tree activated on victory")

	# 3. Выборы 1968 года: победа Барри Голдуотера (Goldwater)
	state.story_flags.erase("president_lbj")
	state.set_flag("president_gld", true)
	fsc.process_turn(1, state)
	assert_true(fsc.current_tree_id == "USA_GLD_68", "Goldwater 1968 focus tree activated on victory")

	# 4. Прогон 20 ходов кампании США
	for i in range(20):
		state.legitimacy = maxf(state.legitimacy, 70.0)
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()
		tm.advance_turn()
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

	assert_true(tm.current_turn >= 20, "Successfully executed 20+ turns for USA campaign")
	assert_true(state.gdp_billions >= 200.0, "USA GDP scale preserved")

	tm.free()
