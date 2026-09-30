extends SceneTree

func _init() -> void:
	_run_verification.call_deferred()

func _run_verification() -> void:
	await process_frame

	print("==================================================================")
	print("=== STARTING COUNTRY LORE VERIFICATION TEST ===")
	print("==================================================================")

	# 1. Initialize LocalizationManager
	var loc = root.get_node_or_null("LocalizationManager")
	if loc == null:
		var loc_script = load("res://core/systems/localization_manager.gd")
		loc = loc_script.new()
		loc.name = "LocalizationManager"
		root.add_child(loc)
	assert(loc != null, "FAIL: LocalizationManager could not be initialized")

	# 2. Initialize ContentLoader
	var cl = ContentLoader.get_instance()
	if cl == null:
		cl = ContentLoader.new()
		cl.name = "ContentLoader"
		root.add_child(cl)
	assert(cl != null, "FAIL: ContentLoader could not be initialized")

	# 3. Initialize GameSession
	var gs = root.get_node_or_null("GameSession")
	if gs == null:
		var gs_script = load("res://core/systems/game_session.gd")
		gs = gs_script.new()
		gs.name = "GameSession"
		root.add_child(gs)

	var test_tags = [
		"USA", "GER", "JAP",
		"WRS", "KOM", "VYT", "SAM", "PRM", "TYU", "SVR", "OMS", "TOM", "NOV", "KEM", "SBA", "IRK", "BRY", "CHT", "MAG", "AMR",
		"SPE", "BOR", "GOR", "HEY",
		"ITA", "IBR", "ENG", "BRG", "FRD", "TUR", "SCO", "WAL", "IRE",
		"GNG", "MAN", "CHI", "THA", "YUN"
	]

	var fail_count = 0
	var success_count = 0

	for tag in test_tags:
		var dossier = gs.get_country_dossier(tag)
		var lore = dossier.get("lore", "")
		var loc_lore = loc.tr_key(tag + "_lore", "")
		var traits = dossier.get("traits", [])

		var resolved_lore = lore
		if not loc_lore.is_empty() and not loc_lore.begins_with("[MISSING"):
			resolved_lore = loc_lore

		var is_missing = resolved_lore.is_empty() or resolved_lore.begins_with("[MISSING")

		if is_missing:
			printerr("❌ [MISSING LORE] %s: lore is empty or [MISSING]! dossier_lore=%s loc_lore=%s" % [tag, lore, loc_lore])
			fail_count += 1
		else:
			print("✅ [%s] %s | Leader: %s | Traits: %d | Lore (%d chars): %s..." % [
				tag,
				dossier.get("name_ru", dossier.get("name", tag)),
				dossier.get("leader_name", "UNKNOWN"),
				traits.size(),
				resolved_lore.length(),
				resolved_lore.substr(0, 60).replace("\n", " ")
			])
			success_count += 1

	# Test full MainMenu instantiation to verify UI binding
	print("\n--- Verifying MainMenu UI dossier rendering ---")
	var menu_scene = load("res://ui/screens/main_menu.tscn")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	await process_frame

	var dossier_lore_node = menu.get_node_or_null("TheaterPanel/VBox/MainHBox/Dossier/Scroll/VBox/LoreText")
	assert(dossier_lore_node != null, "FAIL: LoreText node not found in main_menu")

	for sample_tag in ["GER", "USA", "WRS", "VYT", "SPE", "ITA", "GNG"]:
		var d = gs.get_country_dossier(sample_tag)
		menu._update_dossier_panel(d)
		var current_text = dossier_lore_node.text
		if current_text.contains("[MISSING") or current_text.strip_edges() == "[color=#a0ccb8][/color]" or current_text.is_empty():
			printerr("❌ UI Failed for %s: %s" % [sample_tag, current_text])
			fail_count += 1
		else:
			print("✅ UI Rendered for %s: %s..." % [sample_tag, current_text.substr(0, 70).replace("\n", " ")])

	menu.queue_free()

	print("==================================================================")
	print("TEST COMPLETED: Success: %d / %d | Failures: %d" % [success_count, test_tags.size(), fail_count])
	print("==================================================================")

	if fail_count > 0:
		quit(1)
	else:
		quit(0)
