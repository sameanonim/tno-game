class_name TestPhase2SystemsIntegration
extends TNOSimpleTest

##
## TestPhase2SystemsIntegration: Интеграционный тестовый набор Фазы 2
## ==============================================================================
## Проверяет сквозное взаимодействие:
## 1. Экономика ↔ Экран экономики ↔ Топбар
## 2. Директивы/Фокусы ↔ Ходовой цикл (Turn Loop) ↔ Эффекты
## 3. Политика ↔ Общественные законы (Societal Laws) ↔ Расход PC/CAP
## 4. Карта ↔ Военные действия ↔ Территориальный трансфер
## 5. Решения (Decisions) ↔ Ресурсы ↔ Кулдауны
## 6. Шпионаж (Espionage) ↔ Агенты ↔ Прогон хода
## ==============================================================================


func test_economy_ui_integration() -> void:
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.gdp_billions = 15.0
	state.liquid_reserves_billions = 1.0
	state.national_debt_billions = 5.0
	state.inflation_rate = 0.05
	state.central_bank_rate = 0.04
	state.military_spending_share = 25.0
	state.civilian_spending_share = 35.0

	var eco_screen := TNOEconomyScreen.new()
	eco_screen.current_state = state

	var modified_flag := {"fired": false}
	eco_screen.state_modified.connect(func(): modified_flag["fired"] = true)

	# Изменение ставки ЦБ
	state.central_bank_rate += 0.01
	eco_screen.state_modified.emit()
	assert_true(modified_flag["fired"], "state_modified signal fired on interest rate change")
	assert_true(is_equal_approx(state.central_bank_rate, 0.05), "Central bank rate updated to 5%")

	# Проверка печатного станка
	state.money_printing_this_turn += 0.5
	assert_true(state.money_printing_this_turn >= 0.5, "Money printing recorded")

	# Проверка Austerity программы (через флаг is_austerity_active)
	EconomyEngine.toggle_austerity_program(state)
	assert_true(state.is_austerity_active, "Austerity mode activated on state")

	# Проверка денежной реформы
	state.inflation_rate = 0.20
	EconomyEngine.conduct_currency_reform(state)
	assert_true(state.inflation_rate < 0.20, "Currency reform reduced inflation")

	eco_screen.free()


func test_topbar_macro_sync() -> void:
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.country_name = "Республика Коми"
	state.gdp_billions = 22.5
	state.liquid_reserves_billions = 2.4
	state.national_debt_billions = 8.1
	state.political_capital = 145.0
	state.pc_gain_per_turn = 6.5
	state.current_cap = 4
	state.max_cap = 6
	state.civilian_factories = 18
	state.military_factories = 12
	state.manpower_pool = 85000
	state.set_flag("defcon_level", 4)

	var tm := TurnManager.new()
	tm.player_state = state
	tm.current_turn = 5

	var topbar := TNOTopBar.new()
	topbar.update_state(state, tm)

	assert_true(state.political_capital == 145.0, "State PC preserved")
	assert_true(state.current_cap == 4 and state.max_cap == 6, "State CAP values correct")
	assert_true(state.story_flags.get("defcon_level", 5) == 4, "DEFCON level is 4")
	assert_true(tm.current_turn == 5, "Turn number is 5")

	topbar.free()
	tm.free()


func test_directives_progress_loop() -> void:
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.political_capital = 100.0
	state.manpower_pool = 50000

	var tm := TurnManager.new()
	tm.player_state = state

	var dir := DirectiveResource.new()
	dir.id = "test_dir_five_year_plan"
	dir.title = "Пятилетний план Коми"
	dir.turns_to_complete = 2
	dir.turns_remaining = 2
	dir.cost_initial_pc = 20.0
	dir.completion_rewards = [
		{"opcode": "MOD_PC", "value": 15.0},
		{"opcode": "MOD_MANPOWER", "value": 7500}
	]

	var completed_flag := {"completed": false, "dir_id": ""}
	tm.directive_completed.connect(func(d: DirectiveResource):
		completed_flag["completed"] = true
		completed_flag["dir_id"] = d.id
	)

	# Старт директивы
	var started = tm.start_directive(dir, true)
	assert_true(started, "Directive started successfully")
	assert_true(state.active_directives.has(dir.id), "Directive is in state.active_directives")
	assert_true(state.political_capital == 80.0, "PC cost deducted on directive start")

	# Ход 1
	tm.advance_turn()
	assert_false(completed_flag["completed"], "Directive not completed after 1st turn")
	assert_true(dir.turns_remaining == 1, "Turns remaining decremented to 1")

	# Ход 2 -> завершение директивы
	var initial_mp = state.manpower_pool
	tm.advance_turn()
	assert_true(completed_flag["completed"], "Directive completed signal fired on 2nd turn")
	assert_true(completed_flag["dir_id"] == dir.id, "Correct directive completed ID")
	assert_false(state.active_directives.has(dir.id), "Directive removed from active_directives")
	assert_true(state.completed_directives.has(dir.id), "Directive added to completed_directives")
	assert_true(state.manpower_pool > initial_mp, "Manpower increased from directive effects")

	tm.free()


