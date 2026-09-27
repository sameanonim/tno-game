extends SceneTree

##
## Тестовый сценарий верификации системы настроек, экранных разрешений,
## режимов окна, V-Sync, масштабирования UI и ретро-терминала настроек TNO
##

const SettingsTerminalScript = preload("res://ui/screens/settings_terminal.gd")

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("==================================================")
	print("--- TESTING TNO DISPLAY & SETTINGS SUBSYSTEM ---")
	print("==================================================")

	# 1. Проверка синглтона SettingsManager
	var sm = root.get_node_or_null("SettingsManager")
	if sm == null:
		var sm_script = load("res://core/systems/settings_manager.gd")
		sm = sm_script.new()
		sm.name = "SettingsManager"
		root.add_child(sm)
		print("[INFO] SettingsManager manually instantiated for test.")
	assert(sm != null, "SettingsManager must exist!")
	print("[OK] SettingsManager verified. Current resolution:", sm.current_resolution)

	# 2. Проверка списка разрешений
	var resolutions = sm.get_available_resolutions()
	assert(not resolutions.is_empty(), "Resolutions list must not be empty!")
	print("[OK] Available resolutions count: %d. First: %s, Last: %s" % [
		resolutions.size(),
		sm.get_resolution_label(resolutions[0]),
		sm.get_resolution_label(resolutions[-1])
	])

	# 3. Проверка изменения разрешений
	var res_signal = {"fired": false}
	var res_changed_callback = func(new_r: Vector2i):
		res_signal["fired"] = true
	sm.resolution_changed.connect(res_changed_callback)

	sm.apply_resolution(Vector2i(1600, 900))
	assert(sm.current_resolution == Vector2i(1600, 900), "Resolution must be updated to 1600x900!")
	assert(res_signal["fired"], "resolution_changed signal must fire!")
	print("[OK] apply_resolution tested successfully (1600x900).")

	# 4. Проверка смены режимов окна
	var mode_signal = {"fired": false}
	var mode_callback = func(new_m: int):
		mode_signal["fired"] = true
	sm.window_mode_changed.connect(mode_callback)

	sm.apply_window_mode(sm.WindowModeType.WINDOWED)
	assert(sm.current_window_mode == sm.WindowModeType.WINDOWED, "Window mode must be WINDOWED!")
	assert(mode_signal["fired"], "window_mode_changed signal must fire!")
	print("[OK] apply_window_mode tested successfully.")

	# 5. Проверка V-Sync
	sm.apply_vsync(sm.VSyncType.ENABLED)
	assert(sm.current_vsync == sm.VSyncType.ENABLED, "VSync must be ENABLED!")
	print("[OK] apply_vsync tested successfully.")

	# 6. Проверка UI Scale
	sm.apply_ui_scale(1.25)
	assert(is_equal_approx(sm.current_ui_scale, 1.25), "UI scale must be 1.25!")
	assert(is_equal_approx(root.content_scale_factor, 1.25), "root.content_scale_factor must be 1.25!")
	sm.apply_ui_scale(1.0)
	print("[OK] apply_ui_scale tested successfully (1.25 -> 1.0).")

	# 7. Проверка защитного таймера отката (Safety Revert)
	sm.test_display_mode(Vector2i(1280, 720), sm.WindowModeType.FULLSCREEN, 15)
	assert(sm.is_testing_display_mode(), "Must be in display testing mode!")
	assert(sm.current_resolution == Vector2i(1280, 720), "Current resolution must be 1280x720 during test!")

	sm.revert_display_mode()
	assert(not sm.is_testing_display_mode(), "Testing mode must be cancelled after revert!")
	assert(sm.current_resolution == Vector2i(1600, 900), "Resolution must revert back to 1600x900!")
	print("[OK] test_display_mode and revert_display_mode verified.")

	# 8. Проверка сохранения в user://settings.cfg
	sm.apply_resolution(Vector2i(1920, 1080))
	sm.save_settings()
	var cfg = ConfigFile.new()
	var load_res = cfg.load(sm.CONFIG_PATH)
	assert(load_res == OK, "Settings file must load successfully from %s" % sm.CONFIG_PATH)
	assert(cfg.get_value("display", "resolution_width") == 1920, "Config resolution_width must be 1920!")
	assert(cfg.get_value("display", "resolution_height") == 1080, "Config resolution_height must be 1080!")
	assert(cfg.has_section("crt"), "Config must have [crt] section!")
	assert(cfg.has_section("audio"), "Config must have [audio] section!")
	print("[OK] EEPROM BIOS configuration save and read verified.")

	# 9. Проверка инстанцирования SettingsTerminal сцены
	var term_scene = load("res://ui/screens/settings_terminal.tscn") as PackedScene
	assert(term_scene != null, "settings_terminal.tscn must exist and load!")

	var term = term_scene.instantiate()
	root.add_child(term)
	print("[OK] SettingsTerminal instantiated successfully.")

	# Проверка вкладок
	assert(term.tab_display_panel.visible, "Display tab must be visible by default!")
	term._switch_tab(SettingsTerminalScript.TabIndex.CRT)
	assert(term.tab_crt_panel.visible, "CRT tab must be visible after switch!")
	term._switch_tab(SettingsTerminalScript.TabIndex.AUDIO)
	assert(term.tab_audio_panel.visible, "Audio tab must be visible after switch!")
	term._switch_tab(SettingsTerminalScript.TabIndex.LANGUAGE)
	assert(term.tab_lang_panel.visible, "Language tab must be visible after switch!")
	term._switch_tab(SettingsTerminalScript.TabIndex.DISPLAY)
	print("[OK] All 4 terminal tabs switched and verified.")

	# 10. Проверка локализации строк настроек
	var loc = root.get_node_or_null("LocalizationManager")
	if loc == null:
		var loc_script = load("res://core/systems/localization_manager.gd")
		loc = loc_script.new()
		loc.name = "LocalizationManager"
		root.add_child(loc)

	loc.set_locale("en")
	assert("DISPLAY" in term.tab_btn_display.text, "Tab display button must be localized to English: " + term.tab_btn_display.text)
	assert("AUDIO" in term.tab_btn_audio.text, "Tab audio button must be localized to English: " + term.tab_btn_audio.text)

	loc.set_locale("ru")
	assert("ДИСПЛЕЙ" in term.tab_btn_display.text, "Tab display button must be localized to Russian: " + term.tab_btn_display.text)
	assert("ЗВУК" in term.tab_btn_audio.text, "Tab audio button must be localized to Russian: " + term.tab_btn_audio.text)
	print("[OK] Multilingual localization verified for settings UI (EN/RU).")

	term.queue_free()

	# 11. Проверка MainMenu вызова настроек
	var menu_scene = load("res://ui/screens/main_menu.tscn") as PackedScene
	var menu = menu_scene.instantiate() as MainMenu
	root.add_child(menu)
	print("[OK] MainMenu instantiated.")

	menu._on_open_system_settings()
	var spawned_term = null
	for child in menu.get_children():
		if child is SettingsTerminalScript:
			spawned_term = child
			break
	assert(spawned_term != null, "SettingsTerminal must be spawned from MainMenu btn_settings!")
	spawned_term.closed.emit()
	print("[OK] SettingsTerminal spawned and closed from MainMenu.")
	menu.queue_free()

	print("==================================================")
	print("--- ALL DISPLAY & SETTINGS TESTS PASSED [100%] ---")
	print("==================================================")
	quit(0)
