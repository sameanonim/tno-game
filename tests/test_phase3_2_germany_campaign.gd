class_name TestPhase32GermanyCampaign
extends TNOSimpleTest

##
## TestPhase32GermanyCampaign: Тестовый набор Фазы 3.2 — Великогерманский Рейх (GER)
## ==============================================================================
## Полный аудит и интеграционное тестирование кампании Германии:
## 1. 3.2.1 Стартовый пакет данных GER (country.json, events, decisions, trees_manifest).
## 2. 3.2.2 Агония Гитлера (GER_game_start_tree, таймер 12 ходов, интриги претендентов).
## 3. 3.2.3 Система преемников и ветки власти (Шпеер, Борман, Гёринг, Гейдрих).
## 4. 3.2.4 Немецкая Гражданская Война (GCW, 4 претендента, Шпандау, босс-кризисы Анархии).
## 5. 3.2.5 Послевоенная гегемония, реформы сверхдержавы, прокси-войны и DEFCON.
## 6. 3.2.6 35 ходов сквозного стресс-теста немецкой кампании.
## ==============================================================================


func test_3_2_1_germany_data_package_integrity() -> void:
	# 1. Проверка country.json
	var country_path := "res://data/countries/GER/country.json"
	assert_true(FileAccess.file_exists(country_path), "Файл data/countries/GER/country.json существует")

	var f := FileAccess.open(country_path, FileAccess.READ)
	assert_true(f != null, "Файл country.json успешно открывается для чтения")
	if f != null:
		var c_data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		assert_true(c_data is Dictionary, "country.json парсится в Dictionary")
		if c_data is Dictionary:
			assert_eq(str(c_data.get("tag", "")), "GER", "Тег страны в country.json равен GER")
			assert_true(str(c_data.get("name_text", "")).contains("Рейх"), "Название страны содержит Рейх")
			assert_eq(int(c_data.get("capital", 0)), 64, "Столица Германии — Берлин / Германиа (провинция 64)")
			assert_eq(str(c_data.get("ruling_party", "")), "national_socialism", "Стартовая правящая партия — national_socialism")
			var ideas: Array = c_data.get("ideas", [])
			assert_true(ideas.has("Pakt_Leader"), "Присутствует стартовый нацдух Pakt_Leader")
			assert_true(ideas.has("to_banish_want"), "Присутствует стартовый нацдух to_banish_want")
			assert_true(ideas.has("the_two_principles"), "Присутствует стартовый нацдух the_two_principles")
			assert_true(ideas.has("endsieg"), "Присутствует стартовый нацдух endsieg")
			assert_true(ideas.has("GER_Martin_Bormann_hog"), "Присутствует министр Мартин Борман")
			assert_true(ideas.has("GER_Albert_Speer_eco"), "Присутствует министр Альберт Шпеер")
			assert_true(ideas.has("GER_Hermann_Goring_sec"), "Присутствует рейхсмаршал Герман Гёринг")

	# 2. Проверка trees_manifest.json
	var manifest_path := "res://data/countries/GER/directives/trees_manifest.json"
	assert_true(FileAccess.file_exists(manifest_path), "Файл trees_manifest.json существует")
	if FileAccess.file_exists(manifest_path):
		var mf := FileAccess.open(manifest_path, FileAccess.READ)
		var m_data: Variant = JSON.parse_string(mf.get_as_text())
		mf.close()
		assert_true(m_data is Dictionary, "trees_manifest.json парсится в Dictionary")
		if m_data is Dictionary:
			assert_eq(str(m_data.get("starting_tree_id", "")), "GER_game_start_tree", "Стартовое дерево манифеста — GER_game_start_tree")
			var stages: Dictionary = m_data.get("stages", {})
			assert_true(stages.has("PROLOGUE"), "Манифест содержит стадию PROLOGUE")
			assert_true(stages.has("LEADERSHIP"), "Манифест содержит стадию LEADERSHIP")
			assert_true(stages.has("CRISIS"), "Манифест содержит стадию CRISIS")
			assert_true(stages.has("FINAL"), "Манифест содержит стадию FINAL")

			var trees_dict: Dictionary = m_data.get("trees", {})
			assert_true(trees_dict.has("GER_game_start_tree"), "Дерево GER_game_start_tree зарегистрировано")
			assert_true(trees_dict.has("GER_speer_successor"), "Дерево GER_speer_successor зарегистрировано")
			assert_true(trees_dict.has("GER_bormann_successor"), "Дерево GER_bormann_successor зарегистрировано")
			assert_true(trees_dict.has("GER_goring_successor"), "Дерево GER_goring_successor зарегистрировано")
			assert_true(trees_dict.has("GER_heydrich_successor"), "Дерево GER_heydrich_successor зарегистрировано")
			assert_true(trees_dict.has("GER_speer_post_cw_tree"), "Дерево GER_speer_post_cw_tree зарегистрировано")
			assert_true(trees_dict.has("GER_bormann_post_cw_tree"), "Дерево GER_bormann_post_cw_tree зарегистрировано")
			assert_true(trees_dict.has("GER_Germany_War_Tree"), "Дерево GER_Germany_War_Tree зарегистрировано")
			assert_true(trees_dict.has("GER_WW3"), "Дерево GER_WW3 зарегистрировано")

	# 3. Проверка events.json и decisions.json
	var events_path := "res://data/countries/GER/events.json"
	assert_true(FileAccess.file_exists(events_path), "Файл events.json для GER существует")
	var decisions_path := "res://data/countries/GER/decisions.json"
	assert_true(FileAccess.file_exists(decisions_path), "Файл decisions.json для GER существует")

	# 4. Проверка загрузки страны через ContentLoader
	var loader := ContentLoader.get_instance()
	if loader != null:
		var loaded_state := loader.load_country_by_tag("GER")
		assert_true(loaded_state != null, "CountryState для GER успешно загружен через ContentLoader")
		if loaded_state != null:
			assert_eq(loaded_state.country_tag, "GER", "Тег загруженного стейта GER")
			assert_true(loaded_state.country_name.contains("Рейх"), "Название стейта содержит Рейх")


