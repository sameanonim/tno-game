class_name TestPhase31KomiCampaign
extends TNOSimpleTest

##
## TestPhase31KomiCampaign: Тестовый набор Фазы 3.1 — Республика Коми (KOM)
## ==============================================================================
## Полный аудит и интеграционное тестирование кампании Коми:
## 1. 3.1.1 Стартовый пакет данных KOM (country.json, events, decisions, manifest).
## 2. 3.1.2 Стартовое дерево фокусов KOM_pre_election (28 фокусов, рут-директива, награды).
## 3. 3.1.3 Выборные ветки (4 идеологических блока: Центр, Левые, Правые, Монархисты).
## 4. 3.1.4 Механика Часов Судного дня Таборицкого (Midnight Clock, Табун, Коллапс).
## 5. 3.1.5 Механика Российской Смуты (набеги на соседей, трофеи, стадии объединения).
## 6. 3.1.6 50 ходов стресс-теста сквозного пошагового цикла кампании Коми.
## ==============================================================================


func test_3_1_1_komi_data_package_integrity() -> void:
	# 1. Проверка country.json
	var country_path := "res://data/countries/KOM/country.json"
	assert_true(FileAccess.file_exists(country_path), "Файл data/countries/KOM/country.json существует")

	var f := FileAccess.open(country_path, FileAccess.READ)
	assert_true(f != null, "Файл country.json успешно открывается для чтения")
	if f != null:
		var c_data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		assert_true(c_data is Dictionary, "country.json парсится в Dictionary")
		if c_data is Dictionary:
			assert_eq(str(c_data.get("tag", "")), "KOM", "Тег страны в country.json равен KOM")
			assert_true(str(c_data.get("name_text", "")).contains("Коми"), "Название страны содержит Коми")
			assert_eq(int(c_data.get("capital", 0)), 397, "Столица Коми — Сыктывкар (провинция 397)")
			assert_eq(str(c_data.get("ruling_party", "")), "progressivism", "Стартовая правящая партия — прогрессивизм (Центр)")
			assert_true(bool(c_data.get("elections_allowed", false)), "Выборы разрешены")
			var ideas: Array = c_data.get("ideas", [])
			assert_true(ideas.has("KOM_syvtyvkartsi"), "Присутствует стартовый нацдух KOM_syvtyvkartsi")
			assert_true(ideas.has("KOM_clash_of_shadows_c_1"), "Присутствует стартовый нацдух KOM_clash_of_shadows_c_1")

	# 2. Проверка trees_manifest.json
	var manifest_path := "res://data/countries/KOM/directives/trees_manifest.json"
	assert_true(FileAccess.file_exists(manifest_path), "Файл trees_manifest.json существует")
	if FileAccess.file_exists(manifest_path):
		var mf := FileAccess.open(manifest_path, FileAccess.READ)
		var m_data: Variant = JSON.parse_string(mf.get_as_text())
		mf.close()
		assert_true(m_data is Dictionary, "trees_manifest.json парсится в Dictionary")
		if m_data is Dictionary:
			assert_eq(str(m_data.get("starting_tree_id", "")), "KOM_pre_election", "Стартовое дерево манифеста — KOM_pre_election")
			var trees_dict: Dictionary = m_data.get("trees", {})
			assert_true(trees_dict.size() >= 37, "Манифест содержит не менее 37 деревьев для Коми")

	# 3. Проверка загрузки нарративного события komi_friendship.1 через EventManager
	var em := EventManager.new()
	var ev: GameEvent = em.get_or_load_event("komi_friendship.1")
	assert_true(ev != null, "komi_friendship.1 успешно загружается через EventManager")
	if ev != null:
		assert_eq(ev.event_id, "komi_friendship.1", "Event ID равен komi_friendship.1")
		assert_true(ev.options.size() > 0, "Событие komi_friendship.1 содержит опции выбора")
	em.free()


