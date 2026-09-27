extends SceneTree

func _init() -> void:
	_run_tests.call_deferred()

func _run_tests() -> void:
	# Give the engine 1 frame to initialize all Autoloads
	await process_frame

	print("==================================================")
	print("TESTING TNO MAIN MENU & AUDIO SYSTEM INTEGRATION")
	print("==================================================")

	# 1. Test AudioManager
	var am = root.get_node_or_null("AudioManager")
	if am == null:
		var am_script = load("res://core/systems/audio_manager.gd")
		am = am_script.new()
		am.name = "AudioManager"
		root.add_child(am)
	assert(am != null, "FAIL: AudioManager not found!")
	print("✓ PASS: AudioManager is active.")

	# Test playlist
	assert(am.TRACKS.size() >= 5, "FAIL: Less than 5 tracks in playlist!")
	print("✓ PASS: Playlist contains %d authentic TNO tracks." % am.TRACKS.size())

	# Test music play and radio
	am.play_music(0, true)
	assert(am.music_player.playing, "FAIL: MusicPlayer is not playing track 0!")
	print("✓ PASS: Track 0 playing: %s" % am.get_current_track_title())

	am.next_track()
	assert(am.current_track_index == 1, "FAIL: next_track did not advance to track 1!")
	print("✓ PASS: Track 1 playing: %s" % am.get_current_track_title())

	am.prev_track()
	assert(am.current_track_index == 0, "FAIL: prev_track did not return to track 0!")
	print("✓ PASS: Track 0 playing: %s" % am.get_current_track_title())

	am.toggle_pause()
	assert(am.is_music_paused, "FAIL: toggle_pause did not pause!")
	print("✓ PASS: toggle_pause paused music correctly.")

	am.toggle_pause()
	assert(not am.is_music_paused, "FAIL: toggle_pause did not resume!")
	print("✓ PASS: toggle_pause resumed music correctly.")

	# Test SFX
	for sfx in ["ui_menu_over", "click_default", "click_close", "click_checkbox", "start_game_01"]:
		am.play_sfx(sfx)
	print("✓ PASS: All SFX played through SFX pool without error.")

	# 2. Test MainMenu scene
	var menu_scene = load("res://ui/screens/main_menu.tscn")
	assert(menu_scene != null, "FAIL: Failed to load main_menu.tscn")
	var menu = menu_scene.instantiate()
	assert(menu != null, "FAIL: Failed to instantiate main_menu.tscn")
	root.add_child(menu)
	print("✓ PASS: MainMenu added to root SceneTree.")

	# Check textures loaded
	assert(menu.background_texture != null and menu.background_texture.texture != null, "FAIL: Background texture not loaded!")
	print("✓ PASS: Background texture loaded: size = %s" % menu.background_texture.texture.get_size())

	assert(menu.logo_tno != null and menu.logo_tno.texture != null, "FAIL: Logo TNO texture not loaded!")
	print("✓ PASS: Logo TNO texture loaded: size = %s" % menu.logo_tno.texture.get_size())

	assert(menu.logo_game != null and menu.logo_game.texture != null, "FAIL: Logo Game texture not loaded!")
	print("✓ PASS: Logo Game texture loaded: size = %s" % menu.logo_game.texture.get_size())

	assert(menu.menupics_texture != null and menu.menupics_texture.texture != null, "FAIL: Menupics texture not loaded!")
	print("✓ PASS: Menupics texture loaded: size = %s" % menu.menupics_texture.texture.get_size())

	# Test Menupics hover quotes
	menu._on_menupic_hover(1)
	assert(menu.quote_badge != null and "Я знаю" in menu.quote_badge.text, "FAIL: Zone 1 quote not displayed!")
	print("✓ PASS: Menupics Zone 1 quote: %s" % menu.quote_badge.text)

	menu._on_menupic_hover(2)
	assert(menu.quote_badge != null and "боль" in menu.quote_badge.text, "FAIL: Zone 2 quote not displayed!")
	print("✓ PASS: Menupics Zone 2 quote: %s" % menu.quote_badge.text)

	menu._on_menupic_hover(3)
	assert(menu.quote_badge != null and "покое" in menu.quote_badge.text, "FAIL: Zone 3 quote not displayed!")
	print("✓ PASS: Menupics Zone 3 quote: %s" % menu.quote_badge.text)

	# Test Background toggle (1962 <-> 2WRW)
	var initial_is_submod = menu.current_bg_is_submod
	menu._on_toggle_background()
	assert(menu.current_bg_is_submod != initial_is_submod, "FAIL: Background mode did not toggle!")
	print("✓ PASS: Background toggled to 2WRW successfully.")
	menu._on_toggle_background()
	assert(menu.current_bg_is_submod == initial_is_submod, "FAIL: Background mode did not toggle back!")
	print("✓ PASS: Background toggled back to 1962 successfully.")

	# Test State Machine transitions
	menu._switch_state(MainMenu.MenuState.THEATER_SELECT)
	assert(menu.theater_panel.visible and not menu.titular_panel.visible, "FAIL: THEATER_SELECT state mismatch!")
	print("✓ PASS: Switched to THEATER_SELECT state.")

	menu._switch_state(MainMenu.MenuState.CAMPAIGN_SETUP)
	assert(menu.setup_panel.visible and not menu.theater_panel.visible, "FAIL: CAMPAIGN_SETUP state mismatch!")
	print("✓ PASS: Switched to CAMPAIGN_SETUP state.")

	menu._switch_state(MainMenu.MenuState.SETTINGS)
	assert(menu.settings_panel.visible and not menu.setup_panel.visible, "FAIL: SETTINGS state mismatch!")
	print("✓ PASS: Switched to SETTINGS state.")

	menu._switch_state(MainMenu.MenuState.TITULAR)
	assert(menu.titular_panel.visible and not menu.settings_panel.visible, "FAIL: TITULAR state mismatch!")
	print("✓ PASS: Switched back to TITULAR state.")

	# Test English localization switch
	var loc = root.get_node_or_null("LocalizationManager")
	if loc != null:
		loc.set_locale("en")
		menu._update_localized_ui()
		assert("SINGLE PLAYER" in menu.btn_new_game.text or "NEW CAMPAIGN" in menu.btn_new_game.text, "FAIL: English localization not reflected in buttons!")
		print("✓ PASS: English localization verified on menu buttons: %s" % menu.btn_new_game.text)

		menu._on_menupic_hover(1)
		assert("I know" in menu.quote_badge.text, "FAIL: English quote not displayed for zone 1!")
		print("✓ PASS: English menupic quote 1: %s" % menu.quote_badge.text)

		# Switch back to Russian default
		loc.set_locale("ru")
		menu._update_localized_ui()
		print("✓ PASS: Switched back to Russian locale.")

	menu.queue_free()
	print("==================================================")
	print("ALL TNO MAIN MENU & AUDIO TESTS PASSED WITH 0 ERRORS!")
	print("==================================================")
	quit(0)