func test_3_2_2_hitler_agony_countdown_and_influence() -> void:
	# 1. Проверка структуры стартового древа GER_game_start_tree.json
	var tree_path := "res://data/countries/GER/directives/trees/GER_game_start_tree.json"
	assert_true(FileAccess.file_exists(tree_path), "Файл GER_game_start_tree.json существует")

	var f := FileAccess.open(tree_path, FileAccess.READ)
	assert_true(f != null, "GER_game_start_tree.json открывается")
	if f != null:
		var t_data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		assert_true(t_data is Dictionary, "GER_game_start_tree.json валидный JSON")
		if t_data is Dictionary:
			assert_eq(str(t_data.get("tree_id", "")), "GER_game_start_tree", "tree_id совпадает")
			assert_eq(str(t_data.get("stage_category", "")), "PROLOGUE", "Категория стадии — PROLOGUE")
			assert_eq(int(t_data.get("total_directives", 0)), 32, "Дерево пролога содержит 32 директивы")

			var nodes: Dictionary = t_data.get("nodes", {})
			assert_true(nodes.has("GER_a_man_on_the_moon"), "Присутствует корневая директива «Человек на Луне»")
			var moon_dir: Dictionary = nodes.get("GER_a_man_on_the_moon", {})
			assert_eq(str(moon_dir.get("title", "")), "Человек на Луне", "Заголовок — Человек на Луне")
			assert_eq(int(moon_dir.get("turns_to_complete", 0)), 2, "Срок завершения — 2 хода")

			var res := DirectiveResource.from_dict(moon_dir)
			assert_true(res != null, "DirectiveResource успешно создается из директивы Человек на Луне")

	# 2. Инициализация GermanCivilWarManager и проверка Фазы 1
	var gcw_mgr := GermanCivilWarManager.new()
	var state := CountryState.new()
	state.country_tag = "GER"
	state.country_name = "Великогерманский Рейх"
	state.political_capital = 100.0
	state.current_cap = 5
	state.max_cap = 5

	var tm := TurnManager.new()
	tm._ready()
	gcw_mgr.initialize(tm, null, state)

	assert_eq(int(gcw_mgr.active_phase), int(GermanCivilWarManager.GCWPhase.PHASE_1_AGONY), "Стартовая фаза — PHASE_1_AGONY")
	assert_eq(gcw_mgr.turns_until_hitler_death, 12, "До смерти Гитлера ровно 12 ходов")

	# Проверка стартового влияния претендентов (равный баланс 25%)
	var infl: Dictionary = gcw_mgr.faction_influence
	assert_true(is_equal_approx(float(infl.get("SPEER", 0.0)), 25.0), "Влияние Шпеера 25%")
	assert_true(is_equal_approx(float(infl.get("BORMANN", 0.0)), 25.0), "Влияние Бормана 25%")
	assert_true(is_equal_approx(float(infl.get("GOERING", 0.0)), 25.0), "Влияние Гёринга 25%")
	assert_true(is_equal_approx(float(infl.get("HEYDRICH", 0.0)), 25.0), "Влияние Гейдриха 25%")

	# 3. Тест интриг и действий игрока в Фазе 1
	# Действие: Подкуп гауляйтера Шпеером
	var bribe_ok := gcw_mgr.bribe_gauleiter("SPEER", 3512, 25.0)
	assert_true(bribe_ok, "Подкуп гауляйтера успешно выполнен")
	assert_eq(state.political_capital, 75.0, "PC списано за подкуп (-25)")
	assert_true(gcw_mgr.faction_influence["SPEER"] > 25.0, "Влияние Шпеера выросло")
	assert_true(gcw_mgr.regional_partition["SPE"].has(3512), "Провинция 3512 перешла Шпееру")

	# Действие: Вербовка генерала Борманом
	var sway_ok := gcw_mgr.sway_general("BORMANN", "Alfred Jodl", 1)
	assert_true(sway_ok, "Вербовка генерала успешно выполнена")
	assert_eq(state.current_cap, 4, "CAP списано за вербовку (-1)")
	assert_true(gcw_mgr.recruited_commanders["BORMANN"].has("Alfred Jodl"), "Йодль в штабе Бормана")

	# Действие: Захват военных складов Гёрингом
	var seize_ok := gcw_mgr.seize_depot("GOERING", 10000)
	assert_true(seize_ok, "Захват складов успешно выполнен")
	assert_eq(state.political_capital, 55.0, "PC списано за склады (-20)")
	assert_eq(state.current_cap, 3, "CAP списано за склады (-1)")
	assert_eq(int(gcw_mgr.secured_depots["GOERING"]), 50000, "Склады Гёринга увеличены до 50 000")

	# 4. Прогон пошагового отсчета таймера
	for i in range(3):
		gcw_mgr.process_turn(i + 1)

	assert_eq(gcw_mgr.turns_until_hitler_death, 9, "Таймер смерти уменьшился до 9")
	var sum_infl := 0.0
	for v in gcw_mgr.faction_influence.values():
		sum_infl += float(v)
	assert_true(is_equal_approx(sum_infl, 100.0), "Сумма нормализованного влияния равна 100.0%")

	gcw_mgr.free()
	tm.free()