func test_3_1_2_komi_pre_election_starting_tree() -> void:
	var tree_path := "res://data/countries/KOM/directives/trees/KOM_pre_election.json"
	assert_true(FileAccess.file_exists(tree_path), "Файл KOM_pre_election.json существует")

	var f := FileAccess.open(tree_path, FileAccess.READ)
	assert_true(f != null, "KOM_pre_election.json открывается")
	if f != null:
		var t_data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		assert_true(t_data is Dictionary, "KOM_pre_election.json валидный JSON")
		if t_data is Dictionary:
			assert_eq(str(t_data.get("tree_id", "")), "KOM_pre_election", "tree_id совпадает")
			assert_eq(int(t_data.get("directives_count", 0)), 28, "Стартовое дерево содержит ровно 28 директив")
			assert_eq(str(t_data.get("stage_category", "")), "PROLOGUE", "Категория стадии — PROLOGUE")

			var directives: Array = t_data.get("directives", [])
			assert_eq(directives.size(), 28, "Массив directives содержит ровно 28 элементов")

			# Проверка корневой директивы Протокол Съезда
			var root_dir: Dictionary = {}
			for d in directives:
				if d is Dictionary and str(d.get("id", "")) == "KOM_the_minutes_of_the_congress":
					root_dir = d
					break

			assert_false(root_dir.is_empty(), "Найдена корневая директива KOM_the_minutes_of_the_congress")
			assert_eq(str(root_dir.get("title", "")), "Протокол Съезда", "Заголовок — Протокол Съезда")
			assert_eq(int(root_dir.get("turns_to_complete", 0)), 1, "Срок реализации — 1 ход")

			var res := DirectiveResource.from_dict(root_dir)
			assert_true(res != null, "DirectiveResource успешно создается из словаря директивы")
			assert_true(res.completion_rewards.size() >= 2, "Награды за завершение содержат PP и FIRE_EVENT")


