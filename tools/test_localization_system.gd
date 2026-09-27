extends SceneTree

var _tested = false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true
	_run_tests()
	return false

func _run_tests() -> void:
	print("========================================================")
	print("   VERIFYING OPTIMIZED LOCALIZATION MANAGER & SWITCHING")
	print("========================================================")
	
	var root = get_root()
	var loc = root.get_node_or_null("LocalizationManager")
	if loc == null:
		push_error("[FAIL] LocalizationManager autoload not found in root!")
		quit(1)
		return
		
	# TEST 1: Default locale is Russian
	var initial_loc = loc.get_locale()
	print("[TEST 1] Initial locale: [%s]" % initial_loc)
	assert(initial_loc == "ru", "Default locale MUST be 'ru'!")
	print("  [PASS] Default locale is Russian ('ru').")
	
	# TEST 2: tr_key basic lookups and formatting in Russian
	print("[TEST 2] Testing Russian key lookups...")
	var title_ru = loc.tr_key("SYS_TITLE")
	var new_game_ru = loc.tr_key("MENU_NEW_GAME")
	print("  * SYS_TITLE (RU): %s" % title_ru)
	print("  * MENU_NEW_GAME (RU): %s" % new_game_ru)
	assert(not title_ru.begins_with("[MISSING"), "SYS_TITLE must exist in RU")
	assert(not new_game_ru.begins_with("[MISSING"), "MENU_NEW_GAME must exist in RU")
	
	# Parameter replacement test
	var formatted = loc.tr_key("NON_EXISTENT_KEY", {"user": "Commander"}, "Welcome, {user}!")
	print("  * Parameter formatted fallback: %s" % formatted)
	assert(formatted == "Welcome, Commander!", "Context parameters should be replaced properly")
	print("  [PASS] Key lookups and formatting function correctly.")
	
	# TEST 3: Switching locale to English
	print("[TEST 3] Testing switch to English ('en')...")
	var signal_box = {"received": false, "code": ""}
	loc.locale_changed.connect(func(code):
		signal_box["received"] = true
		signal_box["code"] = code
	)
	
	var t0 = Time.get_ticks_msec()
	loc.set_locale("en", false)
	var t_switch_en = Time.get_ticks_msec() - t0
	print("  * Switch to EN took %d ms" % t_switch_en)
	assert(loc.get_locale() == "en", "Locale should now be 'en'")
	assert(signal_box["received"] and signal_box["code"] == "en", "locale_changed signal must be emitted with 'en'")
	
	var title_en = loc.tr_key("SYS_TITLE")
	var new_game_en = loc.tr_key("MENU_NEW_GAME")
	print("  * SYS_TITLE (EN): %s" % title_en)
	print("  * MENU_NEW_GAME (EN): %s" % new_game_en)
	assert(title_en != title_ru, "EN translation should differ from RU")
	print("  [PASS] Switched to English successfully.")
	
	# TEST 4: Instant memory switch back to Russian
	print("[TEST 4] Testing instant switch back to Russian ('ru')...")
	var t_back0 = Time.get_ticks_msec()
	loc.set_locale("ru", true) # save_persisted = true to keep RU as default
	var t_switch_ru = Time.get_ticks_msec() - t_back0
	print("  * Switch back to RU took %d ms" % t_switch_ru)
	assert(t_switch_ru < 20, "Switching between loaded dictionaries should be instantaneous (<20ms)")
	assert(loc.get_locale() == "ru", "Locale should be 'ru'")
	print("  [PASS] Instant switch back to Russian completed in %d ms." % t_switch_ru)
	
	# TEST 5: Fallback behavior for invalid locale
	print("[TEST 5] Testing invalid locale fallback...")
	loc.set_locale("invalid_code_xyz", false)
	assert(loc.get_locale() == "ru", "Invalid locale should fall back to 'ru'")
	print("  [PASS] Fallback to Russian confirmed.")
	
	# TEST 6: Persistence test
	print("[TEST 6] Testing config persistence...")
	loc.set_locale("ru", true)
	var config = ConfigFile.new()
	var err = config.load(LocalizationManager.CONFIG_PATH)
	assert(err == OK, "Settings config must be loadable")
	var saved = config.get_value("localization", "locale", "")
	print("  * Persisted locale in settings.cfg: [%s]" % saved)
	assert(saved == "ru", "Saved locale in settings.cfg must be 'ru'")
	print("  [PASS] Config persistence verified.")
	
	print("========================================================")
	print("   ALL LOCALIZATION OPTIMIZATION TESTS PASSED!")
	print("========================================================")
	quit(0)
