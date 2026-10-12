class_name TestPhase33UsaCampaign
extends TNOSimpleTest

##
## TestPhase33UsaCampaign: Полный комплекс интеграционных тестов Фазы 3.3 (Кампания США)
## ==============================================================================
## Тестирует сквозную кампанию Соединенных Штатов Америки в TNO:
## 1. 3.3.1 Целостность пакета данных (data/countries/USA/, manifest, ContentLoader)
## 2. 3.3.2 Старт администрации Никсона (1962), Уотергейтский кризис и Маккормак / Стром
## 3. 3.3.3 Модель Сената США (100 мест), перевыборы 1/3 (Midterms), законодательный процесс (Bills, Whip, Vote)
## 4. 3.3.4 Президентские выборы 1964 и 1968 гг. (Коллегия выборщиков 538 EV, LBJ, Bennett, RFK, Wallace, Goldwater, Hart, Harrington, Smith, LeMay, Hall/Yockey)
## 5. 3.3.5 Интеграция электорального интерфейса (USCongressScreen, Hemicycle, опросы, сериализация)
## 6. 3.3.6 Сквозной стресс-тест 50 ходов кампании США (Никсон -> Маккормак -> выборы 1964 -> Великое общество)
## ==============================================================================

const USElectoralEngineScript = preload("res://core/systems/usa/us_electoral_engine.gd")
const USCongressScreenScript = preload("res://ui/screens/usa/us_congress_screen.gd")


func test_3_3_1_usa_data_package_integrity() -> void:
	# 1. Проверка структуры data/countries/USA/country.json
	var country_json_path := "res://data/countries/USA/country.json"
	assert_true(FileAccess.file_exists(country_json_path), "Файл country.json для USA существует")

	var f := FileAccess.open(country_json_path, FileAccess.READ)
	assert_true(f != null, "country.json открывается для чтения")
	if f != null:
		var c_data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		assert_true(c_data is Dictionary, "country.json парсится в Dictionary")
		if c_data is Dictionary:
			assert_eq(str(c_data.get("tag", "")), "USA", "Тег страны — USA")
			var c_name := str(c_data.get("country_name", ""))
			assert_true(c_name.contains("Соединенные Штаты") or c_name.contains("United States"), "Название страны корректно")
			assert_true(float(c_data.get("gdp_billions", 0.0)) > 200.0, "Стартовый ВВП США > 200B ($280B канон)")
			assert_true(float(c_data.get("legitimacy", 0.0)) > 50.0, "Стартовая легитимность США > 50%")

	# 2. Проверка манифеста директив trees_manifest.json
	var manifest_path := "res://data/countries/USA/directives/trees_manifest.json"
	assert_true(FileAccess.file_exists(manifest_path), "Файл trees_manifest.json для USA существует")

	var mf := FileAccess.open(manifest_path, FileAccess.READ)
	assert_true(mf != null, "trees_manifest.json открывается")
	if mf != null:
		var m_data: Variant = JSON.parse_string(mf.get_as_text())
		mf.close()
		assert_true(m_data is Dictionary, "trees_manifest.json валидный JSON")
		if m_data is Dictionary:
			assert_eq(str(m_data.get("starting_tree_id", "")), "USA_initial_tree", "Стартовое древо — USA_initial_tree")
			var stages: Dictionary = m_data.get("stages", {})
			assert_true(stages.has("PROLOGUE"), "Манифест содержит стадию PROLOGUE")
			assert_true(stages.has("CRISIS"), "Манифест содержит стадию CRISIS")
			assert_true(stages.has("PRESIDENTIAL_64"), "Манифест содержит стадию PRESIDENTIAL_64")
			assert_true(stages.has("PRESIDENTIAL_68"), "Манифест содержит стадию PRESIDENTIAL_68")

			var trees_dict: Dictionary = m_data.get("trees", {})
			assert_true(trees_dict.has("USA_initial_tree"), "Дерево USA_initial_tree зарегистрировано")
			assert_true(trees_dict.has("USA_mccormack"), "Дерево USA_mccormack зарегистрировано")
			assert_true(trees_dict.has("USA_LBJ_64"), "Дерево USA_LBJ_64 зарегистрировано")
			assert_true(trees_dict.has("USA_RFK_64"), "Дерево USA_RFK_64 зарегистрировано")
			assert_true(trees_dict.has("USA_WAL_64"), "Дерево USA_WAL_64 зарегистрировано")
			assert_true(trees_dict.has("USA_WFB_64"), "Дерево USA_WFB_64 зарегистрировано")
			assert_true(trees_dict.has("USA_GLD_68"), "Дерево USA_GLD_68 зарегистрировано")
			assert_true(trees_dict.has("USA_Hart"), "Дерево USA_Hart зарегистрировано")
			assert_true(trees_dict.has("USA_HAR_68"), "Дерево USA_HAR_68 зарегистрировано")
			assert_true(trees_dict.has("USA_MCS_68"), "Дерево USA_MCS_68 зарегистрировано")
			assert_true(trees_dict.has("USA_STROM_60"), "Дерево USA_STROM_60 зарегистрировано")
			assert_true(trees_dict.has("USA_LEMAY"), "Дерево USA_LEMAY зарегистрировано")

	# 3. Проверка events.json и decisions.json
	assert_true(FileAccess.file_exists("res://data/countries/USA/events.json"), "events.json для USA существует")
	assert_true(FileAccess.file_exists("res://data/countries/USA/decisions.json"), "decisions.json для USA существует")

	# 4. Проверка загрузки через ContentLoader
	var loader := ContentLoader.get_instance()
	if loader != null:
		var usa_state := loader.load_country_by_tag("USA")
		assert_true(usa_state != null, "CountryState для USA успешно загружен")
		if usa_state != null:
			assert_eq(usa_state.country_tag, "USA", "Тег стейта USA")