func test_3_1_3_four_ideological_paths() -> void:
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.country_name = "Республика Коми"
	state.ruling_ideology = "progressivism"

	# --------------------------------------------------------------------------
	# БЛОК 1: Демократы / Центр (DSNP, SMR, PSD)
	# --------------------------------------------------------------------------
	state.story_flags.clear()
	state.set_flag("komi_election_winner_dsnp", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_voznesensky_elected", "Победа DSNP -> KOM_voznesensky_elected")

	state.story_flags.clear()
	state.set_flag("komi_election_winner_smr", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_morozov_elected", "Победа SMR -> KOM_morozov_elected")

	state.story_flags.clear()
	state.set_flag("komi_election_winner_psd", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_stalina_elected", "Победа PSD -> KOM_stalina_elected")

	state.story_flags.clear()
	state.set_flag("komi_center_coup_active", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_ccoup", "Центристский путч -> KOM_ccoup")

	# Региональный этап Центра
	state.story_flags.clear()
	state.set_flag("is_regional_unifier", true)
	state.leader_name = "Николай Вознесенский"
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_socdem_regional", "Регионал Вознесенского -> KOM_socdem_regional")

	state.leader_name = "Светлана Сталина"
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_stalina_regional", "Регионал Сталиной -> KOM_stalina_regional")

	# --------------------------------------------------------------------------
	# БЛОК 2: Коммунисты / Левые (КПК: Суслов, Жданов, Бухарина)
	# --------------------------------------------------------------------------
	state.story_flags.clear()
	state.leader_name = "Михаил Суслов"
	state.set_flag("komi_election_winner_kpk", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_communist_elected", "Победа КПК -> KOM_communist_elected")

	state.story_flags.clear()
	state.set_flag("komi_left_coup_active", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_lcoup", "Левый путч -> KOM_lcoup")

	state.story_flags.clear()
	state.set_flag("smuta_active", true)
	state.set_flag("komi_faction_left", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_communist_smuta", "Смута левых -> KOM_communist_smuta")

	# Регионалы Левых
	state.story_flags.clear()
	state.set_flag("is_regional_unifier", true)
	state.leader_name = "Михаил Суслов"
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_suslov_regional", "Регионал Суслова -> KOM_suslov_regional")

	state.leader_name = "Андрей Жданов"
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_zhdanov_regional", "Регионал Жданова -> KOM_zhdanov_regional")

	state.leader_name = "Светлана Бухарина"
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_bukharina_regional", "Регионал Бухариной -> KOM_bukharina_regional")

	# --------------------------------------------------------------------------
	# БЛОК 3: Фашисты / Правые (Пассионарии: Шафаревич, Гумилев, Серов)
	# --------------------------------------------------------------------------
	state.story_flags.clear()
	state.set_flag("komi_election_winner_rnp", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_shafarevich_elected", "Победа RNP -> KOM_shafarevich_elected")

	state.story_flags.clear()
	state.set_flag("komi_right_coup_active", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_rcoup", "Правый путч -> KOM_rcoup")

	state.story_flags.clear()
	state.set_flag("smuta_active", true)
	state.set_flag("komi_faction_right", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_fascist_smuta", "Смута правых -> KOM_fascist_smuta")

	# Регионалы Правых
	state.story_flags.clear()
	state.set_flag("is_regional_unifier", true)
	state.leader_name = "Лев Гумилев"
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_gumilyov_regional", "Регионал Гумилева -> KOM_gumilyov_regional")

	state.leader_name = "Игорь Шафаревич"
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_shafarevich_regional", "Регионал Шафаревича -> KOM_shafarevich_regional")

	state.leader_name = "Иван Серов"
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_serov_regional", "Регионал Серова -> KOM_serov_regional")

	# --------------------------------------------------------------------------
	# БЛОК 4: Монархисты / БургСист (Таборицкий / Священная Российская Империя)
	# --------------------------------------------------------------------------
	state.story_flags.clear()
	state.leader_name = "Сергей Таборицкий"
	state.ruling_ideology = "Burgundian System"
	state.set_flag("is_regional_unifier", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_taboritsky_regional", "Регионал Таборицкого -> KOM_taboritsky_regional")

	state.story_flags.clear()
	state.set_flag("is_superregional_unifier", true)
	assert_eq(CampaignTreeResolver.resolve_komi_tree(state), "KOM_taboritsky_superregional", "Суперрегионал Таборицкого -> KOM_taboritsky_superregional")

	# Проверка детектора уникальной доктрины варлорда
	var mech_type := WarlordMechanicsManager.get_active_mechanic_type("KOM", state)
	assert_eq(mech_type, "TABORITSKY", "Таборицкий активирует механику TABORITSKY в WarlordMechanicsManager")


func test_3_1_4_taboritsky_midnight_clock_mechanics() -> void:
	var wm := WarlordMechanicsManager.new()
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.country_name = "Священная Российская Империя"
	state.leader_name = "Сергей Таборицкий"
	state.political_capital = 100.0
	state.current_cap = 5
	state.liquid_reserves_billions = 1.0
	state.infantry_weapons_stockpile = 1000
	state.legitimacy = 60.0
	state.radicalization = 30.0

	# 1. Стартовое состояние часов (16:00 / 240 минут)
	assert_eq(wm.taboritsky_clock_minutes, 240, "Стартовые минуты часов равны 240")
	assert_eq(wm.get_taboritsky_clock_str(), "16:00", "Стартовое время — 16:00")
	assert_false(wm.is_midnight_collapsed, "Полночь еще не наступила")

	# 2. Продвижение часов вперед
	var adv_res := wm.advance_taboritsky_clock(30, state)
	assert_eq(wm.taboritsky_clock_minutes, 270, "Минуты часов увеличились на 30")
	assert_eq(wm.get_taboritsky_clock_str(), "16:30", "Время стало 16:30")
	assert_false(bool(adv_res.get("collapsed", true)), "Коллапса нет")

	# 3. Действие: Поиски Царевича Алексея
	var prev_clk: int = wm.taboritsky_clock_minutes
	var alexei_res := wm.taboritsky_action_hunt_alexei(state)
	assert_true(bool(alexei_res.get("success", false)), "Поиски Царевича успешны")
	assert_eq(wm.taboritsky_alexei_searches_count, 1, "Счетчик поисков увеличился")
	assert_eq(wm.taboritsky_clock_minutes, prev_clk + 15, "Поиски добавили +15 минут к часам")

	# 4. Действие: Очищение «Табун»
	prev_clk = wm.taboritsky_clock_minutes
	var tabun_res := wm.taboritsky_action_purification(state)
	assert_true(bool(tabun_res.get("success", false)), "Химическое очищение успешно")
	assert_eq(wm.taboritsky_cleansed_regions_count, 1, "Счетчик очищенных зон равен 1")
	assert_eq(wm.taboritsky_clock_minutes, prev_clk + 25, "Очищение добавило +25 минут к часам")
	assert_true(state.radicalization < 30.0, "Радикализация снизилась после зачистки")

	# 5. Действие: Имперская верификация
	prev_clk = wm.taboritsky_clock_minutes
	var verify_res := wm.taboritsky_action_verify(state)
	assert_true(bool(verify_res.get("success", false)), "Верификация успешна")
	assert_eq(wm.taboritsky_clock_minutes, prev_clk + 10, "Верификация добавила +10 минут к часам")

	# 6. Наступление Полночи (Midnight Strikes / 24:00)
	var collapse_res := wm.trigger_midnight_collapse(state)
	assert_true(wm.is_midnight_collapsed, "is_midnight_collapsed равен true")
	assert_eq(wm.get_taboritsky_clock_str(), "24:00 [ПОЛНОЧЬ]", "Часы пробили 24:00 [ПОЛНОЧЬ]")
	assert_true(state.has_flag("midnight_struck"), "Выставлен флаг midnight_struck")
	assert_true(state.has_flag("post_midnight_collapse"), "Выставлен флаг post_midnight_collapse")
	assert_eq(state.ruling_ideology, "Post-Midnight Anarchy", "Идеология изменилась на Post-Midnight Anarchy")
	assert_eq(state.legitimacy, 0.0, "Легитимность упала до нуля")
	assert_eq(state.radicalization, 100.0, "Радикализация достигла максимума")


func test_3_1_5_russian_smuta_mechanics_and_raids() -> void:
	# 1. Принадлежность к макро-региону
	var macro_reg := RussianUnificationManager.get_macro_region("KOM")
	assert_eq(macro_reg, RussianUnificationManager.MACRO_WEST_RUSSIA, "Коми принадлежит к макро-региону Западная Россия")
	assert_eq(RussianUnificationManager.get_macro_region_name(macro_reg), "ЗАПАДНАЯ РОССИЯ", "Название театра — ЗАПАДНАЯ РОССИЯ")

	# 2. Моделирование пограничного рейда на соседнего варлорда (Вятка / Вологда)
	var attacker := CountryState.new()
	attacker.country_tag = "KOM"
	attacker.army_readiness = 90.0
	attacker.army_morale = 85.0
	attacker.infantry_weapons_stockpile = 1500
	attacker.manpower_pool = 25000
	attacker.liquid_reserves_billions = 0.50

	var target := RegionData.new()
	target.province_id = 398 # соседний сектор
	target.owner_tag = "VYT"
	target.province_name = "Вятка"
	target.terrain_type = "plains"
	target.garrison_strength = 20.0
	target.industrial_capacity = 4
	target.unrest = 10.0

	# Разведка боем (Recon raid)
	var recon_res := MilitaryEngine.execute_border_raid(attacker, target, "recon", 1)
	assert_true(recon_res != null, "Объект RaidResult создан")
	assert_true(recon_res.success, "Разведка боем увенчалась успехом")
	assert_true(recon_res.loot_cash_billions > 0.0, "Захвачены трофейные финансы")
	assert_true(recon_res.captured_weapons > 0, "Захвачено трофейное оружие")
	assert_true(recon_res.narrative_summary.contains("увенчался успехом"), "Сводка содержит текст об успехе")

	# Тяжелый набег (Heavy raid)
	var prev_weapons: int = attacker.infantry_weapons_stockpile
	var heavy_res := MilitaryEngine.execute_border_raid(attacker, target, "heavy", 2)
	assert_true(heavy_res != null, "Тяжелый набег выполнен")
	assert_true(heavy_res.success, "Тяжелый набег успешен при превосходстве сил")

	# Рейд при нехватке вооружений
	attacker.infantry_weapons_stockpile = 10 # недостаточно для тяжелого набега (нужно 500)
	var fail_res := MilitaryEngine.execute_border_raid(attacker, target, "heavy", 3)
	assert_false(fail_res.success, "Рейд сорван из-за дефицита оружия")
	assert_true(fail_res.narrative_summary.contains("острая нехватка"), "Корректная сводка об отказе")


func test_3_1_6_komi_50_turn_campaign_stress_test() -> void:
	var tm := TurnManager.new()
	tm._ready()
	tm.load_world_data()

	var state := CountryState.new()
	state.country_tag = "KOM"
	state.country_name = "Республика Коми"
	state.political_capital = 120.0
	state.current_cap = 5
	state.max_cap = 5
	state.legitimacy = 75.0
	state.radicalization = 20.0
	state.gdp_billions = 16.5
	state.liquid_reserves_billions = 1.31
	state.national_debt_billions = 3.5
	state.infantry_weapons_stockpile = 1000
	state.manpower_pool = 59600
	tm.set_player_state(state)

	var fsc := tm.focus_stage_controller
	assert_true(fsc != null, "FocusStageController активен в TurnManager")
	assert_eq(fsc.current_tree_id, "KOM_pre_election", "Стартовое дерево — KOM_pre_election")

	# Инициализация объединительного менеджера
	var unif := tm.russian_unification_manager
	assert_true(unif != null, "RussianUnificationManager активен")

	# Прогон 50 пошаговых циклов с динамической симуляцией
	for turn_idx in range(50):
		# Симуляция политической активности
		state.legitimacy = clampf(state.legitimacy + 0.2, 50.0, 100.0)
		state.radicalization = clampf(state.radicalization - 0.1, 10.0, 40.0)
		state.infantry_weapons_stockpile += 50 # производство фабрик

		# Переходы по стадиям сюжета в процессе кампании:
		if turn_idx == 10:
			# Выборы 1962: победа левоцентристов (DSNP)
			state.set_flag("komi_election_winner_dsnp", true)
			fsc.process_turn(turn_idx, state)
			assert_eq(fsc.current_tree_id, "KOM_voznesensky_elected", "Ход 10: переход на дерево Вознесенского")
		elif turn_idx == 25:
			# Начало Смуты в регионе
			state.set_flag("smuta_active", true)
			state.set_flag("komi_faction_left", true)
			fsc.process_turn(turn_idx, state)
			assert_eq(fsc.current_tree_id, "KOM_communist_smuta", "Ход 25: переход на дерево Коммунистической Смуты")
		elif turn_idx == 40:
			# Победа в регионале (Суслов)
			state.leader_name = "Михаил Суслов"
			state.set_flag("is_regional_unifier", true)
			fsc.process_turn(turn_idx, state)
			assert_eq(fsc.current_tree_id, "KOM_suslov_regional", "Ход 40: переход на региональное дерево Суслова")

		# Обработка модальных окон при возникновении
		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

		tm.advance_turn()

		if tm.current_state == TurnManager.TurnState.WAITING_FOR_MODAL_EVENT:
			tm.force_unlock_turn()

	assert_true(tm.current_turn >= 50, "Успешно отработано 50+ ходов кампании Коми")
	assert_true(state.gdp_billions > 10.0, "Экономика Коми сохранила стабильность")
	assert_true(state.infantry_weapons_stockpile > 0, "Запас вооружений положителен")
	assert_true(state.legitimacy > 40.0, "Легитимность не обрушилась")

	tm.free()
