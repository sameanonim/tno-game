extends SceneTree

const AgentResource = preload("res://core/data/agent_resource.gd")
const CovertOperationResource = preload("res://core/data/covert_operation_resource.gd")
const EspionageEngine = preload("res://core/systems/espionage_engine.gd")
const EspionageTerminalScene = preload("res://ui/screens/espionage_terminal_view.tscn")

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("[TEST_SUITE] Launching EspionageEngine Test Suite...")
	
	# 1. Запуск headless вычислений движка
	var success = EspionageEngine._run_espionage_debug_simulation()
	if not success:
		push_error("[TEST_SUITE] EspionageEngine._run_espionage_debug_simulation FAILED!")
		quit(1)
		return

	# 2. Тестирование сериализации CountryState (Save/Load)
	print("\n[TEST_SUITE] Testing CountryState Espionage Serialization (to_dict / from_dict)...")
	var st = CountryState.new()
	st.country_tag = "KOM"
	st.black_budget = 42.5
	st.black_budget_allocation_per_turn = 7.5
	st.domestic_security = 72.0
	st.set_infiltration_level("GER", 55.0, "OPERATIONAL")
	
	var ag = AgentResource.new("ag_test_01", "Zodiac", 4, 88.0, 0.7)
	st.add_agent(ag)
	
	var op = CovertOperationResource.new("op_test_01", "Test Steal Tech", CovertOperationResource.OpType.STEAL_TECH, "GER", 40.0, 1.2, 3, 0.2)
	st.add_operation(op)
	
	var serialized = st.to_dict()
	assert(serialized.has("espionage"), "Serialized dict must have espionage section")
	assert(float(serialized["espionage"]["black_budget"]) == 42.5, "Black budget serialized")
	assert(float(serialized["espionage"]["domestic_security"]) == 72.0, "Domestic security serialized")
	
	var restored = CountryState.from_dict(serialized)
	assert(restored.black_budget == 42.5, "Restored black budget matches")
	assert(restored.domestic_security == 72.0, "Restored domestic security matches")
	assert(restored.active_agents.size() == 1, "Restored active agents count matches")
	assert(restored.active_agents[0].codename == "Zodiac", "Restored agent codename matches")
	assert(restored.active_covert_operations.size() == 1, "Restored operations count matches")
	assert(restored.active_covert_operations[0].title == "Test Steal Tech", "Restored op title matches")
	assert(restored.get_infiltration_level("GER") == 55.0, "Restored infiltration level matches")
	print("[OK] CountryState save/load serialization for Espionage verified.")

	# 3. Тестирование UI Терминала ЭЛТ
	print("\n[TEST_SUITE] Testing EspionageTerminalView scene instantiation and UI workflow...")
	var term_instance: EspionageTerminalView = EspionageTerminalScene.instantiate()
	root.add_child(term_instance)
	term_instance.setup(st, null)
	
	assert(term_instance.country_state == st, "Terminal country_state bound properly")
	assert(term_instance.label_black_budget != null, "Black budget label node exists")
	assert(term_instance.networks_container != null, "Networks container node exists")
	assert(term_instance.operations_container != null, "Operations container node exists")
	assert(term_instance.roster_container != null, "Roster container node exists")
	
	# Переключение вкладок
	term_instance._switch_tab("operations")
	assert(term_instance.current_tab == "operations", "Tab switched to operations")
	term_instance._switch_tab("roster")
	assert(term_instance.current_tab == "roster", "Tab switched to roster")
	term_instance._switch_tab("launch")
	assert(term_instance.current_tab == "launch", "Tab switched to launch")
	term_instance._switch_tab("networks")
	assert(term_instance.current_tab == "networks", "Tab switched to networks")

	# Проверка вербовки агента через UI
	var pre_count = st.active_agents.size()
	term_instance._on_recruit_button_pressed()
	assert(st.active_agents.size() == pre_count + 1, "Agent recruited via terminal button")
	
	print("[OK] EspionageTerminalView UI verified and passed all assertions.")

	print("\n================================================================================")
	print("[TEST_SUITE] ALL ESPIONAGE PIPELINES VERIFIED (100% PASS)")
	print("================================================================================")
	quit(0)