func test_3_3_2_nixon_presidency_watergate_and_mccormack() -> void:
	# 1. Проверка структуры стартового древа Никсона
	var initial_tree_path := "res://data/countries/USA/directives/trees/USA_initial_tree.json"
	assert_true(FileAccess.file_exists(initial_tree_path), "Файл USA_initial_tree.json существует")

	var f := FileAccess.open(initial_tree_path, FileAccess.READ)
	assert_true(f != null, "USA_initial_tree.json открывается")
	if f != null:
		var j_data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		assert_true(j_data is Dictionary, "USA_initial_tree.json парсится в Dictionary")
		if j_data is Dictionary:
			assert_eq(str(j_data.get("tree_id", "")), "USA_initial_tree", "tree_id совпадает")
			assert_eq(int(j_data.get("total_directives", 0)), 136, "Дерево Никсона содержит 136 директив")
			var nodes: Dictionary = j_data.get("nodes", {})
			assert_true(nodes.has("USA_the_nixon_presidency"), "Присутствует корневой фокус USA_the_nixon_presidency")

	# 2. Проверка древа Маккормака (Уотергейтский переходный период)
	var mccormack_tree_path := "res://data/countries/USA/directives/trees/USA_mccormack.json"
	assert_true(FileAccess.file_exists(mccormack_tree_path), "Файл USA_mccormack.json существует")

	var mf := FileAccess.open(mccormack_tree_path, FileAccess.READ)
	if mf != null:
		var mc_data: Variant = JSON.parse_string(mf.get_as_text())
		mf.close()
		assert_true(mc_data is Dictionary, "USA_mccormack.json валидный JSON")
		if mc_data is Dictionary:
			assert_eq(int(mc_data.get("total_directives", 0)), 24, "Дерево Маккормака содержит 24 директивы")

	# 3. Проверка резолюции древ через CampaignTreeResolver
	var state := CountryState.new()
	state.country_tag = "USA"
	state.leader_name = "Ричард Никсон"

	# Январь 1962: Никсон президент
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_initial_tree", "Резольвер вернул USA_initial_tree")

	# Уотергейтский кризис и отставка Никсона
	state.set_flag("nixon_resigned", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_mccormack", "Резольвер вернул USA_mccormack после отставки Никсона")

	# Временное президентство Строма Термонда
	state.flags.clear()
	state.set_flag("president_strom", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_STROM_60", "Резольвер вернул USA_STROM_60 для Строма Термонда")


func test_3_3_3_senate_model_midterms_and_legislature() -> void:
	var engine := USElectoralEngine.new()
	var state := CountryState.new()
	state.country_tag = "USA"
	state.political_capital = 100.0
	state.current_cap = 5
	state.max_cap = 5
	state.radicalization = 20.0
	state.legitimacy = 70.0
	state.poverty_rate = 22.0
	state.literacy_rate = 82.0

	# 1. Проверка стартового состава Сената (100 мест)
	assert_eq(engine.get_total_senate_seats(), 100, "Всего в Сенате ровно 100 мест")
	assert_eq(engine.get_seats(USElectoralEngine.FACTION_RD_D), 34, "РДК (Демократы) — 34 места")
	assert_eq(engine.get_seats(USElectoralEngine.FACTION_RD_R), 28, "РДК (Республиканцы) — 28 мест")
	assert_eq(engine.get_seats(USElectoralEngine.FACTION_NPP_C), 20, "НПП (Центр) — 20 мест")
	assert_eq(engine.get_seats(USElectoralEngine.FACTION_NPP_FR), 18, "НПП (Националисты) — 18 мест")

	assert_eq(engine.get_coalition_seats("RD"), 62, "Коалиция РДК контролирует 62 места")
	assert_eq(engine.get_coalition_seats("NPP"), 38, "Пакт НПП контролирует 38 мест")
	assert_true(engine.has_majority("RD"), "РДК имеет абсолютное большинство (>=51)")
	assert_false(engine.has_majority("NPP"), "НПП в меньшинстве")

	var seat_list := engine.get_senate_seat_list()
	assert_eq(seat_list.size(), 100, "Сгенерировано ровно 100 элементов для полукруга Сената")

	# 2. Проверка региональных опросов (4 макрорегиона)
	var polls: Dictionary = engine.calculate_regional_popularities(state)
	assert_true(polls.has(USElectoralEngine.REGION_NORTHEAST), "Опросы содержат NORTHEAST")
	assert_true(polls.has(USElectoralEngine.REGION_MIDWEST), "Опросы содержат MIDWEST")
	assert_true(polls.has(USElectoralEngine.REGION_SOUTH), "Опросы содержат SOUTH")
	assert_true(polls.has(USElectoralEngine.REGION_WEST), "Опросы содержат WEST")

	# 3. Симуляция промежуточных выборов (Midterms: 34 места)
	var midterm_signals := {"updated": false, "total": 0}
	engine.senate_seats_updated.connect(func(seats, _d):
		midterm_signals["updated"] = true
		var t := 0
		for v in seats.values():
			t += int(v)
		midterm_signals["total"] = t
	)

	var mid_report: Dictionary = engine.conduct_senate_elections(state)
	assert_true(midterm_signals["updated"], "Сигнал senate_seats_updated испущен")
	assert_eq(midterm_signals["total"], 100, "После перевыборов общее число мест строго 100")
	assert_eq(engine.get_total_senate_seats(), 100, "Сенат сохраняет размер 100 мест")
	assert_true(mid_report.has("deltas"), "Отчет содержит сдвиги мест (deltas)")

	# 4. Законодательный процесс (Passing Bills)
	var bills: Array[Dictionary] = engine.get_available_bills()
	assert_true(bills.size() >= 4, "Доступно не менее 4 законопроектов TNO")

	# Прогноз голосования по Закону о гражданских правах
	var proj_cra: Dictionary = engine.project_bill_votes("BILL_CIVIL_RIGHTS_1964")
	assert_eq(proj_cra.get("bill_id", ""), "BILL_CIVIL_RIGHTS_1964", "Прогноз рассчитан для BILL_CIVIL_RIGHTS_1964")
	assert_true(proj_cra.get("yeas", 0) + proj_cra.get("nays", 0) + proj_cra.get("undecided", 0) == 100, "Сумма голосов равна 100")

	# Механика лоббирования (Whip Votes)
	var old_pc := state.political_capital
	var whip_res: Dictionary = engine.whip_votes("BILL_CIVIL_RIGHTS_1964", state)
	assert_true(whip_res.get("success", false), "Склонение сенаторов успешно")
	assert_eq(state.political_capital, old_pc - 15.0, "Списано 15 PC за лоббирование")
	assert_eq(state.current_cap, 4, "Списано 1 CAP за лоббирование")
	assert_true(whip_res.get("swayed", 0) > 0, "Колеблющиеся сенаторы склонены на сторону Белого Дома")

	# Финальное голосование по биллю
	var vote_signals := {"completed": false, "bill_id": ""}
	engine.bill_vote_completed.connect(func(b_id, _p, _res):
		vote_signals["completed"] = true
		vote_signals["bill_id"] = b_id
	)

	var vote_res: Dictionary = engine.vote_on_bill("BILL_CIVIL_RIGHTS_1964", state)
	assert_true(vote_signals["completed"], "Сигнал bill_vote_completed испущен")
	assert_eq(vote_signals["bill_id"], "BILL_CIVIL_RIGHTS_1964", "Голосование завершено по BILL_CIVIL_RIGHTS_1964")
	assert_true(vote_res.has("passed"), "Результат содержит флаг passed")
	if vote_res["passed"]:
		assert_eq(engine.civil_rights_status, "STRONG", "Статус гражданских прав повышен до STRONG")
		assert_true(engine.civil_rights_tension > 50.0, "Напряженность вокруг реформы выросла")

	# Проверка голосования по программе «Великое общество»
	var gs_vote: Dictionary = engine.vote_on_bill("BILL_GREAT_SOCIETY", state)
	if gs_vote["passed"]:
		assert_true(state.poverty_rate < 22.0, "Бедность снизилась после программы Великого общества")
		assert_true(state.literacy_rate > 82.0, "Грамотность выросла")


func test_3_3_4_presidential_elections_1964_and_1968() -> void:
	var engine := USElectoralEngine.new()
	var state := CountryState.new()
	state.country_tag = "USA"
	state.political_capital = 150.0
	state.radicalization = 15.0
	state.legitimacy = 80.0

	var election_signals := {"fired": false, "winner": ""}
	engine.president_elected.connect(func(res):
		election_signals["fired"] = true
		election_signals["winner"] = res.get("winner_coalition", "")
	)

	# 1. Проведение президентских выборов 1964 года (LBJ vs RFK)
	var res_1964: Dictionary = engine.conduct_presidential_election(1964, state, "LBJ", "RFK")
	assert_true(election_signals["fired"], "Сигнал president_elected испущен")
	assert_true(res_1964.get("winner_coalition", "") in ["RD", "NPP"], "Победитель — либо РДК, либо НПП")
	assert_eq(res_1964.get("ev_rd", 0) + res_1964.get("ev_npp", 0), 538, "Сумма голосов Коллегии выборщиков строго 538 EV")
	var winning_ev: int = res_1964.get("ev_rd", 0) if res_1964.get("winner_coalition", "") == "RD" else res_1964.get("ev_npp", 0)
	assert_true(winning_ev >= 270, "Победитель набрал не менее 270 голосов выборщиков")

	assert_false(state.leader_name.is_empty(), "Имя президента обновлено в CountryState")
	assert_false(engine.current_president["name"].is_empty(), "Имя президента зафиксировано в электоральном движке")

	# 2. Проверка альтернативных победителей 1964 года и переходов древ
	# Линдон Б. Джонсон (LBJ)
	state.flags.clear()
	state.set_flag("president_lbj", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_LBJ_64", "Резольвер вернул USA_LBJ_64")

	# Уоллес Беннетт (WFB)
	state.flags.clear()
	state.set_flag("president_wfb", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_WFB_64", "Резольвер вернул USA_WFB_64")

	# Роберт Кеннеди (RFK)
	state.flags.clear()
	state.set_flag("president_rfk", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_RFK_64", "Резольвер вернул USA_RFK_64")

	# Джордж Уоллес (WALLACE)
	state.flags.clear()
	state.set_flag("president_wal", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_WAL_64", "Резольвер вернул USA_WAL_64")

	# 3. Проверка кандидатов 1968 года
	# Барри Голдуотер (Goldwater)
	state.flags.clear()
	state.set_flag("president_gld", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_GLD_68", "Резольвер вернул USA_GLD_68")

	# Филип Харт (Hart)
	state.flags.clear()
	state.set_flag("president_hart", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_Hart", "Резольвер вернул USA_Hart")

	# Майкл Харрингтон (Harrington)
	state.flags.clear()
	state.set_flag("president_har", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_HAR_68", "Резольвер вернул USA_HAR_68")

	# Маргарет Чейз Смит (Smith)
	state.flags.clear()
	state.set_flag("president_mcs", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_MCS_68", "Резольвер вернул USA_MCS_68")

	# Кёртис ЛеМей (LeMay)
	state.flags.clear()
	state.set_flag("president_lemay", true)
	assert_eq(CampaignTreeResolver.resolve_usa_tree(state), "USA_LEMAY", "Резольвер вернул USA_LEMAY")

	# 4. Проверка выдвижения экстремистов при коллапсе доверия
	state.radicalization = 65.0
	state.legitimacy = 20.0
	var ext_yockey = engine._select_npp_candidate(1968, "YOCKEY", state)
	assert_true(ext_yockey.get("id", "").contains("Francis_Yockey"), "Номинирован ультранационалист Йоки")

	var ext_hall = engine._select_npp_candidate(1968, "HALL", state)
	assert_true(ext_hall.get("id", "").contains("Gus_Hall"), "Номинирован марксист Гэс Холл")


func test_3_3_5_congress_ui_integration() -> void:
	var state := CountryState.new()
	state.country_tag = "USA"
	state.country_name = "Соединенные Штаты Америки"
	state.leader_name = "Ричард Никсон"
	state.political_capital = 120.0
	state.current_cap = 5
	state.max_cap = 5

	var engine := USElectoralEngine.new()

	# 1. Инстанцирование экрана Конгресса
	var screen_scene = load("res://ui/screens/usa/us_congress_screen.tscn")
	assert_true(screen_scene != null, "Сцена us_congress_screen.tscn успешно загружена")

	var screen = screen_scene.instantiate()
	assert_true(screen is USCongressScreen, "Экран инстанцирован как USCongressScreen")

	# 2. Инициализация через setup()
	screen.setup(state, engine)
	assert_true(screen.engine == engine, "USElectoralEngine подключен к UI")
	assert_true(screen.country_state == state, "CountryState подключен к UI")
	assert_eq(screen.seat_cell_nodes.size(), 100, "100 ячеек мест создано в UI полукруге Сената")
	assert_false(screen.selected_bill_id.is_empty(), "Выбран активный законопроект")

	# 3. Интерактивные клики кнопок в UI
	screen._on_whip_clicked()
	assert_true(engine.whipped_undecided_bonus > 0, "Клик по кнопке лоббирования сработал в UI")

	screen._on_vote_clicked()
	assert_false(screen.lbl_vote_outcome.text.is_empty(), "В UI отображен вердикт голосования")

	# 4. Проверка сериализации движка выборов (Save / Load Integrity)
	var saved_dict: Dictionary = engine.to_dict()
	assert_true(saved_dict.has("senate_seats"), "Сериализован senate_seats")
	assert_true(saved_dict.has("current_president"), "Сериализован current_president")
	assert_true(saved_dict.has("civil_rights_tension"), "Сериализован civil_rights_tension")

	var new_engine := USElectoralEngine.new()
	new_engine.from_dict(saved_dict)
	assert_eq(new_engine.get_seats(USElectoralEngine.FACTION_RD_D), engine.get_seats(USElectoralEngine.FACTION_RD_D), "Сохранение мест RD_D детерминировано")
	assert_eq(new_engine.get_seats(USElectoralEngine.FACTION_RD_R), engine.get_seats(USElectoralEngine.FACTION_RD_R), "Сохранение мест RD_R детерминировано")

	screen.free()


func test_3_3_6_usa_campaign_50_turns_stress_test() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "USA"
	state.country_name = "Соединенные Штаты Америки"
	state.leader_name = "Ричард Никсон"
	state.political_capital = 150.0
	state.current_cap = 5
	state.max_cap = 5
	state.legitimacy = 80.0
	state.radicalization = 15.0
	state.gdp_billions = 280.0
	state.liquid_reserves_billions = 35.0
	state.national_debt_billions = 60.0
	state.infantry_weapons_stockpile = 150000
	state.heavy_equipment_stockpile = 3500
	state.manpower_pool = 2500000
	tm.set_player_state(state)

	var fsc := tm.focus_stage_controller
	assert_true(fsc != null, "FocusStageController активен")
	assert_eq(fsc.current_tree_id, "USA_initial_tree", "Стартовое древо США — USA_initial_tree")

	var elect := tm.us_electoral_engine
	assert_true(elect != null, "USElectoralEngine активен в TurnManager")

	# Прогон 50 ходов кампании США с ключевыми историческими вехами
	for turn_idx in range(50):
		var turn_num := turn_idx + 1

		# Ходы 1-11: Администрация Никсона
		if turn_num <= 11:
			state.current_cap = state.max_cap
			state.political_capital += 3.0
			if turn_num == 4:
				elect.whip_votes("BILL_OFN_DEFENSE_APPROPRIATIONS", state)
				elect.vote_on_bill("BILL_OFN_DEFENSE_APPROPRIATIONS", state)

		# Ход 12: Уотергейтский скандал и отставка Никсона
		elif turn_num == 12:
			state.set_flag("nixon_resigned", true)
			state.leader_name = "Джон Маккормак"
			fsc.process_turn(turn_num, state)
			assert_eq(fsc.current_tree_id, "USA_mccormack", "Ход 12: переход на переходное древо Маккормака")

		# Ходы 13-23: Стабилизация правительства Маккормака
		elif turn_num in range(13, 24):
			state.current_cap = state.max_cap
			state.political_capital += 3.0

		# Ход 24: Промежуточные выборы в Сенат (Midterms каждые 2 года)
		elif turn_num == 24:
			elect.conduct_senate_elections(state)
			assert_eq(elect.get_total_senate_seats(), 100, "Ход 24: Сенат сохраняет 100 мест после выборов")

		# Ходы 25-47: Предвыборная гонка 1964 года
		elif turn_num in range(25, 48):
			state.current_cap = state.max_cap
			state.political_capital += 3.0
			if turn_num == 35:
				elect.whip_votes("BILL_CIVIL_RIGHTS_1964", state)
				elect.vote_on_bill("BILL_CIVIL_RIGHTS_1964", state)

		# Ход 48: Президентские выборы 1964 года (Победа Линдона Джонсона)
		elif turn_num == 48:
			var pres_res = elect.conduct_presidential_election(1964, state, "LBJ", "RFK")
			assert_true(pres_res.has("winning_candidate"), "Выборы 1964 года завершены")
			# Имитируем сигнал победы LBJ
			state.set_flag("president_lbj", true)
			state.set_flag("presidential_election_winner_1964", "LBJ")
			state.leader_name = "Линдон Б. Джонсон"
			fsc.process_turn(turn_num, state)
			assert_eq(fsc.current_tree_id, "USA_LBJ_64", "Ход 48: переход на президентское древо Линдона Джонсона")

		# Ходы 49-50: Программа «Великое общество»
		elif turn_num >= 49:
			state.current_cap = state.max_cap
			if turn_num == 49:
				elect.vote_on_bill("BILL_GREAT_SOCIETY", state)

		# Разблокировка модальных окон
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

		tm.advance_turn()

		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

	# Финальная верификация стабильности после 50 ходов
	assert_true(tm.current_turn >= 50, "Успешно завершено 50 ходов кампании США")
	assert_true(state.gdp_billions > 250.0, "Экономика США устойчива (ВВП > 250B)")
	assert_true(state.legitimacy > 20.0, "Легитимность стабильна")
	assert_false(is_nan(state.gdp_billions), "ВВП не является NaN")
	assert_false(is_nan(state.radicalization), "Радикализация не является NaN")

	tm.free()