func test_3_2_3_successor_system_and_trees() -> void:
	# 1. Проверка наличия и структуры древ преемников
	var trees_to_check := {
		"GER_speer_successor": "GER_speer",
		"GER_bormann_successor": "GER_bormann",
		"GER_goring_successor": "GER_goring",
		"GER_heydrich_successor": "GER_heydrich"
	}

	for t_id in trees_to_check.keys():
		var file_path := "res://data/countries/GER/directives/trees/%s.json" % t_id
		assert_true(FileAccess.file_exists(file_path), "Файл %s.json существует" % t_id)
		var f := FileAccess.open(file_path, FileAccess.READ)
		if f != null:
			var j_data: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if j_data is Dictionary:
				assert_true(str(j_data.get("stage_category", "")) in ["LEADERSHIP", "PROLOGUE"], "Стадия %s — LEADERSHIP или PROLOGUE" % t_id)
				var nodes: Dictionary = j_data.get("nodes", {})
				var root_key: String = trees_to_check[t_id]
				assert_true(nodes.has(root_key), "%s содержит корневой фокус %s" % [t_id, root_key])

	# 2. Проверка резолюции древа через CampaignTreeResolver
	var state := CountryState.new()
	state.country_tag = "GER"

	# Выбор Шпеера
	state.set_flag("successor_speer", true)
	assert_eq(CampaignTreeResolver.resolve_germany_tree(state), "GER_speer_successor", "Резольвер вернул GER_speer_successor")

	# Выбор Бормана
	state.flags.clear()
	state.set_flag("successor_bormann", true)
	assert_eq(CampaignTreeResolver.resolve_germany_tree(state), "GER_bormann_successor", "Резольвер вернул GER_bormann_successor")

	# Выбор Гёринга
	state.flags.clear()
	state.set_flag("successor_goring", true)
	assert_eq(CampaignTreeResolver.resolve_germany_tree(state), "GER_goring_successor", "Резольвер вернул GER_goring_successor")

	# Выбор Гейдриха
	state.flags.clear()
	state.set_flag("successor_heydrich", true)
	assert_eq(CampaignTreeResolver.resolve_germany_tree(state), "GER_heydrich_successor", "Резольвер вернул GER_heydrich_successor")

	# 3. Проверка переключения претендента игрока в GermanyCampaignManager
	var gcw_mgr := GermanCivilWarManager.new()
	var gcm := GermanyCampaignManager.new()
	gcm.initialize(gcw_mgr)

	gcm.select_player_contender("BOR")
	assert_eq(gcm.campaign_state.chosen_contender_tag, "BOR", "GermanyCampaignManager выбрал BOR")
	assert_eq(gcw_mgr.player_contender_tag, "BOR", "Синхронизировано с GermanCivilWarManager")

	gcm.free()
	gcw_mgr.free()


