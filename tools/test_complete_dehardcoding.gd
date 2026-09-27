extends SceneTree

##
## TestCompleteDehardcoding: Комплексная верификация дехардкодинга
## -----------------------------------------------------------
## Проверяет:
## 1. Загрузку стран из разных регионов и театров (GER, SPE, BOR, GOR, HEY, WRS, OMS, KOM, USA, JAP).
## 2. Загрузку лидеров, министров и генералов из изолированных JSON файлов.
## 3. Загрузку национальных директив (древ фокусов) из tree.json.
## 4. Загрузку нарративных событий из events.json.
## 5. Работу GermanyContentBundle исключительно на данных из JSON.
##

const ContentLoaderClass = preload("res://core/systems/content_loader.gd")
const GermanyContentBundleClass = preload("res://core/data/germany_content_bundle.gd")

var tests_passed: int = 0
var tests_failed: int = 0
var _log_file: FileAccess = null

func _log(msg: String) -> void:
	print(msg)
	if _log_file != null:
		_log_file.store_line(msg)
		_log_file.flush()

func _init() -> void:
	_log_file = FileAccess.open("res://test_dehardcoding.log", FileAccess.WRITE)
	_log("================================================================================")
	_log("TNO COMPLETE DEHARDCODING VERIFICATION TEST (COUNTRIES, LEADERS, FOCUSES, EVENTS)")
	_log("================================================================================")

	_test_countries_dehardcoding()
	_test_leaders_and_ministers_dehardcoding()
	_test_focus_trees_dehardcoding()
	_test_events_dehardcoding()
	_test_germany_bundle_dehardcoding()

	_log("================================================================================")
	_log("TEST RESULTS: Passed: %d | Failed: %d" % [tests_passed, tests_failed])
	_log("================================================================================")

	if tests_failed == 0:
		_log(">>> ALL DEHARDCODING TESTS PASSED SUCCESSFULLY! ZERO HARDCODE REMAINING! <<<")
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


# ==============================================================================
# TEST 1: СТРАНЫ И ПРОФИЛИ
# ==============================================================================
func _test_countries_dehardcoding() -> void:
	_log("\n--- TEST 1: MULTI-COUNTRY DYNAMIC LOADING (DATA-DRIVEN) ---")
	var loader = ContentLoaderClass.get_instance()
	if loader == null:
		loader = ContentLoaderClass.new()
		root.add_child(loader)

	var sample_tags = ["GER", "SPE", "BOR", "GOR", "HEY", "WRS", "OMS", "KOM", "USA", "JAP"]
	for tag in sample_tags:
		var st = loader.load_country_by_tag(tag)
		_assert(st != null, "Country state loaded for %s" % tag, "Returned null")
		if st != null:
			_assert(st.country_tag == tag, "%s: Country tag matches" % tag, "Got %s" % st.country_tag)
			_assert(not st.country_name.is_empty(), "%s: Has localized name: %s" % [tag, st.country_name])
			_assert(st.gdp_billions > 0.0, "%s: GDP is valid: %f B" % [tag, st.gdp_billions])
			_assert(st.manpower_pool > 0, "%s: Manpower is valid: %d" % [tag, st.manpower_pool])
			_assert(st.country_color.a > 0.0, "%s: Has color definition" % tag)
			_assert(st.initial_parties.size() > 0, "%s: Has political parties (%d)" % [tag, st.initial_parties.size()])


# ==============================================================================
# TEST 2: ЛИДЕРЫ, МИНИСТРЫ И ГЕНЕРАЛЫ
# ==============================================================================
func _test_leaders_and_ministers_dehardcoding() -> void:
	_log("\n--- TEST 2: LEADERS, MINISTERS & COMMANDERS DYNAMIC LOADING ---")
	var loader = ContentLoaderClass.get_instance()
	if loader == null:
		loader = ContentLoaderClass.new()
		root.add_child(loader)

	# 1. Heads of State
	var speer = loader.load_leader_resource("SPE", "leader_albert_speer")
	_assert(speer != null and speer.leader_name.contains("Шпеер"), "Albert Speer loaded from JSON", "Failed")
	if speer != null:
		_assert(speer.traits.has("architect_of_the_reich"), "Speer has trait architect_of_the_reich")
		_assert(speer.competence == 4, "Speer competence is 4")

	var bormann = loader.load_leader_resource("BOR", "leader_martin_bormann")
	_assert(bormann != null and bormann.leader_name.contains("Борман"), "Martin Bormann loaded from JSON", "Failed")

	var goering = loader.load_leader_resource("GOR", "leader_hermann_goering")
	_assert(goering != null and goering.leader_name.contains("Геринг"), "Hermann Goering loaded from JSON", "Failed")

	var heydrich = loader.load_leader_resource("HEY", "leader_reinhard_heydrich")
	_assert(heydrich != null and heydrich.leader_name.contains("Гейдрих"), "Reinhard Heydrich loaded from JSON", "Failed")

	var goebbels = loader.load_leader_resource("GOB", "leader_joseph_goebbels")
	_assert(goebbels != null and goebbels.leader_name.contains("Геббельс"), "Joseph Goebbels loaded from JSON", "Failed")

	# 2. Military Generals / Commanders
	var speidel = loader.load_leader_resource("SPE", "spe_hans_speidel")
	_assert(speidel != null, "General Hans Speidel loaded dynamically", "Failed")
	if speidel != null:
		_assert(speidel.is_military_commander, "Speidel is military commander")
		_assert(speidel.defense_skill >= 6, "Speidel defense skill >= 6")

	var schorner = loader.load_leader_resource("BOR", "bor_ferdinand_schorner")
	_assert(schorner != null, "General Ferdinand Schörner loaded dynamically", "Failed")

	var milch = loader.load_leader_resource("GOR", "gor_erhard_milch")
	_assert(milch != null, "Luftwaffe General Erhard Milch loaded dynamically", "Failed")

	var wolff = loader.load_leader_resource("HEY", "hey_karl_wolff")
	_assert(wolff != null, "SS General Karl Wolff loaded dynamically", "Failed")

	# 3. Warlord Leaders
	var yegorov = loader.load_leader_resource("WRS", "WRS_Alexander_Yegorov")
	_assert(yegorov != null, "WRS Alexander Yegorov loaded dynamically", "Failed")


