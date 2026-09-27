extends SceneTree

func _init() -> void:
	print("--- VERIFYING UI INSTANTIATION ---")
	
	# 1. Test Theme
	var theme = load("res://ui/themes/tno_theme.tres")
	assert(theme != null, "Failed to load tno_theme.tres")
	print("✓ tno_theme.tres loaded successfully.")

	# 2. Test TNOTopBar
	var topbar_scene = load("res://ui/components/tno_topbar.tscn")
	assert(topbar_scene != null, "Failed to load tno_topbar.tscn")
	var topbar = topbar_scene.instantiate()
	assert(topbar != null, "Failed to instantiate tno_topbar")
	print("✓ TNOTopBar instantiated successfully.")
	topbar.queue_free()

	# 3. Test PoliticsPanel
	var pol_scene = load("res://ui/screens/politics_panel.tscn")
	assert(pol_scene != null, "Failed to load politics_panel.tscn")
	var pol = pol_scene.instantiate()
	assert(pol != null, "Failed to instantiate politics_panel")
	print("✓ PoliticsPanel instantiated successfully.")
	pol.queue_free()

	# 4. Test TNOEconomyScreen
	var econ_scene = load("res://ui/screens/tno_economy_screen.tscn")
	assert(econ_scene != null, "Failed to load tno_economy_screen.tscn")
	var econ = econ_scene.instantiate()
	assert(econ != null, "Failed to instantiate tno_economy_screen")
	print("✓ TNOEconomyScreen instantiated successfully.")
	econ.queue_free()

	# 5. Test TNOSuperEventModal
	var super_scene = load("res://ui/components/tno_super_event_modal.tscn")
	assert(super_scene != null, "Failed to load tno_super_event_modal.tscn")
	var super_modal = super_scene.instantiate()
	assert(super_modal != null, "Failed to instantiate tno_super_event_modal")
	print("✓ TNOSuperEventModal instantiated successfully.")
	super_modal.queue_free()

	# 6. Test TerminalMain
	var term_scene = load("res://ui/screens/terminal_main.tscn")
	assert(term_scene != null, "Failed to load terminal_main.tscn")
	var term = term_scene.instantiate()
	assert(term != null, "Failed to instantiate terminal_main")
	print("✓ TerminalMain instantiated successfully.")
	term.queue_free()

	# 7. Test MainMenu
	var menu_scene = load("res://ui/screens/main_menu.tscn")
	assert(menu_scene != null, "Failed to load main_menu.tscn")
	var menu = menu_scene.instantiate()
	assert(menu != null, "Failed to instantiate main_menu")
	print("✓ MainMenu instantiated successfully.")
	menu.queue_free()

	print("--- ALL UI COMPONENTS VERIFIED WITH ZERO ERRORS ---")
	quit(0)