func test_3_2_4_civil_war_eruption_and_mechanics() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "SPE"
	state.country_name = "Реформистский Рейх (Альберт Шпеер)"
	state.political_capital = 100.0
	state.current_cap = 5
	state.max_cap = 5
	state.heavy_equipment_stockpile = 300
	tm.set_player_state(state)

	var gcw_mgr := tm.german_civil_war_manager
	assert_true(gcw_mgr != null, "GermanCivilWarManager активен")

	var war_signals := {
		"hitler_died": false,
		"cwar_erupted": false
	}
	gcw_mgr.hitler_died.connect(func(): war_signals["hitler_died"] = true)
	gcw_mgr.civil_war_erupted.connect(func(): war_signals["cwar_erupted"] = true)

	# 1. Взрыв гражданской войны
	gcw_mgr.trigger_hitler_death()

	assert_true(war_signals["hitler_died"], "Сигнал hitler_died испущен")
	assert_true(war_signals["cwar_erupted"], "Сигнал civil_war_erupted испущен")
	assert_eq(int(gcw_mgr.active_phase), int(GermanCivilWarManager.GCWPhase.PHASE_2_CIVIL_WAR), "Фаза переключилась на PHASE_2_CIVIL_WAR")
	assert_true(gcw_mgr.gcw_active, "Флаг gcw_active активен")

	# 2. Проверка создания стейтов претендентов в мировом стейте
	var world_countries: Dictionary = tm.countries_world_state
	assert_true(world_countries.has("SPE"), "Стейт SPE (Шпеер) создан")
	assert_true(world_countries.has("BOR"), "Стейт BOR (Борман) создан")
	assert_true(world_countries.has("GOR"), "Стейт GOR (Гёринг) создан")
	assert_true(world_countries.has("HEY"), "Стейт HEY (Гейдрих) создан")
	assert_true(world_countries.has("SPN"), "Стейт SPN (Шпандау/Берлин нейтральный) создан")

	# 3. Проверка контроля Берлина провинция 6521
	var regions: Dictionary = tm.regions_world_state
	assert_true(regions.has(6521), "Провинция 6521 (Берлин) существует")
	if regions.has(6521):
		assert_eq(regions[6521].owner_tag, "SPN", "Берлин под контролем гарнизона Шпандау (SPN)")

	# 4. Проверка фронтов в MilitaryEngine
	var active_fronts := MilitaryEngine.get_active_frontlines()
	assert_true(active_fronts.size() >= 3, "Зарегистрировано не менее 3 фронтов GCW в MilitaryEngine")

	# 5. Проверка механик претендентов за ход
	var old_bor_web: float = gcw_mgr.bormann_party_web
	var old_gor_debt: float = gcw_mgr.goering_war_debt_billions

	gcw_mgr.process_turn(1)

	assert_true(gcw_mgr.bormann_party_web > old_bor_web, "Партийная паутина Бормана усилилась")
	assert_true(gcw_mgr.goering_war_debt_billions > old_gor_debt, "Военный долг Гёринга вырос")

	# 6. Проверка исполнения тактического приказа главнокомандующего (танковый прорыв)
	var order_res: Dictionary = gcw_mgr.execute_tactical_order("panzer_breakthrough")
	assert_true(order_res.get("success", false), "Тактический приказ «Танковый прорыв» исполнен")
	assert_eq(state.current_cap, 4, "Списано 1 CAP за приказ")
	assert_eq(state.heavy_equipment_stockpile, 200, "Списано 100 танков за бронетанковый прорыв")

	# 7. Проверка спавна босс-кризисов Анархии
	# Кризис Йозефа Геббельса (Фольксштурм)
	gcw_mgr.spawn_goebbels_faction()
	assert_true(gcw_mgr.goebbels_crisis_active, "Кризис Геббельса активирован")
	assert_true(world_countries.has("GOB"), "Стейт GOB (Геббельс) создан")
	assert_true(gcw_mgr.goebbels_ai != null, "GoebbelsCrisisAI прикреплен")

	# Кризис Красной Анархии (стачки в Руре)
	gcw_mgr.spawn_red_anarchy()
	assert_true(gcw_mgr.red_anarchy_active, "Красная Анархия в Руре активна")
	assert_true(world_countries.has("DSR"), "Стейт DSR (Красная Анархия) создан")

	# 8. Проверка взятия Берлина
	if regions.has(6521):
		regions[6521].owner_tag = "SPE"
	var berlin_flags := {"fallen": false}
	gcw_mgr.berlin_captured.connect(func(_tag): berlin_flags["fallen"] = true)

	gcw_mgr._check_berlin_status()
	assert_true(gcw_mgr.berlin_has_fallen, "Берлин пал")
	assert_eq(gcw_mgr.berlin_controller, "SPE", "Шпеер контролирует Берлин")
	assert_true(berlin_flags["fallen"], "Сигнал berlin_captured испущен")

	tm.free()


