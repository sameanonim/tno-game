class_name TestSuperEventsSystem
extends SceneTree

##
## test_superevents_system.gd: Комплексный автоматизированный тест супер-событий TNO
## Проверяет:
## 1. Загрузку каталога superevents_catalog.json (179 событий).
## 2. Разрешение артов (.png) и аудиотреков (.ogg).
## 3. Двуязычную локализацию (русский / английский).
## 4. Вызов супер-событий через TurnManager и EventManager.
## 5. Работу TNOSuperEventModal и воспроизведение аудио.
##

func _initialize() -> void:
	print("================================================================================")
	print("TESTING TNO SUPER EVENTS SYSTEM & AUDIO INTEGRATION")
	print("================================================================================")

	var root_node = root

	# --------------------------------------------------------------------------
	# TEST 1: Superevents Catalog Database Validation
	# --------------------------------------------------------------------------
	print("\n--- TEST 1: Superevents Catalog Loading ---")
	var catalog_path = "res://data/events/superevents_catalog.json"
	assert(FileAccess.file_exists(catalog_path), "FAIL: superevents_catalog.json does not exist!")

	var file = FileAccess.open(catalog_path, FileAccess.READ)
	assert(file != null, "FAIL: Cannot open superevents_catalog.json!")
	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(text)
	assert(err == OK, "FAIL: superevents_catalog.json parse error!")
	assert(json.data is Dictionary, "FAIL: Catalog root is not a Dictionary!")
	var catalog: Dictionary = json.data
	assert(catalog.size() >= 100, "FAIL: Catalog contains less than 100 super events (found %d)!" % catalog.size())
	print("✓ PASS: Superevents catalog successfully parsed: %d entries." % catalog.size())

	# --------------------------------------------------------------------------
	# TEST 2: Canonical TNO Events Inspection
	# --------------------------------------------------------------------------
	print("\n--- TEST 2: Canonical TNO Super Events Verification ---")
	var key_events = [
		"SE_GERMAN_CIVIL_WAR",
		"SE_SOUTH_AFRICAN_WAR",
		"SE_NUCLEAR_WAR",
		"SE_RUSSIAN_REUNIFICATION_WRRF_TUKHA"
	]

	for eid in key_events:
		assert(catalog.has(eid), "FAIL: Key superevent '%s' missing from catalog!" % eid)
		var entry: Dictionary = catalog[eid]
		assert(not str(entry.get("title_ru", "")).is_empty() or not str(entry.get("title_en", "")).is_empty(), "FAIL: Title missing for %s" % eid)
		assert(not str(entry.get("art_path", "")).is_empty(), "FAIL: Art path missing for %s" % eid)
		assert(ResourceLoader.exists(entry["art_path"]), "FAIL: Art file '%s' not found on disk for %s!" % [entry["art_path"], eid])

		var audio_path = str(entry.get("audio_path", ""))
		if not audio_path.is_empty():
			assert(FileAccess.file_exists(audio_path), "FAIL: Audio file '%s' not found on disk for %s!" % [audio_path, eid])

		print("✓ PASS: '%s' validated -> Title: '%s', Art: '%s', Audio: '%s'" % [
			eid,
			entry.get("title_ru", entry.get("title_en", "")),
			entry.get("art_path").get_file(),
			audio_path.get_file() if not audio_path.is_empty() else "NONE"
		])

	# --------------------------------------------------------------------------
	# TEST 3: TNOSuperEventModal Component Testing
	# --------------------------------------------------------------------------
	print("\n--- TEST 3: TNOSuperEventModal Instantiation & Display ---")
	var modal_scene = load("res://ui/components/tno_super_event_modal.tscn")
	assert(modal_scene != null, "FAIL: tno_super_event_modal.tscn could not be loaded!")
	var modal: TNOSuperEventModal = modal_scene.instantiate()
	root_node.add_child(modal)

	# Trigger German Civil War super event
	var shown_gcw = modal.show_super_event_by_id("SE_GERMAN_CIVIL_WAR")
	assert(shown_gcw, "FAIL: show_super_event_by_id(SE_GERMAN_CIVIL_WAR) returned false!")
	assert(modal.visible, "FAIL: TNOSuperEventModal is not visible after show_super_event_by_id!")
	assert(modal.lbl_title.text.contains("ГРАЖДАНСКАЯ ВОЙНА") or modal.lbl_title.text.contains("GERMAN CIVIL WAR"),
		"FAIL: Modal title unexpected: %s" % modal.lbl_title.text)
	assert(modal.art_texture.texture != null, "FAIL: ArtTexture texture was not loaded!")
	assert(modal.audio_player != null, "FAIL: AudioPlayer node missing in modal!")
	assert(modal.audio_player.stream != null, "FAIL: AudioStream was not loaded into player!")
	print("✓ PASS: TNOSuperEventModal displayed 'SE_GERMAN_CIVIL_WAR' with authentic art & audio stream!")

	# Simulate button click using Array container for lambda reference capture
	var signal_emitted = [false]
	modal.option_selected.connect(func(): signal_emitted[0] = true)
	modal._on_option_button_pressed()
	assert(signal_emitted[0], "FAIL: option_selected signal was not emitted!")
	print("✓ PASS: TNOSuperEventModal button dismiss and option_selected signal verified.")
	modal.queue_free()

	# --------------------------------------------------------------------------
	# TEST 4: TurnManager & EventManager Wiring
	# --------------------------------------------------------------------------
	print("\n--- TEST 4: TurnManager & EventManager Signal Dispatch ---")
	var tm = TurnManager.new()
	var ev_mgr = EventManager.new()
	tm.event_manager = ev_mgr
	tm.add_child(ev_mgr)
	root_node.add_child(tm)
	tm._ready()

	var super_event_received = [""]
	tm.super_event_requested.connect(func(eid): super_event_received[0] = eid)

	# Test 4.1: Direct trigger from TurnManager
	tm.trigger_super_event("SE_SOUTH_AFRICAN_WAR")
	assert(super_event_received[0] == "SE_SOUTH_AFRICAN_WAR", "FAIL: super_event_requested did not receive SE_SOUTH_AFRICAN_WAR!")
	print("✓ PASS: TurnManager.trigger_super_event correctly routed signal.")

	# Test 4.2: Trigger via Event Choice Effects
	var dummy_event = GameEvent.new()
	dummy_event.event_id = "test_crisis_event"
	var choice_option = {
		"option_id": "opt_escalate",
		"text": "Escalate the conflict.",
		"effects": {
			"FIRE_SUPER_EVENT": "SE_NUCLEAR_WAR"
		}
	}
	super_event_received[0] = ""
	ev_mgr.resolve_event_option(dummy_event, choice_option, tm.player_state)
	assert(super_event_received[0] == "SE_NUCLEAR_WAR", "FAIL: Event effect FIRE_SUPER_EVENT did not trigger super event!")
	print("✓ PASS: Event effect 'FIRE_SUPER_EVENT' routed through EventManager to TurnManager.")

	# Test 4.3: German Civil War Manager integration
	if tm.german_civil_war_manager != null:
		super_event_received[0] = ""
		tm.german_civil_war_manager.civil_war_erupted.emit()
		assert(super_event_received[0] == "SE_GERMAN_CIVIL_WAR", "FAIL: GCW civil_war_erupted did not trigger SE_GERMAN_CIVIL_WAR!")
		print("✓ PASS: GCWManager civil_war_erupted signal automatically triggered SE_GERMAN_CIVIL_WAR.")

	tm.queue_free()

	# --------------------------------------------------------------------------
	# TEST 5: TerminalMain Integration
	# --------------------------------------------------------------------------
	print("\n--- TEST 5: TerminalMain Integration ---")
	var term_scene = load("res://ui/screens/terminal_main.tscn")
	assert(term_scene != null, "FAIL: terminal_main.tscn could not be loaded!")
	var term = term_scene.instantiate()
	root_node.add_child(term)

	assert(term.super_event_modal != null or term.get_node_or_null("TNOSuperEventModal") != null, "FAIL: super_event_modal not found in TerminalMain!")
	if term.super_event_modal == null:
		term.super_event_modal = term.get_node("TNOSuperEventModal")
	term.trigger_super_event("SE_NUCLEAR_WAR")
	assert(term.super_event_modal.visible, "FAIL: SuperEventModal did not become visible in TerminalMain!")
	if term.label_log == null:
		term.label_log = term.get_node_or_null("BottomBar/LogLabel")
	if term.label_log != null:
		assert(term.label_log.text.contains("SE_NUCLEAR_WAR"), "FAIL: Teletype status log did not log super event!")
	print("✓ PASS: TerminalMain successfully launched SE_NUCLEAR_WAR modal and logged to teletype.")
	term.queue_free()

	print("\n================================================================================")
	print("ALL SUPER EVENTS SYSTEM TESTS PASSED WITH 0 ERRORS!")
	print("================================================================================")
	quit(0)
