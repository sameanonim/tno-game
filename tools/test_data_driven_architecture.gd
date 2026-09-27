extends SceneTree

##
## TestDataDrivenArchitecture: Автоматизированная верификация Data-Driven архитектуры
## Проверяет:
## 1. Загрузку ConfigManager и чтение game_constants.json (экономика, война, политика, GCW).
## 2. Динамическую загрузку стран через ContentLoader.load_country_by_tag().
## 3. Динамическую загрузку лидеров через ContentLoader.load_leader_resource().
## 4. Доступность списка стран через ContentLoader.get_available_countries_list().
## 5. Расчет EconomyEngine с опорой на константы ConfigManager.
## 6. Расчет боевых действий MilitaryEngine с опорой на константы ConfigManager.
##

const ConfigManagerClass = preload("res://core/systems/config_manager.gd")
const ContentLoaderClass = preload("res://core/systems/content_loader.gd")
const TurnManagerClass = preload("res://core/systems/turn_manager.gd")

var tests_passed: int = 0
var tests_failed: int = 0
var _log_file: FileAccess = null

func _log(msg: String) -> void:
	print(msg)
	if _log_file != null:
		_log_file.store_line(msg)
		_log_file.flush()

func _init() -> void:
	_log_file = FileAccess.open("res://test_data_driven.log", FileAccess.WRITE)
	_log("================================================================================")
	_log("TNO DATA-DRIVEN ARCHITECTURE VERIFICATION TEST")
	_log("================================================================================")

	_test_config_manager()
	_test_content_loader_dynamic_countries()
	_test_content_loader_dynamic_leaders()
	_test_content_loader_countries_list()
	_test_economy_engine_with_config()
	_test_military_engine_with_config()
	_test_turn_manager_point_accrual()

	_log("================================================================================")
	_log("TEST RESULTS: Passed: %d | Failed: %d" % [tests_passed, tests_failed])
	_log("================================================================================")

	if tests_failed == 0:
		_log(">>> ALL DATA-DRIVEN ARCHITECTURE TESTS PASSED SUCCESSFULLY! <<<")
		if _log_file != null:
			_log_file.close()
		quit(0)
	else:
		_log(">>> VERIFICATION FAILED WITH %d ERRORS! <<<" % tests_failed)
		if _log_file != null:
			_log_file.close()
		quit(1)


func _assert(condition: bool, test_name: String, error_msg: String = "") -> void:
	if condition:
		tests_passed += 1
		_log("  [PASS] %s" % test_name)
	else:
		tests_failed += 1
		_log("  [FAIL] %s - %s" % [test_name, error_msg])


func _test_config_manager() -> void:
	print("\n--- TEST 1: CONFIG MANAGER & GAME CONSTANTS ---")
	var cfg = ConfigManagerClass.get_instance()
	if cfg.get_parent() == null:
		cfg.name = "ConfigManager"
		root.add_child(cfg)

	_assert(cfg.is_loaded, "ConfigManager is_loaded is true", "Config was not loaded")
	
	# Economy constants
	var tpy = cfg.get_float("economy", "turns_per_year", 0.0)
	_assert(absf(tpy - 52.143) < 0.001, "turns_per_year is 52.143", "Got %f" % tpy)
	
	var tax_base = cfg.get_float("economy", "tax_efficiency_base", 0.0)
	_assert(absf(tax_base - 0.8) < 0.001, "tax_efficiency_base is 0.8", "Got %f" % tax_base)
	
	var prod_wep = cfg.get_int("economy", "production_weapons_per_factory", 0)
	_assert(prod_wep >= 45, "production_weapons_per_factory loaded", "Got %d" % prod_wep)

	# Military constants
	var hunger_ratio = cfg.get_float("military", "combat_hunger_threshold_ratio", 0.0)
	_assert(absf(hunger_ratio - 0.4) < 0.001, "combat_hunger_threshold_ratio is 0.4", "Got %f" % hunger_ratio)

	var terrains = cfg.get_dict("military", "terrain_modifiers", {})
	_assert(terrains.has("forest") and terrains.has("mountains"), "terrain_modifiers contains forest and mountains", "Terrains: %s" % str(terrains))

	# Politics constants
	var base_pc = cfg.get_float("politics", "base_pc_gain_per_turn", 0.0)
	_assert(base_pc >= 4.0, "base_pc_gain_per_turn >= 4.0", "Got %f" % base_pc)

	# GCW constants
	var agony_turns = cfg.get_int("gcw", "turns_until_hitler_death", 0)
	_assert(agony_turns == 12, "turns_until_hitler_death is 12", "Got %d" % agony_turns)


func _test_content_loader_dynamic_countries() -> void:
	print("\n--- TEST 2: DYNAMIC COUNTRY LOADING VIA CONTENT LOADER ---")
	var loader = ContentLoaderClass.get_instance()
	if loader == null:
		loader = ContentLoaderClass.new()
		loader.name = "ContentLoader"
		root.add_child(loader)

	# Test contender Speer
	var speer_state = loader.load_country_by_tag("SPE")
	_assert(speer_state != null, "Speer country package loaded (tag SPE)", "Returned null")
	if speer_state != null:
		_assert(speer_state.country_tag == "SPE", "Country tag is SPE", "Got: %s" % speer_state.country_tag)
		_assert("Шпеер" in speer_state.country_name or "Speer" in speer_state.country_name, "Speer country name is correct", "Got: %s" % speer_state.country_name)
		_assert(speer_state.gdp_billions > 30.0, "Speer starting GDP > 30.0 B", "Got: %f" % speer_state.gdp_billions)
		_assert(speer_state.civilian_factories > 0, "Speer has civilian factories", "Factories: %d" % speer_state.civilian_factories)

	# Test contender Bormann
	var bormann_state = loader.load_country_by_tag("BOR")
	_assert(bormann_state != null, "Bormann country package loaded (tag BOR)", "Returned null")
	if bormann_state != null:
		_assert(bormann_state.country_tag == "BOR", "Country tag is BOR", "Got: %s" % bormann_state.country_tag)
		_assert(bormann_state.manpower_pool >= 200000, "Bormann manpower >= 200k", "Got: %d" % bormann_state.manpower_pool)

	# Test West Russian Revolutionary Front (WRS)
	var wrs_state = loader.load_country_by_tag("WRS")
	_assert(wrs_state != null, "WRS country package loaded", "Returned null")
	if wrs_state != null:
		_assert(wrs_state.country_tag == "WRS", "WRS tag is correct", "Got: %s" % wrs_state.country_tag)


