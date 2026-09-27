extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("==================================================")
	print("--- TESTING LOCALIZATION & MAIN MENU INTEGRATION ---")
	print("==================================================")

	var loc = root.get_node_or_null("LocalizationManager")
	if loc == null:
		push_error("LocalizationManager autoload missing!")
		quit(1)
		return

	print("[INFO] Active locale:", loc.get_locale())

	# 1. Instantiate Main Menu
	var menu_scene = load("res://ui/screens/main_menu.tscn") as PackedScene
	if menu_scene == null:
		push_error("Failed to load main_menu.tscn")
		quit(1)
		return

	var menu = menu_scene.instantiate()
	root.add_child(menu)
	print("[OK] Main Menu instantiated successfully.")

	# 2. Verify Language Button exists in Titular Panel
	assert(menu.btn_language != null, "LanguageButton must exist in Main Menu!")
	print("[OK] btn_language verified:", menu.btn_language.text)

	# 3. Test modal Language Settings opening and closing
	menu._on_open_language_settings()
	var lang_dialog = null
	for child in menu.get_children():
		if child is SettingsLanguage:
			lang_dialog = child
			break
	assert(lang_dialog != null, "SettingsLanguage modal dialog must be spawned!")
	print("[OK] SettingsLanguage dialog opened from Main Menu.")
	lang_dialog.closed.emit()
	print("[OK] SettingsLanguage dialog closed.")

	# 4. Test Switch to English
	print("\n--- Testing Switch to EN ---")
	loc.set_locale("en")
	assert("NEW CAMPAIGN" in menu.btn_new_game.text, "btn_new_game text should be in English: " + menu.btn_new_game.text)
	assert("LANGUAGES" in menu.btn_language.text, "btn_language text should be in English: " + menu.btn_language.text)
	assert("OPTIONS" in menu.btn_settings.text or "SETTINGS" in menu.btn_settings.text, "btn_settings text should be in English: " + menu.btn_settings.text)
	assert("EXIT" in menu.btn_exit.text or "POWER DOWN" in menu.btn_exit.text, "btn_exit text should be in English: " + menu.btn_exit.text)
	assert("CRISIS PROTOCOLS" in menu.setup_rules_label.text, "setup_rules_label should be English: " + menu.setup_rules_label.text)
	assert("1 WEEK" in menu.btn_timestep.text, "btn_timestep should be English: " + menu.btn_timestep.text)
	print("[OK] All titular, setup, and rule buttons verified in English.")

	# 5. Test Switch to Russian
	print("\n--- Testing Switch to RU ---")
	loc.set_locale("ru")
	assert("НОВАЯ КАМПАНИЯ" in menu.btn_new_game.text, "btn_new_game text should be in Russian: " + menu.btn_new_game.text)
	assert("ЯЗЫК" in menu.btn_language.text, "btn_language text should be in Russian: " + menu.btn_language.text)
	assert("НАСТРОЙКИ" in menu.btn_settings.text, "btn_settings text should be in Russian: " + menu.btn_settings.text)
	assert("ВЫХОД" in menu.btn_exit.text or "ОТКЛЮЧИТЬ" in menu.btn_exit.text, "btn_exit text should be in Russian: " + menu.btn_exit.text)
	assert("КРИЗИСНЫЕ ПРОТОКОЛЫ" in menu.setup_rules_label.text, "setup_rules_label should be Russian: " + menu.setup_rules_label.text)
	assert("1 НЕДЕЛЯ" in menu.btn_timestep.text, "btn_timestep should be Russian: " + menu.btn_timestep.text)
	print("[OK] All titular, setup, and rule buttons verified in Russian.")

	# 6. Test TerminalMain HUD
	print("\n--- Testing TerminalMain HUD Localization ---")
	menu.queue_free()
	var term_scene = load("res://ui/screens/terminal_main.tscn") as PackedScene
	if term_scene != null:
		var term = term_scene.instantiate()
		root.add_child(term)
		loc.set_locale("en")
		assert("POLITICAL" in term.btn_map_pol.text, "btn_map_pol should be English: " + term.btn_map_pol.text)
		assert("DIRECTIVES" in term.tab_container.get_tab_title(1), "Tab 1 should be English: " + term.tab_container.get_tab_title(1))
		assert("END TURN" in term.btn_end_turn.text, "btn_end_turn should be English: " + term.btn_end_turn.text)
		
		loc.set_locale("ru")
		assert("ПОЛИТИЧЕСКАЯ" in term.btn_map_pol.text, "btn_map_pol should be Russian: " + term.btn_map_pol.text)
		assert("ДИРЕКТИВЫ" in term.tab_container.get_tab_title(1), "Tab 1 should be Russian: " + term.tab_container.get_tab_title(1))
		assert("ЗАВЕРШИТЬ ХОД" in term.btn_end_turn.text, "btn_end_turn should be Russian: " + term.btn_end_turn.text)
		print("[OK] TerminalMain HUD dynamically and correctly switches between RU and EN.")
		term.queue_free()


	print("\n==================================================")
	print("--- ALL LOCALIZATION TESTS PASSED SUCCESSFULLY! ---")
	print("==================================================")
	quit(0)