func test_3_2_5_post_cw_hegemony_and_superpower() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "SPE"
	state.country_name = "Великогерманский Рейх (Альберт Шпеер)"
	state.political_capital = 150.0
	state.current_cap = 5
	state.max_cap = 5
	state.liquid_reserves_billions = 25.0
	state.manpower_pool = 200000
	state.infantry_weapons_stockpile = 50000
	state.heavy_equipment_stockpile = 1000
	tm.set_player_state(state)

	var gcw_mgr := tm.german_civil_war_manager
	gcw_mgr.trigger_hitler_death()

	# 1. Симуляция победы Шпеера в объединении (контроль Берлина + >65% регионов)
	var regions: Dictionary = tm.regions_world_state
	var all_cores: Array[int] = []
	for p_list in gcw_mgr.regional_partition.values():
		for p in p_list:
			if not all_cores.has(p):
				all_cores.append(p)

	for pid in all_cores:
		if regions.has(pid):
			regions[pid].owner_tag = "SPE"

	var concl_flags := {
		"concluded": false,
		"victor": ""
	}
	gcw_mgr.gcw_concluded.connect(func(v): 
		concl_flags["concluded"] = true
		concl_flags["victor"] = v
	)

	var victory_tag: String = gcw_mgr.check_unification_victory()
	assert_eq(victory_tag, "SPE", "Победа в объединении присуждена Шпееру")
	assert_true(concl_flags["concluded"], "Сигнал gcw_concluded испущен")
	assert_eq(concl_flags["victor"], "SPE", "Победитель — SPE")
	assert_eq(int(gcw_mgr.active_phase), int(GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY), "Фаза переключилась на PHASE_3_HEGEMONY")
	assert_true(state.has_flag("germany_unified"), "Флаг germany_unified установлен")
	assert_eq(str(state.get_flag("gcw_victor", "")), "SPE", "Флаг gcw_victor установлен в SPE")
	assert_eq(gcw_mgr.post_cw_tree_id, "GER_speer_post_cw_tree", "Послевоенное древо — GER_speer_post_cw_tree")
	assert_eq(MilitaryEngine.get_active_frontlines().size(), 0, "Фронты гражданской войны распущены")

	# 2. Проверка послевоенных реформ Шпеера
	# Декрет Эрхарда
	var erhard_res: Dictionary = gcw_mgr.execute_speer_reform("erhard_decree")
	assert_true(erhard_res.get("success", false), "Декрет Эрхарда успешно реализован")
	assert_true(gcw_mgr.speer_g4_erhard > 50.0, "Влияние Эрхарда выросло")

	# Ликвидация рабского труда
	var emancip_res: Dictionary = gcw_mgr.execute_speer_reform("slave_emancipation")
	assert_true(emancip_res.get("success", false), "Ликвидация рабства успешно реализована")
	assert_true(gcw_mgr.speer_slave_emancipation > 15.0, "Шкала освобождения рабов продвинулась")

	# Реформа Вермахта фон Трескова
	var tresckow_res: Dictionary = gcw_mgr.execute_speer_reform("tresckow_wehrmacht")
	assert_true(tresckow_res.get("success", false), "Военная реформа Трескова реализована")
	assert_true(gcw_mgr.speer_g4_tresckow > 50.0, "Влияние Трескова выросло")

	# Проверка статуса реформ
	var status_dict: Dictionary = gcw_mgr.get_post_cw_status()
	assert_eq(status_dict.get("victor_tag", ""), "SPE", "Статус реформ подтверждает победу SPE")
	assert_true(status_dict.has("speer"), "В статусе присутствует блок реформ Шпеера")

	# 3. Проверка прокси-войн и поставок ленд-лиза
	var initial_rifles: int = state.infantry_weapons_stockpile
	var ll_res: Dictionary = gcw_mgr.send_proxy_lend_lease("south_africa", 5000, 50, 0.5)
	assert_true(ll_res.get("success", false), "Ленд-лиз в Южную Африку успешно отправлен")
	assert_eq(state.infantry_weapons_stockpile, initial_rifles - 5000, "Винтовки списаны со складов")

	var saw_proxy: Dictionary = gcw_mgr.proxy_wars["south_africa"]
	assert_eq(int(saw_proxy["weapons_delivered"]), 5000, "Оружие доставлено на фронт ЮАР")
	assert_eq(int(saw_proxy["tanks_delivered"]), 50, "Танки доставлены на фронт ЮАР")

	# 4. Проверка управления шкалой DEFCON
	var defcon_flags := {
		"alert": false,
		"lvl": 0
	}
	gcw_mgr.defcon_alert.connect(func(lvl, _r):
		defcon_flags["alert"] = true
		defcon_flags["lvl"] = lvl
	)

	gcw_mgr.adjust_defcon(3, "Кризис в проливах")
	assert_true(defcon_flags["alert"], "Сигнал defcon_alert получен")
	assert_eq(defcon_flags["lvl"], 3, "Уровень DEFCON сдвинут на 3")
	assert_eq(gcw_mgr.current_defcon, 3, "Текущий DEFCON равен 3")

	tm.free()