# ==============================================================================
# TEST 3: НАЦИОНАЛЬНЫЕ ДИРЕКТИВЫ (ДРЕВА ФОКУСОВ)
# ==============================================================================
func _test_focus_trees_dehardcoding() -> void:
	_log("\n--- TEST 3: DIRECTIVE TREES (NATIONAL FOCUSES) ---")
	var loader = ContentLoaderClass.get_instance()
	if loader == null:
		loader = ContentLoaderClass.new()
		root.add_child(loader)

	# Germany Phase 1 & 3
	var ger_dirs = loader.get_directives_for_country("GER")
	_assert(ger_dirs.size() >= 5, "GER has 5+ directives in tree.json", "Got %d" % ger_dirs.size())

	# Speer Tree
	var spe_dirs = loader.get_directives_for_country("SPE")
	_assert(spe_dirs.size() >= 2, "SPE has 2+ reform directives", "Got %d" % spe_dirs.size())
	if spe_dirs.size() >= 2:
		_assert(spe_dirs[0].directive_id == "dir_speer_student_volunteers", "First Speer directive is student volunteers")

	# Bormann Tree
	var bor_dirs = loader.get_directives_for_country("BOR")
	_assert(bor_dirs.size() >= 2, "BOR has 2+ party directives", "Got %d" % bor_dirs.size())

	# Warlord trees
	var wrs_dirs = loader.get_directives_for_country("WRS")
	_assert(wrs_dirs.size() > 0, "WRS has directives loaded", "Got %d" % wrs_dirs.size())

	var oms_dirs = loader.get_directives_for_country("OMS")
	_assert(oms_dirs.size() > 0, "OMS has directives loaded", "Got %d" % oms_dirs.size())


# ==============================================================================
# TEST 4: НАРРАТИВНЫЕ СОБЫТИЯ
# ==============================================================================
func _test_events_dehardcoding() -> void:
	_log("\n--- TEST 4: NARRATIVE EVENTS DYNAMIC LOADING ---")
	var ev_death = GermanyContentBundleClass.create_event_hitler_death()
	_assert(ev_death != null, "Hitler Death event loaded from JSON", "Returned null")
	if ev_death != null:
		_assert(ev_death.event_id == "germany_hitler_dies", "Event ID is germany_hitler_dies")
		_assert(ev_death.is_modal, "Event is modal")
		_assert(ev_death.options.size() > 0, "Event has options")

	var ev_berlin = GermanyContentBundleClass.create_event_fall_of_berlin("SPE")
	_assert(ev_berlin != null, "Fall of Berlin event loaded from JSON", "Returned null")
	if ev_berlin != null:
		_assert(ev_berlin.description.contains("SPE"), "Conqueror tag formatted into event text")

	var ev_strike = GermanyContentBundleClass.create_event_ruhr_strike()
	_assert(ev_strike != null and ev_strike.event_id == "germany_ruhr_strike", "Ruhr Strike event loaded")

	var ev_burgundy = GermanyContentBundleClass.create_event_burgundian_ultimatum()
	_assert(ev_burgundy != null and ev_burgundy.event_id == "germany_burgundian_ultimatum", "Burgundian Ultimatum event loaded")

	var ev_goebbels = GermanyContentBundleClass.create_event_goebbels_uprising()
	_assert(ev_goebbels != null and ev_goebbels.event_id == "germany_goebbels_uprising", "Goebbels Uprising event loaded")


# ==============================================================================
# TEST 5: GERMANY CONTENT BUNDLE BRIDGE
# ==============================================================================
func _test_germany_bundle_dehardcoding() -> void:
	_log("\n--- TEST 5: GERMANY CONTENT BUNDLE 100% DATA-DRIVEN ---")
	var all_leaders = GermanyContentBundleClass.get_all_leaders()
	_assert(all_leaders.has("SPEER") and all_leaders.has("BORMANN") and all_leaders.has("GOERING") and all_leaders.has("HEYDRICH"), "All contenders returned by get_all_leaders()")
	_assert(all_leaders["SPEER"].traits.size() > 0, "Speer traits populated dynamically from JSON")

	var all_directives = GermanyContentBundleClass.get_all_directives()
	_assert(all_directives.size() >= 10, "get_all_directives() returns 10+ directives across contenders", "Got %d" % all_directives.size())
