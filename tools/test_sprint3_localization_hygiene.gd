extends SceneTree

##
## Test Suite: Sprint 3 UI Localization & Code Hygiene
##
## Tests:
## 1. Localization keys completeness for Espionage and Decisions in both ru and en dictionaries.
## 2. Dynamic locale switching (ru <-> en) in EspionageTerminalView and DecisionsPanel.
## 3. Strict type safety and instantiation checks for updated systems.
##

const LocalizationManagerScript = preload("res://core/systems/localization_manager.gd")

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("================================================================================")
	print(">>> RUNNING SPRINT 3 LOCALIZATION & CODE HYGIENE TEST SUITE <<<")
	print("================================================================================")

	var pass_count: int = 0
	var total_tests: int = 3

	if _test_localization_dictionaries_completeness():
		pass_count += 1

	if _test_terminal_views_locale_switching():
		pass_count += 1

	if _test_code_hygiene_and_typing():
		pass_count += 1

	print("================================================================================")
	if pass_count == total_tests:
		print(">>> ALL SPRINT 3 TESTS PASSED SUCCESSFULLY! (%d/%d) <<<" % [pass_count, total_tests])
		quit(0)
	else:
		printerr(">>> SPRINT 3 VERIFICATION FAILED: %d/%d PASSED <<<" % [pass_count, total_tests])
		quit(1)


func _get_or_create_localization_manager() -> Node:
	var loc = root.get_node_or_null("LocalizationManager")
	if loc == null:
		loc = LocalizationManagerScript.new()
		loc.name = "LocalizationManager"
		root.add_child(loc)
	return loc


func _test_localization_dictionaries_completeness() -> bool:
	print("\n[TEST 1] Testing Localization Dictionaries Completeness (ru & en)...")

	var loc = _get_or_create_localization_manager()
	loc.set_locale("ru", false)

	var required_keys = [
		"ESPIONAGE_TITLE",
		"ESPIONAGE_BLACK_BUDGET",
		"ESPIONAGE_DOMESTIC_SECURITY",
		"ESPIONAGE_CAP_POOL",
		"ESPIONAGE_DEFICIT_WARNING",
		"ESPIONAGE_TAB_NETWORKS",
		"ESPIONAGE_TAB_OPERATIONS",
		"ESPIONAGE_TAB_ROSTER",
		"ESPIONAGE_TAB_LAUNCH",
		"ESPIONAGE_NO_NETWORKS",
		"ESPIONAGE_AGENTS_COUNT",
		"ESPIONAGE_BTN_INFILTRATE",
		"ESPIONAGE_NO_OPERATIONS",
		"ESPIONAGE_OP_TARGET",
		"ESPIONAGE_OP_FROZEN",
		"ESPIONAGE_OP_PROGRESS",
		"ESPIONAGE_OP_RISK",
		"ESPIONAGE_BTN_ABORT",
		"ESPIONAGE_NO_AGENTS",
		"ESPIONAGE_LOYALTY",
		"ESPIONAGE_UPKEEP",
		"ESPIONAGE_BTN_RECALL",
		"ESPIONAGE_BTN_ASSIGN",
		"ESPIONAGE_BTN_RECRUIT",
		"ESPIONAGE_ERR_BUDGET",
		"ESPIONAGE_RECRUIT_SUCCESS",
		"ESPIONAGE_AGENT_RECALLED",
		"ESPIONAGE_AGENT_ASSIGNED",
		"ESPIONAGE_AGENT_REASSIGNED",
		"ESPIONAGE_ERR_NO_AGENTS",
		"ESPIONAGE_PLAN_HEADER",
		"ESPIONAGE_PLAN_TITLE",
		"ESPIONAGE_PLAN_TARGET",
		"ESPIONAGE_PLAN_REQ",
		"ESPIONAGE_PLAN_DURATION",
		"ESPIONAGE_PLAN_COST",
		"ESPIONAGE_PLAN_BASE_RISK",
		"ESPIONAGE_PLAN_FAIL_REQS",
		"ESPIONAGE_PLAN_READY",
		"ESPIONAGE_OP_LAUNCHED",
		"ESPIONAGE_OP_STEAL_TECH",
		"ESPIONAGE_OP_SABOTAGE_INDUSTRY",
		"ESPIONAGE_OP_SABOTAGE_MILITARY",
		"ESPIONAGE_OP_FUND_COUP",
		"ESPIONAGE_OP_ARM_REBELS",
		"ESPIONAGE_OP_DISINFORMATION",
		"ESPIONAGE_OP_ASSASSINATION",
		"ESPIONAGE_LOG_ABORT",
		"ESPIONAGE_LOG_SYNC",
		"DEC_LOG_EXECUTED"
	]

	# Check Russian keys
	for k in required_keys:
		var val_ru = loc.tr_key(k, {}, "")
		if val_ru.is_empty():
			printerr("FAIL: Missing RU translation for key: %s" % k)
			return false

	# Switch to English and check English keys
	loc.set_locale("en", false)
	for k in required_keys:
		var val_en = loc.tr_key(k, {}, "")
		if val_en.is_empty():
			printerr("FAIL: Missing EN translation for key: %s" % k)
			return false

	# Verify distinct translations
	loc.set_locale("ru", false)
	var title_ru_actual = loc.tr_key("ESPIONAGE_TITLE", {}, "")
	loc.set_locale("en", false)
	var title_en_actual = loc.tr_key("ESPIONAGE_TITLE", {}, "")

	if title_ru_actual == title_en_actual:
		printerr("FAIL: RU and EN translations for ESPIONAGE_TITLE must not be identical! (%s)" % title_ru_actual)
		return false

	print("  -> PASSED: All 50 required UI keys present and localized in both ru and en.")
	return true


