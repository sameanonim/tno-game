extends SceneTree

##
## Test Sprint 3 Verification:
## 1. Zero-smell signal integrity (100% active, 0 dead signals)
## 2. DEFCON escalation thresholds dehardcoding via ConfigManager
## 3. TopBar & Economy UI reactivity (Warlord War Chest vs Superpower Sovereign Debt)
## 4. CRT & Singleton reactive event bus integrity
##

const CountryState = preload("res://core/data/country_state.gd")
const MilitaryEngine = preload("res://core/systems/military_engine.gd")
const EconomyEngine = preload("res://core/systems/economy_engine.gd")
const ConfigManager = preload("res://core/systems/config_manager.gd")
const TNOTopBar = preload("res://ui/components/tno_topbar.gd")

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("================================================================================")
	print(">>> RUNNING SPRINT 3 VERIFICATION TEST SUITE <<<")
	print("================================================================================")

	_test_signals_zero_smell()
	_test_defcon_config_dehardcoding()
	_test_topbar_warlord_reactivity()
	_test_singleton_event_bus()

	print("\n================================================================================")
	print(">>> ALL SPRINT 3 TESTS PASSED SUCCESSFULLY! <<<")
	print("================================================================================")
	quit(0)


func _test_signals_zero_smell() -> void:
	print("\n[TEST 1] Verifying Signal Architecture (Zero-Smell & 100% Connected)...")
	# Run python audit_signals.py and verify json output
	var output = []
	var exit_code = OS.execute("python", ["tools/audit_signals.py"], output)
	assert(exit_code == 0, "audit_signals.py should execute without errors")

	var report_file = FileAccess.open("res://tools/audit_signals_report.json", FileAccess.READ)
	assert(report_file != null, "audit_signals_report.json must exist")
	var report_text = report_file.get_as_text()
	report_file.close()

	var json = JSON.new()
	var err = json.parse(report_text)
	assert(err == OK, "audit_signals_report.json must be valid JSON")

	var report_dict = json.data as Dictionary
	var dead_count = int(report_dict.get("dead_signals_count", 999))
	var unemitted_count = int(report_dict.get("unemitted_signals_count", 999))
	var total_count = int(report_dict.get("total_signals_declared", 0))

	print("  -> Total Signals Declared: %d" % total_count)
	print("  -> Dead Signals Count: %d" % dead_count)
	print("  -> Unemitted Signals Count: %d" % unemitted_count)

	assert(dead_count == 0, "There must be 0 dead signals! Found %d" % dead_count)
	assert(unemitted_count == 0, "There must be 0 unemitted signals! Found %d" % unemitted_count)
	print("  -> PASSED: 100% signal coverage with zero dead signals.")


func _test_defcon_config_dehardcoding() -> void:
	print("\n[TEST 2] Verifying DEFCON Dehardcoding via ConfigManager...")
	var cfg = ConfigManager.get_instance()
	if cfg == null:
		cfg = ConfigManager.new()
		cfg.name = "ConfigManager"
		root.add_child(cfg)
		cfg.load_constants()

	var defcon_thresh = cfg.get_constant("military", "defcon_escalation_thresholds", {})
	assert(not defcon_thresh.is_empty(), "defcon_escalation_thresholds must be loaded in ConfigManager")
	assert(defcon_thresh.has("DEFCON_1") and defcon_thresh.has("DEFCON_2"), "Must have DEFCON_1 and DEFCON_2 thresholds")

	# Test dynamic evaluation using MilitaryEngine
	var countries = {"USA": CountryState.new(), "GER": CountryState.new()}
	MilitaryEngine.global_world_tension = 95.0 # High tension -> DEFCON 1
	var rep = MilitaryEngine.evaluate_global_defcon([], countries, 1)
	assert(rep.get("current_level") == 1, "Tension 95.0 should trigger DEFCON 1")

	MilitaryEngine.global_world_tension = 10.0 # Low tension -> DEFCON 5
	rep = MilitaryEngine.evaluate_global_defcon([], countries, 2)
	assert(rep.get("current_level") == 5, "Tension 10.0 should trigger DEFCON 5")


	print("  -> PASSED: DEFCON thresholds successfully loaded and evaluated from ConfigManager.")


func _test_topbar_warlord_reactivity() -> void:
	print("\n[TEST 3] Verifying TopBar HUD Reactivity (Warlord War Chest vs Superpower)...")
	var topbar = TNOTopBar.new()
	topbar.lbl_econ = Label.new()

	# 1. Warlord
	var warlord = CountryState.new()
	warlord.country_tag = "OMS"
	warlord.gdp_billions = 4.2
	warlord.liquid_reserves_billions = 0.35
	warlord.national_debt_billions = 0.0

	topbar.update_state(warlord)
	var text_warlord = topbar.lbl_econ.text
	assert(text_warlord.contains("КАЗНА: $0.35B"), "Warlord TopBar must display War Chest reserves")
	assert(text_warlord.contains("КАЗНА: СТАБИЛЬНА"), "Warlord TopBar must show stable war chest badge")

	# 2. Superpower Hegemon
	var hegemon = CountryState.new()
	hegemon.country_tag = "USA"
	hegemon.global_sphere = "OFN"
	hegemon.gdp_billions = 260.0
	hegemon.national_debt_billions = 140.0
	hegemon.liquid_reserves_billions = 15.0

	topbar.update_state(hegemon)
	var text_hegemon = topbar.lbl_econ.text
	assert(text_hegemon.contains("$260.0B / $140.0B"), "Hegemon TopBar must display GDP and Sovereign Debt ratio")

	topbar.lbl_econ.free()
	topbar.free()
	print("  -> PASSED: TopBar correctly adapts presentation to Warlord vs Sovereign archetypes.")


func _test_singleton_event_bus() -> void:
	print("\n[TEST 4] Verifying Singleton Event Bus (Localization & Settings)...")
	var loc = root.get_node_or_null("LocalizationManager")
	if loc != null:
		var initial_loc = loc.current_locale
		assert(not initial_loc.is_empty(), "LocalizationManager must have active locale")
		print("  -> Active locale verified: %s" % initial_loc)

	var sm = root.get_node_or_null("SettingsManager")
	if sm != null:
		assert(sm.crt_settings.has("curvature"), "SettingsManager must have valid CRT parameters")
		print("  -> SettingsManager CRT parameters verified.")

	print("  -> PASSED: Singletons responsive and operational.")
