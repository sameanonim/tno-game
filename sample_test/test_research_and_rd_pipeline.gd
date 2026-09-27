extends SceneTree

const ResearchManager = preload("res://core/systems/research_manager.gd")
const TechResource = preload("res://core/data/tech_resource.gd")
const CountryState = preload("res://core/data/country_state.gd")
const EconomyEngine = preload("res://core/systems/economy_engine.gd")
const EspionageEngine = preload("res://core/systems/espionage_engine.gd")
const CovertOperationResource = preload("res://core/data/covert_operation_resource.gd")
const ResearchTerminalScene = preload("res://ui/screens/research_terminal_view.tscn")
const ResearchTerminalView = preload("res://ui/screens/research_terminal_view.gd")
const TerminalMainScene = preload("res://ui/screens/terminal_main.tscn")
const TerminalMain = preload("res://ui/screens/terminal_main.gd")

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("================================================================================")
	print("[TEST_SUITE] Launching R&D & Research Pipeline Comprehensive Test Suite")
	print("================================================================================")

	# 1. Тестирование ResearchManager и базы данных технологий
	print("\n[STEP 1] Testing ResearchManager technology catalog and category indexing...")
	var rm = ResearchManager.new()
	assert(rm.all_technologies.size() >= 20, "Should load at least 20 technologies from database, got %d" % rm.all_technologies.size())
	print("-> Loaded %d total technologies." % rm.all_technologies.size())

	for cat_idx in range(6):
		var cat_techs = rm.get_techs_by_category(cat_idx)
		assert(cat_techs.size() > 0, "Category %d must contain technologies" % cat_idx)
		print("   Category %d (%s): %d techs" % [cat_idx, TechResource.TechCategory.keys()[cat_idx], cat_techs.size()])

	var basic_machinery = rm.get_tech("tech_basic_machinery")
	assert(basic_machinery != null, "tech_basic_machinery must exist in database")
	assert(basic_machinery.prerequisite_techs.is_empty(), "tech_basic_machinery has no prerequisites")
	assert(basic_machinery.category == TechResource.TechCategory.INDUSTRY, "tech_basic_machinery is INDUSTRY")

	var advanced_machinery = rm.get_tech("tech_advanced_machinery")
	assert(advanced_machinery != null, "tech_advanced_machinery must exist")
	assert(advanced_machinery.prerequisite_techs.has("tech_basic_machinery"), "advanced machinery requires basic machinery")
	print("[PASS] Step 1: Technology catalog loaded and validated.")

	# 2. Тестирование стейта державы (CountryState) и сериализации
	print("\n[STEP 2] Testing CountryState R&D properties and Save/Load serialization...")
	var state = CountryState.new()
	state.country_tag = "RUS"
	state.research_slots_count = 3
	state.research_points_pool = 150.0
	state.research_points_per_turn = 25.0
	state.researched_techs = ["tech_basic_machinery"]
	state.active_researches = {
		"tech_advanced_machinery": {
			"slot": 0,
			"progress": 50.0,
			"cost": 150.0,
			"turns_remaining": 4
		}
	}

	assert(state.is_tech_researched("tech_basic_machinery") == true, "is_tech_researched must return true")
	assert(state.is_tech_researched("tech_advanced_machinery") == false, "not yet researched")
	assert(state.get_total_research_slots() == 3, "Total slots must be 3")
	assert(state.has_available_research_slot() == true, "Should have 2 available slots")

	var serialized = state.to_dict()
	assert(serialized.has("research"), "Serialized dict must have 'research' key")
	assert(serialized["research"]["slots_count"] == 3, "Slots count serialized")
	assert(serialized["research"]["points_pool"] == 150.0, "Points pool serialized")
	assert(serialized["research"]["researched_techs"].has("tech_basic_machinery"), "Researched techs serialized")

	var restored = CountryState.from_dict(serialized)
	assert(restored.research_slots_count == 3, "Restored slots match")
	assert(restored.research_points_pool == 150.0, "Restored pool matches")
	assert(restored.is_tech_researched("tech_basic_machinery") == true, "Restored tech verified")
	assert(restored.active_researches.has("tech_advanced_machinery"), "Restored active research verified")
	print("[PASS] Step 2: CountryState serialization verified.")

	# 3. Тестирование генерации очков науки в EconomyEngine
	print("\n[STEP 3] Testing EconomyEngine R&D budget spending to points generation...")
	var econ_state = CountryState.new()
	econ_state.country_tag = "USA"
	econ_state.gdp_billions = 500.0
	econ_state.rd_spending_share = 0.05 # 5% of GDP
	econ_state.literacy_rate = 85.0
	econ_state.industrial_equipment_level = 75.0
	econ_state.fiscal_crisis_active = false

	var econ_report = EconomyEngine.process_turn(econ_state)
	assert(econ_report != null, "Economic report must not be null")
	assert(econ_report.research_points_generated > 0.0, "Should generate positive research points")
	assert(econ_state.research_points_per_turn > 0.0, "CountryState research_points_per_turn updated")
	assert(econ_state.research_points_pool > 0.0, "Research points pool accumulated")
	print("-> Economic report generated %.2f RP from $%.2fB R&D budget (pool now: %.2f RP)" % [
		econ_report.research_points_generated,
		econ_report.rd_expense,
		econ_state.research_points_pool
	])
	print("[PASS] Step 3: EconomyEngine R&D output verified.")

	# 4. Тестирование работы ResearchManager (старт, прогресс, завершение, применение эффектов)
	print("\n[STEP 4] Testing ResearchManager lifecycle (start, progress, completion)...")
	var player = CountryState.new()
	player.country_tag = "GER"
	player.research_slots_count = 2
	player.research_points_per_turn = 50.0
	player.research_points_pool = 0.0
	player.gdp_growth_rate = 3.0
	player.factory_output_multiplier = 1.0

	# Попытка исследовать продвинутую технологию без предварительной
	var prereq_check = rm.can_research(player, "tech_advanced_machinery")
	assert(prereq_check["allowed"] == false, "Should not be able to research advanced machinery without basic")
	print("   Prerequisite check blocked as expected: '%s'" % prereq_check["reason"])

	# Запуск базовой технологии
	var start_res = rm.start_research(player, "tech_basic_machinery")
	assert(start_res["success"] == true, "Must successfully start basic machinery")
	assert(player.active_researches.has("tech_basic_machinery"), "tech_basic_machinery is active")

	# Симулируем 1 ход исследований
	var completed_reports = rm.process_turn(1, player)
	# Стоимость basic_machinery 90 RP, при 50 RP/ход за 1 ход не должна завершиться
	assert(player.active_researches.has("tech_basic_machinery"), "Should still be researching")
	var prog = player.active_researches["tech_basic_machinery"]["progress"]
	print("   After turn 1: Progress = %.1f / 90.0 RP" % prog)
	assert(prog >= 50.0, "Progress should be at least 50.0")

	# Симулируем 2-й ход исследований
	completed_reports = rm.process_turn(2, player)
	assert(completed_reports.size() == 1, "tech_basic_machinery must complete on turn 2")
	assert(player.is_tech_researched("tech_basic_machinery") == true, "tech_basic_machinery now researched")
	assert(player.active_researches.is_empty(), "Active research queue must be empty")
	assert(player.factory_output_multiplier > 1.0, "Factory output modifier applied (+5%%)")
	print("   After completion: factory_output_multiplier = %.2f" % player.factory_output_multiplier)

	# Теперь продвинутая технология доступна
	var adv_check = rm.can_research(player, "tech_advanced_machinery")
	assert(adv_check["allowed"] == true, "Advanced machinery should now be allowed")
	print("[PASS] Step 4: Research progression and modifiers application verified.")

	# 5. Тестирование шпионажа: кража технологий (STEAL_TECH) и чертежи
	print("\n[STEP 5] Testing Espionage tech theft (STEAL_TECH) and blueprint bonuses...")
	var victim_state = CountryState.new()
	victim_state.country_tag = "USA"
	victim_state.researched_techs = ["tech_advanced_machinery", "tech_atomic_reactor", "tech_jet_engines"]

	var spy_state = CountryState.new()
	spy_state.country_tag = "SOV"
	spy_state.research_slots_count = 2
	spy_state.researched_techs = ["tech_basic_machinery"] # knows basic, but not advanced

	var world_map = {"USA": victim_state, "SOV": spy_state}

	# Создаем операцию кражи технологий
	var op = CovertOperationResource.new(
		"op_test_steal",
		"Steal US Aeronautics & Nuclear Tech",
		CovertOperationResource.OpType.STEAL_TECH,
		"USA",
		30.0,
		1.0,
		1,
		0.0 # 0% danger of detection for deterministic test
	)

	var esp_engine = EspionageEngine.new()
	var op_res = esp_engine._resolve_operation(op, spy_state, world_map)
	assert(op_res["success"] == true, "STEAL_TECH operation must succeed")
	print("   Theft report: %s" % op_res["report"])

	var stolen_id = op_res.get("stolen_tech_id", "")
	assert(not stolen_id.is_empty(), "stolen_tech_id must not be empty")
	print("   Successfully stole blueprints for: %s" % stolen_id)

	var bp_flag = "blueprint_" + stolen_id
	assert(spy_state.has_flag(bp_flag), "spy_state must receive blueprint flag: %s" % bp_flag)

	# Проверяем скидку на чертеж в can_research
	var cost_orig = rm.get_tech(stolen_id).research_cost
	var cost_check = rm.can_research(spy_state, stolen_id)
	var final_cost = cost_check.get("final_cost", cost_orig)
	assert(final_cost < cost_orig, "Cost must be discounted with blueprint")
	print("   Blueprint discount verified: original cost %.0f -> discounted cost %.0f RP" % [cost_orig, final_cost])
	print("[PASS] Step 5: Espionage tech theft and blueprints verified.")

	# 6. Тестирование сцены ResearchTerminalView и интеграции в TerminalMain
	print("\n[STEP 6] Testing ResearchTerminalView UI instantiation and binding...")
	var research_ui: ResearchTerminalView = ResearchTerminalScene.instantiate()
	root.add_child(research_ui)
	research_ui.setup(player, null, rm)
	assert(research_ui.player_state == player, "UI player_state bound")
	assert(research_ui.research_manager == rm, "UI research_manager bound")
	assert(research_ui.lbl_status_slots != null, "lbl_status_slots initialized")
	assert(research_ui.active_slots_container != null, "active_slots_container initialized")
	assert(research_ui.tech_cards_container != null, "tech_cards_container initialized")
	research_ui.refresh_view()
	print("   ResearchTerminalView rendered successfully without errors.")

	# 7. Тестирование TerminalMain с включенным табом НИОКР
	print("\n[STEP 7] Testing TerminalMain scene containing Research tab and HUD button...")
	var term_main: TerminalMain = TerminalMainScene.instantiate()
	root.add_child(term_main)
	assert(term_main.research_terminal_view != null, "research_terminal_view node exists in TerminalMain")
	assert(term_main.btn_research_toggle != null, "btn_research_toggle button exists in TacticalMap HUD")
	assert(term_main.tab_container != null, "TabContainer exists")
	print("   TerminalMain has %d tabs." % term_main.tab_container.get_tab_count())
	assert(term_main.tab_container.get_tab_count() >= 7, "TabContainer must have at least 7 tabs including Research")

	# Симулируем переключение на вкладку НИОКР
	term_main._toggle_research_screen()
	assert(term_main.tab_container.current_tab == 6, "Must switch to tab 6 (Research)")
	term_main._toggle_research_screen()
	assert(term_main.tab_container.current_tab == 0, "Must toggle back to tab 0 (TacticalMap)")
	print("[PASS] Step 7: TerminalMain Research tab and navigation verified.")

	print("\n================================================================================")
	print("[SUCCESS] ALL 7 R&D / RESEARCH PIPELINE TESTS PASSED COMPLETELY!")
	print("================================================================================")
	quit(0)