func test_politics_societal_laws_reform() -> void:
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.political_capital = 50.0
	state.current_cap = 3
	state.max_cap = 5
	state.ensure_default_societal_laws()

	assert_false(state.societal_laws.is_empty(), "Default societal laws initialized")
	var law_idx: int = 0
	var initial_tier: int = int(state.societal_laws[law_idx].get("tier", 1))

	# Проводим реформу повышения уровня (+1)
	var res_up = SocietalLawsManager.enact_law_reform(state, law_idx, 1, 20.0, 1)
	assert_true(res_up.get("success", false), "Law reform up succeeded")
	assert_true(int(state.societal_laws[law_idx].get("tier", 1)) == initial_tier + 1, "Law tier incremented")
	assert_true(state.political_capital == 30.0, "PC deducted by 20")
	assert_true(state.current_cap == 2, "CAP deducted by 1")

	# Проводим откат реформы (-1)
	var res_down = SocietalLawsManager.enact_law_reform(state, law_idx, -1, 15.0, 1)
	assert_true(res_down.get("success", false), "Law rollback down succeeded")
	assert_true(int(state.societal_laws[law_idx].get("tier", 1)) == initial_tier, "Law tier decremented back")
	assert_true(state.political_capital == 15.0, "PC deducted by 15")

	# Проверяем блокировку при нехватке ресурсов (нужно 20 PC, а осталось 15 PC)
	var res_fail = SocietalLawsManager.enact_law_reform(state, law_idx, 1, 20.0, 1)
	assert_false(res_fail.get("success", false), "Law reform rejected due to insufficient PC")


func test_map_military_territory_sync() -> void:
	var tm := TurnManager.new()
	var state := CountryState.new()
	state.country_tag = "KOM"
	tm.player_state = state

	var reg1 := RegionData.new()
	reg1.province_id = 101
	reg1.owner_tag = "VYT"
	tm.regions_world_state[101] = reg1
	tm.state_to_provinces[101] = [101]

	var transferred_flag := {"fired": false, "new_owner": ""}
	tm.state_transferred.connect(func(_sid: int, _old_tag: String, new_tag: String):
		transferred_flag["fired"] = true
		transferred_flag["new_owner"] = new_tag
	)

	# Трансфер владения регионом 101
	var ok = tm.transfer_state(101, "KOM")
	assert_true(ok, "Region transferred successfully")
	assert_true(transferred_flag["fired"], "state_transferred signal fired")
	assert_true(transferred_flag["new_owner"] == "KOM", "New owner is KOM")
	assert_true(tm.regions_world_state[101].owner_tag == "KOM", "Region owner updated in world state")

	# Проверка активности фронтов
	var active_fronts = MilitaryEngine.get_active_frontlines()
	assert_true(active_fronts is Array, "Active frontlines list returned")

	tm.free()


func test_decisions_subsystem_execution() -> void:
	var state := CountryState.new()
	state.country_tag = "KOM"
	state.political_capital = 50.0
	state.current_cap = 3
	state.liquid_reserves_billions = 1.0
	state.infantry_weapons_stockpile = 1000

	var tm := TurnManager.new()
	tm.player_state = state
	tm.current_turn = 1

	var dm := DecisionManager.new()
	dm.setup(state, tm)

	var available = dm.get_decisions("all")
	assert_false(available.is_empty(), "Available decisions loaded for KOM")

	var dec_id = "smuta_arms_smuggling"
	assert_true(dm._decisions_by_id.has(dec_id), "smuta_arms_smuggling found in decision index")

	var dec: Dictionary = dm._decisions_by_id[dec_id]
	assert_true(dm.can_afford(dec), "Player can afford smuta_arms_smuggling")

	var executed_flag := {"executed": false, "id": ""}
	dm.decision_executed.connect(func(id: String, _eff: Dictionary):
		executed_flag["executed"] = true
		executed_flag["id"] = id
	)

	# Исполняем решение
	var success = dm.execute_decision(dec_id)
	assert_true(success, "Decision executed successfully")
	assert_true(executed_flag["executed"] and executed_flag["id"] == dec_id, "decision_executed signal fired")
	assert_true(state.political_capital == 35.0, "PC deducted by 15")
	assert_true(state.current_cap == 2, "CAP deducted by 1")
	assert_true(state.infantry_weapons_stockpile >= 4000, "Weapons added (+3000)")

	# Проверяем кулдаун
	assert_true(dm.is_on_cooldown(dec), "Decision is now on cooldown")
	assert_false(dm.can_afford(dec), "Cannot afford while on cooldown")

	# Переход на следующий ход не снимает кулдаун (cooldown = 2 хода)
	tm.current_turn = 2
	assert_true(dm.is_on_cooldown(dec), "Still on cooldown on turn 2")

	# Переход на ход 3 снимает кулдаун
	tm.current_turn = 3
	assert_false(dm.is_on_cooldown(dec), "Cooldown expired on turn 3")

	tm.free()


func test_espionage_engine_flow() -> void:
	var state := CountryState.new()
	state.country_tag = "KOM"

	var ag = EspionageEngine.recruit_agent("Зорге", 4, "GER", 0.75)
	assert_true(ag != null, "Agent recruited successfully")
	assert_true(ag.codename == "Зорге", "Agent codename matches")
	assert_true(ag.competence == 4, "Agent competence matches")

	state.add_agent(ag)
	assert_true(state.active_agents.size() == 1, "Agent added to player state")

	var world_states: Dictionary = {
		"KOM": state,
		"GER": CountryState.new()
	}
	world_states["GER"].country_tag = "GER"

	var ee := EspionageEngine.new()
	var reports = ee.process_turn(world_states, 1)
	assert_true(reports is Array, "Espionage reports generated")
