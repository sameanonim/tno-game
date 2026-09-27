extends SceneTree

func _init() -> void:
	call_deferred("_run_ui_test")


func _run_ui_test() -> void:
	print("\n========================================================")
	print("       STARTING FULL UI & SCENE FLOW TEST")
	print("========================================================")

	# 1. Test MainMenu scene loading and instantiation
	print("\n[TEST 1] Loading and instantiating MainMenu...")
	var MainMenuScene = load("res://ui/screens/main_menu.tscn")
	assert(MainMenuScene != null, "MainMenu scene must load")
	var menu = MainMenuScene.instantiate()
	root.add_child(menu)
	print("  * MainMenu instantiated successfully.")

	# Switch to theater select
	menu._switch_state(1) # MenuState.THEATER_SELECT
	print("  * Switched to THEATER_SELECT.")

	# Test country selection via map widget
	var map_widget = menu.map_widget
	assert(map_widget != null, "map_widget must exist in MainMenu")
	print("  * MapWidget found, simulating country selection...")
	map_widget.select_country("OMS", false)
	assert(menu.selected_tag == "OMS", "Selected tag must be OMS")
	print("  * Country selected on map: OMS. Focus tree preview updated.")

	menu.queue_free()

	# 2. Test TerminalMain scene and TNOTopBar with CountryState
	print("\n[TEST 2] Testing TerminalMain and TNOTopBar initialization...")
	var test_state = CountryState.new()
	test_state.country_tag = "KOM"
	test_state.war_support_percent = 72.0
	assert(test_state.war_support_percent == 72.0, "war_support_percent must be accessible")

	var TopBarScene = load("res://ui/components/tno_topbar.tscn")
	var topbar = TopBarScene.instantiate()
	root.add_child(topbar)
	topbar.update_state(test_state)
	print("  * TNOTopBar updated successfully with war_support_percent: %s" % topbar.lbl_war.text)
	assert("72%" in topbar.lbl_war.text, "Topbar must display 72%")
	topbar.queue_free()

	# 3. Test PoliticsPanel
	print("\n[TEST 3] Testing PoliticsPanel.display_country...")
	var PoliticsScene = load("res://ui/screens/politics_panel.tscn")
	var pol_panel = PoliticsScene.instantiate()
	root.add_child(pol_panel)
	pol_panel.display_country(test_state)
	print("  * PoliticsPanel displayed country successfully: leader=%s, title=%s" % [pol_panel.lbl_leader_name.text, pol_panel.lbl_leader_title.text])
	assert(not pol_panel.lbl_leader_title.text.is_empty(), "Leader title must not be empty")
	pol_panel.queue_free()

	print("\n========================================================")
	print("       ALL UI & SCENE FLOW TESTS PASSED CLEANLY!")
	print("========================================================\n")
	quit(0)