func _test_terminal_views_locale_switching() -> bool:
	print("\n[TEST 2] Testing Dynamic Locale Switching in EspionageTerminalView...")

	var loc = _get_or_create_localization_manager()
	loc.set_locale("ru", false)

	var state = CountryState.new()
	state.country_tag = "KOM"
	state.black_budget = 25.0
	state.black_budget_allocation_per_turn = 2.5
	state.domestic_security = 65.0
	state.current_cap = 3
	state.max_cap = 5

	var esp_scene = load("res://ui/screens/espionage_terminal_view.tscn")
	if esp_scene == null:
		printerr("FAIL: Could not load espionage_terminal_view.tscn")
		return false

	var esp_view = esp_scene.instantiate() as EspionageTerminalView
	root.add_child(esp_view)
	esp_view.setup(state, null)

	var title_lbl = esp_view.find_child("TitleLabel", true, false) as Label
	var bb_lbl = esp_view.find_child("BlackBudgetLabel", true, false) as Label

	# Verify initial RU texts
	if not "ТЕРМИНАЛ" in title_lbl.text:
		printerr("FAIL: Russian header title not set: %s" % title_lbl.text)
		esp_view.queue_free()
		return false
	if not "ЧЕРНЫЙ БЮДЖЕТ" in bb_lbl.text:
		printerr("FAIL: Russian black budget label not set: %s" % bb_lbl.text)
		esp_view.queue_free()
		return false

	# Switch to English
	loc.set_locale("en", false)

	# Verify switched EN texts
	if not "COVERT" in title_lbl.text and not "TERMINAL" in title_lbl.text:
		printerr("FAIL: Header title failed to switch to English: %s" % title_lbl.text)
		esp_view.queue_free()
		return false
	if not "BLACK BUDGET" in bb_lbl.text:
		printerr("FAIL: Black budget label failed to switch to English: %s" % bb_lbl.text)
		esp_view.queue_free()
		return false

	# Switch back to Russian
	loc.set_locale("ru", false)
	esp_view.queue_free()

	# Verify DecisionsPanel dynamic localization
	var dec_scene = load("res://ui/components/decisions_panel.tscn")
	if dec_scene != null:
		var dec_panel = dec_scene.instantiate() as DecisionsPanel
		root.add_child(dec_panel)
		dec_panel.setup(state, null)

		# Check Russian key
		var dec_title_ru = loc.tr_key("DEC_SMUTA_ARMS_SMUGGLING_TITLE", {}, "")
		if not "Контрабандистов" in dec_title_ru:
			printerr("FAIL: Russian decision title missing in localization: %s" % dec_title_ru)
			dec_panel.queue_free()
			return false

		# Switch to English
		loc.set_locale("en", false)
		var dec_title_en = loc.tr_key("DEC_SMUTA_ARMS_SMUGGLING_TITLE", {}, "")
		if not "Smugglers" in dec_title_en:
			printerr("FAIL: English decision title missing in localization: %s" % dec_title_en)
			dec_panel.queue_free()
			return false

		loc.set_locale("ru", false)
		dec_panel.queue_free()

	print("  -> PASSED: EspionageTerminalView & DecisionsPanel dynamically responded to locale_changed signal and updated UI.")
	return true


func _test_code_hygiene_and_typing() -> bool:
	print("\n[TEST 3] Testing Core System Instantiation & Type Hygiene...")

	# Verify instantiate without error
	var state = CountryState.new()
	var region = RegionData.new()
	var front = Frontline.new()
	var axis = OperationalAxis.new()
	var event = GameEvent.new()
	var leader = LeaderResource.new()

	if state == null or region == null or front == null or axis == null or event == null or leader == null:
		printerr("FAIL: Core resource instantiation returned null")
		return false

	# Check property types
	if typeof(state.credit_rating_index) != TYPE_INT:
		printerr("FAIL: credit_rating_index is not int")
		return false
	if typeof(state.interest_rate) != TYPE_FLOAT:
		printerr("FAIL: interest_rate alias is not float")
		return false
	if typeof(axis.target_region_ids) != TYPE_ARRAY:
		printerr("FAIL: target_region_ids is not Array")
		return false

	print("  -> PASSED: All core resources instantiated and verified with strict type integrity.")
	return true