func test_3_2_6_germany_campaign_35_turns_stress_test() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "GER"
	state.country_name = "Великогерманский Рейх"
	state.political_capital = 120.0
	state.current_cap = 5
	state.max_cap = 5
	state.legitimacy = 70.0
	state.radicalization = 25.0
	state.gdp_billions = 220.0
	state.liquid_reserves_billions = 18.0
	state.national_debt_billions = 45.0
	state.infantry_weapons_stockpile = 80000
	state.heavy_equipment_stockpile = 1200
	state.manpower_pool = 1200000
	tm.set_player_state(state)

	var fsc := tm.focus_stage_controller
	assert_true(fsc != null, "FocusStageController активен в TurnManager")
	assert_eq(fsc.current_tree_id, "GER_game_start_tree", "Стартовое дерево — GER_game_start_tree")

	var gcw_mgr := tm.german_civil_war_manager
	assert_true(gcw_mgr != null, "GermanCivilWarManager активен")

	var gcm := tm.germany_campaign_manager
	assert_true(gcm != null, "GermanyCampaignManager активен")

	# Симуляция 35 ходов сквозной кампании Германии
	for turn_idx in range(35):
		var current_turn_num := turn_idx + 1

		# ФАЗА 1: Ходы 1-11 (Агония Гитлера)
		if current_turn_num <= 11:
			state.political_capital += 5.0
			state.current_cap = state.max_cap
			# Выполнение политических маневров
			if current_turn_num == 3:
				gcw_mgr.bribe_gauleiter("SPEER", 3512, 10.0)
			elif current_turn_num == 6:
				gcw_mgr.sway_general("SPEER", "Hans Speidel", 1)
			elif current_turn_num == 9:
				state.set_flag("successor_speer", true)

		# ФАЗА 2: Ход 12 (Смерть Гитлера и взрыв Гражданской Войны)
		elif current_turn_num == 12:
			gcw_mgr.trigger_hitler_death()
			assert_eq(int(gcw_mgr.active_phase), int(GermanCivilWarManager.GCWPhase.PHASE_2_CIVIL_WAR), "Ход 12: взрыв GCW")

		# Ходы 13-22: Гражданская война в разгаре
		elif current_turn_num in range(13, 23):
			state.current_cap = state.max_cap
			if current_turn_num == 14:
				gcw_mgr.execute_tactical_order("panzer_breakthrough")
			elif current_turn_num == 17:
				# Захват Берлина Шпеером
				if tm.regions_world_state.has(6521):
					tm.regions_world_state[6521].owner_tag = "SPE"
				gcw_mgr._check_berlin_status()

		# Ход 23: Триумф Шпеера и окончание Гражданской Войны
		elif current_turn_num == 23:
			for pid in tm.regions_world_state.keys():
				var r: RegionData = tm.regions_world_state[pid]
				if r != null and (r.owner_tag in ["SPE", "BOR", "GOR", "HEY", "SPN", "GER"]):
					r.owner_tag = "SPE"
			gcw_mgr.check_unification_victory()
			assert_eq(int(gcw_mgr.active_phase), int(GermanCivilWarManager.GCWPhase.PHASE_3_HEGEMONY), "Ход 23: победа и гегемония Шпеера")

		# Ходы 24-35: Сверхдержава и Холодная война (Фаза 3)
		elif current_turn_num >= 24:
			state.current_cap = state.max_cap
			if current_turn_num == 25:
				gcw_mgr.execute_speer_reform("erhard_decree")
			elif current_turn_num == 28:
				gcw_mgr.execute_speer_reform("slave_emancipation")
			elif current_turn_num == 31:
				gcw_mgr.send_proxy_aid("south_africa", 1, 0.2)
			elif current_turn_num == 33:
				gcw_mgr.adjust_defcon(3, "Ближневосточные маневры")

		# Разрешение модальных кризисов для непрерывности теста
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

		tm.advance_turn()

		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

	# Финальные проверки стабильности после 35 ходов
	assert_true(tm.current_turn >= 35, "Успешно завершено 35+ ходов кампании Германии")
	assert_true(state.gdp_billions > 100.0, "Экономика Рейха стабильна (ВВП > 100B)")
	assert_true(state.liquid_reserves_billions >= 0.0, "Казна Рейха неотрицательна")
	assert_true(state.legitimacy > 20.0, "Легитимность Шпеера на приемлемом уровне")
	assert_false(is_nan(state.gdp_billions), "ВВП не является NaN")
	assert_false(is_nan(state.radicalization), "Радикализация не является NaN")

	tm.free()