func _test_content_loader_dynamic_leaders() -> void:
	print("\n--- TEST 3: DYNAMIC LEADER RESOURCE LOADING ---")
	var loader = ContentLoaderClass.get_instance()
	if loader == null:
		loader = ContentLoaderClass.new()
		root.add_child(loader)

	var speer_leader = loader.load_leader_resource("SPE", "leader_albert_speer")
	_assert(speer_leader != null, "Albert Speer leader loaded dynamically", "Returned null")
	if speer_leader != null:
		_assert(speer_leader.leader_id == "leader_albert_speer", "Leader ID is leader_albert_speer", "Got: %s" % speer_leader.leader_id)
		_assert(speer_leader.traits.size() > 0, "Speer has extracted traits", "Traits: %s" % str(speer_leader.traits))
		_assert(speer_leader.competence >= 3, "Speer competence >= 3", "Got: %d" % speer_leader.competence)

	var bormann_leader = loader.load_leader_resource("BOR", "leader_martin_bormann")
	_assert(bormann_leader != null, "Martin Bormann leader loaded dynamically", "Returned null")


func _test_content_loader_countries_list() -> void:
	print("\n--- TEST 4: AVAILABLE COUNTRIES LIST API ---")
	var loader = ContentLoaderClass.get_instance()
	if loader == null:
		loader = ContentLoaderClass.new()
		root.add_child(loader)

	var list = loader.get_available_countries_list()
	_assert(list.size() >= 10, "Available countries list contains 10+ entries", "Got: %d" % list.size())

	var found_spe = false
	var found_wrs = false
	for entry in list:
		if entry.get("tag") == "SPE":
			found_spe = true
		if entry.get("tag") == "WRS":
			found_wrs = true

	_assert(found_spe, "Contender SPE found in available countries list", "SPE not in list")
	_assert(found_wrs, "WRS found in available countries list", "WRS not in list")


func _test_economy_engine_with_config() -> void:
	print("\n--- TEST 5: ECONOMY ENGINE DATA-DRIVEN CALCULATION ---")
	var loader = ContentLoaderClass.get_instance()
	var state = loader.load_country_by_tag("SPE")
	if state == null:
		state = CountryState.new()
		state.country_tag = "SPE"
		state.gdp_billions = 40.0
		state.tax_rate = 0.20

	var rev = EconomyEngine.calculate_turn_revenue(state)
	_assert(rev > 0.05, "Turn revenue calculated with data-driven multipliers", "Revenue: %f" % rev)

	var exp_dict = EconomyEngine.calculate_turn_expenses(state)
	_assert(exp_dict.has("total") and exp_dict["total"] > 0.0, "Turn expenses calculated with data-driven multipliers", "Expenses: %s" % str(exp_dict))

	var report = EconomyEngine.process_turn(state)
	_assert(report != null, "process_turn returned valid report", "Report is null")
	_assert(report.gdp_new > 0.0, "New GDP updated properly", "New GDP: %f" % report.gdp_new)


func _test_military_engine_with_config() -> void:
	print("\n--- TEST 6: MILITARY ENGINE DATA-DRIVEN FORMULAS ---")
	var attacker = CountryState.new()
	attacker.country_tag = "KOM"
	attacker.manpower_pool = 80000
	attacker.infantry_weapons_stockpile = 15000
	attacker.army_readiness = 75.0
	attacker.army_morale = 80.0

	var reg = RegionData.new()
	reg.province_id = 100
	reg.province_name = "Сыктывкар"
	reg.terrain_type = "forest"
	reg.garrison_strength = 50.0

	# Test border raid with ConfigManager data
	var raid_rep = MilitaryEngine.execute_border_raid(attacker, reg, "medium")
	_assert(raid_rep != null, "Border raid executed using ConfigManager raid presets", "Raid report null")
	_assert(raid_rep.narrative_summary.length() > 0, "Raid summary generated: %s" % raid_rep.narrative_summary)


func _test_turn_manager_point_accrual() -> void:
	print("\n--- TEST 7: TURN MANAGER DATA-DRIVEN ACCRUAL ---")
	var tm = TurnManagerClass.new()
	root.add_child(tm)

	var p_state = CountryState.new()
	p_state.country_tag = "TEST"
	p_state.political_capital = 50.0
	p_state.pc_gain_per_turn = 7.5
	p_state.max_cap = 5
	p_state.current_cap = 0
	tm.player_state = p_state

	tm.end_turn()

	_assert(p_state.current_cap == 5, "CAP restored to max_cap on end_turn", "CAP: %d" % p_state.current_cap)
	_assert(p_state.political_capital >= 57.0, "Political capital increased by pc_gain_per_turn", "PC: %f" % p_state.political_capital)
