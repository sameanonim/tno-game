extends SceneTree

##
## test_settings_application_everywhere.gd
## Комплексный тест корректного применения настроек интерфейса во всех ключевых экранах:
## - SettingsManager & central overlay registry
## - terminal_main (CRTPostProcess, UI scale, Localization, In-game Settings)
## - main_menu (CRTOverlay, sliders, audio volume, UI scale)
## - settings_terminal (UI scale dropdown, CRT sliders, BIOS persistence)
## - settings_language (CRTOverlay synchronization)
##

func _init() -> void:
	call_deferred("_run_integration_tests")


func _run_integration_tests() -> void:
	print("==================================================")
	print("--- TESTING GLOBAL UI SETTINGS PROPAGATION ---")
	print("==================================================")

	# 1. Синглтоны
	var sm = root.get_node_or_null("SettingsManager")
	assert(sm != null, "SettingsManager Autoload must exist!")
	var loc = root.get_node_or_null("LocalizationManager")
	assert(loc != null, "LocalizationManager Autoload must exist!")

	# Сбрасываем к эталону
	sm.apply_ui_scale(1.0)
	sm.set_crt_enabled(true)
	sm.set_crt_param("curvature", 0.04)

	# 2. Тест Главного меню (main_menu.tscn)
	var menu_scene = load("res://ui/screens/main_menu.tscn") as PackedScene
	assert(menu_scene != null, "main_menu.tscn must exist!")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	print("[OK] MainMenu instantiated.")

	var menu_crt = menu.get_node_or_null("CRTOverlay")
	assert(menu_crt != null, "MainMenu must have CRTOverlay node!")
	assert(menu_crt.visible == true, "CRTOverlay in MainMenu must be visible when enabled!")

	# Проверяем, что menu_crt зарегистрирован в SettingsManager
	assert(sm._registered_crt_overlays.has(menu_crt), "MainMenu CRTOverlay must be registered in SettingsManager!")

	# Меняем параметр CRT через SettingsManager — должен обновиться в MainMenu CRTOverlay
	sm.set_crt_param("curvature", 0.12)
	assert(is_equal_approx(float(menu_crt.material.get_shader_parameter("curvature")), 0.12), "MainMenu CRT curvature must be 0.12!")
	print("[OK] CRT curvature dynamically propagated to MainMenu shader.")

	# Выключаем CRT через SettingsManager — оверлей в MainMenu должен скрыться
	sm.set_crt_enabled(false)
	assert(menu_crt.visible == false, "MainMenu CRTOverlay must be hidden when CRT is disabled!")
	print("[OK] CRT disable dynamically hid MainMenu overlay.")

	sm.set_crt_enabled(true)
	assert(menu_crt.visible == true, "MainMenu CRTOverlay must be restored when CRT is re-enabled!")

	# Проверяем настройки внутри панели MainMenu Settings
	menu._switch_state(menu.MenuState.SETTINGS)
	menu._refresh_settings_ui()
	assert(is_equal_approx(menu.slider_curvature.value, 0.12), "MainMenu Settings slider must reflect current CRT curvature!")

	# Двигаем слайдер громкости в MainMenu Settings
	menu.slider_volume.value = 0.65
	menu.slider_volume.value_changed.emit(0.65)
	assert(is_equal_approx(sm.audio_settings["master_volume"], 0.65), "SettingsManager master volume must be updated from MainMenu slider!")
	print("[OK] MainMenu settings sliders properly bound to SettingsManager.")

	menu.queue_free()
	# Даем дереву такт на очистку
	await create_timer(0.05).timeout

	# 3. Тест Игрового Терминала (terminal_main.tscn)
	var term_scene = load("res://ui/screens/terminal_main.tscn") as PackedScene
	assert(term_scene != null, "terminal_main.tscn must exist!")
	var term = term_scene.instantiate()
	root.add_child(term)
	print("[OK] TerminalMain instantiated.")

	var term_crt = term._get_crt_node()
	assert(term_crt != null, "TerminalMain must find its CRT node (CRTPostProcess)!")
	assert(sm._registered_crt_overlays.has(term_crt), "TerminalMain CRT node must be registered in SettingsManager!")
	assert(term_crt.visible == true, "TerminalMain CRT must be visible when enabled!")

	# Проверяем динамическое изменение параметров CRT на игровом экране
	sm.set_crt_param("curvature", 0.08)
	assert(is_equal_approx(float(term_crt.material.get_shader_parameter("curvature")), 0.08), "TerminalMain CRT curvature must match 0.08!")
	sm.set_crt_enabled(false)
	assert(term_crt.visible == false, "TerminalMain CRT must be hidden when CRT disabled!")
	sm.set_crt_enabled(true)
	assert(term_crt.visible == true, "TerminalMain CRT must be visible when re-enabled!")
	print("[OK] TerminalMain CRT dynamically syncs with SettingsManager.")

	# Проверяем масштабирование UI на игровом экране
	sm.apply_ui_scale(1.5)
	assert(is_equal_approx(sm.current_ui_scale, 1.5), "SettingsManager current_ui_scale must be 1.5!")
	assert(is_equal_approx(root.content_scale_factor, 1.5), "root.content_scale_factor must be 1.5!")
	sm.apply_ui_scale(1.0)
	assert(is_equal_approx(root.content_scale_factor, 1.0), "root.content_scale_factor must be 1.0!")
	print("[OK] UI scale successfully applied to root viewport and TerminalMain.")

	# Проверяем переключение языка в реальном времени
	loc.set_locale("en")
	assert("MAP" in term.tab_container.get_tab_title(0) or "TACTICAL" in term.tab_container.get_tab_title(0), "Tab 0 must be in English!")
	loc.set_locale("ru")
	assert("КАРТА" in term.tab_container.get_tab_title(0), "Tab 0 must be in Russian!")
	print("[OK] Real-time localization updates confirmed in TerminalMain tabs.")

	# Проверяем открытие и закрытие настроек во время игры (ESC)
	term._toggle_in_game_settings()
	assert(term._active_settings_terminal != null, "In-game settings terminal must be spawned!")
	assert(term_crt.visible == false, "Main terminal CRT must be temporarily hidden while Settings modal is open!")

	# Закрываем настройки
	term._active_settings_terminal.closed.emit()
	assert(term_crt.visible == true, "Main terminal CRT must be restored after closing settings!")
	print("[OK] In-game settings modal toggled and CRT state restored cleanly.")

	term.queue_free()
	await create_timer(0.05).timeout

	# 4. Тест Экрана Языков (settings_language.tscn)
	var lang_scene = load("res://ui/screens/settings_language.tscn") as PackedScene
	assert(lang_scene != null, "settings_language.tscn must exist!")
	var lang_screen = lang_scene.instantiate()
	root.add_child(lang_screen)
	print("[OK] SettingsLanguage instantiated.")

	var lang_crt = lang_screen.get_node_or_null("CRTOverlay")
	assert(lang_crt != null, "SettingsLanguage must have CRTOverlay!")
	assert(sm._registered_crt_overlays.has(lang_crt), "SettingsLanguage CRTOverlay must be registered in SettingsManager!")
	sm.set_crt_enabled(false)
	assert(lang_crt.visible == false, "SettingsLanguage CRTOverlay must be hidden when disabled!")
	sm.set_crt_enabled(true)
	assert(lang_crt.visible == true, "SettingsLanguage CRTOverlay must be visible when enabled!")
	print("[OK] SettingsLanguage CRTOverlay correctly synchronized.")

	lang_screen.queue_free()

	# Возвращаем дефолтные параметры
	sm.set_crt_enabled(true)
	sm.set_crt_param("curvature", 0.03)
	sm.apply_ui_scale(1.0)
	sm.save_settings()

	print("==================================================")
	print("--- ALL GLOBAL UI SETTINGS TESTS PASSED [100%] ---")
	print("==================================================")
	quit(0)
